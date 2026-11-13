extends SceneTree
var report := {}
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func sample(scene, label: String, firing: bool) -> Dictionary:
	var times: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	var down_frames := 0
	scene.debug_set_input(Vector2(0.0, -1.0) if firing else Vector2.ZERO, firing, firing)
	while Time.get_ticks_usec() - start < 6000000:
		if firing:
			var enemy = scene.enemy_at(0)
			if is_instance_valid(enemy) and enemy.is_alive():
				scene.debug_aim_at(enemy.global_position)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		if scene._local.player.is_incapacitated():
			down_frames += 1
	scene.debug_set_input(Vector2.ZERO, false, false)
	var total := 0.0
	for value in times:
		total += value
	times.sort()
	var slow_count := maxi(1, ceili(times.size() * 0.01))
	var slow_total := 0.0
	for index in range(times.size() - slow_count, times.size()):
		slow_total += times[index]
	var result := {"scenario": label, "frames": times.size(), "average_fps": times.size() * 1000.0 / total, "one_percent_low_fps": slow_count * 1000.0 / slow_total, "p95_ms": times[int(times.size() * 0.95)], "max_ms": times.back(), "incapacitated_frames": down_frames}
	print(JSON.stringify(result))
	return result
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	Engine.max_fps = 0
	report = {"resolution": [1280,720], "vsync": DisplayServer.window_get_vsync_mode(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "results": []}
	for path in ["res://stage_1_festival.tscn", "res://stage_2_tomatina.tscn"]:
		var scene = load(path).instantiate()
		root.add_child(scene)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 3000:
			await process_frame
		report.results.append(await sample(scene, path + " idle", false))
		report.results.append(await sample(scene, path + " moving_and_spraying", true))
		scene.queue_free()
		await process_frame
	var file := FileAccess.open("res://reports/fps_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FPS_BENCHMARK_DONE")
	quit()
