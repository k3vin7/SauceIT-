import bpy, math, os
from mathutils import Vector
bpy.context.preferences.filepaths.file_preview_type='NONE'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system='METRIC'
def mat(name,color):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1)
 m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.72
 return m
red=mat('Pump_Red',(.55,.08,.045)); black=mat('Motor_Charcoal',(.055,.065,.07)); steel=mat('Frame_Steel',(.22,.25,.26)); blue=mat('Water_Pipe',(.08,.33,.42)); yellow=mat('Safety_Yellow',(.95,.63,.09)); ivory=mat('Gauge_Ivory',(.82,.79,.65))
def finish(obj,name,material):
 obj.name=name; obj.data.materials.append(material); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 return obj
def box(name,p,s,m):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p); o=bpy.context.object; o.dimensions=s; return finish(o,name,m)
def cylinder(name,p,r,d,m,axis='Z'):
 bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=r,depth=d,location=p)
 o=bpy.context.object
 if axis=='X':o.rotation_euler.y=math.pi/2
 if axis=='Y':o.rotation_euler.x=math.pi/2
 return finish(o,name,m)
box('Skid',(0,0,.16),(3.25,2.1,.25),steel)
for x in [-1.35,1.35]:
 box('FrameRail',(x,0,.47),(.13,1.95,.22),red)
 for y in [-.84,.84]:box('FrameUpright',(x,y,.98),(.13,.13,1.5),red)
 box('FrameTop',(x,0,1.71),(.13,1.8,.13),red)
box('Engine',(0,-.12,.8),(1.52,1.25,.95),black)
for x in [-.6,-.4,-.2,0,.2,.4,.6]:box('CoolingFin',(x,-.15,.9),(.055,1.33,.65),steel)
box('FuelTank',(0,0,1.54),(1.75,1.32,.4),red)
cylinder('FuelCap',(.48,.1,1.8),.16,.15,yellow)
cylinder('Flywheel',(-1.04,-.05,.83),.52,.35,black,'X')
cylinder('PumpHousing',(1.02,-.05,.8),.46,.44,blue,'X')
cylinder('Outlet',(1.44,-.05,.8),.18,.45,steel,'X')
cylinder('HoseCoupler',(1.69,-.05,.8),.23,.12,blue,'X')
box('ControlPlate',(0,-.78,1.16),(1.12,.13,.55),steel)
for x in [-.32,.05]:
 cylinder('Gauge',(x,-.87,1.26),.12,.035,ivory,'Y')
 box('Needle',(x,-.895,1.28),(.015,.018,.13),black)
cylinder('StartSwitch',(.36,-.88,1.1),.10,.06,yellow,'Y')
box('Exhaust',(-.65,.56,1.33),(.18,.18,.7),black)
for x in [-1.12,1.12]:
 for y in [-.64,.64]:cylinder('RubberMount',(x,y,.31),.14,.22,black)
for obj in bpy.context.scene.objects:
 if obj.type=='MESH':
  assert min(obj.scale)>0
  if not obj.data.color_attributes:
   color=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
   for item in color.data:item.color=obj.data.materials[0].diffuse_color
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.shading.color_type='MATERIAL'
root=os.path.dirname(os.path.abspath(__file__))
blend=os.path.join(root,'Stage2_PumpGenerator.blend'); glb=os.path.join(root,'Stage2_PumpGenerator.glb')
bpy.ops.wm.save_as_mainfile(filepath=blend)
bpy.ops.export_scene.gltf(filepath=glb,export_format='GLB',export_animations=False)
bpy.ops.wm.open_mainfile(filepath=blend)
assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])>20
print('PUMP_GENERATOR_VALIDATED')
