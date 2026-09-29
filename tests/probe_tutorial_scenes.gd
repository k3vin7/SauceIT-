extends SceneTree

# Which scenes run the opening sequence, and which do not.
#
# The scale-comparison scenes embed `main.tscn` to get a real street and a real
# player to measure against. That also brought the tutorial with them: run either
# `.command` and the rushers charged the body being measured, the doctor talked
# over the stopwatch, and the floor got painted by something the measurement knew
# nothing about.
#
# **This file deliberately does not touch `MayoTutorial.disabled`.** That flag is
# process-wide and is what the headless probes use; if this file set it, it would
# prove nothing about what happens when somebody double-clicks the `.command`.
# What is under test is the per-world switch stored in the scene file, so the
# scenes are loaded exactly as the `.command` loads them.
#
# What is checked here:
#   * neither scale scene builds a tutorial, and neither grows one over time
#   * no bodies, no captions, no drone and no tutorial spill in those scenes
#   * the scale test's own fixtures still exist: the player, the dummies, the
#     stopwatch and the reset
#   * and a plain `main.tscn` still starts the sequence, which is the thing all
#     of the above must not have broken

const SCALE_SCENES := [
	["res://test_scale_227.tscn", 2.27],
	["res://test_scale_180.tscn", 1.80],
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _wait(frames: int) -> void:
	for _f in frames:
		await process_frame
		await physics_frame


func _run() -> void:
	# The process-wide switch must be off for this whole file, or the scale scenes
	# would be quiet for the wrong reason and `main.tscn` below would not start.
	_check(not MayoTutorial.disabled,
		"this probe must run with the process-wide switch off or it tests nothing")

	for entry in SCALE_SCENES:
		var path: String = entry[0]
		var expected_scale: float = entry[1]
		var packed := load(path) as PackedScene
		_check(packed != null, "%s did not load" % path)
		if packed == null:
			continue
		var scene := packed.instantiate() as ScaleTestBase
		root.add_child(scene)
		await process_frame
		await physics_frame
		# Long enough that the sequence would have introduced itself and placed
		# its opening roster had it been running at all.
		await _wait(420)

		var game = scene.game
		_check(game != null, "%s has no embedded game" % path)
		if game == null:
			continue
		var run_tutorial = game.tutorial()
		print("%s: scale %.2f, tutorial=%s, enemies=%d, player=%s, dummies=%d" % [
			path, expected_scale, str(run_tutorial),
			game.enemy_count(),
			str(scene.player != null and is_instance_valid(scene.player)),
			scene.get_node("EnemyDummies").get_child_count()
				if scene.has_node("EnemyDummies") else -1])

		# --- nothing of the sequence is here ---------------------------------
		_check(run_tutorial == null,
			"%s built a tutorial despite the scene switching it off" % path)
		_check(not game.tutorial_enabled,
			"%s did not carry the scene's tutorial_enabled override" % path)
		# No bodies of its own, and no captions or drone to go with them. The
		# scale scenes place their own dummies; what must not appear is the
		# sequence's roster, which would be walking at the body being measured.
		_check(game.enemy_count() == 0,
			"%s has %d enemies: the sequence placed its roster" % [
				path, game.enemy_count()])
		_check(game.tutorial_spawned().is_empty(),
			"%s recorded tutorial spawns" % path)
		_check(game.get_node_or_null("Tutorial") == null,
			"%s still has a Tutorial node" % path)
		_check(game.get_node_or_null("TutorialDrone") == null,
			"%s has a drone flying in it" % path)
		# And nothing painted the road behind the measurement's back. The scale
		# scenes never fire, so any thickness at all here came from the spill.
		var painted: int = game._floor.grid.painted_cell_count()
		_check(painted == 0,
			"%s has %d painted floor cells: something spilled sauce in it" % [
				path, painted])

		# --- and the measurement's own fixtures are untouched ----------------
		_check(scene.player != null and is_instance_valid(scene.player),
			"%s lost its player" % path)
		_check(is_equal_approx(scene.map_scale, expected_scale),
			"%s came up at scale %.2f rather than %.2f" % [
				path, scene.map_scale, expected_scale])
		_check(scene.has_node("EnemyDummies")
			and scene.get_node("EnemyDummies").get_child_count() > 0,
			"%s built no enemy dummies" % path)
		_check(scene.has_node("HUD/Stopwatch"), "%s lost its stopwatch" % path)
		# The reset is the one behaviour worth exercising rather than looking at:
		# it is what a person uses between runs.
		scene.player.global_position += Vector3(3.0, 0.0, 3.0)
		await physics_frame
		var moved_to: Vector3 = scene.player.global_position
		scene.reset_to_spawn()
		await physics_frame
		print("  reset: %.1v -> %.1v" % [moved_to, scene.player.global_position])
		_check(moved_to.distance_to(scene.player.global_position) > 1.0,
			"%s: reset did not put the player back" % path)

		scene.free()
		await process_frame

	# --- and the plain game still runs it --------------------------------
	# The switch is per world, so turning it off in those two scenes must leave
	# this one alone. Without this the fix above could be "the tutorial never runs".
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await physics_frame
	world.set_process_unhandled_input(false)
	var tutorial: MayoTutorial = world.tutorial()
	_check(world.tutorial_enabled, "main.tscn has the sequence switched off")
	_check(tutorial != null, "main.tscn built no tutorial")
	if tutorial != null:
		# Started, not finished: the opening now waits for somebody to walk onto
		# the light, and nobody is driving this world. What is under test here is
		# that a plain run runs the sequence at all -- `probe_tutorial` is where
		# the whole of it is played through.
		var started := false
		for _f in 1800:
			# The light, not just the stage: it comes up with its own caption a
			# few seconds in, and it is the thing worth confirming reached the
			# world.
			if tutorial.move_target() != Vector3.INF:
				started = true
				break
			await physics_frame
		print("main.tscn: tutorial=%s, started=%s, light at %.1v, objective '%s'" % [
			str(tutorial != null), str(started), tutorial.move_target(),
			tutorial.objective_text()])
		_check(started, "main.tscn did not start the sequence")
		_check(tutorial.move_target() != Vector3.INF,
			"main.tscn started the sequence but lit no spot to walk to")
		_check(world.get_node_or_null("TutorialMoveLight") != null,
			"main.tscn lit no blue light in the world")
	world.free()
	await process_frame

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MAYO_TUTORIAL_SCENES_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
