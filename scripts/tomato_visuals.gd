class_name TomatoVisuals
extends RefCounted

const EnemyInk := preload("res://scripts/enemy_ink.gd")

## The Tomatina roster uses colored primitives that face -Z and receive
## the same sauce overlay as imported enemies.
##
## Every builder returns a `Node3D` centred on the body's own origin -- the
## middle of its collider -- so the enemy can parent it at the origin and the
## topple, the overlay's rest matrix and the colliders all agree.

const TOMATO := Color("d8321e")
const OVERRIPE := Color("8f1a10")
const STEM := Color("4c8a2e")
const EYE := Color("1b0f0c")
const EYE_WHITE := Color("fff0c9")
const MOZZARELLA := Color("f1ead6")
const BASIL := Color("3f7a2f")
const BOTTLE := Color("b8231a")
const CAP := Color("f2f2f2")
static var _sphere_meshes := {}
static var _cylinder_meshes := {}
static var _grunt_meshes := {}
const CRATE := Color("8c6a3e")


## The grunt: a tomato with a stem. `tier` 2 is the overripe one -- darker and
## with a split in its side -- so a player can tell from across the street
## which one is going to go off big.
static func grunt(radius: float, tier: int) -> Node3D:
	var root := Node3D.new()
	root.name = "TomatoGruntVisual"
	var overripe := tier >= 2
	var key := Vector2(radius, float(overripe))
	if not _grunt_meshes.has(key):
		_grunt_meshes[key] = _build_grunt_mesh(radius, overripe)
	var model := MeshInstance3D.new()
	model.name = "Body"
	model.mesh = _grunt_meshes[key]
	root.add_child(model)
	EnemyInk.apply(root)
	return root


static func _build_grunt_mesh(radius: float, overripe: bool) -> ArrayMesh:
	var root := Node3D.new()
	var skin := OVERRIPE if overripe else TOMATO
	_sphere(root, "Body", Vector3.ZERO, radius, skin, 0.55)
	var stem_height := radius * (0.68 if overripe else 0.45)
	_cylinder(root, "Stem", Vector3(0.0, radius * 1.02, 0.0), radius * 0.12, stem_height,
		Color("e3c767") if overripe else STEM)
	_calyx(root, radius, overripe)
	_eyes(root, radius)
	if overripe:
		_cylinder(root, "Split", Vector3(0.0, 0.0, 0.0), radius * 1.025, radius * 0.17,
			Color("381b2d"))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offset := 0
	for part: MeshInstance3D in root.get_children():
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var material := part.mesh.surface_get_material(0) as StandardMaterial3D
		var normal_basis := part.basis.inverse().transposed()
		for i in vertices.size():
			surface.set_color(material.albedo_color)
			surface.set_normal((normal_basis * normals[i]).normalized())
			surface.add_vertex(part.transform * vertices[i])
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			surface.add_index(offset + index)
		offset += vertices.size()
	root.free()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.6
	surface.set_material(material)
	return surface.commit()


