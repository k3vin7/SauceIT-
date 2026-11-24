extends SceneTree

const Runtime := preload("res://scripts/mayo_prototype.gd")

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

	var approach := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_APPROACH)
	var crest := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_CREST)
	var crest_hit := _ray(crest + Vector3.UP, crest - Vector3.UP)
	_check(crest.y - approach.y >= 2.4 and crest_hit.get("collider") == runtime._floor,
		"market floor collision does not climb to the crest")
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

	var spitter: MayoEnemy
	for body: MayoEnemy in runtime._enemies:
		if body.kind == MayoEnemy.EnemyKind.KETCHUP_SPITTER and int(body.get_meta("encounter")) == 0:
			spitter = body
	_check(is_instance_valid(spitter) and spitter.global_position.y - spitter.stand_height() > 3.5,
		"the first spitter is not stationed above the street")
	if is_instance_valid(spitter):
		var below := spitter.global_position - Vector3.UP * spitter.stand_height()
		var deck := _ray(below + Vector3.UP * 0.25, below - Vector3.UP * 0.25)
		_check(String(deck.collider.name).begins_with("ArcadeDeck") if deck.has("collider") else false,
			"the spitter has no physical terrace under it")

	var bowler := runtime._market_bowler
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
	for body: MayoEnemy in runtime._enemies:
		if body == bowler or body.kind != MayoEnemy.EnemyKind.BOWLING_TOMATO:
			continue
		var crossing := body.global_position + Vector3.LEFT * 10.0
		crossing.y = TomatinaMap.ground_height(crossing) + 1.28
		player.finish_respawn(crossing)
		body._advance_bowler(2.1, player)
		body._advance_bowler(MayoEnemy.SPECIAL_WINDUP + 0.01, player)
		var cross_ball: MayoEnemy = body.ball_pool[0]
		_check(cross_ball.is_ball_live() and cross_ball._ball_velocity.normalized().dot(Vector3.LEFT) > 0.99,
			"the second bowler did not throw across the plaza approach")
		cross_ball._retire_ball()
	runtime.play_support.special_leases.clear()

	var brute := runtime._market_ambush_enemy
	var blind := TomatinaMap.at_cell(Vector2(17.8, 163.8)) + Vector3.UP * 1.65
	var corner := _ray(blind, brute.global_position)
	_check(String(corner.collider.name) == "MarketCornerPier" if corner.has("collider") else false,
		"the brute is visible up the market street")
	_check_wall_splat(corner, "ambush corner")
	runtime._advance_market_ambush([player])
	_check(not runtime._market_ambush_started, "the brute triggered before the player crossed the corner")
	var trip := TomatinaMap.at_cell(TomatinaMap.STREET_PROFILE.MARKET_TRIP) + Vector3.UP * 1.28
	player.finish_respawn(trip)
	await physics_frame
	runtime._advance_market_ambush([player])
	_check(runtime._market_ambush_started and brute._windup > 0.0 and brute._windup < 0.15,
		"the brute did not start its short ambush after the player rounded the corner")
	brute.advance(0.135, [player])
	_check(brute.is_charging(), "the short ambush did not turn into a real charge")
	for message in failures:
		printerr(message)
	if failures.is_empty():
		print("TOMATINA_STREET_OK")
	quit(0 if failures.is_empty() else 1)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	static_query.from = from
	static_query.to = to
	return runtime.get_world_3d().direct_space_state.intersect_ray(static_query)


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
