"""Create the optional import integration fixture in a fresh background Blender.

Run from any working directory:
    blender --background --factory-startup --python tests/create_blend_fixture.py

Never run this script in an interactive Blender session: it deliberately replaces
the current scene. The command above starts an isolated process with factory data.
The generated .blend file is disposable, ignored test data, not a source asset.
"""

from pathlib import Path

import bpy


def neutral_material(name: str, value: float, roughness: float):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (value, value, value, 1.0)
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is None:
        raise RuntimeError("Factory Principled BSDF node is unavailable")
    principled.inputs["Base Color"].default_value = (value, value, value, 1.0)
    principled.inputs["Roughness"].default_value = roughness
    return material


def create_fixture() -> Path:
    if not bpy.app.background:
        raise RuntimeError("Run in a fresh Blender --background --factory-startup process")
    output = Path(__file__).resolve().parent / "fixtures" / "generated" / "import_smoke.blend"
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # Blender Z-up is converted to Godot Y-up by the editor's glTF pipeline.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.0, 0.0, 0.6))
    body = bpy.context.object
    body.name = "ImportBody"
    body.dimensions = (1.0, 0.75, 1.2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    body.data.materials.append(neutral_material("NeutralStone", 0.6, 0.9))

    bpy.ops.mesh.primitive_cone_add(
        vertices=12, radius1=0.7, radius2=0.15, depth=0.6,
        location=(0.0, 0.0, 1.5), rotation=(0.0, 0.0, 0.15),
    )
    cap = bpy.context.object
    cap.name = "ImportCap"
    cap.data.materials.append(neutral_material("NeutralRoof", 0.8, 0.5))

    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    # Do not accumulate .blend1 backup copies for this disposable fixture.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False)
    return output


if __name__ == "__main__":
    print("BLEND_IMPORT_FIXTURE=" + str(create_fixture()))
