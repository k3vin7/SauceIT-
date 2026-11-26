extends SceneTree

# Blasts that do not check sides, on the Tomatina streets:
#   * an ordinary tomato bursting still only stains the players near it
#   * the overripe tomato's blast kills the grunts in its ring, leaves the ones
#     outside it alone, and hurts every player standing in it
#   * a thrown tomato hurts the thrower *and* their teammate, by distance, and
#     still hurts a teammate when the thrower is nowhere near
#   * a wall is cover from either

var failures: Array[String] = []


func _initialize() -> void:
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _grunt(scene, at: Vector3) -> MayoEnemy:
	var grunt: MayoEnemy = scene.enemy_at(scene.tutorial_add_enemy(MayoTutorial.KIND_TOMATO_GRUNT, at))
	# Whatever card its index was dealt, this one is an ordinary small grunt.
	grunt.burst_tier = 0
	grunt.burst_radius = 1.5
	return grunt


func _stand(player: MayoPlayer, at: Vector3, height: float) -> void:
	player.reset_state()
	# These checks put an already-standing player in the blast.
	player.damage_grace = 0.0
	player.state = MayoPlayer.State.NORMAL
	player.health = player.max_health
	player.global_position = Vector3(at.x, height, at.z)


func _expected(damage: float, distance: float, radius: float) -> float:
	return damage * lerpf(0.27, 1.0, 1.0 - distance / radius)


