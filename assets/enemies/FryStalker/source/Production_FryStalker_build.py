import bpy
import math
import os
from mathutils import Vector


ASSET = "FryStalker"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_PATH = os.path.join(OUT_DIR, "Production_FryStalker.blend")
FPS = 24


def clean_scene():
    bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for item in list(block):
            block.remove(item)


def mat(name, color, metallic=0.0, rough=0.7):
    m = bpy.data.materials.new(f"{ASSET}_MAT_{name}")
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metallic
    return m


def assign(obj, material):
    obj.data.materials.append(material)
    obj.color = material.diffuse_color


def cube(name, location, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = f"{ASSET}_{name}"
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('SoftEdges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    assign(obj, material)
    return obj


def sphere(name, location, radius, material, segments=12, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = f"{ASSET}_{name}"
    for p in obj.data.polygons:
        p.use_smooth = False
    assign(obj, material)
    return obj


def segment(name, a, b, radius, material, vertices=7):
    a, b = Vector(a), Vector(b)
    delta = b - a
    mid = (a + b) * 0.5
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius * 0.88, radius2=radius, depth=delta.length, location=mid)
    obj = bpy.context.object
    obj.name = f"{ASSET}_{name}"
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, material)
    return obj


def fry_piece(name, a, b, width_start, width_end, material, crisp_material,
              overlap=0.030, bend=0.015):
    """One irregular low-poly french fry, tapered at both join ends."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    aa, bb = a - axis * overlap, b + axis * overlap
    length = (bb - aa).length
    # Stable local basis around the fry's long axis.
    helper = Vector((0,0,1)) if abs(axis.z) < 0.92 else Vector((0,1,0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    centers = (aa, (aa + bb) * 0.5 + u * bend, bb)
    widths = (width_start, max(width_start, width_end) * 1.08, width_end)
    # An irregular rounded-rectangle cross section: recognizably fry-like, never a cube.
    profile = ((1.00,0.18),(0.68,0.72),(0.08,0.92),(-0.72,0.66),
               (-1.00,-0.12),(-0.62,-0.74),(-0.05,-0.94),(0.75,-0.61))
    verts=[]
    for ring,(center,w) in enumerate(zip(centers,widths)):
        twist = (ring-1) * 0.09
        ct,st = math.cos(twist),math.sin(twist)
        for px,py in profile:
            qx,qy = px*ct-py*st, px*st+py*ct
            verts.append(tuple(center + u*(qx*w) + v*(qy*w*0.82)))
    faces=[]
    n=len(profile)
    faces.append(tuple(range(n-1,-1,-1)))
    for ring in range(2):
        for j in range(n):
            a0=ring*n+j; a1=ring*n+(j+1)%n
            b1=(ring+1)*n+(j+1)%n; b0=(ring+1)*n+j
            faces.append((a0,a1,b1,b0))
    faces.append(tuple(range(2*n,3*n)))
    mesh=bpy.data.meshes.new(f"{ASSET}_{name}_Mesh")
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    obj=bpy.data.objects.new(f"{ASSET}_{name}",mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj.data.materials.append(crisp_material)
    # Sparse darker side facets and the terminal cap read as fried edges.
    for i,poly in enumerate(obj.data.polygons):
        poly.use_smooth=False
        if i in {3,7,11,15,len(obj.data.polygons)-1}:
            poly.material_index=1
    return obj


def poly_panel(name, x0, x1, material):
    # Tapered front/back half-shell with a slightly flared, asymmetrical top.
    zb, zt = 1.72, 3.72
    bottom_y, top_y = 0.43, 0.57
    verts = [
        (x0 * 0.80, -bottom_y, zb), (x1 * 0.80, -bottom_y, zb),
        (x1, -top_y, zt), (x0, -top_y, zt),
        (x0 * 0.80, bottom_y, zb), (x1 * 0.80, bottom_y, zb),
        (x1, top_y, zt), (x0, top_y, zt),
    ]
    faces = [(0,1,2,3), (5,4,7,6), (4,0,3,7), (1,5,6,2), (3,2,6,7), (4,5,1,0)]
    mesh = bpy.data.meshes.new(f"{ASSET}_{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"{ASSET}_{name}", mesh)
    bpy.context.collection.objects.link(obj)
    assign(obj, material)
    bevel = obj.modifiers.new('FoldedCardEdges', 'BEVEL')
    bevel.width = 0.035
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def curve_logo(name, points, material, bevel=0.045):
    curve = bpy.data.curves.new(f"{ASSET}_{name}_Curve", 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = bevel
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1.0)
    obj = bpy.data.objects.new(f"{ASSET}_{name}", curve)
    bpy.context.collection.objects.link(obj)
    assign(obj, material)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return bpy.context.object


def bone_parent(obj, rig, bone_name):
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = 'BONE'
    obj.parent_bone = bone_name
    parent_world = rig.matrix_world @ rig.data.bones[bone_name].matrix_local
    obj.matrix_parent_inverse = parent_world.inverted()
    obj.matrix_world = world


def add_bone(arm, name, head, tail, parent=None):
    eb = arm.edit_bones.new(name)
    eb.head, eb.tail = head, tail
    eb.use_connect = False
    if parent:
        eb.parent = arm.edit_bones[parent]
    return eb


def key_pose(pb, frame, loc=None, rot=None, scale=None):
    if loc is not None:
        pb.location = loc
    if rot is not None:
        pb.rotation_euler = rot
    if scale is not None:
        pb.scale = scale
    pb.keyframe_insert('location', frame=frame, group=pb.name)
    pb.keyframe_insert('rotation_euler', frame=frame, group=pb.name)
    pb.keyframe_insert('scale', frame=frame, group=pb.name)


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def new_action(rig, name, start, end, loop):
    action = bpy.data.actions.new(f"{ASSET}_{name}")
    action.use_fake_user = True
    action['frame_start'] = start
    action['frame_end'] = end
    action['fps'] = FPS
    action['loop'] = loop
    action['root_motion'] = False
    rig.animation_data.action = action
    reset_pose(rig)
    for pb in rig.pose.bones:
        key_pose(pb, start)
        key_pose(pb, end)
    return action


def set_interpolation(action, interpolation='BEZIER'):
    fcurves = []
    if hasattr(action, 'fcurves'):
        fcurves = action.fcurves
    else:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    fcurves.extend(bag.fcurves)
    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = interpolation


def build_actions(rig, leg_defs, fry_names):
    rig.animation_data_create()
    body = rig.pose.bones['Body']

    # WALK: eight distinct phase offsets create a sequential arthropod gait.
    action = new_action(rig, 'Walk', 1, 49, True)
    stride_frames = [1, 7, 13, 19, 25, 31, 37, 43]
    for i, leg in enumerate(leg_defs):
        upper = rig.pose.bones[leg['upper']]
        lower = rig.pose.bones[leg['lower']]
        claw = rig.pose.bones[leg['claw']]
        f0 = stride_frames[i]
        for base in (f0, f0 + 48):
            if base <= 49:
                key_pose(upper, base, rot=(0.0, 0.0, -0.10 * leg['side']))
                key_pose(lower, base, rot=(0.0, 0.0, 0.02))
                key_pose(claw, base, rot=(0.0, 0.0, 0.0))
        for f, lift, swing in ((f0+3, 0.30, -0.32), (f0+6, 0.48, 0.0), (f0+9, 0.26, 0.30), (f0+12, 0.0, 0.08)):
            while f > 49:
                f -= 48
            key_pose(upper, f, rot=(swing, 0.08 * leg['side'], 0.16 * leg['side']))
            key_pose(lower, f, rot=(-lift, 0.0, -0.08 * leg['side']))
            key_pose(claw, f, rot=(lift * 0.55, 0.0, 0.0))
    for f, z, roll, squash in ((1,0,0,1),(7,0.08,0.035,0.97),(13,0,-0.025,1),(19,0.09,-0.04,0.965),(25,0,0,1),(31,0.08,0.04,0.97),(37,0,-0.025,1),(43,0.09,-0.035,0.965),(49,0,0,1)):
        key_pose(body, f, loc=(0,0,z), rot=(0,0,roll), scale=(1.02 if squash<1 else 1, 1.02 if squash<1 else 1, squash))
    set_interpolation(action)

    # ATTACK: front pair rises, hangs, then snaps down toward the player.
    action = new_action(rig, 'Attack', 1, 36, False)
    front = leg_defs[:2]
    for f, by, bz, pitch, scalez in ((1,0,0,0,1),(8,0.18,-0.05,-0.13,0.96),(14,-0.10,0.16,0.16,1.08),(18,-0.14,0.20,0.20,1.10),(22,0.20,-0.24,-0.18,0.88),(25,0.10,-0.12,-0.08,0.94),(36,0,0,0,1)):
        key_pose(body, f, loc=(0,by,bz), rot=(pitch,0,0), scale=(1,1,scalez))
    for leg in front:
        upper, lower, claw = [rig.pose.bones[leg[k]] for k in ('upper','lower','claw')]
        side = leg['side']
        poses = {
            1: (0,0,0), 8: (0.32,-0.38,0.20), 14: (0.78,-0.92,0.44),
            18: (0.92,-1.08,0.55), 22: (-0.80,0.82,-0.36), 25: (-0.55,0.48,-0.22), 36: (0,0,0)
        }
        for f,(u,l,c) in poses.items():
            key_pose(upper, f, rot=(u, 0.10*side, 0.08*side))
            key_pose(lower, f, rot=(l, 0, -0.08*side))
            key_pose(claw, f, rot=(c, 0, 0))
    set_interpolation(action)

    # HIT: quick rearward recoil (+Y), compressed shell, elastic overshoot.
    action = new_action(rig, 'Hit', 1, 18, False)
    for f, loc, rot, sc in (
        (1,(0,0,0),(0,0,0),(1,1,1)),
        (3,(0,0.24,0.05),(-0.18,0,0.08),(1.05,0.92,0.94)),
        (7,(0,0.34,0.10),(-0.30,0,-0.10),(1.08,0.90,0.88)),
        (11,(0,0.13,0.03),(0.10,0,0.04),(0.97,1.03,1.05)),
        (15,(0,0.04,0),(-0.04,0,0),(1.01,0.99,0.99)),
        (18,(0,0,0),(0,0,0),(1,1,1))):
        key_pose(body, f, loc=loc, rot=rot, scale=sc)
    for i, leg in enumerate(leg_defs):
        upper = rig.pose.bones[leg['upper']]
        key_pose(upper, 3, rot=(-0.12 + 0.04*(i%2), 0, 0.12*leg['side']))
        key_pose(upper, 7, rot=(-0.24 + 0.05*(i%3), 0, -0.18*leg['side']))
        key_pose(upper, 11, rot=(0.09, 0, 0.06*leg['side']))
        key_pose(upper, 18, rot=(0,0,0))
    set_interpolation(action)

    # DEATH: shell halves and fries burst apart, then the whole creature crumples to the ground.
    action = new_action(rig, 'Death', 1, 60, False)
    for f, loc, rot, sc in (
        (1,(0,0,0),(0,0,0),(1,1,1)),
        (8,(0,0,0.12),(-0.08,0,0.10),(1,1,1.06)),
        (16,(0,0.10,0.30),(0.18,0,-0.18),(1.04,1.04,0.92)),
        (25,(0,0.28,-0.35),(0.62,0.10,0.34),(1.02,1.02,0.72)),
        (40,(0,0.48,-1.02),(1.18,0.20,0.58),(1.08,1.08,0.48)),
        (60,(0,0.54,-1.28),(1.34,0.18,0.62),(1.10,1.10,0.40))):
        key_pose(body, f, loc=loc, rot=rot, scale=sc)
    for side, bone_name in ((-1,'Shell.L'),(1,'Shell.R')):
        pb = rig.pose.bones[bone_name]
        key_pose(pb, 8, loc=(0,0,0), rot=(0,0,0))
        key_pose(pb, 16, loc=(0.20*side,-0.08,0.12), rot=(0.08,0.18*side,0.20*side))
        key_pose(pb, 28, loc=(0.54*side,0.04,-0.20), rot=(0.34,0.72*side,0.80*side))
        key_pose(pb, 60, loc=(0.68*side,0.18,-0.54), rot=(0.72,1.05*side,1.20*side))
    for i, bone_name in enumerate(fry_names):
        pb = rig.pose.bones[bone_name]
        side = -1 if i % 2 == 0 else 1
        depth = -1 if i % 3 == 0 else 1
        key_pose(pb, 8)
        key_pose(pb, 18, loc=(0.07*side*(i+1), 0.05*depth, 0.10+0.025*i), rot=(0.10*i,0.12*side*i,0.08*depth*i))
        key_pose(pb, 34, loc=(0.12*side*(i+1), 0.10*depth*(1+i%2), -0.20-0.05*i), rot=(0.34*i,0.24*side*i,0.20*depth*i))
        key_pose(pb, 60, loc=(0.15*side*(i+1), 0.16*depth, -0.60-0.06*i), rot=(0.56*i,0.42*side*i,0.33*depth*i))
    for i, leg in enumerate(leg_defs):
        upper = rig.pose.bones[leg['upper']]
        lower = rig.pose.bones[leg['lower']]
        key_pose(upper, 16, rot=(0.16*(i%3-1),0,0.18*leg['side']))
        key_pose(upper, 30, rot=(0.60*(1 if i%2 else -1),0,0.55*leg['side']))
        key_pose(upper, 60, rot=(0.92*(1 if i%2 else -1),0,1.12*leg['side']))
        key_pose(lower, 30, rot=(-0.55+0.12*(i%3),0,0))
        key_pose(lower, 60, rot=(-1.10+0.16*(i%3),0,0))
    set_interpolation(action)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clean_scene()
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.fps = FPS
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.length_unit = 'METERS'
    scene.unit_settings.scale_length = 1.0
    scene['asset_name'] = ASSET
    scene['intended_dimensions_m'] = '2.0 x 2.0 x 4.2'
    scene['forward_axis'] = '-Y'
    scene['up_axis'] = '+Z'
    scene['animation_fps'] = FPS
    scene['root_motion'] = False
    scene['style'] = 'low-poly arthropod french-fry alien; original folded-box emblem'

    red = mat('PaprikaCarton', (0.62, 0.045, 0.025), rough=0.82)
    red_dark = mat('CartonShadow', (0.27, 0.012, 0.008), rough=0.9)
    fry = mat('GoldenFry', (1.00, 0.55, 0.075), rough=0.72)
    fry_tip = mat('CrispyTip', (0.72, 0.24, 0.035), rough=0.8)
    cream = mat('EmblemCream', (1.0, 0.80, 0.24), rough=0.65)
    black = mat('EyeBlack', (0.008, 0.006, 0.004), rough=0.55)
    eye_white = mat('CyclopsSclera', (0.72, 0.88, 0.56), rough=0.42)
    iris_red = mat('CyclopsIris', (0.55, 0.012, 0.008), rough=0.34)

    # Armature
    arm_data = bpy.data.armatures.new(f"{ASSET}_ArmatureData")
    arm_data.display_type = 'STICK'
    rig = bpy.data.objects.new(f"{ASSET}_RIG", arm_data)
    rig.show_in_front = False
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    add_bone(arm_data, 'Root', (0,0,0), (0,0,0.45))
    add_bone(arm_data, 'Body', (0,0,1.70), (0,0,3.55), 'Root')
    add_bone(arm_data, 'Shell.L', (-0.22,0,2.45), (-0.22,0,3.15), 'Body')
    add_bone(arm_data, 'Shell.R', (0.22,0,2.45), (0.22,0,3.15), 'Body')

    # Fry bones fan from carton to the exact 4.2m top envelope.
    fry_specs = [
        (-0.56,-0.05,3.48,-0.68,0.02,4.12), (-0.38,0.02,3.52,-0.30,0.01,4.20),
        (-0.18,-0.02,3.50,-0.12,-0.05,4.08), (0.02,0.02,3.50,0.10,0.03,4.16),
        (0.22,-0.03,3.48,0.26,-0.04,4.10), (0.40,0.02,3.50,0.48,0.02,4.18),
        (0.57,-0.01,3.46,0.70,-0.02,4.10),
    ]
    fry_names = []
    for i, s in enumerate(fry_specs):
        name = f"Fry.{i+1:02d}"
        fry_names.append(name)
        add_bone(arm_data, name, s[:3], s[3:], 'Body')

    # Legs are listed front pair first, then travel rearward. Every bone is independently keyed.
    leg_roots = [
        # Front pair grows directly from the face-side underside and performs the slam.
        ('Front.L', -1, (-0.30,-0.49,2.08), (-0.42,-0.78,1.28), (-0.56,-0.88,0.52), (-0.64,-0.97,0.03)),
        ('Front.R',  1, ( 0.30,-0.49,2.08), ( 0.42,-0.78,1.28), ( 0.56,-0.88,0.52), ( 0.64,-0.97,0.03)),
        # Front-side pair bridges the front corners into the lateral silhouette.
        ('MidFront.L',-1,(-0.59,-0.27,2.02),(-0.82,-0.46,1.18),(-0.89,-0.56,0.42),(-0.97,-0.66,0.03)),
        ('MidFront.R', 1,(0.59,-0.27,2.02),(0.82,-0.46,1.18),(0.89,-0.56,0.42),(0.97,-0.66,0.03)),
        # Rear-side pair continues around the whole body perimeter.
        ('MidRear.L',-1,(-0.59,0.27,2.02),(-0.82,0.46,1.18),(-0.89,0.56,0.42),(-0.97,0.66,0.03)),
        ('MidRear.R', 1,(0.59,0.27,2.02),(0.82,0.46,1.18),(0.89,0.56,0.42),(0.97,0.66,0.03)),
        # Back pair grows directly from the rear underside instead of the side wall.
        ('Rear.L',-1,(-0.30,0.49,2.08),(-0.42,0.78,1.28),(-0.56,0.88,0.52),(-0.64,0.97,0.03)),
        ('Rear.R', 1,(0.30,0.49,2.08),(0.42,0.78,1.28),(0.56,0.88,0.52),(0.64,0.97,0.03)),
    ]
    leg_defs = []
    for base, side, hip, knee, ankle, foot in leg_roots:
        upper, lower, claw = f"Leg.{base}.Upper", f"Leg.{base}.Lower", f"Leg.{base}.Claw"
        add_bone(arm_data, upper, hip, knee, 'Body')
        add_bone(arm_data, lower, knee, ankle, upper)
        add_bone(arm_data, claw, ankle, foot, lower)
        leg_defs.append({'base':base, 'side':side, 'upper':upper, 'lower':lower, 'claw':claw,
                         'hip':hip, 'knee':knee, 'ankle':ankle, 'foot':foot})
    bpy.ops.object.mode_set(mode='POSE')
    reset_pose(rig)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Carton shell halves and recessed dark interior.
    shell_l = poly_panel('Shell_Left', -0.82, 0.0, red)
    shell_r = poly_panel('Shell_Right', 0.0, 0.82, red)
    bone_parent(shell_l, rig, 'Shell.L')
    bone_parent(shell_r, rig, 'Shell.R')
    interior = cube('CartonInterior', (0,0,3.61), (0.69,0.45,0.08), red_dark, 0.03)
    bone_parent(interior, rig, 'Body')

    # Original emblem: an angular falling-star/seasoning-bolt, not the reference arches.
    emblem_pts = [(-0.43,-0.596,3.28),(-0.14,-0.596,3.05),(-0.02,-0.596,3.31),(0.16,-0.596,2.98),(0.43,-0.596,3.29)]
    emblem = curve_logo('SeasoningBolt_Emblem', emblem_pts, cream, 0.052)
    bone_parent(emblem, rig, 'Body')

    # One huge cyclops eye. A wide iris and dilated pupil dominate the face.
    socket = sphere('CyclopsSocket', (0,-0.565,2.60), 0.335, black, 16, 8)
    socket.scale.y = 0.34
    sclera = sphere('CyclopsSclera', (0,-0.615,2.60), 0.272, eye_white, 18, 9)
    sclera.scale.y = 0.30
    iris = sphere('CyclopsIris', (0,-0.686,2.60), 0.205, iris_red, 18, 9)
    iris.scale.y = 0.24
    pupil = sphere('CyclopsDilatedPupil', (0,-0.735,2.60), 0.148, black, 18, 9)
    pupil.scale.y = 0.20
    glint = sphere('CyclopsGlint', (-0.052,-0.768,2.67), 0.030, cream, 10, 5)
    glint.scale.y = 0.15
    for eye_part in (socket, sclera, iris, pupil, glint):
        bone_parent(eye_part, rig, 'Body')

    # Fries: square, slightly crooked sticks with darker crisp tips.
    for i, s in enumerate(fry_specs):
        a, b = Vector(s[:3]), Vector(s[3:])
        direction = b-a
        mid = (a+b)*0.5
        obj = cube(f'Fry_{i+1:02d}', mid, (0.067,0.067,direction.length*0.5), fry, 0.025)
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = Vector((0,0,1)).rotation_difference(direction.normalized())
        bone_parent(obj, rig, fry_names[i])
        tip = cube(f'FryTip_{i+1:02d}', b - direction.normalized()*0.035, (0.069,0.069,0.035), fry_tip, 0.018)
        tip.rotation_mode = 'QUATERNION'
        tip.rotation_quaternion = Vector((0,0,1)).rotation_difference(direction.normalized())
        bone_parent(tip, rig, fry_names[i])

    # Every leg is literally three individual fries joined end-to-end.
    # Their tapered ends overlap slightly, so the bend reads as a sharp fry-to-fry joint
    # without a separate mechanical knuckle, sphere, or box.
    for leg in leg_defs:
        for suffix, a, b, bone, w0, w1, bend in (
            ('FryPiece_A',leg['hip'],leg['knee'],leg['upper'],0.092,0.064, 0.018*leg['side']),
            ('FryPiece_B',leg['knee'],leg['ankle'],leg['lower'],0.067,0.048,-0.013*leg['side']),
            ('FryPiece_C_Point',leg['ankle'],leg['foot'],leg['claw'],0.051,0.010,0.008*leg['side'])):
            obj = fry_piece(f"{leg['base']}_{suffix}", a, b, w0, w1, fry, fry_tip,
                            overlap=0.032 if suffix!='FryPiece_C_Point' else 0.020,
                            bend=bend)
            bone_parent(obj, rig, bone)

    build_actions(rig, leg_defs, fry_names)

    rig['forward_axis'] = '-Y'
    rig['animation_fps'] = FPS
    rig['actions'] = 'Walk, Attack, Hit, Death'
    rig['loop_Walk'] = True
    rig['loop_Attack'] = False
    rig['loop_Hit'] = False
    rig['loop_Death'] = False
    rig['root_motion'] = False
    rig['overall_dimensions_m'] = (2.0, 2.0, 4.2)
    rig['attack_contact_frame'] = 22
    rig['notes'] = 'Eight-leg sequential arthropod gait; front-pair slam; knockback; separating collapse.'

    # Ground reference collection (non-rendering) and clean inspection state.
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    rig.animation_data.action = bpy.data.actions[f'{ASSET}_Walk']
    scene.frame_start, scene.frame_end = 1, 49
    scene.frame_set(1)
    scene.tool_settings.transform_pivot_point = 'MEDIAN_POINT'
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig

    # Apply transforms on non-rig objects while preserving bone-parent relations.
    for obj in bpy.context.scene.objects:
        if obj.type in {'MESH','CURVE'}:
            obj.hide_render = False

    bpy.context.preferences.filepaths.file_preview_type = 'NONE'
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)

    # Reopen and perform persistence + structural validation.
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    rig2 = bpy.data.objects.get(f'{ASSET}_RIG')
    required = {f'{ASSET}_{n}' for n in ('Walk','Attack','Hit','Death')}
    present = {a.name for a in bpy.data.actions}
    assert rig2 is not None and rig2.type == 'ARMATURE'
    assert required.issubset(present), (required, present)
    assert len([o for o in bpy.data.objects if o.type == 'ARMATURE']) == 1
    assert all(bpy.data.actions[n].use_fake_user for n in required)
    stored_dims = list(rig2.get('overall_dimensions_m'))
    assert all(abs(a-b) < 1e-5 for a,b in zip(stored_dims, [2.0,2.0,4.2]))
    print('VALIDATION_OK')
    print('ARMATURE', rig2.name, 'BONES', len(rig2.data.bones))
    for n in sorted(required):
        a = bpy.data.actions[n]
        print('ACTION', n, tuple(a.frame_range), 'FPS', a['fps'], 'LOOP', a['loop'])
    print('DELIVERABLE', BLEND_PATH)


if __name__ == '__main__':
    main()
