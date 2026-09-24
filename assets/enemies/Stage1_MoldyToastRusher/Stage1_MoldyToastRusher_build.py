"""Build the Sauce It Stage 1 Moldy Toast Rusher and export it for Godot.

The model is intentionally assembled from rigid low-poly pieces driven by one
armature.  Every mesh keeps body-space vertex coordinates so the game's shared
cylindrical sauce mask can be applied consistently across all pieces.
"""

from pathlib import Path
import math
import sys

import bpy
from mathutils import Vector


ASSET = "Stage1_MoldyToastRusher"
HERE = Path(__file__).resolve().parent
BLEND_PATH = HERE / f"{ASSET}.blend"
GLB_PATH = HERE / f"{ASSET}.glb"
FPS = 24


def clean_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures,
                   bpy.data.materials, bpy.data.actions):
        for block in list(blocks):
            blocks.remove(block)


def material(name, colour, roughness=0.82, metallic=0.0):
    mat = bpy.data.materials.new(f"{ASSET}_{name}")
    mat.diffuse_color = colour
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Roughness"].default_value = roughness
    metallic_input = bsdf.inputs.get("Metallic IOR Level") or bsdf.inputs.get("Metallic")
    if metallic_input is not None:
        metallic_input.default_value = metallic
    return mat


