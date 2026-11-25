extends AudioStreamPlayer
## Exactly one audible source. Fade out -> stop/swap -> fade in, never crossfade.
var world
const TRACK := "res://assets/audio/music/tomatina_main.mp3"
const BOSS_TRACK := "res://assets/audio/music/tomatina_boss_mischievous.ogg"
const MIX_DB := -22.0
const BOSS_MIX_DB := -19.0
var tracks: Array[AudioStream] = []
var current_mode := 0
var music_gain := 0.0
var retired := false
var priority_duck := false

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
		var track := load(path) as AudioStream
		if track == null:
			push_error("Stage music could not load: "+path)
			return
		track = track.duplicate() as AudioStream
		track.set("loop", true)
		tracks.append(track)
	stream = tracks[0]
	volume_db = -80.0
	play()

func _process(delta: float) -> void:
	if retired or tracks.size() != 2:
		return
	var has_world := is_instance_valid(world)
	var entrance = world._boss_entrance if has_world else null
	var truck_arrival = world._truck_arrival if has_world else null
	var entering: bool = is_instance_valid(entrance) and entrance.active
	var truck_cinematic: bool = is_instance_valid(truck_arrival) and truck_arrival.active
	var battle: bool = has_world and is_instance_valid(world._press_king) and world._press_king.is_alive()
	var desired := 1 if (entering or battle) and not truck_cinematic else 0
	if desired != current_mode:
		music_gain = move_toward(music_gain,0.0,delta/0.25)
		if music_gain <= 0.0:
			stop()
			current_mode = desired
			stream = tracks[current_mode]
			var start_at := 0.0
			if current_mode == 1:
				var combat_start := (stream as AudioStreamOggVorbis).loop_offset
				start_at = combat_start
				if entering:
					# Land on the first combat downbeat when the player regains control.
					var remaining: float = entrance.DURATION - entrance.elapsed
					start_at = clampf(combat_start - remaining, 0.0, combat_start)
			play(start_at)
	else:
		music_gain = move_toward(music_gain,1.0,delta/0.45)
	var target := BOSS_MIX_DB if current_mode == 1 else MIX_DB
	if priority_duck:
		target -= 7.0
	if entering or truck_cinematic:
		target -= 8.0
	elif is_instance_valid(world) and world.tomatina_intro_active():
		target -= world._tomatina_intro.music_duck()
	elif is_instance_valid(world) and not world._input_enabled:
		target -= 5.0
	volume_db = target+linear_to_db(maxf(music_gain,0.0001))

func retire() -> void:
	retired = true
	stop()
	set_process(false)

func _exit_tree() -> void:
	stop()
