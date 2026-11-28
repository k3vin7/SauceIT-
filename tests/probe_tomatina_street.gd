extends SceneTree

const Runtime := preload("res://scripts/mayo_prototype.gd")
const TomatinaBreakout := preload("res://scripts/tomatina_breakout.gd")

var failures: Array[String] = []
var runtime: Runtime
var static_query := PhysicsRayQueryParameters3D.new()


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _run() -> void:
	runtime = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(runtime)
	await physics_frame
	await physics_frame
	runtime.set_physics_process(false)
	var player: MayoPlayer = runtime._local.player
	var ignored: Array[RID] = [player.get_rid()]
	for body: MayoEnemy in runtime._enemies:
		ignored.append(body.get_rid())
	static_query.exclude = ignored
	static_query.collision_mask = 1
	_check_floor_geometry()
	_check_side_streets(player, ignored)

	var approach := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_APPROACH)
	var crest := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_CREST)
	var crest_hit := _ray(crest + Vector3.UP, crest - Vector3.UP)
	_check(crest.y - approach.y >= 5.0 and crest_hit.get("collider") == runtime._floor,
		"market floor collision does not climb to the crest")
	var rise := approach.lerp(crest, 0.39)
	rise.y = TomatinaMap.ground_height(rise)
	var uphill := _ray(rise + Vector3.UP, rise - Vector3.UP)
	_check(uphill.get("collider") == runtime._floor and uphill.normal.y < cos(deg_to_rad(12.0)),
		"the market ramp still has a shallow physical grade")
	_check_fall_camera_on_hill(player, rise)
	_check(TomatinaMap.at_cell(Vector2(33.2, 74.5)).y < -0.65,
		"rescue street lost its downhill section")
	_check(is_zero_approx(TomatinaMap.at_cell(Vector2(30, 36.0)).y),
		"the plaza entrance did not return to the plaza level")
	for location in [Vector2(26.4, 215.5), Vector2(33.2, 74.5), Vector2(30.1, 43.15)]:
		var ground := TomatinaMap.at_cell(location)
		var ground_hit := _ray(ground + Vector3.UP * 0.2, ground - Vector3.UP * 0.2)
		_check(absf(ground.y) > 0.4 and ground_hit.get("collider") == runtime._floor,
			"a street outside the market is missing its physical slope at %s" % location)

	var curb := TomatinaMap.at_cell(Vector2(14.5, 167.0))
	var under := curb + Vector3.FORWARD * 1.7
	under.y = TomatinaMap.ground_height(under)
	var above := _ray(under + Vector3.UP * 1.5, under + Vector3.UP * 4.5)
	_check(String(above.collider.name).begins_with("ArcadeDeck") if above.has("collider") else false,
		"no solid balcony directly over the market pavement")
	_check_wall_splat(above, "balcony underside")
	var from := under + Vector3.UP * 1.65 - Vector3.RIGHT * 1.65
	var to := from + Vector3.RIGHT * 3.3
	_check(_ray(from, to).is_empty(), "the support blocks the walk under the balcony")
	var motion := PhysicsTestMotionParameters3D.new()
	var start := Vector3(from.x, TomatinaMap.ground_height(from) + 1.47, from.z)
	var end := Vector3(to.x, TomatinaMap.ground_height(to) + 1.47, to.z)
	motion.from = Transform3D(Basis.IDENTITY, start)
	motion.motion = end - start
	motion.exclude_bodies = ignored
	_check(not PhysicsServer3D.body_test_motion(player.get_rid(), motion),
		"the player capsule cannot travel through the balcony passage")
	var pier := curb + Vector3(-TomatinaMap.ARCADE_PIER_X, 1.65, -TomatinaMap.ARCADE_PIER_Z)
	var pier_hit := _ray(pier + Vector3.FORWARD * 1.2, pier)
	_check(String(pier_hit.collider.name).begins_with("ArcadePier") if pier_hit.has("collider") else false,
		"the visible stone support does not block a shot")
	_check_wall_splat(pier_hit, "stone support")

	var street := TomatinaMap.at_cell(Vector2(16, 164.5))
	var pavement := _ray(street + Vector3.UP, street - Vector3.UP)
	_check(pavement.get("collider") == runtime._floor, "the slope does not intercept a shot")
	if pavement.get("collider") == runtime._floor:
		var old_count := runtime._pending_splats.size()
		runtime._record_floor_splat(runtime._local, 1, pavement.position, ContaminationGrid.KIND_MUSTARD)
		_check(runtime._pending_splats.size() == old_count + 4 \
			and runtime._floor.sauce_kind_at(pavement.position) == ContaminationGrid.KIND_MUSTARD,
			"the raised pavement did not store and queue the sauce splat")

	_check_balcony_guards(player)

	var bowler := _bowler_at(&"market_bowler")
	var lane := bowler.bowling_lane
	var target := crest + lane * 20.0
	target.y = TomatinaMap.ground_height(target) + 1.28
	player.finish_respawn(target)
	bowler._advance_bowler(2.1, player)
	bowler._advance_bowler(MayoEnemy.SPECIAL_WINDUP + 0.01, player)
	var ball: MayoEnemy = bowler.ball_pool[0]
	var launch := ball.global_position
	_check(ball.is_ball_live() and launch.y > ball.stand_height() + 1.5,
		"the market ball did not launch from the slope")
	player.finish_respawn(approach + Vector3.RIGHT * 20.0 + Vector3.UP * 15.0)
	var rolled := 0.0
	var dropped := 0.0
	for step in 120:
		if not ball.is_ball_live():
			break
		ball.advance(1.0 / 60.0, [])
		await physics_frame
		if ball.is_ball_live():
			rolled = maxf(rolled, (ball.global_position - launch).dot(lane))
			dropped = maxf(dropped, launch.y - ball.global_position.y)
	_check(rolled > 22.0 and dropped > 1.5,
		"the ball did not follow the downhill lane: %.2f m over %.2f m drop" % [rolled, dropped])
	ball._retire_ball()
	runtime.play_support.special_leases.clear()
	for tag in TomatinaMap.BOWLER_TARGETS:
		if tag == &"market_bowler":
			continue
		var body := _bowler_at(tag)
		_check(is_equal_approx(body.solo_health, 32.0), "the %s does not have 32 base health" % tag)
		var crossing := TomatinaMap.at_cell(TomatinaMap.BOWLER_TARGETS[tag]) + Vector3.UP * 1.28
		player.finish_respawn(crossing)
		_check(body._has_clear_shot(player, body.global_position + Vector3.UP * (body.height * 0.3)),
			"the %s cannot see the path it bowls down" % tag)
		body._advance_bowler(2.1, player)
		body._advance_bowler(MayoEnemy.SPECIAL_WINDUP + 0.01, player)
		var cross_ball: MayoEnemy = body.ball_pool[0]
		_check(cross_ball.is_ball_live() and cross_ball._ball_velocity.normalized().dot(body.bowling_lane) > 0.99,
			"the %s did not throw down its assigned lane" % tag)
		if not String(tag).begins_with("cross_street_bowler") and cross_ball.is_ball_live():
			player.finish_respawn(crossing + Vector3.UP * 12.0)
			var released := cross_ball.global_position
			for _step in 80:
				cross_ball.advance(1.0 / 60.0, [])
				if not cross_ball.is_ball_live() or released.y - cross_ball.global_position.y > 0.65:
					break
				await physics_frame
			_check(cross_ball.is_ball_live() and released.y - cross_ball.global_position.y > 0.65,
				"the %s ball did not roll downhill" % tag)
		cross_ball._retire_ball()
		runtime.play_support.special_leases.clear()
	_check_bowling_groups(player)

	var shutter := runtime._street_breakouts[0]
	var brute := shutter.enemy
	var blind := TomatinaMap.at_cell(Vector2(17.8, 163.8)) + Vector3.UP * 1.65
	var corner_at: Vector3 = TomatinaMap.market_corner_box().position
	var corner := _ray(corner_at + Vector3.LEFT * 1.5, corner_at)
	_check(not brute.visible and brute.collision_layer == 0, "the dormant brute is still in play")
	_check(not _ray(blind, brute.global_position).is_empty(), "the market approach sees past the ambush cover")
	_check_wall_splat(corner, "ambush corner")
	var blocked := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_BEND) + Vector3.UP * 1.28
	player.finish_respawn(blocked)
	runtime._advance_street_breakout(shutter, 0.0, [player])
	_check(is_zero_approx(shutter.windup) and not shutter.opened,
		"the brute tried to charge through the stone corner")
	var trip := TomatinaMap.at_cell(Vector2(21.91, 161.35)) + Vector3.UP * 1.28
	player.finish_respawn(trip)
	await physics_frame
	_check(_ray(trip, brute.global_position).get("collider") == shutter.solid,
		"the shutter does not physically hide the brute from the road")
	_check_wall_splat(_ray(trip, brute.global_position), "wooden shutter")
	runtime._advance_street_breakout(shutter, 0.0, [player])
	runtime._advance_street_breakout(shutter, 0.16, [player])
	_check(shutter.windup > 0.0 and not shutter.opened and not brute.visible,
		"the rattle did not keep the brute hidden behind the solid shutter")
	runtime._advance_street_breakout(shutter, 0.16, [player])
	_check(shutter.opened and shutter.played_break and brute.visible and brute.is_charging(),
		"the shutter did not burst as the brute started charging")
	await physics_frame
	_check(_ray(trip, brute.global_position).is_empty(), "the broken shutter still blocks the road")
	var hit: MayoPlayer
	for _step in 55:
		hit = brute.advance(1.0 / 60.0, [player])
		if hit != null or not brute.is_charging():
			break
		await physics_frame
	_check(hit == player, "the opening charge did not traverse the shutter and hit a stationary player")

	var status := runtime.tomatina_status()
	shutter.reset()
	runtime.apply_tomatina_status(status)
	_check(shutter.opened and brute.visible and not shutter.played_break,
		"a late stage snapshot did not restore the opening without replaying the effect")

	shutter.reset()
	player.finish_respawn(trip)
	runtime._advance_street_breakout(shutter, 0.0, [player])
	var aim := shutter.charge.normalized()
	var sidestep := trip + aim.cross(Vector3.UP) * 3.2
	sidestep.y = TomatinaMap.ground_height(sidestep) + 1.28
	player.finish_respawn(sidestep)
	await physics_frame
	runtime._advance_street_breakout(shutter, runtime.BREAKOUT_RATTLE_SECONDS + 0.01, [player])
	_check(brute.is_charging() and aim.dot(brute._charge_direction) > 0.999,
		"the opening charge tracked a player who dodged during the rattle")
	hit = null
	for _step in 55:
		hit = brute.advance(1.0 / 60.0, [player])
		if hit != null or not brute.is_charging():
			break
		await physics_frame
	_check(hit == null and not brute.is_charging(), "the opening charge still hit after a sidestep")
	runtime._advance_street_breakout(shutter, 0.0, [player])
	_check(shutter.windup <= 0.0, "the broken shutter started a second ambush")
	await _check_truck_breakouts(player)
	for message in failures:
		printerr(message)
	if failures.is_empty():
		print("TOMATINA_STREET_OK")
	quit(0 if failures.is_empty() else 1)


