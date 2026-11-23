"""Build the cab-over transport truck, with articulated wheels and tail doors."""
from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


OUT = Path(__file__).resolve().parent
NAME = "Stage2_PartyBongo"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.file_preview_type = "NONE"
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene.unit_settings.system = "METRIC"
parts = []


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Roughness"].default_value = .79
    return mat


paint = material("Deep petrol", (.035,.135,.142))
trim = material("Ivory trim", (.59,.51,.36))
canvas = material("Faded sage canvas", (.19,.25,.171))
seam = material("Canvas seams", (.118,.171,.102))
steel = material("Gunmetal", (.075,.10,.108))
rubber = material("Tires", (.032,.039,.041))
glass = material("Sky blue windshield", (.072,.181,.234))
glint = material("Windshield reflection", (.19,.352,.41))
amber = material("Turn signal", (.90,.39,.036))
red = material("Tail lights", (.55,.051,.037))
wood = material("Bed planks", (.35,.20,.095))


def model(name, verts, faces, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    colors = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    colors.data.foreach_set("color", list(mat.diffuse_color) * len(mesh.vertices))
    parts.append(obj)
    return obj


def shell(name, outline, width, mat, x=0):
    n = len(outline)
    verts = [(x+side*width*.5,y,z) for side in (-1,1) for y,z in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return model(name, verts, faces, mat)


def box(name, at, size, mat):
    x,y,z = at
    width,length,height = size
    return shell(name, [(y-length*.5,z-height*.5),(y+length*.5,z-height*.5),
         (y+length*.5,z+height*.5),(y-length*.5,z+height*.5)], width, mat, x)


def join(parts_to_join, name, pivot=(0,0,0)):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts_to_join:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts_to_join[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    for vert in obj.data.vertices:
        vert.co -= Vector(pivot)
    obj.location = pivot
    return obj


# Local forward in Blender is +Y, matching gameplay -Z after glTF export.
shell("Cab", [(1.08,.60),(2.93,.60),(3.12,.89),(3.12,1.72),(2.84,2.54),
    (2.66,2.69),(1.27,2.69),(1.05,2.46)], 2.24, paint)
box("Running chassis", (0,.0,.62), (1.87,6.07,.26), steel)
box("Front bumper", (0,3.12,.67), (2.29,.18,.235), trim)
box("Rear bumper", (0,-3.02,.53), (2.35,.16,.16), steel)
box("Grille", (0,3.132,1.21), (1.34,.06,.43), steel)
for slat in range(4):
    box("Grille bar", (0,3.168,1.064+slat*.09), (1.18,.026,.027), trim)
for side in (-1,1):
    x = side*.90
    box("Headlight housing", (x,3.127,1.23), (.35,.08,.405), steel)
    box("Headlight lens", (x,3.174,1.29), (.27,.03,.245), trim)
    box("Amber signal", (x,3.174,1.099), (.27,.03,.092), amber)
    shell("Windshield", [(2.867,2.51),(3.068,1.915),(3.099,1.82),(2.89,2.53)], .92, glass, side*.49)
    shell("Glass glint", [(2.92,2.397),(2.946,2.325),(2.954,2.327),(2.927,2.41)], .86, glint, side*.49)
    shell("Door glazing", [(1.26,1.782),(2.94,1.782),(2.69,2.48),(1.45,2.48),(1.27,2.33)],
          .044, glass, side*1.115)
    box("Cab stripe", (side*1.127,2.03,1.50), (.04,1.92,.095), trim)
    box("Cab latch", (side*1.158,1.55,1.68), (.071,.22,.055), steel)
    box("Mirror stalk", (side*1.238,2.75,1.98), (.30,.081,.075), steel)
    box("Wing mirror", (side*1.386,2.75,2.06), (.12,.20,.315), steel)
    box("Tail lens", (side*.99,-3.115,.71), (.30,.069,.15), red)
    box("Rear bed side", (side*1.12,-1.004,1.11), (.16,3.85,.48), paint)
    box("Bed stripe", (side*1.21,-1.0,1.115), (.036,3.86,.115), trim)
    box("Canopy side", (side*1.124,-1.02,2.015), (.15,3.88,1.43), canvas)
    for rib in range(5):
        box("Canopy tie seam", (side*1.201,.812-rib*.905,2.04), (.028,.067,1.434), seam)
    box("Bench seat", (side*.807,-.92,1.20), (.40,3.59,.19), wood)
for board in range(8):
    box("Bed floor", (-.906+board*.259,-.995,.88), (.254,3.87,.18), wood)
shell("Rounded canopy", [(-3.03,2.59),(.95,2.59),(.93,2.78),(.77,2.96),
    (-2.86,2.96),(-3.03,2.82)], 2.31, canvas)
box("Canopy front", (0,.907,1.88), (2.22,.14,1.83), seam)
box("Rear upper sill", (0,-2.98,2.725), (2.29,.19,.21), seam)
join(parts[:], "TruckBody")


for side, suffix in [(-1,"Left"),(1,"Right")]:
    start = len(parts)
    x = side*.557
    # Open upper panes show the passengers as the truck rolls to a stop.
    box("Lower door", (x,-2.964,1.24), (1.085,.136,.658), paint)
    box("Tail stripe", (x,-3.041,1.235), (1.085,.028,.114), trim)
    for post in (x-.505,x+.505):
        box("Door window stile", (post,-2.964,2.02), (.076,.15,1.03), steel)
    box("Door window head", (x,-2.964,2.535), (1.075,.15,.087), paint)
    box("Door handle", (side*.152,-3.068,1.44), (.20,.08,.066), steel)
    join(parts[start:], "RearDoor"+suffix, (side*1.10,-2.964,0))

for axle, y in [("Front",2.186),("Rear",-2.0)]:
    for side, suffix in [(-1,"Left"),(1,"Right")]:
        start = len(parts)
        x,z = side*1.018,.54
        for radius, width, offset, mat in [(.54,.36,0,rubber),(.33,.035,.181,trim),
                  (.19,.046,.205,steel),(.079,.053,.232,trim)]:
            outline = [(y+radius*cos(i*pi/10),z+radius*sin(i*pi/10)) for i in range(20)]
            shell("Wheel ring", outline, width, mat, x+side*offset)
        join(parts[start:], "Wheel"+axle+suffix, (x,y,z))

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.color_type = "MATERIAL"
            area.spaces.active.region_3d.view_distance = 11
            area.spaces.active.region_3d.view_location = (0, 0, 1.4)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
bpy.ops.export_scene.gltf(filepath=str(OUT / (NAME + ".glb")), export_vertex_color="NONE")
