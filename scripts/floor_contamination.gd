class_name FloorContamination
extends StaticBody3D

## Flat floor carrying one contamination grid. The grid is also the source of
## truth for the slip test, so what is drawn and what trips the player are the
## same data.

@export_group("Contamination Grid")
@export_range(0.05, 0.5, 0.01, "suffix:m") var cell_size := 0.1
@export_range(0.05, 1.5, 0.01, "suffix:m") var brush_radius := 0.4
@export var floor_size := Vector2(12.0, 12.0)
@export var clean_color := Color("53616d")
@export var mayo_color := Color("fff0a8")

var grid := ContaminationGrid.new()
var _floor_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("mayo_floor")
	_rebuild_floor()


func _process(_delta: float) -> void:
	grid.upload_if_dirty()


func configure(new_cell_size: float, new_brush_radius: float) -> void:
	var grid_changed := not is_equal_approx(cell_size, new_cell_size)
	cell_size = new_cell_size
	brush_radius = new_brush_radius
	if grid_changed and is_node_ready():
		_rebuild_grid()


func paint_mayo(world_position: Vector3) -> void:
	grid.paint(_to_grid(world_position), brush_radius)


## Cell-exact slip query: true when the cell under this position is painted.
func is_mayo_at(world_position: Vector3) -> bool:
	return grid.is_painted(_to_grid(world_position))


func reset_debug_counters() -> void:
	grid.reset_debug_counters()


func debug_paint_calls() -> int:
	return grid.paint_calls


func debug_texture_uploads() -> int:
	return grid.texture_uploads


func _to_grid(world_position: Vector3) -> Vector2:
	var local := to_local(world_position)
	return Vector2(local.x, local.z)


func _rebuild_floor() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "PerfectlyFlatFloor"
	var plane := PlaneMesh.new()
	plane.size = floor_size
	_floor_mesh.mesh = plane
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_mesh)

	var collision := CollisionShape3D.new()
	collision.name = "FloorCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(floor_size.x, 0.04, floor_size.y)
	collision.shape = box
	collision.position.y = -0.02
	add_child(collision)
	_rebuild_grid()


func _rebuild_grid() -> void:
	grid.configure(floor_size, cell_size, clean_color, mayo_color)
	_floor_mesh.material_override = grid.material
