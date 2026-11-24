extends SceneTree

# 새 시작 흐름의 화면을 정적 캡처한다(성능 측정 아님). 창을 띄워 실행:
#   godot --path . --resolution 1280x720 --script res://tests/capture_office_flow.gd -- <출력 폴더>

var out_dir := "res://tmp"


func _initialize() -> void:
	MayoTutorial.disabled = true
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	call_deferred("_run")


func _shot(file_name: String) -> void:
	for _frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file_name))
	print("saved ", file_name)


func _until(condition: Callable, frames := 6000) -> bool:
	for _index in frames:
		if condition.call():
			return true
		await process_frame
	return false


func _run() -> void:
	var app := (load("res://app.tscn") as PackedScene).instantiate() as SauceApp
	app.save_path_override = "res://tmp/sauce_it_capture_%d.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	await _shot("1_title.png")
	app._open_party_panel()
	await _shot("6_party_panel.png")
	app._close_party_panel()
	app._start_solo()
	await _shot("2_character_select.png")
	app._character_layer._select(2)
	app._character_layer._confirm_pick()
	var office := app.current_space as OfficeLobby
	await _shot("3_office.png")
	office._yaw = PI * 0.5
	office._apply_local_look()
	await _shot("4_office_locker_side.png")
	office.open_map()
	await _shot("5_map.png")
	office.pick_stage("stage_2")
	office.request_start()
	# 스테이지 2는 자체 인트로(트럭 도착 컷신)를 튼다. 조금 보다가 건너뛴다.
	await _until(func(): return app.flow == SauceApp.Flow.STAGE and app._stage_intro_active())
	print("intro active=", app._stage_intro_active(), " input=", app.current_space.gameplay_input_enabled())
	await _shot("7_intro_start.png")
	await _until(func(): return app.current_space._tomatina_intro.elapsed > 8.0)
	await _shot("8_intro_middle.png")
	app._skip_stage_intro()
	await process_frame
	print("after skip: intro active=", app._stage_intro_active(), " input=",
		app.current_space.gameplay_input_enabled(), " hint=", app._intro_hint_layer != null)
	await _shot("9_play.png")
	DirAccess.remove_absolute(app.save_path_override)
	quit(0)
