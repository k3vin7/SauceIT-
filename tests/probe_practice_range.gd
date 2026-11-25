extends SceneTree

# 사격 연습장을 끝에서 끝까지 확인한다(성능 측정 아님).
#   혼자하기
#     * 사무실 사격 연습장의 카운터에서 들어간다. 캐릭터를 고르기 전에는 못 들어간다
#     * 소스 세 가지와 파츠 전부를 값 없이 바꿔 낀다. 파츠마다 실제로 소스가 나간다
#     * 표적은 쓰러지고, 같은 자리에 다시 선다. 플레이어는 다치지 않는다
#     * 사무실로 돌아오면 지도에서 골라 둔 축제가 그대로다
#   같이하기 (127.0.0.1)
#     * 참가자가 청해도 팀 전원이 간다. 참가자의 소스·파츠 선택은 방장을 거쳐 양쪽에 보인다
#     * 참가자가 청해도 팀 전원이 사무실로 돌아온다

const PORT := 24861
const HOST_PICK := 3
const GUEST_PICK := 1

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _until(condition: Callable, frames := 3600) -> bool:
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
	app.save_path_override = "res://tmp/sauce_it_range_%s_%d.cfg" % [view_name, Time.get_ticks_usec()]
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s/App" % view_name))
	viewport.add_child(app)
	return app


func _pick(app: SauceApp, index: int) -> void:
	var select: CanvasLayer = app._character_layer
	if select == null or not is_instance_valid(select):
		failures.push_back("no character select to pick %d on" % index)
		return
	select._select(index)
	select._confirm_pick()


func _press(parent: Node, caption: String) -> void:
	for child in parent.find_children("*", "Button", true, false):
		var button := child as Button
		if button.text == caption and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()
			return
	failures.push_back("no available button: %s" % caption)


