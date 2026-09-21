extends SceneTree

# An enemy has to get to the player, not lean on the wall between them.
#
# It used to walk the straight line between the two, which works right up until
# something is on that line -- and the street is a street, so something usually
# is. These checks put a corner between the two and fail unless the gap closes.
#
#   * the route avoids what is standing on the street, not just the walls
#   * a corner is walked round rather than leaned on
#   * a clear line is taken straight, so an open street does not read as a body
#     pacing out the middle of every cell
#   * no router at all still chases, badly, rather than stopping

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
	var nav: StreetNav = scene._nav
	var player: MayoPlayer = scene._player
	var stand: float = scene.spawn_position_for(0).y

	# --- the map it routes on ---
	var walkable := StreetMap.walkable_cells()
	var street := StreetMap.floor_cells()
	var blocked := StreetMap.blocked_cells()
	print("street %d cells, %d under props, %d walkable" % [
		street.size(), blocked.size(), walkable.size()])
	_check(blocked.size() > 0, "nothing on the street is treated as standing on it")
	_check(walkable.size() < street.size(),
		"the props are on the street but the router does not know it")
	# A stall's own cells must be shut: routing through one is how a chaser ends
	# up wedged in the furniture.
	var shut := 0
	for cell in blocked:
		if street.has(cell) and not nav.is_walkable(cell):
			shut += 1
	print("prop cells that are also street: %d, all shut to the router: %s" % [
		shut, str(shut > 0)])
	_check(shut > 0, "no prop cell is shut to the router")

	# --- a route round a corner exists and is longer than the straight line ---
	# The start zone and the festival square are on different arms of the map,
	# so nothing can walk from one to the other in a straight line.
	var from: Vector3 = scene.spawn_position_for(0)
	var to: Vector3 = StreetMap.arena_centre()
	var route := nav.route(from, to)
	var walked := 0.0
	for index in range(1, route.size()):
		walked += route[index - 1].distance_to(route[index])
	print("start zone to the square: %d waypoints, %.0f m walked against %.0f m straight" % [
		route.size(), walked, from.distance_to(to)])
	_check(route.size() > 2, "no route from the start zone to the square")
	_check(walked > from.distance_to(to),
		"the route is shorter than the straight line, which cannot be a route")
	# Every step of it is somewhere a body may stand.
	var off_route := 0
	for point in route:
		if not nav.is_walkable(StreetMap.cell_at(point)):
			off_route += 1
	_check(off_route == 0, "%d waypoints stand where a body cannot" % off_route)

	# --- the chase itself, round a corner ---
	scene.debug_clear_enemies()
	var enemy := MayoEnemy.new()
	root.add_child(enemy)
	enemy.build(scene.body_cell_size, scene.contamination_brush_radius, Color("4d3f6b"))
	enemy.nav = nav
	enemy.match_player_speed(player.walk_speed, scene.enemy_speed_fraction)

	# Round the corner from each other: the enemy on Karja, the player along
	# Saue, with the buildings between them.
	var corner_a := StreetMap.cell_middle(Vector2i(27, 50)) + Vector3(0.0, enemy.stand_height(), 0.0)
	var corner_b := StreetMap.cell_middle(Vector2i(17, 63)) + Vector3(0.0, stand, 0.0)
	enemy.global_position = corner_a
	player.global_position = corner_b
	await physics_frame
	_check(not enemy._can_see(player.global_position),
		"the two are in sight of each other, so this case tests nothing")

	var opening := enemy.global_position.distance_to(player.global_position)
	var targets: Array = [player]
	for _f in 600:
		enemy.advance(1.0 / 60.0, targets)
		await physics_frame
	var closed := opening - enemy.global_position.distance_to(player.global_position)
	print("round a corner: %.0f m apart, closed %.0f m in 10 s at %.2f m/s" % [
		opening, closed, enemy.move_speed])
	# Ten seconds at 3.6 m/s is 36 m of walking; a body leaning on a wall closes
	# almost none of it, and one walking the route closes most of it.
	_check(closed > opening * 0.5,
		"it closed only %.0f m of %.0f in ten seconds: it is stuck on something"
			% [closed, opening])

	# --- a clear line is taken straight ---
	var square: Vector3 = StreetMap.arena_centre()
	enemy.global_position = square + Vector3(0.0, enemy.stand_height(), -14.0)
	player.global_position = square + Vector3(0.0, stand, 14.0)
	await physics_frame
	_check(enemy._can_see(player.global_position),
		"the square is not open enough for a straight run, so this tests nothing")
	enemy._route = PackedVector3Array([Vector3(999.0, 0.0, 999.0)])
	enemy.advance(1.0 / 60.0, targets)
	print("in the open: route dropped=%s" % str(enemy._route.is_empty()))
	_check(enemy._route.is_empty(),
		"the enemy kept a route while it could see the player, so it walks the lattice in the open")

	# --- no router: still chases ---
	enemy.nav = null
	enemy.global_position = square + Vector3(0.0, enemy.stand_height(), -14.0)
	await physics_frame
	var before := enemy.global_position.distance_to(player.global_position)
	for _f in 60:
		enemy.advance(1.0 / 60.0, targets)
		await physics_frame
	print("with no router at all: closed %.2f m in a second" % [
		before - enemy.global_position.distance_to(player.global_position)])
	_check(before - enemy.global_position.distance_to(player.global_position) > 1.0,
		"an enemy with no router stopped chasing rather than falling back to the straight line")
	enemy.queue_free()

	if failures.is_empty():
		print("MAYO_CHASE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
