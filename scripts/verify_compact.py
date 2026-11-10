#!/usr/bin/env python3
"""Verify every v2 crop against v1 source bytes; Pillow, no rendering shortcuts."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('source', type=Path)
p.add_argument('packed', type=Path)
p.add_argument('report', type=Path)
a = p.parse_args()
old = json.loads(a.source.read_text())
new = json.loads(a.packed.read_text())
assert old['schema_version'] == 1 and new['schema_version'] == 2
for key in ['profile', 'parts', 'animations', 'depth']:
    assert old[key] == new[key], key
sources = {(s['part_id'],s['animation_id']):s for s in old['sheets']}
count = checks = 0
for sheet in new['sheets']:
    source = sources[(sheet['part_id'],sheet['animation_id'])]
    frames = {(int(f['frame']),int(f['direction'])):f for f in source['frames']}
    for page_index,page in enumerate(sheet['pages']):
        # The Baker migrator preserves page membership while repacking its frames.
        channels = ['color','mask','depth']
        before = [Image.open(a.source.parent/source['pages'][page_index][c]).convert('RGBA') for c in channels]
        after = [Image.open(a.packed.parent/page[c]).convert('RGBA') for c in channels]
        for frame in [f for f in sheet['frames'] if int(f['page'])==page_index]:
            original = frames[(int(frame['frame']),int(frame['direction']))]
            assert int(original['page']) == page_index
            x,y,w,h = map(int,frame['rect'])
            ox,oy = map(int,frame['offset'])
            sx,sy,sw,sh = map(int,original['rect'])
            assert frame['source_size'] == [sw,sh]
            assert ox+w <= sw and oy+h <= sh
            union = Image.new('L',(sw,sh))
            for old_image in before:
                union = ImageChops.lighter(union,old_image.crop((sx,sy,sx+sw,sy+sh)).getchannel('A'))
            bbox=union.getbbox()
            if frame['empty']:
                assert bbox is None and (w,h,ox,oy)==(1,1,0,0)
            else:
                assert bbox == (ox,oy,ox+w,oy+h), (sheet['part_id'], frame, bbox)
            for old_image,new_image in zip(before,after):
                crop=new_image.crop((x,y,x+w,y+h))
                if frame['empty']:
                    assert not any(crop.tobytes())
                else:
                    assert crop.tobytes()==old_image.crop((sx+ox,sy+oy,sx+ox+w,sy+oy+h)).tobytes()
                checks+=1
            count+=1
        for im in before+after: im.close()
a.report.parent.mkdir(parents=True,exist_ok=True)
a.report.write_text(json.dumps({'all_passed':True,'frames':count,'channel_checks':checks,'minimal_union_alpha_bounds':True,'profile_parts_animations_depth_unchanged':True},indent=2)+'\n')
print(f'{count} frames / {checks} channel crops byte-identical; all bounds minimal')
