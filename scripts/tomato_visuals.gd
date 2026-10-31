class_name TomatoVisuals
extends RefCounted

## The Tomatina roster, drawn from engine primitives: spheres, capsules and
## cylinders and nothing else. A greybox, deliberately -- every one of these is
## a placeholder for an authored model, and what it has to do until then is be
## the right size, face the right way (-z is a body's front, as everywhere in
## `MayoEnemy`) and take sauce. `BodyContamination.add_visual_overlay` puts the
## stain on any `MeshInstance3D` it finds under the root, so these need no
## special material.
##
## Every builder returns a `Node3D` centred on the body's own origin -- the
## middle of its collider -- so the enemy can parent it at the origin and the
## topple, the overlay's rest matrix and the colliders all agree.

const TOMATO := Color("d8321e")
const OVERRIPE := Color("8f1a10")
const STEM := Color("4c8a2e")
const EYE := Color("1b0f0c")
const MOZZARELLA := Color("f1ead6")
const BASIL := Color("3f7a2f")
const BOTTLE := Color("b8231a")
const CAP := Color("f2f2f2")
const CRATE := Color("8c6a3e")


## The grunt: a tomato with a stem. `tier` 2 is the overripe one -- darker and
## with a split in its side -- so a player can tell from across the street
## which one is going to go off big.
static func grunt(radius: float, tier: int) -> Node3D:
	var root := Node3D.new()
	root.name = "TomatoGruntVisual"
	var skin := OVERRIPE if tier >= 2 else TOMATO
	_sphere(root, "Body", Vector3.ZERO, radius, skin, 0.55)
	_cylinder(root, "Stem", Vector3(0.0, radius * 0.95, 0.0), radius * 0.12, radius * 0.45, STEM)
	_eyes(root, radius)
	if tier >= 2:
		# The split: a darker band round the body where it is about to go.
		_cylinder(root, "Split", Vector3(0.0, 0.0, 0.0), radius * 1.02, radius * 0.12,
			Color("3b0a06"))
	return root


## The brute: a tomato twice the size with two arms it swings.
static func brute(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TomatoBruteVisual"
	_sphere(root, "Body", Vector3.ZERO, radius, OVERRIPE, 0.6)
	_cylinder(root, "Stem", Vector3(0.0, radius * 0.95, 0.0), radius * 0.1, radius * 0.4, STEM)
	for side in [-1.0, 1.0]:
		_capsule(root, "Arm%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * radius * 0.9, radius * 0.1, 0.0),
			Vector3(side * radius * 1.55, -radius * 0.55, -radius * 0.45),
			radius * 0.22, TOMATO)
		_sphere(root, "Fist%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * radius * 1.55, -radius * 0.55, -radius * 0.45), radius * 0.3, TOMATO, 0.6)
	_eyes(root, radius)
	return root


## The bowler: a crate on end with a tomato held over it, ready to roll.
static func bowler(radius: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BowlingTomatoVisual"
	_cylinder(root, "Body", Vector3(0.0, -height * 0.1, 0.0), radius, height * 0.8, CRATE)
	_sphere(root, "Held", Vector3(0.0, height * 0.45, -radius * 0.3), radius * 0.55, TOMATO, 0.55)
	_cylinder(root, "Stem", Vector3(0.0, height * 0.45 + radius * 0.5, -radius * 0.3),
		radius * 0.07, radius * 0.25, STEM)
	_eyes(root, radius, -height * 0.05)
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
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	mesh.material = _material(color, roughness)
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


static func _cylinder(parent: Node3D, node_name: String, at: Vector3, radius: float,
		height: float, color: Color, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = _material(color, 0.7)
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


## Two eyes on the front (-z) of a sphere of `radius` centred at `y`, `z`.
static func _eyes(parent: Node3D, radius: float, y := 0.0, z := 0.0) -> void:
	for side in [-1.0, 1.0]:
		_sphere(parent, "Eye%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * radius * 0.35, y + radius * 0.25, z - radius * 0.88), radius * 0.13, EYE, 0.3)
