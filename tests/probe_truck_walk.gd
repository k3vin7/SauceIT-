extends SceneTree

# Walking around inside the truck, over a real two-peer ENet session.
#
# The truck used to be scenery with the party parked on its benches, so nothing
# in it had to agree between two machines. Now it is walked through, on the same
# split as the stage -- clients send keys, the host walks every body and sends
# back where they ended up -- and this is the acceptance list for that:
#
#   * a guest's keys move the guest, on the guest's own screen and on the host's
#   * the host's keys move the host, on both screens too
#   * the two screens put every occupant in the same place
#   * the hull holds: nobody walks out through the bench or the tailgate
#   * a NaN in a client packet never reaches a body the host owns
#   * an oversized move vector does not walk faster than the keys could
#
# Each truck sits under its own SubViewport so the two get separate World3Ds:
# sharing one would put eight capsules and two floors in the same physics space.

const PORT := 24839
const TruckScene := preload("res://truck_lobby.tscn")
## How far apart the two screens may put the same occupant. The guest's own body
## is a frame or two behind the host's by design -- there is no prediction -- so
## this is a latency allowance, not a correctness one. At the truck's 3.4 m/s a
## frame is 5.7 cm.
const AGREEMENT := 0.25

var failures: Array[String] = []
var host: MayoNet
var guest: MayoNet
var host_truck: TruckLobby
var guest_truck: TruckLobby


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _until(condition: Callable, frames := 600) -> bool:
	for _index in frames:
		if condition.call():
			return true
		await physics_frame
	return false


func _wait(frames: int) -> void:
	for _index in frames:
		await physics_frame


func _make_peer(view_name: String) -> Array:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var peer_root := Node.new()
	peer_root.name = "PeerRoot"
	viewport.add_child(peer_root)
	var session := MayoNet.new()
	session.name = "Session"
	peer_root.add_child(session)
	var api := SceneMultiplayer.new()
	set_multiplayer(api, peer_root.get_path())
	return [session, viewport]


## The truck is built only once the session has a roster, because that is what
## it spawns occupants from -- exactly as `AppRoot` does it.
func _make_truck(session: MayoNet, viewport: SubViewport, truck_name: String) -> TruckLobby:
	var truck := TruckScene.instantiate() as TruckLobby
	truck.name = truck_name
	truck.session = session
	# `Input` is global and both trucks can see it, so neither reads the
	# keyboard: the checks below drive them through the debug seam instead.
	truck.debug_input_override = true
	viewport.add_child(truck)
	truck.set_process_unhandled_input(false)
	return truck


