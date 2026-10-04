extends SceneTree

class FlightWorld:
	extends "res://scripts/mayo_prototype.gd"

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _flight(world, shooter, speed: float, pitch: float, pressure_age: float,
		released: bool, moving: bool, old_gravity := false) -> Vector2:
	world.extend_speed = speed
	world.gravity_acceleration = 9.8
	if old_gravity:
		world.gravity_acceleration /= pow(speed / world.emission_speed, 2.0)
	shooter.points.clear()
	shooter.burst_elapsed = pressure_age
	shooter.aim_pivot.rotation.x = deg_to_rad(pitch)
	shooter.attack_direction = -shooter.aim_pivot.global_basis.z
	shooter.player.velocity = Vector3(4, 0, 0) if moving else Vector3.ZERO
	world._emit_point(shooter)
	var point = shooter.points[0]
	var start: Vector3 = point.position
	if released:
		world._apply_release_pressure_loss(shooter)
	for frame in 600:
		world._simulate_points(1.0 / 60.0, shooter)
		if point.phase == world.PointPhase.LANDING:
			var flat: Vector3 = point.position - start
			flat.y = 0.0
			return Vector2(flat.length(), float(frame + 1) / 60.0)
	_check(false, "point never landed")
	return Vector2.ZERO

func _run() -> void:
	# An unobstructed physical floor isolates true travel from buildings/enemies.
	var world := FlightWorld.new()
	root.add_child(world)
	world.muzzle_forward_offset = 0.0
	world.lateral_position_jitter = 0.0
	world.yaw_angle_jitter = 0.0
	world.speed_magnitude_jitter = 0.0
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 0.2, 200)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.1
	world.add_child(floor)
	var shooter = world.Shooter.new()
	shooter.player = MayoPlayer.new()
	world.add_child(shooter.player)
	shooter.player.set_physics_process(false)
	shooter.aim_pivot = Node3D.new()
	shooter.aim_pivot.position = Vector3(0, 1.3, 0)
	world.add_child(shooter.aim_pivot)
	shooter.muzzle = Marker3D.new()
	shooter.muzzle.position = Vector3(0, 1.3, 0)
	world.add_child(shooter.muzzle)
	await physics_frame

	var baseline := _flight(world, shooter, 14.0, 0.0, 0.0, false, false)
	var uncorrected := _flight(world, shooter, 20.0, 0.0, 0.0, false, false, true)
	print("level full-pressure: original %.2f m, speed-only bug %.2f m" % [baseline.x, uncorrected.x])
	_check(uncorrected.x > baseline.x + 2.0, "test did not reproduce the extended-range bug")
	for pitch in [-20.0, 0.0, 30.0]:
		for pressure_age in [0.0, 0.65]:
			for released in [false, true]:
				for moving in [false, true]:
					var slow := _flight(world, shooter, 14.0, pitch, pressure_age, released, moving)
					var fast := _flight(world, shooter, 20.0, pitch, pressure_age, released, moving)
					print("pitch %+.0f age %.2f release %s moving %s: %.2f -> %.2f m, %.3f -> %.3f s" % [pitch, pressure_age, released, moving, slow.x, fast.x, slow.y, fast.y])
					# Allow one fast physics step (20 / 60 m) for the quantized
					# pressure transition and semi-implicit fall integration.
					_check(absf(fast.x - slow.x) <= 20.0 / 60.0 + 0.01, "landing range changed by more than one fast physics step")
					_check(fast.y < slow.y, "same arc was not traversed faster")
	for failure in failures:
		push_error(failure)
	print("MAYO_FLIGHT_RANGE_OK" if failures.is_empty() else "MAYO_FLIGHT_RANGE_FAILED")
	world.queue_free()
	await process_frame
	call_deferred("quit", 0 if failures.is_empty() else 1)
