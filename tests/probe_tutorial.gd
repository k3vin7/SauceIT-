extends SceneTree

# End-to-end standalone tutorial story. All traversal uses player movement, initial/refill
# interactions use the real station reach check. Damage is injected only once
# toast bodies are in bottle range so the test is about staging, not aim.
var failures: Array[String] = []
var world
var tutorial: MayoTutorial
var seen_lines: Array[int] = []
var seen_stages: Array[int] = []
var _capture := false
var _real_sauce_first_fight := false

func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.push_back(message)

func step() -> void:
	await physics_frame
	await process_frame
	if world == null:
		return
	check(not world._player.frozen, "player controls were frozen")
	check(tutorial.allows_looking(), "camera was locked")
	if not seen_stages.has(tutorial.stage):
		seen_stages.push_back(tutorial.stage)
		print("STAGE ", MayoTutorial.Stage.keys()[tutorial.stage], " player=", world._player.global_position)
	var line := tutorial.current_line_id()
	if line >= 0 and not seen_lines.has(line):
		seen_lines.push_back(line)
		print("LINE ", tutorial.current_speaker(), ": ", tutorial.current_line())
		if line <= MayoTutorial.SAY_HOLD_STILL:
			check(tutorial.current_speaker() == "뚱보", "opening attributed to doctor")

func until(condition: Callable, frames := 1800) -> bool:
	for frame in frames:
		if condition.call():
			return true
		await step()
	return false

func walk(at: Vector3, run := false, frames := 1500) -> bool:
	for frame in frames:
		var pos: Vector3 = world._player.global_position
		if Vector2(pos.x - at.x, pos.z - at.z).length() < 0.3:
			world.debug_set_input(Vector2.ZERO, false, false)
			return true
		world.debug_aim_at(Vector3(at.x, pos.y, at.z))
		world.debug_set_input(Vector2(0, -1), run and tutorial.slipped.is_empty(), false)
		await step()
	world.debug_set_input(Vector2.ZERO, false, false)
	return false

func shot(label: String) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	picture.save_png("res://reports/tutorial_flow_%s.png" % label)

func fresh() -> void:
	world = load("res://tutorial_world.tscn").instantiate()
	root.add_child(world)
	world.set_process_unhandled_input(false)
	tutorial = world.tutorial()
	seen_lines.clear()
	seen_stages.clear()
	world.debug_set_input(Vector2.ZERO, false, false)
	await step()

func start_fight() -> bool:
	check(world._local.sauce == 0.0, "started with sauce before pickup")
	check(not tutorial.has_bottle(1), "started with a bottle")
	await until(func(): return tutorial.stage == MayoTutorial.Stage.GET_SAUCE)
	for frame in 300:
		await step()
	check(world.enemy_count() == 0, "toast spawned without pickup")
	await shot("01_pickup")
	var station: Dictionary = world.refill_stations()[tutorial.station_index()]
	var approach: Vector3 = station.position + station.facing * 1.5
	check(await walk(approach), "cannot walk to the starting counter")
	check(world.refill_for(1, 0), "mayo selection cannot collect initial bottle")
	check(tutorial.has_bottle(1), "pickup did not grant a bottle")
	if not await until(func(): return tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT):
		check(false, "no first fight after pickup")
		return false
	for index in tutorial.fight_enemies:
		check(world.enemy_at(index).position.z > TutorialCourse.CENTRE_Z + TutorialCourse.DEPTH * 0.5,
			"toast spawned beyond the tutorial fight area")
	check(await walk(Vector3(0, 0, -4)), "cannot return to the street")
	world.debug_aim_at(Vector3(0, world._player.global_position.y, -50))
	var crossed := {}
	for frame in 2400:
		var living := 0
		for index in tutorial.fight_enemies:
			var enemy: MayoEnemy = world.enemy_at(index)
			if not enemy.is_alive():
				continue
			living += 1
			if enemy.position.z > TutorialCourse.CENTRE_Z + TutorialCourse.DEPTH * 0.5:
				crossed[index] = true
			if enemy.global_position.distance_to(world._player.global_position) < world.stream_range:
				if _real_sauce_first_fight:
					world.debug_aim_at(enemy.global_position)
					world.debug_set_input(Vector2.ZERO, false, true)
					break
				# Leave a visible hit frame to exercise the reaction line.
				enemy.take_sauce_hit(world._player.global_position)
				await step()
				while enemy.is_alive():
					enemy.take_sauce_hit(world._player.global_position)
		if living == 0:
			break
		await step()
	world.debug_set_input(Vector2.ZERO, false, false)
	check(crossed.size() == tutorial.fight_enemies.size(), "toasts failed to walk through narrow passage")
	if not await until(func(): return tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES):
		check(false, "no monster warning after toasts")
		return false
	# Waiting does not pretend that the player turned around. Looking at the
	# actual threat moves the lesson forward without waiting out the caption.
	for frame in 300:
		await step()
	check(tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES, "time alone completed look lesson")
	world.debug_aim_at(world.enemy_at(tutorial.monster_index).global_position)
	if not await until(func(): return tutorial.stage == MayoTutorial.Stage.RUN):
		check(false, "no run stage after toasts")
		return false
	check(tutorial.stomps_heard == 2, "expected two heavy footsteps")
	check(seen_lines.has(MayoTutorial.SAY_BEHIND_YOU), "doctor warning missing")
	check(await until(func(): return tutorial.current_line_id() == MayoTutorial.SAY_RUN),
		"run instruction did not follow the look warning")
	return true

