class_name SauceSaveStore
extends RefCounted

const DEFAULT_PATH := "user://sauce_it.cfg"
var path := DEFAULT_PATH
var tutorial_completed := false
var master_volume := 0.8
var mouse_sensitivity := 0.09


func _init(custom_path := "") -> void:
	if not custom_path.is_empty():
		path = custom_path


func load_data() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	tutorial_completed = bool(config.get_value("progress", "tutorial_completed", false))
	master_volume = clampf(float(config.get_value("options", "master_volume", 0.8)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(config.get_value("options", "mouse_sensitivity", 0.09)), 0.02, 0.3)


func save_progress_complete() -> int:
	tutorial_completed = true
	return _write()


func save_options(volume: float, sensitivity: float) -> int:
	master_volume = clampf(volume, 0.0, 1.0)
	mouse_sensitivity = clampf(sensitivity, 0.02, 0.3)
	return _write()


func _write() -> int:
	var config := ConfigFile.new()
	config.set_value("progress", "tutorial_completed", tutorial_completed)
	config.set_value("options", "master_volume", master_volume)
	config.set_value("options", "mouse_sensitivity", mouse_sensitivity)
	return config.save(path)
