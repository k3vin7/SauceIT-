"""Add weapon-carry locomotion and death actions to Character_4.

Character_4 is treated as an independent character asset (project character slot 4,
zero-based runtime index 3).
No weapon mesh is included. A non-deforming Weapon_Socket bone is supplied on the
right hand for a future sauce-container attachment.

Motion references consulted before animation:
- Fall Guys official PlayStation gameplay/launch trailers: broad waddling steps,
  bean-like bounce, off-balance recovery, and comic collapse language.
  https://www.youtube.com/watch?v=FcITAzKW3fY
  https://www.youtube.com/watch?v=AyADwdiW7rQ
- Nintendo's official Splatoon 3 weapon/gameplay material: forward-ready upper-body
  silhouette while moving with an ink-firing weapon.
  https://splatoon.nintendo.com/en/weapons/
  https://www.youtube.com/watch?v=-xh-HuNsoBw

The result is original animation adapted to this short-limbed mesh. Locomotion is
in-place. The tongue uses authored overlap and follow-through on every action.
"""

import bpy
import math
import os
from mathutils import Vector


ASSET = "Character_4"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(OUT_DIR, "Character_4.blend")
RUNTIME_OUTPUT = os.path.join(OUT_DIR, "Character_4.glb")
ACTION_PREFIX = f"{ASSET}_"


def ensure_object_mode():
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')


def find_character():
    armatures = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if len(armatures) != 1 or len(meshes) < 1:
        raise RuntimeError("Animated_Character_4 requires one armature and its mesh")
    return armatures[0], max(meshes, key=lambda o: len(o.data.vertices))


def add_weapon_socket(arm):
    ensure_object_mode()
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    ebones = arm.data.edit_bones
    socket = ebones.get("Weapon_Socket") or ebones.new("Weapon_Socket")
    socket.head = (-3.60, 0.05, 2.55)
    socket.tail = (-3.60, -0.38, 2.55)
    socket.roll = 0.0
    socket.use_deform = False
    socket.use_connect = False
    socket.parent = ebones.get("mixamorig:RightHand")
    bpy.ops.object.mode_set(mode='OBJECT')


CONTROLLED = [
    "Root", "mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2",
    "mixamorig:Neck", "mixamorig:Head",
    "mixamorig:LeftShoulder", "mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:LeftHand",
    "mixamorig:RightShoulder", "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand",
    "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot",
    "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot",
    "Tongue_Base", "Tongue_Mid", "Tongue_Tip", "Weapon_Socket",
]


WEAPON_STANCE = {
    "mixamorig:Spine1": {"rot": (4, 0, 0)},
    "mixamorig:Spine2": {"rot": (4, 0, 0)},
    # Right hand aims the trigger/grip forward; left hand crosses inward to
    # support the sauce container/nozzle instead of reaching zombie-style.
    "mixamorig:LeftShoulder": {"rot": (-3, 0, -22)},
    "mixamorig:RightShoulder": {"rot": (3, 0, 30)},
    "mixamorig:LeftArm": {"rot": (-6, 0, -72)},
    "mixamorig:RightArm": {"rot": (8, 0, 75)},
    "mixamorig:LeftForeArm": {"rot": (13, 0, -40)},
    "mixamorig:RightForeArm": {"rot": (-4, 0, 20)},
    "mixamorig:LeftHand": {"rot": (6, -18, 12)},
    "mixamorig:RightHand": {"rot": (-2, 5, -2)},
}


def merged_pose(*layers):
    result = {}
    for layer in layers:
        for bone, values in layer.items():
            current = result.setdefault(bone, {})
            for channel, value in values.items():
                if channel in current and channel in {"rot", "loc"}:
                    current[channel] = tuple(a + b for a, b in zip(current[channel], value))
                else:
                    current[channel] = tuple(value)
    return result


def reset_controlled_pose(arm):
    for name in CONTROLLED:
        pb = arm.pose.bones.get(name)
        if not pb:
            raise RuntimeError(f"Missing required control bone: {name}")
        pb.rotation_mode = 'XYZ'
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


