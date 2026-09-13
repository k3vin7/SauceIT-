class_name ContaminationGrid
extends RefCounted

## One rectangular contamination grid: the cell mask, the texture it uploads to,
## and the material that renders it. The floor owns one; a wall owns one per
## face. Local coordinates run from -extent/2 to +extent/2 on both axes, so the
## same code serves a floor plane and a wall face.

const ShaderFile := preload("res://scripts/contamination.gdshader")

## The splat's edge, in metres: how far it wanders, and how big the wandering's
## features are. Both in metres rather than in cells, because a stain has to
## look the same on a surface whatever that surface's cells happen to be, and
## because the two have to scale together. `_cell_noise` is white noise, one
## value per lattice square, so raising only the amplitude does not make the
## roughness bigger -- it makes a wide band of random speckle. The feature size
## is what turns that back into an edge.
##
## These are what the floor has always had: 0.42 of a 0.1 m cell, one cell to a
## feature. Every other surface now gets the same thing in metres.
const EDGE_WOBBLE_METRES := 0.042
const EDGE_FEATURE_METRES := 0.1

var cell_size := 0.1
var extent := Vector2(1.0, 1.0)
## True when the x axis is a loop rather than an edge, which is what a body
## unwrapped around its own axis needs: a splat near the seam has to carry on
## round the other side instead of being clipped off.
var wrap_x := false
var width := 1
var height := 1
var cells := PackedByteArray()
## The same mask as `cells`, but as the texture wants it: R8 is read back
## normalised, so a painted cell has to be 255 here, not the 1 that `cells`
## carries. Kept alongside rather than converted on upload, which would be a
## pass over the whole grid every frame it changes.
var _image_data := PackedByteArray()
## How big a cell is in metres. The same as cell_size for a surface measured in
## metres, which is all of them but the visor, whose grid is in view units.
var metres_per_cell := 0.1
var image: Image
var texture: ImageTexture
var material: ShaderMaterial
var dirty := false
var paint_calls := 0
var texture_uploads := 0


func configure(new_extent: Vector2, new_cell_size: float, clean_color: Color, mayo_color: Color) -> void:
	extent = new_extent
	cell_size = maxf(new_cell_size, 0.01)
	metres_per_cell = cell_size
	width = maxi(1, roundi(extent.x / cell_size))
	height = maxi(1, roundi(extent.y / cell_size))
	cells.resize(width * height)
	cells.fill(0)
	_image_data.resize(width * height)
	_image_data.fill(0)
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
	if cell.y < 0 or cell.y >= height:
		return false
	return wrap_x or (cell.x >= 0 and cell.x < width)


## The column a cell falls in, brought back inside the grid when x loops.
func wrapped_x(x: int) -> int:
	if not wrap_x:
		return x
	return posmod(x, width)


func is_painted(local: Vector2) -> bool:
	var cell := cell_of(local)
	if not has_cell(cell):
		return false
	return cells[cell.y * width + wrapped_x(cell.x)] == 1


## Marks a disc of `radius_meters` around a local position, and returns the
## centre cell it painted around, or (-1, -1) if the position was off the grid.
## The radius is given in metres and converted here, so changing cell_size does
## not change how big a splat is.
func paint(local: Vector2, radius_meters: float) -> Vector2i:
	return paint_cell(cell_of(local), radius_meters)


