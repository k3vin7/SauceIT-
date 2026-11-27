class_name FloorContamination
extends StaticBody3D

## Floor carrying one projected contamination grid. The grid is also the source of
## truth for the slip test, so what is drawn and what trips the player are the
## same data.

@export_group("Contamination Grid")
@export_range(0.05, 0.5, 0.005, "suffix:m") var cell_size := 0.1
@export_range(0.05, 1.5, 0.01, "suffix:m") var brush_radius := 0.4
@export var floor_size := Vector2(12.0, 12.0)
@export var clean_color := Color("53616d")
var pavement_mask: Texture2D
var pavement_bounds := Rect2()
var terrain_height: Callable
var terrain_regions: Array[Rect2] = []
@export var mayo_color := Color("fff0a8")
## How much thicker a cell gets per **pass** -- one trigger pull -- rather than
## per splat that lands on it. A burst lays one layer down over everything it
## reaches; see `ContaminationGrid._coats` for why. The threshold below is set
## against this, so the pair is what decides how many passes it takes.
@export_range(1, 63, 1) var thickness_per_pass := 1
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
@export_range(1, 63, 1) var slip_thickness := 3
## How many layers of mustard it takes before the floor drags. Lower than the
## slip threshold on purpose: mustard is meant to be laid down and used, so a
## single pass across a doorway should already be worth something, where mayo
## needs the three passes that make a puddle the player can see coming.
@export_range(1, 63, 1) var slow_thickness := 2
## The floor is uploaded as tiles and only the changed ones are sent, so this is
## what a frame with sauce landing on it actually costs. Bigger tiles mean fewer
## draw calls and a larger upload when one is touched; smaller means the reverse.
@export_range(32, 4096, 32) var tile_cells := 512
## Extra samples across each tile edge, for the filtered sauce contour.
var tile_sample_margin := 0

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
@export_range(1, 63, 1) var stain_mid_thickness := 2
## Where light cream becomes heavy cream. Clamped below `slip_thickness`, since
## a step at or past it would simply never be drawn.
@export_range(1, 63, 1) var stain_thick_thickness := 2
@export_range(0.0, 1.0, 0.01) var mayo_roughness := 0.34
@export_range(0.0, 1.0, 0.01) var deep_roughness := 0.06

class FloorBatch:
	var clean: MeshInstance3D
	var tiles: Array[MeshInstance3D] = []
	var painted_mask := 0


var grid := ContaminationGrid.new()
var _floor_mesh: MeshInstance3D
var upload_tiles_per_frame := 0
var batch_clean_tiles := false
var _batches_by_tile: Array[FloorBatch] = []
var _batch_slots_by_tile := PackedByteArray()
var _clean_batch_materials: Dictionary[int, ShaderMaterial] = {}
var _festival_before_attack := false


func _ready() -> void:
	add_to_group("mayo_floor")
	grid.tile_paint_changed.connect(_on_tile_paint_changed)
	_rebuild_floor()


func _process(_delta: float) -> void:
	if not grid.dirty:
		return
	var focus := Vector2.INF
	var camera := get_viewport().get_camera_3d()
	if upload_tiles_per_frame > 0 and camera != null:
		var at := to_local(camera.global_position)
		focus = Vector2(at.x, at.z)
	grid.upload_if_dirty(upload_tiles_per_frame, focus)


func configure(new_cell_size: float, new_brush_radius: float) -> void:
	var grid_changed := not is_equal_approx(cell_size, new_cell_size)
	cell_size = new_cell_size
	brush_radius = new_brush_radius
	if grid_changed and is_node_ready():
		_rebuild_floor()


## Returns the centre cell of the splat, or (-1, -1) if it fell off the grid.
## The server broadcasts that cell and every peer replays it through
## `paint_mayo_cell`, so the wire carries two ints per splat rather than the
## cell list, and every grid stays byte-identical.
## `kind` is which sauce is landing, and it defaults to mayo so that every
## caller written when there was only one sauce still means what it said.
func paint_mayo(world_position: Vector3, coat := -1,
		kind := ContaminationGrid.KIND_MAYO, brush := ContaminationGrid.BRUSH_POOL) -> Vector2i:
	return grid.paint(_to_grid(world_position), brush_radius, thickness_per_pass,
		coat, kind, brush)


