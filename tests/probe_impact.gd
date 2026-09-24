extends SceneTree

# Checks the impact spray and the splat sound: that they are pooled and capped,
# that the splat timer belongs to the enemy rather than to the strand hitting
# it, and -- the part the spec is most particular about -- that both fire on a
# client, above the authority test, rather than waiting for the server.

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

	# --- the pool is fixed, and both pools are nodes rather than spawners ---
	_check(scene._specks.size() == scene.impact_pool_size,
		"the impact pool is not the size it was configured to")
	_check(get_nodes_in_group("mayo_droplets").size() == 2,
		"the impact spray is not a pooled MultiMesh alongside the droplets")
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# --- firing at a wall throws spray ---------------------------------------
	var wall_hits := 0
	scene.debug_set_aim(0.0, 0.0)
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _i in 120:
		await physics_frame
		wall_hits = maxi(wall_hits, scene._active_speck_indices.size())
	print("impact spray: %d pieces live at peak, pool %d" % [
		wall_hits, scene.impact_pool_size])
	_check(wall_hits > 0, "firing at the world threw no impact spray at all")
	# The cap is the whole point of pooling: it must never exceed the pool.
	_check(wall_hits <= scene.impact_pool_size,
		"more spray was live than the pool can hold")
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("node count while spraying: %d -> %d" % [nodes_before, nodes_after])
	_check(nodes_after - nodes_before < 8,
		"the impact spray created nodes per hit instead of using the pool")

	# --- the rate cap holds it back -----------------------------------------
	# A strand lands about 187 points a second; at the default 0.03 s interval
	# at most ~33 of those may throw an impact.
	var thrown := 0
	var previous: int = scene._active_speck_indices.size()
	for _i in 60:
		await physics_frame
		var now: int = scene._active_speck_indices.size()
		if now > previous:
			thrown += 1
		previous = now
	print("one second of held fire: %d frames added spray (cap %.0f/s at %.3f s)" % [
		thrown, 1.0 / maxf(scene.impact_min_interval, 0.001), scene.impact_min_interval])
	_check(thrown <= int(1.0 / maxf(scene.impact_min_interval, 0.001)) + 4,
		"the impact rate cap is not holding a held stream back")
	scene.debug_clear_input_override()

	# --- the splat timer belongs to the enemy, not to the strand ------------
	# There are no clips shipped, and no clips means silence by design -- so the
	# voice checks below would pass without proving anything. Give it one clip
	# to play first; what is under test is the routing, not the audio.
	_check(scene.splat_sounds.is_empty(),
		"a splat clip is shipped now: this probe's stand-in should be removed")
	var stand_in := AudioStreamWAV.new()
	stand_in.format = AudioStreamWAV.FORMAT_8_BITS
	stand_in.mix_rate = 22050
	var frames := PackedByteArray()
	frames.resize(4410)
	frames.fill(128)
	stand_in.data = frames
	scene.splat_sounds = [stand_in]

	var enemy = scene.enemy_at(0)
	_check(enemy != null, "there is no enemy to hit")
	if enemy != null:
		scene._enemy_splat_clock.clear()
		var at: Vector3 = enemy.global_position
		# Four separate hits in one frame, as four players hosing one monster
		# would give. One timer per enemy means one of them is heard.
		for _i in 4:
			scene._play_enemy_splat(enemy, at)
		var sounding := 0
		for voice in scene._splat_voices:
			if voice.playing:
				sounding += 1
		print("four hits on one enemy in one frame: %d voice(s) sounding" % sounding)
		_check(sounding == 1,
			"one hit on one enemy sounded %d voices, not one" % sounding)
		_check(sounding <= 1,
			"the splat timer is per hit rather than per enemy: %d voices fired at once" % sounding)
		_check(scene._enemy_splat_clock.has(enemy.get_instance_id()),
			"the splat timer was not keyed by the enemy")

	# --- the voice cap ------------------------------------------------------
	_check(scene._splat_voices.size() == scene.splat_voices,
		"the splat voice pool is not the size it was configured to")
	# Asking for far more than there are voices must never exceed the cap.
	var enemies: Array = []
	for index in scene.enemy_count():
		enemies.push_back(scene.enemy_at(index))
	for round_index in 40:
		scene._enemy_splat_clock.clear()
		for e in enemies:
			scene._play_enemy_splat(e, e.global_position)
	var busy := 0
	for voice in scene._splat_voices:
		if voice.playing:
			busy += 1
	print("hammering every enemy: %d of %d voices busy" % [busy, scene.splat_voices])
	_check(busy > 0, "hammering every enemy sounded nothing at all")
	_check(busy <= scene.splat_voices,
		"more splat voices sounded than the cap allows")

	# --- the thrown lumps come down and mark what they land on -------------
	# The ring of spatter round a fight is the point; a lump that expires in
	# mid-air leaves nothing behind.
	scene.debug_clear_input_override()
	for _i in 30:
		await physics_frame
	scene._floor._rebuild_grid()
	var painted_before: int = scene._floor.painted_cell_count()
	# Fired at the street at a glance, so the strand lands in one place and the
	# spray is thrown clear of it -- otherwise the stream's own splats and the
	# spatter's cannot be told apart.
	scene.debug_set_aim(0.0, -35.0)
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _i in 40:
		await physics_frame
	scene.debug_clear_input_override()
	var landed := 0
	for _i in 90:
		await physics_frame
		landed = scene._floor.painted_cell_count()
	print("floor cells painted: %d -> %d" % [painted_before, landed])
	_check(landed > painted_before, "nothing marked the street at all")

	# And with the marking turned off, the lumps still fly but leave nothing.
	scene.impact_paints = false
	scene._floor._rebuild_grid()
	var quiet_before: int = scene._floor.painted_cell_count()
	for speck in scene._specks:
		speck.active = false
	scene._active_speck_indices.resize(0)
	scene._impact_clock = 0.0
	scene._spawn_impact_spray(scene._local.player.global_position + Vector3(0.0, 1.5, 0.0),
		Vector3.UP, Vector3.DOWN, false, scene._local)
	var flying: int = scene._active_speck_indices.size()
	for _i in 60:
		await physics_frame
	print("with marking off: %d lumps thrown, floor %d -> %d" % [
		flying, quiet_before, scene._floor.painted_cell_count()])
	_check(flying > 0, "turning marking off stopped the spray being thrown")
	_check(scene._floor.painted_cell_count() == quiet_before,
		"impact_paints was off and the spray marked the street anyway")
	scene.impact_paints = true

	# --- and the whole thing is local: a client shows it too ----------------
	# `_is_authority()` is what gates painting. The spray and the splat are
	# called above it, so switching the world off authority must not silence
	# them. Checked by reading the call site rather than by standing a session
	# up: the ordering *is* the requirement.
	var source := FileAccess.get_file_as_string("res://scripts/mayo_prototype.gd")
	var spray_at := source.find("_spawn_impact_spray(hit.position")
	var authority_at := source.find("if _is_authority() and collider != null:")
	print("call site order: spray at %d, authority test at %d" % [spray_at, authority_at])
	_check(spray_at > 0 and authority_at > 0 and spray_at < authority_at,
		"the impact spray is below the authority test, so a client would not see it")

	if failures.is_empty():
		print("MAYO_IMPACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
