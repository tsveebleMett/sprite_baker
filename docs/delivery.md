# Delivery to plunderground_rust

The interchange contract remains [export format v1](export-format.md). The baker
owns source models, animation sampling, cameras, masks and depth capture. The
consumer owns outfit selection, per-region tint colors, depth composition,
animation playback and game rendering. Do not flatten modular parts in transit.

After a successful bake, deliver a new immutable bundle:

```sh
python3 scripts/deliver_export.py output/<completed-export> \
  ../plunderground_rust/assets/sprites/human_male \
  --outfits configs/human_male_outfits.json \
  --provenance assets/human_male/generated/provenance.json
```

The destination must not exist. The script rejects incomplete export directories,
unsafe/missing page paths, unsupported schema versions and inconsistent RGBA8 PNG
headers, then copies the manifest and referenced pages unchanged. A staging
folder is renamed only after all copies finish. `delivery.json` records SHA-256
for every delivered file, plus asset/profile identity. This is transport
validation, not a substitute for the consumer's full manifest/image validator.
To update, publish a new destination and point the game at its manifest. Do not
mix parts from separately fitted profiles.

Outfits are consumer configuration, not a new atlas schema:

```json
{"outfits":[{"id":"example","slots":{"body":"body_base","helmet":""},
"tints":{"skin":[0.81,0.61,0.45],"body_primary":[0.14,0.48,0.84]}}]}
```

Slots map to exact part IDs; an empty string disables a slot. Unspecified slots
use the v1 lexicographic default. Tint names match each part's `regions` list;
values are sRGB floats in [0,1]. Missing tints are white. This allows independent
skin, hair, armor and helmet colors even though each individual part has only
three mask channels.

Run the consumer from its repository root:

```sh
cargo run -- --sprite-manifest assets/sprites/human_male/manifest.json \
  --sprite-outfits assets/sprites/human_male/outfits.json
cargo run -- --sprite-manifest assets/sprites/human_male/manifest.json \
  --sprite-outfits assets/sprites/human_male/outfits.json \
  --sprite-preview exports/human-preview
```

The preview must capture the consumer renderer. Baker-rendered previews are
useful export diagnostics but do not prove the game import/render pipeline.

## Cross-language composition check

`scripts/reference_composites.gd` uses the existing GDScript reference compositor
and produces frame-zero PNGs for each outfit and direction of the first animation:

```sh
godot --headless --path . --script scripts/reference_composites.gd -- \
  /absolute/export/manifest.json /absolute/outfits.json /absolute/reference-output
```

The Rust `--sprite-compose <new-directory>` command outputs CPU-composed frame-zero
PNGs for all animations/directions. Compare them to the reference before interpreting
GPU screenshot differences (window scaling, presentation background, text, etc.).
