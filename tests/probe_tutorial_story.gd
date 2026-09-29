extends SceneTree

# The opening stretch as a story, checked by the order its events actually
# happened in.
#
# Every other tutorial check asks "did it end up in the right stage". This one
# asks whether the stages were *earned*: it records a timestamped log of stage
# changes, captions, player state transitions, the drone appearing and taking the
# burger, and top-ups being counted, and then asserts the order of that log.
#
# **Nothing here manufactures the result.** The party is driven with the same
# `debug_set_input` the other probes drive it with, the toasts are killed with the
# damage call a stream hit makes, and the escape is run on the keys. No player is
# teleported into the mess, `begin_slip` is never called, `_enter` is never
# called, and no stage timer is stretched to make something fit.
#
# Four scenarios, which have to come out differently from each other:
#
#   1. nothing is done          -- no drone, no congratulation, no progress
#   2. the instructions are followed -- prompt, run, slip, *then* rescue
#   3. the reaction is slow     -- same, and no stale order plays afterwards
#   4. the mess is walked round -- a dodge, and it is not called a rescue
#
# and one about the top-up counting from the moment it is asked for.

var failures: Array[String] = []

# --- the log ---------------------------------------------------------------
## Every entry is [seconds, kind, detail]. Kinds are plain strings so a failure
## can print the story back.
var log: Array = []
var _clock := 0.0
var _last_stage := -1
var _last_line := -1
var _last_state := {}
var _last_drone := false
var _last_grab := false
var _last_supplied := 0

var scene
var tutorial: MayoTutorial
var player: MayoPlayer


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _note(kind: String, detail: String) -> void:
	log.push_back([_clock, kind, detail])


## One physics step, with everything worth remembering written down.
func _step() -> void:
	_clock += 1.0 / float(Engine.physics_ticks_per_second)
	await physics_frame
	if tutorial == null:
		return
	# Bodies first, then the sequence. The player's own physics runs before the
	# world's -- `process_physics_priority` is -10 on the body -- so a fall and
	# the stage that reacts to it land on the same frame in that order, and
	# writing the stage down first would make the log say the drone beat the fall.
	for peer_id in scene.shooter_ids():
		var shooter = scene.shooter_for(peer_id)
		if shooter == null:
			continue
		var body: MayoPlayer = shooter.player
		var was: int = _last_state.get(peer_id, -1)
		if body.state != was:
			_last_state[peer_id] = body.state
			_note("state", "%d:%s" % [peer_id,
				MayoPlayer.State.keys()[body.state]])
	if tutorial.stage != _last_stage:
		_last_stage = tutorial.stage
		_note("stage", MayoTutorial.Stage.keys()[tutorial.stage])
	var line: int = tutorial.current_line_id()
	if line != _last_line:
		_last_line = line
		if line >= 0:
			_note("line", str(line))
	if tutorial.drone_alive != _last_drone:
		_last_drone = tutorial.drone_alive
		_note("drone", "up" if tutorial.drone_alive else "down")
	if tutorial.drone_has_it != _last_grab:
		_last_grab = tutorial.drone_has_it
		if tutorial.drone_has_it:
			_note("drone", "has the burger")
	if tutorial.supplied.size() != _last_supplied:
		_last_supplied = tutorial.supplied.size()
		_note("refill", "counted, %d so far" % _last_supplied)


func _run_steps(frames: int) -> void:
	for _f in frames:
		await _step()


## Runs until `condition`, logging as it goes. Returns whether it happened.
func _until(condition: Callable, frames := 3000) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await _step()
	return false


## The first entry of this kind and detail, or -1.
func _index_of(kind: String, detail: String) -> int:
	for index in log.size():
		if log[index][1] == kind and log[index][2] == detail:
			return index
	return -1


func _has(kind: String, detail: String) -> bool:
	return _index_of(kind, detail) >= 0


func _said(line_id: int) -> bool:
	return _has("line", str(line_id))


func _said_at(line_id: int) -> int:
	return _index_of("line", str(line_id))


func _print_log(title: String) -> void:
	print("--- %s ---" % title)
	for entry in log:
		print("   %6.2fs  %-6s %s" % [entry[0], entry[1], entry[2]])


# ---------------------------------------------------------------------------
# Getting a world as far as the escape, on the keys
# ---------------------------------------------------------------------------

func _fresh_world() -> void:
	log = []
	_clock = 0.0
	_last_stage = -1
	_last_line = -1
	_last_state = {}
	_last_drone = false
	_last_grab = false
	_last_supplied = 0
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	tutorial = scene.tutorial()
	player = scene._player


