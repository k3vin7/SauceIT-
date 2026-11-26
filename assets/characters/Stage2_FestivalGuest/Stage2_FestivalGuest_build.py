"""Build the rounded Tomatina guest, its actions, and three static fallen poses."""
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Quaternion, Vector


OUT = Path(__file__).resolve().parent
NAME = "Stage2_FestivalGuest"
FPS = 24
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.file_preview_type = "NONE"
scene = bpy.context.scene
scene.render.fps = FPS
scene.unit_settings.system = "METRIC"


def material(name, hex_color):
    color = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    color = tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in color)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Roughness"].default_value = .64
    return mat


palette = {name: material(name, color) for name, color in {
    "Skin": "dc9a70", "Cheeks": "e68c6d", "Hair": "482a24", "Shirt": "f7e4c3",
    "Trousers": "384958", "Shoes": "62392b", "Scarf": "bd342d",
    "Eyes": "fff9ea", "Pupils": "201916", "Mouth": "3d1824", "Lip": "a65e48",
    "Tongue": "d64c5f", "Trim": "aa683d",
    "Beer": "c57b24", "Foam": "fff1ce", "Cup": "854523",
    "Helmet": "cba032", "Visor": "58422c", "Badge": "f2dca1",
}.items()}
arm = bpy.data.armatures.new(NAME)
rig = bpy.data.objects.new(NAME, arm)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
rig.show_in_front = True
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, head, tail, parent=None, connected=False):
    item = arm.edit_bones.new(name)
    item.head, item.tail = head, tail
    if parent:
        item.parent = arm.edit_bones[parent]
        item.use_connect = connected


bone("Root", (0, 0, 0), (0, 0, .24))
bone("Body", (0, 0, .91), (0, 0, 1.57), "Root")
bone("Head", (0, 0, 1.59), (0, 0, 2.20), "Body")
bone("Mouth", (0, -.431, 1.83), (0, -.431, 1.98), "Head")
for side, sign in (("L", 1), ("R", -1)):
    shoulder, elbow, wrist = ((sign * .422, 0, 1.47), (sign * .548, 0, 1.16),
                              (sign * .587, -.012, .91))
    hip, knee, ankle = ((sign * .21, 0, .92), (sign * .22, .015, .52),
                        (sign * .245, 0, .17))
    bone("Upper." + side, shoulder, elbow, "Body")
    bone("Fore." + side, elbow, wrist, "Upper." + side, True)
    bone("Hand." + side, wrist, (wrist[0], -.03, .75), "Fore." + side, True)
    bone("Thigh." + side, hip, knee, "Root")
    bone("Shin." + side, knee, ankle, "Thigh." + side, True)
    bone("Foot." + side, ankle, (ankle[0], -.23, .12), "Shin." + side, True)
    eye = (sign * .182, -.388, 2.056)
    bone("Eye." + side, eye, (eye[0], eye[1], eye[2] + .12), "Head")
    bone("Pupil." + side, eye, (eye[0], eye[1], eye[2] + .1), "Eye." + side)
    brow = (sign * .176, -.372, 2.226)
    bone("Brow." + side, brow, (brow[0], brow[1], brow[2] + .095), "Head")
bpy.ops.object.mode_set(mode="OBJECT")
rig["forward"] = "-Y"
rig["fps"] = FPS
rig["root_motion"] = "In place. Godot moves each performer through the shot."

parts = []


