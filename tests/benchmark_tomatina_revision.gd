extends SceneTree
## Opt-in only. Ask the user immediately before supplying --allow-performance.
## One local rendered world, not a four-player or long-session qualification.
var results: Array[Dictionary] = []
var scene
var wall_hitches: Array[Dictionary] = []
func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--allow-performance"):
		push_error("PERFORMANCE_APPROVAL_REQUIRED")
		quit(2)
		return
	MayoTutorial.disabled = true
	call_deferred("run")
func sample(label: String, seconds: float) -> void:
	var times: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	var last_profile: Dictionary = scene.debug_timings_us.duplicate()
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		times.append(frame_ms)
		if frame_ms > 33.4:
			var cpu := {}
			for key in scene.debug_timings_us:
				cpu[key] = float(scene.debug_timings_us[key] - last_profile[key]) / 1000.0
			wall_hitches.append({"scenario": label, "wall_frame_ms": frame_ms, "script_sections_ms": cpu})
		last_profile = scene.debug_timings_us.duplicate()
		last = now
	var total := 0.0
	for value in times:
		total += value
	times.sort()
	var count := maxi(1, ceili(times.size() * 0.01))
	var slow_total := 0.0
	for index in range(times.size() - count, times.size()):
		slow_total += times[index]
	results.append({"scenario": label, "frames": times.size(), "average_fps": times.size() * 1000.0 / total,
		"one_percent_low_fps": count * 1000.0 / slow_total, "p95_ms": times[int(times.size() * 0.95)],
		"max_ms": times.back(), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered performance test requires a display")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	scene._healing_rng.seed = 20261117
	scene._sauce_parts._rng.seed = 20261117
	scene.debug_profile_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(3.0).timeout
	scene.play_support.diagnostics_enabled = true
	await sample("start_idle_324_grunts", 8.0)
	var enemy: MayoEnemy
	for candidate in scene._enemies:
		if candidate.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
			enemy = candidate
			break
	var at: Vector3 = enemy.global_position + Vector3(0, 0, 5)
	at.y = 1.28
	scene._local.player.finish_respawn(at)
	scene.debug_aim_at(enemy.global_position)
	scene.debug_set_input(Vector2.ZERO, false, true)
	await sample("alley_spraying", 10.0)
	scene.debug_set_input(Vector2.ZERO, false, false)
	# Synthetic chain workload. It is not a player completion/difficulty result.
	var bomb: MayoEnemy
	for candidate in scene._enemies:
		if candidate.is_alive() and scene._is_overripe(candidate):
			bomb = candidate
			break
	if bomb != null:
		at = bomb.global_position + Vector3(0, 0, 8)
		at.y = 1.28
		scene._local.player.finish_respawn(at)
		scene.debug_aim_at(bomb.global_position)
		bomb.take_sauce_hit(Vector3.INF, bomb.max_health + 1.0)
		scene._finish_tomato_kill(bomb, scene._local)
	await sample("synthetic_chain_burst", 10.0)
	scene.play_support.save_diagnostics("res://reports/tomatina_revision_hitches.json")
	var file := FileAccess.open("res://reports/tomatina_revision_performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "single rendered world, 31 seconds, no four-player/long-session claim",
		"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [1280,720], "vsync": false, "results": results, "wall_hitches": wall_hitches}, "\t"))
	print("TOMATINA_APPROVED_PERFORMANCE_DONE")
	scene.queue_free()
	await process_frame
	quit()
