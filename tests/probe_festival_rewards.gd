extends SceneTree

# 축제 보상(팀 돈·전리품)을 확인한다.
#   * 셈: 완료 40 + 담아 온 토마토 하나당 1(최대 10). 토마토 축제는 한 사람당 2개 이상이면 케찹
#   * 저장: 돈·전리품·완료 횟수가 저장 파일에 남고 다시 읽힌다
#   * 혼자하기: 토마토 축제를 마치면 방장 저장에 더해지고, 사무실 진열장·기록판에 나온다
#   * 같이하기: 방장의 돈과 전리품이 참가자의 사무실에도 보인다
#     godot --headless --path . --script tests/probe_festival_rewards.gd

const PORT := 24861

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


func _make_app(view_name: String, money := 0, trophy := "") -> SauceApp:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	root.add_child(viewport)
	var app := (load("res://app.tscn") as PackedScene).instantiate() as SauceApp
	app.name = "App"
	app.save_path_override = "res://tmp/sauce_it_reward_%s_%d.cfg" % [view_name, Time.get_ticks_usec()]
	if money > 0:
		var store := SauceSaveStore.new(app.save_path_override)
		store.add_reward("stage_2", money, trophy)
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


func _trophy(office: OfficeLobby) -> Node3D:
	return office._room.get_node("TrophyShelf/Trophy_tomato_ketchup") as Node3D


