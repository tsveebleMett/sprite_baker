# Modular human milestone verification

Local baseline: producer `07116d2291ac3099a6a92c0362a5b5a8da857e6b`,
consumer `86400075d924c6a5dbcf43b3f7f7c5fea3c3f114`.
Verification date: 2026-11-04. Godot 4.6.1, Forward+, Linux/Xvfb,
Mesa llvmpipe software Vulkan. This is correctness evidence, not a target-hardware
performance measurement.

## Producer checks

- `tests/test_core.gd`: 325 checks, zero failures.
- `tests/test_export.gd`: 110 assertions, zero failures. On Linux the existing
  test requires `TEMP` set to an external writable directory.
- `tests/test_scene.gd`: 74 checks, zero failures.
- `tests/test_render.gd`: zero failures, GPU-backed PNG publication/consumption.
- `tests/test_render_quality.gd`: 226 checks, zero failures, including eight
  directions and packed-depth/cutout reconstruction.
- `python3 -m unittest discover -s tests -p 'test_*.py'`: delivery and outfit
  regressions, including explicit disabled slots and fixed-palette empty tints.
- `tests/test_human.gd`: full 43-part recipes configure successfully for idle/walk, two-handed, bow and
  staff animation families, including source rig/material validation.
- Optional full-endpoint palette mode: isolated original-head single-frame bake
  succeeds. This does not establish pixel-exact source shader parity.

## Delivered family

The verified preview bundle contains 13 parts, 26 part/animation sheets, 39 atlas
pages and 117 RGBA8 PNG files. Idle has 16 samples; walk has 17 samples. All eight
directions are present: 3,432 part/frame/direction samples. Target resolution is
128×128, exported at 256×256 then composed/downsampled by the consumer.

The final bake exited successfully with no script/render errors. Its immutable
output was copied unchanged into `plunderground_rust/assets/sprites/human_male/`.
`delivery.json` records verified SHA-256 digests for the 120 payload files:
manifest, 117 PNGs, outfits and original-source provenance inventory.

Three explicit outfits exercise different skin/hair/clothing colors, two armors,
two helmets, three hand weapons and two shields. Unused slots are empty strings;
omission would select the first available part under schema v1.

An earlier diagnostic revealed the source's +Z forward axis. The prepared scene
now applies the original Hoardfall PI-facing wrapper before sampling; equipment
inherits the same skeleton transform. A later interrupted bake was not published
because its display server exited. Only the subsequently completed bake was
transported to the consumer.

## Cross-engine verification

The original small creature fixture passes all eight directions with at most one
8-bit channel step difference between GDScript and Rust composition. The delivered human family also passes all 24 idle-frame-zero comparisons
(three outfits × eight directions), with at most one RGBA byte step difference.
The Rust consumer additionally emits all 48 idle/walk frame-zero images.
Comparison evidence is `plunderground_rust/exports/human-final-parity/comparison.json`.
Actual Bevy screenshots/GIFs are recorded in the consumer's validation evidence,
not treated as producer-rendered game screenshots.

## Boundaries

43 parts are prepared and source-validated; the delivered milestone contains the
13-part representative family, not every equipment combination. The ring's
textured triplanar material remains unsupported. Runtime tint mode and the
optional 30-endpoint fixed-palette bake are different workflows; see the
[palette contract](../assets/human_male/README.md). Original 3D sources remain
local and ignored; no source-asset redistribution license is asserted.
