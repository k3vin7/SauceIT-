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
## junction passable. Ordinary alleys are five or six cells across so a party
## can dodge and pass. The overturned-truck stretch stays a short chokepoint.
const SEGMENTS: Array[Rect2i] = [
	Rect2i(26, 90, 8, 6),    # 0 the village edge: start plaza, sauce truck
	Rect2i(27, 70, 6, 21),   # 1 Calle San Luis, north out of the start
	Rect2i(15, 69, 14, 5),   # 2 west fork, across
	Rect2i(15, 55, 5, 16),   # 3 west fork, up
	Rect2i(15, 53, 15, 5),   # 4 west fork, back to the Cid
	Rect2i(31, 69, 13, 5),   # 5 east fork, across
	Rect2i(39, 49, 5, 22),   # 6 east fork, up (the bowling lane)
	Rect2i(30, 49, 14, 5),   # 7 east fork, back to the Cid
	Rect2i(25, 48, 10, 8),    # 8 Calle del Cid, where the forks rejoin
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

## Where the street is already under tomato juice before anyone arrives: the
## short fork end to end, the chokepoint under the overturned truck, and the
## middle of the plaza where the fight is going to be. Painted solid, wall to
## wall: the real street is a red river by noon, not a spatter.
const JUICE_ZONES: Array[Rect2i] = [
	Rect2i(15, 69, 14, 5),
	Rect2i(15, 55, 5, 16),
	Rect2i(15, 53, 15, 5),
	Rect2i(28, 42, 4, 6),
	Rect2i(26, 26, 8, 7),
]

## Where the start arrow is drawn, in metres from the lattice origin, which is
## the middle of the start plaza. The arrow is 22 m nose to tail, so drawn at
## the origin its tail ran under the south wall; this puts the whole of it on
## the plaza.
const START_ARROW := Vector3(0.0, 0.0, -7.2)

## Where the party stands at the start: single file down the arrow's shaft
## from its tail, the host at the very end, everyone facing the way it
## points -- so the whole arrow is in front of you, pointing up the street.
## Three metres apart, so nobody stands in anybody. The shaft ends at
## z = 11.2, so the host stands a metre and a half short of its tail.
const SPAWNS := [
	Vector3(0.0, 1.28, 9.5),
	Vector3(0.0, 1.28, 6.5),
	Vector3(0.0, 1.28, 3.5),
	Vector3(0.0, 1.28, 0.5),
]


static func spawn_position(slot: int) -> Vector3:
	return SPAWNS[slot % SPAWNS.size()]


## The elites, as `[kind, cell]` with the kind named as `MayoEnemy.EnemyKind`
## reads it. A cell may be fractional: it is a position, not an index. Placed
## by hand because each is a set piece: a bowler at the top of a straight, a
## brute where the forks rejoin, a spitter covering a crowd.
const ELITES := [
	["BOWLING_TOMATO", Vector2(30.0, 70.5)],
	["KETCHUP_SPITTER", Vector2(18.0, 55.5)],
	["CAPRESE_CRAWLER", Vector2(22.5, 55.5)],
	["BOWLING_TOMATO", Vector2(41.5, 51.5)],
	["TOMATO_BRUTE", Vector2(30.5, 38.0)],
	["CAPRESE_CRAWLER", Vector2(29.5, 40.0)],
	["TOMATO_BRUTE", Vector2(30.0, 29.5)],
	["TOMATO_BRUTE", Vector2(34.0, 30.0)],
	["KETCHUP_SPITTER", Vector2(24.5, 28.5)],
	["KETCHUP_SPITTER", Vector2(36.0, 26.5)],
]

## How many grunts stand on the street before the horde.
const GRUNT_COUNT := 60


## The standing roster: the elites, then the grunts. Grunts are dealt onto the
## street rather than listed (see `grunt_cells`), so the count is one number
## and none of them is ever inside a truck.
static func roster() -> Array:
	var out := ELITES.duplicate()
	for cell in grunt_cells():
		out.push_back(["TOMATO_GRUNT", cell])
	return out


## `GRUNT_COUNT` positions in encounter packs along the route from the foot of
## Calle San Luis to the plaza: never in the start plaza or the fire bay,
## never in a cell a prop stands in (the tomato heap included), never in an
## elite's cell. A pure function of the constants, so every peer agrees.
static func grunt_cells() -> Array[Vector2]:
	var props: Array[Dictionary] = debris_boxes()
	props.append_array(refill_boxes())
	props.push_back(fire_truck_box())
	var taken := _box_cells(props)
	for elite in ELITES:
		var at: Vector2 = elite[1]
		taken[Vector2i(int(floor(at.x)), int(floor(at.y)))] = true
	# Nothing within two cells of the start plaza either: the first grunt is
	# up the street, not on the point of the arrow.
	var plaza_edge: int = SEGMENTS[START_SEGMENT].position.y - 2
	var candidates: Array[Vector2i] = []
	for index in range(START_SEGMENT + 1, FIRE_BAY_SEGMENT):
		var rect: Rect2i = SEGMENTS[index]
		for j in rect.size.y:
			for i in rect.size.x:
				var cell := rect.position + Vector2i(i, j)
				if taken.has(cell) or cell.y >= plaza_edge:
					continue
				taken[cell] = true
				candidates.push_back(cell)
	# Encounter packs leave the entry, connecting streets and regroup bay empty.
	var packs := [
		[Rect2i(27, 80, 6, 3), 6],
		[Rect2i(25, 69, 8, 5), 8],
		[Rect2i(15, 58, 5, 5), 8],
		[Rect2i(39, 58, 5, 5), 8],
		[Rect2i(28, 36, 4, 6), 10],
		[Rect2i(20, 24, 20, 10), 20],
	]
	var out: Array[Vector2] = []
	for pack in packs:
		var available: Array[Vector2i] = []
		for cell in candidates:
			if (pack[0] as Rect2i).has_point(cell):
				available.push_back(cell)
		for k in mini(int(pack[1]), available.size()):
			var pick := int(floor((float(k) + 0.5) * available.size() / float(pack[1])))
			var cell := available[mini(pick, available.size() - 1)]
			out.push_back(Vector2(cell) + Vector2(0.5, 0.5))
	return out


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
	var props: Array[Dictionary] = []
	for box in debris_boxes():
		if box.get("jumpable", false):
			continue
		props.push_back(box)
	props.append_array(refill_boxes())
	props.push_back(fire_truck_box())
	return _box_cells(props)


## The lattice cells the boxes' footprints cover.
static func _box_cells(props: Array[Dictionary]) -> Dictionary:
	var covered := {}
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
				covered[Vector2i(i, j)] = true
	return covered


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
	boxes.push_back(metre_box(Vector2(16.75, 62.5), Vector3(2.8, 1.1, 0.7), "FallenBoothA", booth))
	boxes.push_back(metre_box(Vector2(22.5, 70.75), Vector3(0.7, 1.1, 2.8), "FallenBoothB", booth))
	# East fork: long and clean. Crates stagger the lane without closing it.
	boxes.push_back(metre_box(Vector2(42.25, 60.5), Vector3(1.6, 1.2, 1.0), "CratesA", crate))
	boxes.push_back(metre_box(Vector2(40.75, 55.5), Vector3(1.6, 1.2, 1.0), "CratesB", crate))
	# Cover on the approach to each fork's ranged enemy; side routes stay open.
	boxes.push_back(metre_box(Vector2(17.5, 64.5), Vector3(2.8, 1.25, 0.65), "WestRangedCover", booth))
	boxes.push_back(metre_box(Vector2(41.0, 57.0), Vector3(1.8, 1.3, 1.0), "EastRangedCover", crate))
	# Offset obstacles break straight pursuit without narrowing the full lane.
	boxes.push_back(metre_box(Vector2(29.0, 78.0), Vector3(2.6, 1.0, 0.65), "OpeningBrokenStall", booth))
	boxes.push_back(metre_box(Vector2(36.0, 71.5), Vector3(1.5, 1.1, 0.9), "ForkTomatoCrates", crate))
	boxes.push_back(metre_box(Vector2(22.5, 32.0), Vector3(2.8, 1.1, 0.7), "PlazaBrokenStall", booth))
	boxes.push_back(metre_box(Vector2(36.0, 33.0), Vector3(1.8, 1.3, 1.0), "PlazaTomatoCrates", crate))
	# Staggered small props offer passing choices, not a wall across the street.
	for entry in [
		[Vector2(31.5, 85), Vector3(1.5, 1.1, 0.9), "EntryTomatoCrates"],
		[Vector2(27.8, 74.5), Vector3(2.5, 1.0, 0.65), "ForkBrokenStall"],
		[Vector2(20.5, 72.5), Vector3(1.5, 1.2, 0.9), "WestTomatoCrates"],
		[Vector2(18.8, 66), Vector3(2.4, 1.0, 0.65), "WestBrokenStall"],
		[Vector2(24.5, 56.5), Vector3(1.6, 1.2, 1.0), "WestExitCrates"],
		[Vector2(40, 65), Vector3(1.5, 1.1, 0.9), "EastTomatoCrates"],
		[Vector2(36, 52.5), Vector3(2.4, 1.1, 0.65), "EastExitStall"],
		[Vector2(28.5, 40.5), Vector3(1.6, 1.2, 0.9), "TruckApproachCrates"],
		[Vector2(26, 34.5), Vector3(2.6, 1.1, 0.65), "PlazaEntryStall"],
		[Vector2(30, 27), Vector3(1.6, 1.2, 0.9), "PlazaCentreCrates"],
		[Vector2(37.5, 25), Vector3(2.4, 1.1, 0.65), "PlazaSideStall"],
	]:
		boxes.push_back(metre_box(entry[0], entry[1], entry[2], crate))
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
## a vending-machine box with a facing -- so the reach test is unchanged. One
## every forty metres or so, so a bottle is never far from being filled.
static func refill_boxes() -> Array[Dictionary]:
	# Backed onto a side wall: 3 m deep into the street, 6.4 m along the wall.
	var side := Vector3(3.0, 3.2, 6.4)
	# Backed onto an end wall: the same truck turned to lie along it.
	var end := Vector3(6.4, 3.2, 3.0)
	var boxes: Array[Dictionary] = []
	# The start plaza, one against each side wall.
	boxes.push_back(_truck_against_wall(Vector2(34.0, 92.5), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(26.0, 92.5), Vector3.RIGHT, side))
	# Calle San Luis, three up its length, alternating walls.
	boxes.push_back(_truck_against_wall(Vector2(27.0, 86.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(33.0, 80.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(27.0, 75.0), Vector3.RIGHT, side))
	# A truck is a cell and a half deep, so in a three-cell alley every truck
	# goes on the same wall as the rubble: two on opposite walls at the same
	# height would close the alley.
	# The west fork: three on the outer wall going up, the north wall of the
	# way back.
	boxes.push_back(_truck_against_wall(Vector2(15.0, 67.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(15.0, 60.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(15.0, 57.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(22.0, 53.0), Vector3.BACK, end))
	# The east fork: both end walls going across, two on the outer wall going
	# up (the crates' wall), the north wall of the way back.
	boxes.push_back(_truck_against_wall(Vector2(35.0, 69.0), Vector3.BACK, end))
	boxes.push_back(_truck_against_wall(Vector2(38.5, 74.0), Vector3.FORWARD, end))
	boxes.push_back(_truck_against_wall(Vector2(44.0, 66.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(44.0, 62.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(36.0, 49.0), Vector3.BACK, end))
	# Calle del Cid: both walls where the forks rejoin, then past the
	# overturned truck. Nothing on the east wall beside the truck: the heap
	# gap is one cell wide and a truck there would close its only approach.
	boxes.push_back(_truck_against_wall(Vector2(35.0, 54.5), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(25.0, 50.5), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(28.0, 39.5), Vector3.RIGHT, side))
	# The plaza: two on each side wall, one on the north wall beside the bay.
	boxes.push_back(_truck_against_wall(Vector2(20.0, 24.5), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(20.0, 29.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 29.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 34.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(36.0, 22.0), Vector3.BACK, end))
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

## Floods the juice zones before anyone arrives: every cell of every zone,
## wall to wall, one layer deep. Written straight into the grid rather than
## splatted, so the edge is the kerb and there are no holes: a street that has
## had a lorry of tomatoes thrown along it is red, not spotted. Every peer
## makes exactly these calls, so nothing goes over the wire; a peer joining
## later takes the grid snapshot. One layer, because ketchup is never
## slippery: it is a stain to run through and nothing more.
static func seed_floor(floor_body: FloorContamination) -> void:
	for rect in JUICE_ZONES:
		var low := at_cell(Vector2(rect.position))
		var high := at_cell(Vector2(rect.position + rect.size))
		floor_body.fill_rect(low, high, 1, ContaminationGrid.KIND_KETCHUP)


## 0..1, a pure function of its inputs.
static func _hash(x: int, y: int, salt: int) -> float:
	var value := sin(float(x * 127 + y * 311 + salt * 17 + 5) * 0.173) * 43758.5453
	return value - floor(value)