func _drop_world() -> void:
	scene.free()
	await process_frame
	scene = null
	tutorial = null
	player = null


## Walks to the light and fights the opening fight, both on the keys. Leaves the
## world at the moment the burger has been put down and is walking in.
func _play_to_the_escape() -> bool:
	await _until(func() -> bool: return tutorial.move_target() != Vector3.INF, 1800)
	var light: Vector3 = tutorial.move_target()
	for _f in 1800:
		if tutorial.stage != MayoTutorial.Stage.INTRO:
			break
		scene.debug_aim_at(Vector3(light.x, player.global_position.y, light.z))
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		await _step()
	scene.debug_set_input(Vector2.ZERO, false, false)

	if not await _until(func() -> bool:
			return tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT, 1800):
		return false
	# The toasts, killed with the call a stream hit makes, at the reach a stream
	# has. Nothing here reaches further than the bottle does.
	for _f in 2400:
		var alive := 0
		for index in tutorial.fight_enemies:
			var body: MayoEnemy = scene.enemy_at(index)
			if body == null or not body.is_alive():
				continue
			alive += 1
			if body.global_position.distance_to(player.global_position) \
					<= scene.stream_range:
				var guard := 0
				while body.is_alive() and guard < 4000:
					body.take_sauce_hit(body.global_position)
					guard += 1
		if alive == 0:
			break
		await _step()
	return await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES, 1800)


## Which way is away from the burger, flat.
func _away_from_monster() -> Vector3:
	var monster: MayoEnemy = scene.enemy_at(tutorial.monster_index)
	if monster == null:
		return Vector3.FORWARD
	var away: Vector3 = player.global_position - monster.global_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		return Vector3.FORWARD
	return away.normalized()


## Walks to a spot on the keys, stepping round whatever is in the way.
##
## The opening fight leaves toast corpses lying in the road and they keep their
## colliders, so a straight line at a stall can end against one. A player would
## step round it; so does this. Nothing is teleported.
func _walk_to(at: Vector3, frames: int) -> bool:
	var stuck := 0
	var was: Vector3 = player.global_position
	var side := 1.0
	for _f in frames:
		var to := Vector3(at.x - player.global_position.x, 0.0,
			at.z - player.global_position.z)
		if to.length() < 1.0:
			scene.debug_set_input(Vector2.ZERO, false, false)
			return true
		var aim: Vector3 = at
		if stuck > 30:
			aim = player.global_position \
				+ to.normalized().rotated(Vector3.UP, side * 0.9) * 6.0
			if stuck > 120:
				stuck = 31
				side = -side
		scene.debug_aim_at(Vector3(aim.x, player.global_position.y, aim.z))
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		if player.global_position.distance_to(was) < 0.04:
			stuck += 1
		else:
			stuck = 0
			was = player.global_position
		await _step()
	scene.debug_set_input(Vector2.ZERO, false, false)
	return false


## Faces away from the burger and holds forward. `run` picks Shift.
func _flee(run: bool) -> void:
	var away := _away_from_monster()
	scene.debug_aim_at(player.global_position + away * 10.0)
	scene.debug_set_input(Vector2(0.0, -1.0), run, false)


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

## 1. The toasts are dead and the player does nothing at all.
func _scenario_idle() -> void:
	await _fresh_world()
	if not await _play_to_the_escape():
		_check(false, "idle: never reached the escape")
		await _drop_world()
		return
	# Hands off the keys from here. Long enough that every old timer -- the 20 s
	# patience, the 1.1 s lunge -- would have fired several times over.
	await _run_steps(2400)
	_print_log("1. nothing is done")
	print("   ended in %s, drone up=%s, dodged=%s, rescued peer=%d" % [
		MayoTutorial.Stage.keys()[tutorial.stage], str(tutorial.drone_alive),
		str(tutorial.dodged), tutorial.rescue_peer])

	_check(not tutorial.drone_alive,
		"idle: the drone came out for a player who never moved")
	_check(not _has("drone", "up"),
		"idle: a drone appeared at some point without anybody being rescued")
	_check(not _said(MayoTutorial.SAY_STAYED_UP),
		"idle: told a motionless player they had dodged it")
	_check(not tutorial.dodged, "idle: a player who did nothing was recorded as dodging")
	_check(tutorial.rescue_peer == 0, "idle: somebody was recorded as rescued")
	_check(tutorial.stage == MayoTutorial.Stage.RUN,
		"idle: the sequence moved on to %s by itself"
			% MayoTutorial.Stage.keys()[tutorial.stage])
	# Being waited for is not being stuck: the order is repeated.
	var orders := 0
	for entry in log:
		if entry[1] == "line" and entry[2] == str(MayoTutorial.SAY_RUN_AWAY):
			orders += 1
	print("   the order to run was given %d times" % orders)
	_check(orders >= 2, "idle: the doctor never repeated himself")
	# And nothing chewed through them while they stood there.
	_check(player.health > player.max_health * 0.5,
		"idle: a player being waited for was worn down to %.0f health" % player.health)
	await _drop_world()


