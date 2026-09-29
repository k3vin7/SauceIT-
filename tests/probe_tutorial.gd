extends SceneTree

# The opening stretch of the street, driven the way a player drives it.
#
# The rule this file is written to: **no stage is allowed to advance because the
# test told it to.** Bodies are killed with the real damage call, bottles are
# filled through the real stall reach test, players are moved and then left to be
# noticed. The only thing called directly is the roster sizing, which is the thing
# under test in that one section.
#
# What is checked here:
#   * a plain run of the game actually starts the sequence
#   * the opening roster is party size plus one, at one through four players
#   * the burger does not appear until every one of those bodies is down
#   * the mess they leave is real floor thickness, and running on it puts a player
#     down through the game's own slip rule
#   * a player who walks across instead still moves the sequence on -- not falling
#     must never be a dead end
#   * while the drone has it, the burger walks at the drone and cannot touch a
#     player
#   * the drone survives while anybody still has not topped up
#   * once everybody has, and the doctor has finished talking, it goes down once
#   * after that the burger comes back for the party and can hurt them again
#   * putting it down completes the stretch and leaves the controls alone

var failures: Array[String] = []

var scene
var tutorial: MayoTutorial


func _initialize() -> void:
	# **Deliberately not disabled.** Every other probe switches the sequence off
	# because it would change the street under them; this one is the check that a
	# plain run of the shipped game really does start it, so it runs the shipped
	# configuration and asserts the flag below.
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _wait(frames: int) -> void:
	for _f in frames:
		await physics_frame


## Waits for something to be true rather than for a count of frames.
func _until(condition: Callable, frames := 3000) -> bool:
	for _f in frames:
		if condition.call():
			return true
		await physics_frame
	return false


## Every enemy on the opening roster, by index.
func _roster() -> Array:
	var out := []
	for index in tutorial.fight_enemies:
		var enemy: MayoEnemy = scene.enemy_at(index)
		if enemy != null and is_instance_valid(enemy):
			out.push_back(enemy)
	return out


## Kills one body with the damage call the stream uses. Not a tutorial function:
## this is what a hit does, repeated until the bar is empty.
func _hose_to_death(enemy: MayoEnemy) -> void:
	var guard := 0
	while enemy.is_alive() and guard < 4000:
		enemy.take_sauce_hit(enemy.global_position + Vector3(0.0, 0.0, 2.0))
		guard += 1


func _stage_name(value: int) -> String:
	return MayoTutorial.Stage.keys()[value]


