class_name TutorialWreck
extends Node3D

## A destroyed row of festival carts leaves one route through a ruptured mayo
## tank's spill. Built identically on every peer, only in tutorial worlds.
const CELL := StreetMap.CELL
const CENTRE_Z := -7.5 * CELL
const HALF_GAP := 1.1
const DEPTH := CELL
const HEIGHT := 3.6
const SPILL_FRONT := CENTRE_Z - DEPTH * 0.5 + 0.4
const SPILL_BACK := SPILL_FRONT - 8.0
const SPILL_CENTRE := (SPILL_FRONT + SPILL_BACK) * 0.5
const EXIT := Vector3(0.0, 0.0, SPILL_BACK - 4.0)
const TANK := Vector3(-HALF_GAP - 0.45, 2.55, CENTRE_Z)
var _impact_age := 10.0
var _shake_parts: Array[Node3D] = []
var _rest_rotations: Array[Vector3] = []

func play_impact() -> void:
	_impact_age = 0.0

func _process(delta: float) -> void:
	if _impact_age > 0.8:
		return
	_impact_age += delta
	var wobble := sin(_impact_age * 38.0) * maxf(1.0 - _impact_age / 0.8, 0.0) * 0.065
	for index in _shake_parts.size():
		_shake_parts[index].rotation = _rest_rotations[index] + Vector3(wobble, 0, -wobble)


func _ready() -> void:
	name = "TutorialWreck"
	var charcoal := _material(Color("34302d"))
	var wood := _material(Color("654634"))
	var metal := _material(Color("625f57"))
	var canvas := _material(Color("aa6740"))
	var cream := _material(Color("fff0a8"), 0.24)
	for side in [-1.0, 1.0]:
		for index in 3:
			var x: float = side * (CELL + CELL * (float(index) + 0.5))
			var at := Vector3(x, HEIGHT * 0.5, CENTRE_Z)
			# Closed, crushed cart bodies form the obstruction. Collision matches
			# the visible body; bent roof pieces are dressing above that body.
			_box("CharredCart", at, Vector3(CELL, HEIGHT, DEPTH), charcoal, true)
			# Split front panels, blackened blast hole and loose boards make the
			# wreck read as destroyed even before the player sees the leaking tank.
			var front := _box("ScorchedFront", at + Vector3(0, -0.15, DEPTH * 0.5 + 0.03),
				Vector3(CELL - 0.18, HEIGHT - 0.5, 0.1), wood)
			_blast_hole(front, charcoal, float(index) * 0.5)
			for plank in 3:
				var board := _box("BrokenBoard", at + Vector3(-1.3 + float(plank) * 1.05,
					-0.8 + float(plank % 2) * 0.9, DEPTH * 0.5 + 0.15),
					Vector3(1.6, 0.16, 0.12), metal if plank == 1 else wood)
				board.rotation.z = side * (0.35 + float(plank) * 0.45)
			for post_x in [-0.4, 0.4]:
				var post := _box("BentFrame", at + Vector3(post_x * CELL, 1.9, 0),
					Vector3(0.14, 1.9, 0.14), metal)
				post.rotation.z = side * 0.28
			for panel in 3:
				var roof := _box("TornAwning", at + Vector3(
					(float(panel) - 1.0) * CELL / 3.0, 2.0 - float(panel % 2) * 0.65, 0),
					Vector3(CELL / 3.0 - 0.13, 0.12, DEPTH - float(panel % 2)), canvas)
				roof.rotation = Vector3(0.12 * float(index - 1), 0,
					side * (0.18 + float(panel % 2) * 0.6))
				var band := _box("AwningStripe", Vector3.ZERO,
					Vector3(0.36, 0.025, DEPTH - float(panel % 2)), charcoal)
				band.reparent(roof)
				band.position = Vector3(0, 0.08, 0)
			for wheel_x in [-0.32, 0.32]:
				_cylinder("CartWheel", at + Vector3(wheel_x * CELL, -1.15, DEPTH * 0.5),
					0.48, 0.23, charcoal, Vector3(PI * 0.5, 0, 0))
			var sign := Label3D.new()
			sign.text = "MAYO" if index == 0 and side < 0 else "FOOD"
			sign.font_size = 64
			sign.pixel_size = 0.011
			sign.position = at + Vector3(0, 0.65, DEPTH * 0.5 + 0.1)
			sign.modulate = Color("d1b78b")
			sign.rotation.z = side * (0.06 + 0.05 * float(index))
			add_child(sign)
	# Two crushed counters narrow the surviving passage to one person. Their
	# visible closed bodies are the colliders that catch the much wider burger.
	for side in [-1.0, 1.0]:
		var width := CELL - HALF_GAP
		var at := Vector3(side * (HALF_GAP + width * 0.5), HEIGHT * 0.5, CENTRE_Z)
		_box("CrushedCounter", at, Vector3(width, HEIGHT, DEPTH), wood, true)
		var lid := _box("BentCounterTop", at + Vector3(0, HEIGHT * 0.5, 0),
			Vector3(width, 0.15, DEPTH), charcoal)
		lid.rotation.z = side * 0.12
	# The open end faces the gap; the displaced lid exposes the cream inside.
	_cylinder("RupturedTank", TANK, 0.85, 2.5, metal, Vector3(0, 0, PI * 0.5))
	_cylinder("OpenTankMayo", TANK + Vector3(1.26, 0, 0), 0.7, 0.025,
		cream, Vector3(0, 0, PI * 0.5))
	_cylinder("DislodgedLid", TANK + Vector3(0.5, 0.95, -0.55), 0.86, 0.07,
		metal, Vector3(0.2, 0.4, 0.8))
	var stream := _box("LeakingMayo", TANK + Vector3(1.35, -1.2, 0),
		Vector3(0.3, 2.5, 0.3), cream)
	stream.rotation.z = -0.08
	_cylinder("ThrownWheel", Vector3(-7.2, 0.4, CENTRE_Z + 3.3),
		0.65, 0.3, charcoal, Vector3(0.3, 0, 0.35))
	for index in 7:
		var scrap := _box("Splinter", Vector3(-HALF_GAP - 0.6 - float(index) * 0.47,
			0.12, CENTRE_Z + DEPTH * 0.5 + 0.3 + float(index % 3) * 0.35),
			Vector3(1.2, 0.16, 0.24), wood)
		scrap.rotation.y = float(index) * 0.73

	_remember_rotations()