func _run() -> void:
	await _solo()
	await _party()
	if failures.is_empty():
		print("SAUCE_PRACTICE_RANGE_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _solo() -> void:
	var app := _make_app("SoloView")
	await process_frame
	_press(app._title_layer, "혼자하기")
	await process_frame
	var office := app.current_space as OfficeLobby
	_check(not office.can_enter_range() and not office.enter_range(),
		"the range opened before a character was picked")
	_pick(app, 2)
	await process_frame
	_check(StageRegistry.has_stage(MayoNet.RANGE_STAGE) \
		and not StageRegistry.available_ids().has(MayoNet.RANGE_STAGE),
		"the range must be a stage that the festival map does not list")
	var chosen := app.session.selected_stage
	# 사선 카운터 앞에 서서 사로를 바라본다.
	var body := office._occupants[1] as CharacterBody3D
	body.position = Vector3(8.4, body.position.y, 15.0)
	office._yaw = -PI * 0.5
	office._apply_local_look()
	for _index in 5:
		await physics_frame
	_check(office.interact_target() == OfficeLobby.Target.RANGE, "the range counter is not something to use")
	_check(office.enter_range(), "the range did not start")
	_check(await _until(func(): return app.flow == SauceApp.Flow.STAGE), "the range never began")
	var world = app.current_space
	_check(world.practice_range and world.gameplay_input_enabled(), "the range is not live")
	_check(world._enemies.size() == PracticeRange.TARGET_ROWS.size(), "the range has the wrong targets")
	for sauce in world.STATION_SAUCES.size():
		world.request_range_sauce(sauce)
		_check(world._local.sauce_kind == world.STATION_SAUCES[sauce] and world._local.sauce > 0.99,
			"sauce %d was not handed over full" % sauce)
	for part in world.SauceParts.CATALOG.size():
		world.request_range_part(part)
		_check(world._local.sauce_part == part, "part %d was not fitted" % part)
	world.request_range_part(world.SauceParts.Part.STANDARD)
	world.open_range_panel()
	_check(world.is_range_panel_open() and world._local.player.frozen, "the equipment panel did not open")
	world.close_range_panel()
	_check(not world.is_range_panel_open() and not world._local.player.frozen, "the equipment panel did not close")

	# 가까운 표적을 기본 줄기로 쓰러뜨린다. 눌렀다 떼기를 되풀이한다(압력 규칙 그대로).
	var first = world._enemies[0]
	for index in 3000:
		world.debug_aim_at(first.global_position)
		world.debug_set_input(Vector2.ZERO, false, index % 90 < 60)
		if world._local.sauce < 0.3:
			world.request_range_sauce(2)
		await physics_frame
		if not first.is_alive():
			break
	world.debug_set_input(Vector2.ZERO, false, false)
	_check(not first.is_alive(), "the stream did not put the nearest target down")
	var count: int = world._enemies.size()
	_check(await _until(func(): return world._enemies.size() > count, 900), "the target did not come back")
	var again = world._enemies[-1]
	_check(again.is_alive() and again.move_speed == 0.0 and again.sight_range == 0.0 \
		and again.global_position.distance_to(first.global_position) < 3.0,
		"the target that came back is not a standing one on the same spot")

	# 파츠마다 쏴 본다: 소스가 나가야 한다.
	var brute = world._enemies[5]
	for part in range(1, world.SauceParts.CATALOG.size()):
		world.request_range_part(part)
		world.request_range_sauce(part % 3)
		for _index in 40:
			await physics_frame
		var before: float = world._local.sauce
		for index in 240:
			world.debug_aim_at(brute.global_position + Vector3.UP * 0.4)
			world.debug_set_input(Vector2.ZERO, false, index % 60 < 20)
			await physics_frame
		world.debug_set_input(Vector2.ZERO, false, false)
		_check(world._local.sauce < before, "part %d let no sauce out" % part)
	for _index in 120:
		await physics_frame
	_check(world._local.player.health >= world._local.player.max_health - 0.01 \
		and world._local.player.state == MayoPlayer.State.NORMAL, "the range hurt the player")

	_check(app.session.request_range_exit(), "could not leave the range")
	_check(await _until(func(): return app.flow == SauceApp.Flow.OFFICE and app.current_space is OfficeLobby),
		"leaving the range did not lead back to the office")
	_check(app.session.selected_stage == chosen, "the festival picked on the map was lost")
	office = app.current_space as OfficeLobby
	_check(await _until(func(): return office.can_enter_range(), 600), "the office is not ready after the range")
	print("solo: office -> range -> sauces, parts, targets -> office OK")


func _party() -> void:
	var host := _make_app("HostView")
	var guest := _make_app("GuestView")
	await process_frame
	_press(host._title_layer, "같이하기")
	host._port_field.text = str(PORT)
	host._code_field.text = "test-code"
	_press(host._party_layer, "방 만들기")
	await process_frame
	_pick(host, HOST_PICK)
	_press(guest._title_layer, "같이하기")
	guest._port_field.text = str(PORT)
	guest._code_field.text = "test-code"
	_press(guest._party_layer, "참여하기")
	_check(await _until(func(): return guest.flow == SauceApp.Flow.OFFICE and guest._character_layer != null),
		"joining did not lead to the office")
	var guest_id := guest.session.local_id()
	var guest_office := guest.current_space as OfficeLobby
	_check(await _until(func(): return host.session.seat_assignments().has(guest_id) \
		and host.session.all_lobby_ready()), "the host never saw the guest's office")
	_check(not guest_office.can_enter_range(), "the range opened with a guest undressed")
	_pick(guest, GUEST_PICK)
	_check(await _until(func(): return guest_office.can_enter_range()), "a dressed party cannot enter the range")
	var chosen := host.session.selected_stage

	# 참가자가 청한다 -> 방장이 일으킨다 -> 둘 다 간다.
	_check(guest_office.enter_range(), "the guest could not ask for the range")
	_check(await _until(func(): return host.flow == SauceApp.Flow.STAGE and guest.flow == SauceApp.Flow.STAGE),
		"the party did not arrive at the range together")
	var host_world = host.current_space
	var guest_world = guest.current_space
	_check(host_world.practice_range and guest_world.practice_range, "somebody is not in the range")
	_check(await _until(func(): return guest_world.gameplay_input_enabled() \
		and host_world._shooters.has(guest_id) and guest_world._shooters.has(guest_id)),
		"the guest has no body in the range")

	# 참가자의 선택은 방장이 받아 모두에게 알린다.
	var mustard: int = host_world.STATION_SAUCES.find(ContaminationGrid.KIND_MUSTARD)
	guest_world.request_range_sauce(mustard)
	_check(await _until(func(): return host_world._shooters[guest_id].sauce_kind == ContaminationGrid.KIND_MUSTARD \
		and guest_world._local.sauce_kind == ContaminationGrid.KIND_MUSTARD, 600),
		"the guest's sauce pick did not reach both sides")
	_check(host_world._local.sauce_kind == ContaminationGrid.KIND_KETCHUP, "the guest's pick changed the host's bottle")
	var cannon: int = host_world.SauceParts.Part.CANNON
	guest_world.request_range_part(cannon)
	_check(await _until(func(): return host_world._shooters[guest_id].sauce_part == cannon \
		and guest_world._local.sauce_part == cannon, 600), "the guest's part pick did not reach both sides")

	# 참가자가 청해도 둘 다 돌아온다.
	_check(guest.session.request_range_exit(), "the guest could not ask to leave the range")
	_check(await _until(func(): return host.flow == SauceApp.Flow.OFFICE and guest.flow == SauceApp.Flow.OFFICE \
		and host.current_space is OfficeLobby and guest.current_space is OfficeLobby),
		"the party did not return to the office together")
	_check(host.session.selected_stage == chosen, "the host lost the festival picked on the map")
	_check(await _until(func(): return guest.session.selected_stage == chosen \
		and host.session.can_start_stage(), 900), "the office is not ready to set out after the range")
	print("party: guest asks -> both in range -> picks replicate -> both back OK")
