extends SceneTree
func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("run")
func run() -> void:
	var stage1 = load("res://stage_1_festival.tscn").instantiate()
	root.add_child(stage1)
	await process_frame
	assert(stage1._stage_music == null,"music leaked into another stage")
	stage1.queue_free()
	await process_frame
	var stage2 = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(stage2)
	await process_frame
	var music: AudioStreamPlayer = stage2._stage_music
	assert(is_instance_valid(music) and music.playing,"stage music did not start")
	assert(music.stream is AudioStreamMP3 and music.stream.loop,"main music should play as a looped MP3")
	assert(absf(music.stream.get_length() - 249.68) < 0.1,"unexpected main track duration")
	assert(music.bus == "Music","music bus was not assigned")
	music.volume_db = music.MIX_DB
	stage2._truck_arrival.active = true
	music._process(1.0)
	assert(music.volume_db < music.MIX_DB - 6.0,"music did not duck for truck cinematic")
	stage2._truck_arrival.active = false
	music._process(2.0)
	assert(music.volume_db > music.MIX_DB - 1.0,"music did not recover after cinematic")
	stage2._boss_entrance.active = true
	music._process(2.0)
	music._process(1.0)
	assert(music.current_mode == 1 and music.playing,"boss music did not start during the entrance")
	assert(music.volume_db < music.BOSS_MIX_DB - 6.0,"boss music did not duck for the entrance")
	assert(music.get_child_count() == 0,"secondary music player can overlap tracks")
	assert(music.stream is AudioStreamOggVorbis and music.stream.loop,"boss music does not loop")
	assert(absf(music.stream.loop_offset - 9.23) < 0.01,"boss loop must skip the opening")
	assert(absf(music.stream.get_length() - 92.31) < 0.05,"unexpected boss track duration")
	var entrance_playback := music.get_stream_playback()
	var boss = stage2.PressKing.new()
	boss.health = 100.0
	stage2._press_king = boss
	stage2._boss_entrance.active = false
	music._process(1.0)
	assert(music.current_mode == 1 and music.stream == music.tracks[1],"boss music did not continue into combat")
	assert(music.get_stream_playback() == entrance_playback,"boss music restarted when combat began")
	boss.health = 0.0
	music._process(4.0)
	music._process(1.0)
	assert(music.current_mode == 0 and music.stream == music.tracks[0],"boss music continued after death")
	# Repeated scene/music initialization must retire the old source immediately.
	var replacement = load("res://scripts/tomatina_music.gd").new()
	replacement.world = stage2
	stage2.add_child(replacement)
	assert(music.retired and not music.playing,"old music source remained audible")
	music._process(1.0)
	assert(not music.playing,"retired source restarted")
	assert(replacement.playing,"replacement music did not start")
	boss.free()
	stage2.queue_free()
	await process_frame
	assert(not is_instance_valid(music),"music survived stage unload")
	print("TOMATINA_MUSIC_OK: boss entrance to combat, loop points, stage isolation, ducking, cleanup")
	quit()
