class_name PracticeRange
extends RefCounted

## 사격 연습장. 사무실의 사격 연습장 방에서 들어오는 곳으로, 스테이지 2와 같은 사격 코드를
## (소스 막힘·압력·파츠·반동까지) 작은 방에서 그대로 돌린다 -- 따로 만든 흉내가 아니다.
##
## 맵은 씬이 아니라 여기서 값으로 만든다: `TomatinaAuthoredMap`을 채워 `TomatinaMap`에
## 넘기면 바닥·벽·길찾기·시작 자리가 전부 그 값을 따른다(`MayoPrototype._build_world`).
## 축제의 것(입구, 피난처, 쓰러진 참가자)은 하나도 없다.
##
## 여기서는
##   * 소스 세 가지와 파츠 전부를 값 없이 바로 골라 쓴다(B, `MayoPrototype._build_range_panel`)
##   * 표적은 서 있기만 하고, 쓰러지면 `RESPAWN_SECONDS` 뒤에 같은 자리에 다시 선다
##   * 플레이어는 다치지 않는다

## 연습장 바닥(칸). 한 칸은 `StreetMap.CELL`(약 4.6 m). 가로 5칸, 세로 13칸.
const AREA := Rect2i(27, 87, 5, 13)
## 플레이어가 서는 줄(칸의 y). 표적은 여기서 -y 쪽으로 늘어선다.
const FIRING_LINE := 99.0
## 표적: [종류, 가로 칸, 사선에서의 거리(m)]. 기본 줄기가 닿는 5 m와 8 m(뭉쳐 선 셋과
## 덩치 -- 폭발·관통용), 집중 노즐의 12 m, 그 너머는 던지고 쏘아 보내는 파츠와 저격용이다.
const TARGET_ROWS := [
	["TOMATO_GRUNT", 28.3, 5.0],
	["TOMATO_GRUNT", 30.7, 5.0],
	["TOMATO_GRUNT", 28.15, 8.0],
	["TOMATO_GRUNT", 28.5, 8.6],
	["TOMATO_GRUNT", 28.35, 9.6],
	["TOMATO_BRUTE", 30.8, 8.0],
	["TOMATO_GRUNT", 29.5, 12.0],
	["TOMATO_GRUNT", 28.4, 20.0],
	["TOMATO_BRUTE", 30.6, 20.0],
	["TOMATO_GRUNT", 28.3, 30.0],
	["TOMATO_GRUNT", 30.7, 30.0],
	["TOMATO_BRUTE", 29.5, 45.0],
	["TOMATO_GRUNT", 28.3, 45.0],
]
## 표적이 쓰러진 뒤 다시 서기까지.
const RESPAWN_SECONDS := 3.0
## 거리 표시를 세우는 곳: 사선에서 이만큼(m) 떨어진 줄마다 하나.
const DISTANCE_MARKS := [5, 10, 20, 30, 40, 50]

const SAUCE_NAMES := ["마요네즈", "머스터드", "케첩"]


static func map_data() -> TomatinaAuthoredMap:
	var data := TomatinaAuthoredMap.new()
	for y in range(AREA.position.y, AREA.end.y):
		for x in range(AREA.position.x, AREA.end.x):
			data.floor_legs[Vector2i(x, y)] = 0
	for entry in targets():
		data.roster.append([entry[0], entry[1]])
	for slot in 4:
		data.spawns.append(TomatinaMap.at_cell(Vector2(28.6 + 0.6 * slot, FIRING_LINE + 0.1))
			+ Vector3.UP * 1.28)
	data.start_arrow = Vector3.INF
	# 발전기(사이렌)는 벽 밖에 둔다 -- 여기에는 최종전이 없다.
	data.siren_cell = Vector2(AREA.position) - Vector2(6.0, 6.0)
	return data


## 표적마다 [종류, 칸]. 순서가 곧 만들어지는 순서다.
static func targets() -> Array:
	var out: Array = []
	for row in TARGET_ROWS:
		out.append([row[0], Vector2(float(row[1]), FIRING_LINE - float(row[2]) / StreetMap.CELL)])
	return out


## 사선에서 `metres` 떨어진 줄의 한가운데(바닥).
static func line_at(metres: float) -> Vector3:
	var line := TomatinaMap.at_cell(Vector2(float(AREA.position.x) + AREA.size.x * 0.5, FIRING_LINE))
	return line + Vector3.FORWARD * metres
