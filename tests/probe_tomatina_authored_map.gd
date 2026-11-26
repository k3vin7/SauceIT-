extends SceneTree

## Run tools/bake_tomatina_map.gd first to compare a fresh bake with the stage layout.
const BAKED_SCENE := "res://.godot/tomatina_map_bake/tomatina_map_editable.tscn"

var _failed := false


func _initialize() -> void:
	if not ResourceLoader.exists(BAKED_SCENE, "PackedScene"):
		push_error("Run tools/bake_tomatina_map.gd with its default output before testing parity")
		quit(1)
		return
	TomatinaMap.use_authored(null)
	var floor_a := TomatinaMap.floor_cells()
	var bounds_a := TomatinaMap.bounds()
	var debris_a := TomatinaMap.debris_boxes()
	var parked_a := TomatinaMap.parked_trucks()
	var truck_a := TomatinaMap.fire_truck_box()
	var roster_a := TomatinaMap.roster()
	var blocked_a := TomatinaMap.blocked_cells()
	var entrance_cells := TomatinaMap._box_cells(TomatinaMap.entrance_obstacles())
	var gate_a := TomatinaMap.market_gate_cells()
	var rooms_a := TomatinaMap.safe_rooms().duplicate()
	var spawn_a := TomatinaMap.spawn_position(2)
	var arrow_a := TomatinaMap.start_arrow()
	var pose_a := TomatinaMap._route_pose(1, 0.37)
	StreetMap.layout_override = TomatinaMap.new()
	var walls_a := TomatinaMap.boundary_boxes()
	var victims_a := TomatinaVillageArt.victim_placements()

	var data := TomatinaAuthoredMap.from_scene(load(BAKED_SCENE))
	TomatinaMap.use_authored(data)
	_check(TomatinaMap.floor_cells() == floor_a, "floor cells")
	_check(TomatinaMap.bounds() == bounds_a, "bounds")
	_check(_sorted(TomatinaMap.debris_boxes()) == _sorted(debris_a), "debris boxes")
	_check(_sorted(TomatinaMap.parked_trucks()) == _sorted(parked_a), "parked trucks")
	_check(_key(TomatinaMap.fire_truck_box()) == _key(truck_a), "fire truck")
	_check(TomatinaMap.entrance_obstacles().is_empty(), "preview entrance")
	_check(TomatinaMap.blocked_cells().merged(entrance_cells) == blocked_a, "blocked cells with the runtime entrance")
	_check(TomatinaMap.market_gate_cells() == gate_a, "market gate cells")
	_check(TomatinaMap.safe_rooms() == rooms_a, "safe rooms")
	_check(TomatinaMap.spawn_position(2).is_equal_approx(spawn_a), "spawn")
	_check(TomatinaMap.start_arrow().is_equal_approx(arrow_a), "start arrow")
	_check(_sorted(TomatinaMap.boundary_boxes().map(_named)) == _sorted(walls_a.map(_named)), "walls")
	var victims_b := TomatinaVillageArt.victim_placements()
	var same_victims := victims_a.size() == victims_b.size()
	for index in mini(victims_a.size(), victims_b.size()):
		same_victims = same_victims and victims_a[index].model == victims_b[index].model \
			and (victims_a[index].at as Vector3).distance_to(victims_b[index].at) < 0.001 \
			and (victims_a[index].facing as Vector3).distance_to(victims_b[index].facing) < 0.001
	_check(same_victims, "victims")
	var pose_b := TomatinaMap._route_pose(1, 0.37)
	_check(pose_b[0].distance_to(pose_a[0]) < 0.001, "route pose")
	var roster_b := TomatinaMap.roster()
	var same_roster := roster_b.size() == roster_a.size()
	for index in mini(roster_a.size(), roster_b.size()):
		same_roster = same_roster and roster_a[index][0] == roster_b[index][0] \
			and (roster_a[index][1] as Vector2).distance_to(roster_b[index][1]) < 0.001 \
			and roster_a[index].slice(2) == roster_b[index].slice(2)
	_check(same_roster, "roster")
	TomatinaMap.use_authored(null)
	StreetMap.layout_override = null
	_check(TomatinaMap.floor_cells() == floor_a, "original restored")
	print("PROBE_TOMATINA_AUTHORED_MAP_OK" if not _failed else "PROBE_TOMATINA_AUTHORED_MAP_FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		push_error("mismatch: " + what)


func _key(box: Dictionary) -> String:
	var position: Vector3 = box["position"]
	var size: Vector3 = box["size"]
	return "%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%s|%s|%s|%s|%s" % [box["name"], position.x, position.y,
		position.z, size.x, size.y, size.z, str(box.get("facing", Vector3.ZERO).round()),
		box.get("jumpable", false), box.has("aftermath"), box.get("closed_passage", false),
		(box.get("color", Color.BLACK) as Color).to_html()]


func _named(box: Dictionary) -> Dictionary:
	var out := box.duplicate()
	out["name"] = "wall"
	return out


func _sorted(boxes: Array) -> Array:
	var keys := boxes.map(_key)
	keys.sort()
	return keys
