extends SceneTree

var failures: Array[String] = []
var world

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)

func press(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	world._unhandled_input(event)

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process_unhandled_input(false)
	world.set_physics_process(false)
	world._player.set_physics_process(false)
	world.debug_set_input(Vector2.ZERO, false, false)
	await process_frame
	check(world.local_sauce_kind() == -1, "HUD marks a held sauce before getting a bottle")
	check(not InputMap.has_action("refill_sauce"), "E refill action still exists")
	check(HealthHud.PROMPT_LINES == ["[1]  마요네즈", "[2]  머스타드", "[3]  케찹"],
		"stall menu is not the requested three choices")
	var shooter = world._local
	var expected := [ContaminationGrid.KIND_MAYO, ContaminationGrid.KIND_MUSTARD, ContaminationGrid.KIND_KETCHUP]
	var stations: Array = world.refill_stations()
	for station in stations:
		world._player.global_position = station.position + station.facing * 1.5
		world._player.global_position.y = 1.28
		check(world.local_at_station(), "a stall has no selection prompt")
		for choice in 3:
			shooter.sauce = 0.15
			press(KEY_1 + choice)
			check(shooter.sauce_kind == expected[choice], "number key selected wrong sauce")
			check(is_equal_approx(shooter.sauce, 1.0), "new bottle is not full")
			check(world.local_sauce_kind() == choice, "HUD does not mark selected bottle")
			check(shooter.bottle_pickup_left > 0.0, "bottle pickup animation did not start")
		shooter.sauce = 0.25
		press(KEY_E)
		check(is_equal_approx(shooter.sauce, 0.25), "E still fills the bottle")
	# The same selection also means a fresh bottle, not a no-op or a top-up
	# which retains an empty bottle's catch/trigger state.
	shooter.catch_hold = 0.5
	shooter.catches_in_a_row = 2
	shooter.fire_hold = 0.2
	press(KEY_3)
	check(shooter.sauce == 1.0 and shooter.catch_hold == 0.0 and shooter.fire_hold == 0.0,
		"same-sauce pickup kept the old bottle's state")
	check(shooter.weapon_sway.position.y < -0.1, "fresh bottle did not come up from below")
	shooter.firing = true
	var before: int = shooter.points.size()
	world._advance_strand(shooter, 0.1)
	check(shooter.points.size() == before and shooter.sauce == 1.0,
		"bottle sprays during pickup")
	shooter.firing = false
	world._advance_strand(shooter, 0.3)
	check(shooter.bottle_pickup_left == 0.0 and is_zero_approx(shooter.weapon_sway.position.y),
		"pickup pose did not settle")
	check(not world.refill_for(1, -1) and not world.refill_for(1, 3), "invalid sauce choice accepted")
	world._player.global_position = Vector3(0, 1.28, 0)
	shooter.sauce = 0.25
	press(KEY_1)
	check(shooter.sauce == 0.25 and shooter.sauce_kind == ContaminationGrid.KIND_KETCHUP,
		"number key swaps bottles away from a stall")
	var station: Dictionary = stations.back()
	world._player.global_position = station.position - station.facing * 1.5
	world._player.global_position.y = 1.28
	check(not world.refill_for(1, 0), "bottle selected through the back of a stall")
	if "--capture" in OS.get_cmdline_user_args():
		world._player.global_position = station.position + station.facing * 1.5
		world._player.global_position.y = 1.28
		var look_at: Vector3 = station.position
		look_at.y = 1.7
		world.debug_aim_at(look_at)
		press(KEY_2)
		world._advance_strand(shooter, 0.4)
		shooter.weapon.visible = true
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		picture.save_png("res://reports/bottle_selection_2026_10_04.png")
	print("Checked three choices and disabled E at %d stalls" % stations.size())
	world.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAYO_BOTTLE_SELECTION_OK")
	quit(0 if failures.is_empty() else 1)