def skin(obj, color, joint):
    obj.data.materials.append(palette[color])
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    layer = obj.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    layer.data.foreach_set("color", list(palette[color].diffuse_color) * len(obj.data.vertices))
    obj.vertex_groups.new(name=joint).add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    modifier = obj.modifiers.new("Festival rig", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    parts.append(obj)
    return obj


def loft(name, loops, color, joint):
    segments = len(loops[0])
    verts = [vertex for section in loops for vertex in section]
    faces = [tuple(reversed(range(segments)))]
    for row in range(len(loops) - 1):
        for i in range(segments):
            a, b = row * segments + i, row * segments + (i + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    faces.append(tuple(range(len(verts) - segments, len(verts))))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return skin(obj, color, joint)


def ellipse(z, width, depth, y, segments, x=0):
    return [(x + math.cos(i * math.tau / segments) * width,
             y + math.sin(i * math.tau / segments) * depth, z) for i in range(segments)]


def rings(name, profiles, color, joint, segments=32):
    """(height, half width, half depth, forward/back centre) from bottom to top."""
    return loft(name, [ellipse(*profile, segments) for profile in profiles], color, joint)


def limb(name, sections, color, upper, lower):
    """Skin a continuous limb with a short transition around the bend."""
    count = 24
    obj = loft(name, [ellipse(z, width, depth, y, count, x)
                      for z, width, depth, x, y, _ in sections], color, upper)
    upper_weights = obj.vertex_groups[upper]
    lower_weights = obj.vertex_groups.new(name=lower)
    for row, section in enumerate(sections):
        weight = section[-1]
        indices = list(range(row * count, (row + 1) * count))
        if weight:
            upper_weights.add(indices, 1 - weight, "REPLACE")
            lower_weights.add(indices, weight, "REPLACE")


def oval(name, at, size, color, joint, angle=0, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=16)
    obj = bpy.context.object
    obj.name = name
    rotation = Euler((0, angle, 0)).to_matrix()
    for vert in obj.data.vertices:
        vert.co = Vector(at) + rotation @ Vector([vert.co[i] * size[i] for i in range(3)])
    return skin(obj, color, joint)


rings("High waisted trousers", [(.68,.24,.25,.025), (.73,.37,.31,.022),
    (.83,.47,.34,.02), (.99,.47,.35,.02), (1.075,.40,.32,.02)], "Trousers", "Body")
rings("Round festival pullover", [(.8,.30,.24,.026), (.84,.428,.315,.019),
    (.94,.52,.373,.009), (1.09,.55,.403,-.003), (1.26,.555,.407,0),
    (1.42,.531,.392,.011), (1.55,.489,.367,.015), (1.64,.42,.322,.017),
    (1.72,.31,.271,.026)], "Shirt", "Body", 40)
head_profile = [(1.485,.258,.25,-.006), (1.55,.362,.331,-.014),
    (1.65,.461,.389,-.022), (1.76,.522,.414,-.023), (1.9,.54,.425,-.017),
    (2.05,.523,.428,-.004), (2.18,.482,.403,.014), (2.29,.398,.354,.024),
    (2.38,.271,.266,.041), (2.425,.137,.151,.05), (2.445,.018,.022,.055)]


def head_widths(height):
    for low, high in zip(head_profile, head_profile[1:]):
        if height <= high[0]:
            t = (height - low[0]) / (high[0] - low[0])
            return tuple(a + t * (b - a) for a, b in zip(low[1:], high[1:]))
    return head_profile[-1][1:]


def rounded_head():
    # The scalp and face share one surface. The material boundary follows a
    # wavy hairline instead of two overlapping skull meshes.
    sides = 52
    divided = 12
    high_rows = 7
    loops = []
    for row in range(divided + high_rows + 1):
        section = []
        for index in range(sides):
            angle = index * math.tau / sides
            front = max(0, -math.sin(angle))
            hairline = 2.111 + .195 * front**1.2 + .033 * front * math.cos(angle * 3.0 + .4)
            if row <= divided:
                t = row / divided
                z = 1.485 + (hairline - 1.485) * t
            else:
                t = (row - divided) / high_rows
                z = hairline + (2.445 - hairline) * t
            w, d, y = head_widths(z)
            section.append((w * math.cos(angle), y + d * math.sin(angle), z))
        loops.append(section)
    obj = loft("Seamless head and scalp", loops, "Skin", "Head")
    obj.data.materials.append(palette["Hair"])
    for polygon in obj.data.polygons[1 + divided * sides:]:
        polygon.material_index = 1
    colors = obj.data.color_attributes["Color"].data
    for vertex in range((divided + 1) * sides, len(colors)):
        colors[vertex].color = palette["Hair"].diffuse_color


rounded_head()
# A flat knit band sits where the broad face meets the pullover.
rings("Festival neckerchief", [(1.523,.405,.331,-.011), (1.548,.468,.373,-.019),
    (1.586,.475,.387,-.021), (1.624,.455,.374,-.018)], "Scarf", "Body")
oval("Kerchief knot", (.139,-.373,1.553), (.102,.067,.069), "Scarf", "Body")
oval("Kerchief tail", (.177,-.39,1.466), (.065,.044,.12), "Scarf", "Body", -.46)
for side, sign in (("L", 1), ("R", -1)):
    oval("Ear." + side, (sign*.495,.017,1.941), (.090,.102,.117), "Skin", "Head")
    oval("Cheek." + side, (sign*.298,-.338,1.867), (.097,.052,.052), "Cheeks", "Head")
    oval("Eye socket." + side, (sign*.181,-.362,2.056), (.148,.088,.145), "Skin", "Head")
    oval("Eye." + side, (sign*.182,-.388,2.056), (.134,.087,.132), "Eyes", "Eye."+side)
    oval("Pupil." + side, (sign*.174,-.47,2.069), (.047,.022,.057), "Pupils", "Pupil."+side)
    oval("Eye glint." + side, (sign*.174-.014,-.49,2.088), (.015,.008,.016), "Eyes", "Pupil."+side)
    oval("Brow." + side, (sign*.176,-.362,2.226), (.106,.042,.024), "Hair", "Brow."+side, .13*sign)
    oval("Rolled sleeve." + side, (sign*.448,.009,1.379), (.185,.172,.223),
         "Shirt", "Upper."+side, -.30*sign)
    limb("Continuous arm." + side, [
        (.842,.079,.079,sign*.595,-.015,1), (.911,.11,.112,sign*.586,-.012,1),
        (1.03,.128,.123,sign*.57,-.009,1), (1.11,.133,.125,sign*.558,-.003,.91),
        (1.16,.131,.125,sign*.548,0,.48), (1.216,.134,.13,sign*.526,0,.1),
        (1.3,.146,.142,sign*.491,0,0), (1.401,.139,.136,sign*.45,.002,0),
        (1.466,.089,.092,sign*.423,0,0),
    ], "Skin", "Upper."+side, "Fore."+side)
    oval("Mitten." + side, (sign*.59,-.015,.87), (.134,.118,.135), "Skin", "Hand."+side)
    oval("Thumb." + side, (sign*.525,-.087,.898), (.061,.061,.084), "Skin", "Hand."+side)
    limb("Trouser leg." + side, [
        (.194,.123,.134,sign*.244,.004,1), (.242,.157,.158,sign*.241,.006,1),
        (.34,.175,.177,sign*.235,.009,1), (.443,.174,.182,sign*.226,.012,.94),
        (.521,.179,.185,sign*.22,.015,.52), (.589,.183,.192,sign*.218,.02,.1),
        (.68,.195,.21,sign*.214,.022,0), (.796,.197,.221,sign*.212,.024,0),
        (.897,.166,.184,sign*.211,.018,0),
    ], "Trousers", "Thigh."+side, "Shin."+side)
    oval("Boot sole." + side, (sign*.247,-.08,.073), (.176,.265,.073), "Trim", "Foot."+side)
    oval("Boot." + side, (sign*.247,-.076,.161), (.171,.244,.144), "Shoes", "Foot."+side)
oval("Button nose", (0,-.409,1.985), (.073,.084,.064), "Skin", "Head")


def mouth():
    # The front edge follows the cheek curve. Rings turn inward to form a
    # dark concave cavity whose inner wall holds the teeth and tongue.
    count = 36
    profile = [(1.12,-.401), (1.04,-.482), (.92,-.515), (.77,-.505),
               (.58,-.489), (.21,-.473), (.045,-.466)]
    verts, faces = [], []
    for size, depth in profile:
        for i in range(count):
            angle = i * math.tau / count
            across = math.cos(angle)
            curve = (size * across) ** 2
            verts.append((.254*size*across, depth + .042*curve,
                          1.83 + .114*size*math.sin(angle) + .021*curve))
    for row in range(len(profile)-1):
        for i in range(count):
            a, b = count*row+i, count*row+(i+1)%count
            faces.append((a, b, b+count, a+count))
    faces.append(tuple(range(len(verts)-count, len(verts))))
    faces.append(tuple(reversed(range(count))))
    mesh = bpy.data.meshes.new("Mouth with inner wall")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Mouth with inner wall", mesh)
    scene.collection.objects.link(obj)
    skin(obj, "Lip", "Mouth")
    mesh.materials.append(palette["Mouth"])
    for polygon in mesh.polygons[count*2:-1]:
        polygon.material_index = 1
    colors = mesh.color_attributes["Color"].data
    for index in range(count*3, len(verts)):
        colors[index].color = palette["Mouth"].diffuse_color


mouth()
teeth = oval("Upper tooth row", (0,-.491,1.892), (.154,.026,.031), "Eyes", "Mouth")
tongue = oval("Tongue seated in lower jaw", (0,-.486,1.775), (.125,.029,.027), "Tongue", "Mouth")
for interior in (teeth, tongue):
    group = interior.vertex_groups.new(name="FallenMouthInterior")
    group.add(list(range(len(interior.data.vertices))), 1.0, "REPLACE")

# Equipment stays separate so the same guest rig can work in both shots.
cup_start = len(parts)
for obj in [
    rings("Beer mug", [(.79,.095,.084,-.149), (.82,.112,.103,-.149),
        (1.005,.124,.109,-.149), (1.035,.118,.106,-.149)], "Beer", "Hand.R"),
    oval("Beer foam", (0,-.149,1.03), (.117,.103,.039), "Foam", "Hand.R"),
    rings("Beer base", [(.786,.095,.087,-.149), (.828,.113,.104,-.149)], "Cup", "Hand.R"),
]:
    obj.location.x = -.59

helmet_start = len(parts)
rings("Helmet dome", [(2.24,.502,.433,.028), (2.33,.472,.403,.028),
    (2.47,.369,.326,.036), (2.535,.234,.198,.04), (2.57,.092,.084,.04)], "Helmet", "Head")
rings("Helmet brim", [(2.219,.495,.436,-.008), (2.246,.549,.496,-.018),
    (2.279,.503,.452,-.009)], "Visor", "Head")
oval("Helmet badge", (0,-.375,2.366), (.087,.059,.086), "Badge", "Head")


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    bpy.context.object.name = name
    return bpy.context.object


body = join(parts[:cup_start], "GuestBody")
mug = join(parts[cup_start:helmet_start], "BeerMug")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
helmet = join(parts[helmet_start:], "FireHelmet")

# Team17's Overcooked! 2 material describes readable tosses between players.
# Double Fine's Gang Beasts material describes physics-driven throwing and
# falling. The poses here use an original late arm snap, held recoil, wiping
# hand, split-second freeze on the reveal and a one-sided backward glance.
EXPRESSIONS = {
    # mouth width, opening, eye opening, brow lift, outside brow roll, pupil size
    "smile": (1, .57, .95, .005, 0, 1),
    "laugh": (1.08, .92, .63, .013, -9, 1),
    "blink": (1, .52, .09, -.012, -4, 1),
    "aim": (.80, .43, .75, -.014, -15, 1.02),
    "sip": (.48, .38, .75, -.02, -4, 1),
    "squint": (.79, .46, .12, -.023, -21, .93),
    "gasp": (.76, 1.11, 1.15, .047, 19, .77),
    "fear": (.80, 1.42, 1.25, .065, 23, .65),
    "closed": (.77, .45, .065, -.014, 6, .93),
    "fallen": (.66, .075, .048, -.025, 0, 1),
}


def pose(frame, lift=0, expression="smile", gaze=(0, 0), **angles):
    width, opening, eyelids, raised, brow_roll, pupil_size = EXPRESSIONS[expression]
    for joint in rig.pose.bones:
        joint.rotation_mode = "QUATERNION"
        orient = joint.bone.matrix_local.to_quaternion()
        rotation = angles.get(joint.name, (0, 0, 0))
        offset = Vector((0, 0, lift if joint.name == "Root" else 0))
        scale = (1, 1, 1)
        if joint.name == "Mouth":
            scale = (width, opening, 1)
        elif joint.name.startswith("Eye."):
            scale = (1, eyelids, 1)
        elif joint.name.startswith("Pupil."):
            offset = Vector((gaze[0] * .031, 0, gaze[1] * .031))
            scale = (pupil_size, pupil_size, 1)
        elif joint.name.startswith("Brow."):
            side = 1 if joint.name.endswith(".L") else -1
            rotation = (0, side * brow_roll, 0)
            offset = Vector((0, raised * .59, raised))
        euler = Euler(tuple(math.radians(a) for a in rotation))
        joint.rotation_quaternion = orient.inverted() @ euler.to_quaternion() @ orient
        joint.location = orient.inverted() @ offset
        joint.scale = scale
        joint.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=joint.name)
        joint.keyframe_insert(data_path="location", frame=frame, group=joint.name)
        if joint.name == "Mouth" or joint.name.startswith(("Eye.", "Pupil.")):
            joint.keyframe_insert(data_path="scale", frame=frame, group=joint.name)


def action(name, end, loop=False):
    data = rig.animation_data_create()
    data.action = bpy.data.actions.new(name + ("-loop" if loop else ""))
    data.action.use_fake_user = True
    data.action.use_frame_range = True
    data.action.frame_start, data.action.frame_end = 0, end
    data.action["fps"] = FPS
    data.action["loop"] = loop
    return data.action


idle = action("Cheer", 40, True)
for frame, lift, lean, yaw, arm, face in ((0,0,0,-4,-34,"smile"), (8,.05,12,6,-63,"laugh"),
        (13,.13,-15,5,-106,"laugh"), (18,0,9,-2,-48,"blink"),
        (23,.09,-12,-7,-89,"laugh"), (32,0,3,-6,-42,"smile"), (40,0,0,-4,-34,"smile")):
    pose(frame, lift, face, (.45, 0), Body=(lean,-6,yaw), Head=(-lean*.68,3,-yaw*.7),
         **{"Upper.R":(arm,22,-6), "Upper.L":(arm+28,-19,8),
            "Fore.R":(-33,0,0), "Fore.L":(-58,0,0)})

action("Throw", 34, True)
for frame, torso, arm_angle, fore, lift, face in [(0,0,-18,-37,0,"smile"),
        (8,26,73,-88,-.06,"aim"), (12,19,87,-104,-.04,"aim"),
        (14,-16,-108,-31,.07,"gasp"), (18,-31,-72,-6,.015,"laugh"),
        (25,-8,-34,-28,0,"smile"), (34,0,-18,-37,0,"smile")]:
    pose(frame, lift, face, (.24, .17), Body=(torso*.44,torso*.17,torso), Head=(torso*-.25,0,-torso*.75),
         **{"Upper.R":(arm_angle,22,0), "Fore.R":(fore,0,0), "Hand.R":(torso*.6,0,0),
            "Upper.L":(-30-torso*.82,-19,0), "Fore.L":(-40,0,0),
            "Thigh.L":(-11-torso*.12,0,-6), "Shin.L":(9+max(0,torso*.47),0,0)})

action("Sip", 70, True)
for frame, upper, fore, head in [(0,-21,-39,0), (13,-37,-87,4),
                                 (23,-48,-121,-6), (40,-48,-121,-6), (57,-21,-39,0), (70,-21,-39,0)]:
    pose(frame, expression="sip" if 13 <= frame <= 40 else "smile",
         Head=(head,0,0), **{"Upper.R":(upper,0,16), "Fore.R":(fore,-8,9),
                                 "Hand.R":(36,0,0), "Fore.L":(-17,0,0)})

# Solve the held pose against the foam edge and lips. The tilted cup still
# follows the hand, so the lift into this pose can be edited as regular keys.
shoulder, rest_elbow, rest_wrist = [
    rig.data.bones[name].head_local for name in ("Upper.R", "Fore.R", "Hand.R")]
wrist = Vector((-.190, -.475, 1.680))
reach = wrist - shoulder
upper_length = (rest_elbow - shoulder).length
fore_length = (rest_wrist - rest_elbow).length
along = (upper_length**2 - fore_length**2 + reach.length_squared) / (2 * reach.length)
heading = reach.normalized()
bend = Vector((-.65, 0, -.8))
bend = (bend - heading * bend.dot(heading)).normalized()
elbow = shoulder + heading * along + bend * math.sqrt(upper_length**2 - along**2)
upper_aim = (rest_elbow - shoulder).rotation_difference(elbow - shoulder)
lower_aim = (upper_aim @ (rest_wrist - rest_elbow)).rotation_difference(wrist - elbow) @ upper_aim
cup_tilt = Euler((math.radians(16), 0, math.radians(75))).to_quaternion()
for frame in (23, 40):
    for name, before, target in [("Upper.R", Quaternion(), upper_aim),
                                 ("Fore.R", upper_aim, lower_aim),
                                 ("Hand.R", lower_aim, cup_tilt)]:
        joint = rig.pose.bones[name]
        rest = joint.bone.matrix_local.to_quaternion()
        joint.rotation_quaternion = rest.inverted() @ before.inverted() @ target @ rest
        joint.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=name)