## The splat itself, addressed by cell rather than by position. Everything below
## depends only on the centre cell and the radius -- `_cell_noise` is a pure
## function of the cell coordinates -- so two machines given the same centre
## cell paint byte-identical grids. That is what lets the network send two ints
## per splat instead of the cell list, and it is checked by probe_determinism.
func paint_cell(centre: Vector2i, radius_meters: float) -> Vector2i:
	paint_calls += 1
	if not has_cell(centre):
		return Vector2i(-1, -1)
	centre.x = wrapped_x(centre.x)
	var radius := maxi(1, roundi(radius_meters / cell_size))
	var scale := maxf(metres_per_cell, 0.0001)
	# The wobble and its features, converted from metres into this grid's cells.
	var wobble := EDGE_WOBBLE_METRES / scale
	var feature := maxi(1, roundi(EDGE_FEATURE_METRES / scale))
	# Enough margin for the edge to wander outwards without being clipped.
	var margin := maxi(1, ceili(wobble))
	var low := -radius - margin
	var high := radius + margin

	# The noise lattice for this splat, worked out once. Read per cell it was
	# four calls and four sines for every cell tested, which on a big brush is
	# tens of thousands of them; the lattice is `feature` cells apart, so there
	# are a few dozen points in the whole splat. Same values either way.
	var lattice_x0 := floori(float(centre.x + low) / float(feature))
	var lattice_x1 := floori(float(centre.x + high) / float(feature))
	if wrap_x:
		# A splat that runs over the seam comes back on the far side, so its
		# cells can be anywhere across the grid and so can the lattice points
		# they read. A row of them is a few dozen values; the splat's own span
		# is no use here.
		lattice_x0 = 0
		lattice_x1 = floori(float(width - 1) / float(feature))
	var lattice_y0 := floori(float(centre.y + low) / float(feature))
	var lattice_w := lattice_x1 - lattice_x0 + 2
	var lattice_h := floori(float(centre.y + high) / float(feature)) - lattice_y0 + 2
	var lattice := PackedFloat32Array()
	lattice.resize(lattice_w * lattice_h)
	for ly in lattice_h:
		for lx in lattice_w:
			lattice[ly * lattice_w + lx] = _cell_noise(lattice_x0 + lx, lattice_y0 + ly)

	var changed := false
	# has_cell, wrapped_x and a Vector2 length are all inlined below: this loop
	# runs once per cell in the brush's bounding box, which on a big brush is
	# tens of thousands of times per splat, and a GDScript call is dear.
	for offset_y in range(low, high + 1):
		var row := centre.y + offset_y
		if row < 0 or row >= height:
			continue
		var row_base := row * width
		for offset_x in range(low, high + 1):
			var column := centre.x + offset_x
			if wrap_x:
				# The noise is read at the wrapped column, so a cell gets the
				# same jitter whichever side of the seam the splat came from.
				column = posmod(column, width)
			elif column < 0 or column >= width:
				continue
			var index := row_base + column
			if cells[index] == 1:
				continue
			var cell := Vector2i(column, row)
			var distance_squared := float(offset_x * offset_x + offset_y * offset_y)
			# Value noise off the lattice above, inlined: the four points around
			# this cell, eased and blended, so the edge wanders continuously
			# rather than stepping from one lattice square to the next.
			var place_x := float(cell.x) / float(feature)
			var place_y := float(cell.y) / float(feature)
			var base_x := floori(place_x)
			var base_y := floori(place_y)
			var across := smoothstep(0.0, 1.0, place_x - float(base_x))
			var down := smoothstep(0.0, 1.0, place_y - float(base_y))
			var corner := (base_y - lattice_y0) * lattice_w + (base_x - lattice_x0)
			var top: float = lerpf(lattice[corner], lattice[corner + 1], across)
			var bottom: float = lerpf(lattice[corner + lattice_w],
				lattice[corner + lattice_w + 1], across)
			# Deterministic cell noise roughens only the hard boundary. No blur/alpha.
			var edge_jitter: float = lerpf(top, bottom, down) * wobble
			var reach := float(radius) + edge_jitter
			# Squared on both sides, to keep the square root out of the loop.
			if reach > 0.0 and distance_squared <= reach * reach:
				cells[index] = 1
				_image_data[index] = 255
				changed = true
	if changed:
		dirty = true
	return centre


## Wipes the grid. Both halves of the mask go together -- clearing one and not
## the other is how a wiped surface keeps showing its old stain.
func clear() -> void:
	cells.fill(0)
	_image_data.fill(0)
	dirty = true


## Byte-exact fingerprint of the whole cell mask, for comparing two machines'
## grids against each other.
func cells_md5() -> String:
	return Marshalls.raw_to_base64(cells).md5_text()


## Replaces the whole mask, for handing a joining peer the state it missed.
func restore_cells(new_cells: PackedByteArray) -> bool:
	if new_cells.size() != cells.size():
		return false
	cells = new_cells
	for i in cells.size():
		_image_data[i] = 255 if cells[i] == 1 else 0
	dirty = true
	return true


## All cell writes made during a physics frame share one upload. The image is
## rebuilt from the mask rather than kept in step cell by cell: `cells` is
## already exactly an R8 buffer, and one allocation a frame beats a set_pixel
## for every cell a splat touches.
func upload_if_dirty() -> void:
	if not dirty:
		return
	image = Image.create_from_data(width, height, false, Image.FORMAT_R8, _image_data)
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


## Value noise on a lattice `feature` cells wide: the four lattice points around
## the cell, eased and blended. Picking one value per lattice square instead
## would give every cell in the square the same threshold, and the square's own
## edges would show through as steps -- which is what a coarse feature size did
## before this. A pure function of the cell and the feature size, so it stays
## deterministic.
##
## At a feature size of one cell this is exactly `_cell_noise`: the lattice
## coordinate lands on an integer, the blend weights are zero, and the corner
## value is returned unchanged. The floor is on that size, so it is untouched.
func _edge_noise(x: int, y: int, feature: int) -> float:
	var lattice_x := float(x) / float(feature)
	var lattice_y := float(y) / float(feature)
	var x0 := floori(lattice_x)
	var y0 := floori(lattice_y)
	var across := smoothstep(0.0, 1.0, lattice_x - float(x0))
	var down := smoothstep(0.0, 1.0, lattice_y - float(y0))
	return lerpf(
		lerpf(_cell_noise(x0, y0), _cell_noise(x0 + 1, y0), across),
		lerpf(_cell_noise(x0, y0 + 1), _cell_noise(x0 + 1, y0 + 1), across),
		down)


func _cell_noise(x: int, y: int) -> float:
	var value := sin(float(x * 127 + y * 311 + 19) * 0.173) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
