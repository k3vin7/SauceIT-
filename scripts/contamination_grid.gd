class_name ContaminationGrid
extends RefCounted

signal tile_paint_changed(index: int, has_paint: bool)

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
const KETCHUP_DROP_ANGLES := [-0.85, 0.12, 1.04, 2.68, -2.16]

const BRUSH_POOL := 0
const BRUSH_FLECK := 1
const BRUSH_BEAD := 2
const BRUSH_STROKE := 3
const STROKE_DIRECTIONS := 12
const BRUSH_KIND_MASK := 31
const BRUSH_PHASE_SHIFT := 5
const DETAIL_BRUSH_LIMIT := 1152
# Reused across grids with the same resolution and brush radius.
static var _detail_brushes: Dictionary[Vector4i, PackedInt32Array] = {}


static func stroke_brush(tangent: Vector2) -> int:
	if tangent.length_squared() < 0.12 * 0.12:
		return BRUSH_POOL
	return BRUSH_STROKE + posmod(roundi(tangent.angle() * float(STROKE_DIRECTIONS) / TAU), STROKE_DIRECTIONS)

var cell_size := 0.1
var extent := Vector2(1.0, 1.0)
## True when the x axis is a loop rather than an edge, which is what a body
## unwrapped around its own axis needs: a splat near the seam has to carry on
## round the other side instead of being clipped off.
var wrap_x := false
var scatter_ketchup := false
var width := 1
var height := 1
## One byte per cell, holding **which sauce is on it and how thick that sauce
## is**: the thickness in the top six bits, the sauce in the bottom two.
##
## It doubles as the texture's own bytes. It used to be a 0/1 mask with a
## parallel array of 0/255 kept beside it purely so the R8 texture had something
## to read; a thickness is already exactly what the texture wants, so the second
## array is gone -- on the floor that is 13.9 MB of it.
##
## **Why the sauce goes in the *bottom* bits.** A second array of kinds beside
## this one is another 13.9 MB on this floor, so the kind shares the byte. Which
## end it shares matters, because `contamination.gdshader` samples this texture
## twice: `texelFetch` for the thickness bands, which reads a cell's own byte and
## does not care how it is laid out, and a `filter_linear` `texture()` for the
## boundary, which blends neighbouring bytes and very much does. With the kind in
## the top bits, mayo one layer deep beside mustard one layer deep is byte 1
## against byte 65, and the blend between them passes through 33 -- a boundary
## drawn as if there were a thick pile of mayo along every seam between two
## sauces. In the bottom bits the same pair is 4 against 5: a kind is worth less
## than one layer, so the blend stays a blend of thicknesses and the seam is
## drawn where it actually is.
##
## Thresholds move with it. A thickness of `t` is stored as `t << KIND_BITS`, so
## whoever sets the shader's cut-offs scales them the same way -- which is the
## whole of what the five shaders reading this needed to keep working.
var cells := PackedByteArray()
## Signed distance from the rounded stain, encoded around 128 at its edge.
var contour_cells := PackedByteArray()
var contour_texture: ImageTexture
var _contour_textures: Array[ImageTexture] = []
## How many of the low bits name the sauce, and the mask that reads them.
const KIND_BITS := 2
const KIND_MASK := 0b11
## The sauces a cell can hold. Mayo is 0 so an untouched byte and a cell of
## nothing are the same thing, and so is the value every caller that predates
## more than one sauce passes without knowing it.
const KIND_MAYO := 0
const KIND_MUSTARD := 1
const KIND_KETCHUP := 2
## Six bits of thickness rather than eight. The bands the floor draws run to
## twenty-odd layers, so 63 is still an order of magnitude of headroom over what
## anything reads -- and the alternative was a second array the size of this one.
const MAX_THICKNESS := 63
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
const UPLOAD_THICKNESS := 1
const UPLOAD_CONTOUR := 2
const UPLOAD_BOTH := UPLOAD_THICKNESS | UPLOAD_CONTOUR
var _tile_dirty := PackedByteArray()
var track_tile_paint := false
var _tile_paint_channels := PackedByteArray()
var _next_upload_tile := 0
var _tile_margin := 0
var _tile_samples: Array[Rect2i] = []
var _wash_spans: Dictionary[float, PackedInt32Array] = {}
## Bytes handed to the GPU by the last `upload_if_dirty`, and since the last
## reset. What the headless checks can measure of an upload they cannot time.
var bytes_uploaded := 0
var bytes_uploaded_total := 0
var measure_uploads := false
var upload_time_us := 0

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
## Counting *layers* instead puts both ends of a trail on the same clock. A
## coat is opened per trigger pull and reopened every `coat_seconds` it stays
## open, so brushing a cell in passing leaves one layer and holding the stream
## on it leaves one every interval -- sauce pools where you park it, at a rate
## that no longer outruns the rest of the trail by a hundred to one.
##
## Kept as a set per coat rather than a coat id per cell, because a byte per
## cell is 13.9 MB on the floor and a coat only ever touches a few thousand.
## Old coats are evicted by id, oldest first: a held trigger opens a few a
## second and four players can be firing, so the ceiling is generous and a coat
## that has stopped arriving is finished.
var _coats := {}
const MAX_LIVE_COATS := 48

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
		mayo_color: Color, new_tile_cells := 0, tile_margin := 0) -> void:
	extent = new_extent
	cell_size = maxf(new_cell_size, 0.01)
	metres_per_cell = cell_size
	width = maxi(1, roundi(extent.x / cell_size))
	height = maxi(1, roundi(extent.y / cell_size))
	cells.resize(width * height)
	cells.fill(0)
	contour_cells.resize(cells.size() if cell_size <= 0.05 else 0)
	contour_cells.fill(0)
	painted_count = 0
	deep_count = 0
	_coats.clear()
	_wash_spans.clear()

	tile_cells = maxi(width, height) if new_tile_cells <= 0 else new_tile_cells
	_tiles_across = ceili(float(width) / float(tile_cells))
	_tiles_down = ceili(float(height) / float(tile_cells))
	_tile_dirty.resize(_tiles_across * _tiles_down)
	_tile_dirty.fill(0)
	_tile_paint_channels.resize(_tile_dirty.size() if track_tile_paint else 0)
	_tile_paint_channels.fill(0)
	_next_upload_tile = 0
	_tile_textures.clear()
	_contour_textures.clear()
	_tile_materials.clear()
	_tile_samples.clear()
	_tile_margin = clampi(tile_margin if contour_cells.is_empty() else maxi(tile_margin, 2), 0, tile_cells - 1)
	for index in _tiles_across * _tiles_down:
		var interior := Rect2i(tile_origin(index), tile_size(index))
		var sample_rect := interior.grow(_tile_margin).intersection(Rect2i(0, 0, width, height))
		_tile_samples.append(sample_rect)
		var size := sample_rect.size
		# One byte per cell. No mipmaps: they would soften the boundary at
		# distance, and the boundary is the whole look.
		var tile_image := Image.create(size.x, size.y, false, Image.FORMAT_R8)
		tile_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		var tile_texture := ImageTexture.create_from_image(tile_image)
		_tile_textures.push_back(tile_texture)
		var tile_material := ShaderMaterial.new()
		tile_material.shader = ShaderFile
		tile_material.set_shader_parameter("mask_texture", tile_texture)
		tile_material.set_shader_parameter("fine_contours", not contour_cells.is_empty())
		if not contour_cells.is_empty():
			var field := ImageTexture.create_from_image(tile_image)
			_contour_textures.push_back(field)
			tile_material.set_shader_parameter("contour_texture", field)
		if _tile_margin > 0:
			tile_material.set_shader_parameter("mask_cell_origin", Vector2(sample_rect.position))
		if sample_rect != interior:
			tile_material.set_shader_parameter("mask_uv_offset", Vector2(interior.position - sample_rect.position) / Vector2(size))
			tile_material.set_shader_parameter("mask_uv_scale", Vector2(interior.size) / Vector2(size))
		tile_material.set_shader_parameter("clean_color", clean_color)
		tile_material.set_shader_parameter("mayo_color", mayo_color)
		_tile_materials.push_back(tile_material)
	dirty = false
	bytes_uploaded = 0

	# The single-tile case keeps the old names, so every surface that only ever
	# had one texture carries on addressing it the way it always did.
	texture = _tile_textures[0]
	contour_texture = null if _contour_textures.is_empty() else _contour_textures[0]
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
	var tile_x := column / tile_cells
	var tile_y := row / tile_cells
	_tile_dirty[tile_y * _tiles_across + tile_x] |= UPLOAD_BOTH
	# The border texels belong to the neighbouring tile's filter too.
	if _tile_margin > 0 and _tile_dirty.size() > 1:
		var x := column % tile_cells
		var y := row % tile_cells
		if x < _tile_margin or x >= tile_cells - _tile_margin \
				or y < _tile_margin or y >= tile_cells - _tile_margin:
			_touch_tile_span(column, row, column, row)


