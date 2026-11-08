"""Build the La Tomatina environment kit and its Godot mesh library."""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--crate", type=Path, default=ROOT.parent / "Stage1_TomatoCrate" / "Stage1_TomatoCrate.blend")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.file_preview_type = "NONE"
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.render.engine = "BLENDER_EEVEE"
bpy.context.scene.view_settings.view_transform = "Standard"

palette = {
    "Cream": "E8CDA8", "Lime": "F1DFC0", "Peach": "DDAA87", "Sand": "CEB395",
    "Stone": "A8998C", "Slate": "63737F", "Grout": "83786C", "Ochre": "D6A660",
    "Terracotta": "B85737", "RoofLight": "D77952", "RoofDark": "943F30",
    "Door": "754432", "Wood": "93623F", "Glass": "416071", "Shade": "323944",
    "Red": "B72B29", "Scarlet": "E5412F", "Canvas": "F2DAB3", "CanvasDark": "B98963",
    "Leaf": "758D49", "LeafLight": "9DAC64", "LeafDark": "576A3B",
    "Flame": "FF8328", "Gold": "FFD163", "Rubber": "30343D",
    "Chrome": "B7BFC2", "Blue": "566D88", "White": "FFF2D1",
}


def linear(channel):
    return channel / 12.92 if channel <= .04045 else ((channel + .055) / 1.055) ** 2.4


def toon_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    tree = mat.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    emission = tree.nodes.new("ShaderNodeEmission")
    tint = tree.nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1
    tint.inputs[1].default_value = color
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    ramp.color_ramp.elements[0].color = (.46, .42, .47, 1)
    for at, shade in [(0.22, (.71, .67, .70, 1)), (0.52, (1, .96, .87, 1))]:
        ramp.color_ramp.elements.new(at).color = shade
    light = tree.nodes.new("ShaderNodeShaderToRGB")
    diffuse = tree.nodes.new("ShaderNodeBsdfDiffuse")
    tree.links.new(diffuse.outputs[0], light.inputs[0])
    tree.links.new(light.outputs[0], ramp.inputs[0])
    tree.links.new(ramp.outputs[0], tint.inputs[2])
    tree.links.new(tint.outputs[0], emission.inputs[0])
    tree.links.new(emission.outputs[0], output.inputs[0])
    return mat


materials = {
    name: toon_material(name, tuple(linear(int(hex_color[i:i + 2], 16) / 255)
                                    for i in (0, 2, 4)) + (1,))
    for name, hex_color in palette.items()
}
parts = []
models = []


def paint(obj, color):
    obj.data.materials.append(materials[color])
    parts.append(obj)
    return obj


def box(at, size, color, tilt=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.dimensions = size
    obj.rotation_euler.x = tilt
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return paint(obj, color)


def cone(at, lower, upper, height, color, sides=8, rotate=0):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=lower, radius2=upper,
                                   depth=height, location=at, rotation=(rotate, 0, 0))
    return paint(bpy.context.object, color)


def gem(at, scale, color, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=at)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return paint(obj, color)


def gable(width, depth, base, rise, color):
    x, y = width / 2, depth / 2
    vertices = [(-x, -y, base), (x, -y, base), (0, -y, base + rise),
                (-x, y, base), (x, y, base), (0, y, base + rise)]
    mesh = bpy.data.meshes.new("Gable")
    mesh.from_pydata(vertices, [], [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (0, 2, 5, 3), (2, 1, 4, 5)])
    obj = bpy.data.objects.new("Gable", mesh)
    bpy.context.collection.objects.link(obj)
    return paint(obj, color)


