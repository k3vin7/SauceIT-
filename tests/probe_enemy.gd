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

	# The silhouette is the mesh's, not the declared numbers': the bones are
	# fractions of the height, and an arm reaching a finger's width too far
	# would make the figure wider than the size it claims to be.
	var envelope: AABB = enemy._body_mesh.mesh.get_aabb()
	print("welded mesh: %d surface(s), %.2f m wide, %.2f m tall, %.2f m deep" % [
		enemy._body_mesh.mesh.get_surface_count(), envelope.size.x, envelope.size.y,
		envelope.size.z])
	_check(enemy._body_mesh.mesh.get_surface_count() == 1,
		"the body is %d surfaces; the unwrap needs one mesh in the body's space"
			% enemy._body_mesh.mesh.get_surface_count())
	_check(absf(envelope.size.x - station.x * 2.0) < 0.02,
		"the figure is %.2f m across, not the %.2f m it claims" % [
			envelope.size.x, station.x * 2.0])
	_check(absf(envelope.size.y - station.y * 2.0) < 0.02,
		"the figure is %.2f m tall, not the %.2f m it claims" % [
			envelope.size.y, station.y * 2.0])
	# A person, not a pillar: taller than wide and much thinner than wide.
	_check(envelope.size.z < envelope.size.x * 0.5,
		"the figure is %.2f m deep against %.2f m wide, which is not a body shape" % [
			envelope.size.z, envelope.size.x])
	# One collider per bone, so what you can see is what you can hit.
	var colliders := 0
	for child in enemy.get_children():
		if child is CollisionShape3D:
			colliders += 1
	print("colliders: %d (one per bone)" % colliders)
	_check(colliders >= 6, "the figure has %d colliders; the limbs are not hittable" % colliders)

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

	# --- its health bar actually lands on screen ---
	# The bar is drawn in the window's pixels and was briefly being scaled by a
	# Control size that is zero under a CanvasLayer, which collapsed every one
	# of them into the corner. Nothing looked broken -- the bar was simply not
	# where anyone was looking -- so the rect is checked rather than the drawing.
	var hud: HealthHud = scene._health_hud
	var camera: Camera3D = scene._camera
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 14.0)
	player.global_position.y = scene.spawn_position_for(0).y
	scene.debug_aim_at(enemy.global_position)
	await physics_frame
	await process_frame
	var bar: Rect2 = hud.enemy_bar_rect(enemy, camera)
	print("health bar at %.0v size %.0v, inside the view %s of %s" % [
		bar.position, bar.size, str(hud.frame.encloses(bar)), str(hud.frame)])
	_check(bar.size.x > 0.0, "the enemy in front of the player gets no health bar at all")
	_check(hud.frame.encloses(bar),
		"the health bar sits at %.0v, outside the %s being drawn" % [bar.position, str(hud.frame)])
	# Over the enemy rather than anywhere on screen: a bar in the corner is the
	# failure this is here to catch.
	var on_body: Vector2 = camera.unproject_position(enemy.global_position)
	_check(bar.get_center().distance_to(on_body) < hud.frame.size.y * 0.5,
		"the bar is %.0f px from the enemy it belongs to" % bar.get_center().distance_to(on_body))
	_check(bar.get_center().y < on_body.y, "the bar is under the enemy rather than over it")

	# --- killing it puts it on its back, over its own feet ---
	var standing_sole: Vector3 = enemy.global_transform * Vector3(0.0, -enemy.height * 0.5, 0.0)
	var facing: Vector3 = -enemy.global_transform.basis.z
	enemy.health = enemy.sauce_damage_per_hit
	_check(enemy.take_sauce_hit(), "the last point of health did not kill it")
	_check(not enemy.is_alive(), "it is still alive at zero health")
	var falling_frames := 0
	for _f in int(enemy.fall_duration * 60.0) + 30:
		await physics_frame
		if enemy.fall_angle < MayoEnemy.FLAT:
			falling_frames += 1
	var sole: Vector3 = enemy.global_transform * Vector3(0.0, -enemy.height * 0.5, 0.0)
	var crown: Vector3 = enemy.global_transform * Vector3(0.0, enemy.height * 0.5, 0.0)
	var drift := Vector2(sole.x - standing_sole.x, sole.z - standing_sole.z).length()
	var backwards: float = (crown - sole).dot(facing)
	print("went over in %d frames: angle %.1f deg, soles moved %.2f m, crown %.1f m %s of them, at y=%.2f" % [
		falling_frames, rad_to_deg(enemy.fall_angle), drift, absf(backwards),
		"behind" if backwards < 0.0 else "ahead", crown.y])
	_check(falling_frames > 1, "it snapped flat instead of toppling over %.2f s" % enemy.fall_duration)
	_check(is_equal_approx(enemy.fall_angle, MayoEnemy.FLAT),
		"it stopped at %.1f degrees rather than flat" % rad_to_deg(enemy.fall_angle))
	# The feet are the axis: they stay put while everything above them swings.
	_check(drift < 0.05, "its feet slid %.2f m instead of staying planted" % drift)
	# And it goes over backwards, so its back takes the floor.
	_check(backwards < -enemy.height * 0.8,
		"its head ended %.2f m along its facing; it did not fall onto its back" % backwards)
	# Resting on the ground rather than sunk into it or hovering over it.
	print("at rest the body centre is %.2f m up, torso half-thickness %.2f m" % [
		enemy.global_position.y, enemy._rest_radius])
	_check(absf(enemy.global_position.y - enemy._rest_radius) < 0.02,
		"flat on its back the body sits %.2f m up rather than on its %.2f m torso" % [
			enemy.global_position.y, enemy._rest_radius])
	_check(hud.enemy_bar_rect(enemy, camera).size.x == 0.0,
		"a dead enemy still has a health bar over it")

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
