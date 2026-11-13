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
## Trace the village from the reference: an irregular south-to-north spine
## with the refuge courts staggered east, west and east.
const SEED := 0x70A7A70
const BOUNDARY_HEIGHT := 6.8
const START_PLAZA := Rect2i(26, 224, 8, 6)
const FINISH_APPROACH := Rect2i(28, 36, 4, 9)
const PLAZA := Rect2i(20, 22, 20, 15)
const FIRE_BAY := Rect2i(27, 16, 6, 7)
const PLAZA_CORNERS := [
	Vector2i(20, 22), Vector2i(21, 22), Vector2i(20, 23),
	Vector2i(38, 22), Vector2i(39, 22), Vector2i(39, 23),
	Vector2i(20, 35), Vector2i(20, 36), Vector2i(21, 36),
	Vector2i(39, 35), Vector2i(39, 36), Vector2i(38, 36),
]
const SAFE_ROOMS: Array[Rect2i] = [
	Rect2i(34, 190, 5, 5),
	Rect2i(14, 120, 5, 5),
	Rect2i(37, 64, 7, 5),
]
const SAFE_ROOM_NAMES := ["급수 마당", "시장 피난처", "축제 본부"]


const ROUTE_POINTS := [
	[
		Vector2(29.2, 225.1), Vector2(29.2, 221.1), Vector2(26, 214.7), Vector2(29.2, 206.8),
		Vector2(28.4, 199.6), Vector2(35.2, 199.1), Vector2(36.4, 192.5),
	],
	[
		Vector2(36.4, 192.5), Vector2(30, 190.9), Vector2(17.3, 190.9), Vector2(8.5, 186.9),
		Vector2(4.6, 178.9), Vector2(3.8, 171), Vector2(10.1, 166.2), Vector2(20.5, 163),
		Vector2(25.2, 157.5), Vector2(28.4, 149.5), Vector2(35.0, 144.0),
		Vector2(37.0, 137.0), Vector2(36.5, 130.0), Vector2(32.4, 122.5),
		Vector2(16.5, 122.5),
	],
	[
		Vector2(16.5, 122.5), Vector2(10.9, 114.6), Vector2(6.9, 108.2), Vector2(10.9, 102.6),
		Vector2(15.7, 97.1), Vector2(17.3, 89.9), Vector2(21.3, 84.3), Vector2(28.4, 82),
		Vector2(33.2, 77.2), Vector2(33.2, 70.8), Vector2(29.2, 66.1), Vector2(41.1, 66.1),
	],
	[
		Vector2(41.1, 66.1), Vector2(38, 60.5), Vector2(31.6, 58.1), Vector2(21.3, 56.5),
		Vector2(16.5, 52.5), Vector2(18.9, 47), Vector2(25.2, 44.6), Vector2(29.8, 43),
		Vector2(30, 39),
	],
]
## Distance along each leg and its half-width in cells. The profiles alternate
## short pinches with wider markets so the bends reveal distinct spaces.
const ROAD_WIDTHS := [
	[Vector2(0, 2.45), Vector2(0.13, 1.75), Vector2(0.23, 1.63), Vector2(0.32, 2.48),
		Vector2(0.40, 2.88), Vector2(0.54, 3.88), Vector2(0.65, 3.28), Vector2(0.76, 2.32),
		Vector2(0.87, 1.72), Vector2(0.94, 2.28), Vector2(1, 2.45)],
	[Vector2(0, 2.45), Vector2(0.12, 1.76), Vector2(0.21, 2.53), Vector2(0.30, 3.70),
		Vector2(0.37, 3.48), Vector2(0.44, 1.82), Vector2(0.53, 3.10), Vector2(0.63, 3.44),
		Vector2(0.73, 1.72), Vector2(0.81, 2.20), Vector2(0.91, 3.28), Vector2(1, 2.45)],
	[Vector2(0, 2.45), Vector2(0.12, 2.10), Vector2(0.23, 1.68), Vector2(0.30, 2.83),
		Vector2(0.37, 3.65), Vector2(0.47, 2.40), Vector2(0.55, 1.68), Vector2(0.63, 2.66),
		Vector2(0.69, 3.33), Vector2(0.76, 3.77), Vector2(0.85, 1.76), Vector2(1, 2.45)],
	[Vector2(0, 2.45), Vector2(0.14, 1.85), Vector2(0.24, 2.45), Vector2(0.36, 3.43),
		Vector2(0.43, 3.35), Vector2(0.51, 2.72), Vector2(0.60, 1.75), Vector2(0.71, 2.90),
		Vector2(0.78, 2.75), Vector2(0.87, 1.78), Vector2(0.96, 2.23), Vector2(1, 2.45)],
]
const CAPRESE_RESCUE_BAY := Rect2i(26, 68, 6, 5)
const CAPRESE_AMBUSH_CELL := Vector2(31.5, 68.5)
const ROAD_POCKETS := [
	[1, Rect2i(0, 168, 5, 4)],
	[1, Rect2i(37, 137, 5, 4)],
	[2, Rect2i(11, 95, 5, 4)],
	[2, CAPRESE_RESCUE_BAY],
]
# Smaller side passages end at houses and never bypass a refuge.
const SIDE_ALLEYS := [
	[0, [Vector2(29.2, 206.8), Vector2(24, 203.9), Vector2(20, 199.4), Vector2(17, 196.2)]],
	[1, [Vector2(10.1, 166.2), Vector2(10, 159), Vector2(6.8, 155.2), Vector2(7.8, 149.4)]],
	[1, [Vector2(35.4, 128.0), Vector2(41.0, 124.5), Vector2(41.5, 119.2)]],
	[2, [Vector2(16.1, 95.4), Vector2(21.7, 96.3), Vector2(27.1, 97.8), Vector2(31.1, 95.1)]],
	[3, [Vector2(32.2, 58.4), Vector2(36.2, 54.3), Vector2(40.7, 53), Vector2(43.5, 48.6)]],
]
const MARKET_SHORTCUT := [Vector2(10.1, 166.2), Vector2(13.5, 156.5), Vector2(15.5, 143.5), Vector2(22.5, 132.0), Vector2(28.0, 122.5)]
const MARKET_GATE_CELL := Vector2(15.0, 146.0)
const TRUCK_ROW := 44.0
const SIREN_CELL := Vector2(25.5, 27.5)
const PRESS_KING_CELL := Vector2(35.5, 23.5)
const PRESS_KING_YAW := 2.55
const JUICE_ZONES: Array[Rect2i] = [
	Rect2i(1, 168, 16, 21),
	Rect2i(10, 144, 11, 19),
	Rect2i(8, 90, 13, 20),
	Rect2i(15, 47, 15, 12),
	Rect2i(28, 42, 4, 6),
]