func _touch_tile_span(left: int, top: int, right: int, bottom: int, channels := UPLOAD_BOTH) -> void:
	if _tile_dirty.size() == 1:
		_tile_dirty[0] |= channels
		return
	var first_x := maxi(0, left - _tile_margin) / tile_cells
	var last_x := mini(width - 1, right + _tile_margin) / tile_cells
	var first_y := maxi(0, top - _tile_margin) / tile_cells
	var last_y := mini(height - 1, bottom + _tile_margin) / tile_cells
	for tile_y in range(first_y, last_y + 1):
		var base := tile_y * _tiles_across
		for tile_x in range(first_x, last_x + 1):
			_tile_dirty[base + tile_x] |= channels


func _touch_all_tiles() -> void:
	_tile_dirty.fill(UPLOAD_BOTH)


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
	return cells[cell.y * width + wrapped_x(cell.x)] >> KIND_BITS > 0


## Four subcell positions preserve where the incoming point touched the cell.
## The same phase is included in the replicated brush without extra packet words.
func position_brush(local: Vector2, brush: int) -> int:
	if cell_size > 0.05:
		return brush
	var at := (local + extent * 0.5) / cell_size
	var quadrant := int(at.x - floorf(at.x) >= 0.5) + 2 * int(at.y - floorf(at.y) >= 0.5)
	return (brush & BRUSH_KIND_MASK) | ((quadrant + 1) << BRUSH_PHASE_SHIFT)


