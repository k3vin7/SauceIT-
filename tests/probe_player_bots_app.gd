extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("BOT_APP_TIMEOUT"); quit(2))
	var app = load("res://app.tscn").instantiate()
	app.save_path_override = "res://reports/runtime_home/bot_app_probe.cfg"
	root.add_child(app)
	app._start_solo()
	app._on_character_chosen(2)
	var office := app.current_space as OfficeLobby
	office.open_map()
	for button in office._map_modes.get_children():
		if (button as Button).text == "봇 3명과 토마티나 연습":
			(button as Button).pressed.emit()
	await physics_frame
	assert(app.flow == app.Flow.STAGE)
	assert(app.current_space.party_size() == 4)
	assert(app.session.selected_stage == "stage_2")
	assert(not app.session.lobby_flow)
	assert(is_instance_valid(app.bot_team) and not app.bot_team.autoplay)
	var world = app.current_space
	assert(world._local.character_index == 2)
	var intro = world._tomatina_intro
	assert(world.tomatina_intro_active() and not world.gameplay_input_enabled())
	assert(intro.passengers.get_child_count() == 4 and not world._hud_layer.visible)
	for slot in range(4):
		var spawn := TomatinaMap.spawn_position(slot)
		assert(TomatinaMap.FESTIVAL_ENTRANCE.has_point(StreetMap.cell_at(spawn)))
		assert(world._nav.is_walkable(StreetMap.cell_at(spawn)))
		assert(not world._nav.route(spawn, TomatinaMap.at_cell(Vector2(29.2, 222.5))).is_empty())
	var toss = intro.tosses.back()
	intro._process(toss.hit_time - intro.elapsed + .11)
	assert(toss.receiver.animation.current_animation == &"TomatoHit")
	assert(toss.smear.visible and toss.splash[0].visible and not toss.thrower.tomato.visible)
	intro._process(intro.PANIC_CHASE - intro.elapsed + .93)
	assert(intro.runner.animation.current_animation == &"Panic")
	assert(intro.grade.visible and intro.truck_monster.visible and not intro.hose_cloud.visible)
	intro._process(intro.LATCH_TIME - intro.elapsed + .01)
	assert(intro.blackout.color.a >= .99 and intro.effects.stream == intro.LATCH)
	intro._process(intro.FIRST_PERSON - intro.elapsed + .1)
	assert(world._camera.current and world._first_person and not world.gameplay_input_enabled())
	assert(is_equal_approx(world._tomatina_entrance.left_door.rotation.y, -world._tomatina_entrance.OPEN_ANGLE))
	intro._process(intro.DURATION - intro.elapsed + .1)
	assert(not world.tomatina_intro_active() and world.gameplay_input_enabled() and world._hud_layer.visible)
	app._open_pause()
	assert(paused)
	app._close_pause()
	assert(not paused and app.current_space._input_enabled)
	app._on_stage_cleared()
	assert(app.flow == app.Flow.RESULT and is_instance_valid(app._result_layer))
	var tint := app._result_layer.find_child("ResultBackdropTint", true, false) as ColorRect
	var panel := app._result_layer.find_child("ResultPanel", true, false) as PanelContainer
	assert(tint != null and tint.color.a < 0.3)
	assert(panel != null and panel.get_parent() is HBoxContainer \
		and panel.get_parent().alignment == BoxContainer.ALIGNMENT_END)
	app._retry_current_stage()
	assert(app.flow == app.Flow.STAGE and app.current_space.party_size() == 4)
	assert(app.current_space.tomatina_intro_active())
	app._show_title()
	assert(app.flow == app.Flow.TITLE and app.bot_team == null)
	app.queue_free()
	await process_frame
	print("PLAYER_BOTS_APP_OK")
	quit()