func _check_fall_camera_on_hill(player: MayoPlayer, ground: Vector3) -> void:
	var saved := player.global_position
	runtime.set_first_person(true)
	player.finish_respawn(ground + Vector3.UP * MayoPlayer.CAPSULE_HEIGHT * 0.5)
	for direction in [-1.0, 1.0]:
		player.state = MayoPlayer.State.DOWN
		player.fall_direction = direction
		runtime.debug_set_aim(0.0, -40.0)
		var eye := runtime._camera.global_position
		var pavement := _ray(eye + Vector3.UP * 4.0, eye - Vector3.UP * 4.0)
		_check(pavement.get("collider") == runtime._floor and eye.y >= pavement.position.y + 0.50,
			"the first-person eye entered the market ramp with fall direction %.0f" % direction)
	player.finish_respawn(saved)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	static_query.from = from
	static_query.to = to
	return runtime.get_world_3d().direct_space_state.intersect_ray(static_query)


func _bowler_at(tag: StringName) -> MayoEnemy:
	for body in runtime._enemies:
		if body.get_meta("bowling_post", &"") == tag:
			return body
	return null


func _check_balcony_guards(player: MayoPlayer) -> void:
	var targets := [Vector2(27.53, 211.5), Vector2(26.39, 218.5), Vector2(15.5, 163.39),
		Vector2(32.39, 71.5), Vector2(30.39, 38.5)]
	var guards: Array[MayoEnemy] = []
	for body in runtime._enemies:
		if body.has_meta("balcony_guard"):
			guards.append(body)
	_check(guards.size() == targets.size(), "a balcony guard is missing")
	for index in mini(guards.size(), targets.size()):
		var guard := guards[index]
		var below := guard.global_position - Vector3.UP * guard.stand_height()
		var deck := _ray(below + Vector3.UP * 0.25, below - Vector3.UP * 0.25).get("collider") as Node
		_check(deck != null and String(deck.name).begins_with("ArcadeDeck"), "spitter %d has no deck" % index)
		player.finish_respawn(TomatinaMap.at_cell(targets[index]) + Vector3.UP * 1.28)
		guard._advance_spitter(2.0, player)
		_check(guard.take_spit_request() == player, "balcony spitter %d cannot shoot through its frontage" % index)
		runtime.play_support.special_leases.clear()


