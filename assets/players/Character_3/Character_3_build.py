"""Repair and extend the Character_3 rig in-place.

Motion references consulted (2026-10-06):
- Nintendo, Yoshi and the Mysterious Book: tongue protrudes from an anchored mouth
  base for a readable grab/gobble action.
  https://www.nintendo.com/en-ca/store/products/yoshi-and-the-mysterious-book-125659/
- Riot Games, Tahm Kench: tongue action is described and shown as a forward lash.
  https://www.leagueoflegends.com/en-ph/champions/tahmkench/
- Nintendo, Splatoon 3 gameplay/weapons: compact weapon-ready silhouettes and
  readable movement while carrying a ranged tool.
  https://splatoon.nintendo.com/ca/gameplay/
  https://splatoon.nintendo.com/en/weapons/
- Nintendo, Luigi's Mansion 3 gameplay: both hands organize around a bulky
  forward-facing tool while the torso and legs supply locomotion.
  https://luigismansion.nintendo.com/en_CA/gameplay/
- PlayStation, Fall Guys: broad, bouncy stubby-limb running and intentionally
  ridiculous falling/stumbling silhouettes.
  https://www.playstation.com/en-us/games/fall-guys-ultimate-knockout/

Observed: a fixed oral root, decisive extension, and a clear return read best in
gameplay. Professional adaptation: this character uses a compact looping wag with
staggered base/mid/tip overlap, plus a small head counter-motion. This is original
motion authored for this asset, not copied animation data. The three armed actions
carry an imaginary sauce canister; no weapon object is created or merged.

The script is idempotent and is intended to be run with Blender 5.2 in background
mode against Character_3.blend. It saves back to the file it was opened from.
"""

import bpy
import heapq
import math
from pathlib import Path
from mathutils import Euler, Matrix, Vector


ARMATURE_NAME = "chef character 3d model"
MESH_NAME = "tripo_node_d405fd25"
ACTION_NAME = "Character_3_Tongue_Wiggle"
TONGUE_NAMES = ("Tongue_Base", "Tongue_Mid", "Tongue_Tip")
ARMED_WALK = "Character_3_Armed_Walk"
ARMED_RUN = "Character_3_Armed_Run"
ARMED_DEATH = "Character_3_Armed_Death"
HERE = Path(__file__).resolve().parent
RUNTIME_PATH = HERE / "Character_3.glb"


def require_object(name, obj_type):
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != obj_type:
        raise RuntimeError(f"Expected {obj_type} object {name!r}")
    return obj