func block_navigation(nav: StreetNav) -> void:
	nav.passage = Rect2(Vector2(-HALF_GAP, CENTRE_Z - DEPTH * 0.5),
		Vector2(HALF_GAP * 2.0, DEPTH))
	# Block the cart wings on the lattice. The passage constrains the two
	# central cells to the surviving gap without changing the global map cache.
	for side in [-1.0, 1.0]:
		for index in 3:
			var x: float = side * (CELL + CELL * (float(index) + 0.5))
			nav.grid.set_point_solid(StreetMap.cell_at(Vector3(x, 0, CENTRE_Z)), true)


func seed_floor(floor_body: FloorContamination) -> void:
	# Deterministic initial map state, built once on each peer. Late joiners
	# replace it with the normal authoritative floor snapshot, never add it.
	# Fine overlapping stamps close the noisy brush's holes across the lane.
	var step := 0.18
	for row in int(ceil((SPILL_FRONT - SPILL_BACK) / step)) + 1:
		var z := SPILL_BACK + float(row) * step
		var edge := 0.25 * sin(float(row) * 0.19)
		for column in int(ceil((HALF_GAP * 2.0 + 0.8) / step)) + 1:
			var x := -HALF_GAP - 0.4 + float(column) * step
			var spread := Vector2((x + 0.1) / 2.5, (z - SPILL_CENTRE) / 4.0).length()
			if spread > 1.0:
				continue
			var at := Vector3(x, 0, z + edge)
			# A broad central slick joins the source to both sides of the passage;
			# thinner cream at the ends shows the spill spreading outwards.
			var layers := floor_body.slip_thickness if spread < 0.93 and z < SPILL_FRONT - 1.0 else 1
			for layer in layers:
				floor_body.paint_mayo(at, 900000 + layer)

	# A thin stream leads from the open tank to the deep pool on the exit
	# side. Running does not trip the player before the burger's reach is clear.
	for index in 35:
		floor_body.paint_mayo(Vector3(-0.2, 0, CENTRE_Z - float(index) * 0.1), 900000)
	# Release temporary paint-coat IDs so normal stream bursts own their IDs.
	for layer in floor_body.slip_thickness:
		floor_body.grid._coats.erase(900000 + layer)


static func in_spill(at: Vector3) -> bool:
	return absf(at.x) <= HALF_GAP + 0.5 and at.z <= SPILL_FRONT + 0.5 \
		and at.z >= SPILL_BACK - 0.5


static func replaces_stall(box: Dictionary) -> bool:
	var at: Vector3 = box["position"]
	var size: Vector3 = box["size"]
	var footprint := Rect2(Vector2(at.x - size.x * 0.5, at.z - size.z * 0.5),
		Vector2(size.x, size.z))
	for side in [-1.0, 1.0]:
		var left: float = HALF_GAP if side > 0 else -4.0 * CELL
		if footprint.intersects(Rect2(Vector2(left, CENTRE_Z - DEPTH * 0.5),
				Vector2(4.0 * CELL - HALF_GAP, DEPTH))):
			return true
	return false


func _material(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _blast_hole(front: MeshInstance3D, material: Material, phase: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "BlastScorch"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 16:
		var a := TAU * float(index) / 16.0
		var b := TAU * float(index + 1) / 16.0
		var ra := 1.0 + 0.18 * sin(float(index) * 2.7 + phase)
		var rb := 1.0 + 0.18 * sin(float(index + 1) * 2.7 + phase)
		for point in [Vector3(0, -0.15, 0.07),
			Vector3(cos(b) * rb * 1.2, sin(b) * rb, 0.07),
			Vector3(cos(a) * ra * 1.2, sin(a) * ra, 0.07)]:
			surface.add_vertex(point)
	surface.generate_normals()
	mesh.mesh = surface.commit()
	var soot := material.duplicate() as StandardMaterial3D
	soot.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = soot
	front.add_child(mesh)


func _box(label: String, at: Vector3, size: Vector3, material: Material,
		collides := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	add_child(mesh)
	if label in ["TornAwning", "BrokenBoard", "Splinter", "BentCounterTop"]:
		_shake_parts.push_back(mesh)
		# Capture authored rotations after _ready has assigned them.

	if collides:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = size
		shape.shape = volume
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


func _cylinder(label: String, at: Vector3, radius: float, height: float,
		material: Material, angles: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = at
	mesh.rotation = angles
	add_child(mesh)


func _remember_rotations() -> void:
	_rest_rotations.clear()
	for part in _shake_parts:
		_rest_rotations.push_back(part.rotation)
