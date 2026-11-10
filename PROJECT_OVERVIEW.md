> **Project Overview Snapshot Date:** 2026-11-05
> **Audience:** AI coding agents — optimized for fast context loading before code tasks.
> **Maintenance Policy:** This document is maintained by AI agents. If you notice
> outdated information, update the relevant section and refresh the snapshot date.

## Project Identity

### Executive Summary

Sprite Baker is a native Godot authoring tool for isometric sprite sheets from
animated modular creatures, static items and props. It exports immutable,
engine-independent PNG atlases and JSON manifests, not a running game or service.
Each interchangeable part retains aligned color, recoloring-mask and depth data;
the consumer selects equipment, recolors and depth-composes the final appearance.
The built-in preview consumes only exported PNG/JSON files.

Current exports use manifest schema 2 with cropped frames; readers also accept
legacy schema 1. Authoring configurations independently remain schema 1.
See [the export contract](docs/export-format.md) and [delivery contract](docs/delivery.md).

### Domain Glossary

| Term | Project-specific meaning |
| --- | --- |
| Family | Parts fitted together across selected poses/directions with one camera, pivot, depth range and timing contract. |
| Animation family | One-handed (`1h`), two-handed (`2h`), bow or staff idle/walk clips; not permission to mix separately fitted exports. |
| Profile / lock signature | Camera/raster configuration and signed inputs checked before baking; not an environment profile. |
| Part / slot / variant | Independently captured geometry / exclusive selection group / authoring label. Empty selection disables a slot; omission chooses its first part ID. |
| Paper doll | Per-pixel depth composition of equipment layers, not ordinary sprite draw ordering. |
| Sheet / page | A part-animation collection / matching color, mask and depth atlases within it. |
| RGB24 depth | Big-endian packed linear camera-space depth with alpha validity, not hardware depth or sRGB color. |
| Region | One of up to three named tint-mask channels per part; outfit tint names can span different parts. |
| Runtime tints / fixed endpoints | Neutralized source palette for runtime recoloring / source-gradient colors baked with tint masks disabled. |
| Artifact slots | `artifact_1` and `artifact_2` attach ring geometry to right/left hand bones. |
| Hoardfall shortbow | `weapon_hoardfall_shortbow`, a Longbow appearance scaled by 0.72; distinct from the original Shortbow mesh. |

## Architecture & Components

### Module Map

| Module | Responsibility |
| --- | --- |
| `src/ui/` | Programmatic Control UI: source inspection, part/clip editing, fit/bake and exported-image preview. |
| `src/core/` | RefCounted helpers for config validation, sampling, atlas layout, depth encoding and CPU composition. |
| `src/scene/` | Procedural demos, imported scenes, rig validation, isolated animation sampling and posed geometry. |
| `src/render/` | Bake coordinator, isolated SubViewport stage, orthographic framing and beauty/mask/depth passes. |
| `src/export/` | Manifest validation, immutable publication, bounded-image reader and shared-channel packing; external PNG/JSON interface. |
| `configs/` | Authoring recipes, human palette/catalog data and consumer outfit sidecars. |
| `scripts/` | Standalone launcher, preparation, migration, verification and delivery tools; not all are part of app startup or aggregate tests. |
| `tests/` | SceneTree tests, Python unittest and optional original-source integrations. |
| `assets/`, `docs/` | Local input ownership and technical contracts; generated human binaries are ignored. |

### Directory Structure

```text
sprite_baker/
├── assets/                 # User-owned model sources
│   └── human_male/         # Original-human adapter documentation
├── configs/                # Recipes, palettes and outfit catalogs
├── docs/                   # Interchange contracts and validation evidence
├── scripts/                # Launcher and standalone pipeline tools
├── src/                    # Godot application
│   ├── core/               # Pure validation and image algorithms
│   ├── export/             # Package publication and consumption
│   ├── render/             # Capture stage and shaders
│   ├── scene/              # Imported models and sampled geometry
│   └── ui/                 # Authoring and preview controls
└── tests/                  # Logic, integration and rendering harnesses
```

### Data Flow

1. `src/ui/main.tscn` loads `src/ui/main.gd`; UI or `scripts/bake_human.gd`
   passes a JSON configuration to `src/render/baker.gd` for validation.
2. The scene adapter loads a procedural demo or imported scene, strips source
   node scripts, validates parts/rigs/tracks and samples poses without gameplay.
3. Framing measures every selected pose/direction and locks shared camera/raster
   inputs. Baking rechecks the signature and bounds before capturing parts alone.
4. The stage renders beauty, mask and depth; `compact_page.gd` crops their common
   alpha union and packs aligned rectangles, preserving canvas offsets and pivot.
5. The writer validates staged PNGs, writes the manifest last and renames the
   `.partial-*` directory. Failures/cancellation never publish a complete bundle.
6. The reader restores cropped frames into the common canvas, selects nearest
   valid depth, applies linear-light tints and downsamples the composed image.
