extends SceneTree

# Screenshots of the opening stretch, for looking at rather than for asserting.
#
# Not headless: it needs a real rendering context, so it is run windowed. It walks
# the sequence to each beat worth seeing, points the camera at it and saves a PNG.
# Nothing here decides pass or fail -- `probe_tutorial` does that. This is the
# "does it actually read on screen" pass: which way things come from, whether the
# danger colour is visible, whether the marker and the captions are legible, and
# whether the burger fits down the street.
#
# Usage:
#   Godot --path . --rendering-driver opengl3 --resolution 1280x720 \
#         --script res://tests/capture_tutorial.gd -- --out=/some/directory

var _out := "/tmp"
var _shots: Array[String] = []

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


## Stands the player at `from` and points them at `target`.
##
## The yaw comes from `debug_aim_at`, which is the game's own "look at that" --
## hand-computed yaws were wrong twice here and produced shots of empty street
## next to the thing they were meant to show.
func _view(from: Vector3, target: Vector3) -> void:
	scene._player.global_position = Vector3(from.x,
		scene._player.global_position.y, from.z)
	scene._player.velocity = Vector3.ZERO
	await _wait(2)
	scene.debug_aim_at(target)
	await _wait(6)


## Stands the player at `at` and looks along the street at a fixed pitch, for the
## shots that are about the road rather than about one object.
func _look_from(at: Vector3, yaw_degrees: float, pitch_degrees: float) -> void:
	scene._player.global_position = Vector3(at.x, scene._player.global_position.y, at.z)
	scene._player.velocity = Vector3.ZERO
	scene.debug_set_aim(yaw_degrees, pitch_degrees)
	await _wait(6)