action("Hose", 32, True)
for frame, angle in ((0,0), (16,12), (32,0)):
    pose(frame, expression="laugh" if frame == 16 else "smile", gaze=(.35,.15),
         Body=(9,0,angle), Head=(-7,0,-angle*.35),
         **{"Upper.L":(-54,-25,0), "Fore.L":(-33,0,0),
            "Upper.R":(-48,17,0), "Fore.R":(-38,0,0),
            "Thigh.R":(-16,0,0), "Shin.R":(21,0,0)})

action("TomatoHit", 33)
pose(0, expression="gasp", gaze=(-.8,.15), Head=(0,0,13), **{"Fore.R":(-29,0,0)})
pose(2, -.075, "squint", Body=(18,-13,8), Head=(20,-16,20),
     **{"Upper.R":(-87,22,-18), "Fore.R":(-79,0,0), "Upper.L":(-55,-35,9)})
pose(8, -.08, "squint", Body=(4,-6,2), Head=(12,2,-9),
     **{"Upper.R":(-61,-7,-12), "Fore.R":(-95,-19,13), "Upper.L":(-21,-25,0)})
pose(15, -.025, "blink", Body=(9,-5,-10), Head=(1,15,-16),
     **{"Upper.R":(-55,-23,11), "Fore.R":(-107,-15,0), "Upper.L":(-18,-22,0)})
