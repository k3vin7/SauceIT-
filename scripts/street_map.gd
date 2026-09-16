class_name StreetMap
extends RefCounted

## The tutorial street, traced off the hand sketch.
##
## The whole map lives on one lattice whose cell is exactly one person wide, so
## "the road is eight people wide" is the literal statement `ROAD_CELLS = 8`
## rather than a metre figure that drifts when the capsule changes. Every
## segment below is given in lattice cells, which is why the corridors are all
## the same width by construction: each one is 8 cells across, and a junction is
## just two of them overlapping.
##
## Sketch pixels map onto the lattice at `PX_PER_CELL`, which is how the stall
## and vending-machine anchors stay traceable back to the drawing they came
## from -- they are the pixel coordinates of the cyan and red marks.

## How much bigger the street is than the lattice it was laid out on. The
## layout stays in whole cells whatever this is -- the scale is applied once,
## here, when a cell is turned into metres -- so the corridors stay exactly as
## wide as each other and the junctions stay square.
##
## The stalls and the vending machines are deliberately NOT scaled by it: they
## are furniture at a fixed real size, and leaving them alone is what makes the
## street read as bigger rather than as the same street viewed closer.
const SCALE := 1.5

## One person wide, times the scale. The capsule is 0.64 m in radius, so the
## unscaled cell is its diameter and everything on the map is a whole number of
## people across.
const PERSON := 1.28
const CELL := PERSON * SCALE
const ROAD_CELLS := 8
const ROAD_WIDTH := CELL * ROAD_CELLS

## Tall enough that the arena's far side is not visible over a corridor wall
## from anywhere a player can stand. Scaled with the rest: a wall that stayed
## put while the street grew would start showing what is behind it.
const WALL_HEIGHT := 7.0 * SCALE
## Walls are two cells deep so they read as building fronts rather than as
## cardboard: at one cell a corner shows its own thickness across the street.
const WALL_DEPTH_CELLS := 2

## The sketch's road came out 90 px across, which is this lattice's 8 cells.
const PX_PER_CELL := 11.25
## Lattice cell the start zone is centred on. Placing the origin here keeps the
## spawns, and every probe that hard-codes a position near them, on open street.
const ORIGIN_CELL := Vector2i(20, 94)

## Ground beyond the outermost wall, so the floor plane does not end in mid-air
## where a player can see the seam.
const FLOOR_MARGIN_CELLS := 4

## The route, south (start) to north (arena), as lattice rectangles. Consecutive
## segments overlap rather than abut: the overlap *is* the corner, so no junction
## needs a special case and the walls fall out of the union.
const SEGMENTS: Array[Rect2i] = [
	Rect2i(15, 92, 10, 8),   # start plaza, wider than the road it feeds
	Rect2i(16, 54, 8, 42),   # the long run north
	Rect2i(16, 54, 24, 8),   # east along the bottom
	Rect2i(32, 38, 8, 20),   # north again
	Rect2i(32, 34, 15, 8),   # east across the middle
	Rect2i(39, 29, 8, 13),   # the first step of the zigzag
	Rect2i(39, 25, 12, 8),   # the second
	Rect2i(43, 22, 8, 8),    # the neck into the arena
	Rect2i(35, 3, 25, 19),   # the arena
]

## Stalls, as their sketch pixel position and the wall they back onto. The
## direction is the way the stall faces *into* -- (-1, 0) backs onto a west wall.
const STALL_ANCHORS := [
	[410, 50, 0, -1], [663, 50, 0, -1],          # the arena's north corners
	[410, 228, 0, 1], [663, 228, 0, 1],          # its south corners
	[437, 400, 0, -1], [515, 460, 0, 1],         # across the middle
	[378, 508, -1, 0], [432, 560, 1, 0],         # the second run north
	[258, 630, 0, -1], [325, 680, 0, 1], [446, 692, 0, 1],
	[184, 710, -1, 0], [264, 795, 1, 0],
	[184, 808, -1, 0], [263, 885, 1, 0],
	[181, 940, -1, 0], [181, 1030, -1, 0], [265, 1030, 1, 0],
]

## Fixed metres, not cells: a food stall is the size a food stall is, and it
## does not grow when the street does. Roughly three people of frontage and two
## of depth at the unscaled size the sketch was traced at.
const STALL_SIZE := Vector3(PERSON * 3.0, 2.8, PERSON * 2.0)

const VENDING_ANCHORS := [
	[373, 440, -1, 0],
	[265, 705, 1, 0],
]

const VENDING_SIZE := Vector3(1.15, 2.05, 0.82)


static func road_width() -> float:
	return ROAD_WIDTH


## Corner of a lattice cell in world space. x runs east, y runs south, which is
## +z: the sketch is read the way it is drawn, with the start at the bottom.
static func cell_corner(cell: Vector2i) -> Vector3:
	return Vector3(
		float(cell.x - ORIGIN_CELL.x) * CELL,
		0.0,
		float(cell.y - ORIGIN_CELL.y) * CELL)


static func from_pixels(px: float, py: float) -> Vector3:
	return Vector3(
		(px / PX_PER_CELL - float(ORIGIN_CELL.x)) * CELL,
		0.0,
		(py / PX_PER_CELL - float(ORIGIN_CELL.y)) * CELL)


static func cell_of_pixels(px: float, py: float) -> Vector2i:
	return Vector2i(int(floor(px / PX_PER_CELL)), int(floor(py / PX_PER_CELL)))


