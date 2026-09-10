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

@export_group("Movement")
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var walk_speed := 2.6
@export_range(0.5, 14.0, 0.1, "suffix:m/s") var run_speed := 5.2
@export_range(1.0, 40.0, 0.5) var acceleration := 18.0

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
## How long after standing up a fresh slip counts as losing footing you never
## had, and goes over forwards instead of backwards.
@export_range(0.0, 3.0, 0.05, "suffix:s") var recovery_window := 0.7

var frame_movement := Vector3.ZERO
## False on a client for every player including their own: the body is placed
## by the server. Aim stays local -- see MayoPrototype._read_local_input.
var authority := true
## Which player this body belongs to. The splat batch addresses a body by it.
var peer_id := 1
## The server plays a remote player's keys back through these. Offline and for
## the host's own body this stays false and the real keyboard is read.
var use_injected_input := false
var input_move := Vector2.ZERO
var input_run := false
var state := State.NORMAL
## +1 goes over backwards, -1 pitches forward. Set when the slip starts and
## held until the player is back on their feet; the prototype mirrors the
## capsule and the camera by it.
var fall_direction := 1.0
var _state_timer := 0.0
var _recovery_timer := 0.0
var _network_previous_position := Vector3.ZERO
## The stain on this body. Set by the world when it builds the capsule; the
## strand finds it through here, because what a raycast hits is the body.
var contamination: BodyContamination


func _ready() -> void:
	process_physics_priority = -10
	add_to_group("mayo_contaminable")


## The strand marks a body the same way it marks a wall. Purely cosmetic: the
## grid here is never read back, and slipping is decided by the floor alone.
func paint_mayo(world_position: Vector3, world_normal: Vector3) -> Vector2i:
	if contamination == null:
		return Vector2i(-1, -1)
	return contamination.paint_mayo(world_position, world_normal)


func paint_mayo_cell(cell: Vector2i) -> void:
	if contamination != null:
		contamination.paint_mayo_cell(cell)


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

	var desired := Vector3.ZERO
	if state == State.NORMAL:
		var input_vector := movement_input()
		# Movement is relative to where the player is facing, which the prototype
		# drives from the aim yaw.
		desired = global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
		desired.y = 0.0
		desired *= run_speed if run_held() else walk_speed

	# Going down keeps whatever speed the player slipped at and scrubs it off,
	# so they skid forward instead of stopping dead where they tripped.
	var rate := acceleration
	if state != State.NORMAL:
		rate = forward_slip_slide_friction if fall_direction < 0.0 else slip_slide_friction
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	velocity.y = 0.0
	var before := global_position
	move_and_slide()
	global_position.y = before.y
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
	if use_injected_input:
		return input_move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func run_held() -> bool:
	if use_injected_input:
		return input_run
	return Input.is_action_pressed("run")


## Whole-body state from the server. The fall is not re-simulated here: the
## timer comes over the wire too, so the stumble, the fall, the slide and
## standing up line up frame for frame on both machines.
func apply_network_state(new_position: Vector3, yaw: float, new_velocity: Vector3,
		new_state: int, timer: float, direction: float) -> void:
	global_position = new_position
	rotation.y = yaw
	velocity = new_velocity
	state = new_state as State
	_state_timer = timer
	fall_direction = direction


## What the server sends: enough to place the body and to replay the fall.
func network_state() -> Array:
	return [global_position, rotation.y, velocity, int(state), _state_timer, fall_direction]


func is_incapacitated() -> bool:
	return state != State.NORMAL


## No grace period after standing up. Slipping already needs the run key and a
## direction held, so a player who keeps sprinting across mayo goes straight
## back down, which is the point.
func can_slip() -> bool:
	return state == State.NORMAL


## Slipping starts with a stumble, not the fall itself -- unless the player is
## still recovering from the last one. Sprinting the instant you are upright
## means your feet never take the weight, so you pitch straight forward with no
## balance to catch: the stumble is skipped and the fall starts immediately.
func begin_slip() -> void:
	if state != State.NORMAL:
		return
	if _recovery_timer > 0.0:
		fall_direction = -1.0
		state = State.FALLING
	else:
		fall_direction = 1.0
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
