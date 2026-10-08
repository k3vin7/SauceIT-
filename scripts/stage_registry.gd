class_name StageRegistry
extends RefCounted

const STAGES := {
	"stage_1": {
		"display_name": "스테이지 1 · 축제 거리",
		"scene": "res://stage_1_festival.tscn",
		"clear_condition": "all_target_enemies_defeated",
	},
}


static func has_stage(stage_id: String) -> bool:
	return STAGES.has(stage_id)


static func scene_path(stage_id: String) -> String:
	return str(STAGES.get(stage_id, STAGES["stage_1"])["scene"])


static func display_name(stage_id: String) -> String:
	return str(STAGES.get(stage_id, STAGES["stage_1"])["display_name"])


static func available_ids() -> Array[String]:
	return ["stage_1"]
