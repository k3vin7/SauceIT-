class_name ContaminableObject
extends StaticBody3D

## Box obstacle whose six faces each carry their own contamination grid, drawn
## on their own quad. Same grid code and same shader as the floor; walls are
## purely visual and are never queried for slipping.

# Per face: outward normal, u axis, v axis. Chosen so u.cross(v) == normal.
const FACE_BASIS := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]

@export var size := Vector3(5.0, 2.2, 0.18)
@export var body_color := Color("8e6f63")

@export_group("Contamination Grid")
@export_range(0.05, 0.5, 0.01, "suffix:m") var cell_size := 0.1
@export_range(0.05, 1.5, 0.01, "suffix:m") var brush_radius := 0.4
@export var mayo_color := Color("fff0a8")

var grids: Array[ContaminationGrid] = []


func _ready() -> void:
	add_to_group("mayo_wall")
	# What the strand looks for: anything it can mark, walls and bodies alike.
	add_to_group("mayo_contaminable")
	_rebuild()


func _process(_delta: float) -> void:
	for grid in grids:
		grid.upload_if_dirty()


func configure(new_cell_size: float, new_brush_radius: float) -> void:
	var grid_changed := not is_equal_approx(cell_size, new_cell_size)
	cell_size = new_cell_size
	brush_radius = new_brush_radius
	if grid_changed and is_node_ready():
		_rebuild()


## Marks the impact on whichever face `world_normal` points out of. Called when
## the raycast hits, not when a point lands, so the stain does not depend on how
## long the strand point survives.
## Returns (face, cell_x, cell_y) for the splat, or (-1, -1, -1) if it missed.
## The floor's note on why the centre cell alone goes over the wire applies here
## too; `paint_mayo_cell` is the replay side.
func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector3i:
	if grids.is_empty():
		return Vector3i(-1, -1, -1)
	var local_normal := (global_transform.basis.inverse() * world_normal).normalized()
	var face := _face_for_normal(local_normal)
	if face < 0:
		return Vector3i(-1, -1, -1)
	var local := to_local(world_position)
	var u_axis: Vector3 = FACE_BASIS[face][1]
	var v_axis: Vector3 = FACE_BASIS[face][2]
	# The brush clips at the face border instead of wrapping around the box
	# edge; a strand hitting a corner marks only the face it hit.
	var cell := grids[face].paint(Vector2(local.dot(u_axis), local.dot(v_axis)), brush_radius)
	if cell.x < 0:
		return Vector3i(-1, -1, -1)
	return Vector3i(face, cell.x, cell.y)


func paint_mayo_cell(face: int, cell: Vector2i) -> void:
	if face < 0 or face >= grids.size():
		return
	grids[face].paint_cell(cell, brush_radius)


func cells_md5() -> String:
	var parts := PackedStringArray()
	for grid in grids:
		parts.push_back(grid.cells_md5())
	return "|".join(parts)


func snapshot_cells(face: int) -> PackedByteArray:
	return grids[face].cells.duplicate()


func restore_cells(face: int, cells: PackedByteArray) -> bool:
	if face < 0 or face >= grids.size():
		return false
	return grids[face].restore_cells(cells)


func face_count() -> int:
	return grids.size()


func painted_cell_count() -> int:
	var total := 0
	for grid in grids:
		total += grid.painted_cell_count()
	return total


func reset_debug_counters() -> void:
	for grid in grids:
		grid.reset_debug_counters()


func debug_paint_calls() -> int:
	var total := 0
	for grid in grids:
		total += grid.paint_calls
	return total


func debug_texture_uploads() -> int:
	var total := 0
	for grid in grids:
		total += grid.texture_uploads
	return total


func _face_for_normal(local_normal: Vector3) -> int:
	var best := -1
	var best_dot := 0.0
	for i in FACE_BASIS.size():
		var dot: float = local_normal.dot(FACE_BASIS[i][0])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best


func _extent_along(axis: Vector3) -> float:
	return absf(axis.x) * size.x + absf(axis.y) * size.y + absf(axis.z) * size.z


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	grids.clear()

	for i in FACE_BASIS.size():
		var normal: Vector3 = FACE_BASIS[i][0]
		var u_axis: Vector3 = FACE_BASIS[i][1]
		var v_axis: Vector3 = FACE_BASIS[i][2]
		var face_extent := Vector2(_extent_along(u_axis), _extent_along(v_axis))
		var grid := ContaminationGrid.new()
		grid.configure(face_extent, cell_size, body_color, mayo_color)
		grids.push_back(grid)

		var face := MeshInstance3D.new()
		face.name = "Face%d" % i
		face.mesh = _build_face_quad(normal, u_axis, v_axis, face_extent)
		face.material_override = grid.material
		add_child(face)

	var collision := CollisionShape3D.new()
	collision.name = "WallCollision"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	add_child(collision)


func _build_face_quad(normal: Vector3, u_axis: Vector3, v_axis: Vector3, face_extent: Vector2) -> ArrayMesh:
	var centre := normal * (_extent_along(normal) * 0.5)
	var half_u := u_axis * (face_extent.x * 0.5)
	var half_v := v_axis * (face_extent.y * 0.5)
	# The same +extent/2 offset is used here and in ContaminationGrid.cell_of,
	# so cell (0,0) is the (-u, -v) corner in both.
	var corner_signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var positions := []
	var uvs := []
	for sign_pair in corner_signs:
		positions.push_back(centre + half_u * sign_pair.x + half_v * sign_pair.y)
		uvs.push_back(Vector2((sign_pair.x + 1.0) * 0.5, (sign_pair.y + 1.0) * 0.5))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var texture_uvs := PackedVector2Array()
	for index in [0, 1, 2, 0, 2, 3]:
		vertices.push_back(positions[index])
		normals.push_back(normal)
		texture_uvs.push_back(uvs[index])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
