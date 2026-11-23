@tool
class_name TomatinaMapEditor
extends Node3D

## 노드로 편집하는 토마티나 맵의 루트. 구성과 규칙은 `TomatinaAuthoredMap` 머리말 참고.
## 실제 게임은 stage_2_tomatina_editable.tscn 으로 실행한다(F6).
##
## 벽·집·담장·소품·장식이 전부 노드로 들어 있어서 그대로 옮기고 지우고 복제하면 된다.
## 바닥(Floor)을 크게 다시 칠했다면 아래 버튼으로 벽 충돌 상자와 길가 건물(Art/Streets)을
## 새 바닥에 맞춰 다시 만들 수 있다. 그 두 폴더를 손으로 고친 내용은 덮어써진다(되돌리기 없음).

@export_tool_button("바닥 기준으로 Walls + Art/Streets 다시 만들기 (덮어씀)", "Reload")
var regenerate_button := regenerate_walls_and_streets

const NAMED_REGIONS := ["Leg0", "Leg1", "Leg2", "Leg3"]


func regenerate_walls_and_streets() -> void:
	var data := TomatinaAuthoredMap.from_root(self)
	data.has_walls = false
	var previous_layout = StreetMap.layout_override
	var previous_map = TomatinaMap.authored
	TomatinaMap.use_authored(data)
	StreetMap.layout_override = TomatinaMap.new()
	var art := TomatinaVillageArt.new()
	art.load_kit()
	art.recording = true
	art.record_tag = "street"
	art._build_frontages()
	var walls := reset_folder(self, "Walls")
	add_walls(walls, TomatinaMap.boundary_boxes())
	walls.visible = false
	var art_root := get_node_or_null("Art") as Node3D
	if art_root == null:
		art_root = reset_folder(self, "Art")
	add_street_pieces(reset_folder(art_root, "Streets"), art.recorded)
	StreetMap.layout_override = previous_layout
	TomatinaMap.use_authored(previous_map)
	_own(self)
	print("토마티나 맵: 벽 %d개, 길가 조각 %d개를 다시 만들었다" % [walls.get_child_count(), art.recorded.size()])


## `parent` 아래 `folder_name` 폴더를 비우고(없으면 만들고) 돌려준다.
static func reset_folder(parent: Node, folder_name: String) -> Node3D:
	var old := parent.get_node_or_null(folder_name)
	var index := -1
	if old != null:
		index = old.get_index()
		parent.remove_child(old)
		old.free()
	var folder := Node3D.new()
	folder.name = folder_name
	parent.add_child(folder)
	if index >= 0:
		parent.move_child(folder, index)
	return folder


static func add_walls(parent: Node3D, boxes: Array[Dictionary]) -> void:
	for index in boxes.size():
		var box := boxes[index]
		var size: Vector3 = box["size"]
		var wall := TomatinaMapWall.new()
		wall.name = "Wall%03d" % index
		wall.size = size
		wall.position = box["position"] - Vector3.UP * size.y * 0.5
		parent.add_child(wall)


## 길가 조각(담장, 집, 창문, 가게 앞면, 길바닥 쓰레기)을 종류/구간 폴더로 나눠 넣는다.
static func add_street_pieces(parent: Node3D, recorded: Array) -> void:
	var folders := {}
	var counts := {}
	for entry: Array in recorded:
		var key: String = entry[0]
		var xf: Transform3D = entry[1]
		var category := _street_category(key, entry[2])
		var region := _region(xf.origin)
		var path := "%s/%s" % [category, region]
		if not folders.has(path):
			var group: Node = parent.get_node_or_null(category)
			if group == null:
				group = Node3D.new()
				group.name = category
				parent.add_child(group)
			var leaf := Node3D.new()
			leaf.name = region
			group.add_child(leaf)
			folders[path] = leaf
		var count := int(counts.get(key, 0))
		counts[key] = count + 1
		folders[path].add_child(make_piece(key, xf, "%s_%04d" % [key, count]))


static func make_piece(key: String, xf: Transform3D, piece_name: String) -> TomatinaArtPiece:
	var piece := TomatinaArtPiece.new()
	piece.name = piece_name
	piece.model = key
	piece.transform = xf
	return piece


static func _street_category(key: String, tag: String) -> String:
	if key == "BoundaryWall":
		return "BoundaryWalls"
	if key in TomatinaVillageArt.HOUSES:
		return "BackHouses" if tag == "backlot" else "Houses"
	if key.begins_with("Facade"):
		return "Facades"
	if TomatinaVillageArt.STREET_ACCENTS.has(key):
		return "StreetFronts"
	return "Litter"


## 가장 가까운 도로 구간 이름.
static func _region(at: Vector3) -> String:
	var cell := TomatinaAuthoredMap.world_to_cell(at)
	var best := 0
	var best_distance := INF
	for leg in TomatinaMap.route_points().size():
		var distance := TomatinaMap.route_distance(cell, leg)
		if distance < best_distance:
			best_distance = distance
			best = leg
	return NAMED_REGIONS[best] if best < NAMED_REGIONS.size() else "Leg%d" % best


func _own(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = self
		_own(child)
