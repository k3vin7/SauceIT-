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
## One byte per cell, and that byte is now **how thick the mayo is**, 0 to 255,
## rather than whether there is any. Sauce lands in amounts and piles up, and
## the slip test reads a threshold on it rather than a flag.
##
## It doubles as the texture's own bytes. It used to be a 0/1 mask with a
## parallel array of 0/255 kept beside it purely so the R8 texture had something
## to read; a thickness is already exactly what the texture wants, so the second
## array is gone -- on the floor that is 13.9 MB of it.
var cells := PackedByteArray()
## How big a cell is in metres. Every contamination surface uses metre units.
var metres_per_cell := 0.1
## The grid is uploaded as tiles, and only the tiles that changed are sent.
##
## **Why tiles and not a dirty rectangle.** A dirty rectangle is the obvious
## answer and cannot be built here: Godot's public API has no partial update for
## a 2D texture. `ImageTexture.update` and `RenderingServer.texture_2d_update`
## both replace the whole thing, so knowing precisely which cells changed buys
## nothing -- the upload is all-or-nothing per texture. Making the textures
## smaller is therefore the only lever there is, and that is what a tile is.
##
## The data does **not** tile. `cells` stays one array over the whole surface,
## because the slip test, the network snapshot and the determinism hash all read
## it and all want one. Only the upload is cut up.
var tile_cells := 0
var _tiles_across := 1
var _tiles_down := 1
var _tile_textures: Array[ImageTexture] = []
var _tile_materials: Array[ShaderMaterial] = []
var _tile_dirty := PackedByteArray()
## Bytes handed to the GPU by the last `upload_if_dirty`, and since the last
## reset. What the headless checks can measure of an upload they cannot time.
var bytes_uploaded := 0
var bytes_uploaded_total := 0

## Running counts, kept as cells change rather than found by scanning. The floor
## is fourteen million cells and something wants to know "how much of it is
## dangerous" a few times a second; walking it to find out costs more than
## everything else the floor does put together.
var painted_count := 0
var deep_count := 0
## The thickness `deep_count` counts past. Set by whoever owns the threshold.
var deep_threshold := 255

## The cells each live burst has already coated, one set per burst.
##
## **A cell rises once per trigger pull, however many splats land on it.** The
## stream does not spread its sauce evenly: measured on a standing burst, the
## cell the stream sat on took 100 of the 111 splats while the far end of the
## same trail took one to three. Counting splats therefore made the head of a
## trail slippery inside a second and the tail of the same trail never, which is
## exactly what "only the bit it landed on turns yellow" was.
##
## Counting *passes* instead makes the whole trail equal: one trigger pull adds
## one layer everywhere it reached, and it takes three overlapping passes to
## make anything slippery -- head, tail and all.
##
## Kept as a set per burst rather than a coat id per cell, because a byte per
## cell is 13.9 MB on the floor and a burst only ever touches a few thousand.
## Old bursts are evicted by id, oldest first: four players can have four bursts
## in the air at once, and a burst that has stopped arriving is finished.
var _coats := {}
const MAX_LIVE_COATS := 8

var image: Image
var texture: ImageTexture
var material: ShaderMaterial
var dirty := false
var paint_calls := 0
var texture_uploads := 0


