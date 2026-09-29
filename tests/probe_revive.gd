extends SceneTree

# Losing your ground puts you back at the start, whole and topped up. It does
# **not** wash you.
#
# The sauce on a revived player's body and glasses stays exactly where it was, on
# every peer, and the glasses come clean the one way they ever did: the player
# wipes them. Dying is not a wipe. What the respawn does reset is the state
# machine -- the fall, its timers, the recovery window, a wipe in progress and
# the shove from whatever killed them -- none of which it used to touch at all,
# so a player killed while flat on their back respawned still on their back and
# finished the fall they died in from there.
#
# Run over real peers on 127.0.0.1, because "on every screen" is the claim, and
# the masks are compared by hash rather than by cell count: two grids with the
# same number of painted cells in different places are not the same grid.
#
# What is checked here:
#   * both players are made filthy, and every peer agrees cell for cell first
#   * B dies flat on the floor and comes back upright and in control
#   * B's body and glasses come back with exactly the mask they went down with,
#     on the host and on the guest
#   * A is untouched by any of it
#   * and B can then wipe, which clears B's glasses -- and only B's glasses --
#     on every peer, leaving B's body dirty

const PORT := 24795

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


func _until(condition: Callable, frames := 1200) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await process_frame
		await physics_frame
	return false


func _wait(frames: int) -> void:
	for _f in frames:
		await process_frame
		await physics_frame


## Sprays whatever `world` is aimed at, for long enough to land a mask, and stops.
func _hose(world, at: Vector3, frames := 90) -> void:
	world.debug_aim_at(at)
	world.debug_set_input(Vector2.ZERO, false, true)
	await _wait(frames)
	world.debug_set_input(Vector2.ZERO, false, false)
	await _wait(20)


## Every peer's hash of one player's body and glasses, plus the cell counts,
## which are only there to make a failure readable.
func _masks(peer_id: int) -> Array:
	var out := []
	for world in _worlds:
		var player: MayoPlayer = world.shooter_for(peer_id).player
		out.push_back({
			"body": player.contamination.cells_md5(),
			"visor": player.visor.cells_md5(),
			"body_cells": player.contamination.painted_cell_count(),
			"visor_cells": player.visor.painted_cell_count(),
		})
	return out


func _describe(who: String, masks: Array) -> String:
	var line := who
	for index in masks.size():
		line += " | %s body %d/%s visor %d/%s" % [
			"host" if index == 0 else "guest",
			masks[index]["body_cells"], masks[index]["body"].substr(0, 8),
			masks[index]["visor_cells"], masks[index]["visor"].substr(0, 8)]
	return line


## Every guest holding the host's masks for all of these players.
func _agreed(peer_ids: Array) -> bool:
	for peer_id in peer_ids:
		var reference: MayoPlayer = _worlds[0].shooter_for(peer_id).player
		var body := reference.contamination.cells_md5()
		var visor := reference.visor.cells_md5()
		for index in range(1, _worlds.size()):
			var player: MayoPlayer = _worlds[index].shooter_for(peer_id).player
			if player.contamination.cells_md5() != body \
					or player.visor.cells_md5() != visor:
				return false
	return true


## Waits until nothing is still landing on these players and every peer agrees on
## what has landed.
##
## **Two conditions, not one.** Agreement on its own is not enough: letting go of
## the trigger does not empty the air, and the strand's points -- and the spray
## thrown off an impact after them -- go on landing for the best part of a second.
## A mask can therefore be agreed upon and then keep growing, which is exactly
## what made this comparison flake: B's body was snapshotted at 72 cells and read
## back at 77. So the host's masks have to hold still for `quiet` turns running
## *as well as* being matched everywhere.
##
## Waited for rather than counted out in frames, like the rest of the session
## tests: the splat batch is a reliable RPC delivered one `multiplayer.poll()` per
## *rendered* frame, and a headless run hands those out sparingly -- the guest was
## seen taking 34 packets in the time the host sent 287.
##
## A timeout is not swallowed: every caller asserts the agreement afterwards, so
## masks that never settle fail rather than passing quietly.
func _settled(peer_ids: Array, quiet := 45, frames := 1800) -> bool:
	var previous := ""
	var still := 0
	for _f in frames:
		var here := ""
		for peer_id in peer_ids:
			var player: MayoPlayer = _worlds[0].shooter_for(peer_id).player
			here += player.contamination.cells_md5() + player.visor.cells_md5()
		if here == previous:
			still += 1
		else:
			still = 0
			previous = here
		if still >= quiet and _agreed(peer_ids):
			return true
		await process_frame
		await physics_frame
	return false


