class_name TutorialCourse
extends Node3D

## Map-specific configuration for the standalone tutorial. Nothing in the
## sequence needs festival pixel coordinates any more; it asks this course for
## its authored start, fight, escape, trap and refill markers.
const WIDTH := 36.0
const LENGTH := 82.0
const WALL_HEIGHT := 5.0
const START_Z := 35.0
const START_STATION := Vector3(-8.0, 1.5, 29.0)
const FIRST_FIGHT := Vector3(0.0, 0.0, 18.0)
const CENTRE_Z := -4.0
const DEPTH := 5.0
# 1.8 m opening: comfortably wider than the 1.28 m player capsule, but too
# narrow for the bruiser's compound burger body to squeeze through at an angle.
const HALF_GAP := 0.9
const SPILL_FRONT := CENTRE_Z + DEPTH * 0.5 + 0.8
const DEEP_FRONT := CENTRE_Z + DEPTH * 0.5
const SPILL_BACK := -14.0
const SPILL_CENTRE := (SPILL_FRONT + SPILL_BACK) * 0.5
const SPILL_REACH := (SPILL_FRONT - SPILL_BACK) * 0.5
const EXIT := Vector3(0.0, 0.0, -20.0)
const REFILL_STATION := Vector3(8.0, 1.5, -29.0)

var _impact_age := 10.0
var _barriers: Array[Node3D] = []


static func floor_plane() -> Dictionary:
	return {"size": Vector2(WIDTH, LENGTH), "centre": Vector3(0.0, 0.0, 0.0)}


static func spawn_position(slot: int) -> Vector3:
	const OFFSETS := [-2.4, -0.8, 0.8, 2.4]
	return Vector3(OFFSETS[slot % OFFSETS.size()], MayoPlayer.CAPSULE_HEIGHT * 0.5, START_Z)


static func first_enemy_position(index: int) -> Vector3:
	return FIRST_FIGHT + Vector3(0.0, 0.0, -float(index) * 3.2)


static func can_stand(at: Vector3) -> bool:
	if absf(at.x) > WIDTH * 0.5 - 1.0 or absf(at.z) > LENGTH * 0.5 - 1.0:
		return false
	var in_barrier_z := absf(at.z - CENTRE_Z) <= DEPTH * 0.5 + 0.8
	return not in_barrier_z or absf(at.x) <= HALF_GAP


static func in_spill(at: Vector3) -> bool:
	return absf(at.x) <= HALF_GAP + 0.5 and at.z <= SPILL_FRONT + 0.5 \
		and at.z >= SPILL_BACK - 0.5


static func constrain_bruiser(at: Vector3, _previous: Vector3, radius: float) -> Vector3:
	# The burger is made from several precise limb/body shapes rather than one
	# oversized capsule. CharacterBody sliding can otherwise rotate that compound
	# silhouette through the gap even though its broad gameplay radius cannot fit.
	# Keep the scripted heavy's centre on the approach side of the physical mouth;
	# minions and players still use ordinary collision and pass through.
	var mouth := CENTRE_Z + DEPTH * 0.5
	if at.z < mouth + radius:
		at.z = mouth + radius
	return at


func _ready() -> void:
	name = "TutorialCourse"
	# Two plain blocks leave a player-width gap. The player's 0.64 m radius
	# clears it; the large burger cannot, so the geometry teaches the escape.
	var wing_width := WIDTH * 0.5 - HALF_GAP
	for side in [-1.0, 1.0]:
		var centre_x: float = float(side) * (HALF_GAP + wing_width * 0.5)
		_barriers.push_back(_box("EscapeBarrier", Vector3(centre_x, 1.8, CENTRE_Z),
			Vector3(wing_width, 3.6, DEPTH), Color("67584c"), true))
	# A few waist-high guides make the route readable without copying the street.
	_box("RouteGuideA", Vector3(-7.0, 0.65, 11.0), Vector3(5.0, 1.3, 1.2), Color("3e5968"), true)
	_box("RouteGuideB", Vector3(7.0, 0.65, 4.0), Vector3(5.0, 1.3, 1.2), Color("3e5968"), true)
	_add_marker("PlayerStart", Vector3(0.0, 0.0, START_Z))
	_add_marker("SaucePickup", START_STATION)
	_add_marker("FirstFight", FIRST_FIGHT)
	_add_marker("EscapeGap", Vector3(0.0, 0.0, CENTRE_Z))
	_add_marker("EscapeTarget", EXIT)
	_add_marker("Refill", REFILL_STATION)
	_add_marker("FinalFight", Vector3(0.0, 0.0, -22.0))


func seed_floor(floor_body: FloorContamination) -> void:
	var step := 0.2
	for row in int(ceil((SPILL_FRONT - SPILL_BACK) / step)) + 1:
		var z := SPILL_BACK + float(row) * step
		for column in int(ceil((HALF_GAP * 2.0 + 1.0) / step)) + 1:
			var x := -HALF_GAP - 0.5 + float(column) * step
			var in_lane := absf(x) <= HALF_GAP + 0.25 and z <= DEEP_FRONT
			var ellipse := Vector2(x / (HALF_GAP + 1.0),
				(z - SPILL_CENTRE) / SPILL_REACH).length()
			if ellipse > 1.0 and not in_lane:
				continue
			for layer in (floor_body.slip_thickness if in_lane else 1):
				floor_body.paint_mayo(Vector3(x, 0.0, z), 910000 + layer)
	for layer in floor_body.slip_thickness:
		floor_body.grid._coats.erase(910000 + layer)


func play_impact() -> void:
	_impact_age = 0.0


func _process(delta: float) -> void:
	if _impact_age > 0.7:
		return
	_impact_age += delta
	var shake := sin(_impact_age * 35.0) * maxf(1.0 - _impact_age / 0.7, 0.0) * 0.06
	for barrier in _barriers:
		barrier.rotation.z = shake


func _add_marker(marker_name: String, at: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	add_child(marker)


func _box(box_name: String, at: Vector3, size: Vector3, color: Color,
		collides := false) -> Node3D:
	var holder := Node3D.new()
	holder.name = box_name
	holder.position = at
	add_child(holder)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	holder.add_child(mesh)
	if collides:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		holder.add_child(body)
	return holder