## Marks the surface around a local position, and returns the
## centre cell it painted around, or (-1, -1) if the position was off the grid.
## The radius is given in metres and converted here, so changing cell_size does
## not change how big a splat is.
func paint(local: Vector2, radius_meters: float, deposit := 1, coat := -1,
		kind := KIND_MAYO, brush := BRUSH_POOL) -> Vector2i:
	return paint_cell(cell_of(local), radius_meters, deposit, coat, kind, brush)


## The splat itself, addressed by cell rather than by position. Everything below
## depends on the centre, brush and radius. The host and peer replay the same
## packed stamp and maintain byte-identical masks without sending a cell list.
## `coat` identifies the trigger pull this splat belongs to. A cell rises at most
## once for a given coat, so a burst lays down one layer rather than one per
## splat. -1 means no coat: every splat counts, which is what the surfaces
## nobody walks on still do.
## `kind` is which sauce is landing. A cell holds one: painting a sauce onto a
## cell that holds a different one takes it over at one layer rather than adding
## to the pile that is there.
func paint_cell(centre: Vector2i, radius_meters: float, deposit := 1,
		coat := -1, kind := KIND_MAYO, brush := BRUSH_POOL) -> Vector2i:
	paint_calls += 1
	if not has_cell(centre):
		return Vector2i(-1, -1)
	var coated := {}
	var new_coat := coat >= 0 and not _coats.has(coat)
	if coat >= 0 and not new_coat:
		coated = _coats[coat]
	centre.x = wrapped_x(centre.x)
	if cell_size <= 0.05:
		if not _paint_detail(centre, radius_meters, deposit, kind, brush, coat >= 0, coated):
			return Vector2i(-1, -1)
		# No-change stamps send no packet, so they must not evict a live coat.
		if new_coat:
			_remember_coat(coat, coated)
		return centre
	if new_coat:
		_remember_coat(coat, coated)
	if scatter_ketchup and kind == KIND_KETCHUP:
		var radius_in_cells := maxf(1.0, radius_meters * 1.20 / cell_size)
		_paint_ketchup_scatter(centre, radius_in_cells, deposit, coat >= 0, coated)
		return centre

	var radius := maxf(1.0, radius_meters / cell_size)
	var scale := maxf(metres_per_cell, 0.0001)
	# The wobble and its features, converted from metres into this grid's cells.
	var wobble := EDGE_WOBBLE_METRES / scale
	var feature := maxi(1, roundi(EDGE_FEATURE_METRES / scale))
	# Enough margin for the edge to wander outwards without being clipped.
	var margin := maxi(1, ceili(wobble))
	var high := ceili(radius) + margin
	var low := -high
	var safe_radius := maxf(radius - wobble, 0.0)
	var inner_squared := safe_radius * safe_radius
	var outer_radius := radius + wobble
	var outer_squared := outer_radius * outer_radius

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

	# has_cell, wrapped_x and a Vector2 length are all inlined below: this loop
	# runs once per cell in the brush's bounding box, which on a big brush is
	# tens of thousands of times per splat, and a GDScript call is dear.
	for offset_y in range(low, high + 1):
		var row := centre.y + offset_y
		if row < 0 or row >= height:
			continue
		var row_base := row * width
		var place_y := float(row) / float(feature)
		var base_y := floori(place_y)
		var down := smoothstep(0.0, 1.0, place_y - float(base_y))
		var lattice_row := (base_y - lattice_y0) * lattice_w
		var distance_y := offset_y * offset_y
		for offset_x in range(low, high + 1):
			var distance_squared := float(offset_x * offset_x + distance_y)
			if distance_squared > outer_squared:
				continue
			var column := centre.x + offset_x
			if wrap_x:
				# The noise is read at the wrapped column, so a cell gets the
				# same jitter whichever side of the seam the splat came from.
				column = posmod(column, width)
			elif column < 0 or column >= width:
				continue
			var index := row_base + column
			# Saturated cells are done: nothing more can land on them, and
			# skipping them keeps the noise work off the hottest cells. Only
			# saturated against the *same* sauce, though -- a full pile of mayo
			# is still a cell mustard can take over.
			var here := int(cells[index])
			if here >> KIND_BITS >= MAX_THICKNESS and (here & KIND_MASK) == kind:
				continue
			var cell := Vector2i(column, row)
			if distance_squared <= inner_squared:
				_deposit_cell(cell, index, here, deposit, kind, coat >= 0, coated)
				continue
			# Value noise off the lattice above, inlined: the four points around
			# this cell, eased and blended, so the edge wanders continuously
			# rather than stepping from one lattice square to the next.
			var place_x := float(cell.x) / float(feature)
			var base_x := floori(place_x)
			var across := smoothstep(0.0, 1.0, place_x - float(base_x))
			var corner := lattice_row + base_x - lattice_x0
			var top: float = lerpf(lattice[corner], lattice[corner + 1], across)
			var bottom: float = lerpf(lattice[corner + lattice_w],
				lattice[corner + lattice_w + 1], across)
			# Deterministic cell noise roughens only the hard boundary. No blur/alpha.
			var edge_jitter: float = lerpf(top, bottom, down) * wobble
			var reach := radius + edge_jitter
			# Squared on both sides, to keep the square root out of the loop.
			if reach > 0.0 and distance_squared <= reach * reach:
				_deposit_cell(cell, index, here, deposit, kind, coat >= 0, coated)
	return centre


