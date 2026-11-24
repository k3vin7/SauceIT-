extends Node3D

## 사무실 배치 씬(`maps/command.tscn`)을 에디터에서 "현재 씬 재생"으로 띄웠을 때만
## 걸어 다닐 몸을 하나 만들어 준다. 다른 씬 안에 넣어 쓰일 때는 아무것도 하지 않으므로
## 실제 게임 흐름과는 무관하다.
##
## WASD 이동 · Shift 달리기 · Space 점프 · 마우스 시점 · Esc 커서 풀기/잡기

const WALK_SPEED := 5.2
const RUN_SPEED := 9.0
const JUMP_SPEED := 5.0
const GRAVITY := 14.0
const EYE_HEIGHT := 1.6
const MOUSE_SENSITIVITY := 0.12

var _body: CharacterBody3D
var _camera: Camera3D
var _pitch := 0.0


func _ready() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	if get_tree().current_scene != self:
		return
	_spawn_walker()
	set_physics_process(true)
	set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_walker() -> void:
	_body = CharacterBody3D.new()
	_body.name = "TestWalker"
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	_body.add_child(shape_node)
	_camera = Camera3D.new()
	_camera.position.y = EYE_HEIGHT
	_camera.fov = 80.0
	_body.add_child(_camera)
	add_child(_body)
	var spawn := get_node_or_null("Spawns/Spawn1") as Node3D
	if spawn != null:
		_body.global_position = spawn.global_position
		_body.rotation.y = spawn.global_rotation.y
	_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_body.rotation.y -= deg_to_rad(MOUSE_SENSITIVITY) * motion.relative.x
		_pitch = clampf(_pitch - deg_to_rad(MOUSE_SENSITIVITY) * motion.relative.y,
			deg_to_rad(-85.0), deg_to_rad(85.0))
		_camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var direction := _body.global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	direction = direction.limit_length(1.0)
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	_body.velocity.x = direction.x * speed
	_body.velocity.z = direction.z * speed
	if _body.is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			_body.velocity.y = JUMP_SPEED
	else:
		_body.velocity.y -= GRAVITY * delta
	_body.move_and_slide()
