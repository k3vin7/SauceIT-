extends SceneTree

# Two independent SceneMultiplayer instances exercise the persistent session
# protocol without loading two copies of the expensive combat world. The same
# MayoNet nodes remain alive across truck, loading, stage, result and truck.

const PORT := 24831

var failures: Array[String] = []
var host: MayoNet
var guest: MayoNet


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _until(condition: Callable, frames := 600) -> bool:
	for _index in frames:
		if condition.call():
			return true
		await process_frame
	return false


func _make_peer(view_name: String) -> MayoNet:
	var viewport := SubViewport.new()
	viewport.name = view_name
	root.add_child(viewport)
	var peer_root := Node.new()
	peer_root.name = "PeerRoot"
	viewport.add_child(peer_root)
	var session := MayoNet.new()
	session.name = "Session"
	peer_root.add_child(session)
	var api := SceneMultiplayer.new()
	set_multiplayer(api, peer_root.get_path())
	return session


func _run() -> void:
	host = _make_peer("HostView")
	guest = _make_peer("GuestView")
	await process_frame

	_check(host.begin_host_room(PORT, "FLOW7", false, "stage_1"),
		"host could not create the truck room")
	_check(guest.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"guest could not begin joining the truck room")
	var joined := await _until(func() -> bool:
		return guest.phase() == MayoNet.SessionPhase.TRUCK \
			and host.seat_assignments().size() == 2 \
			and guest.seat_assignments().size() == 2 \
			and host.all_lobby_ready()
	)
	_check(joined, "two peers did not converge on a ready truck roster")
	_check(host.seat_assignments().values().has(0)
		and host.seat_assignments().values().has(1), "first guest did not receive seat 2")
	_check(host.seat_assignments() == guest.seat_assignments(),
		"host and guest disagree on seat assignments")
	_check(not guest.request_stage_start(), "a guest was able to start the stage")

	_check(host.request_stage_start(), "ready host could not begin the stage transition")
	_check(await _until(func(): return guest.phase() == MayoNet.SessionPhase.LOADING),
		"guest did not enter the shared loading phase")
	var transition := host._transition_id
	host.report_world_loaded(transition)
	await process_frame
	_check(host.phase() == MayoNet.SessionPhase.LOADING,
		"host started before the guest reported loaded")
	guest.report_world_loaded(transition)
	var both_playing := await _until(func() -> bool:
		return host.phase() == MayoNet.SessionPhase.STAGE \
			and guest.phase() == MayoNet.SessionPhase.STAGE
	)
	_check(both_playing, "loaded barrier did not authorize both peers together")
	var late := _make_peer("LateView")
	await process_frame
	_check(late.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"late guest could not attempt a connection")
	_check(await _until(func(): return not late.is_online() \
		and late.status() == "session is already in progress"),
		"play-in-progress connection did not return an explicit busy reason")
	print("lobby probe: busy rejection complete")

	host.finish_stage({"title": "festival clear", "remaining": 0})
	var both_result := await _until(func() -> bool:
		return host.phase() == MayoNet.SessionPhase.RESULT \
			and guest.phase() == MayoNet.SessionPhase.RESULT
	)
	_check(both_result, "result phase was not broadcast to every participant")
	_check(not guest.return_to_truck(), "a guest was able to force result exit")
	_check(host.return_to_truck(), "host could not return the party to the truck")
	_check(await _until(func(): return guest.phase() == MayoNet.SessionPhase.TRUCK),
		"guest did not return to the truck with the host")
	guest.report_lobby_initialized()
	_check(await _until(func(): return host.all_lobby_ready()),
		"returned truck did not re-arm the lobby ready barrier")

	var guest_two := _make_peer("GuestTwoView")
	var guest_three := _make_peer("GuestThreeView")
	await process_frame
	_check(guest_two.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"third player could not begin joining")
	_check(await _until(func(): return guest_two.phase() == MayoNet.SessionPhase.TRUCK),
		"third player did not enter the truck")
	_check(guest_three.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"fourth player could not begin joining")
	_check(await _until(func(): return guest_three.phase() == MayoNet.SessionPhase.TRUCK \
		and host.seat_assignments().size() == 4 and host.all_lobby_ready()),
		"four-player roster did not converge")
	_check(host.seat_assignments().values().duplicate().all(
		func(seat): return int(seat) >= 0 and int(seat) < 4),
		"four-player roster assigned an invalid seat")
	_check(late.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"overflow guest could not attempt a connection")
	_check(await _until(func(): return not late.is_online() \
		and late.status() == "room is full"),
		"overflow guest did not receive the explicit room-full reason")
	print("lobby probe: room-full rejection complete")
	guest_two.leave()
	_check(await _until(func(): return host.seat_assignments().size() == 3),
		"third player was not removed from the roster")
	guest_three.leave()
	_check(await _until(func(): return host.seat_assignments().size() == 2),
		"extra guests were not removed from the roster")
	print("lobby probe: extra guests left")

	var old_guest_id := guest.local_id()
	guest.leave()
	_check(await _until(func(): return host.seat_assignments().size() == 1),
		"disconnected guest remained in the fixed roster")
	_check(host.seat_assignments().get(1, -1) == 0,
		"host seat changed after a guest left")
	_check(guest.begin_join_room("127.0.0.1", PORT, "FLOW7"),
		"guest could not reconnect to the same persistent session")
	var rejoined := await _until(func() -> bool:
		return guest.phase() == MayoNet.SessionPhase.TRUCK \
			and host.seat_assignments().size() == 2 \
			and host.all_lobby_ready()
	)
	_check(rejoined, "reconnecting guest did not rejoin the ready truck")
	var new_guest_id := guest.local_id()
	_check(new_guest_id != old_guest_id, "reconnection unexpectedly reused an ENet peer id")
	_check(host.seat_assignments().get(new_guest_id, -1) == 1,
		"released seat was not reused after reconnection")
	print("lobby probe: seat reuse complete")

	host.leave()
	_check(await _until(func(): return not guest.is_online()),
		"guest remained online after the host closed the session")
	_check(guest.status() == "host closed the session",
		"guest did not receive the host-closed reason")

	if failures.is_empty():
		print("SAUCE_LOBBY_FLOW_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
