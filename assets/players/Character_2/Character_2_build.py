"""Build three weapon-hold gameplay actions for Sauce It Character 2.

Motion notes (observed reference + original adaptation):
- Valve's official Team Fortress 2 Heavy material establishes a broad, weighty
  character carrying a very heavy front-held weapon and moving more slowly while
  it is readied.  I used the planted stance, elbows-out support silhouette, and
  visible burden as mechanical reference, not its proprietary animation data.
  Sources consulted 2026-10-05:
  https://www.teamfortress.com/post.php?id=1740
  https://wiki.teamfortress.com/wiki/Minigun
- Original Sauce It adaptation: in-place cycles, bigger vertical bounce, uneven
  shoulder counter-motion, an imaginary two-hand sauce-tank grip, and a comic
  sideways collapse while the grip remains readable. No weapon mesh is created.

Run with Blender 5.2:
  blender --background --factory-startup Character_2.blend --python Character_2_build.py
"""

import bpy
import math
from mathutils import Matrix, Vector
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
OUTPUT_BLEND = BASE_DIR / "Character_2.blend"
RUNTIME_GLTF = BASE_DIR / "Character_2.glb"
FPS = 24

ACTION_SPECS = {
    "Character_2_Walk_WeaponHold": (1, 25, True, 24),
    "Character_2_Run_WeaponHold": (1, 17, True, 16),
    "Character_2_Death_WeaponHold": (1, 36, False, 36),
}

B = {
    "root": "Character_2_Root",
    "hips": "mixamorig:Hips",
    "spine": "mixamorig:Spine",
    "spine1": "mixamorig:Spine1",
    "spine2": "mixamorig:Spine2",
    "neck": "mixamorig:Neck",
    "head": "mixamorig:Head",
    "shoulder_l": "mixamorig:LeftShoulder",
    "upperarm_l": "mixamorig:LeftArm",
    "forearm_l": "mixamorig:LeftForeArm",
    "hand_l": "mixamorig:LeftHand",
    "shoulder_r": "mixamorig:RightShoulder",
    "upperarm_r": "mixamorig:RightArm",
    "forearm_r": "mixamorig:RightForeArm",
    "hand_r": "mixamorig:RightHand",
    "thigh_l": "mixamorig:LeftUpLeg",
    "shin_l": "mixamorig:LeftLeg",
    "foot_l": "mixamorig:LeftFoot",
    "toe_l": "mixamorig:LeftToeBase",
    "thigh_r": "mixamorig:RightUpLeg",
    "shin_r": "mixamorig:RightLeg",
    "foot_r": "mixamorig:RightFoot",
    "toe_r": "mixamorig:RightToeBase",
}

CONTROLLED = tuple(dict.fromkeys(B.values()))


def armature_object():
    rigs = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
    if len(rigs) != 1:
        raise RuntimeError(f"Expected exactly one armature; found {len(rigs)}")
    return rigs[0]


arm = armature_object()
scene = bpy.context.scene
scene.render.fps = FPS
scene.render.fps_base = 1.0

# Normalize the imported Mixamo-style transform while preserving visible size.
bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
if any(abs(v - 1.0) > 1e-5 for v in arm.scale):
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Stable, non-deforming root for engine placement; hips remain the motion body.
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
if B["root"] not in arm.data.edit_bones:
    root = arm.data.edit_bones.new(B["root"])
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 0.5)
    root.use_deform = False
else:
    root = arm.data.edit_bones[B["root"]]
hips_edit = arm.data.edit_bones[B["hips"]]
hips_edit.parent = root
hips_edit.use_connect = False
bpy.ops.object.mode_set(mode="POSE")

# Stable project-specific naming helps this file stay independent if imported.
arm.name = "Character_2_Rig"
arm.data.name = "Character_2_Armature"
meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
if len(meshes) != 1:
    raise RuntimeError(f"Expected exactly one character mesh; found {len(meshes)}")
mesh = meshes[0]
mesh.name = "Character_2_Mesh"
mesh.data.name = "Character_2_Geo"
for index, mat in enumerate(mesh.data.materials):
    if mat and not mat.name.startswith("Character_2_"):
        mat.name = f"Character_2_Material_{index + 1:02d}"


