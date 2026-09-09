extends SceneTree

# Slip system checks:
#   * running over painted floor trips the player, walking over it does not
#   * movement and firing are locked out until the player is back up
#   * the fall and stand-up take their configured times
#   * immunity stops an immediate second fall on the same patch
#   * the trip happens on the cell the floor says is painted

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _release_all() -> void:
	for action in ["fire_mayo", "run", "move_forward", "move_backward", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## Paints a straight patch of floor ahead of the player and returns its centre.
func _paint_patch(scene, ahead: float) -> Vector3:
	var start: Vector3 = scene._player.global_position
	var patch := Vector3(start.x, 0.0, start.z - ahead)
	for i in range(-2, 3):
		scene._floor.paint_mayo(patch + Vector3(float(i) * 0.1, 0.0, 0.0))
		scene._floor.paint_mayo(patch + Vector3(0.0, 0.0, float(i) * 0.1))
	return patch


func _reset(scene) -> void:
	_release_all()
	scene._player.state = 0
	scene._player._state_timer = 0.0
	scene._player._immunity_timer = 0.0
	scene._player.velocity = Vector3.ZERO
	scene._player.global_position = Vector3(0.0, 0.64, 3.0)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process_unhandled_input(false)
	scene.debug_set_aim(0.0, 0.0)
	var player: MayoPlayer = scene._player
	print("walk %.1f m/s, run %.1f m/s, fall %.2f s, down %.2f s, stand up %.2f s, immunity %.2f s" % [
		player.walk_speed, player.run_speed, player.fall_duration, player.down_duration,
		player.stand_up_duration, player.slip_immunity_time])

	# --- walking over mayo must not trip ---
	_reset(scene)
	var patch := _paint_patch(scene, 1.2)
	_check(scene._floor.is_mayo_at(patch), "the test patch was not painted")
	Input.action_press("move_forward")
	var walked_over := false
	# A fall lasts about 60 frames, so checking the state only at the end would
	# miss a trip that has already recovered. Watch every frame.
	var fell_while_walking := false
	for _f in 90:
		await physics_frame
		if scene._floor.is_mayo_at(player.global_position):
			walked_over = true
		if player.state != MayoPlayer.State.NORMAL:
			fell_while_walking = true
	_release_all()
	print("walking: crossed the patch=%s, fell at any point=%s" % [
		str(walked_over), str(fell_while_walking)])
	_check(walked_over, "the player never reached the patch while walking")
	_check(not fell_while_walking, "walking over mayo knocked the player down")

	# --- running over the same mayo must trip, on a painted cell ---
	_reset(scene)
	Input.action_press("move_forward")
	Input.action_press("run")
	var trip_position := Vector3.ZERO
	var tripped := false
	for _f in 90:
		await physics_frame
		if not tripped and player.state != MayoPlayer.State.NORMAL:
			tripped = true
			trip_position = player.global_position
			break
	print("running: tripped=%s at %.2v, that cell painted=%s" % [
		str(tripped), trip_position, str(scene._floor.is_mayo_at(trip_position))])
	_check(tripped, "running over mayo did not knock the player down")
	_check(scene._floor.is_mayo_at(trip_position),
		"the player fell on a cell the floor says is clean")

	# --- controls are locked and the timings hold ---
	var start_position: Vector3 = player.global_position
	var fired := false
	var moved := 0.0
	var frames_down := 0
	var flat_frames := 0
	Input.action_press("fire_mayo")
	scene._points.clear()
	while player.is_incapacitated() and frames_down < 300:
		await physics_frame
		frames_down += 1
		moved = maxf(moved, start_position.distance_to(player.global_position))
		if is_equal_approx(player.fall_tilt(), 1.0):
			flat_frames += 1
		# Firing legitimately resumes on the very frame the player stands up, so
		# only count sauce emitted while still down.
		if player.is_incapacitated() and not scene._points.is_empty():
			fired = true
	_release_all()
	var expected := int(round((player.fall_duration + player.down_duration + player.stand_up_duration) * 60.0))
	print("down for %d frames (expected ~%d), flat for %d, moved %.3f m, emitted sauce=%s" % [
		frames_down, expected, flat_frames, moved, str(fired)])
	_check(absi(frames_down - expected) <= 3,
		"down for %d frames, expected about %d" % [frames_down, expected])
	# The capsule must stay flat through the whole lying-down beat.
	_check(flat_frames >= int(round(player.down_duration * 60.0)) - 3,
		"the player was only flat for %d frames, expected at least the %.2f s down beat" % [
			flat_frames, player.down_duration])
	_check(moved < 0.05, "the player moved %.3f m while down" % moved)
	_check(not fired, "the player kept firing while down")

	# --- immunity prevents an instant second fall on the same spot ---
	_check(player.state == MayoPlayer.State.NORMAL, "the player did not get back up")
	_check(not player.can_slip(), "immunity did not start after standing up")
	Input.action_press("move_forward")
	Input.action_press("run")
	var immune_frames := 0
	while not player.can_slip() and immune_frames < 300:
		await physics_frame
		immune_frames += 1
	_release_all()
	print("immune for %d frames (expected ~%d)" % [
		immune_frames, int(round(player.slip_immunity_time * 60.0))])
	_check(absi(immune_frames - int(round(player.slip_immunity_time * 60.0))) <= 2,
		"immunity lasted %d frames, expected about %d" % [
			immune_frames, int(round(player.slip_immunity_time * 60.0))])

	if failures.is_empty():
		print("MAYO_SLIP_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
