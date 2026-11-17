extends SceneTree

func _initialize() -> void:
	var world = preload("res://scripts/mayo_prototype.gd").new()
	world.map_kind = world.MapKind.TOMATINA
	var expected_waves := [100, 135, 170, 205]
	for players in range(1, 5):
		assert(world.minion_spawn_count(100, players) == expected_waves[players - 1])
		assert(is_equal_approx(world.boss_health_for(840.0, players), 840.0 * (1.0 + 0.6 * (players - 1))))
		assert(world.active_grunt_limit(players) == world.tomatina_active_grunt_cap + 4 * (players - 1))
		assert(is_equal_approx(world.heavy_health_for(100.0, players), float(expected_waves[players - 1])))
	assert(world.minion_spawn_count(0, 4) == 0)
	# Actual avatar membership, including bots, determines the default curve.
	world._shooters = {1: null, 9001: null, 9002: null, 9003: null}
	var boss = preload("res://scripts/tomatina_press_king.gd").new()
	boss.grade = MayoEnemy.Grade.HEAVY
	boss.solo_health = 840.0
	boss.max_health = 840.0
	boss.health = 420.0
	world._enemies.append(boss)
	world.rescale_enemies()
	assert(is_equal_approx(boss.max_health, 2352.0))
	assert(is_equal_approx(boss.health_fraction(), 0.5))
	world._shooters = {1: null}
	world.rescale_enemies()
	assert(is_equal_approx(boss.max_health, 840.0))
	assert(is_equal_approx(boss.health, 420.0))
	world._shooters.clear()
	world._enemies.clear()
	boss.free()
	world.free()
	print("TOMATINA_PARTY_BALANCE_OK")
	quit()
