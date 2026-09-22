extends SceneTree

# The bottle's three bands, and the one rule that makes them safe to network.
#
#   * steady above `steady_level`: the stream starts at once and does not break
#   * unreliable between the two: it catches, and never more than
#     `max_consecutive_catches` rolls in a row
#   * bottom band: air only, no sauce, and `air_shot_fired` for it
#   * a low bottle never reduces damage -- it costs delivery, not power
#   * the host decides every catch and the answer travels, so two screens see
#     the same shot
#
# The last one is the reason any of this is in the state packet. Everything else
# about a squirt follows from the trigger flag every peer already has; a catch
# is a coin toss, and a coin tossed on each machine separately gives every
# player a different fight.

var failures: Array[String] = []
var air_events := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.push_back(message)


func _hold_frames(scene, shooter, frames: int) -> Dictionary:
	var modes := {}
	var longest_catch_run := 0
	var run := 0
	scene.debug_set_input(Vector2.ZERO, false, true)
	for _f in frames:
		await physics_frame
		modes[shooter.nozzle] = int(modes.get(shooter.nozzle, 0)) + 1
		# A run is counted in *rolls*, not frames: one catch holds for a while.
		if shooter.nozzle == scene.Nozzle.CAUGHT:
			run = maxi(run, shooter.catches_in_a_row)
		else:
			longest_catch_run = maxi(longest_catch_run, run)
			run = 0
	longest_catch_run = maxi(longest_catch_run, run)
	scene.debug_set_input(Vector2.ZERO, false, false)
	return {"modes": modes, "longest_run": longest_catch_run}


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.set_process_unhandled_input(false)
	scene.debug_clear_enemies()
	scene.debug_input_override = true
	var shooter = scene._local
	scene.air_shot_fired.connect(func(_id, _from, _dir): air_events += 1)

	print("bands: steady above %.0f%%, air at or below %.0f%%; catch %.0f%% every %.2f s for %.2f..%.2f s, at most %d in a row" % [
		scene.steady_level * 100.0, scene.spluttering_level * 100.0,
		scene.catch_chance * 100.0, scene.catch_roll_interval,
		scene.catch_delay_min, scene.catch_delay_max, scene.max_consecutive_catches])

	# --- the bands are where they say they are ---
	_check(scene.sauce_stage_of(1.0) == scene.SauceStage.STEADY, "a full bottle is not steady")
	_check(scene.sauce_stage_of(scene.steady_level + 0.01) == scene.SauceStage.STEADY,
		"just above the steady threshold is not steady")
	_check(scene.sauce_stage_of(scene.steady_level - 0.01) == scene.SauceStage.SPLUTTERING,
		"just below the steady threshold is not spluttering")
	_check(scene.sauce_stage_of(scene.spluttering_level) == scene.SauceStage.EMPTY,
		"the bottom threshold itself is not in the bottom band")
	# Seconds left is the whole reason the drain is a flow.
	print("a full bottle is %.1f s of delivery at %.3f tank/s" % [
		scene.sauce_seconds_left(1.0), scene.sauce_flow_per_second])
	_check(is_equal_approx(scene.sauce_seconds_left(1.0), 1.0 / scene.sauce_flow_per_second),
		"seconds left is not level divided by flow")

	# --- steady: no catches at all ---
	shooter.sauce = 1.0
	var steady := await _hold_frames(scene, shooter, 40)
	print("full bottle, 40 frames: %s" % str(steady.modes))
	_check(not steady.modes.has(scene.Nozzle.CAUGHT),
		"a full bottle caught, which is what 'steady' is supposed to rule out")
	_check(int(steady.modes.get(scene.Nozzle.STREAM, 0)) > 30,
		"a full bottle delivered on only %d of 40 frames"
			% int(steady.modes.get(scene.Nozzle.STREAM, 0)))

	# --- unreliable: it catches, and the run is capped ---
	var caught_at_least_once := false
	var worst_run := 0
	var unreliable: float = (scene.steady_level + scene.spluttering_level) * 0.5
	for attempt in 24:
		await _idle(scene, 0.35)
		shooter.sauce = unreliable
		var spell := await _hold_frames(scene, shooter, 26)
		if spell.modes.has(scene.Nozzle.CAUGHT):
			caught_at_least_once = true
		worst_run = maxi(worst_run, int(spell.longest_run))
	print("%.0f%% bottle over 24 presses: caught at least once=%s, longest run of catches=%d (cap %d)" % [
		unreliable * 100.0, str(caught_at_least_once), worst_run,
		scene.max_consecutive_catches])
	_check(caught_at_least_once,
		"24 presses on an unreliable bottle never caught once")
	_check(worst_run <= scene.max_consecutive_catches,
		"%d catches in a row, over the cap of %d" % [worst_run, scene.max_consecutive_catches])

	# --- bottom band: air, and the event for it ---
	# Long enough to clear the pause the last press left behind, so the window
	# is a press and not the tail of the one before it.
	await _idle(scene, 1.0)
	air_events = 0
	shooter.sauce = scene.spluttering_level * 0.6
	var bottom := await _hold_frames(scene, shooter, 20)
	var air_frames := int(bottom.modes.get(scene.Nozzle.AIR, 0))
	print("bottom band, 20 frames: %s, air_shot_fired %d time(s)" % [
		str(bottom.modes), air_events])
	# What matters is that sauce never comes out and air does. How many frames
	# of each is the squirt allowance and its cooldown, which apply down here
	# too and are `probe_sauce`'s subject.
	_check(not bottom.modes.has(scene.Nozzle.STREAM),
		"a bottle in the bottom band still delivered sauce")
	_check(not bottom.modes.has(scene.Nozzle.CAUGHT),
		"a bottle in the bottom band caught rather than blowing air")
	_check(air_frames > 0, "the bottom band never blew air at all")
	_check(air_events > 0, "the bottom band never raised air_shot_fired")

	# --- the unreliable band sputters: air mixed in with the sauce ---
	# What a nearly empty squeeze bottle sounds like, and the only feedback the
	# band has now that crossing into it is silent. A beep at the threshold said
	# it once; this keeps saying it, and says it while the sauce is still coming.
	# Accumulated over several presses rather than one. A press only rolls the
	# dice every `catch_roll_interval`, so a single short one gets about four
	# rolls -- and four rolls at this chance come up empty nearly a fifth of the
	# time, which is a coin toss deciding whether the check passes rather than
	# the behaviour it is asking about.
	air_events = 0
	var mixed := {}
	for _press in 6:
		await _idle(scene, 0.7)
		scene.debug_set_input(Vector2.ZERO, false, true)
		for _f in 70:
			shooter.sauce = unreliable
			await physics_frame
			mixed[shooter.nozzle] = int(mixed.get(shooter.nozzle, 0)) + 1
		scene.debug_set_input(Vector2.ZERO, false, false)
	print("unreliable band over 6 presses: %s, air_shot_fired %d time(s)" % [
		str(mixed), air_events])
	_check(int(mixed.get(scene.Nozzle.STREAM, 0)) > 0,
		"the unreliable band never delivered sauce at all")
	_check(int(mixed.get(scene.Nozzle.CAUGHT, 0)) > 0,
		"the unreliable band never caught, so nothing was mixed in")
	_check(air_events > 0,
		"the unreliable band caught but never puffed: sauce and air are not mixing")

	# --- you can see the sauce through the bottle ---
	# The level *is* the contents, so the body has to actually be translucent.
	# An alpha in the colour does nothing by itself -- `StandardMaterial3D`
	# ignores it until transparency is switched on -- so this was set
	# see-through and drawn solid, with the gauge sealed inside it. Nothing
	# failed; the bottle simply told you nothing.
	var body: MeshInstance3D = shooter.weapon.get_node("Body")
	var body_material: StandardMaterial3D = body.material_override
	print("bottle body: alpha %.2f, transparency mode %d, contents visible=%s" % [
		body_material.albedo_color.a, body_material.transparency,
		str(shooter.bottle_contents.visible)])
	_check(body_material.albedo_color.a < 0.95,
		"the bottle body is opaque, so the sauce in it cannot be read")
	_check(body_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
		"the bottle body has an alpha but transparency is off, so it draws solid")
	# And the contents move with the level rather than being decoration.
	shooter.sauce = 1.0
	scene._update_bottle_gauge(shooter)
	var full_scale: float = shooter.bottle_contents.scale.y
	shooter.sauce = 0.25
	scene._update_bottle_gauge(shooter)
	var quarter_scale: float = shooter.bottle_contents.scale.y
	print("contents: %.2f of the bottle when full, %.2f at a quarter" % [
		full_scale, quarter_scale])
	_check(quarter_scale < full_scale * 0.5,
		"the sauce in the bottle does not drop with the level")

	# --- a low bottle never costs damage ---
	# Damage is per strand point, and nothing in the reliability code touches
	# it. Checked as a fact about the settings rather than by shooting, so it
	# cannot quietly become false.
	_check(not scene.low_sauce_reduces_damage,
		"low_sauce_reduces_damage is on: a low bottle is meant to cost delivery, not power")
	var enemy_damage := 0.0
	var fresh := MayoEnemy.new()
	root.add_child(fresh)
	fresh.build(scene.body_cell_size, scene.contamination_brush_radius, Color("4d3f6b"))
	enemy_damage = fresh.sauce_damage_per_hit
	for level in [1.0, unreliable, scene.spluttering_level * 0.5]:
		shooter.sauce = level
		_check(is_equal_approx(fresh.sauce_damage_per_hit, enemy_damage),
			"damage per hit changed with the bottle level")
	print("damage per hit is %.2f at every level" % enemy_damage)
	fresh.queue_free()

	if failures.is_empty():
		print("MAYO_RELIABILITY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _idle(scene, seconds: float) -> void:
	scene.debug_set_input(Vector2.ZERO, false, false)
	for _f in int(seconds * 60.0):
		await physics_frame
