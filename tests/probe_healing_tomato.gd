extends SceneTree
func _initialize():
	MayoTutorial.disabled = true
	call_deferred("run")
func run():
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	scene._unhandled_input(wheel)
	assert(scene.selected_item_slot(scene._local.peer_id) == 4, "wheel up did not wrap to slot 5")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scene._unhandled_input(wheel)
	assert(scene.selected_item_slot(scene._local.peer_id) == 0, "wheel down did not wrap to slot 1")
	scene.healing_tomato_chance = 1.0
	var enemy = scene.enemy_at(0)
	var clear_ground: Vector3 = scene.spawn_position_for(0) + Vector3.FORWARD * 7.0
	enemy.global_position = clear_ground
	enemy.health = 0
	scene.tutorial_clear_corpse(0)
	scene._advance_healing_tomatoes(0.01)
	assert(scene._healing_tomatoes.size() == 1, "guaranteed drop missing")
	var item = scene._healing_tomatoes.values()[0].node
	var player = scene._player
	player.state = MayoPlayer.State.NORMAL
	player.global_position = item.global_position + Vector3.UP
	player.health = player.max_health
	scene._advance_healing_tomatoes(0.7)
	assert(scene._healing_tomatoes.size() == 1, "full-health player consumed item")
	scene.tomato_action(player.peer_id, 0)
	assert(scene.local_holds_tomato(), "E did not pick up tomato")
	scene.tomato_action(player.peer_id, 2)
	assert(scene.local_holds_tomato(), "full health consumed held tomato")
	player.health = player.max_health - 10
	scene.tomato_action(player.peer_id, 2)
	assert(player.health == player.max_health, "healing failed or exceeded maximum")
	assert(not scene.local_holds_tomato(), "consumed item still equipped")
	scene._advance_healing_tomatoes(0.01)
	assert(scene._healing_tomatoes.is_empty(), "same death dropped twice")
	assert(scene.item_slots(player.peer_id) == [2,0,0,0,0], "consumed slot not empty")
	var second = null
	for candidate in scene._enemies:
		if candidate.is_alive() and candidate.kind != MayoEnemy.EnemyKind.TOMATO_BALL:
			second = candidate
			break
	second.global_position = clear_ground + Vector3.RIGHT * 5.0
	second.health = 0
	scene.tutorial_clear_corpse(scene._enemies.find(second))
	scene._advance_healing_tomatoes(0.01)
	var drop = scene._healing_tomatoes.values()[0].node
	player.global_position = drop.global_position + Vector3.UP
	scene.tomato_action(player.peer_id,0)
	assert(scene.local_holds_tomato(), "second pickup failed")
	scene.tomato_action(player.peer_id,10)
	assert(not scene.local_holds_tomato(), "slot 1 did not equip sauce")
	scene.tomato_action(player.peer_id,11)
	assert(scene.local_holds_tomato(), "slot 2 did not re-equip tomato")
	var before: float = player.health
	scene.tomato_action(player.peer_id,3)
	assert(scene._thrown_tomatoes.is_empty(), "press threw before release")
	assert(scene.local_holds_tomato(), "charging consumed item")
	scene._tomato_charge_started[player.peer_id] = Time.get_ticks_msec() - 2000
	assert(scene.tomato_charge_fraction(player.peer_id) == 1.0, "charge did not cap")
	scene.tomato_action(player.peer_id,1)
	assert(not scene._tomato_charge_started.has(player.peer_id), "release left charge active")
	assert(scene._thrown_tomatoes.values()[0].velocity.length() > 22.0, "full charge did not increase launch speed")
	assert(not scene.local_holds_tomato() and scene._thrown_tomatoes.size() == 1, "throw failed")
	scene._advance_thrown_tomatoes(0.02)
	assert(player.health == before, "throw damaged owner")
	# Where it lands is a splash: a grunt beside the landing is hurt by it.
	var target = null
	for candidate in scene._enemies:
		if candidate.is_alive() and candidate.kind == MayoEnemy.EnemyKind.TOMATO_GRUNT:
			target = candidate
			break
	var flying = scene._thrown_tomatoes.values()[0]
	target.global_position = flying.node.global_position + Vector3(1.0, 0.0, 0.0)
	target.global_position.y = target.stand_height()
	var target_health: float = target.health
	flying.velocity = Vector3.DOWN * 200.0
	scene._advance_thrown_tomatoes(0.02)
	assert(flying.has("ground_hit"), "the tomato did not land")
	assert(target.health == target_health, "the tomato damaged a target before the fuse expired")
	assert(scene.get_node_or_null("TomatoFuseWarning") != null, "the landing warning was not built")
	var landing: Vector3 = flying.ground_hit
	var protected: MayoEnemy = scene.enemy_at(scene.enemy_count() - 1)
	protected.global_position = landing + Vector3.LEFT * 3.4 + Vector3.UP * protected.stand_height()
	var protected_health := protected.health
	scene._create_wall("BlastTestCover", landing + Vector3.LEFT * 1.7 + Vector3.UP * 1.4,
		Vector3(0.5, 2.8, 3.0), Color.GRAY)
	player.global_position = clear_ground + Vector3.LEFT * 9.0
	await physics_frame
	scene._advance_thrown_tomatoes(scene.THROWN_TOMATO_FUSE + 0.01)
	assert(scene._thrown_tomatoes.is_empty(), "the tomato did not explode after the fuse")
	print("splash: the grunt beside the landing lost %.2f health" % (target_health - target.health))
	assert(target.health < target_health, "a grunt beside the landing was not hurt by the splash")
	assert(protected.health == protected_health, "the explosion damaged a target through cover")
	assert(player.health == before, "the splash hurt the thrower")
	print("HEALING_TOMATO_OK")
	quit()
