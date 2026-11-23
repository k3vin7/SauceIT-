extends SceneTree

## 원래 코드로 만든 토마티나 맵(TomatinaMap + TomatinaVillageArt)을 그대로 노드 씬으로 굽는다.
##   <godot> --headless --path . --script res://tools/bake_tomatina_map.gd
## 결과: res://maps/tomatina_map_editable.tscn (+ 바닥 타일, 장식 줄 메시)
## 주의: 다시 실행하면 손으로 편집한 맵 씬을 덮어쓴다. 원래 맵 코드는 건드리지 않는다.

const OUT_SCENE := "res://maps/tomatina_map_editable.tscn"
const OUT_TILES := "res://maps/tomatina_floor_tiles.tres"
const OUT_BUNTING := "res://maps/tomatina_festival_bunting.res"
const TILE_NAMES := ["구간0 출발~급수마당", "구간1 급수마당~시장", "구간2 시장~축제본부",
	"구간3 축제본부~광장", "피난처 바닥"]
const TILE_COLORS := [Color("d98f4e"), Color("5b8fd9"), Color("a46ad1"), Color("d9c24e"), Color("4fbf86")]
## mayo_prototype._build_tomatina_route_signs 의 길 표지 글자.
const ROUTE_LABELS := [
	[Vector2(10.9, 166.0), "지름길 폐쇄 · 큰길 이용"],
	[Vector2(15.5, 164.8), "시장 큰길 · 볼러 주의"],
	[Vector2(28.0, 70.5), "큰길 · 광장 방면"],
]


