extends SceneTree
const Boss = preload("res://scripts/tomatina_press_king.gd")
var failures: Array[String] = []
var hits := 0
var warnings := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok:
		failures.append(text)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	world.add_child(floor)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	collider.position.y = -0.5
	floor.add_child(collider)
	var target := MayoPlayer.new()
	target.frozen = true
	target.collision_layer = 2
	target.collision_mask = 1
	world.add_child(target)
	target.position = Vector3(0, 1.28, -10)
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = MayoPlayer.CAPSULE_RADIUS
	capsule.height = MayoPlayer.CAPSULE_HEIGHT
	player_shape.shape = capsule
	target.add_child(player_shape)
	var boss = Boss.new()
	world.add_child(boss)
	boss.build_press_king(0.1, 0.2)
	boss.configure_combat_speed(5.2, 1.65)
	boss.arena = Rect2(-30,-30,60,60)
	boss.position = Vector3(0, boss.stand_height(), 0)
	boss.slam_hit.connect(func(_player, damage): hits += 1; check(damage == Boss.CHARGE_DAMAGE, "wrong charge damage"))
	boss.special_warning.connect(func(_enemy, direction, _duration): warnings += 1; check(not direction.is_zero_approx(), "charge warning has no direction"))
	check(boss.max_health == 840, "boss health was not increased")
	check(is_equal_approx(boss.move_speed, 8.58), "chase does not match rusher")
	check(is_equal_approx(boss.charge_speed, 25.74), "charge does not match brute")
	boss.act = Boss.Act.IDLE
	boss._cooldown = 0.0
	await physics_frame
	boss.advance(1.0/60.0, [target])
	check(boss.act == Boss.Act.CHARGE_WINDUP and warnings == 1, "charge did not telegraph")
	var initial: Vector3 = boss.global_position
	for i in 20:
		await physics_frame
		boss.advance(1.0/60.0, [target])
	check(boss.global_position.distance_to(initial) < 0.01, "boss moved during windup")
	for i in 110:
		await physics_frame
		boss.advance(1.0/60.0, [target])
	check(hits == 1, "charge should hit target exactly once: %d" % hits)
	check(boss.act == Boss.Act.CHARGE_RECOVER or boss.act == Boss.Act.IDLE or boss.act == Boss.Act.WALK, "charge did not recover")
	boss.act = Boss.Act.CHARGE
	boss.act_time = 0.0
	boss.global_position = Vector3(0, boss.stand_height(), -28.0)
	boss._boss_charge_direction = Vector3.FORWARD
	await physics_frame
	boss.advance(0.1, [])
	check(boss.act == Boss.Act.CHARGE_RECOVER, "arena boundary did not stop charge")
	check(boss.arena.grow(-boss.radius).grow(0.001).has_point(Vector2(boss.global_position.x, boss.global_position.z)), "charge escaped arena")
	for action in [Boss.Act.CHARGE_WINDUP, Boss.Act.CHARGE, Boss.Act.CHARGE_RECOVER]:
		boss.act = action
		boss.armor_broken = true
		boss.act_time = 0.32
		var state: Array = boss.network_state()
		boss.apply_network_state(state[0], state[1], state[2], state[3], state[4])
		check(boss.act == action and boss.armor_broken, "new charge state failed network roundtrip")
	boss.act = Boss.Act.IDLE
	boss.health = boss.max_health
	boss.armor_broken = true
	boss.take_aimed_sauce_hit(boss.to_global(Vector3(0,-0.68,-1.0)),100.0)
	check(is_equal_approx(boss.max_health-boss.health,63.25), "weak spot damage was not reduced")
	boss.health = boss.max_health
	boss.armor_broken = false
	boss.exposed_left = 0.0
	boss.take_sauce_hit(Vector3.ZERO,100.0)
	check(is_equal_approx(boss.max_health-boss.health,16.0), "armored damage changed unexpectedly")
	boss.armor_broken = true
	boss.health = 1.0
	boss.take_sauce_hit(Vector3.ZERO, 10.0)
	check(boss.act == Boss.Act.DEATH, "death did not interrupt charge")
	var at: Vector3 = boss.global_position
	boss.advance(0.1,[target])
	check(boss.global_position.distance_to(at) < 0.001, "dead boss kept charging")
	var death_at: Vector3 = boss.global_position
	for frame in 121:
		boss._update_death_burst(float(frame) / 60.0)
		check(boss._visual_root.transform.is_finite(), "death pose became nonfinite")
		check(boss._visual_root.transform.is_equal_approx(boss._death_rest), "death overlay hops, twists or squashes model")
		check(boss.global_position.distance_to(death_at) < 0.001, "death effect moved gameplay body")
	check(boss._death_chunks.size() == 8, "death burst missing debris")
	check(boss._death_chunks[0].scale.length() < 0.001, "death debris did not finish before extraction")
	print("PRESS_KING_DEATH_OK")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PRESS_KING_CHARGE_OK")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
