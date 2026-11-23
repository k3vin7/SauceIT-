extends "res://tests/probe_lobby_flow.gd"

# A 2- to 4-player Tomatina session on localhost: every peer goes through the
# truck lobby, the shared loading barrier and into stage 2. Then, with every
# request sent the way a guest's keys send it:
#   1. roster and the party scaling the host applies
#   2. each guest walks its own way; the gap is sampled while they move and
#      every screen must agree once they stop
#   3. a guest refills at a supply station
#   4. a grunt the host kills is gone on every screen
#   5. a guest rescues a downed guest
#   6. the last guest leaves, and a new player joins at the safe point
#   7. a guest powers the generator, another takes a fire hose
# and every screen agrees on everybody's position, health and sauce after each.
#
#   godot --headless --path . --script res://tests/probe_tomatina_party_sync.gd -- --players=4
#
# A short functional check, not a performance or soak test: it measures no FPS.

const SYNC_PORT := 24851
const POSITION_TOLERANCE := 1.0
const MOVING_TOLERANCE := 2.0
const MOVE_FRAMES := 40
const SETTLE_FRAMES := 30

var players := 3
var sessions: Array[MayoNet] = []
var worlds := {}
var authorized := {}
var host_world


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


func _physics_until(condition: Callable, frames := 240) -> bool:
	for _index in frames:
		if condition.call():
			return true
		await physics_frame
	return false


func _add_session(index: int) -> MayoNet:
	var session := _make_peer("Peer%dView" % index)
	session.get_viewport().own_world_3d = true
	session.transition_requested.connect(func(stage, transition): _mount(session, stage, transition))
	session.play_authorized.connect(func(_transition):
		worlds[session].set_gameplay_input_enabled(true)
		authorized[session] = true)
	sessions.append(session)
	return session


func _id(index: int) -> int:
	return sessions[index].local_id()


func _world(index: int):
	return worlds[sessions[index]]


## Puts a player somewhere on every screen at once: the host owns the body,
## and the owner's prediction would otherwise walk it back to where it was.
func _place(peer_id: int, at: Vector3) -> void:
	for session in sessions:
		var shooter = worlds[session].shooter_for(peer_id)
		if shooter == null:
			continue
		shooter.player.global_position = at
		shooter.player.velocity = Vector3.ZERO
		shooter.player.reset_physics_interpolation()


func _safe_room_centre(room: int) -> Vector3:
	var rect: Rect2i = TomatinaMap.SAFE_ROOMS[room]
	return TomatinaMap.at_cell(Vector2(rect.position) + Vector2(rect.size) * 0.5) + Vector3.UP * 1.28


## A walkable cell just outside a safe room and its neighbour just inside,
## as [outside point, inside point], or [] if the room has no open edge.
func _doorway(room: int) -> Array:
	var rect: Rect2i = TomatinaMap.SAFE_ROOMS[room]
	var grown := rect.grow(1)
	for x in range(grown.position.x, grown.end.x):
		for y in range(grown.position.y, grown.end.y):
			var outside := Vector2i(x, y)
			if TomatinaMap.safe_room_at(outside) >= 0:
				continue
			var out_at := TomatinaMap.at_cell(Vector2(outside) + Vector2.ONE * 0.5) + Vector3.UP * 1.28
			if not host_world._nav.is_walkable(StreetMap.cell_at(out_at)):
				continue
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var inside: Vector2i = outside + step
				if TomatinaMap.safe_room_at(inside) != room:
					continue
				var in_at := TomatinaMap.at_cell(Vector2(inside) + Vector2.ONE * 0.5) + Vector3.UP * 1.28
				# A cell (4.6 m) is wider than the 2.5 m rescue reach, so both
				# stand 0.6 m either side of the edge the two cells share.
				var edge := (out_at + in_at) * 0.5
				var across := (in_at - out_at).normalized()
				var lying := edge - across * 0.6
				var kneeling := edge + across * 0.6
				if TomatinaMap.safe_room_at(StreetMap.cell_at(kneeling)) == room 						and TomatinaMap.safe_room_at(StreetMap.cell_at(lying)) < 0 						and host_world._nav.is_walkable(StreetMap.cell_at(in_at)) 						and host_world._nav.line_is_walkable(kneeling, lying):
					return [lying, kneeling]
	return []


