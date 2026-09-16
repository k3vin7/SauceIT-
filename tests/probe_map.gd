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
	var start_cell := StreetMap.cell_of_pixels(225.0, 1057.5)
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

	var arena_cell := StreetMap.cell_of_pixels(537.0, 142.0)
	_check(seen.has(arena_cell), "the arena cannot be walked to from the start zone")

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
	print("props=%d (%d stalls, %d vending), narrowest road left past one=%.2f m" % [
		props.size(), StreetMap.stall_boxes().size(), StreetMap.vending_boxes().size(),
		worst_clearance])
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
