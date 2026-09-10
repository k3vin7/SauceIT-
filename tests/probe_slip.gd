extends SceneTree

# Slip system checks:
#   * running over painted floor trips the player, walking over it does not
#   * a slip starts with a stumble, not the fall itself
#   * movement and firing are locked out until the player is back up
#   * the fall and stand-up take their configured times
#   * with no grace period, holding run on mayo puts you straight back down,
#     while letting go of it makes the same patch harmless
#   * the trip happens on the cell the floor says is painted
#   * slipping again inside the recovery window pitches the player forward,
#     with no stumble, and the capsule and view go over the other way

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
	scene._player.velocity = Vector3.ZERO
	scene._player.fall_direction = 1.0
	scene._player._recovery_timer = 0.0
	scene._player.global_position = Vector3(0.0, 0.64, 3.0)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process_unhandled_input(false)
	scene.debug_set_aim(0.0, 0.0)
	var player: MayoPlayer = scene._player
	print("walk %.1f m/s, run %.1f m/s, fall %.2f s, down %.2f s, stand up %.2f s" % [
		player.walk_speed, player.run_speed, player.fall_duration, player.down_duration,
		player.stand_up_duration])

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

	# --- the player skids forward, uncontrolled, and the timings hold ---
	var start_position: Vector3 = player.global_position
	var slide_direction: Vector3 = player.velocity
	slide_direction.y = 0.0
	_check(slide_direction.length() > 0.1, "the player had no speed left to skid with")
	slide_direction = slide_direction.normalized()
	# Fight the slide: input must not steer or stop it. The forward/run keys from
	# the run-up have to be let go first, or the two inputs cancel and the check
	# passes without ever pushing against the skid.
	_release_all()
	Input.action_press("move_backward")
	var fired := false
	var moved := 0.0
	var frames_down := 0
	var flat_frames := 0
	var resting_speed := 0.0
	var body_pitch := 0.0
	var view_up := -2.0
	var body_behind := -2.0
	var third_person_up := 2.0
	var stumble_frames := 0
	var stumble_body_sway := 0.0
	var stumble_camera_shake := 0.0
	var stumble_tilt := 0.0
	var stumbled_first := player.state == MayoPlayer.State.STUMBLE
	var locked_through_stumble := true
	Input.action_press("fire_mayo")
	scene._points.clear()
	while player.is_incapacitated() and frames_down < 300:
		await physics_frame
		frames_down += 1
		moved = maxf(moved, start_position.distance_to(player.global_position))
		if is_equal_approx(player.fall_tilt(), 1.0):
			# Flat out: the capsule must have gone over backwards and the view
			# with it, so the player ends up looking up off their back.
			body_pitch = scene._body_mesh.rotation.x
			# Local +Z is behind the player, and the capsule's own up axis must
			# have swung there.
			body_behind = (scene._body_mesh.global_basis.y).dot(scene._player.global_basis.z)
			view_up = (-scene._camera.global_basis.z).y
			# The shoulder camera stays upright so the fall can be watched.
			scene.set_first_person(false)
			await process_frame
			third_person_up = (-scene._camera.global_basis.z).y
			scene.set_first_person(true)
			await process_frame
		if player.state == MayoPlayer.State.STUMBLE:
			stumble_frames += 1
			stumble_body_sway = maxf(stumble_body_sway, absf(scene._body_mesh.rotation.z))
			# A level aim keeps the camera's right vector horizontal, so any Y on
			# it is the shake rolling the view.
			stumble_camera_shake = maxf(stumble_camera_shake, absf(scene._camera.global_basis.x.y))
			stumble_tilt = maxf(stumble_tilt, player.fall_tilt())
			locked_through_stumble = locked_through_stumble and player.is_incapacitated()
		if player.state == MayoPlayer.State.STANDING_UP:
			resting_speed = maxf(resting_speed, Vector3(player.velocity.x, 0.0, player.velocity.z).length())
		if is_equal_approx(player.fall_tilt(), 1.0):
			flat_frames += 1
		# Firing legitimately resumes on the very frame the player stands up, so
		# only count sauce emitted while still down.
		if player.is_incapacitated() and not scene._points.is_empty():
			fired = true
	_release_all()
	var expected := int(round((player.stumble_duration + player.fall_duration
		+ player.down_duration + player.stand_up_duration) * 60.0))
	var slide: Vector3 = player.global_position - start_position
	slide.y = 0.0
	print("down for %d frames (expected ~%d), flat for %d, skidded %.3f m, %.1f deg off travel, speed left %.3f m/s, emitted sauce=%s" % [
		frames_down, expected, flat_frames, slide.length(),
		rad_to_deg(slide.normalized().angle_to(slide_direction)) if slide.length() > 0.001 else 0.0,
		resting_speed, str(fired)])
	_check(absi(frames_down - expected) <= 4,
		"down for %d frames, expected about %d" % [frames_down, expected])
	var stumble_expected := int(round(player.stumble_duration * 60.0))
	print("stumble: %d frames (expected ~%d), first=%s, locked=%s, capsule swayed %.1f deg, view shake %.3f, tilt %.2f" % [
		stumble_frames, stumble_expected, str(stumbled_first), str(locked_through_stumble),
		rad_to_deg(stumble_body_sway), stumble_camera_shake, stumble_tilt])
	_check(stumbled_first, "the player went straight to falling without stumbling first")
	_check(absi(stumble_frames - stumble_expected) <= 2,
		"stumbled for %d frames, expected about %d" % [stumble_frames, stumble_expected])
	_check(locked_through_stumble, "controls were still live during the stumble")
	_check(stumble_body_sway > deg_to_rad(scene.stumble_body_roll_degrees * 0.5),
		"the capsule only swayed %.1f deg while stumbling" % rad_to_deg(stumble_body_sway))
	_check(stumble_camera_shake > 0.02,
		"the view barely shook while stumbling (%.3f)" % stumble_camera_shake)
	_check(stumble_tilt < 0.01,
		"the capsule was already tipping over during the stumble (tilt %.2f)" % stumble_tilt)
	# The capsule must stay flat through the whole lying-down beat.
	_check(flat_frames >= int(round(player.down_duration * 60.0)) - 3,
		"the player was only flat for %d frames, expected at least the %.2f s down beat" % [
			flat_frames, player.down_duration])
	# The skid must happen, must follow the direction of travel rather than the
	# input fighting it, and must be over before the player gets up.
	_check(slide.length() > 0.1, "the player did not skid at all, they stopped dead" )
	_check(slide.length() < 3.0, "the player skidded %.3f m, far past a slight slide" % slide.length())
	_check(slide.normalized().dot(slide_direction) > 0.95,
		"the skid went %.1f deg off the direction of travel, so input steered it" % rad_to_deg(slide.normalized().angle_to(slide_direction)))
	_check(resting_speed < 0.01,
		"the player was still moving at %.3f m/s by the time they stood up" % resting_speed)
	print("flat out: capsule pitched %.1f deg, its top %.2f toward the player's back, first-person view up %.2f, shoulder view up %.2f" % [
		rad_to_deg(body_pitch), body_behind, view_up, third_person_up])
	_check(body_pitch > deg_to_rad(80.0),
		"the capsule only pitched %.1f deg, so it did not lie down" % rad_to_deg(body_pitch))
	_check(body_behind > 0.9,
		"the capsule went over the wrong way: its top ended %.2f toward the player's back" % body_behind)
	_check(view_up > 0.5,
		"the view ended pointing %.2f up, so the player is not looking up off their back" % view_up)
	_check(absf(third_person_up) < 0.35,
		"the shoulder camera tilted to %.2f with the fall instead of staying upright" % third_person_up)
	_check(not fired, "the player kept firing while down")

	# --- slipping again straight after standing up pitches you forward ---
	_reset(scene)
	var forward_patch := _paint_patch(scene, 1.2)
	_check(scene._floor.is_mayo_at(forward_patch), "the second-fall patch was not painted")
	Input.action_press("move_forward")
	Input.action_press("run")
	# First fall: backwards, with a stumble, as always.
	for _f in 120:
		await physics_frame
		if player.state != MayoPlayer.State.NORMAL:
			break
	_check(player.state == MayoPlayer.State.STUMBLE,
		"the first fall skipped the stumble")
	_check(player.fall_direction > 0.0,
		"the first fall went forwards (direction %.1f)" % player.fall_direction)
	# Ride it out with the keys still held, so the player is sprinting again the
	# instant they are upright -- which is the case this covers.
	for _f in 300:
		await physics_frame
		if not player.is_incapacitated():
			break
	# The skid carries the player past the first patch, so paint the ground they
	# stood up on: they are sprinting again the instant they are upright.
	_paint_patch(scene, 0.0)
	_check(scene._floor.is_mayo_at(player.global_position),
		"the player did not stand up on painted floor, so this case tests nothing")
	var second_stumbled := false
	var second_fall := false
	for _f in 10:
		await physics_frame
		if player.state == MayoPlayer.State.STUMBLE:
			second_stumbled = true
		if player.state == MayoPlayer.State.FALLING:
			second_fall = true
			break
	# Let go now the fall is under way: still sprinting on the patch would just
	# put the player straight back down and never end this loop.
	_release_all()
	var forward_pitch := 0.0
	var forward_body_ahead := 0.0
	var forward_view_down := 0.0
	for _f in 300:
		await physics_frame
		if not player.is_incapacitated():
			break
		if is_equal_approx(player.fall_tilt(), 1.0):
			forward_pitch = scene._body_mesh.rotation.x
			# Local -Z is ahead of the player: the capsule's up axis must have
			# swung out in front instead of behind.
			forward_body_ahead = (scene._body_mesh.global_basis.y).dot(-scene._player.global_basis.z)
			forward_view_down = (-scene._camera.global_basis.z).y
	_release_all()
	print("second fall: happened=%s, stumbled=%s, direction %.1f, capsule pitched %.1f deg, top %.2f ahead, view up %.2f" % [
		str(second_fall), str(second_stumbled), player.fall_direction,
		rad_to_deg(forward_pitch), forward_body_ahead, forward_view_down])
	_check(second_fall, "sprinting straight after standing up did not knock the player down again")
	_check(not second_stumbled,
		"the second fall stumbled first instead of pitching straight forward")
	_check(forward_pitch < deg_to_rad(-80.0),
		"the capsule pitched %.1f deg, so it did not go over forwards" % rad_to_deg(forward_pitch))
	_check(forward_body_ahead > 0.9,
		"the capsule went over the wrong way: its top ended %.2f ahead of the player" % forward_body_ahead)
	_check(forward_view_down < -0.5,
		"the view ended pointing %.2f up, so the player is not face down" % forward_view_down)
	# Standing up clears the direction, so the next fall is a backwards one again.
	_check(player.fall_direction > 0.0,
		"the fall direction stayed forward after standing up (%.1f)" % player.fall_direction)

	# --- no grace period: keep sprinting on mayo and you go straight back down,
	# but let go of the run key and you are fine ---
	_check(player.state == MayoPlayer.State.NORMAL, "the player did not get back up")
	_reset(scene)
	_paint_patch(scene, 0.0)
	_check(scene._floor.is_mayo_at(player.global_position),
		"the player is not standing on painted floor, so this case tests nothing")

	Input.action_press("move_forward")
	Input.action_press("run")
	# Count entries into FALLING, not the incapacitated edge: the player is back
	# on their feet for less than a frame before going down again, so a
	# not-incapacitated frame is never observed.
	var falls := 0
	var upright_frames := 0
	var was_falling := false
	var loop_start: Vector3 = player.global_position
	for _frame in 400:
		await physics_frame
		var falling_now := player.state == MayoPlayer.State.FALLING
		if falling_now and not was_falling:
			falls += 1
		was_falling = falling_now
		if player.state == MayoPlayer.State.NORMAL:
			upright_frames += 1
		if falls >= 3:
			break
	var travelled: Vector3 = player.global_position - loop_start
	travelled.y = 0.0
	print("still holding run on mayo: fell %d times, upright for %d frames in between, moved %.3f m total" % [
		falls, upright_frames, travelled.length()])
	_check(falls >= 3, "the player only fell %d times while sprinting on mayo" % falls)
	_check(upright_frames <= 2,
		"the player stayed on their feet for %d frames, so something is granting a grace period" % upright_frames)
	# With no run-up there is no speed to skid with, so sprinting cannot carry
	# the player out of a patch: they are pinned until they let go of the key.
	_check(travelled.length() < 0.3,
		"the player sprinted %.3f m out of the patch instead of being pinned" % travelled.length())

	# Let go of run and the same patch is harmless.
	_release_all()
	scene._player.state = 0
	scene._player._state_timer = 0.0
	Input.action_press("move_forward")
	var fell_walking := false
	for _f in 90:
		await physics_frame
		if player.is_incapacitated():
			fell_walking = true
	_release_all()
	print("same patch, walking: fell=%s" % str(fell_walking))
	_check(not fell_walking, "walking over the patch still knocked the player down")

	if failures.is_empty():
		print("MAYO_SLIP_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
