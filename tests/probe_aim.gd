extends SceneTree

# Checks the mouse-look aim path: accumulation, pitch clamping, that the strand
# leaves along the camera forward axis in both camera modes, and that the
# emission jitter axes survive near-vertical aim.

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

	# --- input wiring: F1 toggles the camera mode, motion drives the aim ---
	# Driven by calling the handler directly so the check does not depend on a
	# display server, then switched off so a real mouse cannot drift the aim
	# underneath the geometry assertions below.
	var was_first_person: bool = scene._first_person
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_F1
	toggle.pressed = true
	scene._unhandled_input(toggle)
	_check(scene._first_person != was_first_person, "F1 did not toggle the camera mode")
	scene._unhandled_input(toggle)
	_check(scene._first_person == was_first_person, "F1 did not toggle the camera mode back")
	scene.set_process_unhandled_input(false)

	# --- mouse-look accumulation and pitch clamp ---
	scene.debug_set_aim(0.0, 0.0)
	scene.apply_look(Vector2(100.0, 0.0))
	var expected_yaw := -deg_to_rad(100.0 * scene.mouse_sensitivity)
	_check(absf(scene._aim_yaw - expected_yaw) < 0.0001,
		"yaw did not accumulate from relative mouse motion")
	scene.debug_set_aim(0.0, 0.0)
	for _i in 200:
		scene.apply_look(Vector2(0.0, -100.0))
	var limit := deg_to_rad(scene.pitch_limit_degrees)
	_check(absf(scene._aim_pitch - limit) < 0.0001, "pitch was not clamped looking up")
	for _i in 400:
		scene.apply_look(Vector2(0.0, 100.0))
	_check(absf(scene._aim_pitch + limit) < 0.0001, "pitch was not clamped looking down")

	# --- attack direction is the camera forward, in both modes ---
	for pitch in [0.0, 45.0, -45.0, 85.0, -85.0]:
		for first_person in [true, false]:
			scene.set_first_person(first_person)
			scene.debug_set_aim(37.0, pitch)
			await physics_frame
			var forward: Vector3 = -scene._camera.global_basis.z
			_check(scene._attack_direction.distance_to(forward) < 0.001,
				"attack direction diverged from camera forward at pitch %.0f (fp=%s)" % [pitch, str(first_person)])
			_check(absf(scene._attack_direction.y - sin(deg_to_rad(pitch))) < 0.001,
				"vertical aim not applied at pitch %.0f" % pitch)

	# --- camera placement per mode ---
	scene.debug_set_aim(0.0, 0.0)
	scene.set_first_person(true)
	await physics_frame
	var eye: Vector3 = scene._player.global_position + Vector3.UP * scene.eye_height
	_check(scene._camera.global_position.distance_to(eye) < 0.001, "first-person camera is not at eye height")
	_check(not scene._body_mesh.visible, "player body is visible in first person")
	scene.set_first_person(false)
	await physics_frame
	var offset: Vector3 = scene._camera.global_position - eye
	_check(scene._body_mesh.visible, "player body is hidden in third person")
	_check(absf(offset.z - scene.shoulder_distance) < 0.001, "shoulder camera is not behind the player")
	_check(absf(offset.x - scene.shoulder_offset_right) < 0.001, "shoulder camera has no lateral offset")
	_check(offset.length() < 3.0, "shoulder camera is a distant top-down camera, not over the shoulder")

	# --- emission jitter must not collapse near vertical ---
	for pitch in [0.0, 85.0, -85.0]:
		scene.debug_set_aim(0.0, pitch)
		await physics_frame
		var directions: Array[Vector3] = []
		var laterals: Array[float] = []
		scene._points.clear()
		for _i in 400:
			scene._emit_point()
		var muzzle: Vector3 = scene._muzzle.global_position
		for point in scene._points:
			directions.push_back(point.launch_direction)
			# Distance of the spawn point from the aim axis through the muzzle.
			var to_point: Vector3 = point.position - muzzle
			laterals.push_back((to_point - scene._attack_direction * to_point.dot(scene._attack_direction)).length())
		var max_angle := 0.0
		for d in directions:
			max_angle = maxf(max_angle, rad_to_deg(d.angle_to(scene._attack_direction)))
		var max_lateral := 0.0
		for l in laterals:
			max_lateral = maxf(max_lateral, l)
		print("pitch=%+5.0f  max_fan_angle=%.3f deg (jitter=%.3f)  max_lateral_offset=%.4f m (jitter=%.4f)" % [
			pitch, max_angle, rad_to_deg(scene.yaw_angle_jitter), max_lateral, scene.lateral_position_jitter])
		_check(max_angle > rad_to_deg(scene.yaw_angle_jitter) * 0.8,
			"yaw jitter fan collapsed at pitch %.0f" % pitch)
		_check(max_lateral > scene.lateral_position_jitter * 0.8,
			"lateral position jitter collapsed at pitch %.0f" % pitch)
	scene._points.clear()

	# --- near-camera handling ---
	# The rig keeps the strand root clear of the camera on its own, so these
	# guards are insurance rather than something the default tuning exercises.
	# Assert the invariant they protect, then drive them directly.
	scene.debug_set_aim(0.0, 0.0)
	for first_person in [true, false]:
		scene.set_first_person(first_person)
		Input.action_press("fire_mayo")
		for _frame in 40:
			await physics_frame
		Input.action_release("fire_mayo")
		var camera_position: Vector3 = scene._camera.global_position
		var nearest := INF
		for point in scene._points:
			nearest = minf(nearest, point.position.distance_to(camera_position))
		print("first_person=%-5s points=%3d nearest_to_camera=%.3f m (cull=%.2f, billboard_fallback=%.2f)" % [
			str(first_person), scene._points.size(), nearest,
			scene.strand_near_cull_distance, scene._air_visual.min_view_distance])
		_check(nearest > scene.strand_near_cull_distance,
			"a rendered strand point sat inside the cull radius (fp=%s)" % str(first_person))
		scene._points.clear()

	# Guard 1: the cull predicate drops a point placed on top of the camera.
	scene.set_first_person(true)
	await physics_frame
	var camera_at: Vector3 = scene._camera.global_position
	var probe = scene.MayoPoint.new()
	probe.position = camera_at + Vector3.FORWARD * (scene.strand_near_cull_distance * 0.5)
	_check(scene._is_near_camera(probe, camera_at), "cull predicate missed a point on top of the camera")
	probe.position = camera_at + Vector3.FORWARD * (scene.strand_near_cull_distance * 2.0)
	_check(not scene._is_near_camera(probe, camera_at), "cull predicate dropped a point at a normal distance")

	# Guard 2: the billboard falls back to the view axis inside min_view_distance,
	# instead of the point-to-camera vector that swings wildly there.
	var visual = scene._air_visual
	var forward := Vector3.FORWARD
	var far_view: Vector3 = visual._view_vector(camera_at + forward * 5.0, camera_at, forward)
	_check(far_view.distance_to((camera_at - (camera_at + forward * 5.0)).normalized()) < 0.001,
		"billboard ignored the true view vector at a normal distance")
	var swing_a: Vector3 = visual._view_vector(camera_at + Vector3(0.001, 0.0, 0.0), camera_at, forward)
	var swing_b: Vector3 = visual._view_vector(camera_at + Vector3(-0.001, 0.0, 0.0), camera_at, forward)
	_check(swing_a.distance_to(swing_b) < 0.001,
		"billboard vector still swings for points straddling the camera")
	_check(swing_a.distance_to(-forward) < 0.001, "billboard fallback is not the view axis")

	if failures.is_empty():
		print("MAYO_AIM_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
