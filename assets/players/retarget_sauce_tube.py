"""Fit the production sauce tube to one playable character and rebake both arms.

This post-process is idempotent.  It removes the old Character 1 canister (when
present), embeds the shared production tube, adds socket/muzzle bones, bakes a
two-bone solve on every action frame, saves the .blend, and exports the runtime
GLB.  It is intentionally separate from gameplay: capsule size and movement are
not changed.

Run with Blender 5.2 and one character number after ``--``:
  blender --background --factory-startup --python retarget_sauce_tube.py -- 1
"""

from pathlib import Path
import math
import sys

import bpy
from mathutils import Matrix, Vector


HERE = Path(__file__).resolve().parent
TUBE_BLEND = HERE.parent / "props" / "Production_SauceTube_S1" / "Production_SauceTube_S1.blend"
SOCKET = "SauceTubeSocket"
MUZZLE = "SauceTubeMuzzle"

# Coordinates are in each armature's local space.  Character 1 and 3 retain
# their imported x10 armature object scale, hence their smaller local values.
CONFIG = {
    1: dict(rig="cartoon chef 3d model", scale=0.38, grip_half=0.09,
            carry_base=(0.0, -0.29, 0.37)),
    2: dict(rig="Character_2_Rig", scale=3.50, grip_half=0.84,
            carry_base=(0.0, -2.80, 4.55)),
    3: dict(rig="chef character 3d model", scale=0.38, grip_half=0.09,
            carry_base=(0.0, -0.28, 0.36)),
    4: dict(rig="Character_4_Rig", scale=2.30, grip_half=0.55,
            carry_base=(0.0, -2.80, 2.25)),
}


def action_fcurves(action):
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            if hasattr(strip, "channelbags"):
                for channelbag in strip.channelbags:
                    curves.extend(channelbag.fcurves)
    return curves


def remove_old_weapon(character):
    prefixes = (
        "Character_1_SauceContainer_",
        "SauceTube_",
        f"Character_{character}_SauceTube",
        f"Character_{character}_SauceFill",
    )
    for obj in list(bpy.data.objects):
        if any(obj.name.startswith(prefix) for prefix in prefixes):
            bpy.data.objects.remove(obj, do_unlink=True)
    old_collection = bpy.data.collections.get("Character_1_SauceContainer")
    if old_collection is not None:
        bpy.data.collections.remove(old_collection)
    generated_collection = bpy.data.collections.get(f"Character_{character}_SauceTube")
    if generated_collection is not None:
        bpy.data.collections.remove(generated_collection)


def ensure_bones(rig, config):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="OBJECT") if rig.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    hips = edit.get("mixamorig:Hips")
    right_hand = edit.get("mixamorig:RightHand")
    if hips is None or right_hand is None:
        raise RuntimeError("Required hips/right-hand bones are missing")
    right_grip = right_hand.head.copy()
    base = right_grip + Vector((config["grip_half"], 0.0, 0.0))
    unit = config["scale"]
    socket = edit.get(SOCKET) or edit.new(SOCKET)
    socket.head = base
    socket.tail = base + Vector((0.0, -max(0.12 * unit, 0.012), 0.0))
    # The socket is keyed to the right palm on every animation frame.  Keeping
    # its forward orientation stable prevents a hand-roll from steering the
    # long tube through the character's chest.
    socket.parent = hips
    socket.use_connect = False
    socket.use_inherit_rotation = True
    socket.inherit_scale = "NONE"
    socket.use_deform = True
    muzzle = edit.get(MUZZLE) or edit.new(MUZZLE)
    muzzle.head = base + Vector((0.0, -1.2 * unit, 0.0))
    muzzle.tail = muzzle.head + Vector((0.0, -max(0.08 * unit, 0.008), 0.0))
    muzzle.parent = socket
    muzzle.use_connect = False
    muzzle.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return base, right_grip, base + Vector((config["grip_half"], 0.0, 0.0))