func _remember_coat(coat: int, covered: Dictionary) -> void:
	if _coats.size() >= MAX_LIVE_COATS:
		var oldest: int = _coats.keys().min()
		_coats.erase(oldest)
	_coats[coat] = covered


## Stamp rows are relative to the impact cell, so the cache is shared by the
## authority and its peers without carrying a mask or a random seed in packets.
func _paint_detail(centre: Vector2i, radius_meters: float, deposit: int, kind: int,
		brush: int, track_coat: bool, coated: Dictionary) -> bool:
	var seed := (centre.x * 31) ^ (centre.y * 73)
	var variant := seed & 3
	var style := brush & BRUSH_KIND_MASK
	var phase := mini(brush >> BRUSH_PHASE_SHIFT, 4)
	var sector := (style - BRUSH_STROKE) if style >= BRUSH_STROKE else posmod(seed, STROKE_DIRECTIONS)
	var stamp := (phase * STROKE_DIRECTIONS + sector) * 32 + style
	var key := Vector4i(roundi(cell_size * 100000.0), roundi(radius_meters * 10000.0), kind, stamp * 4 + variant)
	var rows: PackedInt32Array
	if _detail_brushes.has(key):
		rows = _detail_brushes[key]
	else:
		if _detail_brushes.size() >= DETAIL_BRUSH_LIMIT:
			var oldest := Vector4i.ZERO
			for cached_key in _detail_brushes:
				oldest = cached_key
				break
			_detail_brushes.erase(oldest)
		rows = _build_detail_brush(key, style, variant)
		_detail_brushes[key] = rows
	var changed := false
	var deduplicate := track_coat or (wrap_x and radius_meters * 4.0 >= extent.x)
	var start := 0
	while start < rows.size():
		var row := centre.y + rows[start]
		var left := centre.x + rows[start + 1]
		var length := rows[start + 2]
		var data := start + 3
		start = data + length
		if row < 0 or row >= height:
			continue
		var base := row * width
		var first := width
		var last := -1
		var channels := 0
		# Clip the scanline once. The kept samples still read the same stamp
		# indices, including when a brush crosses the edge of the floor.
		var first_offset := 0 if wrap_x else maxi(0, -left)
		var end_offset := length if wrap_x else mini(length, width - left)
		for offset in range(first_offset, end_offset):
			var ink := rows[data + offset]
			if ink == 0:
				continue
			var column := left + offset
			if wrap_x:
				column = posmod(column, width)
			var index := base + column
			var pixel_channels := 0
			if ink > contour_cells[index]:
				contour_cells[index] = ink
				pixel_channels = UPLOAD_CONTOUR
			if ink >= 128 and (not deduplicate or not coated.has(index)):
				var here := int(cells[index])
				if (here & KIND_MASK) != kind or here >> KIND_BITS < MAX_THICKNESS:
					if deduplicate:
						coated[index] = true
					_write_deposit(index, here, deposit, kind)
					pixel_channels |= UPLOAD_THICKNESS
			if pixel_channels != 0:
				first = mini(first, column)
				last = maxi(last, column)
				channels |= pixel_channels
		if last >= 0:
			_touch_tile_span(first, row, last, row, channels)
			changed = true
	dirty = dirty or changed
	return changed


