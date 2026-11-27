class_name StreamVisual
extends MeshInstance3D

## Camera-facing ribbon with reusable GPU buffers sized for the visible strand.

const CAP_STEPS := 10
const MIN_BUFFER_VERTICES := 96

static var _cap_ring := PackedVector2Array()

var ribbon_material: Material
var _dynamic_mesh: ArrayMesh
var _mesh_buffers: Dictionary[int, ArrayMesh] = {}
var _buffer_capacity := 0
var _has_uv := false
var _vertex_cache := PackedVector3Array()
var _uv_cache := PackedVector2Array()
var _side_cache: Array[Vector3] = []
var _centre_cache: Array[Vector3] = []
var smooth_centres := false
var draw_caps := true
var _max_vertices := 0
var _used_vertices := 0
var _previous_used_vertices := 0
var _bounds_low := Vector3.ZERO
var _bounds_high := Vector3.ZERO
## Below this distance the point-to-camera vector swings violently between
## frames and twists the ribbon, so the fixed view axis is used instead.
var min_view_distance := 0.5


func setup(material: Material, maximum_points: int = 192) -> void:
	ribbon_material = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep CPU staging large enough for isolated discs. Most strands need only
	# a fraction of this many vertices on the GPU.
	_max_vertices = maximum_points * CAP_STEPS * 3 + 60
	_vertex_cache.resize(_max_vertices)
	_has_uv = material is ShaderMaterial
	if _has_uv:
		_uv_cache.resize(_max_vertices)
	if _cap_ring.is_empty():
		for i in CAP_STEPS + 1:
			_cap_ring.append(Vector2.from_angle(TAU * float(i) / CAP_STEPS))
	_select_mesh_buffer()
	visible = false


func _select_mesh_buffer() -> void:
	if _used_vertices <= _buffer_capacity and _used_vertices * 4 > _buffer_capacity:
		return
	var capacity := MIN_BUFFER_VERTICES
	while capacity < _used_vertices:
		capacity *= 2
	capacity = mini(capacity, _max_vertices)
	if capacity == _buffer_capacity:
		return
	_buffer_capacity = capacity
	_dynamic_mesh = _mesh_buffers.get(capacity)
	if _dynamic_mesh != null:
		_previous_used_vertices = capacity
		_dynamic_mesh.surface_set_material(0, ribbon_material)
		mesh = _dynamic_mesh
		return

	var vertices := PackedVector3Array()
	vertices.resize(capacity)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if _has_uv:
		var uvs := PackedVector2Array()
		uvs.resize(capacity)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	_dynamic_mesh = ArrayMesh.new()
	_dynamic_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
	)
	_dynamic_mesh.surface_set_material(0, ribbon_material)
	_mesh_buffers[capacity] = _dynamic_mesh
	_previous_used_vertices = 0
	mesh = _dynamic_mesh


func set_ribbon_material(material: Material) -> void:
	if ribbon_material != material:
		ribbon_material = material
		if _dynamic_mesh != null:
			_dynamic_mesh.surface_set_material(0, material)


func update_ribbon(
		segments: Array,
		camera_position: Vector3,
		camera_forward: Vector3,
		base_width: float,
		y_offset: float = 0.0
	) -> void:
	_used_vertices = 0
	_bounds_low = Vector3.INF
	_bounds_high = -Vector3.INF
	for raw_segment in segments:
		var segment: Array = raw_segment
		if segment.is_empty():
			continue
		_append_strip(segment, camera_position, camera_forward, base_width, y_offset)

	if _used_vertices == 0:
		visible = false
		return

	_select_mesh_buffer()
	var upload_vertices := maxi(_used_vertices, _previous_used_vertices)
	var collapse_point := _vertex_cache[0]
	for i in range(_used_vertices, upload_vertices):
		_vertex_cache[i] = collapse_point
	# Convert only the dirty prefix. Converting the full worst-case capacity was
	# measurable even though only the prefix was sent to RenderingServer.
	var vertex_bytes := _vertex_cache.slice(0, upload_vertices).to_byte_array()
	_dynamic_mesh.surface_update_vertex_region(0, 0, vertex_bytes)
	if _has_uv:
		_dynamic_mesh.surface_update_attribute_region(0, 0, _uv_cache.slice(0, _used_vertices).to_byte_array())
	_previous_used_vertices = _used_vertices
	# Vertices are written in world space and this node carries no transform of
	# its own, so its local space is the world's and the bounds go straight in.
	# Padded by half a strand width because the collapsed tail vertices sit on
	# the first vertex, which is already inside.
	var pad := Vector3.ONE * base_width * 0.5
	custom_aabb = AABB(_bounds_low - pad, (_bounds_high - _bounds_low) + pad * 2.0)
	visible = true


