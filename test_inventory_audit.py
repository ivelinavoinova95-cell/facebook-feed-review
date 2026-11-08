import unittest
from inventory_audit import audit

PRODUCTS = '''<products><product><id>762</id><tags>fb</tags><price>32</price>
<variants><variant><id>1</id><quantity>0</quantity><parameters><parameter>
<name>Размер</name><value>S</value></parameter></parameters></variant>
<variant><id>2</id><quantity>1</quantity><parameters><parameter>
<name>Размер</name><value>L</value></parameter></parameters></variant>
</variants></product></products>'''
FEED = '''<rss xmlns:g="http://base.google.com/ns/1.0"><channel><item>
<g:id>762</g:id><g:title>Комплект</g:title><g:price>32 EUR</g:price>
<g:availability>in stock</g:availability></item></channel></rss>'''
META = [{'retailer_id': '762', 'price': {'amount': '32', 'currency': 'EUR'},
         'availability': 'in stock'}]


class InventoryTests(unittest.TestCase):
    def test_partial_stock_keeps_model_and_only_available_size(self):
        result = audit(PRODUCTS, FEED, META)
        self.assertFalse(result['issues'])
        self.assertEqual(result['products'][0]['available_variants'][0]['parameters'], {'Размер': 'L'})
        self.assertFalse(result['ready_for_meta_import'])

    def test_child_quantity_not_attribute(self):
        source = PRODUCTS.replace('<variant>', '<variant quantity="99">').replace('<quantity>1</quantity>', '<quantity>0</quantity>')
        self.assertIn('no_positive_variant_quantity', [i['reason'] for i in audit(source, FEED)['issues']])

    def test_two_variants_of_same_size_count_as_one_size(self):
        source = PRODUCTS.replace('<quantity>0</quantity>', '<quantity>1</quantity>').replace('<value>S</value>', '<value>L</value>')
        row = audit(source, FEED)['products'][0]
        self.assertEqual(row['available_variant_count'], 2)
        self.assertEqual(row['available_size_count'], 1)

    def test_unknown_size_is_reported(self):
        result = audit(PRODUCTS.replace('<name>Размер</name>', '<name>unknown</name>'), FEED)
        self.assertIn('available_variant_missing_or_ambiguous_size', [i['reason'] for i in result['issues']])

    def test_preorder_and_exact_fb_tag(self):
        result = audit(PRODUCTS.replace('<tags>fb</tags>', '<tags>notfb</tags>'),
                       FEED.replace('Комплект', 'Комплект ОЧАКВА СЕ'))
        self.assertEqual({i['reason'] for i in result['issues']}, {'missing_fb_tag', 'preorder_title_or_category'})

    def test_missing_quantity_is_unknown_not_zero(self):
        with self.assertRaises(ValueError):
            audit(PRODUCTS.replace('<quantity>1</quantity>', ''), FEED)

    def test_duplicates_rejected(self):
        with self.assertRaises(ValueError):
            audit(PRODUCTS.replace('<id>2</id>', '<id>1</id>'), FEED)

    def test_discount_and_meta_disagreement(self):
        result = audit(PRODUCTS.replace('<price>32</price>', '<price>30</price>'),
                       FEED.replace('<g:price>32 EUR</g:price>', '<g:price>32 EUR</g:price><g:sale_price>30 EUR</g:sale_price>'), META)
        self.assertEqual([i['reason'] for i in result['issues']], ['meta_feed_price_mismatch'])

    def test_missing_meta_item(self):
        self.assertEqual(audit(PRODUCTS, FEED, [])['issues'][0]['reason'], 'feed_missing_from_meta')

    def test_xml_entities_rejected(self):
        with self.assertRaises(ValueError):
            audit('<!DOCTYPE products []>' + PRODUCTS, FEED)

    def test_unknown_quantity_rejected(self):
        for bad in ['NaN', '-1', 'Infinity']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                audit(PRODUCTS.replace('<quantity>1</quantity>', '<quantity>' + bad + '</quantity>'), FEED)


if __name__ == '__main__':
    unittest.main()
