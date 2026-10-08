extends "res://tests/probe_tutorial.gd"

# Branches not covered by the ordinary sprint/walk playthrough: delayed input,
# an early kill, and repeated/truncated network snapshots.
func _run() -> void:
	await fresh()
	if await start_fight():
		var hp: float = world._player.health
		for frame in 1000:
			await step()
		check(tutorial.stage == MayoTutorial.Stage.RUN, "waiting falsely completed escape")
		check(not tutorial.monster_trapped, "heavy trapped before reaching the wreck")
		check(world._player.health == hp, "slow reader was killed during the escape prompt")
		check(await walk(TutorialCourse.EXIT, true), "delayed escape cannot cross the passage")
		check(await until(func(): return tutorial.monster_trapped), "delayed heavy never trapped")
		check(await until(func(): return tutorial.refill_is_open()), "delayed escape has no refill")
		check(tutorial.current_line_id() != MayoTutorial.SAY_RUN, "stale run order survived trapping")
		var snapshot := tutorial.state()
		var said := tutorial.lines_shown
		for frame in 10:
			tutorial.apply_state(snapshot)
		check(tutorial.lines_shown == said, "snapshot replayed dialogue")
		var broken := snapshot.duplicate()
		broken.resize(broken.size() - 1)
		tutorial.apply_state(broken)
		check(tutorial.state() == snapshot, "partial snapshot changed state")
	world.free()
	world = null
	await fresh()
	if await start_fight():
		var monster: MayoEnemy = world.enemy_at(tutorial.monster_index)
		while monster.is_alive():
			monster.take_sauce_hit(world._player.global_position)
		check(await until(func(): return tutorial.refill_is_open()), "early kill stranded the refill lesson")
		check(not tutorial.monster_trapped, "dead monster falsely marked trapped")
	world.free()
	world = null
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAYO_TUTORIAL_STORY_OK")
	quit(0 if failures.is_empty() else 1)
