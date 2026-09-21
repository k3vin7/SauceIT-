class_name StreetMap
extends RefCounted

## The tutorial street, traced off the Haapsalu "maitsete promenaad" map.
##
## The whole map lives on one lattice whose cell is exactly one person wide, so
## "the road is eight people wide" is the literal statement `ROAD_CELLS = 8`
## rather than a metre figure that drifts when the capsule changes. Every
## segment below is given in lattice cells, which is why the streets are all the
## same width by construction: each one is 8 cells across, and a junction is just
## two of them overlapping.
##
## Map pixels convert at `PX_PER_CELL`, which is how the stall anchors stay
## traceable back to the drawing -- they are the pixel positions of the numbered
## red markers, in the order they are numbered on it.
##
## What was traced, and what was not. The festival map is stylised: its streets
## are drawn a good deal narrower than eight people relative to its blocks, so
## tracing it at true proportions would need a map several times this one's area
## and a floor mask to match (see the note on the grid below). The **topology**
## is what is reproduced here -- Ehte across the top, Karja as the promenade
## down the middle, Saue crossing it, Kalda along the bottom, and the festival
## square with the stage and the tower hanging off Karja's east side -- with the
## streets opened out to the eight-person width the game is built around. The
## blocks between them are correspondingly thinner than on the drawing.

## How much bigger the street is than the lattice it was laid out on. The
## layout stays in whole cells whatever this is -- the scale is applied once,
## here, when a cell is turned into metres -- so the streets stay exactly as
## wide as each other and the junctions stay square.
##
## The stalls are deliberately NOT scaled by it: they are furniture at a fixed
## real size, and leaving them alone is what makes the street read as bigger
## rather than as the same street viewed closer.
const SCALE := 1.8

## One person wide, times the scale. The capsule is 0.64 m in radius, so the
## unscaled cell is its diameter and everything on the map is a whole number of
## people across.
const PERSON := 1.28
const CELL := PERSON * SCALE
const ROAD_CELLS := 8
const ROAD_WIDTH := CELL * ROAD_CELLS

## Tall enough that the square's far side is not visible over a street wall from
## anywhere a player can stand. Scaled with the rest: a wall that stayed put
## while the street grew would start showing what is behind it.
const WALL_HEIGHT := 7.0 * SCALE
## Walls are two cells deep so they read as building fronts rather than as
## cardboard: at one cell a corner shows its own thickness across the street.
const WALL_DEPTH_CELLS := 2

## Ten map pixels to the cell. Chosen so the whole promenade comes out about the
## size of the street it replaces rather than the four-times-larger one true
## proportions would need -- the floor is one grid and its cost goes with area.
const PX_PER_CELL := 10.0
## Lattice cell the start zone sits on: the bottom of the map, on Kalda tänav,
## so the promenade runs away north from where the player appears.
const ORIGIN_CELL := Vector2i(29, 93)

## Ground beyond the outermost wall, so the floor plane does not end in mid-air
## where a player can see the seam.
const FLOOR_MARGIN_CELLS := 4

## The streets, as lattice rectangles. Consecutive ones overlap rather than
## abut: the overlap *is* the junction, so no crossing needs a special case and
## the walls fall out of the union. Named for the street each one is.
const SEGMENTS: Array[Rect2i] = [
	Rect2i(2, 14, 64, 8),    # Ehte tänav, along the top
	Rect2i(23, 18, 8, 48),   # Karja tänav, the promenade
	Rect2i(30, 45, 15, 21),  # the festival square: the stage and the tower
	Rect2i(14, 60, 22, 8),   # Saue tänav, crossing the promenade
	Rect2i(25, 66, 8, 28),   # the run down from Saue to Kalda
	Rect2i(18, 89, 29, 8),   # Kalda tänav, along the bottom
]

## Which segment is the open square, for anything that wants somewhere with
## nothing in the way.
const SQUARE_SEGMENT := 2