func _initialize() -> void:
	TomatinaMap.use_authored(null)
	StreetMap.layout_override = TomatinaMap.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://maps"))
	ResourceSaver.save(_make_tiles(), OUT_TILES)
	var tiles: MeshLibrary = load(OUT_TILES)

	var root := TomatinaMapEditor.new()
	root.name = "TomatinaMap"

	# --- 바닥 칸 -------------------------------------------------------------
	var floor_map := GridMap.new()
	floor_map.name = "Floor"
	floor_map.mesh_library = tiles
	floor_map.cell_size = Vector3(StreetMap.CELL, 0.1, StreetMap.CELL)
	floor_map.cell_center_y = false
	floor_map.position = TomatinaMap.at_cell(Vector2.ZERO)
	var floor_legs := TomatinaMap.floor_cells()
	for cell: Vector2i in floor_legs:
		var leg: int = floor_legs[cell]
		floor_map.set_cell_item(Vector3i(cell.x, 0, cell.y), leg if leg >= 0 else 4)
	root.add_child(floor_map)

	# --- 벽 충돌 상자 ----------------------------------------------------------
	var walls := _folder(root, "Walls")
	TomatinaMapEditor.add_walls(walls, TomatinaMap.boundary_boxes())
	# 숨겨 둔다: 켜 두면 반투명 벽 상자가 집 앞을 가려서 집이 클릭되지 않는다.
	walls.visible = false

	# --- 경로 -------------------------------------------------------------------
	var routes := _folder(root, "Routes")
	var route_points := TomatinaMap.route_points()
	for leg in route_points.size():
		var path := Path3D.new()
		path.name = "Leg%d" % leg
		path.curve = Curve3D.new()
		for point: Vector2 in route_points[leg]:
			path.curve.add_point(TomatinaMap.at_cell(point) + Vector3.UP * 0.4)
		routes.add_child(path)

	# --- 피난처 -----------------------------------------------------------------
	var rooms := _folder(root, "SafeRooms")
	var room_nodes: Array[Node3D] = []
	var safe_rooms := TomatinaMap.safe_rooms()
	for index in safe_rooms.size():
		var rect: Rect2i = safe_rooms[index]
		var room := TomatinaMapRoom.new()
		room.name = "Room%d" % index
		room.room_name = TomatinaMap.safe_room_names()[index]
		room.size_cells = rect.size
		room.position = TomatinaMap.at_cell(Vector2(rect.position) + Vector2(rect.size) * 0.5)
		# 자식 모델(배너·샤워기)을 클릭해도 피난처 노드가 잡히게 묶는다.
		room.set_meta("_edit_group_", true)
		rooms.add_child(room)
		room_nodes.append(room)

	# --- 소품 ---------------------------------------------------------------------
	var props := _folder(root, "Props")
	var folders := {}
	var debris := TomatinaMap.debris_boxes()
	var parked_boxes := TomatinaMap.parked_trucks()
	var debris_nodes: Array[Node3D] = []
	var parked_nodes: Array[Node3D] = []
	var count := 0
	for box in debris:
		var folder_name := _category(box)
		if not folders.has(folder_name):
			folders[folder_name] = _folder(props, folder_name)
		var node := _prop(box, TomatinaMapProp.Group.DEBRIS, count)
		folders[folder_name].add_child(node)
		debris_nodes.append(node)
		count += 1
	var parked := _folder(props, "ParkedTrucks")
	for box in parked_boxes:
		var node := _prop(box, TomatinaMapProp.Group.PARKED_TRUCK, count)
		parked.add_child(node)
		parked_nodes.append(node)
		count += 1
	props.add_child(_prop(TomatinaMap.fire_truck_box(), TomatinaMapProp.Group.FIRE_TRUCK, count))

	# --- 마을 아트: 원래 빌드를 그대로 돌리고, 놓인 조각을 노드로 옮긴다 -----------------
	var art_root := _folder(root, "Art")
	var art := TomatinaVillageArt.new()
	if not art.load_kit():
		push_error("village kit did not load")
		quit(1)
		return
	art.recording = true
	var holder := Node3D.new()
	art.build(holder, debris, parked_boxes, TomatinaMap.fire_truck_box())
	var streets: Array = []
	var landmarks := _folder(art_root, "Landmarks")
	var counts := {}
	for entry: Array in art.recorded:
		var key: String = entry[0]
		var xf: Transform3D = entry[1]
		var tag: String = entry[2]
		if tag == "street" or tag == "backlot":
			streets.append(entry)
			continue
		var owner_node: Node3D = landmarks
		var parts := tag.split(":")
		match parts[0]:
			"debris":
				owner_node = debris_nodes[int(parts[1])]
			"parked":
				owner_node = parked_nodes[int(parts[1])]
			"room":
				owner_node = room_nodes[int(parts[1])]
		var number := int(counts.get(key, 0))
		counts[key] = number + 1
		# 소품·피난처 노드의 자식으로: 그 노드를 옮기면 모델도 따라간다.
		owner_node.add_child(TomatinaMapEditor.make_piece(key, owner_node.transform.affine_inverse() * xf,
			"Art_%s_%03d" % [key, number]))
	TomatinaMapEditor.add_street_pieces(_folder(art_root, "Streets"), streets)

	for child in holder.get_children():
		if child is MeshInstance3D and child.name == "FestivalBunting":
			ResourceSaver.save(child.mesh, OUT_BUNTING)
			child.mesh = load(OUT_BUNTING)
			holder.remove_child(child)
			art_root.add_child(child)
		elif child.is_in_group("tomatina_fire"):
			var brazier := _nearest_brazier(child.position, debris, debris_nodes)
			holder.remove_child(child)
			child.name = "Fire"
			child.remove_from_group("tomatina_fire")
			child.add_to_group("tomatina_fire", true)
			child.position = brazier.transform.affine_inverse() * child.position
			brazier.add_child(child)
	holder.free()

	var signs := _folder(art_root, "Signs")
	var waymark_holder := Node3D.new()
	TomatinaVillageArt.build_plaza_waymarks(waymark_holder)
	for child in waymark_holder.get_children():
		waymark_holder.remove_child(child)
		signs.add_child(child)
	var waymarks := signs.get_node("PlazaWaymarks")
	for index in waymarks.get_child_count():
		var plaque := waymarks.get_child(index)
		plaque.name = "Plaque%d" % index
		for part in plaque.get_children():
			part.name = "Lettering" if part is Label3D else "Face"
	waymark_holder.free()
	for index in ROUTE_LABELS.size():
		var entry: Array = ROUTE_LABELS[index]
		var label := Label3D.new()
		label.name = "RouteLabel%d" % index
		label.text = entry[1]
		label.position = TomatinaMap.at_cell(entry[0]) + Vector3.UP * 3.8
		label.pixel_size = 0.012
		label.font_size = 64
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("e7f1b1")
		signs.add_child(label)

	# --- 쓰러진 사람 -------------------------------------------------------------
	var victims := _folder(root, "Victims")
	var placements := TomatinaVillageArt.victim_placements()
	for index in placements.size():
		var placement: Dictionary = placements[index]
		var facing: Vector3 = placement.facing
		var victim := TomatinaMapVictim.new()
		victim.name = "Victim%02d" % index
		victim.model = placement.model
		victim.position = placement.at
		victim.rotation.y = atan2(facing.x, facing.z)
		victims.add_child(victim)

	# --- 적 -------------------------------------------------------------------------
	var enemies := _folder(root, "Enemies")
	var roster := TomatinaMap.roster()
	for index in roster.size():
		var entry: Array = roster[index]
		var enemy := TomatinaMapEnemy.new()
		enemy.name = "E%03d_%s" % [index, entry[0]]
		enemy.kind = entry[0]
		if entry.size() > 2:
			enemy.tag = str(entry[2])
		enemy.position = TomatinaMap.at_cell(entry[1])
		enemies.add_child(enemy)

	# --- 표시점 ---------------------------------------------------------------------
	var spawns := _folder(root, "Spawns")
	for slot in TomatinaMap.SPAWNS.size():
		var marker := Marker3D.new()
		marker.name = "Spawn%d" % slot
		marker.position = TomatinaMap.spawn_position(slot)
		spawns.add_child(marker)
	var arrow := Marker3D.new()
	arrow.name = "StartArrow"
	arrow.position = TomatinaMap.start_arrow()
	root.add_child(arrow)
	var siren := Marker3D.new()
	siren.name = "Siren"
	siren.position = TomatinaMap.at_cell(TomatinaMap.siren_cell())
	root.add_child(siren)

	_own(root, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, OUT_SCENE)
	print("BAKE_TOMATINA_MAP %s floor=%d walls=%d props=%d art=%d victims=%d enemies=%d" % [
		"OK" if error == OK else "ERROR %d" % error, floor_legs.size(),
		TomatinaMap.boundary_boxes().size(), count + 1, art.recorded.size(), placements.size(), roster.size()])
	StreetMap.layout_override = null
	root.free()
	quit(0 if error == OK else 1)


