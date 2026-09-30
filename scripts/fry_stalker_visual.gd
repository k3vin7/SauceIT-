class_name FryStalkerVisual
extends Node3D

## Runtime presentation for the user-authored Production_FryStalker asset.
##
## The source Blender build describes a 2 x 2 x 4.2 metre french-fry carton
## creature with eight three-piece legs.  Blender is not required at runtime:
## this node rebuilds that low-poly silhouette from engine primitives and drives
## the same sequential arthropod gait and front-pair slam described by the
## source actions.

const SOURCE_HEIGHT := 4.2
const STRIDE := 2.10
const STANCE_SHARE := 0.62
const STEP_REACH := 0.52
const STEP_LIFT := 0.50

var _legs: Array[Dictionary] = []
var _distance := 0.0
var _walking := false
var _attack_elapsed := 0.0
var _attack_duration := 0.0
var _attacking := false
var _body: Node3D

var _red: StandardMaterial3D
var _red_dark: StandardMaterial3D
var _fry: StandardMaterial3D
var _crisp: StandardMaterial3D
var _cream: StandardMaterial3D
var _black: StandardMaterial3D
var _sclera: StandardMaterial3D
var _iris: StandardMaterial3D


func _ready() -> void:
	if _body == null:
		_build()
	set_process(true)


func set_motion(distance_covered: float, walking: bool) -> void:
	_distance = distance_covered
	_walking = walking


func play_slam(duration: float) -> void:
	_attack_duration = maxf(duration, 0.01)
	_attack_elapsed = 0.0
	_attacking = true


func is_slamming() -> bool:
	return _attacking


func debug_foot_position(index: int) -> Vector3:
	if index < 0 or index >= _legs.size():
		return Vector3.ZERO
	return _legs[index]["foot"]


func _process(delta: float) -> void:
	if _body == null:
		return
	if _attacking:
		_attack_elapsed += delta
		if _attack_elapsed >= _attack_duration:
			_attacking = false
			_attack_elapsed = 0.0

	var attack_t := clampf(_attack_elapsed / maxf(_attack_duration, 0.01), 0.0, 1.0) \
		if _attacking else -1.0
	for index in _legs.size():
		_animate_leg(index, attack_t)

	var bob := 0.0
	var roll := 0.0
	if _walking and not _attacking:
		var turn := _distance / STRIDE * TAU
		bob = (1.0 - cos(turn * 2.0)) * 0.035
		roll = sin(turn) * 0.025
	if _attacking:
		var drive := _slam_curve(attack_t)
		bob = -0.13 * drive
		_body.rotation.x = -0.14 * drive
	else:
		_body.rotation.x = 0.0
	_body.position.y = bob
	_body.rotation.z = roll


