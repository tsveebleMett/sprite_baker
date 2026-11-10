#!/usr/bin/env python3
"""Lossless cropped level frames -> bounded shared RGBA atlas pages."""
import argparse, hashlib, json, shutil
from pathlib import Path
from PIL import Image

def straight_image(path, terrain=False):
    image=Image.open(path).convert('RGBA')
    # SubViewport/Lanczos capture stores premultiplied edge RGB. PNG consumers
    # expect straight alpha. Terrain receives half-pixel coverage overlap so
    # adjoining independently rasterized tile edges cannot darken into cracks.
    image=Image.frombytes('RGBa',image.size,image.tobytes()).convert('RGBA')
    if terrain:image.putalpha(image.getchannel('A').point(lambda a:min(255,a*2)))
    return image

def pack(folder, destination, layout, page_size=2048):
    if page_size not in (2048,4096):raise ValueError("Atlas size must be2048 or4096")
    manifest=json.loads((folder/'capture.json').read_text())
    if any(manifest.get(k) != layout.get(k) for k in ('seed','layout_digest')):
        raise ValueError('Capture and layout seed/digest differ')
    navigation=json.loads((folder/'navigation.json').read_text())
    if navigation.get('layout_digest') != layout['layout_digest']:
        raise ValueError('Navigation and layout digest differ')
    destination.mkdir(parents=True, exist_ok=False)
    pages=[]; atlas=Image.new('RGBA',(page_size,page_size)); x=y=row=0; used=0
    seen={}
    def flush():
        nonlocal atlas,x,y,row,used
        if not used:return
        name=f'level-{len(pages):03}.png'
        # Keep edge-bound crop lossless; NPOT pages avoid allocating an almost
        # empty final4096² texture.64-row alignment keeps resource sizes regular.
        height=min(page_size,((y+row+63)//64)*64)
        atlas.crop((0,0,page_size,height)).save(destination/name)
        pages.append({'file':name,'size':[page_size,height]})
        atlas=Image.new('RGBA',(page_size,page_size));x=y=row=used=0
    unique={}
    for entry in manifest['entries']:
        for frame in entry['frames']:
            image=straight_image(folder/frame.pop('file'),entry['kind']!='torch')
            digest=hashlib.sha256(image.tobytes()+str(image.size).encode()).hexdigest()
            if digest not in unique:unique[digest]={'image':image,'frames':[]}
            unique[digest]['frames'].append(frame)
    for digest,data in sorted(unique.items(),key=lambda item:(-item[1]['image'].height,-item[1]['image'].width)):
        image=data['image'];w,h=image.size
        if max(w,h)>page_size-2:raise ValueError('Oversize frame')
        if x+w+2>page_size:x=0;y+=row;row=0
        if y+h+2>page_size:flush()
        atlas.paste(image,(x+1,y+1))
        record={'page':len(pages),'rect':[x+1,y+1,w,h]}
        for frame in data['frames']:frame.update(record)
        seen[digest]=record
        x+=w+2;row=max(row,h+2);used+=1
    flush()
    templates={e['orientation']:e for e in manifest['entries'] if e['kind']=='torch' and 'orientation' in e}
    manifest['entries']=[e for e in manifest['entries'] if e['kind']!='torch' or 'orientation' not in e]
    cells={(t['x'],t['y']):t['kind'] for r in layout['regions'] for t in r['tiles']}
    for region in layout['regions']:
        for tile in region['tiles']:
            if tile['kind']!='torch' or not templates:continue
            orientation=next((i for i,(dx,dy) in enumerate([(0,-1),(1,0),(0,1),(-1,0)]) if cells.get((tile['x']+dx,tile['y']+dy))=='floor'),0)
            entry=dict(templates[orientation],region=region['id'],x=tile['x'],y=tile['y'],id=f"torch_{region['id']}_{tile['x']}_{tile['y']}")
            manifest['entries'].append(entry)
    # Independent source 3D reference and sprite painter reconstruction.
    placements={(p['x'],p['y']):p['pixel'] for p in manifest.pop('reference_placements',[])}
    comparison=Image.new('RGBA',(1024,1024))
    original=json.loads((folder/'capture.json').read_text())
    layers=[e for e in original['entries'] if e['kind']!='torch' and (e.get('x'),e.get('y')) in placements]
    layers.sort(key=lambda e:(e['kind']!='floor',e['x']+e['y'],e['x']))
    for entry in layers:
        frame=entry['frames'][0];frame_image=straight_image(folder/frame['file'],entry['kind']!='torch')
        origin=placements[(entry['x'],entry['y'])]
        comparison.alpha_composite(frame_image,(round(origin[0]-frame['pivot'][0]),round(origin[1]-frame['pivot'][1])))
    comparison.save(destination/'sprite-patch.png')
    straight_image(folder/'source-patch.png').save(destination/'source-patch.png')
    navigation=folder/'navigation.json'
    if navigation.exists():shutil.copyfile(navigation,destination/'navigation.json')
    if (folder/'source-mounted-torch.png').exists():
        straight_image(folder/'source-mounted-torch.png').save(destination/'source-mounted-torch.png')
    (destination/'layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    manifest['pages']=pages
    (destination/'level-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'{len(manifest["entries"])} entries, {len(seen)} unique frames, {len(pages)} pages, {sum(p["size"][0]*p["size"][1]*4 for p in pages)//(1024*1024)} MiB RGBA')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture',type=Path);p.add_argument('destination',type=Path);p.add_argument('--layout',type=Path,required=True);p.add_argument('--page-size',type=int,choices=[2048,4096],default=2048);a=p.parse_args();pack(a.capture,a.destination,json.loads(a.layout.read_text()),a.page_size)