func _nearest_brazier(at: Vector3, debris: Array[Dictionary], nodes: Array[Node3D]) -> Node3D:
	var best: Node3D = nodes[0]
	var best_distance := INF
	for index in debris.size():
		if debris[index]["name"] != "RefugeBrazier":
			continue
		var centre: Vector3 = debris[index]["position"]
		var distance := Vector2(centre.x - at.x, centre.z - at.z).length()
		if distance < best_distance:
			best_distance = distance
			best = nodes[index]
	return best


func _make_tiles() -> MeshLibrary:
	var library := MeshLibrary.new()
	for item in TILE_NAMES.size():
		var mesh := BoxMesh.new()
		mesh.size = Vector3(StreetMap.CELL * 0.94, 0.08, StreetMap.CELL * 0.94)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(TILE_COLORS[item], 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = material
		library.create_item(item)
		library.set_item_name(item, TILE_NAMES[item])
		library.set_item_mesh(item, mesh)
	return library


func _prop(box: Dictionary, group: int, index: int) -> TomatinaMapProp:
	var prop := TomatinaMapProp.new()
	var size: Vector3 = box["size"]
	prop.name = "%03d_%s" % [index, String(box["name"]).validate_node_name()]
	prop.prop_name = box["name"]
	prop.group = group
	prop.size = size
	prop.color = box.get("color", Color("6d5a4e"))
	prop.facing = box.get("facing", Vector3.ZERO)
	prop.jumpable = box.get("jumpable", false)
	prop.aftermath = box.has("aftermath")
	prop.closed_passage = box.get("closed_passage", false)
	prop.position = box["position"] - Vector3.UP * size.y * 0.5
	# 자식 모델을 클릭해도 소품 노드가 잡히게 묶는다(모델과 충돌 상자가 같이 움직인다).
	prop.set_meta("_edit_group_", true)
	return prop


func _category(box: Dictionary) -> String:
	var name: String = box["name"]
	if box.get("closed_passage", false):
		return "ClosedPassages"
	if box.has("aftermath"):
		return "Aftermath"
	if name.begins_with("Refuge"):
		return "Refuges"
	if name.begins_with("TomatoCratesSupply"):
		return "SupplyCrates"
	if name.begins_with("TomatoCrate") or name == "MarketBarrels":
		return "Crates"
	if name.ends_with("TomatoTruck"):
		return "CargoTrucks"
	if name.begins_with("Plaza") or name.begins_with("Siren"):
		return "Plaza"
	return "Rubble"


func _folder(parent: Node, folder_name: String) -> Node3D:
	var folder := Node3D.new()
	folder.name = folder_name
	parent.add_child(folder)
	return folder


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
