extends SceneTree

# Two worlds, two MultiplayerAPIs, one process, talking to each other over
# 127.0.0.1. Each world sits under its own SubViewport so it gets its own
# World3D: without that the two floors and four capsules would share a physics
# space and every raycast would hit the wrong world.
#
# This is the acceptance list for the session, in order:
#   * both peers end up with both players
#   * the grid stains land on exactly the same cells on both screens -- the
#     whole floor is compared by hash, not by eye
#   * mayo laid down by A trips B when B runs through it
#   * B going down is visible on A's screen: A's copy of B lies down too
#   * the fall states line up on both screens, every frame, through the
#     stumble, the fall, the slide and standing up
#   * only the server paints: a client's own strand marks nothing by itself
#   * a client cannot move faster than its keys allow, and cannot put a NaN
#     into a body the server owns
#   * both screens agree which way each player is facing and spraying, at an
#     angle picked so that "not replicated at all" would still look plausible
#   * spraying a player marks their body identically on both screens, and puts
#     sauce on the sprayed player's camera and on nobody else's

const PORT := 24777

var failures: Array[String] = []
var server_world
var client_world


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _make_world(view_name: String, world_name: String):
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var world = load("res://main.tscn").instantiate()
	world.name = world_name
	viewport.add_child(world)
	world.set_process_unhandled_input(false)
	return world


func _wait(frames: int) -> void:
	for _f in frames:
		await physics_frame


## World position of a cell that is actually painted, nearest the middle of
## everything that is. The centroid itself can easily sit in a gap.
func _painted_cell_position(world) -> Vector3:
	var grid = world._floor.grid
	var total := Vector2.ZERO
	var count := 0
	for y in grid.height:
		for x in grid.width:
			if grid.cells[y * grid.width + x] == 1:
				total += Vector2(float(x), float(y))
				count += 1
	if count == 0:
		return Vector3.ZERO
	var centroid := total / float(count)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in grid.height:
		for x in grid.width:
			if grid.cells[y * grid.width + x] != 1:
				continue
			var distance := centroid.distance_squared_to(Vector2(float(x), float(y)))
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	var local := Vector2(
		(float(best.x) + 0.5) * grid.cell_size - grid.extent.x * 0.5,
		(float(best.y) + 0.5) * grid.cell_size - grid.extent.y * 0.5)
	return world._floor.to_global(Vector3(local.x, 0.0, local.y))


