extends SceneTree

# The squirt length limit:
#
#   * a full tank gives about `full_burst_seconds` of held fire and then cuts,
#     whether or not the button is still down
#   * keeping the button down does not start another one -- letting go does
#   * the allowance shrinks with the tank, down to a floor it does not go under
#   * the tank drains only while firing, and the limit is fixed when the squirt
#     starts rather than shrinking underneath it
#   * an empty tank fires nothing

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


## Holds the trigger for `seconds` and reports how long sauce actually came out
## for, in one unbroken run from the first frame it fired.
func _hold(scene, seconds: float) -> Dictionary:
	var shooter = scene._local
	var fired := 0
	var gaps := 0
	var was := false
	var started := false
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _f in int(seconds * 60.0):
		await physics_frame
		var now: bool = shooter.was_firing
		if now:
			started = true
			fired += 1
		elif started and not now and was:
			gaps += 1
		was = now
	scene.debug_set_input(Vector2.ZERO, false, false)
	return {"seconds": float(fired) / 60.0, "restarts": maxi(gaps - 1, 0)}


func _idle(scene, seconds: float) -> void:
	scene.debug_set_input(Vector2.ZERO, false, false)
	for _f in int(seconds * 60.0):
		await physics_frame


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.debug_input_override = true
	var shooter = scene._local

	print("tank holds %.0f s of fire; a press runs %.1f s at full, %.1f s from %.0f%% down" % [
		scene.sauce_capacity_seconds, scene.full_burst_seconds,
		scene.low_burst_seconds, scene.burst_floor_at * 100.0])

	# --- the curve itself ---
	var full: float = scene.burst_seconds_at(1.0)
	var floor_level: float = scene.burst_seconds_at(scene.burst_floor_at)
	var nearly_dry: float = scene.burst_seconds_at(0.02)
	var half_way: float = scene.burst_seconds_at((1.0 + scene.burst_floor_at) * 0.5)
	print("allowance: full %.2f s, %.0f%% %.2f s, half of that %.2f s, nearly dry %.2f s" % [
		full, scene.burst_floor_at * 100.0, floor_level, half_way, nearly_dry])
	_check(is_equal_approx(full, scene.full_burst_seconds),
		"a full tank allows %.2f s, not %.2f" % [full, scene.full_burst_seconds])
	_check(is_equal_approx(floor_level, scene.low_burst_seconds),
		"at the floor it allows %.2f s, not %.2f" % [floor_level, scene.low_burst_seconds])
	_check(is_equal_approx(nearly_dry, scene.low_burst_seconds),
		"nearly dry it allows %.2f s rather than holding the %.2f s floor" % [
			nearly_dry, scene.low_burst_seconds])
	_check(half_way > floor_level and half_way < full,
		"the allowance does not fall smoothly between full and the floor")

	# --- a full tank cuts at the allowance, with the button still down ---
	shooter.sauce = 1.0
	var long_hold := await _hold(scene, scene.full_burst_seconds + 2.5)
	print("held the button %.1f s on a full tank: sauce came out for %.2f s, restarts %d" % [
		scene.full_burst_seconds + 2.5, long_hold.seconds, long_hold.restarts])
	# The squirt is cut but still runs out its minimum, so it overshoots by that.
	_check(long_hold.seconds >= scene.full_burst_seconds - 0.1
			and long_hold.seconds <= scene.full_burst_seconds + scene.minimum_fire_time + 0.1,
		"a full-tank press ran %.2f s rather than about %.2f" % [
			long_hold.seconds, scene.full_burst_seconds])
	# And holding it down does not buy another squirt.
	_check(long_hold.restarts == 0,
		"holding the button started %d more squirts: the limit is not a limit"
			% long_hold.restarts)
	_check(shooter.burst_locked, "the trigger was not locked after running its allowance")

	# --- letting go re-arms it ---
	await _idle(scene, 0.4)
	_check(not shooter.burst_locked, "letting go of the trigger did not re-arm it")
	var again := await _hold(scene, 0.6)
	print("after letting go, a 0.6 s press put out %.2f s" % again.seconds)
	_check(again.seconds > 0.3, "the trigger did not fire again after being released")

	# --- the allowance follows the tank down ---
	await _idle(scene, 0.2)
	shooter.sauce = 1.0
	var at_full := await _hold(scene, 6.0)
	await _idle(scene, 0.4)
	shooter.sauce = scene.burst_floor_at
	var at_floor := await _hold(scene, 6.0)
	print("same press, full tank %.2f s vs %.0f%% tank %.2f s" % [
		at_full.seconds, scene.burst_floor_at * 100.0, at_floor.seconds])
	_check(at_floor.seconds < at_full.seconds - 0.5,
		"a %.0f%% tank gave %.2f s against a full tank's %.2f: the tank is not shortening the squirt"
			% [scene.burst_floor_at * 100.0, at_floor.seconds, at_full.seconds])

	# --- the allowance is fixed when the squirt starts ---
	# Draining during the squirt must not shorten the squirt that is spending it.
	await _idle(scene, 0.4)
	shooter.sauce = 1.0
	scene.debug_set_input(Vector2.ZERO, false, true)
	await physics_frame
	var allowance: float = shooter.burst_allowance
	for _f in 30:
		await physics_frame
	var mid_tank: float = shooter.sauce
	print("half a second in: tank %.2f -> %.2f, allowance still %.2f s (would now be %.2f)" % [
		1.0, mid_tank, shooter.burst_allowance, scene.burst_seconds_at(mid_tank)])
	_check(is_equal_approx(shooter.burst_allowance, allowance),
		"the allowance moved from %.2f to %.2f while the squirt was spending it" % [
			allowance, shooter.burst_allowance])
	_check(mid_tank < 1.0, "firing did not drain the tank")
	scene.debug_set_input(Vector2.ZERO, false, false)

	# --- the refill stations ---
	# The tank does not fill itself any more, so a station has to actually work
	# or the bottle is a one-use item.
	_check(is_zero_approx(scene.sauce_refill_per_second),
		"the tank still trickles back at %.3f/s; the stations are meant to be the refill"
			% scene.sauce_refill_per_second)
	var stations: Array = scene._refill_stations
	print("refill stations: %d, reach %.1f m" % [stations.size(), scene.refill_reach])
	_check(stations.size() > 0, "there are no refill stations on the map")

	var station: Dictionary = stations[0]
	var stand_y: float = scene.spawn_position_for(0).y
	var player: MayoPlayer = scene._player

	# Standing in front of one, within reach.
	await _idle(scene, 0.2)
	player.global_position = station["position"] \
		+ station["facing"] * (scene.refill_reach * 0.6) + Vector3(0.0, stand_y, 0.0)
	player.global_position.y = stand_y
	await physics_frame
	_check(scene.station_in_reach(player) == 0,
		"standing %.1f m in front of a station is not in reach" % (scene.refill_reach * 0.6))
	_check(scene.local_at_station(), "the prompt does not show at a station")
	shooter.sauce = 0.2
	shooter.burst_locked = true
	_check(scene.refill_for(scene._local.peer_id), "the station refused to fill the bottle")
	print("at the station: tank 0.20 -> %.2f, trigger re-armed %s" % [
		shooter.sauce, str(not shooter.burst_locked)])
	_check(is_equal_approx(shooter.sauce, 1.0),
		"the station filled the tank to %.2f rather than full" % shooter.sauce)
	_check(not shooter.burst_locked,
		"the tank was filled but the trigger is still locked from running dry")
	# And a full tank means a full-length squirt again.
	var after_refill := await _hold(scene, scene.full_burst_seconds + 1.5)
	print("after refilling, a long press put out %.2f s" % after_refill.seconds)
	_check(after_refill.seconds >= scene.full_burst_seconds - 0.1,
		"a refilled tank only gave %.2f s" % after_refill.seconds)

	# Out of reach, and behind it, are both refused -- the second because a
	# station bolted to a wall must not be usable through that wall.
	await _idle(scene, 0.2)
	player.global_position = station["position"] \
		+ station["facing"] * (scene.refill_reach + 2.0)
	player.global_position.y = stand_y
	await physics_frame
	_check(scene.station_in_reach(player) < 0,
		"a station reached %.1f m away" % (scene.refill_reach + 2.0))
	shooter.sauce = 0.2
	_check(not scene.refill_for(scene._local.peer_id),
		"a station filled the bottle from across the street")
	_check(is_equal_approx(shooter.sauce, 0.2), "an out-of-reach station changed the tank")

	player.global_position = station["position"] \
		- station["facing"] * (scene.refill_reach * 0.6)
	player.global_position.y = stand_y
	await physics_frame
	print("behind it at %.1f m: in reach %s" % [
		scene.refill_reach * 0.6, str(scene.station_in_reach(player) >= 0)])
	_check(scene.station_in_reach(player) < 0,
		"the station can be used from behind, through the wall it is bolted to")

	# --- the tank only drains while firing ---
	await _idle(scene, 0.5)
	shooter.sauce = 0.5
	var quiet_before: float = shooter.sauce
	await _idle(scene, 0.5)
	print("half a second idle: tank %.3f -> %.3f" % [quiet_before, shooter.sauce])
	_check(is_equal_approx(shooter.sauce, quiet_before),
		"the tank moved by %.3f while nothing was being fired and nothing was refilling"
			% absf(shooter.sauce - quiet_before))

	# --- an empty tank fires nothing ---
	await _idle(scene, 0.4)
	shooter.sauce = 0.0
	shooter.burst_locked = false
	var dry := await _hold(scene, 1.5)
	print("dry tank, 1.5 s on the button: %.2f s of sauce" % dry.seconds)
	_check(dry.seconds <= scene.minimum_fire_time + 0.05,
		"an empty tank still put out %.2f s of sauce" % dry.seconds)

	if failures.is_empty():
		print("MAYO_SAUCE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
