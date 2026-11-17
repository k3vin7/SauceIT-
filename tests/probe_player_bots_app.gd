extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("BOT_APP_TIMEOUT"); quit(2))
	var app = load("res://app.tscn").instantiate()
	app.save_path_override = "res://reports/runtime_home/bot_app_probe.cfg"
	root.add_child(app)
	app._show_bot_practice()
	await physics_frame
	assert(app.flow == app.Flow.STAGE)
	assert(app.current_space.party_size() == 4)
	assert(app.session.selected_stage == "stage_2")
	assert(is_instance_valid(app.bot_team) and not app.bot_team.autoplay)
	app._open_pause()
	assert(paused)
	app._close_pause()
	assert(not paused and app.current_space._input_enabled)
	app._on_stage_cleared()
	assert(app.flow == app.Flow.RESULT and is_instance_valid(app._result_layer))
	app._retry_current_stage()
	assert(app.flow == app.Flow.STAGE and app.current_space.party_size() == 4)
	app._show_title()
	assert(app.flow == app.Flow.TITLE and app.bot_team == null)
	app.queue_free()
	await process_frame
	print("PLAYER_BOTS_APP_OK")
	quit()