func _build() -> void:
	_red = _material(Color("9e0b06"), 0.82)
	_red_dark = _material(Color("450302"), 0.9)
	_fry = _material(Color("ff8c13"), 0.72)
	_crisp = _material(Color("b83d09"), 0.8)
	_cream = _material(Color("ffcc3d"), 0.65)
	_black = _material(Color("020201"), 0.55)
	_sclera = _material(Color("b8e08f"), 0.42)
	_iris = _material(Color("8c0302"), 0.34)

	_body = Node3D.new()
	_body.name = "FryStalkerBody"
	add_child(_body)

	_add_box(_body, "CartonLeft", Vector3(0.80, 2.0, 1.02),
		Vector3(-0.41, 2.72, 0.0), _red)
	_add_box(_body, "CartonRight", Vector3(0.80, 2.0, 1.02),
		Vector3(0.41, 2.72, 0.0), _red)
	_add_box(_body, "CartonInterior", Vector3(1.38, 0.16, 0.90),
		Vector3(0.0, 3.61, 0.0), _red_dark)

	_add_sphere(_body, "CyclopsSocket", Vector3(0.0, 2.60, -0.58),
		Vector3(0.67, 0.67, 0.22), _black)
	_add_sphere(_body, "CyclopsSclera", Vector3(0.0, 2.60, -0.63),
		Vector3(0.54, 0.54, 0.16), _sclera)
	_add_sphere(_body, "CyclopsIris", Vector3(0.0, 2.60, -0.68),
		Vector3(0.40, 0.40, 0.11), _iris)
	_add_sphere(_body, "CyclopsPupil", Vector3(0.0, 2.60, -0.72),
		Vector3(0.29, 0.29, 0.08), _black)
	_add_sphere(_body, "CyclopsGlint", Vector3(-0.06, 2.68, -0.76),
		Vector3(0.06, 0.06, 0.035), _cream)

	# Original angular seasoning-bolt emblem from the Blender source.
	var logo := [
		Vector3(-0.43, 3.28, -0.60), Vector3(-0.14, 3.05, -0.60),
		Vector3(-0.02, 3.31, -0.60), Vector3(0.16, 2.98, -0.60),
		Vector3(0.43, 3.29, -0.60),
	]
	for index in logo.size() - 1:
		_add_segment(_body, "Emblem%02d" % index, logo[index], logo[index + 1],
			0.055, _cream, 8)

	var fry_tops := [
		[-0.56, 3.48, 4.12, -0.68], [-0.38, 3.52, 4.20, -0.30],
		[-0.18, 3.50, 4.08, -0.12], [0.02, 3.50, 4.16, 0.10],
		[0.22, 3.48, 4.10, 0.26], [0.40, 3.50, 4.18, 0.48],
		[0.57, 3.46, 4.10, 0.70],
	]
	for index in fry_tops.size():
		var spec: Array = fry_tops[index]
		var a := Vector3(spec[0], spec[1], 0.0)
		var b := Vector3(spec[3], spec[2], 0.0)
		_add_segment(_body, "Fry%02d" % index, a, b, 0.075, _fry, 8)
		_add_sphere(_body, "FryTip%02d" % index, b, Vector3.ONE * 0.085, _crisp, 8, 4)

	# Blender coordinates (x, y, z) become Godot (x, z, y); -z is forward.
	var authored := [
		[Vector3(-0.30,2.08,-0.49), Vector3(-0.42,1.28,-0.78), Vector3(-0.56,0.52,-0.88), Vector3(-0.64,0.03,-0.97)],
		[Vector3(0.30,2.08,-0.49), Vector3(0.42,1.28,-0.78), Vector3(0.56,0.52,-0.88), Vector3(0.64,0.03,-0.97)],
		[Vector3(-0.59,2.02,-0.27), Vector3(-0.82,1.18,-0.46), Vector3(-0.89,0.42,-0.56), Vector3(-0.97,0.03,-0.66)],
		[Vector3(0.59,2.02,-0.27), Vector3(0.82,1.18,-0.46), Vector3(0.89,0.42,-0.56), Vector3(0.97,0.03,-0.66)],
		[Vector3(-0.59,2.02,0.27), Vector3(-0.82,1.18,0.46), Vector3(-0.89,0.42,0.56), Vector3(-0.97,0.03,0.66)],
		[Vector3(0.59,2.02,0.27), Vector3(0.82,1.18,0.46), Vector3(0.89,0.42,0.56), Vector3(0.97,0.03,0.66)],
		[Vector3(-0.30,2.08,0.49), Vector3(-0.42,1.28,0.78), Vector3(-0.56,0.52,0.88), Vector3(-0.64,0.03,0.97)],
		[Vector3(0.30,2.08,0.49), Vector3(0.42,1.28,0.78), Vector3(0.56,0.52,0.88), Vector3(0.64,0.03,0.97)],
	]
	for index in authored.size():
		var leg_root := Node3D.new()
		leg_root.name = "Leg%02d" % index
		_body.add_child(leg_root)
		var pieces: Array[MeshInstance3D] = []
		for piece in 3:
			var mesh := MeshInstance3D.new()
			mesh.name = "FryPiece%d" % piece
			var shape := CylinderMesh.new()
			shape.top_radius = [0.070, 0.052, 0.012][piece]
			shape.bottom_radius = [0.094, 0.070, 0.052][piece]
			shape.height = 1.0
			shape.radial_segments = 8
			shape.rings = 1
			shape.material = _fry
			mesh.mesh = shape
			leg_root.add_child(mesh)
			pieces.push_back(mesh)
		_legs.push_back({
			"root": leg_root,
			"pieces": pieces,
			"hip": authored[index][0],
			"rest_knee": authored[index][1],
			"rest_ankle": authored[index][2],
			"rest_foot": authored[index][3],
			"foot": authored[index][3],
		})
	for index in _legs.size():
		_animate_leg(index, -1.0)