func _check_bowling_groups(player: MayoPlayer) -> void:
	var crossings := {
		"market_bowler": Vector2(14.31, 164.91),
		"terrace_bowler": Vector2(26.2, 215.32),
		"rescue_climb_bowler": Vector2(15.71, 96.78),
		"cross_street_bowler": Vector2(30.85, 41.72),
	}
	var expected := {"market_bowler": 3, "terrace_bowler": 2, "rescue_climb_bowler": 3, "cross_street_bowler": 2}
	for group: String in crossings:
		player.finish_respawn(TomatinaMap.at_cell(crossings[group]) + Vector3.UP * 1.28)
		var launchers: Array[MayoEnemy] = []
		for tag in TomatinaMap.BOWLER_TARGETS:
			if String(tag).begins_with(group):
				launchers.append(_bowler_at(tag))
		_check(launchers.size() == expected[group], "%s is missing some bowlers" % group)
		for body in launchers:
			body._advance_bowler(MayoEnemy.BOWLING_INTERVAL + 0.01, player)
		for body in launchers:
			body._advance_bowler(MayoEnemy.SPECIAL_WINDUP + 0.01, player)
			_check(body.ball_pool[0].is_ball_live(), "%s did not fire with its group" % body.get_meta("bowling_post"))
		for body in launchers:
			body.ball_pool[0]._retire_ball()


