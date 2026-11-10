"""Delivery boundary tests; run python3 -m unittest discover -s tests -p test_delivery.py."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('delivery', Path(__file__).parents[1] / 'scripts/deliver_export.py')
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        # Header-level validation is enough here; the consumer validates decoding.
        (self.source / 'sheet.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'\0\0\0\rIHDR' + (1).to_bytes(4, 'big') * 2 + bytes([8, 6, 0, 0, 0, 0, 0, 0, 0]))
        self.manifest = {'schema_version': 1, 'asset_id': 'test', 'profile': {'id': 'test-v1'}, 'sheets': [{'pages': [{'size': [1, 1], 'color': 'sheet.png', 'mask': 'sheet.png', 'depth': 'sheet.png'}]}]}
        self.write_manifest()

    def write_manifest(self):
        (self.source / 'manifest.json').write_text(json.dumps(self.manifest))

    def test_delivery_preserves_bytes_and_refuses_overwrite(self):
        target = self.root / 'consumer'
        delivery.deliver(self.source, target)
        self.assertEqual((target / 'manifest.json').read_bytes(), (self.source / 'manifest.json').read_bytes())
        self.assertIn('sheet.png', json.loads((target / 'delivery.json').read_text())['sha256'])
        with self.assertRaises(FileExistsError):
            delivery.deliver(self.source, target)

    def test_unsafe_and_missing_paths_are_rejected_before_publication(self):
        for name in ('../sheet.png', '/sheet.png', 'sub/../sheet.png', 'missing.png', 'delivery.json', 'sheet.PNG'):
            self.manifest['sheets'][0]['pages'][0]['color'] = name
            self.write_manifest()
            with self.assertRaises(ValueError):
                delivery.deliver(self.source, self.root / 'consumer')
            self.assertFalse((self.root / 'consumer').exists())

    def test_complete_metadata_is_hashed_and_invalid_json_is_not_published(self):
        metadata = self.root / 'presets.json'
        metadata.write_text('{"outfits": []}')
        target = self.root / 'complete'
        delivery.deliver(self.source, target, outfits_all=metadata,
                         outfits_showcase=metadata, catalog=metadata)
        hashes = json.loads((target / 'delivery.json').read_text())['sha256']
        for name in ('outfits_all.json', 'outfits_showcase.json', 'catalog.json'):
            self.assertIn(name, hashes)
            self.assertEqual((target / name).read_bytes(), metadata.read_bytes())
        metadata.write_text('not JSON')
        invalid = self.root / 'invalid'
        with self.assertRaises(ValueError):
            delivery.deliver(self.source, invalid, outfits_all=metadata)
        self.assertFalse(invalid.exists())

    def test_partial_and_incorrect_png_are_rejected(self):
        partial = self.root / '.partial-test'
        partial.mkdir()
        with self.assertRaises(ValueError):
            delivery.deliver(partial, self.root / 'consumer')
        (self.source / 'sheet.png').write_bytes(b'bad')
        with self.assertRaises(ValueError):
            delivery.deliver(self.source, self.root / 'consumer')


if __name__ == '__main__':
    unittest.main()
