class_name StageRegistry
extends RefCounted

const STAGES := {
	"stage_1": {
		"display_name": "스테이지 1 · 축제 거리",
		"scene": "res://stage_1_festival.tscn",
		"clear_condition": "all_target_enemies_defeated",
		"place": "축제 거리",
		"blurb": "노점이 늘어선 거리 축제. 오염된 손님들을 씻어 내세요.",
		"map_pin": Vector2(0.30, 0.62),
	},
	"stage_2": {
		"display_name": "스테이지 2 · 토마토 축제",
		"scene": "res://stage_2_tomatina.tscn",
		"clear_condition": "all_elite_enemies_defeated_and_party_at_fire_truck",
		"place": "스페인 · 부뇰",
		"blurb": "토마토 축제 한복판. 광장의 소방차까지 길을 뚫으세요.",
		"map_pin": Vector2(0.68, 0.36),
	},
}


static func has_stage(stage_id: String) -> bool:
	return STAGES.has(stage_id)


static func scene_path(stage_id: String) -> String:
	return str(STAGES.get(stage_id, STAGES["stage_1"])["scene"])


static func display_name(stage_id: String) -> String:
	return str(STAGES.get(stage_id, STAGES["stage_1"])["display_name"])


static func available_ids() -> Array[String]:
	return ["stage_1", "stage_2"]


## Where the festival is and what is waiting there, for the office map.
static func place(stage_id: String) -> String:
	return str(STAGES.get(stage_id, {}).get("place", ""))


static func blurb(stage_id: String) -> String:
	return str(STAGES.get(stage_id, {}).get("blurb", ""))


## The pin on the office map, as a fraction of the map's width and height.
static func map_pin(stage_id: String) -> Vector2:
	return STAGES.get(stage_id, {}).get("map_pin", Vector2(0.5, 0.5))
