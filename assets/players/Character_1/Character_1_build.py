"""Build weapon-carry locomotion and death actions for Character_1.

Motion reference notes (consulted 2026-10-05):
- Nintendo's official Splatoon 3 launch/announcement footage and weapon guide were
  used for the broad gameplay idea: the weapon remains a readable forward-facing
  mass while the character's body supplies the bounce, lean, and lateral energy.
- Observed principle: compact upper-body weapon carry, clear forward lean, fast
  high-mobility lower-body rhythm. Professional adaptation: this chef's extremely
  round proportions need larger hip shifts, shorter strides, and a comic wobble.
- Death choreography is original: a sharp recoil, two-stage knee buckle, then a
  diagonal face-first collapse while the empty weapon-holding pose remains intact.

The animation is intentionally in-place. A rigid low-poly sauce canister is fitted
to the authored two-handed grip and weighted to the hips so both hands, the prop,
and the body use the same stable attachment space through every action.
"""

import bpy
import math
from pathlib import Path
from mathutils import Euler, Matrix, Vector


ASSET = "Character_1"
RIG_NAME = "cartoon chef 3d model"
PROP_COLLECTION = "Character_1_SauceContainer"
FPS = 24
HERE = Path(__file__).resolve().parent
BLEND_PATH = HERE / "Character_1.blend"
RUNTIME_PATH = HERE / "Character_1.glb"
MUZZLE_BONE = "Character_1_SauceMuzzle"

ACTION_SPECS = {
    "Weapon_Walk": {"range": (1, 25), "playback": (1, 24), "loop": True},
    "Weapon_Run": {"range": (1, 17), "playback": (1, 16), "loop": True},
    "Weapon_Death": {"range": (1, 48), "playback": (1, 48), "loop": False},
}

CONTROLLED = [
    "mixamorig:Hips",
    "mixamorig:Spine",
    "mixamorig:Spine1",
    "mixamorig:Spine2",
    "mixamorig:Neck",
    "mixamorig:Head",
    "mixamorig:LeftShoulder",
    "mixamorig:LeftArm",
    "mixamorig:LeftForeArm",
    "mixamorig:LeftHand",
    "mixamorig:RightShoulder",
    "mixamorig:RightArm",
    "mixamorig:RightForeArm",
    "mixamorig:RightHand",
    "mixamorig:LeftUpLeg",
    "mixamorig:LeftLeg",
    "mixamorig:LeftFoot",
    "mixamorig:LeftToeBase",
    "mixamorig:RightUpLeg",
    "mixamorig:RightLeg",
    "mixamorig:RightFoot",
    "mixamorig:RightToeBase",
]

FINGER_ROOTS = [
    "mixamorig:LeftHandIndex1", "mixamorig:LeftHandPinky1", "mixamorig:LeftHandThumb1",
    "mixamorig:RightHandIndex1", "mixamorig:RightHandPinky1", "mixamorig:RightHandThumb1",
]


def rad3(values):
    return tuple(math.radians(v) for v in values)


def get_material(name, color, metallic=0.0, roughness=0.55):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return material


def finish_prop_part(obj, rig, collection, material):
    """Freeze primitive transforms, then rigidly weight the part to the hips."""
    obj.name = f"{ASSET}_SauceContainer_{obj.name}"
    if obj.data:
        obj.data.name = f"{obj.name}_Mesh"
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)

    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.matrix_parent_inverse = Matrix.Identity(4)

    group = obj.vertex_groups.new(name="mixamorig:Hips")
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Character_1_SauceContainer_Rigid", type="ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = False
    obj["asset"] = ASSET
    obj["attachment_bone"] = "mixamorig:Hips"
    obj["attachment_mode"] = "rigid_weight"
    return obj


def ensure_muzzle_bone(rig):
    """Add a non-deforming gameplay socket that inherits the animated hips."""
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bone = rig.data.edit_bones.get(MUZZLE_BONE)
    if bone is None:
        bone = rig.data.edit_bones.new(MUZZLE_BONE)
    bone.head = (0.0, -0.522, 0.455)
    bone.tail = (0.0, -0.622, 0.455)
    bone.parent = rig.data.edit_bones.get("mixamorig:Hips")
    bone.use_connect = False
    bone.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")


