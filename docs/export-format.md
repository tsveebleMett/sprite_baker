# Sprite Baker export format, version 1

An export is a directory containing `manifest.json` and lossless RGBA8 PNG
atlases. It has no dependency on Godot at consumption time. The reference
consumer is `src/export/export_reader.gd`, backed by the pure image compositor
in `src/core/compositor.gd`. This document defines the same algorithm for other
engines. Consumers must implement the depth comparison and recoloring; simply
drawing conventional 2D sprite layers does not reproduce the export.

## Publication and files

The writer creates `.partial-<asset>-<timestamp>-<unique>/` under the chosen
output directory. It writes every PNG, validates the manifest against the image
headers, writes `manifest.json` last, then renames the directory to
`<asset>-<timestamp>-<unique>/`. Existing exports are never overwritten.
Canceled or failed exports remain visibly incomplete in `.partial-` directories;
the reader refuses them. These directories can be deleted manually after
checking that their data is no longer needed.

The default location is `res://output`, excluded from Git. The writer adds
`.gdignore` to that dedicated root if missing, and to each owned staging directory
so Godot does not import its own outputs. Existing markers are preserved byte for
byte. External selected parent directories are never given or rewritten a marker;
only the newly created export directory is ignored. Internal custom locations must
stay below `output/`; external absolute directories and `user://` locations are
supported. Source assets and saved bake configurations remain separate.

The filenames are:

```text
sheet_<sheet_key>__p000_color.png
sheet_<sheet_key>__p000_mask.png
sheet_<sheet_key>__p000_depth.png
manifest.json
```

`sheet_key` is the full lowercase hexadecimal SHA-256 of the compact JSON array
`[part_id,animation_id]`. Array serialization preserves ID boundaries, while the
hash avoids filename aliases for IDs differing only in case on Windows. Consumers
always read paths from the manifest rather than deriving filenames.

IDs contain only ASCII letters, digits, `_` and `-`, with 1–100 characters.
Paths in the manifest are relative to the manifest directory. Absolute paths,
backslashes, `.` and `..` path segments are invalid. PNG images use 8 bits per
channel, RGBA color type, straight alpha, no mipmaps and lossless compression.
Do not apply color-space conversions or texture compression to mask/depth bytes.

## Manifest structure

| Field | Meaning |
| --- | --- |
| `schema_version` | Integer `1`; reject unknown versions. |
| `asset_id`, `asset_type` | Asset identity; type is `creature`, `item`, or `prop`. |
| `profile` | Shared camera and raster profile, including its stable `id`. |
| `depth` | Shared linear depth range and encoding described below. |
| `animations` | Ordered list with `id`, source `name`, `times` in seconds, and `loop`. |
| `parts` | List of `id`, `slot`, `variant`, integer `priority`, and up to three `regions` names. |
| `sheets` | Exactly one entry for every part/animation pair. |

The profile includes `target_size: [width,height]`,
`export_size: [width,height]`, integer `supersample`, `directions`, and
`pivot: [x,y]`. Export dimensions equal target dimensions times supersample.
The default supersampling factor is two. `pivot` is the projected common model
origin in **export-frame pixels**, measured from the upper-left corner; divide
by `supersample` for target-frame coordinates. It is not relative to an atlas.
The profile also retains camera elevation, azimuth, orthographic size, target,
distance, near/far planes, and locking settings for reproducibility.

Each sheet has `part_id`, `animation_id`, `pages`, and `frames`. A page contains
`size: [width,height]` and the three image paths `color`, `mask`, and `depth`.
A frame contains:

```json
{"frame": 0, "direction": 0, "page": 0, "rect": [0, 0, 512, 512]}
```

`frame` indexes the animation's `times` array. Coordinates are integer pixels,
with origin at the upper left. `rect` is `[x,y,width,height]` and is identical
for all three channels. Every frame/direction pair occurs exactly once. Frames
form columns, directions form rows; pages split columns and, when necessary,
direction rows. Page dimensions never exceed 4096 × 4096. Consumers use explicit
rectangles rather than assuming a fixed number of columns.

Times are finite, nonnegative and strictly increasing. A static pose has one
time. Loop sampling omits the duplicated final pose. All combinable parts share
the same profile, animation times and frame geometry; a profile change requires
rebaking the family. Parts from different profile revisions cannot be mixed.

## Coordinate and lighting conventions

