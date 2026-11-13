extends SkeletonModifier3D
## Original procedural performance inspired by How to Fish's inspected IK/body
## architecture. Authored locomotion remains the base; this runs after animation.
var shooter
var world
var remote_charge := 0.0
var eat_left := 0.0
var clock := 0.0
var kick := 0.0
var pressure := 0.0
var previous_fire := false
var reach_left := 0.0
var reach_world := Vector3.ZERO
var bones := {}
var feet := {}
var last_position := Vector3.ZERO
var initialized := false
var previous_slot := -1
var equip_left := 0.0

## Where the hands hold a bottle stood on end to be shaken, from its socket.
const GRIP_SPREAD := 0.17
const GRIP_LIFT := 0.30


func configure(owner_shooter, owner_world) -> void:
	shooter = owner_shooter
	world = owner_world
	var skeleton := get_skeleton()
	for label in ["Hips", "Spine", "Spine1", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "SauceTubeSocket"]:
		bones[label] = skeleton.find_bone("SauceTubeSocket" if label == "SauceTubeSocket" else "mixamorig_" + label)
	last_position = shooter.player.global_position
	initialized = true

func reach_for(at: Vector3) -> void:
	reach_world = at
	reach_left = 0.48

func _process_modification() -> void:
	if not initialized or not is_instance_valid(shooter.player):
		return
	var dt := minf(get_process_delta_time(), 0.05)
	clock += dt
	var body = shooter.player
	var skeleton := get_skeleton()
	var teleported: bool = body.global_position.distance_to(last_position) > 3.0
	last_position = body.global_position
	if teleported:
		feet.clear()
	# Authored falls, death and resurrection own the complete pose.
	if body.state != MayoPlayer.State.NORMAL:
		feet.clear()
		kick = 0.0
		pressure = 0.0
		reach_left = 0.0
		eat_left = 0.0
		previous_fire = false
		return
	var firing: bool = shooter.was_firing
	if firing and not previous_fire:
		kick = 1.0
	previous_fire = firing
	kick *= exp(-dt * 13.0)
	pressure = lerpf(pressure, 1.0 if firing else 0.0, 1.0 - exp(-dt * 10.0))
	reach_left = maxf(0.0, reach_left - dt)
	eat_left = maxf(0.0, eat_left - dt)
	var local_velocity: Vector3 = body.global_basis.inverse() * body.velocity
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	var moving := clampf(speed / body.run_speed, 0.0, 1.0)
	_rotate("Spine", Vector3(clampf(-local_velocity.z * 0.012, -0.12, 0.12), 0.0, clampf(-local_velocity.x * 0.012, -0.12, 0.12)))
	_rotate("Spine1", Vector3(sin(clock * 2.1) * 0.012, 0.0, sin(clock * 3.4) * moving * 0.018))
	_rotate("Head", Vector3(clampf(shooter.aim_pitch, -0.65, 0.65) * 0.45, 0.0, 0.0))
	# Move the tube socket and BOTH palm targets together so recoil never breaks grip.
	var socket: int = bones["SauceTubeSocket"]
	var displacement: Vector3 = body.global_basis * Vector3(0.0, kick * 0.08 + pressure * 0.035, kick * 0.09 + pressure * 0.025)
	# Shaking the bottle: the tube and both hands come up and go up and down
	# together, and the tube is stood on end -- see below.
	var upright: float = smoothstep(0.0, 1.0, shooter.bottle_shake_pose)
	if upright > 0.001:
		displacement += body.global_basis * (Vector3(0.0, 0.22, 0.0) * upright \
			+ Vector3(0.0, sin(clock * 42.0) * 0.16, 0.0) * shooter.bottle_shake_show)
	var slot: int = world.selected_item_slot(shooter.peer_id)
	if slot != previous_slot:
		equip_left = 0.3
		previous_slot = slot
	equip_left = maxf(0.0, equip_left - dt)
	displacement += body.global_basis * Vector3(0.0, -0.18, 0.08) * pow(equip_left / 0.3, 2.0)
	var hand_targets := {}
	for side in ["Left", "Right"]:
		var hand: int = bones[side + "Hand"]
		if hand >= 0:
			hand_targets[side] = skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin + displacement
	if socket >= 0:
		var pose := skeleton.get_bone_global_pose(socket)
		pose.origin += skeleton.global_basis.inverse() * displacement
		if upright > 0.001:
			# Tipped about the body's own side-to-side axis, so the nozzle that
			# pointed ahead points up.
			var side: Vector3 = (skeleton.global_basis.inverse() * body.global_basis.x).normalized()
			pose.basis = Basis(side, deg_to_rad(world.BOTTLE_SHAKE_UPRIGHT_DEGREES) * upright) * pose.basis
			# Both hands come in to hold it where it now stands, one either side.
			var grip: Vector3 = skeleton.global_transform * pose.origin
			for hand_side in hand_targets:
				var across := -GRIP_SPREAD if hand_side == "Left" else GRIP_SPREAD
				hand_targets[hand_side] = (hand_targets[hand_side] as Vector3).lerp(
					grip + body.global_basis * Vector3(across, GRIP_LIFT, 0.0), upright)
		skeleton.set_bone_global_pose(socket, pose)
	for side in hand_targets:
		var target: Vector3 = hand_targets[side]
		if side == "Right":
			var held = world._held_tomatoes.get(shooter.peer_id)
			if not is_instance_valid(held) and world._healing_tomatoes.has(-shooter.peer_id):
				held = world._healing_tomatoes[-shooter.peer_id].node
			if slot > 0 and is_instance_valid(held):
				target = held.global_position + body.global_basis * Vector3(0.0, -0.08, 0.12)
			var throw_time: float = world._item_throw_time.get(shooter.peer_id, 0.0)
			if throw_time > 0.0:
				target += body.global_basis * Vector3(0.0, 0.2, -0.35) * sin(clampf(throw_time / 0.3, 0.0, 1.0) * PI)
			if eat_left > 0.0:
				target = target.lerp(body.global_position + body.global_basis * Vector3(0.0, 0.8, -0.22), sin(eat_left / 0.48 * PI))
			if body.wipe_timer > 0.0:
				target = body.global_position + body.global_basis * Vector3(sin(clock * 18.0) * 0.15, 0.85, -0.25)
		if side == "Right" and reach_left > 0.0:
			var weight := sin((1.0 - reach_left / 0.48) * PI)
			target = target.lerp(reach_world, weight)
		_solve(side + "Arm", side + "ForeArm", side + "Hand", target, body.global_basis * Vector3(-1.0 if side == "Left" else 1.0, -0.3, 0.2))
	# Preserve the authored stride and adapt its foot endpoints to nearby ground.
	for side in ["Left", "Right"]:
		_ground_foot(side, dt, speed)