## The brute has a squat body and heavy, rounded fists.
static func brute(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TomatoBruteVisual"
	var hide := Color("a73524")
	var body := _sphere(root, "Body", Vector3(0.0, radius * 0.21, 0.0), radius, hide)
	body.scale = Vector3(1.0, 0.78, 0.92)
	_cylinder(root, "Stem", Vector3(-0.08, 1.05, 0.04) * radius, radius * 0.105,
		radius * 0.36, Color("64623b"), Vector3(0.32, 0.0, 0.43))
	_calyx(root, radius, true)
	_brute_face(root, radius)
	for side in [-1.0, 1.0]:
		_brute_arm(root, radius, side, hide)
	return root


static func _brute_arm(root: Node3D, radius: float, side: float, hide: Color) -> void:
	var shoulder := Node3D.new()
	shoulder.name = "ShoulderL" if side < 0.0 else "ShoulderR"
	shoulder.position = Vector3(side * 0.79, 0.31, 0.02) * radius
	root.add_child(shoulder)
	var joint := Vector3(side * 0.36, -0.29, 0.08) * radius
	var deltoid := _sphere(shoulder, "Deltoid", Vector3.ZERO, radius * 0.31, hide)
	deltoid.scale = Vector3(1.0, 0.85, 0.94)
	_capsule(shoulder, "UpperArm", Vector3.ZERO, joint, radius * 0.21, hide)
	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = joint
	shoulder.add_child(elbow)
	var hand := Vector3(side * 0.13, -0.43, -0.14) * radius
	var wrist := hand * 0.76
	var hand_color := Color("a7402b")
	_capsule(elbow, "Forearm", Vector3.ZERO, wrist, radius * 0.19, hand_color)
	var fist := _sphere(elbow, "Fist", hand, radius * 0.24, hand_color)
	fist.scale = Vector3(0.92, 1.10, 0.88)
	fist.rotation.z = side * 0.22
	var thumb := _sphere(elbow, "Thumb", hand + Vector3(-side * 0.162, 0.027, -0.103) * radius,
		radius * 0.125, hand_color)
	thumb.scale = Vector3(0.88, 1.12, 0.90)
	thumb.rotation.z = side * 0.35


static func _brute_face(root: Node3D, radius: float) -> void:
	_brute_eye(root, radius, "L", Vector3(-0.30, 0.41, -0.835), 0.245, Vector2(-0.04, 0.055), 0.21)
	_brute_eye(root, radius, "R", Vector3(0.34, 0.33, -0.857), 0.171, Vector2(-0.042, -0.033), -0.13)

	var mouth := Node3D.new()
	mouth.name = "CrookedGrin"
	mouth.position = Vector3(0.025, -0.085, -0.855) * radius
	mouth.rotation.z = -0.17
	root.add_child(mouth)
	_sphere(mouth, "LipRim", Vector3.ZERO, radius, Color("92372a")).scale = Vector3(0.49, 0.185, 0.19)
	_sphere(mouth, "MouthCavity", Vector3(0.0, 0.006, -0.060) * radius,
		radius, Color("391a22")).scale = Vector3(0.425, 0.137, 0.151)
	var front_left := _sphere(mouth, "FrontToothL", Vector3(-0.124, 0.060, -0.136) * radius,
		radius, EYE_WHITE)
	front_left.scale = Vector3(0.082, 0.101, 0.054)
	front_left.rotation.z = 0.12
	var front_right := _sphere(mouth, "FrontToothR", Vector3(0.052, 0.070, -0.139) * radius,
		radius, EYE_WHITE)
	front_right.scale = Vector3(0.077, 0.087, 0.056)
	front_right.rotation.z = -0.16
	var tongue := _sphere(mouth, "Tongue", Vector3(0.237, -0.119, -0.153) * radius,
		radius, Color("ee796e"))
	tongue.scale = Vector3(0.100, 0.135, 0.075)
	tongue.rotation.z = 0.48


static func _brute_eye(root: Node3D, radius: float, suffix: String, at: Vector3,
		size: float, look: Vector2, brow_tilt: float) -> void:
	_sphere(root, "EyeSocket" + suffix, at * radius,
		size * radius * 1.12, Color("92362b")).scale.z = 0.52
	_sphere(root, "Eye" + suffix, (at + Vector3(0.0, 0.0, -0.045)) * radius,
		size * radius, EYE_WHITE).scale = Vector3(0.94, 1.0, 0.54)
	var pupil_at := at + Vector3(look.x, look.y, -0.031 - size * 0.54)
	_sphere(root, "Pupil" + suffix, pupil_at * radius,
		size * radius * 0.41, EYE).scale = Vector3(0.92, 1.0, 0.43)
	_sphere(root, "Glint" + suffix, (pupil_at + Vector3(-0.018, 0.026, -size * 0.15)) * radius,
		size * radius * 0.115, Color("fff9e9"))
	var brow := _sphere(root, "Brow" + suffix,
		(at + Vector3(0.0, size * 1.08, size * 0.32)) * radius, size * radius, Color("762f25"))
	brow.scale = Vector3(1.0, 0.25, 0.44)
	brow.rotation.z = brow_tilt


## The bowler: a crate on end with a tomato held over it, ready to roll.
static func bowler(radius: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BowlingTomatoVisual"
	_cylinder(root, "Body", Vector3(0.0, -height * 0.1, 0.0), radius, height * 0.8, CRATE)
	_cylinder(root, "UpperHoop", Vector3(0.0, height * 0.22, 0.0), radius * 1.025,
		height * 0.09, Color("614731"))
	_cylinder(root, "LowerHoop", Vector3(0.0, -height * 0.42, 0.0), radius * 1.025,
		height * 0.09, Color("614731"))
	_sphere(root, "Held", Vector3(0.0, height * 0.45, -radius * 0.3), radius * 0.55, TOMATO, 0.55)
	_cylinder(root, "Stem", Vector3(0.0, height * 0.45 + radius * 0.5, -radius * 0.3),
		radius * 0.07, radius * 0.25, STEM)
	_eyes(root, radius, -height * 0.05, -radius * 0.09)
	return root


## The thing it rolls: a tomato and nothing else. Darker, so it reads as a
## projectile rather than one more grunt.
static func ball(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TomatoBallVisual"
	_sphere(root, "Body", Vector3.ZERO, radius, Color("c0281a"), 0.5)
	for index in 3:
		var angle := TAU * float(index) / 3.0
		_sphere(root, "Spot%d" % index,
			Vector3(cos(angle) * radius * 0.7, sin(angle * 1.7) * radius * 0.5, sin(angle) * radius * 0.7),
			radius * 0.28, OVERRIPE, 0.6)
	return root


## The spitter: a ketchup bottle with a head and a nozzle.
static func spitter(radius: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "KetchupSpitterVisual"
	var body_height := height * 0.62
	_cylinder(root, "Body", Vector3(0.0, -height * 0.5 + body_height * 0.5, 0.0), radius,
		body_height, BOTTLE)
	var label_y := -height * 0.5 + body_height * 0.49
	_cylinder(root, "PaperLabel", Vector3(0.0, label_y, 0.0), radius * 1.01,
		body_height * 0.40, EYE_WHITE)
	var badge := _sphere(root, "LabelTomato", Vector3(0.0, label_y, -radius * 0.99),
		radius * 0.23, TOMATO)
	badge.scale.z = 0.20
	var head_y := -height * 0.5 + body_height + radius * 0.55
	_sphere(root, "Head", Vector3(0.0, head_y, 0.0), radius * 0.62, TOMATO, 0.55)
	_cylinder(root, "Nozzle", Vector3(0.0, head_y, -radius * 0.7), radius * 0.16, radius * 0.6, CAP,
		Vector3(deg_to_rad(90.0), 0.0, 0.0))
	_eyes(root, radius * 0.62, head_y)
	return root


## The crawler: tomato, mozzarella, basil, tomato, mozzarella -- a caprese skewer
## of capsules, head at the front.
static func caprese(segment_radius: float, count: int, spacing: float) -> Node3D:
	var root := Node3D.new()
	root.name = "CapreseCrawlerVisual"
	var colors := [TOMATO, MOZZARELLA, BASIL]
	var total := spacing * float(count - 1)
	for index in count:
		var z := -total * 0.5 + spacing * float(index)
		var color: Color = colors[index % colors.size()]
		var r := segment_radius * (1.0 if index > 0 else 1.15)
		_sphere(root, "Segment%d" % index, Vector3(0.0, 0.0, z), r, color, 0.5 if index % 3 != 1 else 0.3)
	# A thread of mozzarella along the spine, so the chain reads as one animal.
	_capsule(root, "Spine", Vector3(0.0, 0.0, -total * 0.5), Vector3(0.0, 0.0, total * 0.5),
		segment_radius * 0.3, MOZZARELLA)
	_eyes(root, segment_radius * 1.15, 0.0, -total * 0.5)
	return root


# --- the primitives -----------------------------------------------------------

static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _sphere(parent: Node3D, node_name: String, at: Vector3, radius: float,
		color: Color, roughness := 0.6) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var key := Vector3(radius, roughness, 0.0)
	var materials: Dictionary = _sphere_meshes.get_or_add(key, {})
	var mesh: SphereMesh = materials.get(color)
	if mesh == null:
		mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 8 if radius < 0.15 else 20
		mesh.rings = 4 if radius < 0.15 else 10
		mesh.material = _material(color, roughness)
		materials[color] = mesh
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


static func _cylinder(parent: Node3D, node_name: String, at: Vector3, radius: float,
		height: float, color: Color, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var key := Vector2(radius, height)
	var materials: Dictionary = _cylinder_meshes.get_or_add(key, {})
	var mesh: CylinderMesh = materials.get(color)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 16
		mesh.rings = 1
		mesh.material = _material(color, 0.7)
		materials[color] = mesh
	node.mesh = mesh
	node.position = at
	node.rotation = rotation
	parent.add_child(node)
	return node


static func _capsule(parent: Node3D, node_name: String, a: Vector3, b: Vector3,
		radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var span := b - a
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = span.length() + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _material(color, 0.6)
	node.mesh = mesh
	if span.length_squared() > 0.000001:
		var y_axis := span.normalized()
		var reference := Vector3.FORWARD if absf(y_axis.z) < 0.9 else Vector3.RIGHT
		var x_axis := reference.cross(y_axis).normalized()
		node.transform = Transform3D(Basis(x_axis, y_axis, x_axis.cross(y_axis)), (a + b) * 0.5)
	else:
		node.position = a
	parent.add_child(node)
	return node


static func _calyx(parent: Node3D, radius: float, overripe: bool) -> void:
	var color := Color("a38039") if overripe else STEM
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var leaf := _sphere(parent, "Calyx%d" % index,
			Vector3(sin(angle) * 0.25, 0.96, cos(angle) * 0.25) * radius,
			radius * 0.28, color)
		leaf.scale = Vector3(0.42, 0.20, 1.0)
		leaf.rotation = Vector3(0.26, angle, 0.0)


## Front-facing cream eyes and inward-sloped brows read at street distance.
static func _eyes(parent: Node3D, radius: float, y := 0.0, z := 0.0) -> void:
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var eye := Vector3(side * radius * 0.35, y + radius * 0.25, z - radius * 0.89)
		_sphere(parent, "Eye" + suffix, eye, radius * 0.22, EYE_WHITE).scale = Vector3(1.0, 0.80, 0.70)
		var pupil := eye + Vector3(-side * 0.045, -0.02, -0.13) * radius
		_sphere(parent, "Pupil" + suffix, pupil, radius * 0.096, EYE).scale.z = 0.55
		var brow := _sphere(parent, "Brow" + suffix,
			eye + Vector3(0.0, 0.14, -0.105) * radius, radius * 0.24, EYE)
		brow.scale = Vector3(1.0, 0.30, 0.36)
		brow.rotation.z = side * 0.33
