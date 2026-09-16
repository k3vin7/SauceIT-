extends SceneTree

# The two-player harness, checked from the outside: the swap keys do swap, and
# only the side being driven moves. Input routing is the part of it that is
# easy to get wrong -- Input is global, so without the hold on the idle side
# every key would drive both players at once.
#
# It also carries the session checks that need more peers than the dev scene
# builds: a client flooding the host, four players at once, a peer rejoining
# over and over, and a wrong lobby code.

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _initialize() -> void:
	call_deferred("_run")

func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

## One world per peer, each in its own SubViewport so it gets its own physics
## space, and its own MultiplayerAPI so it is as separate as another process.
## `codes` is one lobby code per peer, host first; an empty array means an open
## session.
func _session(count: int, port: int, codes: Array = []) -> Array:
	var worlds := []
	for i in count:
		var viewport := SubViewport.new()
		viewport.name = "Peer%d_%d" % [port, i]
		viewport.own_world_3d = true
		viewport.size = Vector2i(64, 64)
		root.add_child(viewport)
		var world = load("res://main.tscn").instantiate()
		world.name = "World"
		viewport.add_child(world)
		world.set_process_unhandled_input(false)
		worlds.push_back(world)
	await physics_frame
	for i in count:
		set_multiplayer(SceneMultiplayer.new(), worlds[i].get_path())
	for i in count:
		worlds[i]._net.lobby_code = str(codes[i]) if i < codes.size() else ""
	worlds[0]._net.host(port, codes.is_empty())
	for i in range(1, count):
		worlds[i]._net.join("127.0.0.1", port)
	for _f in 90:
		await physics_frame
	return worlds


func _close(worlds: Array) -> void:
	for world in worlds:
		world._net.leave()
	await physics_frame


