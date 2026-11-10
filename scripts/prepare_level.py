#!/usr/bin/env python3
"""Stage a pinned original terrain compiler and its source dependencies, without touching it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOTS = [
 'scenes/levels/terrain/ironmine_dressing.gd',
 'data/levels/procGen/mines/level_1/environment.tscn',
 'scenes/levels/terrain/terrain_resolver.gd',
 'scenes/levels/terrain/terrain_mesh_builder.gd',
 'scenes/levels/terrain/terrain_materials.gd',
 'scenes/levels/terrain/mine_floor_contact.gd',
 'data/levels/procGen/mines/terrain_profile.tres',
 'assets/models/walls/mines/wall_torch1.tscn',
 'assets/materials/wood/brown.tres', 'assets/materials/metal/iron.tres',
]
PREFIX = 'res://assets/level_source/'
TEXT = {'.gd', '.tscn', '.tres', '.gdshader', '.gdshaderinc', '.obj', '.mtl'}
REF = re.compile(r'res://([^"\s\\]+)')

def stage(source, destination):
    source, destination = source.resolve(), destination.resolve()
    if source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError("Source and staging destination must not overlap")
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    pending, done = list(ROOTS), {}
    while pending:
        relative = pending.pop()
        if relative in done:
            continue
        origin = (source / relative).resolve()
        if not origin.is_relative_to(source) or not origin.is_file():
            raise ValueError(f'Invalid/missing source dependency: {relative}')
        raw = origin.read_bytes()
        content = raw
        if origin.suffix in TEXT:
            text = raw.decode('utf-8')
            # Some original OBJ files name absent authoring MTL files; their
            # PackedScenes assign the real source materials explicitly. Remove
            # only missing sidecar declarations in this staged copy.
            if origin.suffix == '.obj':
                text = re.sub(r'^mtllib (.+)$', lambda m: m[0] if (origin.parent/m[1].strip()).is_file() else '', text, flags=re.M)
            pending.extend(REF.findall(text))
            text = REF.sub(lambda m: PREFIX + m[1], text)
            # Explicit sampled clock only in the isolated copy, not original shaders.
            if relative.endswith(('VFX_fire.tres', 'VFX_flare.tres')):
                text = re.sub(r'\bTIME\b', 'bake_time', text)
                text = text.replace('shader_type spatial;', 'shader_type spatial;\\nuniform float bake_time = 0.0;')
            # UID identifiers belong to the original project database, not this copy.
            text = re.sub(r' uid="uid://[^"]+"', '', text)
            content = text.encode()
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        done[relative] = {'source_sha256': hashlib.sha256(raw).hexdigest(), 'prepared_sha256': hashlib.sha256(content).hexdigest()}
    record = {'source_revision': revision, 'roots': ROOTS, 'files': dict(sorted(done.items())),
              'adaptations': ['res paths isolated', 'original project UIDs removed', 'missing original OBJ MTL declarations omitted; original assembly binds materials', 'VFX TIME replaced by explicit sample clock in staged copy']}
    (destination / 'provenance.json').write_text(json.dumps(record, indent=2)+'\n')
    return record

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, default=Path(__file__).resolve().parents[1]/'assets/level_source')
    args = parser.parse_args()
    record = stage(args.source, args.destination)
    print(f"Staged {len(record['files'])} pinned dependencies from {record['source_revision']}")
