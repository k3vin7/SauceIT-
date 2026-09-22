extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	await _check_scene("res://test_scale_227.tscn", 2.27)
	await _check_scene("res://test_scale_180.tscn", 1.80)
	quit(1 if failures > 0 else 0)


func _check_scene(path: String, expected_scale: float) -> void:
	var failures_before := failures
	var packed := load(path) as PackedScene
	_check(packed != null, "%s did not load" % path)
	if packed == null:
		return
	var scene := packed.instantiate() as ScaleTestBase
	root.add_child(scene)
	await process_frame
	await physics_frame
	await physics_frame

	var scaled_map := scene.get_node("ScaledMap") as Node3D
	var graybox := scene.get_node("ScaledMap/CorridorGraybox") as CorridorGraybox
	var game := scene.get_node("Game")
	var player := scene.player
	var player_shape: CollisionShape3D
	for child in player.get_children():
		if child is CollisionShape3D:
			player_shape = child as CollisionShape3D
			break
	var net := game.get_node("Net") as MayoNet
	var camera := game.get_node("ThirdPersonCamera") as Camera3D
	_check(scaled_map.scale.is_equal_approx(Vector3.ONE * expected_scale),
		"%s scale is %s, expected %.2f" % [path, scaled_map.scale, expected_scale])
	_check(graybox.corridor_distance_m == 45.0, "%s corridor is not 45 m" % path)
	_check(graybox.inside_building_count == 47,
		"%s has %d inside buildings, expected 47" % [path, graybox.inside_building_count])
	_check(graybox.row3_building_count == 150,
		"%s has %d Row3 buildings, expected 150" % [path, graybox.row3_building_count])
	_check(get_nodes_in_group("Row3").size() == 150,
		"%s Row3 group does not contain 150 nodes" % path)
	_check(graybox.collision_body_count() == 48,
		"%s has %d map collision bodies, expected 47 buildings + terrain" % [
			path, graybox.collision_body_count()])

	_check(player != null and player is MayoPlayer,
		"%s did not instance the actual MayoPlayer from main.tscn" % path)
	_check(is_equal_approx(player.global_position.x, ScaleTestBase.SPAWN_POSITION.x) \
		and is_equal_approx(player.global_position.z, ScaleTestBase.SPAWN_POSITION.z),
		"%s player is not at the Kalda spawn" % path)
	var capsule := player_shape.shape as CapsuleShape3D if player_shape != null else null
	_check(capsule != null and is_equal_approx(capsule.height, 2.56),
		"%s player capsule is not 2.56 m" % path)
	_check(is_equal_approx(player.walk_speed, 5.2) and is_equal_approx(player.run_speed, 10.4),
		"%s actual player speeds changed" % path)
	_check(net != null and not net.is_online(),
		"%s did not start as an offline one-player session" % path)
	_check(camera != null and camera.current,
		"%s actual game camera is not current" % path)

	var dummies := get_nodes_in_group("scale_test_dummy")
	_check(dummies.size() == 4, "%s has %d narrow-section dummies, expected 4" % [
		path, dummies.size()])
	for node in dummies:
		var dummy := node as MayoEnemy
		_check(dummy != null and is_equal_approx(dummy.height, 4.1),
			"%s has a dummy that is not the 4.1 m enemy body" % path)
		_check(not dummy.authority and dummy.get_child_count() > 0,
			"%s dummy is active or has no collision geometry" % path)

	var query := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 12.0, 0.0), Vector3(0.0, -12.0, 0.0))
	query.exclude = [player.get_rid()]
	var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "%s terrain collision missed at the spawn" % path)

	# Exercise the exact main.tscn input adapter and MayoPlayer simulation.
	var movement_start := player.global_position
	game.debug_set_input(Vector2(0.0, -1.0), false, false)
	for index in 12:
		await physics_frame
	game.debug_clear_input_override()
	_check(player.global_position.z < movement_start.z - 0.05,
		"%s actual player did not walk through the main.tscn input path" % path)
	_check(scene.stopwatch_state == ScaleTestBase.StopwatchState.RUNNING,
		"%s stopwatch did not start after leaving spawn" % path)

	player.global_position = scene.rootsiturg_entry_world
	await process_frame
	await process_frame
	_check(scene.stopwatch_state == ScaleTestBase.StopwatchState.FINISHED,
		"%s stopwatch did not stop on Rootsiturg entry" % path)
	scene.reset_to_spawn()
	_check(scene.stopwatch_state == ScaleTestBase.StopwatchState.WAITING \
		and is_zero_approx(scene.stopwatch_seconds) \
		and is_equal_approx(player.global_position.x, ScaleTestBase.SPAWN_POSITION.x) \
		and is_equal_approx(player.global_position.z, ScaleTestBase.SPAWN_POSITION.z),
		"%s reset did not restore spawn and stopwatch" % path)

	graybox.corridor_distance_m = 30.0
	await process_frame
	_check(graybox.inside_building_count == 31 and graybox.row3_building_count == 166,
		"%s export corridor did not reclassify at 30 m" % path)
	_check(graybox.collision_body_count() == 32,
		"%s collision bodies did not follow the 30 m corridor" % path)
	graybox.corridor_distance_m = 45.0
	await process_frame
	_check(graybox.inside_building_count == 47 and graybox.row3_building_count == 150,
		"%s export corridor did not restore at 45 m" % path)

	if failures == failures_before:
		print("MAYO_MAP_OK %s" % path.get_file())
	scene.queue_free()
	await process_frame
