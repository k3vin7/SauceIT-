extends SceneTree

# The character select, end to end, with two whole apps on 127.0.0.1:
#   * being let into a room -- host or guest -- puts up the select, not the truck
#   * a guest still choosing holds the host's start button shut
#   * the pick dresses the truck occupant on both screens
#   * the same pick is what both screens draw in the stage
#   * coming back from the stage goes straight to the truck, still dressed
#
# Each app sits under its own SubViewport with its own world and its own
# SceneMultiplayer, the way `probe_network` stands two worlds side by side.

const PORT := 24847
const HOST_PICK := 3
const GUEST_PICK := 1

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _until(condition: Callable, frames := 1200) -> bool:
	for _index in frames:
		if condition.call():
			return true
		await process_frame
	return false


func _make_app(view_name: String) -> SauceApp:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	root.add_child(viewport)
	var app := (load("res://app.tscn") as PackedScene).instantiate() as SauceApp
	app.name = "App"
	app.save_path_override = "res://tmp/sauce_it_select_%s_%d.cfg" % [view_name, Time.get_ticks_usec()]
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s/App" % view_name))
	viewport.add_child(app)
	return app


func _select_of(app: SauceApp) -> CanvasLayer:
	var layer: CanvasLayer = app._character_layer
	return layer if layer != null and is_instance_valid(layer) else null


func _run() -> void:
	var host := _make_app("HostView")
	var guest := _make_app("GuestView")
	await process_frame
	host._show_recruitment()
	guest._show_recruitment()
	await process_frame

	# --- the host makes a room: the select, not the truck -------------------
	_check(host.session.begin_host_room(PORT, "", true, "stage_1"), "host could not open a room")
	await process_frame
	_check(_select_of(host) != null, "hosting a room did not put up the character select")
	_check(host.flow == SauceApp.Flow.RECRUITMENT, "the host was put in the truck before picking")
	var host_select := _select_of(host)
	if host_select != null:
		_check(host_select._cards.size() == 4, "the select does not offer four characters")
		host_select._select(HOST_PICK)
		host_select._confirm_pick()
	await process_frame
	await process_frame
	_check(host.flow == SauceApp.Flow.TRUCK_LOBBY, "picking did not lead into the truck")
	_check(_select_of(host) == null, "the select is still up in the truck")
	_check(host.session.character_of(1) == HOST_PICK, "the session did not keep the host's pick")
	var host_truck := host.current_space as TruckLobby
	_check(host_truck != null and int(host_truck._worn.get(1, -1)) == HOST_PICK,
		"the host's truck occupant is not wearing the pick")

	# --- a guest joins: select first, and the host waits for them -----------
	_check(guest.session.begin_join_room("127.0.0.1", PORT, ""), "guest could not begin joining")
	_check(await _until(func(): return _select_of(guest) != null),
		"joining a room did not put up the character select")
	var guest_id := guest.session.local_id()
	_check(await _until(func(): return host.session.seat_assignments().has(guest_id)),
		"the host never seated the guest")
	for _frame in 20:
		await process_frame
	_check(guest.flow == SauceApp.Flow.RECRUITMENT, "the guest was put in the truck before picking")
	_check(not host.session.all_lobby_ready(),
		"the host could start while the guest was still choosing")
	_check(await _until(func(): return guest.session.character_of(1) == HOST_PICK),
		"the guest was not told what the host picked")
	var guest_select := _select_of(guest)
	if guest_select != null:
		_check(String(guest_select._taken[HOST_PICK].text).contains("P1"),
			"the select does not show the host's pick as taken")
		guest_select._select(GUEST_PICK)
		guest_select._confirm_pick()
	_check(await _until(func(): return guest.flow == SauceApp.Flow.TRUCK_LOBBY),
		"the guest's pick did not lead into the truck")
	_check(await _until(func(): return host.session.character_of(guest_id) == GUEST_PICK),
		"the host was not told what the guest picked")
	_check(await _until(func(): return host.session.all_lobby_ready()),
		"the lobby never became ready after the guest picked")
	_check(await _until(func(): return int(host_truck._worn.get(guest_id, -1)) == GUEST_PICK),
		"the host's truck did not re-dress the guest's occupant")
	var guest_truck := guest.current_space as TruckLobby
	_check(guest_truck != null and int(guest_truck._worn.get(guest_id, -1)) == GUEST_PICK
		and int(guest_truck._worn.get(1, -1)) == HOST_PICK,
		"the guest's truck does not show both picks")

	# --- into the stage: the same two characters, on both screens -----------
	_check(host.session.request_stage_start(), "the ready host could not start the stage")
	var playing := await _until(func() -> bool:
		return host.flow == SauceApp.Flow.STAGE and guest.flow == SauceApp.Flow.STAGE, 3600)
	_check(playing, "both apps did not reach the stage")
	if playing:
		for _frame in 30:
			await physics_frame
		for entry in [["host", host], ["guest", guest]]:
			var world = entry[1].current_space
			var as_host = world.shooter_for(1)
			var as_guest = world.shooter_for(guest_id)
			_check(as_host != null and as_host.character_index == HOST_PICK,
				"the %s's stage draws the host as character %d, not %d" % [entry[0],
					as_host.character_index if as_host != null else -1, HOST_PICK])
			_check(as_guest != null and as_guest.character_index == GUEST_PICK,
				"the %s's stage draws the guest as character %d, not %d" % [entry[0],
					as_guest.character_index if as_guest != null else -1, GUEST_PICK])
		print("stage: host wears %d, guest wears %d on both screens" % [
			host.current_space.shooter_for(1).character_index,
			host.current_space.shooter_for(guest_id).character_index])

		# --- and back: straight to the truck, still dressed -----------------
		host.session.finish_stage({"title": "probe"})
		_check(await _until(func(): return guest.flow == SauceApp.Flow.RESULT),
			"the result never reached the guest")
		_check(host.session.return_to_truck(), "the host could not return to the truck")
		_check(await _until(func(): return guest.flow == SauceApp.Flow.TRUCK_LOBBY \
			and host.flow == SauceApp.Flow.TRUCK_LOBBY), "both apps did not return to the truck")
		await process_frame
		_check(_select_of(host) == null and _select_of(guest) == null,
			"returning from a stage asked for a character again")
		host_truck = host.current_space as TruckLobby
		_check(await _until(func(): return host_truck != null \
			and int(host_truck._worn.get(1, -1)) == HOST_PICK \
			and int(host_truck._worn.get(guest_id, -1)) == GUEST_PICK),
			"the truck after the stage lost a pick")

	host.session.leave()
	await process_frame
	for app in [host, guest]:
		DirAccess.remove_absolute(app.save_path_override)
	if failures.is_empty():
		print("SAUCE_CHARACTER_SELECT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
