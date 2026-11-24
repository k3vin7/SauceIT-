extends Node3D

const SHUTTER_SIZE := Vector3(4.14, 3.52, 0.22)
const TIMBER := [Color("684336"), Color("7c5140"), Color("725045")]
const TRUCK_PAINT := Color("60877f")

var solid: ContaminableObject
var enemy: MayoEnemy
var tag: StringName
var leg: int
var windup := 0.0
var charge := Vector3.ZERO
var parking_cells: Array[Vector2i] = []
var opened := false
var played_break := false
var _home := Vector3.ZERO
var _enemy_layer := 0
var _truck := false
var _boards := Node3D.new()
var _pieces: Array[MeshInstance3D] = []
var _dust: CPUParticles3D
var _rattle: Tween
var _fragments: Node3D


func build(body: MayoEnemy, wall: ContaminableObject, cab: ContaminableObject) -> void:
	solid = wall
	enemy = body
	_home = body.global_position
	_enemy_layer = body.collision_layer
	global_position = wall.global_position
	add_child(_boards)
	_truck = cab != null
	if _truck:
		_build_truck(cab)
	else:
		_build_shutter()
	_build_dust()
	reset()


func _build_shutter() -> void:
	var plank_width := SHUTTER_SIZE.x / 8.0
	for column in 8:
		var x := -SHUTTER_SIZE.x * 0.5 + plank_width * (float(column) + 0.5)
		var split := 0.14 * float(column % 3 - 1)
		for row in 2:
			var low := -SHUTTER_SIZE.y * 0.5 if row == 0 else split
			var high := split if row == 0 else SHUTTER_SIZE.y * 0.5
			_pieces.append(_box(_boards, Vector3(x, (low + high) * 0.5, 0.0),
				Vector3(plank_width - 0.022, high - low - 0.01, SHUTTER_SIZE.z), TIMBER[column % TIMBER.size()]))
	for y in [-0.91, 0.92]:
		for x in [-SHUTTER_SIZE.x * 0.25, SHUTTER_SIZE.x * 0.25]:
			_pieces.append(_box(_boards, Vector3(x, y, -0.14),
				Vector3(SHUTTER_SIZE.x * 0.5 - 0.045, 0.20, 0.10), Color("48352c")))
	_box(self, Vector3(0.0, SHUTTER_SIZE.y * 0.5 - 0.08, -0.17),
		Vector3(SHUTTER_SIZE.x + 0.16, 0.22, 0.25), Color("534039"))
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * (SHUTTER_SIZE.x * 0.5 - 0.04), 0.0, -0.17),
			Vector3(0.12, SHUTTER_SIZE.y, 0.20), Color("534039"))


func _build_truck(cab: ContaminableObject) -> void:
	var half := solid.size * 0.5
	var steel := Color("3c423d")
	var glass := Color("283d43")
	var cargo_height := solid.size.y - 0.63
	var panel_y := half.y - cargo_height * 0.5
	for side: float in [-1.0, 1.0]:
		# Split the sheet metal into sections so the roof and doors buckle outwards.
		for depth: float in [-0.5, 0.5]:
			var x := side * (half.x - 0.07)
			var z := depth * half.z
			_pieces.append(_box(_boards, Vector3(x, panel_y, z),
				Vector3(0.14, cargo_height, half.z - 0.018), TRUCK_PAINT))
			_pieces.append(_box(_boards, Vector3(x + side * 0.06, panel_y + 0.38, z),
				Vector3(0.04, 0.18, half.z - 0.025), Color("a6b7a0")))
		_pieces.append(_box(_boards, Vector3(side * half.x * 0.5, half.y - 0.07, 0.0),
			Vector3(half.x - 0.025, 0.14, solid.size.z), TRUCK_PAINT.lightened(0.17)))
		_pieces.append(_box(_boards, Vector3(side * half.x * 0.5, panel_y, -half.z + 0.055),
			Vector3(half.x - 0.04, cargo_height, 0.11), TRUCK_PAINT.darkened(0.22)))
		_pieces.append(_box(_boards, Vector3(side * 0.22, panel_y - 0.22, -half.z - 0.045),
			Vector3(0.09, 0.34, 0.09), steel))
	_box(_boards, Vector3(0.0, panel_y, half.z - 0.06),
		Vector3(solid.size.x, cargo_height, 0.12), TRUCK_PAINT)
	_box(self, Vector3(0.0, -half.y + 0.26, 0.87), Vector3(3.25, 0.25, 5.58), steel)
	var nose := to_local(cab.global_position)
	_box(self, nose + Vector3.DOWN * 0.2, cab.size - Vector3(0.13, 0.41, 0.06), Color("b6c3a0"))
	_box(self, nose + Vector3(0.0, 0.44, cab.size.z * 0.5), Vector3(2.72, 0.92, 0.065), glass)
	_box(self, nose + Vector3(0.0, -0.83, cab.size.z * 0.5 + 0.015), Vector3(3.45, 0.24, 0.18), steel)
	var tire := CylinderMesh.new()
	tire.top_radius = 0.53
	tire.bottom_radius = 0.53
	tire.height = 0.33
	tire.radial_segments = 12
	tire.material = _material(Color("242724"))
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(side * 1.30, -half.y + 0.36, -half.z - 0.025),
			Vector3(0.36, 0.18, 0.10), Color("993930"))
		_box(self, nose + Vector3(side * 1.73, 0.44, 0.17), Vector3(0.06, 0.77, 1.0), glass)
		_box(self, nose + Vector3(side * 1.19, -0.53, cab.size.z * 0.5), Vector3(0.57, 0.26, 0.09), Color("e6ce8f"))
		for axle: float in [-1.03, 2.65]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = tire
			wheel.position = Vector3(side * 1.55, -half.y + 0.53, axle)
			wheel.rotation.z = PI * 0.5
			add_child(wheel)


