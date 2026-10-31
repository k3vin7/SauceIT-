class_name TomatinaMap
extends RefCounted

## Stage 2: La Tomatina in Buñol, as a greybox.
##
## The same lattice as `StreetMap` -- the same `CELL`, the same `ORIGIN_CELL`,
## the same conversions -- and only the **design** is different. `StreetMap`
## hands its `floor_cells`, `bounds` and `blocked_cells` over to an instance of
## this while the stage is up (see `StreetMap.layout_override`), so the wall
## merger, the router and the floor plane all keep working without a line
## changed in any of them.
##
## The route follows the real festival: in at the village edge, up Calle San
## Luis, which forks around a block (the short way is awash with juice, the
## long way is clean), back together on Calle del Cid under an overturned
## tomato truck, out into the Plaza del Pueblo, and finally the fire truck bay
## on its far side. y runs south, so the start is at the bottom and the finale
## is at the top, the way `StreetMap` reads its own drawing.

## Which stage this is, for anything that keys a seed off the map.
const SEED := 0x70A7A70

## The streets, as lattice rectangles. Consecutive ones overlap by at least a
## cell: the router moves in four directions, so an overlap is what makes a
## junction passable. Alleys are three or four cells across -- narrower than
## the festival street's eight -- which is what makes a fork and a chokepoint
## read as such at this scale.
const SEGMENTS: Array[Rect2i] = [
	Rect2i(26, 90, 8, 6),    # 0 the village edge: start plaza, sauce truck
	Rect2i(28, 70, 4, 21),   # 1 Calle San Luis, north out of the start
	Rect2i(16, 70, 13, 3),   # 2 west fork, across
	Rect2i(16, 56, 3, 15),   # 3 west fork, up
	Rect2i(16, 54, 14, 3),   # 4 west fork, back to the Cid
	Rect2i(31, 70, 12, 3),   # 5 east fork, across
	Rect2i(40, 50, 3, 21),   # 6 east fork, up (the bowling lane)
	Rect2i(30, 50, 13, 3),   # 7 east fork, back to the Cid
	Rect2i(28, 48, 4, 8),    # 8 Calle del Cid, where the forks rejoin
	Rect2i(28, 36, 4, 13),   # 9 Calle del Cid, the overturned truck
	Rect2i(20, 22, 20, 15),  # 10 Plaza del Pueblo
	Rect2i(27, 16, 6, 7),    # 11 the fire truck bay
]

const START_SEGMENT := 0
const PLAZA_SEGMENT := 10
const FIRE_BAY_SEGMENT := 11

## Where the overturned truck lies across Calle del Cid: three of the four
## cells, leaving one cell of gap on the east side with a tomato heap in it.
const TRUCK_ROW := 44.0

## Cells painted with tomato juice before anyone arrives. `[rect, step]`:
## the short fork is awash, the chokepoint is messy, and the plaza has a patch
## in the middle where the fight is going to be.
const JUICE_ZONES := [
	[Rect2i(16, 70, 13, 3), 0.5],
	[Rect2i(16, 56, 3, 15), 0.5],
	[Rect2i(16, 54, 14, 3), 0.5],
	[Rect2i(28, 42, 4, 6), 0.8],
	[Rect2i(26, 26, 8, 7), 1.0],
]

## The standing roster, as `[kind, cell]` with the kind named as
## `MayoEnemy.EnemyKind` reads it. A cell may be fractional: it is a position,
## not an index.
const ROSTER := [
	["TOMATO_GRUNT", Vector2(31.0, 88.0)],
	["TOMATO_GRUNT", Vector2(29.5, 84.5)],
	["TOMATO_GRUNT", Vector2(30.5, 80.5)],
	["TOMATO_GRUNT", Vector2(29.0, 76.5)],
	["TOMATO_GRUNT", Vector2(28.5, 73.0)],
	["TOMATO_GRUNT", Vector2(20.5, 71.5)],
	["TOMATO_GRUNT", Vector2(17.5, 66.5)],
	["TOMATO_GRUNT", Vector2(18.0, 60.5)],
	["TOMATO_GRUNT", Vector2(17.5, 58.5)],
	["CAPRESE_CRAWLER", Vector2(22.5, 55.5)],
	["BOWLING_TOMATO", Vector2(41.5, 51.5)],
	["TOMATO_GRUNT", Vector2(33.5, 71.0)],
	["TOMATO_GRUNT", Vector2(36.5, 71.5)],
	["TOMATO_GRUNT", Vector2(41.0, 68.5)],
	["TOMATO_GRUNT", Vector2(41.5, 64.5)],
	["TOMATO_GRUNT", Vector2(41.0, 58.0)],
	["TOMATO_GRUNT", Vector2(30.0, 52.5)],
	["TOMATO_GRUNT", Vector2(29.0, 49.5)],
	["TOMATO_GRUNT", Vector2(30.5, 41.0)],
	["TOMATO_GRUNT", Vector2(29.5, 37.5)],
	["TOMATO_BRUTE", Vector2(30.0, 29.5)],
	["KETCHUP_SPITTER", Vector2(24.5, 28.5)],
	["TOMATO_GRUNT", Vector2(22.5, 34.5)],
	["TOMATO_GRUNT", Vector2(33.0, 34.0)],
	["TOMATO_GRUNT", Vector2(37.5, 33.5)],
	["TOMATO_GRUNT", Vector2(28.0, 24.0)],
	["TOMATO_GRUNT", Vector2(36.5, 24.5)],
]

