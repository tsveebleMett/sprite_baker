#!/usr/bin/env python3
"""Publish a completed Baker export to a consumer's asset directory, unchanged."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile


def deliver(source: Path, destination: Path, outfits: Path | None = None,
            provenance: Path | None = None, outfits_all: Path | None = None,
            outfits_showcase: Path | None = None, catalog: Path | None = None) -> None:
    source = source.resolve()
    if source.name.startswith('.partial-'):
        raise ValueError('Incomplete exports cannot be delivered')
    manifest_path = source / 'manifest.json'
    if manifest_path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('Manifest exceeds 16 MiB')
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('schema_version') != 1:
        raise ValueError('Only sprite_baker schema version 1 is supported')
    files = {'manifest.json': manifest_path}
    for sheet in manifest['sheets']:
        for page in sheet['pages']:
            for channel in ('color', 'mask', 'depth'):
                name = page[channel]
                relative = PurePosixPath(name)
                if not name.endswith('.png') or len(name) > 240 or '\\' in name or ':' in name or relative.is_absolute() or any(p in ('', '.', '..') for p in name.split('/')):
                    raise ValueError(f'Unsafe export path: {name}')
                path = (source / name).resolve()
                if not path.is_relative_to(source) or not path.is_file():
                    raise ValueError(f'Missing or escaping export file: {name}')
                with path.open('rb') as stream:
                    header = stream.read(33)
                if (len(header) < 33 or header[8:12] != bytes([0, 0, 0, 13]) or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR'
                    or [int.from_bytes(header[16:20], 'big'), int.from_bytes(header[20:24], 'big')] != page['size']
                    or header[24:26] != bytes([8, 6])):
                    raise ValueError(f'Expected matching RGBA8 PNG: {name}')
                files[name] = path
    metadata = {'outfits.json': outfits, 'source-provenance.json': provenance,
                'outfits_all.json': outfits_all, 'outfits_showcase.json': outfits_showcase,
                'catalog.json': catalog}
    for name, path in metadata.items():
        if path is None:
            continue
        if path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError(f'Metadata exceeds 16 MiB: {name}')
        json.loads(path.read_text())
        if name in files:
            raise ValueError(f'Export already contains {name}')
        files[name] = path.resolve()
    if 'delivery.json' in files:
        raise ValueError('Export page collides with delivery metadata')
    if destination.exists():
        raise FileExistsError(f'Refusing to overwrite {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.partial-delivery-', dir=destination.parent))
    try:
        digests = {}
        for name, path in sorted(files.items()):
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            digests[name] = hashlib.sha256(target.read_bytes()).hexdigest()
        (staging / 'delivery.json').write_text(json.dumps({
            'schema_version': 1, 'asset_id': manifest['asset_id'],
            'profile_id': manifest['profile']['id'], 'sha256': digests,
        }, indent=2) + '\n')
        staging.rename(destination)
    except BaseException:
        shutil.rmtree(staging)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Completed export directory')
    parser.add_argument('destination', type=Path, help='New directory in consumer assets')
    parser.add_argument('--outfits', type=Path)
    parser.add_argument('--provenance', type=Path, help='Optional source hash inventory')
    parser.add_argument('--outfits-all', type=Path)
    parser.add_argument('--outfits-showcase', type=Path)
    parser.add_argument('--catalog', type=Path)
    args = parser.parse_args()
    deliver(args.source, args.destination, args.outfits, args.provenance,
            args.outfits_all, args.outfits_showcase, args.catalog)
    print(args.destination / 'manifest.json')
