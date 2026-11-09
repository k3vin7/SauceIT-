"""Build the Tomatina Press King with Blender 5.2.

Motion references consulted: semiwork's R.E.P.O. Steam material for chunky
co-op silhouettes, and Capcom's Monster Hunter Wilds reveal article for
deliberately telegraphed monster attacks and exposed targets. The overhead
hold, double-fist contact, recoil and stagger below are original pose choices.
Valve's Left 4 Dead design talk describes the Tank's throw as a way to make
players reconsider their position. Lob uses an original shoulder load,
held aim, fast release on frame 29, and loose cargo follow-through.
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

BASE = "Stage2_PressKing"
HERE = Path(__file__).resolve().parent
FPS = 30
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.file_preview_type = "NONE"
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.render.fps = FPS

PALETTE = {
    "Skin": (0.68, 0.056, 0.026), "Cheek": (0.91, 0.14, 0.044),
    "Pulp": (0.93, 0.27, 0.075), "Wet": (0.39, 0.026, 0.018),
    "Mouth": (0.12, 0.014, 0.018), "Ivory": (0.91, 0.76, 0.48),
    "Ink": (0.049, 0.025, 0.018), "Lid": (0.47, 0.048, 0.024),
    "Stem": (0.17, 0.25, 0.069), "Leaf": (0.30, 0.43, 0.105),
    "Wood": (0.44, 0.23, 0.103), "WoodLight": (0.66, 0.38, 0.176),
    "WoodDark": (0.29, 0.14, 0.073), "Steel": (0.108, 0.19, 0.22),
    "Teal": (0.20, 0.37, 0.37), "Bolt": (0.69, 0.60, 0.42),
    "Stripe": (0.91, 0.66, 0.22), "Seed": (1.0, 0.77, 0.30),
}
materials = {}
parts = {}


def finish(obj, label, bone, color, group="Body"):
    obj.name = BASE + "_" + label
    obj.data.name = obj.name + "_Mesh"
    if color not in materials:
        material = bpy.data.materials.new(BASE + "_" + color)
        material.diffuse_color = (*PALETTE[color], 1)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = material.diffuse_color
        shader.inputs["Roughness"].default_value = 0.78
        if color == "Seed":
            shader.inputs["Emission Color"].default_value = material.diffuse_color
            shader.inputs["Emission Strength"].default_value = 0.24
        materials[color] = material
    obj.data.materials.append(materials[color])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    parts.setdefault(group, []).append((obj, bone))
    return obj


def flesh(label, bone, at, scale, color, group="Body", level=2, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=level, radius=1, location=at)
    obj = bpy.context.object
    obj.scale = scale
    obj.rotation_euler = Euler(rotation)
    return finish(obj, label, bone, color, group)


def plank(label, bone, at, size, color, group="Armor", rotation=(0, 0, 0), bevel=0.045):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.scale = size
    obj.rotation_euler = Euler(rotation)
    finish(obj, label, bone, color, group)
    modifier = obj.modifiers.new("Cut corners", "BEVEL")
    modifier.width = bevel
    modifier.segments = 1
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def limb(label, bone, start, end, r1, r2, color, group="Body", sides=8):
    span = Vector(end) - Vector(start)
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r1, radius2=r2,
                                   depth=span.length, location=Vector(start) + span * .5)
    obj = bpy.context.object
    obj.rotation_euler = span.to_track_quat("Z", "Y").to_euler()
    return finish(obj, label, bone, color, group)


def model():
    flesh("Tomato", "Torso", (0, 0, 3.00), (1.88, 1.57, 1.69), "Skin", level=3)
    flesh("Lower_rind", "Torso", (0, -.38, 2.29), (1.64, 1.30, .91), "Cheek")
    flesh("Mouth", "Torso", (0, -1.39, 3.05), (1.06, .29, .45), "Mouth")
    flesh("Lower_lip", "Jaw", (0, -1.53, 2.77), (.99, .33, .25), "Wet")
    for i in range(6):
        x = (i - 2.5) * .255
        plank(f"Tooth_{i}", "Torso", (x, -1.60 + abs(x) * .11, 3.21 - abs(x) * .12),
              (.20, .21, .26), "Ivory", "Body", (0, x * .17, 0), .048)
    for i, s in enumerate((-1, 1)):
        suffix = ("R", "L")[i]
        upper, arm, fist = (f"Upper.{suffix}", f"Forearm.{suffix}", f"Fist.{suffix}")
        flesh("Eye_" + suffix, "Torso", (s * .64, -1.29, 3.83), (.54, .35, .38), "Ivory")
        flesh("Pupil_" + suffix, "Torso", (s * .57, -1.585, 3.80), (.213, .12, .235), "Ink")
        flesh("Glint_" + suffix, "Torso", (s * .53, -1.69, 3.89), (.060, .036, .062), "Ivory")
        plank("Brow_" + suffix, "Torso", (s * .68, -1.44, 4.08),
              (1.02, .36, .24), "Lid", "Body", (0, -s * .34, s * .13), .085)
        flesh("Shoulder_" + suffix, upper, (s * 1.58, -.08, 3.45), (.57, .60, .64), "Cheek")
        limb("Upper_arm_" + suffix, upper, (s * 1.51, -.07, 3.50),
             (s * 2.08, -.24, 2.57), .50, .37, "Skin")
        flesh("Elbow_" + suffix, arm, (s * 2.04, -.24, 2.57), (.40, .43, .42), "Wet")
        limb("Forearm_" + suffix, arm, (s * 2.04, -.24, 2.57),
             (s * 2.15, -.70, 1.62), .36, .46, "Cheek")
        flesh("Knuckles_" + suffix, fist, (s * 2.13, -.78, 1.52), (.51, .57, .54), "Skin")
        for k in range(3):
            flesh(f"Finger_{suffix}_{k}", fist, (s * (1.82 + k * .25), -1.12, 1.48),
                  (.19, .29, .23), "Cheek", level=1)
        leg = f"Leg.{suffix}"
        limb("Leg_" + suffix, leg, (s * .80, .12, 1.85),
             (s * 1.07, -.11, .58), .48, .39, "Wet")
        flesh("Ankle_" + suffix, leg, (s * 1.07, -.11, .56), (.47, .47, .44), "Skin")
        plank("Boot_" + suffix, f"Foot.{suffix}", (s * 1.09, -.42, .28),
              (.95, 1.39, .56), "WoodDark", "Body", bevel=.13)
        plank("Boot_rim_" + suffix, f"Foot.{suffix}", (s * 1.09, -.49, .14),
              (1.02, 1.40, .18), "WoodLight", "Body", bevel=.065)
        plank("Shoulder_wood_" + suffix, upper, (s * 1.76, -.42, 3.45),
              (.89, .44, .79), "Wood", "Armor", (0, s * .45, s * .13), .08)

    limb("Stem_base", "Stem", (0, .05, 4.33), (.08, .13, 5.31), .30, .18, "Stem")
    limb("Stem_tip", "Stem", (.08, .13, 5.27), (-.18, .23, 5.88), .185, .115, "Leaf")
    for i in range(5):
        angle = i * math.tau / 5 + .3
        x, y = math.cos(angle), math.sin(angle)
        flesh(f"Calyx_{i}", "Stem", (x * .42, y * .40, 4.55),
              (.67, .27, .13), "Leaf" if i % 2 else "Stem", rotation=(0, .15, angle))

    # Inverted cargo box, held by two visible straps and bolted rails.
    plank("Bed", "Cargo", (0, 1.35, 3.50), (3.65, .48, 3.13), "Steel", rotation=(.11, 0, .06))
    for i in range(6):
        plank(f"Bed_slat_{i}", "Cargo", (0, 1.62, 2.10 + i * .51),
              (3.53 - .10 * (i % 3), .21, .42), ("Teal", "Wood", "WoodLight")[i % 3],
              rotation=(0, .045 * (-1) ** i, .055))
    for s in (-1, 1):
        plank(f"Side_rail_{s}", "Cargo", (s * 1.76, 1.71, 3.55), (.28, .66, 3.43),
              "Steel", rotation=(.07, s * .045, .035))
        plank(f"Bed_wing_{s}", "Cargo", (s * 1.90, 1.37, 4.64), (.62, .94, .46),
              "Teal", rotation=(.14, s * -.20, .035))
        plank(f"Strap_{s}", "Torso", (s * 1.29, -.69, 3.61), (.24, .40, 2.26),
              "Steel", rotation=(.26, s * -.22, 0))
        for j in range(3):
            flesh(f"Rail_bolt_{s}_{j}", "Cargo", (s * 1.76, 2.045, 2.44 + j * .91),
                  (.12, .084, .12), "Bolt", "Armor", 1)
    for i in range(5):
        x = (i - 2) * .59
        plank(f"Hazard_stripe_{i}", "Cargo", (x, 1.72 + x * .055, 4.72),
              (.26, .13, .38), "Stripe", rotation=(0, .48, .055), bevel=.026)
    plank("Belly_crate", "Guard", (0, -1.46, 2.18), (1.61, .46, .98), "WoodDark",
          rotation=(.13, -.08, .05))
    for i in range(3):
        plank(f"Belly_slat_{i}", "Guard", ((i - 1) * .50, -1.71, 2.19),
              (.43, .15, .93 - .08 * i), "WoodLight" if i == 1 else "Wood",
              rotation=(.12, -.14 + .09 * i, -.05), bevel=.055)
    flesh("Exposed_pulp", "Torso", (0, -1.46, 2.18), (.70, .30, .43), "Pulp", "WeakSpot")
    for i in range(5):
        angle = i * math.tau / 5
        flesh(f"Core_seed_{i}", "Torso", (.37 * math.cos(angle), -1.74,
              2.18 + .23 * math.sin(angle)), (.082, .057, .115), "Seed", "WeakSpot", 1)


model()


def review():
    target = Path(sys.argv[sys.argv.index("--review") + 1])
    target.mkdir(parents=True, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 440
    scene.render.resolution_y = 440
    scene.render.resolution_percentage = 100
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("Review backdrop")
    scene.world.color = (.12, .15, .18)
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 7.5
    scene.camera = camera
    for label, position in {
        "front": (0, -14, 2.9), "side": (14, 0, 2.9), "back": (0, 14, 2.9),
        "three_quarter": (9, -14, 7), "top": (0, 0, 15), "gameplay": (-5, -13, 2.1),
    }.items():
        camera.location = position
        camera.rotation_euler = (Vector((0, 0, 2.9)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(target / f"press-king-{label}.png")
        bpy.ops.render.render(write_still=True)


if "--review" in sys.argv:
    review()
    if "--model-only" in sys.argv:
        sys.exit(0)


def rig_parts():
    data = bpy.data.armatures.new(BASE + "_Skeleton")
    arm = bpy.data.objects.new(BASE + "_Rig", data)
    scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name, point, parent=None):
        item = data.edit_bones.new(name)
        item.head = point
        item.tail = Vector(point) + Vector((0, 0, .48))
        if parent:
            item.parent = data.edit_bones[parent]
        item.use_deform = name != "Root"

    bone("Root", (0, 0, 0))
    bone("Torso", (0, 0, 2.53), "Root")
    bone("Cargo", (0, 1.21, 3.59), "Torso")
    bone("Guard", (0, -1.42, 2.23), "Torso")
    bone("Stem", (0, .05, 4.36), "Torso")
    bone("Jaw", (0, -1.10, 2.81), "Torso")
    for s, suffix in [(-1, "R"), (1, "L")]:
        bone("Upper." + suffix, (s * 1.55, -.10, 3.45), "Torso")
        bone("Forearm." + suffix, (s * 2.04, -.24, 2.57), "Upper." + suffix)
        bone("Fist." + suffix, (s * 2.13, -.71, 1.62), "Forearm." + suffix)
        bone("Leg." + suffix, (s * .80, .12, 1.80), "Root")
        bone("Foot." + suffix, (s * 1.07, -.11, .55), "Leg." + suffix)
    bpy.ops.object.mode_set(mode="OBJECT")
    for label, group in parts.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj, name in group:
            obj.vertex_groups.new(name=name).add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
            obj.select_set(True)
        mesh = group[0][0]
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.join()
        scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mesh.name = label
        mesh.data.name = BASE + "_" + label + "_Mesh"
        mesh.parent = arm
        modifier = mesh.modifiers.new("Rigid part skin", "ARMATURE")
        modifier.object = arm
        assert all(len(v.groups) == 1 and v.groups[0].weight == 1.0 for v in mesh.data.vertices)
    arm["forward"] = "-Y"
    arm["root_motion"] = "In place"
    arm["animation_fps"] = FPS
    arm["dimensions_m"] = "5.9 tall, 5.3 wide"
    return arm


def pose(arm, frame, rotations=None, positions=None, squash=(1, 1, 1)):
    rotations, positions = rotations or {}, positions or {}
    for bone in arm.pose.bones:
        basis = bone.bone.matrix_local.to_3x3()
        bone.rotation_mode = "XYZ"
        rotation = Euler(tuple(math.radians(v) for v in rotations.get(bone.name, (0, 0, 0))))
        bone.rotation_euler = (basis.inverted() @ rotation.to_matrix() @ basis).to_euler()
        bone.location = basis.inverted() @ Vector(positions.get(bone.name, (0, 0, 0)))
        bone.scale = (squash[0], squash[2], squash[1]) if bone.name == "Torso" else (1, 1, 1)
        for channel in ("rotation_euler", "location", "scale"):
            bone.keyframe_insert(channel, frame=frame, group=bone.name)


def animation(arm, name, last, loop, keys):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start, action.frame_end = 0, last
    action["fps"], action["loop"] = FPS, loop
    arm.animation_data.action = action
    for frame, turns, moves, scale in keys:
        pose(arm, frame, turns, moves, scale)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, action)
    track.mute = True
    return action


ONE = (1, 1, 1)
REST = ({}, {}, ONE)
CROUCH = ({"Torso": (34, -4, 0), "Cargo": (48, 7, 0), "Upper.L": (-53, 2, 12),
           "Upper.R": (-58, -3, -12), "Forearm.L": (49, 0, 0), "Forearm.R": (55, 0, 0)},
          {"Torso": (0, .03, -.72)}, (1.04, 1.10, .68))
RAISE = ({"Torso": (-18, 0, 0), "Upper.L": (-137, -10, -12), "Upper.R": (-131, 11, 12),
          "Forearm.L": (34, 0, 0), "Forearm.R": (27, 0, 0), "Cargo": (14, 0, 0),
          "Jaw": (-19, 0, 0), "Stem": (17, 0, 0)}, {"Torso": (0, .20, .26)}, (1, 1, 1.06))
IMPACT = ({"Torso": (30, 0, 0), "Upper.L": (-19, 0, 9), "Upper.R": (-22, 0, -9),
           "Forearm.L": (12, 0, 0), "Forearm.R": (12, 0, 0), "Jaw": (-13, 0, 0),
           "Stem": (-26, 0, 0), "Cargo": (-17, 0, 0)},
          {"Torso": (0, -.18, -.65)}, (1.11, 1.06, .84))


def stride(sign):
    return ({"Torso": (6, 7 * sign, -4 * sign), "Cargo": (0, -8 * sign, 0),
             "Stem": (5, -14 * sign, 0), "Upper.L": (22 * sign, 0, -4),
             "Upper.R": (-22 * sign, 0, 4), "Forearm.L": (16, 0, 0),
             "Forearm.R": (14, 0, 0), "Leg.L": (-20 * sign, 0, 0),
             "Leg.R": (20 * sign, 0, 0), "Foot.L": (20 * sign, 0, 0),
             "Foot.R": (-20 * sign, 0, 0)},
            {"Torso": (.15 * sign, 0, .06), "Leg.L": (0, 0, .18 if sign > 0 else 0),
             "Leg.R": (0, 0, .18 if sign < 0 else 0)}, ONE)


arm = rig_parts()
arm.animation_data_create()
idle = animation(arm, "Idle", 60, True, [
    (0, *REST), (21, {"Torso": (0, 3, -3), "Cargo": (-4, -4, 3), "Stem": (5, 12, 0)},
     {"Torso": (.12, 0, .13)}, (.99, .99, 1.03)),
    (44, {"Torso": (2, -3, 3), "Stem": (-6, -9, 0)}, {"Torso": (-.10, 0, -.07)}, (1.02, 1.02, .98)),
    (60, *REST)])
animation(arm, "Walk", 36, True, [(0, *stride(1)), (9, {}, {"Torso": (0, 0, .24)}, ONE),
                                (18, *stride(-1)), (27, {}, {"Torso": (0, 0, .24)}, ONE), (36, *stride(1))])
rise = animation(arm, "Rise", 66, False, [
    (0, *CROUCH), (9, {**CROUCH[0], "Torso": (34, 7, 0), "Cargo": (52, -10, 8)},
     {"Torso": (0, .03, -.67)}, CROUCH[2]),
    (20, *CROUCH), (33, {"Torso": (15, -6, 0), "Cargo": (-20, 9, 0),
                         "Upper.L": (40, 0, -12), "Upper.R": (24, 0, 10)},
     {"Torso": (0, 0, -.44)}, (1.04, 1.04, .88)),
    (48, *RAISE), (57, {"Torso": (6, -4, 0), "Cargo": (-12, 0, 0), "Stem": (-17, 0, 0)}, {}, ONE),
    (66, *REST)])
animation(arm, "Slam", 69, False, [
    (0, *REST), (9, {"Torso": (15, 0, 0), "Forearm.L": (25, 0, 0), "Forearm.R": (32, 0, 0)},
     {"Torso": (0, 0, -.28)}, (1.05, 1.03, .92)),
    (24, *RAISE), (33, *RAISE), (38, *IMPACT), (43, *IMPACT),
    (51, {"Torso": (13, 0, 0), "Cargo": (10, -7, 0), "Stem": (20, 0, 0)}, {}, ONE), (69, *REST)])
throw_load = ({"Torso": (-12, -9, 25), "Upper.R": (-129, -12, 9),
               "Forearm.R": (78, 0, 0), "Upper.L": (-57, 0, -14), "Jaw": (-9, 0, 0),
               "Cargo": (-8, 8, -12), "Stem": (11, 0, -9)},
              {"Torso": (-.13, .15, .13)}, (1.01, 1.0, 1.04))
animation(arm, "Lob", 57, False, [
    (0, *REST), (8, {"Torso": (12, -8, 12), "Upper.R": (-50, 0, 8), "Forearm.R": (28, 0, 0)},
     {"Torso": (-.09, 0, -.18)}, (1.03, 1.02, .94)),
    (19, *throw_load), (25, *throw_load),
    (29, {"Torso": (19, 8, -21), "Upper.R": (-96, -6, -9), "Forearm.R": (5, 0, 0),
          "Upper.L": (31, 0, -12), "Jaw": (-16, 0, 0), "Cargo": (11, 8, 14),
          "Stem": (19, 3, 16)}, {"Torso": (.14, -.21, .04)}, ONE),
    (37, {"Torso": (23, 11, -20), "Upper.R": (-45, -8, -8), "Forearm.R": (-11, 0, 0),
          "Cargo": (18, 4, 8), "Stem": (-15, 0, -16)}, {"Torso": (.11, -.11, -.09)}, ONE),
    (48, {"Torso": (5, -4, 4), "Cargo": (-9, 0, -6), "Stem": (8, 0, 5)}, {}, ONE),
    (57, *REST)])
animation(arm, "ArmorBreak", 39, False, [
    (0, *REST), (9, {"Torso": (-22, 9, 0), "Cargo": (-30, 17, 12), "Guard": (-20, 0, 0),
                    "Upper.L": (38, 0, -16), "Upper.R": (29, 0, 18), "Jaw": (-24, 0, 0)},
     {"Torso": (0, .26, .16), "Cargo": (0, .26, .28)}, ONE),
    (22, {"Torso": (19, -6, 0), "Stem": (-22, 0, 0)}, {"Torso": (0, -.14, -.24)}, (1.08, 1.05, .91)), (39, *REST)])
animation(arm, "Collapse", 57, False, [
    (0, *REST), (10, {"Torso": (-21, 12, 0), "Upper.L": (70, 0, -18),
                      "Upper.R": (55, 0, 21), "Jaw": (-28, 0, 0)}, {"Torso": (0, .12, .08)}, ONE),
    (32, {"Torso": (41, -9, 10), "Cargo": (-18, 12, 0), "Stem": (-34, 0, 0),
          "Upper.L": (-65, 0, -24), "Upper.R": (-75, 0, 27)},
     {"Torso": (0, -.28, -.80)}, (1.16, 1.10, .51)),
    (42, {"Torso": (31, -5, 8), "Stem": (14, 0, 0), "Upper.L": (-52, 0, -21),
          "Upper.R": (-62, 0, 22)}, {"Torso": (0, -.16, -.73)}, (1.10, 1.09, .57)),
    (57, {"Torso": (41, -9, 10), "Stem": (-18, 0, 0), "Upper.L": (-65, 0, -24),
          "Upper.R": (-75, 0, 27)}, {"Torso": (0, -.28, -.80)}, (1.16, 1.10, .51))])

arm["actions"] = "Idle, Walk, Rise, Slam, ArmorBreak, Collapse, Lob"
for action in bpy.data.actions:
    arm.animation_data.action = action
    for frame in range(0, int(action.frame_end) + 1, 3):
        scene.frame_set(frame)
        assert all(math.isfinite(v) for pb in arm.pose.bones for row in pb.matrix for v in row)
    if action["loop"]:
        scene.frame_set(0)
        start = [p.matrix_basis.copy() for p in arm.pose.bones]
        scene.frame_set(int(action.frame_end))
        assert all(abs(a - b) < 0.001 for matrix, p in zip(start, arm.pose.bones)
                   for row, other in zip(matrix, p.matrix_basis) for a, b in zip(row, other))

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
arm.show_in_front = True
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.color_type = "MATERIAL"
            area.spaces.active.region_3d.view_distance = 11
            area.spaces.active.region_3d.view_location = (0, 0, 2.9)
            area.spaces.active.region_3d.view_rotation = (Vector((0, 0, 2.9)) - Vector((8, -13, 6))).to_track_quat("-Z", "Y")
arm.animation_data.action = idle
scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE / (BASE + ".blend")))
arm.animation_data.action = None
for track in arm.animation_data.nla_tracks:
    track.mute = False
bpy.ops.export_scene.gltf(filepath=str(HERE / (BASE + ".glb")), export_format="GLB",
                         export_animation_mode="NLA_TRACKS", export_animations=True,
                         export_anim_slide_to_zero=True, export_force_sampling=True)
print("PRESS_KING_BUILD_OK", len(arm.data.bones), len(bpy.data.actions))
