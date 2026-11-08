extends RefCounted

const CLOTH := preload("res://assets/props/Stage2_TomatinaVillage/tomatina_festival_cloth.gdshader")
const COLORS := [
	Color("bf392d"), Color("eab84d"), Color("f0db9c"),
	Color("558f88"), Color("b52f31"), Color("54779b"),
]
const ROPE_COLOR := Color("5f4730")
const ALLEY_ROWS := [
	[0.08, 0.23, 0.44, 0.54, 0.68, 0.88],
	[0.09, 0.21, 0.29, 0.37, 0.44, 0.56, 0.65, 0.75, 0.88, 0.94],
	[0.12, 0.21, 0.36, 0.53, 0.68, 0.77, 0.86],
	[0.17, 0.29, 0.42, 0.61, 0.72, 0.85],
]


static func build(parent: Node3D, facades: Array[Transform3D]) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row := 0
	for leg in ALLEY_ROWS.size():
		for progress: float in ALLEY_ROWS[leg]:
			var pose := TomatinaMap._route_pose(leg, progress)
			var forward := Vector3(pose[1].x, 0.0, pose[1].y)
			if _span(surface, facades, TomatinaMap.at_cell(pose[0]), forward, 62.0, row):
				row += 1
	for centre in [Vector2(30.0, 26.4), Vector2(30.0, 33.1)]:
		if _span(surface, facades, TomatinaMap.at_cell(centre), Vector3.FORWARD, 102.0, row):
			row += 1
	for index in range(2, facades.size(), 9):
		_drape(surface, facades[index], COLORS[index % COLORS.size()])

	var material := ShaderMaterial.new()
	material.shader = CLOTH
	surface.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "FestivalBunting"
	mesh.mesh = surface.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


static func _span(surface: SurfaceTool, facades: Array[Transform3D], centre: Vector3,
		forward: Vector3, max_length: float, row: int) -> bool:
	var across := forward.cross(Vector3.UP)
	var endpoints := PackedVector3Array([Vector3.INF, Vector3.INF])
	var scores := PackedFloat32Array([INF, INF])
	for facade in facades:
		var anchor := facade.origin
		var offset := Vector3(anchor.x - centre.x, 0.0, anchor.z - centre.z)
		var lateral := offset.dot(across)
		var along := absf(offset.dot(forward))
		if absf(lateral) < 4.0 or absf(lateral) > max_length * 0.60 or along > 12.0:
			continue
		if facade.basis.z.dot(-offset.normalized()) < 0.42:
			continue
		var side := int(lateral > 0.0)
		var score := along * 2.8 + absf(lateral) * 0.26
		if score < scores[side]:
			scores[side] = score
			endpoints[side] = anchor
	if not endpoints[0].is_finite() or not endpoints[1].is_finite():
		return false
	var length := endpoints[0].distance_to(endpoints[1])
	if length < 8.0 or length > max_length:
		return false
	var sag := clampf(length * 0.031, 0.38, 1.32)
	_add_string(surface, endpoints[0], endpoints[1], sag, row)
	return true


static func _rope_at(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3.UP * (sag * 4.0 * t * (1.0 - t))


static func _add_string(surface: SurfaceTool, a: Vector3, b: Vector3, sag: float, row: int) -> void:
	var length := a.distance_to(b)
	var segments := maxi(8, ceili(length / 1.65))
	var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var front := tangent.cross(Vector3.DOWN)
	for index in segments:
		var start := _rope_at(a, b, sag, float(index) / segments)
		var end := _rope_at(a, b, sag, float(index + 1) / segments)
		for cross in [Vector3.UP * 0.028, front * 0.028]:
			_triangle(surface, [start - cross, start + cross, end + cross], [0.0, 0.0, 0.0], front, ROPE_COLOR)
			_triangle(surface, [start - cross, end + cross, end - cross], [0.0, 0.0, 0.0], front, ROPE_COLOR)
	var flags := maxi(4, floori(length / 1.51))
	for index in range(1, flags):
		var hang := _rope_at(a, b, sag, float(index) / flags)
		var color: Color = COLORS[(row * 3 + index) % COLORS.size()]
		var half_width := 0.37 if index % 4 != 0 else 0.44
		var height := 0.83 + 0.13 * float((row + index) % 3)
		var left := hang - tangent * half_width
		var right := hang + tangent * half_width
		var mid := hang + Vector3.DOWN * height * 0.46
		var mid_left := mid - tangent * half_width * 0.54
		var mid_right := mid + tangent * half_width * 0.54
		var tip := hang + Vector3.DOWN * height + tangent * 0.13
		_triangle(surface, [left, right, mid_right], [0.0, 0.0, 0.46], front, color)
		_triangle(surface, [left, mid_right, mid_left], [0.0, 0.46, 0.46], front, color)
		_triangle(surface, [mid_left, mid_right, tip], [0.46, 0.46, 1.0], front, color)


static func _drape(surface: SurfaceTool, facade: Transform3D, color: Color) -> void:
	var front := facade.basis.z
	var tangent := facade.basis.x
	var top := facade.origin + front * 0.19 - Vector3.UP * 0.52
	var left := top - tangent * 0.72
	var right := top + tangent * 0.72
	var lower_left := left - Vector3.UP * 1.92
	var lower_right := right - Vector3.UP * 1.92
	var notch := top - Vector3.UP * 1.71
	var stripe_left := left - Vector3.UP * 1.43 + front * 0.012
	var stripe_right := right - Vector3.UP * 1.43 + front * 0.012
	_triangle(surface, [left, right, notch], [0.0, 0.0, 0.88], front, color)
	_triangle(surface, [left, notch, lower_left], [0.0, 0.88, 1.0], front, color)
	_triangle(surface, [right, lower_right, notch], [0.0, 1.0, 0.88], front, color)
	var stripe := Color("efcc80")
	_triangle(surface, [stripe_left, stripe_right, stripe_right - Vector3.UP * 0.13],
		[0.74, 0.74, 0.81], front, stripe)
	_triangle(surface, [stripe_left, stripe_right - Vector3.UP * 0.13, stripe_left - Vector3.UP * 0.13],
		[0.74, 0.81, 0.81], front, stripe)


static func _triangle(surface: SurfaceTool, points: Array, weight: Array, normal: Vector3, color: Color) -> void:
	for index in 3:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.set_uv(Vector2(0.0, weight[index]))
		surface.add_vertex(points[index])
