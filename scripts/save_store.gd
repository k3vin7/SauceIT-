class_name SauceSaveStore
extends RefCounted

const DEFAULT_PATH := "user://sauce_it.cfg"
var path := DEFAULT_PATH
var tutorial_completed := false
## 팀 공용 돈과 전리품, 축제별 완료 횟수. 방을 연 사람(방장)의 것이 그 방의 것이다.
var money := 0
var trophies := PackedStringArray()
var clears: Dictionary = {}
var master_volume := 0.8
var bgm_volume := 1.0
## A third of full: the effects were loud against the music at 1.0. Only the
## default -- a volume a player has already saved is kept.
const DEFAULT_SFX_VOLUME := 1.0 / 3.0
var sfx_volume := DEFAULT_SFX_VOLUME
var mouse_sensitivity := 0.09
var game_options := preload("res://scripts/game_options.gd").new()


func _init(custom_path := "") -> void:
	if not custom_path.is_empty():
		path = custom_path


func load_data() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		game_options.load_config(config)
		return
	game_options.load_config(config)
	tutorial_completed = bool(config.get_value("progress", "tutorial_completed", false))
	money = maxi(int(config.get_value("progress", "money", 0)), 0)
	trophies = PackedStringArray(config.get_value("progress", "trophies", PackedStringArray()))
	var saved_clears = config.get_value("progress", "clears", {})
	clears = saved_clears if saved_clears is Dictionary else {}
	master_volume = clampf(float(config.get_value("options", "master_volume", 0.8)), 0.0, 1.0)
	bgm_volume = clampf(float(config.get_value("options", "bgm_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("options", "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(config.get_value("options", "mouse_sensitivity", 0.09)), 0.02, 0.3)


func save_progress_complete() -> int:
	tutorial_completed = true
	return _write()


## 축제 하나를 마치고 번 것을 더해 저장한다. 이미 가진 전리품은 다시 올리지 않는다.
func add_reward(stage_id: String, money_gain: int, trophy_id: String) -> int:
	money += maxi(money_gain, 0)
	if not trophy_id.is_empty() and not trophies.has(trophy_id):
		trophies.push_back(trophy_id)
	clears[stage_id] = int(clears.get(stage_id, 0)) + 1
	return _write()


## 사무실에서 쓰거나 딴 뒤의 팀 돈을 적는다.
func set_money(value: int) -> int:
	money = maxi(value, 0)
	return _write()


func save_options(volume: float, sensitivity: float, music: float = -1.0, effects: float = -1.0) -> int:
	if music >= 0: bgm_volume = clampf(music, 0.0, 1.0)
	if effects >= 0: sfx_volume = clampf(effects, 0.0, 1.0)
	master_volume = clampf(volume, 0.0, 1.0)
	mouse_sensitivity = clampf(sensitivity, 0.02, 0.3)
	return _write()


func _write() -> int:
	var config := ConfigFile.new()
	config.set_value("progress", "tutorial_completed", tutorial_completed)
	config.set_value("progress", "money", money)
	config.set_value("progress", "trophies", trophies)
	config.set_value("progress", "clears", clears)
	config.set_value("options", "master_volume", master_volume)
	config.set_value("options", "bgm_volume", bgm_volume)
	config.set_value("options", "sfx_volume", sfx_volume)
	config.set_value("options", "mouse_sensitivity", mouse_sensitivity)
	game_options.write_config(config)
	return config.save(path)
