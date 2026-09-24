extends SceneTree

# Phase 3 and 4: the grade and its flinch list, the flinch itself (which rides
# on `fall_angle` and so adds nothing to the packet), the eased topple and its
# bounce, the ground correction, who the shake is sent to, and the party
# scaling.

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
	var here: Vector3 = scene._local.player.global_position

	# --- the grade and the list it carries ---------------------------------
	print("grade=%d thresholds=%s max_health=%.0f solo=%.0f" % [
		enemy.grade, str(enemy.flinch_thresholds), enemy.max_health, enemy.solo_health])
	_check(enemy.grade == MayoEnemy.Grade.HEAVY, "the shipped enemies are not heavies")
	_check(enemy.flinch_thresholds.size() == 3,
		"a heavy's default flinch list is not the three quarters")

	# --- a minion never flinches -------------------------------------------
	var minion := MayoEnemy.new()
	minion.grade = MayoEnemy.Grade.MINION
	minion.flinch_thresholds = []
	scene.add_child(minion)
	minion.build(scene.body_cell_size, scene.contamination_brush_radius, Color.WHITE)
	minion.max_health = 10.0
	minion.health = 10.0
	for _i in 12:
		minion.take_sauce_hit(here)
	print("minion after 12 hits: flinching=%s alive=%s" % [
		str(minion.is_flinching()), str(minion.is_alive())])
	_check(not minion.is_flinching(), "a minion with an empty list still flinched")
	minion.queue_free()

	# --- crossing a threshold flinches, once -------------------------------
	enemy.health = enemy.max_health
	enemy.fall_angle = 0.0
	var before: Vector3 = enemy.global_position
	# One hit big enough to cross all three at once.
	enemy.sauce_damage_per_hit = enemy.max_health * 0.8
	enemy.take_sauce_hit(here)
	print("one hit across three thresholds: flinching=%s" % str(enemy.is_flinching()))
	_check(enemy.is_flinching(), "crossing a threshold did not flinch it")
	# And the pose must not have thrown it anywhere: this is the `_fall_pivot`
	# trap -- branching the pose on `fall_angle` sent a living body to the origin.
	await physics_frame
	var drift: float = enemy.global_position.distance_to(before)
	print("drift while flinching: %.4f m (origin is %.1f m away)" % [
		drift, before.length()])
	_check(drift < 1.0, "the flinch teleported it: the pose branched on the angle")
	_check(enemy.fall_angle > 0.0, "the flinch did not rock it back at all")
	_check(enemy.fall_angle < deg_to_rad(enemy.flinch_degrees) + 0.01,
		"the flinch rocked further than it was told to")
	# A second hit at the same contamination must not flinch again.
	enemy.sauce_damage_per_hit = 0.01
	var flinching_before: bool = enemy.is_flinching()
	for _i in 20:
		enemy._flinch_left = 0.0
		enemy.take_sauce_hit(here)
	print("20 more hits past the last threshold: flinching=%s" % str(enemy.is_flinching()))
	_check(not enemy.is_flinching(),
		"a threshold already crossed flinched it again")

	# --- and it recovers to upright ----------------------------------------
	enemy._flinch_left = enemy.flinch_seconds
	for _i in int(enemy.flinch_seconds * 60.0) + 4:
		enemy._advance_flinch(1.0 / 60.0)
	print("after the flinch: fall_angle=%.5f rad" % enemy.fall_angle)
	_check(absf(enemy.fall_angle) < 0.001, "the flinch never came back to upright")

	# --- the topple: aimed away from the shot, eased, bounced --------------
	var victim = scene.enemy_at(1)
	victim.health = victim.sauce_damage_per_hit
	var shooter_at: Vector3 = victim.global_position + Vector3(0.0, 0.0, 6.0)
	victim.take_sauce_hit(shooter_at)
	_check(not victim.is_alive(), "the killing hit did not kill it")
	# Facing the shot means the back -- which is the way it goes over -- is away
	# from it.
	var facing := Vector3(-sin(victim.facing_yaw), 0.0, -cos(victim.facing_yaw))
	var to_shooter: Vector3 = shooter_at - victim.global_position
	to_shooter.y = 0.0
	print("death facing dot to-shooter: %.3f (1.0 = looking straight at them)" % [
		facing.dot(to_shooter.normalized())])
	_check(facing.dot(to_shooter.normalized()) > 0.99,
		"it did not turn to face the player who killed it")

	var angles: Array[float] = []
	for _i in 200:
		victim._advance_fall(1.0 / 60.0)
		angles.push_back(victim.fall_angle)
	# Eased: the first half of the turn is covered in less than half the time.
	var half_at := -1
	for index in angles.size():
		if angles[index] >= MayoEnemy.FLAT * 0.5:
			half_at = index
			break
	var flat_at := -1
	for index in angles.size():
		if angles[index] >= MayoEnemy.FLAT - 0.0001:
			flat_at = index
			break
	print("topple: halfway at frame %d, first flat at frame %d" % [half_at, flat_at])
	_check(half_at > 0 and flat_at > 0 and float(half_at) < float(flat_at) * 0.5,
		"the topple turned at a constant rate instead of easing")
	# The bounce: it must leave the floor once after arriving, then stop.
	var peak_back := 0.0
	for index in range(flat_at, angles.size()):
		peak_back = maxf(peak_back, MayoEnemy.FLAT - angles[index])
	print("bounce: rocked back %.4f rad (%.1f%% of the topple), settled at %.5f" % [
		peak_back, peak_back / MayoEnemy.FLAT * 100.0, angles[angles.size() - 1]])
	_check(peak_back > 0.0001, "it landed dead with no bounce at all")
	_check(is_equal_approx(angles[angles.size() - 1], MayoEnemy.FLAT),
		"it did not come to rest flat after the bounce")

	# --- nothing was added to the packet -----------------------------------
	_check(scene.ENEMY_STATE_STRIDE == 6,
		"the enemy state packet grew: the flinch was meant to ride on fall_angle")
	var state: Array = victim.network_state()
	_check(state.size() == 4 and state[3] is float,
		"fall_angle is no longer the fourth field of the enemy state")

	# --- the shake goes to whoever was hitting it --------------------------
	var target = scene.enemy_at(2)
	scene._hit_credit.clear()
	scene._credit_hit(target, scene._local)
	var book: Dictionary = scene._hit_credit[target.get_instance_id()]
	_check(book.has(scene._local.peer_id), "the hit was not credited to the shooter")
	scene._local.shake_left = 0.0
	scene.apply_enemy_shake(2, PackedInt32Array([scene._local.peer_id]), 4.0, 0.3)
	_check(scene._local.shake_left > 0.0, "the shake never started")
	var offset: Vector2 = scene._shake_offset(scene._local)
	print("shake: %.4f s left, offset (%.4f, %.4f) rad" % [
		scene._local.shake_left, offset.x, offset.y])
	# Someone who was not hitting it feels nothing.
	scene._local.shake_left = 0.0
	scene.apply_enemy_shake(2, PackedInt32Array([999]), 4.0, 0.3)
	_check(scene._local.shake_left == 0.0,
		"a player who was not hitting it was shaken anyway")
	# The credit runs out.
	scene._advance_hit_credit(scene.hit_credit_seconds + 0.01)
	_check(not scene._hit_credit.has(target.get_instance_id()),
		"the hit credit never expired")

	# --- party scaling ------------------------------------------------------
	var solo := 240.0
	print("heavy health: solo %.0f, 2p %.0f, 3p %.0f, 4p %.0f (per-player %.2f)" % [
		scene.heavy_health_for(solo, 1), scene.heavy_health_for(solo, 2),
		scene.heavy_health_for(solo, 3), scene.heavy_health_for(solo, 4),
		scene.heavy_health_per_player])
	_check(is_equal_approx(scene.heavy_health_for(solo, 1), solo),
		"solo scaling is not 1x")
	_check(is_equal_approx(scene.heavy_health_for(solo, 4), solo * 2.8),
		"four-player scaling is not 1 + 0.6 * 3")
	print("minion spawns from 4: 1p %d, 2p %d, 3p %d, 4p %d (per-player %.2f)" % [
		scene.minion_spawn_count(4, 1), scene.minion_spawn_count(4, 2),
		scene.minion_spawn_count(4, 3), scene.minion_spawn_count(4, 4),
		scene.minion_spawn_per_player])
	_check(scene.minion_spawn_count(4, 1) == 4, "solo minion count is not the base")
	_check(scene.minion_spawn_count(4, 3) == 10, "3-player minion count is not round(4 * 2.5)")

	# --- and rescaling keeps how ruined a body already is -------------------
	var scaled = scene.enemy_at(0)
	scaled.grade = MayoEnemy.Grade.HEAVY
	scaled.solo_health = 240.0
	scaled.max_health = 240.0
	scaled.health = 60.0
	var fraction_before: float = scaled.health_fraction()
	scene.create_avatar(2, 1, false)
	print("a player joined: max %.0f -> %.0f, fraction %.3f -> %.3f" % [
		240.0, scaled.max_health, fraction_before, scaled.health_fraction()])
	_check(is_equal_approx(scaled.max_health, 240.0 * 1.6),
		"the heavy was not rescaled when a player joined")
	_check(absf(scaled.health_fraction() - fraction_before) < 0.001,
		"rescaling moved how ruined the body already was")
	scene.remove_avatar(2)
	_check(is_equal_approx(scaled.max_health, 240.0),
		"the heavy was not rescaled back when the player left")

	if failures.is_empty():
		print("MAYO_FLINCH_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