static func _build_detail_brush(key: Vector4i, brush: int, variant: int) -> PackedInt32Array:
	var cell := float(key.x) / 100000.0
	var radius := float(key.y) / 10000.0 / cell
	var pixels: Dictionary[Vector2i, int] = {}
	var oriented := key.w / (4 * 32)
	var sector := oriented % STROKE_DIRECTIONS
	var phase := oriented / STROKE_DIRECTIONS
	var origin := Vector2.ZERO
	if phase > 0:
		var quadrant := phase - 1
		origin = Vector2(float(quadrant & 1), float(quadrant >> 1)) * 0.5 - Vector2.ONE * 0.25
	var axis := Vector2.from_angle(float(sector) * TAU / STROKE_DIRECTIONS)
	var side := axis.orthogonal()
	var skew := -1.0 if (variant & 1) == 0 else 1.0
	if brush == BRUSH_FLECK or brush == BRUSH_BEAD:
		var metres := 0.038 if brush == BRUSH_FLECK else 0.072
		var dot_size := maxf(0.95, minf(radius * 0.56, metres / cell) * (0.91 + 0.08 * variant))
		_add_detail_ellipse(pixels, origin, axis, Vector2(dot_size, dot_size * 0.86))
	else:
		var dragged := brush >= BRUSH_STROKE
		match key.z:
			KIND_KETCHUP:
				_add_detail_ellipse(pixels, origin - axis * 0.10 * radius, axis, Vector2(1.03, 0.87) * radius)
				_add_detail_ellipse(pixels, origin + (axis * (0.69 if dragged else 0.48) + side * skew * 0.19) * radius,
					axis.rotated(skew * 0.24), Vector2(0.74, 0.43) * radius)
			KIND_MUSTARD:
				var wide := 0.69 if dragged else 0.89
				_add_detail_ellipse(pixels, origin, axis, Vector2(1.06, wide) * radius)
				_add_detail_ellipse(pixels, origin + (axis * 0.73 + side * skew * 0.14) * radius,
					axis, Vector2(0.60, 0.29) * radius)
			_:
				_add_detail_ellipse(pixels, origin, axis, Vector2(0.99, 0.93) * radius)
				_add_detail_ellipse(pixels, origin + (axis * 0.61 + side * skew * 0.35) * radius,
					axis, Vector2(0.57, 0.39) * radius)
		# Smaller detached dots keep the direction of the main splash and vary
		# around its sides. They share the physical coat and wash with the pool.
		var scatter := 0.15 if key.z == KIND_MAYO else 0.20
		for dot in 2 + (variant & 1):
			var spread_axis := axis.rotated(skew * (0.68 + 1.15 * float(dot)))
			var reach := 1.37 + 0.13 * float((variant + dot) % 3)
			var at := origin + spread_axis * radius * reach
			var size := maxf(0.98, radius * scatter * (1.0 - 0.20 * float(dot)))
			_add_detail_ellipse(pixels, at, spread_axis, Vector2(size, size * 0.86))
	var spans: Dictionary[int, Vector2i] = {}
	for pixel in pixels:
		var span: Vector2i = spans.get(pixel.y, Vector2i(pixel.x, pixel.x))
		spans[pixel.y] = Vector2i(mini(span.x, pixel.x), maxi(span.y, pixel.x))
	var row_indices := spans.keys()
	row_indices.sort()
	var rows := PackedInt32Array()
	for row in row_indices:
		var span: Vector2i = spans[row]
		rows.append(row)
		rows.append(span.x)
		rows.append(span.y - span.x + 1)
		for column in range(span.x, span.y + 1):
			rows.append(pixels.get(Vector2i(column, row), 0))
	return rows


static func _add_detail_ellipse(pixels: Dictionary[Vector2i, int], centre: Vector2,
		axis: Vector2, radii: Vector2) -> void:
	var side := axis.orthogonal()
	var span := (axis * radii.x).abs() + (side * radii.y).abs() + Vector2.ONE * 2.0
	var first := Vector2i((centre - span).ceil())
	var last := Vector2i((centre + span).floor())
	var along := axis / maxf(radii.x, 0.45)
	var across := side / maxf(radii.y, 0.45)
	var minor := maxf(0.45, minf(radii.x, radii.y))
	for row in range(first.y, last.y + 1):
		for column in range(first.x, last.x + 1):
			var pixel := Vector2i(column, row)
			var offset := Vector2(pixel) - centre
			var distance := (1.0 - Vector2(offset.dot(along), offset.dot(across)).length()) * minor
			var field := clampi(roundi(127.5 + 63.75 * distance), 0, 255)
			if field > int(pixels.get(pixel, 0)):
				pixels[pixel] = field


## A round, asymmetric blot with a short smear and scattered droplets.
## Seed the silhouette from the impact cell so the host and every peer can
## reconstruct it from the same splat packet.
func _paint_ketchup_scatter(centre: Vector2i, radius: float, deposit: int,
		track_coat: bool, coated: Dictionary) -> void:
	var covered: Dictionary[Vector2i, bool] = {}
	var origin := Vector2(centre)
	var rotation := PI * _cell_noise(centre.x, centre.y)
	var flow := Vector2.from_angle(rotation)
	var bend := 0.48 * _cell_noise(centre.x + 13, centre.y - 5)
	_stamp_ellipse(covered, origin - flow * radius * 0.14, flow, Vector2(1.10, 0.91) * radius)
	var smear := flow.rotated(bend)
	_stamp_ellipse(covered, origin + smear * radius * 0.84, smear, Vector2(0.86, 0.55) * radius)
	for index in KETCHUP_DROP_ANGLES.size():
		var skew := _cell_noise(centre.x + 17 * index, centre.y - 31)
		var spread := _cell_noise(centre.x - 23, centre.y + 19 * index)
		var axis := Vector2.from_angle(rotation + KETCHUP_DROP_ANGLES[index] + skew * 0.32)
		var reach := maxf(3.0, radius * (2.70 + 0.49 * spread))
		var drop := (origin + axis * reach).round()
		var size := Vector2(0.37 + 0.18 * skew, 0.21 + 0.08 * skew) * radius
		_stamp_ellipse(covered, drop, axis, size)

	for cell: Vector2i in covered:
		var index := cell.y * width + cell.x
		var here := int(cells[index])
		if here >> KIND_BITS < MAX_THICKNESS or (here & KIND_MASK) != KIND_KETCHUP:
			_deposit_cell(cell, index, here, deposit, KIND_KETCHUP, track_coat, coated)


