extends "res://tests/probe_lobby_flow.gd"

# A 3- or 4-player Tomatina session on localhost: every peer goes through the
# truck lobby, the shared loading barrier and into stage 2. Each guest then
# walks its own way, and every screen must agree on where everybody is and on
# their health and sauce. The party scaling the host applies is checked too.
#
#   godot --headless --path . --script res://tests/probe_tomatina_party_sync.gd -- --players=4
#
# A short functional check, not a performance or soak test: it measures no FPS.

const SYNC_PORT := 24851
const POSITION_TOLERANCE := 1.0
const MOVE_FRAMES := 40
const SETTLE_FRAMES := 30

var players := 3
var sessions: Array[MayoNet] = []
var worlds := {}
var authorized := {}


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
	worlds[session] = world
	session.report_world_loaded(transition)


func _physics(frames: int) -> void:
	for _index in frames:
		await physics_frame


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--players="):
			players = clampi(argument.trim_prefix("--players=").to_int(), 2, 4)
	create_timer(240.0).timeout.connect(func(): push_error("PARTY_SYNC_TIMEOUT"); quit(2))
	MayoTutorial.disabled = true
	for index in players:
		var session := _make_peer("Peer%dView" % index)
		session.get_viewport().own_world_3d = true
		session.transition_requested.connect(func(stage, transition): _mount(session, stage, transition))
		session.play_authorized.connect(func(_transition):
			worlds[session].set_gameplay_input_enabled(true)
			authorized[session] = true)
		sessions.append(session)
	host = sessions[0]
	await process_frame

	_check(host.begin_host_room(SYNC_PORT, "SYNC%d" % players, false, "stage_2"), "host could not open the room")
	for index in range(1, players):
		_check(sessions[index].begin_join_room("127.0.0.1", SYNC_PORT, "SYNC%d" % players),
			"guest %d could not begin joining" % index)
		_check(await _until(func(): return sessions[index].phase() == MayoNet.SessionPhase.TRUCK),
			"guest %d never reached the truck" % index)
	_check(await _until(func(): return host.seat_assignments().size() == players and host.all_lobby_ready()),
		"the %d-player roster did not converge" % players)
	_check(host.request_stage_start(), "host could not start Tomatina")
	if not await _until(func(): return authorized.size() == players, 7200):
		_check(false, "only %d of %d peers were authorized to play" % [authorized.size(), players])
		_finish()
		return
	await _physics(10)

	# --- the roster every screen holds ---
	var host_world = worlds[host]
	for session in sessions:
		var world = worlds[session]
		_check(world.shooter_ids().size() == players,
			"peer %d sees %d players, not %d" % [session.local_id(), world.shooter_ids().size(), players])
		_check(world.party_size() == players, "peer %d party_size is %d" % [session.local_id(), world.party_size()])

	# --- the party scaling the host applies ---
	_check(host_world.active_grunt_limit() == host_world.tomatina_active_grunt_cap + 4 * (players - 1),
		"active grunt limit is %d for %d players" % [host_world.active_grunt_limit(), players])
	_check(host_world.minion_spawn_count(host_world.HOSE_WAVE_COUNT)
		== int(round(host_world.HOSE_WAVE_COUNT * (1.0 + 0.35 * (players - 1)))),
		"hose counterattack is not scaled for %d players" % players)
	var heavies := 0
	var unscaled := 0
	for enemy in host_world._enemies:
		if enemy.is_alive() and enemy.kind in [MayoEnemy.EnemyKind.TOMATO_BRUTE, MayoEnemy.EnemyKind.CAPRESE_CRAWLER]:
			heavies += 1
			if not is_equal_approx(enemy.max_health, host_world.heavy_health_for(enemy.solo_health, players)):
				unscaled += 1
	_check(heavies > 0 and unscaled == 0, "%d of %d heavies were not scaled to %d players" % [unscaled, heavies, players])

	# --- every guest walks its own way, then every screen must agree ---
	var directions := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var starts := {}
	for index in range(1, players):
		var world = worlds[sessions[index]]
		starts[index] = world._local.player.global_position
		world.debug_set_input(directions[index - 1], false, false)
	await _physics(MOVE_FRAMES)
	for index in range(1, players):
		worlds[sessions[index]].debug_set_input(Vector2.ZERO, false, false)
	await _physics(SETTLE_FRAMES)
	for index in range(1, players):
		var session := sessions[index]
		var moved: float = worlds[session]._local.player.global_position.distance_to(starts[index])
		_check(moved > 0.5, "guest %d did not move (%.2f m)" % [index, moved])
		# The same walk seen from the host, so a zero gap below means agreement
		# and not everyone standing at the spawn.
		var at_host: float = host_world.shooter_for(session.local_id()).player.global_position.distance_to(starts[index])
		_check(at_host > 0.5, "the host never saw guest %d move (%.2f m)" % [index, at_host])
		print("guest %d moved %.2f m locally, %.2f m at the host" % [index, moved, at_host])

	var worst := 0.0
	for peer_id in host_world.shooter_ids():
		var truth = host_world.shooter_for(peer_id)
		for session in sessions:
			if session == host:
				continue
			var seen = worlds[session].shooter_for(peer_id)
			if seen == null:
				_check(false, "peer %d has no avatar for %d" % [session.local_id(), peer_id])
				continue
			var gap: float = seen.player.global_position.distance_to(truth.player.global_position)
			worst = maxf(worst, gap)
			_check(gap < POSITION_TOLERANCE,
				"peer %d sees %d %.2f m from the host" % [session.local_id(), peer_id, gap])
			_check(absf(seen.player.health - truth.player.health) < 0.01,
				"peer %d sees %d at %.1f health, host %.1f" % [session.local_id(), peer_id, seen.player.health, truth.player.health])
			_check(absf(seen.sauce - truth.sauce) < 0.02,
				"peer %d sees %d with %.3f sauce, host %.3f" % [session.local_id(), peer_id, seen.sauce, truth.sauce])
	print("party sync: players=%d worst position gap=%.3f m" % [players, worst])
	_finish()


func _finish() -> void:
	for session in sessions:
		session.leave()
	if failures.is_empty():
		print("TOMATINA_PARTY_SYNC_OK players=%d" % players)
	quit(0 if failures.is_empty() else 1)
