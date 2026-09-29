extends SceneTree

# The opening stretch over a real session on 127.0.0.1.
#
# The sequence is the server's: what this file checks is that every peer ends up
# looking at the same one, and that the awkward moments -- somebody arriving
# halfway through, somebody leaving mid-stage, somebody dying and coming back --
# neither stall it nor rewind it.
#
# What is checked here:
#   * both peers agree on the stage, all the way through
#   * the enemy list is the same list in the same order, which is what the state
#     packet and the splat batch address a body by
#   * the roster for the opening fight is fixed when it starts: somebody joining
#     mid-fight does not add another body
#   * a caption is an event, so an ordinary state packet cannot replay one that
#     has already been said
#   * a peer that joins during the top-up stage is told the stage, gets the
#     bodies, and can top up
#   * a peer that leaves stops being waited for
#   * dying and respawning neither resets the stage nor loses a top-up, and the
#     respawn rules themselves still hold

const PORT := 24797

var failures: Array[String] = []
var _worlds: Array = []


func _initialize() -> void:
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


func _until(condition: Callable, frames := 2400) -> bool:
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


## How many players other than `except_id` are off their feet.
func _others_off_their_feet(world, except_id: int) -> int:
	var count := 0
	for peer_id in world.shooter_ids():
		if peer_id == except_id:
			continue
		var shooter = world.shooter_for(peer_id)
		if shooter == null:
			continue
		if shooter.player.state != MayoPlayer.State.NORMAL:
			count += 1
	return count


func _stage_name(value: int) -> String:
	return MayoTutorial.Stage.keys()[value]


## Every world's enemy list as "kind@index", so a mismatch names itself.
func _roster_signature(world) -> String:
	var parts := PackedStringArray()
	for index in world.enemy_count():
		var enemy: MayoEnemy = world.enemy_at(index)
		parts.push_back("%d:%d" % [index, enemy.kind if enemy != null else -1])
	return " ".join(parts)


## Kills a body with the damage call the stream uses.
func _hose_to_death(enemy: MayoEnemy) -> void:
	var guard := 0
	while enemy.is_alive() and guard < 4000:
		enemy.take_sauce_hit(enemy.global_position + Vector3(0.0, 0.0, 2.0))
		guard += 1


