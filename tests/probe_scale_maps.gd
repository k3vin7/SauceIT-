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
	var packed := load(path) as PackedScene
	_check(packed != null, "%s did not load" % path)
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var scaled_map := scene.get_node("ScaledMap") as Node3D
	var graybox := scene.get_node("ScaledMap/CorridorGraybox") as CorridorGraybox
	var player := scene.get_node("Player") as CharacterBody3D
	var player_shape := scene.get_node("Player/CollisionShape3D") as CollisionShape3D
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
	_check(player.position.x == 0.0 and player.position.z == 0.0,
		"%s player is not at the Kalda origin" % path)
	var capsule := player_shape.shape as CapsuleShape3D
	_check(capsule != null and is_equal_approx(capsule.height, 2.56),
		"%s player capsule is not 2.56 m" % path)

	var query := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 12.0, 0.0), Vector3(0.0, -12.0, 0.0))
	query.exclude = [player.get_rid()]
	var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "%s terrain collision missed at the spawn" % path)

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

	if failures == 0:
		print("MAYO_MAP_OK %s" % path.get_file())
	scene.queue_free()
	await process_frame