def set_active(obj):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def mirror_right_arm_from_left(arm):
    """Replace the malformed screen-left (character Right) rest chain."""
    set_active(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = arm.data.edit_bones
    left_names = [b.name for b in ebones if b.name.startswith("mixamorig:Left")]
    # Parents are already correct; copy geometry and roll for the entire arm/hand branch.
    for left_name in left_names:
        right_name = left_name.replace("mixamorig:Left", "mixamorig:Right", 1)
        src = ebones.get(left_name)
        dst = ebones.get(right_name)
        if src is None or dst is None:
            continue
        if not any(token in left_name for token in ("Shoulder", "Arm", "ForeArm", "Hand")):
            continue
        src_z = src.z_axis.copy()
        dst.head = Vector((-src.head.x, src.head.y, src.head.z))
        dst.tail = Vector((-src.tail.x, src.tail.y, src.tail.z))
        dst.align_roll(Vector((-src_z.x, src_z.y, src_z.z)))
    bpy.ops.object.mode_set(mode="OBJECT")


def add_head_and_tongue_bones(arm):
    set_active(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = arm.data.edit_bones
    head = ebones.get("mixamorig:Head")
    neck = ebones.get("mixamorig:Neck")
    if head is None or neck is None:
        raise RuntimeError("Existing Mixamo head/neck bones were not found")

    ctrl = ebones.get("CTRL_Head") or ebones.new("CTRL_Head")
    ctrl.head = head.head.copy()
    ctrl.tail = head.tail.copy()
    ctrl.roll = head.roll
    ctrl.parent = neck
    ctrl.use_connect = False
    ctrl.use_deform = False
    head.parent = ctrl
    head.use_connect = False

    # Centers measured from the actual connected tongue surface in world space.
    world_points = (
        Vector((0.10, -0.98, 4.58)),
        Vector((0.22, -1.30, 4.50)),
        Vector((0.31, -1.65, 4.48)),
        Vector((0.41, -2.04, 4.40)),
    )
    points = [arm.matrix_world.inverted() @ p for p in world_points]
    parent = head
    for i, name in enumerate(TONGUE_NAMES):
        b = ebones.get(name) or ebones.new(name)
        b.head = points[i]
        b.tail = points[i + 1]
        b.parent = parent
        b.use_connect = i > 0
        b.use_deform = True
        b.align_roll(Vector((0.0, 0.0, 1.0)))
        parent = b
    bpy.ops.object.mode_set(mode="OBJECT")

    # Keep controls easy to identify without changing the source armature display style.
    if hasattr(arm.data, "collections"):
        controls = arm.data.collections.get("Controls") or arm.data.collections.new("Controls")
        face_rig = arm.data.collections.get("Face_Tongue") or arm.data.collections.new("Face_Tongue")
        controls.assign(arm.data.bones["CTRL_Head"])
        for name in TONGUE_NAMES:
            face_rig.assign(arm.data.bones[name])

    arm.pose.bones["CTRL_Head"]["control_role"] = "Head rotation control"
    for name in TONGUE_NAMES:
        arm.pose.bones[name]["control_role"] = "Tongue FK control"


def tongue_geodesic(mesh_obj):
    mesh = mesh_obj.data
    world = mesh_obj.matrix_world
    seed_target = Vector((0.45, -2.02, 4.34))
    seed = min(mesh.vertices, key=lambda v: (world @ v.co - seed_target).length).index
    adjacency = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        pa = world @ mesh.vertices[a].co
        pb = world @ mesh.vertices[b].co
        length = (pb - pa).length
        adjacency[a].append((b, length))
        adjacency[b].append((a, length))
    dist = [float("inf")] * len(mesh.vertices)
    dist[seed] = 0.0
    heap = [(0.0, seed)]
    while heap:
        d, vertex = heapq.heappop(heap)
        if d != dist[vertex] or d > 1.55:
            continue
        for neighbor, edge_length in adjacency[vertex]:
            nd = d + edge_length
            if nd < dist[neighbor]:
                dist[neighbor] = nd
                heapq.heappush(heap, (nd, neighbor))
    return dist


def gaussian(x, center, sigma):
    return math.exp(-0.5 * ((x - center) / sigma) ** 2)


def weight_tongue(mesh_obj):
    mesh = mesh_obj.data
    dist = tongue_geodesic(mesh_obj)
    selected = [i for i, d in enumerate(dist) if d <= 1.42]
    if not 55 <= len(selected) <= 220:
        raise RuntimeError(f"Tongue selection sanity check failed: {len(selected)} vertices")

    groups = {}
    for name in ("mixamorig:Head",) + TONGUE_NAMES:
        groups[name] = mesh_obj.vertex_groups.get(name) or mesh_obj.vertex_groups.new(name=name)
    # Clear previous generated weights globally, making reruns deterministic.
    all_indices = list(range(len(mesh.vertices)))
    for name in TONGUE_NAMES:
        groups[name].remove(all_indices)

    for index in selected:
        # Tongue vertices should not inherit stray torso/face weights.
        for membership in list(mesh.vertices[index].groups):
            mesh_obj.vertex_groups[membership.group].remove([index])
        d = dist[index]
        raw = {
            "Tongue_Tip": gaussian(d, 0.12, 0.27),
            "Tongue_Mid": gaussian(d, 0.62, 0.27),
            "Tongue_Base": gaussian(d, 1.08, 0.28),
            "mixamorig:Head": gaussian(d, 1.43, 0.20),
        }
        total = sum(raw.values())
        for name, value in raw.items():
            groups[name].add([index], value / total, "REPLACE")
    return len(selected)


def insert_transform_key(pbone, frame, rotation=(0.0, 0.0, 0.0)):
    pbone.rotation_mode = "XYZ"
    pbone.location = (0.0, 0.0, 0.0)
    pbone.rotation_euler = rotation
    pbone.scale = (1.0, 1.0, 1.0)
    pbone.keyframe_insert("location", frame=frame, group=pbone.name)
    pbone.keyframe_insert("rotation_euler", frame=frame, group=pbone.name)
    pbone.keyframe_insert("scale", frame=frame, group=pbone.name)


def build_tongue_action(arm):
    if old := bpy.data.actions.get(ACTION_NAME):
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(ACTION_NAME)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action

    ctrl = arm.pose.bones["CTRL_Head"]
    base = arm.pose.bones["Tongue_Base"]
    mid = arm.pose.bones["Tongue_Mid"]
    tip = arm.pose.bones["Tongue_Tip"]
    poses = {
        1:  ((0, 0, 0), (0, 0, 0),       (0, 0, 0),        (0, 0, 0)),
        7:  ((0.02, 0, -0.04), (0.05, 0, 0.10),  (-0.10, 0, -0.26), (0.14, 0, 0.42)),
        13: ((-0.015, 0, 0.03), (-0.04, 0, -0.08), (0.08, 0, 0.22),  (-0.12, 0, -0.36)),
        19: ((0.025, 0, -0.035), (0.04, 0, 0.09), (-0.09, 0, -0.24), (0.12, 0, 0.38)),
        25: ((-0.01, 0, 0.02), (-0.03, 0, -0.06), (0.06, 0, 0.17), (-0.09, 0, -0.28)),
        33: ((0, 0, 0), (0, 0, 0),       (0, 0, 0),        (0, 0, 0)),
    }
    for frame, values in poses.items():
        for pbone, rotation in zip((ctrl, base, mid, tip), values):
            insert_transform_key(pbone, frame, rotation)

    fcurves = []
    if hasattr(action, "fcurves"):
        fcurves.extend(action.fcurves)
    else:
        for layer in action.layers:
            for strip in layer.strips:
                if hasattr(strip, "channelbags"):
                    for channelbag in strip.channelbags:
                        fcurves.extend(channelbag.fcurves)
    for fcurve in fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "BEZIER"
        fcurve.modifiers.new("CYCLES")
    return action


ANIMATED_BONES = (
    "mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Spine2",
    "mixamorig:Neck", "CTRL_Head",
    "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot", "mixamorig:LeftToeBase",
    "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot", "mixamorig:RightToeBase",
    "mixamorig:LeftShoulder", "mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:LeftHand",
    "mixamorig:RightShoulder", "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand",
    "Tongue_Base", "Tongue_Mid", "Tongue_Tip",
)


def iter_action_fcurves(action):
    if hasattr(action, "fcurves"):
        yield from action.fcurves
        return
    for layer in action.layers:
        for strip in layer.strips:
            if hasattr(strip, "channelbags"):
                for channelbag in strip.channelbags:
                    yield from channelbag.fcurves


def reset_pose(arm):
    for pbone in arm.pose.bones:
        pbone.rotation_mode = "QUATERNION"
        pbone.location = (0.0, 0.0, 0.0)
        pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pbone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def begin_action(arm, name, end_frame, loop):
    if old := bpy.data.actions.get(name):
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action["fps"] = 24
    action["frame_start"] = 1
    action["frame_end"] = end_frame
    action["loop"] = loop
    action["root_motion"] = "in-place"
    action["weapon_policy"] = "Two-hand imaginary sauce-canister carry; no weapon object included"
    action["tongue_secondary_motion"] = True
    arm.animation_data_create()
    arm.animation_data.action = action
    reset_pose(arm)
    return action


def aim_pose_bone(pbone, direction, roll_hint=Vector((0.0, 0.0, 1.0))):
    """Swing local Y toward direction without replacing the source bone roll."""
    desired = Vector(direction).normalized()
    current = (pbone.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
    swing = current.rotation_difference(desired)
    origin = pbone.matrix.translation.copy()
    rotated = swing.to_matrix().to_4x4() @ pbone.matrix.to_3x3().to_4x4()
    pbone.matrix = Matrix.Translation(origin) @ rotated
    bpy.context.view_layer.update()


def rotate_global(arm, name, axis, degrees):
    """Match the proven Character_2 global-space posing method."""
    bpy.context.view_layer.update()
    pbone = arm.pose.bones[name]
    pivot = pbone.matrix.translation.copy()
    rotation = Matrix.Rotation(math.radians(degrees), 4, Vector(axis))
    pbone.matrix = Matrix.Translation(pivot) @ rotation @ Matrix.Translation(-pivot) @ pbone.matrix
    bpy.context.view_layer.update()


def translate_global(arm, name, offset):
    bpy.context.view_layer.update()
    pbone = arm.pose.bones[name]
    # Pose matrices are in armature space. Character_3's armature carries a 10x
    # object scale, so convert the requested world offset before applying it.
    armature_offset = arm.matrix_world.inverted().to_3x3() @ Vector(offset)
    pbone.matrix = Matrix.Translation(armature_offset) @ pbone.matrix
    bpy.context.view_layer.update()


def key_current_pose(arm, frame):
    for name in ANIMATED_BONES:
        pbone = arm.pose.bones[name]
        pbone.keyframe_insert("location", frame=frame, group=name)
        pbone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        pbone.keyframe_insert("scale", frame=frame, group=name)


def correct_ground_contact(arm, margin=0.015):
    """Lift the root only when the evaluated mesh would penetrate world Z=0."""
    mesh_obj = bpy.data.objects[MESH_NAME]
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = mesh_obj.evaluated_get(depsgraph)
    eval_mesh = eval_obj.to_mesh()
    min_z = min((eval_obj.matrix_world @ v.co).z for v in eval_mesh.vertices)
    eval_obj.to_mesh_clear()
    if min_z >= margin:
        return 0.0
    hips = arm.pose.bones["mixamorig:Hips"]
    local_up_armature = hips.bone.matrix_local.to_3x3() @ Vector((0.0, 1.0, 0.0))
    world_up = arm.matrix_world.to_3x3() @ local_up_armature
    units_to_world_z = world_up.z
    if abs(units_to_world_z) < 1e-6:
        raise RuntimeError("Cannot derive hips vertical translation axis")
    correction = (margin - min_z) / units_to_world_z
    hips.location.y += correction
    bpy.context.view_layer.update()
    return correction


def set_local_rotation(arm, name, rotation, location=None, scale=None):
    pbone = arm.pose.bones[name]
    pbone.rotation_mode = "QUATERNION"
    pbone.rotation_quaternion = Euler(rotation, "XYZ").to_quaternion()
    if location is not None:
        pbone.location = location
    if scale is not None:
        pbone.scale = scale
    bpy.context.view_layer.update()


def torso_pose(arm, side, lean, nod=0.0):
    aim_pose_bone(arm.pose.bones["mixamorig:Spine"], (side * 0.35, -lean, 1.0))
    aim_pose_bone(arm.pose.bones["mixamorig:Spine1"], (-side * 0.15, -lean * 0.75, 1.0))
    aim_pose_bone(arm.pose.bones["mixamorig:Spine2"], (side * 0.10, -lean * 0.55, 1.0))
    aim_pose_bone(arm.pose.bones["mixamorig:Neck"], (-side * 0.08, 0.03 + nod, 1.0))
    aim_pose_bone(arm.pose.bones["CTRL_Head"], (side * 0.04, 0.05 + nod, 1.0))


def weapon_hold(arm, side=0.0, lift=0.0, flare=0.0):
    """Same readable two-hand imaginary sauce-tank grip used by Character_2."""
    aim_pose_bone(arm.pose.bones["mixamorig:LeftShoulder"], (1.0, -0.16 - side * 0.05, -0.04 + lift))
    aim_pose_bone(arm.pose.bones["mixamorig:RightShoulder"], (-1.0, -0.16 - side * 0.05, -0.04 + lift))
    aim_pose_bone(arm.pose.bones["mixamorig:LeftArm"], (0.38 + flare, -0.86, -0.34 + lift))
    aim_pose_bone(arm.pose.bones["mixamorig:RightArm"], (-0.38 - flare, -0.86, -0.34 + lift))
    aim_pose_bone(arm.pose.bones["mixamorig:LeftForeArm"], (-0.58, -0.78, 0.02 + lift * 0.6))
    aim_pose_bone(arm.pose.bones["mixamorig:RightForeArm"], (0.58, -0.78, 0.02 + lift * 0.6))
    aim_pose_bone(arm.pose.bones["mixamorig:LeftHand"], (-0.10, -1.0, -0.02))
    aim_pose_bone(arm.pose.bones["mixamorig:RightHand"], (0.10, -1.0, -0.02))


def legs_pose(arm, limbs):
    names = (
        "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot", "mixamorig:LeftToeBase",
        "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot", "mixamorig:RightToeBase",
    )
    for name, direction in zip(names, limbs):
        aim_pose_bone(arm.pose.bones[name], direction)


def tongue_follow(arm, side, bounce, run=False):
    amount = 1.35 if run else 0.85
    set_local_rotation(arm, "Tongue_Base", (0.05 * bounce, 0.0, -0.10 * side * amount))
    set_local_rotation(arm, "Tongue_Mid", (-0.10 * bounce, 0.0, 0.22 * side * amount))
    set_local_rotation(arm, "Tongue_Tip", (0.15 * bounce, 0.0, -0.38 * side * amount))


def pose_walk(arm, index):
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
    reset_pose(arm)
    rotate_global(arm, "mixamorig:Hips", (0, 1, 0), data["side"] * 10.0)
    translate_global(arm, "mixamorig:Hips", (0.0, 0.0, data["z"]))
    torso_pose(arm, data["side"], data["lean"])
    legs_pose(arm, data["limbs"])
    weapon_hold(arm, side=data["side"], lift=data["z"] * 0.025)
    tongue_follow(arm, data["side"], data["z"], run=False)


def pose_run(arm, index):
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
    reset_pose(arm)
    rotate_global(arm, "mixamorig:Hips", (0, 1, 0), data["side"] * 13.0)
    translate_global(arm, "mixamorig:Hips", (0.0, 0.0, data["z"]))
    torso_pose(arm, data["side"], 0.28, nod=-0.03)
    legs_pose(arm, data["limbs"])
    weapon_hold(arm, side=data["side"], lift=0.035 + data["z"] * 0.02, flare=0.05)
    tongue_follow(arm, data["side"], data["z"], run=True)


def finish_action(action, loop):
    for fcurve in iter_action_fcurves(action):
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR" if ('mixamorig:Hips' in fcurve.data_path and fcurve.data_path.endswith('location')) else "BEZIER"
        if loop:
            fcurve.modifiers.new("CYCLES")
    return action


def bake_ground_corrections(arm, action, start, end, margin=0.01, passes=2):
    """Add only the root-height keys needed to keep every sampled frame above ground."""
    arm.animation_data.action = action
    for _ in range(passes):
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            if correct_ground_contact(arm, margin=margin):
                arm.pose.bones["mixamorig:Hips"].keyframe_insert(
                    "location", frame=frame, group="mixamorig:Hips"
                )
    for fcurve in iter_action_fcurves(action):
        if 'mixamorig:Hips' in fcurve.data_path and fcurve.data_path.endswith('location'):
            for key in fcurve.keyframe_points:
                key.interpolation = "LINEAR"
    return action


def build_armed_walk(arm):
    action = begin_action(arm, ARMED_WALK, 25, True)
    for frame, pose_index in ((1, 0), (7, 1), (13, 2), (19, 3), (25, 0)):
        pose_walk(arm, pose_index)
        correct_ground_contact(arm)
        key_current_pose(arm, frame)
    finish_action(action, True)
    return bake_ground_corrections(arm, action, 1, 25, margin=0.01)


def build_armed_run(arm):
    action = begin_action(arm, ARMED_RUN, 17, True)
    for frame, pose_index in ((1, 0), (5, 1), (9, 2), (13, 3), (17, 0)):
        pose_run(arm, pose_index)
        correct_ground_contact(arm)
        key_current_pose(arm, frame)
    finish_action(action, True)
    return bake_ground_corrections(arm, action, 1, 17, margin=0.01)


def pose_death(arm, stage):
    reset_pose(arm)
    if stage == 0:
        torso_pose(arm, 0.0, 0.14)
        legs_pose(arm, ((0.03, -0.12, -1.0), (0.00, 0.04, -1.0), (0.00, -1.0, -0.04), (0.00, -1.0, 0.0),
                        (-0.03, 0.12, -1.0), (0.00, -0.04, -1.0), (0.00, -1.0, -0.04), (0.00, -1.0, 0.0)))
        weapon_hold(arm)
    elif stage == 1:
        rotate_global(arm, "mixamorig:Hips", (1, 0, 0), -11.0)
        translate_global(arm, "mixamorig:Hips", (0.0, 0.26, 0.24))
        torso_pose(arm, 0.10, -0.22, nod=0.10)
        legs_pose(arm, ((0.05, -0.18, -1.0), (0.00, 0.12, -1.0), (0.00, -1.0, -0.03), (0.00, -1.0, 0.0),
                        (-0.04, 0.12, -1.0), (0.00, -0.10, -1.0), (0.00, -1.0, -0.03), (0.00, -1.0, 0.0)))
        weapon_hold(arm, lift=0.30, flare=0.16)
    elif stage == 2:
        rotate_global(arm, "mixamorig:Hips", (0, 1, 0), 24.0)
        rotate_global(arm, "mixamorig:Hips", (1, 0, 0), 12.0)
        translate_global(arm, "mixamorig:Hips", (0.30, 0.05, 0.39))
        torso_pose(arm, 0.36, 0.34, nod=-0.05)
        legs_pose(arm, ((0.20, -0.26, -0.72), (0.08, -0.62, -0.52), (0.05, -0.94, -0.12), (0.00, -1.0, 0.08),
                        (-0.22, 0.10, -0.78), (-0.08, -0.58, -0.58), (-0.05, -0.92, -0.14), (0.00, -1.0, 0.08)))
        weapon_hold(arm, side=0.30, lift=-0.05, flare=0.22)
    else:
        final = stage >= 4
        rotate_global(arm, "mixamorig:Hips", (0, 1, 0), 88.0 if final else 62.0)
        rotate_global(arm, "mixamorig:Hips", (0, 0, 1), -13.0 if final else -10.0)
        translate_global(arm, "mixamorig:Hips", (1.32, -0.12, 1.40) if final else (1.05, -0.05, 1.04))
        aim_pose_bone(arm.pose.bones["mixamorig:LeftArm"], (0.15 if final else 0.30, -0.78 if final else -0.80, -0.44 if final else -0.30))
        aim_pose_bone(arm.pose.bones["mixamorig:RightArm"], (-0.12 if final else -0.20, -0.80 if final else -0.82, -0.40 if final else -0.25))
        aim_pose_bone(arm.pose.bones["mixamorig:LeftForeArm"], (-0.46 if final else -0.50, -0.82, -0.18 if final else -0.10))
        aim_pose_bone(arm.pose.bones["mixamorig:RightForeArm"], (0.46 if final else 0.50, -0.82, -0.18 if final else -0.10))
        aim_pose_bone(arm.pose.bones["mixamorig:LeftHand"], (-0.08, -1.0, -0.10))
        aim_pose_bone(arm.pose.bones["mixamorig:RightHand"], (0.08, -1.0, -0.10))
        aim_pose_bone(arm.pose.bones["mixamorig:LeftUpLeg"], (0.30, -0.18 if final else -0.25, -0.78))
        aim_pose_bone(arm.pose.bones["mixamorig:LeftLeg"], (0.12, -0.56 if final else -0.62, -0.70 if final else -0.62))
        aim_pose_bone(arm.pose.bones["mixamorig:RightUpLeg"], (-0.22 if final else -0.20, 0.12 if final else 0.18, -0.82))
        aim_pose_bone(arm.pose.bones["mixamorig:RightLeg"], (-0.10 if final else -0.08, -0.52 if final else -0.55, -0.74 if final else -0.70))
        if final:
            aim_pose_bone(arm.pose.bones["mixamorig:LeftFoot"], (0.08, -0.88, -0.22))
            aim_pose_bone(arm.pose.bones["mixamorig:RightFoot"], (-0.05, -0.90, -0.18))
    set_local_rotation(arm, "Tongue_Base", (0.08 * stage, 0.0, -0.12 * stage))
    set_local_rotation(arm, "Tongue_Mid", (-0.12 * stage, 0.0, 0.24 * stage))
    set_local_rotation(arm, "Tongue_Tip", (0.18 * stage, 0.0, -0.38 * stage))


def build_armed_death(arm):
    action = begin_action(arm, ARMED_DEATH, 40, False)
    for frame, stage in ((1, 0), (7, 1), (15, 2), (27, 3), (34, 4), (40, 4)):
        pose_death(arm, stage)
        correct_ground_contact(arm, margin=0.01)
        key_current_pose(arm, frame)
    # Snappier recoil into a slower final settle.
    for fcurve in iter_action_fcurves(action):
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR" if ('mixamorig:Hips' in fcurve.data_path and fcurve.data_path.endswith('location')) else "BEZIER"
    return bake_ground_corrections(arm, action, 1, 40, margin=0.01)


def set_metadata(scene, arm, selected_count):
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 33
    scene.frame_set(1)
    arm["asset_name"] = "Character_3"
    arm["forward_axis"] = "-Y"
    arm["up_axis"] = "+Z"
    arm["animation_fps"] = 24
    arm["actions"] = ", ".join((ACTION_NAME, ARMED_WALK, ARMED_RUN, ARMED_DEATH))
    arm["loop_flags"] = f"{ACTION_NAME}: loop; {ARMED_WALK}: loop; {ARMED_RUN}: loop; {ARMED_DEATH}: one-shot"
    arm["root_motion_policy"] = "in-place"
    arm["asset_role"] = "Sauce It playable character 3; standalone asset"
    arm["weapon_animation_policy"] = "Imaginary two-hand sauce-canister carry; weapon geometry intentionally absent"
    arm["screen_left_arm_mapping"] = "mixamorig:Right*"
    arm["rig_revision"] = "screen-left arm mirror repair + head control + 3-bone tongue FK"
    arm["tongue_weighted_vertices"] = selected_count
    arm["motion_reference_notes"] = (
        "Official Splatoon 3 reference: readable weapon-ready locomotion; Luigi's Mansion 3: two-hand tool carry; "
        "official Fall Guys reference: bouncy stubby-limb comedy and broad stumble/fall. Original adaptation uses "
        "a stable imaginary sauce-canister grip, exaggerated in-place gait, staged collapse, and tongue overlap."
    )


def main():
    if not bpy.data.filepath:
        raise RuntimeError("Open Character_3.blend before running this script")
    arm = require_object(ARMATURE_NAME, "ARMATURE")
    mesh = require_object(MESH_NAME, "MESH")
    mirror_right_arm_from_left(arm)
    add_head_and_tongue_bones(arm)
    selected_count = weight_tongue(mesh)
    tongue_action = build_tongue_action(arm)
    walk_action = build_armed_walk(arm)
    run_action = build_armed_run(arm)
    death_action = build_armed_death(arm)
    set_metadata(bpy.context.scene, arm, selected_count)
    set_active(arm)
    arm.animation_data.action = walk_action
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 25
    bpy.context.scene.frame_set(1)
    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(RUNTIME_PATH),
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
    print(
        "CHARACTER_3_RIG_COMPLETE",
        {
            "actions": [tongue_action.name, walk_action.name, run_action.name, death_action.name],
            "ranges": {a.name: tuple(a.frame_range) for a in (tongue_action, walk_action, run_action, death_action)},
            "tongue_vertices": selected_count,
        },
    )
    print("CHARACTER_3_EXPORTED", RUNTIME_PATH)


if __name__ == "__main__":
    main()