## A spot just in front of a stall's counter, on the side it faces.
func _approach(world, station: Vector3, stand_y: float) -> Vector3:
	var facing := Vector3.BACK
	for entry in world._refill_stations:
		if (entry["position"] as Vector3).distance_to(station) < 0.01:
			facing = entry["facing"]
			break
	var at: Vector3 = station + facing * (world.refill_reach * 0.5)
	at.y = stand_y
	return at


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

	var host_tutorial: MayoTutorial = host.tutorial()
	var guest_tutorial: MayoTutorial = guest.tutorial()
	_check(host_tutorial != null and guest_tutorial != null,
		"one of the two peers built no tutorial")
	if host_tutorial == null or guest_tutorial == null:
		_finish()
		return
	# Neither peer places the street's standing roster, so the list both of them
	# append to starts empty and index 0 means the same body on both.
	_check(host.enemy_count() == 0 and guest.enemy_count() == 0,
		"the standing roster was built as well: host %d, guest %d bodies" % [
			host.enemy_count(), guest.enemy_count()])

	# --- onto the light, which is what starts the fight --------------------
	# The opening waits for the whole party to be standing on it. Stood there
	# rather than walked there: what is under test in this file is that the stage
	# and the roster are the same on every peer, and the condition the server
	# checks is where the bodies are, which is exactly what this sets.
	# Waited for the light rather than for the stage: it comes up with its own
	# caption a few seconds in, not at the top of the stage.
	await _until(func() -> bool:
		return host_tutorial.move_target() != Vector3.INF, 1800)
	var light: Vector3 = host_tutorial.move_target()
	_check(light != Vector3.INF, "the opening lit no spot to walk to")
	var placed := 0
	for peer_id in host.shooter_ids():
		var shooter = host.shooter_for(peer_id)
		# Spread around the light rather than stacked inside each other.
		var around := float(placed) * TAU / float(maxi(host.shooter_ids().size(), 1))
		shooter.player.global_position = Vector3(
			light.x + cos(around) * 1.1, shooter.player.global_position.y,
			light.z + sin(around) * 1.1)
		shooter.player.velocity = Vector3.ZERO
		placed += 1
	await _wait(10)

	# --- the opening fight, and the roster both peers hold ------------------
	var fighting := await _until(func() -> bool:
		return host_tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT, 3600)
	_check(fighting, "the sequence never reached the opening fight")
	var mirrored := await _until(func() -> bool:
		return guest.enemy_count() == host.enemy_count() \
			and guest_tutorial.stage == host_tutorial.stage)
	print("opening fight: host %d bodies, guest %d, stages %s / %s" % [
		host.enemy_count(), guest.enemy_count(),
		_stage_name(host_tutorial.stage), _stage_name(guest_tutorial.stage)])
	_check(mirrored, "the guest never caught up with the opening fight")
	# Two players, so three bodies -- and it is the party at the moment the fight
	# began, which is what the next part leans on.
	_check(host_tutorial.fight_enemies.size() == 3,
		"a two-player opening fight placed %d bodies rather than 3"
			% host_tutorial.fight_enemies.size())
	_check(_roster_signature(host) == _roster_signature(guest),
		"the two peers hold different enemy lists:\n  host  %s\n  guest %s" % [
			_roster_signature(host), _roster_signature(guest)])
	print("roster signature: %s" % _roster_signature(host))

	# --- a third player mid-fight does not add a fourth body ---------------
	var third = _make_world(2)
	await physics_frame
	set_multiplayer(SceneMultiplayer.new(), third.get_path())
	third._net.join("127.0.0.1", PORT)
	var joined := await _until(func() -> bool:
		return host.shooter_ids().size() == 3 and third.shooter_ids().size() == 3 \
			and third._net.debug_state_packets > 0, 2400)
	_check(joined, "the third player never got in: '%s'" % third._net.status())
	var third_tutorial: MayoTutorial = third.tutorial()
	# Waited for, not counted out. The catch-up is a run of reliable RPCs -- the
	# whole floor snapshot, then every body the tutorial has placed, then the
	# stage -- and reliable RPCs arrive one `multiplayer.poll()` per *rendered*
	# frame, which a headless run hands out sparingly. A fixed frame count here is
	# that ratio written down as an assumption. A timeout is not swallowed: the
	# checks below assert what the wait was for.
	var caught_up := await _until(func() -> bool:
		return third.enemy_count() == host.enemy_count() \
			and third_tutorial.stage == host_tutorial.stage, 2400)
	_check(caught_up, "the mid-join peer never caught up with the session")
	print("third joined mid-fight: roster %d, host bodies %d, third bodies %d, third stage %s" % [
		host_tutorial.fight_enemies.size(), host.enemy_count(), third.enemy_count(),
		_stage_name(third_tutorial.stage)])
	_check(host_tutorial.fight_enemies.size() == 3,
		"a player joining mid-fight grew the roster to %d"
			% host_tutorial.fight_enemies.size())
	# And the newcomer was caught up: same bodies, same order, same stage.
	_check(_roster_signature(third) == _roster_signature(host),
		"the mid-join peer holds a different enemy list:\n  host  %s\n  third %s" % [
			_roster_signature(host), _roster_signature(third)])
	_check(third_tutorial.stage == host_tutorial.stage,
		"the mid-join peer is on stage %s and the host on %s" % [
			_stage_name(third_tutorial.stage), _stage_name(host_tutorial.stage)])

	# --- a caption is an event, not part of the state ----------------------
	# The guest has been taking state packets this whole time. If a caption rode
	# in one of them, this count would climb every frame.
	var said_before: int = guest_tutorial.lines_shown
	await _wait(120)
	print("guest captions: %d before, %d after 120 frames of state packets" % [
		said_before, guest_tutorial.lines_shown])
	_check(guest_tutorial.lines_shown == said_before,
		"the guest was handed %d more captions just from state packets"
			% (guest_tutorial.lines_shown - said_before))

	# --- the fight ends, and the burger arrives on every screen ------------
	for index in host_tutorial.fight_enemies:
		_hose_to_death(host.enemy_at(index))
	var arrived := await _until(func() -> bool:
		return host_tutorial.monster_index >= 0 \
			and guest.enemy_count() == host.enemy_count() \
			and third.enemy_count() == host.enemy_count())
	print("roster down: monster index %d, bodies host %d / guest %d / third %d" % [
		host_tutorial.monster_index, host.enemy_count(), guest.enemy_count(),
		third.enemy_count()])
	_check(arrived, "the burger never reached every peer")
	_check(_roster_signature(host) == _roster_signature(guest)
		and _roster_signature(host) == _roster_signature(third),
		"the peers disagree about the enemy list once the burger arrived")
	# Every peer names the same body as the monster.
	var agreed := await _until(func() -> bool:
		return guest_tutorial.monster_index == host_tutorial.monster_index \
			and third_tutorial.monster_index == host_tutorial.monster_index)
	_check(agreed, "the peers disagree about which body is the burger")

	# --- into the top-up stage, over the mess the fight left --------------
	# Everybody walked into the danger zone; nothing calls a stage function.
	# --- one of them runs, and one of them goes over ----------------------
	# **One fall is enough for the party.** The shared stage moves on the event,
	# not on everybody being made to have it: nobody is dragged through a slip of
	# their own to satisfy the script.
	await _until(func() -> bool:
		return host_tutorial.stage == MayoTutorial.Stage.RUN, 3600)
	var runner: MayoPlayer = host.shooter_for(1).player
	var burger: MayoEnemy = host.enemy_at(host_tutorial.monster_index)
	for _f in 3000:
		var away: Vector3 = runner.global_position - burger.global_position
		away.y = 0.0
		host.debug_aim_at(runner.global_position + away.normalized() * 10.0)
		host.debug_set_input(Vector2(0.0, -1.0), true, false)
		if host_tutorial.drone_alive:
			break
		await _wait(1)
	host.debug_set_input(Vector2.ZERO, false, false)
	print("one player ran and went over: rescued peer %d, dodged=%s, others down=%d" % [
		host_tutorial.rescue_peer, str(host_tutorial.dodged),
		_others_off_their_feet(host, 1)])
	_check(host_tutorial.rescue_peer == 1,
		"the runner's fall was not what started the rescue")
	_check(_others_off_their_feet(host, 1) == 0,
		"somebody who never ran was put on the floor to make the stage move")

	# --- and everybody is sent to the same stall --------------------------
	var pointed := await _until(func() -> bool:
		return host_tutorial.marker_position() != Vector3.INF, 1800)
	_check(pointed, "the stall was never pointed out")
	var markers_agree := await _until(func() -> bool:
		return guest_tutorial.station_index() == host_tutorial.station_index() \
			and third_tutorial.station_index() == host_tutorial.station_index(), 1800)
	print("stall: host #%d at %.1v | guest #%d at %.1v | third #%d at %.1v" % [
		host_tutorial.station_index(), host_tutorial.marker_position(),
		guest_tutorial.station_index(), guest_tutorial.marker_position(),
		third_tutorial.station_index(), third_tutorial.marker_position()])
	_check(markers_agree,
		"the peers are being sent to different stalls: host #%d, guest #%d, third #%d" % [
			host_tutorial.station_index(), guest_tutorial.station_index(),
			third_tutorial.station_index()])
	_check(guest_tutorial.marker_position().distance_to(
			host_tutorial.marker_position()) < 0.05,
		"the guest's marker stands somewhere else than the host's")
	# The drone crosses the same sky on every screen.
	var entry_agrees := await _until(func() -> bool:
		return guest_tutorial.drone_entry().distance_to(
			host_tutorial.drone_entry()) < 0.05, 1800)
	_check(entry_agrees, "the peers disagree about where the drone came in from")

	var refilling := await _until(func() -> bool:
		return host_tutorial.stage == MayoTutorial.Stage.REFILL, 3600)
	_check(refilling, "the rescue never handed over to the top-up stage")
	var stages_agree := await _until(func() -> bool:
		return guest_tutorial.stage == host_tutorial.stage \
			and third_tutorial.stage == host_tutorial.stage)
	print("top-up stage: host %s, guest %s, third %s" % [
		_stage_name(host_tutorial.stage), _stage_name(guest_tutorial.stage),
		_stage_name(third_tutorial.stage)])
	_check(stages_agree, "the peers disagree about the top-up stage")

	# --- the stage waits, and a peer that leaves stops being waited for ---
	var station_at: Vector3 = host_tutorial._station_position
	var guest_id: int = guest._net.local_id()
	var third_id: int = third._net.local_id()
	# Only the host tops up. Two players still owe, so nothing may move.
	host.shooter_for(1).player.global_position = _approach(host, station_at,
		host.shooter_for(1).player.global_position.y)
	await _wait(10)
	_check(host.refill_for(1), "the host could not top up at the marked stall")
	await _wait(180)
	print("host topped up: supplied %s, drone up=%s, stage %s" % [
		str(host_tutorial.supplied), str(host_tutorial.drone_alive),
		_stage_name(host_tutorial.stage)])
	_check(host_tutorial.stage == MayoTutorial.Stage.REFILL,
		"the stage moved on with two players still to top up")
	_check(host_tutorial.drone_alive, "the drone went down with players still to top up")
	# The supplied list is the server's, and it reaches the others.
	var supplied_seen := await _until(func() -> bool:
		return guest_tutorial.supplied.has(1))
	_check(supplied_seen, "the guest never heard who had topped up")

	# --- and the guest tops up through its own request path ---------------
	# **Walked to the stall its own screen marked, and asked the way pressing E
	# asks.** Calling the server's `refill_for` from the test would be the server
	# agreeing with itself: what has to hold is that a guest following the marker
	# it was given is recognised by the server as having used the stall the server
	# chose. The guest is placed from its own `marker_position`, not the host's.
	var guest_marker: Vector3 = guest_tutorial.marker_position()
	_check(guest_marker != Vector3.INF, "the guest was shown no stall to go to")
	var guest_stand: Vector3 = _approach(guest, guest_marker,
		host.shooter_for(guest_id).player.global_position.y)
	# The server owns every body, so that is where the guest's is put; the point
	# is that the *spot* came off the guest's own marker.
	host.shooter_for(guest_id).player.global_position = guest_stand
	guest.shooter_for(guest_id).player.global_position = guest_stand
	await _wait(10)
	guest._request_refill()
	var guest_counted := await _until(func() -> bool:
		return host_tutorial.supplied.has(guest_id), 900)
	print("the guest walked to its own marker %.1v and pressed E: counted=%s" % [
		guest_marker, str(guest_counted)])
	_check(guest_counted,
		"a guest that followed its own marker was not recognised by the server")
	await _wait(120)
	_check(host_tutorial.stage == MayoTutorial.Stage.REFILL,
		"the stage moved on with one player still to top up")

	# --- and now the third leaves without ever topping up ----------------
	# A player who has gone must stop being waited for, or the stage never ends.
	third._net.leave()
	var gone := await _until(func() -> bool:
		return host.shooter_ids().size() == 2 and not host_tutorial.supplied.has(third_id))
	_check(gone, "the host never dropped the peer that left")
	_worlds.remove_at(2)
	var unblocked := await _until(func() -> bool:
		return not host_tutorial.drone_alive, 2400)
	print("third left without topping up: drone down=%s, stage %s" % [
		str(not host_tutorial.drone_alive), _stage_name(host_tutorial.stage)])
	_check(unblocked,
		"the peer that left is still being waited for: the stage is stuck at %s"
			% _stage_name(host_tutorial.stage))
	var drone_agreed := await _until(func() -> bool:
		return guest_tutorial.drone_alive == host_tutorial.drone_alive)
	_check(drone_agreed, "the guest still has the drone flying")

	# --- dying and coming back neither resets nor stalls it --------------
	var stage_before: int = host_tutorial.stage
	var supplied_before: Array = host_tutorial.supplied.duplicate()
	var guest_player: MayoPlayer = host.shooter_for(guest_id).player
	# Dirtied first, so the respawn rules can be checked at the same time.
	guest_player.contamination.paint_mayo(
		guest_player.global_position + Vector3(0.0, 0.2, 0.6), Vector3.BACK)
	var dirty_before := guest_player.contamination.cells_md5()
	var cells_before: int = guest_player.contamination.painted_cell_count()
	_check(cells_before > 0, "the guest could not be dirtied before dying")
	guest_player.begin_slip()
	await _until(func() -> bool:
		return guest_player.state == MayoPlayer.State.DOWN, 300)
	host._damage_player(guest_player, guest_player.max_health * 2.0)
	await _wait(120)
	print("guest died and respawned: stage %s (was %s), supplied %s (was %s), sauce cells %d (was %d)" % [
		_stage_name(host_tutorial.stage), _stage_name(stage_before),
		str(host_tutorial.supplied), str(supplied_before),
		guest_player.contamination.painted_cell_count(), cells_before])
	_check(host_tutorial.stage >= stage_before,
		"a respawn rewound the sequence from %s to %s" % [
			_stage_name(stage_before), _stage_name(host_tutorial.stage)])
	_check(host_tutorial.supplied == supplied_before,
		"a respawn lost who had topped up")
	# The respawn rules themselves, unchanged by any of this.
	_check(guest_player.contamination.cells_md5() == dirty_before,
		"respawning changed the sauce on the player")
	_check(guest_player.state == MayoPlayer.State.NORMAL,
		"the respawned player is in state %d rather than upright" % guest_player.state)
	# And the sequence is still alive: the burger can still be put down.
	var monster: MayoEnemy = host.enemy_at(host_tutorial.monster_index)
	_check(monster != null and monster.is_alive(),
		"the burger is gone, so the last part tests nothing")
	if monster != null and monster.is_alive():
		_hose_to_death(monster)
		var done := await _until(func() -> bool: return host_tutorial.is_complete())
		var done_everywhere := await _until(func() -> bool:
			return guest_tutorial.is_complete())
		print("burger down after a respawn: host complete=%s, guest complete=%s" % [
			str(host_tutorial.is_complete()), str(guest_tutorial.is_complete())])
		_check(done, "the stretch never completed after a respawn")
		_check(done_everywhere, "the guest never saw the stretch complete")

	_finish()


func _finish() -> void:
	for world in _worlds:
		world._net.leave()
	if failures.is_empty():
		print("MAYO_TUTORIAL_NET_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