func _stamp_ellipse(covered: Dictionary[Vector2i, bool], centre: Vector2,
		axis: Vector2, radii: Vector2) -> void:
	var side := axis.orthogonal()
	var span := (axis * radii.x).abs() + (side * radii.y).abs()
	var first := Vector2i((centre - span).ceil())
	var last := Vector2i((centre + span).floor())
	for row in range(maxi(first.y, 0), mini(last.y + 1, height)):
		for column in range(first.x, last.x + 1):
			if not wrap_x and (column < 0 or column >= width):
				continue
			var offset := Vector2(column, row) - centre
			var local := Vector2(offset.dot(axis), offset.dot(side)) / radii
			if local.length_squared() <= 1.0:
				covered[Vector2i(wrapped_x(column), row)] = true


func _deposit_cell(cell: Vector2i, index: int, packed: int, deposit: int, kind: int,
		track_coat: bool, coated: Dictionary) -> void:
	# Each pass adds one layer per cell. Switching sauces starts a fresh layer.
	if track_coat:
		if coated.has(index):
			return
		coated[index] = true
	_write_deposit(index, packed, deposit, kind)
	_touch_tile(cell.x, cell.y)
	dirty = true


func _write_deposit(index: int, packed: int, deposit: int, kind: int) -> void:
	var was := packed >> KIND_BITS
	var stacked := was if (packed & KIND_MASK) == kind else 0
	var now := mini(stacked + deposit, MAX_THICKNESS)
	cells[index] = (now << KIND_BITS) | kind
	if was == 0:
		painted_count += 1
	if was < deep_threshold and now >= deep_threshold:
		deep_count += 1
	elif was >= deep_threshold and now < deep_threshold:
		deep_count -= 1


## Wipes the grid. Both halves of the mask go together -- clearing one and not
## the other is how a wiped surface keeps showing its old stain.
## Sets every cell from `first` to `last` inclusive to `thickness` of `kind`,
## clipped to the grid. Returns whether any cell changed.
func fill_rect(first: Vector2i, last: Vector2i, thickness: int, kind: int) -> bool:
	var level := clampi(thickness, 0, MAX_THICKNESS)
	var packed := (level << KIND_BITS) | (kind & KIND_MASK) if level > 0 else 0
	var top := maxi(first.y, 0)
	var bottom := mini(last.y, height - 1)
	var left := maxi(first.x, 0)
	var right := mini(last.x, width - 1)
	if top > bottom or left > right:
		return false
	var changed := false
	for row in range(top, bottom + 1):
		var row_base := row * width
		for column in range(left, right + 1):
			var index := row_base + column
			var previous := int(cells[index])
			if not contour_cells.is_empty():
				var field := 255 if level > 0 else 0
				if contour_cells[index] != field:
					contour_cells[index] = field
					changed = true
			if previous == packed:
				continue
			var was := previous >> KIND_BITS
			cells[index] = packed
			changed = true
			if was == 0 and level > 0:
				painted_count += 1
			elif was > 0 and level == 0:
				painted_count -= 1
			if was < deep_threshold and level >= deep_threshold:
				deep_count += 1
			elif was >= deep_threshold and level < deep_threshold:
				deep_count -= 1
	if not changed:
		return false
	_touch_tile_span(left, top, right, bottom)
	dirty = true
	return true


## Clear the cells under a round brush. Radius stays in metres on every surface.
## A splat packet only needs the centre cell and both peers replay the same rows.
func erase_disc(centre: Vector2i, radius_meters: float) -> bool:
	if painted_count == 0 or not has_cell(centre):
		return false
	if not contour_cells.is_empty():
		return _erase_fine_disc(centre, radius_meters)
	var spans: PackedInt32Array = _wash_spans.get(radius_meters, PackedInt32Array())
	if spans.is_empty():
		var radius := maxf(0.0, radius_meters / cell_size)
		var radius_squared := radius * radius
		spans.resize(floori(radius) + 1)
		for row in spans.size():
			spans[row] = floori(sqrt(maxf(0.0, radius_squared - float(row * row))))
		if _wash_spans.size() >= 8:
			_wash_spans.clear()
		_wash_spans[radius_meters] = spans
	var extent_y := spans.size() - 1
	var first_row := maxi(0, centre.y - extent_y)
	var last_row := mini(height - 1, centre.y + extent_y)
	var changed := false
	for row in range(first_row, last_row + 1):
		var reach := spans[absi(row - centre.y)]
		var left := centre.x - reach
		var right := centre.x + reach
		if wrap_x:
			# A span can cross the body's seam, or cover a narrow chart entirely.
			var start := posmod(left, width)
			var length := mini(2 * reach + 1, width)
			var end := start + length - 1
			changed = _erase_row(row, start, mini(end, width - 1)) or changed
			if end >= width:
				changed = _erase_row(row, 0, end - width) or changed
		else:
			changed = _erase_row(row, maxi(0, left), mini(width - 1, right)) or changed
	return changed