## `new_tile_cells` of 0 means one tile over the whole surface, which is what a
## wall face or a body wants -- they are small, and a second texture would cost
## more in draw calls than it ever saved in upload. The floor passes a real size.
func configure(new_extent: Vector2, new_cell_size: float, clean_color: Color,
		mayo_color: Color, new_tile_cells := 0) -> void:
	extent = new_extent
	cell_size = maxf(new_cell_size, 0.01)
	metres_per_cell = cell_size
	width = maxi(1, roundi(extent.x / cell_size))
	height = maxi(1, roundi(extent.y / cell_size))
	cells.resize(width * height)
	cells.fill(0)
	painted_count = 0
	deep_count = 0

	tile_cells = maxi(width, height) if new_tile_cells <= 0 else new_tile_cells
	_tiles_across = ceili(float(width) / float(tile_cells))
	_tiles_down = ceili(float(height) / float(tile_cells))
	_tile_dirty.resize(_tiles_across * _tiles_down)
	_tile_dirty.fill(0)
	_tile_textures.clear()
	_tile_materials.clear()
	for index in _tiles_across * _tiles_down:
		var size := tile_size(index)
		# One byte per cell. No mipmaps: they would soften the boundary at
		# distance, and the boundary is the whole look.
		var tile_image := Image.create(size.x, size.y, false, Image.FORMAT_R8)
		tile_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		var tile_texture := ImageTexture.create_from_image(tile_image)
		_tile_textures.push_back(tile_texture)
		var tile_material := ShaderMaterial.new()
		tile_material.shader = ShaderFile
		tile_material.set_shader_parameter("mask_texture", tile_texture)
		tile_material.set_shader_parameter("clean_color", clean_color)
		tile_material.set_shader_parameter("mayo_color", mayo_color)
		_tile_materials.push_back(tile_material)
	dirty = false
	bytes_uploaded = 0

	# The single-tile case keeps the old names, so every surface that only ever
	# had one texture carries on addressing it the way it always did.
	texture = _tile_textures[0]
	material = _tile_materials[0]
	image = Image.create(tile_size(0).x, tile_size(0).y, false, Image.FORMAT_R8)


func tile_count() -> int:
	return _tile_textures.size()


func tile_material(index: int) -> ShaderMaterial:
	return _tile_materials[index]


## Where a tile starts, in cells.
func tile_origin(index: int) -> Vector2i:
	return Vector2i((index % _tiles_across) * tile_cells, (index / _tiles_across) * tile_cells)


## How big a tile is, in cells. The last column and row are short.
func tile_size(index: int) -> Vector2i:
	var origin := tile_origin(index)
	return Vector2i(mini(tile_cells, width - origin.x), mini(tile_cells, height - origin.y))


## The patch of surface a tile covers, in local metres, for laying out its quad.
func tile_region(index: int) -> Rect2:
	var origin := tile_origin(index)
	var size := tile_size(index)
	return Rect2(
		Vector2(float(origin.x) * cell_size - extent.x * 0.5,
			float(origin.y) * cell_size - extent.y * 0.5),
		Vector2(float(size.x) * cell_size, float(size.y) * cell_size))


func _touch_tile(column: int, row: int) -> void:
	_tile_dirty[(row / tile_cells) * _tiles_across + (column / tile_cells)] = 1


func _touch_all_tiles() -> void:
	_tile_dirty.fill(1)


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
	return cells[cell.y * width + wrapped_x(cell.x)] > 0


## Marks a disc of `radius_meters` around a local position, and returns the
## centre cell it painted around, or (-1, -1) if the position was off the grid.
## The radius is given in metres and converted here, so changing cell_size does
## not change how big a splat is.
func paint(local: Vector2, radius_meters: float, deposit := 1, coat := -1) -> Vector2i:
	return paint_cell(cell_of(local), radius_meters, deposit, coat)


