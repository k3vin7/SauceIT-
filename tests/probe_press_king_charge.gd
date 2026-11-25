extends SceneTree
const Boss = preload("res://scripts/tomatina_press_king.gd")
var failures: Array[String] = []
var hits := 0
var warnings := 0
var roars := 0
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
	boss.special_warning.connect(func(enemy, direction, _duration):
		if enemy.act == Boss.Act.CHARGE_WINDUP:
			warnings += 1
			check(not direction.is_zero_approx(), "charge warning has no direction"))
	boss.roared.connect(func(): roars += 1)
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
	var airborne := false
	var landed := false
	var hit_at := target.global_position
	for i in 290:
		await physics_frame
		boss.advance(1.0/60.0, [target])
		if target.charge_effect_state() < 0.0:
			check(target.confusion_left == 0.0, "confusion started before landing")
			airborne = airborne or target.global_position.y > hit_at.y + 0.8
		if not landed and target.state == MayoPlayer.State.DOWN:
			landed = true
			check(target.global_position.distance_to(hit_at) > 10.0, "charge landed the player too close")
			check(target.confusion_left > 3.0, "landing did not apply confusion")
		if warnings == 2 and boss.act == Boss.Act.IDLE:
			break
	check(hits >= 1 and airborne and landed, "charge did not launch and knock down the player")
	check(warnings == 2 and boss.act == Boss.Act.IDLE, "first combo did not finish after two charges")
	target.reset_state()
	target.position = Vector3(0, 1.28, -10)
	boss.global_position = initial
	boss._cooldown = 0.0
	boss._boss_charge_cooldown = 0.0
	for i in 480:
		await physics_frame
		boss.advance(1.0/60.0, [target])
		if warnings == 5 and boss.act == Boss.Act.IDLE:
			break
	check(warnings == 5 and boss.act == Boss.Act.IDLE, "second combo did not finish after three charges")
	boss.act = Boss.Act.CHARGE
	boss.act_time = 0.0
	boss.global_position = Vector3(0, boss.stand_height(), -28.0)
	boss._boss_charge_direction = Vector3.FORWARD
	await physics_frame
	boss.advance(0.1, [])
	check(boss.act == Boss.Act.CHARGE_RECOVER, "arena boundary did not stop charge")
	check(boss.arena.grow(-boss.radius).grow(0.001).has_point(Vector2(boss.global_position.x, boss.global_position.z)), "charge escaped arena")
	for action in [Boss.Act.CHARGE_WINDUP, Boss.Act.CHARGE, Boss.Act.CHARGE_RECOVER, Boss.Act.ROAR]:
		boss.act = action
		boss.armor_broken = true
		boss.act_time = 0.32
		var state: Array = boss.network_state()
		boss.apply_network_state(state[0], state[1], state[2], state[3], state[4])
		check(boss.act == action and boss.armor_broken, "new charge state failed network roundtrip")
	boss.global_position = initial
	_probe_lob(boss)
	boss.act = Boss.Act.IDLE
	boss._cooldown = 0.0
	boss._roar_wait = 0.0
	target.position = Vector3(8.0, 1.28, -10.0)
	boss.advance(0.01, [target])
	check(boss.act == Boss.Act.ROAR and roars == 0, "roar did not telegraph before summoning")
	boss.advance(Boss.ROAR_LENGTH + 0.01, [target])
	check(roars == 1, "roar did not call for reinforcements")
	boss.advance(0.01, [target])
	check(boss.act != Boss.Act.ROAR and roars == 1, "roar immediately repeated")
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


func _probe_lob(boss: Boss) -> void:
	var launches: Array[Vector3] = []
	var telegraphs: Array[Vector3] = []
	var counts := {}
	var previous_count := 0
	var repeated_count := false
	boss.lob_warning.connect(func(at, _duration, _primary): telegraphs.push_back(at))
	boss.lob_release.connect(func(origin, velocity, _seconds):
		launches.push_back(origin + velocity * Boss.LOB_FLIGHT
			+ Vector3.DOWN * Boss.LOB_GRAVITY * Boss.LOB_FLIGHT ** 2 * 0.5))
	seed(314159)
	for attempt in 30:
		launches.clear()
		telegraphs.clear()
		boss.act = Boss.Act.IDLE
		boss._start_lob(Vector2(0.0, -16.0), Vector3.FORWARD)
		boss.advance(Boss.LOB_RELEASE - 0.01, [])
		check(launches.is_empty(), "volley launched before its warning window")
		boss.advance(0.02, [])
		var count := launches.size()
		counts[count] = true
		repeated_count = repeated_count or count == previous_count
		previous_count = count
		check(count >= 3 and count <= 5 and telegraphs.size() == count, "volley did not release 3–5 projectiles together")
		for index in launches.size():
			check(launches[index].distance_to(telegraphs[index]) < 0.001, "lob missed its warning marker")
			var distance := launches[index].distance_to(launches[0])
			check(index == 0 or (distance >= 2.4 - 0.001 and distance <= Boss.LOB_CLUSTER_RADIUS + 0.001),
				"lob left the shared impact cluster")
	check(counts.size() == 3 and repeated_count, "volley sizes did not vary randomly")
