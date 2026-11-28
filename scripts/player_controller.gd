class_name MayoPlayer
extends CharacterBody3D

## Walk/run movement plus the slip-and-fall state machine. Falling and standing
## up lock out movement and firing; the prototype reads `is_incapacitated()`.
##
## In a session the server owns every player: it runs this simulation for both,
## reading the remote player's keys out of `input_move`/`input_run` instead of
## the local keyboard, and the clients' copies are set from the network with
## `apply_network_state` rather than simulated.

enum State { NORMAL, STUMBLE, FALLING, DOWN, STANDING_UP, DEAD }

## Shared by player construction, by the imported characters so every variant
## stays aligned with the gameplay body, and by enemies whose authored size is
## expressed as a multiple of it.
const CAPSULE_RADIUS := 0.64
const CAPSULE_HEIGHT := 2.56

@export_group("Movement")
@export_range(0.5, 24.0, 0.1, "suffix:m/s") var walk_speed := 5.2
@export_range(0.5, 28.0, 0.1, "suffix:m/s") var run_speed := 10.4
## Doubled with the speeds, so getting up to them still takes the time it did:
## left alone, twice the top speed would take twice as long to reach and the
## player would feel heavier rather than faster.
@export_range(1.0, 80.0, 0.5) var acceleration := 36.0
## How fast a downed player drags themselves, as a fraction of the walk. Only
## where the world allows it (`crawl_allowed`) and only once the death clip
## has played out: a body still falling is not yet a body that can crawl.
@export_range(0.0, 1.0, 0.05) var crawl_speed_scale := 0.4
## Jump. The body is 2.56 m, so these are scaled for it: 8 m/s against 20 m/s^2
## clears about 1.6 m, a little over half its own height. Gravity here is the
## body's own, not the sauce's -- a player that floated like a droplet would be
## unplayable.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_speed := 8.0

@export_group("Mustard")
## What mustard does to a walk and a run, as a fraction of each.
##
## One scale for both rather than a flat subtraction: taking a fixed 3 m/s off
## leaves a walk crawling and barely touches a run, so the sauce meant to stop
## somebody closing on you would be worth least against the thing sprinting at
## you.
@export_range(0.05, 1.0, 0.01) var mustard_slow_scale := 0.55
## How long a hit keeps dragging. Long enough to matter after the shooter has
## moved on, short enough that a single splash is not a sentence.
@export_range(0.0, 10.0, 0.1, "suffix:s") var mustard_slow_seconds := 2.5
@export_range(1.0, 60.0, 0.5, "suffix:m/s²") var fall_gravity := 20.0

@export_group("Health")
@export_range(10.0, 1000.0, 1.0) var max_health := 100.0

@export_group("Being run into")
## The most a frame's worth of charges can throw a player, flat and upward.
## See `apply_enemy_impact`: the shoves add up, and a pack of rushers arriving
## together was launching people across the street.
@export_range(0.0, 40.0, 0.5, "suffix:m/s") var max_enemy_impact := 9.5
@export_range(0.0, 20.0, 0.5, "suffix:m/s") var max_enemy_lift := 3.0

@export_group("Slip and Fall")
## Catching your balance before you actually go over. Controls are already
## locked here; this is where an arm-flailing animation would go.
@export_range(0.05, 1.0, 0.01, "suffix:s") var stumble_duration := 0.18
## How many full side-to-side swings the stumble makes.
@export_range(0.5, 5.0, 0.25) var stumble_wobble_cycles := 1.5
@export_range(0.05, 3.0, 0.01, "suffix:s") var fall_duration := 0.18
## Beat spent flat on the floor between hitting it and pushing back up.
@export_range(0.0, 3.0, 0.01, "suffix:s") var down_duration := 0.5
@export_range(0.05, 3.0, 0.01, "suffix:s") var stand_up_duration := 0.5
## The supplied death clip is 48 frames at 24 fps. Keep the body in the world
## for that full performance before the authority respawns it.
@export_range(0.1, 5.0, 0.05, "suffix:s") var death_duration := 2.0
## How hard the slide scrubs off speed once the player goes down. The player
## keeps the speed they slipped at and carries it forward, so at run speed this
## is what sets how far they skid.
@export_range(1.0, 60.0, 0.5, "suffix:m/s²") var slip_slide_friction := 16.0
## Pitching forward puts the skid under the body instead of out from under it,
## so a long slide reads as a slide tackle. Scrubbed harder to land face first.
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var forward_slip_slide_friction := 34.0
## How long wiping the lenses takes. Firing is locked for it -- movement and
## aim are not -- so being blinded costs you the shot rather than the fight.
@export_range(0.1, 3.0, 0.05, "suffix:s") var wipe_duration := 0.7
## How long after standing up a fresh slip counts as losing footing you never
## had, and goes over forwards instead of backwards.
@export_range(0.0, 3.0, 0.05, "suffix:s") var recovery_window := 0.7

