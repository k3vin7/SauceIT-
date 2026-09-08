class_name MayoPlayer
extends CharacterBody3D

@export_range(0.5, 12.0, 0.1, "suffix:m/s") var move_speed := 3.8
@export_range(1.0, 40.0, 0.5) var acceleration := 18.0

var frame_movement := Vector3.ZERO


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var desired := Vector3(input_vector.x, 0.0, input_vector.y) * move_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	velocity.y = 0.0
	var before := global_position
	move_and_slide()
	global_position.y = before.y
	frame_movement = global_position - before