func _check_truck_breakouts(player: MayoPlayer) -> void:
	_check(runtime._street_breakouts.size() == 4, "the street should have a shutter and three truck ambushes")
	if runtime._street_breakouts.size() < 4:
		return
	var targets := {
		&"truck_ambush": Vector2(24.18, 56.95),
		&"truck_ambush_terrace": Vector2(32.5, 198.85),
		&"truck_ambush_rescue": Vector2(26.5, 81.85),
	}
	for truck in runtime._street_breakouts:
		if targets.has(truck.tag):
			await _check_one_truck(player, truck, targets[truck.tag])
	var status := runtime.tomatina_status()
	for breakout in runtime._street_breakouts:
		breakout.reset()
	runtime.apply_tomatina_status(status)
	for breakout in runtime._street_breakouts:
		_check(breakout.opened and not breakout.played_break, "the stage snapshot lost a broken cover")


func _check_one_truck(player: MayoPlayer, truck: TomatinaBreakout, crossing: Vector2) -> void:
	var brute := truck.enemy
	var target := TomatinaMap.at_cell(crossing) + Vector3.UP * 1.28
	var cab_name: String = TomatinaMap.breakout_truck_boxes(truck.tag)[1].name
	var cab := runtime.get_node(cab_name) as ContaminableObject
	player.finish_respawn(target)
	await physics_frame
	_check(not brute.visible and _ray(target, brute.global_position).get("collider") == truck.solid,
		"a player can see inside the intact truck")
	for cell in truck.parking_cells:
		_check(not runtime._nav.is_walkable(cell), "navigation enters the intact cargo")
	runtime._advance_street_breakout(truck, 0.0, [player])
	_check(truck.windup > 0.0, "%s does not trigger on the main street" % truck.tag)
	runtime._advance_street_breakout(truck, runtime.BREAKOUT_RATTLE_SECONDS + 0.01, [player])
	_check(truck.opened and truck.played_break and brute.is_charging() and cab.collision_layer != 0,
		"the cargo did not break while the cab stayed in place")
	for cell in truck.parking_cells:
		_check(runtime._nav.is_walkable(cell), "navigation still treats the broken cargo as solid")
	var hit: MayoPlayer
	for _step in 55:
		hit = brute.advance(1.0 / 60.0, [player])
		if hit != null or not brute.is_charging():
			break
		await physics_frame
	_check(hit == player, "%s brute did not reach a player in the charge lane" % truck.tag)