static var _floor_legs: Dictionary
static var _floor_bounds := Rect2i()
static var _routes: Array[PackedVector2Array] = []


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


static func start_arrow() -> Vector3:
	return START_ARROW + _start_offset()


static func spawn_position(slot: int) -> Vector3:
	return SPAWNS[slot % SPAWNS.size()] + _start_offset()


static func _start_offset() -> Vector3:
	return Vector3.BACK * ((START_PLAZA.position.y - 90) * StreetMap.CELL)


const PLAZA_ELITES := [
	["TOMATO_BRUTE", Vector2(30.5, 37.5)],
	["CAPRESE_CRAWLER", Vector2(23.5, 33.5)],
	["TOMATO_BRUTE", Vector2(30.0, 29.5)],
	["TOMATO_BRUTE", Vector2(34.0, 30.0)],
	["KETCHUP_SPITTER", Vector2(24.5, 28.5)],
	["KETCHUP_SPITTER", Vector2(36.0, 26.5)],
]
const ALLEY_ELITES := [
	["KETCHUP_SPITTER", 0, 0.61], ["CAPRESE_CRAWLER", 0, 0.83],
	["BOWLING_TOMATO", 1, 0.29], ["BOWLING_TOMATO", 1, 0.81],
	["TOMATO_BRUTE", 2, 0.45],
]
# Each group is centred on a distance along its leg.
const GRUNT_PACKS := [
	[0, 0.19, 8], [0, 0.46, 10], [0, 0.77, 12],
	[1, 0.13, 7], [1, 0.34, 8], [1, 0.53, 8], [1, 0.72, 9], [1, 0.89, 8],
	[2, 0.21, 8], [2, 0.51, 10], [2, 0.81, 9],
	[3, 0.36, 8], [3, 0.73, 9],
]
# Leg, trip point past the mouth of a side alley, then the forward and rear threats.
const ALLEY_AMBUSHES := [
	[0, Vector2(28.9, 204.3), [
		["TOMATO_BRUTE", Vector2i(28, 201)], ["CAPRESE_CRAWLER", Vector2i(25, 206)],
		["TOMATO_GRUNT", Vector2i(24, 203)],
	]],
	[1, Vector2(15.8, 164.7), [
		["BOWLING_TOMATO", Vector2i(20, 163)], ["KETCHUP_SPITTER", Vector2i(12, 165)],
		["TOMATO_GRUNT", Vector2i(10, 161)],
	]],
	[1, Vector2(33.6, 125.8), [
		["TOMATO_BRUTE", Vector2i(29, 122)], ["CAPRESE_CRAWLER", Vector2i(36, 128)],
		["TOMATO_GRUNT", Vector2i(39, 125)],
	]],
	[2, Vector2(16.8, 92.7), [
		["BOWLING_TOMATO", Vector2i(18, 88)], ["CAPRESE_CRAWLER", Vector2i(18, 95)],
		["TOMATO_GRUNT", Vector2i(21, 95)],
	]],
	[3, Vector2(28.5, 57.6), [
		["TOMATO_BRUTE", Vector2i(24, 57)], ["KETCHUP_SPITTER", Vector2i(31, 58)],
		["TOMATO_GRUNT", Vector2i(36, 54)],
	]],
]
const ALLEY_REINFORCEMENT := &"alley_reinforcement"
# Each pack adds a specialist and four grunts between the existing alley fights.
const ALLEY_REINFORCEMENTS := [
	[0, 0.34, "KETCHUP_SPITTER"],
	[1, 0.20, "CAPRESE_CRAWLER"],
	[1, 0.62, "TOMATO_BRUTE"],
	[2, 0.11, "KETCHUP_SPITTER"],
	[2, 0.69, "TOMATO_BRUTE"],
	[3, 0.11, "CAPRESE_CRAWLER"],
	[3, 0.79, "KETCHUP_SPITTER"],
]
const REINFORCEMENT_GRUNTS := 4


