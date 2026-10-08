extends SceneTree

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

	var shooter = scene._local
	var player_collision: CollisionShape3D
	for child in shooter.player.get_children():
		if child is CollisionShape3D:
			player_collision = child as CollisionShape3D
			break
	_check(shooter.character_index == 0, "the default character is not Character_1")
	_check(shooter.player_visual.name == "Character_1Visual",
		"Character_1 visual was not built")

	var has_c_binding := false
	for event in InputMap.action_get_events("switch_character"):
		if event is InputEventKey and event.physical_keycode == KEY_C:
			has_c_binding = true
	_check(has_c_binding, "switch_character is not bound to the C key")
	var switch_event := InputEventAction.new()
	switch_event.action = &"switch_character"
	switch_event.pressed = true
	scene._unhandled_input(switch_event)
	await process_frame
	_check(shooter.character_index == 1, "character index did not switch to Character_2")
	_check(shooter.player_visual.name == "Character_2Visual",
		"Character_2 visual was not built")
	_check(shooter.player_animation != null, "Character_2 has no AnimationPlayer")
	for required in [shooter.walk_animation, shooter.run_animation, shooter.death_animation]:
		_check(not required.is_empty(), "Character_2 is missing a gameplay animation")
	_check(is_equal_approx(shooter.player_visual.scale.x,
		MayoPlayer.CAPSULE_HEIGHT / scene.PLAYER_CHARACTER_SOURCE_HEIGHTS[1]),
		"Character_2 was not scaled to the gameplay capsule")
	var ids := PackedInt32Array()
	var state: PackedFloat32Array = scene._net._collect_state(ids)
	_check(state.size() == scene._net.STATE_STRIDE,
		"network state does not contain exactly one complete player record")
	_check(int(state[scene._net.STATE_STRIDE - 1]) == 1,
		"Character_2 selection is missing from network state")

	scene._unhandled_input(switch_event)
	await process_frame
	_check(shooter.character_index == 2, "character index did not switch to Character_3")
	_check(shooter.player_visual.name == "Character_3Visual",
		"Character_3 visual was not built")
	_check(shooter.player_animation != null, "Character_3 has no AnimationPlayer")
	for required in [shooter.walk_animation, shooter.run_animation, shooter.death_animation]:
		_check(not required.is_empty(), "Character_3 is missing a gameplay animation")
	_check(is_equal_approx(shooter.player_visual.scale.x,
		MayoPlayer.CAPSULE_HEIGHT / scene.PLAYER_CHARACTER_SOURCE_HEIGHTS[2]),
		"Character_3 was not scaled to the gameplay capsule")
	state = scene._net._collect_state(ids)
	_check(int(state[scene._net.STATE_STRIDE - 1]) == 2,
		"Character_3 selection is missing from network state")
	var replica = load("res://main.tscn").instantiate()
	root.add_child(replica)
	await process_frame
	replica._net._apply_state(ids, state)
	await process_frame
	_check(replica._local.character_index == 2,
		"Character_3 selection was not applied from network state")
	root.remove_child(replica)
	replica.queue_free()

	scene._unhandled_input(switch_event)
	await process_frame
	_check(shooter.character_index == 3, "character index did not switch to Character_4")
	_check(shooter.player_visual.name == "Character_4Visual",
		"Character_4 visual was not built")
	_check(shooter.player_animation != null, "Character_4 has no AnimationPlayer")
	for required in [shooter.walk_animation, shooter.run_animation, shooter.death_animation]:
		_check(not required.is_empty(), "Character_4 is missing a gameplay animation")
	_check(is_equal_approx(shooter.player_visual.scale.x,
		MayoPlayer.CAPSULE_HEIGHT / scene.PLAYER_CHARACTER_SOURCE_HEIGHTS[3] \
		* scene.PLAYER_CHARACTER_SIZE_MULTIPLIERS[3]),
		"Character_4 was not scaled to the gameplay capsule")
	var character_4_capsule := player_collision.shape as CapsuleShape3D
	_check(is_equal_approx(character_4_capsule.radius,
		MayoPlayer.CAPSULE_RADIUS * scene.PLAYER_CHARACTER_SIZE_MULTIPLIERS[3]),
		"Character_4 collider radius was not scaled with the visual")
	_check(is_equal_approx(character_4_capsule.height,
		MayoPlayer.CAPSULE_HEIGHT * scene.PLAYER_CHARACTER_SIZE_MULTIPLIERS[3]),
		"Character_4 collider height was not scaled with the visual")
	_check(is_equal_approx(player_collision.position.y - character_4_capsule.height * 0.5,
		-MayoPlayer.CAPSULE_HEIGHT * 0.5),
		"Character_4 collider bottom moved away from the shared ground point")
	state = scene._net._collect_state(ids)
	_check(int(state[scene._net.STATE_STRIDE - 1]) == 3,
		"Character_4 selection is missing from network state")
	replica = load("res://main.tscn").instantiate()
	root.add_child(replica)
	await process_frame
	replica._net._apply_state(ids, state)
	await process_frame
	_check(replica._local.character_index == 3,
		"Character_4 selection was not applied from network state")
	var replica_collision: CollisionShape3D
	for child in replica._local.player.get_children():
		if child is CollisionShape3D:
			replica_collision = child as CollisionShape3D
			break
	var replica_capsule := replica_collision.shape as CapsuleShape3D
	_check(replica_capsule != null and is_equal_approx(replica_capsule.height,
		MayoPlayer.CAPSULE_HEIGHT * scene.PLAYER_CHARACTER_SIZE_MULTIPLIERS[3]),
		"Character_4 collider size was not applied from network state")
	root.remove_child(replica)
	replica.queue_free()

	scene.set_first_person(true)
	_check(not shooter.player_visual.visible, "local Character_4 is visible in first person")
	scene.set_first_person(false)
	_check(shooter.player_visual.visible, "local Character_4 is hidden in third person")
	scene._unhandled_input(switch_event)
	await process_frame
	_check(shooter.player_visual.name == "Character_1Visual",
		"switching back did not rebuild Character_1")
	var character_1_capsule := player_collision.shape as CapsuleShape3D
	_check(is_equal_approx(character_1_capsule.radius, MayoPlayer.CAPSULE_RADIUS) \
		and is_equal_approx(character_1_capsule.height, MayoPlayer.CAPSULE_HEIGHT) \
		and is_zero_approx(player_collision.position.y),
		"switching back did not restore the Character_1 collider")

	# A remote Character_1 fires from its authored bottle socket. When it changes
	# to a character without that socket, the old visual is freed and the stable
	# viewmodel muzzle must replace it instead of leaving a dangling reference.
	var remote = scene.create_avatar(2, 1, false)
	var old_remote_muzzle = remote.muzzle
	_check(is_instance_valid(old_remote_muzzle), "remote Character_1 has no muzzle")
	scene.set_character_variant(remote.peer_id, 1)
	await process_frame
	_check(is_instance_valid(remote.muzzle),
		"remote character switch left the muzzle pointing at a freed node")
	_check(remote.muzzle == remote.viewmodel_muzzle,
		"remote character without a bottle socket did not fall back to the viewmodel muzzle")
	var point_count: int = remote.points.size()
	scene._emit_point(remote)
	_check(remote.points.size() == point_count + 1,
		"remote character could not emit after switching away from Character_1")

	if failures.is_empty():
		print("CHARACTER_SWITCH_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
