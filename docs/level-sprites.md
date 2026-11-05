# Original terrain sprites

The level adapter captures a **complete pinned layout**, not independently fitted
wall masks. Current master uses terrain v3: contour smoothing crosses tile seams
and is seeded. The older four-quadrant OBJ Wall scene is still present but is not
the current mines generator. Capturing 256 independent legacy masks would not
preserve current geometry. No new graphics/physics library is required.

## Reproduction

1. Export a Rust layout with `examples/export_level_layout.rs`. It contains all
   region coordinates, floor/wall/torch tags, seed and canonical layout digest.
2. `python3 scripts/prepare_level.py --source ORIGINAL_MASTER_CHECKOUT`
3. `godot --headless --editor --path . --import`
4. On a real display with the configured Forward+ renderer:
   `godot --path . --fixed-fps 60 --script scripts/bake_level.gd -- LAYOUT.json NEW_CAPTURE`
5. `godot --headless --path . --script scripts/level_navigation.gd -- LAYOUT.json NEW_CAPTURE/navigation.json`
6. `python3 scripts/pack_level.py NEW_CAPTURE NEW_BUNDLE --layout LAYOUT.json --page-size 4096`
7. Copy `assets/level_source/provenance.json` to `NEW_BUNDLE/source-provenance.json`
   and run `python3 scripts/verify_level.py NEW_BUNDLE` to validate and hash the delivered payload.

On Linux specify `--display-driver wayland` when using native Wayland. The baker
selects supported mailbox presentation; no OS scheduling or GPU settings change.
Use a new output directory; never overwrite an already delivered bundle.
`pack_level.py --page-size 4096` reduces texture switches without changing pixels.
`bake_level_torches.gd -- LAYOUT NEW_CAPTURE PREVIOUS_CAPTURE` recaptures only
mounted torches while copying static captures byte-for-byte.

## Source and capture contract

`prepare_level.py` stages only transitive dependencies, preserving source hashes.
`bake_level.gd` invokes the original Resolver, Builder and Materials over the full
layout. The mine wall-contact field is built over that same layout. Original
material texture data, deformation, contours, black crown and assembly are used.
The fixed projection is azimuth45/elevation30, 160×80 pixels per2.5-world-unit
cell, 2× supersampling. Every sprite shares the original tileground pivot. Frames
are alpha-cropped and losslessly shelf-packed into shared2048² or4096² RGBA pages with
transparent gutters. Identical pixel frames are deduplicated. Frames are packed
by descending height to avoid floor/wall shelf fragmentation. Capture edge RGB
is unpremultiplied for PNG consumption; opaque terrain receives half-pixel
coverage overlap at antialiased seams. True particle transparency is not hardened.

Source floor/opaque and wall meshes are separate layers: the contour compiler can
put vertical wall geometry in a coarse floor cell. Consumers must render every
exported layer, not infer visual kind solely from the original coarse tag.
The original terrain flags are exported separately for subtile navigation review.
Their5×5 row-major cells correspond to offsets[-2,2] around the source tilecenter.

Torch geometry, wood/metal assignments, GPU particle resources, flame/smoke/flare
textures and VFX shaders are original. The actual master
`IronmineDressing._place_torch` adapter moves the emitter to the wooden tip,
rotates the complete scene byPI and mounts its bracket against sampled displaced
wall triangles. Coarse torch requests without a safe source anchor are rejected.
Each accepted mount receives24frames at12fps with its exact fitted transform;
the bare source scene at identity is not the assembled runtime appearance.
The seed and shader sample clock are fixed. Each adjacent sample spans exactly
five60Hz simulation ticks (including the capture await), matching its1/12-second
timestamp; this is asserted during capture and independently validated from
exported `simulation_tick` values. Preparation rejects overlapping source/staging
paths. Packing rejects mismatched capture/layout/navigation digests before publication. This is a sampled particle animation,
not an authored mathematically periodic cycle. A finite loop may have a wrap change.

## Appearance limits

The mine's original lighting color, ambient energy and tonemap are retained.
Screen-distance fog, volumetric fog, bloom and dynamic shadows are disabled for
independent transparent sprites. Sprites do not relight dynamically, and the torch
sprite does not illuminate neighboring wall/ground sprites. These are fixed-view,
fixed-lighting segment captures, not pixel-identical arbitrary 3D camera scenes.

`source-patch.png` is an independent depth-tested original3D patch captured under
that same fixed rig; `sprite-patch.png` reconstructs its per-cell layers. Their
comparison exposes painter-order and alpha seam differences. It does not certify
all world occlusions or game FPS. Consumer hardware acceptance must measure the
full scene with100living enemies and animation enabled, not this offline producer.

A bundle is valid only for its exact seed/layout digest. Re-bake changed layouts;
never silently substitute a matching-neighbor mask from a different compiled world.
