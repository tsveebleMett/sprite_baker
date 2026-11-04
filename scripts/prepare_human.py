#!/usr/bin/env python3
"""Stage local original human assets; no download and no source-repository writes.
Requires Pillow. Generated source assets are deliberately ignored by Git.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/human_male/generated'
RES = 'res://assets/human_male/generated/'
SKINS = ['cf9b74', 'e6b99c', 'd2a181', 'f0c9a8', 'c38d70', 'e1ae8e']
CLOTH = ['247ad6', '566f54', '96494c', '66527e', '537b82', 'a67e42']
HAIR = ['5b4124', '704a31', '9b6b43', '47352b', '6b533b', '554437', '85513b']
BODIES = ['base', 'hideArmor', 'furArmor', 'lightArmor', 'leatherArmor', 'cuirBouilli', 'studdedLeather', 'robe', 'surcoat']
HELMETS = ['Hood', 'Pelt', 'Cerveilliere', 'KettleHat']
ROLES = {'base':['cloth'], 'hideArmor':['leather'], 'furArmor':['fur','fur'], 'lightArmor':['cloth','cloth'], 'leatherArmor':['leather','cloth'], 'cuirBouilli':['leather'], 'studdedLeather':['leather','metal'], 'robe':['cloth'], 'surcoat':['cloth','metal']}
HELMET_ROLES = {'Hood':['cloth'], 'Pelt':['fur'], 'Cerveilliere':['metal','leather'], 'KettleHat':['metal','leather']}

def rgb(value):
    return [int(value[i:i+2],16)/255 for i in (0,2,4)]

def tint(cloth, role):
    target, mix = {'cloth':(cloth,0),'leather':([.71,.582,.454],.65),'fur':(rgb('665b52'),.8),'metal':([.72,.74,.78],.9)}[role]
    return [round(a*(1-mix)+b*mix,6) for a,b in zip(cloth,target)]

def write_json(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,indent=2)+'\n')

def srgb(value):
    return value*12.92 if value <= .0031308 else 1.055*value**(1/2.4)-.055

def linear(value):
    return value/12.92 if value <= .04045 else ((value+.055)/1.055)**2.4

def glb(source, palette=None):
    raw = source.read_bytes()
    length = struct.unpack_from('<I',raw,12)[0]
    doc = json.loads(raw[20:20+length])
    start = 20+length+8
    binary = raw[start:]
    view = doc['bufferViews'][doc['images'][0]['bufferView']]
    image = Image.open(io.BytesIO(binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])).convert('RGBA')
    if image.size != (5,96):
        raise ValueError(f'Unexpected palette dimensions: {image.size}')
    # Each mesh owns its palette adaptation: normalizing a stripe used as
    # unmasked trim by another mesh would otherwise silently bleach that trim.
    original_image = image.copy()
    original_material = json.loads(json.dumps(doc['materials'][0]))
    for node in doc['nodes']:
        name = node.get('name', '')
        if 'mesh' not in node:
            continue
        stripes = []
        if name.startswith('Body_'):
            stripes = [(0,0),(0,1),(2,0),(2,1)]
        elif name.startswith('Helmet_'):
            stripes = [(1,0),(1,1)]
        elif name.startswith(('Hair_', 'Beard_')):
            stripes = [(0,3)]
        elif name.startswith('Head_'):
            stripes = [(0,0)]
        image = original_image.copy()
        for row,col in stripes:
            pixels = [image.getpixel((col,y)) for y in range(row*32,(row+1)*32)]
            lumas = [sum(c*w for c,w in zip(p[:3],(.2126,.7152,.0722))) for p in pixels]
            peak = max(lumas) or 1
            for i,(pixel,lum) in enumerate(zip(pixels,lumas)):
                gray = round(255*lum/peak)
                image.putpixel((col,row*32+i),(gray,gray,gray,pixel[3]))
        if palette is not None:
            # Standard-material bake: sample the original shader's gradient in
            # linear light at 1024 levels/row, preserving the original vertex AO.
            # This finite texture has <=1/2048 interpolation-parameter error.
            image = Image.new('RGBA',(5,3072))
            for row in range(3):
                for col in range(5):
                    for step in range(1024):
                        amount=(step+.5)/1024
                        endpoints=palette[row][col]
                        if row and endpoints[0][3]*(1-amount)+endpoints[1][3]*amount <= .001:
                            endpoints=palette[0][col]
                        value=[linear(endpoints[0][c])*(1-amount)+linear(endpoints[1][c])*amount for c in range(3)]
                        image.putpixel((col,row*1024+step),tuple(round(255*srgb(c)) for c in value)+(255,))
        encoded = io.BytesIO(); image.save(encoded,format='PNG')
        png = encoded.getvalue()
        binary += b'\0' * (-len(binary)%4)
        view_id = len(doc['bufferViews'])
        doc['bufferViews'].append(dict(buffer=0,byteOffset=len(binary),byteLength=len(png)))
        binary += png
        image_id = len(doc['images'])
        doc['images'].append(dict(bufferView=view_id,mimeType='image/png',name=name+'_palette'))
        texture_id = len(doc['textures'])
        doc['textures'].append(dict(source=image_id,sampler=0))
        material = json.loads(json.dumps(original_material))
        material['name'] = name+'_palette'
        material['pbrMetallicRoughness']['baseColorTexture']['index'] = texture_id
        material_id = len(doc['materials']); doc['materials'].append(material)
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            primitive['material'] = material_id
    doc['buffers'][0]['byteLength'] = len(binary)
    # Nearest filtering is essential for the five-pixel palette and data masks.
    for sampler in doc.get('samplers',[]):
        sampler.update(magFilter=9728,minFilter=9728)
    payload = json.dumps(doc,separators=(',',':')).encode(); payload += b' ' * (-len(payload)%4)
    binary += b'\0' * (-len(binary)%4)
    out = struct.pack('<III',0x46546c67,2,12+8+len(payload)+8+len(binary))
    out += struct.pack('<II',len(payload),0x4e4f534a)+payload
    out += struct.pack('<II',len(binary),0x004e4942)+binary
    (DEST/'human_male.glb').write_bytes(out)
    return doc

def mask(name,stripes):
    image=Image.new('RGB',(5,96))
    for row,col,channel in stripes:
        color=tuple(255 if i==channel else 0 for i in range(3))
        for y in range(row*32,(row+1)*32): image.putpixel((col,y),color)
    image.save(DEST/(name+'.png'))
    return RES+name+'.png'

def part(name,slot,regions,mask_path='',source='',bone=''):
    return {'id':name.lower(),'slot':slot,'variant':name.lower(),'node_path':'human_male/Human_Skeleton/Skeleton3D/'+name,
            'source':source,'attachment_bone':bone,'position':[0,0,0],'rotation_degrees':[0,0,0],
            'scale':[1,1,1],'priority':len(slot),'regions':regions,'material_regions':{},'mask_texture':mask_path}

def stage_dependency(original,root):
    if not original.is_file(): raise FileNotFoundError(original)
    target=DEST/'items'/(hashlib.sha256(original.read_bytes()).hexdigest()[:12]+'_'+original.name)
    target.parent.mkdir(exist_ok=True)
    if original.suffix=='.tres':
        content=re.sub(r' uid="[^"]+"','',original.read_text())
        def replace(match):
            return 'path="'+stage_dependency(root/match.group(1),root)+'"'
        content=re.sub(r'path="res://([^"]+)"',replace,content)
        target.write_text(content)
    elif original.suffix in ['.png','.jpg','.webp']:
        target.write_bytes(original.read_bytes())
    else:
        raise ValueError('Unsupported equipment dependency: '+str(original))
    return RES+'items/'+target.name

def stage_item(source,root):
    # Keep resources and actual authored mesh/container transforms, without game
    # scripts, collisions, VFX instances or callbacks. Drop unused declarations
    # before copying dependency closures (e.g. dormant weapon-enchantment scenes).
    sections=re.split(r'(?=^\[)',source.read_text(),flags=re.M)
    kept=[]
    for section in sections:
        header=section.split('\n',1)[0]
        if 'type="Script"' in header or header.startswith('[connection'): continue
        if header.startswith('[node') and 'type="MeshInstance3D"' not in header and 'type="Node3D"' not in header and 'parent=' in header: continue
        section=re.sub(r'^script = .*\n','',section,flags=re.M)
        kept.append(re.sub(r' uid="[^"]+"','',section))
    references=set(re.findall(r'ExtResource\("([^"]+)"\)', ''.join(kept)))
    result=[]
    for section in kept:
        if section.startswith('[ext_resource'):
            resource_id=re.search(r'id="([^"]+)"',section).group(1)
            if resource_id not in references: continue
            match=re.search(r'path="res://([^"]+)"',section)
            if match:
                section=section.replace('res://'+match.group(1),stage_dependency(root/match.group(1),root))
        result.append(section)
    (DEST/'items'/source.name).write_text(''.join(result))
    return RES+'items/'+source.name

def preview_outfits(fixed_palette=False):
    outfits=[]
    specs=[('blue_swordsman','lightArmor','KettleHat','falchion','reinforcedshield',0),
           ('red_leather_swordsman','studdedLeather','Cerveilliere','shortsword','kiteshield',2),
           ('green_traveller','base','','walkingstick','',1)]
    for oid,body,helmet,weapon,shield,palette in specs:
        cloth=rgb(CLOTH[palette]); roles=ROLES[body]
        slots={slot:'' for slot in ['body','head','hair','beard','helmet','weapon','shield']}
        slots.update(body='body_'+body.lower(),head='head_base',beard='beard_goatee',weapon='weapon_'+weapon)
        if helmet: slots['helmet']='helmet_'+helmet.lower()
        else: slots['hair']='hair_short'
        if shield: slots['shield']='shield_'+shield
        tints={'skin':rgb(SKINS[palette]),'hair':rgb(HAIR[palette]),'body_primary':tint(cloth,roles[0]),'body_secondary':tint(cloth,roles[-1])}
        if helmet:
            roles=HELMET_ROLES[helmet]
            tints.update(helmet_primary=tint(cloth,roles[0]),helmet_secondary=tint(cloth,roles[-1]))
        outfits.append(dict(id=oid,slots=slots,tints={} if fixed_palette else tints))
    return outfits

def complete_outfits(part_styles, fixed_palette=False):
    """One explicit loadout per weapon, cycling all armor, helmet and shield variants."""
    outfits = []
    weapons = sorted(part_styles)
    shields = ['kiteshield', 'plankshield', 'reinforcedshield', 'roundshield']
    one_handed = 0
    for index, weapon in enumerate(weapons):
        style = part_styles[weapon]
        body = BODIES[index % len(BODIES)]
        helmet = ([''] + HELMETS)[index % (len(HELMETS) + 1)]
        palette = index % len(CLOTH)
        cloth = rgb(CLOTH[palette])
        slots = {slot: '' for slot in ['body', 'head', 'hair', 'beard', 'helmet', 'weapon', 'shield']}
        slots.update(body='body_' + body.lower(), head='head_base', beard='beard_goatee', weapon=weapon)
        if helmet:
            slots['helmet'] = 'helmet_' + helmet.lower()
        else:
            slots['hair'] = 'hair_short'
        if style == '1h':
            slots['shield'] = 'shield_' + shields[one_handed % len(shields)]
            one_handed += 1
        roles = ROLES[body]
        tints = {'skin': rgb(SKINS[palette]), 'hair': rgb(HAIR[index % len(HAIR)]),
                 'body_primary': tint(cloth, roles[0]), 'body_secondary': tint(cloth, roles[-1])}
        if helmet:
            roles = HELMET_ROLES[helmet]
            tints.update(helmet_primary=tint(cloth, roles[0]), helmet_secondary=tint(cloth, roles[-1]))
        slots['artifact_1'] = 'ring_right' if index % 3 == 0 else ''
        slots['artifact_2'] = 'ring_left' if index % 3 == 1 or index == 0 else ''
        suffix = '' if style == '1h' else '_' + style
        outfits.append(dict(id=weapon.removeprefix('weapon_'), slots=slots,
                            tints={} if fixed_palette else tints,
                            animations={'idle': 'idle' + suffix, 'walk': 'walk' + suffix}))
    return outfits

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True,help='Plunderground_4.4 checkout')
    parser.add_argument('--hoardfall-root',type=Path,required=True)
    parser.add_argument('--palette-config',type=Path,help='JSON rows: 3 rows x 5 stripes x 2 RGBA sRGB endpoints; fixed shader-color bake instead of tint masks')
    args=parser.parse_args()
    palette = json.loads(args.palette_config.read_text())['rows'] if args.palette_config else None
    if palette is not None:
        if len(palette)!=3 or any(len(row)!=5 for row in palette) or any(len(slot)!=2 for row in palette for slot in row) or any(len(color)!=4 or any(not isinstance(c,(int,float)) or not 0<=c<=1 for c in color) for row in palette for slot in row for color in slot):
            raise ValueError('Expected 3x5x2 RGBA endpoints, each in [0,1]')
    DEST.mkdir(parents=True,exist_ok=True)
    original=args.source_root/'src_models/human_male/human_male.glb'
    doc=glb(original,palette)
    (DEST/'human_male.tscn').write_text('[gd_scene load_steps=2 format=3]\n\n'
        '[ext_resource type="PackedScene" path="'+RES+'human_male.glb" id="1"]\n\n'
        '[node name="HumanMale" type="Node3D"]\n\n'
        '[node name="human_male" parent="." instance=ExtResource("1")]\n'
        'rotation = Vector3(0, 3.141592653589793, 0)\n')
    parts=[]
    body_mask=mask('body_mask',[(0,0,0),(0,1,1),(2,0,1),(2,1,2)])
    for body in BODIES: parts.append(part('Body_'+body,'body',['skin','body_primary','body_secondary'],body_mask))
    parts += [part('Head_base','head',['skin'],mask('skin_mask',[(0,0,0)])),
              part('Hair_short','hair',['hair'],mask('hair_mask',[(0,3,0)])),
              part('Beard_goatee','beard',['hair'],RES+'hair_mask.png')]
    helmet_mask=mask('helmet_mask',[(1,0,0),(1,1,1)])
    for helmet in HELMETS: parts.append(part('Helmet_'+helmet,'helmet',['helmet_primary','helmet_secondary'],helmet_mask))
    item_files=[]
    part_styles={}
    # Same-named Hoardfall scenes are the explicitly imported/adapted versions.
    # Keep their transforms; add the rest of the original game's hand equipment.
    for category in ['1h-weapons','2h-weapons','bows','staves','shields']:
        found = {}
        for source_root in [args.source_root, args.hoardfall_root]:
            for item in sorted((source_root/'assets/models/items'/category).glob('*.tscn')):
                found[item.stem] = (item, source_root)
        for item, source_root in found.values():
            slot = 'shield' if category=='shields' else ('artifact' if category=='rings' else 'weapon')
            source = stage_item(item,source_root)
            bone = 'Bone.hand_L.Attachment' if slot=='shield' else 'Bone.hand_R.Attachment'
            parts.append(part(slot+'_'+item.stem,slot,[],source=source,bone=bone))
            if slot == 'weapon':
                part_styles['weapon_' + item.stem.lower()] = {'1h-weapons':'1h', '2h-weapons':'2h', 'bows':'bow', 'staves':'staff'}[category]
            item_files.append({'repository':'Hoardfall' if source_root==args.hoardfall_root else 'Plunderground_4.4', 'path':str(item.relative_to(source_root)), 'sha256':hashlib.sha256(item.read_bytes()).hexdigest()})
    # Hoardfall's shortbow is a scaled Longbow, distinct from the original
    # Plunderground Shortbow mesh; keep both appearances instead of aliasing them.
    hoardfall_shortbow = json.loads(json.dumps(next(p for p in parts if p['id']=='weapon_longbow')))
    hoardfall_shortbow.update(id='weapon_hoardfall_shortbow', variant='weapon_hoardfall_shortbow', scale=[0.72,0.72,0.72])
    parts.append(hoardfall_shortbow)
    part_styles['weapon_hoardfall_shortbow']='bow'
    ring_path=args.hoardfall_root/'assets/models/items/rings/Ring.tscn'
    ring_source=stage_item(ring_path,args.hoardfall_root)
    for side,slot,bone in [('right','artifact_1','Bone.hand_R.Attachment'),('left','artifact_2','Bone.hand_L.Attachment')]:
        parts.append(part('ring_'+side,slot,[],source=ring_source,bone=bone))
    item_files.append({'repository':'Hoardfall','path':str(ring_path.relative_to(args.hoardfall_root)),
                       'sha256':hashlib.sha256(ring_path.read_bytes()).hexdigest()})
    if palette is not None:
        for definition in parts:
            definition['mask_texture']=''
            definition['regions']=[]
    config=json.loads((ROOT/'configs/demo_creature.json').read_text())
    config.update(asset_id='human_male',source=RES+'human_male.tscn',fps=6,parts=parts)
    config['profile'].update(id='human-male-v1',target_size=[128,128],supersample=2,locked=False,directions=8)
    def animations(style):
        names={'1h':['Idle','Walk'],'2h':['Idle-2h','Walk-2h'],'bow':['Idle-Bow-Battle','Walk-Bow-Battle'],'staff':['Idle-Staff','Walk-Staff-Battle']}[style]
        result=[]
        for clip,name in zip(['idle','walk'],names):
            anim=next(a for a in doc['animations'] if a['name']==name)
            duration=max(doc['accessors'][s['input']]['max'][0] for s in anim['samplers'])
            result.append(dict(id=clip,name=name,start=0,end=duration,loop=True))
        return result
    config['animations']=animations('1h')
    write_json(ROOT/'configs/human_male.json',config)
    outfits=preview_outfits(palette is not None)
    write_json(ROOT/'configs/human_male_outfits.json',{'outfits':outfits})
    selected={pid for o in outfits for pid in o['slots'].values() if pid}
    preview=json.loads(json.dumps(config)); preview['asset_id']='human_male_preview'
    preview['parts']=[p for p in parts if p['id'] in selected]
    write_json(ROOT/'configs/human_male_preview.json',preview)
    for style in ['2h','bow','staff']:
        styled=json.loads(json.dumps(config)); styled['asset_id']='human_male_'+style; styled['animations']=animations(style)
        write_json(ROOT/f'configs/human_male_{style}.json',styled)
    complete=json.loads(json.dumps(config)); complete['asset_id']='human_male_complete'
    complete['animations']=[]
    for style in ['1h','2h','bow','staff']:
        for animation in animations(style):
            if style != '1h': animation['id'] += '_' + style
            complete['animations'].append(animation)
    write_json(ROOT/'configs/human_male_complete.json',complete)
    all_outfits=complete_outfits(part_styles,palette is not None)
    write_json(ROOT/'configs/human_male_outfits_all.json',{'outfits':all_outfits})
    by_id={outfit['id']:outfit for outfit in all_outfits}
    defaults=['falchion','flangedmace','claymore','longbow','quarterstaff','walkingstick']
    showcase=['falchion','morningstar','battleaxe','claymore','longbow','hoardfall_shortbow','gemstonestaff','walkingstick']
    write_json(ROOT/'configs/human_male_outfits_default.json',{'outfits':[by_id[name] for name in defaults]})
    write_json(ROOT/'configs/human_male_outfits_showcase.json',{'outfits':[by_id[name] for name in showcase]})
    write_json(DEST/'provenance.json',{'source':'Plunderground_4.4','original_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'items':item_files,'palette_mode':'fixed_endpoints' if palette else 'runtime_tints', 'appearance_definition':{'repository':'Hoardfall','path':'scripts/roguelike/starter_party.gd','sha256':hashlib.sha256((args.hoardfall_root/'scripts/roguelike/starter_party.gd').read_bytes()).hexdigest()}, 'adaptations':['normalize recolorable palette stripes','nearest palette filtering','strip gameplay callbacks from equipment','Hoardfall shortbow uses Longbow at model_scale 0.72','Hoardfall ring attaches independently to both hand artifact slots'],'license':'No asset redistribution license found in inspected source asset directories. Local user-owned input; not committed or relicensed.'})
    write_json(ROOT/'configs/human_male_catalog.json',{'skin_colors':SKINS,'cloth_colors':CLOTH,'hair_colors':HAIR,'bodies':BODIES,'helmets':HELMETS,'body_material_roles':ROLES,'helmet_material_roles':HELMET_ROLES,'parts':[p['id'] for p in parts], 'weapon_animation_families':part_styles, 'unsupported':[], 'artifact_slots':{'artifact_1':'ring_right','artifact_2':'ring_left'}})
    print(f'Staged {len(parts)} modular parts; preview {len(preview["parts"])} parts, {len(outfits)} outfits')

if __name__=='__main__': main()
