extends RefCounted

## Distances and heights in metres, measured along existing streets. The cross
## slope tapers beyond the frontages; none of these profiles adds a road cell.
const MARKET_APPROACH := Vector2(10.1, 166.2)
const MARKET_CREST := Vector2(18.7, 163.55)
const MARKET_BEND := Vector2(20.5, 163.0)
const MARKET_AMBUSH := Vector2(22.4, 163.8)
const MARKET_TRIP := Vector2(22.0, 162.35)
const CROSS_STREET_BOWLER := Vector2(32.1, 41.45)
const TERRACE_SPITTER := Vector2(25.65, 211.5)
const TERRACE_CURB := Vector2(25.0, 211.5)

const PROFILES := [
	[Vector2(26.0, 216.0), Vector2(29.2, 206.8), 14.0, 25.0,
		[Vector2(-14.0, 0.0), Vector2(5.0, 0.85), Vector2(25.0, 0.85), Vector2(45.0, 0.0)]],
	[MARKET_APPROACH, MARKET_BEND, 14.0, 27.0,
		[Vector2(3.0, 0.0), Vector2(32.0, 2.5), Vector2(43.0, 2.5), Vector2(52.0, 0.0)]],
	[Vector2(33.2, 77.2), Vector2(31.0, 66.1), 11.0, 20.0,
		[Vector2(-14.0, 0.0), Vector2(8.0, -0.85), Vector2(34.0, -0.85), Vector2(52.0, 0.0)]],
	[Vector2(29.8, 43.0), Vector2(30.0, 39.0), 13.0, 25.0,
		[Vector2(-22.0, 0.0), Vector2(-9.0, 0.9), Vector2(1.0, 0.9), Vector2(21.0, 0.0)]],
]


static func relief_bounds() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for profile in PROFILES:
		var start: Vector2 = profile[0]
		var end: Vector2 = profile[1]
		var direction := start.direction_to(end)
		var origin := (start - Vector2(StreetMap.ORIGIN_CELL)) * StreetMap.CELL
		var side := direction.orthogonal() * float(profile[3])
		var span: Array = profile[4]
		var first := origin + direction * float(span[0].x)
		var last := origin + direction * float(span[-1].x)
		var bounds := Rect2(first - side, Vector2.ZERO)
		result.append(bounds.expand(first + side).expand(last - side).expand(last + side))
	return result


static func height_at(at: Vector3) -> float:
	var cell := Vector2(at.x, at.z) / StreetMap.CELL + Vector2(StreetMap.ORIGIN_CELL)
	var height := 0.0
	for profile in PROFILES:
		var start: Vector2 = profile[0]
		var end: Vector2 = profile[1]
		var direction := start.direction_to(end)
		var offset := (cell - start) * StreetMap.CELL
		var along := offset.dot(direction)
		var span: Array = profile[4]
		if along <= span[0].x or along >= span[-1].x:
			continue
		var across := absf(offset.cross(direction))
		if across >= float(profile[3]):
			continue
		for index in range(1, span.size()):
			var next: Vector2 = span[index]
			if along <= next.x:
				var previous: Vector2 = span[index - 1]
				var level := lerpf(previous.y, next.y, smoothstep(previous.x, next.x, along))
				height += level * (1.0 - smoothstep(float(profile[2]), float(profile[3]), across))
				break
	return height
