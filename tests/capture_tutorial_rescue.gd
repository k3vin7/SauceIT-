extends SceneTree

# Screenshots of the two beats that have to read as cause and effect:
#
#   * the rescue -- the party goes down on their own mess, the drone comes in,
#     the burger turns after it, and they get up
#   * the hand-off -- the last bottle is filled, and from the stall the party can
#     still see the drone and the burger it is holding when it goes down
#
# Not headless: it needs a real rendering context, so it is run windowed. Nothing
# here decides pass or fail; `probe_tutorial` does that. This is the "can anybody
# tell what just happened" pass.
#
# Usage:
#   Godot --path . --rendering-driver opengl3 --resolution 1280x720 \
#         --script res://tests/capture_tutorial_rescue.gd -- --out=/some/directory

var _out := "/tmp"
var scene
var tutorial: MayoTutorial


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	call_deferred("_run")


func _wait(frames: int) -> void:
	for _f in frames:
		await process_frame
		await physics_frame


func _until(condition: Callable, frames := 3000) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await process_frame
		await physics_frame
	return false


func _shot(label: String, note := "") -> void:
	await _wait(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_width() > 1600:
		image.resize(1600, int(1600.0 * float(image.get_height())
			/ float(image.get_width())), Image.INTERPOLATE_LANCZOS)
	var path := "%s/rescue_%s.png" % [_out, label]
	if image.save_png(path) != OK:
		push_error("could not save %s" % path)
		return
	print("SHOT %-20s stage=%-14s %s" % [label,
		MayoTutorial.Stage.keys()[tutorial.stage], note])


func _hose_to_death(enemy: MayoEnemy) -> void:
	var guard := 0
	while enemy.is_alive() and guard < 4000:
		enemy.take_sauce_hit(enemy.global_position)
		guard += 1


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.set_first_person(false)
	tutorial = scene.tutorial()
	var player: MayoPlayer = scene._player

	# --- walk to the light, which is what opens the fight ------------------
	await _until(func() -> bool: return tutorial.move_target() != Vector3.INF, 1800)
	var light: Vector3 = tutorial.move_target()
	for _f in 1800:
		if tutorial.stage != MayoTutorial.Stage.INTRO:
			break
		scene.debug_aim_at(Vector3(light.x, player.global_position.y, light.z))
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		await process_frame
		await physics_frame
	scene.debug_set_input(Vector2.ZERO, false, false)

	# --- the opening fight, played the way a player plays it ---------------
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT, 3600)
	for _f in 1800:
		var alive := 0
		for index in tutorial.fight_enemies:
			var body: MayoEnemy = scene.enemy_at(index)
			if body == null or not body.is_alive():
				continue
			alive += 1
			# Killed at the reach the stream actually has, so the mess lands where
			# it would in a real fight rather than wherever a test put it.
			if body.global_position.distance_to(player.global_position) <= scene.stream_range:
				_hose_to_death(body)
		if alive == 0:
			break
		await physics_frame

	# --- and then they run, which is what the doctor just told them to do ---
	var monster: MayoEnemy = null
	var down_shot := false
	var drone_shot := false
	# The cue holds the keys for a beat while the burger is put down behind them.
	await _until(func() -> bool: return tutorial.allows_movement(), 900)
	# Waits for the order to actually be on screen, then acts on it -- the same
	# ordering `probe_tutorial_story` asserts, photographed.
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_RUN_AWAY, 1800)
	monster = scene.enemy_at(tutorial.monster_index) if tutorial.monster_index >= 0 else null
	if monster != null:
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 2.5, 0.0))
		await _wait(8)
		await _shot("00c_told_to_run", "line '%s', burger %.1f m, drone up=%s" % [
			tutorial.current_line(),
			monster.global_position.distance_to(player.global_position),
			str(tutorial.drone_alive)])
	# Turned round to watch it come in, which is the beat between the two lines.
	monster = scene.enemy_at(tutorial.monster_index) if tutorial.monster_index >= 0 else null
	if monster != null:
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 2.5, 0.0))
		await _wait(8)
		await _shot("00a_it_is_coming", "burger %.1f m away and walking" % \
			monster.global_position.distance_to(player.global_position))
		# And again once it is close enough for the doctor to say so.
		await _until(func() -> bool:
			return tutorial.stage == MayoTutorial.Stage.RUN, 1800)
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 2.5, 0.0))
		await _wait(6)
		await _shot("00b_too_close", "burger %.1f m away, line '%s'" % [
			monster.global_position.distance_to(player.global_position),
			tutorial.current_line()])
	# Turn away and sprint into their own mess, which is what the order says.
	if monster != null:
		var away: Vector3 = player.global_position - monster.global_position
		away.y = 0.0
		scene.debug_aim_at(player.global_position + away.normalized() * 10.0)
	scene.debug_set_input(Vector2(0.0, -1.0), true, false)
	for _f in 1200:
		if monster == null and tutorial.monster_index >= 0:
			monster = scene.enemy_at(tutorial.monster_index)
		# The moment they are on the floor with it still coming: this is the
		# frame the rescue has to beat.
		if not down_shot and player.state != MayoPlayer.State.NORMAL:
			down_shot = true
			scene.debug_set_input(Vector2.ZERO, false, false)
			if monster != null:
				scene.debug_aim_at(monster.global_position + Vector3(0.0, 2.0, 0.0))
			await _shot("01_down_and_coming",
				"burger %.1f m away, drone up=%s" % [
					monster.global_position.distance_to(player.global_position)
						if monster else -1.0, str(tutorial.drone_alive)])
		if not drone_shot and tutorial.drone_alive:
			drone_shot = true
			await _until(func() -> bool:
				return tutorial._drone != null and is_instance_valid(tutorial._drone), 240)
			if monster != null:
				scene.debug_aim_at(monster.global_position + Vector3(0.0, 3.0, 0.0))
			# Mid-flight: the drone is on its way and the burger is still coming
			# for the player on the floor.
			await _shot("02_drone_on_its_way",
				"player state %d, burger %.1f m away, has it=%s" % [
					player.state,
					monster.global_position.distance_to(player.global_position)
						if monster else -1.0, str(tutorial.drone_has_it)])
			# And the hand-off itself.
			await _until(func() -> bool: return tutorial.drone_has_it, 900)
			if monster != null:
				scene.debug_aim_at(monster.global_position + Vector3(0.0, 3.0, 0.0))
			await _wait(6)
			await _shot("02b_handed_over",
				"burger %.1f m away (bites at %.1f), baited=%s, health %.0f" % [
					monster.global_position.distance_to(player.global_position)
						if monster else -1.0,
					monster.radius + 0.64 + monster.contact_reach if monster else -1.0,
					str(monster != null and monster.bait != null), player.health])
			break
		await process_frame
		await physics_frame
	scene.debug_set_input(Vector2.ZERO, false, false)

	# --- on their feet again, with it busy elsewhere -----------------------
	await _until(func() -> bool: return player.state == MayoPlayer.State.NORMAL, 600)
	await _wait(150)
	if monster != null:
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 3.0, 0.0))
	await _shot("03_up_again_it_is_busy",
		"burger %.1f m away, baited=%s" % [
			monster.global_position.distance_to(player.global_position) if monster else -1.0,
			str(monster != null and monster.bait != null)])

	# --- the walk to the stall, and what can be seen from it ---------------
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.REFILL, 3600)
	var station: Vector3 = tutorial._station_position
	var facing := Vector3.BACK
	for entry in scene._refill_stations:
		if (entry["position"] as Vector3).distance_to(station) < 0.01:
			facing = entry["facing"]
			break
	player.global_position = station + facing * (scene.refill_reach * 0.5)
	player.velocity = Vector3.ZERO
	await _wait(10)
	var to_fight: float = station.distance_to(monster.global_position) if monster else -1.0
	# Turned round to look back at the fight they walked away from.
	if monster != null:
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 3.0, 0.0))
	await _shot("04_looking_back_from_the_stall",
		"stall is %.1f m from the burger" % to_fight)

	# --- the last bottle, then the hand-off --------------------------------
	var filled_at := Time.get_ticks_msec()
	scene.refill_for(1)
	await _wait(60)
	await _shot("05_just_after_refilling",
		"drone up=%s, stage waits" % str(tutorial.drone_alive))
	# Facing the stall, backs to the fight: this is the moment the arrow exists for.
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.DRONE_DOWN, 2400)
	scene.debug_aim_at(station + facing * -6.0 + Vector3(0.0, 1.5, 0.0))
	await _wait(20)
	await _shot("05b_warned_with_back_turned",
		"threat arrow target %s" % str(tutorial.threat_position().round()))
	var went := await _until(func() -> bool: return not tutorial.drone_alive, 2400)
	print("  drone went down: %s, %.1f s after the last bottle was filled" % [
		str(went), float(Time.get_ticks_msec() - filled_at) / 1000.0])
	await _wait(60)
	if monster != null:
		scene.debug_aim_at(monster.global_position + Vector3(0.0, 3.0, 0.0))
	await _shot("06_drone_goes_down", "burger back on the party")

	print("CAPTURED into %s" % _out)
	quit(0)
