extends AudioStreamPlayer
## Scene-owned streamed music: one source per stage, freed with the stage.
var world
const TRACK := "res://assets/audio/music/tomatina_trompeta.ogg"
const MIX_DB := -22.0 # Keep music behind team voice communication.
const BOSS_TRACK := "res://assets/audio/music/tomatina_boss.ogg"
var boss_player: AudioStreamPlayer
var boss_mix := 0.0
func _ready() -> void:
	name = "TomatinaFestivalMusic"
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus < 0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus,"Music")
		AudioServer.set_bus_send(music_bus,"Master")
	bus = "Music"
	var track := load(TRACK) as AudioStreamOggVorbis
	if track == null:
		push_error("Tomatina festival BGM could not load")
		return
	track = track.duplicate() as AudioStreamOggVorbis
	track.loop = true
	stream = track
	volume_db = -45.0
	play()
	boss_player = AudioStreamPlayer.new()
	boss_player.name = "PressKingBattleMusic"
	boss_player.bus = "Music"
	var battle := load(BOSS_TRACK) as AudioStreamOggVorbis
	if battle != null:
		battle = battle.duplicate() as AudioStreamOggVorbis
		battle.loop = true
		boss_player.stream = battle
	boss_player.volume_db = -80.0
	add_child(boss_player)
func _process(delta: float) -> void:
	var battle_active := false
	var cinematic := false
	if is_instance_valid(world):
		cinematic = is_instance_valid(world._boss_entrance) and world._boss_entrance.active
		battle_active = is_instance_valid(world._press_king) and world._press_king.is_alive() and not cinematic
	if battle_active and is_instance_valid(boss_player) and not boss_player.playing:
		boss_player.play()
	boss_mix = lerpf(boss_mix,1.0 if battle_active else 0.0,1.0-exp(-delta*2.5))
	if is_instance_valid(boss_player):
		boss_player.volume_db = MIX_DB - 1.0 + linear_to_db(maxf(boss_mix,0.0001)) - (8.0 if cinematic else 0.0)
		if not battle_active and boss_mix < 0.001:
			boss_player.stop()
	var target := MIX_DB + linear_to_db(maxf(1.0-boss_mix,0.0001))
	if is_instance_valid(world):
		if is_instance_valid(world._boss_entrance) and world._boss_entrance.active:
			target -= 8.0
		elif not world._input_enabled:
			target -= 5.0
	volume_db = lerpf(volume_db,target,1.0-exp(-delta*2.8))
