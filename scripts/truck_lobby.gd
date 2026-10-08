class_name TruckLobby
extends Node3D

signal start_requested
signal leave_requested

const CHARACTER_SCENES: Array[PackedScene] = [
	preload("res://assets/players/Character_1/Character_1.glb"),
	preload("res://assets/players/Character_2/Character_2.glb"),
	preload("res://assets/players/Character_3/Character_3.glb"),
	preload("res://assets/players/Character_4/Character_4.glb"),
]
const CHARACTER_HEIGHTS := [8.94, 9.513729, 7.888794, 5.453089]
const SEATS := [
	{"position": Vector3(-2.25, 0.85, -1.8), "yaw": -PI * 0.5},
	{"position": Vector3(-2.25, 0.85, 1.2), "yaw": -PI * 0.5},
	{"position": Vector3(2.25, 0.85, -1.8), "yaw": PI * 0.5},
	{"position": Vector3(2.25, 0.85, 1.2), "yaw": PI * 0.5},
]

var session: MayoNet
var _avatars: Dictionary = {}
var _roster_label: Label
var _stage_label: Label
var _status_label: Label
var _start_button: Button
var _camera_pivot: Node3D
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_build_truck()
	_build_camera()
	_build_ui()
	if session != null:
		if not session.roster_changed.is_connected(_refresh_roster):
			session.roster_changed.connect(_refresh_roster)
		if not session.status_changed.is_connected(_on_status):
			session.status_changed.connect(_on_status)
	_refresh_roster()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if session != null:
		if session.roster_changed.is_connected(_refresh_roster):
			session.roster_changed.disconnect(_refresh_roster)
		if session.status_changed.is_connected(_on_status):
			session.status_changed.disconnect(_on_status)


func _unhandled_input(event: InputEvent) -> void:
	# The cursor stays available for the host buttons. Hold the right mouse
	# button to look around the truck without breaking the seated state.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var motion := event as InputEventMouseMotion
		_yaw = clampf(_yaw - motion.relative.x * 0.003, -1.15, 1.15)
		_pitch = clampf(_pitch - motion.relative.y * 0.003, -0.65, 0.65)
		_camera_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


func _build_truck() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("10130f")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4c8b2")
	settings.ambient_light_energy = 0.58
	environment.environment = settings
	add_child(environment)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 3.0, 0.0)
	lamp.light_color = Color("ffe7af")
	lamp.light_energy = 5.0
	lamp.omni_range = 12.0
	add_child(lamp)
	_box("Floor", Vector3(0.0, -0.15, 0.0), Vector3(6.4, 0.3, 9.0), Color("30382e"))
	_box("Roof", Vector3(0.0, 4.1, 0.0), Vector3(6.4, 0.25, 9.0), Color("293126"))
	_box("LeftHull", Vector3(-3.1, 2.0, 0.0), Vector3(0.25, 4.0, 9.0), Color("394535"))
	_box("RightHull", Vector3(3.1, 2.0, 0.0), Vector3(0.25, 4.0, 9.0), Color("394535"))
	_box("CabWall", Vector3(0.0, 2.0, -4.4), Vector3(6.4, 4.0, 0.25), Color("252d23"))
	_box("TailGate", Vector3(0.0, 1.6, 4.4), Vector3(6.4, 3.2, 0.25), Color("465641"))
	_box("LeftBench", Vector3(-2.45, 0.55, 0.0), Vector3(1.0, 0.35, 7.2), Color("6c5941"))
	_box("RightBench", Vector3(2.45, 0.55, 0.0), Vector3(1.0, 0.35, 7.2), Color("6c5941"))


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.position = Vector3(0.0, 2.25, 2.7)
	add_child(_camera_pivot)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 78.0
	_camera_pivot.add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "수송 트럭"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	_stage_label = Label.new()
	column.add_child(_stage_label)
	_roster_label = Label.new()
	column.add_child(_roster_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	_start_button = Button.new()
	_start_button.text = "시작하기"
	_start_button.pressed.connect(func(): start_requested.emit())
	column.add_child(_start_button)
	var leave := Button.new()
	leave.text = "세션 나가기"
	leave.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave)
	var hint := Label.new()
	hint.text = "오른쪽 마우스를 누른 채 둘러보기 · 좌석 이동/발사 없음"
	hint.modulate = Color(0.75, 0.78, 0.72)
	column.add_child(hint)


func _refresh_roster() -> void:
	if session == null or _roster_label == null:
		return
	var assignments := session.seat_assignments()
	for peer_id in _avatars.keys():
		if not assignments.has(peer_id):
			_avatars[peer_id].queue_free()
			_avatars.erase(peer_id)
	var lines: Array[String] = []
	var ids: Array = assignments.keys()
	ids.sort_custom(func(a, b): return int(assignments[a]) < int(assignments[b]))
	for peer_id in ids:
		var seat := int(assignments[peer_id])
		lines.push_back("좌석 %d · 플레이어 %d%s" % [seat + 1, peer_id,
			" (방장)" if int(peer_id) == 1 else ""])
		if not _avatars.has(peer_id):
			_spawn_seated_avatar(int(peer_id), seat)
	_roster_label.text = "참가자 %d / 4\n%s" % [assignments.size(), "\n".join(lines)]
	_stage_label.text = "선택: %s" % StageRegistry.display_name(session.selected_stage)
	var host := session.is_server()
	_status_label.text = "%s\n%s" % [session.connection_summary(), session.status()] \
		if host and session.is_online() else session.status()
	_start_button.visible = host
	_start_button.disabled = not host or not session.all_lobby_ready()
	_start_button.tooltip_text = "모든 참가자의 로비 초기화를 기다리는 중" \
		if _start_button.disabled else "1~4인으로 시작"


func _spawn_seated_avatar(peer_id: int, seat: int) -> void:
	var root := Node3D.new()
	root.name = "SeatedPlayer_%d" % peer_id
	root.position = SEATS[seat]["position"]
	root.rotation.y = SEATS[seat]["yaw"]
	add_child(root)
	var visual := CHARACTER_SCENES[seat % CHARACTER_SCENES.size()].instantiate() as Node3D
	visual.name = "Character"
	visual.scale = Vector3.ONE * (1.65 / CHARACTER_HEIGHTS[seat % CHARACTER_HEIGHTS.size()])
	# The current character files contain walk/run/death but no sitting clip.
	# This restrained lean and lowered root is the explicit temporary seated pose.
	visual.rotation.x = deg_to_rad(-7.0)
	visual.position.y = -0.15
	root.add_child(visual)
	var tag := Label3D.new()
	tag.text = "P%d" % peer_id
	tag.font_size = 54
	tag.pixel_size = 0.008
	tag.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(tag)
	_avatars[peer_id] = root


func _on_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = "%s\n%s" % [session.connection_summary(), message] \
			if session != null and session.is_server() and session.is_online() else message


func _box(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.position = at
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	add_child(mesh)