var health := 100.0
var recovery_protection := false
var damage_grace := 0.0
var slip_grace := 0.0
var predict_local := false
var prediction_sequence := 0
var server_input_sequence := 0
var _prediction_history: Array[Dictionary] = []
var _prediction_error := Vector3.ZERO
var _last_ack := -1
var _pending_reconciliation: Array = []
var _reconciling := false
var frame_movement := Vector3.ZERO
var cheese_snag_left := 0.0
## False on a client for every player including their own: the body is placed
## by the server. Aim stays local -- see MayoPrototype._read_local_input.
var authority := true
## Which player this body belongs to. The splat batch addresses a body by it.
var peer_id := 1
## The server plays a remote player's keys back through these. Offline and for
## the host's own body this stays false and the real keyboard is read.
var use_injected_input := false
## Set by the world when this death is one a teammate can undo -- the
## Tomatina rescue window. Elsewhere a dead player lies still.
var crawl_allowed := false
## Held still while the doctor is talking, and only ever for a beat.
##
## Read at the bottom of the input path rather than anywhere higher up: every
## source of movement -- the real keyboard, the injected keys the server plays a
## remote player back through, the checks' own overrides -- comes through the
## three accessors below, so one flag covers all of them and cannot be routed
## around. The body is not made invulnerable, immovable or unaimable by it: it is
## the *keys* that stop, so a shove still moves it and the fall still plays.
var frozen := false
var input_move := Vector2.ZERO
var input_run := false
## Counts down while a mustard hit is still dragging.
var mustard_slow := 0.0
## True while standing in mustard thick enough to drag, set from the floor by
## whoever is already asking the floor about this player. Kept as a flag rather
## than read here, because a body has no business knowing where the floor node
## is -- the slip test is arranged the same way.
var in_mustard := false
var input_jump := false
var state := State.NORMAL
## +1 goes over backwards, -1 pitches forward. Set when the slip starts and
## held until the player is back on their feet; the prototype mirrors the
## capsule and the camera by it.
var fall_direction := 1.0
var _state_timer := 0.0
var _recovery_timer := 0.0
var _network_previous_position := Vector3.ZERO
## Velocity handed over by something that ran into this player, applied on the
## next physics step and then cleared. Accumulated rather than assigned so two
## rushers arriving on the same frame both count.
var _pending_enemy_impact := Vector3.ZERO
var _charge_knockdown := false
var _charge_confusion_seconds := 0.0
var confusion_left := 0.0
## The top speed the ground allowed on the last frame the feet were on it: the
## most a jump may carry through the air. See `_physics_process`.
var _air_carry := 0.0
## Horizontal pressure on the body in m/s, added to the movement target.
## The host sends it with velocity so the guest predicts the same shove.
var external_drift := Vector3.ZERO
## The jump is taken on the press, not while the key is down, and the press is
## found here rather than with Input.is_action_just_pressed: a client's jump
## arrives as a held flag in a packet, and the server has to see the edge in it.
## The stain on this body. Set by the world when it builds the capsule; the
## strand finds it through here, because what a raycast hits is the body.
var contamination: BodyContamination
## The glasses on this body's face. The mask on them is what blinds the player
## looking through them, and what everyone else sees is filthy.
var visor: VisorContamination
## Counts down while the lenses are being wiped. Replicated like the fall timer,
## so the wipe plays out frame for frame on every screen.
var wipe_timer := 0.0


func _ready() -> void:
	process_physics_priority = -10
	add_to_group("mayo_contaminable")
	health = max_health


## Damage only ever lands on the authority; everyone else is told the result in
## the next state packet. Returns true when this was the hit that emptied the
## bar, so whoever dealt it can respond once rather than poll.
func take_damage(amount: float) -> bool:
	if health <= 0.0:
		return false
	if recovery_protection and damage_grace > 0.0:
		return false
	health = maxf(health - amount, 0.0)
	if recovery_protection and amount > 0.0:
		damage_grace = 0.65 if amount >= 18.0 else 0.18
	return health <= 0.0


