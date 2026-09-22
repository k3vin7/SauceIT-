extends SceneTree

# Mayo has a thickness, and only deep mayo puts you down.
#
#   * a splat adds to a cell rather than flagging it, so a stream that lands
#     every frame builds up instead of tripping a flag on its first frame
#   * one pass over a patch leaves a stain nobody slips on
#   * enough passes make it slippery, and the slip test says so
#   * the slip test is a question asked of the *floor*, not of the player: the
#     same call is what an enemy will use
#   * the floor is uploaded a tile at a time, so a frame with sauce landing on
#     it sends a tile and not the whole map

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.debug_clear_enemies()
	scene.debug_input_override = true
	var floor_node: FloorContamination = scene._floor
	var grid: ContaminationGrid = floor_node.grid
	var player: MayoPlayer = scene._player

	print("deposit %d per splat, slippery at %d, floor %dx%d in %d tiles of %d cells" % [
		floor_node.thickness_per_splat, floor_node.slip_thickness,
		grid.width, grid.height, grid.tile_count(), floor_node.tile_cells])

	# --- a splat adds, it does not flag ---
	var spot := floor_node.to_global(Vector3(4.0, 0.0, 4.0))
	var thicknesses := PackedInt32Array()
	for splat in 6:
		floor_node.paint_mayo(spot)
		thicknesses.push_back(floor_node.thickness_at(spot))
	print("six splats on one spot: thickness went %s" % str(thicknesses))
	_check(thicknesses[0] > 0, "a splat left no thickness at all")
	_check(thicknesses[5] > thicknesses[0],
		"six splats left the same thickness as one: it is flagging, not piling up")
	_check(thicknesses[5] == thicknesses[0] * 6,
		"thickness did not add evenly: %s" % str(thicknesses))
	# And it stops at the top of the byte rather than wrapping round to nothing.
	for _splat in 300:
		floor_node.paint_mayo(spot)
	print("after 306 splats: thickness %d (a byte tops out at 255)" % floor_node.thickness_at(spot))
	_check(floor_node.thickness_at(spot) == 255,
		"thickness saturated at %d rather than 255" % floor_node.thickness_at(spot))

	# --- one pass is a stain; several are a hazard ---
	grid.clear()
	var stand: float = scene.spawn_position_for(0).y
	var home: Vector3 = scene.spawn_position_for(0)
	var thin_peak := 0
	var deep_peak := 0
	for sweep in 4:
		player.global_position = home
		player.velocity = Vector3.ZERO
		scene.debug_set_aim(0.0, -38.0)
		await physics_frame
		scene._local.sauce = 1.0
		scene.debug_set_input(Vector2(0.0, -1.0), false, true)
		for _f in 70:
			scene._local.sauce = 1.0
			await physics_frame
		scene.debug_set_input(Vector2.ZERO, false, false)
		for _f in 45:
			await physics_frame
		var peak := 0
		for cell in grid.cells:
			if cell > peak:
				peak = cell
		if sweep == 0:
			thin_peak = peak
			print("after one pass: thickest cell %d, %d cells at or over the threshold" % [
				peak, floor_node.deep_cell_count()])
			# The headline claim: walking your own one-pass trail is safe.
			_check(peak < floor_node.slip_thickness,
				"one pass already reached %d, at or over the %d that trips: nothing would be safe"
					% [peak, floor_node.slip_thickness])
			_check(floor_node.deep_cell_count() == 0,
				"one pass left %d slippery cells" % floor_node.deep_cell_count())
		deep_peak = peak
	print("after four passes: thickest cell %d, %d slippery cells, %.0f%% of the stain" % [
		deep_peak, floor_node.deep_cell_count(), floor_node.deep_fraction() * 100.0])
	_check(deep_peak >= floor_node.slip_thickness,
		"four passes only reached %d, under the %d that trips: nothing would ever be slippery"
			% [deep_peak, floor_node.slip_thickness])
	_check(floor_node.deep_cell_count() > 0, "four passes left no slippery cells")

	# --- the running counts agree with counting ---
	# `painted_cell_count` and `deep_cell_count` are kept as cells change rather
	# than found by scanning, because something asks them a few times a second
	# and the floor is fourteen million cells. A running count that drifts is
	# invisible -- it just quietly reports the wrong number forever -- so it is
	# checked against the scan it replaced.
	var scanned_painted := 0
	var scanned_deep := 0
	for cell in grid.cells:
		if cell > 0:
			scanned_painted += 1
			if cell >= floor_node.slip_thickness:
				scanned_deep += 1
	print("counts: %d painted / %d deep running, %d / %d by scanning" % [
		grid.painted_count, grid.deep_count, scanned_painted, scanned_deep])
	_check(grid.painted_count == scanned_painted,
		"the running painted count says %d and counting says %d" % [
			grid.painted_count, scanned_painted])
	_check(grid.deep_count == scanned_deep,
		"the running deep count says %d and counting says %d" % [
			grid.deep_count, scanned_deep])
	_check(grid.deep_threshold == floor_node.slip_thickness,
		"the grid counts past %d while the floor trips at %d" % [
			grid.deep_threshold, floor_node.slip_thickness])
	# And a wipe puts them both back to nothing.
	var kept := grid.cells.duplicate()
	grid.clear()
	_check(grid.painted_count == 0 and grid.deep_count == 0,
		"clearing the floor left the counts at %d / %d" % [
			grid.painted_count, grid.deep_count])
	# Restoring a peer's floor has to recount, not carry the cleared numbers on.
	grid.restore_cells(kept)
	_check(grid.painted_count == scanned_painted and grid.deep_count == scanned_deep,
		"a restored floor reports %d / %d rather than %d / %d" % [
			grid.painted_count, grid.deep_count, scanned_painted, scanned_deep])

	# --- the slip test is the floor's, and reads the same cells ---
	var disagreed := 0
	var sampled := 0
	for cell_y in range(0, grid.height, 29):
		for cell_x in range(0, grid.width, 31):
			var thickness: int = grid.cells[cell_y * grid.width + cell_x]
			if thickness == 0:
				continue
			sampled += 1
			var at := floor_node.to_global(Vector3(
				(float(cell_x) + 0.5) * grid.cell_size - grid.extent.x * 0.5, 0.0,
				(float(cell_y) + 0.5) * grid.cell_size - grid.extent.y * 0.5))
			if floor_node.is_slippery_at(at) != (thickness >= floor_node.slip_thickness):
				disagreed += 1
	print("slip test vs stored thickness over %d painted cells: %d disagree" % [sampled, disagreed])
	_check(sampled > 0, "no painted cells were sampled, so this tests nothing")
	_check(disagreed == 0,
		"the slip test disagreed with the thickness it is supposed to read on %d cells" % disagreed)

	# --- and it is a question about the floor, not about a player ---
	# Anything standing anywhere gets the same answer from the same call. This
	# is what makes it usable for the enemies later without touching it.
	var deep_spot := Vector3.ZERO
	for cell_y in grid.height:
		var found := false
		for cell_x in grid.width:
			if grid.cells[cell_y * grid.width + cell_x] >= floor_node.slip_thickness:
				deep_spot = floor_node.to_global(Vector3(
					(float(cell_x) + 0.5) * grid.cell_size - grid.extent.x * 0.5, 0.0,
					(float(cell_y) + 0.5) * grid.cell_size - grid.extent.y * 0.5))
				found = true
				break
		if found:
			break
	_check(floor_node.is_slippery_at(deep_spot),
		"a cell over the threshold is not reported slippery")
	# The answer is about the cell underneath, so whatever is asking and however
	# tall it is gets the same one.
	_check(floor_node.is_slippery_at(deep_spot + Vector3(0.0, 40.0, 0.0)),
		"height changed the answer: it is meant to be a fact about the floor")

	# --- a player walking thin mayo stays up; running deep mayo goes down ---
	grid.clear()
	player.global_position = home
	player.velocity = Vector3.ZERO
	await physics_frame
	# A dotted trail: splats half a metre apart, which is wider than one is, so
	# each spot's thickness is exactly the number of times it was painted.
	# Laying them on top of each other instead piles the overlap up and saturates
	# the middle in a couple of dozen calls, which is not a thin patch at all.
	var trail: Array[Vector3] = []
	for step in 6:
		trail.push_back(home + Vector3(0.0, 0.0, -5.0 - float(step) * 0.5))
	var thin_splats: int = maxi(floor_node.slip_thickness
		/ maxi(floor_node.thickness_per_splat, 1) / 2, 1)
	for _splat in thin_splats:
		for spot_at in trail:
			floor_node.paint_mayo(spot_at)
	var thin: Vector3 = trail[2]
	print("thin trail: %d splats a spot -> thickness %d, slippery=%s" % [
		thin_splats, floor_node.thickness_at(thin), str(floor_node.is_slippery_at(thin))])
	_check(floor_node.is_mayo_at(thin), "the thin patch has no mayo on it at all")
	_check(not floor_node.is_slippery_at(thin),
		"the thin patch is already slippery, so this case tests nothing")
	var fell_on_thin := await _run_over(scene, player, thin)
	print("running over thin mayo: fell=%s" % str(fell_on_thin))
	_check(not fell_on_thin, "running over thin mayo knocked the player down")

	# Same trail, piled up until it is over the threshold.
	for _splat in floor_node.slip_thickness:
		for spot_at in trail:
			floor_node.paint_mayo(spot_at)
	print("same trail piled up: thickness %d, slippery=%s" % [
		floor_node.thickness_at(thin), str(floor_node.is_slippery_at(thin))])
	_check(floor_node.is_slippery_at(thin), "piling mayo on did not make it slippery")
	var fell_on_deep := await _run_over(scene, player, thin)
	print("running over the same trail once it is deep: fell=%s" % str(fell_on_deep))
	_check(fell_on_deep, "running over deep mayo did not knock the player down")

	if failures.is_empty():
		print("MAYO_THICKNESS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## Sprints the player through a spot and reports whether they went down.
func _run_over(scene, player: MayoPlayer, spot: Vector3) -> bool:
	player.global_position = spot + Vector3(0.0, 0.0, 4.0)
	player.global_position.y = scene.spawn_position_for(0).y
	player.velocity = Vector3.ZERO
	scene.debug_set_aim(0.0, 0.0)
	await physics_frame
	scene.debug_set_input(Vector2(0.0, -1.0), true, false)
	var fell := false
	for _f in 150:
		await physics_frame
		if player.is_incapacitated():
			fell = true
			break
	scene.debug_set_input(Vector2.ZERO, false, false)
	for _f in 120:
		await physics_frame
	return fell