## Round places, as centre cell and radius in cells. The map has one: the circle
## drawn where Karja tänav meets Ehte tänav, at the head of the promenade.
##
## It is a filled circle rather than a ring with an island in it, and that is
## read off the drawing rather than assumed. The circle there is about twice the
## width of the street running into it -- so at the drawing's own proportions a
## ring road around an island would leave an island of nothing. It is a place
## that happens to be round, not a roundabout, and the radius below keeps that
## same two-to-one against the street the game actually uses.
##
## Rectangles cannot express this, which is why it is a separate list: a circle
## approximated by stacked `Rect2i`s is a staircase that the wall merger then
## turns into a dozen boxes, and the edge you walk along is visibly square.
## Centred so its rim just meets Ehte tänav rather than on the pixel the
## drawing's circle sits at: the streets here are opened out to the eight-person
## width and the circle is sized to keep the drawing's two-to-one against them,
## so a circle placed at the original centre is swallowed whole by the widened
## Ehte and reads as a bulge rather than a round place. Tangent below it is what
## the drawing shows.
const CIRCLES := [
	[31, 31, 9],
]

## The numbered red markers, as their pixel position on the map. Unlike the
## hand-sketch version these carry no direction: which wall a stall backs onto
## is worked out from the streets themselves, because fifty-one of them is far
## too many to hand-label and a mislabelled one silently disappears.
const STALL_ANCHORS := [
	[299, 190], [340, 172], [400, 172], [452, 172], [500, 152], [535, 133],
	[492, 182], [543, 170], [508, 211], [433, 240], [367, 246], [345, 265],
	[293, 268], [301, 232],
	[259, 279], [249, 313], [281, 318], [269, 349], [267, 383], [240, 373],
	[238, 394],
	[285, 462], [252, 466], [248, 490], [283, 487], [245, 508], [307, 505],
	[311, 521], [243, 530], [293, 558], [259, 580],
	[322, 600], [330, 620], [338, 645], [305, 658],
	[266, 618], [267, 634],
	[265, 692], [272, 716], [298, 713], [268, 738], [292, 755], [296, 771],
	[298, 789], [307, 800], [290, 828], [317, 828], [327, 845], [347, 855],
	[302, 862], [216, 548],
]

## A stall is a 3 m x 3 m pop-up gazebo, which is the standard market pitch and
## what a festival like this one is actually made of: 3 x 3 m on the ground,
## 3.27 m to the peak, eaves about 2.2 m, and a serving counter at waist height.
##
## Those are real metres, and this world is not built in them -- its people are
## the prototype's 2.56 m capsule. A literal 3.27 m canopy over a 2.56 m player
## leaves 0.7 m of headroom and reads as a toy, so the real figures are scaled
## by the ratio between the capsule and the height it is meant to *be*. The
## numbers below stay the real ones, and the conversion is stated once.
##
## 1.80 m is the height the player is taken to be, so everything measured in
## real metres is 2.56/1.80 larger here than it is in the world.
const HUMAN_HEIGHT := 1.80
const CAPSULE_HEIGHT := 2.56
const HUMAN_SCALE := CAPSULE_HEIGHT / HUMAN_HEIGHT

const STALL_FOOTPRINT_M := 3.0
const STALL_PEAK_M := 3.27
const STALL_EAVES_M := 2.2
## Deliberately not 0.95, which is what a real serving counter is. The stall
## around it was scaled up so a 4.1 m enemy can walk under the canopy, and the
## counter came up with it -- to shoulder height on the player, which stops it
## being the thing it is for. Its height is a *relationship to the player*
## rather than a prop dimension, so it is the one figure here trimmed to hold
## that relationship: this lands it back at about two thirds of a player, which
## is cover you shoot over.
const STALL_COUNTER_HEIGHT_M := 0.82
const STALL_COUNTER_DEPTH_M := 0.7
const STALL_LEG_M := 0.08