## Where the horde comes in from once the party is on the plaza: its edges,
## cycled through in this order so every peer agrees on body N's position.
const HORDE_EDGES := [
	Vector2(21.0, 23.0), Vector2(38.5, 23.0), Vector2(21.0, 35.5),
	Vector2(38.5, 35.5), Vector2(29.5, 23.0), Vector2(24.5, 35.5),
	Vector2(35.5, 35.5), Vector2(21.0, 29.0), Vector2(38.5, 29.0),
	Vector2(33.5, 23.0), Vector2(25.5, 23.0), Vector2(29.5, 35.5),
]


# --- the three calls StreetMap forwards ---------------------------------------

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


## Street cells something is standing on. Every box a body cannot walk through
## -- debris, the sauce trucks, the fire truck -- except the tomato heap in the
## truck's gap, which is jumped and is left out so a route through the
## chokepoint still exists.
static func blocked_cells() -> Dictionary:
	var blocked := {}
	var props: Array[Dictionary] = []
	for box in debris_boxes():
		if box.get("jumpable", false):
			continue
		props.push_back(box)
	props.append_array(refill_boxes())
	props.push_back(fire_truck_box())
	for box in props:
		var position: Vector3 = box["position"]
		var size: Vector3 = box["size"]
		var first := Vector2i(
			int(floor((position.x - size.x * 0.5) / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.x,
			int(floor((position.z - size.z * 0.5) / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.y)
		var last := Vector2i(
			int(floor((position.x + size.x * 0.5 - 0.001) / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.x,
			int(floor((position.z + size.z * 0.5 - 0.001) / StreetMap.CELL)) + StreetMap.ORIGIN_CELL.y)
		for j in range(first.y, last.y + 1):
			for i in range(first.x, last.x + 1):
				blocked[Vector2i(i, j)] = true
	return blocked


# --- positions ----------------------------------------------------------------

## A fractional cell as a point on the ground.
static func at_cell(cell: Vector2) -> Vector3:
	return Vector3(
		(cell.x - float(StreetMap.ORIGIN_CELL.x)) * StreetMap.CELL,
		0.0,
		(cell.y - float(StreetMap.ORIGIN_CELL.y)) * StreetMap.CELL)


## A box given in cells: its centre cell, its footprint in cells, its height in
## metres. Returned the way the world builds walls and props from.
static func cell_box(centre: Vector2, footprint: Vector2, height: float,
		name := "", color := Color("6d5a4e")) -> Dictionary:
	var size := Vector3(footprint.x * StreetMap.CELL, height, footprint.y * StreetMap.CELL)
	return {
		"name": name,
		"position": at_cell(centre) + Vector3(0.0, height * 0.5, 0.0),
		"size": size,
		"color": color,
	}


## A box given in metres, placed by cell. For props that are a fixed real size
## -- the trucks -- rather than a share of the road.
static func metre_box(centre: Vector2, size: Vector3, name := "",
		color := Color("6d5a4e")) -> Dictionary:
	return {
		"name": name,
		"position": at_cell(centre) + Vector3(0.0, size.y * 0.5, 0.0),
		"size": size,
		"color": color,
	}


static func segment_rect_world(index: int) -> Rect2:
	var rect: Rect2i = SEGMENTS[index]
	var corner := at_cell(Vector2(rect.position))
	return Rect2(Vector2(corner.x, corner.z),
		Vector2(float(rect.size.x), float(rect.size.y)) * StreetMap.CELL)


static func plaza_rect() -> Rect2:
	return segment_rect_world(PLAZA_SEGMENT)


static func fire_truck_zone() -> Rect2:
	return segment_rect_world(FIRE_BAY_SEGMENT)


static func in_rect(rect: Rect2, at: Vector3) -> bool:
	return rect.has_point(Vector2(at.x, at.z))


# --- props --------------------------------------------------------------------

## The rubble in the alleys: what makes a fork a choice and a street a
## chokepoint. Axis-aligned boxes, which is all a greybox needs.
static func debris_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var booth := Color("7a5a3c")
	var crate := Color("8c7a4a")
	# West fork: short and awash. A fallen booth leaves half the alley.
	boxes.push_back(cell_box(Vector2(16.75, 62.5), Vector2(1.5, 1.0), 2.4, "FallenBoothA", booth))
	boxes.push_back(cell_box(Vector2(22.5, 70.75), Vector2(1.0, 1.5), 2.4, "FallenBoothB", booth))
	# East fork: long and clean. Crates stagger the lane without closing it.
	boxes.push_back(cell_box(Vector2(42.25, 60.5), Vector2(1.5, 1.0), 2.0, "CratesA", crate))
	boxes.push_back(cell_box(Vector2(40.75, 55.5), Vector2(1.5, 1.0), 2.0, "CratesB", crate))
	# Calle del Cid: the overturned tomato truck. Three cells of four, and a
	# tomato heap in the gap that is jumped rather than walked round.
	boxes.push_back(cell_box(Vector2(29.5, TRUCK_ROW + 0.75), Vector2(3.0, 1.5), 3.2,
		"OverturnedTruck", Color("b8302a")))
	var heap := metre_box(Vector2(31.5, TRUCK_ROW + 0.75), Vector3(2.4, 1.0, 1.6),
		"TomatoHeap", Color("c9402f"))
	heap["jumpable"] = true
	boxes.push_back(heap)
	return boxes


## Where the sauce is topped up: trucks parked against the walls, which stand
## in for the festival street's stalls. Built like the tutorial's stations --
## a vending-machine box with a facing -- so the reach test is unchanged.
static func refill_boxes() -> Array[Dictionary]:
	var size := Vector3(3.0, 3.2, 6.4)
	var boxes: Array[Dictionary] = []
	# Start plaza, against its east wall.
	boxes.push_back(_truck_against_wall(Vector2(34.0, 92.5), Vector3.LEFT, size))
	# Calle San Luis, halfway up, against the east wall.
	boxes.push_back(_truck_against_wall(Vector2(32.0, 78.0), Vector3.LEFT, size))
	# The west fork, against its outer wall, short of the fallen booth.
	boxes.push_back(_truck_against_wall(Vector2(16.0, 57.0), Vector3.RIGHT, size))
	# The east fork, against its outer wall, before the crates.
	boxes.push_back(_truck_against_wall(Vector2(43.0, 66.0), Vector3.LEFT, size))
	# Calle del Cid, against the west wall past the overturned truck.
	boxes.push_back(_truck_against_wall(Vector2(28.0, 39.5), Vector3.RIGHT, size))
	# The plaza, one against each side wall.
	boxes.push_back(_truck_against_wall(Vector2(20.0, 29.0), Vector3.RIGHT, size))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 29.0), Vector3.LEFT, size))
	return boxes


## A truck parked with its back on the wall face at `wall_cell` (a whole cell
## coordinate along the axis it backs onto) and its front out into the street.
static func _truck_against_wall(wall_cell: Vector2, facing: Vector3, size: Vector3) -> Dictionary:
	var face := at_cell(wall_cell)
	var depth: float = size.x if absf(facing.x) > 0.5 else size.z
	var position := face + facing * (depth * 0.5)
	position.y = size.y * 0.5
	var footprint := Vector3(size.z, size.y, size.x) if absf(facing.x) > 0.5 else size
	return {"position": position, "size": footprint, "facing": facing}


## The fire truck itself, parked at the back of its bay.
static func fire_truck_box() -> Dictionary:
	return metre_box(Vector2(30.0, 17.6), Vector3(5.5, 4.2, 14.0), "FireTruck", Color("c4231d"))


# --- the floor ----------------------------------------------------------------

## Paints the juice zones before anyone arrives. Every peer makes exactly these
## calls in this order, so nothing goes over the wire; a peer joining later
## takes the grid snapshot. Thin on purpose: ketchup is never slippery, so one
## layer is a stain to run through and nothing more. One coat, so overlapping
## splats stay one layer rather than piling up to the deep band.
static func seed_floor(floor_body: FloorContamination) -> void:
	const COAT := 920000
	for zone in JUICE_ZONES:
		var rect: Rect2i = zone[0]
		var step: float = zone[1]
		var corner := at_cell(Vector2(rect.position))
		var span := Vector2(float(rect.size.x), float(rect.size.y)) * StreetMap.CELL
		var columns := int(ceil(span.x / step))
		var rows := int(ceil(span.y / step))
		for row in rows:
			for column in columns:
				# A hash per lattice point scatters the splats so the zone reads
				# as spattered rather than tiled; the same hash on every peer.
				var noise := _hash(column, row, rect.position.x + rect.position.y * 131)
				if noise > 0.82:
					continue
				var jitter := Vector2(_hash(column + 7, row + 3, 11), _hash(column + 1, row + 9, 23))
				var x: float = corner.x + (float(column) + 0.5 + (jitter.x - 0.5) * 0.9) * step
				var z: float = corner.z + (float(row) + 0.5 + (jitter.y - 0.5) * 0.9) * step
				floor_body.paint_mayo(Vector3(x, 0.0, z), COAT, ContaminationGrid.KIND_KETCHUP)
	floor_body.grid._coats.erase(COAT)


## 0..1, a pure function of its inputs.
static func _hash(x: int, y: int, salt: int) -> float:
	var value := sin(float(x * 127 + y * 311 + salt * 17 + 5) * 0.173) * 43758.5453
	return value - floor(value)
