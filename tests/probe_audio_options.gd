extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := "user://audio_options_probe.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value("options", "master_volume", 0.37)
	assert(legacy.save(path) == OK)
	var app = load("res://app.tscn").instantiate()
	app.save_path_override = path
	root.add_child(app)
	await process_frame
	assert(is_equal_approx(app.save_store.bgm_volume, 1.0))
	assert(is_equal_approx(app.save_store.master_volume, 0.37))
	app._open_options()
	app._bgm_slider.value = 0.0
	app._sfx_slider.value = 0.63
	app._save_options()
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	assert(music >= 0 and sfx >= 0)
	assert(AudioServer.is_bus_mute(music))
	assert(not AudioServer.is_bus_mute(sfx))
	assert(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx)), 0.63))
	var loaded := SauceSaveStore.new(path)
	loaded.load_data()
	assert(is_zero_approx(loaded.bgm_volume))
	assert(is_equal_approx(loaded.sfx_volume, 0.63))
	app._open_options()
	app._bgm_slider.value = 0.44
	app._sfx_slider.value = 0
	app._close_options()
	assert(AudioServer.is_bus_mute(music) and not AudioServer.is_bus_mute(sfx))
	assert(is_equal_approx(app.save_store.sfx_volume, 0.63))
	var stage = load("res://stage_2_tomatina.tscn").instantiate()
	MayoTutorial.disabled = true
	root.add_child(stage)
	await process_frame
	assert(stage._stage_music.bus == "Music")
	for player in [stage._sauce_audio, stage._spray_loop_audio, stage._spray_edge_audio, stage._footstep_voice]:
		assert(player.bus == "SFX")
	for player in stage._splat_voices:
		assert(player.bus == "SFX")
	app._open_options()
	app._bgm_slider.value = 0.44
	app._sfx_slider.value = 0.0
	app._save_options()
	assert(not AudioServer.is_bus_mute(music) and AudioServer.is_bus_mute(sfx))
	assert(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music)), 0.44))
	stage.queue_free()
	app.queue_free()
	DirAccess.remove_absolute(path)
	await process_frame
	print("AUDIO_OPTIONS_OK")
	quit()
