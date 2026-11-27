class_name StreamVisual
extends MeshInstance3D

## Fixed-capacity, camera-facing dynamic ribbon. The ArrayMesh surface and its GPU
## vertex buffer are allocated once; frames only upload the used vertex prefix.

const CAP_STEPS := 10

var ribbon_material: Material
var _dynamic_mesh: ArrayMesh
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
	# Worst case allows a round disc for every isolated point. Normal continuous
	# strands use only ~6 vertices per point, so only a small prefix is uploaded.
	_max_vertices = maximum_points * CAP_STEPS * 3 + 60
	_vertex_cache.resize(_max_vertices)
	_vertex_cache.fill(Vector3.ZERO)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertex_cache
	if material is ShaderMaterial:
		_uv_cache.resize(_max_vertices)
		arrays[Mesh.ARRAY_TEX_UV] = _uv_cache
	_dynamic_mesh = ArrayMesh.new()
	_dynamic_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
	)
	_dynamic_mesh.surface_set_material(0, ribbon_material)
	mesh = _dynamic_mesh
	# Dynamic vertex updates do not recalculate the resource AABB, so it is set
	# by hand in `update_ribbon` from the vertices actually written. It used to
	# be a fixed 48 m box around the origin, which was the whole world when the
	# world was one 48 m floor -- on a street that runs 186 m the box is nowhere
	# near the strand, and the renderer culls a stream that is right in front of
	# the player. Nothing else notices: the points still fly, still collide and
	# still paint, so the stains keep landing while the strand blinks out as the
	# view turns and the stale box leaves the frustum.
	visible = false


func set_ribbon_material(material: Material) -> void:
	if ribbon_material != material:
		ribbon_material = material
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

	var upload_vertices := maxi(_used_vertices, _previous_used_vertices)
	var collapse_point := _vertex_cache[0]
	for i in range(_used_vertices, upload_vertices):
		_vertex_cache[i] = collapse_point
	# Convert only the dirty prefix. Converting the full worst-case capacity was
	# measurable even though only the prefix was sent to RenderingServer.
	var vertex_bytes := _vertex_cache.slice(0, upload_vertices).to_byte_array()
	_dynamic_mesh.surface_update_vertex_region(0, 0, vertex_bytes)
	if not _uv_cache.is_empty():
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
	for i in points.size() - 1:
		var point_a = points[i]
		var point_b = points[i + 1]
		var center_a: Vector3 = centres[i] + Vector3.UP * y_offset
		var center_b: Vector3 = centres[i + 1] + Vector3.UP * y_offset
		var half_a := base_width * 0.5 * float(point_a.width_scale)
		var half_b := base_width * 0.5 * float(point_b.width_scale)
		var left_a := center_a - sides[i] * half_a
		var right_a := center_a + sides[i] * half_a
		var left_b := center_b - sides[i + 1] * half_b
		var right_b := center_b + sides[i + 1] * half_b
		var distance_b := distance_a
		if not _uv_cache.is_empty():
			distance_b += center_a.distance_to(center_b)
		var uv_left_a := Vector2(0.0, distance_a)
		var uv_right_a := Vector2(1.0, distance_a)
		var uv_left_b := Vector2(0.0, distance_b)
		var uv_right_b := Vector2(1.0, distance_b)
		_append_triangle(left_a, left_b, right_a, uv_left_a, uv_left_b, uv_right_a)
		_append_triangle(right_a, left_b, right_b, uv_right_a, uv_left_b, uv_right_b)
		distance_a = distance_b

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
	var arc := TAU if inward.is_zero_approx() else PI
	var start := PI if inward.dot(up) > 0.0 else 0.0
	var steps := CAP_STEPS if arc == TAU else CAP_STEPS / 2
	var increment := arc / steps
	for i in steps:
		var angle_a := start + increment * i
		var angle_b := angle_a + increment
		var ring_a := Vector2(cos(angle_a), sin(angle_a))
		var ring_b := Vector2(cos(angle_b), sin(angle_b))
		var edge_a := center + (side * ring_a.x + up * ring_a.y) * radius
		var edge_b := center + (side * ring_b.x + up * ring_b.y) * radius
		_append_triangle(center, edge_a, edge_b, Vector2(0.5, distance),
			Vector2(0.5 + 0.5 * ring_a.x, distance + ring_a.y * radius),
			Vector2(0.5 + 0.5 * ring_b.x, distance + ring_b.y * radius))


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
	if not _uv_cache.is_empty():
		_uv_cache[_used_vertices] = uv_a
		_uv_cache[_used_vertices + 1] = uv_b
		_uv_cache[_used_vertices + 2] = uv_c
	_used_vertices += 3
	_bounds_low = _bounds_low.min(a).min(b).min(c)
	_bounds_high = _bounds_high.max(a).max(b).max(c)