def append_tube(rig, character, config, base):
    if not TUBE_BLEND.exists():
        raise RuntimeError(f"Build the shared tube first: {TUBE_BLEND}")
    with bpy.data.libraries.load(str(TUBE_BLEND), link=False) as (source, target):
        target.objects = [name for name in ("SauceTube_Bottle", "SauceFill") if name in source.objects]
    if len(target.objects) != 2:
        raise RuntimeError("Shared tube blend is missing its bottle or SauceFill")

    collection = bpy.data.collections.get(f"Character_{character}_SauceTube")
    if collection is None:
        collection = bpy.data.collections.new(f"Character_{character}_SauceTube")
        bpy.context.scene.collection.children.link(collection)
    rotation = Matrix.Rotation(math.radians(90.0), 4, "X")
    scale = config["scale"]
    for obj in target.objects:
        collection.objects.link(obj)
        is_fill = obj.name == "SauceFill"
        obj.name = f"Character_{character}_{'SauceFill' if is_fill else 'SauceTube_Bottle'}"
        obj.data = obj.data.copy()
        # Apply the complete source object transform before fitting it to the
        # character; then orient the upright +Z tube down authored -Y.
        source_matrix = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            source_point = source_matrix @ vertex.co
            vertex.co = base + rotation @ (source_point * scale)
        obj.matrix_world = Matrix.Identity(4)
        # Match the existing skinned character mesh: shared armature space,
        # armature parent, and a rigid one-bone vertex group.  Character 1 and
        # 3 retain an authored x10 armature-object scale, so omitting the parent
        # made their bottle one tenth of the intended size and left it near the
        # origin instead of between the hands.
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        group = obj.vertex_groups.new(name=SOCKET)
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        modifier = obj.modifiers.new(name=f"Character_{character}_SauceTube_Rigid", type="ARMATURE")
        modifier.object = rig
        modifier.use_vertex_groups = True
        modifier.use_bone_envelopes = False
        obj["sauce_fill_axis_godot"] = "+Z" if is_fill else ""
        obj["sauce_fill_anchor"] = "base"


def place_socket(rig, base):
    socket = rig.pose.bones[SOCKET]
    matrix = Vector((0.0, -1.0, 0.0)).to_track_quat("Y", "Z").to_matrix().to_4x4()
    matrix.translation = base
    socket.matrix = matrix
    bpy.context.view_layer.update()


def solve_arm(rig, side, target):
    upper = rig.pose.bones[f"mixamorig:{side}Arm"]
    fore = rig.pose.bones[f"mixamorig:{side}ForeArm"]
    hand = rig.pose.bones[f"mixamorig:{side}Hand"]
    upper.scale = Vector((1.0, 1.0, 1.0))
    fore.scale = Vector((1.0, 1.0, 1.0))
    hand.scale = Vector((1.0, 1.0, 1.0))
    bpy.context.view_layer.update()
    shoulder = upper.head.copy()
    toward = target - shoulder
    distance = max(toward.length, 1e-6)
    direction = toward.normalized()
    length_a = upper.bone.length
    length_b = fore.bone.length
    stretch = max(1.0, distance / max((length_a + length_b) * 0.992, 1e-6))
    if stretch > 2.25:
        return False
    length_a *= stretch
    length_b *= stretch
    solved = min(distance, (length_a + length_b) * 0.992)
    along = (length_a * length_a - length_b * length_b + solved * solved) / (2.0 * solved)
    height = math.sqrt(max(length_a * length_a - along * along, 0.0))
    outward = Vector((1.0, 0.0, 0.0)) if side == "Left" else Vector((-1.0, 0.0, 0.0))
    bend = outward - direction * outward.dot(direction)
    if bend.length < 1e-5:
        bend = Vector((0.0, 0.0, 1.0))
    bend.normalize()
    elbow = shoulder + direction * along + bend * height

    upper_matrix = (elbow - shoulder).normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()
    upper_matrix.translation = shoulder
    upper.matrix = upper_matrix
    upper.scale.y = stretch
    bpy.context.view_layer.update()
    fore_head = fore.head.copy()
    fore_matrix = (target - fore_head).normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()
    fore_matrix.translation = fore_head
    fore.matrix = fore_matrix
    required_forearm = (target - fore_head).length / max(fore.bone.length, 1e-6)
    if required_forearm > 2.25:
        return False
    if required_forearm > 1.0:
        fore.scale.y = required_forearm
    bpy.context.view_layer.update()
    hand_head = hand.head.copy()
    palm = Vector((-0.08 if side == "Left" else 0.08, -1.0, -0.04)).normalized()
    hand_matrix = palm.to_track_quat("Y", "Z").to_matrix().to_4x4()
    hand_matrix.translation = hand_head
    hand.matrix = hand_matrix
    bpy.context.view_layer.update()
    return True