## And then the bit that is not arithmetic. Game architecture is built larger
## than its real counterpart, because a camera with a fixed field of view makes
## a space read tighter than it measures and because a player who cannot judge
## depth needs room the real user of the space does not. There is no canonical
## multiplier for it -- the published guidance is all "build it, stand in it,
## and trust what it looks like" -- so this is a knob rather than a derivation.
##
## There is a concrete reason for it here beyond the feel. At 1.0 the canopy
## eaves sit 3.13 m up and the player is 2.56 m: 57 cm of headroom, which the
## over-the-shoulder camera cannot fit through. At 1.25 that is 1.35 m.
##
## It also lifts the serving counter from 53% of the player's height to 66% --
## waist-high to chest-high -- which changes what the counter is as cover. That
## is the number to watch when tuning this.
## Raised from 1.25 so the canopy clears an enemy. They are 4.10 m tall and the
## eaves were at 3.91 m, so they could not walk under a stall at all -- and the
## line-of-sight test could see under one, which is how they ended up walking
## into canopies they were never going to fit through.
const PROP_SCALE := 1.45

## The one conversion from real metres to this world's.
const STALL_SCALE := HUMAN_SCALE * PROP_SCALE

## Vendors that cook on the pitch get two gazebos rather than one -- the
## standard catering layout is one over the cooking and a second over the
## serving counter, which is why 3 x 6 m is a stock size alongside 3 x 3 m.
## Listed by the marker number on the drawing, so it reads against the legend:
## the food trucks, the grills and the burger and kebab stands.
const DOUBLE_BAY_MARKERS := [2, 7, 13, 19, 20, 21, 23, 25, 27, 37, 50]

## How many 3 m bays the stall at this marker has. Markers are numbered from 1
## on the drawing; the anchor list is indexed from 0.
static func bays_for_marker(index: int) -> int:
	return 2 if DOUBLE_BAY_MARKERS.has(index + 1) else 1

## Fixed metres, not cells: a stall is the size a stall is, and it does not grow
## when the street does. The height here is the peak, which is what the placement
## maths wants; the parts are built from the figures above.
const STALL_SIZE := Vector3(
	STALL_FOOTPRINT_M * STALL_SCALE,
	STALL_PEAK_M * STALL_SCALE,
	STALL_FOOTPRINT_M * STALL_SCALE)


static func stall_metre(real_metres: float) -> float:
	return real_metres * STALL_SCALE

## Two machines kept off the promenade. They hand nothing out -- the sauce comes
## from the stalls -- but `MayoEnemy` is sized as a multiple of one, so the size
## below is load-bearing even where the props are not.
const VENDING_ANCHORS := [
	[470, 190, 0, -1],
	[210, 640, 0, -1],
]

const VENDING_SIZE := Vector3(1.15, 2.05, 0.82)

## LAVA on the map: the festival stage, in the square. A platform rather than a
## wall -- it is a thing to stand on and spray off, and the square is the one
## place with room for it.
const STAGE_PIXELS := Vector2(357, 537)
const STAGE_SIZE := Vector3(9.0, 1.1, 7.0)

## Kodanike torn -- the Citizens' Tower. The one landmark tall enough to steer
## by from the far end of the promenade, which is what it is here for.
const TOWER_PIXELS := Vector2(400, 585)
const TOWER_RADIUS := 3.2
const TOWER_HEIGHT := 26.0


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
	for circle in CIRCLES:
		var centre := Vector2i(circle[0], circle[1])
		var radius: int = circle[2]
		# Measured to the cell's middle, so the rim comes out as round as a
		# lattice this size can make it rather than a cell prouder on the axes.
		for j in range(centre.y - radius, centre.y + radius + 1):
			for i in range(centre.x - radius, centre.x + radius + 1):
				var offset := Vector2(float(i - centre.x), float(j - centre.y))
				if offset.length() <= float(radius) + 0.5:
					cells[Vector2i(i, j)] = true
	return cells


static func bounds() -> Rect2i:
	var rect := SEGMENTS[0]
	for i in range(1, SEGMENTS.size()):
		rect = rect.merge(SEGMENTS[i])
	for circle in CIRCLES:
		var radius: int = circle[2]
		rect = rect.merge(Rect2i(
			circle[0] - radius, circle[1] - radius, radius * 2 + 1, radius * 2 + 1))
	return rect


