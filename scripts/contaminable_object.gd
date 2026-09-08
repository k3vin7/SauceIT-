class_name ContaminableObject
extends StaticBody3D

## Box obstacle whose six faces share one contamination grid. Face grids are
## packed into a single atlas image so a wall still costs one draw call, and the
## atlas is uploaded to the texture at most once per rendered frame — the same
## batching rule FloorContamination uses.

const FACE_PADDING := 1

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
@export_range(0.05, 0.5, 0.01, "suffix:m") var cell_size := 0.2
@export_range(1, 2, 1, "or_greater") var impact_brush_radius_cells := 2
@export var mayo_color := Color("fff0a8")

var _atlas_width := 0
var _atlas_height := 0
# Per face: [origin_x, origin_y, grid_width, grid_height].
var _face_regions: Array[Vector4i] = []
var _cells := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _mesh_instance: MeshInstance3D
var _texture_dirty := false
var debug_paint_calls := 0
var debug_texture_uploads := 0


func _ready() -> void:
	add_to_group("mayo_wall")
	_rebuild()


func _process(_delta: float) -> void:
	# All cell writes performed during a physics frame share one texture upload.
	if _texture_dirty:
		_texture.update(_image)
		_texture_dirty = false
		debug_texture_uploads += 1


func configure(new_cell_size: float, new_brush_radius: int) -> void:
	var grid_changed := not is_equal_approx(cell_size, new_cell_size)
	cell_size = new_cell_size
	impact_brush_radius_cells = maxi(new_brush_radius, 1)
	# Only the cell size changes the atlas; the brush radius is read per paint.
	if grid_changed and is_node_ready():
		_rebuild()


## Marks the impact cell and its brush footprint on whichever face `world_normal`
## points out of. Called at collision time, not at landing time — the stain is
## independent of how long the strand point survives.
func paint_mayo(world_position: Vector3, world_normal: Vector3) -> void:
	debug_paint_calls += 1
	if _face_regions.is_empty():
		return
	var basis_inverse := global_transform.basis.inverse()
	var local_normal := (basis_inverse * world_normal).normalized()
	var face := _face_for_normal(local_normal)
	if face < 0:
		return

	var region := _face_regions[face]
	var u_axis: Vector3 = FACE_BASIS[face][1]
	var v_axis: Vector3 = FACE_BASIS[face][2]
	var local_position := to_local(world_position)
	var center_x := floori((local_position.dot(u_axis) + _extent_along(u_axis) * 0.5) / cell_size)
	var center_y := floori((local_position.dot(v_axis) + _extent_along(v_axis) * 0.5) / cell_size)

	var radius := impact_brush_radius_cells
	var changed := false
	for offset_y in range(-radius - 1, radius + 2):
		for offset_x in range(-radius - 1, radius + 2):
			var x := center_x + offset_x
			var y := center_y + offset_y
			# The brush clips at the face border instead of wrapping around the
			# box edge; a strand hitting a corner marks only the face it hit.
			if x < 0 or y < 0 or x >= region.z or y >= region.w:
				continue
			var distance := Vector2(offset_x, offset_y).length()
			# Deterministic cell noise roughens only the hard boundary. No blur/alpha.
			var edge_jitter := _cell_noise(x, y) * 0.42
			if distance <= float(radius) + edge_jitter:
				var atlas_x := region.x + x
				var atlas_y := region.y + y
				var index := atlas_y * _atlas_width + atlas_x
				if _cells[index] != 1:
					_cells[index] = 1
					_image.set_pixel(atlas_x, atlas_y, mayo_color)
					changed = true
	if changed:
		_texture_dirty = true


func painted_cell_count() -> int:
	var total := 0
	for cell in _cells:
		if cell == 1:
			total += 1
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

	_pack_atlas()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "WallVisual"
	_mesh_instance.mesh = _build_box_mesh()
	add_child(_mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "WallCollision"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	add_child(collision)


func _pack_atlas() -> void:
	# Single-row atlas: each face gets a contiguous column block plus one padding
	# column, so nearest-filtered sampling never bleeds across a face boundary.
	_face_regions.clear()
	var cursor_x := 0
	var height := 1
	for i in FACE_BASIS.size():
		var u_axis: Vector3 = FACE_BASIS[i][1]
		var v_axis: Vector3 = FACE_BASIS[i][2]
		var grid_width := maxi(1, roundi(_extent_along(u_axis) / cell_size))
		var grid_height := maxi(1, roundi(_extent_along(v_axis) / cell_size))
		_face_regions.push_back(Vector4i(cursor_x, 0, grid_width, grid_height))
		cursor_x += grid_width + FACE_PADDING
		height = maxi(height, grid_height)

	_atlas_width = cursor_x
	_atlas_height = height
	_cells.resize(_atlas_width * _atlas_height)
	_cells.fill(0)
	_image = Image.create(_atlas_width, _atlas_height, false, Image.FORMAT_RGBA8)
	_image.fill(body_color)
	_texture = ImageTexture.create_from_image(_image)
	_texture_dirty = false


func _build_box_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in FACE_BASIS.size():
		var normal: Vector3 = FACE_BASIS[i][0]
		var u_axis: Vector3 = FACE_BASIS[i][1]
		var v_axis: Vector3 = FACE_BASIS[i][2]
		var region := _face_regions[i]
		var center := normal * (_extent_along(normal) * 0.5)
		var half_u := u_axis * (_extent_along(u_axis) * 0.5)
		var half_v := v_axis * (_extent_along(v_axis) * 0.5)
		# Corners in (u, v) sign order, and their matching atlas UVs. The same
		# +extent/2 offset is used here and in paint_mayo, so cell (0,0) of a
		# face is the (-u, -v) corner in both.
		var corner_signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var corner_positions := []
		var corner_uvs := []
		for sign_pair in corner_signs:
			corner_positions.push_back(center + half_u * sign_pair.x + half_v * sign_pair.y)
			corner_uvs.push_back(Vector2(
				(float(region.x) + (sign_pair.x + 1.0) * 0.5 * float(region.z)) / float(_atlas_width),
				(float(region.y) + (sign_pair.y + 1.0) * 0.5 * float(region.w)) / float(_atlas_height)))
		for index in [0, 1, 2, 0, 2, 3]:
			vertices.push_back(corner_positions[index])
			normals.push_back(normal)
			uvs.push_back(corner_uvs[index])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.86
	material.metallic = 0.0
	# Winding is not relied upon; explicit normals carry the lighting.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _cell_noise(x: int, y: int) -> float:
	var value := sin(float(x * 127 + y * 311 + 19) * 0.173) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