pose(22, .035, "laugh", (.6,.1), Body=(-14,6,-12), Head=(-13,-9,18),
     **{"Upper.R":(-42,31,11), "Fore.R":(-56,0,0), "Upper.L":(-67,-22,0)})
pose(33, 0, "smile", (.36,0), Head=(1,0,8), **{"Fore.R":(-23,0,0)})

action("Startle", 19)
pose(0, expression="aim", **{"Fore.L":(-22,0,0), "Fore.R":(-21,0,0)})
pose(4, -.06, "gasp", (-.79,.38), Body=(11,6,-14), Head=(-5,3,42),
     **{"Upper.L":(-60,-41,0), "Upper.R":(-52,47,0), "Fore.L":(-28,0,0), "Fore.R":(-57,0,0)})
pose(10, -.11, "fear", (-.92,.42), Body=(17,10,3), Head=(-17,-6,37),
     **{"Upper.L":(-87,-43,0), "Upper.R":(-65,25,0), "Fore.R":(-68,0,0),
        "Thigh.L":(-25,0,0), "Shin.L":(38,0,0), "Shin.R":(23,0,0)})
pose(19, -.03, "fear", (-.8,.32), Body=(-10,2,-17), Head=(2,4,63),
     **{"Upper.L":(-32,-30,0), "Upper.R":(-82,17,0), "Fore.R":(-65,0,0), "Thigh.R":(-28,0,0)})

