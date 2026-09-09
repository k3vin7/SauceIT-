class_name MayoPlayer
extends CharacterBody3D

## Walk/run movement plus the slip-and-fall state machine. Falling and standing
## up lock out movement and firing; the prototype reads `is_incapacitated()`.

enum State { NORMAL, FALLING, DOWN, STANDING_UP }

@export_group("Movement")
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var walk_speed := 2.6
@export_range(0.5, 14.0, 0.1, "suffix:m/s") var run_speed := 5.2
@export_range(1.0, 40.0, 0.5) var acceleration := 18.0

@export_group("Slip and Fall")
@export_range(0.05, 3.0, 0.05, "suffix:s") var fall_duration := 0.5
## Beat spent flat on the floor between hitting it and pushing back up.
@export_range(0.0, 3.0, 0.05, "suffix:s") var down_duration := 0.5
@export_range(0.05, 3.0, 0.05, "suffix:s") var stand_up_duration := 0.5
## Grace period after standing up, so the same patch cannot trip you again the
## instant you are back on your feet.
@export_range(0.0, 5.0, 0.05, "suffix:s") var slip_immunity_time := 0.8

var frame_movement := Vector3.ZERO
var state := State.NORMAL
var _state_timer := 0.0
var _immunity_timer := 0.0


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	_immunity_timer = maxf(_immunity_timer - delta, 0.0)
	if state != State.NORMAL:
		_advance_fall(delta)

	var desired := Vector3.ZERO
	if state == State.NORMAL:
		var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		# Movement is relative to where the player is facing, which the prototype
		# drives from the aim yaw.
		desired = global_basis * Vector3(input_vector.x, 0.0, input_vector.y)
		desired.y = 0.0
		desired *= run_speed if Input.is_action_pressed("run") else walk_speed

	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	velocity.y = 0.0
	var before := global_position
	move_and_slide()
	global_position.y = before.y
	frame_movement = global_position - before


## True while the run key is held and a direction is actually pressed. Standing
## still with the key down is not running, so it cannot trip you.
func is_running() -> bool:
	if state != State.NORMAL or not Input.is_action_pressed("run"):
		return false
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward").length_squared() > 0.0


func is_incapacitated() -> bool:
	return state != State.NORMAL


func can_slip() -> bool:
	return state == State.NORMAL and _immunity_timer <= 0.0


func begin_fall() -> void:
	if state != State.NORMAL:
		return
	state = State.FALLING
	_state_timer = 0.0
	velocity = Vector3.ZERO


## 0 upright, 1 flat on the floor. Drives both the capsule and the camera.
func fall_tilt() -> float:
	match state:
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
	if state == State.FALLING and _state_timer >= fall_duration:
		state = State.DOWN
		_state_timer = 0.0
	elif state == State.DOWN and _state_timer >= down_duration:
		state = State.STANDING_UP
		_state_timer = 0.0
	elif state == State.STANDING_UP and _state_timer >= stand_up_duration:
		state = State.NORMAL
		_state_timer = 0.0
		_immunity_timer = slip_immunity_time
