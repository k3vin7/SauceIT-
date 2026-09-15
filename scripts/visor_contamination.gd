class_name VisorContamination
extends Node3D

## The player's glasses: a contamination grid worn on the face.
##
## Sauce that lands on the lenses is painted here, and this mask is what blinds
## you -- there is no separate screen effect to keep in step with it. Like the
## body, the grid and brush are measured in metres. The lens has the same 16:9
## shape as the screen, so the mask can still be sampled 1:1 by the overlay.
##
## It hangs off the aim pivot, which already carries the aim pitch, so it moves
## exactly with the camera -- sauce on your lenses stays where it landed on the
## screen as you look around, the way sauce on glasses does. Being a real object
## on the head, it is also visible to everyone else: they can see your lenses
## are filthy, and see you stop to wipe them.

## The lenses as an object: as wide as the head is at eye height, and 16:9, the
## shape of the mask they carry. The contamination grid spans this physical size.
const LENS_SIZE := Vector2(1.00, 0.56)
const LENS_DISTANCE := 0.54

## Configured from the body's cell size, so both surfaces use the same metre grid.
@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size := 0.1
## The world's brush in metres, shared with the body, floor and walls.
@export_range(0.01, 1.5, 0.005, "suffix:m") var brush_radius := 0.4
@export var mayo_color := Color("fff0a8")
@export var lens_color := Color(0.12, 0.15, 0.19, 1.0)
## How far the lenses tip up while they are being wiped.
@export_range(0.0, 90.0, 1.0, "suffix:°") var wipe_lift_degrees := 55.0

var grid := ContaminationGrid.new()

var _lens: MeshInstance3D
## The lenses swing on this rather than on the mesh itself: the mesh's own
## rotation is the base that faces it forward, and an animation writing to the
## same axis would wipe that out every frame.
var _hinge: Node3D


## Uses the same cell size and brush radius as the body. Both are in metres.
func configure(new_cell_size: float, new_brush_radius: float) -> void:
	cell_size = new_cell_size
	brush_radius = new_brush_radius


func _ready() -> void:
	grid.configure(LENS_SIZE, cell_size, lens_color, mayo_color)
	_build_lens()


func _process(_delta: float) -> void:
	grid.upload_if_dirty()


## Projects a body hit from the eye onto the physical lens plane, then paints in
## the lens's local X/Y metres. Anything level with the lenses or behind them
## misses: it is not in front of your eyes, so it does not blind you.
func paint_from_hit(direction: Vector3) -> Vector2i:
	if direction.z >= -0.001:
		return Vector2i(-1, -1)
	var scale := LENS_DISTANCE / -direction.z
	var lens_position := Vector2(direction.x, direction.y) * scale
	return grid.paint(lens_position, brush_radius)


func paint_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius)


func clear() -> void:
	grid.clear()


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
	if _hinge == null:
		return
	var lift := sin(clampf(progress, 0.0, 1.0) * PI)
	_hinge.rotation.x = deg_to_rad(wipe_lift_degrees) * lift


## How far the lenses are tipped up, in radians. What everyone else sees of a
## wipe, and what the checks measure it by.
func wipe_lift() -> float:
	return 0.0 if _hinge == null else absf(_hinge.rotation.x)


## The lenses as another player sees them: a small quad on the face carrying the
## same mask. Its own UVs are used, so the grid's (0,0) corner has to be the
## quad's (-u, -v) corner, which is the convention ContaminationGrid.cell_of
## already uses everywhere else.
func _build_lens() -> void:
	_hinge = Node3D.new()
	_hinge.name = "LensHinge"
	add_child(_hinge)

	_lens = MeshInstance3D.new()
	_lens.name = "Lenses"
	var quad := PlaneMesh.new()
	quad.size = LENS_SIZE
	quad.orientation = PlaneMesh.FACE_Z
	_lens.mesh = quad
	# Clear of the head. The capsule is 0.64 at its waist but only about 0.50
	# across at eye height, which is up in the rounded end of it.
	_lens.position = Vector3(0.0, 0.0, -LENS_DISTANCE)
	# The plane faces +Z and the player looks down -Z, so it is turned to face
	# out of the front of the head. About X, not Y: both turns face it forward,
	# but turning about Y takes the mesh's +X with it, and the mask would come
	# out mirrored -- sauce on the wearer's right drawn on their left. About X
	# the mesh's +X stays the wearer's right, and the flip it does apply to Y
	# is the one the mask needs, since a PlaneMesh's v counts downwards and the
	# grid's counts up.
	_lens.rotation.x = PI
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/contamination.gdshader")
	material.set_shader_parameter("mask_texture", grid.texture)
	material.set_shader_parameter("clean_color", lens_color)
	material.set_shader_parameter("mayo_color", mayo_color)
	_lens.material_override = material
	_hinge.add_child(_lens)
