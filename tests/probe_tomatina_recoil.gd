extends SceneTree

const Parts := preload("res://scripts/tomatina_sauce_parts.gd")
const Stage := preload("res://stage_2_tomatina.tscn")
const STEP := 1.0 / 60.0

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _run() -> void:
	if OS.get_cmdline_user_args().has("--network"):
		await _probe_network()
	else:
		await _probe_offline()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("TOMATINA_RECOIL_OK")
	quit(0 if failures.is_empty() else 1)


func _probe_offline() -> void:
	var world = Stage.instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.debug_clear_enemies()
	world.catch_chance = 0.0
	world.lateral_position_jitter = 0.0
	world.yaw_angle_jitter = 0.0
	world.set_gameplay_input_enabled(true)
	var shooter = world._local
	shooter.player.set_physics_process(false)
	shooter.player.global_position = Vector3(0.0, 100.0, 0.0)
	await physics_frame

	for part in Parts.STREAM_AIM_RECOIL:
		_prepare(world, shooter, part)
		var view_before: Vector3 = -world._camera.global_basis.z
		var arms = shooter.first_person_arms
		world._apply_nozzle_sway(shooter)
		arms.refresh_pose(null)
		var palm: Node3D = arms.palms[0]
		var palm_before := palm.position
		shooter.firing = true
		var launch_min := INF
		var launch_max := -INF
		var side := 0.0
		var reversals := 0
		var grip_travel := 0.0
		var palm_travel := 0.0
		var previous_pitch := view_before.y
		var smooth_climb := true
		var reticle_aligned := true
		var early_pitch := 0.0
		var quarter_second_pitch := 0.0
		var sustained_pitch := 0.0
		var leftmost := 0.0
		var rightmost := 0.0
		for tick in 46:
			_step(world, shooter)
			world._update_camera()
			var view := _reticle_direction(world)
			reticle_aligned = reticle_aligned and view.is_equal_approx(shooter.attack_direction)
			leftmost = minf(leftmost, view.x)
			rightmost = maxf(rightmost, view.x)
			smooth_climb = smooth_climb and view.y >= previous_pitch - 0.00001
			previous_pitch = view.y
			if tick < 10:
				early_pitch += view.y / 10.0
			elif tick == 14:
				quarter_second_pitch = view.y
			elif tick >= 36:
				sustained_pitch += view.y / 10.0
			world._apply_nozzle_sway(shooter)
			var grip: Vector3 = shooter.weapon_sway.position
			grip_travel = maxf(grip_travel, absf(grip.x))
			if absf(grip.x) > 0.00025:
				var next_side := signf(grip.x)
				if side != 0.0 and next_side != side:
					reversals += 1
				side = next_side
			arms.refresh_pose(null)
			var hand_shift := palm.position - palm_before
			palm_travel = maxf(palm_travel, absf(hand_shift.x))
			if not shooter.points.is_empty():
				var direction: Vector3 = shooter.points.back().launch_direction
				launch_min = minf(launch_min, direction.y)
				launch_max = maxf(launch_max, direction.y)
		var peak: float = Parts.STREAM_AIM_RECOIL[part].lift
		_check(smooth_climb and quarter_second_pitch > deg_to_rad(1.3)
			and sustained_pitch - early_pitch > deg_to_rad(6.5) and is_equal_approx(asin(previous_pitch), peak),
			"stream %s did not lift the camera smoothly" % part)
		_check(leftmost < -0.0035 and rightmost > 0.0035 and maxf(-leftmost, rightmost) < deg_to_rad(1.03),
			"stream %s side recoil was missing or too strong" % part)
		_check(grip_travel > 0.001 and grip_travel < 0.009 and reversals >= 7,
			"stream %s did not keep fine vibration in the grip (%d reversals)" % [part, reversals])
		_check(palm_travel > 0.001 and palm_travel < 0.0125,
			"stream %s first-person hand moved %.1f mm" % [part, palm_travel * 1000.0])
		_check(reticle_aligned, "stream %s no longer aimed through the screen centre" % part)
		_check(launch_max - launch_min > deg_to_rad(6.5), "stream %s did not lift the emitted sauce" % part)
		_check(is_zero_approx(shooter.player.rotation.y), "stream recoil turned the movement body")
		shooter.firing = false
		for tick in 75:
			_step(world, shooter)
		world._update_camera()
		_check(is_zero_approx(shooter.stream_recoil_pitch) and is_zero_approx(shooter.stream_recoil_yaw)
			and _reticle_direction(world).is_equal_approx(view_before),
			"stream %s camera did not settle after release" % part)

	_prepare(world, shooter, Parts.Part.STANDARD)
	world.set_first_person(false)
	var shoulder_before: Vector3 = -world._camera.global_basis.z
	shooter.stream_recoil_pitch = deg_to_rad(2.2)
	shooter.stream_recoil_yaw = deg_to_rad(0.32)
	world._update_aim()
	world._update_camera()
	_check(_reticle_direction(world).y > shoulder_before.y + 0.03, "stream did not raise the shoulder camera")
	_check(_reticle_direction(world).is_equal_approx(shooter.attack_direction), "shoulder reticle missed the nozzle direction")
	world.set_first_person(true)

	# Keep the authored launch pose still while comparing two shots at one target.
	shooter.procedural_motion.active = false
	await process_frame
	_fire_burst(world, shooter, false)
	var shots: Array[Dictionary] = world._sauce_parts._projectiles
	_check(shots.size() == 3, "expected three projectiles for the recoil target test")
	if shots.size() == 3:
		var first: Dictionary = shots.front()
		var ticks_to_target := 19
		# The burst integrates gravity before moving each tick. This small target
		# sits on the first shot's trajectory, below the aim ray.
		var centre: Vector3 = first.origin + first.launch_velocity * (STEP * ticks_to_target) \
			+ Vector3.DOWN * (Parts.GRAVITY * STEP * STEP * ticks_to_target * (ticks_to_target + 1) * 0.5)
		var target := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.10
		collision.shape = sphere
		target.position = centre
		target.add_child(collision)
		world.add_child(target)
		await physics_frame
		for i in 25:
			world._sauce_parts.advance_projectiles(STEP, true)
		_check(shots.size() == 2, "only the first shot should hit without mouse correction")

		_fire_burst(world, shooter, true)
		for i in 25:
			world._sauce_parts.advance_projectiles(STEP, true)
		_check(shots.is_empty(), "pulling the mouse down did not land all three shots")
	shooter.procedural_motion.active = true

	var expected_lift := {Parts.Part.ARC: 14.0, Parts.Part.CANNON: 19.0, Parts.Part.SNIPER: 6.0}
	for part in expected_lift:
		_prepare(world, shooter, part)
		shooter.firing = true
		_step(world, shooter)
		_check(is_zero_approx(shooter.attack_direction.y), "projectile part %s kicked before launch" % part)
		for tick in 8:
			_step(world, shooter)
		_check(is_equal_approx(rad_to_deg(asin(shooter.attack_direction.y)), expected_lift[part]),
			"projectile part %s did not reach its full aim lift" % part)
		world._update_camera()
		_check(_reticle_direction(world).is_equal_approx(shooter.attack_direction),
			"projectile part %s lost its camera recoil" % part)
		_prepare(world, shooter, part)
		shooter.sauce = 0.0
		shooter.firing = true
		_step(world, shooter)
		_step(world, shooter)
		_check(is_zero_approx(shooter.aim_recoil_pitch), "empty part %s recoiled" % part)

	_prepare(world, shooter, Parts.Part.ARC)
	shooter.bottle_charge = 1.0
	shooter.firing = true
	for tick in 9:
		_step(world, shooter)
	_check(is_equal_approx(rad_to_deg(asin(shooter.attack_direction.y)), 21.0),
		"the charged mortar did not reach its full aim lift")

	_probe_projectile_ribbons(world, shooter)
	await _probe_sniper_range(world, shooter)

	shooter.aim_pitch = deg_to_rad(world.pitch_limit_degrees)
	shooter.aim_recoil_pitch = deg_to_rad(5.0)
	world.apply_look(Vector2(0.0, 1.0 / world.mouse_sensitivity))
	_check(is_equal_approx(rad_to_deg(world.effective_aim_pitch(shooter)), world.pitch_limit_degrees - 1.0),
		"recoil at the pitch limit hid the player's downward mouse correction")


