class_name ScarecrowVisual
extends RefCounted

## The firing range's target: a scarecrow on a post. Built from primitives around
## the body's origin, which is `radius` above the ground (a target stands where a
## tomato grunt would, and is as wide as one).
##
## It faces -Z, the way every enemy visual does.

const WOOD := Color("6b4a2f")
const BURLAP := Color("d6b77a")
const SHIRT := Color("a8483a")
const STRAW := Color("e4c456")
const HAT := Color("5a4632")
const INK := Color("2a1f1a")

## How far the figure reaches above the body's origin and how wide its trunk is,
## in radii: what the target's collider is cut to (`MayoEnemy.become_scarecrow`).
const TOP := 1.45
const TRUNK := 0.5

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


static func build(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ScarecrowVisual"
	var ground := -radius
	# The post, from the ground up through the head.
	_cylinder(root, "Post", Vector3(0.0, (ground + radius * 1.0) * 0.5, 0.0), radius * 0.08,
		radius * 1.0 - ground, WOOD)
	# The crossbar the arms hang on, and straw hands at its ends.
	var bar := _cylinder(root, "Crossbar", Vector3(0.0, radius * 0.38, 0.0), radius * 0.07, radius * 2.1, WOOD)
	bar.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var sleeve := _cylinder(root, "Sleeve", Vector3(side * radius * 0.62, radius * 0.38, 0.0),
			radius * 0.16, radius * 0.78, SHIRT)
		sleeve.rotation.z = PI * 0.5
		var hand := _cylinder(root, "Hand", Vector3(side * radius * 1.1, radius * 0.38, 0.0),
			radius * 0.13, radius * 0.24, STRAW, radius * 0.05)
		hand.rotation.z = PI * 0.5 * side
	# The trunk: a stuffed shirt over a straw skirt.
	_cylinder(root, "Shirt", Vector3(0.0, radius * 0.02, 0.0), radius * 0.44, radius * 0.95, SHIRT, radius * 0.36)
	_cylinder(root, "Skirt", Vector3(0.0, radius * -0.62, 0.0), radius * 0.3, radius * 0.4, STRAW, radius * 0.42)
	_box(root, "Belt", Vector3(0.0, radius * -0.42, 0.0), Vector3(radius * 0.86, radius * 0.08, radius * 0.86), INK)
	# The head: a burlap sack with a stitched face, under a hat.
	var head_y := radius * 0.88
	_sphere(root, "Head", Vector3(0.0, head_y, 0.0), radius * 0.36, BURLAP)
	for side in [-1.0, 1.0]:
		_sphere(root, "Eye", Vector3(side * radius * 0.13, head_y + radius * 0.06, -radius * 0.32), radius * 0.055, INK)
	_box(root, "Mouth", Vector3(0.0, head_y - radius * 0.13, -radius * 0.33),
		Vector3(radius * 0.24, radius * 0.035, radius * 0.04), INK)
	_cylinder(root, "Brim", Vector3(0.0, head_y + radius * 0.27, 0.0), radius * 0.62, radius * 0.05, HAT)
	_cylinder(root, "Crown", Vector3(0.0, head_y + radius * 0.46, 0.0), radius * 0.34, radius * 0.36, HAT, radius * 0.2)
	return root


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_materials[color] = material
	return _materials[color]


static func _part(root: Node3D, part_name: String, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = at
	part.material_override = _material(color)
	root.add_child(part)
	return part


static func _cylinder(root: Node3D, part_name: String, at: Vector3, radius: float, height: float,
		color: Color, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return _part(root, part_name, mesh, at, color)


static func _sphere(root: Node3D, part_name: String, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	return _part(root, part_name, mesh, at, color)


static func _box(root: Node3D, part_name: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(root, part_name, mesh, at, color)
