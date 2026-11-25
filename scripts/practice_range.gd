class_name PracticeRange
extends RefCounted

## 사무실의 사격 연습장. 사무실 안의 방 하나이고, 그 방 안에서 바로 쏜다 -- 어디로도
## 옮겨 가지 않는다.
##
## 쏘는 것은 스테이지 2의 코드 그대로다(소스 막힘·압력·파츠·반동까지). 사무실은 방 안에
## `MayoPrototype` 월드를 하나 품고 있고(`OfficeLobby`), 문을 지나 방에 들어서면 그 월드의
## 플레이어로 바뀌어 걷는다. 그 월드의 맵이 이 파일이다: 씬이 아니라 값으로 만들어
## `TomatinaAuthoredMap`에 채워 넘기면 바닥·벽·길찾기가 전부 그 값을 따른다
## (`MayoPrototype._build_world`). 좌표는 전부 사무실 방 씬(`maps/command.tscn`)의 것이고,
## 방의 벽·진열대·선택대는 그 씬에 놓여 있다 -- 여기 숫자와 맞춰 고친다.
##
## 여기서는
##   * 앞벽의 진열대에서 소스 세 가지를, 뒷벽의 선택대에서 파츠 전부를 값 없이 집는다(E)
##   * 표적은 서 있기만 하고, 쓰러지면 `RESPAWN_SECONDS` 뒤에 같은 자리에 다시 선다
##   * 플레이어는 다치지 않는다
## 연습은 각자의 화면에서만 돈다: 방 안의 팀원은 서로 걷는 모습만 보고, 줄기와 표적은
## 저마다 자기 것을 본다.

## 방의 안쪽(벽면에서 벽면). 사무실 씬의 `Annex/ShootingRange`와 같다.
const ROOM := Rect2(5.175, 10.175, 31.65, 9.65)
## 벽 높이와, 방 안쪽에 덧대는 소스 묻는 벽판의 두께.
const WALL_HEIGHT := 5.0
const LINER := 0.12
## 홀로 통하는 문(홀 쪽 벽 x = `ROOM.position.x`): z의 범위와 높이.
const DOOR_Z := Vector2(13.5, 16.5)
const DOOR_HEIGHT := 3.0
## 문을 지나 이 x를 넘어서면 연습장의 몸이 되고, 돌아 나와 `EXIT_X` 아래로 가면 사무실의
## 몸으로 돌아간다. 둘 사이의 틈은 문턱에서 오락가락하지 않게 하는 여유다.
const ENTER_X := 5.9
const EXIT_X := 5.45
## 쏘는 줄. 표적은 여기서 +x 쪽으로 늘어선다.
const FIRING_X := 12.0
## 표적: [종류, z, 사선에서의 거리(m)]. 기본 줄기가 닿는 5 m와 8 m(뭉쳐 선 셋과 덩치 --
## 폭발·관통용), 집중 노즐의 12 m, 그 너머는 던지고 쏘아 보내는 파츠와 저격용이다.
const TARGET_ROWS := [
	["TOMATO_GRUNT", 12.4, 5.0],
	["TOMATO_GRUNT", 17.6, 5.0],
	["TOMATO_GRUNT", 12.0, 8.0],
	["TOMATO_GRUNT", 12.9, 8.5],
	["TOMATO_GRUNT", 12.4, 9.4],
	["TOMATO_BRUTE", 17.4, 8.0],
	["TOMATO_GRUNT", 15.0, 12.0],
	["TOMATO_GRUNT", 12.4, 17.0],
	["TOMATO_BRUTE", 17.6, 17.0],
	["TOMATO_GRUNT", 12.2, 23.4],
	["TOMATO_BRUTE", 15.0, 23.6],
	["TOMATO_GRUNT", 17.8, 23.4],
]
## 표적이 쓰러진 뒤 다시 서기까지.
const RESPAWN_SECONDS := 3.0
## 거리 표지를 붙이는 줄: 사선에서 이만큼(m).
const DISTANCE_MARKS := [5, 10, 15, 20]
## 진열대의 병: 소스 번호(`MayoPrototype.STATION_SAUCES`)마다 하나. 앞벽에 놓인다.
const SAUCE_SPOTS := [
	Vector3(6.2, 1.3, 10.6),
	Vector3(7.2, 1.3, 10.6),
	Vector3(8.2, 1.3, 10.6),
]
## 선택대의 파츠: 뒷벽을 따라 `PART_SPACING`씩. 번호는 `SauceParts.Part`.
const PART_FIRST := Vector3(5.95, 1.12, 19.4)
const PART_SPACING := 0.85
## 병이나 파츠에서 이만큼(바닥 거리) 안에 서야 집을 수 있다.
const PICK_REACH := 2.4
## 연습장의 몸이 서는 곳(바닥). 방에 들어서기 전에는 숨겨져 여기 서 있다.
const SPAWN := Vector3(7.5, 0.0, 15.0)