func _reticle_direction(world) -> Vector3:
	var point: Vector2 = world._crosshair.size * 0.5
	return world._camera.project_ray_normal(point)


func _probe_projectile_ribbons(world, shooter) -> void:
	var system = world._sauce_parts
	system.reset()
	var origin: Vector3 = shooter.aim_pivot.global_position + Vector3.UP * 12.0
	var parts := [Parts.Part.BURST, Parts.Part.ARC, Parts.Part.CANNON, Parts.Part.SNIPER]
	var widths := {}
	var lengths := {}
	var pooled_ribbon: StreamVisual
	for i in parts.size():
		var part: int = parts[i]
		var sauce: int = i % world.SAUCE_TINTS.size()
		system.show_volley(shooter.peer_id, part, sauce, origin, Vector3.FORWARD)
		system.advance_projectiles(0.18, false)
		_check(system._projectiles.size() == 1, "open-air projectile %s did not survive" % part)
		if system._projectiles.size() != 1:
			continue
		var shot: Dictionary = system._projectiles[0]
		var ribbon := shot.node as StreamVisual
		_check(ribbon != null and ribbon.visible, "part %s did not draw a sauce ribbon" % part)
		if ribbon != null:
			_check(pooled_ribbon == null or pooled_ribbon == ribbon, "part %s did not reuse a ribbon" % part)
			_check(ribbon.ribbon_material == world.SAUCE_STREAM_MATERIALS[sauce],
				"part %s drew the wrong sauce material" % part)
			_check(ribbon.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV != 0,
				"part %s drew a ribbon without sauce coordinates" % part)
			_check(ribbon.custom_aabb.has_point(shot.head), "part %s ribbon missed its own projectile tip" % part)
			var size := ribbon.custom_aabb.size
			widths[part] = maxf(size.x, size.y)
			lengths[part] = size.z
			pooled_ribbon = ribbon
		system.reset()
	if widths.size() == parts.size():
		_check(widths[Parts.Part.ARC] > widths[Parts.Part.BURST] and widths[Parts.Part.CANNON] > widths[Parts.Part.BURST],
			"heavy projectile ribbons were not thicker than the burst")
		_check(widths[Parts.Part.SNIPER] < widths[Parts.Part.BURST] and lengths[Parts.Part.SNIPER] > lengths[Parts.Part.ARC]
			and lengths[Parts.Part.SNIPER] > lengths[Parts.Part.CANNON], "sniper ribbon was not the longest and thinnest")


