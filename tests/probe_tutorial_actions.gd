extends "res://tests/probe_tutorial.gd"

# Small deterministic action fixtures, followed by a real-projectile playthrough.
# The fixtures isolate timing/queue behavior; the playthrough exercises the floor
# pollution which direct damage in the staging probe deliberately does not make.
var _combat_spill_checked := false

func step() -> void:
	await super.step()
	if world != null and _real_sauce_first_fight and not _combat_spill_checked and tutorial.slipped.has(1):
		_combat_spill_checked = true
		check(tutorial.current_line_id() == MayoTutorial.SAY_WALK,
			"real combat-spill fall did not show walking advice")

func action_fixture() -> void:
	await fresh()
	world.set_physics_process(false)
	world._player.set_physics_process(false)
	tutorial.advance(1.0)
	var station: Dictionary = world.refill_stations()[tutorial.station_index()]
	world._player.global_position = station.position + station.facing * 1.5
	world._player.global_position.y = 1.28
	check(world.refill_for(1, 0), "fixture pickup failed")
	tutorial.advance(0.01)
	check(tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT, "pickup waited for dialogue")
	for index in tutorial.fight_enemies:
		var enemy: MayoEnemy = world.enemy_at(index)
		while enemy.is_alive():
			enemy.take_sauce_hit(world._player.global_position)
	world._player.global_position = Vector3(0, 1.28, -4)
	world.debug_aim_at(Vector3(0, 1.28, -50))
	tutorial.advance(0.01)
	tutorial.advance(0.5)
	tutorial.advance(1.0)
	tutorial.advance(1.0)
	await step()
	check(tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES, "missing look lesson")
	for tick in 20:
		tutorial.advance(0.5)
	check(tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES, "waiting completed an action")

func action_cases() -> void:
	await action_fixture()
	world.debug_aim_at(world.enemy_at(tutorial.monster_index).global_position)
	tutorial.advance(0.01)
	check(tutorial.stage == MayoTutorial.Stage.RUN, "looking did not immediately advance")
	check(tutorial.current_line_id() == MayoTutorial.SAY_BEHIND_YOU,
		"looking cut off the look warning")
	# Move outside the authored spill; a fall caused by combat sauce must still
	# teach walking and replace every on-screen sprint instruction.
	world._player.global_position = Vector3(0.0, 1.28, 24.0)
	check(not TutorialCourse.in_spill(world._player.global_position), "slip fixture is in authored spill")
	world._player.state = MayoPlayer.State.DOWN
	tutorial.note_slip(1)
	check(tutorial.slipped.has(1), "combat-spill fall was ignored")
	check(tutorial.current_line_id() == MayoTutorial.SAY_WALK, "fall did not interrupt with walk advice")
	check("Shift를 놓고" in tutorial.objective_text(), "objective still orders sprinting")
	check("걷기" in tutorial.marker_label(), "marker still orders sprinting")
	world._player.state = MayoPlayer.State.NORMAL
	# Simulate another peer still displaying the old refill caption. It must
	# never unlock gameplay locally; only the authority's state does that.
	tutorial._refill_open = false
	tutorial._say_now(MayoTutorial.SAY_GO_REFILL, MayoTutorial.TAG_REFILL)
	check(not tutorial.refill_is_open(), "a caption unlocked refill")
	tutorial._enter(MayoTutorial.Stage.TRAPPED)
	check(tutorial.refill_is_open(), "refill waits for narration")
	var trap_line := tutorial.current_line_id()
	var station: Dictionary = world.refill_stations()[tutorial.station_index()]
	world._player.global_position = station.position + station.facing * 1.5
	world._player.global_position.y = 1.28
	check(world.refill_for(1, 0), "refill during trap dialogue failed")
	check(tutorial.supplied.has(1), "early refill was not counted")
	tutorial.advance(0.01)
	tutorial.advance(0.01)
	check(tutorial.stage == MayoTutorial.Stage.COOP_FIGHT, "refill waited for dialogue to end")
	check(tutorial.current_line_id() == trap_line, "banter was unnecessarily cut")
	world._local.firing = true
	for tick in 30:
		tutorial.advance(0.5)
		check(tutorial.current_line_id() != MayoTutorial.SAY_GO_REFILL, "completed refill instruction played late")
		check(tutorial.current_line_id() != MayoTutorial.SAY_FINISH, "shoot instruction played while firing")
	world.free()
	world = null

	await action_fixture()
	# Starting the escape without turning is also valid, including at a walk.
	world.debug_set_input(Vector2(0, -1), false, false)
	world._read_local_input()
	world._player.frame_movement = Vector3(0, 0, -0.1)
	tutorial.advance(0.01)
	check(tutorial.stage == MayoTutorial.Stage.RUN, "escape forced a look-back")
	check(tutorial.current_line_id() == MayoTutorial.SAY_BEHIND_YOU,
		"moving cut off the look warning")
	var look_left := tutorial._line_left
	for tick in int(floor(look_left / 0.1)):
		tutorial.advance(0.1)
		check(tutorial.current_line_id() == MayoTutorial.SAY_BEHIND_YOU,
			"look warning disappeared before its display time")
	for tick in 10:
		if tutorial.current_line_id() == MayoTutorial.SAY_RUN:
			break
		tutorial.advance(0.1)
	check(tutorial.current_line_id() == MayoTutorial.SAY_RUN, "run warning never followed look warning")
	# Starting to sprint must not hide this caption on the following frame.
	world.debug_set_input(Vector2(0, -1), true, false)
	world._read_local_input()
	for tick in 30:
		tutorial.advance(0.1)
		check(tutorial.current_line_id() == MayoTutorial.SAY_RUN,
			"running cut off the run warning before its display time")
	for tick in 10:
		tutorial.advance(0.1)
	check(tutorial.current_line_id() != MayoTutorial.SAY_RUN, "run warning did not expire naturally")
	world.free()
	world = null

func _run() -> void:
	await action_cases()
	_real_sauce_first_fight = true
	await scenario(true)
	# Whether the live shot happens to leave a deep patch in the route is balance
	# dependent; the deterministic fixture above covers the notification itself.
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAYO_TUTORIAL_ACTIONS_OK")
	quit(0 if failures.is_empty() else 1)
