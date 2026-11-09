extends Node3D
## A low strand across the road. It has no body collider, so players can
## choose to cross it and sauce continues through it after cutting it.

const HEIGHT := 0.64
const WINDUP := 0.75
const LIFE := 5.0
const CUT_RADIUS := 0.18
const SNAG_RADIUS := 0.46

var from := Vector3.ZERO
var to := Vector3.ZERO
var left := WINDUP + LIFE
var tripped: Dictionary = {}
var _strand: MeshInstance3D
var _material: StandardMaterial3D
var _anchors: Array[MeshInstance3D] = []


func configure(start: Vector3, finish: Vector3) -> void:
	from = start
	to = finish
	var span := to - from
	_strand = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.105, 0.105, span.length())
	_strand.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_strand.material_override = _material
	_strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_strand)
	_strand.global_transform = Transform3D(Basis.looking_at(span), (from + to) * 0.5)
	for end in [from, to]:
		var anchor := MeshInstance3D.new()
		var bead := SphereMesh.new()
		bead.radius = 0.25
		bead.height = 0.5
		anchor.mesh = bead
		anchor.material_override = _material
		add_child(anchor)
		anchor.global_position = end
		_anchors.append(anchor)
		var peg := MeshInstance3D.new()
		var post := CylinderMesh.new()
		post.height = HEIGHT
		post.top_radius = 0.05
		post.bottom_radius = 0.11
		peg.mesh = post
		peg.material_override = _material
		add_child(peg)
		peg.global_position = end - Vector3.UP * HEIGHT * 0.5
	update_visual()


func armed() -> bool:
	return left > 0.0 and left <= LIFE


func update_visual() -> void:
	var glow := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.031)
	_material.albedo_color = Color("fff4cc") if armed() else Color("e9a94e").lerp(Color("ffecc6"), glow)
	_strand.visible = armed()
	for anchor in _anchors:
		anchor.scale = Vector3.ONE * (0.7 if armed() else lerpf(0.8, 1.3, glow))


func hit_by_stream(start: Vector3, finish: Vector3) -> bool:
	if not armed() or start.is_equal_approx(finish):
		return false
	var nearest := Geometry3D.get_closest_points_between_segments(start, finish, from, to)
	return nearest[0].distance_squared_to(nearest[1]) <= CUT_RADIUS * CUT_RADIUS


func snagged(player: MayoPlayer) -> bool:
	if not armed() or player.state != MayoPlayer.State.NORMAL:
		return false
	var feet := player.global_position - Vector3.UP * (MayoPlayer.CAPSULE_HEIGHT * 0.5)
	# A foot above the strand clears it even if the swept horizontal path crosses.
	if feet.y > from.y + 0.15 or feet.y + MayoPlayer.CAPSULE_HEIGHT < from.y:
		return false
	var at := Vector3(feet.x, from.y, feet.z)
	var movement := Vector3(player.frame_movement.x, 0.0, player.frame_movement.z)
	if movement.is_zero_approx():
		return false
	var nearest := Geometry3D.get_closest_points_between_segments(at - movement, at, from, to)
	return nearest[0].distance_squared_to(nearest[1]) <= SNAG_RADIUS * SNAG_RADIUS

