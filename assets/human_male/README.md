# Original modular male human

This adapter uses the original user-provided Plunderground meshes, skeleton,
animations and equipment, not generated replacement artwork. Source files remain
in the user's reference repositories. Derived binary assets under `generated/`
are ignored: no redistribution license was found in the inspected asset folders,
and this adapter does not grant or change one.

## Reproduce

Requires Python 3 with Pillow and the project's Godot version. From the baker root:

```sh
python3 scripts/prepare_human.py --source-root /path/to/plunderground_4.4 --hoardfall-root /path/to/Hoardfall
godot --headless --editor --path . --import
godot --path . --script scripts/bake_human.gd -- res://configs/human_male_preview.json
```

The bake requires a graphics renderer, including under Xvfb on Linux. A second
argument after the config selects an absolute output parent. Existing exports are
not overwritten. Preparation deterministically refreshes **only generated inputs**
and the `configs/human_male*.json` recipes; customize a copied recipe instead.

## Inventory and conventions

- Nine original body meshes: base, hideArmor, furArmor, lightArmor, leatherArmor,
  cuirBouilli, studdedLeather, robe, surcoat. Surcoat is present in Plunderground's
  GLB but not enabled by Hoardfall's human model map.
- Original head, short hair, goatee; four helmets: Hood, Pelt, Cerveilliere, KettleHat.
- Hoardfall's authored equipment scenes: Falchion, FlangedMace, ShortSword,
  BattleAxe, Longbow, Quarterstaff, WalkingStick, KiteShield, ReinforcedShield,
  RoundShield. Each is stripped to its authored mesh and texture dependencies;
  game scripts/collisions/callbacks are not executed. The remaining original
  Plunderground hand equipment is also included: Centefist, Hammer, MorningStar,
  SpikedClub, Claymore, Greatclub, Maul, Pickaxe, StoneAxe, Flatbow, RecurveBow,
  Shortbow, Warbow, GemstoneStaff, MetalStaff, Shortstaff and PlankShield.
  Thus the full recipe has 43 independently selectable parts. Same-named
  Hoardfall imports take precedence; texture filenames include a content hash
  to prevent accidental cross-repository basename collisions.
- Weapons attach to `Bone.hand_R.Attachment`, including bows. Shields attach to
  `Bone.hand_L.Attachment`. Mesh-local transforms (including shield rotations)
  survive staging. The original rig remains intact; there is no retargeting.
  The original model faces +Z; a PI-radian Y wrapper (also used by Hoardfall)
  normalizes the entire rig and its attachments to the baker's -Z convention.
- `human_male.json` uses original `Idle` / `Walk`; `_2h`, `_bow`, `_staff` recipes
  use their matching authored clips. These recipes share all parts for further
  loadout authoring; choose a clip family suitable for the equipped weapon.
- Every recipe uses eight directions, 128×128 target pixels, 2× supersampling,
  six samples/second and complete source loops. The baker fits a common profile
  over every selected part, direction and sampled pose.
- The preview recipe selects thirteen parts for three color/equipment combinations.
  `human_male_outfits.json` selects parts by slot and tints by region name, for the
  Rust consumer. Hair is omitted under helmets; it must not be stacked through one.

## Palette contract

`human_male_catalog.json` records Hoardfall's six cloth colors, six skin colors,
seven hair colors and body/helmet material roles. These are independent choices,
not three immutable character skins. The generated preview outfits are examples.
Skin, hair, body primary/secondary and helmet primary/secondary can be recolored
independently at composition time using sRGB float triplets. Body/helmet material
colors follow Hoardfall's outfit/material blends (leather 65%, fur 80%, metal 90%).

The source palette is 5×96 pixels: base, helmet and body rows of 32 gradient shades.
Masks address the same UVs. Selected source stripes are converted to grayscale
and normalized to their peak luminance **per mesh**, retaining the authored shade
shape; unmasked source trim stays unchanged. This is essential: multiplying a
new color onto originally blue cloth or brown hair cannot recover arbitrary colors.
The baker still supplies its own lighting and linear-light composition, so exact
pixel parity with either Godot game's lighting/shader is not claimed.

### Full source-gradient bake

To author all thirty source palette endpoints, pass
`--palette-config configs/human_male_source_palette.json` during preparation.
Its `rows` array contains 3 rows × 5 slots × 2 RGBA endpoints, in sRGB, taken from
Plunderground's original male `Default_palette.tres`. This path disables runtime
tint masks and bakes the selected fixed appearance. Re-import before baking; an
existing export is immutable and is unaffected. To return to runtime tint mode,
prepare again without `--palette-config` and re-import.

The source shader interpolates endpoint colors in linear light, falling back to
base-row colors when an equipment override is transparent. The adapter samples
that same formula into a nearest-filtered 5×3072 texture (1024 shade steps per
row), retaining the original vertex colors. This supports every endpoint color,
but **is not pixel-exact shader parity**: texture quantization bounds the gradient
parameter error to 1/2048 within a stripe, plus 8-bit color rounding. Runtime tint
mode instead preserves normalized authored gradient shape; it does not independently
change both endpoints. Animated status/enchantment shaders and custom item material
rolls are not baked by this adapter.

Cuirass and FinnegansValor have item-display scenes but no distinct active worn
visual in the inspected source: `assets/models/creatures/model.gd:333` hides armor
item models and leaves `attach_item_meshes(item)` commented out; their item data
sets no `armor_skin`. The adapter therefore does not invent rigid chest visuals
for those item names.

## Provenance

`generated/provenance.json` records the original male GLB SHA-256 and each imported
item scene hash. The original GLB is
`Plunderground_4.4/src_models/human_male/human_male.glb`; Hoardfall's corresponding
source manifest is `assets/models/players/plunderground/source-manifest.json`.
Colors/material roles come from `scripts/roguelike/starter_party.gd`,
`scripts/ui/components/human_model.gd`, and `scripts/ui/equipment_palette.gd`.
Generated palettes modify no vertex, skin bind, bone, or animation data.

### Explicit material exclusion

`artifact_ring` is listed in the catalog's `unsupported` entries, not silently
substituted: its original iron material uses real triplanar color, normal,
roughness and metalness textures. The baker rejects that material model. The
43-part recipes therefore cover the source human meshes plus hand weapons and
shields, not rings. A future ring adapter needs faithful UV/material conversion.

### Verification

After preparation/import, validate all four 43-part animation-family recipes and
the forward-axis contract with:

```sh
godot --headless --path . --script tests/test_human.gd
python3 -m unittest discover -s tests -p test_human_outfits.py
```

The outfit contract intentionally lists **every available preview slot** and uses
`""` for disabled parts. Omitting a slot selects a default part; adding unknown
slots is invalid. Therefore the unhelmeted traveller explicitly selects
`"helmet": ""` and `"shield": ""`, while helmeted outfits set `"hair": ""`.
Preparation/validation of all 43 parts is not a claim that all combinations have
been rendered: the initial preview bake contains thirteen selected parts.
