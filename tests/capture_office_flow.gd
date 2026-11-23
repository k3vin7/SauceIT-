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
	await _shot("2_party_panel.png")
	app._close_party_panel()
	app._start_solo()
	await _shot("3_character_select.png")
	app._character_layer._select(2)
	app._character_layer._confirm_pick()
	var office := app.current_space as OfficeLobby
	await _shot("4_office.png")
	office._yaw = PI * 0.5
	office._apply_local_look()
	await _shot("5_office_locker_side.png")
	office.open_map()
	await _shot("6_map.png")
	office.pick_stage("stage_2")
	office.request_start()
	await _until(func(): return app._arrival != null and is_instance_valid(app._arrival) and app._arrival.active)
	await _shot("7_arrival_start.png")
	await _until(func(): return app._arrival == null or not is_instance_valid(app._arrival) \
		or app._arrival._clock > StageArrival.DURATION * 0.55)
	await _shot("8_arrival_middle.png")
	await _until(func(): return app._arrival == null or not is_instance_valid(app._arrival) 		or app._arrival._clock > StageArrival.DURATION * 0.85)
	await _shot("8b_arrival_late.png")
	await _until(func(): return app.flow == SauceApp.Flow.STAGE)
	await _shot("9_play.png")
	DirAccess.remove_absolute(app.save_path_override)
	quit(0)
