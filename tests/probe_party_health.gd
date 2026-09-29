extends SceneTree

# One health bar, one set of numbers, on every screen.
#
# A heavy's maximum contamination is scaled to the size of the party, and the
# scaling is the server's business. What every peer has to agree about is not
# just how hurt a body is but *how hurt out of what*: a bar is a fraction, and
# two peers holding the same `health` against different ceilings draw two
# different bars off one number.
#
# Run over real peers on 127.0.0.1 rather than by calling the packet functions
# directly, because the thing that went wrong is precisely what the packet does
# and does not carry.
#
# What is checked here:
#   * a two-player session agrees on a heavy's ceiling, not just its health
#   * and so draws the same bar for it
#   * a third player arriving re-scales it on every screen at once
#   * somebody leaving walks it back on every screen at once
#   * the existing policy survives all of that: the share already taken off a
#     body is what is preserved across a re-scale, not the absolute figure
#   * the client still decides nothing -- it has no hand in the scaling

const PORT := 24791

var failures: Array[String] = []
var _worlds: Array = []


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


func _make_world(index: int):
	var viewport := SubViewport.new()
	viewport.name = "Peer%d" % index
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var world = load("res://main.tscn").instantiate()
	world.name = "World"
	viewport.add_child(world)
	world.set_process_unhandled_input(false)
	_worlds.push_back(world)
	return world


## Waits on both clocks: the state packet is sent from `_process`, and a headless
## run hands out rendered frames far more sparingly than physics ones.
func _until(condition: Callable, frames := 1200) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await process_frame
		await physics_frame
	return false


## Everybody online holding everybody, and every guest actually taking state.
func _settled(count: int) -> bool:
	for world in _worlds:
		if not world._net.is_online():
			return false
		if world.shooter_ids().size() != count:
			return false
	for index in range(1, _worlds.size()):
		if _worlds[index]._net.debug_state_packets <= 0:
			return false
	return true


## The first heavy, by the build index every peer shares.
func _heavy_index(world) -> int:
	for index in world.enemy_count():
		if world.enemy_at(index).grade == MayoEnemy.Grade.HEAVY:
			return index
	return -1


## Sets the server's copy of a heavy to `fraction` of its own ceiling, then waits
## for every guest to have heard about it. Waiting on the value rather than on a
## frame count: the enemy packet is unreliable_ordered, so "a few frames" is not
## a delivery guarantee.
func _push_health(index: int, fraction: float) -> bool:
	var host = _worlds[0]
	var body: MayoEnemy = host.enemy_at(index)
	var wanted: float = body.max_health * fraction
	body.health = wanted
	return await _until(func() -> bool:
		for guest_index in range(1, _worlds.size()):
			if absf(_worlds[guest_index].enemy_at(index).health - wanted) > 0.01:
				return false
		return true)


## Prints and compares every peer's reading of one body.
func _agree(index: int, what: String) -> void:
	var host = _worlds[0]
	var reference: MayoEnemy = host.enemy_at(index)
	var line := "%s: host %.1f/%.1f (%.1f%%)" % [what, reference.health,
		reference.max_health, reference.health_fraction() * 100.0]
	for guest_index in range(1, _worlds.size()):
		var body: MayoEnemy = _worlds[guest_index].enemy_at(index)
		line += " | peer %d %.1f/%.1f (%.1f%%)" % [guest_index, body.health,
			body.max_health, body.health_fraction() * 100.0]
		_check(absf(body.max_health - reference.max_health) < 0.01,
			"%s: peer %d holds a ceiling of %.1f against the host's %.1f" % [
				what, guest_index, body.max_health, reference.max_health])
		_check(absf(body.health - reference.health) < 0.01,
			"%s: peer %d holds %.1f health against the host's %.1f" % [
				what, guest_index, body.health, reference.health])
		_check(absf(body.health_fraction() - reference.health_fraction()) < 0.005,
			"%s: peer %d draws the bar at %.1f%% and the host at %.1f%%" % [
				what, guest_index, body.health_fraction() * 100.0,
				reference.health_fraction() * 100.0])
	print(line)