func _shot(label: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	# Down to something a reviewer can open side by side; the window is retina.
	if image.get_width() > 1600:
		image.resize(1600, int(1600.0 * float(image.get_height())
			/ float(image.get_width())), Image.INTERPOLATE_LANCZOS)
	var path := "%s/tutorial_%s.png" % [_out, label]
	var error := image.save_png(path)
	if error != OK:
		push_error("could not save %s" % path)
		return
	_shots.push_back(path)
	print("SHOT %-22s stage=%-16s %s" % [label,
		MayoTutorial.Stage.keys()[tutorial.stage], path])


func _hose_to_death(enemy: MayoEnemy) -> void:
	var guard := 0
	while enemy.is_alive() and guard < 4000:
		enemy.take_sauce_hit(enemy.global_position + Vector3(0.0, 0.0, 2.0))
		guard += 1


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	# Third person for every shot: the point is to see the player's own body in
	# the street along with whatever is coming at it.
	scene.set_first_person(false)
	tutorial = scene.tutorial()
	if tutorial == null:
		push_error("no tutorial to capture")
		quit(1)
		return
	var player: MayoPlayer = scene._player

	# --- 1. the blue light and the walk to it ------------------------------
	# First the greeting, with nothing lit: the light must not be giving the
	# instruction away before the doctor gets to it.
	await _until(func() -> bool:
		return tutorial.current_line() == MayoTutorial.LINES[MayoTutorial.SAY_HELLO], 900)
	print("  greeting: light in world=%s, marker=%s, objective='%s'" % [
		str(scene.get_node_or_null("TutorialMoveLight") != null),
		str(tutorial.marker_position() != Vector3.INF), tutorial.objective_text()])
	await _shot("00_greeting_nothing_lit")

	await _until(func() -> bool:
		return tutorial.move_target() != Vector3.INF, 1800)
	var light: Vector3 = tutorial.move_target()
	scene.debug_aim_at(Vector3(light.x, player.global_position.y, light.z))
	await _wait(30)
	print("  light at %.1v, player %.1v" % [light, player.global_position])
	await _shot("01_walk_to_the_light")

	# Walked there on the keys, which is what ends the stage.
	for _f in 1800:
		if tutorial.stage != MayoTutorial.Stage.INTRO:
			break
		scene.debug_aim_at(Vector3(light.x, player.global_position.y, light.z))
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		await process_frame
		await physics_frame
	scene.debug_set_input(Vector2.ZERO, false, false)
	await _wait(20)
	print("  briefing: frozen=%s" % str(player.frozen))
	await _shot("01b_briefing_holds_the_keys")

	# --- 2. the rushers, coming from the front -----------------------------
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT, 3600)
	# Let them close in so the shot has them in it rather than as dots.
	await _wait(260)
	await _look_from(player.global_position, 0.0, -6.0)
	await _shot("02_rushers_ahead")

	# --- 3. the mess they leave, and its colour ----------------------------
	var roster := []
	for index in tutorial.fight_enemies:
		roster.push_back(scene.enemy_at(index))
	var spill_at: Vector3 = roster[0].global_position
	for body in roster:
		_hose_to_death(body)
	await _wait(30)
	# From above and behind, so the puddles read as puddles.
	await _look_from(spill_at + Vector3(0.0, 0.0, 13.0), 0.0, -16.0)
	await _shot("03_danger_floor")

	# --- 4. the burger arriving from behind, and the arrow -----------------
	await _until(func() -> bool: return tutorial.monster_index >= 0, 3600)
	var monster: MayoEnemy = scene.enemy_at(tutorial.monster_index)
	# The cue: held still, with it put down behind them.
	scene.debug_aim_at(monster.global_position + Vector3(0.0, 2.5, 0.0))
	await _wait(10)
	print("  cue: frozen=%s, burger %.1f m behind" % [str(player.frozen),
		monster.global_position.distance_to(player.global_position)])
	await _shot("03b_behind_you_cue")
	# Facing up the street, the way a player running away would be: the monster is
	# behind, so this is the shot the arrow exists for. Up the street from it, the way a party that has started running would be.
	# Stood three metres in front of it the burger sits between the third-person
	# camera and the player, which is a true reading of "where is it" but a poor
	# picture of the case the arrow exists for.
	await _look_from(monster.global_position + Vector3(0.0, 0.0, -22.0), 0.0, -4.0)
	await _wait(60)
	var threat: Vector3 = tutorial.threat_position()
	print("  threat behind: %s (player %s) -- arrow should be drawn" % [
		str(threat.round()), str(scene._player.global_position.round())])
	await _shot("04_threat_behind_arrow")
	# And turned round to look at it.
	await _look_from(monster.global_position + Vector3(0.0, 0.0, -18.0), 180.0, -4.0)
	await _shot("05_burger_in_the_street")

	# --- 6. the drone in its face -----------------------------------------
	player.global_position = Vector3(spill_at.x, player.global_position.y, spill_at.z)
	await _until(func() -> bool: return tutorial.drone_alive, 3600)
	await _until(func() -> bool:
		return tutorial._drone != null and is_instance_valid(tutorial._drone), 240)
	# Long enough for the burger to have walked to it: the shot is meant to show
	# the two of them together, not the drone still on its way in.
	await _wait(360)
	# Framed on the spot the drone holds the burger at, not on where the burger
	# started: the burger walks to the drone, so the spot is where the pair of them
	# end up and is the only framing that reliably has both in shot.
	var anchor: Vector3 = tutorial.bait_anchor
	await _view(anchor + Vector3(11.0, 0.0, 2.0), anchor + Vector3(0.0, 3.0, 0.0))
	print("  drone at %s, burger at %s, anchor %s" % [
		str(tutorial._drone.global_position.round()),
		str(monster.global_position.round()), str(anchor.round())])
	await _shot("06_drone_baiting")

	# --- 7. the marked stall, from the road -------------------------------
	var station_at: Vector3 = tutorial._station_position
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.REFILL, 3600)
	var facing := Vector3.BACK
	for entry in scene._refill_stations:
		if (entry["position"] as Vector3).distance_to(station_at) < 0.01:
			facing = entry["facing"]
			break
	# Stood off the counter at about the distance a player walks up from, looking
	# at it: this is the shot for "can I find it, and am I close enough".
	var approach: Vector3 = station_at + facing * (scene.refill_reach * 2.2)
	await _view(approach, station_at + Vector3(0.0, 1.2, 0.0))
	await _shot("07_stall_marker_far")
	# And inside the reach, where the stall's own prompt appears.
	var close: Vector3 = station_at + facing * (scene.refill_reach * 0.5)
	await _view(close, station_at + Vector3(0.0, 1.2, 0.0))
	print("  at the counter: station_in_reach=%d (reach %.2f m)" % [
		scene.station_in_reach(player), scene.refill_reach])
	await _shot("08_stall_in_reach")

	# --- 9. the drone going down ------------------------------------------
	scene.refill_for(1)
	await _until(func() -> bool: return not tutorial.drone_alive, 3600)
	# Long enough for it to have hit the road: it is thrown clear and falls under
	# its own gravity, which takes most of a second from four metres up.
	await _wait(110)
	var wreck: Vector3 = tutorial._drone.global_position if \
		(tutorial._drone != null and is_instance_valid(tutorial._drone)) \
		else monster.global_position
	await _view(wreck + Vector3(3.2, 0.0, 3.2), wreck + Vector3(0.0, 0.3, 0.0))
	print("  wreck at %s, burger at %s" % [
		str(wreck.round()), str(monster.global_position.round())])
	await _shot("09_drone_wrecked")

	# --- 10. the coop fight, and the burger in the street ----------------
	await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.COOP_FIGHT, 3600)
	# Let it walk at the player for a while, then look at where it got to: this is
	# the shot for "does it fit down the street and past the stalls".
	# Inside the distance the burger notices a player from, measured off the body
	# rather than written down: parked 44 m up the street it simply never saw them,
	# and the shot was of a monster standing still for a reason that had nothing to
	# do with the tutorial.
	player.global_position = Vector3(monster.global_position.x,
		player.global_position.y, monster.global_position.z - monster.sight_range * 0.6)
	player.velocity = Vector3.ZERO
	var walked_from: Vector3 = monster.global_position
	await _wait(420)
	var walked: float = walked_from.distance_to(monster.global_position)
	print("  the burger walked %.1f m of the street unaided" % walked)
	await _view(player.global_position, monster.global_position + Vector3(0.0, 2.0, 0.0))
	await _shot("10_coop_fight")

	# --- 11. the completed stretch ---------------------------------------
	_hose_to_death(monster)
	await _until(func() -> bool: return tutorial.is_complete(), 1200)
	await _wait(20)
	await _shot("11_complete")

	print("CAPTURED %d shots into %s" % [_shots.size(), _out])
	quit(0)
