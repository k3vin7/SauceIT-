"""Build the shared Sauce It squeeze-tube asset from the supplied empty bottle.

The source mesh is intentionally kept empty.  This build adds a separate,
opaque mayonnaise volume named ``SauceFill`` so Godot can scale it without
touching the translucent bottle shell.

Run with Blender 5.2:
  blender --background --factory-startup --python Production_SauceTube_S1_build.py
"""

from pathlib import Path
import math

import bpy


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source" / "Production_SauceTube_S1_empty.blend"
OUTPUT_BLEND = HERE / "Production_SauceTube_S1.blend"
OUTPUT_GLB = HERE / "Production_SauceTube_S1.glb"
ASSET = "Production_SauceTube_S1"


def make_sauce_material():
    material = bpy.data.materials.get(f"{ASSET}_Mayonnaise")
    if material is None:
        material = bpy.data.materials.new(f"{ASSET}_Mayonnaise")
    material.diffuse_color = (1.0, 0.875, 0.43, 1.0)
    material.use_nodes = True
    principled = next(
        node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"
    )
    principled.inputs["Base Color"].default_value = (1.0, 0.875, 0.43, 1.0)
    principled.inputs["Roughness"].default_value = 0.32
    return material


def build_fill():
    old = bpy.data.objects.get("SauceFill")
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)

    # Elliptical rings follow the interior of the soft tube.  Mesh Z starts at
    # zero and the object origin sits at the bottle base, so scaling local Z in
    # Blender (local Y after glTF import) lowers only the sauce surface.
    rings = (
        (0.0, 0.205, 0.112),
        (0.18, 0.218, 0.120),
        (0.58, 0.210, 0.115),
        (0.76, 0.185, 0.104),
        (0.84, 0.145, 0.087),
    )
    segments = 20
    vertices = []
    for z, radius_x, radius_y in rings:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((
                math.cos(angle) * radius_x,
                math.sin(angle) * radius_y,
                z,
            ))
    faces = []
    faces.append(tuple(reversed(range(segments))))
    for ring in range(len(rings) - 1):
        lower = ring * segments
        upper = (ring + 1) * segments
        for index in range(segments):
            nxt = (index + 1) % segments
            faces.append((lower + index, lower + nxt, upper + nxt, upper + index))
    top = (len(rings) - 1) * segments
    faces.append(tuple(top + index for index in range(segments)))

    mesh = bpy.data.meshes.new(f"{ASSET}_SauceFill_Geo")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(make_sauce_material())
    mesh.update()
    fill = bpy.data.objects.new("SauceFill", mesh)
    fill.location.z = 0.04
    bpy.context.collection.objects.link(fill)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return fill


def validate(bottle, fill):
    if len([obj for obj in bpy.context.scene.objects if obj.type == "MESH"]) != 2:
        raise RuntimeError("Expected exactly the bottle shell and SauceFill meshes")
    if bottle.dimensions.z < 1.19 or bottle.dimensions.z > 1.21:
        raise RuntimeError(f"Unexpected bottle height: {bottle.dimensions.z}")
    if min(vertex.co.z for vertex in fill.data.vertices) < -1e-6:
        raise RuntimeError("SauceFill is not anchored at its base")
    if max(vertex.co.z for vertex in fill.data.vertices) > 0.85:
        raise RuntimeError("SauceFill protrudes into the cap")


def main():
    if not SOURCE.exists():
        raise RuntimeError(f"Missing supplied source bottle: {SOURCE}")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one source mesh; found {len(meshes)}")
    bottle = meshes[0]
    bottle.name = "SauceTube_Bottle"
    bottle.data.name = f"{ASSET}_Bottle_Geo"
    bpy.context.view_layer.objects.active = bottle
    bottle.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for material in bottle.data.materials:
        if material is not None and not material.name.startswith(f"{ASSET}_"):
            material.name = f"{ASSET}_{material.name}"

    fill = build_fill()
    bpy.context.scene["asset_name"] = ASSET
    bpy.context.scene["forward_axis"] = "+Z (upright asset); rotate -90 degrees X in Godot"
    bpy.context.scene["fill_node"] = "SauceFill"
    bpy.context.scene["fill_axis_godot"] = "+Y"
    bpy.context.scene["muzzle_height"] = 1.2
    validate(bottle, fill)

    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_materials="EXPORT",
        export_extras=True,
    )
    print("SAUCE_TUBE_BUILD_OK", OUTPUT_BLEND, OUTPUT_GLB)


if __name__ == "__main__":
    main()
