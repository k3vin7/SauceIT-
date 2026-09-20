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

	print("tank holds %.0f s of fire; a press runs %.2f s full, %.2f s at %.0f%%, %.2f s empty" % [
		scene.sauce_capacity_seconds, scene.full_burst_seconds, scene.half_burst_seconds,
		scene.burst_midpoint * 100.0, scene.empty_burst_seconds])

	# --- the curve itself ---
	# The three pinned points land where they are set to.
	var full: float = scene.burst_seconds_at(1.0)
	var middle: float = scene.burst_seconds_at(scene.burst_midpoint)
	var empty: float = scene.burst_seconds_at(0.0)
	print("allowance: full %.2f s, %.0f%% %.2f s, empty %.2f s" % [
		full, scene.burst_midpoint * 100.0, middle, empty])
	_check(is_equal_approx(full, scene.full_burst_seconds),
		"a full tank allows %.2f s, not %.2f" % [full, scene.full_burst_seconds])
	_check(is_equal_approx(middle, scene.half_burst_seconds),
		"a %.0f%% tank allows %.2f s, not %.2f" % [
			scene.burst_midpoint * 100.0, middle, scene.half_burst_seconds])
	_check(is_equal_approx(empty, scene.empty_burst_seconds),
		"an empty tank allows %.2f s, not %.2f" % [empty, scene.empty_burst_seconds])

	# And it falls the whole way down -- no level at which it stops shrinking,
	# which is the difference between this curve and the one it replaced.
	var steps := 40
	var previous: float = scene.burst_seconds_at(1.0) + 1.0
	var flat_spots := 0
	var rises := 0
	for step in steps + 1:
		var level := 1.0 - float(step) / float(steps)
		var allowance: float = scene.burst_seconds_at(level)
		if allowance > previous + 0.0001:
			rises += 1
		elif allowance > previous - 0.0001:
			flat_spots += 1
		previous = allowance
	print("walking the tank down in %d steps: %d rises, %d flat spots" % [steps, rises, flat_spots])
	_check(rises == 0, "the allowance goes back up %d times as the tank empties" % rises)
	_check(flat_spots == 0,
		"the allowance stops shrinking for %d of %d steps down the tank" % [flat_spots, steps])
	# The last squirt is still a squirt, not a puff the minimum swallows.
	_check(scene.empty_burst_seconds > scene.minimum_fire_time,
		"an empty tank allows %.2f s, under the %.2f s every press gets anyway" % [
			scene.empty_burst_seconds, scene.minimum_fire_time])

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
	shooter.sauce = scene.burst_midpoint
	var at_half := await _hold(scene, 6.0)
	await _idle(scene, 0.4)
	shooter.sauce = 0.05
	var at_dregs := await _hold(scene, 6.0)
	print("same press: full %.2f s, %.0f%% %.2f s, nearly dry %.2f s" % [
		at_full.seconds, scene.burst_midpoint * 100.0, at_half.seconds, at_dregs.seconds])
	_check(at_half.seconds < at_full.seconds - 0.2,
		"a %.0f%% tank gave %.2f s against a full tank's %.2f: the tank is not shortening the squirt"
			% [scene.burst_midpoint * 100.0, at_half.seconds, at_full.seconds])
	# And it keeps shortening past the half mark, in the game rather than only
	# in the curve.
	_check(at_dregs.seconds < at_half.seconds - 0.1,
		"a nearly dry tank gave %.2f s, no shorter than the %.2f s a half tank gave"
			% [at_dregs.seconds, at_half.seconds])

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
	print("refill stalls: %d, reach %.1f m from the counter" % [
		stations.size(), scene.refill_reach])
	_check(stations.size() == StreetMap.stall_boxes().size(),
		"%d of the %d stalls serve sauce" % [stations.size(), StreetMap.stall_boxes().size()])
	# The red machines are scenery: the sauce comes from the blue stalls.
	_check(stations.size() > StreetMap.vending_boxes().size(),
		"the refill points look like the vending machines rather than the stalls")

	var station: Dictionary = stations[0]
	var stand_y: float = scene.spawn_position_for(0).y
	var player: MayoPlayer = scene._player

	# Standing in front of one, within reach.
	await _idle(scene, 0.2)
	player.global_position = station["position"] \
		+ station["facing"] * (scene.refill_reach * 0.6) + Vector3(0.0, stand_y, 0.0)
	player.global_position.y = stand_y
	await physics_frame
	_check(scene.station_in_reach(player) >= 0,
		"standing %.1f m in front of a stall counter is not in reach"
			% (scene.refill_reach * 0.6))
	_check(scene.local_at_station(), "the prompt does not show at a stall")
	shooter.sauce = 0.2
	shooter.burst_locked = true
	_check(scene.refill_for(scene._local.peer_id), "the stall refused to fill the bottle")
	print("at the stall: tank 0.20 -> %.2f, trigger re-armed %s" % [
		shooter.sauce, str(not shooter.burst_locked)])
	_check(is_equal_approx(shooter.sauce, 1.0),
		"the stall filled the tank to %.2f rather than full" % shooter.sauce)
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
		"a stall served from %.1f m away" % (scene.refill_reach + 2.0))
	shooter.sauce = 0.2
	_check(not scene.refill_for(scene._local.peer_id),
		"a stall filled the bottle from across the street")
	_check(is_equal_approx(shooter.sauce, 0.2), "an out-of-reach stall changed the tank")

	player.global_position = station["position"] \
		- station["facing"] * (scene.refill_reach * 0.6)
	player.global_position.y = stand_y
	await physics_frame
	print("behind it at %.1f m: in reach %s" % [
		scene.refill_reach * 0.6, str(scene.station_in_reach(player) >= 0)])
	_check(scene.station_in_reach(player) < 0,
		"the stall serves from behind, through its own back wall")

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
	_check(is_zero_approx(dry.seconds),
		"an empty tank still put out %.2f s of sauce; it must put out nothing"
			% dry.seconds)
	# The very last of the tank still fires, so "empty" means empty rather than
	# "nearly empty".
	shooter.sauce = 0.02
	shooter.burst_locked = false
	var dregs := await _hold(scene, 1.5)
	print("2%% left, 1.5 s on the button: %.2f s of sauce" % dregs.seconds)
	_check(dregs.seconds > 0.0, "a tank with something left in it fired nothing")

	if failures.is_empty():
		print("MAYO_SAUCE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
