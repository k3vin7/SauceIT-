extends SceneTree

class FeedbackWorld:
	extends "res://scripts/mayo_prototype.gd"
	var accents: Array[int] = []

	func _broadcast_enemy_shake(enemy: MayoEnemy, degrees: float, seconds: float, accent := 0) -> void:
		accents.append(accent)
		super._broadcast_enemy_shake(enemy, degrees, seconds, accent)

var failures: Array[String] = []

func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _measure_delivery(scene, speed: float) -> Array:
	var shooter = scene._local
	scene.extend_speed = speed
	shooter.points.clear()
	shooter.emit_distance = 0.0
	shooter.fire_hold = 0.0
	shooter.fire_cooldown = 0.0
	shooter.was_firing = false
	shooter.trigger_released = true
	shooter.sauce = 1.0
	shooter.firing = true
	shooter.burst_elapsed = 0.0
	shooter.rng.seed = 84
	for _i in 30:
		scene._advance_strand(shooter, 1.0 / 60.0)
	return [shooter.points.size(), shooter.sauce, shooter.points[0].velocity.length()]

func _run() -> void:
	var scene := FeedbackWorld.new()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_physics_process(false)
	scene.set_process_unhandled_input(false)
	var shooter = scene._local
	var before := _measure_delivery(scene, 14.0)
	var after := _measure_delivery(scene, 20.0)
	print("delivery 14 -> 20 m/s: points %d -> %d, tank %.5f -> %.5f, velocity %.2f -> %.2f" % [before[0], after[0], before[1], after[1], before[2], after[2]])
	_check(before[0] == after[0], "travel speed changed damage sampling rate")
	_check(is_equal_approx(before[1], after[1]), "travel speed changed tank consumption")
	_check(after[2] > before[2] * 1.4, "point travel did not speed up")

	# Bottle kick must be visible independently of camera settings, then recover.
	shooter.bottle_kick = 0.0
	shooter.bottle_pressure = 0.0
	shooter.was_firing = false
	var muzzle: Vector3 = shooter.muzzle.global_position
	var direction: Vector3 = shooter.attack_direction
	var camera: Transform3D = scene._camera.global_transform
	scene._advance_spray_feel(shooter, 1.0 / 60.0, true)
	shooter.was_firing = true
	for _i in 4:
		scene._advance_spray_feel(shooter, 1.0 / 60.0, true)
	_check(shooter.weapon_sway.position.z > 0.035, "bottle has no visible backward kick")
	_check(absf(shooter.weapon_sway.rotation.x) < deg_to_rad(4.0), "bottle rotates too far instead of pushing backward")
	_check(shooter.muzzle.global_position.distance_to(muzzle) < 0.00001, "recoil moved the real muzzle")
	_check(shooter.attack_direction.distance_to(direction) < 0.00001, "recoil changed aim")
	_check(scene._camera.global_transform.is_equal_approx(camera), "bottle recoil moved the camera")
	for _i in 60:
		scene._advance_spray_feel(shooter, 1.0 / 60.0, true)
	_check(shooter.weapon_sway.position.z > 0.01, "bottle returned to rest while still delivering")
	for _i in 90:
		scene._advance_spray_feel(shooter, 1.0 / 60.0, false)
		shooter.was_firing = false
	_check(shooter.weapon_sway.position.length() < 0.0001, "bottle never returned to rest")

	# The visible root follows the moved bottle, without moving simulated sauce.
	shooter.was_firing = true
	shooter.nozzle = scene.Nozzle.STREAM
	shooter.points.clear()
	shooter.bottle_kick = 1.0
	scene._apply_nozzle_sway(shooter)
	scene._emit_point(shooter)
	var emitted: Vector3 = shooter.points.back().position
	var roots: Array = scene._nozzle_segments(shooter, scene._camera.global_position)
	_check(roots.size() == 1, "spraying left a gap between nozzle and stream")
	if not roots.is_empty():
		var tip: Vector3 = shooter.weapon_sway.to_global(shooter.muzzle.position)
		_check(roots[0][0].position.distance_to(tip) < 0.005, "visual stream does not start at the recoiling tip")
		_check(roots[0].back().position.distance_to(emitted) < 0.0001, "nozzle connection misses the simulated stream")
		_check(roots[0][0].width_scale < roots[0].back().width_scale, "stream does not taper to the nozzle")
	_check(shooter.points.back().position == emitted, "visual attachment moved the simulated shot")
	shooter.was_firing = false
	_check(scene._nozzle_segments(shooter, scene._camera.global_position).is_empty(), "released sauce stayed tethered to the bottle")
	shooter.was_firing = true
	shooter.burst_index += 1
	_check(scene._nozzle_segments(shooter, scene._camera.global_position).is_empty(), "new burst tethered an old strand")
	shooter.was_firing = false

	var enemy: MayoEnemy = scene.enemy_at(0)
	var at := enemy.global_position
	var initial: int = scene._speck_cursor
	scene._impact_clock = 1.0 # A street hit cannot suppress first contact on an enemy.
	scene._note_stream_contact(enemy, at, Vector3.UP, Vector3.DOWN, shooter)
	var first: int = scene._speck_cursor
	_check(first != initial, "first contact was swallowed by the world spray timer")
	for _i in 10:
		scene._note_stream_contact(enemy, at, Vector3.UP, Vector3.DOWN, shooter)
	_check(scene._speck_cursor == first, "continuous hits repeated the first-contact burst")
	scene._advance_impact_clocks(0.19)
	scene._note_stream_contact(enemy, at, Vector3.UP, Vector3.DOWN, shooter)
	var sustained: int = scene._speck_cursor - first
	_check(sustained > 0 and sustained < first - initial, "sustained spray is not smaller than first contact")
	scene._advance_impact_clocks(0.23)
	var reentry: int = scene._speck_cursor
	scene._note_stream_contact(enemy, at, Vector3.UP, Vector3.DOWN, shooter)
	_check(scene._speck_cursor - reentry == first - initial, "reacquiring target did not restore first contact")

	enemy._flinch_left = 0.0
	enemy._pressure_left = 0.0
	for _i in 30:
		enemy.take_shove(at + Vector3.FORWARD * 3.0)
		enemy._advance_flinch(1.0 / 60.0)
	_check(enemy.fall_angle > deg_to_rad(2.0), "enemy did not lean under sustained pressure")
	_check(not enemy.is_flinching(), "pressure posture became a threshold flinch")
	for _i in 90:
		enemy._advance_flinch(1.0 / 60.0)
	_check(absf(enemy.fall_angle) < 0.001, "enemy did not recover after pressure stopped")

	# A threshold causes one accent, even when more points arrive during its flinch.
	enemy.health = enemy.max_health * 0.75 + enemy.sauce_damage_per_hit * 0.5
	enemy._flinch_crossed = 0
	scene.accents.clear()
	for _i in 10:
		scene._record_splat(enemy, at, Vector3.UP, shooter)
	_check(scene.accents == [1], "threshold feedback repeated for every point during flinch")
	enemy.health = enemy.sauce_damage_per_hit * 0.5
	scene._record_splat(enemy, at, Vector3.UP, shooter)
	_check(scene.accents == [1, 2], "kill did not produce one distinct defeat event")
	_check(scene._crosshair.impact_kill, "kill confirmation is absent")
	shooter.on_target_left = 0.0
	scene._simulate_points(1.0 / 60.0, shooter)

	for stream in [scene.spray_loop_sound, scene.spray_loop_on_target_sound]:
		_check(stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"continuous spray clip does not loop")
		_check(stream.get_length() > 1.0, "continuous clip is missing audio")

	for failure in failures:
		push_error(failure)
	print("MAYO_COMBAT_FEEL_OK" if failures.is_empty() else "MAYO_COMBAT_FEEL_FAILED")
	scene.queue_free()
	await process_frame
	call_deferred("quit", 0 if failures.is_empty() else 1)