func _animate_leg(index: int, attack_t: float) -> void:
	var leg: Dictionary = _legs[index]
	var hip: Vector3 = leg["hip"]
	var rest_foot: Vector3 = leg["rest_foot"]
	var foot := rest_foot

	if attack_t >= 0.0 and index < 2:
		var side := -1.0 if index == 0 else 1.0
		if attack_t < 0.24:
			var t := _ease(attack_t / 0.24)
			foot = rest_foot.lerp(Vector3(0.82 * side, 1.05, -1.42), t)
		elif attack_t < 0.40:
			var t := _ease((attack_t - 0.24) / 0.16)
			foot = Vector3(0.82 * side, 1.05, -1.42).lerp(
				Vector3(0.76 * side, 0.015, -1.55), t)
		elif attack_t < 0.82:
			# The claws are visibly buried and do not slide during the punish window.
			foot = Vector3(0.76 * side, -0.025, -1.55)
		else:
			foot = Vector3(0.76 * side, -0.025, -1.55).lerp(rest_foot,
				_ease((attack_t - 0.82) / 0.18))
	elif _walking and attack_t < 0.0:
		var phase := fposmod(_distance / STRIDE + float(index) * 0.125, 1.0)
		if phase < STANCE_SHARE:
			var through := phase / STANCE_SHARE
			foot.z += lerpf(STEP_REACH, -STEP_REACH, through)
		else:
			var through := (phase - STANCE_SHARE) / (1.0 - STANCE_SHARE)
			foot.z += lerpf(-STEP_REACH, STEP_REACH, _ease(through))
			foot.y += sin(through * PI) * STEP_LIFT
		foot.x += sin(phase * TAU) * 0.11 * (-1.0 if index % 2 == 0 else 1.0)

	var out := Vector3(signf(rest_foot.x), 0.0, 0.0)
	var bend := 0.0
	if _walking and attack_t < 0.0:
		var phase := fposmod(_distance / STRIDE + float(index) * 0.125, 1.0)
		bend = absf(sin(phase * TAU))
	var lift := maxf(foot.y - rest_foot.y, 0.0)
	var knee := hip.lerp(foot, 0.40) + out * (0.34 + bend * 0.18) \
		+ Vector3.UP * (0.27 + lift * 0.55)
	var ankle := hip.lerp(foot, 0.74) + out * (0.18 + bend * 0.09) \
		+ Vector3.UP * (0.11 + lift * 0.22)
	if attack_t >= 0.0 and index < 2:
		knee.z -= 0.18
		ankle.z -= 0.10
	_set_piece(leg["pieces"][0], hip, knee)
	_set_piece(leg["pieces"][1], knee, ankle)
	_set_piece(leg["pieces"][2], ankle, foot)
	leg["foot"] = foot
	_legs[index] = leg


func _slam_curve(t: float) -> float:
	if t < 0.24:
		return _ease(t / 0.24) * 0.35
	if t < 0.40:
		return lerpf(0.35, 1.0, _ease((t - 0.24) / 0.16))
	if t < 0.82:
		return 1.0
	return 1.0 - _ease((t - 0.82) / 0.18)


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _set_piece(piece: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var span := b - a
	if span.length_squared() < 0.000001:
		return
	var basis := _aligned_basis(span)
	basis.y *= span.length()
	piece.transform = Transform3D(basis, (a + b) * 0.5)


func _aligned_basis(span: Vector3) -> Basis:
	var y_axis := span.normalized()
	var reference := Vector3.FORWARD if absf(y_axis.z) < 0.9 else Vector3.RIGHT
	var x_axis := reference.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, x_axis.cross(y_axis))


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _add_box(parent: Node3D, node_name: String, size: Vector3, at: Vector3,
		material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


func _add_sphere(parent: Node3D, node_name: String, at: Vector3, scale: Vector3,
		material: Material, radial := 16, rings := 8) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = radial
	mesh.rings = rings
	mesh.material = material
	node.mesh = mesh
	node.position = at
	node.scale = scale
	parent.add_child(node)
	return node


func _add_segment(parent: Node3D, node_name: String, a: Vector3, b: Vector3,
		radius: float, material: Material, sides: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = sides
	mesh.material = material
	node.mesh = mesh
	parent.add_child(node)
	_set_piece(node, a, b)
	return node
