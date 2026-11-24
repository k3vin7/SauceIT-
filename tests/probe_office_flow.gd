extends SceneTree

# 새 시작 흐름을 끝에서 끝까지 확인한다. 앱 세 개를 127.0.0.1에 세운다.
#   혼자하기
#     * 타이틀의 혼자하기 -> 사무실 + 캐릭터 선택, 포트는 열지 않는다
#     * 지도에서 축제를 고르고 출발 -> 도착 연출 -> 플레이 -> 결과 -> 다시 사무실
#   같이하기
#     * 방장/참가자 모두 사무실로 들어온다. 캐릭터는 겹칠 수 없다(방장이 판정)
#     * 축제는 방장만 고른다. 전원이 캐릭터를 골라야 출발할 수 있다
#     * 도착 연출은 방장만 건너뛰고, 전원에게 적용된다
#     * 출발한 방에는 못 들어온다. 사무실로 돌아오면 다시 들어올 수 있다
#     * 난이도 인원은 출발할 때 고정된다 -- 중간에 누가 나가도 그대로다

const PORT := 24853
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


## 방장 쪽 사무실에서 `peer_id`의 몸을 출발 구역에 세운다(방장이 모든 몸의 위치를 정한다).
func _stand_on_zone(office: OfficeLobby, peer_id: int) -> void:
	var body := office._occupants[peer_id] as CharacterBody3D
	var at := office.depart_zone_position() + Vector3(-1.0 if peer_id == 1 else 1.0, 0.0, 0.0)
	body.position = Vector3(at.x, body.position.y, at.z)
	body.velocity = Vector3.ZERO


func _make_app(view_name: String) -> SauceApp:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	root.add_child(viewport)
	var app := (load("res://app.tscn") as PackedScene).instantiate() as SauceApp
	app.name = "App"
	app.save_path_override = "res://tmp/sauce_it_office_%s_%d.cfg" % [view_name, Time.get_ticks_usec()]
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/%s/App" % view_name))
	viewport.add_child(app)
	return app


func _select_of(app: SauceApp) -> CanvasLayer:
	var layer: CanvasLayer = app._character_layer
	return layer if layer != null and is_instance_valid(layer) else null


