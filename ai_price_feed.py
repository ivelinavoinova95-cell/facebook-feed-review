"""Build an AI-only copy of the public Facebook RSS feed; never call Meta.

Only custom_label_3 changes. Parent IDs, links, stock, regular/sale prices,
images and all other source fields are preserved. No customer data or tokens.
"""
import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

NS = 'http://base.google.com/ns/1.0'
ET.register_namespace('g', NS)


def parse_xml(data):
    if b'\x00' in data or b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('DTD/entities are not supported')
    root = ET.fromstring(data)
    if root.tag != 'rss' or root.find('channel') is None:
        raise ValueError('Expected the Facebook RSS source')
    return root


def field(item, name):
    nodes = item.findall(f'{{{NS}}}{name}')
    if len(nodes) > 1:
        raise ValueError(f'Duplicate {name}')
    return (nodes[0].text or '').strip() if nodes else ''


def price(value):
    parts = value.split()
    if len(parts) != 2 or parts[1] != 'EUR':
        raise ValueError('Expected an explicit EUR price')
    try:
        amount = Decimal(parts[0])
    except InvalidOperation as exc:
        raise ValueError('Invalid price') from exc
    if not amount.is_finite() or amount <= 0 or amount != amount.quantize(Decimal('.01')):
        raise ValueError('Expected a positive EUR price with at most two decimals')
    return amount


def sale_active(date_range, now):
    if not date_range:
        return True
    parts = date_range.split('/')
    if len(parts) != 2:
        raise ValueError('Invalid sale date range')
    times = [datetime.fromisoformat(v.replace('Z', '+00:00')) for v in parts]
    if any(t.tzinfo is None for t in times) or times[0] >= times[1]:
        raise ValueError('Sale dates need offsets and increasing bounds')
    return times[0] <= now < times[1]


def build(data, *, now=None, previous=None, allow_large_change=False):
    now = now or datetime.now(timezone.utc)
    root = parse_xml(data)
    items = root.findall('channel/item')
    if not items:
        raise ValueError('Empty source; previous feed must be retained')
    ids, discounts = set(), 0
    for item in items:
        ident = field(item, 'id')
        if not ident.isdigit() or ident in ids:
            raise ValueError('Missing, non-parent or duplicate ID')
        ids.add(ident)
        for key in ('title', 'description', 'image_link', 'availability', 'condition'):
            if not field(item, key):
                raise ValueError(f'Missing {key} for {ident}')
        link = urlsplit(field(item, 'link'))
        if link.scheme != 'https' or link.hostname not in ('drehizavseki.com', 'www.drehizavseki.com') or not link.path.startswith('/product/'):
            raise ValueError(f'Invalid canonical product link for {ident}')
        regular = price(field(item, 'price'))
        sale = price(field(item, 'sale_price')) if field(item, 'sale_price') else None
        discounted = sale is not None and sale < regular and sale_active(field(item, 'sale_price_effective_date'), now)
        fmt = lambda value: format(value, '.2f').replace('.', ',')
        label = (f'{fmt(sale)} EUR (редовна цена {fmt(regular)} EUR)'
                 if discounted else f'{fmt(regular)} EUR')
        discounts += int(discounted)
        # Validate duplicate labels before replacing; all other children stay intact.
        field(item, 'custom_label_3')
        old = item.find(f'{{{NS}}}custom_label_3')
        if old is None:
            old = ET.SubElement(item, f'{{{NS}}}custom_label_3')
        old.text = label
    if previous is not None and not allow_large_change:
        old_ids = {field(i, 'id') for i in parse_xml(previous).findall('channel/item')}
        if old_ids and len(ids & old_ids) / len(old_ids) < .75:
            raise ValueError('More than 25% of previous products disappeared; manual review required')
    output = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    report = {
        'mode': 'AI_PRICE_FEED', 'product_count': len(items),
        'active_sale_count': discounts, 'source_generation_age_known': False,
        'built_at_utc': now.isoformat(), 'source_sha256': hashlib.sha256(data).hexdigest(),
        'output_sha256': hashlib.sha256(output).hexdigest(),
        'only_changed_field': 'custom_label_3', 'uses_parent_product_ids': True,
        'intended_catalog_id': '903676082457339', 'advertising_catalog_changed': False,
    }
    return output, report


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--status', type=Path, required=True)
    parser.add_argument('--allow-large-change', action='store_true')
    args = parser.parse_args()
    # All checks finish before either published file is touched.
    output, report = build(args.source.read_bytes(),
                           previous=args.output.read_bytes() if args.output.exists() else None,
                           allow_large_change=args.allow_large_change)
    atomic_write(args.output, output)
    atomic_write(args.status, (json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode())
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