## Centre of the round place at the head of the promenade, in world space.
static func circle_centre(index := 0) -> Vector3:
	var circle: Array = CIRCLES[index]
	return cell_corner(Vector2i(circle[0], circle[1])) + Vector3(CELL * 0.5, 0.0, CELL * 0.5)


static func circle_radius(index := 0) -> float:
	return float(CIRCLES[index][2]) * CELL


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


## Centre of the festival square. It is the widest open space on the map, which
## is what a strand test wants when it needs nothing in the way: the square is
## comfortably wider than the stream's range in both directions, and a street is
## not. Kept under the old name because the probes that want open ground ask for
## it by that name.
static func arena_centre() -> Vector3:
	var rect: Rect2i = SEGMENTS[SQUARE_SEGMENT]
	return cell_corner(rect.position) + Vector3(
		float(rect.size.x) * CELL * 0.5, 0.0, float(rect.size.y) * CELL * 0.5)


## Where the stage stands, on the ground.
static func stage_position() -> Vector3:
	return from_pixels(STAGE_PIXELS.x, STAGE_PIXELS.y)


## Where the tower stands, on the ground.
static func tower_position() -> Vector3:
	return from_pixels(TOWER_PIXELS.x, TOWER_PIXELS.y)


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


## The counter's own box, given a stall's. The counter is the only part of a
## stall at ground level: the canopy is overhead and the legs are thin. Shared
## by the thing that builds it and the thing that routes around it, so the two
## cannot come to different conclusions about where it is.
static func counter_box(stall: Dictionary) -> Dictionary:
	var size: Vector3 = stall["size"]
	var facing: Vector3 = stall["facing"]
	var deep := stall_metre(STALL_COUNTER_DEPTH_M)
	# Depth runs along the facing, frontage runs across it. Getting these two
	# the wrong way round is the bug this function exists to stop happening
	# twice: on a single bay they are the same number and nothing shows.
	var wide: float = size.z if absf(facing.x) > 0.5 else size.x
	var span: float = size.x if absf(facing.x) > 0.5 else size.z
	return {
		"position": stall["position"] + facing * (span - deep) * 0.5,
		"size": Vector3(deep, stall_metre(STALL_COUNTER_HEIGHT_M), wide) \
			if absf(facing.x) > 0.5 else Vector3(wide, stall_metre(STALL_COUNTER_HEIGHT_M), deep),
		"facing": facing,
	}


## Street cells something is standing on. The stalls back onto the walls but
## their footprints sit on the road, so anything walking the map has to treat
## them as wall -- which is the whole reason an enemy needs a route rather than
## a direction.
static func blocked_cells() -> Dictionary:
	var blocked := {}
	# The stage and the tower stand on the street too. Leaving them out is how
	# an enemy routed straight through the tower and then leaned on it: the
	# router has to know about everything standing on the road, not just the
	# things that came from the marker list.
	# Only the **counter** of a stall blocks the ground. The canopy is overhead
	# and now high enough for an enemy to walk under, and the legs are a hand
	# wide -- shutting the whole footprint made every stall a pillar and turned
	# a third of the street into wall.
	var props: Array[Dictionary] = []
	for stall in stall_boxes():
		props.push_back(counter_box(stall))
	props.append_array(vending_boxes())
	props.push_back({"position": stage_position(), "size": STAGE_SIZE})
	props.push_back({
		"position": tower_position(),
		"size": Vector3(TOWER_RADIUS * 2.0, TOWER_HEIGHT, TOWER_RADIUS * 2.0),
	})
	for box in props:
		var position: Vector3 = box["position"]
		var size: Vector3 = box["size"]
		var first := Vector2i(
			int(floor((position.x - size.x * 0.5) / CELL)) + ORIGIN_CELL.x,
			int(floor((position.z - size.z * 0.5) / CELL)) + ORIGIN_CELL.y)
		var last := Vector2i(
			int(floor((position.x + size.x * 0.5 - 0.001) / CELL)) + ORIGIN_CELL.x,
			int(floor((position.z + size.z * 0.5 - 0.001) / CELL)) + ORIGIN_CELL.y)
		for j in range(first.y, last.y + 1):
			for i in range(first.x, last.x + 1):
				blocked[Vector2i(i, j)] = true
	return blocked


