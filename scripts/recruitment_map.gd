class_name RecruitmentMap
extends Node3D

signal screen_interacted
signal pause_requested

const PLAYER_HEIGHT := 2.56
const PLAYER_RADIUS := 0.64
const SCREEN_POSITION := Vector3(0.0, 2.35, -8.65)
const INTERACT_DISTANCE := 4.2
const LOOK_DOT := 0.88

var mouse_sensitivity := 0.09
var input_locked := false
var _player: CharacterBody3D
var _pivot: Node3D
var _camera: Camera3D
var _prompt: Label
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_ensure_actions()
	_build_room()
	_build_player()
	_build_hud()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if not _player.is_on_floor():
		_player.velocity.y -= 20.0 * delta
	var input := Vector2.ZERO if input_locked else Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward")
	var forward := -Basis(Vector3.UP, _yaw).z
	var right := Basis(Vector3.UP, _yaw).x
	var wish := (right * input.x + forward * -input.y).normalized()
	var speed := 5.2
	_player.velocity.x = move_toward(_player.velocity.x, wish.x * speed, 28.0 * delta)
	_player.velocity.z = move_toward(_player.velocity.z, wish.z * speed, 28.0 * delta)
	if not input_locked and Input.is_action_just_pressed("jump") and _player.is_on_floor():
		_player.velocity.y = 8.0
	_player.move_and_slide()
	var available := _can_use_screen()
	_prompt.visible = available and not input_locked
	if available and not input_locked and Input.is_action_just_pressed("interact"):
		screen_interacted.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw = wrapf(_yaw - deg_to_rad(mouse_sensitivity) * motion.relative.x, -PI, PI)
		_pitch = clampf(_pitch - deg_to_rad(mouse_sensitivity) * motion.relative.y,
			deg_to_rad(-80.0), deg_to_rad(80.0))
		_player.rotation.y = _yaw
		_pivot.rotation.x = _pitch


func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked and _player != null:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if locked else Input.MOUSE_MODE_CAPTURED


func can_use_screen() -> bool:
	return _can_use_screen()


func _can_use_screen() -> bool:
	if _camera == null:
		return false
	var to_screen := SCREEN_POSITION - _camera.global_position
	if to_screen.length() > INTERACT_DISTANCE:
		return false
	return (-_camera.global_basis.z).dot(to_screen.normalized()) >= LOOK_DOT


func _build_room() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("101720")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b9c6d2")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)
	_box("Floor", Vector3(0.0, -0.2, 0.0), Vector3(18.0, 0.4, 20.0), Color("394149"), true)
	_box("Ceiling", Vector3(0.0, 5.2, 0.0), Vector3(18.0, 0.25, 20.0), Color("242b31"), false)
	_box("LeftWall", Vector3(-9.0, 2.5, 0.0), Vector3(0.35, 5.0, 20.0), Color("59636c"), true)
	_box("RightWall", Vector3(9.0, 2.5, 0.0), Vector3(0.35, 5.0, 20.0), Color("59636c"), true)
	_box("BackWall", Vector3(0.0, 2.5, -10.0), Vector3(18.0, 5.0, 0.35), Color("4b555e"), true)
	_box("FrontWall", Vector3(0.0, 2.5, 10.0), Vector3(18.0, 5.0, 0.35), Color("4b555e"), true)
	_box("DeskA", Vector3(-5.8, 0.75, 0.0), Vector3(3.8, 1.5, 1.8), Color("76573e"), true)
	_box("DeskB", Vector3(5.8, 0.75, 1.0), Vector3(3.8, 1.5, 1.8), Color("76573e"), true)
	_box("ScreenFrame", Vector3(0.0, 2.6, -9.72), Vector3(8.5, 4.1, 0.22), Color("15191d"), false)
	var screen := _box("RecruitmentScreen", SCREEN_POSITION, Vector3(7.8, 3.4, 0.12),
		Color("247b9b"), false)
	var label := Label3D.new()
	label.text = "SAUCE IT!\nCREW TERMINAL"
	label.font_size = 72
	label.pixel_size = 0.012
	label.modulate = Color("d9f7ff")
	label.position = Vector3(0.0, 0.0, 0.08)
	screen.add_child(label)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "OfficePlayer"
	_player.position = Vector3(0.0, PLAYER_HEIGHT * 0.5, 5.5)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	collision.shape = capsule
	_player.add_child(collision)
	add_child(_player)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 0.62, 0.0)
	_player.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.near = 0.05
	_pivot.add_child(_camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_prompt = Label.new()
	_prompt.text = "[ E ] 큰 스크린 사용"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-160.0, -105.0)
	_prompt.size = Vector2(320.0, 40.0)
	_prompt.visible = false
	layer.add_child(_prompt)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 24)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8.0, -16.0)
	layer.add_child(cross)


func _box(node_name: String, at: Vector3, size: Vector3, color: Color,
		collides: bool) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	add_child(holder)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	holder.add_child(mesh)
	if collides:
		var body := StaticBody3D.new()
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.add_child(shape_node)
		holder.add_child(body)
	return holder


func _ensure_actions() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("interact", key)
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var jump_key := InputEventKey.new()
		jump_key.physical_keycode = KEY_SPACE
		InputMap.action_add_event("jump", jump_key)
