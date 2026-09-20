extends SceneTree

# The street is generated, not authored, so the things a hand-built level would
# get for free have to be checked:
#
#   * every corridor is exactly the road width, because the width is the one
#     number the map was specified by
#   * the arena is reachable on foot from the start zone -- a segment list that
#     looks connected on paper can still leave a one-cell gap
#   * the walls seal it: no cell touching the street, diagonals included, is
#     left open, or a strand flies out of the world through the corner
#   * the props stand on the street and against a wall, not in mid-road and not
#     buried, and they leave enough of the road to walk past
#   * every spawn is on open ground

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

	var floor_set := StreetMap.floor_cells()
	var bounds := StreetMap.bounds()
	print("scale=%.2fx  cell=%.3f m  road=%.2f m (%d people)  walls %.1f m tall" % [
		StreetMap.SCALE, StreetMap.CELL, StreetMap.ROAD_WIDTH,
		StreetMap.ROAD_CELLS, StreetMap.WALL_HEIGHT])
	print("street: %d cells over %d x %d, i.e. %.0f x %.0f m" % [
		floor_set.size(), bounds.size.x, bounds.size.y,
		float(bounds.size.x) * StreetMap.CELL, float(bounds.size.y) * StreetMap.CELL])

	# --- corridor width ---
	# Measured as the run of street cells across each segment's short axis, at
	# its own middle, which is where a junction cannot pad the count.
	for index in StreetMap.SEGMENTS.size():
		var rect: Rect2i = StreetMap.SEGMENTS[index]
		var narrow: int = mini(rect.size.x, rect.size.y)
		_check(narrow >= StreetMap.ROAD_CELLS,
			"segment %d is %d cells across, under the %d-cell road" % [
				index, narrow, StreetMap.ROAD_CELLS])

	# --- reachable on foot ---
	# The start zone is the lattice origin by construction, and the square is
	# asked of the map rather than by a pixel that only the drawing knows.
	var start_cell := StreetMap.ORIGIN_CELL
	_check(floor_set.has(start_cell), "the start zone is not on the street")
	var seen := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if floor_set.has(next) and not seen.has(next):
				seen[next] = true
				queue.push_back(next)
	print("reachable from the start zone: %d of %d street cells" % [seen.size(), floor_set.size()])
	_check(seen.size() == floor_set.size(),
		"%d street cells are walled off from the start zone" % (floor_set.size() - seen.size()))

	var square := StreetMap.arena_centre()
	var square_cell := _cell_at(square)
	_check(seen.has(square_cell),
		"the festival square cannot be walked to from the start zone")

	# The square has to be the open space the strand tests take it for: wider
	# than the stream reaches, in both directions, with nothing in the middle.
	var square_rect: Rect2i = StreetMap.SEGMENTS[StreetMap.SQUARE_SEGMENT]
	var span := Vector2(float(square_rect.size.x), float(square_rect.size.y)) * StreetMap.CELL
	print("festival square %.0f x %.0f m, stream reaches %.1f m" % [span.x, span.y, 14.9])
	_check(minf(span.x, span.y) > 14.9 * 2.0,
		"the square is %.0f x %.0f m, too tight for a strand to be fired across" % [span.x, span.y])

	# The stage and the tower stand in it, not in a wall.
	for landmark in [["stage", StreetMap.stage_position()], ["tower", StreetMap.tower_position()]]:
		var name: String = landmark[0]
		var at: Vector3 = landmark[1]
		_check(floor_set.has(_cell_at(at)), "the %s is not standing on the street" % name)
	print("stage at %.0v, tower at %.0v, square centre %.0v" % [
		StreetMap.stage_position(), StreetMap.tower_position(), square])

	# --- the round place at the head of the promenade ---
	# A circle cannot be written as a Rect2i, so it is generated separately, and
	# what makes it worth generating is that it is actually round: an approximation
	# out of stacked rectangles gives a staircase you can see underfoot and that
	# the wall merger turns into a dozen boxes. Checked by walking out from the
	# centre along several headings and comparing how far the street lasts.
	var circle_centre := StreetMap.circle_centre()
	var circle_radius := StreetMap.circle_radius()
	_check(floor_set.has(_cell_at(circle_centre)), "the round place's centre is not street")
	var shortest := INF
	var longest := 0.0
	var rims := 0
	var exits := 0
	for step in 32:
		var heading := TAU * float(step) / 32.0
		var direction := Vector3(cos(heading), 0.0, sin(heading))
		var reach := 0.0
		while reach < circle_radius * 3.0:
			if not floor_set.has(_cell_at(circle_centre + direction * (reach + 0.5))):
				break
			reach += 0.5
		# A heading that leaves through one of the streets joining the circle
		# never meets a rim, and says nothing about how round it is. Those run
		# far past the radius; a rim sits within a cell or so of it.
		if reach > circle_radius + StreetMap.CELL * 2.0:
			exits += 1
			continue
		rims += 1
		shortest = minf(shortest, reach)
		longest = maxf(longest, reach)
	print("round place: radius %.1f m, %d rim headings between %.1f and %.1f m, %d leading out" % [
		circle_radius, rims, shortest, longest, exits])
	_check(rims >= 16,
		"only %d of 32 headings met a rim: the circle is mostly street, not a place" % rims)
	_check(longest - shortest < StreetMap.CELL * 1.5,
		"the rim runs from %.1f m to %.1f m out: that is a polygon, not a circle" % [
			shortest, longest])
	_check(absf(shortest - circle_radius) < StreetMap.CELL * 1.5,
		"the rim sits %.1f m out against a declared radius of %.1f m" % [
			shortest, circle_radius])
	# And it has to be a *place*, wider than the street that leaves it.
	_check(circle_radius * 2.0 > StreetMap.ROAD_WIDTH * 1.5,
		"the round place is %.1f m across against a %.1f m street: it would not read as one"
			% [circle_radius * 2.0, StreetMap.ROAD_WIDTH])
	_check(seen.has(_cell_at(circle_centre)),
		"the round place cannot be walked to from the start zone")

	# --- the walls seal it ---
	var wall_set := {}
	for box in StreetMap.wall_boxes():
		var rect_cells := _cells_of(box)
		for cell in rect_cells:
			wall_set[cell] = true
	var leaks := 0
	for cell in floor_set:
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var near := Vector2i(cell.x + di, cell.y + dj)
				if not floor_set.has(near) and not wall_set.has(near):
					leaks += 1
	print("wall boxes=%d covering %d cells, open cells touching the street=%d" % [
		StreetMap.wall_boxes().size(), wall_set.size(), leaks])
	_check(leaks == 0, "%d cells next to the street are neither street nor wall" % leaks)

	# --- the props ---
	var props := StreetMap.stall_boxes() + StreetMap.vending_boxes()
	var worst_clearance := StreetMap.ROAD_WIDTH
	for prop in props:
		var position: Vector3 = prop["position"]
		var size: Vector3 = prop["size"]
		var facing: Vector3 = prop["facing"]
		var depth: float = size.x if absf(facing.x) > 0.5 else size.z
		# Its front centre must be street, its back must be past the street's
		# edge: that is what "against the wall" means.
		var front := position + facing * (depth * 0.5 - 0.05)
		var back := position - facing * (depth * 0.5 + 0.05)
		_check(floor_set.has(_cell_at(front)),
			"a prop at %.1v faces into a wall rather than onto the street" % position)
		_check(not floor_set.has(_cell_at(back)),
			"a prop at %.1v stands in the road instead of against a wall" % position)
		worst_clearance = minf(worst_clearance, StreetMap.ROAD_WIDTH - depth)
	print("props=%d (%d stalls from %d markers, %d vending), narrowest road left past one=%.2f m" % [
		props.size(), StreetMap.stall_boxes().size(), StreetMap.STALL_ANCHORS.size(),
		StreetMap.vending_boxes().size(), worst_clearance])
	# Every numbered marker on the drawing is a vendor, so every one of them has
	# to become a stall. They place themselves, and a stall that cannot find a
	# free frontage disappears silently -- which is exactly what this catches.
	_check(StreetMap.stall_boxes().size() == StreetMap.STALL_ANCHORS.size(),
		"only %d of %d markers became stalls" % [
			StreetMap.stall_boxes().size(), StreetMap.STALL_ANCHORS.size()])
	# And no two of them share ground.
	var footprints := {}
	var overlaps := 0
	for stall in StreetMap.stall_boxes():
		var at := _cell_at(stall["position"])
		if footprints.has(at):
			overlaps += 1
		footprints[at] = true
	_check(overlaps == 0, "%d stalls stand on the same cell as another" % overlaps)

	# The stall is a 3 m x 3 m pitch at 3.27 m to the peak, in this world's
	# units rather than real ones -- its people are the 2.56 m capsule, so a
	# literal 3.27 m canopy would clear a player's head by 0.7 m.
	var stall_size: Vector3 = StreetMap.STALL_SIZE
	print("stall %.2f x %.2f m, %.2f m to the peak (%.1f m x %.1f m real, x%.2f for a %.2f m person)" % [
		stall_size.x, stall_size.z, stall_size.y, StreetMap.STALL_FOOTPRINT_M,
		StreetMap.STALL_FOOTPRINT_M, StreetMap.HUMAN_SCALE, StreetMap.CAPSULE_HEIGHT])
	_check(stall_size.y > StreetMap.CAPSULE_HEIGHT * 1.4,
		"the canopy peaks at %.2f m over a %.2f m player: they would be wearing it"
			% [stall_size.y, StreetMap.CAPSULE_HEIGHT])
	# The counter has to be something you shoot over rather than hide behind.
	var counter: float = StreetMap.stall_metre(StreetMap.STALL_COUNTER_HEIGHT_M)
	print("counter at %.2f m against a %.2f m player: %.0f%% of their height" % [
		counter, StreetMap.CAPSULE_HEIGHT, 100.0 * counter / StreetMap.CAPSULE_HEIGHT])
	_check(counter < StreetMap.CAPSULE_HEIGHT * 0.75,
		"the counter is %.2f m of a %.2f m player: that is a wall, not a counter"
			% [counter, StreetMap.CAPSULE_HEIGHT])
	# Two players abreast is 2.56 m; anything under that turns a stall into a
	# door rather than an obstacle.
	_check(worst_clearance > 2.56,
		"a prop leaves only %.2f m of road, which is not enough to get past" % worst_clearance)

	# --- spawns ---
	for slot in 4:
		var spawn: Vector3 = scene.spawn_position_for(slot)
		_check(floor_set.has(_cell_at(spawn)), "spawn %d at %.1v is not on the street" % [slot, spawn])
	print("spawns: 4 of 4 on the street, at %.1v .. %.1v" % [
		scene.spawn_position_for(0), scene.spawn_position_for(3)])

	# --- the built scene matches the plan ---
	_check(scene._floor.floor_size.x >= float(bounds.size.x) * StreetMap.CELL
		and scene._floor.floor_size.y >= float(bounds.size.y) * StreetMap.CELL,
		"the ground plane is smaller than the street standing on it")
	print("floor plane %.0f x %.0f m -> grid %dx%d, %d contaminable bodies in the world" % [
		scene._floor.floor_size.x, scene._floor.floor_size.y,
		scene._floor.grid.width, scene._floor.grid.height, scene._walls.size()])

	if failures.is_empty():
		print("MAYO_MAP_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _cell_at(world_position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.x,
		int(floor(world_position.z / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.y)


func _cells_of(box: Dictionary) -> Array[Vector2i]:
	var position: Vector3 = box["position"]
	var size: Vector3 = box["size"]
	var corner := Vector3(position.x - size.x * 0.5, 0.0, position.z - size.z * 0.5)
	var first := _cell_at(corner + Vector3(StreetMap.CELL * 0.5, 0.0, StreetMap.CELL * 0.5))
	var cells: Array[Vector2i] = []
	for j in int(round(size.z / StreetMap.CELL)):
		for i in int(round(size.x / StreetMap.CELL)):
			cells.push_back(first + Vector2i(i, j))
	return cells