func _run() -> void:
	var harness = load("res://dev_two_player.tscn").instantiate()
	root.add_child(harness)
	for _f in 60:
		await physics_frame
	_check(harness._active == 0, "the harness did not start on the host")
	await _press(KEY_TAB)
	_check(harness._active == 1, "Tab did not move to the client")
	await _press(KEY_TAB)
	_check(harness._active == 0, "Tab did not move back to the host")
	await _press(KEY_2)
	_check(harness._active == 1, "2 did not pick the client")
	await _press(KEY_1)
	_check(harness._active == 0, "1 did not pick the host")
	print("swap keys: Tab, 1 and 2 all move the controls")
	# And does driving actually move only the active player?
	harness._set_active(1)
	var client = harness._worlds[1]
	var host = harness._worlds[0]
	var client_id: int = client._net.local_id()
	# A leftover process on the harness port leaves both sides offline, and
	# every check below would then fail on a missing body rather than on the
	# port, which is the thing that actually went wrong.
	if host.shooter_for(client_id) == null:
		_check(false, "no session came up: host says '%s', client says '%s'" % [
			host._net.status(), client._net.status()])
		_finish()
		return
	var before_b: Vector3 = host.shooter_for(client_id).player.global_position
	var before_a: Vector3 = host.shooter_for(1).player.global_position
	Input.action_press("move_forward")
	for _f in 60:
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	var moved_b: float = before_b.distance_to(host.shooter_for(client_id).player.global_position)
	var moved_a: float = before_a.distance_to(host.shooter_for(1).player.global_position)
	print("driving B: B moved %.2f m, A moved %.2f m" % [moved_b, moved_a])
	_check(moved_b > 0.5, "the side being driven only moved %.2f m" % moved_b)
	_check(moved_a < 0.01,
		"the side that is not being driven moved %.2f m as well" % moved_a)

	# --- a client flooding the host is ignored, not answered ---
	var flood := await _session(2, 24730)
	var flood_host = flood[0]
	var guest = flood[1]
	if flood_host.shooter_ids().size() < 2:
		_check(false, "the flood session did not come up: %s" % flood_host._net.status())
	else:
		var before_dropped: int = flood_host._net.dropped_packets
		var before_position: Vector3 = flood_host.shooter_for(guest._net.local_id()).player.global_position
		# Twenty input packets a tick, for a second. A well-behaved client sends
		# one; the other nineteen are what the budget is for.
		for _f in 60:
			for _i in 20:
				guest._net._submit_input.rpc_id(1, Vector2(0.0, -1.0), true, false, false, 0.0, 0.0)
			await physics_frame
		var dropped: int = flood_host._net.dropped_packets - before_dropped
		var sent := 60 * 20
		var moved: float = before_position.distance_to(
			flood_host.shooter_for(guest._net.local_id()).player.global_position)
		print("flood: %d of %d input packets dropped, the guest still moved %.2f m" % [
			dropped, sent, moved])
		_check(dropped > sent / 2,
			"only %d of %d flooded packets were dropped" % [dropped, sent])
		_check(moved > 1.0,
			"the flood cost the guest their own movement: they went %.2f m" % moved)
		# And the reliable channel.
		var before_wipe_dropped: int = flood_host._net.dropped_packets
		for _f in 60:
			for _i in 10:
				guest._net._request_wipe.rpc_id(1)
			await physics_frame
		var wipe_dropped: int = flood_host._net.dropped_packets - before_wipe_dropped
		print("wipe flood: %d of %d requests dropped (budget %.0f a second)" % [
			wipe_dropped, 600, MayoNet.WIPE_REQUESTS_PER_SECOND])
		_check(wipe_dropped > 550,
			"only %d of 600 wipe requests were dropped" % wipe_dropped)
	await _close(flood)

	# --- four players at once, each in their own body ---
	var party := await _session(4, 24731)
	var party_host = party[0]
	var ids := {}
	for world in party:
		ids[world._net.local_id()] = true
	print("four peers: host sees %d players, ids seen %d, statuses %s" % [
		party_host.shooter_ids().size(), ids.size(),
		str(party.map(func(w): return w._net.is_online()))])
	_check(party_host.shooter_ids().size() == 4,
		"the host has %d players, expected 4" % party_host.shooter_ids().size())
	_check(ids.size() == 4, "the four peers do not have four distinct ids")
	var spawns := {}
	var overlapping := 0
	for id in party_host.shooter_ids():
		var here: Vector3 = party_host.shooter_for(id).player.global_position
		for other in party_host.shooter_ids():
			if other != id and party_host.shooter_for(other).player.global_position.distance_to(here) < 1.28:
				overlapping += 1
		spawns[id] = here
	print("  spawns %.0f m apart at the closest" % _closest(spawns.values()))
	_check(overlapping == 0, "%d players spawned inside another" % overlapping)
	for world in party:
		_check(world.shooter_ids().size() == 4,
			"a peer sees %d players, expected 4" % world.shooter_ids().size())

	# What a four-player session actually costs the host: all four hosing the
	# floor at once, which is the worst case rather than the usual one.
	var before_state: int = party_host._net.state_bytes_sent
	var before_splat: int = party_host._net.splat_bytes_sent
	for world in party:
		world.debug_set_aim(0.0, -30.0)
		world.debug_set_input(Vector2.ZERO, false, true)
	for _f in 120:
		await physics_frame
	for world in party:
		world.debug_clear_input_override()
	var state_rate: float = (party_host._net.state_bytes_sent - before_state) / 2048.0
	var splat_rate: float = (party_host._net.splat_bytes_sent - before_splat) / 2048.0
	print("  four firing, host upload: state %.1f kB/s, splats %.1f kB/s, total %.1f kB/s" % [
		state_rate, splat_rate, state_rate + splat_rate])
	_check(state_rate + splat_rate < 200.0,
		"a four-player host is pushing %.1f kB/s" % (state_rate + splat_rate))
	await _close(party)

	# --- a peer rejoining over and over gets its spawn back ---
	var revolving := await _session(2, 24732)
	var door_host = revolving[0]
	var comer = revolving[1]
	var slots_seen := {}
	var spawns_seen := {}
	for round in 10:
		var id: int = comer._net.local_id()
		if door_host._net._slots.has(id):
			slots_seen[door_host._net._slots[id]] = true
			spawns_seen[str(door_host.spawn_position_for(door_host._net._slots[id]))] = true
		comer._net.leave()
		for _f in 20:
			await physics_frame
		comer._net.join("127.0.0.1", 24732)
		for _f in 40:
			await physics_frame
	print("ten rejoins: slots handed out %s, distinct spawns %d, host sees %d players" % [
		str(slots_seen.keys()), spawns_seen.size(), door_host.shooter_ids().size()])
	_check(slots_seen.size() == 1,
		"ten rejoins used %d different slots: %s" % [slots_seen.size(), str(slots_seen.keys())])
	_check(door_host.shooter_ids().size() == 2,
		"after ten rejoins the host has %d players, expected 2" % door_host.shooter_ids().size())
	await _close(revolving)

	# --- a stain lands in the cell it was aimed at, on any screen ---
	print("stain placement, worst error in cells (want 0,0):")
	for shape in [
			["16:9", 16.0 / 9.0, Vector2i(1280, 720)],
			["16:10", 16.0 / 10.0, Vector2i(1280, 800)],
			["21:9", 21.0 / 9.0, Vector2i(1260, 540)]]:
		var table := await _mapping_errors(74.0, shape[1], shape[2])
		print("  %-6s %s at 74 deg -> %s" % [shape[0], str(shape[2]), str(table.worst)])
		_check(table.worst == Vector2i.ZERO,
			"%s is off by %s cells: %s" % [shape[0], str(table.worst), str(table.rows)])
	for fov in [60.0, 74.0, 110.0]:
		var table := await _mapping_errors(fov, 16.0 / 9.0, Vector2i(1280, 720))
		print("  16:9   at %.0f deg -> %s" % [fov, str(table.worst)])
		_check(table.worst == Vector2i.ZERO,
			"%.0f deg is off by %s cells: %s" % [fov, str(table.worst), str(table.rows)])

	# --- a peer's camera is what it declared, whatever it sends ---
	var seen := await _session(2, 24734)
	var seen_host = seen[0]
	var looker = seen[1]
	var looker_id: int = looker._net.local_id()
	for _f in 20:
		await physics_frame
	# The report has to arrive on its own. The first one goes out as the
	# connection comes up, which is exactly when a packet is most likely to go
	# nowhere, and nothing else will ever send another until the player resizes
	# their window.
	var honest: Vector2 = seen_host._net.view_for(looker_id)
	print("first report: host holds %s for the guest, guest renders (%.1f, %.3f), pane aspect %.3f" % [
		str(honest), looker.camera_fov, looker._view_aspect,
		looker.get_viewport().get_visible_rect().size.aspect()])
	_check(seen_host._net._views.has(looker_id),
		"the guest's first view report never reached the host")
	_check(is_equal_approx(looker._view_aspect, honest.y)
			and is_equal_approx(looker.camera_fov, honest.x),
		"the guest renders (%.1f, %.3f) while the host paints it on %s" % [
			looker.camera_fov, looker._view_aspect, str(honest)])
	looker._net._submit_view.rpc_id(1, 200.0, 0.0)
	for _f in 20:
		await physics_frame
	var clamped: Vector2 = seen_host._net.view_for(looker_id)
	print("view clamp: honest %s, after sending (200, 0) host has %s, client renders (%.1f, %.3f)" % [
		str(honest), str(clamped), looker.camera_fov, looker._view_aspect])
	_check(is_equal_approx(clamped.x, MayoNet.MAX_FOV_DEGREES),
		"a 200 degree claim was stored as %.1f" % clamped.x)
	_check(is_equal_approx(clamped.y, MayoNet.MIN_ASPECT),
		"a zero aspect was stored as %.3f" % clamped.y)
	_check(is_equal_approx(looker.camera_fov, clamped.x)
			and is_equal_approx(looker._view_aspect, clamped.y),
		"the client renders (%.1f, %.3f) but the host paints (%s)" % [
			looker.camera_fov, looker._view_aspect, str(clamped)])
	var before_rejected: int = seen_host._net.rejected_packets
	var before_view: Vector2 = seen_host._net.view_for(looker_id)
	looker._net._submit_view.rpc_id(1, NAN, INF)
	for _f in 20:
		await physics_frame
	print("view NaN: rejected %d -> %d, stored view %s -> %s" % [
		before_rejected, seen_host._net.rejected_packets,
		str(before_view), str(seen_host._net.view_for(looker_id))])
	_check(seen_host._net.rejected_packets > before_rejected,
		"a NaN view was not counted as rejected")
	_check(seen_host._net.view_for(looker_id) == before_view,
		"a NaN view changed the stored one")
	await _close(seen)

	# --- two peers on different cameras are each painted on their own ---
	var pair := await _session(3, 24735)
	var pair_host = pair[0]
	var narrow_id: int = pair[1]._net.local_id()
	var wide_id: int = pair[2]._net.local_id()
	pair[1]._net._submit_view.rpc_id(1, 60.0, 16.0 / 9.0)
	pair[2]._net._submit_view.rpc_id(1, 110.0, 16.0 / 9.0)
	for _f in 20:
		await physics_frame
	# The same direction off the eye, half way to the edge of a 74 degree screen.
	var look := Vector3(0.0, tan(deg_to_rad(37.0)) * 0.5, -1.0)
	var narrow_visor = pair_host.shooter_for(narrow_id).player.visor
	var wide_visor = pair_host.shooter_for(wide_id).player.visor
	narrow_visor.clear()
	wide_visor.clear()
	var narrow_cell: Vector2i = narrow_visor.paint_from_hit(look)
	var wide_cell: Vector2i = wide_visor.paint_from_hit(look)
	print("two cameras: 60 deg peer -> row %d, 110 deg peer -> row %d (same hit)" % [
		narrow_cell.y, wide_cell.y])
	_check(narrow_cell.y > wide_cell.y,
		"the narrow camera did not put the hit higher up the screen: %d vs %d" % [
			narrow_cell.y, wide_cell.y])
	_check(pair_host._net.view_for(narrow_id).x == 60.0
			and pair_host._net.view_for(wide_id).x == 110.0,
		"the host is not holding a separate view per peer")
	await _close(pair)

	# --- a guest that does not know the code never becomes a player ---
	var gated := await _session(3, 24733, ["mayo", "mayo", "ketchup"])
	var gate_host = gated[0]
	var welcome = gated[1]
	var refused = gated[2]
	print("lobby code: host sees %d players, right code online %s, wrong code online %s (%s), refused %d" % [
		gate_host.shooter_ids().size(), str(welcome._net.is_online()),
		str(refused._net.is_online()), refused._net.status(),
		gate_host._net.refused_peers])
	_check(gate_host.shooter_ids().size() == 2,
		"the host has %d players: the wrong code got in" % gate_host.shooter_ids().size())
	_check(welcome._net.is_online(), "the right code was refused as well")
	_check(not refused._net.is_online(), "the wrong code is still connected")
	_check(gate_host._net.refused_peers == 1,
		"the host refused %d peers, expected 1" % gate_host._net.refused_peers)
	_check(refused._net.status().contains("code"),
		"the refused guest was told '%s' rather than that its code was wrong" % refused._net.status())
	await _close(gated)

	# --- an empty code is a generated one, not an open door ---
	var made := await _session(1, 24736, ["", ""])
	var made_code: String = made[0]._net.lobby_code
	var alphabet := MayoNet.CODE_ALPHABET
	var legible := true
	for character in made_code:
		legible = legible and alphabet.contains(character)
	print("generated code: '%s' (%d chars, only legible characters %s)" % [
		made_code, made_code.length(), str(legible)])
	_check(made_code.length() == MayoNet.CODE_LENGTH,
		"a generated code is %d characters, expected %d" % [
			made_code.length(), MayoNet.CODE_LENGTH])
	_check(legible, "the generated code '%s' has a character that reads wrong" % made_code)
	await _close(made)

	# --- and guessing at it gets the address shut out ---
	var door := await _session(1, 24737, ["thecode"])
	var locked_host = door[0]
	var tries := 0
	var blocked_at := 0
	for attempt in MayoNet.CODE_ATTEMPTS + 2:
		var knocker := await _session(1, 24738)
		knocker[0]._net.leave()
		knocker[0]._net.lobby_code = "wrong%d" % attempt
		knocker[0]._net.join("127.0.0.1", 24737)
		for _f in 40:
			await physics_frame
		tries += 1
		if blocked_at == 0 and locked_host._net.blocked_attempts > 0:
			blocked_at = tries
		_check(not knocker[0]._net.is_online(),
			"a wrong code got in on try %d" % tries)
		await _close(knocker)
	print("wrong codes: %d tries -> %d refused, %d turned away unasked (blocked from try %d), 127.0.0.1 waits %.0f s" % [
		tries, locked_host._net.refused_peers, locked_host._net.blocked_attempts,
		blocked_at, locked_host._net.block_remaining("127.0.0.1")])
	_check(locked_host._net.refused_peers == MayoNet.CODE_ATTEMPTS,
		"the host checked %d codes, expected to stop asking after %d" % [
			locked_host._net.refused_peers, MayoNet.CODE_ATTEMPTS])
	_check(locked_host._net.blocked_attempts == 2,
		"%d tries were turned away unasked, expected 2" % locked_host._net.blocked_attempts)
	_check(locked_host._net.block_remaining("127.0.0.1") > 0.0,
		"the address is not waiting out a block")
	_check(locked_host._net.block_count("127.0.0.1") == 1,
		"the address is on rung %d after one block" % locked_host._net.block_count("127.0.0.1"))
	# What is left of it, since the two attempts that followed took a few seconds
	# of it. That it is the bottom rung and not one of the long ones is the point
	# here; the exact lengths are walked through below.
	var first_block: float = locked_host._net.block_remaining("127.0.0.1")
	_check(first_block > 0.0 and first_block <= MayoNet.CODE_BLOCK_LADDER[0],
		"the first block has %.0f s left, which is not inside the bottom rung of %.0f" % [
			first_block, MayoNet.CODE_BLOCK_LADDER[0]])
	# A blocked address is told how long it has, rather than dropped without a
	# word.
	var before_replies: int = locked_host._net.blocked_replies
	var caller := await _session(1, 24741)
	caller[0]._net.leave()
	# Past the second the tries above have already used up this address's answer.
	for _f in 80:
		await physics_frame
	caller[0]._net.lobby_code = "wrong"
	caller[0]._net.join("127.0.0.1", 24737)
	for _f in 40:
		await physics_frame
	print("  turned away: told '%s', %d s to wait" % [
		caller[0]._net.status(), caller[0]._net.blocked_seconds()])
	_check(caller[0]._net.blocked_seconds() > 0,
		"the blocked peer was told nothing: '%s'" % caller[0]._net.status())
	_check(caller[0]._net.blocked_seconds() <= MayoNet.CODE_BLOCK_LADDER[0],
		"the peer was told to wait %d s, longer than the bottom rung" %
			caller[0]._net.blocked_seconds())
	_check(locked_host._net.blocked_replies - before_replies == 1,
		"the host sent %d answers to one knock" % (
			locked_host._net.blocked_replies - before_replies))
	await _close(caller)

	# And the answer is worth one packet a second per address, not one per knock.
	# Driven on an injected clock: a knock takes a handshake and the machine
	# running this decides how long that is, which is not a thing to measure a
	# per-second limit against.
	var limiter = locked_host._net
	var beat := 5000.0
	var answers := []
	for step in [0.0, 0.2, 0.5, 1.1, 1.2]:
		answers.push_back(limiter._may_answer_block("10.0.0.9", beat + step))
	print("  reply limit at +0.0/+0.2/+0.5/+1.1/+1.2 s: %s" % str(answers))
	_check(answers == [true, false, false, true, false],
		"the reply limit answered %s, expected one a second" % str(answers))

	# And the right code is no use while the address is shut out.
	var latecomer := await _session(1, 24739)
	latecomer[0]._net.leave()
	latecomer[0]._net.lobby_code = "thecode"
	latecomer[0]._net.join("127.0.0.1", 24737)
	for _f in 40:
		await physics_frame
	print("  the right code during a block: online %s" % str(latecomer[0]._net.is_online()))
	_check(not latecomer[0]._net.is_online(),
		"the block let the right code straight through")
	await _close(latecomer)
	await _close(door)

	# --- and each block is longer than the last ---
	# Walked through the same _record_failure the handshake calls, with the clock
	# passed in: the blocks are minutes long and a check cannot sit through them.
	var ladder := await _session(1, 24740)
	var counter = ladder[0]._net
	var clock := 1000.0
	var handed := []
	for round in MayoNet.CODE_BLOCK_LADDER.size() + 1:
		for _try in MayoNet.CODE_ATTEMPTS:
			counter._record_failure("10.0.0.7", clock)
		handed.push_back(counter.block_remaining("10.0.0.7", clock))
		# Wait the block out, then come back: inside the memory, so the next one
		# is the next rung up.
		clock += handed[handed.size() - 1] + 1.0
	print("block ladder: %s s (rungs %s), address is on rung %d" % [
		str(handed), str(MayoNet.CODE_BLOCK_LADDER), counter.block_count("10.0.0.7")])
	var expected_ladder := []
	for round in MayoNet.CODE_BLOCK_LADDER.size() + 1:
		expected_ladder.push_back(MayoNet.CODE_BLOCK_LADDER[
			mini(round, MayoNet.CODE_BLOCK_LADDER.size() - 1)])
	for i in handed.size():
		_check(is_equal_approx(handed[i], expected_ladder[i]),
			"block %d lasted %.0f s, expected %.0f" % [i + 1, handed[i], expected_ladder[i]])

	# And nothing is remembered once it is over.
	var quiet := clock + MayoNet.CODE_BLOCK_MEMORY + MayoNet.CODE_SWEEP_SECONDS + 1.0
	counter._record_failure("10.0.0.8", quiet)
	counter._next_sweep = 0.0
	counter._sweep_blocks(quiet)
	print("sweep: %d blocks and %d failure runs left after %.0f s of quiet" % [
		counter._blocks.size(), counter._code_failures.size(), MayoNet.CODE_BLOCK_MEMORY])
	_check(not counter._blocks.has("10.0.0.7"),
		"an expired block was still on the books %.0f s later" % MayoNet.CODE_BLOCK_MEMORY)
	_check(counter._code_failures.has("10.0.0.8"),
		"the sweep threw away a run of wrong codes that is still going")
	counter._next_sweep = 0.0
	counter._sweep_blocks(quiet + MayoNet.CODE_ATTEMPT_WINDOW + 1.0)
	_check(not counter._code_failures.has("10.0.0.8"),
		"a run of wrong codes that went quiet was kept")
	_check(counter._blocks.is_empty() and counter._code_failures.is_empty(),
		"the sweep left %d blocks and %d runs behind" % [
			counter._blocks.size(), counter._code_failures.size()])
	await _close(ladder)

	_finish()


