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
	var replica = load("res://main.tscn").instantiate()
	root.add_child(replica)
	await process_frame
	replica._net._apply_state(ids, state)
	await process_frame
	_check(replica._local.character_index == 1,
		"Character_2 selection was not applied from network state")
	root.remove_child(replica)
	replica.queue_free()

	scene.set_first_person(true)
	_check(not shooter.player_visual.visible, "local Character_2 is visible in first person")
	scene.set_first_person(false)
	_check(shooter.player_visual.visible, "local Character_2 is hidden in third person")
	scene._unhandled_input(switch_event)
	await process_frame
	_check(shooter.player_visual.name == "Character_1Visual",
		"switching back did not rebuild Character_1")

	if failures.is_empty():
		print("CHARACTER_SWITCH_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
