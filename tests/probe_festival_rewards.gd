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
	var rich := FestivalRewards.settle("stage_2", 2, 1, 23)
	_check(rich.money == 65 and rich.coins == 23, "leftover coins are not added to the settlement")
	_check(TomatinaVictims.coins_for(0.0) == 10 and TomatinaVictims.coins_for(0.049) == 10 \
		and TomatinaVictims.coins_for(0.051) == 1 and TomatinaVictims.coins_for(0.24) == 2 \
		and TomatinaVictims.coins_for(0.5) == 3 and TomatinaVictims.coins_for(0.999) == 5,
		"a searched body does not pay 1-5 at 19% each and 10 at 5%")
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
	_pick(guest, 1)
	_check(await _until(func(): return guest._character_layer == null), "the guest's character pick was not confirmed")
	_check(await _until(func(): return guest.session.team_money == 90 \
		and guest.session.team_trophies.has("tomato_ketchup")), "the guest was not told the team's money and trophy")
	await process_frame
	var guest_office := guest.current_space as OfficeLobby
	_check(_trophy(guest_office).visible and guest_office._info_label.text.contains("90"),
		"the guest's office does not show the team's money and trophy")
	_check(guest.save_store.money == 0, "the team's money leaked into the guest's own save")
	print("party: guest sees the host's 90 and the ketchup OK")
	# --- 디버그 모드: 방장이 켠 방에서만, 그 방의 누구나 팀 돈을 더한다 ------------------
	_check(not guest.session.debug_active() and not guest.session.request_debug_money(100),
		"debug money worked with debug mode off")
	_check(not guest.session.set_debug_mode(true) and not host.session.debug_active(),
		"a guest switched the room's debug mode on")
	_check(host.session.set_debug_mode(true), "the host could not switch debug mode on")
	_check(await _until(func(): return guest.session.debug_active()), "the guest was not told debug mode is on")
	_check(guest.session.request_debug_money(100), "the guest could not ask for debug money")
	_check(await _until(func(): return guest.session.team_money == 190), "debug money did not add 100")
	_check(host.save_store.money == 190, "the debug money was not saved")
	host.session.set_debug_mode(false)
	_check(await _until(func(): return not guest.session.debug_active()), "the guest was not told debug mode is off")
	host.session.set_team_progress(90, host.session.team_trophies, host.session.team_clears)
	host.save_store.set_money(90)
	_check(await _until(func(): return guest.session.team_money == 90), "could not put the money back for the next checks")

	# --- 슬롯머신: 누구나 돌리고, 방장이 굴리고, 방장 저장에 남는다 ----------------
	var host_office := host.current_space as OfficeLobby
	_check(host_office._slot_position != Vector3.INF, "the office has no slot machine to walk up to")
	_check(not guest.session.request_slot_spin(91) and not guest.session.request_slot_spin(0),
		"a bet above the team's money or of nothing was accepted")
	host.session.slot_pick_override = 0.0          # 0.5%: 7 7 7, 10배
	# 한 번에 한 명: 자리는 방장이 내주고, 앉은 사람만 돌린다.
	_check(not host.session.request_slot_spin(10), "a spin with nobody at the machine was accepted")
	guest_office.open_slot()
	_check(await _until(func(): return guest_office.is_slot_open()), "the guest was not given the machine")
	_check(host.session.slot_user == guest.session.local_id(), "the host does not know who is at the machine")
	host_office.open_slot()
	_check(not host_office.is_slot_open() and not host.session.request_slot_spin(10),
		"a second player got on the machine while it was in use")
	guest_office.set_slot_bet(40)
	_check(guest_office.spin_slot(), "the guest could not spin")
	_check(await _until(func(): return guest.session.team_money == 450 and host.session.team_money == 450),
		"a 10x on 40 did not make 90 into 450 for everyone")
	_check(host.save_store.money == 450 and guest.save_store.money == 0, "the win was not saved for the host only")
	_check(await _until(func(): return not guest_office._slot_waiting and guest_office._slot_message.text.contains("당첨")),
		"the guest's machine never showed the win")
	_check(guest_office._slot_reels[0].symbol == OfficeSlot.GOLDEN and guest_office._slot_reels[1].symbol == OfficeSlot.GOLDEN \
		and guest_office._slot_reels[2].symbol == OfficeSlot.GOLDEN, "the 10x did not show three golden bottles")
	guest_office.close_slot()
	_check(await _until(func(): return host.session.slot_user == 0), "closing the machine did not free it")
	host_office.open_slot()
	_check(host_office.is_slot_open() and await _until(func(): return guest.session.slot_user == 1),
		"the host could not take the freed machine")
	guest_office.open_slot()
	_check(not guest_office.is_slot_open() and not guest_office._slot_seat_wanted,
		"the guest asked for a machine it knew was taken")
	host.session.slot_pick_override = 0.01         # 1%: 같은 소스 셋, 4배
	host_office.set_slot_bet(50)
	_check(host_office.spin_slot(), "the host could not spin")
	_check(await _until(func(): return guest.session.team_money == 600), "a 4x on 50 did not add 150")
	_check(await _until(func(): return not host_office._slot_waiting), "the host's machine never stopped")
	host.session.slot_pick_override = 0.03         # 4%: 7 둘, 2배
	_check(host_office.spin_slot(), "the host could not spin for the 2x")
	_check(await _until(func(): return guest.session.team_money == 650), "a 2x on 50 did not add 50")
	_check(await _until(func(): return not host_office._slot_waiting), "the host's machine never stopped")
	host.session.slot_pick_override = 0.2          # 33%: 같은 소스 둘, 1.1배
	_check(host_office.spin_slot(), "the host could not spin again")
	_check(await _until(func(): return guest.session.team_money == 655), "a 1.1x on 50 did not add 5")
	_check(await _until(func(): return not host_office._slot_waiting and host_office._slot_message.text.contains("+5")),
		"a 1.1x did not read as a small win")
	host_office.set_slot_bet(4)
	_check(host_office.spin_slot(), "the host could not spin a small bet")
	_check(await _until(func(): return not host_office._slot_waiting and host_office._slot_message.text.contains("본전")),
		"a 1.1x on 4 did not read as breaking even")
	_check(host.session.team_money == 655, "a 1.1x on 4 changed the money")
	host.session.slot_pick_override = 0.9          # 61.5%: 전부 다름, 꽝
	host_office.set_slot_bet(9999)
	_check(host_office._slot_bet == 655, "the bet was not capped at the team's money")
	_check(host_office.spin_slot(), "the host could not go all in")
	_check(await _until(func(): return guest.session.team_money == 0 and host.save_store.money == 0),
		"losing it all did not empty the team's money")
	_check(await _until(func(): return not host_office._slot_waiting), "the host's machine never stopped")
	_check(host_office._slot_spin.disabled and not host_office.spin_slot(), "an empty wallet can still spin")
	# 잭팟: 꽝으로 잃은 돈의 20%가 쌓이고, 황금 셋이 10배에 더해 통째로 가져간다.
	_check(host.session.team_jackpot == 131 and host.save_store.jackpot == 131,
		"losing 655 did not put 131 in the jackpot: %d" % host.session.team_jackpot)
	_check(await _until(func(): return guest.session.team_jackpot == 131), "the guest was not told the jackpot")
	_check((host_office._room.get_node("SlotMachine/Label") as Label3D).text.contains("131"),
		"the machine's sign does not show the jackpot")
	_check(host.session.add_team_money(100), "could not add money for the jackpot check")
	host.session.slot_pick_override = 0.0
	host_office.set_slot_bet(10)
	_check(host_office.spin_slot(), "the host could not spin for the jackpot")
	_check(host_office._slot_shown_money == 100 and host.session.team_money == 321,
		"the screen showed the winnings before the reels stopped, or 10x + 131 on 10 was not 321")
	_check(await _until(func(): return not host_office._slot_waiting), "the jackpot spin never stopped")
	_check(host_office._slot_banner.visible and host_office._slot_banner.text.contains("131") \
		and host_office._slot_message.text.contains("잭팟 131"), "the jackpot was not celebrated")
	_check(await _until(func(): return host_office._slot_shown_money == 321), "the money did not count up to 321")
	_check(host.session.team_jackpot == 0 and host.save_store.jackpot == 0 and host.save_store.money == 321,
		"the jackpot was not emptied and saved")
	# --- workbench: anyone unlocks a part with the team's money, the host keeps it ---
	host_office.close_slot()
	var parts_script := preload("res://scripts/tomatina_sauce_parts.gd")
	_check(host.session.team_parts == 1 and not guest.session.request_part_unlock(0) 		and not guest.session.request_part_unlock(99), "the basic nozzle or a part that does not exist can be unlocked")
	guest_office.open_bench()
	_check(guest_office.is_bench_open() and guest_office._bench_buttons.size() == parts_script.CATALOG.size() - 1,
		"the workbench does not list every part but the basic one")
	_check(guest_office.unlock_part(parts_script.Part.FAN), "the guest could not ask for an unlock")
	_check(await _until(func(): return guest.session.team_parts == 3 and host.session.team_parts == 3 		and guest.session.team_money == 221), "unlocking the 3-way nozzle did not cost 100 for everyone")
	_check(host.save_store.parts == 3 and host.save_store.money == 221, "the unlock was not saved for the host")
	_check(guest_office._bench_buttons[0].disabled and guest_office._bench_buttons[0].text.contains("해금됨"),
		"the workbench does not show the part as unlocked")
	_check(not host.session.request_part_unlock(parts_script.Part.FAN), "a part was unlocked twice")
	_check(host.session.request_part_unlock(parts_script.Part.SNIPER) and host.session.team_money == 101 		and not host.session.request_part_unlock(parts_script.Part.CANNON), "120 was not charged, or a part was sold for less than it costs")
	var reread := SauceSaveStore.new(host.save_store.path)
	reread.load_data()
	_check(reread.parts == host.session.team_parts, "the unlocked parts did not survive a save and load")
	guest_office.close_bench()
	# --- shower booth: the curtain and the water are everybody's ---
	_check(guest_office._curtain != null and guest_office._shower_water != null, "the booth has no curtain or shower head to use")
	guest_office.toggle_prop(OfficeLobby.PROP_CURTAIN)
	host_office.toggle_prop(OfficeLobby.PROP_SHOWER)
	_check(await _until(func(): return host.session.office_props == 3 and guest.session.office_props == 3),
		"the curtain and the shower were not shared")
	_check(await _until(func(): return host_office._curtain.transform.is_equal_approx(host_office._curtain_closed)) 		and host_office._shower_water.emitting and guest_office._shower_water.emitting,
		"the curtain did not close or the water did not run")
	guest_office.toggle_prop(OfficeLobby.PROP_SHOWER)
	_check(await _until(func(): return not host_office._shower_water.emitting), "the shower could not be turned off")
	_check(await _until(func(): return guest_office._slot_announce.visible \
		and guest_office._slot_announce.text.contains("잭팟")), "the guest was not told about the jackpot win")
	_check(OfficeSlot.tier_of(PackedInt32Array([3, 3, 3])) == 4 and OfficeSlot.tier_of(PackedInt32Array([1, 1, 1])) == 3 \
		and OfficeSlot.tier_of(PackedInt32Array([3, 0, 3])) == 2 and OfficeSlot.tier_of(PackedInt32Array([2, 2, 0])) == 1 \
		and OfficeSlot.tier_of(PackedInt32Array([0, 1, 2])) == 0, "the tiers are read wrong off the reels")
	_check(OfficeSlot.stop_times(PackedInt32Array([1, 1, 0]))[2] > OfficeSlot.stop_times(PackedInt32Array([1, 0, 1]))[2],
		"two matching reels do not hold the third one back")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	var returned := 0
	for _index in 200000:
		var outcome := OfficeSlot.roll(rng)
		var reels: PackedInt32Array = outcome.reels
		var sevens := int(reels[0] == 3) + int(reels[1] == 3) + int(reels[2] == 3)
		var same := int(reels[0] == reels[1]) + int(reels[1] == reels[2]) + int(reels[0] == reels[2])
		var shown := 0.0
		if same == 3:
			shown = 10.0 if sevens == 3 else 4.0
		elif same == 1:
			shown = 2.0 if sevens == 2 else 1.1
		_check(shown == outcome.multiplier, "the reels %s do not match a %.0fx" % [reels, outcome.multiplier])
		counts[outcome.multiplier] = int(counts.get(outcome.multiplier, 0)) + 1
		returned += 100 + OfficeSlot.gain_for(100, outcome.multiplier)
	var summary: Array[String] = []
	for payout in OfficeSlot.PAYOUTS:
		var rate := int(counts.get(payout[1], 0)) / 200000.0
		_check(absf(rate - payout[0]) < maxf(payout[0] * 0.15, 0.004), "the %.1fx rate is off: %.3f%%" % [payout[1], rate * 100.0])
		summary.push_back("%.1fx %.2f%%" % [payout[1], rate * 100.0])
	_check(OfficeSlot.gain_for(40, 10.0) == 360 and OfficeSlot.gain_for(7, 0.0) == -7 and OfficeSlot.gain_for(10, 1.1) == 1 \
		and OfficeSlot.gain_for(4, 1.1) == 0,
		"the payout sums are off")
	print("slot over 200000: %s, returned %.1f%% of the bets" % [", ".join(summary), returned / 200000.0])
	host_office.close_slot()
	guest_office.close_slot()
	host._show_title()
	await process_frame
	for app in [host, guest]:
		DirAccess.remove_absolute(app.save_path_override)
		app.get_parent().queue_free()
	await process_frame
