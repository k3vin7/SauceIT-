extends SceneTree

# Stage 2, La Tomatina, as a greybox:
#
#   * the stage scene builds on the Tomatina layout, with the start on the
#     street and a walkable route from the start to the fire truck bay
#   * every stage 2 kind builds, and the bowler brings its balls
#   * the juice is on the floor where it should be and nowhere else, and it is
#     never slippery
#   * a grunt dying bursts: ketchup on the floor, none of it slippery, and the
#     splats queued for the peers
#   * the burst a grunt is dealt is reproducible from its index alone, and the
#     deal is mostly small with a few large
#   * a bowled tomato bursts on the first wall and parks itself
#   * stepping onto the plaza brings the horde
#   * the stage clears when the elites are down and somebody is at the truck
#   * stage 1 gets its own street back afterwards

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func _run() -> void:
	StreetMap.layout_override = null
	var festival_cells := StreetMap.floor_cells().size()

	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await _frames(2)
	scene.set_process_unhandled_input(false)

	# --- the map ---
	_check(scene.map_kind == scene.MapKind.TOMATINA, "stage 2 scene did not select the Tomatina map")
	_check(StreetMap.layout_override is TomatinaMap, "the lattice is not carrying the Tomatina design")
	var floor_set := StreetMap.floor_cells()
	_check(floor_set.size() != festival_cells, "the Tomatina floor is the festival floor")
	for slot in 4:
		var spawn: Vector3 = scene.spawn_position_for(slot)
		_check(floor_set.has(StreetMap.cell_at(spawn)), "spawn %d is not on the street" % slot)
	var truck_zone: Rect2 = TomatinaMap.fire_truck_zone()
	var truck_centre := Vector3(truck_zone.get_center().x, 0.0, truck_zone.get_center().y)
	_check(scene._nav != null, "stage 2 built no router")
	var route: PackedVector3Array = scene._nav.route(scene.spawn_position_for(0), truck_centre)
	print("route from the start to the fire truck: %d waypoints" % route.size())
	_check(route.size() > 10, "there is no walkable route from the start to the fire truck bay")
	# The overturned truck is a chokepoint, not a wall: the route goes through
	# its gap rather than round, and the gap is the one cell left of four.
	var cid_blocked := 0
	for i in range(28, 32):
		if StreetMap.blocked_cells().has(Vector2i(i, int(TomatinaMap.TRUCK_ROW))):
			cid_blocked += 1
	_check(cid_blocked == 3, "the overturned truck blocks %d of 4 cells, not 3" % cid_blocked)
	_check(scene.refill_stations().size() == 7, "stage 2 does not have its seven sauce trucks")

	# --- the roster ---
	var counts := {}
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		counts[enemy.kind] = int(counts.get(enemy.kind, 0)) + 1
	print("roster: %s" % str(counts))
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_GRUNT, 0)) >= 20, "too few grunts on the street")
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_BRUTE, 0)) == 1, "no brute")
	_check(int(counts.get(MayoEnemy.EnemyKind.BOWLING_TOMATO, 0)) == 1, "no bowler")
	_check(int(counts.get(MayoEnemy.EnemyKind.TOMATO_BALL, 0)) == MayoEnemy.BALLS_PER_BOWLER,
		"the bowler did not bring its balls")
	_check(int(counts.get(MayoEnemy.EnemyKind.KETCHUP_SPITTER, 0)) == 1, "no spitter")
	_check(int(counts.get(MayoEnemy.EnemyKind.CAPRESE_CRAWLER, 0)) == 1, "no crawler")
	_check(scene._tomatina_elites_alive() == 4, "elite count is %d, not 4" % scene._tomatina_elites_alive())
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_BALL:
			_check(enemy.global_position.y < -40.0, "a ball is not parked under the floor")
			continue
		_check(scene._nav.is_walkable(StreetMap.cell_at(enemy.global_position)),
			"%s stands on a cell nothing can walk" % enemy.name)
		_check(enemy.contamination != null and enemy._visual_root != null,
			"%s has no stain grid or no visual" % enemy.name)
		_check(enemy._visual_root.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"%s has no meshes to look at" % enemy.name)

	# --- the deal ---
	var tiers := [0, 0, 0]
	for index in 400:
		var deal: Dictionary = scene._deal_grunt_burst(index)
		var again: Dictionary = scene._deal_grunt_burst(index)
		_check(deal == again, "the burst dealt to body %d changed between two asks" % index)
		tiers[int(deal["tier"])] += 1
		var radius: float = deal["radius"]
		match int(deal["tier"]):
			0: _check(radius >= 1.2 and radius <= 2.0, "a small burst of %.2f m" % radius)
			1: _check(radius >= 2.5 and radius <= 3.5, "a medium burst of %.2f m" % radius)
			2: _check(radius >= 5.0 and radius <= 6.5, "a large burst of %.2f m" % radius)
	print("400 grunts dealt: %d small, %d medium, %d large" % tiers)
	_check(tiers[0] > 220, "fewer than 55%% of grunts burst small")
	_check(tiers[2] >= 4 and tiers[2] <= 60, "the large burst is dealt %d times in 400" % tiers[2])

	# --- the floor ---
	var floor_body: FloorContamination = scene._floor
	var juicy := TomatinaMap.at_cell(Vector2(17.5, 63.0))
	var clean := TomatinaMap.at_cell(Vector2(41.5, 66.0))
	var juicy_hits := 0
	for dx in 6:
		for dz in 6:
			var at := juicy + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)
			if floor_body.thickness_at(at) > 0:
				juicy_hits += 1
				_check(floor_body.sauce_kind_at(at) == ContaminationGrid.KIND_KETCHUP,
					"the juice in the west fork is not ketchup")
				_check(not floor_body.is_slippery_at(at), "the juice in the west fork is slippery")
	print("juice under 36 samples in the west fork: %d painted" % juicy_hits)
	_check(juicy_hits > 10, "the west fork is not awash")
	var clean_hits := 0
	for dx in 6:
		for dz in 6:
			if floor_body.thickness_at(clean + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)) > 0:
				clean_hits += 1
	_check(clean_hits == 0, "the east fork has juice on it")

	# --- a grunt bursts ---
	scene.set_physics_process(false)
	var grunt: MayoEnemy = null
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.burst_tier == 0:
			grunt = enemy
			break
	_check(grunt != null, "no small grunt to burst")
	if grunt != null:
		var before := floor_body.grid.painted_cell_count()
		scene._pending_splats.clear()
		grunt.health = grunt.sauce_damage_per_hit * 0.5
		var hit_at := grunt.global_position + Vector3(0.0, 0.0, grunt.radius)
		scene._record_splat(grunt, hit_at, Vector3.BACK, scene._local)
		_check(not grunt.is_alive(), "the last hit did not kill the grunt")
		var after := floor_body.grid.painted_cell_count()
		print("burst of %.2f m: %d floor cells painted, %d ints queued" % [
			grunt.burst_radius, after - before, scene._pending_splats.size()])
		_check(after > before, "the burst painted nothing on the floor")
		var floor_splats := 0
		var ketchup_code: int = scene._splat_code(scene.SPLAT_FLOOR, ContaminationGrid.KIND_KETCHUP)
		var i := 0
		while i + 3 < scene._pending_splats.size():
			if scene._pending_splats[i] == ketchup_code:
				floor_splats += 1
			i += 4
		_check(floor_splats > 5, "the burst queued %d floor splats for the peers" % floor_splats)
		var expected := int(round(scene.TOMATO_SPLATS_PER_M2 * PI * grunt.burst_radius * grunt.burst_radius))
		_check(floor_splats == mini(expected, scene.TOMATO_BURST_SPLAT_CAP),
			"the burst laid %d splats, not the %d its radius is worth" % [floor_splats, expected])
		var slippery := 0
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				var at := grunt.global_position + Vector3(float(dx) * 0.3, 0.0, float(dz) * 0.3)
				if floor_body.is_slippery_at(at):
					slippery += 1
		_check(slippery == 0, "the burst left %d slippery cells" % slippery)

	# --- a bowled tomato ---
	var bowler: MayoEnemy = null
	for index in scene.enemy_count():
		if scene.enemy_at(index).kind == MayoEnemy.EnemyKind.BOWLING_TOMATO:
			bowler = scene.enemy_at(index)
	_check(bowler != null and bowler.ball_pool.size() == MayoEnemy.BALLS_PER_BOWLER,
		"the bowler has no pool")
	if bowler != null and not bowler.ball_pool.is_empty():
		var ball: MayoEnemy = bowler.ball_pool[0]
		# Rolled east from just clear of the bowler, into the lane's east wall
		# a cell and a half away. Clear of it, as the bowler itself throws:
		# a ball started inside another body is pushed out of it first, and
		# the way out is as likely to be down through the floor as anywhere.
		ball.launch(bowler.global_position + Vector3.RIGHT * (bowler.radius + ball.radius + 0.3),
			Vector3.RIGHT)
		var launched_at := ball.global_position
		_check(ball.is_ball_live(), "the ball did not go live")
		var burst_at := Vector3.INF
		for _tick in 240:
			ball.advance(1.0 / 60.0, [])
			await physics_frame
			burst_at = ball.take_burst_request()
			if burst_at != Vector3.INF:
				break
		print("ball met its wall at %s, launched from %s" % [str(burst_at), str(launched_at)])
		_check(burst_at != Vector3.INF, "the bowled tomato never met a wall")
		_check(burst_at != Vector3.INF and absf(burst_at.y - launched_at.y) < 0.2,
			"the ball left the ground on its way to the wall")
		_check(burst_at != Vector3.INF and burst_at.x > launched_at.x + 2.0,
			"the ball burst before it had rolled anywhere")
		_check(not ball.is_ball_live() and ball.global_position.y < -40.0,
			"the ball did not park after bursting")
		_check(ball.burst_radius > 0.0, "the ball has nothing to burst with")

	# --- the horde ---
	scene.set_physics_process(true)
	var player: MayoPlayer = scene._player
	var before_horde: int = scene.enemy_count()
	var plaza: Rect2 = TomatinaMap.plaza_rect()
	player.global_position = Vector3(plaza.get_center().x, 1.28, plaza.get_center().y)
	await _frames(3)
	_check(scene.horde_spawned(), "stepping onto the plaza did not bring the horde")
	var expected_horde: int = scene.minion_spawn_count(scene.TOMATINA_HORDE_BASE)
	print("horde: %d bodies for a party of %d" % [scene.enemy_count() - before_horde, scene.party_size()])
	_check(scene.enemy_count() - before_horde == expected_horde,
		"the horde is %d bodies, not %d" % [scene.enemy_count() - before_horde, expected_horde])
	_check(scene.tutorial_spawned().size() == expected_horde,
		"the horde is not recorded for a late joiner")

	# --- the clear ---
	var cleared := [false]
	scene.stage_cleared.connect(func() -> void: cleared[0] = true)
	player.global_position = Vector3(truck_centre.x, 1.28, truck_centre.z)
	await _frames(3)
	_check(not cleared[0], "the stage cleared with the elites still standing")
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.grade == MayoEnemy.Grade.HEAVY:
			enemy.health = 0.0
	player.global_position = Vector3(plaza.get_center().x, 1.28, plaza.get_center().y)
	await _frames(3)
	_check(not cleared[0], "the stage cleared with nobody at the fire truck")
	player.global_position = Vector3(truck_centre.x, 1.28, truck_centre.z)
	await _frames(3)
	_check(cleared[0], "the elites are down and the party is at the truck, and the stage did not clear")

	scene.free()
	await process_frame

	# --- stage 1 is unharmed ---
	var festival = load("res://stage_1_festival.tscn").instantiate()
	root.add_child(festival)
	await _frames(2)
	_check(StreetMap.layout_override == null, "stage 1 is still carrying the Tomatina design")
	_check(StreetMap.floor_cells().size() == festival_cells,
		"stage 1's street changed after stage 2 was built")
	_check(festival.enemy_count() > 0 and festival.enemy_at(0).kind == MayoEnemy.EnemyKind.BRUISER,
		"stage 1's roster is not its own")
	festival.free()
	await process_frame

	if failures.is_empty():
		print("TOMATINA_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
