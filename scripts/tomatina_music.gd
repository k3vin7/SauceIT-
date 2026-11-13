extends AudioStreamPlayer
## Exactly one audible source. Fade out -> stop/swap -> fade in, never crossfade.
var world
const TRACK := "res://assets/audio/music/tomatina_trompeta.ogg"
const BOSS_TRACK := "res://assets/audio/music/tomatina_boss.ogg"
const MIX_DB := -22.0
var tracks: Array[AudioStreamOggVorbis] = []
var current_mode := 0
var music_gain := 0.0
var retired := false

func _ready() -> void:
	name = "TomatinaFestivalMusic"
	# Scope ownership to a viewport: separate network-test worlds remain independent.
	for other in get_tree().get_nodes_in_group("stage_bgm"):
		if other != self and other.get_viewport() == get_viewport():
			other.retire()
	add_to_group("stage_bgm")
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus < 0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count-1
		AudioServer.set_bus_name(music_bus,"Music")
		AudioServer.set_bus_send(music_bus,"Master")
	bus = "Music"
	for path in [TRACK,BOSS_TRACK]:
		var track := load(path) as AudioStreamOggVorbis
		if track == null:
			push_error("Stage music could not load: "+path)
			return
		track = track.duplicate() as AudioStreamOggVorbis
		track.loop = true
		tracks.append(track)
	stream = tracks[0]
	volume_db = -80.0
	play()

func _process(delta: float) -> void:
	if retired or tracks.size() != 2:
		return
	var cinematic := false
	if is_instance_valid(world):
		for key in ["_boss_entrance","_truck_arrival"]:
			var cutscene = world.get(key)
			if is_instance_valid(cutscene) and cutscene.active:
				cinematic = true
	var battle: bool = is_instance_valid(world) and is_instance_valid(world._press_king) and world._press_king.is_alive() and not cinematic
	var desired := 1 if battle else 0
	if desired != current_mode:
		music_gain = move_toward(music_gain,0.0,delta/0.25)
		if music_gain <= 0.0:
			stop()
			current_mode = desired
			stream = tracks[current_mode]
			play()
	else:
		music_gain = move_toward(music_gain,1.0,delta/0.45)
	var target := MIX_DB - float(current_mode)
	if cinematic:
		target -= 8.0
	elif is_instance_valid(world) and not world._input_enabled:
		target -= 5.0
	volume_db = target+linear_to_db(maxf(music_gain,0.0001))

func retire() -> void:
	retired = true
	stop()
	set_process(false)

func _exit_tree() -> void:
	stop()
