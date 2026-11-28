extends SceneTree

class FlightWorld:
	extends "res://scripts/mayo_prototype.gd"

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)

const STEP := 1.0 / 60.0

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
	_aim(shooter, 0.0, pitch)
	shooter.player.velocity = Vector3(4, 0, 0) if moving else Vector3.ZERO
	world._emit_point(shooter)
	var point = shooter.points[0]
	var start: Vector3 = point.position
	if released:
		var velocity: Vector3 = point.velocity
		world._apply_release_pressure_loss(shooter)
		_check(point.velocity.is_equal_approx(velocity), "trigger release snapped an airborne sample's speed")
	for frame in 600:
		world._simulate_points(1.0 / 60.0, shooter)
		if point.phase == world.PointPhase.LANDING:
			var flat: Vector3 = point.position - start
			flat.y = 0.0
			return Vector2(flat.length(), float(frame + 1) / 60.0)
	_check(false, "point never landed")
	return Vector2.ZERO

func _aim(shooter, yaw: float, pitch: float) -> void:
	shooter.aim_pivot.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	shooter.attack_basis = shooter.aim_pivot.global_basis
	shooter.attack_direction = -shooter.attack_basis.z
	shooter.stream_target = Vector3.INF


func _probe_aim_motion(world, shooter) -> void:
	world.extend_speed = 20.0
	world.gravity_acceleration = 9.8
	shooter.player.velocity = Vector3.ZERO
	var gravity: float = world.gravity_acceleration * (world.extend_speed / world.emission_speed) ** 2
	for profile in ["level", "up", "horizontal sweep", "vertical sweep"]:
		shooter.points.clear()
		shooter.burst_elapsed = 0.0
		var pitch := 65.0 if profile == "up" else 0.0
		_aim(shooter, 0.0, pitch)
		world._emit_point(shooter)
		var first = shooter.points.back()
		var start_y: float = first.position.y
		var peak := start_y
		var passed_apex := false
		var aim_ok := true
		var gravity_ok := true
		var projection_ok := true
		var release_tick := 15
		var released_tail = null
		var tail_checked := false
		var airborne_ticks := 0
		for tick in 180:
			if tick == release_tick:
				released_tail = shooter.points.back()
				world._apply_release_pressure_loss(shooter)
			elif tick < release_tick:
				var yaw := sin(float(tick) * 0.35) * 50.0 if profile == "horizontal sweep" else 0.0
				var aimed_pitch := sin(float(tick) * 0.45) * 50.0 if profile == "vertical sweep" else pitch
				_aim(shooter, yaw, aimed_pitch)
				world._emit_point(shooter)
				var sample = shooter.points.back()
				var arrival: float = sample.aimed_until - STEP
				var impact: Vector3 = sample.position + sample.velocity * arrival + Vector3.DOWN * (0.5 * gravity * arrival * arrival)
				aim_ok = aim_ok and arrival > 0.0 and impact.distance_to(shooter.stream_target) < 0.004
			var height: float = first.position.y
			var vertical_speed: float = first.velocity.y
			var tail_speed: float = released_tail.velocity.y if released_tail != null else 0.0
			world._apply_inertial_follow(Vector3(0.012, 0.055, 0.0), shooter)
			world._simulate_points(STEP, shooter)
			world._update_connections(shooter)
			world._enforce_spacing_constraint(shooter)
			if released_tail != null and released_tail.phase == world.PointPhase.AIR:
				tail_checked = true
				gravity_ok = gravity_ok and absf(released_tail.velocity.y - (tail_speed - gravity * STEP)) < 0.0001
			if first.phase == world.PointPhase.LANDING:
				break
			airborne_ticks += 1
			gravity_ok = gravity_ok and absf(first.velocity.y - (vertical_speed - gravity * STEP)) < 0.0001
			gravity_ok = gravity_ok and absf(first.position.y - (height + (vertical_speed - gravity * STEP * 0.5) * STEP)) < 0.0001
			peak = maxf(peak, first.position.y)
			passed_apex = passed_apex or first.velocity.y < 0.0
			first.draw_offset = Vector3(0.0, 0.68, -0.4)
			first.draw_lateral = Vector3(0.2, 0.0, 0.0)
			var display: Vector3 = world._ribbon_point_position(first, true)
			var limit: float = world.STREAM_RISING_MUZZLE_BLEND_DISTANCE
			if first.distance_travelled >= limit:
				projection_ok = projection_ok and is_equal_approx(display.y, first.position.y)
			if first.distance_travelled >= world.STREAM_SIDE_BLEND_DISTANCE:
				projection_ok = projection_ok and display.is_equal_approx(first.position)
		_check(aim_ok, "%s failed to curve through the sight" % profile)
		_check(gravity_ok and tail_checked and airborne_ticks > 15,
			"%s applied a vertical impulse to released liquid" % profile)
		_check(projection_ok, "%s lifted the ribbon outside the muzzle transition" % profile)
		_check(passed_apex and first.phase == world.PointPhase.LANDING, "%s did not fall and hit the floor" % profile)
		_check(peak - start_y > 1.0 if profile == "up" else peak - start_y > 0.35,
			"%s never rose from the muzzle to the intended aim height" % profile)
		print("%s: apex %.3f m over mouth, %d flight ticks, gravity %s" % [
			profile, peak - start_y, airborne_ticks, "continuous" if gravity_ok else "failed"])
	shooter.points.clear()
	_aim(shooter, 0.0, 0.0)
	world._emit_point(shooter)
	_aim(shooter, 65.0, 0.0)
	world._emit_point(shooter)
	world._update_connections(shooter)
	_check(shooter.points.back().severed, "a sharp turn drew a bridge between two directions")

	# A real lens in the crosshair can be hit despite the muzzle sitting lower.
	shooter.points.clear()
	_aim(shooter, 0.0, 0.0)
	shooter.stream_target = shooter.character_muzzle.global_position + Vector3(-0.12, 0.55, -2.3)
	world._emit_point(shooter)
	var point = shooter.points.back()
	var to_lens: Vector3 = shooter.stream_target - point.position
	var duration := Vector2(to_lens.x, to_lens.z).length() / Vector2(point.velocity.x, point.velocity.z).length()
	var at_lens: Vector3 = point.position + point.velocity * duration + Vector3.DOWN * (0.5 * gravity * duration * duration)
	_check(at_lens.distance_to(shooter.stream_target) < 0.004, "face aiming ignored the ballistic drop")