def build_sauce_container(rig):
    """Create the game sauce canister around the authored two-hand grip volume."""
    old_collection = bpy.data.collections.get(PROP_COLLECTION)
    if old_collection:
        for obj in list(old_collection.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old_collection)
    collection = bpy.data.collections.new(PROP_COLLECTION)
    bpy.context.scene.collection.children.link(collection)

    red = get_material(f"{ASSET}_Sauce_Red", (0.56, 0.018, 0.012), 0.05, 0.42)
    dark = get_material(f"{ASSET}_Sauce_Grip", (0.035, 0.042, 0.048), 0.12, 0.5)
    cream = get_material(f"{ASSET}_Sauce_Label", (0.92, 0.72, 0.31), 0.0, 0.6)
    glass = get_material(f"{ASSET}_Sauce_Gauge", (0.45, 0.82, 0.9), 0.05, 0.25)

    parts = []

    def cylinder(name, location, radius, depth, rotation, material, vertices=12):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=vertices, radius=radius, depth=depth,
            location=location, rotation=rotation,
        )
        obj = bpy.context.object
        obj.name = name
        parts.append(finish_prop_part(obj, rig, collection, material))
        return obj

    def sphere(name, location, scale, material, subdivisions=2):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
        obj = bpy.context.object
        obj.name = name
        obj.scale = scale
        parts.append(finish_prop_part(obj, rig, collection, material))
        return obj

    def cube(name, location, scale, material, bevel=0.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
        obj = bpy.context.object
        obj.name = name
        obj.scale = scale
        if bevel:
            modifier = obj.modifiers.new(name="SoftCorners", type="BEVEL")
            modifier.width = bevel
            modifier.segments = 1
        parts.append(finish_prop_part(obj, rig, collection, material))
        return obj

    # The body sits just forward of the torso. Its two end grips are centered on
    # the same +/-X hand targets used by solve_two_hand_carry().
    axis_x = (0.0, math.radians(90.0), 0.0)
    axis_y = (math.radians(90.0), 0.0, 0.0)
    # Keep the tank clear of the chef's unusually deep belly during the strongest
    # run lean; rearward grip stalks bridge back to the authored palm targets.
    body_y = -0.295
    body_z = 0.455
    cylinder("Body", (0.0, body_y, body_z), 0.078, 0.238, axis_x, red, 14)
    sphere("EndCap.L", (0.119, body_y, body_z), (0.036, 0.076, 0.076), red)
    sphere("EndCap.R", (-0.119, body_y, body_z), (0.036, 0.076, 0.076), red)
    cylinder("Band.L", (0.095, body_y, body_z), 0.081, 0.014, axis_x, cream, 14)
    cylinder("Band.R", (-0.095, body_y, body_z), 0.081, 0.014, axis_x, cream, 14)

    # Chunky side grips meet the two palm targets at x +/-0.15, y -0.12.
    for side, x in (("L", 0.151), ("R", -0.151)):
        cylinder(f"Grip.{side}", (x, -0.132, body_z), 0.034, 0.064, axis_x, dark, 10)
        sphere(f"GripStop.{side}", (x + (0.035 if side == "L" else -0.035), -0.132, body_z),
               (0.012, 0.043, 0.043), cream, 1)
        cylinder(f"GripStalk.{side}", (x, -0.215, body_z), 0.021, 0.15, axis_y, dark, 8)

    # Forward-facing outlet makes the canister's gameplay direction unmistakable.
    cylinder("NozzleBase", (0.0, -0.365, body_z), 0.033, 0.075, axis_y, dark, 10)
    bpy.ops.mesh.primitive_cone_add(
        vertices=10, radius1=0.031, radius2=0.015, depth=0.09,
        location=(0.0, -0.445, body_z), rotation=axis_y,
    )
    nozzle = bpy.context.object
    nozzle.name = "Nozzle"
    parts.append(finish_prop_part(nozzle, rig, collection, cream))
    cylinder("NozzleTip", (0.0, -0.502, body_z), 0.012, 0.035, axis_y, dark, 10)

    # Readable service details: fill cap, label plate, and raised pressure gauge.
    cylinder("FillNeck", (0.0, body_y, 0.535), 0.03, 0.028, (0.0, 0.0, 0.0), dark, 10)
    cylinder("FillCap", (0.0, body_y, 0.558), 0.041, 0.022, (0.0, 0.0, 0.0), cream, 10)
    cube("Label", (0.0, -0.371, body_z), (0.068, 0.008, 0.038), cream, bevel=0.006)
    cylinder("Gauge", (0.0, -0.383, body_z), 0.022, 0.009, axis_y, glass, 12)

    collection["asset"] = ASSET
    collection["prop_type"] = "two-handed sauce canister"
    collection["forward_axis"] = "-Y"
    collection["primary_attachment_bone"] = "mixamorig:Hips"
    collection["left_grip_local"] = (0.151, -0.132, body_z)
    collection["right_grip_local"] = (-0.151, -0.132, body_z)
    collection["muzzle_local"] = (0.0, -0.522, body_z)
    return parts


def base_pose():
    """Two-handed imaginary sauce-sprayer carry pose."""
    return {
        "mixamorig:Hips": {"loc": (0.0, 0.0, 0.001), "rot": (0.0, 0.0, 0.0)},
        "mixamorig:Spine": {"rot": (4.0, 0.0, 0.0)},
        "mixamorig:Spine1": {"rot": (4.0, 0.0, 0.0)},
        "mixamorig:Spine2": {"rot": (6.0, 0.0, 0.0)},
        "mixamorig:Neck": {"rot": (-4.0, 0.0, 0.0)},
        "mixamorig:Head": {"rot": (-3.0, 0.0, 0.0)},
        "mixamorig:LeftShoulder": {"rot": (0.0, -8.0, -8.0)},
        "mixamorig:LeftArm": {"rot": (-12.0, 18.0, -72.0)},
        "mixamorig:LeftForeArm": {"rot": (0.0, -12.0, -64.0)},
        "mixamorig:LeftHand": {"rot": (5.0, -8.0, -8.0)},
        "mixamorig:RightShoulder": {"rot": (0.0, 8.0, 8.0)},
        "mixamorig:RightArm": {"rot": (-12.0, -18.0, 72.0)},
        "mixamorig:RightForeArm": {"rot": (0.0, 12.0, 64.0)},
        "mixamorig:RightHand": {"rot": (5.0, 8.0, 8.0)},
        "mixamorig:LeftUpLeg": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:LeftLeg": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:LeftFoot": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:LeftToeBase": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:RightUpLeg": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:RightLeg": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:RightFoot": {"rot": (0.0, 0.0, 0.0)},
        "mixamorig:RightToeBase": {"rot": (0.0, 0.0, 0.0)},
    }


def merged_pose(overrides=None):
    pose = base_pose()
    if overrides:
        for bone_name, values in overrides.items():
            pose.setdefault(bone_name, {}).update(values)
    return pose


def clear_pose(rig):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = "XYZ"


def apply_world_delta(rig, bone, values):
    """Apply an armature-space rotation and offset independent of bone roll."""
    rest = bone.bone.matrix_local
    if bone.parent:
        parent_rest_inv = bone.parent.bone.matrix_local.inverted()
        base = bone.parent.matrix @ parent_rest_inv @ rest
    else:
        base = rest.copy()

    desired = base.copy()
    if "rot" in values:
        delta = Euler(rad3(values["rot"]), "XYZ").to_matrix()
        desired_rot = delta @ base.to_3x3()
        for row in range(3):
            for col in range(3):
                desired[row][col] = desired_rot[row][col]
    if "loc" in values:
        desired.translation = base.translation + Vector(values["loc"])
    bone.matrix = desired
    if "scale" in values:
        bone.scale = values["scale"]


def solve_two_hand_carry(rig):
    """Aim both two-bone arm chains at stable imaginary-weapon grip points.

    The source rig's arm bone rolls are asymmetric, so direct Euler mirroring does
    not produce a reliable two-handed carry.  This small analytic IK solve writes
    the final FK rotations into the action and leaves no live constraints behind.
    """
    hips = rig.pose.bones["mixamorig:Hips"]
    hips_rest = rig.data.bones["mixamorig:Hips"].matrix_local
    hips_delta = hips.matrix @ hips_rest.inverted()

    grip_rest = {
        "Left": Vector((0.150, -0.120, 0.455)),
        "Right": Vector((-0.150, -0.120, 0.455)),
    }

    for side in ("Left", "Right"):
        upper = rig.pose.bones[f"mixamorig:{side}Arm"]
        fore = rig.pose.bones[f"mixamorig:{side}ForeArm"]
        hand = rig.pose.bones[f"mixamorig:{side}Hand"]
        shoulder = upper.head.copy()
        target = hips_delta @ grip_rest[side]
        to_target = target - shoulder
        distance = max(to_target.length, 1e-6)
        direction = to_target.normalized()
        l1 = upper.bone.length
        l2 = fore.bone.length
        solved_distance = min(distance, (l1 + l2) * 0.995)
        along = (l1 * l1 - l2 * l2 + solved_distance * solved_distance) / (2.0 * solved_distance)
        height_sq = max(l1 * l1 - along * along, 0.0)
        height = math.sqrt(height_sq)

        outward = Vector((1.0, 0.0, 0.0)) if side == "Left" else Vector((-1.0, 0.0, 0.0))
        bend = outward - direction * outward.dot(direction)
        if bend.length < 1e-5:
            bend = Vector((0.0, 0.0, 1.0))
        bend.normalize()
        elbow = shoulder + direction * along + bend * height

        upper_dir = (elbow - shoulder).normalized()
        upper_matrix = upper_dir.to_track_quat("Y", "Z").to_matrix().to_4x4()
        upper_matrix.translation = shoulder
        upper.matrix = upper_matrix
        bpy.context.view_layer.update()

        fore_head = fore.head.copy()
        fore_dir = (target - fore_head).normalized()
        fore_matrix = fore_dir.to_track_quat("Y", "Z").to_matrix().to_4x4()
        fore_matrix.translation = fore_head
        fore.matrix = fore_matrix
        bpy.context.view_layer.update()

        hand_head = hand.head.copy()
        # Palms point forward with a slight inward cant around the invisible bottle.
        hand_dir = Vector((-0.10 if side == "Left" else 0.10, -1.0, -0.05)).normalized()
        hand_matrix = hand_dir.to_track_quat("Y", "Z").to_matrix().to_4x4()
        hand_matrix.translation = hand_head
        hand.matrix = hand_matrix
        bpy.context.view_layer.update()


def apply_and_key(rig, action, frame, pose):
    rig.animation_data.action = action
    bpy.context.scene.frame_set(frame)
    clear_pose(rig)
    for bone_name, values in pose.items():
        bone = rig.pose.bones.get(bone_name)
        if not bone:
            continue
        apply_world_delta(rig, bone, values)

    bpy.context.view_layer.update()
    solve_two_hand_carry(rig)

    # Close the mitten-like hands around an imaginary grip without a weapon mesh.
    for finger_name in FINGER_ROOTS:
        finger = rig.pose.bones.get(finger_name)
        if not finger:
            continue
        side = -1.0 if "Left" in finger_name else 1.0
        curl = 24.0 if "Thumb" not in finger_name else 16.0
        finger.rotation_mode = "XYZ"
        finger.rotation_euler = rad3((0.0, side * curl, side * 8.0))

    for bone_name in CONTROLLED + FINGER_ROOTS:
        bone = rig.pose.bones.get(bone_name)
        if not bone:
            continue
        # Quaternion channels avoid Euler wrap/flips between authored grip poses;
        # this is especially important for the two arms around a rigid prop.
        bone.rotation_mode = "QUATERNION"
        bone.keyframe_insert("location", frame=frame, group=bone_name)
        bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
        bone.keyframe_insert("scale", frame=frame, group=bone_name)


def bake_two_hand_contact(rig, action, start, end):
    """Bake the arm solve each frame so neither palm drifts off the rigid grips."""
    rig.animation_data.action = action
    arm_bones = [
        f"mixamorig:{side}{part}"
        for side in ("Left", "Right")
        for part in ("Arm", "ForeArm", "Hand")
    ]
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        solve_two_hand_carry(rig)
        for bone_name in arm_bones:
            bone = rig.pose.bones[bone_name]
            bone.rotation_mode = "QUATERNION"
            bone.keyframe_insert("location", frame=frame, group=bone_name)
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone_name)
            bone.keyframe_insert("scale", frame=frame, group=bone_name)