func _rotate(label: String, angles: Vector3) -> void:
	var index: int = bones.get(label, -1)
	if index < 0:
		return
	var skeleton := get_skeleton()
	var rotation := skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, rotation * Quaternion.from_euler(angles))

func _solve(upper_name: String, middle_name: String, end_name: String, target_world: Vector3, pole_world: Vector3) -> void:
	var skeleton := get_skeleton()
	var upper: int = bones.get(upper_name, -1)
	var middle: int = bones.get(middle_name, -1)
	var end: int = bones.get(end_name, -1)
	if mini(upper, mini(middle, end)) < 0:
		return
	var end_basis := skeleton.get_bone_global_pose(end).basis
	var inverse := skeleton.global_transform.affine_inverse()
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(middle).origin
	var c := skeleton.get_bone_global_pose(end).origin
	var target := inverse * target_world
	var length_a := a.distance_to(b)
	var length_b := b.distance_to(c)
	if minf(length_a, length_b) < 0.0001:
		return
	var direction := (target - a).normalized()
	if direction.length_squared() < 0.5:
		return
	var distance := clampf(a.distance_to(target), absf(length_a - length_b) + 0.0001, (length_a + length_b) * 0.995)
	var pole := b - a
	if pole.cross(direction).length_squared() < 0.00001:
		pole = skeleton.global_basis.inverse() * pole_world
	pole = (pole - direction * pole.dot(direction)).normalized()
	if pole.length_squared() < 0.5:
		pole = direction.cross(Vector3.RIGHT).normalized()
	var along := (length_a * length_a + distance * distance - length_b * length_b) / (2.0 * distance)
	var elbow := a + direction * along + pole * sqrt(maxf(0.0, length_a * length_a - along * along))
	var pose := skeleton.get_bone_global_pose(upper)
	pose.basis = Basis(Quaternion((b - a).normalized(), (elbow - a).normalized())) * pose.basis
	skeleton.set_bone_global_pose(upper, pose)
	var end_point := a + direction * distance
	pose = skeleton.get_bone_global_pose(middle)
	pose.origin = elbow
	pose.basis = Basis(Quaternion((c - b).normalized(), (end_point - elbow).normalized())) * pose.basis
	skeleton.set_bone_global_pose(middle, pose)
	pose = skeleton.get_bone_global_pose(end)
	pose.origin = end_point
	pose.basis = end_basis
	skeleton.set_bone_global_pose(end, pose)

func _ground_foot(side: String, dt: float, speed: float) -> void:
	var body = shooter.player
	if not body.is_on_floor():
		feet.erase(side)
		return
	var skeleton := get_skeleton()
	var index: int = bones.get(side + "Foot", -1)
	if index < 0:
		return
	var point := skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point - Vector3.UP * 0.5, body.collision_mask)
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		feet.erase(side)
		return
	# Only correct feet close to contact; never flatten the authored swing arc.
	var floor_point: Vector3 = hit.position + Vector3.UP * 0.07
	if point.y - floor_point.y > 0.22:
		feet.erase(side)
		return
	var target: Vector3 = feet.get(side, floor_point)
	if speed > 0.3 or target.distance_to(floor_point) > 0.3:
		target = target.lerp(floor_point, 1.0 - exp(-dt * 24.0))
	feet[side] = target
	_solve(side + "UpLeg", side + "Leg", side + "Foot", target, body.global_basis * Vector3(0.0, 0.0, -1.0))