func paint_mayo_cell(cell: Vector2i, coat := -1,
		kind := ContaminationGrid.KIND_MAYO, brush := ContaminationGrid.BRUSH_POOL) -> void:
	grid.paint_cell(cell, brush_radius, thickness_per_pass, coat, kind, brush)


## Returns the center of the wash patch when it cleared any sauce.
func wash_at(world_position: Vector3) -> Vector2i:
	var cell := wash_cell_at(world_position)
	return cell if wash_cell(cell) else Vector2i(-1, -1)


func wash_cell_at(world_position: Vector3) -> Vector2i:
	return grid.cell_of(_to_grid(world_position))


func wash_cell(cell: Vector2i, radius_meters := 0.42) -> bool:
	return grid.erase_disc(cell, radius_meters)


func is_mayo_at(world_position: Vector3) -> bool:
	return grid.is_painted(_to_grid(world_position))


## **Cell-exact: true when the mayo here is thick enough to put someone down.**
##
## This is the question the game asks, and it is asked of the floor rather than
## of the thing standing on it. Nothing player-shaped is in here: an enemy that
## should slip later calls exactly this, and gets exactly the same answer from
## exactly the same data the shader draws.
## **Mayo only.** A cell holds one sauce, so asking whether the floor is
## slippery is asking whether the sauce on it is the slippery one. Left as a
## thickness test alone, a mustard puddle laid down to slow a monster would put
## the party on the ground as well -- the two effects would be the same patch,
## and the one the player aimed for would be indistinguishable from the one they
## were punished by.
func is_slippery_at(world_position: Vector3) -> bool:
	var sauce := grid.sauce_at(_to_grid(world_position))
	return sauce.y == ContaminationGrid.KIND_MAYO and sauce.x >= slip_thickness


## **Mustard only: true where the floor drags on whatever is standing in it.**
##
## The mirror of `is_slippery_at`, and deliberately the same shape: asked of the
## floor, answered off the same bytes the shader draws, and player-shaped in no
## way at all, so an enemy wading through mustard is slowed by the same call.
func is_slowing_at(world_position: Vector3) -> bool:
	var sauce := grid.sauce_at(_to_grid(world_position))
	return sauce.y == ContaminationGrid.KIND_MUSTARD and sauce.x >= slow_thickness


## How thick the sauce here is, 0 to `ContaminationGrid.MAX_THICKNESS`.
func thickness_at(world_position: Vector3) -> int:
	return grid.thickness_at(_to_grid(world_position))


## Which sauce is under this position. Meaningless on a clean cell -- it reads
## as mayo -- so ask `thickness_at` first.
func sauce_kind_at(world_position: Vector3) -> int:
	return grid.kind_at(_to_grid(world_position))


## Floods the floor between two world corners to `thickness` of `kind`,
## straight into the grid: no brush, no edge noise, no coat. The high corner
## is exclusive, so two patches that share an edge do not overlap.
func fill_rect(low: Vector3, high: Vector3, thickness: int, kind: int) -> void:
	var a := grid.cell_of(_to_grid(low))
	var b := grid.cell_of(_to_grid(high))
	grid.fill_rect(Vector2i(mini(a.x, b.x), mini(a.y, b.y)),
		Vector2i(maxi(a.x, b.x) - 1, maxi(a.y, b.y) - 1), thickness, kind)


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
	return grid.snapshot()


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

	_rebuild_grid()
	var terrain_faces := _rebuild_tiles()
	var collision := CollisionShape3D.new()
	collision.name = "FloorCollision"
	if terrain_height.is_valid():
		var surface := ConcavePolygonShape3D.new()
		surface.set_faces(terrain_faces)
		collision.shape = surface
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(floor_size.x, 0.04, floor_size.y)
		collision.shape = box
		collision.position.y = -0.02
	add_child(collision)


