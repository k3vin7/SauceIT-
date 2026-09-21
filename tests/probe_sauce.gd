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


## Holds the trigger for `seconds` and reports what came out: every unbroken run
## of sauce and every pause between them. Holding now restarts by itself after
## the pause, so "how long did it fire" is no longer one number -- the first run
## and the gap after it are the two the checks care about.
func _hold(scene, seconds: float) -> Dictionary:
	var shooter = scene._local
	var bursts: Array[int] = []
	var gaps: Array[int] = []
	var run := 0
	var was := false
	var started := false
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _f in int(seconds * 60.0):
		await physics_frame
		var now: bool = shooter.was_firing
		if now != was:
			if was:
				bursts.push_back(run)
			elif started:
				gaps.push_back(run)
			run = 0
		if now:
			started = true
		run += 1
		was = now
	if was:
		bursts.push_back(run)
	scene.debug_set_input(Vector2.ZERO, false, false)
	var total := 0
	for burst in bursts:
		total += burst
	return {
		"seconds": float(total) / 60.0,
		"first": (float(bursts[0]) / 60.0) if not bursts.is_empty() else 0.0,
		"bursts": bursts.size(),
		"gap": (float(gaps[0]) / 60.0) if not gaps.is_empty() else 0.0,
	}


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
		scene.sauce_seconds_left(1.0), scene.full_burst_seconds, scene.half_burst_seconds,
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

	# --- a full tank cuts at the allowance, then comes back on its own ---
	shooter.sauce = 1.0
	var long_hold := await _hold(scene, scene.full_burst_seconds * 2.0 + scene.spent_burst_cooldown + 1.5)
	print("button held down: first squirt %.2f s, then %.2f s of nothing, %d squirts in all" % [
		long_hold.first, long_hold.gap, long_hold.bursts])
	# The squirt is cut but still runs out its minimum, so it overshoots by that.
	_check(long_hold.first >= scene.full_burst_seconds - 0.1
			and long_hold.first <= scene.full_burst_seconds + scene.minimum_fire_time + 0.1,
		"a full-tank press ran %.2f s rather than about %.2f" % [
			long_hold.first, scene.full_burst_seconds])
	# Holding through the pause starts the next one without letting go.
	_check(long_hold.bursts >= 2,
		"holding the button gave %d squirt(s): it never came back after the pause"
			% long_hold.bursts)
	# And the pause is the long one, not the short between-taps one.
	_check(absf(long_hold.gap - scene.spent_burst_cooldown) < 0.1,
		"the pause after a spent squirt was %.2f s, not the %.2f s cooldown" % [
			long_hold.gap, scene.spent_burst_cooldown])
	_check(scene.spent_burst_cooldown > scene.fire_cooldown_time,
		"the spent-squirt pause (%.2f s) is no longer than the between-taps one (%.2f s)"
			% [scene.spent_burst_cooldown, scene.fire_cooldown_time])

	# --- letting go and pressing again still works ---
	await _idle(scene, 0.6)
	var again := await _hold(scene, 0.6)
	print("after letting go, a 0.6 s press put out %.2f s" % again.seconds)
	_check(again.seconds > 0.3, "the trigger did not fire again after being released")

	# --- the allowance follows the tank down ---
	# Measured inside the steady band on purpose. Below it the nozzle is
	# unreliable and a press is broken up by catches, so a stopwatch on the
	# first unbroken run of sauce would be measuring the dice and not the
	# allowance. The bands are their own section below.
	await _idle(scene, 0.4)
	shooter.sauce = 1.0
	var at_full := await _hold(scene, 6.0)
	await _idle(scene, 0.8)
	var lower: float = (scene.steady_level + 1.0) * 0.5
	shooter.sauce = lower
	var at_lower := await _hold(scene, 6.0)
	await _idle(scene, 0.8)
	var lowest: float = scene.steady_level + 0.02
	shooter.sauce = lowest
	var at_lowest := await _hold(scene, 6.0)
	print("first squirt of a press: full %.2f s, %.0f%% %.2f s, %.0f%% %.2f s" % [
		at_full.first, lower * 100.0, at_lower.first, lowest * 100.0, at_lowest.first])
	_check(at_lower.first < at_full.first,
		"a %.0f%% tank gave %.2f s against a full tank's %.2f: the tank is not shortening the squirt"
			% [lower * 100.0, at_lower.first, at_full.first])
	_check(at_lowest.first < at_lower.first,
		"a %.0f%% tank gave %.2f s, no shorter than the %.2f s a %.0f%% tank gave"
			% [lowest * 100.0, at_lowest.first, at_lower.first, lower * 100.0])

	# --- the allowance is fixed when the squirt starts ---
	# Draining during the squirt must not shorten the squirt that is spending it.
	await _idle(scene, 0.4)
	shooter.sauce = 1.0
	scene.debug_set_input(Vector2.ZERO, false, true)
	# Captured once the squirt is actually under way. Pressing into the tail of
	# the last one's cooldown means nothing starts for a few frames, and the
	# allowance read on frame one is the *previous* squirt's -- which then
	# "changes" when the real one begins.
	for _f in 60:
		await physics_frame
		if shooter.was_firing:
			break
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
	_check(scene.refill_for(scene._local.peer_id), "the stall refused to fill the bottle")
	print("at the stall: tank 0.20 -> %.2f" % shooter.sauce)
	_check(is_equal_approx(shooter.sauce, 1.0),
		"the stall filled the tank to %.2f rather than full" % shooter.sauce)
	# And a full tank means a full-length squirt again.
	var after_refill := await _hold(scene, scene.full_burst_seconds + 1.0)
	print("after refilling, the first squirt ran %.2f s" % after_refill.first)
	_check(after_refill.first >= scene.full_burst_seconds - 0.1,
		"a refilled tank only gave %.2f s" % after_refill.first)

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
	var dry := await _hold(scene, 1.5)
	print("dry tank, 1.5 s on the button: %.2f s of sauce" % dry.seconds)
	_check(is_zero_approx(dry.seconds),
		"an empty tank still put out %.2f s of sauce; it must put out nothing"
			% dry.seconds)
	# A bottle with a little left in it no longer puts out sauce either -- that
	# is what the bottom band is -- but it does blow air, which is a different
	# thing from the trigger being dead.
	shooter.sauce = scene.spluttering_level * 0.5
	scene.debug_set_input(Vector2.ZERO, false, true)
	var air_frames := 0
	var sauce_frames := 0
	# Only while the press itself is alive: the squirt allowance and its
	# cooldown still apply down here, so a longer window would be counting the
	# pause between presses as a failure to blow air.
	for _f in 15:
		await physics_frame
		if shooter.nozzle == scene.Nozzle.AIR:
			air_frames += 1
		if shooter.was_firing:
			sauce_frames += 1
	scene.debug_set_input(Vector2.ZERO, false, false)
	print("%.0f%% left: %d of 15 frames blowing air, %d delivering sauce" % [
		scene.spluttering_level * 50.0, air_frames, sauce_frames])
	_check(air_frames >= 14,
		"a bottle in the bottom band blew air on only %d of 15 frames" % air_frames)
	_check(sauce_frames == 0,
		"a bottle in the bottom band still delivered sauce on %d frames" % sauce_frames)

	if failures.is_empty():
		print("MAYO_SAUCE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
