extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
func run() -> void:
	create_timer(25.0).timeout.connect(func(): push_error("BOT_PROBE_TIMEOUT"); quit(2))
	var world = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(world)
	var team = preload("res://scripts/player_bot_team.gd").new()
	world.add_child(team)
	team.configure(world, false)
	check(world.party_size() == 4, "team does not contain four players")
	check(not world.debug_input_override, "human leader input was overridden")
	check(team.brains.size() == 4, "missing bot brains")
	for peer in team.brains:
		if team.brains[peer].slot > 0:
			check(world.shooter_for(peer).player.use_injected_input, "teammate input is not injected")
	var bot = world.shooter_for(9001)
	var brain: Dictionary = team.brains[9001]
	var before: Vector3 = bot.player.global_position
	for index in 8:
		await physics_frame
	check(bot.player.global_position.distance_to(before) < 5.0, "bot teleported")
	team.autoplay = true
	for index in 8:
		await physics_frame
	check(world.debug_input_override, "autoplay leader did not get normal input")
	check(team.report().players.size() == 4, "report does not contain four players")
	# Reproduce the route bookkeeping error from the actual observation log.
	var saved: Vector3 = world._local.player.global_position
	world._local.player.global_position = Vector3(15.14, 1.28, 495.71)
	team.route_index = 2
	team._advance_route()
	check(team.route_index > 2 and team.route_index <= 6, "leader backtracks to a waypoint already passed in combat")
	world._local.player.global_position = saved
	world.set_menu_input_enabled(false)
	await physics_frame
	check(not bot.firing and bot.player.input_move == Vector2.ZERO, "bot continued input in pause")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PLAYER_BOTS_OK")
	quit(0 if failures.is_empty() else 1)
