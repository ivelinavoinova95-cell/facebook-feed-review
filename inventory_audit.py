"""Read-only CloudCart inventory audit. Never uploads or rewrites a feed.

Usage: python inventory_audit.py products.xml facebook.xml [meta-products.json]
Meta input must be a complete JSON array of catalog item objects. Pagination
completeness must be verified by the caller before supplying that snapshot.
Exit 0: no detected exceptions; 2: exceptions; 1: invalid/unverifiable input.
This snapshot check does not prove source generation age or future delivery.
"""
import json
import sys
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation


def text(node, name):
    return next(((c.text or '').strip() for c in node
                 if c.tag.rsplit('}', 1)[-1] == name), '')


def xml(value):
    if '<!DOCTYPE' in value.upper() or '<!ENTITY' in value.upper():
        raise ValueError('DTD/entities are not supported')
    return ET.fromstring(value)


def index(nodes, key):
    result = {}
    for node in nodes:
        ident = text(node, key)
        if not ident or ident in result:
            raise ValueError('Missing or duplicate product ID')
        result[ident] = node
    if not result:
        raise ValueError('Empty product source')
    return result


def number(value):
    try:
        result = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError('Missing or invalid numeric value') from exc
    if not result.is_finite() or result < 0:
        raise ValueError('Negative or nonfinite numeric value')
    return result


def eur(value):
    parts = value.split()
    if len(parts) != 2 or parts[1] != 'EUR':
        raise ValueError('Expected EUR price')
    return number(parts[0])


def audit(products_xml, feed_xml, meta=None):
    products = index(xml(products_xml).findall('product'), 'id')
    feed = index(xml(feed_xml).findall('.//item'), 'id')
    issues, rows, seen_variants = [], [], set()
    for ident, item in feed.items():
        def issue(reason):
            issues.append({'product_id': ident, 'reason': reason})
        source = products.get(ident)
        if source is None:
            issue('missing_native_product')
            continue
        tags = [t.strip().casefold() for t in text(source, 'tags').split(',')]
        if 'fb' not in tags:
            issue('missing_fb_tag')
        labels = ' '.join(text(n, k) for n, k in [
            (source, 'title'), (source, 'category'), (source, 'sub_category'),
            (item, 'title'), (item, 'product_type')]).casefold()
        if 'очаква се' in labels:
            issue('preorder_title_or_category')
        variants = source.findall('variants/variant')
        if not variants:
            raise ValueError('Missing variants: ' + ident)
        available = []
        for variant in variants:
            vid = text(variant, 'id')
            if not vid or vid in seen_variants:
                raise ValueError('Missing or duplicate variant ID')
            seen_variants.add(vid)
            # Child quantity is authoritative for this source, never an attribute.
            quantity = number(text(variant, 'quantity'))
            parameters = {text(p, 'name'): text(p, 'value')
                          for p in variant.findall('parameters/parameter')}
            if quantity > 0:
                available.append({'variant_id': vid, 'quantity': str(quantity),
                                  'parameters': parameters})
        if not available:
            issue('no_positive_variant_quantity')
        if text(item, 'availability') != 'in stock':
            issue('unexpected_feed_availability')
        price = eur(text(item, 'sale_price') or text(item, 'price'))
        if price != number(text(source, 'price')):
            issue('native_feed_effective_price_mismatch')
        rows.append({'product_id': ident, 'available_variant_count': len(available),
                     'available_variants': available, 'effective_price_eur': str(price)})
    if meta is not None:
        ids = set()
        for item in meta:
            ident = item.get('retailer_id')
            if not ident or ident in ids:
                raise ValueError('Missing or duplicate Meta retailer ID')
            ids.add(ident)
            if ident not in feed:
                issues.append({'product_id': ident, 'reason': 'meta_missing_from_feed'})
                continue
            price = item.get('sale_price') or item.get('price') or {}
            if price.get('currency') != 'EUR':
                raise ValueError('Missing or non-EUR Meta price')
            if number(price.get('amount', '')) != eur(
                    text(feed[ident], 'sale_price') or text(feed[ident], 'price')):
                issues.append({'product_id': ident, 'reason': 'meta_feed_price_mismatch'})
            if item.get('availability') != text(feed[ident], 'availability'):
                issues.append({'product_id': ident, 'reason': 'meta_feed_availability_mismatch'})
        issues.extend({'product_id': ident, 'reason': 'feed_missing_from_meta'}
                      for ident in sorted(set(feed) - ids))
    return {'mode': 'READ_ONLY_AUDIT', 'ready_for_meta_import': False,
            'source_generation_age_known': False, 'meta_snapshot_supplied': meta is not None,
            'native_product_count': len(products), 'feed_product_count': len(feed),
            'one_available_variant_count': sum(r['available_variant_count'] == 1 for r in rows),
            'multiple_available_variants_count': sum(r['available_variant_count'] >= 2 for r in rows),
            'issues': issues, 'products': rows}


if __name__ == '__main__':
    from pathlib import Path
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    try:
        report = audit(Path(sys.argv[1]).read_text(encoding='utf-8-sig'),
                       Path(sys.argv[2]).read_text(encoding='utf-8-sig'),
                       json.loads(Path(sys.argv[3]).read_text(encoding='utf-8-sig'))
                       if len(sys.argv) == 4 else None)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        sys.exit(2 if report['issues'] else 0)
    except (ValueError, ET.ParseError) as exc:
        print(json.dumps({'mode': 'INVALID_INPUT', 'error': str(exc)}))
        sys.exit(1)
