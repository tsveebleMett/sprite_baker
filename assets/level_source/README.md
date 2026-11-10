# Pinned original level sources

Generated dependencies are ignored. `scripts/prepare_level.py --source CHECKOUT`
stages the dependency closure of the original Plunderground terrain v3 compiler,
mesh builder, materials and mine torch. It records both original and transformed
SHA-256 hashes and the Git revision. No original files are edited.

The isolated copy rewrites resource paths, removes foreign UIDs, preserves the original wall-torch material-assignment script, and replaces VFX shader TIME with a sampled uniform.
Missing original OBJ MTL sidecar declarations are omitted only in the staged copy;
source assembly explicitly binds the actual wood/stone materials.
Geometry, texture bytes, resolver rules, material properties, and particle process
resources otherwise come from the source tree. Redistribution rights remain those
of the source assets; this adapter does not grant a new license.