## Cells a body may walk on: street, less whatever is standing on it.
static func walkable_cells() -> Dictionary:
	var cells := floor_cells()
	for cell in blocked_cells():
		cells.erase(cell)
	return cells


## Middle of a cell, on the ground.
static func cell_middle(cell: Vector2i) -> Vector3:
	return cell_corner(cell) + Vector3(CELL * 0.5, 0.0, CELL * 0.5)


## Which cell a world position is in.
static func cell_at(world_position: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / CELL)) + ORIGIN_CELL.x,
		int(floor(world_position.z / CELL)) + ORIGIN_CELL.y)


static func stall_boxes() -> Array[Dictionary]:
	return _anchored_boxes(STALL_ANCHORS, STALL_SIZE)


static func vending_boxes() -> Array[Dictionary]:
	return _anchored_boxes(VENDING_ANCHORS, VENDING_SIZE)


## Places one box per anchor with its back flat against a wall and its front
## onto the street.
##
## Two things are worked out rather than declared, because fifty-one hand-made
## entries is fifty-one chances to be quietly wrong. **Which cell** it stands on:
## the traced pixel is only roughly where the marker sits, and markers on the
## drawing sit on the buildings as often as on the road, so the anchor is snapped
## to the nearest street cell. **Which way it faces**: the nearest wall from that
## cell is the one it backs onto. A mislabelled direction used to make a stall
## vanish without a word; there is no label to get wrong now.
##
## Every marker on the drawing is a food or drink stall, so every one of them
## gets a stall. Where two would stand on the same cells -- the markers cluster
## more tightly than a stall's frontage allows, and two boxes in one place read
## as one broken one -- the second slides along its wall to the nearest free
## frontage rather than being dropped. Sliding rather than dropping is the whole
## reason a vendor cannot go missing without anyone noticing.
static func _anchored_boxes(anchors: Array, size_in: Vector3) -> Array[Dictionary]:
	var floor_set := floor_cells()
	var taken := {}
	var boxes: Array[Dictionary] = []
	var is_stalls := anchors == STALL_ANCHORS
	for marker in anchors.size():
		var anchor: Array = anchors[marker]
		# A two-bay vendor needs twice the frontage, and needs it reserved
		# before anything else claims the cell next door.
		var bays := bays_for_marker(marker) if is_stalls else 1
		var size := Vector3(size_in.x * float(bays), size_in.y, size_in.z)
		var px: float = anchor[0]
		var py: float = anchor[1]
		var cell := _nearest_street(floor_set, cell_of_pixels(px, py))
		if cell.x == INVALID.x and cell.y == INVALID.y:
			continue
		# A direction may be given -- the vending machines still carry one --
		# and is used as the wall to back onto when it is.
		var dir: Vector2i = Vector2i(anchor[2], anchor[3]) if anchor.size() >= 4 \
			else _wall_direction(floor_set, cell)
		if dir == Vector2i.ZERO:
			continue
		while floor_set.has(cell + dir):
			cell += dir

		var footprint := Vector3(
			size.z if dir.x != 0 else size.x,
			size.y,
			size.z if dir.y != 0 else size.x)
		var spot := _free_frontage(floor_set, taken, cell, dir, footprint)
		if spot.is_empty() and bays > 1:
			# A double needs five cells of unbroken wall and some pitches do not
			# have them -- a short frontage, or the round place, whose rim turns
			# a corner every couple of cells. The vendor is still on the drawing,
			# so it gets one tent rather than none.
			bays = 1
			size = Vector3(size_in.x, size_in.y, size_in.z)
			footprint = Vector3(
				size.z if dir.x != 0 else size.x,
				size.y,
				size.z if dir.y != 0 else size.x)
			spot = _free_frontage(floor_set, taken, cell, dir, footprint)
		if spot.is_empty():
			continue
		cell = spot["cell"]
		dir = spot["dir"]
		footprint = Vector3(
			size.z if dir.x != 0 else size.x,
			size.y,
			size.z if dir.y != 0 else size.x)

		# Far edge of the last street cell, along dir: the wall face.
		var corner := cell_corner(cell)
		var wall_face := corner + Vector3(
			CELL if dir.x > 0 else 0.0,
			0.0,
			CELL if dir.y > 0 else 0.0)
		var facing := Vector3(float(dir.x), 0.0, float(dir.y))
		# Along the wall the stall is centred on the cell it ended up in, so two
		# neighbours line up with each other instead of with the traced pixels.
		var along := corner + Vector3(CELL * 0.5, 0.0, CELL * 0.5)
		var centre := Vector3(
			wall_face.x if dir.x != 0 else along.x,
			size.y * 0.5,
			wall_face.z if dir.y != 0 else along.z)
		centre -= facing * (footprint.x if dir.x != 0 else footprint.z) * 0.5
		boxes.push_back({
			"position": centre,
			"size": footprint,
			"facing": -facing,
			"bays": bays,
		})
	return boxes


