class_name StreetNav
extends RefCounted

## Routes across the street, for anything that has to get somewhere it cannot
## see.
##
## The enemies used to walk at the player along the straight line between them,
## which works until a wall is on that line -- and then they lean on it. The map
## is already a lattice of walkable cells, so there is no need to infer its shape
## with feeler rays and no need to bake a navigation mesh over geometry that was
## generated from that lattice in the first place: `AStarGrid2D` runs on the
## cells directly, and what comes back is a real route round the corner rather
## than a guess that gets stuck in one.
##
## Feeler rays still earn their keep, just not for finding the way. A route made
## of cells hugs the middle of them, which reads as an enemy walking a staircase
## down an open street, so `is_clear` lets a chaser skip the route entirely while
## it can see where it is going. See `MayoEnemy.advance`.

var grid := AStarGrid2D.new()
var _region := Rect2i()


func build() -> void:
	_region = StreetMap.bounds().grow(2)
	grid.region = _region
	grid.cell_size = Vector2.ONE
	# Straight lines only. A diagonal step between two cells that share nothing
	# but a corner cuts that corner, and a body as wide as a cell clips the wall
	# on the way through.
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()

	var walkable := StreetMap.walkable_cells()
	for j in range(_region.position.y, _region.end.y):
		for i in range(_region.position.x, _region.end.x):
			var cell := Vector2i(i, j)
			grid.set_point_solid(cell, not walkable.has(cell))


func is_walkable(cell: Vector2i) -> bool:
	return _region.has_point(cell) and not grid.is_point_solid(cell)


## The nearest walkable cell to this one, so a body that has been shoved into a
## stall still has somewhere to route from. Rings outwards rather than scanning
## the map: whatever pushed it in is right next to it.
func nearest_walkable(cell: Vector2i) -> Vector2i:
	if is_walkable(cell):
		return cell
	for radius in range(1, 8):
		for j in range(-radius, radius + 1):
			for i in range(-radius, radius + 1):
				if maxi(absi(i), absi(j)) != radius:
					continue
				var probe := Vector2i(cell.x + i, cell.y + j)
				if is_walkable(probe):
					return probe
	return cell


## The route from one world position to another, as world points on the ground.
## Empty if there is no way through.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := nearest_walkable(StreetMap.cell_at(from))
	var goal := nearest_walkable(StreetMap.cell_at(to))
	var points := PackedVector3Array()
	if not is_walkable(start) or not is_walkable(goal):
		return points
	for cell in grid.get_id_path(start, goal):
		points.push_back(StreetMap.cell_middle(cell))
	return points
