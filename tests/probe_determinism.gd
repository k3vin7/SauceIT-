extends SceneTree

# The grid sync sends two ints per splat -- the centre cell -- and every peer
# replays it locally. That is only sound if paint() is a pure function of the
# centre cell, so this probe attacks that assumption directly:
#   * two independently built grids given the same centre cells hash identically
#   * replaying through paint_cell matches painting through a world position
#   * different float positions inside one cell produce the same grid, which is
#     what makes the cell-quantised wire format safe against float drift
#   * order of splats does not change the result
#   * a full-grid snapshot restores to the same hash, for a peer joining late
#   * the same is true of a wall's per-face grids
# It also prints the hash so two separate process runs can be compared.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _new_grid() -> ContaminationGrid:
	var grid := ContaminationGrid.new()
	grid.configure(Vector2(12.0, 12.0), 0.1, Color("53616d"), Color("fff0a8"))
	return grid


## A spread of centre cells, including ones that clip the grid edge.
func _splat_cells() -> Array:
	var cells := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x535041
	for _i in 200:
		cells.push_back(Vector2i(rng.randi_range(-3, 122), rng.randi_range(-3, 122)))
	return cells


func _run() -> void:
	var splats := _splat_cells()

	# --- two independent grids, same centre cells, byte-identical result ---
	var left := _new_grid()
	var right := _new_grid()
	for cell in splats:
		left.paint_cell(cell, 0.4)
	for cell in splats:
		right.paint_cell(cell, 0.4)
	print("two instances: %d cells / %s  vs  %d cells / %s" % [
		left.painted_cell_count(), left.cells_md5(),
		right.painted_cell_count(), right.cells_md5()])
	_check(left.cells_md5() == right.cells_md5(),
		"two grids given the same centre cells produced different masks")
	_check(left.painted_cell_count() > 1000,
		"the test painted only %d cells, too few to prove anything" % left.painted_cell_count())

	# --- replaying a centre cell matches painting at a world position ---
	# This is the server/client split: the server paints from the landing
	# position and sends the cell, the client replays the cell.
	var painted_by_position := _new_grid()
	var replayed := _new_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x504f53
	var sent: Array[Vector2i] = []
	for _i in 120:
		var local := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		sent.push_back(painted_by_position.paint(local, 0.4))
	for cell in sent:
		replayed.paint_cell(cell, 0.4)
	print("position vs replayed cell: %s vs %s" % [
		painted_by_position.cells_md5(), replayed.cells_md5()])
	_check(painted_by_position.cells_md5() == replayed.cells_md5(),
		"replaying the broadcast centre cell did not reproduce the painted grid")

	# --- float drift inside a cell cannot change the outcome ---
	# Two machines that disagree by a fraction of a cell about where a strand
	# landed must still paint the same thing once it is quantised to a cell.
	var jittered := _new_grid()
	var straight := _new_grid()
	for _i in 120:
		var local := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		var cell := straight.paint(local, 0.4)
		# Somewhere else inside the same cell, up to a third of a cell away.
		var nudged := local + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
		if jittered.cell_of(nudged) != cell:
			nudged = local
		jittered.paint(nudged, 0.4)
	print("float drift inside a cell: %s vs %s" % [straight.cells_md5(), jittered.cells_md5()])
	_check(straight.cells_md5() == jittered.cells_md5(),
		"a sub-cell difference in the landing position changed the grid")

	# --- splat order does not matter ---
	# Packets are batched per frame, so a reordering inside a batch must be
	# harmless. Painting only ever sets cells, never clears them.
	var forward := _new_grid()
	var backward := _new_grid()
	for cell in splats:
		forward.paint_cell(cell, 0.4)
	var reversed_splats := splats.duplicate()
	reversed_splats.reverse()
	for cell in reversed_splats:
		backward.paint_cell(cell, 0.4)
	print("splat order: %s vs %s" % [forward.cells_md5(), backward.cells_md5()])
	_check(forward.cells_md5() == backward.cells_md5(),
		"replaying the same splats in a different order produced a different grid")

	# --- a snapshot restores byte-exactly, for a peer joining mid-game ---
	var joined := _new_grid()
	var restored: bool = joined.restore_cells(left.cells.duplicate())
	print("snapshot restore: ok=%s, %s" % [str(restored), joined.cells_md5()])
	_check(restored, "restoring a snapshot of the same size failed")
	_check(joined.cells_md5() == left.cells_md5(),
		"a restored snapshot did not match the grid it came from")
	_check(joined.painted_cell_count() == left.painted_cell_count(),
		"the restored snapshot has a different painted cell count")

	# --- the same holds for a wall's six face grids ---
	var wall_a := ContaminableObject.new()
	var wall_b := ContaminableObject.new()
	for wall in [wall_a, wall_b]:
		wall.size = Vector3(1.65, 2.2, 0.18)
		wall.cell_size = 0.1
		wall.brush_radius = 0.4
		root.add_child(wall)
	await process_frame
	var wall_rng := RandomNumberGenerator.new()
	wall_rng.seed = 0x57414c
	var wall_splats := []
	for _i in 60:
		wall_splats.push_back([wall_rng.randi_range(0, 5),
			Vector2i(wall_rng.randi_range(0, 20), wall_rng.randi_range(0, 20))])
	for splat in wall_splats:
		wall_a.paint_mayo_cell(splat[0], splat[1])
	for splat in wall_splats:
		wall_b.paint_mayo_cell(splat[0], splat[1])
	print("wall faces: %d cells / %s" % [wall_a.painted_cell_count(), wall_a.cells_md5()])
	_check(wall_a.cells_md5() == wall_b.cells_md5(),
		"two walls given the same face cells produced different masks")
	_check(wall_a.painted_cell_count() > 100,
		"the wall test painted only %d cells" % wall_a.painted_cell_count())

	_probe_detailed_stamps()
	_probe_clean_floor_batches()
	_probe_shared_sauce_splats()

	# The reference hash. Run this probe twice, in two processes, and compare:
	# a mismatch means paint() depends on something outside the centre cell.
	print("MAYO_GRID_HASH %s" % left.cells_md5())
	if failures.is_empty():
		print("MAYO_DETERMINISM_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _probe_shared_sauce_splats() -> void:
	for cell_size: float in [0.1, 0.05]:
		var ketchup := ContaminationGrid.new()
		ketchup.scatter_ketchup = true
		ketchup.configure(Vector2(4.0, 4.0), cell_size, Color.GRAY, Color.WHITE)
		var centre := ketchup.cell_of(Vector2(0.2, -0.1))
		var brush := ketchup.position_brush(Vector2(0.2, -0.1), ContaminationGrid.stroke_brush(Vector2.RIGHT))
		ketchup.paint_cell(centre, 0.27, 1, -1, ContaminationGrid.KIND_KETCHUP, brush)
		for kind in [ContaminationGrid.KIND_MAYO, ContaminationGrid.KIND_MUSTARD]:
			var sauce := ContaminationGrid.new()
			sauce.shared_splat_shape = true
			sauce.configure(Vector2(4.0, 4.0), cell_size, Color.GRAY, Color.WHITE)
			sauce.paint_cell(centre, 0.27, 1, -1, kind, brush)
			var same_footprint := true
			for index in ketchup.cells.size():
				if (sauce.cells[index] >> ContaminationGrid.KIND_BITS) \
						!= (ketchup.cells[index] >> ContaminationGrid.KIND_BITS) \
						or (sauce.cells[index] > 0 and (sauce.cells[index] & ContaminationGrid.KIND_MASK) != kind):
					same_footprint = false
					break
			_check(same_footprint and sauce.contour_cells == ketchup.contour_cells,
				"sauce %d had a different splat footprint from ketchup at %s m" % [kind, cell_size])


func _probe_detailed_stamps() -> void:
	var author := ContaminationGrid.new()
	var replica := ContaminationGrid.new()
	for grid in [author, replica]:
		grid.configure(Vector2(1.0, 1.0), 0.025, Color.GRAY, Color.WHEAT)
		grid.wrap_x = true
	var center := Vector2i(0, 20)
	var sauce := ContaminationGrid.KIND_MUSTARD
	var brush := ContaminationGrid.stroke_brush(Vector2.RIGHT)
	author.paint_cell(center, 0.2, 1, 7, sauce, brush)
	replica.paint_cell(center, 0.2, 1, 7, sauce, brush)
	_check(author.snapshot() == replica.snapshot(), "a directional fine stamp did not replay byte-for-byte")
	var received := ContaminationGrid.new()
	received.configure(Vector2(1.0, 1.0), 0.025, Color.GRAY, Color.WHEAT)
	_check(received.restore_cells(author.snapshot()) and received.snapshot() == author.snapshot(),
		"a snapshot lost the continuous stain edge")
	_check(author.cells[center.y * author.width + author.width - 1] > 0,
		"a directional stamp stopped at the wrap seam")
	var before := author.cells.duplicate()
	_check(author.paint_cell(center, 0.2, 1, 7, sauce, brush).x < 0 and author.cells == before,
		"a repeated fine stamp counted the same coat twice")

	_check(author.erase_disc(center, 0.11) and replica.erase_disc(center, 0.11), "fine wash did not remove sauce")
	_check(author.snapshot() == replica.snapshot() and author.cells[center.y * author.width] == 0,
		"fine wash did not clear the centre or replay its edge")

	# A no-op cannot change the authority's coat history if peers receive no packet.
	var fleck := ContaminationGrid.BRUSH_FLECK
	for grid in [author, replica]:
		grid.fill_rect(Vector2i.ZERO, Vector2i(grid.width - 1, grid.height - 1),
			ContaminationGrid.MAX_THICKNESS, sauce)
	_check(author.paint_cell(center, 0.2, 1, 8, sauce, fleck).x < 0
		and author._coats.keys() == replica._coats.keys(), "a saturated fine stamp changed the active coats")

	author.clear()
	author.paint_cell(center, 0.2, 1, 9, sauce, brush)
	author.upload_if_dirty()
	var first_upload := author.bytes_uploaded
	var contour := author.contour_cells.duplicate()
	author.paint_cell(center, 0.2, 1, 10, sauce, brush)
	author.upload_if_dirty()
	_check(first_upload == author.cells.size() * 2 and author.bytes_uploaded == author.cells.size()
		and contour == author.contour_cells and author.image.get_data() == author.cells,
		"stacking the same stamp did not upload only the changed thickness")


func _probe_clean_floor_batches() -> void:
	var floor := FloorContamination.new()
	floor.floor_size = Vector2(3.2, 3.2)
	floor.cell_size = 0.05
	floor.tile_cells = 32
	floor.batch_clean_tiles = true
	root.add_child(floor)
	var batch := floor._batches_by_tile[0]
	_check(batch.clean.visible and batch.tiles.size() == 4 and not batch.tiles[0].visible,
		"clean floor did not draw its four tiles as one mesh")
	var centre := Vector2i(31, 31)
	floor.grid.paint_cell(centre, 0.2, 1, -1, ContaminationGrid.KIND_MUSTARD)
	floor.grid.upload_if_dirty(1)
	_check(batch.clean.visible and batch.tiles[0].visible and batch.painted_mask == 1,
		"the first painted tile did not leave the clean batch independently")
	for slot in range(1, 4):
		_check(not batch.tiles[slot].visible, "a clean neighbour left the batch")
	floor.grid.upload_if_dirty()
	_check(not batch.clean.visible and batch.painted_mask == 15,
		"the clean batch still draws after all four tiles hold paint")
	floor.grid.erase_disc(centre, 0.65)
	floor.grid.upload_if_dirty()
	_check(batch.clean.visible and not batch.tiles[0].visible and batch.painted_mask == 0,
		"washing across the tile seam did not restore the clean batch")
	floor.queue_free()