## Builds one world in a viewport of the given size, points its camera at the
## given view, and reports where a hit aimed at each of nine screen points is
## actually painted on the lenses.
##
## The aiming is done through the camera's own projection rather than through the
## mapping under test: a screen pixel is unprojected to a world point and that
## point is handed to the ordinary hit path. In first person the camera sits at
## the eye the lenses hang off, so the two see the same frustum and the cell the
## splat lands in has to be the cell that pixel falls in.
func _mapping_errors(fov: float, aspect: float, size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "View_%d_%d" % [size.x, size.y]
	viewport.own_world_3d = true
	viewport.size = size
	root.add_child(viewport)
	var world = load("res://main.tscn").instantiate()
	viewport.add_child(world)
	world.set_process_unhandled_input(false)
	await physics_frame
	world.set_first_person(true)
	world.camera_fov = fov
	world.apply_view(fov, aspect)
	world.debug_set_aim(0.0, 0.0)
	for _f in 4:
		await physics_frame
	var camera: Camera3D = world._camera
	var player = world._local.player
	var visor = player.visor
	var width: int = visor.grid.width
	var height: int = visor.grid.height
	var worst := Vector2i.ZERO
	var rows := []
	# 1% in from each edge, so a corner point is inside the corner cell rather
	# than exactly on the boundary between it and nothing.
	for v in [0.01, 0.5, 0.99]:
		for u in [0.01, 0.5, 0.99]:
			visor.clear()
			var pixel := Vector2(u * size.x, v * size.y)
			var point := camera.project_position(pixel, 3.0)
			world._pending_splats.clear()
			world._record_visor_splat(player, point)
			var expected := Vector2i(
				clampi(floori(u * width), 0, width - 1),
				clampi(floori((1.0 - v) * height), 0, height - 1))
			var actual := Vector2i(-1, -1)
			if world._pending_splats.size() >= 4:
				actual = Vector2i(world._pending_splats[2], world._pending_splats[3])
			var error := Vector2i(99, 99) if actual.x < 0 else actual - expected
			worst = Vector2i(maxi(worst.x, absi(error.x)), maxi(worst.y, absi(error.y)))
			rows.push_back("(%.2f,%.2f) want %s got %s" % [u, v, str(expected), str(actual)])
	viewport.queue_free()
	await physics_frame
	return {"worst": worst, "rows": rows}


## Closest distance between any two of the given positions.
func _closest(positions: Array) -> float:
	var nearest := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			nearest = minf(nearest, positions[i].distance_to(positions[j]))
	return nearest


func _finish() -> void:
	if failures.is_empty():
		print("MAYO_HARNESS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