const INVALID := Vector2i(-99999, -99999)


## The street cell nearest this one, or INVALID if the map has no streets at all.
static func _nearest_street(floor_set: Dictionary, cell: Vector2i) -> Vector2i:
	if floor_set.has(cell):
		return cell
	var best := INVALID
	var best_distance := INF
	for candidate in floor_set:
		var offset := Vector2(candidate - cell)
		var distance := offset.length_squared()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Which way the nearest wall lies from this street cell. Walks each of the four
## directions until the street runs out; the shortest walk wins, so a stall on a
## narrow street backs onto its near side rather than crossing it.
static func _wall_direction(floor_set: Dictionary, cell: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_distance := 1 << 30
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i(0, -1), Vector2i(0, 1)]:
		var distance := 0
		var probe := cell
		while floor_set.has(probe) and distance <= ROAD_CELLS * 4:
			probe += step
			distance += 1
		if distance < best_distance:
			best_distance = distance
			best = step
	return best


## The nearest spot to `cell` that is against a wall with room for this stall,
## as {cell, dir}. Empty if there is none within reach.
##
## A breadth-first walk over street cells rather than a march along the wall.
## Marching only reaches what lies on the two axes from where it started, so a
## stall whose own wall is full could not cross the street to the other side, or
## round a corner, and the last couple of markers on a crowded stretch had
## nowhere to go. Spreading outwards finds the genuinely nearest free frontage,
## whichever wall it belongs to, and the wall is re-derived at each candidate so
## a stall that ends up on the far side faces back across the street correctly.
static func _free_frontage(floor_set: Dictionary, taken: Dictionary, cell: Vector2i,
		dir: Vector2i, footprint: Vector3) -> Dictionary:
	# Ceil, not round: a stall claims every cell its frontage actually covers,
	# or neighbours end up spaced closer than they are wide and their meshes
	# grow through each other.
	var span: float = footprint.x if dir.y != 0 else footprint.z
	var frontage := int(ceil(span / CELL - 0.001))
	var seen := {cell: true}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	while head < queue.size() and head < 4096:
		var here: Vector2i = queue[head]
		head += 1
		var wall := dir if here == cell else _wall_direction(floor_set, here)
		if wall != Vector2i.ZERO and not floor_set.has(here + wall):
			var across := Vector2i(1, 0) if wall.y != 0 else Vector2i(0, 1)
			if _claim(taken, here, across, frontage):
				return {"cell": here, "dir": wall}
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i(0, -1), Vector2i(0, 1)]:
			var next: Vector2i = here + step
			if floor_set.has(next) and not seen.has(next):
				seen[next] = true
				queue.push_back(next)
	return {}


## Marks the cells a stall of this frontage would stand on, or reports the spot
## already taken.
static func _claim(taken: Dictionary, cell: Vector2i, across: Vector2i, frontage: int) -> bool:
	var half := frontage / 2
	for step in range(-half, frontage - half):
		if taken.has(cell + across * step):
			return false
	for step in range(-half, frontage - half):
		taken[cell + across * step] = true
	return true


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