func _probe_sniper_range(world, shooter) -> void:
	_prepare(world, shooter, Parts.Part.SNIPER)
	var eye: Vector3 = shooter.aim_pivot.global_position
	var index: int = world.tutorial_add_enemy(MayoTutorial.KIND_TOMATO_BRUTE, eye)
	var target: MayoEnemy = world.enemy_at(index)
	target.global_position = eye + Vector3.UP * 0.12 + Vector3.FORWARD * 58.0
	await physics_frame
	Input.action_press("aim_sniper")
	world._sniper_zoom = 1.0
	world._update_camera()
	world.play_support._update_aim_feedback()
	_check(not world._crosshair.effective_range, "scope marked a target 58 m away as in range")
	target.global_position -= Vector3.FORWARD * 6.0
	await physics_frame
	world.play_support._update_aim_feedback()
	_check(world._crosshair.scope > 0.99 and world._crosshair.effective_range,
		"scope did not mark a target 52 m away as in range")
	var health := target.health
	shooter.firing = true
	_step(world, shooter)
	shooter.firing = false
	for tick in 3:
		_step(world, shooter)
	world._update_camera()
	_check(world._crosshair.scope > 0.99 and is_equal_approx(rad_to_deg(asin(_reticle_direction(world).y)), 6.0),
		"scoped sniper pitch did not reach six degrees")
	for tick in 36:
		world._sauce_parts.advance_projectiles(STEP, true)
	_check(target.health < health, "the sniper shot did not hit the target 52 m away")
	Input.action_release("aim_sniper")
	world._sniper_zoom = 0.0


func _prepare(world, shooter, part: int) -> void:
	world._sauce_parts.reset()
	world.debug_equip_part(shooter.peer_id, part)
	shooter.points.clear()
	shooter.side_points.clear()
	shooter.sauce = 1.0
	shooter.bottle_charge = 0.0
	shooter.firing = false
	shooter.was_firing = false
	shooter.fire_cooldown = 0.0
	shooter.fire_hold = 0.0
	shooter.part_cooldown = 0.0
	shooter.part_trigger_down = false
	shooter.stream_recoil_pitch = 0.0
	shooter.stream_recoil_yaw = 0.0
	shooter.stream_recoil_time = 0.0
	shooter.aim_recoil_pitch = 0.0
	shooter.aim_recoil_pending = 0.0
	shooter.aim_recoil_hold = 0.0
	world.debug_set_aim(0.0, 0.0)


func _step(world, shooter) -> void:
	world._advance_stream_aim_recoil(shooter, STEP)
	world._advance_aim_recoil(shooter, STEP)
	world._update_aim(shooter)
	world._advance_strand(shooter, STEP)


func _fire_burst(world, shooter, compensate: bool) -> void:
	_prepare(world, shooter, Parts.Part.BURST)
	shooter.firing = true
	for tick in 20:
		world._advance_aim_recoil(shooter, STEP)
		if compensate:
			var error: float = world.effective_aim_pitch(shooter)
			world.apply_look(Vector2(0.0, rad_to_deg(error) / world.mouse_sensitivity))
		world._update_aim(shooter)
		world._advance_strand(shooter, STEP)
		shooter.firing = false