func heal_to_full() -> void:
	health = max_health


func begin_death() -> void:
	state = State.DEAD
	_state_timer = 0.0
	velocity = Vector3.ZERO
	_pending_enemy_impact = Vector3.ZERO
	_charge_knockdown = false
	_charge_confusion_seconds = 0.0
	confusion_left = 0.0


## Back at the start, whole -- and, through `reset_state`, out of whatever they
## were in the middle of when they died.
func finish_respawn(at: Vector3) -> void:
	global_position = at
	reset_physics_interpolation()
	_render_snap_until = Engine.get_physics_frames() + 2
	velocity = Vector3.ZERO
	health = max_health
	reset_state()


## Back on their feet and out of whatever they were in the middle of.
##
## Health, sauce and the spawn point are the world's business, and the two
## contamination grids are nobody's: the sauce on a respawned player stays on
## them, and the glasses come clean only when the player wipes them. This is
## only the state machine, which the respawn used not to touch at all -- a player
## killed while flat on their back was put at the spawn point still on their
## back, and finished the fall they died in from there.
##
## Every field here is one that would otherwise be carried into the new life: the
## fall and its timer, the lean it is drawn with, the recovery window that makes
## the *next* slip pitch forward, a wipe still running, and the shove from
## whatever killed them, which is applied on the next physics step -- which is
## after this.
##
## Cancelling the wipe does *not* clean the lenses: it stops the action, and the
## mask is left exactly as it was for the player to wipe off again. The world has
## to drop its own mid-wipe note to match -- see `_damage_player`.

func reset_state() -> void:
	state = State.NORMAL
	_state_timer = 0.0
	fall_direction = 1.0
	_recovery_timer = 0.0
	wipe_timer = 0.0
	_pending_enemy_impact = Vector3.ZERO
	_charge_knockdown = false
	_charge_confusion_seconds = 0.0
	confusion_left = 0.0
	cheese_snag_left = 0.0
	if recovery_protection:
		slip_grace = 1.2
		damage_grace = 0.8


## How long the body has been in its current state, for the respawn timer.
func state_time() -> float:
	return _state_timer


func health_fraction() -> float:
	return clampf(health / maxf(max_health, 0.001), 0.0, 1.0)


## The strand marks a body the same way it marks a wall. Purely cosmetic: the
## grid here is never read back, and slipping is decided by the floor alone.
## Something charged into this player. Flat direction plus a little lift, so a
## rusher knocks them back and slightly up rather than grinding them along the
## floor.
##
## Authority only in practice: it is called from the enemy's contact step, which
## a client never runs, and the resulting position travels in the state packet.
## **Mustard drags, and being hit and standing in it are the same drag.**
##
## Deliberately not multiplied together. Both are mustard, and at the default
## scale two of them is 0.30 -- a player shot while crossing a puddle would be
## slower than a walk on a floor they cannot see the difference in, for a reason
## they have no way to read off the screen. The worse of the two wins instead,
## which is what a player can actually follow: mustard is on you, or it is not.
func mustard_factor() -> float:
	if recovery_protection and slip_grace > 0.0:
		return 1.0
	if mustard_slow > 0.0 or in_mustard:
		return mustard_slow_scale
	return 1.0


## A mustard hit landed. Authority only: the drag changes this body's velocity,
## and the position that comes out of it is what travels.
func splash_mustard() -> void:
	if recovery_protection and (state != State.NORMAL or slip_grace > 0.0):
		return
	mustard_slow = mustard_slow_seconds