## Each tile keeps its planar UVs so every peer still addresses the same sauce
## cells. The terrain collision is assembled from the rendered triangles.
func _rebuild_tiles() -> PackedVector3Array:
	var faces := PackedVector3Array()
	var tiles: Array[MeshInstance3D] = []
	_batches_by_tile.clear()
	_batch_slots_by_tile.clear()
	_clean_batch_materials.clear()
	for index in grid.tile_count():
		var region := grid.tile_region(index)
		var quad := MeshInstance3D.new()
		quad.name = "FloorTile%03d" % index
		if terrain_height.is_valid():
			var mesh := _terrain_tile(region, _tile_has_relief(region))
			quad.mesh = mesh
			faces.append_array(mesh.get_faces())
		else:
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
		tiles.append(quad)
	if batch_clean_tiles:
		_build_clean_batches(tiles)
	return faces


## Keep the clean part of each 2x2 group in one draw. Each tile's vertices
## carry its local slot so a painted tile can leave the batch independently.
func _build_clean_batches(tiles: Array[MeshInstance3D]) -> void:
	var clean_material := grid.tile_material(0).duplicate() as ShaderMaterial
	clean_material.set_shader_parameter("mask_texture", null)
	clean_material.set_shader_parameter("contour_texture", null)
	clean_material.set_shader_parameter("fine_contours", false)
	_clean_batch_materials[0] = clean_material
	var batches: Dictionary[Vector2i, FloorBatch] = {}
	for index in tiles.size():
		var key := grid.tile_origin(index) / (grid.tile_cells * 2)
		if not batches.has(key):
			batches[key] = FloorBatch.new()
		var batch: FloorBatch = batches[key]
		_batch_slots_by_tile.append(batch.tiles.size())
		batch.tiles.append(tiles[index])
		_batches_by_tile.append(batch)
	for batch: FloorBatch in batches.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tile_slots := PackedVector2Array()
		for slot in batch.tiles.size():
			var tile := batch.tiles[slot]
			surface.append_from(tile.mesh, 0, tile.transform)
			var offset := tile_slots.size()
			var vertices: PackedVector3Array = tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var end := offset + vertices.size()
			tile_slots.resize(end)
			for vertex in range(offset, end):
				tile_slots[vertex] = Vector2(slot, 0.0)
			tile.hide()
		var arrays := surface.commit_to_arrays()
		arrays[Mesh.ARRAY_TEX_UV2] = tile_slots
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		batch.clean = MeshInstance3D.new()
		batch.clean.mesh = mesh
		batch.clean.material_override = clean_material
		batch.clean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch.clean)


func _on_tile_paint_changed(index: int, has_paint: bool) -> void:
	var batch := _batches_by_tile[index]
	var slot := int(_batch_slots_by_tile[index])
	var bit := 1 << slot
	batch.painted_mask = batch.painted_mask | bit if has_paint else batch.painted_mask & ~bit
	batch.tiles[slot].visible = has_paint
	batch.clean.visible = batch.painted_mask != (1 << batch.tiles.size()) - 1
	if not batch.clean.visible:
		return
	# Every batch with this mask shares a material. Per-instance shader
	# uniforms exhaust the Compatibility renderer's slots on the full map.
	var material := _clean_batch_materials.get(batch.painted_mask) as ShaderMaterial
	if material == null:
		material = _clean_batch_materials[0].duplicate() as ShaderMaterial
		material.set_shader_parameter("painted_floor_tiles", batch.painted_mask)
		_clean_batch_materials[batch.painted_mask] = material
	batch.clean.material_override = material


func set_festival_before_attack(enabled: bool) -> void:
	_festival_before_attack = enabled
	for index in grid.tile_count():
		grid.tile_material(index).set_shader_parameter("festival_before_attack", enabled)
	for material in _clean_batch_materials.values():
		material.set_shader_parameter("festival_before_attack", enabled)


