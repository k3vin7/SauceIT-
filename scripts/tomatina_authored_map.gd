class_name TomatinaAuthoredMap
extends RefCounted

## 노드로 편집한 토마티나 맵에서 읽어 낸 설계 데이터.
##
## `TomatinaMap.use_authored`에 넘기면 `TomatinaMap`의 정적 함수들이 원래 코드 대신
## 이 값을 돌려준다. 읽는 쪽 노드 구성은 `TomatinaMapEditor`(맵 씬의 루트)를 본다.
##
## 맵 씬 구성 (루트 바로 아래 이름으로 찾는다):
##   Floor      GridMap. 칠한 칸 = 걸을 수 있는 바닥(적 길찾기·바닥 오염 범위).
##              아이템 0~3 = 도로 구간(leg), 4 = 피난처 바닥.
##   Walls      TomatinaMapWall들. 벽 충돌 상자. (없으면 바닥 둘레에 자동 생성)
##   Art        TomatinaArtPiece들(집, 담장, 창문, 등불 ...), 장식 줄, 길 안내판. 그림만, 충돌 없음.
##   Victims    TomatinaMapVictim들. 쓰러진 축제 참가자(뒤지기). (없으면 자동 배치)
##   Routes     Path3D 자식들(구간 0~3 순서). 봇 경로, 축제 장식 줄, 적 추격 구간 계산에 쓴다.
##   SafeRooms  TomatinaMapRoom 자식들(피난처). 순서 = 피난처 번호.
##   Props      TomatinaMapProp들(하위 폴더 자유). 잔해/주차 트럭/소방차.
##   Enemies    TomatinaMapEnemy들(하위 폴더 자유). 트리 순서 = 생성 순서.
##   Spawns     Marker3D 자식들. 플레이어 시작 자리(순서 = 슬롯).
##   StartArrow Marker3D. 출발 화살표 위치.
##   Siren      Marker3D. 발전기(사이렌) 위치.

const FLOOR_SAFE_ITEM := 4

var floor_legs := {}
var route_points: Array = []
var safe_rooms: Array[Rect2i] = []
var safe_room_names: Array = []
var debris: Array[Dictionary] = []
var parked: Array[Dictionary] = []
var fire_truck := {}
var roster: Array = []
var spawns: Array[Vector3] = []
var start_arrow := Vector3.ZERO
var siren_cell := TomatinaMap.SIREN_CELL
var has_walls := false
var walls: Array[Dictionary] = []
var has_victims := false
var victims: Array[Dictionary] = []


static func from_scene(scene: PackedScene) -> TomatinaAuthoredMap:
	var root := scene.instantiate()
	var data := from_root(root)
	root.free()
	return data


static func from_root(root: Node) -> TomatinaAuthoredMap:
	var data := TomatinaAuthoredMap.new()
	var floor_map := root.get_node_or_null("Floor") as GridMap
	if floor_map != null:
		# GridMap을 옮겨 놓았으면 그만큼 칸을 민다(칸 단위로 반올림).
		var shift := (floor_map.position - TomatinaMap.at_cell(Vector2.ZERO)) / StreetMap.CELL
		var offset := Vector2i(roundi(shift.x), roundi(shift.z))
		for used: Vector3i in floor_map.get_used_cells():
			var item := floor_map.get_cell_item(used)
			data.floor_legs[Vector2i(used.x, used.z) + offset] = item if item < FLOOR_SAFE_ITEM else -1

	var routes := root.get_node_or_null("Routes")
	if routes != null:
		for path in routes.get_children():
			if not path is Path3D:
				continue
			var xf := relative_transform(path, root)
			var points: Array = []
			var curve: Curve3D = path.curve
			if curve != null:
				for index in curve.point_count:
					points.append(world_to_cell(xf * curve.get_point_position(index)))
			data.route_points.append(points)

	var rooms := root.get_node_or_null("SafeRooms")
	if rooms != null:
		for room in rooms.get_children():
			if not room is TomatinaMapRoom:
				continue
			var rect: Rect2i = room.cell_rect(relative_transform(room, root))
			data.safe_rooms.append(rect)
			data.safe_room_names.append(room.room_name)
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					data.floor_legs[Vector2i(x, y)] = -1

	var props := root.get_node_or_null("Props")
	if props != null:
		for prop in props.find_children("*", "", true, false):
			if not prop is TomatinaMapProp:
				continue
			var box: Dictionary = prop.to_box(relative_transform(prop, root))
			match prop.group:
				TomatinaMapProp.Group.PARKED_TRUCK:
					data.parked.append(box)
				TomatinaMapProp.Group.FIRE_TRUCK:
					if data.fire_truck.is_empty():
						data.fire_truck = box
				_:
					data.debris.append(box)

	var walls := root.get_node_or_null("Walls")
	if walls != null:
		data.has_walls = true
		for wall in walls.find_children("*", "", true, false):
			if wall is TomatinaMapWall:
				data.walls.append(wall.to_box(relative_transform(wall, root)))

	var victims := root.get_node_or_null("Victims")
	if victims != null:
		data.has_victims = true
		for victim in victims.find_children("*", "", true, false):
			if victim is TomatinaMapVictim:
				data.victims.append(victim.to_placement(relative_transform(victim, root)))

	var enemies := root.get_node_or_null("Enemies")
	if enemies != null:
		for enemy in enemies.find_children("*", "", true, false):
			if enemy is TomatinaMapEnemy:
				data.roster.append(enemy.to_entry(relative_transform(enemy, root)))

	var spawns := root.get_node_or_null("Spawns")
	if spawns != null:
		for spawn in spawns.get_children():
			if spawn is Node3D:
				data.spawns.append(relative_transform(spawn, root).origin)
	var arrow := root.get_node_or_null("StartArrow") as Node3D
	# 화살표 노드가 없으면 첫 출발 지점 바닥에 그린다.
	if arrow != null:
		data.start_arrow = relative_transform(arrow, root).origin
	elif not data.spawns.is_empty():
		data.start_arrow = Vector3(data.spawns[0].x, 0.0, data.spawns[0].z)
	var siren := root.get_node_or_null("Siren") as Node3D
	if siren != null:
		data.siren_cell = world_to_cell(relative_transform(siren, root).origin)
	return data


## 루트 기준 변환. 씬을 트리에 넣지 않고 읽으므로 global_transform 대신 직접 곱한다.
static func relative_transform(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk := node
	while walk != null and walk != root:
		if walk is Node3D:
			xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	return xf


static func world_to_cell(at: Vector3) -> Vector2:
	return Vector2(at.x / StreetMap.CELL + float(StreetMap.ORIGIN_CELL.x),
		at.z / StreetMap.CELL + float(StreetMap.ORIGIN_CELL.y))
