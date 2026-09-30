extends SceneTree

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

	var fry: MayoEnemy
	var burger: MayoEnemy
	var toast: MayoEnemy
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		match enemy.kind:
			MayoEnemy.EnemyKind.FRY_STALKER:
				fry = enemy
			MayoEnemy.EnemyKind.BRUISER:
				if burger == null:
					burger = enemy
			MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER:
				if toast == null:
					toast = enemy

	_check(fry != null, "the Fry Stalker was not spawned")
	_check(burger != null and toast != null, "comparison enemies are missing")
	if fry == null or burger == null or toast == null:
		_finish()
		return

	print("speeds burger %.2f < fry %.2f < toast %.2f" % [
		burger.move_speed, fry.move_speed, toast.move_speed])
	_check(fry.move_speed > burger.move_speed, "Fry Stalker is not faster than the hamburger")
	_check(fry.move_speed < toast.move_speed, "Fry Stalker is not slower than the toast")
	_check(is_equal_approx(fry.max_health, burger.max_health),
		"Fry Stalker health does not match the hamburger")
	_check(is_equal_approx(fry.sight_range, burger.sight_range),
		"Fry Stalker detection does not match the hamburger")
	_check(is_equal_approx(fry.height,
		MayoPlayer.CAPSULE_HEIGHT * MayoEnemy.FRY_STALKER_PLAYER_HEIGHT_MULTIPLE),
		"Fry Stalker is not exactly 2.5 player heights tall")

	var player: MayoPlayer = scene._player
	var fry_gap := Vector2(fry.global_position.x - player.global_position.x,
		fry.global_position.z - player.global_position.z).length()
	var nearest_old := INF
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy == fry:
			continue
		nearest_old = minf(nearest_old, Vector2(
			enemy.global_position.x - player.global_position.x,
			enemy.global_position.z - player.global_position.z).length())
	print("first encounter fry %.1f m, previous nearest %.1f m" % [fry_gap, nearest_old])
	_check(fry_gap < nearest_old, "Fry Stalker is not ahead of the nearest hamburger/toast")
	_check(StreetMap.floor_cells().has(StreetMap.cell_at(fry.global_position)),
		"Fry Stalker spawn is not on walkable street")

	var visual: Node = fry._fry_visual
	_check(visual != null, "Fry Stalker visual was not built")
	if visual != null:
		var before: Array[Vector3] = []
		visual.set_motion(0.0, true)
		visual._process(0.0)
		for index in 8:
			before.push_back(visual.debug_foot_position(index))
		visual.set_motion(0.31, true)
		visual._process(0.0)
		for index in 8:
			_check(visual.debug_foot_position(index).distance_to(before[index]) > 0.01,
				"leg %d did not participate in the spider gait" % index)

	# Put it just inside slam reach. The hit starts a planted-claw window; while
	# it lasts even a queued hose shove must not slide the body.
	player.global_position = scene.spawn_position_for(0)
	fry.global_position = player.global_position + Vector3(0.0, 0.0,
		fry.radius + 0.64 + fry.contact_reach - 0.05)
	fry._alerted = true
	fry._contact_cooldown = 0.0
	var hit = fry.advance(0.016, [player])
	_check(hit == player, "the front-leg slam did not register at close range")
	_check(fry.is_attack_locked(), "the slam did not plant the front legs")
	var planted_at := Vector2(fry.global_position.x, fry.global_position.z)
	fry.take_shove(player.global_position)
	fry.advance(0.45, [player])
	var after_lock_step := Vector2(fry.global_position.x, fry.global_position.z)
	_check(after_lock_step.distance_to(planted_at) < 0.01,
		"the planted Fry Stalker slid during its punish window")
	if visual != null:
		visual._process(fry.attack_lock_seconds * 0.48)
		_check(visual.debug_foot_position(0).y < 0.02
			and visual.debug_foot_position(1).y < 0.02,
			"the two front claws are not buried during the lock")
	fry.advance(fry.attack_lock_seconds + 0.1, [])
	_check(not fry.is_attack_locked(), "the Fry Stalker never recovered from its planted slam")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("FRY_STALKER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