static func part_spot(part: int) -> Vector3:
	return PART_FIRST + Vector3(PART_SPACING * float(part), 0.0, 0.0)


## 표적마다 [종류, 바닥 자리]. 순서가 곧 만들어지는 순서다.
static func targets() -> Array:
	var out: Array = []
	for row in TARGET_ROWS:
		out.append([row[0], Vector3(FIRING_X + float(row[2]), 0.0, float(row[1]))])
	return out


## 소스가 묻는 바닥이 덮는 곳: 방의 안쪽 그대로.
static func floor_plane() -> Dictionary:
	var centre := ROOM.get_center()
	return {"centre": Vector3(centre.x, 0.0, centre.y), "size": ROOM.size}


## 방 안쪽에 덧대는 벽판. 사무실의 벽은 그림과 충돌일 뿐이라 소스가 묻지 않는다 -- 묻는 것은
## 이 판이고, 문 자리만 비어 있다.
static func walls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var low := WALL_HEIGHT * 0.5
	var x0 := ROOM.position.x
	var x1 := ROOM.end.x
	var z0 := ROOM.position.y
	var z1 := ROOM.end.y
	var half := LINER * 0.5
	out.append({"position": Vector3((x0 + x1) * 0.5, low, z0 + half),
		"size": Vector3(x1 - x0, WALL_HEIGHT, LINER)})
	out.append({"position": Vector3((x0 + x1) * 0.5, low, z1 - half),
		"size": Vector3(x1 - x0, WALL_HEIGHT, LINER)})
	out.append({"position": Vector3(x1 - half, low, (z0 + z1) * 0.5),
		"size": Vector3(LINER, WALL_HEIGHT, z1 - z0)})
	out.append({"position": Vector3(x0 + half, low, (z0 + DOOR_Z.x) * 0.5),
		"size": Vector3(LINER, WALL_HEIGHT, DOOR_Z.x - z0)})
	out.append({"position": Vector3(x0 + half, low, (DOOR_Z.y + z1) * 0.5),
		"size": Vector3(LINER, WALL_HEIGHT, z1 - DOOR_Z.y)})
	out.append({"position": Vector3(x0 + half, (DOOR_HEIGHT + WALL_HEIGHT) * 0.5, (DOOR_Z.x + DOOR_Z.y) * 0.5),
		"size": Vector3(LINER, WALL_HEIGHT - DOOR_HEIGHT, DOOR_Z.y - DOOR_Z.x)})
	return out


static func map_data() -> TomatinaAuthoredMap:
	var data := TomatinaAuthoredMap.new()
	# 걸을 수 있는 칸: 방을 덮는 칸 전부. 길찾기와 범위 계산에만 쓰인다(표적은 걷지 않는다).
	var low := TomatinaAuthoredMap.world_to_cell(Vector3(ROOM.position.x, 0.0, ROOM.position.y))
	var high := TomatinaAuthoredMap.world_to_cell(Vector3(ROOM.end.x, 0.0, ROOM.end.y))
	for y in range(floori(low.y), ceili(high.y)):
		for x in range(floori(low.x), ceili(high.x)):
			data.floor_legs[Vector2i(x, y)] = 0
	data.has_walls = true
	data.walls = walls()
	for entry in targets():
		data.roster.append([entry[0], TomatinaAuthoredMap.world_to_cell(entry[1])])
	for slot in 4:
		data.spawns.append(SPAWN + Vector3(0.0, 1.28, 0.0))
	data.start_arrow = SPAWN
	# 발전기(사이렌)는 아주 먼 곳에 둔다 -- 여기에는 최종전이 없다.
	data.siren_cell = Vector2(29.0, 20.0)
	return data


## 사선에서 `metres` 떨어진 줄의 한가운데(바닥).
static func line_at(metres: float) -> Vector3:
	return Vector3(FIRING_X + metres, 0.0, ROOM.get_center().y)


## 이 자리(사무실 좌표)가 연습장 안인가: 문을 지나 `ENTER_X`를 넘어섰다.
static func is_inside(at: Vector3) -> bool:
	return at.x > ENTER_X and at.x < ROOM.end.x and at.z > ROOM.position.y and at.z < ROOM.end.y
