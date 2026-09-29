extends SceneTree

# Whether a contact attack can actually reach where the player is standing.
#
# The chase is decided flat on purpose -- a player on a stall roof is worth
# walking towards -- but the *hit* is not the chase. A burger is 4.1 m of body
# and a moldy toast slab is 1.1 m, so the two have very different reaches, and
# neither of them can hit somebody ten metres up in the air.
#
# What is checked here:
#   * both bodies hit a player standing on the same floor, and knock them about
#     exactly as they did before
#   * neither hits a player far above it, and neither knocks one about either
#   * the reach is the body's own: a toast stops reaching far below where a
#     burger does
#   * a miss does not burn the contact cooldown, so the attack is still ready
#     the moment the player comes back down
#   * being off the ground is not on its own a reprieve: a player inside the
#     jump the game actually gives them is still hit

var failures: Array[String] = []

var _scene
var _player: MayoPlayer
## Where each body was standing when the level finished building it, which is
## the one height it is known not to be inside the floor at. Everything is
## placed from these rather than from `height * 0.5`: an enemy's origin is not
## the middle of its colliders, and a body dropped even slightly into the road
## is flung by depenetration long before the contact check is reached.
var _rest: Dictionary = {}


func _initialize() -> void:
	# The opening sequence is not what this file is about, and it would change the
	# street under it: it places its own bodies and keeps the standing roster off
	# the map. Switched off here, before the world is built -- the world builds
	# itself in `_ready()`, so there is no later chance to ask for this.
	MayoTutorial.disabled = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


## One contact test: the player stood `lift` metres above the enemy's own feet,
## horizontally just inside its flat reach. Returns [hit, knockback speed].
func _contact(enemy: MayoEnemy, lift: float) -> Array:
	var rest: Vector3 = _rest[enemy.get_instance_id()]
	enemy.global_position = rest
	enemy.velocity = Vector3.ZERO
	# Just inside the flat reach the body already had -- this test changes
	# nothing about that number, only about the height it is allowed at.
	var apart := enemy.radius + _player.contamination.radius + enemy.contact_reach - 0.05
	var feet := rest.y - enemy.height * 0.5
	_player.global_position = Vector3(rest.x, feet + _player.contamination.height * 0.5 + lift,
		rest.z + apart)
	_player.velocity = Vector3.ZERO
	_player._pending_enemy_impact = Vector3.ZERO
	enemy._contact_cooldown = 0.0
	enemy._alerted = true
	var hit = enemy.advance(0.016, [_player])
	return [hit == _player, _player._pending_enemy_impact.length()]


func _run() -> void:
	_scene = load("res://main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame
	_scene.set_process_unhandled_input(false)

	var burger: MayoEnemy = null
	var toast: MayoEnemy = null
	for index in _scene.enemy_count():
		var enemy: MayoEnemy = _scene.enemy_at(index)
		_rest[enemy.get_instance_id()] = enemy.global_position
		if enemy.kind == MayoEnemy.EnemyKind.BRUISER and burger == null:
			burger = enemy
		elif enemy.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER and toast == null:
			toast = enemy
	_check(burger != null and toast != null, "one of the two bodies is missing")
	if burger == null or toast == null:
		_finish()
		return

	_player = _scene._player
	print("bodies: burger %.2f m tall, r %.2f, reach %.2f | toast %.2f m tall, r %.2f, reach %.2f | player %.2f m tall" % [
		burger.height, burger.radius, burger.contact_reach,
		toast.height, toast.radius, toast.contact_reach,
		_player.contamination.height])

	# --- on the flat, both of them connect ----------------------------------
	for body in [burger, toast]:
		var body_name := "burger" if body == burger else "toast"
		var flat := _contact(body, 0.0)
		print("%s on the flat: hit=%s knockback %.2f m/s" % [body_name, str(flat[0]), flat[1]])
		_check(flat[0], "the %s stopped hitting a player standing right next to it" % body_name)
		if body.impact_push_speed > 0.0 or body.impact_lift_speed > 0.0:
			_check(flat[1] > 1.0, "the %s connected but queued no knockback" % body_name)
		# And the hit still costs it its cooldown, as it always did.
		_check(body._contact_cooldown > 0.0,
			"the %s hit without spending its contact cooldown" % body_name)

	# --- ten metres up, neither of them can ---------------------------------
	# The reproduction from the report: horizontally touching, vertically miles
	# apart. That is not a hit, for either body.
	for body in [burger, toast]:
		var body_name := "burger" if body == burger else "toast"
		var high := _contact(body, 10.0)
		print("%s with the player 10 m up: hit=%s knockback %.2f m/s" % [
			body_name, str(high[0]), high[1]])
		_check(not high[0], "the %s attacked a player ten metres above it" % body_name)
		_check(high[1] < 0.001, "the %s shoved a player ten metres above it" % body_name)
		# A swing it never took must not go on cooldown: the player comes down
		# and it is ready, rather than having spent the swing on thin air.
		_check(body._contact_cooldown <= 0.0,
			"the %s burned its cooldown on a player it could not reach" % body_name)

	# --- and the ceiling is each body's own ---------------------------------
	# Measured rather than compared against a constant: the point is that the
	# reach comes out of the body, so a 4.1 m burger keeps reaching long after a
	# 1.1 m slab has stopped.
	var ceiling := {}
	for body in [burger, toast]:
		var highest := -1.0
		var lift := 0.0
		while lift < 12.0:
			if _contact(body, lift)[0]:
				highest = lift
			lift += 0.1
		ceiling[body] = highest
	print("highest lift still hit: burger %.1f m, toast %.1f m" % [
		ceiling[burger], ceiling[toast]])
	_check(ceiling[burger] > ceiling[toast] + 1.0,
		"the tall body and the small slab reach the same height, so the reach is a constant")
	_check(ceiling[toast] > 0.0,
		"the toast cannot reach a player even slightly off the floor")
	_check(ceiling[burger] < 11.0,
		"the burger reaches the whole way up, so nothing is limiting it")

	# --- being airborne is not a reprieve on its own ------------------------
	# A player inside the jump this game actually gives them is still in reach.
	# The very apex is allowed to be outside a small body's reach -- that is the
	# point of measuring from the body -- but the jump must not be a hiding place.
	var jump_apex: float = _player.jump_speed * _player.jump_speed \
		/ (2.0 * _player.fall_gravity)
	print("the jump tops out at %.2f m" % jump_apex)
	for body in [burger, toast]:
		var body_name := "burger" if body == burger else "toast"
		var mid := _contact(body, jump_apex * 0.5)
		print("%s with the player halfway up a jump (%.2f m): hit=%s" % [
			body_name, jump_apex * 0.5, str(mid[0])])
		_check(mid[0],
			"the %s cannot touch a player halfway up an ordinary jump" % body_name)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("MAYO_REACH_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