func _run() -> void:
	var host = _make_world(0)
	var guest = _make_world(1)
	await physics_frame
	for world in _worlds:
		set_multiplayer(SceneMultiplayer.new(), world.get_path())
	host._net.host(PORT, true)
	guest._net.join("127.0.0.1", PORT)
	var up := await _until(func() -> bool: return _settled(2), 2400)
	if not up:
		_check(false, "the two-player session never came up: host '%s', guest '%s'" % [
			host._net.status(), guest._net.status()])
		_finish()
		return
	for _f in 10:
		await physics_frame

	var index := _heavy_index(host)
	_check(index >= 0, "there is no heavy in the level to scale")
	if index < 0:
		_finish()
		return
	_check(_heavy_index(guest) == index,
		"the two peers do not agree which enemy index is the heavy")

	var solo: float = host.enemy_at(index).solo_health
	print("heavy %d: solo ceiling %.0f, scaling %.2f per extra player" % [
		index, solo, host.heavy_health_per_player])

	# --- two players: the ceiling itself has to have travelled ---------------
	_check(absf(host.enemy_at(index).max_health
		- host.heavy_health_for(solo, 2)) < 0.01,
		"the host did not scale the heavy to the two players in the session")
	_agree(index, "two players, untouched")

	# The reproduction from the report: half gone on the server must read half
	# gone everywhere, not four fifths gone.
	_check(await _push_health(index, 0.5), "the hurt heavy never reached the guest")
	_agree(index, "two players, half gone")

	# --- a third arrives mid-fight -----------------------------------------
	# The policy being protected: the share already taken off stays taken off.
	# The body gets tougher, it does not get healthier.
	var before_fraction: float = host.enemy_at(index).health_fraction()
	var third = _make_world(2)
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), third.get_path())
	third._net.join("127.0.0.1", PORT)
	var joined := await _until(func() -> bool: return _settled(3), 2400)
	_check(joined, "the third player never got in: '%s'" % third._net.status())
	if joined:
		for _f in 10:
			await physics_frame
		_check(absf(host.enemy_at(index).max_health
			- host.heavy_health_for(solo, 3)) < 0.01,
			"the host did not re-scale the heavy when a third player joined")
		_check(absf(host.enemy_at(index).health_fraction() - before_fraction) < 0.005,
			"the re-scale moved how ruined the body is: %.1f%% became %.1f%%" % [
				before_fraction * 100.0,
				host.enemy_at(index).health_fraction() * 100.0])
		# Including the peer that only just arrived and never saw it clean.
		_agree(index, "three players, mid-join")

		# And a fresh figure pushed after the join still lands the same way.
		_check(await _push_health(index, 0.25), "the guests never heard the new figure")
		_agree(index, "three players, three quarters gone")

	# --- and one leaves -----------------------------------------------------
	before_fraction = host.enemy_at(index).health_fraction()
	third._net.leave()
	var left := await _until(func() -> bool:
		return host.shooter_ids().size() == 2 and guest.shooter_ids().size() == 2)
	_check(left, "the host never noticed the third player leave")
	_worlds.remove_at(2)
	for _f in 20:
		await physics_frame
	_check(absf(host.enemy_at(index).max_health
		- host.heavy_health_for(solo, 2)) < 0.01,
		"the host did not walk the scaling back when a player left")
	_check(absf(host.enemy_at(index).health_fraction() - before_fraction) < 0.005,
		"walking the scaling back moved how ruined the body is")
	# The guest has to follow the ceiling down as well as up.
	_check(await _push_health(index, 0.25), "the remaining guest stopped taking state")
	_agree(index, "back to two players")

	# --- the client decides none of this ------------------------------------
	# Its own scaling pass is a no-op: the figures it holds are the server's.
	var guest_before: float = guest.enemy_at(index).max_health
	guest.rescale_enemies()
	_check(absf(guest.enemy_at(index).max_health - guest_before) < 0.01,
		"the guest re-scaled the heavy itself, so the ceiling is not the server's")

	_finish()


func _finish() -> void:
	for world in _worlds:
		world._net.leave()
	if failures.is_empty():
		print("MAYO_PARTY_HEALTH_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