func _check_side_streets(player: MayoPlayer, ignored: Array[RID]) -> void:
	var pockets := [
		["loading pocket", [Vector2(4.5, 169.5), Vector2(1.92, 169.5)],
			Vector2(1.4, 169.35), Vector2(4.4, 168.5), Vector2(1.7, 168.5), "OverturnedHandcart"],
		["market side lane", [Vector2(36.7, 140.5), Vector2(39.7, 140.5), Vector2(39.7, 138.7),
			Vector2(39.7, 137.5), Vector2(36.7, 137.5)],
			Vector2(40.55, 138.7), Vector2(36.7, 139.0), Vector2(39.7, 139.0), "ParkedVan"],
		["rescue bay", [Vector2(30.0, 71.55), Vector2(27.15, 71.55), Vector2(27.15, 69.55)],
			Vector2(26.65, 69.55), Vector2(30.0, 70.5), Vector2(26.75, 70.5), "CollapsedStoneWall"],
	]
	var motion := PhysicsTestMotionParameters3D.new()
	motion.exclude_bodies = ignored
	for pocket: Array in pockets:
		var label: String = pocket[0]
		var lane: Array = pocket[1]
		for index in range(1, lane.size()):
			var from := TomatinaMap.at_cell(lane[index - 1]) + Vector3.UP * 1.47
			var to := TomatinaMap.at_cell(lane[index]) + Vector3.UP * 1.47
			motion.from = Transform3D(Basis.IDENTITY, from)
			motion.motion = to - from
			_check(not PhysicsServer3D.body_test_motion(player.get_rid(), motion),
				"the player capsule cannot traverse %s at %s" % [label, str(lane[index])])
		var cache_cell: Vector2 = pocket[2]
		var cache := TomatinaMap.at_cell(cache_cell)
		var cache_side := Vector2(39.99, 138.7) if label == "market side lane" else Vector2(lane.back())
		player.finish_respawn(TomatinaMap.at_cell(cache_side) + Vector3.UP * 1.28)
		var station := runtime.station_in_reach(player)
		_check(station >= 0 and (runtime.refill_stations()[station].position as Vector3).distance_to(cache) < 1.0,
			"the cache cannot be used from %s" % label)
		var cover := _ray(TomatinaMap.at_cell(pocket[3]) + Vector3.UP * 1.1,
			TomatinaMap.at_cell(pocket[4]) + Vector3.UP * 1.1).get("collider") as ContaminableObject
		_check(cover != null and String(cover.name).ends_with(pocket[5]), "%s has no solid cover" % label)


func _check_floor_geometry() -> void:
	var floor_body := runtime._floor
	var full_triangles := 0
	for index in floor_body.grid.tile_count():
		var tile := floor_body.grid.tile_region(index)
		full_triangles += maxi(1, ceili(tile.size.x / 2.0)) * maxi(1, ceili(tile.size.y / 2.0)) * 2
	var collider := floor_body.get_node("FloorCollision") as CollisionShape3D
	var terrain := collider.shape as ConcavePolygonShape3D
	var triangles := int(terrain.get_faces().size() / 3.0)
	_check(triangles < full_triangles, "flat tiles are still fully subdivided")
	print("floor collision triangles: %d instead of %d" % [triangles, full_triangles])


func _check_wall_splat(hit: Dictionary, label: String) -> void:
	var wall := hit.get("collider") as ContaminableObject
	_check(wall != null, label + " has no paintable collider")
	if wall == null:
		return
	var old_count := runtime._pending_splats.size()
	var old_coverage := wall.painted_cell_count()
	runtime._record_splat(wall, hit.position, hit.normal, runtime._local, false, ContaminationGrid.KIND_KETCHUP)
	var packet := runtime._pending_splats.slice(old_count)
	_check(packet.size() == 4 and wall.painted_cell_count() > old_coverage,
		label + " did not store and queue the sauce splat")
	if packet.size() != 4:
		return
	var face := packet[1] % runtime.FACES_PER_WALL
	_check(wall.get_child(face).visible, label + " has a hidden paint overlay")
	wall.wash_at(hit.position, hit.normal, 1.0)
	_check(wall.painted_cell_count() == old_coverage, label + " did not wash off")
	runtime.apply_splats(packet)
	_check(wall.painted_cell_count() > old_coverage and wall.get_child(face).visible,
		label + " did not restore the visible paint when a packet was replayed")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)