## Every peer holding the same mask for this player.
func _agree(who: String, masks: Array) -> void:
	for index in range(1, masks.size()):
		_check(masks[index]["body"] == masks[0]["body"],
			"%s: the guest's copy of the body differs from the host's (%d cells vs %d)" % [
				who, masks[index]["body_cells"], masks[0]["body_cells"]])
		_check(masks[index]["visor"] == masks[0]["visor"],
			"%s: the guest's copy of the glasses differs from the host's (%d cells vs %d)" % [
				who, masks[index]["visor_cells"], masks[0]["visor_cells"]])


func _run() -> void:
	var host = _make_world(0)
	var guest = _make_world(1)
	await physics_frame
	for world in _worlds:
		set_multiplayer(SceneMultiplayer.new(), world.get_path())
	host._net.host(PORT, true)
	guest._net.join("127.0.0.1", PORT)
	var up := await _until(func() -> bool:
		return host.shooter_ids().size() == 2 and guest.shooter_ids().size() == 2 \
			and guest._net.debug_state_packets > 0, 2400)
	if not up:
		_check(false, "the session never came up: host '%s', guest '%s'" % [
			host._net.status(), guest._net.status()])
		_finish()
		return
	await _wait(10)

	var b_id: int = guest._net.local_id()
	var a_id := 1

	# Nothing else is allowed to paint anybody while the masks are being
	# compared. The enemies are the one thing in the level that moves on its own:
	# a contact hit would respawn B a second time in the middle of the
	# comparison, and a body walking through the two of them would shove them
	# about. Cleared on both peers so neither has a body the other does not.
	for world in _worlds:
		world.debug_clear_enemies()
	await _wait(10)

	var stand: float = host.spawn_position_for(0).y
	# Stood facing each other, close enough that a hose reaches the face. The
	# guest turns to look back, so the spray lands on the lenses as well as the
	# chest -- sprayed in the back their glasses stay clean, which is correct and
	# tests nothing.
	host.shooter_for(b_id).player.global_position = Vector3(0.0, stand, 0.05)
	host.shooter_for(a_id).player.global_position = Vector3(0.0, stand, 1.55)
	guest.debug_set_aim(180.0, 0.0)
	await _wait(10)

	# --- both players made filthy, and every peer agreeing on it -------------
	await _hose(host, host.shooter_for(b_id).player.global_position
		+ Vector3.UP * host.eye_height)
	await _hose(guest, host.shooter_for(a_id).player.global_position
		+ Vector3.UP * host.eye_height)
	# Both triggers are off and both worlds are back on the real keyboard, which
	# is not pressed in a headless run: no strand is live from here on.
	for world in _worlds:
		world.debug_clear_input_override()
	await _wait(10)
	await _settled([b_id, a_id])

	var b_before := _masks(b_id)
	var a_before := _masks(a_id)
	print(_describe("B before ", b_before))
	print(_describe("A before ", a_before))
	# The test is worthless unless both players really are dirty, on both
	# screens, in the same places.
	_check(b_before[0]["body_cells"] > 0, "B's body was never marked")
	_check(b_before[0]["visor_cells"] > 0, "B's glasses were never marked")
	_check(a_before[0]["body_cells"] > 0, "A's body was never marked")
	_agree("B before dying", b_before)
	_agree("A before B dies", a_before)

	# --- B is killed flat on the floor --------------------------------------
	# Going over is what exposed the state machine: the respawn never touched it.
	var b_on_host: MayoPlayer = host.shooter_for(b_id).player
	b_on_host.begin_slip()
	var went_down := await _until(func() -> bool:
		return b_on_host.state == MayoPlayer.State.DOWN, 300)
	_check(went_down, "B never reached the DOWN state to be killed in")
	# A wipe running and a shove arriving on the same frame as the killing blow:
	# both used to carry over into the new life. The wipe is the interesting one
	# now -- it must be cancelled *without* the lenses coming clean.
	b_on_host.wipe_timer = b_on_host.wipe_duration
	host._wiping[b_id] = true
	b_on_host.apply_enemy_impact(Vector3.FORWARD, 8.0, 3.0)
	_check(b_on_host._pending_enemy_impact.length() > 0.0,
		"the test never queued a shove to check")
	host.shooter_for(b_id).sauce = 0.0
	print("B at death: state %d, wipe %.2f s, queued shove %.2f m/s" % [
		b_on_host.state, b_on_host.wipe_timer, b_on_host._pending_enemy_impact.length()])

	host._damage_player(b_on_host, b_on_host.max_health * 2.0)

	# --- read the server the instant it happens ------------------------------
	# Snapshotted here rather than after the wait below, because the fall B was
	# killed in runs itself out in about a second: wait first and a respawn that
	# left the player on their back has already stood them up, and the bug reads
	# as fixed.
	var at_revive := {
		"state": b_on_host.state,
		"tilt": b_on_host.fall_tilt(),
		"wipe": b_on_host.wipe_timer,
		"pending": b_on_host._pending_enemy_impact.length(),
		"recovery": b_on_host._recovery_timer,
		"health": b_on_host.health,
		"sauce": host.shooter_for(b_id).sauce,
		"position": b_on_host.global_position,
		"wiping": host._wiping.has(b_id),
	}
	print("B the instant it is revived: state %d, tilt %.2f, wipe %.2f s, shove %.2f m/s" % [
		at_revive["state"], at_revive["tilt"], at_revive["wipe"], at_revive["pending"]])
	_check(at_revive["state"] == MayoPlayer.State.NORMAL,
		"B was revived in state %d instead of upright" % at_revive["state"])
	_check(is_zero_approx(at_revive["tilt"]),
		"B was revived still tilted over at %.2f" % at_revive["tilt"])
	_check(is_zero_approx(at_revive["wipe"]),
		"B was revived with a wipe still running")
	_check(at_revive["pending"] < 0.000001,
		"the shove that killed B was still waiting at the spawn point")
	_check(is_zero_approx(at_revive["recovery"]),
		"B was revived inside the recovery window of the fall that killed them")
	# The mid-wipe note has to go, or `_finish_wipes` clears the lenses for
	# everybody and hands B the free clean this whole rule is against.
	_check(not at_revive["wiping"],
		"the server still has B down as mid-wipe, so their glasses will be cleared for free")
	# And what already worked still works, read at the same instant so a body
	# that has since walked cannot mask it.
	_check(is_equal_approx(at_revive["health"], b_on_host.max_health),
		"B was revived on %.0f of %.0f health" % [at_revive["health"], b_on_host.max_health])
	_check(is_equal_approx(at_revive["sauce"], 1.0),
		"B was revived with %.2f of a tank instead of a full one" % at_revive["sauce"])
	var spawn: Vector3 = host.spawn_position_for(host._slot_of(b_on_host))
	var off_spawn: float = at_revive["position"].distance_to(spawn)
	_check(off_spawn < 0.01, "B was revived %.2f m from their spawn point" % off_spawn)

	# Long enough for the respawn to have reached the guest, and for the fall B
	# died in to have run out had it not been cancelled.
	await _until(func() -> bool:
		return guest.shooter_for(b_id).player.state == MayoPlayer.State.NORMAL, 900)
	await _wait(60)
	await _settled([b_id, a_id])

	# --- the sauce on them is exactly the sauce they went down with -----------
	var b_after := _masks(b_id)
	var a_after := _masks(a_id)
	print(_describe("B after  ", b_after))
	print(_describe("A after  ", a_after))
	for index in b_after.size():
		var who := "host" if index == 0 else "guest"
		_check(b_after[index]["body"] == b_before[index]["body"],
			"%s: reviving B changed the mask on their body (%d cells -> %d)" % [
				who, b_before[index]["body_cells"], b_after[index]["body_cells"]])
		_check(b_after[index]["visor"] == b_before[index]["visor"],
			"%s: reviving B changed the mask on their glasses (%d cells -> %d)" % [
				who, b_before[index]["visor_cells"], b_after[index]["visor_cells"]])
		_check(a_after[index]["body"] == a_before[index]["body"],
			"%s: reviving B changed the mask on A's body" % who)
		_check(a_after[index]["visor"] == a_before[index]["visor"],
			"%s: reviving B changed the mask on A's glasses" % who)
	# Stated separately from the comparisons above: those would all hold just as
	# well if the respawn had somehow left every grid empty.
	_check(b_after[0]["body_cells"] > 0,
		"B respawned with a clean body: dying is not a wipe")
	_check(b_after[0]["visor_cells"] > 0,
		"B respawned with clean glasses: dying is not a wipe")
	_agree("B after reviving", b_after)
	_agree("A after B revives", a_after)
	_check(guest.shooter_for(b_id).player.state == MayoPlayer.State.NORMAL,
		"the guest still has B in state %d rather than upright" % \
			guest.shooter_for(b_id).player.state)

	# --- and B can wipe, which is how glasses come clean --------------------
	# The request goes from the client to the server and everything after it is
	# the server's, exactly as before: this is the ordinary wipe, still working
	# on a body that has just respawned.
	guest._request_wipe()
	var wiping := await _until(func() -> bool: return b_on_host.is_wiping(), 600)
	_check(wiping, "B asked to wipe after respawning and the server never started one")
	var ran_out := await _until(func() -> bool: return not b_on_host.is_wiping(), 600)
	_check(ran_out, "B's wipe never finished")
	# The clear lands at the end of the wipe and travels in the splat batch.
	await _until(func() -> bool:
		return guest.shooter_for(b_id).player.visor.painted_cell_count() == 0, 600)
	await _wait(10)
	await _settled([b_id, a_id])

	var b_wiped := _masks(b_id)
	var a_wiped := _masks(a_id)
	print(_describe("B wiped  ", b_wiped))
	print(_describe("A wiped  ", a_wiped))
	for index in b_wiped.size():
		var who := "host" if index == 0 else "guest"
		_check(b_wiped[index]["visor_cells"] == 0,
			"%s: B wiped and %d cells are still on their glasses" % [
				who, b_wiped[index]["visor_cells"]])
		# The wipe is for the lenses only -- it must not wash the body down too.
		_check(b_wiped[index]["body"] == b_before[index]["body"],
			"%s: wiping B's glasses changed the mask on their body" % who)
		_check(a_wiped[index]["visor"] == a_before[index]["visor"],
			"%s: wiping B's glasses touched A's glasses" % who)
		_check(a_wiped[index]["body"] == a_before[index]["body"],
			"%s: wiping B's glasses touched A's body" % who)
	_agree("B after wiping", b_wiped)
	_check(a_wiped[0]["visor_cells"] == a_before[0]["visor_cells"],
		"A's glasses changed when B wiped theirs")

	_finish()


func _finish() -> void:
	for world in _worlds:
		world._net.leave()
	if failures.is_empty():
		print("MAYO_REVIVE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