def reset_pose():
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def point_bone(name, direction):
    """Swing a bone in armature space toward direction while retaining roll."""
    pb = arm.pose.bones[name]
    desired = Vector(direction).normalized()
    current = (pb.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
    swing = current.rotation_difference(desired)
    origin = pb.matrix.translation.copy()
    rotated = swing.to_matrix().to_4x4() @ pb.matrix.to_3x3().to_4x4()
    pb.matrix = Matrix.Translation(origin) @ rotated
    bpy.context.view_layer.update()


def rotate_global(name, axis, degrees):
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    pivot = pb.matrix.translation.copy()
    rot = Matrix.Rotation(math.radians(degrees), 4, Vector(axis))
    pb.matrix = Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def translate_global(name, offset):
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    pb.matrix = Matrix.Translation(Vector(offset)) @ pb.matrix
    bpy.context.view_layer.update()


def torso_pose(side, lean, nod=0.0):
    point_bone(B["spine"], (side * 0.35, -lean, 1.0))
    point_bone(B["spine1"], (-side * 0.15, -lean * 0.75, 1.0))
    point_bone(B["spine2"], (side * 0.10, -lean * 0.55, 1.0))
    point_bone(B["neck"], (-side * 0.08, 0.03 + nod, 1.0))
    point_bone(B["head"], (side * 0.04, 0.05 + nod, 1.0))


def weapon_hold(side=0.0, lift=0.0, flare=0.0):
    """Two-hand invisible sauce-tank grip centered in front of the torso."""
    point_bone(B["shoulder_l"], (1.0, -0.16 - side * 0.05, -0.04 + lift))
    point_bone(B["shoulder_r"], (-1.0, -0.16 - side * 0.05, -0.04 + lift))
    point_bone(B["upperarm_l"], (0.38 + flare, -0.86, -0.34 + lift))
    point_bone(B["upperarm_r"], (-0.38 - flare, -0.86, -0.34 + lift))
    point_bone(B["forearm_l"], (-0.58, -0.78, 0.02 + lift * 0.6))
    point_bone(B["forearm_r"], (0.58, -0.78, 0.02 + lift * 0.6))
    point_bone(B["hand_l"], (-0.10, -1.0, -0.02))
    point_bone(B["hand_r"], (0.10, -1.0, -0.02))


def legs_pose(left):
    """Apply explicit world-space limb directions for one keyed gait pose."""
    point_bone(B["thigh_l"], left[0])
    point_bone(B["shin_l"], left[1])
    point_bone(B["foot_l"], left[2])
    point_bone(B["toe_l"], left[3])
    right = left[4:]
    point_bone(B["thigh_r"], right[0])
    point_bone(B["shin_r"], right[1])
    point_bone(B["foot_r"], right[2])
    point_bone(B["toe_r"], right[3])


def key_pose(action, frame):
    for name in CONTROLLED:
        pb = arm.pose.bones[name]
        group = name
        pb.keyframe_insert("location", frame=frame, group=group)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=group)
        pb.keyframe_insert("scale", frame=frame, group=group)


def new_action(name):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action
    action["fps"] = FPS
    start, end, loop, playback_end = ACTION_SPECS[name]
    action["loop"] = loop
    action["root_motion"] = False
    action["playback_start"] = start
    action["playback_end"] = playback_end
    action["weapon_mesh_included"] = False
    action["pose_intent"] = "Two-hand front-held sauce tank/sprayer grip"
    action.use_frame_range = True
    action.frame_start = start
    action.frame_end = end
    return action


def pose_walk(index):
    # Contact L, passing, contact R, passing. Final key duplicates index 0.
    data = [
        dict(z=0.00, side=0.10, lean=0.12,
             limbs=((0.05, -0.48, -1.0), (0.00, 0.28, -1.0), (0.00, -1.0, -0.05), (0.00, -1.0, 0.0),
                    (-0.05, 0.42, -1.0), (0.00, -0.18, -0.82), (0.00, -0.82, -0.20), (0.00, -1.0, 0.05))),
        dict(z=0.22, side=-0.03, lean=0.16,
             limbs=((0.03, -0.05, -1.0), (0.00, 0.02, -1.0), (0.00, -1.0, -0.06), (0.00, -1.0, 0.0),
                    (-0.04, -0.18, -0.74), (0.00, -0.62, -0.58), (0.00, -0.90, -0.10), (0.00, -1.0, 0.06))),
        dict(z=0.00, side=-0.10, lean=0.12,
             limbs=((0.05, 0.42, -1.0), (0.00, -0.18, -0.82), (0.00, -0.82, -0.20), (0.00, -1.0, 0.05),
                    (-0.05, -0.48, -1.0), (0.00, 0.28, -1.0), (0.00, -1.0, -0.05), (0.00, -1.0, 0.0))),
        dict(z=0.22, side=0.03, lean=0.16,
             limbs=((0.04, -0.18, -0.74), (0.00, -0.62, -0.58), (0.00, -0.90, -0.10), (0.00, -1.0, 0.06),
                    (-0.03, -0.05, -1.0), (0.00, 0.02, -1.0), (0.00, -1.0, -0.06), (0.00, -1.0, 0.0))),
    ][index]
    reset_pose()
    rotate_global(B["hips"], (0, 1, 0), data["side"] * 10.0)
    translate_global(B["hips"], (0.0, 0.0, data["z"]))
    torso_pose(data["side"], data["lean"])
    legs_pose(data["limbs"])
    weapon_hold(side=data["side"], lift=data["z"] * 0.025)