action("Stumble", 18)
pose(0, expression="fear", Body=(-16,9,7), Head=(-4,-6,-40),
     **{"Upper.L":(-81,-35,-8), "Upper.R":(-33,40,7), "Thigh.R":(-35,0,0)})
pose(5, -.22, "squint", Body=(-37,-19,11), Head=(25,7,-18),
     **{"Upper.L":(-98,-39,0), "Fore.L":(-36,0,0), "Upper.R":(-93,34,-6),
        "Thigh.L":(-27,0,0), "Shin.L":(75,0,0), "Thigh.R":(31,0,0)})
pose(10, -.19, "fear", (-.9,.1), Body=(-35,15,14), Head=(23,-17,53),
     **{"Upper.L":(-114,-37,0), "Upper.R":(-32,33,0), "Thigh.L":(-14,0,0),
        "Shin.L":(30,0,0), "Thigh.R":(-36,0,0), "Shin.R":(23,0,0)})
pose(18, 0, "fear", (-.7,.05), Body=(-17,1,-9), Head=(-1,4,62),
     **{"Upper.L":(-17,-17,0), "Upper.R":(-88,20,0), "Fore.R":(-76,0,0)})

action("Panic", 18, True)
for frame, stride, lift, turn in [(0,49,.015,64), (4,14,.12,71), (8,-48,.023,37),
                                  (13,-9,.16,27), (16,22,.09,51), (18,49,.015,64)]:
    pose(frame, lift, "fear", (-.8,.25), Body=(-21,stride*.12,-turn*.18), Head=(13,7,turn),
         **{"Thigh.L":(-stride,0,-4), "Thigh.R":(stride*.91,0,4),
            "Shin.L":(11+max(0,stride)*1.22,0,0), "Shin.R":(8+max(0,-stride)*1.08,0,0),
            "Upper.R":(-55+stride*.72,22,0), "Upper.L":(-54-stride*.65,-18,0),
            "Fore.R":(-77,0,0), "Fore.L":(-73,0,0)})

