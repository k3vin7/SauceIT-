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
## And the body is small: the world's 0.4 m brush would cover a fifth of the way
## round a player, so bodies carry their own much smaller brush.

## The stain is purely cosmetic. Nothing reads this grid back -- slipping is
## decided by the floor, and it is the floor alone.
@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size := 0.02
@export_range(0.01, 0.5, 0.005, "suffix:m") var brush_radius := 0.07
@export var mayo_color := Color("fff0a8")

var grid := ContaminationGrid.new()
var radius := 0.32
var height := 1.28

var _mesh: MeshInstance3D
var _body: Node3D


## `body` is the node the hit positions are given in the space of -- the player
## -- and `mesh` is the capsule the mask is drawn on.
func configure(body: Node3D, mesh: MeshInstance3D, capsule_radius: float,
		capsule_height: float, clean_color: Color) -> void:
	_body = body
	_mesh = mesh
	radius = capsule_radius
	height = capsule_height
	grid.wrap_x = true
	grid.configure(Vector2(TAU * radius, height), cell_size, clean_color, mayo_color)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/body_contamination.gdshader")
	material.set_shader_parameter("mask_texture", grid.texture)
	material.set_shader_parameter("clean_color", clean_color)
	material.set_shader_parameter("mayo_color", mayo_color)
	material.set_shader_parameter("body_height", height)
	_mesh.material_override = material


func _process(_delta: float) -> void:
	grid.upload_if_dirty()


## Marks the hit and returns the centre cell, or (-1, -1) if it landed off the
## body. The normal is unused: on a body every hit is on the one surface.
func paint_mayo(world_position: Vector3, _world_normal: Vector3) -> Vector2i:
	return grid.paint(_to_grid(world_position), brush_radius)


func paint_mayo_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius)


## Clean again, for a body that is being handed to a different player.
func clear() -> void:
	grid.cells.fill(0)
	grid.image.fill(Color(0.0, 0.0, 0.0, 1.0))
	grid.dirty = true


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
func _to_grid(world_position: Vector3) -> Vector2:
	var local := _body.to_local(world_position)
	var angle := atan2(local.x, local.z)
	return Vector2(angle / TAU * (TAU * radius), local.y)
