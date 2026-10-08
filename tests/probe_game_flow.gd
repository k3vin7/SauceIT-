extends SceneTree

var failures: Array[String] = []
var test_save := "/tmp/sauce_it_flow_test_%d.cfg" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
		await physics_frame


func _run() -> void:
	# A dedicated path proves tests never touch the real user:// progress file.
	var store := SauceSaveStore.new(test_save)
	store.load_data()
	_check(not store.tutorial_completed, "a missing save did not default to tutorial incomplete")
	_check(is_equal_approx(store.master_volume, 0.8), "default volume changed")
	_check(store.save_options(0.37, 0.14) == OK, "test options could not be saved")
	var reloaded := SauceSaveStore.new(test_save)
	reloaded.load_data()
	_check(not reloaded.tutorial_completed, "saving options incorrectly completed the tutorial")
	_check(is_equal_approx(reloaded.master_volume, 0.37), "volume did not persist")
	_check(is_equal_approx(reloaded.mouse_sensitivity, 0.14), "sensitivity did not persist")
	_check(reloaded.save_progress_complete() == OK, "tutorial completion could not be saved")
	var completed := SauceSaveStore.new(test_save)
	completed.load_data()
	_check(completed.tutorial_completed, "tutorial completion did not persist")

	_check(StageRegistry.available_ids() == ["stage_1"], "unimplemented stages are exposed")
	_check(StageRegistry.scene_path("stage_1") == "res://stage_1_festival.tscn",
		"stage 1 registry path is wrong")

	var tutorial = load("res://tutorial_world.tscn").instantiate()
	root.add_child(tutorial)
	await _frames(2)
	_check(tutorial.map_kind == tutorial.MapKind.TUTORIAL_RECTANGLE,
		"tutorial scene did not select the rectangle map")
	_check(tutorial.tutorial() != null, "tutorial scene did not build progression")
	_check(tutorial.has_node("TutorialCourse"), "tutorial course was not built")
	var course: Node = tutorial.get_node_or_null("TutorialCourse")
	for marker in ["PlayerStart", "SaucePickup", "FirstFight", "EscapeGap",
			"EscapeTarget", "Refill", "FinalFight"]:
		_check(course != null and course.has_node(marker), "missing tutorial marker %s" % marker)
	_check(tutorial.refill_stations().size() == 2, "tutorial does not have pickup and refill stations")
	_check(tutorial.spawn_position_for(0).z > TutorialCourse.CENTRE_Z,
		"tutorial spawn is not before the escape obstacle")
	_check(TutorialCourse.can_stand(Vector3(0.0, 0.0, TutorialCourse.CENTRE_Z)),
		"player gap is not walkable")
	_check(not TutorialCourse.can_stand(Vector3(5.0, 0.0, TutorialCourse.CENTRE_Z)),
		"escape barrier is not configured as blocked")
	tutorial.free()
	await process_frame

	var stage = load("res://stage_1_festival.tscn").instantiate()
	root.add_child(stage)
	await _frames(2)
	_check(not stage.tutorial_enabled and stage.tutorial() == null,
		"festival stage still runs tutorial progression")
	_check(stage.stage_mode, "festival scene is not registered as a combat stage")
	_check(stage.enemy_count() > 0, "festival stage has no target enemies")
	_check(stage._local != null and stage._local.sauce > 0.99,
		"festival stage inherited the tutorial's empty bottle")
	_check(stage._stage_roster_initialized, "stage clear armed before/without enemy initialization")
	stage.free()
	await process_frame

	var hub := load("res://recruitment_map.tscn").instantiate() as RecruitmentMap
	root.add_child(hub)
	await _frames(2)
	hub._player.global_position = Vector3(0.0, 1.28, -5.3)
	hub._yaw = 0.0
	hub._pitch = 0.0
	hub._player.rotation.y = 0.0
	hub._pivot.rotation.x = 0.0
	await physics_frame
	_check(hub.can_use_screen(), "office screen distance/look interaction failed")
	hub.set_input_locked(true)
	_check(hub.input_locked, "office UI did not lock movement/look/fire input")
	hub.set_input_locked(false)
	_check(not hub.input_locked, "office controls were not restored after UI close")
	hub.free()
	await process_frame

	# Seat allocation keeps existing seats and fills the lowest released one.
	var net := MayoNet.new()
	root.add_child(net)
	net._slots = {1: 0, 20: 1, 30: 3}
	_check(net._free_slot() == 2, "released lobby seat was not reused")
	net.lobby_flow = true
	net.session_phase = MayoNet.SessionPhase.TRUCK
	net._lobby_ready = {1: true, 20: true, 30: true}
	_check(net.all_lobby_ready(), "ready barrier rejected an initialized roster")
	net._lobby_ready.erase(20)
	_check(not net.all_lobby_ready(), "ready barrier allowed an uninitialized participant")
	_check(not net.request_stage_start(), "offline/client context was allowed to start a room")
	net.free()

	var app_scene := load("res://app.tscn") as PackedScene
	_check(app_scene != null, "app entry scene does not load")
	if app_scene != null:
		var app_save := "/tmp/sauce_it_app_test_%d.cfg" % Time.get_ticks_usec()
		var app = app_scene.instantiate()
		app.save_path_override = app_save
		root.add_child(app)
		await _frames(2)
		_check(app.flow == SauceApp.Flow.TITLE, "app did not begin at title")
		_check(app.get_node_or_null("TitleUI") != null, "SAUCE IT title UI was not created")
		app._start_game()
		await _frames(2)
		_check(app.flow == SauceApp.Flow.TUTORIAL,
			"fresh app profile did not route to the standalone tutorial")
		_check(app.current_space != null and app.current_space.map_kind \
			== app.current_space.MapKind.TUTORIAL_RECTANGLE,
			"fresh app profile routed to the wrong map")
		var completed_world: Node = app.current_space
		var completion_saw_world := [false]
		completed_world.tutorial_completed.connect(func() -> void:
			# Connected after the app handler, so this observes the exact state the
			# rest of the emitting physics tick inherits from the scene transition.
			completion_saw_world[0] = completed_world.is_inside_tree()
		)
		completed_world.tutorial().stage = MayoTutorial.Stage.COMPLETE
		await _frames(2)
		_check(completion_saw_world[0],
			"tutorial world was detached in the middle of its completion callback")
		_check(app.flow == SauceApp.Flow.RECRUITMENT,
			"tutorial completion did not route to recruitment")
		var routed_save := SauceSaveStore.new(app_save)
		routed_save.load_data()
		_check(routed_save.tutorial_completed,
			"app route did not persist actual tutorial completion")
		app.free()
		await process_frame
		var returning_app = app_scene.instantiate()
		returning_app.save_path_override = app_save
		root.add_child(returning_app)
		await _frames(2)
		returning_app._start_game()
		await _frames(2)
		_check(returning_app.flow == SauceApp.Flow.RECRUITMENT,
			"returning completed profile did not skip the tutorial")
		returning_app.free()
		DirAccess.remove_absolute(app_save)

	DirAccess.remove_absolute(test_save)
	if failures.is_empty():
		print("SAUCE_GAME_FLOW_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
