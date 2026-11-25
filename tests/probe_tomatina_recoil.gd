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
	world.set_gameplay_input_enabled(true)
	var shooter = world._local
	shooter.player.set_physics_process(false)
	shooter.player.global_position = Vector3(0.0, 100.0, 0.0)
	await physics_frame

	for part in Parts.STREAM_AIM_RECOIL:
		_prepare(world, shooter, part)
		var before: Vector3 = shooter.attack_direction
		shooter.firing = true
		for tick in 20:
			_step(world, shooter)
		_check(shooter.attack_direction.y > before.y + 0.02 and shooter.points.size() > 1,
			"held stream %s did not climb" % part)
		if shooter.points.size() > 1:
			_check(shooter.points.back().launch_direction.y > shooter.points.front().launch_direction.y + 0.02,
				"stream %s moved the view without moving the emitted sauce" % part)
		world.camera_motion_scale = 0.0
		world._update_camera()
		_check((-world._camera.global_basis.z).is_equal_approx(shooter.attack_direction),
			"camera-motion setting separated the reticle from the firing direction")
		shooter.firing = false
		for tick in 75:
			_step(world, shooter)
		_check(is_zero_approx(shooter.aim_recoil_pitch), "stream %s did not settle after release" % part)

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

	var expected_lift := {Parts.Part.ARC: 12.0, Parts.Part.CANNON: 16.0, Parts.Part.SNIPER: 3.0}
	for part in expected_lift:
		_prepare(world, shooter, part)
		shooter.firing = true
		_step(world, shooter)
		_check(is_zero_approx(shooter.attack_direction.y), "projectile part %s kicked before launch" % part)
		for tick in 8:
			_step(world, shooter)
		_check(is_equal_approx(rad_to_deg(asin(shooter.attack_direction.y)), expected_lift[part]),
			"projectile part %s did not reach its full aim lift" % part)
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
	_check(is_equal_approx(rad_to_deg(asin(shooter.attack_direction.y)), 18.0),
		"the charged mortar did not reach its full aim lift")

	await _probe_sniper_range(world, shooter)

	shooter.aim_pitch = deg_to_rad(world.pitch_limit_degrees)
	shooter.aim_recoil_pitch = deg_to_rad(5.0)
	world.apply_look(Vector2(0.0, 1.0 / world.mouse_sensitivity))
	_check(is_equal_approx(rad_to_deg(world.effective_aim_pitch(shooter)), world.pitch_limit_degrees - 1.0),
		"recoil at the pitch limit hid the player's downward mouse correction")


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
	shooter.aim_recoil_pitch = 0.0
	shooter.aim_recoil_pending = 0.0
	shooter.aim_recoil_hold = 0.0
	world.debug_set_aim(0.0, 0.0)


func _step(world, shooter) -> void:
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
