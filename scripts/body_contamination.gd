class_name BodyContamination
extends Node

## Contamination for a player's body: the same ContaminationGrid the floor and
## the walls use, wrapped around the body instead of laid flat.
##
## The body is a capsule, which is a cylinder with rounded ends, so unwrapping
## it about its own axis gives a rectangle -- u is the angle about Y times the
## circumference, v is the height -- and the existing grid, shader and
## deterministic paint all apply unchanged. That is the point of doing it this
## way rather than per polygon: the splat still travels as a centre cell, and
## `probe_determinism` still covers it.
##
## Two things differ from a flat face. The u axis is a loop, so the grid wraps
## there (`wrap_x`) and a splat near the seam carries on round the far side.
## And the body is small, so the same world brush that is a patch on a wall is a
## large mark on a player -- which is the point: being hit reads the same either
## way, and the edge roughness comes out in the same metre scale too.

## The stain is purely cosmetic. Nothing reads this grid back -- slipping is
## decided by the floor, and it is the floor alone.
@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size := 0.1
## The world's brush, not one of its own: a splat is the same size on a person
## as on a wall.
@export_range(0.01, 1.5, 0.005, "suffix:m") var brush_radius := 0.4
@export var mayo_color := Color("fff0a8")

var grid := ContaminationGrid.new()
var radius := 0.32
var height := 1.28

var _mesh: MeshInstance3D
var _body: Node3D
var _visual_overlay: ShaderMaterial


## `body` is the node the hit positions are given in the space of -- the player
## -- and `mesh` is the capsule the mask is drawn on.
## The axis the unwrap turns about, in the body's own space. A player is
## centred on their own node and leaves this at zero; the burger monster's body
## sits a third of a metre back of its node, and measuring the angle about the
## node instead skews a stain by up to ten degrees around its flanks -- which is
## exactly where a player aims. Set before `configure`.
var axis_offset := Vector3.ZERO

## How deep a cap chart is, in metres out from the axis. **0 means no caps**,
## which is what a player's capsule wants: its ends are hemispheres and the
## cylinder's own mapping carries them well enough.
##
## A flat top is another matter. The side chart maps a point by its angle and
## its height and throws the radius away, which is exact on a vertical wall and
## degenerate on a horizontal one: every point on the crown of a burger's bun at
## the same angle shares one texel whatever its radius, so a stain up there is
## drawn as a streak running from the centre to the rim rather than as a blob.
## It does not show while the monster is upright and you are looking at its
## side. It shows the moment it topples and the crown turns to face you.
##
## So the mask carries three charts rather than one, stacked in the one texture:
##
##     v below -height/2    the underside, polar: v is the radius from the axis
##     v within +/-height/2 the side, as before: v is the height
##     v above +height/2    the crown, polar again
##
## **u stays the angle in all three.** That is what makes this cost nothing
## anywhere else: the wrap at the seam is still correct across the whole
## texture, the splat still travels as one cell, and which chart a cell belongs
## to is already written in its row -- so the packet stays four ints and needs
## no chart number, and the snapshot, the MD5 and the replay go on reading one
## grid.
var cap_depth := 0.0

## How far a surface has to face up or down before its hit is recorded on a cap
## rather than on the side. Hard selection: a hit belongs to one chart. Blending
## between them would mean painting several charts per splat, which is a much
## larger change to what travels over the wire than it looks.
var cap_normal_cut := 0.7


func configure(body: Node3D, mesh: MeshInstance3D, capsule_radius: float,
		capsule_height: float, clean_color: Color) -> void:
	_body = body
	_mesh = mesh
	radius = capsule_radius
	height = capsule_height
	grid.wrap_x = true
	grid.configure(Vector2(TAU * radius, height + cap_depth * 2.0), cell_size,
		clean_color, mayo_color)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/body_contamination.gdshader")
	material.set_shader_parameter("mask_texture", grid.texture)
	material.set_shader_parameter("clean_color", clean_color)
	material.set_shader_parameter("mayo_color", mayo_color)
	material.set_shader_parameter("body_height", height)
	material.set_shader_parameter("axis_offset", axis_offset)
	material.set_shader_parameter("cap_depth", cap_depth)
	material.set_shader_parameter("cap_normal_cut", cap_normal_cut)
	_mesh.material_override = material


func _process(_delta: float) -> void:
	grid.upload_if_dirty()
	if _visual_overlay != null and _body != null:
		_visual_overlay.set_shader_parameter(
			"world_to_body", _body.global_transform.affine_inverse())


## Projects the same deterministic mask over an authored multi-mesh visual.
## `material_overlay` preserves every imported burger material underneath it;
## only pixels whose mask cells are painted survive the overlay shader.
func add_visual_overlay(visual_root: Node) -> void:
	if visual_root == null:
		return
	_visual_overlay = ShaderMaterial.new()
	_visual_overlay.shader = preload("res://scripts/enemy_contamination_overlay.gdshader")
	_visual_overlay.set_shader_parameter("mask_texture", grid.texture)
	_visual_overlay.set_shader_parameter("mayo_color", mayo_color)
	_visual_overlay.set_shader_parameter("body_height", height)
	_visual_overlay.set_shader_parameter("axis_offset", axis_offset)
	_visual_overlay.set_shader_parameter("cap_depth", cap_depth)
	_visual_overlay.set_shader_parameter("cap_normal_cut", cap_normal_cut)
	_visual_overlay.set_shader_parameter(
		"world_to_body", _body.global_transform.affine_inverse())
	for child in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		mesh_instance.material_overlay = _visual_overlay


## Marks the hit and returns the centre cell, or (-1, -1) if it landed off the
## body. **The normal picks the chart**: it is what says whether the sauce
## landed on a wall of the body or on its top. With no caps there is only one
## chart and it is ignored, which is what it was for a long time.
func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector2i:
	return grid.paint(_to_grid(world_position, world_normal), brush_radius)


func paint_mayo_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius)


## Clean again, for a body that is being handed to a different player.
func clear() -> void:
	grid.clear()


func painted_cell_count() -> int:
	return grid.painted_cell_count()


func coverage() -> float:
	return float(grid.painted_cell_count()) / float(maxi(grid.width * grid.height, 1))


func cells_md5() -> String:
	return grid.cells_md5()


func snapshot_cells() -> PackedByteArray:
	return grid.cells.duplicate()


func restore_cells(cells: PackedByteArray) -> bool:
	return grid.restore_cells(cells)


## World position -> the unwrapped body surface, in metres. The shader derives
## its own coordinate from the same local position, so the two agree by
## construction rather than by matching the mesh's UVs.
## The chart coordinate a hit maps to, for the checks. Same call the painter
## makes, so a check cannot agree with a mapping the game does not use.
func debug_to_grid(world_position: Vector3, world_normal: Vector3) -> Vector2:
	return _to_grid(world_position, world_normal)


func _to_grid(world_position: Vector3, world_normal := Vector3.ZERO) -> Vector2:
	var local := _body.to_local(world_position)
	var about := local - axis_offset
	var across := atan2(about.x, about.z) / TAU * (TAU * radius)
	if cap_depth <= 0.0:
		return Vector2(across, local.y)
	# Which way the surface faces, in the body's own space.
	var facing := _body.global_transform.basis.inverse() * world_normal
	if absf(facing.y) < cap_normal_cut:
		return Vector2(across, local.y)
	# A cap: the radius out from the axis takes the place of the height, so
	# what the side chart throws away is exactly what this one keeps.
	var rim := minf(Vector2(about.x, about.z).length(), cap_depth)
	return Vector2(across, signf(facing.y) * (height * 0.5 + rim))