func apply_enemy_impact(flat_direction: Vector3, push_speed: float,
		lift_speed: float) -> void:
	if recovery_protection and (state != State.NORMAL or slip_grace > 0.0 or damage_grace > 0.0):
		return
	if _charge_knockdown:
		return
	var direction := Vector3(flat_direction.x, 0.0, flat_direction.z)
	if direction.length_squared() < 0.000001:
		return
	_pending_enemy_impact += direction.normalized() * push_speed + Vector3.UP * lift_speed
	# **Capped, because it accumulates.** Several rushers reaching a player on
	# the same frame each add their own shove: six of them at 7.5 m/s is 45 m/s
	# of it, which does not knock a player back, it fires them off the map. The
	# cap keeps a crowd hitting harder than one of them without that.
	#
	# The two are capped apart. Flat and lift do different jobs -- one moves you,
	# the other takes your footing -- and a single cap on the length would let a
	# pile of lift eat the whole budget and leave the knock back with none.
	var flat := Vector3(_pending_enemy_impact.x, 0.0, _pending_enemy_impact.z)
	if flat.length() > max_enemy_impact:
		flat = flat.normalized() * max_enemy_impact
	_pending_enemy_impact = flat + Vector3.UP * minf(
		_pending_enemy_impact.y, max_enemy_lift)


func apply_charge_impact(direction: Vector3, push_speed: float, lift_speed: float,
		confusion_seconds := 0.0) -> void:
	if recovery_protection and (state != State.NORMAL or slip_grace > 0.0 or damage_grace > 0.0):
		return
	if state == State.DEAD or _charge_knockdown:
		return
	# Replace the current run momentum so the hit carries the player away
	# from the brute even when they were sprinting into it.
	velocity = Vector3.ZERO
	_pending_enemy_impact = direction * push_speed + Vector3.UP * lift_speed
	_charge_knockdown = true
	_charge_confusion_seconds = confusion_seconds
	fall_direction = 1.0
	state = State.FALLING
	_state_timer = 0.0


func paint_mayo(world_position: Vector3, world_normal: Vector3,
		kind := ContaminationGrid.KIND_MAYO, brush := ContaminationGrid.BRUSH_POOL) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal, kind, brush)


func paint_mayo_cell(cell: Vector2i, kind := ContaminationGrid.KIND_MAYO,
		brush := ContaminationGrid.BRUSH_POOL) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell, kind, brush)



func _physics_process(delta: float) -> void:
	# Where this tick starts from, for the predicted body's own interpolation --
	# see `render_position`. A correction below moves it with the body.
	_render_from = global_position
	if predict_local and not _pending_reconciliation.is_empty():
		var snapshot := _pending_reconciliation
		_pending_reconciliation = []
		_reconciling = true
		callv("apply_network_state", snapshot)
		_reconciling = false
	damage_grace = maxf(damage_grace - delta, 0.0)
	slip_grace = maxf(slip_grace - delta, 0.0)
	_trace_run_tick(delta)
	if not authority and not (predict_local and state == State.NORMAL):
		# The strand's inertial follow still needs to know how far the body
		# moved, and on a client that is whatever the last sync moved it by.
		frame_movement = global_position - _network_previous_position
		_network_previous_position = global_position
		_render_to = global_position
		_render_ready = true
		return
	if predict_local and not authority:
		prediction_sequence += 1
		_prediction_history.append({"sequence": prediction_sequence, "delta": delta,
			"move": movement_input(), "run": run_held(), "jump": jump_wanted(), "yaw": rotation.y})
		if _prediction_history.size() > 120:
			_prediction_history.pop_front()
	_simulate_movement(delta)
	_render_to = global_position
	_render_ready = true