action("Hit", 25)
pose(0, expression="fear", **{"Fore.L":(-24,0,0), "Fore.R":(-24,0,0)})
pose(5,.13, "fear", Body=(20,0,12), Head=(18,0,-9), **{"Upper.L":(-113,-49,0), "Upper.R":(-123,55,0)})
pose(11,.28, "squint", Body=(44,0,-19), Head=(-16,0,4),
     **{"Upper.L":(-165,-36,0), "Upper.R":(-153,47,0), "Thigh.L":(-47,0,0), "Thigh.R":(28,0,0)})
pose(25, expression="closed", Body=(12,0,-13), Head=(12,0,14),
     **{"Upper.L":(-105,-50,0), "Upper.R":(-66,35,0), "Thigh.L":(-27,0,0), "Shin.L":(48,0,0)})

fallen = []
for i in range(3):
    fallen.append(action(("FallenBack", "FallenFront", "FallenSide")[i], 1))
    for frame in (0, 1):
        pose(frame, expression="fallen", Body=(12-13*i,0,-12+11*i), Head=(11-9*i,0,17-13*i),
             **{"Upper.L":(-52+26*i,-48+12*i,13), "Upper.R":(-25-31*i,50-9*i,-8),
                "Fore.L":(-44-11*i,12,0), "Fore.R":(-16-19*i,-8,0),
                "Thigh.L":(-19+6*i,0,-8), "Thigh.R":(11-12*i,0,12),
                "Shin.L":(25-6*i,0,0), "Shin.R":(6+11*i,0,0)})