## 2. The instructions are followed: the prompt is read, then acted on.
func _scenario_follows() -> void:
	await _fresh_world()
	if not await _play_to_the_escape():
		_check(false, "follows: never reached the escape")
		await _drop_world()
		return
	# Waits for the order to actually be on screen before doing anything about
	# it. This is the ordering the whole file is about.
	var told := await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_RUN_AWAY, 1800)
	_check(told, "follows: the order to run never reached the screen")
	var told_at := log.size()
	# And only now: turn away and sprint. Into their own mess, which is where the
	# toasts died and the way out of it.
	for _f in 2400:
		_flee(true)
		if tutorial.drone_alive:
			break
		await _step()
	scene.debug_set_input(Vector2.ZERO, false, false)
	await _until(func() -> bool: return tutorial.drone_has_it, 900)
	# And on until the doctor has finished explaining what just happened: the
	# lesson is part of the rescue, so it is part of what is being checked.
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_GO_REFILL, 1800)
	_print_log("2. the instructions are followed")

	# The *first* time they were off their feet, not the last: FALLING comes
	# before DOWN, and taking the later of the two put the fall after the drone
	# that was reacting to it.
	var fell_at: int = _index_of("state", "1:FALLING")
	if fell_at < 0:
		fell_at = _index_of("state", "1:DOWN")
	var drone_at: int = _index_of("drone", "up")
	var order_at: int = _said_at(MayoTutorial.SAY_RUN_AWAY)
	print("   order at %d, fall at %d, drone at %d" % [order_at, fell_at, drone_at])
	_check(order_at >= 0, "follows: the order to run was never said")
	_check(fell_at >= 0, "follows: running into their own mess never put them down")
	_check(drone_at >= 0, "follows: nobody was rescued")
	_check(order_at < fell_at,
		"follows: they went over before being told to run")
	_check(fell_at < drone_at,
		"follows: the drone arrived before anybody had gone over")
	_check(tutorial.rescue_peer != 0,
		"follows: the rescue was not recorded against the player who fell")
	_check(not tutorial.dodged, "follows: a fall was recorded as a dodge")
	# The lesson matches what happened.
	_check(_said(MayoTutorial.SAY_THICK_IS_SLIPPERY),
		"follows: they went over and were never told why")
	_check(not _said(MayoTutorial.SAY_STAYED_UP),
		"follows: a player who went over was congratulated for staying up")
	# And the drone really did take it off them.
	_check(tutorial.drone_has_it, "follows: the drone never got the burger's attention")
	_check(told_at >= 0, "follows: log bookkeeping")
	await _drop_world()


## 3. The same, but slowly. The orders must not turn up after the rescue.
func _scenario_slow() -> void:
	await _fresh_world()
	if not await _play_to_the_escape():
		_check(false, "slow: never reached the escape")
		await _drop_world()
		return
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_RUN_AWAY, 1800)
	# Dithers for a few seconds before doing as they are told.
	await _run_steps(300)
	for _f in 2400:
		_flee(true)
		if tutorial.drone_alive:
			break
		await _step()
	scene.debug_set_input(Vector2.ZERO, false, false)
	await _run_steps(420)
	_print_log("3. the reaction is slow")

	var drone_at: int = _index_of("drone", "up")
	_check(drone_at >= 0, "slow: nobody was rescued")
	# Nothing that was an order may be on screen after the rescue began.
	for index in range(drone_at + 1, log.size()):
		if log[index][1] != "line":
			continue
		var said: int = int(log[index][2])
		_check(said != MayoTutorial.SAY_RUN_AWAY and said != MayoTutorial.SAY_TOO_CLOSE,
			"slow: the order to run was still being shouted after the rescue")
	await _drop_world()