def apply_pose(arm, pose):
    reset_controlled_pose(arm)
    for name, values in pose.items():
        pb = arm.pose.bones[name]
        if "loc" in values:
            pb.location = values["loc"]
        if "rot" in values:
            pb.rotation_euler = tuple(math.radians(v) for v in values["rot"])
        if "scale" in values:
            pb.scale = values["scale"]


def key_controlled(arm, frame):
    for name in CONTROLLED:
        pb = arm.pose.bones[name]
        pb.keyframe_insert(data_path="location", frame=frame, group=name)
        pb.keyframe_insert(data_path="rotation_euler", frame=frame, group=name)
        pb.keyframe_insert(data_path="scale", frame=frame, group=name)


def action_fcurves(action):
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    return curves


def create_action(arm, name, poses, loop, intended_playback):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    action["loop"] = bool(loop)
    action["fps"] = 30
    action["root_motion"] = False
    action["intended_playback"] = intended_playback
    action["weapon_pose"] = "right-hand trigger/aim grip with left-hand under-barrel support; attach weapon to Weapon_Socket"
    action["tongue_secondary_motion"] = True
    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in poses:
        bpy.context.scene.frame_set(frame)
        apply_pose(arm, pose)
        key_controlled(arm, frame)
    action.use_frame_range = True
    action.frame_start = poses[0][0]
    action.frame_end = poses[-1][0]
    action.use_cyclic = bool(loop)
    for fcurve in action_fcurves(action):
        for point in fcurve.keyframe_points:
            point.interpolation = 'BEZIER'
            point.handle_left_type = 'AUTO_CLAMPED'
            point.handle_right_type = 'AUTO_CLAMPED'
    return action