## The splat itself, addressed by cell rather than by position. Everything below
## depends only on the centre cell and the radius -- `_cell_noise` is a pure
## function of the cell coordinates -- so two machines given the same centre
## cell paint byte-identical grids. That is what lets the network send two ints
## per splat instead of the cell list, and it is checked by probe_determinism.
## `coat` identifies the trigger pull this splat belongs to. A cell rises at most
## once for a given coat, so a burst lays down one layer rather than one per
## splat. -1 means no coat: every splat counts, which is what the surfaces
## nobody walks on still do.
func paint_cell(centre: Vector2i, radius_meters: float, deposit := 1,
		coat := -1) -> Vector2i:
	paint_calls += 1
	if not has_cell(centre):
		return Vector2i(-1, -1)
	var coated := {}
	if coat >= 0:
		if not _coats.has(coat):
			if _coats.size() >= MAX_LIVE_COATS:
				var ids := _coats.keys()
				ids.sort()
				_coats.erase(ids[0])
			_coats[coat] = {}
		coated = _coats[coat]
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
			# Saturated cells are done: nothing more can land on them, and
			# skipping them keeps the noise work off the hottest cells.
			if cells[index] >= 255:
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
				# Already part of this pass: the stream crossing the same cell
				# again inside one trigger pull adds nothing.
				if coat >= 0:
					if coated.has(index):
						continue
					coated[index] = true
				# Added, not set. What makes a patch dangerous is how many
				# passes have gone over it, and each one adds its layer to
				# whatever the last one left.
				var was := int(cells[index])
				var now := mini(was + deposit, 255)
				cells[index] = now
				if was == 0:
					painted_count += 1
				if was < deep_threshold and now >= deep_threshold:
					deep_count += 1
				_touch_tile(column, row)
				changed = true
	if changed:
		dirty = true
	return centre


## Wipes the grid. Both halves of the mask go together -- clearing one and not
## the other is how a wiped surface keeps showing its old stain.
func clear() -> void:
	cells.fill(0)
	_coats.clear()
	painted_count = 0
	deep_count = 0
	_touch_all_tiles()
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
	# Recounted rather than tracked: a restore replaces everything at once and
	# happens when a peer joins, not in a frame that matters.
	_recount()
	_touch_all_tiles()
	dirty = true
	return true


## All cell writes made during a physics frame share one upload. The image is
## rebuilt from the mask rather than kept in step cell by cell: `cells` is
## already exactly an R8 buffer, and one allocation a frame beats a set_pixel
## for every cell a splat touches.
func upload_if_dirty() -> void:
	# Reset *after* the early out, not before it: this is "what the last real
	# upload cost", and zeroing it on every idle call meant anything reading it
	# a frame later almost always saw 0. `bytes_uploaded_total` is what to take
	# differences of.
	if not dirty:
		return
	bytes_uploaded = 0
	for index in _tile_textures.size():
		if _tile_dirty[index] == 0:
			continue
		_tile_dirty[index] = 0
		var origin := tile_origin(index)
		var size := tile_size(index)
		# The tile's bytes are cut out of `cells` a row at a time. A row is one
		# `slice`, which is a memcpy; going cell by cell would be a quarter of a
		# million GDScript iterations per tile and would cost far more than the
		# upload it is feeding.
		var data := PackedByteArray()
		for row in size.y:
			var start := (origin.y + row) * width + origin.x
			data.append_array(cells.slice(start, start + size.x))
		var tile_image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, data)
		_tile_textures[index].update(tile_image)
		bytes_uploaded += data.size()
		texture_uploads += 1
	bytes_uploaded_total += bytes_uploaded
	dirty = false
	# Kept in step for anything reading the whole-surface image, which is the
	# checks: headless has no GPU to read a texture back from.
	if _tile_textures.size() == 1:
		image = Image.create_from_data(width, height, false, Image.FORMAT_R8, cells)


func reset_debug_counters() -> void:
	paint_calls = 0
	texture_uploads = 0
	bytes_uploaded = 0
	bytes_uploaded_total = 0


## The running count. `cells_at_least` below is the scanning version, for the
## checks that want to confirm this one is telling the truth.
func painted_cell_count() -> int:
	return painted_count


func _recount() -> void:
	painted_count = 0
	deep_count = 0
	for cell in cells:
		if cell > 0:
			painted_count += 1
			if cell >= deep_threshold:
				deep_count += 1


## How many cells are at or over a thickness. For the debug readout: how much of
## this floor is thick enough to put someone down.
func cells_at_least(thickness: int) -> int:
	var total := 0
	for cell in cells:
		if cell >= thickness:
			total += 1
	return total


## Thickness under a local position, 0 to 255, or 0 off the grid.
func thickness_at(local: Vector2) -> int:
	var cell := cell_of(local)
	if not has_cell(cell):
		return 0
	return cells[cell.y * width + wrapped_x(cell.x)]


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
