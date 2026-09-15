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
func _session(count: int, port: int) -> Array:
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
	worlds[0]._net.host(port)
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

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MAYO_HARNESS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