func _simulate_movement(delta: float) -> void:
	confusion_left = maxf(confusion_left - delta, 0.0)
	if state != State.NORMAL:
		_advance_fall(delta)
	else:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
	mustard_slow = maxf(mustard_slow - delta, 0.0)
	cheese_snag_left = maxf(0.0, cheese_snag_left - delta)
	_advance_wipe(delta)

	var desired := Vector3.ZERO
	var crawling := is_crawling()
	if state == State.NORMAL or crawling:
		var input_vector := movement_input()
		# Movement is relative to where the player is facing, which the prototype
		# drives from the aim yaw.
		desired = global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
		desired.y = 0.0
		# **Running is something the feet do.** The boost is a harder push off the
		# ground, so there has to be ground: in the air the target drops to a walk.
		#
		# It drops to a walk without *braking* to one. The target keeps whatever
		# horizontal speed the body already carries, so a jump taken at a run
		# crosses the gap at a run and simply cannot gain any more -- scrubbing it
		# to walking pace in mid-air would make a running jump land shorter than
		# the run that set it up, which is the opposite of what a run is for.
		#
		# **What the air keeps is what the feet last gave it**, not whatever speed
		# the body happens to have. Keeping the body's own speed made a held jump
		# key a run with no run key: each landing is one frame on the ground, one
		# frame of braking takes 0.6 m/s off, and the next hop carried the rest --
		# seven seconds of running pace after Shift was let go. So the ground notes
		# the pace it allowed on every frame it is stood on, and a hop pushed off
		# at a walk is held to a walk however fast the body arrived.
		var grounded := is_on_floor()
		var top := run_speed if (run_held() and grounded) else walk_speed
		if crawling:
			top = walk_speed * crawl_speed_scale
		elif grounded:
			_air_carry = top
		else:
			top = maxf(top, minf(Vector2(velocity.x, velocity.z).length(), _air_carry))
		desired *= top
		desired *= mustard_factor()
		if confusion_left > 0.0:
			desired *= 0.75
		if cheese_snag_left > 0.0 and (not recovery_protection or slip_grace <= 0.0):
			desired *= 0.40
		if state == State.NORMAL:
			desired += Vector3(external_drift.x, 0.0, external_drift.z)

	# Going down keeps whatever speed the player slipped at and scrubs it off,
	# so they skid forward instead of stopping dead where they tripped.
	var rate := acceleration
	if state != State.NORMAL and not crawling:
		rate = forward_slip_slide_friction if fall_direction < 0.0 else slip_slide_friction
		if _charge_knockdown and not is_on_floor():
			rate = 0.0 if _charge_confusion_seconds > 0.0 else slip_slide_friction * 0.5
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)

	if is_on_floor():
		velocity.y = 0.0
		# **Held, not pressed.** The key being down on a frame where the feet are
		# on the ground is a jump, so holding it hops again the moment a landing
		# touches down rather than waiting for the player to let go and press
		# again -- a gap taken as a run of jumps is one held key, not a drum solo.
		#
		# Still only while upright: going over backwards is not a jump, it is a
		# fall, and a held key must not cancel one.
		if jump_wanted() and state == State.NORMAL:
			velocity.y = jump_speed
	else:
		velocity.y -= fall_gravity * delta
	if _pending_enemy_impact.length_squared() > 0.0:
		velocity += _pending_enemy_impact
		_pending_enemy_impact = Vector3.ZERO

	var before := global_position
	move_and_slide()
	frame_movement = global_position - before


## True while the run key is held and a direction is actually pressed. Standing
## still with the key down is not running, so it cannot trip you.
func is_running() -> bool:
	if state != State.NORMAL or not run_held():
		return false
	return movement_input().length_squared() > 0.0


## The movement keys this body is being driven by: the real keyboard for the
## local player, the last packet for a player the server is simulating.
func movement_input() -> Vector2:
	if frozen:
		return Vector2.ZERO
	if use_injected_input:
		return input_move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func run_held() -> bool:
	if frozen:
		return false
	if use_injected_input:
		return input_run
	return run_key_down()


## The run key. Now and again the run stayed on with the key up until it was
## pressed and let go again: the key had come up and the action had not heard.
## The engine keeps the raw key and the action in separate books, so the key
## coming up is told to the action directly -- see `_input` -- and a release
## the action missed no longer leaves the player running.
##
## The run still sticks now and again (2026-11), so the action is also checked
## against the raw key book on every read: an action that says "held" while the
## key it is bound to is up is released on the spot, and the moment is written
## to `RUN_TRACE_PATH` -- see `trace_run`.
static func run_key_down() -> bool:
	if not Input.is_action_pressed("run"):
		return false
	# Only once a real key has been seen: the headless checks hold the action
	# down through the API with no key behind it at all.
	var key := _run_physical_key()
	if _run_key_seen and key != KEY_NONE and not Input.is_physical_key_pressed(key):
		trace_run("action 'run' held while its key %s is up -- released" % OS.get_keycode_string(key))
		Input.action_release("run")
		return false
	return true


static func _run_physical_key() -> Key:
	for event in InputMap.action_get_events("run"):
		var key := event as InputEventKey
		if key != null and key.physical_keycode != KEY_NONE:
			return key.physical_keycode
	return KEY_NONE


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo or not InputMap.event_is_action(key, "run"):
		return
	_run_key_seen = true
	_run_events.append("%d %s" % [Time.get_ticks_msec(), "down" if key.pressed else "up"])
	if _run_events.size() > 8:
		_run_events.pop_front()
	if not key.pressed and Input.is_action_pressed("run"):
		trace_run("run key came up with the action still held -- released")
		Input.action_release("run")


