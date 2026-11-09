extends SceneTree

# Running pace is something the run key gives, and only the run key:
#   * a jump taken at a run crosses its gap at a run
#   * letting go of Shift and holding Space is not a run -- the next hop is
#     pushed off at a walk, so the pace is gone within one landing instead of
#     bleeding off 0.6 m/s a hop for seven seconds
#   * still holding Shift, a chain of hops keeps the run

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _speed(player: MayoPlayer) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _release_all() -> void:
	for action in ["run", "jump", "move_forward"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## Back to the start of the street, on the ground, and up to a full run. Each
## check begins here so none of them is run into the far wall by the last one.
func _run_up(player: MayoPlayer, start: Vector3) -> void:
	_release_all()
	player.velocity = Vector3.ZERO
	player.global_position = start
	for _frame in 20:
		await physics_frame
	Input.action_press("move_forward")
	Input.action_press("run")
	for _frame in 40:
		await physics_frame
	_check(player.is_on_floor() and _speed(player) > player.run_speed - 0.2,
		"the player did not reach a run on the ground (%.2f m/s)" % _speed(player))


func _run() -> void:
	# The Tomatina street: a long straight run from the spawn with nothing in it.
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process_unhandled_input(false)
	scene.debug_set_aim(0.0, 0.0)
	var player: MayoPlayer = scene._player
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		enemy.health = 0.0
		enemy.global_position = Vector3(4000.0, -300.0, 4000.0)
	for _frame in 20:
		await physics_frame
	var start := player.global_position

	await _run_up(player, start)

	# --- Shift held: hops keep the run --------------------------------------
	Input.action_press("jump")
	var slowest := INF
	for _frame in 120:
		await physics_frame
		slowest = minf(slowest, _speed(player))
	print("hopping with Shift held: slowest %.2f m/s" % slowest)
	_check(slowest > player.run_speed - 1.0, "hopping with the run key held lost the run")

	# --- a jump taken at a run, Shift let go in the air: carried to the landing
	await _run_up(player, start)
	Input.action_press("jump")
	for _frame in 3:
		await physics_frame
	Input.action_release("jump")
	Input.action_release("run")
	_check(not player.is_on_floor(), "the jump did not leave the ground")
	var carried := INF
	while not player.is_on_floor():
		carried = minf(carried, _speed(player))
		await physics_frame
	print("run jump with Shift let go in the air: slowest %.2f m/s before landing" % carried)
	_check(carried > player.run_speed - 1.0, "a jump taken at a run did not cross its gap at a run")

	# --- Shift let go, Space held: the run is gone ---------------------------
	await _run_up(player, start)
	Input.action_release("run")
	Input.action_press("jump")
	var running_frames := 0
	for _frame in 300:
		await physics_frame
		if _speed(player) > player.walk_speed + 0.5:
			running_frames += 1
	print("hopping with Shift let go: %d frames (%.2f s) above a walk" % [
		running_frames, float(running_frames) / 60.0])
	# The braking takes a few frames, so it is seen -- which is also what says
	# the player really was running when the key came up -- and then it is over.
	_check(running_frames > 0, "the player was not running when the run key was let go")
	_check(running_frames <= 30,
		"running pace survived %.2f s of hopping with the run key up" % (float(running_frames) / 60.0))
	_release_all()

	if failures.is_empty():
		print("RUN_CARRY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