rig.animation_data.action = idle
scene.frame_set(0)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
for equipment in (mug, helmet):
    equipment.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.color_type = "MATERIAL"
            area.spaces.active.region_3d.view_distance = 4.7
            area.spaces.active.region_3d.view_location = (0, 0, 1.2)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
for equipment in (mug, helmet):
    equipment.hide_set(False)
bpy.ops.export_scene.gltf(filepath=str(OUT / (NAME + ".glb")), export_animation_mode="ACTIONS",
                          export_vertex_color="NONE")

def close_fallen_face(mesh):
    # Keep the lip and lid shapes, without visible teeth, tongue or pupils in
    # the static poses. The living guest still has all of its face geometry.
    lid = bpy.data.materials.get("ClosedLid") or material("ClosedLid", "865441")
    lid_index = len(mesh.materials)
    mesh.materials.append(lid)
    shapes = bmesh.new()
    shapes.from_mesh(mesh)
    weights = shapes.verts.layers.deform.active
    hidden = {body.vertex_groups[name].index for name in ("FallenMouthInterior", "Pupil.L", "Pupil.R")}
    eyelids = {body.vertex_groups[name].index for name in ("Eye.L", "Eye.R")}
    jaw = rig.pose.bones["Mouth"]
    jaw_pose = jaw.matrix @ jaw.bone.matrix_local.inverted()
    jaw_rest = jaw_pose.inverted()
    mouth_group = body.vertex_groups["Mouth"].index
    bmesh.ops.delete(shapes, geom=[vert for vert in shapes.verts if hidden.intersection(vert[weights].keys())],
                     context="VERTS")
    # Lower the mouth corners in the posed head's up axis.
    up = (jaw_pose.to_3x3() @ Vector((0, 0, 1))).normalized()
    for vert in shapes.verts:
        if mouth_group in vert[weights]:
            across = abs((jaw_rest @ vert.co).x) / .285
            vert.co -= up * (.024 * across ** 2)
    cheeks = list(mesh.materials).index(palette["Cheeks"])
    skin_index = list(mesh.materials).index(palette["Skin"])
    for face in shapes.faces:
        if all(eyelids.intersection(vert[weights].keys()) for vert in face.verts):
            face.material_index = lid_index
        elif face.material_index == cheeks:
            face.material_index = skin_index
    shapes.to_mesh(mesh)
    shapes.free()


