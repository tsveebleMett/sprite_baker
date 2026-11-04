# Modular male-human equipment

See the [source inventory, palette modes and provenance contract](../assets/human_male/README.md).

- `configs/human_male_complete.json`: all 46 parts, eight animation clips, one
  shared profile. This is the complete equipment delivery recipe.
- `configs/human_male_outfits_all.json`: 24 loadouts covering every part.
- `configs/human_male_outfits_default.json`: six appearances for the normal game.
- `configs/human_male_outfits_showcase.json`: eight appearances, two per family.
- `configs/human_male_preview.json`: original thirteen-part milestone recipe.
- `configs/human_male.json` and `_2h`, `_bow`, `_staff`: family-specific recipes
  for authoring; do not mix separately fitted exports.

The [delivery contract](delivery.md) preserves the exported PNG/JSON bytes.
Appearance `animations` maps semantic movement states to the appropriate baked
family; e.g. `{"idle":"idle_bow","walk":"walk_bow"}`. Legacy presets without
that field retain their original behavior.