func scenario(run: bool) -> void:
	await fresh()
	if not await start_fight():
		world.free()
		world = null
		return
	await shot("02_run")
	var escaped := await walk(TutorialCourse.EXIT, run)
	var escape_monster: MayoEnemy = world.enemy_at(tutorial.monster_index)
	check(escaped, "cannot cross escape passage: player=%s state=%s monster=%s" % [
		str(world._player.global_position), str(world._player.state),
		str(escape_monster.global_position if escape_monster != null else Vector3.INF)])
	if not await until(func(): return tutorial.monster_trapped):
		check(false, "monster never wedged")
		world.free()
		world = null
		return
	var monster: MayoEnemy = world.enemy_at(tutorial.monster_index)
	print("TRAP monster=", monster.global_position, " radius=", monster.radius,
		" player=", world._player.global_position, " slips=", tutorial.slipped)
	check(monster.tutorial_trapped, "enemy movement was not pinned")
	check(tutorial.impacts_heard == 1, "collision cue did not fire exactly once")
	check(tutorial.slipped.has(1) == run, "walk/run slip outcome differs from lesson")
	check(world.get_node_or_null("TutorialDrone") == null, "drone still exists")
	var pinned: Vector3 = monster.global_position
	var hp: float = world._player.health
	# Even inside its old contact reach, being pinned must suppress damage and shove.
	for frame in 180:
		await step()
	check(monster.global_position.distance_to(pinned) < 0.05, "trapped heavy moved")
	check(world._player.health == hp, "trapped heavy still damages player")
	world.debug_aim_at(monster.global_position)
	await shot("03_trapped")
	check(await until(func(): return tutorial.refill_is_open()), "fresh-bottle selection did not open")
	check(tutorial.current_line_id() != MayoTutorial.SAY_RUN, "stale run instruction after escape")
	var station: Dictionary = world.refill_stations()[tutorial.station_index()]
	check(station.position.z < TutorialCourse.SPILL_BACK, "refill is on wrong side")
	var approach: Vector3 = station.position + station.facing * 1.5
	# Stay clear of the booth row until aligned with its front.
	check(await walk(Vector3(0, 0, approach.z)), "cannot reach refill street")
	check(await walk(approach), "cannot reach refill counter")
	check(world.refill_for(1, 0), "cannot select a fresh mayo bottle at objective")
	check(tutorial.supplied.has(1), "early refill during dialogue was ignored")
	check(await until(func(): return tutorial.stage == MayoTutorial.Stage.COOP_FIGHT), "no final fight")
	check(await walk(Vector3(0, 0, approach.z)), "cannot leave refill counter")
	check(await walk(Vector3(0, 0, TutorialCourse.CENTRE_Z - 1.4)), "cannot approach pinned monster")
	world.debug_aim_at(monster.global_position)
	world.debug_set_input(Vector2.ZERO, false, true)
	check(await until(func(): return not monster.is_alive(), 1800), "real sauce stream cannot hit pinned monster")
	world.debug_set_input(Vector2.ZERO, false, false)
	check(await until(func(): return tutorial.is_complete(), 3000), "outro never completed")
	for line in [MayoTutorial.SAY_RECRUIT, MayoTutorial.SAY_NOT_EATEN, MayoTutorial.SAY_LETS_GO]:
		check(seen_lines.has(line), "missing closing dialogue %d" % line)
	world.free()
	world = null
	await process_frame

func _run() -> void:
	await scenario(true)
	await scenario(false)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAYO_TUTORIAL_OK")
	quit(0 if failures.is_empty() else 1)
