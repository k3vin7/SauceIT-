class_name FloorContamination
extends StaticBody3D

@export_group("Contamination Grid")
@export_range(0.05, 0.5, 0.01, "suffix:m") var cell_size := 0.2
@export_range(1, 2, 1, "or_greater") var landing_brush_radius_cells := 2
@export var floor_size := Vector2(12.0, 12.0)
@export var clean_color := Color("53616d")
@export var mayo_color := Color("fff0a8")

var _grid_width := 0
var _grid_height := 0
var _cells := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _floor_mesh: MeshInstance3D
var _texture_dirty := false
var debug_paint_calls := 0
var debug_texture_uploads := 0


func _ready() -> void:
	add_to_group("mayo_floor")
	_rebuild_floor()


func _process(_delta: float) -> void:
	# All cell writes performed during a physics frame share one texture upload.
	if _texture_dirty:
		_texture.update(_image)
		_texture_dirty = false
		debug_texture_uploads += 1


func configure(new_cell_size: float, new_brush_radius: int) -> void:
	cell_size = new_cell_size
	landing_brush_radius_cells = clampi(new_brush_radius, 1, 2)
	if is_node_ready():
		_rebuild_grid()


func paint_mayo(world_position: Vector3) -> void:
	debug_paint_calls += 1
	var local_position := to_local(world_position)
	var center_x := floori((local_position.x + floor_size.x * 0.5) / cell_size)
	var center_y := floori((local_position.z + floor_size.y * 0.5) / cell_size)
	if center_x < 0 or center_y < 0 or center_x >= _grid_width or center_y >= _grid_height:
		return

	var radius := landing_brush_radius_cells
	var changed := false
	for offset_y in range(-radius - 1, radius + 2):
		for offset_x in range(-radius - 1, radius + 2):
			var x := center_x + offset_x
			var y := center_y + offset_y
			if x < 0 or y < 0 or x >= _grid_width or y >= _grid_height:
				continue
			var distance := Vector2(offset_x, offset_y).length()
			# Deterministic cell noise roughens only the hard boundary. No blur/alpha.
			var edge_jitter := _cell_noise(x, y) * 0.42
			if distance <= float(radius) + edge_jitter:
				var index := y * _grid_width + x
				if _cells[index] != 1:
					_cells[index] = 1
					_image.set_pixel(x, y, mayo_color)
					changed = true
	if changed:
		_texture_dirty = true


func _rebuild_floor() -> void:
	for child in get_children():
		child.queue_free()

	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "PerfectlyFlatFloor"
	var plane := PlaneMesh.new()
	plane.size = floor_size
	_floor_mesh.mesh = plane
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_mesh)

	var collision := CollisionShape3D.new()
	collision.name = "FloorCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(floor_size.x, 0.04, floor_size.y)
	collision.shape = box
	collision.position.y = -0.02
	add_child(collision)
	_rebuild_grid()


func _rebuild_grid() -> void:
	_grid_width = maxi(1, roundi(floor_size.x / cell_size))
	_grid_height = maxi(1, roundi(floor_size.y / cell_size))
	_cells.resize(_grid_width * _grid_height)
	_cells.fill(0)
	_image = Image.create(_grid_width, _grid_height, false, Image.FORMAT_RGBA8)
	_image.fill(clean_color)
	_texture = ImageTexture.create_from_image(_image)
	_texture_dirty = false
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.92
	material.metallic = 0.0
	_floor_mesh.material_override = material


func _cell_noise(x: int, y: int) -> float:
	var value := sin(float(x * 127 + y * 311 + 19) * 0.173) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