def walk_poses():
    contact_l = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (-0.06, 0.07, 0.00), "rot": (0, 2, -3)},
        "mixamorig:Spine": {"rot": (4, -2, 2)},
        "mixamorig:Head": {"rot": (-3, 2, -2)},
        "mixamorig:LeftUpLeg": {"rot": (-20, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (18, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (7, 0, 0)},
        "mixamorig:RightLeg": {"rot": (28, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (9, 0, 0)},
        "mixamorig:RightFoot": {"rot": (-13, 0, 0)},
        "mixamorig:LeftArm": {"rot": (-2, 0, -2)},
        "mixamorig:RightArm": {"rot": (2, 0, 2)},
        "Tongue_Base": {"rot": (7, 0, -4)},
        "Tongue_Mid": {"rot": (-12, 0, 7)},
        "Tongue_Tip": {"rot": (18, 0, -11)},
    })
    pass_r = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.04, 0.17, 0.01), "rot": (0, -2, 3)},
        "mixamorig:Spine": {"rot": (6, 2, -2)},
        "mixamorig:Head": {"rot": (-4, -2, 2)},
        "mixamorig:LeftUpLeg": {"rot": (7, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (-6, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (31, 0, 0)},
        "mixamorig:RightLeg": {"rot": (9, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (-15, 0, 0)},
        "mixamorig:RightFoot": {"rot": (7, 0, 0)},
        "mixamorig:LeftArm": {"rot": (3, 0, 1)},
        "mixamorig:RightArm": {"rot": (3, 0, -1)},
        "Tongue_Base": {"rot": (-6, 0, 4)},
        "Tongue_Mid": {"rot": (13, 0, -8)},
        "Tongue_Tip": {"rot": (-19, 0, 13)},
    })
    contact_r = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.06, 0.07, 0.00), "rot": (0, -2, 3)},
        "mixamorig:Spine": {"rot": (4, 2, -2)},
        "mixamorig:Head": {"rot": (-3, -2, 2)},
        "mixamorig:LeftUpLeg": {"rot": (18, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (-20, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (28, 0, 0)},
        "mixamorig:RightLeg": {"rot": (7, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (-13, 0, 0)},
        "mixamorig:RightFoot": {"rot": (9, 0, 0)},
        "mixamorig:LeftArm": {"rot": (2, 0, -2)},
        "mixamorig:RightArm": {"rot": (-2, 0, 2)},
        "Tongue_Base": {"rot": (7, 0, 4)},
        "Tongue_Mid": {"rot": (-12, 0, -7)},
        "Tongue_Tip": {"rot": (18, 0, 11)},
    })
    pass_l = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (-0.04, 0.17, 0.01), "rot": (0, 2, -3)},
        "mixamorig:Spine": {"rot": (6, -2, 2)},
        "mixamorig:Head": {"rot": (-4, 2, -2)},
        "mixamorig:LeftUpLeg": {"rot": (-6, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (7, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (9, 0, 0)},
        "mixamorig:RightLeg": {"rot": (31, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (7, 0, 0)},
        "mixamorig:RightFoot": {"rot": (-15, 0, 0)},
        "mixamorig:LeftArm": {"rot": (3, 0, -1)},
        "mixamorig:RightArm": {"rot": (3, 0, 1)},
        "Tongue_Base": {"rot": (-6, 0, -4)},
        "Tongue_Mid": {"rot": (13, 0, 8)},
        "Tongue_Tip": {"rot": (-19, 0, -13)},
    })
    return [(1, contact_l), (7, pass_r), (13, contact_r), (19, pass_l), (25, contact_l)]


def run_poses():
    contact_l = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (-0.08, 0.08, 0.05), "rot": (7, 2, -5)},
        "mixamorig:Spine": {"rot": (9, -2, 3)},
        "mixamorig:Head": {"rot": (-5, 2, -3)},
        "mixamorig:LeftUpLeg": {"rot": (-31, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (27, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (10, 0, 0)},
        "mixamorig:RightLeg": {"rot": (42, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (15, 0, 0)},
        "mixamorig:RightFoot": {"rot": (-21, 0, 0)},
        "mixamorig:LeftArm": {"rot": (-5, 0, -3)},
        "mixamorig:RightArm": {"rot": (5, 0, 3)},
        "Tongue_Base": {"rot": (12, 0, -7)},
        "Tongue_Mid": {"rot": (-20, 0, 12)},
        "Tongue_Tip": {"rot": (28, 0, -18)},
    })
    air_r = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.05, 0.32, 0.10), "rot": (10, -2, 5)},
        "mixamorig:Spine": {"rot": (11, 2, -3)},
        "mixamorig:Head": {"rot": (-7, -2, 3)},
        "mixamorig:LeftUpLeg": {"rot": (8, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (-17, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (52, 0, 0)},
        "mixamorig:RightLeg": {"rot": (34, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (-20, 0, 0)},
        "mixamorig:RightFoot": {"rot": (13, 0, 0)},
        "mixamorig:LeftArm": {"rot": (6, 0, 2)},
        "mixamorig:RightArm": {"rot": (6, 0, -2)},
        "Tongue_Base": {"rot": (-12, 0, 7)},
        "Tongue_Mid": {"rot": (22, 0, -13)},
        "Tongue_Tip": {"rot": (-32, 0, 20)},
    })
    contact_r = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.08, 0.08, 0.05), "rot": (7, -2, 5)},
        "mixamorig:Spine": {"rot": (9, 2, -3)},
        "mixamorig:Head": {"rot": (-5, -2, 3)},
        "mixamorig:LeftUpLeg": {"rot": (27, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (-31, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (42, 0, 0)},
        "mixamorig:RightLeg": {"rot": (10, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (-21, 0, 0)},
        "mixamorig:RightFoot": {"rot": (15, 0, 0)},
        "mixamorig:LeftArm": {"rot": (5, 0, -3)},
        "mixamorig:RightArm": {"rot": (-5, 0, 3)},
        "Tongue_Base": {"rot": (12, 0, 7)},
        "Tongue_Mid": {"rot": (-20, 0, -12)},
        "Tongue_Tip": {"rot": (28, 0, 18)},
    })
    air_l = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (-0.05, 0.32, 0.10), "rot": (10, 2, -5)},
        "mixamorig:Spine": {"rot": (11, -2, 3)},
        "mixamorig:Head": {"rot": (-7, 2, -3)},
        "mixamorig:LeftUpLeg": {"rot": (-17, 0, 0)},
        "mixamorig:RightUpLeg": {"rot": (8, 0, 0)},
        "mixamorig:LeftLeg": {"rot": (34, 0, 0)},
        "mixamorig:RightLeg": {"rot": (52, 0, 0)},
        "mixamorig:LeftFoot": {"rot": (13, 0, 0)},
        "mixamorig:RightFoot": {"rot": (-20, 0, 0)},
        "mixamorig:LeftArm": {"rot": (6, 0, -2)},
        "mixamorig:RightArm": {"rot": (6, 0, 2)},
        "Tongue_Base": {"rot": (-12, 0, -7)},
        "Tongue_Mid": {"rot": (22, 0, 13)},
        "Tongue_Tip": {"rot": (-32, 0, -20)},
    })
    return [(1, contact_l), (5, air_r), (9, contact_r), (13, air_l), (17, contact_l)]


