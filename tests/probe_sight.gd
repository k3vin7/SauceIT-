extends SceneTree

# What each body notices, and when it gives up. Without a range every enemy on
# a 295x382 m map walks at you from the moment the world loads.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _place(enemy: MayoEnemy, player: MayoPlayer, metres: float) -> void:
	enemy.global_position = player.global_position \
		+ Vector3(0.0, enemy.stand_height() - 1.0, -metres)


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	var player: MayoPlayer = scene._player

	var bruiser: MayoEnemy = null
	var rusher: MayoEnemy = null
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER and rusher == null:
			rusher = enemy
		elif enemy.kind == MayoEnemy.EnemyKind.BRUISER and bruiser == null:
			bruiser = enemy
	_check(bruiser != null and rusher != null, "one of the two bodies is missing")
	print("bruiser sees %.0f m / gives up %.0f m | rusher sees %.0f m / gives up %.0f m" % [
		bruiser.sight_range, bruiser.give_up_range,
		rusher.sight_range, rusher.give_up_range])

	# --- the gap between the two is what stops it flickering ---------------
	for enemy in [bruiser, rusher]:
		_check(enemy.give_up_range > enemy.sight_range,
			"%s gives up at or inside the distance it notices at, so a player on the line strobes it"
				% enemy.name)

	# --- far away, it stands still -----------------------------------------
	# Everything on the map is put to sleep first: another body walking through
	# frame would move the one under test.
	for index in scene.enemy_count():
		scene.enemy_at(index).global_position += Vector3(0.0, 0.0, -500.0)
	_place(bruiser, player, bruiser.sight_range + 8.0)
	var parked: Vector3 = bruiser.global_position
	for _i in 30:
		bruiser.advance(1.0 / 60.0, [player])
		await physics_frame
	var wandered: float = bruiser.global_position.distance_to(parked)
	print("parked %.0f m away (sees %.0f): alerted=%s, moved %.3f m in half a second" % [
		bruiser.sight_range + 8.0, bruiser.sight_range,
		str(bruiser.is_alerted()), wandered])
	_check(not bruiser.is_alerted(), "it noticed a player well outside its sight")
	_check(wandered < 0.5, "it walked at a player it had not noticed")

	# --- inside the range, it comes ----------------------------------------
	_place(bruiser, player, bruiser.sight_range - 4.0)
	var started: float = bruiser.global_position.distance_to(player.global_position)
	for _i in 60:
		bruiser.advance(1.0 / 60.0, [player])
		await physics_frame
	var closed: float = started - bruiser.global_position.distance_to(player.global_position)
	print("inside sight: alerted=%s, closed %.2f m in a second" % [
		str(bruiser.is_alerted()), closed])
	_check(bruiser.is_alerted(), "a player inside its sight did not wake it")
	_check(closed > 0.5, "it noticed a player and then did not come for them")

	# --- and it keeps coming past the sight range, up to the give-up one ----
	# The whole point of the second number: a chase that drops the moment the
	# player steps back over the line is not a chase.
	_place(bruiser, player, bruiser.sight_range + 6.0)
	bruiser.advance(1.0 / 60.0, [player])
	print("stepped back to %.0f m: still alerted=%s" % [
		bruiser.sight_range + 6.0, str(bruiser.is_alerted())])
	_check(bruiser.is_alerted(),
		"stepping just outside the sight range dropped a chase already under way")

	# --- until they are properly gone --------------------------------------
	_place(bruiser, player, bruiser.give_up_range + 5.0)
	bruiser.advance(1.0 / 60.0, [player])
	print("stepped back to %.0f m (gives up at %.0f): alerted=%s" % [
		bruiser.give_up_range + 5.0, bruiser.give_up_range, str(bruiser.is_alerted())])
	_check(not bruiser.is_alerted(), "it never gives up, so the range only delays the swarm")

	# --- sauce tells it where you are --------------------------------------
	_place(bruiser, player, bruiser.give_up_range + 40.0)
	bruiser.advance(1.0 / 60.0, [player])
	_check(not bruiser.is_alerted(), "it is awake before being hit")
	bruiser.take_sauce_hit(player.global_position)
	print("hit from %.0f m away, far outside everything: alerted=%s" % [
		bruiser.give_up_range + 40.0, str(bruiser.is_alerted())])
	_check(bruiser.is_alerted(), "hosing it from out of range did not wake it")

	# --- the rusher notices from further -----------------------------------
	_check(rusher.sight_range > bruiser.sight_range,
		"the rusher does not notice from further than the body it flanks")

	# --- the development rings ---------------------------------------------
	# Off by default: they are a dev aid, not part of the game.
	_check(not scene.show_enemy_sight, "the debug sight rings ship switched on")
	_check(bruiser.get_node_or_null("SightRing") == null,
		"a sight ring was built while the switch was off")
	scene.show_enemy_sight = true
	await process_frame
	var ring: MeshInstance3D = bruiser.get_node_or_null("SightRing")
	var outer: MeshInstance3D = bruiser.get_node_or_null("GiveUpRing")
	_check(ring != null and outer != null, "turning the switch on built no rings")
	if ring != null:
		# Cut loose from the body's transform: `_apply_pose` rolls the whole
		# node over when it topples, and a ring that rolled with it would be
		# standing on edge.
		_check(ring.top_level, "the ring is parented normally, so it topples with the body")
		var span: Vector3 = ring.mesh.get_aabb().size
		print("sight ring: %.1f m across for a %.0f m range, top_level=%s" % [
			span.x, bruiser.sight_range, str(ring.top_level)])
		_check(absf(span.x - bruiser.sight_range * 2.0) < 1.0,
			"the ring is %.1f m across but the range is %.0f m" % [span.x, bruiser.sight_range])
		var outer_span: Vector3 = outer.mesh.get_aabb().size
		_check(outer_span.x > span.x, "the give-up ring is not outside the sight ring")
	# And it lies flat on the ground under the body rather than at its middle.
	await process_frame
	if ring != null:
		print("ring sits %.2f m under the body's centre (stand height %.2f)" % [
			bruiser.global_position.y - ring.global_position.y, bruiser.stand_height()])
		_check(ring.global_position.y < bruiser.global_position.y,
			"the ring floats at the body's middle instead of lying on the ground")
	scene.show_enemy_sight = false
	await process_frame
	_check(bruiser.get_node_or_null("SightRing") == null,
		"turning the switch off left the rings behind")

	if failures.is_empty():
		print("MAYO_SIGHT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
