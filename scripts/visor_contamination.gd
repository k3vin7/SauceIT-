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

## The lenses as an object: as wide as the head is at eye height, and the shape
## of the mask they carry. The height is a whole number of 0.1 m cells on
## purpose -- 0.56 rounded to six rows and the mask was then drawn across 0.56 m,
## so every row sat 7% away from where it was painted.
const LENS_SIZE := Vector2(1.00, 0.60)
const LENS_DISTANCE := 0.54

## What the wearer's camera shows, which is what the mask has to line up with.
## The defaults are the game's own until the wearer says otherwise; on the host
## they are replaced by the values that wearer reported, so a hit is painted
## where it appeared on *their* screen rather than on a guessed one.
const DEFAULT_FOV_DEGREES := 74.0
const DEFAULT_ASPECT := 16.0 / 9.0

## Configured from the body's cell size, so both surfaces use the same metre grid.
@export_range(0.005, 0.2, 0.001, "suffix:m") var cell_size := 0.1
## The world's brush in metres, shared with the body, floor and walls.
@export_range(0.01, 1.5, 0.005, "suffix:m") var brush_radius := 0.4
@export var mayo_color := Color("fff0a8")
@export var lens_color := Color(0.12, 0.15, 0.19, 1.0)
## How far the lenses tip up while they are being wiped.
@export_range(0.0, 90.0, 1.0, "suffix:°") var wipe_lift_degrees := 55.0

var grid := ContaminationGrid.new()
var view_fov_degrees := DEFAULT_FOV_DEGREES
var view_aspect := DEFAULT_ASPECT

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


## The wearer's camera, as the host has been told it is. Called on whichever
## machine owns the painting, so the mask is built against the screen it will be
## drawn on.
func set_view(fov_degrees: float, aspect: float) -> void:
	view_fov_degrees = fov_degrees
	view_aspect = aspect


## Projects a body hit through the wearer's camera frustum and paints where it
## lands on their screen. Anything level with the eyes or behind them misses: it
## is not in front of you, so it does not blind you.
##
## The lens plane itself is not what the hit is projected onto any more. It
## covers 86 degrees across and 55 up and down, where a 74-degree 16:9 camera
## covers 106 and 74, so a hit came out 1.45 times further from the centre than
## it looked on screen and anything past two thirds of the way out was thrown
## away entirely. The mask is the screen, so the screen's own frustum is what it
## has to be divided by.
func paint_from_hit(direction: Vector3) -> Vector2i:
	var depth := -direction.z
	if depth <= 0.001:
		return Vector2i(-1, -1)
	var tan_up := tan(deg_to_rad(view_fov_degrees) * 0.5)
	var tan_across := tan_up * view_aspect
	# -1 to 1 across the screen, then out to the mask's own metres.
	var screen := Vector2(
		direction.x / (depth * tan_across),
		direction.y / (depth * tan_up))
	return grid.paint(screen * LENS_SIZE * 0.5, brush_radius)


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