7. Optional human preparation derives local inputs; delivery copies completed
   PNG/JSON bytes and validated sidecars to a new consumer folder with hashes.

## Tech Stack & Tooling

### Build Commands

Run from the repository root. `godot` means the selected compatible executable;
use the exact engine requirement in `project.godot` and `README.md`.
There is no separate application compilation step or checked-in export preset.

| Purpose | Command |
| --- | --- |
| Run locally | `godot --path .` |
| Open editor | `godot --editor --path .` |
| Initial/changed source import | `godot --headless --editor --path . --import` |
| Core application aggregate (PowerShell) | `./scripts/run.ps1 all-tests` |
| Python regressions | `python3 -m unittest discover -s tests -p 'test_*.py'` |
| Core statement coverage only | `python3 tests/core_coverage.py --godot godot` |
| One headless engine test | `godot --headless --path . --script tests/test_core.gd` |
| One display-backed engine test | `godot --path . --script tests/test_render.gd --resolution 1440x960` |
| Complete human bake, prepared assets required | `godot --path . --script scripts/bake_human.gd -- res://configs/human_male_complete.json` |

Preparation, immutable delivery, original-source tests and legacy-package migration
commands are in [human source instructions](assets/human_male/README.md) and
[delivery instructions](docs/delivery.md). Never rerun preparation just to refresh documentation.

### Languages & Frameworks

- Godot 4 and GDScript: application and SceneTree tests; Forward+ is configured
  in `project.godot`. Godot spatial shader language implements mask/depth capture.
- Python 3: preparation, transport, verification, standard-library unittest and
  coverage instrumentation; Pillow is imported by preparation and crop verification.
- PowerShell: `scripts/run.ps1` launcher and aggregate tests. Python must also be
  available as `python` when this launcher invokes coverage.
- JSON, Godot scene/resource formats and PNG: authoring, source and interchange data.
- Blender and its Python `bpy` API: optional blend import and fixture generation;
  supported setup is documented in `README.md`.
- Linux/Xvfb with Mesa llvmpipe Vulkan is documented correctness-test tooling,
  not a target-hardware performance guarantee or a different application renderer.
- Rust/Bevy and Cargo belong to the external consumer, not a module/build here.
  No Godot addons, package lockfile or pinned Pillow dependency manifest is tracked.

## Key Files & Configuration Reference

| File | Purpose | Notes |
| --- | --- | --- |
| `project.godot` | Engine, renderer and entry point | Forward+, Blender importer, desktop dimensions; no configured autoloads or custom input map. |
| `src/ui/main.tscn` | Minimal main scene | Control hierarchy is constructed by its script. |
| `src/core/config.gd` | Authoring schema/defaults | Capture cap, portable IDs, profile and source/output validation. |
| `src/render/data_pass.gdshader` | Exact data-channel capture | Preserve byte encoding and material sampling contract. |
| `src/export/manifest_validator.gd` | Export boundary | Schema/frame/path/PNG-header validation. |
| `configs/demo_creature.json` | Self-contained example | Variant equipment; no external models required. |
| `configs/human_male_complete.json` | Shared complete bake | 46 parts and eight clips; generated human assets required. |
| `configs/human_male_preview.json` | Smaller milestone bake | 13 parts and two clips. |
| `configs/human_male_outfits_all.json` | Complete loadout coverage | 24 presets; default/showcase companion files contain six/eight. |
| `configs/human_male_catalog.json` | Palette and equipment roles | Weapon-to-animation-family mapping. |
| `configs/human_male_source_palette.json` | Fixed endpoint input | Optional preparation mode, different from runtime tints. |
| `scripts/run.ps1` | Existing aggregate gate | Executable selection, log scanning and coverage; not a CI pipeline. |
| `scripts/prepare_human.py` | Source adapter | Regenerates human inputs and recipes; requires explicit local source roots. |
| `scripts/deliver_export.py` | Byte-preserving consumer delivery | New destination only; records SHA-256 payload inventory. |
| `scripts/compact_export.gd`, `scripts/verify_compact.py` | Offline v1-to-v2 migration/check | New package; no rerendering or source mutation. |
| `scripts/extend_human_bundle.gd` | Add an in-bounds variant | Restores original lock; never refits or replaces published sheets. |
| `scripts/reference_composites.gd` | Consumer parity reference | Export-only composition with outfit/action mapping. |
| `tests/core_coverage.py` | Statement instrumentation | Temporary source copies only under `.godot/core-coverage/`. |
| `assets/human_male/.gitignore`, `.gitignore` | Generated-data boundaries | Keep caches, local tools, outputs and prepared original assets out of Git. |

## Dependencies & External Services