func _place(truck: TruckLobby, peer_id: int) -> Vector3:
	return (truck.occupant_pose(peer_id)[0]) as Vector3


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	var host_pair := _make_peer("HostView")
	var guest_pair := _make_peer("GuestView")
	host = host_pair[0]
	guest = guest_pair[0]
	await process_frame

	_check(host.begin_host_room(PORT, "TRUCK", false, "stage_1"),
		"host could not create the truck room")
	_check(guest.begin_join_room("127.0.0.1", PORT, "TRUCK"),
		"guest could not begin joining the truck room")
	var joined := await _until(func() -> bool:
		return guest.phase() == MayoNet.SessionPhase.TRUCK \
			and host.seat_assignments().size() == 2 \
			and guest.seat_assignments().size() == 2
	)
	_check(joined, "two peers did not converge on a truck roster")
	if not joined:
		_finish()
		return

	host_truck = _make_truck(host, host_pair[1], "HostTruck")
	guest_truck = _make_truck(guest, guest_pair[1], "GuestTruck")
	await _wait(4)

	var host_id := host.local_id()
	var guest_id := guest.local_id()
	_check(host_truck.occupant_ids().size() == 2,
		"the host's truck did not build an occupant for each seat")
	_check(guest_truck.occupant_ids().size() == 2,
		"the guest's truck did not build an occupant for each seat")
	if host_truck.occupant_ids().size() != 2 or guest_truck.occupant_ids().size() != 2:
		_finish()
		return

	# -- the guest walks ------------------------------------------------------
	# Forward, from a seat that faces across the aisle, so the move is along the
	# truck's X and well clear of both benches.
	var guest_start := _place(host_truck, guest_id)
	guest_truck.debug_move = Vector2(0.0, -1.0)
	await _wait(30)
	guest_truck.debug_move = Vector2.ZERO
	await _wait(6)
	var guest_on_host := _place(host_truck, guest_id)
	var guest_on_guest := _place(guest_truck, guest_id)
	print("truck: guest walked %.2f m on the host, %.2f m on its own screen" % [
		_flat(guest_on_host, guest_start), _flat(guest_on_guest, guest_start)])
	_check(_flat(guest_on_host, guest_start) > 0.8,
		"a guest holding forward moved only %.2f m on the host"
			% _flat(guest_on_host, guest_start))
	_check(_flat(guest_on_host, guest_on_guest) < AGREEMENT,
		"the two screens put the guest %.2f m apart"
			% _flat(guest_on_host, guest_on_guest))

	# -- the host walks, and the guest sees it --------------------------------
	var host_start := _place(host_truck, host_id)
	host_truck.debug_move = Vector2(0.0, -1.0)
	await _wait(30)
	host_truck.debug_move = Vector2.ZERO
	await _wait(6)
	var host_on_host := _place(host_truck, host_id)
	var host_on_guest := _place(guest_truck, host_id)
	print("truck: host walked %.2f m, guest's copy of the host moved %.2f m" % [
		_flat(host_on_host, host_start), _flat(host_on_guest, host_start)])
	_check(_flat(host_on_host, host_start) > 0.8,
		"the host holding forward moved only %.2f m" % _flat(host_on_host, host_start))
	_check(_flat(host_on_host, host_on_guest) < AGREEMENT,
		"the two screens put the host %.2f m apart" % _flat(host_on_host, host_on_guest))

	# -- the hull holds -------------------------------------------------------
	# Long enough that an occupant at the truck's speed would be a good way
	# outside it if nothing stopped them.
	guest_truck.debug_move = Vector2(0.0, -1.0)
	host_truck.debug_move = Vector2(1.0, -1.0)
	await _wait(180)
	guest_truck.debug_move = Vector2.ZERO
	host_truck.debug_move = Vector2.ZERO
	await _wait(6)
	for peer_id in [host_id, guest_id]:
		var at := _place(host_truck, peer_id)
		print("truck: player %d ended at %.2v" % [peer_id, at])
		# The interior, less the capsule's own radius: the aisle between the
		# two benches, and the cab wall and tailgate at either end.
		_check(absf(at.x) <= 1.95 - TruckLobby.OCCUPANT_RADIUS + 0.05,
			"player %d walked through a bench to x = %.2f" % [peer_id, at.x])
		_check(absf(at.z) <= 4.275 - TruckLobby.OCCUPANT_RADIUS + 0.05,
			"player %d walked out of the truck to z = %.2f" % [peer_id, at.z])
		_check(absf(at.y - TruckLobby.OCCUPANT_HEIGHT * 0.5) < 0.1,
			"player %d left the floor, y = %.2f" % [peer_id, at.y])

	# -- nothing a client sends is trusted ------------------------------------
	var before := _place(host_truck, guest_id)
	var rejected_before: int = host.rejected_packets
	# The guest's truck is stopped for this, so the only packets the host acts
	# on are the hostile ones below.
	guest_truck.set_physics_process(false)
	for _index in 40:
		await physics_frame
		guest._submit_lobby_input.rpc_id(1, Vector2(NAN, INF), NAN)
	await _wait(4)
	var after_nan := _place(host_truck, guest_id)
	var rejected: int = host.rejected_packets - rejected_before
	print("truck: %d NaN packets rejected, guest at %.2v" % [rejected, after_nan])
	# The channel is unreliable by design, so not all forty arrive, and how many
	# do varies run to run -- `probe_network` asks for twenty of its forty and
	# has been seen delivered eighteen. The floor here is what it takes to
	# conclude from rather than what a good run happens to manage: the two
	# checks below it are the ones that measure the rejection.
	_check(rejected >= 10,
		"only %d of the 40 hostile packets reached the host, too few to conclude from"
			% rejected)
	_check(after_nan.is_finite(), "a NaN reached a body the host owns: %v" % after_nan)
	_check(_flat(after_nan, before) < 0.01,
		"the rejected packets still moved the guest %.2f m" % _flat(after_nan, before))

	# A move vector a hundred times longer than a full stick deflection, held
	# long enough that any speed above the walk would have shown up as distance.
	var sprint_start := _place(host_truck, guest_id)
	var frames := 30
	for _index in frames:
		await physics_frame
		guest._submit_lobby_input.rpc_id(1, Vector2(0.0, -100.0), PI * 0.5)
	await _wait(2)
	var travelled := _flat(_place(host_truck, guest_id), sprint_start)
	var ceiling := TruckLobby.WALK_SPEED * float(frames + 4) / 60.0
	print("truck: oversized move vector covered %.2f m, the walk allows %.2f m" % [
		travelled, ceiling])
	_check(travelled <= ceiling,
		"an oversized move vector walked the guest %.2f m, past the %.2f m the keys allow"
			% [travelled, ceiling])
	# And it did move: a check that passes because nothing happened proves
	# nothing about the clamp.
	_check(travelled > 0.3,
		"the oversized vector moved the guest only %.2f m, so the clamp was not tested"
			% travelled)
	guest_truck.set_physics_process(true)

	# -- the truck lets go of the session on the way out ----------------------
	host_truck.queue_free()
	await _wait(2)
	_check(host.lobby_space == null,
		"the truck left a pointer to a freed scene in the session")

	host.leave()
	guest.leave()
	await _wait(2)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("SAUCE_TRUCK_WALK_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
