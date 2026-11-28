extends SceneTree
## Opt-in only. Ask the user immediately before supplying --allow-performance.
## One local rendered world, not a four-player or long-session qualification.

class ShaderCacheLogger extends Logger:
	var _mutex := Mutex.new()
	var _errors: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if function not in ["_save_to_cache", "_load_from_cache"]:
			return
		_mutex.lock()
		_errors.append({"timestamp_us": Time.get_ticks_usec(), "function": function,
			"file": file, "line": line, "message": rationale if not rationale.is_empty() else code})
		_mutex.unlock()

	func snapshot() -> Array[Dictionary]:
		_mutex.lock()
		var errors := _errors.duplicate()
		_mutex.unlock()
		return errors


var results: Array[Dictionary] = []
var scene
var wall_hitches: Array[Dictionary] = []
var viewport_rid: RID
var resolution := Vector2i(1280, 720)
var cache_logger := ShaderCacheLogger.new()
var frame_budget_ms := 0.0
var warmup_ms := 0.0


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--allow-performance"):
		push_error("PERFORMANCE_APPROVAL_REQUIRED")
		quit(2)
		return
	MayoTutorial.disabled = true
	OS.add_logger(cache_logger)
	call_deferred("run")


func sample(label: String, seconds: float, begin := Callable(), sweep := false) -> void:
	await RenderingServer.frame_post_draw
	var times: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var peak_draw_calls := 0
	var long_frames := 0
	var missed_target := 0
	var slow_frames := 0
	var upload_start: int = scene._floor.grid.bytes_uploaded_total
	var net_start: int = scene._net.state_bytes_sent + scene._net.splat_bytes_sent
	var start := Time.get_ticks_usec()
	var last := start
	var last_profile: Dictionary = scene.debug_timings_us.duplicate()
	var last_upload_bytes := upload_start
	var last_upload_us: int = scene._floor.grid.upload_time_us
	if begin.is_valid():
		begin.call()
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		if sweep:
			scene.apply_look(Vector2(3.0 / scene.mouse_sensitivity, 0.0))
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		var draw_calls := root.get_render_info(
			Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var upload_bytes: int = scene._floor.grid.bytes_uploaded_total
		var upload_us: int = scene._floor.grid.upload_time_us
		times.append(frame_ms)
		render_cpu.append(cpu_ms)
		render_gpu.append(gpu_ms)
		peak_draw_calls = maxi(peak_draw_calls, draw_calls)
		if frame_ms > frame_budget_ms:
			missed_target += 1
		if frame_ms > 33.4:
			long_frames += 1
		if frame_ms > frame_budget_ms * 1.5:
			slow_frames += 1
			var cpu := {}
			for key in scene.debug_timings_us:
				cpu[key] = float(scene.debug_timings_us[key] - last_profile[key]) / 1000.0
			cpu["floor_upload"] = float(upload_us - last_upload_us) / 1000.0
			wall_hitches.append({"scenario": label, "wall_frame_ms": frame_ms,
				"start_us": last, "end_us": now, "script_sections_ms": cpu,
				"render_cpu_ms": cpu_ms, "render_gpu_ms": gpu_ms,
				"visible_draw_calls": draw_calls, "floor_upload_bytes": upload_bytes - last_upload_bytes})
		last_profile = scene.debug_timings_us.duplicate()
		last_upload_bytes = upload_bytes
		last_upload_us = upload_us
		last = now
	var total := 0.0
	for value in times:
		total += value
	times.sort()
	render_cpu.sort()
	render_gpu.sort()
	var count := maxi(1, ceili(times.size() * 0.01))
	var slow_total := 0.0
	for index in range(times.size() - count, times.size()):
		slow_total += times[index]
	results.append({"scenario": label, "frames": times.size(), "average_fps": times.size() * 1000.0 / total,
		"one_percent_low_fps": count * 1000.0 / slow_total, "p95_ms": times[int(times.size() * 0.95)],
		"p99_ms": times[int(times.size() * 0.99)], "frames_over_33ms": long_frames,
		"frames_over_budget": missed_target, "frames_over_1_5x_budget": slow_frames,
		"render_cpu_p95_ms": render_cpu[int(render_cpu.size() * 0.95)],
		"render_gpu_p95_ms": render_gpu[int(render_gpu.size() * 0.95)],
		"visible_draw_calls_peak": peak_draw_calls,
		"floor_upload_bytes": int(scene._floor.grid.bytes_uploaded_total) - upload_start,
		"network_payload_bytes": int(scene._net.state_bytes_sent + scene._net.splat_bytes_sent) - net_start,
		"max_ms": times.back(), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})


func sample_spray_pair() -> void:
	# Compare the first and next press against the same patch of starting floor.
	var shooter = scene._local
	var at: Vector3 = shooter.player.global_position
	scene.debug_aim_at(at - shooter.player.global_basis.z * 2.5 - Vector3.UP * at.y)
	for label in ["first_spray", "repeated_spray"]:
		shooter.sauce = 1.0
		await sample(label, 2.0, scene.debug_set_input.bind(Vector2.ZERO, false, true))
		scene.debug_set_input(Vector2.ZERO, false, false)
		await create_timer(1.5).timeout


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered performance test requires a display")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	if OS.get_cmdline_user_args().has("--1080p"):
		resolution = Vector2i(1920, 1080)
	root.size = resolution
	root.content_scale_size = resolution
	Engine.max_fps = int(ProjectSettings.get_setting("application/run/max_fps"))
	if Engine.max_fps <= 0:
		push_error("The game needs a frame cap to evaluate its frame budget")
		quit(2)
		return
	frame_budget_ms = 1000.0 / float(Engine.max_fps)
	viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	scene = load(StageRegistry.scene_path("stage_2")).instantiate()
	scene.staged_loading = true
	root.add_child(scene)
	while not scene.load_complete:
		await process_frame
	var warmup_started := Time.get_ticks_usec()
	await scene.warm_stage_materials()
	warmup_ms = (Time.get_ticks_usec() - warmup_started) / 1000.0
	scene.set_gameplay_input_enabled(true)
	scene._healing_rng.seed = 20261117
	scene._sauce_parts._rng.seed = 20261117
	scene.debug_profile_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(3.0).timeout
	scene.play_support.diagnostics_enabled = true
	await sample("start_idle", 8.0)
	var cold_look := OS.get_cmdline_user_args().has("--cold-look")
	if cold_look:
		var start_yaw: float = scene._local.aim_yaw
		await sample("first_look_sweep", 4.0, Callable(), true)
		scene._local.aim_yaw = start_yaw
		await process_frame
	await sample_spray_pair()
	var enemy: MayoEnemy
	for candidate in scene._enemies:
		if candidate.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
			enemy = candidate
			break
	var at: Vector3 = enemy.global_position + Vector3(0, 0, 5)
	at.y = 1.28
	scene._local.player.finish_respawn(at)
	scene.debug_aim_at(enemy.global_position)
	await sample("alley_spraying", 10.0, scene.debug_set_input.bind(Vector2.ZERO, false, true))
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
		await sample("synthetic_chain_burst", 10.0, func():
			bomb.take_sauce_hit(Vector3.INF, bomb.max_health + 1.0)
			scene._finish_tomato_kill(bomb, scene._local))
	scene.play_support.save_diagnostics("res://.godot/tomatina_capped_hitches.json")
	var file := FileAccess.open("res://.godot/tomatina_capped_performance.json", FileAccess.WRITE)
	if file == null:
		push_error("Could not write the performance report")
		quit(1)
		return
	var cache_errors := cache_logger.snapshot()
	for hitch in wall_hitches:
		hitch["shader_cache_error_count"] = cache_errors.filter(func(error):
			return error.timestamp_us >= hitch.start_us and error.timestamp_us < hitch.end_us).size()
	file.store_string(JSON.stringify({"scope": "single rendered world, %d sampled seconds" % (36 if cold_look else 32),
		"render_timings": "latest completed viewport draw, GPU timestamps can lag the wall frame",
		"stage_material_warmup_ms": warmup_ms,
		"shader_cache_errors": cache_errors,
		"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [resolution.x, resolution.y], "fps_cap": Engine.max_fps, "frame_budget_ms": frame_budget_ms,
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "results": results, "wall_hitches": wall_hitches}, "\t"))
	print("TOMATINA_APPROVED_PERFORMANCE_DONE")
	scene.queue_free()
	await process_frame
	quit()