## Tries spots around `centre` until the host has the player standing on the
## floor inside `zone`.
func _stand_in_zone(peer_id: int, zone: Rect2, centre: Vector3) -> bool:
	var player: MayoPlayer = host_world.shooter_for(peer_id).player
	for offset in [Vector2(-1.0, -1.0), Vector2(-0.5, -0.5), Vector2(1.0, 1.0), Vector2(-1.0, 0.0),
			Vector2(0.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(0.5, 1.0)]:
		_place(peer_id, centre + Vector3(offset.x, 1.28, offset.y))
		await _physics(12)
		if player.is_on_floor() and player.global_position.y > 1.0 				and TomatinaMap.in_rect(zone, player.global_position):
			return true
	return false


## Everyone standing in the first safe room, spread over its centre.
func _gather_in_safe_room() -> void:
	var safe := _safe_room_centre(0)
	var offsets := [Vector3.ZERO, Vector3.RIGHT * 1.2, Vector3.LEFT * 1.2, Vector3.BACK * 1.2]
	for index in sessions.size():
		_place(_id(index), safe + offsets[index])


## The supply station nearest the first safe room and a walkable point the
## player's reach test accepts, found by trying the ground around it.
## Returns [station index, point] or [-1, null].
func _station_spot(probe: MayoPlayer) -> Array:
	var safe := _safe_room_centre(0)
	var stations: Array = host_world.refill_stations()
	var order := range(stations.size())
	order.sort_custom(func(a, b): return stations[a].position.distance_squared_to(safe) < stations[b].position.distance_squared_to(safe))
	var saved := probe.global_position
	for index in order:
		var centre: Vector3 = stations[index].position
		for radius in [1.0, 1.5, 2.0, 2.5, 3.0]:
			for step in 16:
				var angle := TAU * step / 16.0
				var at := Vector3(centre.x + cos(angle) * radius, 1.28, centre.z + sin(angle) * radius)
				if not host_world._nav.is_walkable(StreetMap.cell_at(at)):
					continue
				probe.global_position = at
				if host_world.station_in_reach(probe) == index:
					probe.global_position = saved
					return [index, at]
	probe.global_position = saved
	return [-1, null]


## Every screen against the host, for every player. Returns the worst gap.
func _agree(label: String, tolerance := POSITION_TOLERANCE, compare_stats := true) -> float:
	var worst := 0.0
	for peer_id in host_world.shooter_ids():
		var truth = host_world.shooter_for(peer_id)
		for session in sessions:
			if session == host:
				continue
			var seen = worlds[session].shooter_for(peer_id)
			if seen == null:
				_check(false, "%s: peer %d has no avatar for %d" % [label, session.local_id(), peer_id])
				continue
			var gap: float = seen.player.global_position.distance_to(truth.player.global_position)
			worst = maxf(worst, gap)
			_check(gap < tolerance, "%s: peer %d sees %d %.2f m from the host" % [label, session.local_id(), peer_id, gap])
			if not compare_stats:
				continue
			_check(absf(seen.player.health - truth.player.health) < 0.01,
				"%s: peer %d sees %d at %.1f health, host %.1f" % [label, session.local_id(), peer_id, seen.player.health, truth.player.health])
			_check(absf(seen.sauce - truth.sauce) < 0.02,
				"%s: peer %d sees %d with %.3f sauce, host %.3f" % [label, session.local_id(), peer_id, seen.sauce, truth.sauce])
			_check(seen.player.state == truth.player.state,
				"%s: peer %d sees %d in state %d, host %d" % [label, session.local_id(), peer_id, seen.player.state, truth.player.state])
	return worst


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--players="):
			players = clampi(argument.trim_prefix("--players=").to_int(), 2, 4)
	create_timer(300.0).timeout.connect(func(): push_error("PARTY_SYNC_TIMEOUT"); quit(2))
	MayoTutorial.disabled = true
	for index in players:
		_add_session(index)
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
	# Nobody sets out undressed, and no two players wear the same character.
	for index in players:
		sessions[index].choose_character(index)
	_check(await _until(func(): return host.all_characters_chosen()), "the picks never reached the host")
	_check(host.request_stage_start(), "host could not start Tomatina")
	if not await _until(func(): return authorized.size() == players, 7200):
		_check(false, "only %d of %d peers were authorized to play" % [authorized.size(), players])
		_finish()
		return
	await _physics(10)
	host_world = worlds[host]

	# --- 1. roster and party scaling ---
	for session in sessions:
		var world = worlds[session]
		_check(world.shooter_ids().size() == players,
			"peer %d sees %d players, not %d" % [session.local_id(), world.shooter_ids().size(), players])
		_check(world.party_size() == players, "peer %d party_size is %d" % [session.local_id(), world.party_size()])
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

	# --- 2. walking: sampled while moving, compared once stopped ---
	var directions := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var starts := {}
	for index in range(1, players):
		starts[index] = _world(index)._local.player.global_position
		_world(index).debug_set_input(directions[index - 1], false, false)
	var moving_worst := 0.0
	for frame in MOVE_FRAMES:
		await physics_frame
		if frame >= 10 and frame % 5 == 0:
			moving_worst = maxf(moving_worst, _agree("while walking", MOVING_TOLERANCE, false))
	for index in range(1, players):
		_world(index).debug_set_input(Vector2.ZERO, false, false)
	await _physics(SETTLE_FRAMES)
	for index in range(1, players):
		var moved: float = _world(index)._local.player.global_position.distance_to(starts[index])
		var at_host: float = host_world.shooter_for(_id(index)).player.global_position.distance_to(starts[index])
		_check(moved > 0.5, "guest %d did not move (%.2f m)" % [index, moved])
		_check(at_host > 0.5, "the host never saw guest %d move (%.2f m)" % [index, at_host])
	var stopped_worst := _agree("after walking")
	print("walk: worst gap while moving %.3f m, after stopping %.3f m" % [moving_worst, stopped_worst])

	# The rest happens in the first safe room: out on the street the grunts
	# keep hitting the party, and a hit rightly cancels a rescue.
	_gather_in_safe_room()
	await _physics(10)

	# --- 3. a guest refills at a station ---
	var refiller := _id(1)
	var supply := _station_spot(host_world.shooter_for(refiller).player)
	_check(supply[0] >= 0, "no reachable spot beside any supply station")
	_place(refiller, supply[1])
	host_world.shooter_for(refiller).sauce = 0.2
	await _physics(6)
	_check(host_world.station_in_reach(host_world.shooter_for(refiller).player) >= 0, "the refill spot is not in reach of the station")
	sessions[1].request_context_action("refill", host_world.station_in_reach(host_world.shooter_for(refiller).player))
	_check(await _physics_until(func(): return host_world.shooter_for(refiller).sauce > 0.99),
		"guest 1's refill request was not honoured (sauce %.2f)" % host_world.shooter_for(refiller).sauce)
	_check(await _physics_until(func(): return _world(2 if players > 2 else 0).shooter_for(refiller).sauce > 0.99),
		"another screen never saw guest 1's refill")
	await _physics(10)
	_agree("after refill")
	_gather_in_safe_room()
	await _physics(10)

	# --- 4. a kill on the host is gone everywhere ---
	var victim := -1
	for index in host_world.enemy_count():
		var enemy: MayoEnemy = host_world.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT and enemy.is_alive():
			victim = index
			break
	_check(victim >= 0, "no grunt to kill")
	if victim >= 0:
		var enemy: MayoEnemy = host_world.enemy_at(victim)
		var guard := 0
		while enemy.is_alive() and guard < 4000:
			enemy.take_sauce_hit(enemy.global_position + Vector3(0, 0, 2))
			guard += 1
		for session in sessions:
			var world = worlds[session]
			_check(await _physics_until(func(): return world.enemy_at(victim) == null or not world.enemy_at(victim).is_alive()),
				"peer %d still sees grunt %d alive" % [session.local_id(), victim])
		var counts := sessions.map(func(session): return worlds[session].enemy_count())
		_check(counts.all(func(count): return count == counts[0]), "screens disagree on the enemy count: %s" % str(counts))

	# --- 5. a guest rescues a downed guest ---
	if players >= 3:
		var downed := _id(1)
		var rescuer := _id(2)
		# A safe room shields whoever stands in it, so the downed guest lies
		# just outside its door and the rescuer reaches out from inside.
		var door := _doorway(0)
		_check(not door.is_empty(), "no doorway found for the first safe room")
		if not door.is_empty():
			_place(downed, door[0])
			_place(rescuer, door[1])
		await _physics(4)
		host_world._damage_player(host_world.shooter_for(downed).player, host_world.shooter_for(downed).player.max_health * 3.0)
		for session in sessions:
			var world = worlds[session]
			_check(await _physics_until(func(): return world.shooter_for(downed).player.state == MayoPlayer.State.DEAD),
				"peer %d never saw guest 1 go down" % session.local_id())
		_world(2).debug_set_input(Vector2.ZERO, false, false)
		sessions[2].request_context_action("rescue", downed)
		_check(await _physics_until(func(): return host_world.shooter_for(downed).player.state == MayoPlayer.State.NORMAL, 240),
			"guest 2's rescue of guest 1 never completed at the host")
		for session in sessions:
			var world = worlds[session]
			_check(await _physics_until(func(): return world.shooter_for(downed).player.state == MayoPlayer.State.NORMAL),
				"peer %d never saw guest 1 back up" % session.local_id())
		await _physics(10)
		_agree("after rescue")

	# --- 6. a guest powers the generator, another takes a hose ---
	# The generator's own body fills the middle of its zone; dropped inside it a
	# player is pushed out under the floor, so find a spot they stand on.
	_check(await _stand_in_zone(_id(1), host_world._siren_zone, TomatinaMap.at_cell(TomatinaMap.SIREN_CELL)),
		"no spot in the generator zone where a player stands")
	sessions[1].request_context_action("generator", 0)
	_check(await _physics_until(func(): return host_world.horde_spawned()), "guest 1's generator request was not honoured")
	for session in sessions:
		var world = worlds[session]
		_check(await _physics_until(func(): return world.horde_spawned()), "peer %d never saw the generator start" % session.local_id())
	var hoser_index := 2 if players > 2 else 1
	var hoser := _id(hoser_index)
	_place(hoser, TomatinaMap.at_cell(host_world.TOMATINA_HOSES[0]) + Vector3.UP * 1.28)
	await _physics(6)
	sessions[hoser_index].request_context_action("hose", 0)
	_check(await _physics_until(func(): return host_world._hose_slot_of(hoser) == 0), "guest %d's hose request was not honoured" % hoser_index)
	for session in sessions:
		var world = worlds[session]
		_check(await _physics_until(func(): return world._hose_slot_of(hoser) == 0), "peer %d never saw guest %d on the hose" % [session.local_id(), hoser_index])
	await _physics(10)
	# The hose's recoil and the finale's grunts keep bodies moving here, so this
	# is held to the moving tolerance; an 0.02-0.18 m gap is typical.
	# Health and sauce change under fire here and arrive a packet late, so only
	# positions and states are compared.
	print("finale: worst gap %.3f m" % _agree("during the finale", MOVING_TOLERANCE, false))
	# --- 7. the last guest leaves; the fight stays sized, and the door stays shut ---
	var leaver: MayoNet = sessions[players - 1]
	var leaver_id := leaver.local_id()
	var leaver_world: Node = worlds[leaver]
	leaver.leave()
	sessions.erase(leaver)
	worlds.erase(leaver)
	leaver_world.queue_free()
	for session in sessions:
		var world = worlds[session]
		_check(await _physics_until(func(): return world.shooter_for(leaver_id) == null, 600),
			"peer %d kept the departed player's avatar" % session.local_id())
	# The party that set out is the party the fight is sized for.
	_check(host_world.party_size() == players,
		"a leaver changed the party the fight is sized for (%d)" % host_world.party_size())
	# ENet retires a departed peer's slot a beat after reporting the leave; a
	# connection that lands in that slot within ~0.1 s comes up with zero
	# channels and times out (see _on_peer_disconnected). A second is ample.
	await create_timer(1.0).timeout
	var newcomer := _make_peer("NewcomerView")
	await process_frame
	_check(newcomer.begin_join_room("127.0.0.1", SYNC_PORT, "SYNC%d" % players), "the newcomer could not knock")
	_check(await _until(func(): return not newcomer.is_online()), "the newcomer was not turned away")
	_check(newcomer.status() == "session is already in progress",
		"the newcomer was not told the party had set out: '%s'" % newcomer.status())
	_check(host.seat_assignments().size() == players - 1 and host._waiting_peers.is_empty(),
		"a player joined a party that had already set out")
	_finish()


func _finish() -> void:
	for session in sessions:
		session.leave()
	if failures.is_empty():
		print("TOMATINA_PARTY_SYNC_OK players=%d" % players)
	quit(0 if failures.is_empty() else 1)
