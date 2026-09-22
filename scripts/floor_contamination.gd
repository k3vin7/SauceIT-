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
## How much thicker a cell gets per splat that lands on it. The threshold below
## is set against this, so the pair is what decides how many passes it takes.
@export_range(1, 64, 1) var thickness_per_splat := 1
## At or over this, the floor is slippery. Under it, it is a stain.
##
## 22 is measured, and it is a **compromise between two aims that cannot both
## be met**, which is worth stating rather than hiding in a number.
##
## Walking past spraying at a steady pace, then walking the same line again:
##
##     passes   median   p90   peak
##          1        9    18     49
##          2       17    36     97
##          3       25    54    145
##
## A pass does not lay sauce down evenly. It leaves a thick ridge where the
## stream's landing point clusters and a thin fringe either side, so one pass's
## **peak (49) is twice three passes' median (25)**. The two aims -- "once over
## is slippery nowhere" and "three times over is slippery mostly" -- therefore
## pull opposite ways, and no single number satisfies both:
##
##     threshold   1 pass deep   3 passes deep
##            50            0%             16%
##            25            5%             51%
##            22            5%             57%
##            20            7%             61%
##
## 50 was the first attempt and took the first aim literally: nothing is ever
## slippery after one pass, and three passes leave only a sixth of the trail
## slippery -- so painting a patch three times and finding it safe, which is
## exactly what it looked like from the outside, and what it was reported as.
##
## 22 takes the other side. Three passes make most of the trail dangerous, and
## one pass makes the very middle of its own ridge dangerous -- about a
## twentieth of it. That residue is the better error of the two: slipping in the
## middle of the mess you just made is a lesson, and spraying a floor three
## times for nothing is a broken mechanic.
##
## Meeting both strictly needs the *ridge* flattened rather than the threshold
## moved -- a cell gains one unit per strand point that lands on it, and three
## land per frame right under the stream against one at the fringe, so capping
## a cell's gain per frame rather than per point would narrow the spread. That
## is a change to the paint path and has not been made.
@export_range(1, 255, 1) var slip_thickness := 22
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
func paint_mayo(world_position: Vector3) -> Vector2i:
	return grid.paint(_to_grid(world_position), brush_radius, thickness_per_splat)


func paint_mayo_cell(cell: Vector2i) -> void:
	grid.paint_cell(cell, brush_radius, thickness_per_splat)


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
		tile.set_shader_parameter("mayo_roughness", mayo_roughness)
		tile.set_shader_parameter("deep_roughness", deep_roughness)
		# Normalised, because the texture reads back 0..1.
		tile.set_shader_parameter("paint_threshold",
			maxf(float(thickness_per_splat) * 0.5, 0.5) / 255.0)
		tile.set_shader_parameter("slip_threshold", float(slip_thickness) / 255.0)


func _rebuild_grid() -> void:
	grid.configure(floor_size, cell_size, clean_color, mayo_color, tile_cells)
	# The grid keeps the count of cells past it, so it has to know where it is.
	grid.deep_threshold = slip_thickness
	_push_shader_values()
