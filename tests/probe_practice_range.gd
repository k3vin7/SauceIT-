extends SceneTree

# 사무실 안의 사격 연습장을 확인한다(성능 측정 아님). 방 안에서 바로 쏘고, 어디로도 옮겨 가지 않는다.
#   혼자하기
#     * 문을 지나 방에 들어서면 연습장의 몸으로 바뀐다. 사무실은 그대로 사무실이다(Flow.OFFICE)
#     * 앞벽 진열대에서 소스 세 가지를, 뒷벽 선택대에서 파츠 전부를 집는다(E 안내 그대로)
#     * 표적은 쓰러지고 같은 자리에 다시 선다. 플레이어는 다치지 않는다
#     * 문으로 걸어 나오면 사무실의 몸으로 돌아오고, 그 자리에 서 있다
#   같이하기 (127.0.0.1)
#     * 참가자가 방 안을 걷는 모습이 방장의 사무실에 보인다. 방장은 사무실에 그대로 있다
#     * 참가자가 나오면 다시 사무실의 몸으로 걷는다

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


## 사무실의 몸을 홀의 문 앞에 세우고 방 안으로 걸어 들어간다. 참가자의 몸은 방장이 걷게
## 하므로(`TruckLobby.apply_occupant_pose`), 참가자일 때는 방장의 사무실(`authority`)에서도
## 같은 자리에 세운다 -- 참가자 화면에서만 옮기면 방장의 다음 자세가 곧바로 덮어쓴다.
func _walk_in(office: OfficeLobby, authority: OfficeLobby = null) -> bool:
	var id := office._local_id()
	var body := office._occupants[id] as CharacterBody3D
	body.position = Vector3(3.5, body.position.y, 15.0)
	body.velocity = Vector3.ZERO
	if authority != null and authority != office:
		var theirs := authority._occupants[id] as CharacterBody3D
		theirs.position = Vector3(3.5, theirs.position.y, 15.0)
		theirs.velocity = Vector3.ZERO
	office._yaw = -PI * 0.5
	office._apply_local_look()
	office.debug_input_override = true
	office.debug_move = Vector2(0.0, -1.0)
	var entered := false
	for _index in 600:
		await physics_frame
		if office.in_range():
			entered = true
			break
	office.debug_move = Vector2.ZERO
	return entered


