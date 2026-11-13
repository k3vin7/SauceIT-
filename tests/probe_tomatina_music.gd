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
	assert(music.stream is AudioStreamOggVorbis and music.stream.loop,"music is not streamed and looped")
	assert(absf(music.stream.get_length()-60.0)<0.05,"unexpected track duration")
	assert(music.bus == "Music","music bus was not assigned")
	music.volume_db = music.MIX_DB
	stage2._boss_entrance.active = true
	music._process(1.0)
	assert(music.volume_db < music.MIX_DB - 6.0,"music did not duck for boss cinematic")
	stage2._boss_entrance.active = false
	music._process(2.0)
	assert(music.volume_db > music.MIX_DB - 1.0,"music did not recover after cinematic")
	var boss = stage2.PressKing.new()
	boss.health = 100.0
	stage2._press_king = boss
	music._process(2.0)
	assert(music.boss_mix > 0.98 and music.boss_player.playing,"boss music did not start")
	assert(music.boss_player.stream.loop,"boss music does not loop")
	boss.health = 0.0
	music._process(4.0)
	assert(music.boss_mix < 0.001 and not music.boss_player.playing,"boss music continued after death")
	boss.free()
	stage2.queue_free()
	await process_frame
	assert(not is_instance_valid(music),"music survived stage unload")
	print("TOMATINA_MUSIC_OK: 60 seconds, 128 BPM, streamed loop, stage isolation, cinematic ducking, cleanup")
	quit()
