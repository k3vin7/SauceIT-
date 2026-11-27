extends RefCounted
## Cosmetic camera-space spring shared by the tube and its two hands.
var offset := Vector3.ZERO
var speed := Vector3.ZERO
var angles := Vector3.ZERO
var angular_speed := Vector3.ZERO
var previous_aim := Vector2.ZERO
var previous_position := Vector3.ZERO
var initialized := false
var pose := Transform3D.IDENTITY
var shake_clock := 0.0

func reset() -> void:
	offset = Vector3.ZERO
	speed = Vector3.ZERO
	angles = Vector3.ZERO
	angular_speed = Vector3.ZERO
	pose = Transform3D.IDENTITY
	initialized = false
	shake_clock = 0.0

func advance(dt: float, shooter, enabled: bool, strength: float) -> void:
	if not enabled or dt <= 0.0:
		reset()
		return
	var body = shooter.player
	# Only walking/running contributes passive movement. Standing fire,
	# looking around, jumping and landing leave the viewmodel still.
	if not body.is_on_floor() or Vector2(body.velocity.x, body.velocity.z).length() <= 0.3:
		reset()
		return
	var aim := Vector2(shooter.aim_pitch, shooter.aim_yaw)
	var at: Vector3 = body.global_position
	if not initialized or at.distance_to(previous_position) > 3.0:
		reset()
		previous_aim = aim
		initialized = true
	previous_position = at
	var turn := Vector2(angle_difference(previous_aim.x, aim.x), angle_difference(previous_aim.y, aim.y)) / maxf(dt, 0.001)
	previous_aim = aim
	turn = turn.limit_length(5.0)
	var velocity: Vector3 = Basis(Vector3.UP, shooter.aim_yaw).inverse() * body.velocity
	var shaking := 0.0
	shake_clock += minf(dt, 0.05)
	var target := Vector3(clampf(-velocity.x * 0.0015, -0.018, 0.018),
		0.0, 0.0)
	var rotation_target := Vector3(-turn.x * 0.007 + clampf(velocity.y * 0.003, -0.02, 0.02),
		-turn.y * 0.007, turn.y * 0.004 - velocity.x * 0.0015)
	# The authored shake/recoil remains the primary action. This small spring
	# adds follow-through, including a gentle rebound when the action stops.
	target.y += sin(shake_clock * 42.0) * shaking * 0.008
	rotation_target.z += sin(shooter.bottle_shake_pose * PI) * shaking * 0.012
	rotation_target.x += cos(shake_clock * 42.0) * shaking * 0.008
	target *= strength
	rotation_target *= strength
	var remaining := minf(dt, 0.05)
	while remaining > 0.00001:
		var step := minf(remaining, 1.0 / 120.0)
		speed += ((target - offset) * 180.0 - speed * 21.0) * step
		offset += speed * step
		angular_speed += ((rotation_target - angles) * 150.0 - angular_speed * 19.0) * step
		angles += angular_speed * step
		remaining -= step
	offset = offset.limit_length(0.045)
	angles = angles.limit_length(0.045)
	pose = Transform3D(Basis.from_euler(angles), offset)