func _pick(app: SauceApp, index: int) -> void:
	var select := _select_of(app)
	if select == null:
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
		print("SAUCE_OFFICE_FLOW_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _solo() -> void:
	var app := _make_app("SoloView")
	await process_frame
	_check(Engine.max_fps == 120, "the running client needs the fixed 120 FPS cap")
	_check(app.flow == SauceApp.Flow.TITLE, "the app did not open on the title")
	_press(app._title_layer, "혼자하기")
	await process_frame
	_check(app.flow == SauceApp.Flow.OFFICE and app.current_space is OfficeLobby,
		"혼자하기 did not lead to the office")
	_check(not app.session.is_online(), "혼자하기 opened a port")
	_check(_select_of(app) != null, "the office did not ask a new player for a character")
	_check(not app.session.can_start_stage(), "a solo room could start before picking")
	_pick(app, 2)
	await process_frame
	_check(_select_of(app) == null, "the solo pick did not close the select")
	_check(app.session.character_of(1) == 2 and app.session.has_character(1),
		"the solo pick was not kept")
	var office := app.current_space as OfficeLobby
	_check(office._room.find_children("*", "CSGShape3D", true, false).is_empty(),
		"the running office still contains unbaked CSG")
	var floor_node := office._room.get_node("Room/Floor") as MeshInstance3D
	_check(floor_node != null and floor_node.find_children("*", "CollisionShape3D", true, false).size() == 1,
		"the baked office lost its floor collision")
	_check(not office.input_locked, "the office stayed locked after the pick")
	_check(app.session.selected_stage == SauceApp.DEFAULT_STAGE, "a new room has no default festival")
	office.open_map()
	_check(office.is_map_open(), "the office map did not open")
	office.pick_stage("stage_1")
	_check(app.session.selected_stage == "stage_1", "the solo host could not pick a festival")
	_check(office._map_pins["stage_1"].button_pressed and app.session.can_start_stage(),
		"the map does not show the pick or will not start")
	office.close_map()
	# 출발은 구역에 올라서야 일어난다: 지도에는 출발 버튼이 없다.
	for _index in 30:
		await physics_frame
	_check(app.flow == SauceApp.Flow.OFFICE and office.occupants_in_depart_zone() == 0,
		"the solo room left without anyone on the departure zone")
	_stand_on_zone(office, 1)
	_check(await _until(func(): return app._arrival != null and is_instance_valid(app._arrival) \
		and app._arrival.active, 3600), "the arrival shot did not start after loading")
	_check(app.flow == SauceApp.Flow.LOADING, "play began before the arrival shot ended")
	_check(not app.current_space.gameplay_input_enabled(), "input was live during the arrival shot")
	_check(app.session.request_intro_skip(), "the solo player could not skip the arrival shot")
	_check(await _until(func(): return app.flow == SauceApp.Flow.STAGE),
		"skipping the arrival shot did not begin play")
	_check(app.current_space.gameplay_input_enabled(), "input was not handed over after the shot")
	_check(app.current_space.party_size() == 1, "a solo stage is not sized for one")
	_check(app.current_space.shooter_for(1) != null \
		and app.current_space.shooter_for(1).character_index == 2,
		"the solo stage does not wear the pick")
	for _frame in 20:
		await physics_frame
	app.session.finish_stage({"title": "probe"})
	_check(await _until(func(): return app.flow == SauceApp.Flow.RESULT), "no solo result")
	# 다시 하기: 연출은 생략하지 않는다.
	_check(app.session.replay_stage(), "the solo retry did not start")
	_check(await _until(func(): return app._arrival != null and is_instance_valid(app._arrival) \
		and app._arrival.active, 3600), "a retry skipped the arrival shot")
	app.session.request_intro_skip()
	_check(await _until(func(): return app.flow == SauceApp.Flow.STAGE), "the retry did not begin play")
	app.session.finish_stage({"title": "probe"})
	_check(await _until(func(): return app.flow == SauceApp.Flow.RESULT), "no result after the retry")
	_check(app.session.request_result_continue(), "the solo result vote failed")
	_check(await _until(func(): return app.flow == SauceApp.Flow.OFFICE),
		"the solo result did not return to the office")
	await process_frame
	_check(_select_of(app) == null and app.session.character_of(1) == 2,
		"returning to the office lost the solo pick")
	app._show_title()
	await process_frame
	_check(not app.session.lobby_flow, "going to the title left the solo room open")
	DirAccess.remove_absolute(app.save_path_override)
	app.get_parent().queue_free()
	await process_frame
	print("solo: office -> arrival -> stage -> retry -> office OK")


func _party() -> void:
	var host := _make_app("HostView")
	var guest := _make_app("GuestView")
	var late := _make_app("LateView")
	await process_frame

	# --- 방장: 타이틀에서 방을 만든 뒤 사무실에서 캐릭터를 고른다 ----------------
	_press(host._title_layer, "같이하기")
	host._port_field.text = str(PORT)
	host._code_field.text = "test-code"
	_press(host._party_layer, "방 만들기")
	await process_frame
	_check(host.session.is_online() and host.flow == SauceApp.Flow.OFFICE \
		and host._party_layer == null and _select_of(host) != null,
		"making a room did not lead to the office and its select")
	_pick(host, HOST_PICK)
	_check(_select_of(host) == null and host.session.character_of(1) == HOST_PICK,
		"the host's pick did not take")
	_check(host.session.can_start_stage(), "a host alone and dressed cannot start")

	# --- 참가자: 잘못된 코드를 받은 뒤 타이틀에서 다시 접속할 수 있다 -------------
	_press(guest._title_layer, "같이하기")
	guest._port_field.text = str(PORT)
	guest._code_field.text = "wrong-code"
	_press(guest._party_layer, "참여하기")
	_check(await _until(func(): return not guest.session.is_online()), "wrong code was admitted")
	_check(guest._party_layer != null and guest._status_label.text == "입장 코드가 맞지 않습니다.",
		"the failed join lost the panel or did not show the error")
	_press(guest._party_layer, "닫기  (Esc)")
	_check(guest.flow == SauceApp.Flow.TITLE and guest._party_layer == null,
		"closing a failed join did not return to the title menu")
	_press(guest._title_layer, "같이하기")
	guest._port_field.text = str(PORT)
	guest._code_field.text = "test-code"
	_press(guest._party_layer, "참여하기")
	_check(await _until(func(): return guest.flow == SauceApp.Flow.OFFICE and _select_of(guest) != null),
		"joining did not lead to the office and its select")
	var guest_id := guest.session.local_id()
	_check(await _until(func(): return host.session.seat_assignments().has(guest_id) \
		and host.session.all_lobby_ready()), "the host never saw the guest's office come up")
	_check(not host.session.can_start_stage(), "the host could start while the guest was undressed")
	_check(not host.session.request_stage_start(), "the start went through with a guest undressed")
	_check(await _until(func(): return guest.session.character_taken(HOST_PICK, guest_id)),
		"the guest was not told what the host holds")
	var guest_select := _select_of(guest)
	_check(guest_select._cards[HOST_PICK].disabled, "the host's character is not shut on the guest's select")
	_check(guest_select.selected != HOST_PICK, "the guest's select is standing on a taken character")
	_check(not guest.session.choose_character(HOST_PICK), "the guest was allowed to ask for a taken character")
	# 판정은 방장이 한다: 가로질러 온 요청(화면을 거치지 않은 요청)도 거절된다.
	guest.session._choose_character.rpc_id(1, HOST_PICK)
	for _frame in 30:
		await process_frame
	_check(not host.session.has_character(guest_id) and not guest.session.has_character(guest_id),
		"the host gave away a character somebody already holds")
	_check(_select_of(guest) != null, "the select closed on a refused pick")
	_pick(guest, GUEST_PICK)
	_check(await _until(func(): return _select_of(guest) == null), "the guest's pick did not close the select")
	_check(await _until(func(): return host.session.character_of(guest_id) == GUEST_PICK \
		and host.session.has_character(guest_id)), "the host was not told the guest's pick")
	var host_office := host.current_space as OfficeLobby
	var guest_office := guest.current_space as OfficeLobby
	_check(await _until(func(): return int(host_office._worn.get(guest_id, -1)) == GUEST_PICK \
		and int(guest_office._worn.get(1, -1)) == HOST_PICK), "the offices do not show both picks")
	_check(host_office._occupants.size() == 2 and guest_office._occupants.size() == 2,
		"an office is missing a body")

	# --- 축제는 방장이 고른다 -------------------------------------------------
	_check(not guest.session.set_selected_stage("stage_1"), "a guest changed the festival")
	guest_office.open_map()
	_check(guest_office._map_pins["stage_1"].disabled, "the guest's map lets them pick")
	host_office.open_map()
	host_office.pick_stage("stage_1")
	_check(await _until(func(): return guest.session.selected_stage == "stage_1"),
		"the guest was not told the festival")
	_check(guest_office._map_pins["stage_1"].button_pressed, "the guest's map did not follow the host's pick")
	_check(host.session.can_start_stage(), "a dressed party cannot start")

	# --- 출발: 연출, 방장만 건너뛰기, 인원 고정 --------------------------------
	# 한 명만 올라서서는 떠나지 않는다. 둘 다 올라서면 센 뒤 떠난다.
	host_office.close_map()
	guest_office.close_map()
	_stand_on_zone(host_office, 1)
	for _index in int(OfficeLobby.DEPART_COUNTDOWN * 60.0) + 60:
		await physics_frame
	_check(host.flow == SauceApp.Flow.OFFICE and host_office.occupants_in_depart_zone() == 1,
		"the party left with one player off the departure zone")
	_check(await _until(func(): return guest_office.occupants_in_depart_zone() == 1),
		"the guest does not see the host on the departure zone")
	_stand_on_zone(host_office, guest_id)
	_check(await _until(func(): return host_office.depart_countdown < OfficeLobby.DEPART_COUNTDOWN \
		and guest_office.depart_countdown < OfficeLobby.DEPART_COUNTDOWN),
		"the countdown did not start on both screens")
	var arriving := await _until(func() -> bool:
		return host._arrival != null and is_instance_valid(host._arrival) and host._arrival.active \
			and guest._arrival != null and is_instance_valid(guest._arrival) and guest._arrival.active, 3600)
	_check(arriving, "both apps did not reach the arrival shot")
	_check(host._arrival.can_skip and not guest._arrival.can_skip, "the wrong player holds the skip")
	_check(not guest.session.request_intro_skip(), "a guest skipped the arrival shot")
	# 떠난 방에는 못 들어온다.
	_check(late.session.begin_join_room("127.0.0.1", PORT, "test-code"), "the latecomer could not knock")
	_check(await _until(func(): return not late.session.is_online()), "the latecomer was not turned away")
	_check(late.session.status() == "session is already in progress",
		"the latecomer was not told why: '%s'" % late.session.status())
	_check(late.flow == SauceApp.Flow.TITLE, "the latecomer left the title")
	_check(host.session.seat_assignments().size() == 2, "the latecomer took a seat")
	_check(host.flow == SauceApp.Flow.LOADING and guest.flow == SauceApp.Flow.LOADING,
		"play began before the arrival shot ended")
	_check(host.session.request_intro_skip(), "the host could not skip the arrival shot")
	_check(await _until(func(): return host.flow == SauceApp.Flow.STAGE \
		and guest.flow == SauceApp.Flow.STAGE), "the host's skip did not begin play for everybody")
	for _frame in 30:
		await physics_frame
	var world = host.current_space
	_check(world.party_size() == 2 and guest.current_space.party_size() == 2,
		"the stage is not sized for the two who set out")
	_check(world.shooter_for(1).character_index == HOST_PICK \
		and world.shooter_for(guest_id).character_index == GUEST_PICK,
		"the stage does not wear the picks")
	var heavy_before := float(world.heavy_health_for(100.0))
	# 중간 이탈은 무시한다: 인원 기준은 그대로다.
	guest.session.leave()
	_check(await _until(func(): return not host.session.seat_assignments().has(guest_id)),
		"the host never noticed the guest leave")
	for _frame in 20:
		await physics_frame
	_check(world.shooter_for(guest_id) == null, "the leaver's body is still in the stage")
	_check(world.party_size() == 2 and is_equal_approx(float(world.heavy_health_for(100.0)), heavy_before),
		"a player leaving mid-stage changed the difficulty")
	print("party: sized for %d, heavy x%.2f before and after a leaver" % [
		world.party_size(), heavy_before / 100.0])

	# --- 돌아오면 다시 들어올 수 있다 ------------------------------------------
	host.session.finish_stage({"title": "probe"})
	_check(await _until(func(): return host.flow == SauceApp.Flow.RESULT), "no result on the host")
	_check(host.session.request_result_continue(), "the host result vote failed")
	_check(await _until(func(): return host.flow == SauceApp.Flow.OFFICE), "the host did not return to the office")
	await process_frame
	_check(_select_of(host) == null and host.session.character_of(1) == HOST_PICK,
		"the host lost its character on the way back")
	_check(late.session.begin_join_room("127.0.0.1", PORT, "test-code"), "the latecomer could not knock again")
	_check(await _until(func(): return late.flow == SauceApp.Flow.OFFICE),
		"a room back in the office did not take a new player")
	# 방장이 쥔 카드 위에는 설 수 없다: 눌러도 선택이 옮겨 가지 않고, 확정은 남은 것 중 하나다.
	var late_id := late.session.local_id()
	_check(await _until(func(): return late.session.character_taken(HOST_PICK, late_id)),
		"the newcomer was not told what the host holds")
	_pick(late, HOST_PICK)
	_check(await _until(func(): return _select_of(late) == null), "the newcomer's pick did not settle")
	_check(await _until(func(): return host.session.has_character(late_id)),
		"the host never heard the newcomer's pick")
	_check(host.session.character_of(late_id) != HOST_PICK and host.session.character_of(1) == HOST_PICK,
		"the newcomer was given the host's character")

	# --- 방장이 나가면 전원 타이틀 ---------------------------------------------
	host._show_title()
	_check(await _until(func(): return late.flow == SauceApp.Flow.TITLE),
		"the host closing the room did not send the guest to the title")
	await process_frame
	for app in [host, guest, late]:
		DirAccess.remove_absolute(app.save_path_override)