def bake_actions(rig, config):
    if rig.animation_data is None:
        rig.animation_data_create()
    left_names = [f"mixamorig:Left{part}" for part in ("Arm", "ForeArm", "Hand")]
    right_names = [f"mixamorig:Right{part}" for part in ("Arm", "ForeArm", "Hand")]
    arm_names = left_names + right_names
    actions = [action for action in bpy.data.actions if any(
        token in action.name.lower() for token in ("walk", "run", "death")
    )]
    for action in actions:
        rig.animation_data.action = action
        start, end = (int(round(value)) for value in action.frame_range)
        supported = 0
        death = "death" in action.name.lower()
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            if death:
                right_hand = rig.pose.bones["mixamorig:RightHand"]
                base = right_hand.head.copy() + Vector((config["grip_half"], 0.0, 0.0))
                place_socket(rig, base)
                left_ok = solve_arm(
                    rig, "Left", base + Vector((config["grip_half"], 0.0, 0.0)))
                names_to_key = left_names + [SOCKET]
            else:
                hips = rig.pose.bones["mixamorig:Hips"]
                hips_rest = rig.data.bones["mixamorig:Hips"].matrix_local
                base = hips.matrix @ hips_rest.inverted() @ Vector(config["carry_base"])
                place_socket(rig, base)
                right_ok = solve_arm(
                    rig, "Right", base - Vector((config["grip_half"], 0.0, 0.0)))
                left_ok = solve_arm(
                    rig, "Left", base + Vector((config["grip_half"], 0.0, 0.0)))
                if not right_ok:
                    raise RuntimeError(f"{action.name} frame {frame} cannot reach the right grip")
                names_to_key = arm_names + [SOCKET]
            if left_ok:
                supported += 1
            elif not death:
                raise RuntimeError(f"{action.name} frame {frame} cannot reach the left grip")
            for name in names_to_key:
                bone = rig.pose.bones[name]
                bone.rotation_mode = "QUATERNION"
                bone.keyframe_insert("location", frame=frame, group=name)
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
                bone.keyframe_insert("scale", frame=frame, group=name)
        action["weapon_mesh_included"] = True
        action["weapon_model"] = "Production_SauceTube_S1"
        action["carry_style"] = "two hands fitted to the production sauce tube"
        action["left_support_frames"] = supported
        action["right_hand_grip"] = "continuous via SauceTubeSocket"
        if not death and supported < end - start:
            raise RuntimeError(
                f"{action.name} left support was reachable on only {supported}/{end - start + 1} frames"
            )
        for curve in action_fcurves(action):
            if any(name in curve.data_path for name in arm_names):
                for key in curve.keyframe_points:
                    key.interpolation = "BEZIER"
    return actions


def validate(rig, character, actions):
    bottle = bpy.data.objects.get(f"Character_{character}_SauceTube_Bottle")
    fill = bpy.data.objects.get(f"Character_{character}_SauceFill")
    if bottle is None or fill is None:
        raise RuntimeError("Embedded bottle meshes are missing")
    if SOCKET not in rig.data.bones or MUZZLE not in rig.data.bones:
        raise RuntimeError("Bottle socket bones are missing")
    for action in actions:
        if "death" not in action.name.lower() and int(action.get("left_support_frames", 0)) <= 0:
            raise RuntimeError(f"{action.name} has no left-hand support frames")
    rig["weapon_mesh_included"] = True
    rig["weapon_model"] = "Production_SauceTube_S1"
    rig["weapon_attachment_bone"] = SOCKET
    rig["weapon_muzzle_bone"] = MUZZLE
    rig["weapon_fit_note"] = "Per-character arm bake; gameplay capsule and character visual scale unchanged"


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) != 1 or not argv[0].isdigit() or int(argv[0]) not in CONFIG:
        raise RuntimeError("Pass one character number (1-4) after --")
    character = int(argv[0])
    config = CONFIG[character]
    blend = HERE / f"Character_{character}" / f"Character_{character}.blend"
    glb = HERE / f"Character_{character}" / f"Character_{character}.glb"
    bpy.ops.wm.open_mainfile(filepath=str(blend), load_ui=False)
    rig = bpy.data.objects.get(config["rig"])
    if rig is None or rig.type != "ARMATURE":
        raise RuntimeError(f"Missing armature {config['rig']}")
    remove_old_weapon(character)
    base, _right_grip_rest, _left_grip_rest = ensure_bones(rig, config)
    append_tube(rig, character, config, base)
    actions = bake_actions(rig, config)
    validate(rig, character, actions)

    walk = next(action for action in actions if "walk" in action.name.lower())
    rig.animation_data.action = walk
    bpy.context.scene.frame_start = int(round(walk.frame_range[0]))
    bpy.context.scene.frame_end = int(round(walk.frame_range[1]))
    bpy.context.scene.frame_set(bpy.context.scene.frame_start)
    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False)
    bpy.ops.export_scene.gltf(
        filepath=str(glb),
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
    print("SAUCE_TUBE_RETARGET_OK", character, blend, glb)


if __name__ == "__main__":
    main()
