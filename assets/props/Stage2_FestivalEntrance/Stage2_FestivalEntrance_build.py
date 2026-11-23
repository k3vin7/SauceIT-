"""Build the brick festival gate and burlap pennants over the pedestrian lane."""
from math import cos, pi, sin
from pathlib import Path

import bpy


OUT = Path(__file__).resolve().parent
NAME = "Stage2_FestivalEntrance"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.file_preview_type = "NONE"
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene.unit_settings.system = "METRIC"
pieces = []


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = mat.diffuse_color
    shader.inputs["Roughness"].default_value = .86
    return mat


brick = [material("Terracotta %d" % i, color) for i, color in enumerate([
    (.30,.103,.053), (.36,.14,.066), (.41,.177,.081), (.34,.121,.056)])]
mortar = material("Warm limewash", (.44,.32,.197))
stone = material("Sandstone", (.57,.405,.228))
trim = material("Sign frame", (.22,.066,.029))
sign = material("Painted crimson", (.35,.027,.021))
gold = material("Honey paint", (.68,.30,.038))
leaf = material("Olive green", (.15,.28,.055))
white = material("Ivory", (.83,.72,.52))


def mesh(name, verts, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    colors = data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    colors.data.foreach_set("color", list(mat.diffuse_color) * len(data.vertices))
    pieces.append(obj)
    return obj


def prism(name, outline, depth, mat, y=0):
    count = len(outline)
    verts = [(x,y+side*depth*.5,z) for side in (-1,1) for x,z in outline]
    faces = [tuple(range(count)), tuple(reversed(range(count,2*count)))]
    faces.extend((i,i+count,(i+1)%count+count,(i+1)%count) for i in range(count))
    return mesh(name, verts, faces, mat)


def box(name, x, z, width, height, depth, mat, y=0):
    return prism(name, [(x-width*.5,z-height*.5),(x+width*.5,z-height*.5),
        (x+width*.5,z+height*.5),(x-width*.5,z+height*.5)], depth, mat, y)


for side in (-1,1):
    x = side * 5.95
    box("Pier", x, 2.05, 1.62, 4.1, 1.78, mortar)
    box("Stone plinth", x, .22, 2.02, .44, 2.05, stone)
    box("Base molding", x, .52, 1.83, .18, 1.94, trim)
    for row in range(9):
        z = .83+row*.355
        for front in (-1,1):
            for column, shift in enumerate((-.405,.405)):
                box("Brick face", x+shift, z, .77, .317, .11, brick[(row+column+side)%4], front*.893)
            box("Brick return", x+front*.802, z, .10, .317, 1.67, brick[(row+front)%4])
    box("Spring molding", x, 4.09, 1.94, .23, 1.97, stone)
    for front in (-1,1):
        box("Painted inset", x, 2.45, .72, 1.16, .055, trim, front*.957)
        box("Painted tile", x, 2.45, .56, .99, .07, sign, front*.978)
        prism("Tile diamond", [(x-.2,2.45),(x,2.82),(x+.2,2.45),(x,2.08)], .08, gold, front*1.012)

# Shallow elliptical arch. The open clear height stays above the players.
for i in range(17):
    a, b = pi*i/17+.004, pi*(i+1)/17-.004
    outline = [(5.16*cos(a),4.11+1.44*sin(a)), (6.76*cos(a),4.11+2.27*sin(a)),
               (6.76*cos(b),4.11+2.27*sin(b)), (5.16*cos(b),4.11+1.44*sin(b))]
    prism("Keystone" if i == 8 else "Arch brick", outline, 1.88, stone if i==8 else brick[i%4])

bevel = .29
span = 4.1
low, high = 5.43, 6.82
outline = [(-span+bevel,low),(span-bevel,low),(span,low+bevel),(span,high-bevel),
           (span-bevel,high),(-span+bevel,high),(-span,high-bevel),(-span,low+bevel)]
prism("Raised hand-painted sign frame", outline, .34, trim, -1.0)
prism("Red signboard", [(x*.964,(z-6.125)*.82+6.125) for x,z in outline], .355, sign, -1.025)
for side in (-1,1):
    x = side*3.65
    prism("Tomato medallion", [(x+.26*cos(i*pi/8),6.10+.23*sin(i*pi/8)) for i in range(16)], .035, gold, -1.227)
    prism("Green tomato crown", [(x-.19,6.26),(x+.03,6.25),(x+.19,6.27),
         (x+.07,6.33),(x,6.44),(x-.06,6.32)], .043, leaf, -1.235)

for index in range(9):
    x = (index-4)*.96
    z = 5.31+.27*(x/4)**2
    shape = [(x-.31,z),(x+.31,z),(x+.12,z-.39),(x-.07,z-.59)]
    prism("Festival pennant", list(reversed(shape)), .028, (white, gold, sign)[index%3], -1.04)

bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
bpy.context.object.name = NAME
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.color_type = "MATERIAL"
            area.spaces.active.region_3d.view_distance = 18
            area.spaces.active.region_3d.view_location = (0, 0, 3.3)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (NAME + ".blend")))
bpy.ops.export_scene.gltf(filepath=str(OUT / (NAME + ".glb")), export_vertex_color="NONE")