func _tile_has_relief(region: Rect2) -> bool:
	if terrain_regions.is_empty():
		return true
	var origin := Vector2(global_position.x, global_position.z)
	# Normals sample up to a metre beyond each tile. Keep that margin so a
	# coarse flat tile always meets a flat edge even beside a sloped tile.
	var world_region := Rect2(region.position + origin, region.size).grow(1.0)
	for bounds in terrain_regions:
		if world_region.intersects(bounds):
			return true
	return false


func _terrain_tile(region: Rect2, has_relief: bool) -> ArrayMesh:
	var columns := maxi(1, ceili(region.size.x / 2.0)) if has_relief else 1
	var rows := maxi(1, ceili(region.size.y / 2.0)) if has_relief else 1
	var stride := columns + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(rows + 1):
		for column in range(columns + 1):
			var uv := Vector2(float(column) / columns, float(row) / rows)
			var flat := region.position + uv * region.size
			var at := Vector3(flat.x, -global_position.y, flat.y)
			var normal := Vector3.UP
			if has_relief:
				var sample := at + global_position
				at.y += float(terrain_height.call(sample))
				var rise_x: float = terrain_height.call(sample + Vector3.RIGHT) \
					- terrain_height.call(sample + Vector3.LEFT)
				var rise_z: float = terrain_height.call(sample + Vector3.BACK) \
					- terrain_height.call(sample + Vector3.FORWARD)
				normal = Vector3(-rise_x, 2.0, -rise_z).normalized()
			vertices.push_back(at)
			normals.push_back(normal)
			uvs.push_back(uv)
	for row in rows:
		for column in columns:
			var corner := row * stride + column
			indices.append_array(PackedInt32Array([corner, corner + 1, corner + stride,
				corner + 1, corner + stride + 1, corner + stride]))
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_TEX_UV] = uvs
	surface[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


## Pushes the look and the threshold into every tile's material. The shader
## needs the threshold because the deep band is drawn from the same number the
## slip test reads -- that is what stops the two from ever disagreeing.
func _push_shader_values() -> void:
	for index in grid.tile_count():
		var tile := grid.tile_material(index)
		if pavement_mask != null:
			tile.set_shader_parameter("paved", true)
			tile.set_shader_parameter("pavement_mask", pavement_mask)
			tile.set_shader_parameter("pavement_origin", pavement_bounds.position)
			tile.set_shader_parameter("pavement_size", pavement_bounds.size)
		tile.set_shader_parameter("deep_color", deep_color)
		tile.set_shader_parameter("mayo_color_mid", mayo_color_mid)
		tile.set_shader_parameter("mayo_color_thick", mayo_color_thick)
		tile.set_shader_parameter("mayo_roughness", mayo_roughness)
		tile.set_shader_parameter("deep_roughness", deep_roughness)
		# Normalised, because the texture reads back 0..1 -- and shifted up by
		# the sauce bits first, because a thickness of `t` is stored as
		# `t << KIND_BITS`. Every cut-off below is a thickness, so they all move
		# by the same factor and the bands land exactly where they did.
		var pack := float(1 << ContaminationGrid.KIND_BITS)
		tile.set_shader_parameter("paint_threshold",
			maxf(float(thickness_per_pass) * 0.5, 0.5) * pack / 255.0)
		var bounds := step_bounds()
		tile.set_shader_parameter("mid_threshold", float(bounds.x) * pack / 255.0)
		tile.set_shader_parameter("thick_threshold", float(bounds.y) * pack / 255.0)
		tile.set_shader_parameter("slip_threshold", float(slip_thickness) * pack / 255.0)


func _rebuild_grid() -> void:
	grid.track_tile_paint = batch_clean_tiles
	grid.configure(floor_size, cell_size, clean_color, mayo_color, tile_cells, tile_sample_margin)
	grid.scatter_ketchup = pavement_mask != null
	# The grid keeps the count of cells past it, so it has to know where it is.
	grid.deep_threshold = slip_thickness
	_push_shader_values()
	set_festival_before_attack(_festival_before_attack)
