extends SceneTree

func _initialize() -> void:
	var changes: Array = []
	var roster := TomatinaMap.roster(changes)
	assert(roster == TomatinaMap.roster(), "roster differs between peers")
	var occupied := {}
	var ambushes := {}
	var props := TomatinaMap.debris_boxes()
	props.append_array(TomatinaMap.parked_trucks())
	props.append(TomatinaMap.fire_truck_box())
	var blocked := TomatinaMap._box_cells(props)
	blocked.merge(TomatinaMap.market_gate_cells())
	for entry in roster:
		var at: Vector2 = entry[1]
		var cell := Vector2i(at.floor())
		assert(not occupied.has(cell), "overlapping enemy spawns")
		assert(not blocked.has(cell), "enemy inside prop")
		assert(TomatinaMap.safe_room_at(cell) < 0, "enemy in safe room")
		assert(TomatinaMap.floor_cells().has(cell), "enemy outside floor")
		occupied[cell] = true
		if not TomatinaMap.PLAZA.has_point(cell):
			assert(TomatinaMap.route_distance(at, TomatinaMap.encounter_at(cell)) <= TomatinaMap.ROSTER_ROUTE_REACH)
		if entry.size() > 2 and entry[2] is int:
			ambushes[entry[2]] = int(ambushes.get(entry[2], 0)) + 1
	for group in TomatinaMap.ALLEY_AMBUSHES.size():
		assert(ambushes.get(group, 0) == 3, "lost intentional ambush")
	assert(TomatinaMap.ALLEY_AMBUSHES.is_empty() and TomatinaMap.ALLEY_REINFORCEMENTS.is_empty(),
		"closed passages still define hidden enemy packs")
	var removed := 0
	for change in changes:
		if change.get("removed", false):
			removed += 1
	var report := {"total": roster.size(), "relocated": changes.size() - removed, "removed": removed, "changes": changes}
	var file := FileAccess.open("res://reports/tomatina_roster_cleanup.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TOMATINA_ROSTER_OK total=%d relocated=%d removed=%d" % [roster.size(), changes.size() - removed, removed])
	quit()