func _run() -> void:
	_rules()
	await _solo()
	await _party()
	if failures.is_empty():
		print("SAUCE_FESTIVAL_REWARDS_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _rules() -> void:
	var none := FestivalRewards.settle("stage_2", 0, 1)
	_check(none.money == 40 and none.trophy == "" and none.needed == 2, "an empty-handed clear is not 40 with no trophy")
	var solo := FestivalRewards.settle("stage_2", 2, 1)
	_check(solo.money == 42 and solo.trophy == "tomato_ketchup", "two tomatoes solo did not earn the ketchup")
	var short := FestivalRewards.settle("stage_2", 7, 4)
	_check(short.money == 47 and short.trophy == "" and short.needed == 8, "seven tomatoes for four earned the ketchup")
	var full := FestivalRewards.settle("stage_2", 16, 4)
	_check(full.money == 50 and full.trophy == "tomato_ketchup", "the bonus is not capped at 50")
	var first := FestivalRewards.settle("stage_1", 9, 2)
	_check(first.money == 49 and first.trophy == "" and first.needed == 0, "stage 1 has a trophy it should not")
	var path := "res://tmp/sauce_it_reward_store_%d.cfg" % Time.get_ticks_usec()
	var store := SauceSaveStore.new(path)
	store.add_reward("stage_2", 42, "tomato_ketchup")
	store.add_reward("stage_2", 45, "tomato_ketchup")
	var again := SauceSaveStore.new(path)
	again.load_data()
	_check(again.money == 87 and again.trophies == PackedStringArray(["tomato_ketchup"]) \
		and int(again.clears.get("stage_2", 0)) == 2, "the reward did not survive a save and load")
	DirAccess.remove_absolute(path)
	print("rules: 40 + tomatoes (max 10), ketchup at 2 per player, saved OK")


func _solo() -> void:
	var app := _make_app("SoloView")
	await process_frame
	app._start_solo()
	await process_frame
	_pick(app, 2)
	await process_frame
	var office := app.current_space as OfficeLobby
	_check(app.session.team_money == 0 and not _trophy(office).visible,
		"a new save starts with money or a trophy")
	office.pick_stage("stage_2")
	office.request_start()
	_check(await _until(func(): return app.flow == SauceApp.Flow.STAGE or app.flow == SauceApp.Flow.LOADING \
		and app._arrival != null and is_instance_valid(app._arrival) and app._arrival.active, 3600),
		"the tomato festival did not load")
	app.session.request_intro_skip()
	_check(await _until(func(): return app.flow == SauceApp.Flow.STAGE, 3600), "the tomato festival did not begin")
	if app._stage_intro_active():
		app._skip_stage_intro()
	for _frame in 20:
		await physics_frame
	var world = app.current_space
	_check(world.carried_tomato_count() == 0, "a fresh player already carries tomatoes")
	var slots: Array = world.item_slots(1)
	slots[1] = 1
	slots[2] = 1
	slots[3] = 1
	_check(world.carried_tomato_count() == 3, "three tomatoes in the slots are not counted as three")
	app._on_stage_cleared()
	_check(await _until(func(): return app.flow == SauceApp.Flow.RESULT), "clearing the festival gave no result")
	var label := app._result_layer.find_child("RewardLabel", true, false) as Label
	_check(label != null and label.text.contains("+43") and label.text.contains("토마토 케찹"),
		"the result does not show the reward: %s" % (label.text if label != null else "no label"))
	_check(app.save_store.money == 43 and app.save_store.trophies.has("tomato_ketchup"),
		"the reward was not saved for the host")
	_check(app.session.request_result_continue(), "the result vote failed")
	_check(await _until(func(): return app.flow == SauceApp.Flow.OFFICE), "did not return to the office")
	await process_frame
	office = app.current_space as OfficeLobby
	var records := office._room.get_node("RecordBoard/Records") as Label3D
	_check(app.session.team_money == 43 and _trophy(office).visible,
		"the office does not show the money or the ketchup after the festival")
	_check(records.text.contains("43") and office._info_label.text.contains("43"),
		"the record board or panel does not show the money")
	print("solo: 3 tomatoes -> +43, ketchup on the shelf OK\n", records.text)
	app._show_title()
	await process_frame
	DirAccess.remove_absolute(app.save_path_override)
	app.get_parent().queue_free()
	await process_frame


func _party() -> void:
	var host := _make_app("HostView", 90, "tomato_ketchup")
	var guest := _make_app("GuestView")
	await process_frame
	_check(host.session.begin_host_room(PORT, "", true, SauceApp.DEFAULT_STAGE), "host could not open a room")
	await process_frame
	_pick(host, 3)
	_check(guest.session.begin_join_room("127.0.0.1", PORT, ""), "guest could not begin joining")
	_check(await _until(func(): return guest.flow == SauceApp.Flow.OFFICE), "the guest did not reach the office")
	_check(await _until(func(): return guest.session.team_money == 90 \
		and guest.session.team_trophies.has("tomato_ketchup")), "the guest was not told the team's money and trophy")
	await process_frame
	var guest_office := guest.current_space as OfficeLobby
	_check(_trophy(guest_office).visible and guest_office._info_label.text.contains("90"),
		"the guest's office does not show the team's money and trophy")
	_check(guest.save_store.money == 0, "the team's money leaked into the guest's own save")
	print("party: guest sees the host's 90 and the ketchup OK")

	# --- 슬롯머신: 누구나 돌리고, 방장이 굴리고, 방장 저장에 남는다 ----------------
	var host_office := host.current_space as OfficeLobby
	_check(host_office._slot_position != Vector3.INF, "the office has no slot machine to walk up to")
	_check(not guest.session.request_slot_spin(91) and not guest.session.request_slot_spin(0),
		"a bet above the team's money or of nothing was accepted")
	host.session.slot_win_chance = 1.0
	guest_office.open_slot()
	guest_office.set_slot_bet(40)
	_check(guest_office.spin_slot(), "the guest could not spin")
	_check(await _until(func(): return guest.session.team_money == 130 and host.session.team_money == 130),
		"a winning 40 did not make 90 into 130 for everyone")
	_check(host.save_store.money == 130 and guest.save_store.money == 0, "the win was not saved for the host only")
	_check(await _until(func(): return not guest_office._slot_waiting and guest_office._slot_message.text.contains("당첨")),
		"the guest's machine never showed the win")
	_check(guest_office._slot_reels[0].text == guest_office._slot_reels[1].text \
		and guest_office._slot_reels[1].text == guest_office._slot_reels[2].text, "a win did not show three of a kind")
	host.session.slot_win_chance = 0.0
	host_office.open_slot()
	host_office.set_slot_bet(9999)
	_check(host_office._slot_bet == 130, "the bet was not capped at the team's money")
	_check(host_office.spin_slot(), "the host could not go all in")
	_check(await _until(func(): return guest.session.team_money == 0 and host.save_store.money == 0),
		"losing it all did not empty the team's money")
	_check(await _until(func(): return not host_office._slot_waiting), "the host's machine never stopped")
	_check(host_office._slot_spin.disabled and not host_office.spin_slot(), "an empty wallet can still spin")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wins := 0
	for _index in 4000:
		var outcome := OfficeSlot.roll(rng)
		var same: bool = outcome.reels[0] == outcome.reels[1] and outcome.reels[1] == outcome.reels[2]
		_check(same == outcome.won, "the reels do not match the outcome")
		wins += int(outcome.won)
	_check(absf(wins / 4000.0 - OfficeSlot.WIN_CHANCE) < 0.03, "the win rate is off: %d / 4000" % wins)
	print("slot: win doubles, loss takes the bet, saved on the host, %.1f%% wins over 4000" % (wins / 40.0))
	host_office.close_slot()
	guest_office.close_slot()
	host._show_title()
	await process_frame
	for app in [host, guest]:
		DirAccess.remove_absolute(app.save_path_override)
		app.get_parent().queue_free()
	await process_frame
