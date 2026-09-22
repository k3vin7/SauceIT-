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
## How much thicker a cell gets per **pass** -- one trigger pull -- rather than
## per splat that lands on it. A burst lays one layer down over everything it
## reaches; see `ContaminationGrid._coats` for why. The threshold below is set
## against this, so the pair is what decides how many passes it takes.
@export_range(1, 64, 1) var thickness_per_pass := 1
## At or over this, the floor is slippery. Under it, it is a stain.
##
## **Three passes, and it is exactly three** -- no longer a measured compromise.
## While a cell counted splats it could not be: the stream dumps a hundred
## splats on the spot it sits over and one on the far end of the same trail, so
## "one pass is slippery nowhere" and "three passes are slippery mostly" wanted
## thresholds a hundred apart, and 22 was the least bad point between them.
##
## Counting layers removes the spread rather than splitting it. A cell takes a
## layer per `coat_seconds` the stream is on it, so the threshold is just a
## count of times the floor was painted:
##
##     1 pass  -- nothing is slippery, anywhere on the trail
##     2       -- still nothing
##     3       -- all of the overlap is slippery, all of it at once
##
## And sauce still pools where it is parked, which is the point of holding a
## trigger: about a second of the stream sitting on a spot puts a puddle there.
## What it no longer does is get there a hundred times faster than the same
## stream sweeping, which is what made the head of a trail slippery while its
## tail stayed clean.
@export_range(1, 255, 1) var slip_thickness := 3
## The floor is uploaded as tiles and only the changed ones are sent, so this is
## what a frame with sauce landing on it actually costs. Bigger tiles mean fewer
## draw calls and a larger upload when one is touched; smaller means the reverse.
@export_range(32, 4096, 32) var tile_cells := 512

@export_group("Slippery Look")
## Deep mayo is drawn in its own colour rather than a darker shade of the same
## one. The point is that it reads **at a glance while running**, and a gradient
## does not: a runner has to be able to tell at the edge of the patch, not by
## comparing two shades of cream.
@export var deep_color := Color("e8cf4a")

@export_subgroup("Thickness Steps")
## The stain is drawn in **steps**, not one flat colour and not a ramp, so the
## sauce piling up is legible before it flips.
##
## How many steps there is room for follows from `slip_thickness`. At three
## passes to slip there are three:
##
##     1 pass   white, the stain
##     2        heavy cream -- one more pass and this is dangerous
##     3        yellow and wet
##
## `mayo_color_mid` and its threshold are the fourth, and are only drawn if the
## deep band is moved out to four passes or more. They are left in rather than
## deleted because `slip_thickness` is a knob and the shader has the slot.
##
## Each boundary is a hard edge on a cell boundary rather than a blend, for the
## same reason the deep band is: it has to be readable at a glance at a run, and
## a hard edge is what reads.
@export var mayo_color_mid := Color("f5e195")
## The one that matters most: this is the warning. It has to be clearly apart
## from the yellow rather than a shade towards it, so it is duller rather than
## brighter -- same lightness, much less saturation, and the deep band's wet
## shine on top of that.
@export var mayo_color_thick := Color("e6cd80")
## Where white becomes light cream.
@export_range(1, 255, 1) var stain_mid_thickness := 2
## Where light cream becomes heavy cream. Clamped below `slip_thickness`, since
## a step at or past it would simply never be drawn.
@export_range(1, 255, 1) var stain_thick_thickness := 2
@export_range(0.0, 1.0, 0.01) var mayo_roughness := 0.34
@export_range(0.0, 1.0, 0.01) var deep_roughness := 0.06

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


## Returns the centre cell of the splat, or (-1, -1) if it fell off the grid.
## The server broadcasts that cell and every peer replays it through
## `paint_mayo_cell`, so the wire carries two ints per splat rather than the
## cell list, and every grid stays byte-identical.
func paint_mayo(world_position: Vector3, coat := -1) -> Vector2i:
	return grid.paint(_to_grid(world_position), brush_radius, thickness_per_pass, coat)


func paint_mayo_cell(cell: Vector2i, coat := -1) -> void:
	grid.paint_cell(cell, brush_radius, thickness_per_pass, coat)


## Cell-exact: true when there is any mayo at all under this position.
func is_mayo_at(world_position: Vector3) -> bool:
	return grid.is_painted(_to_grid(world_position))


## **Cell-exact: true when the mayo here is thick enough to put someone down.**
##
## This is the question the game asks, and it is asked of the floor rather than
## of the thing standing on it. Nothing player-shaped is in here: an enemy that
## should slip later calls exactly this, and gets exactly the same answer from
## exactly the same data the shader draws.
func is_slippery_at(world_position: Vector3) -> bool:
	return grid.thickness_at(_to_grid(world_position)) >= slip_thickness