# Cache the values along the curved edge. The centre uses zero and the
# boundary uses signed distance, so washing away a patch leaves a smooth cut.
func _erase_fine_disc(centre: Vector2i, radius_meters: float) -> bool:
	var rows: PackedInt32Array = _wash_spans.get(radius_meters, PackedInt32Array())
	if rows.is_empty():
		var radius := maxf(0.0, radius_meters / cell_size)
		var edge := radius + 2.0
		for y in floori(edge) + 1:
			var reach := floori(sqrt(maxf(0.0, edge * edge - float(y * y))))
			rows.append(reach)
			for x in reach + 1:
				var distance := Vector2(x, y).length() - radius
				rows.append(clampi(ceili(127.5 + 63.75 * distance), 0, 255))
		if _wash_spans.size() >= 8:
			_wash_spans.clear()
		_wash_spans[radius_meters] = rows
	var removed := 0
	var deep_removed := 0
	var changed := false
	var start := 0
	var y := 0
	while start < rows.size():
		var reach := rows[start]
		start += 1
		for row in range(centre.y - y, centre.y + y + 1, maxi(2 * y, 1)):
			if row < 0 or row >= height:
				continue
			var left := maxi(-reach, -(width / 2) if wrap_x else -centre.x)
			var right := mini(reach, (width - 1) / 2 if wrap_x else width - 1 - centre.x)
			var first := width
			var last := -1
			for offset in range(left, right + 1):
				var column := centre.x + offset
				if wrap_x:
					column = posmod(column, width)
				var index := row * width + column
				var edge := rows[start + absi(offset)]
				var thickness := cells[index] >> KIND_BITS
				var erase_cell := edge <= 128 and thickness > 0
				if contour_cells[index] <= edge and not erase_cell:
					continue
				contour_cells[index] = mini(contour_cells[index], edge)
				if erase_cell:
					cells[index] = 0
					removed += 1
					deep_removed += int(thickness >= deep_threshold)
				first = mini(first, column)
				last = maxi(last, column)
			if last >= 0:
				_touch_tile_span(first, row, last, row)
				changed = true
		y += 1
		start += reach + 1
	painted_count -= removed
	deep_count -= deep_removed
	dirty = dirty or changed
	return changed


func _erase_row(row: int, left: int, right: int) -> bool:
	var base := row * width
	var first := -1
	var last := -1
	var removed := 0
	var deep_removed := 0
	for index in range(base + left, base + right + 1):
		var thickness := cells[index] >> KIND_BITS
		if thickness == 0:
			continue
		cells[index] = 0
		if first < 0:
			first = index
		last = index
		removed += int(thickness > 0)
		deep_removed += int(thickness >= deep_threshold)
	if first < 0:
		return false
	painted_count -= removed
	deep_count -= deep_removed
	_touch_tile_span(first - base, row, last - base, row)
	dirty = true
	return true


func clear() -> void:
	cells.fill(0)
	contour_cells.fill(0)
	_coats.clear()
	painted_count = 0
	deep_count = 0
	_touch_all_tiles()
	dirty = true


## Byte-exact fingerprint of the whole cell mask, for comparing two machines'
## grids against each other.
func cells_md5() -> String:
	return Marshalls.raw_to_base64(cells).md5_text()


func snapshot() -> PackedByteArray:
	var result := cells.duplicate()
	result.append_array(contour_cells)
	return result


