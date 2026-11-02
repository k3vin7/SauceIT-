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

## Where the street is already under tomato juice before anyone arrives: the
## short fork end to end, the chokepoint under the overturned truck, and the
## middle of the plaza where the fight is going to be. Painted solid, wall to
## wall: the real street is a red river by noon, not a spatter.
const JUICE_ZONES: Array[Rect2i] = [
	Rect2i(16, 70, 13, 3),
	Rect2i(16, 56, 3, 15),
	Rect2i(16, 54, 14, 3),
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
	["TOMATO_BRUTE", Vector2(30.5, 51.0)],
	["CAPRESE_CRAWLER", Vector2(29.5, 47.0)],
	["TOMATO_BRUTE", Vector2(30.0, 29.5)],
	["TOMATO_BRUTE", Vector2(34.0, 30.0)],
	["KETCHUP_SPITTER", Vector2(24.5, 28.5)],
	["KETCHUP_SPITTER", Vector2(36.0, 26.5)],
]

## How many grunts stand on the street before the horde.
const GRUNT_COUNT := 88


## The standing roster: the elites, then the grunts. Grunts are dealt onto the
## street rather than listed (see `grunt_cells`), so the count is one number
## and none of them is ever inside a truck.
static func roster() -> Array:
	var out := ELITES.duplicate()
	for cell in grunt_cells():
		out.push_back(["TOMATO_GRUNT", cell])
	return out


## `GRUNT_COUNT` positions spread evenly along the route from the foot of
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
	var out: Array[Vector2] = []
	for k in GRUNT_COUNT:
		var pick := int(floor((float(k) + 0.5) * float(candidates.size()) / float(GRUNT_COUNT)))
		var cell := candidates[mini(pick, candidates.size() - 1)]
		var jitter := Vector2(_hash(cell.x, cell.y, 5), _hash(cell.y, cell.x, 17)) - Vector2(0.5, 0.5)
		out.push_back(Vector2(cell) + Vector2(0.5, 0.5) + jitter * 0.5)
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
	boxes.push_back(_truck_against_wall(Vector2(28.0, 86.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(32.0, 80.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(28.0, 75.0), Vector3.RIGHT, side))
	# A truck is a cell and a half deep, so in a three-cell alley every truck
	# goes on the same wall as the rubble: two on opposite walls at the same
	# height would close the alley.
	# The west fork: three on the outer wall going up, the north wall of the
	# way back.
	boxes.push_back(_truck_against_wall(Vector2(16.0, 67.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(16.0, 60.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(16.0, 57.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(22.0, 54.0), Vector3.BACK, end))
	# The east fork: both end walls going across, two on the outer wall going
	# up (the crates' wall), the north wall of the way back.
	boxes.push_back(_truck_against_wall(Vector2(35.0, 70.0), Vector3.BACK, end))
	boxes.push_back(_truck_against_wall(Vector2(38.5, 73.0), Vector3.FORWARD, end))
	boxes.push_back(_truck_against_wall(Vector2(43.0, 66.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(43.0, 62.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(36.0, 50.0), Vector3.BACK, end))
	# Calle del Cid: both walls where the forks rejoin, then past the
	# overturned truck. Nothing on the east wall beside the truck: the heap
	# gap is one cell wide and a truck there would close its only approach.
	boxes.push_back(_truck_against_wall(Vector2(32.0, 54.5), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(28.0, 50.5), Vector3.RIGHT, side))
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
	# `size` is already in world axes for the wall it is given for -- x across
	# the street, z along it -- which is what `depth` above relies on. It used
	# to be swapped here for side walls as well, which turned every side truck
	# end-on: 6.4 m into the street from a centre 1.5 m off the wall, so 1.7 m
	# of it was buried in the wall and its nose reached 9 cm into the next
	# lane's cell -- enough to mark that whole cell solid for the router, and
	# the grunts were seen walking round the players standing in it.
	return {"position": position, "size": size, "facing": facing}


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