func _build_dust() -> void:

	var puff := SphereMesh.new()
	puff.radius = 0.17
	puff.height = 0.34
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = _material(Color("ac9474"))
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.amount = 26
	_dust.lifetime = 0.52
	_dust.spread = 55.0
	_dust.initial_velocity_min = 2.5
	_dust.initial_velocity_max = 7.0
	_dust.gravity = Vector3.DOWN * 5.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.5, 0.85, 0.10)
	_dust.mesh = puff
	if _truck:
		_dust.position.z = -solid.size.z * 0.47
	add_child(_dust)


func rattle(seconds: float) -> void:
	if opened:
		return
	_rattle = _boards.create_tween()
	_rattle.tween_property(_boards, "position:z", -0.14, seconds * 0.2)
	_rattle.tween_property(_boards, "position:z", 0.0, seconds * 0.3)
	_rattle.tween_property(_boards, "position:z", -0.10, seconds * 0.2)
	_rattle.tween_property(_boards, "position:z", 0.0, seconds * 0.3)


func set_open(value: bool) -> void:
	opened = value
	solid.collision_layer = 0 if value else 1
	solid.visible = not value
	if _rattle != null:
		_rattle.kill()
		_rattle = null
	_boards.position = Vector3.ZERO
	_boards.visible = not value
	enemy.hidden_in_breakout = not value
	enemy.visible = value
	if enemy.is_alive():
		enemy.collision_layer = _enemy_layer if value else 0
	for cell in parking_cells:
		enemy.nav.grid.set_point_solid(cell, not value)
	if not value:
		played_break = false
		_dust.emitting = false
		if is_instance_valid(_fragments):
			_fragments.queue_free()


func reset() -> void:
	windup = 0.0
	enemy.apply_network_state(_home, 0.0, enemy.max_health, 0.0, enemy.max_health)
	enemy.velocity = Vector3.ZERO
	enemy._charge_left = 0.0
	enemy._windup = 0.0
	enemy._attack_lock_left = 0.0
	enemy._shove = Vector3.ZERO
	enemy._blast_push = Vector3.ZERO
	enemy.mustard_slow = 0.0
	enemy.vanished = false
	enemy._visual_root.show()
	enemy.get_node("Body").set_deferred("disabled", false)
	set_open(false)


func burst(direction: Vector3) -> void:
	played_break = true
	_dust.direction = direction + Vector3.UP * 0.24
	_dust.restart()
	_fragments = Node3D.new()
	add_child(_fragments)
	var flight := _fragments.create_tween().set_parallel()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12491
	for source in _pieces:
		var piece := source.duplicate() as MeshInstance3D
		_fragments.add_child(piece)
		var speed := direction * rng.randf_range(3.0, 7.0) + Vector3(
			piece.position.x * 1.8, rng.randf_range(1.4, 4.7), 0.0)
		var spin := Vector3(rng.randf_range(4.0, 9.0), rng.randf_range(-5.0, 5.0),
			rng.randf_range(-5.0, 5.0))
		flight.tween_method(_throw_piece.bind(piece, piece.position, speed, spin), 0.0, 1.05, 1.05)
	flight.chain().tween_callback(_fragments.queue_free)


func _throw_piece(time: float, piece: MeshInstance3D, start: Vector3,
		speed: Vector3, spin: Vector3) -> void:
	piece.position = start + speed * time + Vector3.DOWN * (6.0 * time * time)
	piece.position.y = maxf(piece.position.y, -solid.size.y * 0.5 + 0.08)
	piece.rotation = spin * time
	piece.scale = Vector3.ONE * (1.0 - smoothstep(0.66, 1.05, time))


func _box(parent: Node3D, at: Vector3, extent: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
