import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

spec=importlib.util.spec_from_file_location('level_pack',Path(__file__).parents[1]/'scripts/pack_level.py')
level_pack=importlib.util.module_from_spec(spec)
spec.loader.exec_module(level_pack)

class LevelPackTest(unittest.TestCase):
    def test_terrain_coverage_does_not_harden_particle_transparency(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'edge.png'
            Image.new('RGBA',(1,1),(40,20,10,128)).save(path)
            terrain=level_pack.straight_image(path,True).getpixel((0,0))
            particle=level_pack.straight_image(path,False).getpixel((0,0))
            self.assertEqual(terrain[3],255)
            self.assertEqual(particle[3],128)
            self.assertEqual(terrain[:3],particle[:3])
            self.assertTrue(78 <= terrain[0] <= 80)

    def test_preserves_anchor_coordinates_and_deduplicates_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); capture=root/'capture';capture.mkdir()
            Image.new('RGBA',(4,5),(255,100,50,255)).save(capture/'frame.png')
            Image.new('RGBA',(1024,1024)).save(capture/'source-patch.png')
            frame={'file':'frame.png','pivot':[-2.5,8.0],'time':0.0}
            entries=[dict(id='floor',kind='floor',region=1,x=1,y=2,frames=[dict(frame)],duration=1.0,loop=False)]
            entries += [dict(id=f'torch{i}',kind='torch',orientation=i,frames=[dict(frame)],duration=1.0,loop=True) for i in range(4)]
            (capture/'capture.json').write_text(json.dumps({'entries':entries,'seed':486,'layout_digest':'fixture'}))
            (capture/'navigation.json').write_text(json.dumps({'layout_digest':'fixture'}))
            layout={'seed':486,'layout_digest':'fixture','regions':[{'id':1,'tiles':[{'x':1,'y':2,'kind':'floor'},{'x':1,'y':3,'kind':'torch'}]}]}
            destination=root/'bundle';level_pack.pack(capture,destination,layout)
            result=json.loads((destination/'level-manifest.json').read_text())
            self.assertEqual(len(result['pages']),1)
            self.assertEqual(len(result['entries']),2)
            a,b=result['entries']
            self.assertEqual(a['frames'][0]['rect'],b['frames'][0]['rect'])
            self.assertEqual(b['frames'][0]['pivot'],[-2.5,8.0])
            self.assertEqual(b['orientation'],0)
            self.assertEqual((b['region'],b['x'],b['y']),(1,1,3))
            large=root/'large'
            level_pack.pack(capture,large,layout,4096)
            bigger=json.loads((large/'level-manifest.json').read_text())
            self.assertEqual(bigger['pages'][0]['size'],[4096,64])
            self.assertEqual(bigger['entries'][0]['frames'][0]['pivot'],a['frames'][0]['pivot'])
            small_image=Image.open(destination/result['pages'][0]['file'])
            large_image=Image.open(large/bigger['pages'][0]['file'])
            self.assertEqual(small_image.crop((1,1,5,6)).tobytes(),large_image.crop((1,1,5,6)).tobytes())
            with self.assertRaises(ValueError):level_pack.pack(capture,root/'invalid',layout,8192)
            with self.assertRaises(FileExistsError):level_pack.pack(capture,destination,layout)

    def test_layout_mismatch_or_missing_navigation_never_publishes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); capture=root/'capture';capture.mkdir()
            (capture/'capture.json').write_text(json.dumps({'seed':486,'layout_digest':'a'}))
            for layout in [{'seed':487,'layout_digest':'a'},{'seed':486,'layout_digest':'b'}]:
                with self.assertRaises(ValueError):level_pack.pack(capture,root/'bad',layout)
                self.assertFalse((root/'bad').exists())
            layout={'seed':486,'layout_digest':'a'}
            with self.assertRaises(FileNotFoundError):level_pack.pack(capture,root/'bad',layout)
            (capture/'navigation.json').write_text(json.dumps({'layout_digest':'b'}))
            with self.assertRaises(ValueError):level_pack.pack(capture,root/'bad',layout)
            self.assertFalse((root/'bad').exists())

    def test_staging_rejects_source_destination_overlap_before_writing(self):
        spec=importlib.util.spec_from_file_location('prepare_level',Path(__file__).parents[1]/'scripts/prepare_level.py')
        prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            source=root/'source';source.mkdir();marker=source/'unchanged';marker.write_text('original')
            for destination in [source,source/'nested',root]:
                with self.assertRaises(ValueError):prepare.stage(source,destination)
                self.assertEqual(marker.read_text(),'original')