## How thick the mayo is here, 0 to 255.
func thickness_at(world_position: Vector3) -> int:
	return grid.thickness_at(_to_grid(world_position))


## Share of the painted floor that is thick enough to slip on, for the debug
## readout. Counted as cells cross the threshold rather than by scanning, so it
## is free to ask -- scanning fourteen million cells twice a second, which is
## what this did first, cost more than everything else the floor does put
## together.
func deep_fraction() -> float:
	if grid.painted_count == 0:
		return 0.0
	return float(grid.deep_count) / float(grid.painted_count)


func deep_cell_count() -> int:
	return grid.deep_count


## Where the two middle steps actually sit, as (mid, thick).
##
## Ordered here rather than trusted from the inspector: a step at or past the
## deep band would never be drawn, and one past the other would swallow it, so
## both are pulled back into range instead of quietly disappearing.
func step_bounds() -> Vector2i:
	var thick := clampi(stain_thick_thickness, 1, maxi(slip_thickness - 1, 1))
	return Vector2i(clampi(stain_mid_thickness, 1, thick), thick)


## Which of the four bands a thickness is drawn in: 0 clean, 1 white, 2 light
## cream, 3 heavy cream, 4 deep. This is the shader's own arithmetic, so a check
## can confirm the band that gets drawn and the thickness that is stored agree.
func step_for_thickness(thickness: int) -> int:
	if thickness <= 0:
		return 0
	if thickness >= slip_thickness:
		return 4
	var bounds := step_bounds()
	if thickness >= bounds.y:
		return 3
	if thickness >= bounds.x:
		return 2
	return 1


func stain_step_at(world_position: Vector3) -> int:
	return step_for_thickness(thickness_at(world_position))


func cells_md5() -> String:
	return grid.cells_md5()


func snapshot_cells() -> PackedByteArray:
	return grid.cells.duplicate()


func restore_cells(cells: PackedByteArray) -> bool:
	return grid.restore_cells(cells)


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

	# One quad per tile rather than one plane for the floor. The mask is uploaded
	# a tile at a time, and a tile is a texture, so each needs its own surface to
	# be sampled on. The floor stays perfectly flat and the quads abut exactly:
	# they are cut on cell boundaries, which is where the mask's own cells are.
	var collision := CollisionShape3D.new()
	collision.name = "FloorCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(floor_size.x, 0.04, floor_size.y)
	collision.shape = box
	collision.position.y = -0.02
	add_child(collision)
	_rebuild_grid()
	_rebuild_tiles()


## A quad per mask tile, laid flat and carrying that tile's material.
func _rebuild_tiles() -> void:
	for index in grid.tile_count():
		var region := grid.tile_region(index)
		var quad := MeshInstance3D.new()
		quad.name = "FloorTile%03d" % index
		var mesh := PlaneMesh.new()
		mesh.size = region.size
		quad.mesh = mesh
		quad.position = Vector3(region.position.x + region.size.x * 0.5, 0.0,
			region.position.y + region.size.y * 0.5)
		quad.material_override = grid.tile_material(index)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		if index == 0:
			_floor_mesh = quad


## Pushes the look and the threshold into every tile's material. The shader
## needs the threshold because the deep band is drawn from the same number the
## slip test reads -- that is what stops the two from ever disagreeing.
func _push_shader_values() -> void:
	for index in grid.tile_count():
		var tile := grid.tile_material(index)
		tile.set_shader_parameter("deep_color", deep_color)
		tile.set_shader_parameter("mayo_color_mid", mayo_color_mid)
		tile.set_shader_parameter("mayo_color_thick", mayo_color_thick)
		tile.set_shader_parameter("mayo_roughness", mayo_roughness)
		tile.set_shader_parameter("deep_roughness", deep_roughness)
		# Normalised, because the texture reads back 0..1.
		tile.set_shader_parameter("paint_threshold",
			maxf(float(thickness_per_pass) * 0.5, 0.5) / 255.0)
		var bounds := step_bounds()
		tile.set_shader_parameter("mid_threshold", float(bounds.x) / 255.0)
		tile.set_shader_parameter("thick_threshold", float(bounds.y) / 255.0)
		tile.set_shader_parameter("slip_threshold", float(slip_thickness) / 255.0)


func _rebuild_grid() -> void:
	grid.configure(floor_size, cell_size, clean_color, mayo_color, tile_cells)
	# The grid keeps the count of cells past it, so it has to know where it is.
	grid.deep_threshold = slip_thickness
	_push_shader_values()
