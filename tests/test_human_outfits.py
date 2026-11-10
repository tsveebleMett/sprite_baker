"""Protect explicit selection semantics: omission selects a default, not nothing."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HumanOutfitContract(unittest.TestCase):
    def test_fixed_palette_outfits_do_not_request_absent_tint_regions(self):
        spec = importlib.util.spec_from_file_location('prepare_human', ROOT / 'scripts/prepare_human.py')
        prepare = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(prepare)
        fixed = prepare.preview_outfits(fixed_palette=True)
        tintable = prepare.preview_outfits(fixed_palette=False)
        self.assertEqual(len(fixed), 3)
        for baked, runtime in zip(fixed, tintable):
            self.assertEqual(baked['tints'], {})
            self.assertEqual(baked['slots'], runtime['slots'])
            self.assertIn('skin', runtime['tints'])

    def test_complete_catalog_is_covered_and_animation_families_match(self):
        config = json.loads((ROOT / 'configs/human_male_complete.json').read_text())
        catalog = json.loads((ROOT / 'configs/human_male_catalog.json').read_text())
        outfits = json.loads((ROOT / 'configs/human_male_outfits_all.json').read_text())['outfits']
        parts = {part['id']: part for part in config['parts']}
        self.assertEqual(len(parts), 46)
        self.assertEqual({part for outfit in outfits for part in outfit['slots'].values() if part}, set(parts))
        animation_ids = {animation['id'] for animation in config['animations']}
        self.assertEqual(len(animation_ids), 8)
        for outfit in outfits:
            self.assertEqual(set(outfit['slots']), {part['slot'] for part in parts.values()})
            for slot, part in outfit['slots'].items():
                if part:
                    self.assertEqual(parts[part]['slot'], slot)
            family = catalog['weapon_animation_families'][outfit['slots']['weapon']]
            suffix = '' if family == '1h' else '_' + family
            self.assertEqual(outfit['animations'], {'idle':'idle'+suffix, 'walk':'walk'+suffix})
            self.assertTrue(set(outfit['animations'].values()) <= animation_ids)
            if family != '1h':
                self.assertEqual(outfit['slots']['shield'], '')
            if outfit['slots']['helmet']:
                self.assertEqual(outfit['slots']['hair'], '')
        for subset in ['default', 'showcase']:
            chosen = json.loads((ROOT / ('configs/human_male_outfits_' + subset + '.json')).read_text())['outfits']
            self.assertEqual({catalog['weapon_animation_families'][o['slots']['weapon']] for o in chosen}, {'1h','2h','bow','staff'})
        self.assertEqual(catalog['unsupported'], [])

    def test_explicit_slot_selection_and_membership(self):
        config = json.loads((ROOT / 'configs/human_male_preview.json').read_text())
        outfits = json.loads((ROOT / 'configs/human_male_outfits.json').read_text())['outfits']
        slots = {part['slot'] for part in config['parts']}
        parts = {part['id']: part for part in config['parts']}
        for outfit in outfits:
            with self.subTest(outfit=outfit['id']):
                self.assertEqual(slots, set(outfit['slots']))
                for slot, part_id in outfit['slots'].items():
                    if part_id:
                        self.assertIn(part_id, parts)
                        self.assertEqual(parts[part_id]['slot'], slot)
                if outfit['slots']['helmet']:
                    self.assertEqual(outfit['slots']['hair'], '')
        traveller = next(outfit for outfit in outfits if outfit['id'] == 'green_traveller')
        self.assertEqual(traveller['slots']['helmet'], '')
        self.assertEqual(traveller['slots']['shield'], '')
        self.assertEqual(traveller['slots']['hair'], 'hair_short')


if __name__ == '__main__':
    unittest.main()
