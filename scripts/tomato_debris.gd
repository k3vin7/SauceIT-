class_name TomatoDebris
extends Node3D

## What is left of a tomato that burst: the body, in pieces, on the road.
##
## A corpse that stays whole is a wall -- see `MayoPrototype.CORPSE_LAYER` for
## the toast that taught that lesson -- and a tomato that went off with a bang
## and is then still standing there is a lie. So the body vanishes (see
## `MayoEnemy.vanish`) and this is drawn in its place: a handful of pieces of
## skin thrown outwards, dropping under gravity, settling where they land.
##
## Pure scenery. No collision, no sauce, nothing on the wire: every peer builds
## its own the moment it sees the body die, from the same position and radius,
## and the throw is random because nothing reads it back. The world caps how
## many of these it keeps -- see `MayoPrototype._debris`.

const GRAVITY := 9.8
## Pieces bounce once, losing most of their lift, then lie still.
const BOUNCE := 0.25
const SETTLE_SPEED := 0.4

var _pieces: Array[MeshInstance3D] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _rest_heights: Array[float] = []
var _settled := 0
var _active_count := 0
static var _shared_mesh: SphereMesh
static var _skin_materials := {}


## `radius` is the body that burst; `skin` is its colour. The pieces are a
## few flattened chunks of it, so a big tomato leaves big pieces.
func setup(centre: Vector3, radius: float, skin: Color) -> void:
	global_position = Vector3(centre.x, 0.0, centre.z)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := clampi(int(round(5.0 + radius * 4.0)), 5, 12)
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radius = 1.0
		_shared_mesh.height = 2.0
		_shared_mesh.radial_segments = 12
		_shared_mesh.rings = 6
	if not _skin_materials.has(skin):
		var material := StandardMaterial3D.new()
		material.albedo_color = skin
		material.roughness = 0.55
		_skin_materials[skin] = material
	while _pieces.size() < count:
		var piece := MeshInstance3D.new()
		piece.name = "Piece%d" % _pieces.size()
		piece.mesh = _shared_mesh
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.visibility_range_end = 55.0
		add_child(piece)
		_pieces.push_back(piece)
	for index in _pieces.size():
		_pieces[index].visible = index < count
	_active_count = count
	_settled = 0
	_velocities.resize(count)
	_spins.resize(count)
	_rest_heights.resize(count)
	for index in count:
		var piece := _pieces[index]
		piece.material_override = _skin_materials[skin]
		var piece_radius := radius * rng.randf_range(0.28, 0.5)
		# Flattened: a piece of skin lying on the road, not a marble.
		var squash := rng.randf_range(0.35, 0.55)
		piece.scale = Vector3(rng.randf_range(0.8, 1.3), squash, rng.randf_range(0.8, 1.3)) * piece_radius
		var angle := rng.randf_range(0.0, TAU)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		piece.position = out * radius * 0.4 + Vector3.UP * maxf(centre.y, radius * 0.5)
		piece.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
		_velocities[index] = out * rng.randf_range(2.0, 4.5 + radius) \
			+ Vector3.UP * rng.randf_range(2.0, 4.0)
		_spins[index] = Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		_rest_heights[index] = piece_radius * squash * 0.8
	set_process(true)


func _process(delta: float) -> void:
	for index in _active_count:
		var velocity := _velocities[index]
		if velocity == Vector3.ZERO:
			continue
		var piece := _pieces[index]
		velocity.y -= GRAVITY * delta
		var at := piece.position + velocity * delta
		var rest := _rest_heights[index]
		if at.y <= rest:
			at.y = rest
			if absf(velocity.y) < SETTLE_SPEED * 4.0 or velocity.length() < SETTLE_SPEED:
				velocity = Vector3.ZERO
				piece.rotation = Vector3(0.0, piece.rotation.y, 0.0)
				_settled += 1
			else:
				velocity.y = -velocity.y * BOUNCE
				velocity.x *= 0.6
				velocity.z *= 0.6
		piece.position = at
		if velocity != Vector3.ZERO:
			piece.rotation += _spins[index] * delta
		_velocities[index] = velocity
	if settled():
		set_process(false)


func piece_count() -> int:
	return _active_count


func settled() -> bool:
	return _settled >= _active_count
