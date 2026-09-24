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

	print("deposit %d per pass, slippery at %d, floor %dx%d in %d tiles of %d cells" % [
		floor_node.thickness_per_pass, floor_node.slip_thickness,
		grid.width, grid.height, grid.tile_count(), floor_node.tile_cells])

	# --- a splat adds, it does not flag ---
	var spot := floor_node.to_global(Vector3(4.0, 0.0, 4.0))
	var thicknesses := PackedInt32Array()
	for splat in 6:
		floor_node.paint_mayo(spot)
		thicknesses.push_back(floor_node.thickness_at(spot))
	print("six uncoated splats on one spot: thickness went %s" % str(thicknesses))
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

	# --- a pass lays down one layer, however long the trigger is held ---
	# The reported symptom, at its root. The stream dumps a hundred splats on
	# the cell it happens to sit over and one on the far end of the same trail,
	# so counting splats made the head of a trail slippery inside a second and
	# the tail of it never. A cell rises once per trigger pull instead, which
	# makes a trail flat: what decides whether you slip is how many times the
	# floor was painted, not where the stream lingered while painting it.
	grid.clear()
	var held := floor_node.to_global(Vector3(11.0, 0.0, 11.0))
	for _splat in 40:
		floor_node.paint_mayo(held, 4242)
	var one_coat := floor_node.thickness_at(held)
	for _splat in 40:
		floor_node.paint_mayo(held, 4243)
	var two_coats := floor_node.thickness_at(held)
	print("40 splats in one pass -> %d, another 40 in a second pass -> %d" % [
		one_coat, two_coats])
	_check(one_coat == floor_node.thickness_per_pass,
		"holding the trigger over one cell piled it to %d: a pass has to be one layer"
			% one_coat)
	_check(two_coats == floor_node.thickness_per_pass * 2,
		"a second pass took the cell to %d rather than %d"
			% [two_coats, floor_node.thickness_per_pass * 2])
	# And the cap is per burst, not global: an old burst must not go on
	# suppressing a cell forever.
	_check(floor_node.thickness_at(held) > floor_node.thickness_per_pass,
		"the coat never released the cell")

	# --- a splat thickens every cell it covers, not just the one it landed on ---
	# The visible stain and the range that thickens have to be the same set of
	# cells. If a splat only raised its own landing cell, painting a patch over
	# and over would build a line of dots inside a stain that never got deeper,
	# and the stain would look ready to slip on long before it was.
	grid.clear()
	var here := floor_node.to_global(Vector3(9.0, 0.0, 9.0))
	floor_node.paint_mayo(here)
	var raised := 0
	var drawn := 0
	var cut := maxf(float(floor_node.thickness_per_pass) * 0.5, 0.5)
	var landing := grid.cell_of(Vector2(9.0, 9.0))
	for row in range(landing.y - 8, landing.y + 9):
		for column in range(landing.x - 8, landing.x + 9):
			if grid.cells[row * grid.width + column] > 0:
				raised += 1
			var local := Vector2(
				(float(column) + 0.5) * grid.cell_size - grid.extent.x * 0.5,
				(float(row) + 0.5) * grid.cell_size - grid.extent.y * 0.5)
			if grid.sample_bilinear(local) >= cut:
				drawn += 1
	print("one splat: %d cells thickened, %d cells drawn as stained" % [raised, drawn])
	_check(raised > 1,
		"a splat thickened %d cell(s): it is marking where it landed, not what it covers"
			% raised)
	_check(raised == drawn,
		"a splat thickens %d cells but %d are drawn: the stain and the thickness have come apart"
			% [raised, drawn])

	# --- and overlapping stains stack even when they land on different cells ---
	# The case the dotted-line bug would hide behind: aim slightly differently
	# each time, as anyone would, and the part where the stains overlap has to
	# get deeper even though no two splats landed on the same cell.
	grid.clear()
	var offsets := [0.0, grid.cell_size * 1.0, grid.cell_size * 2.0]
	for offset in offsets:
		floor_node.paint_mayo(floor_node.to_global(Vector3(9.0 + offset, 0.0, 9.0)))
	var landed_on := {}
	for offset in offsets:
		landed_on[grid.cell_of(Vector2(9.0 + offset, 9.0))] = true
	var stacked := 0
	var deepest := 0
	for row in range(landing.y - 8, landing.y + 9):
		for column in range(landing.x - 8, landing.x + 9):
			var value: int = grid.cells[row * grid.width + column]
			deepest = maxi(deepest, value)
			if value >= floor_node.thickness_per_pass * offsets.size():
				stacked += 1
	print("three splats on %d different landing cells: deepest %d, %d cells reached all three" % [
		landed_on.size(), deepest, stacked])
	_check(landed_on.size() == offsets.size(),
		"the three splats shared a landing cell, so this case tests nothing")
	_check(deepest == floor_node.thickness_per_pass * offsets.size(),
		"three overlapping splats reached %d, not the %d of all three stacking"
			% [deepest, floor_node.thickness_per_pass * offsets.size()])
	_check(stacked > 0, "no cell took all three splats, so the overlap is not accumulating")

	# --- the stain is drawn in four steps, and they follow the stored value ---
	# The reported symptom: paint a patch three times and only the spot under
	# the stream turns yellow. It was true, and it was not the thickness failing
	# to accumulate -- a cell is drawn white on its first splat and yellow on its
	# twenty-second, so everything between the two looked identical and the pile
	# building up was invisible. The steps are what make it visible, so what has
	# to hold is that the band drawn follows the byte stored, at every boundary.
	var bounds := floor_node.step_bounds()
	print("steps at 1 / %d / %d / %d (white, light cream, heavy cream, deep)" % [
		bounds.x, bounds.y, floor_node.slip_thickness])
	_check(bounds.x <= bounds.y and bounds.y < floor_node.slip_thickness,
		"the steps are not in order: 1 / %d / %d / %d" % [
			bounds.x, bounds.y, floor_node.slip_thickness])
	# Which bands the configuration can actually reach. With three passes to
	# slip there is only room for three of them -- 1, 2 and deep -- so the
	# check is that the bands that exist land where they say, not that there
	# are four of them.
	var reachable := {}
	var previous := 0
	for value in range(1, floor_node.slip_thickness + 1):
		var band := floor_node.step_for_thickness(value)
		reachable[band] = true
		_check(band >= previous,
			"thickness %d draws as band %d after %d drew as %d: the bands go backwards"
				% [value, band, value - 1, previous])
		previous = band
	_check(floor_node.step_for_thickness(floor_node.slip_thickness) == 4,
		"the deep band does not begin at the thickness that trips")
	_check(floor_node.step_for_thickness(floor_node.slip_thickness - 1) < 4,
		"the deep band starts a pass early")
	_check(reachable.size() >= 3,
		"only %d bands can ever be drawn: the stain has no middle" % reachable.size())
	# And a real cell piling up passes through every band there is, rather than
	# jumping from white to yellow.
	grid.clear()
	var pile := floor_node.to_global(Vector3(14.0, 0.0, 14.0))
	var seen := {}
	for pass_number in floor_node.slip_thickness + 1:
		floor_node.paint_mayo(pile, 9000 + pass_number)
		seen[floor_node.stain_step_at(pile)] = true
	print("a cell piling up passed through bands %s of the %s it can reach" % [
		str(seen.keys()), str(reachable.keys())])
	for band in reachable.keys():
		_check(seen.has(band),
			"a cell went from nothing to slippery without ever drawing band %d" % band)

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
		# Up to walking speed before the trigger goes down. Opening fire from a
		# standstill lets the stream dwell on one spot while the body picks up
		# speed, which piles a spike on the near end that is not a *pass*.
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		for _f in 25:
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
			var one_pass_deep := floor_node.deep_fraction()
			print("after one pass: thickest cell %d, %.0f%% of the trail slippery" % [
				peak, one_pass_deep * 100.0])
			# One pass leaves its own ridge dangerous and nothing else. It is not
			# nothing -- see `slip_thickness` for why no threshold makes it
			# nothing without three passes leaving almost nothing either -- but
			# it has to stay a sliver rather than the whole trail.
			_check(one_pass_deep < 0.20,
				"one pass left %.0f%% of its trail slippery: walking your own fresh trail would be a coin toss"
					% (one_pass_deep * 100.0))
		deep_peak = peak
	print("after four passes: thickest cell %d, %d slippery cells, %.0f%% of the stain" % [
		deep_peak, floor_node.deep_cell_count(), floor_node.deep_fraction() * 100.0])
	# What share of the stain each band covers. The steps are only worth having
	# if the middle two are actually drawn on a real trail rather than being a
	# hairline between white and yellow.
	var census := PackedInt32Array([0, 0, 0, 0, 0])
	for cell in grid.cells:
		census[floor_node.step_for_thickness(cell)] += 1
	var stain: int = census[1] + census[2] + census[3] + census[4]
	print("bands over the trail: white %.0f%%, light %.0f%%, heavy %.0f%%, deep %.0f%%" % [
		100.0 * census[1] / stain, 100.0 * census[2] / stain,
		100.0 * census[3] / stain, 100.0 * census[4] / stain])
	_check(census[2] + census[3] > 0,
		"the two middle bands cover nothing: the stain still jumps white to yellow")
	_check(deep_peak >= floor_node.slip_thickness,
		"four passes only reached %d, under the %d that trips: nothing would ever be slippery"
			% [deep_peak, floor_node.slip_thickness])
	# The thing that was reported: painting a patch several times and finding it
	# safe. Most of what has been gone over repeatedly has to be dangerous.
	_check(floor_node.deep_fraction() > 0.5,
		"four passes left only %.0f%% of the trail slippery: going over a patch again and again does nothing"
			% (floor_node.deep_fraction() * 100.0))

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
	# Sampled at cells this check paints itself rather than at a fixed lattice
	# over the whole floor. The lattice only worked while the fire earlier in
	# this probe happened to land on one of its rows: retuning `stream_range`
	# moved where the stream comes down, every sample missed, and the check
	# passed over nothing. What is under test is that `is_slippery_at` reads the
	# same thickness the grid stores, which does not care where the cells are.
	var probes: Array[Vector3] = []
	for step in 5:
		var probe_at := home + Vector3(float(step) * 0.7 - 1.4, 0.0, -3.0)
		probes.push_back(probe_at)
		# Two of them deliberately over the line and three under it, so both
		# answers are exercised.
		var layers: int = floor_node.slip_thickness + 2 if step < 2 else 1
		for _layer in layers:
			floor_node.paint_mayo(probe_at)

	var disagreed := 0
	var sampled := 0
	for spot_at in probes:
		var cell := grid.cell_of(Vector2(
			spot_at.x - floor_node.global_position.x,
			spot_at.z - floor_node.global_position.z))
		if not grid.has_cell(cell):
			continue
		for cell_y in [cell.y]:
			for cell_x in [cell.x]:
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
		/ maxi(floor_node.thickness_per_pass, 1) / 2, 1)
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

	# --- and sauce pools where the stream is parked ---
	# The other half of the rule. A layer is per `coat_seconds` rather than per
	# trigger pull, so holding the stream on one spot goes on layering: a
	# chokepoint can be puddled deliberately, at a rate that does not outrun
	# the rest of the trail the way counting splats did.
	grid.clear()
	player.global_position = home
	player.velocity = Vector3.ZERO
	scene.debug_set_aim(0.0, -38.0)
	await physics_frame
	scene._local.sauce = 1.0
	scene.debug_set_input(Vector2.ZERO, false, true)
	var tap_peak := 0
	for held_frame in 90:
		scene._local.sauce = 1.0
		await physics_frame
		if held_frame == 30:
			for cell in grid.cells:
				tap_peak = maxi(tap_peak, cell)
	scene.debug_set_input(Vector2.ZERO, false, false)
	for _f in 45:
		await physics_frame
	var parked_peak := 0
	for cell in grid.cells:
		parked_peak = maxi(parked_peak, cell)
	print("stream held on one spot: %d layers after half a second, %d after holding it" % [
		tap_peak, parked_peak])
	_check(parked_peak >= floor_node.slip_thickness,
		"holding the stream on one spot only reached %d of the %d that trips: sauce does not pool"
			% [parked_peak, floor_node.slip_thickness])
	_check(tap_peak < floor_node.slip_thickness,
		"half a second on a spot reached %d and was already slippery" % tap_peak)

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