def death_poses():
    alive = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"rot": (2, 0, 0)},
        "mixamorig:Spine": {"rot": (4, 0, 0)},
        "Tongue_Base": {"rot": (2, 0, 0)},
        "Tongue_Mid": {"rot": (-4, 0, 0)},
        "Tongue_Tip": {"rot": (6, 0, 0)},
    })
    hit = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0, 0.08, -0.06), "rot": (-8, 0, 0)},
        "mixamorig:Spine": {"rot": (-12, 0, 0)},
        "mixamorig:Spine1": {"rot": (-8, 0, 0)},
        "mixamorig:Head": {"rot": (-18, 0, 7)},
        "mixamorig:LeftArm": {"rot": (9, 0, -8)},
        "mixamorig:RightArm": {"rot": (9, 0, 8)},
        "Tongue_Base": {"rot": (-15, 0, -4)},
        "Tongue_Mid": {"rot": (24, 0, 8)},
        "Tongue_Tip": {"rot": (-30, 0, -13)},
    })
    stagger = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.14, 0.36, 0.05), "rot": (10, 4, -10)},
        "mixamorig:Spine": {"rot": (15, -4, 8)},
        "mixamorig:Spine1": {"rot": (12, 0, 7)},
        "mixamorig:Head": {"rot": (18, -7, -12)},
        "mixamorig:LeftUpLeg": {"rot": (-8, 0, -5)},
        "mixamorig:RightUpLeg": {"rot": (12, 0, 6)},
        "mixamorig:LeftLeg": {"rot": (24, 0, 0)},
        "mixamorig:RightLeg": {"rot": (18, 0, 0)},
        "Tongue_Base": {"rot": (20, 0, 9)},
        "Tongue_Mid": {"rot": (-28, 0, -15)},
        "Tongue_Tip": {"rot": (38, 0, 22)},
    })
    buckle = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.10, 0.50, 0.08), "rot": (18, 3, -17)},
        "mixamorig:Spine": {"rot": (24, -2, 12)},
        "mixamorig:Spine1": {"rot": (18, 0, 10)},
        "mixamorig:Head": {"rot": (27, -8, -14)},
        "mixamorig:LeftUpLeg": {"rot": (-5, 0, -8)},
        "mixamorig:RightUpLeg": {"rot": (8, 0, 10)},
        "mixamorig:LeftLeg": {"rot": (46, 0, 0)},
        "mixamorig:RightLeg": {"rot": (51, 0, 0)},
        "mixamorig:LeftArm": {"rot": (-5, 0, 24)},
        "mixamorig:LeftForeArm": {"rot": (10, 0, 20)},
        "mixamorig:RightArm": {"rot": (8, 0, -13)},
        "Tongue_Base": {"rot": (-18, 0, 12)},
        "Tongue_Mid": {"rot": (31, 0, -20)},
        "Tongue_Tip": {"rot": (-42, 0, 29)},
    })
    collapse = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.22, 0.58, 0.10), "rot": (10, 3, -20)},
        "mixamorig:Spine": {"rot": (18, -2, 8)},
        "mixamorig:Spine1": {"rot": (12, 0, 6)},
        "mixamorig:Spine2": {"rot": (7, 0, 4)},
        "mixamorig:Head": {"rot": (18, -5, -8)},
        "mixamorig:LeftUpLeg": {"rot": (2, 0, -12)},
        "mixamorig:RightUpLeg": {"rot": (14, 0, 14)},
        "mixamorig:LeftLeg": {"rot": (61, 0, 0)},
        "mixamorig:RightLeg": {"rot": (56, 0, 0)},
        "mixamorig:LeftArm": {"rot": (4, 0, 68)},
        "mixamorig:LeftForeArm": {"rot": (18, 0, 36)},
        "mixamorig:RightArm": {"rot": (15, 0, -25)},
        "mixamorig:RightForeArm": {"rot": (12, 0, -8)},
        "Tongue_Base": {"rot": (22, 0, -16)},
        "Tongue_Mid": {"rot": (-36, 0, 28)},
        "Tongue_Tip": {"rot": (48, 0, -38)},
    })
    settle = merged_pose(WEAPON_STANCE, {
        "mixamorig:Hips": {"loc": (0.24, 0.55, 0.12), "rot": (12, 3, -23)},
        "mixamorig:Spine": {"rot": (22, -2, 10)},
        "mixamorig:Spine1": {"rot": (14, 0, 7)},
        "mixamorig:Spine2": {"rot": (9, 0, 5)},
        "mixamorig:Head": {"rot": (22, -6, -10)},
        "mixamorig:LeftUpLeg": {"rot": (4, 0, -13)},
        "mixamorig:RightUpLeg": {"rot": (16, 0, 15)},
        "mixamorig:LeftLeg": {"rot": (65, 0, 0)},
        "mixamorig:RightLeg": {"rot": (59, 0, 0)},
        "mixamorig:LeftArm": {"rot": (6, 0, 74)},
        "mixamorig:LeftForeArm": {"rot": (20, 0, 39)},
        "mixamorig:RightArm": {"rot": (17, 0, -28)},
        "mixamorig:RightForeArm": {"rot": (13, 0, -10)},
        "Tongue_Base": {"rot": (18, 0, -13)},
        "Tongue_Mid": {"rot": (-29, 0, 23)},
        "Tongue_Tip": {"rot": (36, 0, -30)},
    })
    return [(1, alive), (6, hit), (12, stagger), (20, buckle), (32, collapse), (40, settle), (48, settle)]