func _probe_reticle_collision(world, shooter) -> void:
	var marker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.075
	shape.shape = sphere
	marker.add_child(shape)
	world.add_child(marker)
	for kind in [ContaminationGrid.KIND_KETCHUP, ContaminationGrid.KIND_MAYO, ContaminationGrid.KIND_MUSTARD]:
		for scenario in [Vector2(0.0, 1.60), Vector2(0.0, 4.35), Vector2(25.0, 3.5), Vector2(-12.0, 4.0)]:
			var pitch: float = scenario.x
			_aim(shooter, 0.0, pitch)
			shooter.sauce_kind = kind
			shooter.burst_elapsed = 0.95
			shooter.player.velocity = Vector3(3.5, 0.0, 0.0)
			shooter.points.clear()
			var center: Vector3 = shooter.aim_pivot.global_position + shooter.attack_direction * scenario.y
			marker.global_position = center
			await physics_frame
			world._emit_point(shooter)
			var drop = shooter.points.back()
			# Let go immediately and move the shooter so changing the current aim
			# cannot drag a sample off this small target after it leaves the bottle.
			world._apply_release_pressure_loss(shooter)
			for tick in 80:
				_aim(shooter, float(tick) * 5.0, -15.0)
				world._apply_inertial_follow(Vector3(0.08, 0.03, 0.0), shooter)
				world._simulate_points(STEP, shooter)
				if drop.phase == world.PointPhase.LANDING:
					break
			_check(drop.phase == world.PointPhase.LANDING and drop.position.distance_to(center) < 0.085,
				"sauce %d at pitch %.0f and %.2f m missed the reticle collider" % [kind, pitch, scenario.y])
	marker.queue_free()
	shooter.points.clear()
	shooter.sauce_kind = ContaminationGrid.KIND_MAYO
	print("RETICLE_COLLISION_MATRIX 12")


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
	shooter.aim_pivot.position = Vector3(0, 1.85, 0)
	world.add_child(shooter.aim_pivot)
	shooter.muzzle = Marker3D.new()
	shooter.muzzle.position = Vector3(0.18, 1.05, -0.30)
	world.add_child(shooter.muzzle)
	shooter.character_muzzle = shooter.muzzle
	await physics_frame
	_probe_aim_motion(world, shooter)
	await _probe_reticle_collision(world, shooter)

	var baseline := _flight(world, shooter, 14.0, 0.0, 0.0, false, false)
	var uncorrected := _flight(world, shooter, 20.0, 0.0, 0.0, false, false, true)
	print("level full-pressure: original %.2f m, speed-only bug %.2f m" % [baseline.x, uncorrected.x])
	_check(uncorrected.x > baseline.x + 2.0, "test did not reproduce the extended-range bug")
	for pitch in [-20.0, 0.0, 30.0, 75.0]:
		for pressure_age in [0.0, 0.65]:
			for released in [false, true]:
				for moving in [false, true]:
					var slow := _flight(world, shooter, 14.0, pitch, pressure_age, released, moving)
					var fast := _flight(world, shooter, 20.0, pitch, pressure_age, released, moving)
					print("pitch %+.0f age %.2f release %s moving %s: %.2f -> %.2f m, %.3f -> %.3f s" % [pitch, pressure_age, released, moving, slow.x, fast.x, slow.y, fast.y])
					# Allow one fast physics step (20 / 60 m) for the quantized
					# collision sweep and discrete pressure taper.
					_check(absf(fast.x - slow.x) <= 20.0 / 60.0 + 0.01, "landing range changed by more than one fast physics step")
					_check(fast.y < slow.y, "same arc was not traversed faster")
	for failure in failures:
		push_error(failure)
	print("MAYO_FLIGHT_RANGE_OK" if failures.is_empty() else "MAYO_FLIGHT_RANGE_FAILED")
	world.queue_free()
	await process_frame
	call_deferred("quit", 0 if failures.is_empty() else 1)