def make_action(rig, name):
    old = bpy.data.actions.get(name)
    if old:
        if rig.animation_data and rig.animation_data.action == old:
            rig.animation_data.action = None
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    spec = ACTION_SPECS[name]
    action.use_frame_range = True
    action.frame_start, action.frame_end = spec["range"]
    action["asset"] = ASSET
    action["fps"] = FPS
    action["loop"] = spec["loop"]
    action["playback_start"] = spec["playback"][0]
    action["playback_end"] = spec["playback"][1]
    action["root_motion"] = False
    action["weapon_mesh_included"] = True
    action["carry_style"] = "two-handed sauce canister"
    action["weapon_attachment_bone"] = "mixamorig:Hips"
    rig.animation_data.action = action
    return action


def set_interpolation(action, interpolation="BEZIER"):
    # Blender 5 layered actions expose fcurves through channelbags.
    curves = action_fcurves(action)
    seen = set()
    for curve in curves:
        if curve.as_pointer() in seen:
            continue
        seen.add(curve.as_pointer())
        for key in curve.keyframe_points:
            key.interpolation = interpolation
            if interpolation == "BEZIER":
                key.handle_left_type = "AUTO_CLAMPED"
                key.handle_right_type = "AUTO_CLAMPED"


def action_fcurves(action):
    curves = []
    if hasattr(action, "fcurves"):
        curves.extend(action.fcurves)
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    curves.extend(bag.fcurves)
    return curves


