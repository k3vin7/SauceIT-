extends SceneTree

# The enemy, end to end:
#
#   * it is twice the sauce refill station's width and height
#   * it walks at the player at half the player's walking speed, and keeps
#     walking at them after they move
#   * sauce sticks to it the way it sticks to a player, and the same hit that
#     marks it is the hit that hurts it
#   * standing in it costs the player health, slowly, on a cooldown rather than
#     every frame
#   * an emptied player bar puts them back at the start, clean
#   * the splat it queues replays into the same cells on another peer

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

	_check(scene.enemy_count() > 0, "no enemies were spawned, so this tests nothing")
	var enemy: MayoEnemy = scene.enemy_at(0)
	var player: MayoPlayer = scene._player

	# --- size ---
	var station: Vector3 = StreetMap.VENDING_SIZE
	print("refill station %.2v -> enemy %.2f m wide, %.2f m tall (%.1fx, %.1fx)" % [
		station, enemy.radius * 2.0, enemy.height,
		enemy.radius * 2.0 / station.x, enemy.height / station.y])
	_check(is_equal_approx(enemy.radius * 2.0, station.x * 2.0),
		"the enemy is %.2f m wide, not twice the station's %.2f m" % [enemy.radius * 2.0, station.x])
	_check(is_equal_approx(enemy.height, station.y * 2.0),
		"the enemy is %.2f m tall, not twice the station's %.2f m" % [enemy.height, station.y])

	# --- speed, and that it is actually chasing ---
	print("player walks %.2f m/s, enemy moves %.2f m/s (%.2fx)" % [
		player.walk_speed, enemy.move_speed, enemy.move_speed / player.walk_speed])
	_check(is_equal_approx(enemy.move_speed, player.walk_speed * 0.5),
		"the enemy moves at %.2f m/s, not half the player's %.2f" % [
			enemy.move_speed, player.walk_speed])

	# Stood well clear so the walk can be measured before contact.
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 26.0)
	player.global_position.y = scene.spawn_position_for(0).y
	await physics_frame
	var opening := enemy.global_position.distance_to(player.global_position)
	var travelled := enemy.global_position
	for _f in 60:
		await physics_frame
	var closed := opening - enemy.global_position.distance_to(player.global_position)
	var moved := Vector3(enemy.global_position.x - travelled.x, 0.0,
		enemy.global_position.z - travelled.z).length()
	print("in 1 s it moved %.2f m and closed %.2f m of a %.1f m gap" % [moved, closed, opening])
	_check(closed > enemy.move_speed * 0.6,
		"it closed only %.2f m in a second at %.2f m/s" % [closed, enemy.move_speed])

	# Move the player sideways: it has to follow, not walk at where they were.
	var before_turn := enemy.global_position
	player.global_position += Vector3(18.0, 0.0, 0.0)
	for _f in 60:
		await physics_frame
	var chase := enemy.global_position - before_turn
	print("player stepped 18 m sideways; the enemy's next second went %.2v" % chase)
	_check(chase.x > 0.5, "the enemy did not turn after the player, moving %.2f m on x" % chase.x)

	# --- sauce marks it and hurts it, off the same hit ---
	var full: float = enemy.health
	var clean: int = enemy.contamination.painted_cell_count()
	_check(clean == 0, "the enemy started out already covered in sauce")
	scene._points.clear()
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 9.0)
	player.global_position.y = scene.spawn_position_for(0).y
	scene.debug_aim_at(enemy.global_position + Vector3(0.0, 0.4, 0.0))
	await physics_frame
	Input.action_press("fire_mayo")
	for _f in 90:
		scene.debug_aim_at(enemy.global_position + Vector3(0.0, 0.4, 0.0))
		await physics_frame
	Input.action_release("fire_mayo")
	await process_frame

	var marked: int = enemy.contamination.painted_cell_count()
	var lost: float = full - enemy.health
	print("90 frames of fire: %d cells of sauce on it, %.1f of %.0f health gone" % [
		marked, lost, full])
	_check(marked > 0, "sauce did not stick to the enemy")
	_check(lost > 0.0, "sauce did not hurt the enemy")
	# The stain and the damage come off the same hit, so neither can happen
	# without the other. Damage is per hit, so the ratio is fixed.
	_check(is_equal_approx(lost, enemy.sauce_damage_per_hit
			* roundf(lost / enemy.sauce_damage_per_hit)),
		"the damage taken is not a whole number of hits")

	# --- it hurts the player, weakly and on a cooldown ---
	var health_before: float = player.health
	player.global_position = enemy.global_position \
		+ Vector3(0.0, 0.0, enemy.radius + 0.64)
	player.global_position.y = scene.spawn_position_for(0).y
	var ticks := 0
	var seconds := 1.5
	for _f in int(seconds * 60.0):
		var was: float = player.health
		await physics_frame
		if player.health < was:
			ticks += 1
	var taken: float = health_before - player.health
	var expected := int(seconds / enemy.contact_interval)
	print("%.1f s of standing in it: %d hits for %.0f damage (one every %.2f s)" % [
		seconds, ticks, taken, enemy.contact_interval])
	_check(ticks > 0, "standing inside the enemy cost the player nothing")
	_check(ticks <= expected + 1,
		"it hit %d times in %.1f s, more than the %.2f s cooldown allows" % [
			ticks, seconds, enemy.contact_interval])
	# "Weak" has to mean something: surviving the cooldown must take a while.
	var to_kill: float = player.max_health / maxf(enemy.contact_damage, 0.001) \
		* enemy.contact_interval
	print("standing in it the whole time would take %.1f s to empty the bar" % to_kill)
	_check(to_kill > 8.0, "the enemy empties a full bar in %.1f s, which is not weak" % to_kill)

	# --- an emptied bar sends the player back to the start ---
	player.contamination.paint_mayo(player.global_position + Vector3(0.0, 0.2, 0.6), Vector3.BACK)
	_check(player.contamination.painted_cell_count() > 0, "the player could not be dirtied")
	scene._damage_player(player, player.max_health)
	var spawn: Vector3 = scene.spawn_position_for(0)
	print("emptied: back at %.1v (spawn %.1v), health %.0f, %d cells of sauce left" % [
		player.global_position, spawn, player.health,
		player.contamination.painted_cell_count()])
	_check(player.global_position.distance_to(spawn) < 0.01,
		"an emptied bar left the player at %.1v rather than the spawn" % player.global_position)
	_check(is_equal_approx(player.health, player.max_health),
		"the player came back with %.0f health" % player.health)
	_check(player.contamination.painted_cell_count() == 0,
		"the player came back still covered in sauce")

	# --- the splat replays into the same cells elsewhere ---
	var replay: MayoEnemy = MayoEnemy.new()
	root.add_child(replay)
	replay.build(scene.body_cell_size, scene.contamination_brush_radius, Color("4d3f6b"))
	var splats := PackedInt32Array()
	var cells: Array[Vector2i] = []
	for step in 12:
		var cell: Vector2i = enemy.contamination.grid.cell_of(
			Vector2(float(step) * 0.3 - 1.5, float(step) * 0.2))
		cells.push_back(cell)
		splats.append_array(PackedInt32Array([scene.SPLAT_ENEMY, 0, cell.x, cell.y]))
	for cell in cells:
		replay.paint_mayo_cell(cell)
	var fresh: MayoEnemy = scene.enemy_at(0)
	fresh.contamination.clear()
	scene.apply_splats(splats)
	print("replayed %d splat cells: %s vs %s" % [
		cells.size(), fresh.cells_md5().substr(0, 12), replay.cells_md5().substr(0, 12)])
	_check(fresh.cells_md5() == replay.cells_md5(),
		"a replayed enemy splat did not reproduce the server's mask")
	replay.queue_free()

	if failures.is_empty():
		print("MAYO_ENEMY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
