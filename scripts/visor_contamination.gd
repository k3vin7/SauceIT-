class_name VisorContamination
extends Node3D

## The player's glasses: a contamination grid worn on the face.
##
## Sauce that lands inside the field of view is painted here, and this mask is
## what blinds you -- there is no separate screen effect to keep in step with
## it. The grid is measured in view units rather than metres, 16 by 9 across the
## field of view, which makes the screen a 1:1 sample of it: no projection, no
## cap, no eviction.
##
## It hangs off the aim pivot, which already carries the aim pitch, so it moves
## exactly with the camera -- sauce on your lenses stays where it landed on the
## screen as you look around, the way sauce on glasses does. Being a real object
## on the head, it is also visible to everyone else: they can see your lenses
## are filthy, and see you stop to wipe them.

## Half the grid in view units. 4.5 up and down is the camera's own field of
## view; 8 across is that at 16:9.
const HALF_HEIGHT := 4.5
const HALF_WIDTH := 8.0

## 0.08 of a view unit is about six screen pixels across at 720p: fine enough
## that the boundary reads as a splat edge rather than as steps.
@export_range(0.02, 1.0, 0.01) var cell_size := 0.08
## In view units too: a body splat a hand's width from the eye covers about this
## much of the view.
@export_range(0.1, 4.0, 0.05) var brush_radius := 1.2
@export var mayo_color := Color("fff0a8")
@export var lens_color := Color(0.12, 0.15, 0.19, 1.0)
## How far the lenses tip up while they are being wiped.
@export_range(0.0, 90.0, 1.0, "suffix:°") var wipe_lift_degrees := 55.0

var grid := ContaminationGrid.new()

var _lens: MeshInstance3D


func _ready() -> void:
	grid.configure(Vector2(HALF_WIDTH * 2.0, HALF_HEIGHT * 2.0), cell_size,
		lens_color, mayo_color)
	_build_lens()


func _process(_delta: float) -> void:
	grid.upload_if_dirty()


## Sauce arriving from `direction`, given in the visor's own space with -Z
## straight ahead. Anything level with the lenses or behind them misses: it is
## not in front of your eyes, so it does not blind you.
func paint_from_view(direction: Vector3, fov_degrees: float) -> Vector2i:
	if direction.z >= -0.001:
		return Vector2i(-1, -1)
	var extent := tan(deg_to_rad(fov_degrees) * 0.5)
	if extent <= 0.0:
		return Vector2i(-1, -1)
	var view := Vector2(
		direction.x / -direction.z / extent * HALF_HEIGHT,
		direction.y / -direction.z / extent * HALF_HEIGHT)
	return grid.paint(view, brush_radius)


func paint_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius)


func clear() -> void:
	grid.cells.fill(0)
	grid.image.fill(Color(0.0, 0.0, 0.0, 1.0))
	grid.dirty = true


## 0 clear, 1 completely blind. What the player has to do something about.
func coverage() -> float:
	return float(grid.painted_cell_count()) / float(maxi(grid.width * grid.height, 1))


func painted_cell_count() -> int:
	return grid.painted_cell_count()


func cells_md5() -> String:
	return grid.cells_md5()


func snapshot_cells() -> PackedByteArray:
	return grid.cells.duplicate()


func restore_cells(cells: PackedByteArray) -> bool:
	return grid.restore_cells(cells)


## `progress` runs 0 -> 1 across the wipe. The lenses tip up out of the way and
## back down, which is the part of it everyone else can see.
func set_wipe_progress(progress: float) -> void:
	if _lens == null:
		return
	var lift := sin(clampf(progress, 0.0, 1.0) * PI)
	_lens.rotation.x = deg_to_rad(wipe_lift_degrees) * lift


## The lenses as another player sees them: a small quad on the face carrying the
## same mask. Its own UVs are used, so the grid's (0,0) corner has to be the
## quad's (-u, -v) corner, which is the convention ContaminationGrid.cell_of
## already uses everywhere else.
func _build_lens() -> void:
	_lens = MeshInstance3D.new()
	_lens.name = "Lenses"
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.26, 0.11)
	quad.orientation = PlaneMesh.FACE_Z
	_lens.mesh = quad
	# Clear of the head. The capsule is 0.32 at its waist but only about 0.25
	# across at eye height, which is up in the rounded end of it.
	_lens.position = Vector3(0.0, 0.0, -0.27)
	# The plane faces +Z and the player looks down -Z, so it is turned to face
	# out of the front of the head.
	_lens.rotation.y = PI
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/contamination.gdshader")
	material.set_shader_parameter("mask_texture", grid.texture)
	material.set_shader_parameter("clean_color", lens_color)
	material.set_shader_parameter("mayo_color", mayo_color)
	_lens.material_override = material
	add_child(_lens)