func _run() -> void:
	# --- 1. the roster is party size plus one, at every party size ----------
	# A fresh world per size, because the count is fixed when the fight starts
	# and the point is what it is fixed to.
	for party in [1, 2, 3, 4]:
		var world = load("res://main.tscn").instantiate()
		root.add_child(world)
		await process_frame
		await physics_frame
		world.set_process_unhandled_input(false)
		for extra in range(1, party):
			world.create_avatar(extra + 1, extra, false)
		await physics_frame
		var run_tutorial: MayoTutorial = world.tutorial()
		if run_tutorial == null:
			_check(false, "the tutorial did not build at all")
			_finish()
			return
		# The sizing is what is under test here, so it is the one thing called.
		run_tutorial._begin_first_fight()
		await physics_frame
		var placed: int = run_tutorial.fight_enemies.size()
		var rushers := 0
		var others := 0
		for index in run_tutorial.fight_enemies:
			var body: MayoEnemy = world.enemy_at(index)
			if body != null and body.kind == MayoEnemy.EnemyKind.MOLDY_TOAST_RUSHER:
				rushers += 1
			else:
				others += 1
		print("%d player(s): party_size=%d roster=%d (%d rushers, %d other)" % [
			party, world.party_size(), placed, rushers, others])
		_check(placed == party + 1,
			"%d players got %d small enemies rather than %d" % [party, placed, party + 1])
		_check(rushers == placed,
			"%d of the opening roster are not toast rushers" % others)
		# Nowhere near each other, or they arrive as one body.
		var spread := 0.0
		for a in _roster_of(world, run_tutorial):
			for b in _roster_of(world, run_tutorial):
				spread = maxf(spread, a.global_position.distance_to(b.global_position))
		_check(placed < 2 or spread > 4.0,
			"%d players: the roster is bunched into %.1f m" % [party, spread])
		# And each one has its own health, untouched by the tutorial.
		for body in _roster_of(world, run_tutorial):
			_check(is_equal_approx(body.health, body.max_health)
				and is_equal_approx(body.max_health, 52.0),
				"a tutorial rusher was given %.0f health rather than its own 52" % body.max_health)
		world.free()
		await process_frame

	# --- the run the rest of this file follows ------------------------------
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	tutorial = scene.tutorial()
	var player: MayoPlayer = scene._player

	# --- 2. a plain run starts it on its own -------------------------------
	_check(not MayoTutorial.disabled,
		"this probe must run with the sequence switched on or it tests nothing")
	_check(tutorial != null, "a plain run of the game has no tutorial")
	if tutorial == null:
		_finish()
		return
	_check(tutorial.is_enabled(), "the tutorial built but is switched off")
	_check(scene.enemy_count() == 0,
		"the street's standing roster was placed as well: %d bodies before the fight"
			% scene.enemy_count())
	# --- 2a. the light, and walking to it ----------------------------------
	# The opening is an instruction: a spot is lit, and the stage ends when it has
	# been stood on. Walking is allowed through it -- it is the thing being taught
	# -- and the bottle is not, because there is nothing yet to shoot at.
	var lit := await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.INTRO)
	_check(lit, "the sequence never started")
	_check(tutorial.allows_movement(), "the opening will not let the player walk")
	_check(not tutorial.allows_firing(),
		"the bottle works before there is anything to shoot at")

	# **Nothing points at the spot before the doctor does.** A lit patch of road
	# is a louder instruction than a caption, so one burning through the greeting
	# gets walked to and the line it illustrates never gets read. Checked on the
	# greeting itself: the light, the on-screen marker and the standing objective
	# all have to still be absent while it is up.
	# The caption queue is popped on the frame after the stage turns over, so this
	# waits for the greeting to actually be up before asserting what is not.
	var greeting := await _until(func() -> bool:
		return tutorial.current_line() == MayoTutorial.LINES[MayoTutorial.SAY_HELLO], 600)
	_check(greeting, "the opening did not start on the greeting")
	_check(tutorial.move_target() == Vector3.INF,
		"the spot was lit before the line that tells you to walk to it")
	_check(tutorial.marker_position() == Vector3.INF,
		"the spot was marked on screen before the line that tells you to walk to it")
	_check(tutorial.objective_text().is_empty(),
		"the objective gave the instruction away before the doctor said it")
	_check(scene.get_node_or_null("TutorialMoveLight") == null,
		"the blue light was already burning during the greeting")

	# And it all arrives together, with its own line.
	var told := await _until(func() -> bool:
		return tutorial.current_line() == MayoTutorial.LINES[MayoTutorial.SAY_WALK_HERE], 900)
	_check(told, "the doctor never got to the line about walking")
	_check(tutorial.move_target() != Vector3.INF,
		"the line played and no spot was lit")
	_check(scene.get_node_or_null("TutorialMoveLight") != null,
		"the line played and no blue light came up in the world")
	_check(tutorial.marker_position() != Vector3.INF,
		"the spot to walk to is not marked on screen")
	print("the light stands at %.1v, %.1f m from the spawn" % [
		tutorial.move_target(),
		Vector2(tutorial.move_target().x - player.global_position.x,
			tutorial.move_target().z - player.global_position.z).length()])

	# Walked there on the keys, not teleported: reaching it is the condition.
	var target: Vector3 = tutorial.move_target()
	var reached_light := false
	for _f in 1800:
		if tutorial.stage != MayoTutorial.Stage.INTRO:
			reached_light = true
			break
		scene.debug_aim_at(Vector3(target.x, player.global_position.y, target.z))
		scene.debug_set_input(Vector2(0.0, -1.0), false, false)
		await physics_frame
	scene.debug_set_input(Vector2.ZERO, false, false)
	print("walked to the light: stage %s, %.1f m short of it" % [
		_stage_name(tutorial.stage),
		Vector2(player.global_position.x - target.x,
			player.global_position.z - target.z).length()])
	_check(reached_light, "walking onto the light did not end the opening")
	_check(tutorial.stage == MayoTutorial.Stage.BRIEF,
		"standing on the light led to %s rather than the briefing"
			% _stage_name(tutorial.stage))

	# --- 2b. the briefing holds the controls, and only for a beat ----------
	_check(not tutorial.allows_movement(), "the briefing does not hold the controls")
	_check(not tutorial.allows_firing(), "the bottle works during the briefing")
	_check(player.frozen, "the player was not actually held still")
	var held_at: Vector3 = player.global_position
	# Keys down the whole time: a held body must not answer them.
	for _f in 150:
		scene.debug_set_input(Vector2(0.0, -1.0), true, true)
		await physics_frame
	scene.debug_set_input(Vector2.ZERO, false, false)
	var drifted: float = held_at.distance_to(player.global_position)
	print("2.5 s of held keys while the doctor talks: moved %.2f m" % drifted)
	_check(drifted < 1.0,
		"the player walked %.2f m while the controls were supposed to be held" % drifted)

	# --- 2c. and they come back when the toasts do -------------------------
	var started := await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT)
	_check(started, "the sequence never reached the opening fight on its own")
	_check(tutorial.allows_movement() and tutorial.allows_firing(),
		"the controls did not come back when the fight started")
	_check(not player.frozen, "the player is still held still during the fight")
	print("opening fight: %d bodies, stage %s, controls back" % [
		tutorial.fight_enemies.size(), _stage_name(tutorial.stage)])

	# --- 3. the burger waits for every one of them -------------------------
	var roster := _roster()
	_check(roster.size() >= 2, "the solo roster should be two bodies")
	_check(tutorial.monster_index < 0, "the burger was already here during the fight")
	# All but one down, and it still must not appear.
	for index in range(roster.size() - 1):
		_hose_to_death(roster[index])
	await _wait(20)
	var alive := 0
	for body in roster:
		if body.is_alive():
			alive += 1
	print("one left standing (%d alive): stage %s, monster index %d" % [
		alive, _stage_name(tutorial.stage), tutorial.monster_index])
	_check(alive == 1, "the test failed to leave exactly one body standing")
	_check(tutorial.monster_index < 0,
		"the burger arrived with a body still standing")
	_check(tutorial.stage == MayoTutorial.Stage.FIRST_FIGHT,
		"the fight ended with a body still standing")

	# --- 4. the mess they leave is real, and it is what trips you ----------
	# Recorded before the last kill so the spill can be attributed to it.
	var spill_at: Vector3 = roster[roster.size() - 1].global_position
	_hose_to_death(roster[roster.size() - 1])
	var arrived := await _until(func() -> bool: return tutorial.monster_index >= 0)
	_check(arrived, "the burger never arrived once the roster was down")
	print("roster down -> stage %s, monster index %d" % [
		_stage_name(tutorial.stage), tutorial.monster_index])

	# --- 4a. it is put down behind them, while they cannot walk away ------
	# The opening fight is fought backing away and turning, so where "behind" is
	# is only knowable when it ends -- and the party is held still for the one
	# line it takes to put the body there, so it cannot be placed beside somebody
	# who walked while it happened.
	_check(tutorial.stage == MayoTutorial.Stage.MONSTER_CUE,
		"the fight ended into %s rather than the cue" % _stage_name(tutorial.stage))
	_check(not tutorial.allows_movement() and player.frozen,
		"the party can walk while the burger is being put down behind them")
	var placed: MayoEnemy = scene.enemy_at(tutorial.monster_index)
	_check(placed != null, "the burger index names nothing")
	if placed != null:
		var to_it: Vector3 = placed.global_position - player.global_position
		to_it.y = 0.0
		# A body's front is its -z, so +z in its own basis is its back.
		var behind: float = to_it.normalized().dot(player.global_basis.z)
		print("burger put down %.1f m away, %.2f of the way behind them (1 = dead behind)" % [
			to_it.length(), behind])
		_check(behind > 0.3,
			"the burger was put down at %.2f -- that is beside or in front of them"
				% behind)
		_check(to_it.length() > 2.5,
			"the burger was put down %.1f m away, which is on top of them"
				% to_it.length())
		_check(to_it.length() < MayoTutorial.MONSTER_BEHIND + 3.0,
			"the burger was put down %.1f m away rather than about %.1f" % [
				to_it.length(), MayoTutorial.MONSTER_BEHIND])
		# Far enough out that there is a walk to watch: the run prompt does not
		# come until it is `MONSTER_CLOSE`, so a spawn inside that would skip the
		# whole approach.
		_check(to_it.length() > MayoTutorial.MONSTER_CLOSE + 2.0,
			"the burger was put down %.1f m away, inside the %.1f m the run prompt fires at"
				% [to_it.length(), MayoTutorial.MONSTER_CLOSE])

	# --- 4b. and the party watches it walk in ------------------------------
	# Between "뒤를 조심하세요!" and "너무 가까워… 물리겠어요!!" the burger is
	# crossing the gap on its own legs, with the controls back. That stretch is
	# the beat: the run prompt waits for it to actually be close.
	var watching := await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.MONSTER_ARRIVES, 900)
	_check(watching, "the cue never handed over to the approach")
	_check(tutorial.allows_movement() and not player.frozen,
		"the controls are still held while the burger walks in")
	var closed_from := 0.0
	var run_gap := 0.0
	if placed != null:
		closed_from = Vector2(player.global_position.x - placed.global_position.x,
			player.global_position.z - placed.global_position.z).length()
		var told_to_run := await _until(func() -> bool:
			return tutorial.stage == MayoTutorial.Stage.RUN, 1800)
		run_gap = Vector2(player.global_position.x - placed.global_position.x,
			player.global_position.z - placed.global_position.z).length()
		print("it walked in from %.1f m; told to run at %.1f m (prompt set at %.1f)" % [
			closed_from, run_gap, MayoTutorial.MONSTER_CLOSE])
		_check(told_to_run, "the burger walked in and the run prompt never came")
		_check(run_gap <= MayoTutorial.MONSTER_CLOSE + 0.5,
			"the run prompt came at %.1f m rather than about %.1f" % [
				run_gap, MayoTutorial.MONSTER_CLOSE])
		_check(closed_from - run_gap > 3.0,
			"the burger only closed %.1f m before the prompt: there was no approach to watch"
				% (closed_from - run_gap))
		_check(tutorial.current_line() == MayoTutorial.LINES[MayoTutorial.SAY_TOO_CLOSE],
			"the run prompt is not the line about it being too close")

	var slippery: bool = scene._floor.is_slippery_at(spill_at)
	var thickness: int = scene._floor.thickness_at(spill_at)
	print("where the last body burst: thickness %d, slip_thickness %d, slippery=%s" % [
		thickness, scene._floor.slip_thickness, str(slippery)])
	_check(slippery,
		"the spill left thickness %d, under the floor's own %d: nothing to slip on" % [
			thickness, scene._floor.slip_thickness])

	# Running on it puts the player down -- through `_update_slip`, which is the
	# game's own rule and is not called from here.
	# After the "look behind you" hold has let go: the keys do nothing while the
	# doctor is talking over it, which is the point of the hold, so running at the
	# mess before then would be testing the hold rather than the floor.
	var keys_back := await _until(func() -> bool: return tutorial.allows_movement(), 900)
	_check(keys_back, "the controls never came back after the burger was placed")
	player.global_position = Vector3(spill_at.x, player.global_position.y, spill_at.z)
	player.velocity = Vector3.ZERO
	await physics_frame
	scene.debug_set_input(Vector2(0.0, -1.0), true, false)
	var went_down := await _until(func() -> bool:
		return player.state != MayoPlayer.State.NORMAL, 240)
	# Let go of the keys by pressing nothing, not by clearing the override:
	# `debug_clear_input_override` hands the trigger back to the real keyboard but
	# leaves the last injected movement vector on the body, so a test that only
	# clears carries on sprinting up the street.
	scene.debug_set_input(Vector2.ZERO, false, false)
	print("running across it: state %d (%s)" % [
		player.state, "went over" if went_down else "stayed up"])
	_check(went_down, "running over the spill did not put the player down")
	# Back on their feet before the next part.
	await _until(func() -> bool: return player.state == MayoPlayer.State.NORMAL, 600)

	# --- 5. the rescue is earned by an actual fall -------------------------
	# The slip test above was a real one: the player ran across their own mess and
	# the floor put them down, which is exactly the event the rescue hangs on. So
	# what is checked here is that it was that fall -- and not standing in danger,
	# and not a clock -- that brought the drone.
	#
	# `probe_tutorial_story` plays the same beat out on the keys from the prompt
	# onwards and asserts the order of the whole log; this is the unit of it.
	_check(scene.floor_is_slippery_at(spill_at),
		"the spot that put the player down is not actually slippery")
	var baited := await _until(func() -> bool:
		return tutorial.stage == MayoTutorial.Stage.DRONE_BAIT \
			or tutorial.stage == MayoTutorial.Stage.REFILL, 1800)
	print("after going over: stage %s, drone up=%s, rescued peer %d, dodged=%s" % [
		_stage_name(tutorial.stage), str(tutorial.drone_alive),
		tutorial.rescue_peer, str(tutorial.dodged)])
	_check(baited, "going over never brought the drone in")
	_check(tutorial.drone_alive, "the stage moved on but no drone came")
	_check(tutorial.rescue_peer == 1,
		"the rescue was not recorded against the player who actually fell")
	_check(not tutorial.dodged, "a player who went over was recorded as having dodged")
	# And the order to run is not still being shouted at somebody already saved.
	_check(tutorial.current_line_id() != MayoTutorial.SAY_RUN_AWAY \
		and tutorial.current_line_id() != MayoTutorial.SAY_TOO_CLOSE,
		"the order to run was still on screen after the rescue")

	# --- 6. the drone has it, so the party does not ------------------------
	var monster: MayoEnemy = scene.enemy_at(tutorial.monster_index)
	_check(monster != null and monster.is_alive(), "the burger is not here to be baited")
	# Built on the frame after the stage turns it on -- it flies in from above
	# rather than appearing -- so this waits for it instead of reading it the
	# instant the stage changed.
	var flew_in := await _until(func() -> bool:
		return tutorial._drone != null and is_instance_valid(tutorial._drone), 240)
	_check(flew_in, "no drone node was built")
	var drone: Node3D = tutorial._drone

	# **It has to arrive before it has the burger's attention.** Coming in is a
	# beat of its own: the burger keeps walking at the party through the whole
	# flight, and only turns when the drone is genuinely in its face and it is
	# going for somebody. Handing the bait over the instant the node existed made
	# it lose interest while the drone was still a second away and the party had
	# not finished turning round.
	_check(monster.bait == null,
		"the burger was handed the drone before the drone had got anywhere near it")
	var grabbed := await _until(func() -> bool: return tutorial.drone_has_it, 900)
	print("the drone took it after %s" % ("arriving" if grabbed else "never arriving"))
	_check(grabbed, "the drone never got its attention")
	_check(monster.bait == drone, "the burger was not given the drone to chase")
	# And it was taken off somebody it was actually going for, not off thin air.
	# Put it right on top of the player: with the drone in its face, nothing about
	# standing next to it may cost health.
	monster.global_position = Vector3(player.global_position.x,
		monster.global_position.y, player.global_position.z + 1.0)
	monster._contact_cooldown = 0.0
	player.health = player.max_health
	var before_health: float = player.health
	var moved_from: Vector3 = monster.global_position
	await _wait(120)
	print("baited, standing on the player: health %.0f -> %.0f, it moved %.2f m" % [
		before_health, player.health, moved_from.distance_to(monster.global_position)])
	_check(is_equal_approx(player.health, before_health),
		"the baited burger took %.0f health off a player" % (before_health - player.health))
	_check(moved_from.distance_to(monster.global_position) > 0.2,
		"the baited burger stood still instead of going for the drone")
	# **And it stays where the drone is holding it.** The first version of the
	# drone hovered off the burger's own nose, so the burger walked at its own face
	# and wandered a hundred metres down the street -- which then left it too far
	# from anybody to notice them once the drone was gone. The drone holds a fixed
	# spot, so the burger has to be found near that spot.
	await _wait(420)
	var from_anchor := Vector2(
		monster.global_position.x - tutorial.bait_anchor.x,
		monster.global_position.z - tutorial.bait_anchor.z).length()
	print("held by the drone: %.1f m from the spot it is held at (lead %.1f m)" % [
		from_anchor, MayoTutorial.DRONE_LEAD])
	_check(from_anchor < MayoTutorial.DRONE_LEAD + 8.0,
		"the baited burger wandered %.1f m off the spot the drone holds it at"
			% from_anchor)

	# --- 7. the drone stays up while anybody still needs sauce -------------
	# A second player who never tops up. The stage must wait for them.
	var guest = scene.create_avatar(2, 1, false)
	await _wait(30)
	_check(tutorial.stage == MayoTutorial.Stage.REFILL
			or tutorial.stage == MayoTutorial.Stage.DRONE_BAIT,
		"the sequence left the top-up stage as soon as a second player joined")
	var station_at: Vector3 = tutorial.marker_position() if \
		tutorial.stage == MayoTutorial.Stage.REFILL else tutorial._station_position
	_check(station_at != Vector3.INF, "no stall was marked to top up at")

	# The local player tops up for real: stood at the machine, through the same
	# reach test the E key goes through.
	await _until(func() -> bool: return tutorial.stage == MayoTutorial.Stage.REFILL)
	player.global_position = _approach(station_at, player.global_position.y)
	await _wait(10)
	# **With a full bottle on purpose.** Somebody who never fired still has to be
	# able to walk up and be counted: the stall succeeds on standing at it, not on
	# being empty, and the sequence follows the stall rather than second-guessing
	# it. A player held up here because they were already full would be stuck.
	scene.shooter_for(1).sauce = 1.0
	var filled: bool = scene.refill_for(1)
	print("host at the stall: refill_for=%s supplied=%s" % [
		str(filled), str(tutorial.supplied)])
	_check(filled, "standing at the marked stall did not top the host up")
	_check(tutorial.supplied.has(1),
		"a player who was already full was not counted as having topped up")
	await _wait(240)
	print("one of two topped up: stage %s, drone up=%s" % [
		_stage_name(tutorial.stage), str(tutorial.drone_alive)])
	_check(tutorial.drone_alive,
		"the drone went down with a player still to top up")
	_check(tutorial.stage == MayoTutorial.Stage.REFILL,
		"the top-up stage ended with a player still to top up")

	# --- 8. everybody topped up, and it goes down once --------------------
	guest.player.global_position = _approach(station_at, guest.player.global_position.y)
	await _wait(10)
	var guest_filled: bool = scene.refill_for(2)
	_check(guest_filled, "the second player could not top up at the same stall")
	var went_down_once := await _until(func() -> bool:
		return not tutorial.drone_alive, 1200)
	print("both topped up: drone down=%s at stage %s" % [
		str(not tutorial.drone_alive), _stage_name(tutorial.stage)])
	_check(went_down_once, "everybody topped up and the drone never went down")
	# And the beat between: it must not have vanished the instant the last bottle
	# was filled.
	_check(tutorial.stage == MayoTutorial.Stage.COOP_FIGHT
			or tutorial.stage == MayoTutorial.Stage.DRONE_DOWN,
		"the drone went down but the stage is %s" % _stage_name(tutorial.stage))
	var drone_deaths := 0
	for _f in 120:
		if not tutorial.drone_alive:
			drone_deaths = 1
		await physics_frame
	_check(drone_deaths == 1 and not tutorial.drone_alive,
		"the drone came back after being destroyed")
	_check(monster.bait == null, "the burger is still chasing a drone that is gone")

	# --- 9. and it comes back for the party -------------------------------
	# First on its own legs, from a distance: with the drone gone it has to notice
	# the party again and walk the street to them.
	player.global_position = Vector3(monster.global_position.x,
		player.global_position.y, monster.global_position.z - 15.0)
	player.velocity = Vector3.ZERO
	await _wait(10)
	var gap_before: float = Vector2(
		player.global_position.x - monster.global_position.x,
		player.global_position.z - monster.global_position.z).length()
	await _wait(420)
	var gap_after: float = Vector2(
		player.global_position.x - monster.global_position.x,
		player.global_position.z - monster.global_position.z).length()
	print("with the drone gone: gap %.1f m -> %.1f m" % [gap_before, gap_after])
	_check(gap_after < gap_before - 4.0,
		"the burger closed only %.1f m of %.1f: it is not chasing again"
			% [gap_before - gap_after, gap_before])

	monster.global_position = Vector3(player.global_position.x,
		monster.global_position.y, player.global_position.z + 1.0)
	monster._contact_cooldown = 0.0
	player.health = player.max_health
	var health_before: float = player.health
	await _wait(180)
	print("after the drone: health %.0f -> %.0f" % [health_before, player.health])
	_check(player.health < health_before,
		"the burger never came back for the player once the drone was gone")

	# --- 10. putting it down completes the stretch ------------------------
	_hose_to_death(monster)
	var done := await _until(func() -> bool: return tutorial.is_complete())
	print("burger down: stage %s complete=%s" % [
		_stage_name(tutorial.stage), str(tutorial.is_complete())])
	_check(done, "the burger went down and the stretch never completed")
	# The controls are still the player's: nothing here locks them at the end.
	#
	# Tried in all four directions and passed if the body answers in any of them.
	# Which way is clear depends on where the chase happened to end and where the
	# corpse is lying, and "cannot walk into a dead monster" is not the thing being
	# tested -- what is, is that the sequence does not hold the keys at the end.
	var upright := await _until(func() -> bool:
		return player.state == MayoPlayer.State.NORMAL, 600)
	_check(upright, "the player was left unable to act after the stretch completed")
	_check(scene._input_enabled,
		"the sequence finished with the player's input still switched off")
	_check(not player.is_incapacitated(),
		"the sequence finished with the player unable to act")
	var best_move := 0.0
	var answered := ""
	for way in [Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0),
			Vector2(1.0, 0.0)]:
		player.velocity = Vector3.ZERO
		await _wait(5)
		var from: Vector3 = player.global_position
		scene.debug_set_input(way, false, false)
		await _wait(45)
		scene.debug_set_input(Vector2.ZERO, false, false)
		var moved: float = from.distance_to(player.global_position)
		if moved > best_move:
			best_move = moved
			answered = str(way)
	print("after completing, the keys moved the player %.2f m (best of four, %s)" % [
		best_move, answered])
	_check(best_move > 0.5,
		"the player could not move in any direction after the stretch completed")

	_finish()


## A spot in front of a stall's counter, on the side the counter faces, just
## inside the reach the game already uses.
func _approach(station: Vector3, stand_y: float) -> Vector3:
	var facing := Vector3.ZERO
	for entry in scene._refill_stations:
		if (entry["position"] as Vector3).distance_to(station) < 0.01:
			facing = entry["facing"]
			break
	if facing == Vector3.ZERO:
		facing = Vector3.BACK
	var at: Vector3 = station + facing * (scene.refill_reach * 0.5)
	at.y = stand_y
	return at


func _roster_of(world, run_tutorial: MayoTutorial) -> Array:
	var out := []
	for index in run_tutorial.fight_enemies:
		var enemy: MayoEnemy = world.enemy_at(index)
		if enemy != null and is_instance_valid(enemy):
			out.push_back(enemy)
	return out


func _finish() -> void:
	if failures.is_empty():
		print("MAYO_TUTORIAL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
