extends SceneTree

# The flamethrower answer: connection state, the spray that tells a body from a
# kerb, the shove, and the slowdown. None of these is an event -- the whole
# point is that each is readable on any frame while the stream is on a monster,
# because a continuous weapon has no hit moment to punctuate.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)

	var enemy = scene.enemy_at(0)
	var player = scene._local.player
	# Stand the monster in front of the player and aim at it.
	enemy.authority = true
	enemy.global_position = player.global_position \
		+ Vector3(0.0, enemy.stand_height() - 1.0, -6.0)
	enemy.nav = null
	await physics_frame
	scene.debug_aim_at(enemy.global_position)

	# --- off target: the reticle is cold -----------------------------------
	print("before firing: connection %.3f" % scene._local.connection)
	_check(scene._local.connection < 0.01, "the reticle was lit before firing")

	# --- on target: everything changes at once ------------------------------
	var health_at: float = enemy.health
	scene.debug_set_input(Vector2.ZERO, false, true)
	var lit := 0.0
	for _i in 60:
		await physics_frame
		lit = maxf(lit, scene._local.connection)
	var crosshair: Crosshair = scene._crosshair as Crosshair
	print("on target: connection %.3f, reticle %.3f, health %.1f -> %.1f" % [
		scene._local.connection, crosshair.connection, health_at, enemy.health])
	_check(lit > 0.5, "the stream was on a monster and the connection never lit")
	_check(enemy.health < health_at, "the stream was on it but it took no damage")
	_check(absf(crosshair.connection - scene._local.connection) < 0.01,
		"the reticle is not being driven by the connection")

	# --- the shove ----------------------------------------------------------
	# Measured where it actually happens. `stream_range` is 2.94 m, so a monster
	# can only be hosed at arm's length -- by which point it has already walked
	# in to its contact distance and stopped. So: let it settle there with the
	# stream off, then turn the stream on and see it pushed back out. That is
	# the loop the shove exists for, and measuring it at range measures nothing,
	# because at range the sauce never arrives.
	scene.debug_clear_input_override()
	for _i in 180:
		await physics_frame
	var settled: float = (enemy.global_position - player.global_position).length()
	scene.debug_aim_at(enemy.global_position)
	scene.debug_set_input(Vector2.ZERO, false, true)
	var pushed_to := settled
	for _i in 90:
		await physics_frame
		scene.debug_aim_at(enemy.global_position)
		pushed_to = maxf(pushed_to,
			(enemy.global_position - player.global_position).length())
	print("at contact: settled at %.2f m, hosed out to %.2f m (+%.2f)" % [
		settled, pushed_to, pushed_to - settled])
	_check(pushed_to > settled + 0.15,
		"the stream did not push it off the player at contact range")

	# --- and it comes off the moment the stream does ------------------------
	scene.debug_clear_input_override()
	for _i in 30:
		await physics_frame
	print("after letting go: connection %.4f, shove %.4f m/s" % [
		scene._local.connection, enemy._shove.length()])
	_check(scene._local.connection < 0.02,
		"the connection stayed lit after the stream came off")
	_check(enemy._shove.length() < 0.01, "the shove never decayed")

	# --- hitting the street does not light it -------------------------------
	# Turned away from the monster first: at contact range it is under the
	# player's nose, and aiming down at the floor would still sweep through it.
	enemy.global_position += Vector3(0.0, 0.0, -40.0)
	await physics_frame
	scene.debug_set_aim(0.0, -80.0)
	scene.debug_set_input(Vector2.ZERO, false, true)
	var floor_lit := 0.0
	for _i in 40:
		await physics_frame
		floor_lit = maxf(floor_lit, scene._local.connection)
	print("hosing the street: peak connection %.4f" % floor_lit)
	_check(floor_lit < 0.02, "hosing the street lit the reticle as if it were a body")
	scene.debug_clear_input_override()

	# --- a body throws more spray than a kerb -------------------------------
	scene._active_speck_indices.resize(0)
	for speck in scene._specks:
		speck.active = false
	scene._impact_clock = 0.0
	scene._spawn_impact_spray(Vector3.ZERO, Vector3.UP, Vector3.DOWN, false)
	var from_wall: int = scene._active_speck_indices.size()
	scene._impact_clock = 0.0
	scene._spawn_impact_spray(Vector3.ZERO, Vector3.UP, Vector3.DOWN, true)
	var from_body: int = scene._active_speck_indices.size() - from_wall
	print("spray pieces: %d off the street, %d off a body (x%.1f)" % [
		from_wall, from_body, scene.body_impact_multiplier])
	_check(from_body > from_wall,
		"a body and a kerb spit the same spray, so the spray says nothing")

	# --- the slowdown is continuous, not a threshold ------------------------
	enemy.health = enemy.max_health
	var clean_pace: float = enemy.move_speed * (1.0 - enemy.soiled_slowdown * 0.0)
	enemy.health = enemy.max_health * 0.25
	var soiled: float = 1.0 - enemy.health_fraction()
	var dirty_pace: float = enemy.move_speed * (1.0 - enemy.soiled_slowdown * soiled)
	print("walk speed: clean %.2f m/s, three quarters gone %.2f m/s (%.0f%%)" % [
		clean_pace, dirty_pace, dirty_pace / clean_pace * 100.0])
	_check(dirty_pace < clean_pace * 0.8,
		"contamination does not slow it down")
	_check(enemy.soiled_slowdown < 1.0, "a fully soiled body would stop dead")
	# The arc the two numbers make together: fresh, it walks through the hose;
	# ruined, the hose wins. That crossover is the fight, so it is asserted
	# rather than left to be noticed.
	print("hose vs walk: fresh %.2f m/s, three quarters gone %.2f m/s (negative = pushed back)" % [
		clean_pace - enemy.shove_speed, dirty_pace - enemy.shove_speed])
	_check(enemy.shove_speed > clean_pace,
		"the hose is slower than the walk, so a fresh body is never pushed back")
	# What stops it being a kite-forever is the bottle, not the reach: a burst
	# runs `full_burst_seconds` and then the nozzle is shut for
	# `spent_burst_cooldown`, and the body closes through every one of those
	# gaps. Printed with the ground each side actually covers, so the balance can
	# be read rather than asserted at a number that stops meaning anything the
	# moment the reach is retuned.
	var pushed_per_burst: float = (enemy.shove_speed - clean_pace) * scene.full_burst_seconds
	var closed_per_gap: float = clean_pace * scene.spent_burst_cooldown
	print("reach %.2f m | burst %.2f s pushes %.2f m, gap %.2f s closes %.2f m" % [
		scene.stream_range, scene.full_burst_seconds, pushed_per_burst,
		scene.spent_burst_cooldown, closed_per_gap])
	_check(scene.spent_burst_cooldown > 0.0,
		"the bottle never stops, so the push can be held indefinitely")
	_check(scene.stream_range > 0.0 and scene.stream_range < 100.0,
		"the stream has no finite reach at all")

	if failures.is_empty():
		print("MAYO_CONNECTION_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
