#!/usr/bin/env python3
"""Validate a level bundle and optionally prove unchanged static decoded frames."""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image

def load_bundle(path):
    manifest=json.loads((path/'level-manifest.json').read_text())
    pages=[]
    for page in manifest['pages']:
        image=Image.open(path/page['file']).convert('RGBA')
        image.load()
        assert list(image.size)==page['size']
        pages.append(image)
    def frame_image(frame):
        x,y,w,h=frame['rect'];image=pages[frame['page']]
        assert x>=0 and y>=0 and w>0 and h>0 and x+w<=image.width and y+h<=image.height
        return image.crop((x,y,x+w,y+h))
    return manifest,pages,frame_image

def verify(path,previous=None):
    manifest,pages,frame_image=load_bundle(path)
    keys=set();distinct=[]
    for entry in manifest['entries']:
        key=(entry['region'],entry['x'],entry['y'],entry['kind'])
        assert key not in keys;keys.add(key)
        for frame in entry['frames']:frame_image(frame)
        if entry['kind']=='torch':
            hashes={hashlib.sha256(frame_image(f).tobytes()).hexdigest() for f in entry['frames']}
            assert len(hashes)==24
            distinct.append(len(hashes))
            assert 'source_wall_contact' in entry
            for a,b in zip(entry['frames'],entry['frames'][1:]):
                assert b['simulation_tick']-a['simulation_tick']==5
                assert abs((b['time']-a['time'])-5/60)<1e-8
    navigation=json.loads((path/'navigation.json').read_text())
    layout=json.loads((path/'layout.json').read_text())
    assert navigation['layout_digest']==layout['layout_digest']==manifest['layout_digest']
    expected={(r['id'],t['x'],t['y']) for r in layout['regions'] for t in r['tiles']}
    assert {(c['region'],c['x'],c['y']) for c in navigation['cells']}==expected
    assert all(len(c['flags'])==25 for c in navigation['cells'])
    assert {(r,x,y) for r,x,y,k in keys if k!='torch'}==expected
    unchanged=0
    if previous:
        before,old_pages,old_frame=load_bundle(previous)
        old={e['id']:e for e in before['entries'] if e['kind']!='torch'}
        new={e['id']:e for e in manifest['entries'] if e['kind']!='torch'}
        assert old.keys()==new.keys()
        for identity,entry in new.items():
            for a,b in zip(entry['frames'],old[identity]['frames'],strict=True):
                assert a['pivot']==b['pivot'] and a['time']==b['time']
                ia,ib=frame_image(a),old_frame(b)
                assert ia.size==ib.size and ia.tobytes()==ib.tobytes()
                unchanged+=1
    report={'complete':True,'source_revision':manifest['source_revision'],'seed':manifest['seed'],'layout_digest':manifest['layout_digest'],'layout_cells':len(expected),'entries':len(keys),'pages':len(pages),'rgba_bytes':sum(i.width*i.height*4 for i in pages),'mounted_torches':len(distinct),'distinct_frames_per_torch':24,'verified_simulation_ticks_per_frame':5,'capture_simulation_fps':60,'unchanged_static_frames_verified':unchanged,'source_torch_assembly':'ironmine_dressing.gd::_place_torch; deformed wall contact, emitter at wooden tip, complete scene PI rotation','limits':['fixed mine lighting; no fog/bloom/dynamic shadows/neighbor torch relighting','per-tile painter ordering, not per-pixel3D depth','sampled particle loop, not mathematically periodic','consumer FPS acceptance separate']}
    assert report['rgba_bytes']<=256*1024**2
    (path/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    inventory={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in path.iterdir() if f.is_file() and f.name!='delivery.json'}
    (path/'delivery.json').write_text(json.dumps({'sha256':inventory},indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path);parser.add_argument('--previous',type=Path)
    args=parser.parse_args();verify(args.bundle,args.previous)
