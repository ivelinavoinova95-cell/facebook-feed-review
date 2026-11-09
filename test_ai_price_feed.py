import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from ai_price_feed import NS, build, field

NOW = datetime(2026, 11, 9, 12, tzinfo=timezone.utc)


def source(price='28.00 EUR', sale='25.20 EUR', dates='', ident='6'):
    return f'''<rss version="2.0" xmlns:g="{NS}"><channel><title>Public feed</title><item>
    <g:id>{ident}</g:id><g:title>Комплект</g:title><g:description>Описание</g:description>
    <g:link>https://www.drehizavseki.com/product/test?cv=1&amp;x=2</g:link>
    <g:image_link>https://cdn.cloudcart.com/image.png</g:image_link>
    <g:availability>in stock</g:availability><g:condition>new</g:condition>
    <g:price>{price}</g:price><g:sale_price>{sale}</g:sale_price>
    <g:sale_price_effective_date>{dates}</g:sale_price_effective_date>
    <g:custom_label_2>sale</g:custom_label_2><g:custom_label_3>fb,tags</g:custom_label_3>
    <g:additional_image_link>https://cdn.cloudcart.com/second.png</g:additional_image_link>
    </item></channel></rss>'''.encode()


class PriceFeedTests(unittest.TestCase):
    def label(self, **kwargs):
        output, _ = build(source(**kwargs), now=NOW)
        return field(ET.fromstring(output).find('channel/item'), 'custom_label_3')

    def test_sale_and_regular(self):
        self.assertEqual(self.label(), '25,20 EUR (редовна цена 28,00 EUR)')
        self.assertEqual(self.label(sale=''), '28,00 EUR')

    def test_inactive_promotions(self):
        self.assertEqual(self.label(dates='2026-11-10T00:00:00Z/2026-11-12T00:00:00Z'), '28,00 EUR')
        self.assertEqual(self.label(dates='2026-11-01T00:00:00Z/2026-11-08T00:00:00Z'), '28,00 EUR')
        self.assertEqual(self.label(dates='2026-11-09T00:00:00+02:00/2026-11-10T00:00:00+02:00'), '25,20 EUR (редовна цена 28,00 EUR)')

    def test_equal_or_higher_sale_is_not_discount(self):
        self.assertEqual(self.label(sale='28.00 EUR'), '28,00 EUR')
        self.assertEqual(self.label(sale='29.00 EUR'), '28,00 EUR')

    def test_preserve_every_other_field(self):
        original = source()
        out, report = build(original, now=NOW)
        before = ET.fromstring(original).find('channel/item')
        after = ET.fromstring(out).find('channel/item')
        self.assertEqual([(n.tag, n.text, n.attrib) for n in before if n.tag != f'{{{NS}}}custom_label_3'],
                         [(n.tag, n.text, n.attrib) for n in after if n.tag != f'{{{NS}}}custom_label_3'])
        self.assertEqual(report['active_sale_count'], 1)
        self.assertFalse(report['source_generation_age_known'])

    def test_bad_prices_fail_closed(self):
        for value in ('0 EUR', '-1 EUR', 'NaN EUR', 'Infinity EUR', '1.001 EUR', '1 BGN', '1,50 EUR', ''):
            with self.subTest(value=value), self.assertRaises(ValueError):
                build(source(price=value), now=NOW)

    def test_bad_sale_fails_closed(self):
        with self.assertRaises(ValueError):
            build(source(sale='-1 EUR'), now=NOW)

    def test_bad_dates_fail_closed(self):
        for dates in ('bad', '2026-11-01/2026-11-10', '2026-11-12T00:00:00Z/2026-11-01T00:00:00Z'):
            with self.subTest(dates=dates), self.assertRaises(ValueError):
                build(source(dates=dates), now=NOW)

    def test_no_duplicate_or_variant_ids(self):
        data = source()
        root = ET.fromstring(data)
        root.find('channel').append(ET.fromstring(data).find('channel/item'))
        with self.assertRaises(ValueError):
            build(ET.tostring(root), now=NOW)
        with self.assertRaises(ValueError):
            build(source(ident='6-S'), now=NOW)

    def test_bad_url_fails_closed(self):
        with self.assertRaises(ValueError):
            build(source().replace(b'www.drehizavseki.com', b'other.example'), now=NOW)

    def test_no_empty_or_unsafe_xml(self):
        for data in (b'<rss><channel/></rss>', b'<!DOCTYPE rss><rss/>', b'<rss>',
                     '<!DOCTYPE rss><rss/>'.encode('utf-16')):
            with self.subTest(data=data), self.assertRaises((ValueError, ET.ParseError)):
                build(data, now=NOW)

    def test_large_removal_requires_explicit_review(self):
        previous = ET.fromstring(source())
        second = ET.fromstring(source(ident='7')).find('channel/item')
        previous.find('channel').append(second)
        with self.assertRaises(ValueError):
            build(source(), previous=ET.tostring(previous), now=NOW)
        build(source(), previous=ET.tostring(previous), now=NOW, allow_large_change=True)

    def test_output_content_is_stable(self):
        self.assertEqual(build(source(), now=NOW)[0], build(source(), now=NOW)[0])


if __name__ == '__main__':
    unittest.main()
