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

const MAX_PIECES := 12
var _batch: MultiMeshInstance3D
var _positions: Array[Vector3] = []
var _rotations: Array[Vector3] = []
var _scales: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _spins: Array[Vector3] = []
var _rest_heights: Array[float] = []
var _washed := PackedByteArray()
var _washed_count := 0
var _piece_bounds := AABB()
var _piece_bounds_dirty := true
var _settled := 0
var _active_count := 0
var terrain_height: Callable
static var _shared_mesh: SphereMesh
static var _skin_materials := {}


static func piece_mesh() -> SphereMesh:
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radius = 1.0
		_shared_mesh.height = 2.0
		_shared_mesh.radial_segments = 12
		_shared_mesh.rings = 6
	return _shared_mesh


static func piece_material(skin: Color) -> StandardMaterial3D:
	if not _skin_materials.has(skin):
		var material := StandardMaterial3D.new()
		material.albedo_color = skin
		material.roughness = 0.55
		_skin_materials[skin] = material
	return _skin_materials[skin]


## `radius` is the body that burst; `skin` is its colour. The pieces are a
## few flattened chunks of it, so a big tomato leaves big pieces.
func setup(centre: Vector3, radius: float, skin: Color) -> void:
	global_position = Vector3(centre.x, 0.0, centre.z)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := clampi(int(round(5.0 + radius * 4.0)), 5, MAX_PIECES)
	if _batch == null:
		_batch = MultiMeshInstance3D.new()
		_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_batch.visibility_range_end = 55.0
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = piece_mesh()
		multimesh.instance_count = MAX_PIECES
		_batch.multimesh = multimesh
		add_child(_batch)
	_batch.material_override = piece_material(skin)
	_batch.multimesh.visible_instance_count = count
	_batch.show()
	_active_count = count
	_settled = 0
	_washed_count = 0
	_washed.resize(count)
	_washed.fill(0)
	_positions.resize(count)
	_rotations.resize(count)
	_scales.resize(count)
	_velocities.resize(count)
	_spins.resize(count)
	_rest_heights.resize(count)
	for index in count:
		var piece_radius := radius * rng.randf_range(0.28, 0.5)
		# Flattened: a piece of skin lying on the road, not a marble.
		var squash := rng.randf_range(0.35, 0.55)
		_scales[index] = Vector3(rng.randf_range(0.8, 1.3), squash, rng.randf_range(0.8, 1.3)) * piece_radius
		var angle := rng.randf_range(0.0, TAU)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		_positions[index] = out * radius * 0.4 + Vector3.UP * maxf(centre.y, radius * 0.5)
		_rotations[index] = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
		_velocities[index] = out * rng.randf_range(2.0, 4.5 + radius) \
			+ Vector3.UP * rng.randf_range(2.0, 4.0)
		_spins[index] = Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		_rest_heights[index] = piece_radius * squash * 0.8
		_write_piece_transform(index)
	_piece_bounds_dirty = true
	set_process(true)


func _process(delta: float) -> void:
	for index in _active_count:
		var velocity := _velocities[index]
		if velocity == Vector3.ZERO:
			continue
		velocity.y -= GRAVITY * delta
		var at := _positions[index] + velocity * delta
		var rest := _rest_heights[index]
		if terrain_height.is_valid():
			rest += float(terrain_height.call(global_position + at))
		if at.y <= rest:
			at.y = rest
			if absf(velocity.y) < SETTLE_SPEED * 4.0 or velocity.length() < SETTLE_SPEED:
				velocity = Vector3.ZERO
				_rotations[index] = Vector3(0.0, _rotations[index].y, 0.0)
				_settled += 1
			else:
				velocity.y = -velocity.y * BOUNCE
				velocity.x *= 0.6
				velocity.z *= 0.6
		_positions[index] = at
		if velocity != Vector3.ZERO:
			_rotations[index] += _spins[index] * delta
		_velocities[index] = velocity
		_write_piece_transform(index)
	_piece_bounds_dirty = true
	if settled():
		set_process(false)


func _write_piece_transform(index: int) -> void:
	var basis := Basis.from_euler(_rotations[index]).scaled_local(_scales[index])
	_batch.multimesh.set_instance_transform(index, Transform3D(basis, _positions[index]))


func piece_count() -> int:
	return _active_count - _washed_count


func _update_piece_bounds() -> void:
	_piece_bounds_dirty = false
	var first := true
	for index in _active_count:
		if _washed[index] != 0:
			continue
		var centre := global_position + _positions[index]
		var size := _scales[index].abs()
		var radius := maxf(size.x, maxf(size.y, size.z))
		var bounds := AABB(centre - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		_piece_bounds = bounds if first else _piece_bounds.merge(bounds)
		first = false


func wash_in_jet(points: PackedVector3Array, jet_bounds: AABB, radius: float,
		impact: Vector3, splash_radius: float, static_hit: Callable) -> void:
	if piece_count() == 0:
		return
	if _piece_bounds_dirty:
		_update_piece_bounds()
	if not _piece_bounds.intersects(jet_bounds):
		return
	var before := _washed_count
	for index in _active_count:
		if _washed[index] != 0:
			continue
		var centre := global_position + _positions[index]
		var piece_radius := maxf(_scales[index].x, _scales[index].z)
		if not jet_bounds.grow(piece_radius).has_point(centre):
			continue
		var splash := impact.is_finite() and centre.distance_squared_to(impact) <= (splash_radius + piece_radius) ** 2
		if splash and static_hit.call(impact + Vector3.UP * 0.05, centre).is_empty():
			_wash_piece(index)
			continue
		for step in range(1, points.size()):
			var start := points[step - 1]
			var nearest := Geometry3D.get_closest_point_to_segment(centre, start, points[step])
			if centre.distance_squared_to(nearest) <= (radius + piece_radius) ** 2 \
					and static_hit.call(nearest.move_toward(start, 0.02), centre).is_empty():
				_wash_piece(index)
				break
	if _washed_count != before:
		if piece_count() == 0:
			_batch.hide()
		_piece_bounds_dirty = true
		if settled():
			set_process(false)


func _wash_piece(index: int) -> void:
	_washed[index] = 1
	_washed_count += 1
	if not _velocities[index].is_zero_approx():
		_settled += 1
	_velocities[index] = Vector3.ZERO
	_batch.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), _positions[index]))


func settled() -> bool:
	return _settled >= _active_count