def validate_actions(arm, actions):
    for action, expected_range, loop in actions:
        if not action.use_fake_user:
            raise RuntimeError(f"{action.name} lacks fake user")
        if tuple(round(x) for x in action.frame_range) != expected_range:
            raise RuntimeError(f"{action.name} range {tuple(action.frame_range)} != {expected_range}")
        if bool(action["loop"]) != loop:
            raise RuntimeError(f"{action.name} loop metadata mismatch")
        if not action_fcurves(action):
            raise RuntimeError(f"{action.name} has no animation curves")
        for frame in range(expected_range[0], expected_range[1] + 1):
            arm.animation_data.action = action
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            for pb in arm.pose.bones:
                if any(not math.isfinite(v) for row in pb.matrix for v in row):
                    raise RuntimeError(f"Non-finite pose matrix in {action.name}, frame {frame}, bone {pb.name}")


def evaluated_min_z(mesh):
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    evaluated_mesh = evaluated.to_mesh()
    try:
        return min((evaluated.matrix_world @ vertex.co).z for vertex in evaluated_mesh.vertices)
    finally:
        evaluated.to_mesh_clear()


def align_action_to_ground(arm, mesh, action, start, end, margin=0.01, passes=2):
    """Keep the collapsing death performance grounded at every sampled frame."""
    arm.animation_data.action = action
    hips = arm.pose.bones["mixamorig:Hips"]
    local_up_armature = hips.bone.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))
    units_to_world_z = (arm.matrix_world.to_3x3() @ local_up_armature).z
    if abs(units_to_world_z) < 1e-6:
        raise RuntimeError("Cannot derive hips vertical translation axis")
    for _ in range(passes):
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            correction = (margin - evaluated_min_z(mesh)) / units_to_world_z
            if abs(correction) > 1e-6:
                hips.location.y += correction
                bpy.context.view_layer.update()
                hips.keyframe_insert(data_path="location", frame=frame, group=hips.name)
    for fcurve in action_fcurves(action):
        if 'mixamorig:Hips' in fcurve.data_path and fcurve.data_path.endswith('location'):
            for point in fcurve.keyframe_points:
                point.interpolation = 'LINEAR'
    return action


