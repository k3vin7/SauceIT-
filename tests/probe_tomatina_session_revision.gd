extends "res://tests/probe_lobby_flow.gd"
var late_world
var host_world
var loaded := false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures.append(message)

func _mount(session: MayoNet, stage_id: String, transition: int) -> void:
	var world = load(StageRegistry.scene_path(stage_id)).instantiate()
	world.name = "World"
	world.external_net = session
	session.get_parent().add_child(world)
	session.attach_play_world(world)
	if session == host:
		host_world = world
	else:
		late_world = world
	session.report_world_loaded(transition)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("SESSION_REVISION_TIMEOUT"); quit(2))
	MayoTutorial.disabled = true
	host = _make_peer("HostView")
	guest = _make_peer("GuestView")
	host.get_viewport().own_world_3d = true
	guest.get_viewport().own_world_3d = true
	host.transition_requested.connect(func(stage, transition): _mount(host, stage, transition))
	guest.transition_requested.connect(func(stage, transition): _mount(guest, stage, transition))
	host.play_authorized.connect(func(_transition): host_world.set_gameplay_input_enabled(true))
	guest.play_authorized.connect(func(_transition): late_world.set_gameplay_input_enabled(true); loaded = true)
	await process_frame
	_check(host.begin_host_room(24839, "JOIN2", false, "stage_2"), "host failed")
	# The door is open in the office and nowhere else: the guest joins before
	# the start, and both pick before anybody sets out.
	_check(guest.begin_join_room("127.0.0.1", 24839, "JOIN2"), "connection failed")
	_check(await _until(func(): return host.seat_assignments().size() == 2 and host.all_lobby_ready()),
		"guest never reached the lobby")
	host.choose_character(0)
	guest.choose_character(0)
	guest.choose_character(1)
	_check(await _until(func(): return host.all_characters_chosen()), "picks never reached the host")
	_check(host.character_of(guest.local_id()) == 1, "the host gave two players one character")
	_check(host.request_stage_start(), "start failed")
	_check(await _until(func(): return loaded and host.phase() == MayoNet.SessionPhase.STAGE), "stage never started")
	if late_world == null:
		quit(1)
		return
	_check(host_world.shooter_ids().size() == 2, "late avatar missing at host")
	_check(late_world != null and late_world.shooter_ids().size() == 2, "late world roster incorrect")
	for index in 12:
		await physics_frame
	_check(host_world.grid_md5() == late_world.grid_md5(), "late join contamination snapshot differs")
	_check(late_world._local.player.predict_local, "local prediction not enabled")
	_check(late_world._local.player.global_position.distance_to(host_world.shooter_for(guest.local_id()).player.global_position) < 2.0, "late player spawned away from checkpoint")
	var local: MayoPlayer = late_world._local.player
	var before := local.global_position
	late_world.debug_set_input(Vector2(1, 0), false, false)
	for index in 15:
		await physics_frame
	_check(local.global_position.distance_to(before) > 0.25, "predicted movement did not respond")
	print("prediction gap=", local.global_position.distance_to(host_world.shooter_for(guest.local_id()).player.global_position),
		" client=", local.global_position, " server=", host_world.shooter_for(guest.local_id()).player.global_position,
		" seq=", local.prediction_sequence, " ack=", local._last_ack, " history=", local._prediction_history.size())
	_check(local.global_position.distance_to(host_world.shooter_for(guest.local_id()).player.global_position) < 1.5, "movement reconciliation diverged")
	late_world.debug_set_input(Vector2.ZERO, false, false)
	late_world._confirmed_contact_until = 0
	host.send_contact_confirmation(guest.local_id())
	for index in 4:
		await physics_frame
	_check(late_world._confirmed_contact_until > 0, "server hit confirmation never arrived")
	host.finish_stage({"title": "test", "statistics": host_world.mission_report()})
	_check(await _until(func(): return guest.phase() == MayoNet.SessionPhase.RESULT), "result did not arrive")
	host_world.queue_free()
	late_world.queue_free()
	await process_frame
	loaded = false
	_check(host.replay_stage(), "fast replay rejected")
	_check(await _until(func(): return loaded and host.phase() == MayoNet.SessionPhase.STAGE), "fast replay failed loaded barrier")
	_check(host_world.shooter_ids().size() == 2 and late_world.shooter_ids().size() == 2, "replay lost roster")
	host.leave()
	guest.leave()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TOMATINA_SESSION_REVISION_OK")
	quit(0 if failures.is_empty() else 1)