# --- run diagnostics -----------------------------------------------------------
#
# Where a stuck run is written down, with what the body, the keys and the
# network looked like at that moment. On Windows `user://` is
# %APPDATA%/Godot/app_userdata/Sauce IT!/.
const RUN_TRACE_PATH := "user://run_trace.log"
static var _run_trace_lines := 0
## Whether a real run key has been pressed this session -- see `run_key_down`.
static var _run_key_seen := false
## The last few presses and releases of the run key this body heard.
var _run_events: Array[String] = []
## How long the body has been moving faster than a walk with the run key up.
var _running_unheld := 0.0
var _run_trace_reported := false
var _run_trace_correction_ms := 0


static func trace_run(message: String) -> void:
	# A runaway loop must not fill the disk: a few hundred lines a session is
	# plenty to see what happened.
	if _run_trace_lines >= 400:
		return
	_run_trace_lines += 1
	var line := "[%s %d] %s" % [Time.get_datetime_string_from_system(), Time.get_ticks_msec(), message]
	print("RUN_TRACE ", line)
	var file := FileAccess.open(RUN_TRACE_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RUN_TRACE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)


## Once a tick, for the body the keyboard drives: notes it moving at a run with
## the run key up for longer than a landing's braking takes, and -- for a
## predicted client -- the server pulling it a long way, which is what a host
## still running this player on an old packet would look like.
func _trace_run_tick(delta: float) -> void:
	if use_injected_input or frozen:
		return
	var key_down := run_key_down()
	var speed := Vector2(velocity.x, velocity.z).length()
	if state == State.NORMAL and is_on_floor() and not key_down and external_drift.is_zero_approx() \
			and speed > walk_speed * 1.15:
		_running_unheld += delta
	else:
		_running_unheld = 0.0
		_run_trace_reported = false
	if _running_unheld > 0.4 and not _run_trace_reported:
		_run_trace_reported = true
		var key := _run_physical_key()
		trace_run("running %.1f m/s with the run key up for %.2f s | authority=%s predict=%s action=%s raw=%s focus=%s mustard=%.2f snag=%.2f | keys: %s" % [
			speed, _running_unheld, authority, predict_local, Input.is_action_pressed("run"),
			Input.is_physical_key_pressed(key) if key != KEY_NONE else false,
			DisplayServer.window_is_focused(), mustard_slow, cheese_snag_left, ", ".join(_run_events)])
	if predict_local and not authority and _prediction_error.length() > 0.6:
		var now := Time.get_ticks_msec()
		if now - _run_trace_correction_ms > 1000:
			_run_trace_correction_ms = now
			trace_run("server corrected this body by %.2f m | run key=%s speed=%.1f" % [
				_prediction_error.length(), key_down, speed])


func jump_wanted() -> bool:
	if frozen:
		return false
	if use_injected_input:
		return input_jump
	return Input.is_action_pressed("jump")


## Starts a wipe, if there is anything to wipe and the player is in a state to
## do it. Going over backwards is not the moment to clean your glasses.
func begin_wipe() -> bool:
	if wipe_timer > 0.0 or state != State.NORMAL:
		return false
	if visor == null or visor.painted_cell_count() == 0:
		return false
	wipe_timer = wipe_duration
	return true


func is_wiping() -> bool:
	return wipe_timer > 0.0


## 0 -> 1 across the wipe, for the lenses tipping up and back down.
func wipe_progress() -> float:
	if wipe_timer <= 0.0:
		return 0.0
	return 1.0 - clampf(wipe_timer / maxf(wipe_duration, 0.0001), 0.0, 1.0)


## Only the authority runs the clock down; everyone else is handed the value.
## The lenses are not cleared here -- that is a change to a grid, and grids are
## only ever changed by the server telling everyone the same thing.
func _advance_wipe(delta: float) -> void:
	if wipe_timer <= 0.0:
		return
	wipe_timer = maxf(wipe_timer - delta, 0.0)


