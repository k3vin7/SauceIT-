extends SceneTree

func _initialize() -> void:
	var rows: Array = []
	for entry in TomatinaMap.roster():
		var at: Vector2 = entry[1]
		if TomatinaMap.PLAZA.has_point(Vector2i(at.floor())):
			continue
		var leg := TomatinaMap.encounter_at(Vector2i(at.floor()))
		var distance := INF
		if leg >= 0:
			var curve: PackedVector2Array = TomatinaMap._routes[leg]
			for index in range(1, curve.size()):
				distance = minf(distance, at.distance_to(Geometry2D.get_closest_point_to_segment(at, curve[index - 1], curve[index])))
		if distance > 3.25 or TomatinaMap.blocked_cells().has(Vector2i(at.floor())):
			rows.append({"kind": entry[0], "cell": str(at), "route_distance_cells": distance})
	print(JSON.stringify(rows, "  "))
	quit()