func _run() -> void:
	server_world = _make_world("ServerView", "World")
	client_world = _make_world("ClientView", "World")
	await physics_frame

	# Each subtree gets its own MultiplayerAPI, so the two peers are as separate
	# as two processes. RPC paths are resolved against these roots, and both
	# worlds are laid out the same way, so "Net" means "Net" on both sides.
	var server_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	set_multiplayer(server_api, ^"/root/ServerView/World")
	set_multiplayer(client_api, ^"/root/ClientView/World")

	_check(server_world._net.host(PORT), "the host could not open the port")
	_check(client_world._net.join("127.0.0.1", PORT), "the client could not start connecting")
	await _wait(60)

	var client_id: int = client_world._net.local_id()
	print("session: server=%s / client=%s, ids server%s client%s" % [
		server_world._net.status(), client_world._net.status(),
		str(server_world.shooter_ids()), str(client_world.shooter_ids())])
	_check(server_world.shooter_ids().size() == 2,
		"the host has %d players, expected 2" % server_world.shooter_ids().size())
	_check(client_world.shooter_ids().size() == 2,
		"the client has %d players, expected 2" % client_world.shooter_ids().size())
	_check(client_world.shooter_for(client_id) != null
			and client_world.shooter_for(client_id).is_local,
		"the client is not looking out of its own body")
	_check(client_world.shooter_for(1) != null,
		"the client never got a body for the host")
	print("state packets the client has taken: %d" % client_world._net.debug_state_packets)
	_check(client_world._net.debug_state_packets > 0,
		"the client never received a state packet")
	if failures.size() > 0:
		_finish()
		return

	# --- a client's packets cannot ask for more than its keyboard could ---
	# The server simulates both bodies off these values, so an unclamped one is
	# a speed hack and a NaN takes the session down with it.
	var target = server_world.shooter_for(client_id).player
	var start_position: Vector3 = target.global_position
	var rejected_before: int = server_world._net.rejected_packets
	client_world.debug_set_input(Vector2.ZERO, false, false)
	# The client world is stopped for this section so that its own well-behaved
	# packet does not land on top of the hostile one and hide the result: what
	# the server acts on here is only what is sent below.
	client_world.set_physics_process(false)
	for _f in 40:
		await physics_frame
		client_world._net._submit_input.rpc_id(1,
			Vector2(NAN, INF), true, true, NAN, INF)
	await _wait(4)
	var after_nan: Vector3 = target.global_position
	print("hostile: %d NaN packets rejected, B at %.2v (started %.2v), speed %.2f m/s" % [
		server_world._net.rejected_packets - rejected_before, after_nan, start_position,
		target.velocity.length()])
	# Not all 40 arrive: the input channel is unreliable by design, and a late
	# one is dropped rather than delivered late. What matters is that every one
	# that did arrive was thrown away, which the two checks below measure.
	_check(server_world._net.rejected_packets - rejected_before > 30,
		"only %d of the 40 hostile packets reached the server, too few to conclude from"
			% (server_world._net.rejected_packets - rejected_before))
	_check(after_nan.is_finite() and target.velocity.is_finite(),
		"a NaN reached the body the server owns: position %v" % after_nan)
	_check(after_nan.distance_to(start_position) < 0.01,
		"the rejected packets still moved B %.2f m" % after_nan.distance_to(start_position))

	# A move vector a hundred times longer than a full stick deflection, held
	# long enough that any speed above the run speed would have shown up.
	for _f in 90:
		await physics_frame
		client_world._net._submit_input.rpc_id(1,
			Vector2(0.0, -100.0), true, false, 0.0, 0.0)
	var top_speed: float = target.velocity.length()
	var run_speed: float = target.run_speed
	print("hostile: oversized move vector reached %.2f m/s, run speed is %.2f m/s" % [
		top_speed, run_speed])
	_check(top_speed <= run_speed + 0.01,
		"an oversized move vector drove B at %.2f m/s, past the %.2f m/s run speed" % [
			top_speed, run_speed])
	# And it did move: a check that passes because nothing happened proves
	# nothing about the clamp.
	_check(top_speed > run_speed - 0.5,
		"B only reached %.2f m/s, so the oversized packet never drove them at all" % top_speed)
	# Put B back where the rest of the checks expect to find them.
	client_world.set_physics_process(true)
	client_world.debug_set_input(Vector2.ZERO, false, false)
	await _wait(30)

	# --- A sprays the floor; both grids must agree cell for cell ---
	server_world.debug_set_input(Vector2.ZERO, false, true)
	client_world.debug_set_input(Vector2.ZERO, false, false)
	# Swept a little while firing, so what lands is a stripe wide enough to run
	# through rather than a single blob.
	for frame in 120:
		server_world.debug_set_aim(-9.0 + 18.0 * float(frame) / 120.0, -34.0)
		await physics_frame
	server_world.debug_set_input(Vector2.ZERO, false, false)
	await _wait(60)

	var server_hash: String = server_world.grid_md5()
	var client_hash: String = client_world.grid_md5()
	var server_cells: int = server_world._floor.grid.painted_cell_count()
	var client_cells: int = client_world._floor.grid.painted_cell_count()
	print("floor after A fires: server %d cells, client %d cells" % [server_cells, client_cells])
	print("  server grid %s" % server_hash)
	print("  client grid %s" % client_hash)
	_check(server_cells > 100, "A only painted %d cells, too few to test with" % server_cells)
	_check(server_hash == client_hash,
		"the two screens disagree about the grid (%d vs %d cells)" % [server_cells, client_cells])

	# --- both screens agree which way a player is aiming and spraying ---
	# Yaw is the one that can go wrong quietly: the body's rotation travels in
	# the state packet, but _update_aim rewrites the body from the aim every
	# frame, so a yaw that lands on the body alone is overwritten and the remote
	# player sprays down whatever yaw this peer happened to have for them.
	for aim in [[47.0, -20.0], [-133.0, 12.0], [95.0, 0.0]]:
		server_world.debug_set_aim(aim[0], aim[1])
		await _wait(6)
		var here = server_world.shooter_for(1)
		var there = client_world.shooter_for(1)
		var facing_gap := rad_to_deg(absf(wrapf(
			here.player.rotation.y - there.player.rotation.y, -PI, PI)))
		var spray_gap := rad_to_deg(here.attack_direction.angle_to(there.attack_direction))
		print("A aims yaw %.0f pitch %.0f: body differs by %.2f deg, spray by %.2f deg" % [
			aim[0], aim[1], facing_gap, spray_gap])
		_check(facing_gap < 1.0,
			"the two screens have A facing %.1f deg apart at yaw %.0f" % [facing_gap, aim[0]])
		_check(spray_gap < 1.0,
			"the two screens have A spraying %.1f deg apart at yaw %.0f" % [spray_gap, aim[0]])
	# The same check the other way round. The two directions read a player's aim
	# from different messages -- the host takes a client's off the input packet,
	# a client takes the host's off the state packet -- so one of them being
	# right says nothing about the other.
	for aim in [[47.0, -20.0], [-133.0, 12.0], [95.0, 0.0]]:
		client_world.debug_set_aim(aim[0], aim[1])
		await _wait(10)
		var mine = client_world.shooter_for(client_id)
		var theirs = server_world.shooter_for(client_id)
		var facing_gap := rad_to_deg(absf(wrapf(
			mine.player.rotation.y - theirs.player.rotation.y, -PI, PI)))
		var spray_gap := rad_to_deg(mine.attack_direction.angle_to(theirs.attack_direction))
		print("B aims yaw %.0f pitch %.0f: body differs by %.2f deg, spray by %.2f deg" % [
			aim[0], aim[1], facing_gap, spray_gap])
		_check(facing_gap < 1.0,
			"the two screens have B facing %.1f deg apart at yaw %.0f" % [facing_gap, aim[0]])
		_check(spray_gap < 1.0,
			"the two screens have B spraying %.1f deg apart at yaw %.0f" % [spray_gap, aim[0]])
	server_world.debug_set_aim(0.0, -34.0)
	client_world.debug_set_aim(0.0, 0.0)
	await _wait(10)

	# --- a client's own strand paints nothing: the server owns the grid ---
	var before_hash: String = client_world.grid_md5()
	client_world.debug_set_aim(0.0, -34.0)
	client_world.debug_set_input(Vector2.ZERO, false, true)
	# Held only long enough for the client's own strand to reach the floor and
	# land, but the server's copy of that same shooter is what marks it.
	await _wait(8)
	var client_only_hash: String = client_world.grid_md5()
	client_world.debug_set_input(Vector2.ZERO, false, false)
	await _wait(90)
	var settled_hash: String = client_world.grid_md5()
	print("client fires: unchanged mid-flight=%s, matches server afterwards=%s" % [
		str(client_only_hash == before_hash), str(settled_hash == server_world.grid_md5())])
	_check(client_only_hash == before_hash,
		"the client painted its own splat instead of waiting for the server")
	_check(settled_hash == server_world.grid_md5(),
		"the grids diverged once the client's own strand landed")

	# --- A sprays B, and B's body is marked the same on both screens ---
	var b_on_host = server_world.shooter_for(client_id).player
	b_on_host.global_position = Vector3(0.0, 0.64, 0.05)
	server_world.shooter_for(1).player.global_position = Vector3(0.0, 0.64, 1.55)
	await _wait(6)
	server_world.debug_aim_at(b_on_host.global_position + Vector3(0.0, 0.15, 0.0))
	server_world.debug_set_input(Vector2.ZERO, false, true)
	await _wait(90)
	server_world.debug_set_input(Vector2.ZERO, false, false)
	await _wait(30)

	print("screens: %d blobs on the shooter's, %d on the player being sprayed" % [
		server_world._splatter.blob_count(), client_world._splatter.blob_count()])
	_check(client_world._splatter.blob_count() > 0,
		"B was sprayed and got no sauce on their camera")
	_check(server_world._splatter.blob_count() == 0,
		"A got %d blobs on their own camera for spraying someone else"
			% server_world._splatter.blob_count())
	client_world._splatter.wipe()
	_check(client_world._splatter.blob_count() == 0, "the wipe left blobs behind")
	_check(client_world.body_md5(client_id) == server_world.body_md5(client_id),
		"wiping B's camera changed the stain on B's body")

	var host_body: String = server_world.body_md5(client_id)
	var client_body: String = client_world.body_md5(client_id)
	var host_body_cells: int = server_world.shooter_for(client_id).player.contamination.painted_cell_count()
	var client_body_cells: int = client_world.shooter_for(client_id).player.contamination.painted_cell_count()
	print("B's body after A sprays them: %d cells on the host, %d on B's screen" % [
		host_body_cells, client_body_cells])
	_check(host_body_cells > 20,
		"A sprayed B and only %d cells of B's body were marked" % host_body_cells)
	_check(host_body == client_body,
		"the two screens disagree about B's body (%d vs %d cells)" % [
			host_body_cells, client_body_cells])

	# --- B runs through A's mayo and goes down ---
	var patch := _painted_cell_position(server_world)
	_check(server_world._floor.is_mayo_at(patch),
		"the patch the run is aimed at is not painted, so this case tests nothing")
	var client_player = server_world.shooter_for(client_id).player
	# A is stood well out of the way first: two capsules overlapping would shove
	# B off the line before they reached the patch.
	server_world.shooter_for(1).player.global_position = Vector3(-5.0, 0.64, 5.0)
	# Dropped in behind the patch, facing it, and told to sprint at it.
	client_player.global_position = patch + Vector3(0.0, 0.64, 1.1)
	client_world.debug_set_aim(0.0, 0.0)
	client_world.debug_set_input(Vector2(0.0, -1.0), true, false)
	print("B starts at %.2v, patch centre %.2v" % [client_player.global_position, patch])

	var tripped_on_server := false
	var tripped_on_client := false
	var mismatches := 0
	var compared := 0
	var states_seen := {}
	var server_tilt_peak := 0.0
	var client_tilt_peak := 0.0
	for frame in 240:
		await physics_frame
		var server_copy = server_world.shooter_for(client_id).player
		if frame % 40 == 0:
			# Both columns are the same body seen from the two peers, so they
			# have to read the same.
			print("  frame %3d: B at %.2v on the host, %.2v on B's screen" % [
				frame, server_copy.global_position,
				client_world.shooter_for(client_id).player.global_position])
		var client_copy = client_world.shooter_for(client_id).player
		if client_copy == null:
			break
		if server_copy.is_incapacitated():
			tripped_on_server = true
			client_world.debug_set_input(Vector2.ZERO, false, false)
		if client_copy.is_incapacitated():
			tripped_on_client = true
		if tripped_on_server:
			compared += 1
			states_seen[server_copy.state] = true
			if server_copy.state != client_copy.state:
				mismatches += 1
			# The capsule A watches go over is A's own copy of B.
			server_tilt_peak = maxf(server_tilt_peak,
				absf(server_world.shooter_for(client_id).body_mesh.rotation.x))
			client_tilt_peak = maxf(client_tilt_peak,
				absf(client_world.shooter_for(client_id).body_mesh.rotation.x))
		if tripped_on_server and server_copy.state == MayoPlayer.State.NORMAL and compared > 30:
			break

	print("B on A's mayo: tripped on host=%s, on B's own screen=%s" % [
		str(tripped_on_server), str(tripped_on_client)])
	print("fall states compared for %d frames, %d disagreed, states seen %s" % [
		compared, mismatches, str(states_seen.keys())])
	print("capsule pitch peak: host's copy of B %.1f deg, B's own %.1f deg" % [
		rad_to_deg(server_tilt_peak), rad_to_deg(client_tilt_peak)])
	_check(tripped_on_server, "B ran through A's mayo and the host never tripped them")
	_check(tripped_on_client, "B went down on the host but not on B's own screen")
	_check(compared > 40, "only %d frames of the fall were compared" % compared)
	_check(mismatches == 0,
		"the two screens disagreed about the fall state on %d of %d frames" % [
			mismatches, compared])
	# Every beat has to show up, not just "not upright": stumble, fall, flat,
	# and standing up again.
	for state in [MayoPlayer.State.STUMBLE, MayoPlayer.State.FALLING,
			MayoPlayer.State.DOWN, MayoPlayer.State.STANDING_UP]:
		_check(states_seen.has(state), "the fall never passed through state %d" % state)
	_check(server_tilt_peak > deg_to_rad(80.0),
		"on A's screen B's capsule only pitched %.1f deg" % rad_to_deg(server_tilt_peak))
	_check(absf(server_tilt_peak - client_tilt_peak) < deg_to_rad(2.0),
		"the capsule lay down differently on the two screens (%.1f vs %.1f deg)" % [
			rad_to_deg(server_tilt_peak), rad_to_deg(client_tilt_peak)])

	# --- and the grid still matches after all of that ---
	print("final grid: server %s / client %s" % [server_world.grid_md5(), client_world.grid_md5()])
	_check(server_world.grid_md5() == client_world.grid_md5(),
		"the grids had drifted apart by the end of the session")
	_finish()


func _finish() -> void:
	if is_instance_valid(server_world):
		server_world._net.leave()
	if is_instance_valid(client_world):
		client_world._net.leave()
	if failures.is_empty():
		print("MAYO_NETWORK_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
