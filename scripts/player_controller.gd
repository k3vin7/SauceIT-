class_name MayoPlayer
extends CharacterBody3D

## Walk/run movement plus the slip-and-fall state machine. Falling and standing
## up lock out movement and firing; the prototype reads `is_incapacitated()`.
##
## In a session the server owns every player: it runs this simulation for both,
## reading the remote player's keys out of `input_move`/`input_run` instead of
## the local keyboard, and the clients' copies are set from the network with
## `apply_network_state` rather than simulated.

enum State { NORMAL, STUMBLE, FALLING, DOWN, STANDING_UP }

## Shared by player construction and imported character presentation so every
## variant remains aligned with the established gameplay body.
const CAPSULE_RADIUS := 0.64
const CAPSULE_HEIGHT := 2.56

@export_group("Movement")
@export_range(0.5, 24.0, 0.1, "suffix:m/s") var walk_speed := 5.2
@export_range(0.5, 28.0, 0.1, "suffix:m/s") var run_speed := 10.4
## Doubled with the speeds, so getting up to them still takes the time it did:
## left alone, twice the top speed would take twice as long to reach and the
## player would feel heavier rather than faster.
@export_range(1.0, 80.0, 0.5) var acceleration := 36.0
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
var frame_movement := Vector3.ZERO
## False on a client for every player including their own: the body is placed
## by the server. Aim stays local -- see MayoPrototype._read_local_input.
var authority := true
## Which player this body belongs to. The splat batch addresses a body by it.
var peer_id := 1
## The server plays a remote player's keys back through these. Offline and for
## the host's own body this stays false and the real keyboard is read.
var use_injected_input := false
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
	health = maxf(health - amount, 0.0)
	return health <= 0.0


func heal_to_full() -> void:
	health = max_health


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
	if mustard_slow > 0.0 or in_mustard:
		return mustard_slow_scale
	return 1.0


## A mustard hit landed. Authority only: the drag changes this body's velocity,
## and the position that comes out of it is what travels.
func splash_mustard() -> void:
	mustard_slow = mustard_slow_seconds


func apply_enemy_impact(flat_direction: Vector3, push_speed: float,
		lift_speed: float) -> void:
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


func paint_mayo(world_position: Vector3, world_normal: Vector3,
		kind := ContaminationGrid.KIND_MAYO) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal, kind)


func paint_mayo_cell(cell: Vector2i, kind := ContaminationGrid.KIND_MAYO) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell, kind)



func _physics_process(delta: float) -> void:
	if not authority:
		# The strand's inertial follow still needs to know how far the body
		# moved, and on a client that is whatever the last sync moved it by.
		frame_movement = global_position - _network_previous_position
		_network_previous_position = global_position
		return
	if state != State.NORMAL:
		_advance_fall(delta)
	else:
		_recovery_timer = maxf(_recovery_timer - delta, 0.0)
	mustard_slow = maxf(mustard_slow - delta, 0.0)
	_advance_wipe(delta)

	var desired := Vector3.ZERO
	if state == State.NORMAL:
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
		var top := run_speed if (run_held() and is_on_floor()) else walk_speed
		if not is_on_floor():
			top = maxf(top, Vector2(velocity.x, velocity.z).length())
		desired *= top
		desired *= mustard_factor()

	# Going down keeps whatever speed the player slipped at and scrubs it off,
	# so they skid forward instead of stopping dead where they tripped.
	var rate := acceleration
	if state != State.NORMAL:
		rate = forward_slip_slide_friction if fall_direction < 0.0 else slip_slide_friction
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
	return Input.is_action_pressed("run")


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
		new_health: float) -> void:
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


func is_incapacitated() -> bool:
	return state != State.NORMAL


## No grace period after standing up. Slipping already needs the run key and a
## direction held, so a player who keeps sprinting across mayo goes straight
## back down, which is the point. Being in the air is the one reprieve: mayo
## underneath you is not underfoot.
func can_slip() -> bool:
	return state == State.NORMAL and is_on_floor()


## Slipping starts with a stumble, not the fall itself -- unless the player is
## still recovering from the last one. Sprinting the instant you are upright
## means your feet never take the weight, so you go straight over backward with
## no balance to catch: the stumble is skipped and the fall starts immediately.
func begin_slip() -> void:
	if state != State.NORMAL:
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
			return clampf(_state_timer / maxf(fall_duration, 0.0001), 0.0, 1.0)
		State.DOWN:
			return 1.0
		State.STANDING_UP:
			return 1.0 - clampf(_state_timer / maxf(stand_up_duration, 0.0001), 0.0, 1.0)
		_:
			return 0.0


func _advance_fall(delta: float) -> void:
	_state_timer += delta
	if state == State.STUMBLE and _state_timer >= stumble_duration:
		state = State.FALLING
		_state_timer = 0.0
	elif state == State.FALLING and _state_timer >= fall_duration:
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
