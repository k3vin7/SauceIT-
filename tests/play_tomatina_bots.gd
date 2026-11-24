extends SceneTree
## Interactive/autoplay observation run; does not collect FPS or performance metrics.
var world
var team
var limit := 120.0
var _finished := false
var _heartbeat := 20.0
func _initialize() -> void:
	MayoTutorial.disabled = true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			limit = clampf(argument.trim_prefix("--seconds=").to_float(), 10.0, 600.0)
	call_deferred("run")
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	world = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(world)
	team = preload("res://scripts/player_bot_team.gd").new()
	world.add_child(team)
	team.configure(world, true)
	world.stage_cleared.connect(finish)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	create_timer(limit).timeout.connect(finish)
	print("BOT_PLAY_STARTED seconds=", limit)
func _process(delta: float) -> bool:
	if _finished or not is_instance_valid(team):
		return false
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_heartbeat = 20.0
		var alive := 0
		for shooter in world._shooters.values():
			if shooter.player.state != MayoPlayer.State.DEAD:
				alive += 1
		print("BOT_PROGRESS seconds=", roundi(team.elapsed), " route=", team.route_index, " standing=", alive)
	return false
func finish() -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = team.report()
	var file := FileAccess.open("res://reports/tomatina_bot_play.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/tomatina_bot_play.png")
	print("BOT_PLAY_DONE route=", report.route_index, "/", report.route_points, " cleared=", report.cleared)
	world.queue_free()
	await process_frame
	quit()