## 연습장의 몸을 `at`(바닥)에 세우고 `look`를 보게 한다.
func _stand(world, at: Vector3, look: Vector3) -> void:
	world._local.player.global_position = at + Vector3.UP * MayoPlayer.CAPSULE_HEIGHT * 0.5
	world._local.player.velocity = Vector3.ZERO
	for _index in 4:
		await physics_frame
	world.debug_aim_at(look)
	await physics_frame


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
	_pick(app, 2)
	await process_frame
	var office := app.current_space as OfficeLobby
	var world = office.range_world()
	_check(world != null and await _until(func(): return world.load_complete, 1200),
		"the office has no firing range world")
	_check(not office.in_range() and not world.is_embedded_active(), "the range was live before anyone walked in")
	_check(await _walk_in(office), "walking through the door did not enter the range")
	_check(app.flow == SauceApp.Flow.OFFICE and app.current_space == office, "entering the range left the office")
	_check(world.is_embedded_active() and world.gameplay_input_enabled(), "the range did not take over")
	_check(world._enemies.size() == PracticeRange.TARGET_ROWS.size(), "the range has the wrong targets")
	_check(office.is_occupant_pinned(1), "the office body is not following the range body")

	# 진열대: 병마다 E 안내가 뜨고, 누르면 그 소스로 가득 찬다.
	for sauce in PracticeRange.SAUCE_SPOTS.size():
		var spot: Vector3 = PracticeRange.SAUCE_SPOTS[sauce]
		await _stand(world, Vector3(spot.x, 0.0, spot.z + 1.4), spot)
		# E 안내는 한번 잡은 대상을 0.3초 붙들고 있다(`TomatinaPlaySupport.context_target`).
		# 병은 1 m 간격이라 옆 병의 안내가 아직 남아 있을 수 있다: 그 시간이 지나기를 기다린다.
		var settled := Time.get_ticks_msec() + 400
		while Time.get_ticks_msec() < settled:
			await physics_frame
		var target: Dictionary = world.play_support.context_target(world._local)
		_check(not target.is_empty() and target.kind == "range_sauce" and int(target.id) == sauce,
			"bottle %d on the rack is not something to take" % sauce)
		world._local.sauce = 0.2
		world.perform_context_action(1, "range_sauce", sauce)
		_check(world._local.sauce_kind == world.STATION_SAUCES[sauce] and world._local.sauce > 0.99,
			"sauce %d was not handed over full" % sauce)
	# 선택대: 파츠마다.
	for part in range(world.SauceParts.CATALOG.size() - 1, -1, -1):
		var spot := PracticeRange.part_spot(part)
		await _stand(world, Vector3(spot.x, 0.0, spot.z - 1.4), spot)
		var target: Dictionary = world.play_support.context_target(world._local)
		_check(not target.is_empty() and target.kind == "range_part" and int(target.id) == part,
			"part %d on the table is not something to take" % part)
		world.perform_context_action(1, "range_part", part)
		_check(world._local.sauce_part == part, "part %d was not fitted" % part)

	# 가까운 표적을 기본 줄기로 쓰러뜨린다. 눌렀다 떼기를 되풀이한다(압력 규칙 그대로).
	var first = world._enemies[0]
	await _stand(world, Vector3(PracticeRange.FIRING_X, 0.0, first.global_position.z), first.global_position)
	for index in 3000:
		world.debug_aim_at(first.global_position)
		world.debug_set_input(Vector2.ZERO, false, index % 90 < 60)
		if world._local.sauce < 0.3:
			world.request_range_sauce(2)
		await physics_frame
		if not first.is_alive():
			break
	world.debug_set_input(Vector2.ZERO, false, false)
	world.debug_clear_input_override()
	_check(not first.is_alive(), "the stream did not put the nearest target down")
	var count: int = world._enemies.size()
	_check(await _until(func(): return world._enemies.size() > count, 900), "the target did not come back")
	_check(world._local.player.health >= world._local.player.max_health - 0.01, "the range hurt the player")

	# 문으로 걸어 나온다.
	await _stand(world, Vector3(6.6, 0.0, 15.0), Vector3(0.0, 2.3, 15.0))
	world.debug_set_input(Vector2(0.0, -1.0), false, false)
	_check(await _until(func(): return not office.in_range(), 600), "walking out of the door did not leave the range")
	world.debug_clear_input_override()
	var body := office._occupants[1] as CharacterBody3D
	_check(not world.is_embedded_active() and body.collision_layer == 1 \
		and body.position.x < PracticeRange.ENTER_X and absf(body.position.z - 15.0) < 1.6,
		"the office body is not standing in the doorway after leaving")
	_check(app.flow == SauceApp.Flow.OFFICE, "leaving the range left the office")
	print("solo: walk in -> rack, table, targets -> walk out OK")


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
	_pick(guest, GUEST_PICK)
	var host_office := host.current_space as OfficeLobby
	var guest_office := guest.current_space as OfficeLobby
	_check(await _until(func(): return host.session.can_start_stage() \
		and guest_office._occupants.has(guest_id) and host_office._occupants.has(guest_id)),
		"the party never settled in the office")
	var guest_world = guest_office.range_world()
	_check(await _until(func(): return guest_world.load_complete, 1200), "the guest has no range world")

	# 참가자가 들어간다: 방장의 사무실에는 방 안을 걷는 모습이 간다. 방장은 그대로다.
	_check(await _walk_in(guest_office, host_office), "the guest could not walk into the range")
	_check(guest_world.is_embedded_active() and guest_world._is_authority(),
		"the guest's range is not its own to run")
	await _stand(guest_world, Vector3(14.0, 0.0, 17.0), Vector3(30.0, 1.0, 17.0))
	var seen := host_office._occupants[guest_id] as CharacterBody3D
	_check(await _until(func(): return absf(seen.position.x - 14.0) < 0.3 and absf(seen.position.z - 17.0) < 0.3, 600),
		"the host does not see the guest standing in the range")
	_check(not host_office.in_range() and not host_office.range_world().is_embedded_active(),
		"the guest walking in switched the host's range on")
	guest_world.perform_context_action(1, "range_part", 5)
	_check(guest_world._local.sauce_part == 0, "a part was fitted from across the room")

	# 참가자가 나온다.
	await _stand(guest_world, Vector3(6.6, 0.0, 15.0), Vector3(0.0, 2.3, 15.0))
	guest_world.debug_set_input(Vector2(0.0, -1.0), false, false)
	_check(await _until(func(): return not guest_office.in_range(), 600), "the guest could not walk out")
	guest_world.debug_clear_input_override()
	_check(await _until(func(): return not host_office.is_occupant_pinned(guest_id) \
		and seen.position.x < PracticeRange.ENTER_X, 600), "the host still holds the guest in the range")
	_check(host.session.can_start_stage(), "the office is not ready to set out after the range")
	print("party: guest walks in -> host sees it -> guest walks out OK")
