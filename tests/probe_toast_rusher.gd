extends SceneTree

# The moldy toast rusher, ported onto the current enemy. It is the same
# `MayoEnemy` as the bruiser with different proportions and numbers -- the
# chase, the contamination, the topple and the state packet are shared -- so
# most of what is checked here is that the fork really is only those numbers.

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

	# --- the roster, and the order every peer builds it in ------------------
	var rushers: Array[MayoEnemy] = []
	var bruisers: Array[MayoEnemy] = []
	for index in scene.enemy_count():
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER:
			rushers.push_back(enemy)
		else:
			bruisers.push_back(enemy)
	print("roster: %d bruisers, %d moldy toast rushers" % [bruisers.size(), rushers.size()])
	_check(bruisers.size() == 3, "the three existing enemies did not survive")
	_check(rushers.size() == bruisers.size() * 2, "a pair of rushers per bruiser was not built")

	# The build order is what the splat batch and the state packet address
	# enemies by, so it is asserted rather than assumed.
	for group in bruisers.size():
		var bruiser: MayoEnemy = scene.enemy_at(group * 3)
		var left: MayoEnemy = scene.enemy_at(group * 3 + 1)
		var right: MayoEnemy = scene.enemy_at(group * 3 + 2)
		_check(bruiser.kind == MayoEnemy.EnemyKind.BRUISER
			and left.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER
			and right.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER,
			"group %d is not one bruiser followed by its pair" % group)
		var left_gap := Vector2(left.global_position.x - bruiser.global_position.x,
			left.global_position.z - bruiser.global_position.z).length()
		var right_gap := Vector2(right.global_position.x - bruiser.global_position.x,
			right.global_position.z - bruiser.global_position.z).length()
		_check(left_gap < 5.0 and right_gap < 5.0,
			"rusher pair %d does not stand beside its bruiser" % group)

	var rusher: MayoEnemy = rushers[0]
	var player: MayoPlayer = scene._player

	# --- outrun it, do not walk away from it -------------------------------
	print("rusher %.2f m/s, %.0f hp | bruiser %.2f m/s, %.0f hp | player walk %.2f run %.2f" % [
		rusher.move_speed, rusher.max_health, bruisers[0].move_speed,
		bruisers[0].max_health, player.walk_speed, player.run_speed])
	_check(rusher.move_speed > player.walk_speed, "it can be walked away from")
	_check(rusher.move_speed < player.run_speed, "it cannot be outrun")
	_check(rusher.max_health < bruisers[0].max_health * 0.3,
		"it is not markedly softer than a bruiser")

	# --- and it is a minion, in the grade system that already exists --------
	_check(rusher.grade == MayoEnemy.Grade.MINION, "the rusher is not graded a minion")
	_check(rusher.flinch_thresholds.is_empty(),
		"the rusher carries flinch thresholds: small things die, they do not stagger")
	_check(bruisers[0].grade == MayoEnemy.Grade.HEAVY, "the bruiser stopped being a heavy")

	# --- the model ----------------------------------------------------------
	_check(rusher._visual_root != null, "the toast model was not instantiated")
	_check(rusher._animation_player != null, "the toast model has no animation player")
	_check(is_equal_approx(absf(rusher._visual_root.rotation.y), PI),
		"the toast model's face is not turned onto the enemy's -Z front")
	if rusher._animation_player != null:
		var names := " ".join(rusher._animation_player.get_animation_list())
		print("toast clips: %s" % names)
		for required in ["Run", "Ram", "Hit", "Death"]:
			_check(names.to_lower().contains(required.to_lower()),
				"the toast model is missing its %s action" % required)
		# It has no Idle, so the walk stands in -- otherwise a stationary rusher
		# plays nothing at all and freezes on whatever frame it stopped on.
		_check(not rusher._idle_animation.is_empty(),
			"the rusher has no idle clip and no stand-in for one")
		_check(String(rusher._attack_animation).to_lower().contains("ram"),
			"the rusher's attack is not its Ram clip")

	# --- the sauce marks the authored model, not a grey capsule -------------
	# The overlay is laid over every imported mesh and keeps that mesh's own
	# material, so the clean toast still reads as toast. Each gets its own copy
	# carrying its rest position in the body -- the mask is unwrapped from a
	# shape that does not animate, and this is what maps it back.
	var overlaid := 0
	var distinct_matrices: Dictionary = {}
	for child in rusher._visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var overlay := mesh_instance.material_overlay as ShaderMaterial
		if overlay == null:
			continue
		overlaid += 1
		distinct_matrices[str(overlay.get_shader_parameter("rest_to_body"))] = true
		_check(mesh_instance.material_override == null,
			"the overlay replaced an imported material instead of sitting over it")
	print("overlay on %d meshes, %d distinct rest matrices" % [
		overlaid, distinct_matrices.size()])
	_check(overlaid > 4, "the sauce overlay reached almost none of the toast's meshes")
	_check(distinct_matrices.size() > 1,
		"every mesh got the same rest matrix, so the stain cannot follow the parts")

	# --- a hit marks it and hurts it ----------------------------------------
	var clean := rusher.contamination.painted_cell_count()
	var health_before := rusher.health
	rusher.paint_mayo(rusher.global_position + Vector3(0.0, 0.1, rusher.radius), Vector3.BACK)
	rusher.take_sauce_hit()
	_check(rusher.contamination.painted_cell_count() > clean,
		"sauce did not visibly mark the toast rusher")
	_check(rusher.health < health_before, "the same hit did not hurt it")

	# --- and it charges rather than biting ----------------------------------
	# The shove is the whole point of the body: without it a swarm of them is a
	# stationary damage tick you can stand in.
	player.global_position = scene.spawn_position_for(0)
	rusher.global_position = player.global_position + Vector3(0.0, 0.0,
		rusher.radius + 0.64 + rusher.contact_reach - 0.05)
	rusher._contact_cooldown = 0.0
	player._pending_enemy_impact = Vector3.ZERO
	var hit = rusher.advance(0.016, [player])
	print("ram: hit=%s queued knockback %.2f m/s (push %.1f, lift %.1f)" % [
		str(hit == player), player._pending_enemy_impact.length(),
		rusher.impact_push_speed, rusher.impact_lift_speed])
	_check(hit == player, "the rusher did not register its close-range ram")
	_check(player._pending_enemy_impact.length() > 1.0,
		"the ram did not queue any knockback")
	_check(player._pending_enemy_impact.y > 0.0,
		"the ram knocked the player along the floor rather than off it")

	# The bruiser must NOT shove: it bites, and giving it a charge would make
	# the two bodies read the same.
	_check(is_zero_approx(bruisers[0].impact_push_speed),
		"the bruiser gained a charge, so it no longer reads differently")

	if failures.is_empty():
		print("MOLDY_TOAST_RUSHER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