static func refuge_shower_at(room: int) -> Vector3:
	var courtyard := SAFE_ROOMS[room]
	return at_cell(Vector2(courtyard.end.x - 1.0, courtyard.position.y + 1.15))


static func refuge_shop_at(room: int) -> Vector3:
	return at_cell(Vector2(SAFE_ROOMS[room].position) + Vector2(0.82, 1.62))


static func safe_room_at(cell: Vector2i) -> int:
	for index in SAFE_ROOMS.size():
		if SAFE_ROOMS[index].has_point(cell):
			return index
	return -1


## Pursuit stays within the curved leg where an enemy spawned.
static func encounter_at(cell: Vector2i) -> int:
	_ensure_layout()
	return int(_floor_legs.get(cell, -1))


static func roster() -> Array:
	var props := debris_boxes()
	props.append_array(parked_trucks())
	props.push_back(fire_truck_box())
	var taken := _box_cells(props)
	taken.merge(market_gate_cells())
	taken[Vector2i(PRESS_KING_CELL)] = true
	var out := PLAZA_ELITES.duplicate()
	for elite in PLAZA_ELITES:
		taken[Vector2i((elite[1] as Vector2).floor())] = true
	var ambush := Vector2i(CAPRESE_AMBUSH_CELL.floor())
	if not taken.has(ambush):
		taken[ambush] = true
		out.append(["CAPRESE_CRAWLER", CAPRESE_AMBUSH_CELL])
	else:
		var cells := _nearby_open_cells(2, CAPRESE_AMBUSH_CELL, taken, 14.0)
		if not cells.is_empty():
			taken[cells[0]] = true
			out.append(["CAPRESE_CRAWLER", Vector2(cells[0]) + Vector2(0.5, 0.5)])
	for entry in ALLEY_ELITES:
		var pose := _route_pose(int(entry[1]), float(entry[2]))
		var cells := _nearby_open_cells(int(entry[1]), pose[0], taken, 14.0)
		if not cells.is_empty():
			var cell: Vector2i = cells[0]
			taken[cell] = true
			out.push_back([entry[0], Vector2(cell) + Vector2(0.5, 0.5)])
	for cell in _grunt_cells(taken):
		out.push_back(["TOMATO_GRUNT", cell])
	# Keep the plaza guard order, including the grunt burst tiers keyed by index.
	for group in ALLEY_AMBUSHES.size():
		var ambush_plan: Array = ALLEY_AMBUSHES[group]
		for entry in ambush_plan[2]:
			var cell: Vector2i = entry[1]
			taken[cell] = true
			out.push_back([entry[0], Vector2(cell) + Vector2.ONE * 0.5, group])
	_add_alley_reinforcements(out, taken)
	return out


static func _add_alley_reinforcements(out: Array, taken: Dictionary) -> void:
	for pack in ALLEY_REINFORCEMENTS:
		var leg: int = pack[0]
		var pose := _route_pose(leg, float(pack[1]))
		var nearby := _nearby_open_cells(leg, pose[0], taken, 3.25)
		if leg == 3:
			nearby = nearby.filter(func(cell: Vector2i) -> bool:
				return cell.y >= PLAZA.end.y)
		if nearby.is_empty():
			continue
		var lead: Vector2i = nearby.pop_front()
		taken[lead] = true
		out.push_back([pack[2], Vector2(lead) + Vector2.ONE * 0.5, ALLEY_REINFORCEMENT])
		var grunts: Array[Vector2] = []
		_add_grunt_pack(grunts, nearby, REINFORCEMENT_GRUNTS, taken)
		for cell in grunts:
			out.push_back(["TOMATO_GRUNT", cell, ALLEY_REINFORCEMENT])


static func grunt_cells() -> Array[Vector2]:
	var cells: Array[Vector2] = []
	for entry in roster():
		if entry[0] == "TOMATO_GRUNT":
			cells.push_back(entry[1])
	return cells


