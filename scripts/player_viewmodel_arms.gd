extends Node3D
## View-only limbs: never supply collision, aim or projectile origins.
var shooter
var world
var limbs: Array[MeshInstance3D] = []
var palms: Array[Node3D] = []
func configure(owner_shooter, owner_world) -> void:
	shooter = owner_shooter
	world = owner_world
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color("e3ddd1")
	sleeve.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("dca780")
	skin.roughness = 0.85
	for side in 2:
		for segment in 2:
			var mesh := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.065 if segment == 0 else 0.047
			capsule.height = 0.3
			capsule.radial_segments = 10
			mesh.mesh = capsule
			mesh.material_override = sleeve if segment == 0 else skin
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)
			limbs.append(mesh)
		var palm := Node3D.new()
		add_child(palm)
		palms.append(palm)
		for finger in 5:
			var mesh := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.018
			capsule.height = 0.095 if finger < 4 else 0.07
			capsule.radial_segments = 8
			mesh.mesh = capsule
			mesh.material_override = skin
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			palm.add_child(mesh)
			mesh.position = Vector3((finger - 1.5) * 0.029, -0.015, -0.025)
			mesh.rotation = Vector3(0.95, 0.0, 0.12 * (finger - 2))
func _process(_dt: float) -> void:
	if shooter == null or not is_instance_valid(shooter.player):
		return
	visible = shooter.is_local and world._first_person and shooter.player.state == MayoPlayer.State.NORMAL
	if not visible:
		return
	transform = shooter.weapon.transform
	var sway: Transform3D = shooter.weapon_sway.transform
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var shoulder := Vector3(sign_x * 0.32, -0.52, 0.36)
		var elbow := Vector3(sign_x * 0.24, -0.28, 0.16)
		var hand := sway * Vector3(sign_x * 0.07, -0.035, -0.12)
		var motion = shooter.procedural_motion
		if side == 1 and is_instance_valid(motion):
			var held = world._held_tomatoes.get(shooter.peer_id)
			if not is_instance_valid(held) and world._healing_tomatoes.has(-shooter.peer_id):
				held = world._healing_tomatoes[-shooter.peer_id].node
			if world.selected_item_slot(shooter.peer_id) > 0 and is_instance_valid(held):
				hand = to_local(held.global_position) + Vector3(0.0, -0.08, 0.1)
			if motion.reach_left > 0.0:
				var reach := to_local(motion.reach_world)
				reach = shoulder + (reach - shoulder).limit_length(0.65)
				hand = hand.lerp(reach, sin((1.0 - motion.reach_left / 0.48) * PI))
			if motion.eat_left > 0.0:
				hand = hand.lerp(Vector3(-0.15, 0.08, 0.05), sin(motion.eat_left / 0.48 * PI))
			var throw_left: float = world._item_throw_time.get(shooter.peer_id, 0.0)
			hand.z -= sin(clampf(throw_left / 0.3, 0.0, 1.0) * PI) * 0.22
		if shooter.player.wipe_timer > 0.0 and side == 1:
			hand = Vector3(-0.2 + sin(Time.get_ticks_msec() * 0.018) * 0.12, 0.12, -0.12)
		_segment(limbs[side * 2], shoulder, elbow)
		_segment(limbs[side * 2 + 1], elbow, hand)
		palms[side].position = hand
func _segment(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	mesh.position = (start + end) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	mesh.scale.y = start.distance_to(end) / 0.3
