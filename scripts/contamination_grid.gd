class_name ContaminationGrid
extends RefCounted

## One rectangular contamination grid: the cell mask, the texture it uploads to,
## and the material that renders it. The floor owns one; a wall owns one per
## face. Local coordinates run from -extent/2 to +extent/2 on both axes, so the
## same code serves a floor plane and a wall face.

const ShaderFile := preload("res://scripts/contamination.gdshader")

var cell_size := 0.1
var extent := Vector2(1.0, 1.0)
var width := 1
var height := 1
var cells := PackedByteArray()
var image: Image
var texture: ImageTexture
var material: ShaderMaterial
var dirty := false
var paint_calls := 0
var texture_uploads := 0


func configure(new_extent: Vector2, new_cell_size: float, clean_color: Color, mayo_color: Color) -> void:
	extent = new_extent
	cell_size = maxf(new_cell_size, 0.01)
	width = maxi(1, roundi(extent.x / cell_size))
	height = maxi(1, roundi(extent.y / cell_size))
	cells.resize(width * height)
	cells.fill(0)
	# One byte per cell. No mipmaps: they would soften the boundary at distance.
	image = Image.create(width, height, false, Image.FORMAT_R8)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	texture = ImageTexture.create_from_image(image)
	dirty = false

	material = ShaderMaterial.new()
	material.shader = ShaderFile
	material.set_shader_parameter("mask_texture", texture)
	material.set_shader_parameter("clean_color", clean_color)
	material.set_shader_parameter("mayo_color", mayo_color)


## Cell containing a local position, without clamping.
func cell_of(local: Vector2) -> Vector2i:
	return Vector2i(
		floori((local.x + extent.x * 0.5) / cell_size),
		floori((local.y + extent.y * 0.5) / cell_size))


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_painted(local: Vector2) -> bool:
	var cell := cell_of(local)
	if not has_cell(cell):
		return false
	return cells[cell.y * width + cell.x] == 1


## Marks a disc of `radius_meters` around a local position. The radius is given
## in metres and converted here, so changing cell_size does not change how big
## a splat is.
func paint(local: Vector2, radius_meters: float) -> void:
	paint_calls += 1
	var centre := cell_of(local)
	if not has_cell(centre):
		return
	var radius := maxi(1, roundi(radius_meters / cell_size))
	var changed := false
	for offset_y in range(-radius - 1, radius + 2):
		for offset_x in range(-radius - 1, radius + 2):
			var cell := centre + Vector2i(offset_x, offset_y)
			if not has_cell(cell):
				continue
			var distance := Vector2(offset_x, offset_y).length()
			# Deterministic cell noise roughens only the hard boundary. No blur/alpha.
			var edge_jitter := _cell_noise(cell.x, cell.y) * 0.42
			if distance <= float(radius) + edge_jitter:
				var index := cell.y * width + cell.x
				if cells[index] != 1:
					cells[index] = 1
					image.set_pixel(cell.x, cell.y, Color(1.0, 0.0, 0.0, 1.0))
					changed = true
	if changed:
		dirty = true


## All cell writes made during a physics frame share one upload.
func upload_if_dirty() -> void:
	if not dirty:
		return
	texture.update(image)
	dirty = false
	texture_uploads += 1


func reset_debug_counters() -> void:
	paint_calls = 0
	texture_uploads = 0


func painted_cell_count() -> int:
	var total := 0
	for cell in cells:
		if cell == 1:
			total += 1
	return total


## The value the shader samples, evaluated on the CPU. Used by the checks to
## confirm the rendered boundary and the slip test agree.
func sample_bilinear(local: Vector2) -> float:
	var texel := Vector2(
		(local.x + extent.x * 0.5) / cell_size - 0.5,
		(local.y + extent.y * 0.5) / cell_size - 0.5)
	var base := Vector2i(floori(texel.x), floori(texel.y))
	var frac := texel - Vector2(base)
	var total := 0.0
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for corner in corners:
		var cell: Vector2i = base + corner
		# Sampling clamps at the texture edge, matching repeat_disable.
		cell.x = clampi(cell.x, 0, width - 1)
		cell.y = clampi(cell.y, 0, height - 1)
		var value := float(cells[cell.y * width + cell.x])
		var weight_x: float = frac.x if corner.x == 1 else 1.0 - frac.x
		var weight_y: float = frac.y if corner.y == 1 else 1.0 - frac.y
		total += value * weight_x * weight_y
	return total


func _cell_noise(x: int, y: int) -> float:
	var value := sin(float(x * 127 + y * 311 + 19) * 0.173) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
