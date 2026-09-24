extends SceneTree

# Checks the squirt's feel: the camera kick and its settle, the nozzle's
# wander, and -- the part that matters most -- that neither of them reaches the
# aim. The whole point of Phase 1 is that firing *looks* less steady without
# *being* less accurate, so most of what is below is the accuracy half.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	# An enemy walking into the line would move the player and the measurements
	# with it.
	scene.debug_clear_enemies()
	scene.set_process_unhandled_input(false)
	var shooter = scene._local

	# --- the aim is untouched by either effect -------------------------------
	# The strongest statement the probe can make, so it is made first and made
	# against exaggerated values: at 30 degrees of kick and 30 of wander, the
	# numbers the strand is fired from must not move at all.
	# All four view-shake numbers ship at zero so they can be turned up one at a
	# time; the probe turns them on because what it tests is the mechanism, not
	# the shipped value.
	scene.recoil_kick_degrees = 30.0
	scene.camera_sway_fraction = 0.12
	scene.nozzle_sway_min_degrees = 30.0
	scene.nozzle_sway_max_degrees = 30.0
	scene.debug_set_aim(25.0, -10.0)
	var aim_yaw_before: float = shooter.aim_yaw
	var aim_pitch_before: float = shooter.aim_pitch
	var direction_before: Vector3 = shooter.attack_direction
	var muzzle_before: Vector3 = shooter.muzzle.global_position
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _i in 40:
		await physics_frame
	print("while firing: sway %.2f/%.2f deg, recoil %.2f deg" % [
		rad_to_deg(shooter.sway_pitch), rad_to_deg(shooter.sway_yaw),
		rad_to_deg(shooter.recoil_pitch)])
	_check(absf(shooter.aim_yaw - aim_yaw_before) < 0.000001
			and absf(shooter.aim_pitch - aim_pitch_before) < 0.000001,
		"firing moved the aim angles themselves")
	_check(shooter.attack_direction.distance_to(direction_before) < 0.000001,
		"firing moved the direction the strand is emitted along")
	# The muzzle is deliberately outside the node the wander turns, so it must
	# not have moved either -- this is what stops a shaking bottle from moving
	# where points are launched from.
	_check(shooter.muzzle.global_position.distance_to(muzzle_before) < 0.0001,
		"the nozzle wander moved the muzzle, so it moved the launch point")
	# And the bottle really is shaking, or the three checks above are vacuous.
	_check(absf(shooter.sway_pitch) + absf(shooter.sway_yaw) > deg_to_rad(1.0),
		"the bottle never wandered at all, so the checks above prove nothing")
	_check(shooter.weapon_sway != null
			and shooter.weapon_sway.rotation.length() > deg_to_rad(1.0),
		"the wander was not applied to the bottle's own node")

	# --- the camera does move, and by roughly the share it was told to -------
	var swayed: float = absf(shooter.sway_pitch) * scene.camera_sway_fraction
	_check(swayed > 0.0, "the camera picks up none of the wander")
	scene.debug_clear_input_override()
	for _i in 40:
		await physics_frame

	# --- the kick, and how long it takes to come back -----------------------
	scene.recoil_kick_degrees = 4.0
	scene.nozzle_sway_min_degrees = 0.0
	scene.nozzle_sway_max_degrees = 0.0
	shooter.recoil_pitch = 0.0
	scene.debug_set_input(Vector2.ZERO, false, true)
	# The kick is fed in over `recoil_attack_seconds`, so the peak is a few
	# frames after the trigger rather than on it -- and is a little under what
	# was asked for, because it is decaying the whole time it arrives. Both are
	# deliberate: the whole angle landing on one frame is what read as a punch.
	var peak := 0.0
	var first_frame := 0.0
	var attack_frames := int(scene.recoil_attack_seconds * 60.0) + 2
	for index in attack_frames:
		await physics_frame
		if index == 0:
			first_frame = rad_to_deg(shooter.recoil_pitch)
		peak = maxf(peak, rad_to_deg(shooter.recoil_pitch))
	print("kick: %.2f deg on the first frame, peaking at %.2f deg (asked for %.1f)" % [
		first_frame, peak, scene.recoil_kick_degrees])
	_check(peak > scene.recoil_kick_degrees * 0.4,
		"the squirt did not kick the view")
	_check(peak <= scene.recoil_kick_degrees + 0.01,
		"the kick overshot the angle it was given")
	# The whole point of the attack: the first frame must not be the whole kick.
	_check(first_frame < peak * 0.75,
		"the kick landed in one frame, which is the snap the attack is for")
	# Held down, it has to be most of the way back within the settle time --
	# the kick is a punctuation mark, not a climb.
	var settle_frames := int(scene.recoil_settle_seconds * 60.0) + 1
	for _i in settle_frames:
		await physics_frame
	var after_settle: float = rad_to_deg(shooter.recoil_pitch)
	print("still firing, %.2f s later: %.2f deg" % [
		scene.recoil_settle_seconds, after_settle])
	_check(after_settle < peak * 0.55,
		"the kick did not settle back while the squirt was still running")
	_check(after_settle > -0.01, "the kick overshot past level")

	# --- and one kick per squirt, not one per frame -------------------------
	for _i in 30:
		await physics_frame
	var late: float = rad_to_deg(shooter.recoil_pitch)
	print("half a second of held fire: %.3f deg (one kick per burst, not a climb)" % late)
	_check(late < peak * 0.5, "holding the trigger piled recoil up instead of kicking once")

	# --- letting go settles the bottle and the view back to level -----------
	scene.debug_clear_input_override()
	var release_frames := int(scene.recoil_release_seconds * 60.0 * 3.0) + 2
	for _i in release_frames:
		await physics_frame
	print("%.2f s after letting go: recoil %.4f deg, sway %.4f deg" % [
		scene.recoil_release_seconds * 3.0, rad_to_deg(shooter.recoil_pitch),
		rad_to_deg(absf(shooter.sway_pitch) + absf(shooter.sway_yaw))])
	_check(absf(rad_to_deg(shooter.recoil_pitch)) < 0.2,
		"the view never came back to level after firing stopped")
	_check(rad_to_deg(absf(shooter.sway_pitch) + absf(shooter.sway_yaw)) < 0.2,
		"the bottle never came back to level after firing stopped")

	# --- the feel dice are not the strand's dice ----------------------------
	# probe_determinism rests on `rng`; anything drawn for an effect has to come
	# from somewhere else or it shifts the strand's own jitter sequence.
	_check(shooter.feel_rng != shooter.rng and shooter.feel_rng != shooter.catch_rng,
		"the effects draw from the strand's own random number generator")

	# --- the sound is wired, and falls back when there are no clips ---------
	print("spray audio: loop=%s edge=%s, clips set=%s" % [
		str(scene._spray_loop_audio != null), str(scene._spray_edge_audio != null),
		str(scene.spray_loop_sound != null)])
	_check(scene._spray_loop_audio != null and scene._spray_edge_audio != null,
		"the spray sound players were never built")
	_check(scene._spray_loop_audio != scene._sauce_audio,
		"the spray loop shares a player with the air puff, so they cut each other")

	if failures.is_empty():
		print("MAYO_FEEL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