| Dependency | Purpose and environment scope |
| --- | --- |
| Godot filesystem/importer | All native application/test modes; local sources, JSON and PNG storage. |
| Blender | Optional `.blend` source import and generated Blender-fixture test only; real local executable. |
| Pillow | Optional human preparation/crop verification and full Python regression discovery; local package. |
| Plunderground source tree and Hoardfall | Optional human preparation only; real local source assets and appearance definitions. |
| plunderground_rust | Optional delivery/parity workflow only; separate filesystem consumer, no runtime network dependency. |

No database, message broker, distributed cache, hosted API, identity provider or
application authentication/secret configuration is implemented in the tracked app.
Local OS permissions govern access. The export reader's six-image memory cache
is not a service. Missing dependencies fail the affected local operation; there
is no remote retry infrastructure. No service listening ports are configured.

## Local Development Setup

1. Obtain this checkout and a compatible Godot 4 executable using the engine
   requirement in `project.godot`/`README.md`; provide a working Forward+ renderer.
2. Use the editor/import and local-run entries above. Built-in demos require no
   external assets. Import newly added sources before selecting them in the UI.
3. Add Python 3 and Pillow for the human/tooling regression path; Blender is only
   needed for blend sources. PowerShell is optional if invoking tools directly.
4. For original humans, follow the source adapter instructions with authorized
   local input trees. Customize copied recipes: preparation refreshes generated
   inputs and `configs/human_male*.json`, not just ignored files.

Launcher precedence: explicit `-Godot`/`GODOT_BINARY`, ignored portable executable,
`GODOT_PATH`, then PATH. JSON recipes configure assets, not dev/staging services.
Desktop rendering, headless logic and optional original-source integrations have
different prerequisites; there are no container deployment profiles or server ports.

## Testing Strategy

Full existing application aggregate: `./scripts/run.ps1 all-tests`.
Also run `python3 -m unittest discover -s tests -p 'test_*.py'` for Python regressions.

- Headless scripts: `test_core`, `test_scene`, `test_export`, `test_compact`, `test_ui`.
- Display-backed scripts: `test_render`, `test_render_quality`, `test_ui_render`.
  Without PowerShell, invoke these same `tests/<name>.gd` scripts using the table's
  appropriate engine command and run the coverage helper separately.
- Coverage enforces at least 80% aggregate executed statements in `src/core/`, not
  branch coverage. Reports are under `.godot/core-coverage/`; runner logs under `.tools/test-logs/`.
- Optional prepared-source gates: `test_human.gd` (headless), `test_ring_render.gd`
  and `test_blend_import.gd` (display-backed); `test_example.gd` is a larger acceptance bake.
- The launcher rejects engine error log lines as well as failed exits. Apply the
  same rule to direct invocations; keep renderer/import state consistent.

No tracked CI, deployment pipeline, formatting gate or repository hook is present.
[Milestone evidence](docs/human-milestone-validation.md) is revision-specific:
its 43-part inventory and ring restriction predate current 46-part/triplanar code.

## Conventions

- Preserve node/bone paths, part IDs, slots, region names, animation mappings and
  schema fields; consumer contracts are broader than the authoring UI.
- Follow existing snake_case GDScript paths/functions, tab indentation, explicit
  preloads and focused helpers; Node owns rendering lifecycle, RefCounted owns algorithms.
- Keep source scenes isolated: supported tracks are 3D position/rotation/scale and
  blend shapes, not live scripts, physics, visibility/material tracks or retargeting.
- Preserve PNG data bytes and crop alignment; downsample only after composition.
  Masks/depth must not receive sRGB conversion, bilinear filtering or lossy compression.
- Keep `.godot/`, local tools, outputs and prepared original binaries untracked.
  Source provenance does not grant redistribution rights. Technical contracts are English;
  existing user-facing UI/README text includes German. No formatter is configured.

## Original level adapter

The optional `scripts/prepare_level.py`, `bake_level.gd`, `level_navigation.gd`
and `pack_level.py` pipeline captures pinned original-master terrain v3 layouts,
source PBR materials and animated torch particles. It exports a separate
`level-manifest.json` contract; it does not change the creature schema. See
[original level sprites](docs/level-sprites.md). Generated source dependencies in
`assets/level_source/` stay ignored; source revision/hashes accompany delivery.

## Operational Gotchas

1. **Headless is not a bake renderer.** `Baker.bake()` rejects it. Use a display-backed
   Forward+ run, including under Xvfb; software-rendered correctness is not performance evidence.
2. **Fit the compatible family together.** Signed input changes require refitting;
   out-of-bounds variants fail. Limits are 100,000 captures and 4096-pixel atlas sides.
3. **Do not confuse schema or selection semantics.** Config v1 differs from export
   v2; restore offsets before composition. Empty slots disable, omitted slots select defaults.
4. **Outputs and sources have different ownership.** Never overwrite published
   bundles or accept `.partial-*` as complete. Original-human preparation needs local
   sources; opaque untinted triplanar is supported, but tinted/cutout triplanar is rejected.
5. **Linux export tests need external `TEMP`.** Set it to a writable directory outside
   this checkout; the test explicitly exercises an external output boundary.