## Whole-body state from the server. The fall is not re-simulated here: the
## timer comes over the wire too, so the stumble, the fall, the slide and
## standing up line up frame for frame on both machines.
func apply_network_state(new_position: Vector3, yaw: float, new_velocity: Vector3,
		new_state: int, timer: float, direction: float, wipe: float,
		new_health: float, acknowledged := -1, slow := 0.0, snag := 0.0, field_slow := false,
		charge_effect := 0.0, new_drift := Vector3.ZERO) -> void:
	# move_and_slide uses the engine's current step. Replaying inside an RPC
	# callback would use a variable render delta instead of the fixed physics tick.
	if predict_local and acknowledged >= 0 and not _reconciling:
		_pending_reconciliation = [new_position, yaw, new_velocity, new_state, timer,
			direction, wipe, new_health, acknowledged, slow, snag, field_slow, charge_effect, new_drift]
		return
	if predict_local and acknowledged >= 0 and acknowledged < _last_ack:
		return
	external_drift = new_drift
	_charge_confusion_seconds = maxf(-charge_effect, 0.0)
	confusion_left = maxf(charge_effect, 0.0)
	if predict_local and acknowledged >= 0:
		_last_ack = acknowledged
		var rendered := global_position + _prediction_error
		var predicted := global_position
		var old_yaw := rotation.y
		var was_dead := state == State.DEAD
		global_position = new_position
		velocity = new_velocity
		state = new_state as State
		_state_timer = timer
		fall_direction = direction
		wipe_timer = wipe
		health = new_health
		mustard_slow = slow
		cheese_snag_left = snag
		in_mustard = field_slow
		_prediction_history = _prediction_history.filter(func(entry): return entry.sequence > acknowledged)
		if state == State.NORMAL and not was_dead and rendered.distance_to(new_position) < 8.0:
			var injected := use_injected_input
			var saved_move := input_move
			var saved_run := input_run
			var saved_jump := input_jump
			use_injected_input = true
			for entry in _prediction_history:
				input_move = entry.move
				input_run = entry.run
				input_jump = entry.jump
				rotation.y = entry.yaw
				_simulate_movement(entry.delta)
			use_injected_input = injected
			input_move = saved_move
			input_run = saved_run
			input_jump = saved_jump
			_prediction_error = (rendered - global_position).limit_length(1.5)
			# The interpolation start moves with the correction, so the view
			# carries on from where it was drawn and the error alone is what
			# eases the difference out -- see `render_position`.
			_render_from += global_position - predicted
		else:
			_prediction_history.clear()
			_prediction_error = Vector3.ZERO
			# A respawn or a long way out: snap, rather than sweep across.
			_render_from = global_position
			_render_to = global_position
		rotation.y = old_yaw
		return
	global_position = new_position
	rotation.y = yaw
	velocity = new_velocity
	state = new_state as State
	_state_timer = timer
	fall_direction = direction
	wipe_timer = wipe
	health = new_health


## What the server sends: enough to place the body and to replay the fall, and
## the health, which the server owns outright -- a client that decided its own
## would disagree with the bar everyone else is watching.
func network_state() -> Array:
	return [global_position, rotation.y, velocity, int(state), _state_timer,
		fall_direction, wipe_timer, health]


## Negative during the launch, positive while the confusion is active.
func charge_effect_state() -> float:
	return -_charge_confusion_seconds if _charge_confusion_seconds > 0.0 else confusion_left


func is_incapacitated() -> bool:
	return state != State.NORMAL


## Down, waiting for a rescue, and past the death clip: the keys move the
## body at `crawl_speed_scale` of a walk. Still incapacitated -- no firing,
## no jump, no run, and enemies pay it no attention.
func is_crawling() -> bool:
	return state == State.DEAD and crawl_allowed and _state_timer >= death_duration


## No grace period after standing up. Slipping already needs the run key and a
## direction held, so a player who keeps sprinting across mayo goes straight
## back down, which is the point. Being in the air is the one reprieve: mayo
## underneath you is not underfoot.
func can_slip() -> bool:
	return state == State.NORMAL and is_on_floor() and (not recovery_protection or slip_grace <= 0.0)


## Slipping starts with a stumble, not the fall itself -- unless the player is
## still recovering from the last one. Sprinting the instant you are upright
## means your feet never take the weight, so you go straight over backward with
## no balance to catch: the stumble is skipped and the fall starts immediately.
func begin_slip() -> void:
	if state != State.NORMAL:
		return
	if recovery_protection and slip_grace > 0.0:
		return
	if _recovery_timer > 0.0:
		fall_direction = 1.0
		state = State.FALLING
	else:
		fall_direction = -1.0
		state = State.STUMBLE
	_state_timer = 0.0