func _append_strip(points: Array, camera_position: Vector3, camera_forward: Vector3, base_width: float, y_offset: float) -> void:
	# Keep a spatial phase per disconnected piece, then measure along the strip.
	var first_position: Vector3 = points[0].position
	var first_distance := first_position.dot(Vector3(0.57, 0.29, 0.71))
	if points.size() == 1:
		if draw_caps:
			_append_round_cap(points[0], Vector3.RIGHT, camera_position, camera_forward, base_width, y_offset,
				first_distance)
		return

	var count := points.size()
	var sides := _side_cache
	var centres := _centre_cache
	sides.resize(count)
	centres.resize(count)
	for i in count:
		centres[i] = points[i].position
		if smooth_centres and i > 0 and i < count - 1:
			var previous: Vector3 = points[i - 1].position
			var following: Vector3 = points[i + 1].position
			var incoming := centres[i].distance_to(previous)
			var length := incoming + centres[i].distance_to(following)
			if length > 0.0001:
				var correction := (previous.lerp(following, incoming / length) - centres[i]) * 0.65
				centres[i] += correction.limit_length(base_width * 0.4)

	var previous_side := camera_forward.cross(Vector3.UP).normalized()
	if previous_side.is_zero_approx():
		previous_side = Vector3.RIGHT
	for i in count:
		var previous: Vector3 = centres[maxi(i - 1, 0)]
		var following: Vector3 = centres[mini(i + 1, count - 1)]
		var tangent := (following - previous).normalized()
		var to_camera := _view_vector(centres[i], camera_position, camera_forward)
		var side := tangent.cross(to_camera)
		if side.length_squared() < 0.0004:
			side = previous_side - to_camera * previous_side.dot(to_camera)
		if side.length_squared() < 0.000001:
			side = to_camera.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		# Adjacent frames must use the same side of the strip, even when
		# projected tangents reverse near the centre of a first-person shot.
		if side.dot(previous_side) < 0.0:
			side = -side
		sides[i] = side
		previous_side = side

	for i in range(1, points.size() - 1):
		var joined: Vector3 = sides[i - 1] + sides[i] + sides[i + 1]
		if joined.length_squared() > 0.000001:
			sides[i] = joined.normalized()

	var distance_a := first_distance
	var height_offset := Vector3.UP * y_offset
	var half_width := base_width * 0.5
	var center_a := centres[0] + height_offset
	var edge := sides[0] * (half_width * float(points[0].width_scale))
	var left_a := center_a - edge
	var right_a := center_a + edge
	var uv_left_a := Vector2(0.0, distance_a)
	var uv_right_a := Vector2(1.0, distance_a)
	for i in range(1, count):
		var center_b := centres[i] + height_offset
		edge = sides[i] * (half_width * float(points[i].width_scale))
		var left_b := center_b - edge
		var right_b := center_b + edge
		if _has_uv:
			distance_a += center_a.distance_to(center_b)
		var uv_left_b := Vector2(0.0, distance_a)
		var uv_right_b := Vector2(1.0, distance_a)
		_append_triangle(left_a, left_b, right_a, uv_left_a, uv_left_b, uv_right_a)
		_append_triangle(right_a, left_b, right_b, uv_right_a, uv_left_b, uv_right_b)
		center_a = center_b
		left_a = left_b
		right_a = right_b
		uv_left_a = uv_left_b
		uv_right_a = uv_right_b

	if draw_caps:
		_append_round_cap(points[0], sides[0], camera_position, camera_forward, base_width, y_offset,
			first_distance, centres[1] - centres[0])
		_append_round_cap(points[-1], sides[-1], camera_position, camera_forward, base_width, y_offset,
			distance_a, centres[-2] - centres[-1])


func _append_round_cap(point, side_hint: Vector3, camera_position: Vector3, camera_forward: Vector3,
		base_width: float, y_offset: float, distance: float, inward := Vector3.ZERO) -> void:
	var center: Vector3 = point.position + Vector3.UP * y_offset
	var face := _view_vector(center, camera_position, camera_forward)
	if face.length_squared() < 0.000001:
		face = Vector3.UP
	var side := side_hint.normalized()
	if side.length_squared() < 0.000001:
		side = face.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.000001:
		side = Vector3.RIGHT
	var up := face.cross(side).normalized()
	var radius := base_width * 0.5 * float(point.width_scale)
	var steps := CAP_STEPS if inward.is_zero_approx() else CAP_STEPS / 2
	var start := CAP_STEPS / 2 if steps != CAP_STEPS and inward.dot(up) > 0.0 else 0
	var ring_a := _cap_ring[start]
	var edge_a := center + (side * ring_a.x + up * ring_a.y) * radius
	var uv_a := Vector2(0.5 + 0.5 * ring_a.x, distance + ring_a.y * radius)
	var uv_center := Vector2(0.5, distance)
	for i in range(start + 1, start + steps + 1):
		var ring_b := _cap_ring[i]
		var edge_b := center + (side * ring_b.x + up * ring_b.y) * radius
		var uv_b := Vector2(0.5 + 0.5 * ring_b.x, distance + ring_b.y * radius)
		_append_triangle(center, edge_a, edge_b, uv_center, uv_a, uv_b)
		edge_a = edge_b
		uv_a = uv_b


## Direction from `position` toward the viewer, stabilised near the camera.
func _view_vector(position: Vector3, camera_position: Vector3, camera_forward: Vector3) -> Vector3:
	var offset := camera_position - position
	if offset.length_squared() < min_view_distance * min_view_distance:
		return -camera_forward
	return offset.normalized()


func _append_triangle(a: Vector3, b: Vector3, c: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	if _used_vertices + 3 > _max_vertices:
		return
	_vertex_cache[_used_vertices] = a
	_vertex_cache[_used_vertices + 1] = b
	_vertex_cache[_used_vertices + 2] = c
	if _has_uv:
		_uv_cache[_used_vertices] = uv_a
		_uv_cache[_used_vertices + 1] = uv_b
		_uv_cache[_used_vertices + 2] = uv_c
	_used_vertices += 3
	_bounds_low = _bounds_low.min(a).min(b).min(c)
	_bounds_high = _bounds_high.max(a).max(b).max(c)