def force_exact_loop(action, start, end):
    """Copy every keyed channel value at start onto the duplicate loop frame."""
    for curve in action_fcurves(action):
        start_key = next((key for key in curve.keyframe_points if abs(key.co.x - start) < 1e-4), None)
        end_key = next((key for key in curve.keyframe_points if abs(key.co.x - end) < 1e-4), None)
        if start_key and end_key:
            end_key.co.y = start_key.co.y
            end_key.handle_left_type = "AUTO_CLAMPED"
            end_key.handle_right_type = "AUTO_CLAMPED"
        curve.update()


def build_walk(rig):
    action = make_action(rig, "Weapon_Walk")
    poses = {
        1: {
            "mixamorig:Hips": {"loc": (0.035, 0.0, 0.008), "rot": (1.0, -2.0, -5.0)},
            "mixamorig:Spine2": {"rot": (7.0, 0.0, 5.0)},
            "mixamorig:Head": {"rot": (-4.0, 0.0, -4.0)},
            "mixamorig:LeftUpLeg": {"rot": (-26.0, 2.0, 2.0)},
            "mixamorig:LeftLeg": {"rot": (8.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (15.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (23.0, -2.0, -2.0)},
            "mixamorig:RightLeg": {"rot": (18.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-10.0, 0.0, 0.0)},
        },
        7: {
            "mixamorig:Hips": {"loc": (-0.018, 0.0, 0.035), "rot": (-1.0, 2.0, 2.0)},
            "mixamorig:Spine2": {"rot": (5.0, 0.0, -2.0)},
            "mixamorig:Head": {"rot": (-2.0, 0.0, 2.0)},
            "mixamorig:LeftUpLeg": {"rot": (8.0, 1.0, 0.0)},
            "mixamorig:LeftLeg": {"rot": (30.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-16.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (-8.0, -1.0, 0.0)},
            "mixamorig:RightLeg": {"rot": (42.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (18.0, 0.0, 0.0)},
        },
        13: {
            "mixamorig:Hips": {"loc": (-0.035, 0.0, 0.008), "rot": (1.0, 2.0, 5.0)},
            "mixamorig:Spine2": {"rot": (7.0, 0.0, -5.0)},
            "mixamorig:Head": {"rot": (-4.0, 0.0, 4.0)},
            "mixamorig:LeftUpLeg": {"rot": (23.0, 2.0, 2.0)},
            "mixamorig:LeftLeg": {"rot": (18.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-10.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (-26.0, -2.0, -2.0)},
            "mixamorig:RightLeg": {"rot": (8.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (15.0, 0.0, 0.0)},
        },
        19: {
            "mixamorig:Hips": {"loc": (0.018, 0.0, 0.035), "rot": (-1.0, -2.0, -2.0)},
            "mixamorig:Spine2": {"rot": (5.0, 0.0, 2.0)},
            "mixamorig:Head": {"rot": (-2.0, 0.0, -2.0)},
            "mixamorig:LeftUpLeg": {"rot": (-8.0, 1.0, 0.0)},
            "mixamorig:LeftLeg": {"rot": (42.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (18.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (8.0, -1.0, 0.0)},
            "mixamorig:RightLeg": {"rot": (30.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-16.0, 0.0, 0.0)},
        },
        25: {},
    }
    for frame, overrides in poses.items():
        if frame == 25:
            overrides = poses[1]
        apply_and_key(rig, action, frame, merged_pose(overrides))
    bake_two_hand_contact(rig, action, 1, 25)
    set_interpolation(action, "BEZIER")
    force_exact_loop(action, 1, 25)
    return action


def build_run(rig):
    action = make_action(rig, "Weapon_Run")
    run_base = {
        "mixamorig:Spine": {"rot": (10.0, 0.0, 0.0)},
        "mixamorig:Spine1": {"rot": (10.0, 0.0, 0.0)},
        "mixamorig:Spine2": {"rot": (14.0, 0.0, 0.0)},
        "mixamorig:Neck": {"rot": (-10.0, 0.0, 0.0)},
        "mixamorig:Head": {"rot": (-8.0, 0.0, 0.0)},
        "mixamorig:LeftArm": {"rot": (-12.0, 18.0, -78.0)},
        "mixamorig:LeftForeArm": {"rot": (0.0, -12.0, -70.0)},
        "mixamorig:RightArm": {"rot": (-12.0, -18.0, 78.0)},
        "mixamorig:RightForeArm": {"rot": (0.0, 12.0, 70.0)},
    }

    def rp(extra):
        merged = dict(run_base)
        merged.update(extra)
        return merged_pose(merged)

    poses = {
        1: {
            "mixamorig:Hips": {"loc": (0.04, 0.0, 0.0), "rot": (6.0, -3.0, -7.0)},
            "mixamorig:Spine2": {"rot": (16.0, 0.0, 6.0)},
            "mixamorig:LeftUpLeg": {"rot": (-38.0, 4.0, 3.0)},
            "mixamorig:LeftLeg": {"rot": (12.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (18.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (36.0, -4.0, -3.0)},
            "mixamorig:RightLeg": {"rot": (34.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-20.0, 0.0, 0.0)},
        },
        5: {
            "mixamorig:Hips": {"loc": (-0.02, -0.005, 0.075), "rot": (8.0, 2.0, 2.0)},
            "mixamorig:Spine2": {"rot": (13.0, 0.0, -2.0)},
            "mixamorig:LeftUpLeg": {"rot": (15.0, 1.0, 0.0)},
            "mixamorig:LeftLeg": {"rot": (48.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-18.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (-18.0, -1.0, 0.0)},
            "mixamorig:RightLeg": {"rot": (60.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (28.0, 0.0, 0.0)},
        },
        9: {
            "mixamorig:Hips": {"loc": (-0.04, 0.0, 0.0), "rot": (6.0, 3.0, 7.0)},
            "mixamorig:Spine2": {"rot": (16.0, 0.0, -6.0)},
            "mixamorig:LeftUpLeg": {"rot": (36.0, 4.0, 3.0)},
            "mixamorig:LeftLeg": {"rot": (34.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-20.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (-38.0, -4.0, -3.0)},
            "mixamorig:RightLeg": {"rot": (12.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (18.0, 0.0, 0.0)},
        },
        13: {
            "mixamorig:Hips": {"loc": (0.02, -0.005, 0.075), "rot": (8.0, -2.0, -2.0)},
            "mixamorig:Spine2": {"rot": (13.0, 0.0, 2.0)},
            "mixamorig:LeftUpLeg": {"rot": (-18.0, 1.0, 0.0)},
            "mixamorig:LeftLeg": {"rot": (60.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (28.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (15.0, -1.0, 0.0)},
            "mixamorig:RightLeg": {"rot": (48.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-18.0, 0.0, 0.0)},
        },
        17: {},
    }
    for frame, extra in poses.items():
        if frame == 17:
            extra = poses[1]
        apply_and_key(rig, action, frame, rp(extra))
    bake_two_hand_contact(rig, action, 1, 17)
    set_interpolation(action, "BEZIER")
    force_exact_loop(action, 1, 17)
    return action


def build_death(rig):
    action = make_action(rig, "Weapon_Death")
    poses = {
        1: {},
        7: {
            "mixamorig:Hips": {"loc": (0.0, 0.015, 0.012), "rot": (-7.0, 0.0, 0.0)},
            "mixamorig:Spine": {"rot": (-10.0, 0.0, 0.0)},
            "mixamorig:Spine1": {"rot": (-12.0, 0.0, 0.0)},
            "mixamorig:Spine2": {"rot": (-18.0, 0.0, 0.0)},
            "mixamorig:Head": {"rot": (-24.0, 0.0, 0.0)},
            "mixamorig:LeftArm": {"rot": (-18.0, 22.0, -80.0)},
            "mixamorig:RightArm": {"rot": (-18.0, -22.0, 80.0)},
        },
        13: {
            "mixamorig:Hips": {"loc": (0.055, -0.012, 0.027), "rot": (9.0, -8.0, -12.0)},
            "mixamorig:Spine": {"rot": (15.0, 0.0, 6.0)},
            "mixamorig:Spine1": {"rot": (18.0, 0.0, 8.0)},
            "mixamorig:Spine2": {"rot": (20.0, 0.0, 10.0)},
            "mixamorig:Neck": {"rot": (-18.0, 0.0, -10.0)},
            "mixamorig:Head": {"rot": (-20.0, 8.0, -16.0)},
            "mixamorig:LeftUpLeg": {"rot": (-18.0, 2.0, 4.0)},
            "mixamorig:LeftLeg": {"rot": (28.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (12.0, -2.0, -4.0)},
            "mixamorig:RightLeg": {"rot": (34.0, 0.0, 0.0)},
        },
        22: {
            "mixamorig:Hips": {"loc": (-0.07, -0.018, 0.02), "rot": (24.0, 7.0, 18.0)},
            "mixamorig:Spine": {"rot": (18.0, 0.0, -8.0)},
            "mixamorig:Spine1": {"rot": (20.0, 0.0, -10.0)},
            "mixamorig:Spine2": {"rot": (24.0, 0.0, -14.0)},
            "mixamorig:Neck": {"rot": (-14.0, 0.0, 12.0)},
            "mixamorig:Head": {"rot": (-10.0, -10.0, 22.0)},
            "mixamorig:LeftUpLeg": {"rot": (-8.0, 8.0, 10.0)},
            "mixamorig:LeftLeg": {"rot": (58.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (-2.0, -8.0, -8.0)},
            "mixamorig:RightLeg": {"rot": (62.0, 0.0, 0.0)},
        },
        30: {
            "mixamorig:Hips": {"loc": (-0.08, -0.055, 0.08), "rot": (58.0, 10.0, 24.0)},
            "mixamorig:Spine": {"rot": (12.0, 0.0, -8.0)},
            "mixamorig:Spine1": {"rot": (10.0, 0.0, -8.0)},
            "mixamorig:Spine2": {"rot": (8.0, 0.0, -10.0)},
            "mixamorig:Neck": {"rot": (16.0, 0.0, 8.0)},
            "mixamorig:Head": {"rot": (22.0, -8.0, 18.0)},
            "mixamorig:LeftUpLeg": {"rot": (-20.0, 12.0, 14.0)},
            "mixamorig:LeftLeg": {"rot": (74.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-22.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (10.0, -10.0, -12.0)},
            "mixamorig:RightLeg": {"rot": (68.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-16.0, 0.0, 0.0)},
        },
        38: {
            "mixamorig:Hips": {"loc": (-0.09, -0.09, 0.108), "rot": (82.0, 12.0, 27.0)},
            "mixamorig:Spine": {"rot": (6.0, 0.0, -6.0)},
            "mixamorig:Spine1": {"rot": (4.0, 0.0, -6.0)},
            "mixamorig:Spine2": {"rot": (2.0, 0.0, -8.0)},
            "mixamorig:Neck": {"rot": (24.0, 0.0, 6.0)},
            "mixamorig:Head": {"rot": (30.0, -10.0, 20.0)},
            "mixamorig:LeftUpLeg": {"rot": (-28.0, 14.0, 18.0)},
            "mixamorig:LeftLeg": {"rot": (86.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-28.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (16.0, -12.0, -14.0)},
            "mixamorig:RightLeg": {"rot": (72.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-20.0, 0.0, 0.0)},
            "mixamorig:LeftArm": {"rot": (-8.0, 28.0, -82.0)},
            "mixamorig:RightArm": {"rot": (-8.0, -28.0, 82.0)},
        },
        44: {
            "mixamorig:Hips": {"loc": (-0.09, -0.095, 0.103), "rot": (86.0, 12.0, 28.0)},
            "mixamorig:Spine": {"rot": (4.0, 0.0, -5.0)},
            "mixamorig:Spine1": {"rot": (2.0, 0.0, -5.0)},
            "mixamorig:Spine2": {"rot": (0.0, 0.0, -7.0)},
            "mixamorig:Neck": {"rot": (27.0, 0.0, 5.0)},
            "mixamorig:Head": {"rot": (34.0, -10.0, 20.0)},
            "mixamorig:LeftUpLeg": {"rot": (-30.0, 14.0, 18.0)},
            "mixamorig:LeftLeg": {"rot": (88.0, 0.0, 0.0)},
            "mixamorig:LeftFoot": {"rot": (-30.0, 0.0, 0.0)},
            "mixamorig:RightUpLeg": {"rot": (18.0, -12.0, -14.0)},
            "mixamorig:RightLeg": {"rot": (74.0, 0.0, 0.0)},
            "mixamorig:RightFoot": {"rot": (-22.0, 0.0, 0.0)},
            "mixamorig:LeftArm": {"rot": (-6.0, 30.0, -84.0)},
            "mixamorig:RightArm": {"rot": (-6.0, -30.0, 84.0)},
        },
        48: {},
    }
    poses[48] = poses[44]
    for frame, overrides in poses.items():
        apply_and_key(rig, action, frame, merged_pose(overrides))
    bake_two_hand_contact(rig, action, 1, 48)
    set_interpolation(action, "BEZIER")
    return action


def main():
    if Path(bpy.data.filepath).resolve() != BLEND_PATH.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(BLEND_PATH), load_ui=False)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    rig = bpy.data.objects.get(RIG_NAME)
    if not rig or rig.type != "ARMATURE":
        raise RuntimeError(f"Expected armature '{RIG_NAME}' was not found")
    missing = [name for name in CONTROLLED if name not in rig.pose.bones]
    if missing:
        raise RuntimeError(f"Required bones are missing: {missing}")

    rig.animation_data_create()
    ensure_muzzle_bone(rig)
    for track in list(rig.animation_data.nla_tracks):
        if track.name.startswith("Character_1_"):
            rig.animation_data.nla_tracks.remove(track)

    walk = build_walk(rig)
    build_run(rig)
    build_death(rig)
    build_sauce_container(rig)

    rig["asset_name"] = ASSET
    rig["forward_axis"] = "-Y"
    rig["up_axis"] = "+Z"
    rig["animation_fps"] = FPS
    rig["action_list"] = "Weapon_Walk, Weapon_Run, Weapon_Death"
    rig["loop_actions"] = "Weapon_Walk, Weapon_Run"
    rig["one_shot_actions"] = "Weapon_Death"
    rig["root_motion"] = False
    rig["weapon_mesh_included"] = True
    rig["weapon_pose_note"] = "Two-handed sauce canister fitted to both grip targets"
    rig["weapon_attachment_bone"] = "mixamorig:Hips"
    rig["motion_reference"] = "Official Nintendo Splatoon 3 footage/weapon guide; original adapted performance"

    scene["Character_1_forward_axis"] = "-Y"
    scene["Character_1_action_list"] = "Weapon_Walk, Weapon_Run, Weapon_Death"
    scene["Character_1_root_motion"] = False
    scene["Character_1_weapon_mesh_included"] = True

    # Predictable inspection state: walk action on its first frame.
    rig.animation_data.action = walk
    scene.frame_start, scene.frame_end = ACTION_SPECS["Weapon_Walk"]["range"]
    scene.frame_set(1)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)

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
    print("CHARACTER_1_BUILD_OK")
    print("CHARACTER_1_EXPORTED", RUNTIME_PATH)


if __name__ == "__main__":
    main()