static func _grunt_cells(taken: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pack in GRUNT_PACKS:
		var leg: int = pack[0]
		var pose := _route_pose(leg, float(pack[1]))
		var nearby := _nearby_open_cells(leg, pose[0], taken, 13.0)
		_add_grunt_pack(out, nearby, int(pack[2]), taken)
	var plaza := _nearby_open_cells(3, Vector2(30, 29), taken, 11.0)
	plaza = plaza.filter(func(cell: Vector2i) -> bool:
		return PLAZA.has_point(cell) and cell.y >= 24 and cell.y < 34)
	_add_grunt_pack(out, plaza, 20, taken)
	return out


static func _add_grunt_pack(out: Array[Vector2], cells: Array[Vector2i],
		count: int, taken: Dictionary) -> void:
	var span := mini(cells.size(), count * 3)
	count = mini(count, span)
	for index in count:
		var pick := int((float(index) + 0.5) * span / count)
		var cell := cells[pick]
		taken[cell] = true
		out.push_back(Vector2(cell) + Vector2(0.5, 0.5))


static func _nearby_open_cells(leg: int, at: Vector2, taken: Dictionary,
		reach: float) -> Array[Vector2i]:
	_ensure_layout()
	var out: Array[Vector2i] = []
	for cell: Vector2i in _floor_legs:
		if _floor_legs[cell] == leg and not taken.has(cell) \
				and (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(at) < reach * reach:
			out.push_back(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(at) \
			< (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(at))
	return out


## Where the horde comes in from once the party is on the plaza: its edges,
## cycled through in this order so every peer agrees on body N's position.
const HORDE_EDGES := [
	[Vector2(21.5, 25.5), Vector2(22.5, 24.5), Vector2(21.5, 26.5),
		Vector2(22.5, 28.5), Vector2(21.5, 30.5), Vector2(22.5, 30.5)],
	[Vector2(38.5, 23.5), Vector2(37.5, 24.5), Vector2(38.5, 26.5),
		Vector2(37.5, 27.5), Vector2(38.5, 29.5), Vector2(37.5, 30.5)],
	[Vector2(23.5, 23.5), Vector2(26.5, 23.5), Vector2(26.5, 24.5),
		Vector2(33.5, 23.5), Vector2(34.5, 23.5), Vector2(35.5, 24.5)],
]


# --- the three calls StreetMap forwards ---------------------------------------

static func floor_cells() -> Dictionary:
	_ensure_layout()
	return _floor_legs.duplicate()


static func bounds() -> Rect2i:
	_ensure_layout()
	return _floor_bounds


static func _ensure_layout() -> void:
	if not _routes.is_empty():
		return
	for leg in ROUTE_POINTS.size():
		var points: Array = ROUTE_POINTS[leg]
		var curve := PackedVector2Array([points[0]])
		for index in range(1, points.size()):
			var a: Vector2 = points[index - 1]
			var b: Vector2 = points[index]
			curve.push_back(a.lerp(b, 0.22))
			curve.push_back(a.lerp(b, 0.78))
		curve.push_back(points.back())
		_routes.push_back(curve)
		var total := _curve_length(curve)
		var traveled := 0.0
		for index in range(1, curve.size()):
			var a := curve[index - 1]
			var b := curve[index]
			var next := traveled + a.distance_to(b)
			_raster_segment(a, b, leg, 4.0, Vector2(traveled / total, next / total))
			traveled = next
	for alley in SIDE_ALLEYS:
		var points: Array = alley[1]
		for index in range(1, points.size()):
			_raster_segment(points[index - 1], points[index], int(alley[0]), 1.23)
	for index in range(1, MARKET_SHORTCUT.size()):
		_raster_segment(MARKET_SHORTCUT[index - 1], MARKET_SHORTCUT[index], 1, 1.65)
	for pocket in ROAD_POCKETS:
		_add_floor_rect(pocket[1], pocket[0])
	_add_floor_rect(START_PLAZA, 0)
	for rect in [FINISH_APPROACH, Rect2i(26, 44, 7, 3), Rect2i(26, 36, 8, 6), PLAZA, FIRE_BAY]:
		_add_floor_rect(rect, 3)
	for corner in PLAZA_CORNERS:
		_floor_legs.erase(corner)
	# This corner is cut off by the stalls on the first market bend.
	_floor_legs.erase(Vector2i(5, 186))
	for room in SAFE_ROOMS:
		_add_floor_rect(room, -1)
	for cell: Vector2i in _floor_legs:
		var pixel := Rect2i(cell, Vector2i.ONE)
		_floor_bounds = pixel if not _floor_bounds.has_area() else _floor_bounds.merge(pixel)


static func _raster_segment(a: Vector2, b: Vector2, leg: int,
		radius: float, progress := Vector2(-1.0, -1.0)) -> void:
	var span := b - a
	var span_squared := span.length_squared()
	if span_squared <= 0.0:
		return
	var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor())
	var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil())
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			var point := Vector2(x + 0.5, y + 0.5)
			var fraction := clampf((point - a).dot(span) / span_squared, 0.0, 1.0)
			var width := _road_radius(leg, lerpf(progress.x, progress.y, fraction)) \
				if progress.x >= 0.0 else radius
			if point.distance_squared_to(a + span * fraction) <= width * width:
				_floor_legs[Vector2i(x, y)] = leg


static func _add_floor_rect(rect: Rect2i, leg: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_floor_legs[Vector2i(x, y)] = leg


static func _road_radius(leg: int, fraction: float) -> float:
	var profile: Array = ROAD_WIDTHS[leg]
	for index in range(1, profile.size()):
		var next: Vector2 = profile[index]
		if fraction <= next.x:
			var previous: Vector2 = profile[index - 1]
			var blend := inverse_lerp(previous.x, next.x, fraction)
			return lerpf(previous.y, next.y, smoothstep(0.0, 1.0, blend))
	return (profile.back() as Vector2).y


static func _curve_length(curve: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, curve.size()):
		length += curve[index - 1].distance_to(curve[index])
	return length


static func _route_pose(leg: int, fraction: float) -> Array[Vector2]:
	_ensure_layout()
	var curve := _routes[leg]
	var remaining := fraction * _curve_length(curve)
	for index in range(1, curve.size()):
		var segment := curve[index] - curve[index - 1]
		var span := segment.length()
		if remaining <= span and span > 0.0:
			return [curve[index - 1] + segment * (remaining / span), segment / span]
		remaining -= span
	return [curve[-1], (curve[-1] - curve[-2]).normalized()]


## Street cells something is standing on. Every box a body cannot walk through
## -- debris, the sauce trucks, the fire truck -- except the tomato heap in the
## truck's gap, which is jumped and is left out so a route through the
## chokepoint still exists.
static func market_gate() -> Dictionary:
	return metre_box(MARKET_GATE_CELL, Vector3(22.8, 4.8, 2.0), "MarketShortcutGate", Color("2f5a64"))


static func market_gate_cells() -> Dictionary:
	return _box_cells([market_gate()])


static func blocked_cells() -> Dictionary:
	var props: Array[Dictionary] = []
	for box in debris_boxes():
		if box.get("jumpable", false):
			continue
		props.push_back(box)
	props.append_array(parked_trucks())
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


static func rect_world(rect: Rect2i) -> Rect2:
	var corner := at_cell(Vector2(rect.position))
	return Rect2(Vector2(corner.x, corner.z),
		Vector2(float(rect.size.x), float(rect.size.y)) * StreetMap.CELL)


static func plaza_rect() -> Rect2:
	return rect_world(PLAZA)


static func fire_truck_zone() -> Rect2:
	var truck := fire_truck_box()
	return Rect2(Vector2(truck.position.x-truck.size.x*.5-2.8,truck.position.z-truck.size.z*.5-2.8),Vector2(truck.size.x+5.6,truck.size.z+5.6))


static func in_rect(rect: Rect2, at: Vector3) -> bool:
	return rect.has_point(Vector2(at.x, at.z))


# --- props --------------------------------------------------------------------

const AFTERMATH_MODELS := [
	["CollapsedStall", Vector3(4.6, 1.85, 3.05)],
	["OverturnedHandcart", Vector3(2.7, 1.6, 3.55)],
	["CollapsedStoneWall", Vector3(4.1, 1.45, 1.9)],
	["BrokenFestivalBarrier", Vector3(3.8, 1.6, 1.6)],
]
const AFTERMATH_STOPS := [
	[0.12, 0.23, 0.38, 0.50, 0.56, 0.63, 0.72, 0.86],
	[0.08, 0.18, 0.27, 0.36, 0.48, 0.59, 0.68, 0.80, 0.88, 0.96],
	[0.10, 0.24, 0.35, 0.44, 0.55, 0.63, 0.73, 0.83, 0.94],
	[0.12, 0.22, 0.34, 0.43, 0.54, 0.65, 0.76, 0.88],
]


static func is_aftermath_prop(box: Dictionary) -> bool:
	return box.has("aftermath")


static func debris_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for leg in ROUTE_POINTS.size():
		var count: int = [5, 8, 8, 6][leg]
		for i in count:
			var fraction := lerpf(0.13, 0.88, float(i) / (count - 1))
			if leg == 3 and i == 1:
				fraction = 0.36
			elif leg == 3 and i == 2:
				fraction = 0.45
			var side := 1.0 if (i + leg) % 2 == 0 else -1.0
			if (leg == 1 and i == 4) or (leg == 2 and i == 5) or (leg == 3 and i == 2):
				side = 1.0
			var at := _alley_side(leg, fraction, side * 1.66)
			var stacked := i % 3 != 0
			var label := "TomatoCrateStack" if stacked else "TomatoCrates"
			var size := Vector3(2.7, 1.55, 1.45) if stacked else Vector3(2.6, 1.2, 1.1)
			boxes.push_back(metre_box(at, size, "%s%02d" % [label, boxes.size()], Color("8c7a4a")))
		for fraction in [0.25, 0.72]:
			var offset := 1.84 if fraction < 0.5 else -1.84
			if leg == 3 and fraction < 0.5:
				fraction = 0.21
			var at := _alley_side(leg, fraction, offset)
			boxes.push_back(metre_box(at, Vector3(2.1, 1.25, 1.4), "MarketBarrels", Color("8c7a4a")))
	# Smaller caches fill gaps between the larger trucks, beside the street.
	for leg in ROUTE_POINTS.size():
		var caches: Array = [
			[Vector2(0.27, -1.76), Vector2(0.55, 1.72), Vector2(0.69, -1.77)],
			[Vector2(0.15, 1.75), Vector2(0.37, 1.70), Vector2(0.57, -1.77), Vector2(0.93, 1.70)],
			[Vector2(0.18, -1.72), Vector2(0.41, 1.76), Vector2(0.72, -1.76), Vector2(0.90, 1.70)],
			[Vector2(0.26, 1.69), Vector2(0.46, -1.76), Vector2(0.73, -1.74)],
		][leg]
		for cache: Vector2 in caches:
			_add_supply_crate(boxes, _alley_side(leg, cache.x, cache.y))
	_add_supply_crate(boxes, Vector2(28.0, 227.8))
	_add_supply_crate(boxes, Vector2(33.5, 30.5))
	_add_supply_crate(boxes, Vector2(27.0, 34.2))
	for leg in ROUTE_POINTS.size():
		var fraction: float = [0.40, 0.53, 0.30, 0.51][leg]
		var pose := _route_pose(leg, fraction)
		var shoulder: float = [1.49, -1.93, 1.49, -1.49][leg]
		var at := _alley_side(leg, fraction, shoulder)
		boxes.push_back(_cargo_truck(at, pose[1], false))
	for entry in [[0, 0.54, -1.68], [1, 0.32, 1.76], [2, 0.75, 1.66]]:
		var at := _alley_side(int(entry[0]), float(entry[1]), float(entry[2]))
		boxes.push_back(metre_box(at, Vector3(4.4, 3.4, 3.0), "PlazaStallAlley"))
	for entry in [[1, 0.61, -1.73], [2, 0.37, 1.74], [3, 0.41, -1.77]]:
		var at := _alley_side(int(entry[0]), float(entry[1]), float(entry[2]))
		boxes.push_back(metre_box(at, Vector3(2.5, 1.0, 2.5), "PlazaTreeAlley"))
	var wreck_pose := _route_pose(2, 0.67)
	var wreck_at := _alley_side(2, 0.67, -1.28)
	boxes.push_back(_cargo_truck(wreck_at, wreck_pose[1], true))
	boxes.push_back(_cargo_truck(Vector2(28.9, TRUCK_ROW), Vector2.RIGHT, true))
	for at in [
		wreck_at + Vector2(0.58, -0.60), wreck_at + Vector2(0.37, 0.59),
		wreck_at + Vector2(-0.51, -0.43),
		Vector2(30.45, TRUCK_ROW + 0.46), Vector2(30.95, TRUCK_ROW - 0.04),
		Vector2(30.4, TRUCK_ROW - 0.7), Vector2(29.4, TRUCK_ROW + 0.72),
	]:
		var spill := metre_box(at, Vector3(2.1, 0.09, 1.15), "CrushedTomatoes", Color("c54d2d"))
		spill["jumpable"] = true
		boxes.push_back(spill)
	for room in SAFE_ROOMS:
		boxes.push_back(metre_box(Vector2(room.position.x + 0.82, room.position.y + 0.82),
			Vector3(5.0, 2.4, 3.2), "RefugeTent", CANOPY))
		for side in [-1.0, 1.0]:
			var x: float = room.get_center().x + 0.5 + 1.7 * side
			_add_supply_crate(boxes, Vector2(x, room.end.y - 0.74))
		var centre := Vector2(room.position) + Vector2(room.size) * 0.5
		boxes.push_back(metre_box(centre, Vector3(1.8, 0.6, 1.8), "RefugeBrazier", Color("b85b28")))
	boxes.push_back(metre_box(Vector2(25.5, 26.5), Vector3(3.5, 1.9, 2.5), "SirenColumn"))
	boxes.push_back(metre_box(Vector2(23.0, 34.5), Vector3(3, 1.1, 3), "PlazaTreeWest"))
	boxes.push_back(metre_box(Vector2(37.0, 34.5), Vector3(3, 1.1, 3), "PlazaTreeEast"))
	boxes.push_back(metre_box(Vector2(22.7, 25.0), Vector3(5, 3.4, 3.4), "PlazaStallWest"))
	boxes.push_back(metre_box(Vector2(38.5, 27.7), Vector3(4, 3.4, 3.4), "PlazaStallEast"))
	_rubble(boxes, "Entry", Vector2(31.4, 223.8), Vector2(31.7, 224.1), Vector2(31.2, 224.5))
	boxes.push_back(metre_box(Vector2(22.5, 32.0), Vector3(2.6, 1.2, 1.1), "TomatoCrateStackPlazaWest"))
	boxes.push_back(metre_box(Vector2(36.0, 33.0), Vector3(2.6, 1.2, 1.1), "TomatoCratesPlazaEast"))
	boxes.push_back(metre_box(Vector2(30.0, 27.0), Vector3(2.6, 1.2, 1.1), "TomatoCratesPlazaCentre"))
	_wrecked_truck(boxes, "Plaza", Vector2(34.5, 34.5), Vector2(35.9, 34.5),
		Vector2(34.5, 33.5), Vector2(33.2, 33.9))
	_add_festival_aftermath(boxes)
	return boxes


static func _add_festival_aftermath(boxes: Array[Dictionary]) -> void:
	var occupied := boxes.duplicate()
	occupied.append_array(parked_trucks())
	occupied.push_back(fire_truck_box())
	var taken := _box_cells(occupied)
	_ensure_layout()
	for leg in AFTERMATH_STOPS.size():
		var stops: Array = AFTERMATH_STOPS[leg]
		for index in stops.size():
			var fraction: float = stops[index]
			var pose := _route_pose(leg, fraction)
			var kind := (index + leg * 3) % AFTERMATH_MODELS.size()
			var side := 1.0 if (index + leg) % 2 == 0 else -1.0
			var tangent := pose[1]
			var shoulder := 1.55 if _road_radius(leg, fraction) >= 2.4 else 1.32
			for offset: float in [side * shoulder, -side * shoulder, side * 0.96, -side * 0.96]:
				var centre := pose[0] + tangent.orthogonal() * offset * (_road_radius(leg, fraction) / 2.45)
				var facing := _aftermath_facing(tangent, kind)
				if _try_add_aftermath(boxes, taken, centre, facing, leg, kind):
					break
	for entry in [[Vector2(24.3, 35.0), 0], [Vector2(37.1, 31.0), 1], [Vector2(34.7, 25.9), 2]]:
		_try_add_aftermath(boxes, taken, entry[0], Vector3.BACK, 3, int(entry[1]))


static func _aftermath_facing(tangent: Vector2, kind: int) -> Vector3:
	# Carts run lengthwise with the street. The other meshes are wider along X.
	var heading := tangent if kind == 1 else tangent.orthogonal()
	if absf(heading.x) > absf(heading.y):
		return Vector3.RIGHT * signf(heading.x)
	return Vector3.BACK * signf(heading.y)


static func _try_add_aftermath(boxes: Array[Dictionary], taken: Dictionary,
		centre: Vector2, facing: Vector3, leg: int, kind: int) -> bool:
	var model: Array = AFTERMATH_MODELS[kind]
	var size: Vector3 = model[1]
	if absf(facing.x) > 0.5:
		size = Vector3(size.z, size.y, size.x)
	var box := metre_box(centre, size, model[0], RUBBLE)
	var footprint := _box_cells([box] as Array[Dictionary])
	for cell: Vector2i in footprint:
		if taken.has(cell) or _floor_legs.get(cell, -1) != leg or START_PLAZA.has_point(cell) \
				or CAPRESE_RESCUE_BAY.has_point(cell):
			return false
	if not _leaves_aftermath_passage(footprint, taken):
		return false
	for cell: Vector2i in footprint:
		taken[cell] = true
	box["aftermath"] = true
	box["facing"] = facing
	boxes.push_back(box)
	return true


## Reject a piece if it isolates even a pocket behind it. A short walk
## around its footprint must connect every neighbouring street tile.
static func _leaves_aftermath_passage(footprint: Dictionary, taken: Dictionary) -> bool:
	const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var neighbours := {}
	var area := Rect2i()
	for cell: Vector2i in footprint:
		var tile := Rect2i(cell, Vector2i.ONE)
		area = area.merge(tile) if area.has_area() else tile
		for step: Vector2i in STEPS:
			var next := cell + step
			if _floor_legs.has(next) and not footprint.has(next) and not taken.has(next):
				neighbours[next] = true
	if neighbours.is_empty():
		return false
	area = area.grow(4)
	var first: Vector2i = neighbours.keys()[0]
	var frontier: Array[Vector2i] = [first]
	var visited := {first: true}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		neighbours.erase(cell)
		if neighbours.is_empty():
			return true
		for step: Vector2i in STEPS:
			var next := cell + step
			if area.has_point(next) and _floor_legs.has(next) and not footprint.has(next) \
					and not taken.has(next) and not visited.has(next):
				visited[next] = true
				frontier.push_back(next)
	return false


static func is_refill_crate(box: Dictionary) -> bool:
	var name: String = box["name"]
	return name.begins_with("TomatoCrate") or name.ends_with("WreckCrate")


static func is_supply_prop(box: Dictionary) -> bool:
	var name: String = box["name"]
	return name == "LoadedTomatoTruck" or name == "OverturnedTomatoTruck" or is_refill_crate(box)


static func _add_supply_crate(boxes: Array[Dictionary], at: Vector2) -> void:
	boxes.push_back(metre_box(at, Vector3(2.2, 1.2, 1.15),
		"TomatoCratesSupply%02d" % boxes.size(), Color("8c7a4a")))


static func _alley_side(leg: int, fraction: float, offset: float) -> Vector2:
	var pose := _route_pose(leg, fraction)
	return pose[0] + pose[1].orthogonal() * offset * (_road_radius(leg, fraction) / 2.45)


static func _cargo_truck(at: Vector2, direction: Vector2, overturned: bool) -> Dictionary:
	var along_x := absf(direction.x) > absf(direction.y)
	var length := 7.7 if overturned else 7.3
	var width := 3.5 if overturned else 3.0
	var size := Vector3(length, 2.9, width) if along_x else Vector3(width, 2.9, length)
	var name := "OverturnedTomatoTruck" if overturned else "LoadedTomatoTruck"
	var box := metre_box(at, size, name, STEEL)
	box["facing"] = Vector3.RIGHT * signf(direction.x) if along_x else Vector3.BACK * signf(direction.y)
	return box


const RUBBLE := Color("7d7368")
const STEEL := Color("5c6470")
const CANOPY := Color("c8b08a")


## A building's corner down: a big chunk at `heap`, a piece of facade on its
## edge at `facade`, a flat slab at `slab` that is jumped, and a small chunk
## beside the big one.
static func _rubble(boxes: Array[Dictionary], label: String, heap: Vector2,
		facade: Vector2, slab: Vector2) -> void:
	boxes.push_back(metre_box(heap, Vector3(3.0, 2.0, 2.4), label + "RubbleHeap", RUBBLE))
	boxes.push_back(metre_box(heap + Vector2(0.45, 0.35), Vector3(1.4, 0.9, 1.2),
		label + "RubbleChunk", RUBBLE))
	boxes.push_back(metre_box(facade, Vector3(0.6, 2.6, 3.4), label + "Facade", RUBBLE))
	var low := metre_box(slab, Vector3(3.4, 0.4, 2.0), label + "Slab", RUBBLE)
	low["jumpable"] = true
	boxes.push_back(low)


## A food truck that will not be serving again: the body, the cab, the
## canopy lying flat beside it (jumped), and a crate that fell out. The body
## runs north-south unless the cab is beside it rather than ahead of it.
static func _wrecked_truck(boxes: Array[Dictionary], label: String, body: Vector2,
		cab: Vector2, canopy: Vector2, crate: Vector2) -> void:
	var along_x := absf(cab.x - body.x) > absf(cab.y - body.y)
	var body_size := Vector3(5.6, 2.4, 2.6) if along_x else Vector3(2.6, 2.4, 5.6)
	var cab_size := Vector3(1.6, 1.8, 2.6) if along_x else Vector3(2.6, 1.8, 1.6)
	boxes.push_back(metre_box(body, body_size, label + "WreckBody", STEEL))
	boxes.push_back(metre_box(cab, cab_size, label + "WreckCab", STEEL))
	var cloth := metre_box(canopy, Vector3(3.0, 0.35, 2.4), label + "WreckCanopy", CANOPY)
	cloth["jumpable"] = true
	boxes.push_back(cloth)
	boxes.push_back(metre_box(crate, Vector3(1.0, 0.9, 1.0), label + "WreckCrate", Color("8c7a4a")))


static func parked_trucks() -> Array[Dictionary]:
	var side := Vector3(3.0, 3.2, 6.4)
	var end := Vector3(6.4, 3.2, 3.0)
	var boxes: Array[Dictionary] = []
	var start_row := float(START_PLAZA.position.y) + 2.5
	boxes.push_back(_truck_against_wall(Vector2(34.0, start_row + 1.0), Vector3.LEFT, side, true))
	boxes.push_back(_truck_against_wall(Vector2(26.0, start_row), Vector3.RIGHT, side))
	var stops := [
		[Vector2(0.32, 1), Vector2(0.54, 1), Vector2(0.65, -1)],
		[Vector2(0.23, -1), Vector2(0.32, 1), Vector2(0.56, 1), Vector2(0.65, -1), Vector2(0.91, -1)],
		[Vector2(0.32, 1), Vector2(0.42, -1), Vector2(0.65, -1), Vector2(0.77, -1)],
		[Vector2(0.32, 1), Vector2(0.48, 1), Vector2(0.65, -1), Vector2(0.78, 1)],
	]
	for leg in stops.size():
		for stop: Vector2 in stops[leg]:
			var pose := _route_pose(leg, stop.x)
			var normal := pose[1].orthogonal() * stop.y
			var edge := pose[0] + normal * (_road_radius(leg, stop.x) - 0.37)
			if absf(normal.x) > absf(normal.y):
				boxes.push_back(_truck_against_wall(edge, Vector3.LEFT * signf(normal.x), side))
			else:
				boxes.push_back(_truck_against_wall(edge, Vector3.FORWARD * signf(normal.y), end))
	boxes.push_back(_truck_against_wall(Vector2(26.0, 39.5), Vector3.RIGHT, side))
	# Park a loaded truck at the plaza's eastern edge.
	boxes.push_back(_truck_against_wall(Vector2(20.0, 24.5), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(20.0, 29.0), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(20.0, 31.5), Vector3.RIGHT, side))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 27.15), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 29.0), Vector3.LEFT, side, true))
	boxes.push_back(_truck_against_wall(Vector2(40.0, 34.0), Vector3.LEFT, side))
	boxes.push_back(_truck_against_wall(Vector2(36.0, 22.0), Vector3.BACK, end))
	return boxes