The scene is right-handed, Y-up. An asset is prepared facing local −Z. The
camera looks along its local −Z axis and stays fixed at the configured azimuth
and elevation, pointed at the profile's camera target. Direction `d` rotates
the complete assembly around its shared origin by
`2π × d / directions` about +Y. The default camera azimuth is 45° and elevation
is 30° above the horizontal, producing the classic 2:1 view. The lights stay
fixed while the assembly rotates.

Each part is rendered in isolation: pixels hidden by other parts remain in its
images. Self-shadowing is allowed, but lighting, shadows, ambient occlusion and
reflections from other exchangeable parts are excluded. Otherwise an individual
part would contain a baked dependency on one equipment combination.

Version 1 supports opaque geometry and alpha-cutout materials. It does not
represent glass, layered translucency, or multiple depth samples at one pixel.
Input equipment must fit its family rig; the baker does not retarget or resize
incompatible armor automatically.

## Linear depth: RGB24, big endian

The manifest contains:

```json
{
  "encoding": "rgb24-be",
  "near": 0.05,
  "far": 20.0,
  "near_is_small": true,
  "tie_break": "higher_priority_then_part_id"
}
```

Depth `z` is positive linear camera-space distance, **not** a hardware depth
buffer value. With the shared near/far range:

```text
n = clamp((z - near) / (far - near), 0, 1)
q = floor(n × 16777215 + 0.5)
R = (q >> 16) & 255
G = (q >> 8) & 255
B = q & 255
A = 255 for a valid sample, 0 for background

q = R × 65536 + G × 256 + B
z = near + q / 16777215 × (far - near)
```

Never bilinearly filter the packed RGB channels, generate mipmaps, average
depth samples, or load depth as sRGB. Compare integer `q` directly when profiles
match. The smallest valid value wins. Equal values prefer higher part priority;
equal priority then prefers the lexicographically smaller part ID. Background
is detected through alpha, not by a special RGB value. Color alpha also must be
nonzero for a sample to participate.

## Three-color masks and tinting

RGB mask channels contain linear weights for `regions[0..2]`, not sRGB colors.
The region names describe their meanings per part, for example cloth, leather,
and metal. A part may declare zero to three regions; missing trailing regions
are unused channels. Black means unchanged. For weights `w` and linear RGB
tint colors `t0`, `t1`, `t2`:

```text
w = clamp(mask.rgb, 0, 1)
if sum(w) > 1: w = w / sum(w)
factor = (1 - sum(w)) + w.r × t0 + w.g × t1 + w.b × t2
tinted_linear_rgb = srgb_to_linear(color.rgb) × factor
alpha = color.a
```

The reference UI accepts sRGB tint colors and converts them to linear first.
Mask alpha is not a fourth tint region. Prepare the tintable base material
with neutral color and useful luminance; multiplication cannot brighten black.
Texture detail and the baked illumination remain in the base color image.

## Composition and downsampling

1. Choose at most one part per slot. An omitted choice selects the
   lexicographically first part ID in that slot. An empty choice disables it.
2. Crop the requested frame/direction from each chosen part's three atlases.
3. At the unfiltered export resolution, select the visible sample using the
   depth/priority/ID rules above.
4. Apply that sample's mask and three tint colors in linear RGB.
5. Downsample the **assembled image**, using a box average of premultiplied
   linear RGB and alpha over each `supersample × supersample` block.
6. Divide the averaged premultiplied RGB by averaged alpha where nonzero,
   convert RGB to sRGB, and write straight-alpha output. Fully transparent
   pixels have zero RGB.

This ordering gives antialiasing without mixing packed depths or baking
coverage fringes independently into overlapping parts. The reader uses only
the manifest and exported PNG bytes and caches at most six atlas images.

## Validation and executable reference

The reference reader rejects unsupported versions, malformed types, unknown
part/animation references, duplicate IDs, missing frame/direction pairs, invalid
rectangles, inconsistent sizes, invalid depth ranges and unsafe paths. PNG
headers are checked before image decoding, including their exact dimensions
and RGBA8 format. JSON manifests are limited to 16 MiB. Image decode errors are
reported instead of returning a partial composite.

Run the I/O tests from the repository root with a Godot 4.6.1 executable:

```powershell
godot --headless --path . --script tests/test_export.gd
```

These tests exercise publication, cancellation, loading, composition, invalid
metadata, path boundaries, exact depth-byte PNG roundtrips and malformed input.