def bake_fallen(index, pose_action):
    rig.animation_data.action = pose_action
    scene.frame_set(0)
    graph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(body.evaluated_get(graph), depsgraph=graph, preserve_all_data_layers=True)
    close_fallen_face(mesh)
    tilt = [Euler((-1.51,0,.04)), Euler((1.53,0,-.07)), Euler((1.43,-.17,.73))][index].to_matrix()
    for vert in mesh.vertices:
        vert.co = tilt @ vert.co
    lo = Vector(tuple(min(v.co[i] for v in mesh.vertices) for i in range(3)))
    hi = Vector(tuple(max(v.co[i] for v in mesh.vertices) for i in range(3)))
    offset = Vector(((lo.x+hi.x)*.5, (lo.y+hi.y)*.5, lo.z))
    for vert in mesh.vertices:
        vert.co -= offset
    obj = bpy.data.objects.new(pose_action.name, mesh)
    scene.collection.objects.link(obj)
    return obj


bpy.ops.object.select_all(action="DESELECT")
for index, pose_action in enumerate(fallen):
    bake_fallen(index, pose_action).select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT / "Stage2_FestivalGuest_Fallen.glb"),
                          use_selection=True, export_animations=False, export_vertex_color="ACTIVE",
                          export_all_vertex_colors=False)