def pose_run(index):
    data = [
        dict(z=0.05, side=0.13,
             limbs=((0.07, -0.72, -0.82), (0.00, 0.30, -0.96), (0.00, -1.0, -0.02), (0.00, -1.0, 0.0),
                    (-0.06, 0.62, -0.78), (0.00, -0.38, -0.64), (0.00, -0.82, -0.20), (0.00, -1.0, 0.10))),
        dict(z=0.52, side=-0.04,
             limbs=((0.05, 0.10, -0.80), (0.00, -0.72, -0.48), (0.00, -0.86, -0.18), (0.00, -1.0, 0.10),
                    (-0.05, -0.12, -0.78), (0.00, -0.75, -0.45), (0.00, -0.88, -0.15), (0.00, -1.0, 0.10))),
        dict(z=0.05, side=-0.13,
             limbs=((0.06, 0.62, -0.78), (0.00, -0.38, -0.64), (0.00, -0.82, -0.20), (0.00, -1.0, 0.10),
                    (-0.07, -0.72, -0.82), (0.00, 0.30, -0.96), (0.00, -1.0, -0.02), (0.00, -1.0, 0.0))),
        dict(z=0.52, side=0.04,
             limbs=((0.05, -0.12, -0.78), (0.00, -0.75, -0.45), (0.00, -0.88, -0.15), (0.00, -1.0, 0.10),
                    (-0.05, 0.10, -0.80), (0.00, -0.72, -0.48), (0.00, -0.86, -0.18), (0.00, -1.0, 0.10))),
    ][index]
    reset_pose()
    rotate_global(B["hips"], (0, 1, 0), data["side"] * 13.0)
    translate_global(B["hips"], (0.0, 0.0, data["z"]))
    torso_pose(data["side"], 0.28, nod=-0.03)
    legs_pose(data["limbs"])
    weapon_hold(side=data["side"], lift=0.035 + data["z"] * 0.02, flare=0.05)


def pose_death(stage):
    reset_pose()
    hips = arm.pose.bones[B["hips"]]
    if stage == 0:  # ready
        torso_pose(0.0, 0.14)
        legs_pose(((0.03, -0.12, -1.0), (0.00, 0.04, -1.0), (0.00, -1.0, -0.04), (0.00, -1.0, 0.0),
                   (-0.03, 0.12, -1.0), (0.00, -0.04, -1.0), (0.00, -1.0, -0.04), (0.00, -1.0, 0.0)))
        weapon_hold()
    elif stage == 1:  # impact recoil, tank yanked upward
        rotate_global(B["hips"], (1, 0, 0), -11.0)
        translate_global(B["hips"], (0.0, 0.26, 0.24))
        torso_pose(0.10, -0.22, nod=0.10)
        legs_pose(((0.05, -0.18, -1.0), (0.00, 0.12, -1.0), (0.00, -1.0, -0.03), (0.00, -1.0, 0.0),
                   (-0.04, 0.12, -1.0), (0.00, -0.10, -1.0), (0.00, -1.0, -0.03), (0.00, -1.0, 0.0)))
        weapon_hold(lift=0.30, flare=0.16)
    elif stage == 2:  # knees buckle, balance tips left
        rotate_global(B["hips"], (0, 1, 0), 24.0)
        rotate_global(B["hips"], (1, 0, 0), 12.0)
        translate_global(B["hips"], (0.30, 0.05, 0.39))
        torso_pose(0.36, 0.34, nod=-0.05)
        legs_pose(((0.20, -0.26, -0.72), (0.08, -0.62, -0.52), (0.05, -0.94, -0.12), (0.00, -1.0, 0.08),
                   (-0.22, 0.10, -0.78), (-0.08, -0.58, -0.58), (-0.05, -0.92, -0.14), (0.00, -1.0, 0.08)))
        weapon_hold(side=0.30, lift=-0.05, flare=0.22)
    elif stage == 3:  # committed fall, still clutching imaginary tank
        rotate_global(B["hips"], (0, 1, 0), 62.0)
        rotate_global(B["hips"], (0, 0, 1), -10.0)
        translate_global(B["hips"], (1.05, -0.05, 1.04))
        point_bone(B["upperarm_l"], (0.30, -0.80, -0.30))
        point_bone(B["upperarm_r"], (-0.20, -0.82, -0.25))
        point_bone(B["forearm_l"], (-0.50, -0.82, -0.10))
        point_bone(B["forearm_r"], (0.50, -0.82, -0.10))
        point_bone(B["hand_l"], (-0.08, -1.0, -0.10))
        point_bone(B["hand_r"], (0.08, -1.0, -0.10))
        point_bone(B["thigh_l"], (0.30, -0.25, -0.78))
        point_bone(B["shin_l"], (0.12, -0.62, -0.62))
        point_bone(B["thigh_r"], (-0.20, 0.18, -0.82))
        point_bone(B["shin_r"], (-0.08, -0.55, -0.70))
    else:  # grounded held end pose
        rotate_global(B["hips"], (0, 1, 0), 88.0)
        rotate_global(B["hips"], (0, 0, 1), -13.0)
        translate_global(B["hips"], (1.32, -0.12, 1.40))
        point_bone(B["upperarm_l"], (0.15, -0.78, -0.44))
        point_bone(B["upperarm_r"], (-0.12, -0.80, -0.40))
        point_bone(B["forearm_l"], (-0.46, -0.82, -0.18))
        point_bone(B["forearm_r"], (0.46, -0.82, -0.18))
        point_bone(B["hand_l"], (-0.08, -1.0, -0.10))
        point_bone(B["hand_r"], (0.08, -1.0, -0.10))
        point_bone(B["thigh_l"], (0.30, -0.18, -0.78))
        point_bone(B["shin_l"], (0.12, -0.56, -0.70))
        point_bone(B["foot_l"], (0.08, -0.88, -0.22))
        point_bone(B["thigh_r"], (-0.22, 0.12, -0.82))
        point_bone(B["shin_r"], (-0.10, -0.52, -0.74))
        point_bone(B["foot_r"], (-0.05, -0.90, -0.18))