## A full snapshot includes the contour; an older mask can derive it from occupancy.
func restore_cells(new_cells: PackedByteArray) -> bool:
	var size := cells.size()
	if new_cells.size() == size + contour_cells.size() and not contour_cells.is_empty():
		cells = new_cells.slice(0, size)
		contour_cells = new_cells.slice(size)
	elif new_cells.size() == size:
		cells = new_cells
		if not contour_cells.is_empty():
			for index in size:
				contour_cells[index] = 255 if cells[index] >= 4 else 0
	else:
		return false
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
func upload_if_dirty(tile_budget := 0, focus := Vector2.INF) -> void:
	# Reset *after* the early out, not before it: this is "what the last real
	# upload cost", and zeroing it on every idle call meant anything reading it
	# a frame later almost always saw 0. `bytes_uploaded_total` is what to take
	# differences of.
	if not dirty:
		return
	var started := Time.get_ticks_usec() if measure_uploads else 0
	bytes_uploaded = 0
	var tile_total := _tile_textures.size()
	var preferred := -1
	if tile_budget > 0 and focus.is_finite():
		var best := INF
		for index in tile_total:
			if _tile_dirty[index] == 0:
				continue
			var sample := _tile_samples[index]
			var center := Vector2(sample.get_center()) * cell_size - extent * 0.5
			var distance := center.distance_squared_to(focus)
			if distance < best:
				best = distance
				preferred = index
	var uploaded := 0
	var first := _next_upload_tile
	for offset in range(-1, tile_total):
		var index := preferred if offset < 0 else (first + offset) % tile_total
		if index < 0:
			continue
		var channels := _tile_dirty[index]
		if channels == 0:
			continue
		_tile_dirty[index] = 0
		var sample := _tile_samples[index]
		var size := sample.size
		var painted := _tile_paint_channels[index] if track_tile_paint else 0
		var was_painted := painted != 0
		if channels & UPLOAD_CONTOUR and not contour_cells.is_empty():
			var field := _tile_bytes(contour_cells, sample)
			_contour_textures[index].update(Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, field))
			if track_tile_paint:
				painted &= ~UPLOAD_CONTOUR
				if field.count(0) < field.size():
					painted |= UPLOAD_CONTOUR
			bytes_uploaded += field.size()
		if channels & UPLOAD_THICKNESS:
			var data := _tile_bytes(cells, sample)
			var tile_image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, data)
			_tile_textures[index].update(tile_image)
			if tile_total == 1:
				image = tile_image
			if track_tile_paint:
				painted &= ~UPLOAD_THICKNESS
				if data.count(0) < data.size():
					painted |= UPLOAD_THICKNESS
			bytes_uploaded += data.size()
		if track_tile_paint:
			_tile_paint_channels[index] = painted
			if was_painted != (painted != 0):
				tile_paint_changed.emit(index, painted != 0)
		texture_uploads += 1
		uploaded += 1
		if offset >= 0:
			_next_upload_tile = (index + 1) % tile_total
		if tile_budget > 0 and uploaded >= tile_budget:
			break
	bytes_uploaded_total += bytes_uploaded
	dirty = _tile_dirty.count(0) < tile_total
	if measure_uploads:
		upload_time_us += Time.get_ticks_usec() - started


func _tile_bytes(source: PackedByteArray, sample: Rect2i) -> PackedByteArray:
	if _tile_textures.size() == 1:
		return source
	var origin := sample.position
	var size := sample.size
	if size.x == width:
		return source.slice(origin.y * width, (origin.y + size.y) * width)
	var data := PackedByteArray()
	for row in size.y:
		var start := (origin.y + row) * width + origin.x
		data.append_array(source.slice(start, start + size.x))
	return data


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
		var thickness := cell >> KIND_BITS
		if thickness > 0:
			painted_count += 1
			if thickness >= deep_threshold:
				deep_count += 1


## How many cells are at or over a thickness. For the debug readout: how much of
## this floor is thick enough to put someone down.
func cells_at_least(thickness: int) -> int:
	var total := 0
	for cell in cells:
		if cell >> KIND_BITS >= thickness:
			total += 1
	return total


## Thickness under a local position, 0 to `MAX_THICKNESS`, or 0 off the grid.
func thickness_at(local: Vector2) -> int:
	var cell := cell_of(local)
	if not has_cell(cell):
		return 0
	return cells[cell.y * width + wrapped_x(cell.x)] >> KIND_BITS


## Thickness and sauce of a cell by its index into `cells`. For the checks and
## the debug readouts, which walk the array rather than asking by position, and
## which have no business knowing how the byte is laid out.
func thickness_of(index: int) -> int:
	return cells[index] >> KIND_BITS


func kind_of(index: int) -> int:
	return cells[index] & KIND_MASK


## Which sauce is under a local position. A cell with nothing on it reads as
## `KIND_MAYO`, so ask `thickness_at` first: "which sauce" is only a question
## about a cell that has one.
func kind_at(local: Vector2) -> int:
	var cell := cell_of(local)
	if not has_cell(cell):
		return KIND_MAYO
	return cells[cell.y * width + wrapped_x(cell.x)] & KIND_MASK


## Thickness and sauce together, for the callers that want both and would
## otherwise walk the same cell twice.
func sauce_at(local: Vector2) -> Vector2i:
	var cell := cell_of(local)
	if not has_cell(cell):
		return Vector2i(0, KIND_MAYO)
	var packed := int(cells[cell.y * width + wrapped_x(cell.x)])
	return Vector2i(packed >> KIND_BITS, packed & KIND_MASK)


## The value the shader samples, evaluated on the CPU. Used by the checks to
## confirm the rendered boundary and the slip test agree.
##
## **In bytes, not in layers.** This exists to stand in for the sampler, and the
## sampler reads the packed byte -- so a caller comparing against it scales its
## own cut-off up past the sauce bits, exactly as the shader's uniforms are
## scaled. Returning layers here would make this agree with the slip test and
## disagree with the thing it is named after.
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
