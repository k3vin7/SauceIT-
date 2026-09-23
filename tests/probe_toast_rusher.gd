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

	var rushers: Array[MayoEnemy] = []
	var bruisers: Array[MayoEnemy] = []
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER:
			rushers.push_back(enemy)
		else:
			bruisers.push_back(enemy)
	print("enemy roster: %d bruisers, %d moldy toast rushers" % [bruisers.size(), rushers.size()])
	_check(bruisers.size() == 3, "expected the three existing enemies to remain")
	_check(rushers.size() == bruisers.size() * 2,
		"expected two toast rushers beside each existing enemy")

	for group in bruisers.size():
		var bruiser: MayoEnemy = scene.enemy_at(group * 3)
		var left: MayoEnemy = scene.enemy_at(group * 3 + 1)
		var right: MayoEnemy = scene.enemy_at(group * 3 + 2)
		_check(left.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER \
			and right.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER,
			"enemy group %d does not contain its rusher pair" % group)
		var left_gap := Vector2(left.global_position.x - bruiser.global_position.x,
			left.global_position.z - bruiser.global_position.z).length()
		var right_gap := Vector2(right.global_position.x - bruiser.global_position.x,
			right.global_position.z - bruiser.global_position.z).length()
		_check(left_gap < 5.0 and right_gap < 5.0,
			"rusher pair %d is not beside its bruiser" % group)

	var rusher := rushers[0]
	var player: MayoPlayer = scene._player
	print("rusher: %.2f m/s, %.0f hp; player walk/run %.2f/%.2f" % [
		rusher.move_speed, rusher.max_health, player.walk_speed, player.run_speed])
	_check(rusher.move_speed > player.walk_speed,
		"toast rusher is not faster than player walking speed")
	_check(rusher.move_speed < player.run_speed,
		"toast rusher cannot be escaped at player running speed")
	_check(rusher.max_health < bruisers[0].max_health * 0.3,
		"toast rusher health is not substantially lower than the existing enemy")

	_check(rusher._visual_root != null, "toast model was not instantiated")
	_check(rusher._animation_player != null, "toast model has no animation player")
	_check(is_equal_approx(absf(rusher._visual_root.rotation.y), PI),
		"toast model face is not aligned with the enemy's -Z movement front")
	var clean_colours: Dictionary = {}
	for mesh in rusher.contamination._meshes:
		var mask_material := mesh.material_override as ShaderMaterial
		if mask_material != null:
			clean_colours[str(mask_material.get_shader_parameter("clean_color"))] = true
			_check(is_equal_approx(float(mask_material.get_shader_parameter(
				"body_angle_offset")), 0.5),
				"toast sauce mask was not rotated with its corrected visual front")
	_check(clean_colours.size() >= 4,
		"sauce mask flattened the toast model's clean material colours")
	if rusher._animation_player != null:
		var names := " ".join(rusher._animation_player.get_animation_list())
		for required in ["Run", "Ram", "Hit", "Death"]:
			_check(names.to_lower().contains(required.to_lower()),
				"toast model is missing the %s action" % required)

	var clean := rusher.contamination.painted_cell_count()
	var health_before := rusher.health
	var paint_point := rusher.global_position + Vector3(0.0, 0.1, rusher.radius)
	rusher.paint_mayo(paint_point, Vector3.BACK)
	rusher.take_sauce_hit()
	_check(rusher.contamination.painted_cell_count() > clean,
		"sauce did not visibly mark the toast rusher")
	_check(rusher.health < health_before,
		"the same sauce hit did not reduce toast rusher health")

	# Put it at contact distance and ask one authoritative step to resolve. The
	# rusher must queue a physical shove, not merely subtract health.
	player.global_position = Vector3.ZERO + Vector3.UP * scene.spawn_position_for(0).y
	rusher.global_position = player.global_position + Vector3(0.0, 0.0,
		rusher.radius + 0.64 + rusher.contact_reach - 0.05)
	rusher._contact_cooldown = 0.0
	player._pending_enemy_impact = Vector3.ZERO
	var hit := rusher.advance(0.016, [player])
	_check(hit == player, "toast rusher did not register its close-range ram")
	_check(player._pending_enemy_impact.length() > 1.0,
		"toast rusher ram did not queue knockback")
	_check(rusher._ram_animation_timer > 0.0,
		"toast rusher did not enter its ram animation")

	if failures.is_empty():
		print("MOLDY_TOAST_RUSHER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