walk = new_action("Character_2_Walk_WeaponHold")
for frame, pose_index in ((1, 0), (7, 1), (13, 2), (19, 3), (25, 0)):
    scene.frame_set(frame)
    pose_walk(pose_index)
    key_pose(walk, frame)
for label, frame in (("Contact_L", 1), ("Passing_L", 7), ("Contact_R", 13), ("Passing_R", 19)):
    walk.pose_markers.new(label).frame = frame

run = new_action("Character_2_Run_WeaponHold")
for frame, pose_index in ((1, 0), (5, 1), (9, 2), (13, 3), (17, 0)):
    scene.frame_set(frame)
    pose_run(pose_index)
    key_pose(run, frame)
for label, frame in (("Contact_L", 1), ("Air_L", 5), ("Contact_R", 9), ("Air_R", 13)):
    run.pose_markers.new(label).frame = frame

death = new_action("Character_2_Death_WeaponHold")
for frame, stage in ((1, 0), (6, 1), (13, 2), (21, 3), (30, 4), (36, 4)):
    scene.frame_set(frame)
    pose_death(stage)
    key_pose(death, frame)
for label, frame in (("Ready", 1), ("Impact", 6), ("Buckle", 13), ("Ground", 30), ("Held_End", 36)):
    death.pose_markers.new(label).frame = frame

# File/rig metadata for deterministic integration.
arm["asset_name"] = "Character_2"
arm["forward_axis"] = "-Y"
arm["up_axis"] = "+Z"
arm["animation_fps"] = FPS
arm["root_motion"] = False
arm["weapon_mesh_included"] = False
arm["weapon_pose"] = "Two-hand front-held sauce tank/sprayer"
arm["actions"] = list(ACTION_SPECS.keys())
arm["motion_reference"] = "TF2 Heavy weight/support principles; original Sauce It motion"
scene["Character_2_forward_axis"] = "-Y"
scene["Character_2_root_motion"] = False
scene["Character_2_actions"] = list(ACTION_SPECS.keys())

# Predictable inspection state: walk action on its first frame.
arm.animation_data.action = walk
scene.frame_start = 1
scene.frame_end = 25
scene.frame_set(1)
for obj in bpy.context.selected_objects:
    obj.select_set(False)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")

bpy.context.preferences.filepaths.file_preview_type = "NONE"
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)
bpy.ops.export_scene.gltf(
    filepath=str(RUNTIME_GLTF),
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_anim_slide_to_zero=True,
    export_materials="EXPORT",
    export_extras=True,
)
print("SAVED", OUTPUT_BLEND)
print("EXPORTED", RUNTIME_GLTF)
print("ACTIONS", [(a.name, tuple(round(v, 3) for v in a.frame_range), a.use_fake_user) for a in bpy.data.actions])