arm, mesh = find_character()
add_weapon_socket(arm)
ensure_object_mode()
for action in list(bpy.data.actions):
    if action.name in {f"{ACTION_PREFIX}Walk_Weapon", f"{ACTION_PREFIX}Run_Weapon", f"{ACTION_PREFIX}Death_Weapon"}:
        bpy.data.actions.remove(action)

walk = create_action(arm, f"{ACTION_PREFIX}Walk_Weapon", walk_poses(), True, "frames 1-24; frame 25 duplicates frame 1 for authoring")
run = create_action(arm, f"{ACTION_PREFIX}Run_Weapon", run_poses(), True, "frames 1-16; frame 17 duplicates frame 1 for authoring")
death = create_action(arm, f"{ACTION_PREFIX}Death_Weapon", death_poses(), False, "frames 1-48; hold frame 48")
align_action_to_ground(arm, mesh, death, 1, 48)

arm["asset_name"] = ASSET
arm["character_slot"] = 4
arm["runtime_character_index"] = 3
arm["independent_character_asset"] = True
arm["forward_axis"] = "-Y"
arm["up_axis"] = "+Z"
arm["animation_fps"] = 30
arm["root_motion_policy"] = "in_place"
arm["action_list"] = ",".join(a.name for a in (walk, run, death))
arm["weapon_attachment_bone"] = "Weapon_Socket"
arm["weapon_mesh_included"] = False
arm["weapon_grip_style"] = "right hand aims and fires; left hand supports the sauce container/nozzle"
arm["motion_references"] = "Fall Guys official gameplay/launch trailers; Splatoon 3 official weapons and launch material"
arm["motion_breakdown"] = "Waddling bounce and comic collapse adapted to a shooter-style sauce-weapon grip: right hand aims, left hand supports; tongue overlaps body acceleration and settles late."
bpy.context.scene["Character_4_animation_notes"] = "Independent playable character 4 asset. In-place Walk/Run and one-shot Death, all authored in weapon-carry context."
bpy.context.scene.render.fps = 30

validate_actions(arm, [(walk, (1, 25), True), (run, (1, 17), True), (death, (1, 48), False)])

# Predictable inspection state: Walk at its first contact pose.
arm.animation_data.action = walk
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 25
bpy.context.scene.frame_set(1)
apply_pose(arm, walk_poses()[0][1])
bpy.context.view_layer.objects.active = arm
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
arm.data.bones.active = arm.data.bones.get("Weapon_Socket")
bpy.context.preferences.filepaths.file_preview_type = 'NONE'
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUTPUT, check_existing=False)
bpy.ops.export_scene.gltf(
    filepath=RUNTIME_OUTPUT,
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
print("ANIMATED_CHARACTER_4_BUILD_OK", OUTPUT, [a.name for a in (walk, run, death)])
print("CHARACTER_4_EXPORTED", RUNTIME_OUTPUT)