func _run() -> void:
	var scene = load("res://stage_2_tomatina.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	# The standing roster out of the way: only the bodies placed below count.
	for index in scene.enemy_count():
		scene.enemy_at(index).global_position = Vector3(4000.0, -300.0, 4000.0)

	var me: MayoPlayer = scene._player
	var height := me.global_position.y
	var mate: MayoPlayer = scene.create_avatar(7, 1, false).player
	# Open ground in the plaza, outside every safe room.
	var centre := TomatinaMap.at_cell(Vector2(30.0, 33.0))
	_check(TomatinaMap.safe_room_at(StreetMap.cell_at(centre)) < 0, "the test ground is a safe room")
	await physics_frame

	# --- an ordinary burst: sauce, no damage --------------------------------
	_stand(me, centre + Vector3(0.0, 0.0, 1.0), height)
	_stand(mate, centre + Vector3(60.0, 0.0, 0.0), height)
	var plain := _grunt(scene, centre)
	plain.take_sauce_hit(Vector3.INF, plain.max_health)
	scene._burst_ground_budget = scene.TOMATO_BURST_TICK_CAP
	scene._finish_tomato_kill(plain, scene._local)
	_check(is_equal_approx(me.health, me.max_health), "an ordinary tomato bursting hurt a player")

	# --- the overripe one: everybody in the ring ----------------------------
	var ripe := _grunt(scene, centre)
	ripe.burst_tier = 2
	ripe.burst_radius = 5.5
	var close := _grunt(scene, centre + Vector3(2.0, 0.0, 0.0))
	var far := _grunt(scene, centre + Vector3(9.0, 0.0, 0.0))
	var close_health := close.health
	var far_health := far.health
	_stand(me, centre + Vector3(0.0, 0.0, 2.2), height)
	_stand(mate, centre + Vector3(0.0, 0.0, -4.4), height)
	await physics_frame
	_check(scene._tomato_blast_reaches(ripe.global_position, me)
		and scene._tomato_blast_reaches(ripe.global_position, mate)
		and scene._tomato_blast_reaches(ripe.global_position, close),
		"something stands between the overripe tomato and the test bodies")
	ripe.take_sauce_hit(Vector3.INF, ripe.max_health)
	scene._finish_tomato_kill(ripe, scene._local)
	_check(is_equal_approx(me.health, me.max_health) and is_equal_approx(close.health, close_health),
		"the overripe tomato hurt somebody before its warning ended")
	var ripe_at := ripe.global_position
	var me_gap := me.global_position.distance_to(ripe_at)
	var mate_gap := mate.global_position.distance_to(ripe_at)
	scene._burst_ground_budget = scene.TOMATO_BURST_TICK_CAP
	scene._advance_overripe_bursts(scene.OVERRIPE_BURST_DELAY + 0.01)
	print("overripe: grunt in the ring %.1f -> %.1f, grunt outside %.1f -> %.1f" % [
		close_health, close.health, far_health, far.health])
	print("overripe: player at %.2f m lost %.2f, teammate at %.2f m lost %.2f" % [
		me_gap, me.max_health - me.health, mate_gap, mate.max_health - mate.health])
	_check(scene.overripe_burst_damage >= close_health, "the blast is not worth a grunt's health")
	_check(not close.is_alive(), "the overripe blast did not kill the grunt in its ring")
	_check(is_equal_approx(far.health, far_health), "the overripe blast reached a grunt outside its ring")
	# A flat share of each player's own maximum, wherever they stand inside it.
	var share: float = scene.overripe_burst_player_health_share
	_check(is_equal_approx(me.max_health - me.health, me.max_health * share),
		"the overripe blast took %.2f off the player, not %.2f" % [me.max_health - me.health,
			me.max_health * share])
	_check(is_equal_approx(mate.max_health - mate.health, mate.max_health * share),
		"the overripe blast did not take the same share off the teammate")

	# --- a thrown tomato: thrower and teammate alike ------------------------
	var radius: float = scene.thrown_tomato_splash_radius
	var target := _grunt(scene, centre + Vector3(-2.0, 0.0, 0.0))
	var target_health := target.health
	_stand(me, centre + Vector3(0.0, 0.0, 1.5), height)
	_stand(mate, centre + Vector3(0.0, 0.0, -2.5), height)
	await physics_frame
	var landing := Vector3(centre.x, 0.0, centre.z)
	_check(scene._tomato_blast_reaches(landing, me) and scene._tomato_blast_reaches(landing, mate),
		"something stands between the landing and the players")
	me_gap = me.global_position.distance_to(landing)
	mate_gap = mate.global_position.distance_to(landing)
	scene._explode_thrown_tomato(landing, scene._local)
	print("thrown: thrower at %.2f m lost %.2f, teammate at %.2f m lost %.2f, grunt lost %.1f" % [
		me_gap, me.max_health - me.health, mate_gap, mate.max_health - mate.health,
		target_health - target.health])
	_check(target.health < target_health, "the thrown tomato did not hurt the grunt beside it")
	_check(is_equal_approx(me.max_health - me.health,
		_expected(scene.thrown_tomato_player_damage, me_gap, radius)),
		"the thrown tomato did not hurt its thrower by distance")
	_check(is_equal_approx(mate.max_health - mate.health,
		_expected(scene.thrown_tomato_player_damage, mate_gap, radius)),
		"the thrown tomato did not hurt the thrower's teammate")

	# The thrower well clear, a teammate standing on it: still hurt.
	_stand(me, centre + Vector3(40.0, 0.0, 0.0), height)
	_stand(mate, centre + Vector3(0.0, 0.0, -1.0), height)
	await physics_frame
	scene._explode_thrown_tomato(landing, scene._local)
	_check(is_equal_approx(me.health, me.max_health), "a thrower outside the blast was hurt by it")
	_check(mate.health < mate.max_health, "a teammate in the blast was spared because the thrower was not")

	# --- and a wall is cover -------------------------------------------------
	_stand(me, centre + Vector3(0.0, 0.0, 3.0), height)
	_stand(mate, centre + Vector3(0.0, 0.0, -3.0), height)
	scene._create_wall("BlastProbeCover", centre + Vector3(0.0, 1.4, 1.5),
		Vector3(3.0, 2.8, 0.5), Color.GRAY)
	await physics_frame
	scene._explode_thrown_tomato(landing, scene._local)
	_check(is_equal_approx(me.health, me.max_health), "the blast hurt a player through a wall")
	_check(mate.health < mate.max_health, "the blast spared a player with nothing in the way")

	me.contamination.clear()
	me.visor.clear()
	mate.contamination.clear()
	var splash := _grunt(scene, centre)
	splash.burst_radius = 4.0
	scene._burst_tomato(splash, landing)
	_check(me.contamination.grid.painted_count == 0 and me.visor.painted_cell_count() == 0,
		"a bursting tomato painted a player through a wall")
	_check(mate.contamination.grid.painted_count > 0, "cover blocked ketchup on the open side, too")

	await _probe_part_sauce(scene, landing + Vector3(0.0, 0.0, -1.0))

	if failures.is_empty():
		print("BLAST_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _probe_part_sauce(scene, landing: Vector3) -> void:
	var parts := preload("res://scripts/tomatina_sauce_parts.gd")
	for enemy in scene._enemies:
		enemy.global_position = Vector3(4000.0, -300.0, 4000.0)
	var target := _grunt(scene, landing + Vector3(-1.0, 0.5, 0.0))
	target.max_health = 200.0
	var shooter = scene._local
	for part in [parts.Part.ARC, parts.Part.CANNON]:
		for sauce in [ContaminationGrid.KIND_MAYO, ContaminationGrid.KIND_MUSTARD,
				ContaminationGrid.KIND_KETCHUP]:
			await create_timer(0.26).timeout
			target.health = target.max_health
			target.contamination.clear()
			var effect := scene._blast_effects.back() as Node3D
			var hit_flash := scene._blast_hits.back() as MeshInstance3D
			shooter.sauce_kind = sauce
			scene._sauce_parts.show_volley(shooter.peer_id, part, sauce, landing + Vector3.UP, Vector3.DOWN)
			var shot: Dictionary = scene._sauce_parts._projectiles.pop_back()
			scene._sauce_parts._release_projectile(shot.node)
			shooter.sauce_kind = (sauce + 1) % 3
			var first_speck: int = scene._speck_cursor
			scene._pending_splats.clear()
			scene._part_projectile_impact({"position": landing, "normal": Vector3.UP, "collider": scene._floor},
				shot, parts.PROJECTILES[part], shooter, true)
			var label := "part %d, sauce %d" % [part, sauce]
			_check(target.health < target.max_health, "%s did not deal splash damage" % label)
			var enemy_code: int = scene._splat_code(scene.SPLAT_ENEMY, sauce)
			var floor_code: int = scene._splat_code(scene.SPLAT_FLOOR, sauce)
			var splat_codes := PackedInt32Array()
			for index in range(0, scene._pending_splats.size(), 4):
				splat_codes.append(scene._pending_splats[index])
			_check(splat_codes.has(enemy_code) and splat_codes.has(floor_code),
				"%s repainted the splash in a different sauce" % label)
			var speck_count := posmod(scene._speck_cursor - first_speck, scene._specks.size())
			var expected_specks := 0
			for offset in speck_count:
				var speck = scene._specks[(first_speck + offset) % scene._specks.size()]
				if speck.sauce == sauce:
					expected_specks += 1
			_check(speck_count > 0 and expected_specks == speck_count,
				"%s drew impact spray in a different sauce" % label)
			if part == parts.Part.ARC:
				var flash := effect.get_child(0) as MeshInstance3D
				var tint := flash.material_override as StandardMaterial3D
				var hit_tint := hit_flash.material_override as StandardMaterial3D
				_check(effect.visible and tint.albedo_color == Color(scene.SAUCE_TINTS[sauce], 0.82),
					"%s drew the blast flash in a different sauce" % label)
				_check(hit_flash.visible and hit_tint.albedo_color == Color(scene.SAUCE_TINTS[sauce], 0.6),
					"%s drew the splash hit flash in a different sauce" % label)