def bake_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def bevel_box(name, location, size, mat, bevel=0.025, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = f"{ASSET}_{name}"
    obj.scale = Vector(size) * 0.5
    bake_transform(obj)
    mod = obj.modifiers.new("Chunky bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 1
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def blob(name, location, scale, mat, segments=8, rings=5, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = f"{ASSET}_{name}"
    obj.scale = scale
    bake_transform(obj)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def extruded(name, points, depth, mat, y=0.0, bevel=0.018):
    count = len(points)
    vertices = [(x, y - depth * 0.5, z) for x, z in points]
    vertices += [(x, y + depth * 0.5, z) for x, z in points]
    faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, count + nxt, count + index))
    mesh = bpy.data.meshes.new(f"{ASSET}_{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(f"{ASSET}_{name}", mesh)
    bpy.context.collection.objects.link(obj)
    mod = obj.modifiers.new("Crisp rounded edge", "BEVEL")
    mod.width = bevel
    mod.segments = 1
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)
    return obj


def create_rig():
    data = bpy.data.armatures.new(f"{ASSET}_ArmatureData")
    arm = bpy.data.objects.new(f"{ASSET}_Rig", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specs = {
        "root": ((0, 0, 0), (0, 0, 0.18), None, False),
        "body": ((0, 0, 0.48), (0, 0, 0.82), "root", True),
        "arm.L": ((-0.36, 0, 0.55), (-0.54, -0.04, 0.43), "body", True),
        "arm.R": ((0.36, 0, 0.55), (0.54, -0.04, 0.43), "body", True),
        "foot.L": ((-0.19, 0, 0.14), (-0.19, -0.18, 0.14), "root", True),
        "foot.R": ((0.19, 0, 0.14), (0.19, -0.18, 0.14), "root", True),
        "jaw": ((0, -0.10, 0.47), (0, -0.18, 0.34), "body", True),
    }
    made = {}
    for name, (head, tail, parent, deform) in specs.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = deform
        if parent:
            bone.parent = made[parent]
        made[name] = bone
    bpy.ops.object.mode_set(mode="POSE")
    for bone in arm.pose.bones:
        bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    arm["forward_axis"] = "-Y"
    arm["up_axis"] = "+Z"
    arm["animation_fps"] = FPS
    arm["actions"] = "Run,Ram,Hit,Death"
    arm["root_motion"] = "in_place"
    arm["gameplay_role"] = "fast_low_health_contact_rusher"
    return arm


def parent_to_bone(obj, arm, bone):
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    obj.matrix_world = world


def create_character(arm):
    crust = material("BurntCrust", (0.18, 0.045, 0.008, 1.0), 0.92)
    bread = material("MoldyBread", (0.34, 0.44, 0.10, 1.0), 0.94)
    mold = material("MoldDark", (0.035, 0.12, 0.015, 1.0), 0.98)
    cheese = material("RottenCheese", (0.60, 0.48, 0.045, 1.0), 0.90)
    eye = material("Eyes", (0.015, 0.025, 0.008, 1.0), 0.65)
    tooth = material("Teeth", (0.72, 0.70, 0.44, 1.0), 0.80)
    shoe = material("Shoes", (0.11, 0.055, 0.018, 1.0), 0.88)

    outer = [(-0.42, 0.18), (-0.46, 0.50), (-0.43, 0.91),
             (-0.28, 1.08), (-0.07, 1.04), (0.13, 1.10),
             (0.34, 1.04), (0.45, 0.88), (0.46, 0.45), (0.40, 0.18)]
    inner = [(x * 0.86, 0.22 + (z - 0.18) * 0.88) for x, z in outer]
    parts = []
    parts.append((extruded("Crust", outer, 0.18, crust, y=0.02, bevel=0.028), "body"))
    parts.append((extruded("Crumb", inner, 0.205, bread, y=-0.005, bevel=0.022), "body"))

    # Chunky, asymmetrical mold islands survive the gameplay camera distance.
    for index, (x, z, sx, sz) in enumerate((
            (-0.25, 0.88, 0.09, 0.12), (0.23, 0.94, 0.11, 0.08),
            (-0.31, 0.49, 0.07, 0.10), (0.30, 0.56, 0.08, 0.12),
            (0.04, 0.73, 0.06, 0.075))):
        parts.append((blob(f"Mold_{index:02d}", (x, -0.116, z),
                           (sx, 0.018, sz), mold, 7, 4), "body"))

    # Angry recessed eyes and a loose jaw make the attack pose readable.
    parts.append((blob("Eye_L", (-0.19, -0.128, 0.76), (0.095, 0.018, 0.075), eye), "body"))
    parts.append((blob("Eye_R", (0.19, -0.128, 0.76), (0.095, 0.018, 0.075), eye), "body"))
    jaw = bevel_box("Jaw", (0, -0.13, 0.40), (0.34, 0.09, 0.13), crust, 0.018)
    parts.append((jaw, "jaw"))
    for index, x in enumerate((-0.105, 0.0, 0.105)):
        parts.append((bevel_box(f"Tooth_{index}", (x, -0.185, 0.44),
                                (0.055, 0.035, 0.085), tooth, 0.008,
                                rotation=(0, 0, 0.08 * (index - 1))), "jaw"))

    # Ragged filling at the sides resembles the supplied moldy sandwich while
    # giving the rusher a sharper, faster silhouette.
    for side in (-1, 1):
        points = [(0.36 * side, 0.33), (0.52 * side, 0.39),
                  (0.39 * side, 0.46), (0.53 * side, 0.55),
                  (0.38 * side, 0.64), (0.48 * side, 0.72)]
        points += [(0.34 * side, 0.69)]
        parts.append((extruded(f"Cheese_{'L' if side < 0 else 'R'}", points,
                               0.08, cheese, y=0.015, bevel=0.01), "body"))

    for side, sign in (("L", -1), ("R", 1)):
        arm_piece = bevel_box(f"Arm_{side}", (0.47 * sign, -0.02, 0.50),
                              (0.22, 0.13, 0.15), crust, 0.04,
                              rotation=(0, -0.35 * sign, 0))
        fist = blob(f"Fist_{side}", (0.58 * sign, -0.07, 0.40),
                    (0.10, 0.09, 0.11), mold, 8, 5)
        foot = blob(f"Foot_{side}", (0.19 * sign, -0.10, 0.12),
                    (0.18, 0.18, 0.12), shoe, 8, 5,
                    rotation=(0, 0, 0.06 * sign))
        parts.extend(((arm_piece, f"arm.{side}"), (fist, f"arm.{side}"),
                      (foot, f"foot.{side}")))

    for obj, bone in parts:
        obj["sauce_mask_space"] = "shared_body_space"
        parent_to_bone(obj, arm, bone)
    return [obj for obj, _ in parts]


def reset_pose(arm):
    for bone in arm.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_euler = (0, 0, 0)
        bone.scale = (1, 1, 1)


def action_curves(action):
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(list(bag.fcurves))
    return curves


def key_pose(arm, frame, pose):
    for name in ("root", "body", "arm.L", "arm.R", "foot.L", "foot.R", "jaw"):
        bone = arm.pose.bones[name]
        values = pose.get(name, {})
        bone.location = values.get("loc", (0, 0, 0))
        bone.rotation_euler = values.get("rot", (0, 0, 0))
        bone.scale = values.get("scale", (1, 1, 1))
        bone.keyframe_insert("location", frame=frame, group=name)
        bone.keyframe_insert("rotation_euler", frame=frame, group=name)
        bone.keyframe_insert("scale", frame=frame, group=name)


def make_action(arm, name, frames, loop=False, playback_end=None):
    action = bpy.data.actions.new(f"{ASSET}_{name}")
    action.use_fake_user = True
    action["display_name"] = name
    action["loop"] = loop
    action["fps"] = FPS
    action["frame_start"] = min(frames)
    action["frame_end"] = max(frames)
    action["playback_end"] = playback_end or max(frames)
    action["root_motion"] = False
    arm.animation_data.action = action
    reset_pose(arm)
    for frame, pose in frames.items():
        key_pose(arm, frame, pose)
    for curve in action_curves(action):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
    return action


def animate(arm):
    run = make_action(arm, "Run", {
        1: {"body": {"loc": (0, -0.03, -0.03), "rot": (0.18, 0, -0.07), "scale": (1.05, 1, 0.94)},
            "arm.L": {"rot": (-0.5, -0.8, -0.2)}, "arm.R": {"rot": (0.5, 0.8, 0.2)},
            "foot.L": {"loc": (0, -0.09, 0)}, "foot.R": {"loc": (0, 0.08, 0.09)}, "jaw": {"rot": (-0.16, 0, 0)}},
        4: {"body": {"loc": (0.025, 0, 0.08), "rot": (0.10, 0.06, 0.05), "scale": (0.97, 1, 1.06)},
            "arm.L": {"rot": (0.8, -1.0, -0.3)}, "arm.R": {"rot": (-0.8, 1.0, 0.3)},
            "foot.L": {"loc": (0, 0.06, 0.10)}, "foot.R": {"loc": (0, -0.07, 0)}, "jaw": {"rot": (0.10, 0, 0)}},
        7: {"body": {"loc": (0, -0.04, -0.04), "rot": (0.19, 0, 0.08), "scale": (1.06, 1, 0.93)},
            "arm.L": {"rot": (0.5, -0.8, -0.2)}, "arm.R": {"rot": (-0.5, 0.8, 0.2)},
            "foot.L": {"loc": (0, 0.08, 0.09)}, "foot.R": {"loc": (0, -0.09, 0)}, "jaw": {"rot": (-0.18, 0, 0)}},
        10: {"body": {"loc": (-0.025, 0, 0.08), "rot": (0.10, -0.06, -0.05), "scale": (0.97, 1, 1.06)},
             "arm.L": {"rot": (-0.8, -1.0, -0.3)}, "arm.R": {"rot": (0.8, 1.0, 0.3)},
             "foot.L": {"loc": (0, -0.07, 0)}, "foot.R": {"loc": (0, 0.06, 0.10)}, "jaw": {"rot": (0.10, 0, 0)}},
        13: {"body": {"loc": (0, -0.03, -0.03), "rot": (0.18, 0, -0.07), "scale": (1.05, 1, 0.94)},
             "arm.L": {"rot": (-0.5, -0.8, -0.2)}, "arm.R": {"rot": (0.5, 0.8, 0.2)},
             "foot.L": {"loc": (0, -0.09, 0)}, "foot.R": {"loc": (0, 0.08, 0.09)}, "jaw": {"rot": (-0.16, 0, 0)}}
    }, True, playback_end=12)

    ram = make_action(arm, "Ram", {
        1: {"body": {"loc": (0, 0.06, -0.08), "rot": (-0.18, 0, 0), "scale": (1.12, 1, 0.82)},
            "arm.L": {"rot": (0.2, -1.25, -0.4)}, "arm.R": {"rot": (-0.2, 1.25, 0.4)}, "jaw": {"rot": (0.22, 0, 0)}},
        5: {"body": {"loc": (0, -0.16, 0.01), "rot": (0.48, 0, 0), "scale": (0.91, 1.08, 1.12)},
            "arm.L": {"rot": (-1.2, -0.45, -0.1)}, "arm.R": {"rot": (1.2, 0.45, 0.1)}, "jaw": {"rot": (-0.38, 0, 0)}},
        8: {"body": {"loc": (0, -0.04, -0.03), "rot": (0.26, 0, 0), "scale": (1.08, 1, 0.90)}, "jaw": {"rot": (-0.12, 0, 0)}},
        13: {}
    })
    hit = make_action(arm, "Hit", {
        1: {}, 3: {"body": {"loc": (0, 0.10, -0.12), "rot": (-0.32, 0, 0.18), "scale": (1.12, 1, 0.82)},
                   "arm.L": {"rot": (0.8, -0.4, -0.9)}, "arm.R": {"rot": (-0.8, 0.4, 0.9)}, "jaw": {"rot": (0.28, 0, 0)}},
        8: {}
    })
    death = make_action(arm, "Death", {
        1: {}, 5: {"body": {"loc": (0, 0.04, -0.08), "rot": (-0.25, 0, -0.20)},
                    "arm.L": {"rot": (1.3, -0.4, -0.7)}, "arm.R": {"rot": (-1.1, 0.5, 0.8)}},
        12: {"body": {"loc": (0, 0.11, -0.22), "rot": (-0.75, 0, 0.35), "scale": (1.15, 1, 0.78)},
             "arm.L": {"rot": (1.7, -0.2, -1.1)}, "arm.R": {"rot": (-1.5, 0.3, 1.0)}, "jaw": {"rot": (0.42, 0, 0)}},
        20: {"body": {"loc": (0, 0.14, -0.28), "rot": (-1.12, 0, 0.52), "scale": (1.22, 1, 0.68)},
             "arm.L": {"rot": (1.9, 0, -1.2)}, "arm.R": {"rot": (-1.7, 0, 1.1)}, "jaw": {"rot": (0.48, 0, 0)}}
    })
    return run, ram, hit, death


def validate(arm, meshes):
    errors = []
    expected_bones = {"root", "body", "arm.L", "arm.R", "foot.L", "foot.R", "jaw"}
    if not expected_bones.issubset(set(arm.data.bones.keys())):
        errors.append("missing required bones")
    expected_actions = {f"{ASSET}_{name}" for name in ("Run", "Ram", "Hit", "Death")}
    found = set(bpy.data.actions.keys())
    if not expected_actions.issubset(found):
        errors.append(f"missing actions: {sorted(expected_actions - found)}")
    for action_name in expected_actions & found:
        action = bpy.data.actions[action_name]
        arm.animation_data.action = action
        for frame in range(int(action["frame_start"]), int(action["frame_end"]) + 1):
            bpy.context.scene.frame_set(frame)
            for bone in arm.pose.bones:
                if not all(math.isfinite(value) for row in bone.matrix for value in row):
                    errors.append(f"non-finite pose in {action_name} at {frame}")
    arm.animation_data.action = None
    reset_pose(arm)
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    mins = Vector(tuple(min(value[i] for value in corners) for i in range(3)))
    maxs = Vector(tuple(max(value[i] for value in corners) for i in range(3)))
    dimensions = maxs - mins
    polygons = sum(len(obj.data.polygons) for obj in meshes)
    print(f"REST_BOUNDS x={dimensions.x:.3f} y={dimensions.y:.3f} z={dimensions.z:.3f} min_z={mins.z:.3f}")
    print(f"LOW_POLY objects={len(meshes)} polygons={polygons}")
    if mins.z < -0.015 or mins.z > 0.03:
        errors.append(f"ground contact is {mins.z:.3f} m")
    if polygons > 1400:
        errors.append(f"polygon budget exceeded: {polygons}")
    run = bpy.data.actions.get(f"{ASSET}_Run")
    arm.animation_data.action = run
    bpy.context.scene.frame_set(1)
    start = {bone.name: bone.matrix.copy() for bone in arm.pose.bones}
    bpy.context.scene.frame_set(13)
    for bone in arm.pose.bones:
        if any(abs(start[bone.name][r][c] - bone.matrix[r][c]) > 1e-5
               for r in range(4) for c in range(4)):
            errors.append(f"run loop seam mismatch on {bone.name}")
    if errors:
        print("VALIDATION_FAILED")
        for error in errors:
            print(" -", error)
        raise RuntimeError("; ".join(errors))
    print("VALIDATION_OK")


def export_glb(arm, meshes):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=False, export_yup=True, export_materials="EXPORT",
        export_animations=True, export_nla_strips=True,
    )
    print(f"EXPORTED {GLB_PATH} ({GLB_PATH.stat().st_size} bytes)")


def setup_preview(arm, action):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = 12
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    arm.animation_data.action = action
    scene.frame_set(1)
    scene["asset_name"] = ASSET
    scene["forward_axis"] = "-Y"
    scene["gameplay_actions"] = "Run,Ram,Hit,Death"
    scene["looping_actions"] = "Run"


def build():
    clean_scene()
    arm = create_rig()
    meshes = create_character(arm)
    arm.animation_data_create()
    actions = animate(arm)
    setup_preview(arm, actions[0])
    validate(arm, meshes)
    setup_preview(arm, actions[0])
    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"SAVED {BLEND_PATH}")
    export_glb(arm, meshes)


def validate_saved():
    arm = bpy.data.objects.get(f"{ASSET}_Rig")
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if arm is None:
        raise RuntimeError("saved file has no rig")
    validate(arm, meshes)
    print("REOPEN_VALIDATION_OK")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    validate_saved() if "--validate" in args else build()