## A truck parked with its back on the wall face at `wall_cell` (a whole cell
## coordinate along the axis it backs onto) and its front out into the street.
static func _truck_against_wall(wall_cell: Vector2, facing: Vector3, size: Vector3,
		loaded := false) -> Dictionary:
	var face := at_cell(wall_cell)
	var depth: float = size.x if absf(facing.x) > 0.5 else size.z
	var position := face + facing * (depth * 0.5)
	position.y = size.y * 0.5
	var footprint := size
	# The open cargo bed runs parallel to the curb and is visible from the road.
	var direction := facing.cross(Vector3.UP) if loaded else facing
	if not loaded and absf(facing.x) > 0.5:
		footprint = Vector3(size.z, size.y, size.x)
	return {"position": position, "size": footprint, "facing": direction,
		"name": "LoadedTomatoTruck" if loaded else "ParkedVan", "color": STEEL}


## The fire truck itself, parked at the back of its bay.
static func fire_truck_box() -> Dictionary:
	return metre_box(Vector2(30.0, 24.0), Vector3(5.5, 4.2, 14.0), "FireTruck", Color("c4231d"))


# --- the floor ----------------------------------------------------------------

## Clip the starting juice to the curved streets. Ragged tile edges and an
## oval plaza stain keep the old straight-sided blocks out of the artwork.
static func seed_floor(floor_body: FloorContamination) -> void:
	_ensure_layout()
	for cell: Vector2i in _floor_legs:
		if _floor_legs[cell] < 0:
			continue
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		var dirt := posmod((cell.x * 31) ^ (cell.y * 73), 17)
		var oval := (point - Vector2(30.0, 29.5)) / Vector2(5.9, 4.7)
		var juicy := oval.length_squared() < 0.84 + float(dirt) * 0.018
		for zone in JUICE_ZONES:
			if zone.has_point(cell) and (dirt > 2):
				juicy = true
				break
		if juicy:
			var shift := Vector2(float(dirt % 5 - 2), float(dirt % 3 - 1)) * 0.095
			var spread := Vector2(0.54 + float(dirt % 4) * 0.043, 0.49 + float(dirt % 5) * 0.05)
			for row in 14:
				var top := float(row) / 14.0
				var bottom := float(row + 1) / 14.0
				var t := ((top + bottom) * 0.5 - 0.5 - shift.y) / spread.y
				if absf(t) >= 1.0:
					continue
				var radius := spread.x * sqrt(1.0 - t * t)
				var centre := 0.5 + shift.x + sin(t * 4.0 + float(dirt)) * 0.065
				var low := at_cell(Vector2(cell) + Vector2(maxf(0.0, centre - radius), top))
				var high := at_cell(Vector2(cell) + Vector2(minf(1.0, centre + radius), bottom))
				floor_body.fill_rect(low, high, 1, ContaminationGrid.KIND_KETCHUP)