def finish(name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.name = obj.data.name = name
    colors = obj.data.color_attributes.new(name="Color", type="BYTE_COLOR", domain="CORNER")
    for face in obj.data.polygons:
        face.use_smooth = False
        color = obj.data.materials[face.material_index].diffuse_color
        for loop in face.loop_indices:
            colors.data[loop].color = color
    obj.data.color_attributes.active_color = colors
    models.append(obj)
    parts.clear()
    return obj


def window(x, y, z):
    box((x, y, z), (.91, .16, 1.03), "Wood")
    box((x, y - .09, z), (.65, .04, .76), "Glass")
    box((x, y - .12, z), (.07, .05, .78), "CanvasDark")
    box((x, y - .10, z - .52), (1.12, .39, .13), "Lime")


def house(name, height, body, roof):
    box((0, 0, .38), (7.8, 6.1, .76), "Stone")
    box((0, 0, height / 2), (7.65, 6, height), body)
    box((0, 0, height - .12), (7.93, 6.22, .26), "Lime")
    gable(8.4, 6.7, height, 2.05, roof)
    box((0, 0, height + 2.06), (.28, 6.75, .18), "RoofLight")
    box((2.1, .97, height + 1.37), (.6, .68, 1.74), "Door")
    box((-.8, -3.06, 1.22), (1.45, .24, 2.44), "Door")
    box((-.8, -3.2, 2.45), (1.75, .43, .16), "Sand")
    for x in (-2.8, 1.35, 2.95):
        window(x, -3.06, height - 1.5)
    window(2.2, -3.06, 1.62)
    finish(name)


house("HouseCream", 6.1, "Cream", "Terracotta")
house("HousePeach", 5.3, "Peach", "RoofDark")
house("HouseLime", 7.0, "Lime", "RoofLight")

box((0, 0, .38), (8.0, 2.6, .76), "Stone")
box((0, 0, 1.02), (7.8, 2.45, .72), "Sand")
box((0, 0, 1.48), (8.05, 2.7, .24), "Cream")
for x in (-2.8, -.7, 1.4, 3.3):
    box((x, -1.25, .82), (.9, .12, .43), "Grout")
finish("LowWall")

box((0, .3, 3.05), (12.0, 7.9, 6.1), "Cream")
gable(12.65, 8.55, 6.1, 2.5, "Terracotta")
box((0, -3.7, 4.15), (5.0, 1.4, 8.3), "Lime")
box((0, -3.6, 8.8), (3.4, 1.75, 2.9), "Lime")
for z, width in [(10.3, 3.7), (10.7, 2.8), (11.05, 1.8)]:
    box((0, -3.6, z), (width, 1.9, .34), "Cream")
box((0, -4.46, 1.33), (2.1, .16, 2.66), "Door")
cone((0, -4.49, 2.52), 1.05, 1.05, .2, "Door", 16, math.pi / 2)
box((0, -4.64, 5.07), (3.75, .24, .72), "Red")
box((0, -4.52, 8.82), (1.4, .22, 1.64), "Shade")
cone((0, -4.68, 8.66), .43, .27, .56, "Gold")
for x in (-4.2, 4.2):
    window(x, -3.66, 2.55)
finish("Church")

for z, radius, height, color in [(.16, 2.4, .32, "Stone"), (.43, 1.95, .24, "Sand"),
                                 (.7, 1.55, .34, "Cream"), (2.1, .35, 2.7, "Sand"),
                                 (3.5, .49, .3, "Lime")]:
    cone((0, 0, z), radius, radius, height, color, sides=8)
gem((0, 0, 3.9), (.43, .43, .55), "Gold")
finish("FestivalColumn")

for x in (-1.95, 1.95):
    for y in (-1.12, 1.12):
        box((x, y, 1.47), (.16, .16, 2.94), "Wood")
for i in range(8):
    x = (i - 3.5) * .56
    color = "Scarlet" if i % 2 == 0 else "Canvas"
    box((x, -.73, 2.99), (.56, 1.59, .11), color, .20)
    box((x, -1.5, 2.77), (.56, .09, .33), color)
box((0, .38, 1.0), (4.05, .94, .21), "Wood")
box((0, .49, .57), (3.74, .66, .76), "Door")
finish("MarketStall")

gable(4.85, 3.1, .055, 2.4, "Canvas")
box((0, -1.57, .54), (.73, .11, 1.06), "CanvasDark")
for x in (-2.32, 2.32):
    box((x, 0, .09), (.16, 3.23, .18), "Wood")
finish("RefugeTent")

for i in range(8):
    angle = i * math.tau / 8
    gem((.62 * math.cos(angle), .62 * math.sin(angle), .17), (.25, .24, .17), "Stone")
cone((0, 0, .28), .44, .25, .28, "Door")
finish("Brazier")

# An open hearth with a cut-out arch, inset logs and a stepped stone chimney.
box((0, -.04, .16), (4.0, 1.88, .32), "Stone")
box((0, .55, 1.42), (3.5, .55, 2.52), "Grout")
for side in (-1, 1):
    for course, z in enumerate((.55, .96, 1.37, 1.78)):
        color = "Sand" if (course + int(side > 0)) % 2 == 0 else "Stone"
        box((side * 1.48, -.07, z), (.72, 1.42, .40), color)
    box((side * 1.09, -.55, 1.15), (.16, .52, 1.62), "Stone")
for index in range(9):
    angle = (index + .5) * math.pi / 9
    stone = box((1.21 * math.cos(angle), -.52, 1.45 + 1.21 * math.sin(angle)),
                (.46, .57, .45), "Cream" if index % 2 else "Sand")
    stone.rotation_euler.y = math.pi / 2 - angle
box((0, .21, 2.63), (3.42, 1.20, .46), "Stone")
box((0, .09, 2.88), (3.76, 1.62, .25), "Cream")
box((0, .25, 3.19), (2.63, 1.06, .42), "Sand")
box((0, .29, 3.73), (1.78, 1.04, .75), "Stone")
box((0, .29, 4.17), (1.97, 1.2, .21), "Grout")
box((0, .29, 4.32), (2.15, 1.35, .14), "Sand")
for x, y, yaw in [(-.16, -.31, -.23), (.20, -.02, .29), (-.11, .20, -.11)]:
    log = cone((x, y, .48), .15, .17, 1.52, "Door", sides=7)
    log.rotation_euler = (0, math.pi / 2, yaw)
finish("RefugeFireplace")

for name, bars in [("BannerWater", 1), ("BannerMarket", 2), ("BannerFestival", 3)]:
    for x in (-1.6, 1.6):
        box((x, 0, 1.85), (.21, .27, 3.7), "Wood")
        box((x, 0, 3.72), (.35, .36, .22), "Sand")
    box((0, 0, 3.4), (3.3, .18, .15), "Wood")
    box((0, -.02, 2.35), (2.76, .13, 1.9), "Red")
    for i in range(bars):
        box(((i - (bars - 1) / 2) * .32, -.102, 2.32), (.19, .045, .72), "Canvas")
    box((0, -.04, 1.43), (2.76, .15, .13), "Gold")
    finish(name)

box((0, 0, .31), (2.35, 2.35, .62), "Sand")
box((0, 0, .59), (1.98, 1.98, .08), "Door")
cone((0, 0, 1.43), .24, .16, 1.7, "Wood", sides=7)
for at, size, color in [((0, 0, 2.65), (1.0, 1.0, 1.15), "Leaf"),
                        ((.66, .17, 2.75), (.75, .72, .78), "LeafLight"),
                        ((-.58, .18, 2.51), (.68, .63, .71), "LeafDark")]:
    gem(at, size, color)
finish("PlanterTree")

def tomato(at, radius, index, stem=False):
    color = ("Scarlet", "Red", "Flame", "Scarlet")[index % 4]
    gem(at, (radius, radius * 0.94, radius * 0.85), color, subdivisions=1)
    if stem:
        cone((at[0], at[1], at[2] + radius * .73), radius * .22,
             radius * .11, radius * .35, "LeafDark", sides=5)


def cargo_tomatoes():
    box((0, .64, 1.11), (2.1, 3.37, .22), "Wood")
    for x in (-.99, .99):
        for z in (1.30, 1.56):
            box((x, .64, z), (.15, 3.4, .22), "CanvasDark")
        for y in (-.97, .3, 1.55, 2.29):
            box((x, y, 1.46), (.21, .14, .74), "Door")
    box((0, 2.33, 1.39), (2.1, .13, .53), "Wood")
    for row in range(6):
        for column in range(4):
            index = row * 4 + column
            tomato(((column - 1.5) * .43, -.79 + row * .50,
                    1.53 + .09 * (index % 3)), .25 + .018 * (index % 4), index, index % 3 == 0)
    for index, (x, y) in enumerate([(-.49, -.34), (.12, -.02), (.4, .55),
                                     (-.33, .89), (.12, 1.23), (-.43, 1.59), (.44, 1.78)]):
        tomato((x, y, 1.89), .27, index + 8, True)


for name, body, stripe in [("FireEngine", "Scarlet", "White"), ("SauceVan", "Ochre", "Red"),
                           ("WreckBody", "Blue", "Canvas"), ("TomatoTruck", "Blue", "Canvas"),
                           ("OverturnedTomatoTruck", "Red", "Canvas")]:
    box((0, 0, .87), (2.1, 5.35, .36), "Shade")
    carries_tomatoes = name.endswith("TomatoTruck")
    if carries_tomatoes:
        cargo_tomatoes()
    else:
        box((0, .38, 1.78), (2.12, 3.57, 1.48), body)
    box((0, -1.57, 1.75), (2.0, 1.58, 1.44), body)
    box((0, -2.39, 2.02), (1.74, .12, .61), "Glass")
    box((0, -2.68, .87), (2.15, .2, .24), "Chrome")
    for x in (-.73, .73):
        box((x, -2.7, 1.15), (.34, .12, .25), "White")
    for x in (-1.05, 1.05):
        if not carries_tomatoes:
            box((x, .46, 1.81), (.09, 3.39, .25), stripe)
        box((x, -1.57, 2.02), (.09, .83, .63), "Glass")
        for y in (-1.64, 1.63):
            tire = cone((x, y, .48), .48, .48, .3, "Rubber", 12)
            tire.rotation_euler.y = math.pi / 2
    if name == "FireEngine":
        box((0, -1.55, 2.63), (1.36, .32, .27), "Blue")
        for x in (-.36, .36):
            box((x, .56, 2.61), (.11, 2.94, .12), "Chrome")
        for y in (-.72, -.22, .28, .78, 1.28, 1.78):
            box((0, y, 2.61), (.77, .11, .1), "Chrome")
    truck = finish(name)
    if name == "OverturnedTomatoTruck":
        truck.data.transform(Matrix.Rotation(math.radians(98), 4, "Y"))
        ground = min(vertex.co.z for vertex in truck.data.vertices)
        truck.data.transform(Matrix.Translation((0, 0, -ground)))


for level, offset in [(0, -.56), (0, .56), (1, -.46)]:
    z = level * .58
    box((offset, 0, z + .09), (1.04, .73, .18), "Door")
    for side in (-1, 1):
        for rail in (.26, .46):
            box((offset, side * .34, z + rail), (1.04, .085, .14), "Wood")
            box((offset + side * .48, 0, z + rail), (.085, .73, .14), "CanvasDark")
        for end in (-1, 1):
            box((offset + side * .46, end * .30, z + .27), (.12, .12, .54), "Door")
    for index in range(5):
        tomato((offset - .34 + (index % 3) * .31, -.13 + (index // 3) * .29,
                z + .43), .18, index + level, index % 2 == 0)
finish("TomatoCrateStack")

def extruded_fragment(outline, height, location, angle, top, sides):
    count = len(outline)
    vertices = [(x, y, 0) for x, y in outline]
    vertices += [(x, y, height + (0.025 if index % 3 == 0 else 0))
                 for index, (x, y) in enumerate(outline)]
    faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, following + count, index + count))
    mesh = bpy.data.meshes.new("Fragment")
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new("Fragment", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler.z = angle
    paint(obj, top)
    mesh.materials.append(materials[sides])
    for face in mesh.polygons:
        if face.index != 1:
            face.material_index = 1
    return obj


for index, (x, y, radius) in enumerate([
        (-1.00, .16, .25), (-.70, -.34, .24), (-.56, .30, .18), (-.24, -.08, .32),
        (.10, .28, .17), (.34, -.37, .20), (.46, .12, .27), (.84, -.09, .22),
        (1.09, .22, .14), (-.19, .54, .13), (.18, -.56, .14)]):
    outline = []
    for k in range(8):
        angle = k * math.tau / 8
        edge = radius * (0.70 + 0.25 * ((index * 5 + k * 3) % 7) / 6)
        outline.append((math.cos(angle) * edge, math.sin(angle) * edge * .62))
    extruded_fragment(outline, .024, (x, y, .004), index * 1.43,
                       "Scarlet" if index % 3 else "Red", "Red")
    if index % 2 == 0:
        gem((x + .04, y - .01, .03), (radius * .52, radius * .38, .025),
            "Flame" if index % 3 else "Scarlet", subdivisions=1)
    for seed in range(2):
        gem((x - .07 + seed * .065, y + .036, .055), (.021, .012, .007),
            "Gold", subdivisions=1)
finish("CrushedTomatoes")

for x, y, length, width, angle in [
        (-.38, -.18, 1.57, .21, .13), (.49, .29, 1.19, .27, -.50),
        (-.27, .52, .72, .19, .52), (.26, -.56, .89, .15, -.33),
        (1.00, .09, .43, .09, .77), (-1.10, .31, .38, .08, -.19)]:
    half = length * .5
    edge = width * .5
    outline = [(-half, -edge * .6), (-half * .79, -edge), (half * .72, -edge),
               (half, -edge * .49), (half * .78, -.015), (half, edge * .40),
               (half * .67, edge), (-half * .91, edge), (-half * .74, .006)]
    extruded_fragment(outline, .059, (x, y, 0), angle, "Wood", "Door")
    stripe = box((x, y, .074), (length * .66, .016, .012), "CanvasDark")
    stripe.rotation_euler.z = angle
    cone((x - math.cos(angle) * length * .27, y - math.sin(angle) * length * .27, .08),
                .017, .017, .017, "Slate", sides=6)
finish("BrokenBoards")

for x, radius, height in [(-.59, .43, 1.02), (.47, .49, 1.19)]:
    cone((x, 0, height * .5), radius * .86, radius, height, "Wood", sides=10)
    for z in (height * .19, height * .75):
        cone((x, 0, z), radius * .98, radius * .98, .10, "Slate", sides=10)
    cone((x, 0, height), radius, radius * .96, .075, "CanvasDark", sides=10)
finish("MarketBarrels")

for at, scale in [((-.36, .0, .31), (.57, .49, .44)), ((.37, .24, .33), (.51, .4, .44)),
                  ((.18, -.31, .19), (.51, .33, .29))]:
    gem(at, scale, "Stone" if at[0] < 0 else "Sand")
finish("Rubble")

def beam(a, b, width, depth, color):
    a, b = Vector(a), Vector(b)
    delta = b - a
    obj = box(tuple((a + b) * .5), (width, depth, delta.length), color)
    obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(delta).to_euler()
    return obj


# A buckled stall frame and a torn striped canopy slumped off its ridge.
for x, base in [(-2.0, .08), (1.94, .14)]:
    beam((x, .60, base), (x * .92, .20, 1.63 if x < 0 else 1.14), .19, .20, "Door")
    beam((x, -.68, .10), (x * .73, -.12, .68), .17, .18, "Wood")
beam((-1.84, .20, 1.63), (1.79, .20, 1.14), .19, .20, "Door")
beam((-2.05, -.83, .17), (1.58, -.19, .60), .16, .19, "Wood")
for index in range(8):
    x = (index - 3.5) * .51
    color = "Scarlet" if index % 2 == 0 else "Canvas"
    low = .29 + (index % 3) * .13
    high = 1.53 - index * .067
    strip = box((x, -.31, (high + low) / 2), (.51, math.hypot(1.28, high - low), .045),
                color, math.atan2(high - low, 1.28))
    strip.rotation_euler.z = (index % 3 - 1) * .045
    if index in (0, 2, 5, 7):
        fray = extruded_fragment([(-.22, -.19), (.21, -.21), (.15, .16), (-.13, .07)],
                                  .023, (x, -1.11, low * .56), .18 * index, color, "CanvasDark")
        fray.rotation_euler.x = .46
box((.48, .84, .30), (2.0, .69, .16), "Wood", .32)
beam((-1.75, -.96, .13), (-.74, -1.23, .34), .16, .12, "Wood")
beam((.32, -1.15, .09), (1.80, -.94, .18), .17, .12, "Door")
finish("CollapsedStall")

# A produce handcart on its side, with its wheel spokes and split bed exposed.
box((0, .11, .69), (1.50, 2.15, .16), "Door")
for index in range(6):
    x = (index - 2.5) * .24
    box((x, .1 + .13 * (index % 3), .80), (.21, 1.96 - .17 * (index % 2), .09),
        "Wood" if index % 2 else "CanvasDark")
for x in (-.73, .73):
    beam((x, -1.75, .55), (x, 1.08, .80), .12, .14, "Door")
    beam((x, -.87, .88), (x * .95, .88, 1.09), .13, .12, "Wood")
    wheel = cone((x, .03, .50), .47, .47, .17, "Door", sides=12)
    wheel.rotation_euler.y = math.pi / 2
    hub = cone((x * 1.12, .03, .50), .18, .18, .19, "Slate", sides=8)
    hub.rotation_euler.y = math.pi / 2
    for spoke in range(5):
        angle = spoke * math.tau / 5
        beam((x * 1.15, .03, .50),
             (x * 1.15, .03 + math.cos(angle) * .36, .50 + math.sin(angle) * .36),
             .058, .06, "CanvasDark")
cart = finish("OverturnedHandcart")
cart.data.transform(Matrix.Rotation(math.radians(104), 4, "Y"))
cart.data.transform(Matrix.Translation((0, 0, -min(v.co.z for v in cart.data.vertices))))

# Three ragged courses of masonry and loose blocks from the fallen end.
for row, columns in enumerate([5, 4, 2]):
    for index in range(columns):
        x = (index - 2) * .62 + row * .17
        stone = box((x, .06 * (index % 3 - 1), .18 + row * .36),
                    (.59, .58 + .05 * (index % 2), .36),
                    ("Stone", "Grout", "Sand")[(row + index) % 3])
        stone.rotation_euler.z = (index % 3 - 1) * .10
for index, (x, y, size) in enumerate([
        (-1.8, -.45, .32), (-1.25, -.61, .23), (-.65, -.71, .22),
        (.23, -.68, .29), (.88, -.45, .26), (1.52, .26, .34), (1.66, -.44, .18)]):
    gem((x, y, size * .47), (size * 1.25, size, size * .52),
        ("Stone", "Sand", "Grout")[index % 3], subdivisions=1)
beam((-1.42, -.22, .73), (.56, -.71, .18), .17, .21, "Wood")
finish("CollapsedStoneWall")

# The remnants of a festival barricade, with snapped posts and torn pennants.
beam((-1.45, -.03, .08), (-1.21, .03, 1.50), .22, .23, "Door")
beam((1.34, -.21, .04), (.80, -.03, 1.03), .21, .23, "Wood")
beam((-1.28, -.02, 1.17), (.38, .06, .95), .25, .19, "Canvas")
beam((-1.17, -.11, .75), (.82, .16, .48), .20, .17, "Scarlet")
beam((.37, .11, .95), (1.48, .42, .24), .23, .19, "CanvasDark")
beam((-1.69, -.38, .08), (-.38, -.63, .22), .16, .12, "Wood")
for x, z, color in [(-1.04, .99, "Scarlet"), (-.58, .91, "Gold"), (.17, .83, "Scarlet")]:
    panel = extruded_fragment([(-.14, -.06), (.13, -.05), (.04, .24), (-.03, .16), (-.15, .25)],
                              .02, (x, -.15, z), 0, color, "CanvasDark")
    panel.rotation_euler.x = -math.pi / 2
finish("BrokenFestivalBarrier")

if not args.crate.is_file():
    raise FileNotFoundError(f"Pass --crate pointing to the Sauce It 3D Blender tomato crate: {args.crate}")
with bpy.data.libraries.load(str(args.crate), link=False) as (source, target):
    target.objects = [name for name in source.objects if "TomatoCrate" in name]
crate = next(obj for obj in target.objects if obj and obj.type == "MESH")
bpy.context.collection.objects.link(crate)
crate.name = crate.data.name = "TomatoCrate"
crate.data.transform(crate.matrix_world)
crate.matrix_world = Matrix.Identity(4)
models.append(crate)

for index, obj in enumerate(models):
    obj.location = ((index % 5) * 16, (index // 5) * 13, 0)
    assert obj.type == "MESH" and obj.data.color_attributes.active_color, obj.name
    assert all(not face.use_smooth for face in obj.data.polygons) or obj == crate

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.color_type = "MATERIAL"
            area.spaces.active.region_3d.view_location = Vector((31, 26, 1))
            area.spaces.active.region_3d.view_distance = 90

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "Stage2_TomatinaVillage.blend"))
# Collapse material boundaries for the runtime. Godot shades the same Color layer.
for obj in models:
    obj.data.materials.clear()
bpy.ops.export_scene.gltf(filepath=str(ROOT / "Stage2_TomatinaVillage.glb"),
                         export_format="GLB", export_materials="NONE",
                         export_vertex_color="ACTIVE", export_normals=True)
print(f"TOMATINA_KIT_OK {len(models)} mesh modules")
