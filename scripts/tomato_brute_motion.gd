extends Node3D

const WALK_CYCLES := 2.4
const CHARGE_CYCLES := 7.5

static var _thigh_mesh: CylinderMesh
static var _shin_mesh: CylinderMesh
static var _shoe_mesh: SphereMesh

var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _shoes: Array[MeshInstance3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _torso: Node3D
var _phase := 0.0
var _stride := 0.0
var _rush := 0.0
var _anger := 0.0
var _face_rest := {}


func build(radius: float, shoulders: Array[Node3D], torso: Node3D) -> void:
	name = "BruteMotion"
	scale = Vector3.ONE * radius
	_shoulders = shoulders
	_torso = torso
	for part_name in ["BrowL", "BrowR", "CrookedGrin"]:
		var part := torso.get_node(part_name) as Node3D
		_face_rest[part] = part.transform
	for shoulder in _shoulders:
		_elbows.append(shoulder.get_node("Elbow"))
	if _thigh_mesh == null:
		_thigh_mesh = _segment_mesh(0.18, 0.135, Color("79291d"))
		_shin_mesh = _segment_mesh(0.138, 0.105, Color("963321"))
		_shoe_mesh = SphereMesh.new()
		_shoe_mesh.radius = 1.0
		_shoe_mesh.height = 2.0
		_shoe_mesh.radial_segments = 10
		_shoe_mesh.rings = 4
		_shoe_mesh.material = _pigment(Color("70271e"))
	for suffix in ["L", "R"]:
		_thighs.append(_part("Thigh" + suffix, _thigh_mesh))
		_shins.append(_part("Shin" + suffix, _shin_mesh))
		var shoe := _part("Shoe" + suffix, _shoe_mesh)
		shoe.scale = Vector3(0.19, 0.11, 0.27)
		_shoes.append(shoe)
	reset_pose()


func advance_pose(delta: float, moving: bool, charging: bool) -> void:
	if not moving and not charging and _stride == 0.0:
		return
	_stride = move_toward(_stride, 1.0 if moving or charging else 0.0, delta * 12.0)
	_rush = move_toward(_rush, 1.0 if charging else 0.0, delta * 18.0)
	_phase = fposmod(_phase + TAU * delta * lerpf(WALK_CYCLES, CHARGE_CYCLES, _rush), TAU)
	_pose()


func advance_expression(delta: float, alerted: bool) -> void:
	_anger = move_toward(_anger, 1.0 if alerted else 0.0,
		delta / (0.28 if alerted else 0.65))
	var blend := smoothstep(0.0, 1.0, _anger)
	for part: Node3D in _face_rest:
		var rest: Transform3D = _face_rest[part]
		part.transform = rest
		if part.name == &"CrookedGrin":
			part.rotation.z = lerpf(-0.17, 0.10, blend)
			part.scale.y = lerpf(1.0, 0.68, blend)
		else:
			var side := -1.0 if part.name == &"BrowL" else 1.0
			part.position.y += scale.x * 0.035 * blend
			part.position.z -= scale.x * 0.04 * blend
			part.rotation.z = lerpf(part.rotation.z, side * 0.48, blend)


func reset_pose() -> void:
	_phase = 0.0
	_stride = 0.0
	_rush = 0.0
	_pose()


func _pose() -> void:
	# Weight shifts over the supporting foot. Shoulders counter-rotate
	# against the stride, while both footfalls produce a small vertical bounce.
	var sway := sin(_phase) * _stride
	_torso.rotation = Vector3(
		0.055 * _rush * _stride,
		-cos(_phase) * lerpf(0.025, 0.045, _rush) * _stride,
		-sway * lerpf(0.035, 0.060, _rush))
	_torso.position = Vector3(
		sway * lerpf(0.018, 0.030, _rush),
		(1.0 - cos(_phase * 2.0)) * lerpf(0.008, 0.014, _rush) * _stride,
		0.0) * scale.x
	for index in 2:
		var phase := _phase + PI * index
		var x := -0.40 if index == 0 else 0.40
		var swing := cos(phase) * _stride
		var lift := maxf(sin(phase), 0.0) * _stride
		# The hip follows the torso, while the planted ankle stays in its
		# ground frame so the body recoil does not drag the feet sideways.
		var hip := (_torso.transform * (Vector3(x, -0.38, 0.0) * scale.x)) / scale.x
		var ankle := Vector3(x, -0.84 + lift * lerpf(0.13, 0.25, _rush),
			swing * lerpf(0.21, 0.39, _rush))
		var knee := hip.lerp(ankle, 0.52) + Vector3(0.0, 0.0, -0.11 - lift * 0.12)
		_fit(_thighs[index], hip, knee)
		_fit(_shins[index], knee, ankle)
		_shoes[index].position = ankle + Vector3(0.0, -0.05, -0.08)
		# The shoulder drives the hand opposite its foot. The elbow folds
		# into the forward stroke and opens as the fist swings behind.
		_shoulders[index].rotation.x = 0.12 * _rush + swing * lerpf(0.30, 0.96, _rush)
		_elbows[index].rotation.x = maxf(swing, 0.0) * lerpf(0.24, 0.60, _rush)


func _part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	add_child(part)
	return part


static func _fit(part: MeshInstance3D, top: Vector3, bottom: Vector3) -> void:
	var span := top - bottom
	var up := span.normalized()
	var right := Vector3.RIGHT
	var basis := Basis(right, up * (span.length() + 0.09), right.cross(up))
	part.transform = Transform3D(basis, top.lerp(bottom, 0.5))


static func _segment_mesh(top: float, bottom: float, color: Color) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.radial_segments = 8
	mesh.rings = 0
	mesh.material = _pigment(color)
	return mesh


static func _pigment(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