func _make_network_world(view_name: String) -> Node3D:
	var viewport := SubViewport.new()
	viewport.name = view_name
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	root.add_child(viewport)
	var world := Stage.instantiate() as Node3D
	world.name = "World"
	viewport.add_child(world)
	set_multiplayer(SceneMultiplayer.new(), world.get_path())
	return world


func _network_tick() -> void:
	await process_frame
	await physics_frame


func _probe_network() -> void:
	var host = _make_network_world("HostView")
	var guest = _make_network_world("GuestView")
	if not host._net.host(24818, true) or not guest._net.join("127.0.0.1", 24818):
		failures.append("could not open the loopback session")
		return
	for frame in 180:
		if guest.shooter_ids().size() == 2 and guest._net.debug_state_packets > 0:
			break
		await _network_tick()
	var host_copy = host.shooter_for(guest._net.local_id())
	if host_copy == null or guest.shooter_ids().size() != 2:
		failures.append("the loopback guest did not join")
		return
	host.debug_clear_enemies()
	var expected_peak := float(Parts.SHOT_AIM_RECOIL[Parts.Part.BURST].lift) * Parts.BURST_SHOTS
	_check(host.debug_equip_part(host_copy.peer_id, Parts.Part.BURST), "host could not equip the guest's burst valve")
	for frame in 60:
		if guest._local.sauce_part == Parts.Part.BURST:
			break
		await _network_tick()
	guest.debug_set_aim(0.0, 0.0)
	guest.debug_set_input(Vector2.ZERO, false, true)
	var host_peak := 0.0
	var guest_peak := 0.0
	for frame in 42:
		await _network_tick()
		host_peak = maxf(host_peak, rad_to_deg(host_copy.aim_recoil_pitch))
		guest_peak = maxf(guest_peak, rad_to_deg(guest._local.aim_recoil_pitch))
	guest.debug_clear_input_override()
	_check(absf(host_peak - expected_peak) < 0.25 and absf(guest_peak - host_peak) < 0.25,
		"guest burst kicks differed on host (%.2f°) and guest (%.2f°)" % [host_peak, guest_peak])
	_check(is_zero_approx(host_copy.aim_pitch), "the guest sent recoil back as mouse input")

	host.debug_equip_part(host._local.peer_id, Parts.Part.CANNON)
	host.debug_set_aim(0.0, 0.0)
	host.debug_set_input(Vector2.ZERO, false, true)
	var remote_copy = guest.shooter_for(host._local.peer_id)
	var remote_peak := 0.0
	for frame in 42:
		await _network_tick()
		remote_peak = maxf(remote_peak, rad_to_deg(guest.effective_aim_pitch(remote_copy)))
	host.debug_clear_input_override()
	var cannon_lift := float(Parts.SHOT_AIM_RECOIL[Parts.Part.CANNON].lift)
	_check(absf(remote_peak - cannon_lift) < 0.25 and is_zero_approx(remote_copy.aim_recoil_pitch),
		"the guest did not display the host's cannon recoil once (peak %.2f°)" % remote_peak)

	host_copy.sauce = 1.0
	_check(host.debug_equip_part(host_copy.peer_id, Parts.Part.FAN), "host could not equip the guest's three-way nozzle")
	for frame in 60:
		if guest._local.sauce_part == Parts.Part.FAN:
			break
		await _network_tick()
	guest.debug_set_aim(0.0, 0.0)
	guest.debug_set_input(Vector2.ZERO, false, true)
	var recoil_peak := 0.0
	var camera_peak := 0.0
	var side_peak := 0.0
	var camera_side_peak := 0.0
	for frame in 62:
		await _network_tick()
		recoil_peak = maxf(recoil_peak, guest._local.stream_recoil_pitch)
		camera_peak = maxf(camera_peak, asin(_reticle_direction(guest).y))
		side_peak = maxf(side_peak, absf(guest._local.stream_recoil_yaw))
		camera_side_peak = maxf(camera_side_peak, absf(guest._camera.global_basis.get_euler().y))
	guest.debug_clear_input_override()
	_check(recoil_peak > deg_to_rad(9.5) and absf(camera_peak - recoil_peak) < deg_to_rad(0.2),
		"the guest camera did not follow the authoritative stream pitch")
	_check(side_peak > deg_to_rad(0.75) and side_peak < deg_to_rad(1.03)
		and absf(camera_side_peak - side_peak) < deg_to_rad(0.1),
		"the guest camera did not follow the small authoritative side recoil")
	_check(is_zero_approx(host_copy.aim_yaw) and is_zero_approx(host_copy.aim_pitch),
		"the guest sent the stream offset back as mouse input")