## Every cell a player can stand on, as a set.
static func floor_cells() -> Dictionary:
	var cells := {}
	for rect in SEGMENTS:
		for j in range(rect.position.y, rect.end.y):
			for i in range(rect.position.x, rect.end.x):
				cells[Vector2i(i, j)] = true
	return cells


static func bounds() -> Rect2i:
	var rect := SEGMENTS[0]
	for i in range(1, SEGMENTS.size()):
		rect = rect.merge(SEGMENTS[i])
	return rect


## Centre and size of the ground plane: the whole map plus enough margin to
## carry the walls and a little ground behind them.
static func floor_plane() -> Dictionary:
	var rect := bounds().grow(FLOOR_MARGIN_CELLS)
	var corner := cell_corner(rect.position)
	var size := Vector3(float(rect.size.x) * CELL, 0.0, float(rect.size.y) * CELL)
	return {
		"centre": corner + size * 0.5,
		"size": Vector2(size.x, size.z),
	}


## The walls, as merged boxes. A wall cell is any cell within `WALL_DEPTH_CELLS`
## of the street that is not street itself; the adjacency test is Chebyshev, so
## a diagonal corner is sealed rather than left as a gap a strand could fly out
## of. Greedy merging turns the long straight runs into single boxes -- without
## it a corridor this size is several hundred separate bodies.
static func wall_boxes() -> Array[Dictionary]:
	var floor_set := floor_cells()
	var wall_set := {}
	for cell in floor_set:
		for dj in range(-WALL_DEPTH_CELLS, WALL_DEPTH_CELLS + 1):
			for di in range(-WALL_DEPTH_CELLS, WALL_DEPTH_CELLS + 1):
				var near := Vector2i(cell.x + di, cell.y + dj)
				if not floor_set.has(near):
					wall_set[near] = true

	var boxes: Array[Dictionary] = []
	for rect in _merge_cells(wall_set):
		var corner := cell_corner(rect.position)
		var size := Vector3(float(rect.size.x) * CELL, WALL_HEIGHT, float(rect.size.y) * CELL)
		boxes.push_back({
			"position": corner + Vector3(size.x * 0.5, WALL_HEIGHT * 0.5, size.z * 0.5),
			"size": size,
		})
	return boxes


static func stall_boxes() -> Array[Dictionary]:
	return _anchored_boxes(STALL_ANCHORS, STALL_SIZE)


static func vending_boxes() -> Array[Dictionary]:
	return _anchored_boxes(VENDING_ANCHORS, VENDING_SIZE)


## Places one box per anchor with its back flat against the wall the anchor
## names. The sketch's marks sit roughly on the wall lines rather than exactly
## on them, so the anchor picks the wall and the street decides the depth: walk
## from the anchor until the street runs out, and that edge is the back face.
## Doing it this way means a stall cannot end up floating in the road or buried
## in a wall if the traced pixel is off by a cell.
static func _anchored_boxes(anchors: Array, size: Vector3) -> Array[Dictionary]:
	var floor_set := floor_cells()
	var boxes: Array[Dictionary] = []
	for anchor in anchors:
		var px: float = anchor[0]
		var py: float = anchor[1]
		var dir := Vector2i(anchor[2], anchor[3])
		var cell := cell_of_pixels(px, py)
		# The mark is usually drawn on the wall line, which is one cell outside
		# the street. Back off along -dir until it is on the street again.
		var steps := 0
		while not floor_set.has(cell) and steps < WALL_DEPTH_CELLS + 2:
			cell -= dir
			steps += 1
		if not floor_set.has(cell):
			continue
		while floor_set.has(cell + dir):
			cell += dir

		# Far edge of the last street cell, along dir: the wall face.
		var corner := cell_corner(cell)
		var wall_face := corner + Vector3(
			CELL if dir.x > 0 else 0.0,
			0.0,
			CELL if dir.y > 0 else 0.0)
		var facing := Vector3(float(dir.x), 0.0, float(dir.y))
		# Along the wall the anchor is taken at face value -- that is the one
		# axis the sketch actually pins down.
		var along := from_pixels(px, py)
		var footprint := Vector3(
			size.z if dir.x != 0 else size.x,
			size.y,
			size.z if dir.y != 0 else size.x)
		var centre := Vector3(
			wall_face.x if dir.x != 0 else along.x,
			size.y * 0.5,
			wall_face.z if dir.y != 0 else along.z)
		centre -= facing * (footprint.x if dir.x != 0 else footprint.z) * 0.5
		boxes.push_back({
			"position": centre,
			"size": footprint,
			"facing": -facing,
		})
	return boxes


## Greedy maximal-rectangle merge over a cell set: take the first free cell in
## reading order, run it as far right as it goes, then as far down as the whole
## run allows.
static func _merge_cells(cells: Dictionary) -> Array[Rect2i]:
	var keys := cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)

	var used := {}
	var rects: Array[Rect2i] = []
	for key in keys:
		if used.has(key):
			continue
		var width := 1
		while true:
			var next := Vector2i(key.x + width, key.y)
			if not cells.has(next) or used.has(next):
				break
			width += 1
		var height := 1
		while true:
			var row_free := true
			for dx in width:
				var probe := Vector2i(key.x + dx, key.y + height)
				if not cells.has(probe) or used.has(probe):
					row_free = false
					break
			if not row_free:
				break
			height += 1
		for dy in height:
			for dx in width:
				used[Vector2i(key.x + dx, key.y + dy)] = true
		rects.push_back(Rect2i(key.x, key.y, width, height))
	return rects
