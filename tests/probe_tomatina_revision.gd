extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
func run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("REVISION_TIMEOUT"); quit(2))
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var player: MayoPlayer = scene._local.player
	player.set_physics_process(false)
	check(is_instance_valid(scene.play_support), "support not installed")
	scene.play_support.advance(0.0)
	player.slip_grace = 1.2
	player.state = MayoPlayer.State.NORMAL
	player.begin_slip()
	check(player.state == MayoPlayer.State.NORMAL, "repeated slip bypasses grace")
	player.health = 100.0
	player.damage_grace = 0.0
	player.take_damage(35.0)
	player.take_damage(35.0)
	check(is_equal_approx(player.health, 65.0), "large hits stack in grace")
	player.health = 100.0
	player.damage_grace = 0.0
	player.take_damage(6.0)
	player.take_damage(6.0)
	check(is_equal_approx(player.health, 94.0), "small simultaneous hits stack without grace")
	player.finish_respawn(player.global_position)
	check(player.slip_grace > 0.0, "respawn has no recovery protection")
	scene._clear_respawn_visor(scene._local)
	check(player.visor.painted_cell_count() == 0, "respawn visor not cleared")
	var bombs := 0
	for index in 200:
		if int(scene._deal_grunt_burst(index).tier) == 2:
			bombs += 1
	check(bombs > 25 and bombs < 75, "explosive mix is not near 22 percent")
	var count := 0
	for enemy in scene._enemies:
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
			count += 1
	check(count >= 220, "main-road enemy density dropped below the approved encounter plan")
	var first = scene._enemies[0]
	var second = scene._enemies[1]
	scene.play_support.special_leases.clear()
	check(scene.play_support.request_special(first, player), "first special denied")
	check(not scene.play_support.request_special(second, player), "simultaneous specials target same player")
	check(scene.play_support.request_contact(first, player), "first contact denied")
	check(not scene.play_support.request_contact(second, player), "crowd contact bypasses budget")
	scene.set_menu_input_enabled(false)
	check(not scene._input_enabled and player.frozen, "menu input is not locked")
	scene.set_physics_process(true)
	scene.set_menu_input_enabled(false)
	check(scene.is_physics_processing(), "multiplayer menu stopped world simulation")
	scene.set_physics_process(false)
	scene.set_menu_input_enabled(true)
	scene.play_support.note_rescue(player.peer_id)
	var report: Dictionary = scene.mission_report()
	check(report.players[0].rescues == 1, "rescue missing from report")
	var column := VBoxContainer.new()
	root.add_child(column)
	preload("res://scripts/mission_statistics.gd").build(column, report)
	check(column.get_child_count() == 2, "statistics screen failed")
	var settings = preload("res://scripts/game_options.gd").new()
	settings.load_config(ConfigFile.new())
	settings.apply_world(scene)
	check(is_equal_approx(scene.camera_fov, 74.0), "display options not applied")
	settings.bindings.run = KEY_Z
	settings.apply_window(root)
	var released := InputEventKey.new()
	released.physical_keycode = KEY_Z
	released.pressed = false
	Input.action_press("run")
	player._input(released)
	check(not Input.is_action_pressed("run"), "rebound run key release remained held")
	scene.play_support._update_aim_feedback()
	# Explicitly build the grenade trajectory; it must never draw a landing marker.
	var slots: Array = scene.item_slots(player.peer_id)
	slots[1] = 1
	scene._item_selected[player.peer_id] = 1
	scene.play_support._update_arc(player.global_position + Vector3.UP, Vector3.FORWARD)
	check(not scene._crosshair.trajectory_segments.is_empty(), "throw trajectory missing")
	var legacy = load("res://scripts/key_legend.gd").new()
	legacy.world = scene
	root.add_child(legacy)
	check(not legacy._rows().is_empty(), "key legend failed")
	var tutorial := MayoTutorial.new()
	tutorial.world = scene
	tutorial.stage = MayoTutorial.Stage.GET_SAUCE
	check(tutorial.objective_text().contains("소스통 받기") and not tutorial.objective_text().contains("1 마요네즈"), "tutorial still teaches obsolete number keys")
	tutorial.free()
	column.queue_free()
	legacy.queue_free()
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TOMATINA_REVISION_OK grunts=", count, " bombs_in_200=", bombs)
	quit(0 if failures.is_empty() else 1)
