class_name RoofContamination
extends Node

## Contamination for a cone: the same `ContaminationGrid` everything else uses,
## laid out as the cone's own flat net rather than wrapped round an axis.
##
## `BodyContamination` maps (angle about Y, height), which is the right unwrap
## for a capsule and the wrong one for a cone -- every angle meets at the apex,
## so a splat came out as a wedge that was the right width at the base and
## tapered to nothing at the point, and a roof with a few shots on it read as a
## sunburst.
##
## A cone is developable, so there is an exact answer: cut it up one side and
## flatten it, and it becomes a sector. A point at slant distance s from the
## apex and angle t lands at polar (s, t * R/L). Distances survive that exactly,
## which is the whole claim -- a 0.4 m splat is 0.4 m wherever it lands.
##
## The one cut is the seam at the back, where a splat straddling it is clipped.
## That is one radial line on the far side of a roof, against a distortion that
## covered the whole of it.

@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size := 0.1
@export_range(0.01, 1.5, 0.005, "suffix:m") var brush_radius := 0.4
@export var mayo_color := Color("fff0a8")

var grid := ContaminationGrid.new()
var radius := 1.0
var height := 1.0

var _mesh: MeshInstance3D
var _body: Node3D


func configure(body: Node3D, mesh: MeshInstance3D, cone_radius: float,
		cone_height: float, clean_color: Color) -> void:
	_body = body
	_mesh = mesh
	radius = cone_radius
	height = cone_height
	# The sector reaches one slant length from the apex in every direction, so
	# a square of twice that holds it whichever way it is cut.
	var extent := _slant() * 2.0
	grid.wrap_x = false
	grid.configure(Vector2(extent, extent), cell_size, clean_color, mayo_color)

	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/roof_contamination.gdshader")
	material.set_shader_parameter("mask_texture", grid.texture)
	material.set_shader_parameter("clean_color", clean_color)
	material.set_shader_parameter("mayo_color", mayo_color)
	material.set_shader_parameter("cone_radius", radius)
	material.set_shader_parameter("cone_height", height)
	material.set_shader_parameter("grid_extent", extent)
	_mesh.material_override = material


func _process(_delta: float) -> void:
	grid.upload_if_dirty()


func paint_mayo(world_position: Vector3, _world_normal: Vector3) -> Vector2i:
	return grid.paint(_to_grid(world_position), brush_radius)


func paint_mayo_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius)


func painted_cell_count() -> int:
	return grid.painted_cell_count()


func cells_md5() -> String:
	return grid.cells_md5()


func snapshot_cells() -> PackedByteArray:
	return grid.cells.duplicate()


func restore_cells(cells: PackedByteArray) -> bool:
	return grid.restore_cells(cells)


func _slant() -> float:
	return sqrt(radius * radius + height * height)


## World position -> the unrolled cone, in metres. The shader derives the same
## coordinate from the same local position, so the two agree by construction
## rather than by matching the mesh's UVs.
func _to_grid(world_position: Vector3) -> Vector2:
	var local := _body.to_local(world_position)
	var slant := _slant()
	# Height places a point on the cone, not distance from the axis: the two
	# agree on the surface, and height is still defined at the apex.
	var from_apex := slant * clampf((height * 0.5 - local.y) / height, 0.0, 1.0)
	var around := atan2(local.x, local.z) * (radius / slant)
	return Vector2(from_apex * cos(around), from_apex * sin(around))