## -1..1 side-to-side sway while catching your balance, 0 at any other time.
## Starts and ends at zero so it blends into the fall.
func stumble_wobble() -> float:
	if state != State.STUMBLE:
		return 0.0
	return sin(_state_timer / maxf(stumble_duration, 0.0001) * TAU * stumble_wobble_cycles)


## 0 upright, 1 flat on the floor. Drives both the capsule and the camera.
func fall_tilt() -> float:
	match state:
		State.STUMBLE:
			return 0.0
		State.FALLING:
			if _charge_confusion_seconds > 0.0:
				return 0.3 * clampf(_state_timer / fall_duration, 0.0, 1.0)
			return clampf(_state_timer / maxf(fall_duration, 0.0001), 0.0, 1.0)
		State.DOWN:
			if confusion_left > 0.0:
				return lerpf(0.3, 1.0, clampf(_state_timer / 0.16, 0.0, 1.0))
			return 1.0
		State.STANDING_UP:
			return 1.0 - clampf(_state_timer / maxf(stand_up_duration, 0.0001), 0.0, 1.0)
		State.DEAD:
			return 0.0
		_:
			return 0.0


func _advance_fall(delta: float) -> void:
	_state_timer += delta
	if state == State.DEAD:
		return
	if state == State.STUMBLE and _state_timer >= stumble_duration:
		state = State.FALLING
		_state_timer = 0.0
	elif state == State.FALLING and _state_timer >= fall_duration \
			and (not _charge_knockdown or (is_on_floor() and _pending_enemy_impact.is_zero_approx())):
		_charge_knockdown = false
		if _charge_confusion_seconds > 0.0:
			confusion_left = _charge_confusion_seconds
			_charge_confusion_seconds = 0.0
		state = State.DOWN
		_state_timer = 0.0
	elif state == State.DOWN and _state_timer >= down_duration:
		state = State.STANDING_UP
		_state_timer = 0.0
	elif state == State.STANDING_UP and _state_timer >= stand_up_duration:
		state = State.NORMAL
		_state_timer = 0.0
		fall_direction = 1.0
		_recovery_timer = recovery_window
		if recovery_protection:
			slip_grace = 1.2
			mustard_slow = minf(mustard_slow, 0.5)
			cheese_snag_left = 0.0


var _render_snap_until := 0
## The predicted body's own interpolation: where the last physics tick started
## and ended. The engine's interpolation cannot be used for it -- a correction
## teleports the body back to the server's position and replays inside one
## tick, so the engine's "previous" is in the uncorrected frame -- so the body
## keeps its own pair, and a correction shifts both by what it moved.
var _render_from := Vector3.ZERO
var _render_to := Vector3.ZERO
## False until a physics tick has filled the pair in.
var _render_ready := false
## The process frame the prediction error was last eased on. `render_position`
## is asked several times a frame (camera, viewmodel, nozzle); easing on each
## call made the error vanish at a rate that depended on how many asked.
var _error_eased_frame := -1
## How fast a correction is eased out, per second: about 0.06 s to halve.
const PREDICTION_EASE_RATE := 12.0

## Where to draw the body this frame. The camera follows this, so it has to move
## at the rendered frame rate: the physics position alone steps at 60 Hz, which
## on a faster screen -- or a 60 Hz one whose frames and ticks drift apart --
## reads as the view juddering whenever the player moves.
func render_position() -> Vector3:
	if predict_local and not authority and _render_ready:
		var frame := Engine.get_process_frames()
		if frame != _error_eased_frame:
			_error_eased_frame = frame
			_prediction_error *= exp(-PREDICTION_EASE_RATE * get_process_delta_time())
			if _prediction_error.length_squared() < 0.000001:
				_prediction_error = Vector3.ZERO
		var drawn := _render_from.lerp(_render_to, Engine.get_physics_interpolation_fraction())
		# Anything this far apart is a teleport the snap branch did not see.
		if _render_from.distance_squared_to(_render_to) > 9.0:
			drawn = _render_to
		return drawn + _prediction_error
	if Engine.get_physics_frames() <= _render_snap_until:
		return global_position
	var rendered := get_global_transform_interpolated().origin
	# Teleports outside the normal respawn path also snap instead of sweeping.
	if rendered.distance_squared_to(global_position) > 1.0:
		reset_physics_interpolation()
		_render_snap_until = Engine.get_physics_frames() + 2
		return global_position
	return rendered
