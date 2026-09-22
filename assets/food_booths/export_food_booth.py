"""Export one supplied Sauce It canopy booth .blend file to a Godot-ready GLB."""

from pathlib import Path
import sys

import bpy


def argument(name: str) -> str:
    args = sys.argv[sys.argv.index("--") + 1 :]
    index = args.index(name)
    return args[index + 1]


output = Path(argument("--output"))
output.parent.mkdir(parents=True, exist_ok=True)

# The supplied files contain one finalized, bottom-centred render mesh.  Export
# only mesh objects so Blender workspaces and helper data cannot leak into the
# runtime asset.
bpy.ops.object.select_all(action="DESELECT")
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError(f"Expected one finalized mesh, found {len(meshes)}")
meshes[0].select_set(True)
bpy.context.view_layer.objects.active = meshes[0]

bpy.ops.export_scene.gltf(
    filepath=str(output),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_materials="EXPORT",
)
print(f"EXPORTED {output} ({output.stat().st_size} bytes)")