## 4. The mess is crossed on foot and they get clear. Not a rescue.
func _scenario_dodge() -> void:
	await _fresh_world()
	if not await _play_to_the_escape():
		_check(false, "dodge: never reached the escape")
		await _drop_world()
		return
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_RUN_AWAY, 1800)
	# Walking, not sprinting: the floor only trips a runner, which is the lesson.
	# First onto the yellow, which is the bit being crossed...
	for _f in 1800:
		_flee(false)
		if scene.floor_is_slippery_at(player.global_position):
			break
		if tutorial.stage != MayoTutorial.Stage.RUN:
			break
		await _step()
	_check(scene.floor_is_slippery_at(player.global_position)
			or tutorial.stage != MayoTutorial.Stage.RUN,
		"dodge: the walk never reached the mess, so nothing was crossed")
	# ...and then on past it and out the far side, round the bodies the fight
	# left lying in the road.
	var beyond: Vector3 = player.global_position + _away_from_monster() * 30.0
	var monster: MayoEnemy = scene.enemy_at(tutorial.monster_index)
	for _f in 3000:
		if tutorial.stage != MayoTutorial.Stage.RUN:
			break
		if player.global_position.distance_to(beyond) < 2.0:
			beyond = player.global_position + _away_from_monster() * 30.0
		await _walk_to(beyond, 240)
		var gap: float = Vector2(player.global_position.x - monster.global_position.x,
			player.global_position.z - monster.global_position.z).length()
		print("   walking clear: at %.1v, on mayo=%s, burger %.1f m back (need %.0f)" % [
			player.global_position,
			str(scene.floor_is_slippery_at(player.global_position)), gap,
			MayoTutorial.DODGE_SAFE_GAP])
	scene.debug_set_input(Vector2.ZERO, false, false)
	# On until the doctor has said his piece about it: which piece he says is the
	# thing being checked.
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_GO_REFILL, 1800)
	_print_log("4. the mess is walked across")
	print("   dodged=%s, rescued peer=%d, ever off their feet=%s" % [
		str(tutorial.dodged), tutorial.rescue_peer,
		str(_has("state", "1:FALLING") or _has("state", "1:DOWN"))])

	_check(not _has("state", "1:FALLING") and not _has("state", "1:DOWN"),
		"dodge: the walker went over, so this is not the branch being tested")
	_check(tutorial.dodged, "dodge: crossing the mess on foot was not recognised")
	_check(tutorial.rescue_peer == 0,
		"dodge: a player who never fell was recorded as rescued")
	_check(_said(MayoTutorial.SAY_STAYED_UP),
		"dodge: they walked it and were not told so")
	_check(not _said(MayoTutorial.SAY_THICK_IS_SLIPPERY),
		"dodge: a player who never slipped was lectured about slipping")
	await _drop_world()


## 5. The top-up counts from the moment it is asked for.
func _scenario_refill_at_once() -> void:
	await _fresh_world()
	if not await _play_to_the_escape():
		_check(false, "refill: never reached the escape")
		await _drop_world()
		return
	await _until(func() -> bool:
		return tutorial.current_line_id() == MayoTutorial.SAY_RUN_AWAY, 1800)
	for _f in 2400:
		_flee(true)
		if tutorial.drone_alive:
			break
		await _step()
	scene.debug_set_input(Vector2.ZERO, false, false)
	# The instant the stall is pointed out -- which is the marker coming up, not
	# the stage turning over -- walk to it and press E.
	var pointed := await _until(func() -> bool:
		return tutorial.marker_position() != Vector3.INF, 1800)
	_check(pointed, "refill: the stall was never pointed out")
	var stage_then: int = tutorial.stage
	var station: Vector3 = tutorial.marker_position()
	var facing := Vector3.BACK
	for entry in scene._refill_stations:
		if (entry["position"] as Vector3).distance_to(station) < 0.01:
			facing = entry["facing"]
			break
	# Walked to the counter on the keys rather than placed at it.
	var stand: Vector3 = station + facing * (scene.refill_reach * 0.5)
	var arrived := await _walk_to(stand, 3000)
	_check(arrived, "refill: never walked to the stall that was pointed out")
	await _run_steps(10)
	# E, through the same request the key press goes through.
	scene._request_refill()
	await _run_steps(10)
	_print_log("5. the top-up is done as soon as it is asked for")
	print("   asked during %s, counted=%s" % [
		MayoTutorial.Stage.keys()[stage_then], str(tutorial.supplied.has(1))])

	_check(scene.station_in_reach(player) >= 0,
		"refill: the walk did not end at the counter")
	_check(tutorial.supplied.has(1),
		"refill: doing as told during %s was not counted"
			% MayoTutorial.Stage.keys()[stage_then])
	await _drop_world()


func _run() -> void:
	_check(not MayoTutorial.disabled,
		"this probe must run with the sequence switched on")
	await _scenario_idle()
	await _scenario_follows()
	await _scenario_slow()
	await _scenario_dodge()
	await _scenario_refill_at_once()

	if failures.is_empty():
		print("MAYO_TUTORIAL_STORY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
