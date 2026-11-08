"""Exercise the command-line contract used by the scheduled workflow."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from test_inventory_audit import PRODUCTS, FEED


class InventoryCliTests(unittest.TestCase):
    def run_audit(self, products):
        with tempfile.TemporaryDirectory() as directory:
            native = Path(directory, 'products.xml')
            facebook = Path(directory, 'facebook.xml')
            native.write_bytes(products.encode('utf-8'))
            facebook.write_bytes(FEED.encode('utf-8'))
            result = subprocess.run([sys.executable,
                str(Path(__file__).with_name('inventory_audit.py')), str(native), str(facebook)],
                capture_output=True, text=True, encoding='utf-8')
            return result.returncode, json.loads(result.stdout)

    def test_success_includes_input_hash_and_explicit_meta_limit(self):
        code, report = self.run_audit(PRODUCTS)
        self.assertEqual(code, 0)
        self.assertEqual(report['source_sha256']['native'],
                         hashlib.sha256(PRODUCTS.encode()).hexdigest())
        self.assertIn('checked_at_utc', report)
        self.assertFalse(report['meta_snapshot_supplied'])
        self.assertFalse(report['ready_for_meta_import'])

    def test_crlf_input_hash_uses_actual_bytes(self):
        products = PRODUCTS.replace('\n', '\r\n')
        code, report = self.run_audit(products)
        self.assertEqual(code, 0)
        self.assertEqual(report['source_sha256']['native'],
                         hashlib.sha256(products.encode()).hexdigest())

    def test_stock_exception_produces_report_and_exit_two(self):
        code, report = self.run_audit(PRODUCTS.replace('<quantity>1</quantity>', '<quantity>0</quantity>'))
        self.assertEqual(code, 2)
        self.assertIn('no_positive_variant_quantity', [i['reason'] for i in report['issues']])

    def test_unknown_quantity_is_invalid_input_not_success(self):
        code, report = self.run_audit(PRODUCTS.replace('<quantity>1</quantity>', ''))
        self.assertEqual(code, 1)
        self.assertEqual(report['mode'], 'INVALID_INPUT')


if __name__ == '__main__':
    unittest.main()
