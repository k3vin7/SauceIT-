class_name StreamVisual
extends MeshInstance3D

## Fixed-capacity, camera-facing dynamic ribbon. The ArrayMesh surface and its GPU
## vertex buffer are allocated once; frames only upload the used vertex prefix.

const CAP_STEPS := 10

var ribbon_material: Material
var _dynamic_mesh: ArrayMesh
var _vertex_cache := PackedVector3Array()
var _max_vertices := 0
var _used_vertices := 0
var _previous_used_vertices := 0
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
	# Dynamic vertex updates do not recalculate the resource AABB.
	custom_aabb = AABB(Vector3(-24.0, -4.0, -24.0), Vector3(48.0, 20.0, 48.0))
	visible = false


func update_ribbon(
		segments: Array,
		camera_position: Vector3,
		camera_forward: Vector3,
		base_width: float,
		_tint: Color,
		y_offset: float = 0.0
	) -> void:
	_used_vertices = 0
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
	_previous_used_vertices = _used_vertices
	visible = true


func _append_strip(points: Array, camera_position: Vector3, camera_forward: Vector3, base_width: float, y_offset: float) -> void:
	if points.size() == 1:
		_append_round_cap(points[0], Vector3.RIGHT, camera_position, camera_forward, base_width, y_offset)
		return

	var sides: Array[Vector3] = []
	sides.resize(points.size())
	for i in points.size():
		var position: Vector3 = points[i].position
		var previous: Vector3 = points[maxi(i - 1, 0)].position
		var following: Vector3 = points[mini(i + 1, points.size() - 1)].position
		var tangent := (following - previous).normalized()
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		var to_camera := _view_vector(position, camera_position, camera_forward)
		var side := tangent.cross(to_camera)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		sides[i] = side.normalized()

	for i in range(1, points.size() - 1):
		var joined: Vector3 = sides[i - 1] + sides[i] + sides[i + 1]
		if joined.length_squared() > 0.000001:
			sides[i] = joined.normalized()

	for i in points.size() - 1:
		var point_a = points[i]
		var point_b = points[i + 1]
		var center_a: Vector3 = point_a.position + Vector3.UP * y_offset
		var center_b: Vector3 = point_b.position + Vector3.UP * y_offset
		var half_a := base_width * 0.5 * float(point_a.width_scale)
		var half_b := base_width * 0.5 * float(point_b.width_scale)
		var left_a := center_a - sides[i] * half_a
		var right_a := center_a + sides[i] * half_a
		var left_b := center_b - sides[i + 1] * half_b
		var right_b := center_b + sides[i + 1] * half_b
		_append_triangle(left_a, left_b, right_a)
		_append_triangle(right_a, left_b, right_b)

	_append_round_cap(points[0], sides[0], camera_position, camera_forward, base_width, y_offset)
	_append_round_cap(points[-1], sides[-1], camera_position, camera_forward, base_width, y_offset)


func _append_round_cap(point, side_hint: Vector3, camera_position: Vector3, camera_forward: Vector3, base_width: float, y_offset: float) -> void:
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
	for i in CAP_STEPS:
		var angle_a := TAU * float(i) / float(CAP_STEPS)
		var angle_b := TAU * float(i + 1) / float(CAP_STEPS)
		var edge_a := center + (side * cos(angle_a) + up * sin(angle_a)) * radius
		var edge_b := center + (side * cos(angle_b) + up * sin(angle_b)) * radius
		_append_triangle(center, edge_a, edge_b)


## Direction from `position` toward the viewer, stabilised near the camera.
func _view_vector(position: Vector3, camera_position: Vector3, camera_forward: Vector3) -> Vector3:
	var offset := camera_position - position
	if offset.length_squared() < min_view_distance * min_view_distance:
		return -camera_forward
	return offset.normalized()


func _append_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	if _used_vertices + 3 > _max_vertices:
		return
	_vertex_cache[_used_vertices] = a
	_vertex_cache[_used_vertices + 1] = b
	_vertex_cache[_used_vertices + 2] = c
	_used_vertices += 3
