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
## The walk clip each character file calls its own, in the same order. These are
## the names `mayo_prototype.gd` already looks up for the stage; a character
## whose file is missing one simply stands still here rather than failing.
const CHARACTER_WALKS := ["Weapon_Walk", "Walk_WeaponHold",
	"Character_3_Armed_Walk", "Walk_Weapon"]
## Standing height and width, kept at the stage's so a player who fits down the
## aisle here fits between two stalls there.
const OCCUPANT_HEIGHT := 2.56
const OCCUPANT_RADIUS := 0.64
const EYE_ABOVE_CENTRE := 0.62
## A truck in motion is no place to sprint, so there is one speed rather than
## the stage's walk and run, and it is below the stage's 5.2: the aisle is 3.9 m
## across and arriving at the far wall should take a moment.
const WALK_SPEED := 3.4
const ACCELERATION := 24.0
const GRAVITY := 20.0
## Where each seat is, and which way the player riding in it faces. Occupants
## stand in the aisle in front of their seat rather than on the bench -- there
## is still no sitting clip, and a character that can walk away from a pose it
## is not really in reads worse than one simply standing up. The benches reach
## x = +/-1.95 and a body is 0.64 across, so the aisle station is 1.25 rather
## than something that starts 4 cm inside the woodwork and gets shoved out of
## it on the first frame.
const SEATS := [
	{"position": Vector3(-1.25, 0.0, -1.8), "yaw": -PI * 0.5},
	{"position": Vector3(-1.25, 0.0, 1.2), "yaw": -PI * 0.5},
	{"position": Vector3(1.25, 0.0, -1.8), "yaw": PI * 0.5},
	{"position": Vector3(1.25, 0.0, 1.2), "yaw": PI * 0.5},
]

var session: MayoNet
var mouse_sensitivity := 0.09
var input_locked := false
## Tests drive the local occupant through these instead of the keyboard, the
## same seam `debug_clear_enemies` opens in the stage. `Input` is global and a
## headless check has no keys to press.
var debug_input_override := false
var debug_move := Vector2.ZERO

var _occupants: Dictionary = {}
var _animators: Dictionary = {}
var _yaws: Dictionary = {}
var _roster_label: Label
var _stage_label: Label
var _status_label: Label
var _start_button: Button
var _hint_label: Label
var _camera_pivot: Node3D
var _idle_camera: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _cursor_free := false


func _ready() -> void:
	_build_truck()
	_build_idle_camera()
	_build_ui()
	if session != null:
		if not session.roster_changed.is_connected(_refresh_roster):
			session.roster_changed.connect(_refresh_roster)
		if not session.status_changed.is_connected(_on_status):
			session.status_changed.connect(_on_status)
		session.bind_lobby(self)
	_refresh_roster()
	if session == null:
		# Opened on its own with `F6`. One occupant, so the space is still
		# something you can walk around while working on it.
		_spawn_occupant(1, 0)
	_apply_mouse_mode()


func _exit_tree() -> void:
	if session != null:
		if session.roster_changed.is_connected(_refresh_roster):
			session.roster_changed.disconnect(_refresh_roster)
		if session.status_changed.is_connected(_on_status):
			session.status_changed.disconnect(_on_status)
		session.unbind_lobby(self)


## The host walks every body from `MayoNet.run_lobby`, and so does a peer with
## no session at all. What is left for a guest is to put its keys on the wire;
## where they take it comes back in the pose packet.
func _physics_process(delta: float) -> void:
	if session == null:
		# No session means no authority but this one, so the truck walks its
		# own bodies. With a session, `MayoNet.run_lobby` does it instead.
		step_occupants({}, delta)
		return
	if not session.is_online() or session.is_server():
		return
	session.send_lobby_input(_local_move(), _yaw)


func _unhandled_input(event: InputEvent) -> void:
	# The host buttons need a cursor and walking needs the mouse, so the truck
	# holds both and `Tab` moves between them. Walking is locked out while the
	# cursor is free, so a click on `시작하기` cannot also be a step sideways.
	if event.is_action_pressed("ui_focus_next"):
		_cursor_free = not _cursor_free
		_apply_mouse_mode()
		_refresh_hint()
		get_viewport().set_input_as_handled()
		return
	if input_locked or _cursor_free:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw = wrapf(_yaw - deg_to_rad(mouse_sensitivity) * motion.relative.x, -PI, PI)
		_pitch = clampf(_pitch - deg_to_rad(mouse_sensitivity) * motion.relative.y,
			deg_to_rad(-70.0), deg_to_rad(70.0))
		_apply_local_look()


## The pause menu and the options panel both want the cursor back, and neither
## wants the player to keep walking behind them.
func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		for peer_id in _occupants:
			var body: CharacterBody3D = _occupants[peer_id]
			body.velocity.x = 0.0
			body.velocity.z = 0.0
	else:
		# `AppRoot` recaptures the cursor for this flow on its way out of a
		# panel. Leaving `_cursor_free` set would hand the mouse back to looking
		# around while walking stayed locked out, with nothing on screen saying
		# why.
		_cursor_free = false
	_apply_mouse_mode()
	_refresh_hint()


# -- what MayoNet drives -------------------------------------------------------

## Every occupant in a stable order, so the pose packet's slots mean the same
## thing on the peer unpacking it as they did on the host filling it.
func occupant_ids() -> PackedInt32Array:
	var ids := PackedInt32Array(_occupants.keys())
	ids.sort()
	return ids


func occupant_pose(peer_id: int) -> Array:
	var body = _occupants.get(peer_id)
	if body == null:
		return [Vector3.ZERO, 0.0]
	return [body.position, float(_yaws.get(peer_id, 0.0))]


## Walk every body one tick. `client_input` is peer id -> [move, yaw] from the
## guests; this peer's own keys are read here rather than passed in, so it does
## not matter whether the truck's `_physics_process` or the session's runs first.
func step_occupants(client_input: Dictionary, delta: float) -> void:
	for peer_id in _occupants:
		var body: CharacterBody3D = _occupants[peer_id]
		var move := Vector2.ZERO
		var yaw: float = _yaws.get(peer_id, body.rotation.y)
		if int(peer_id) == _local_id():
			move = _local_move()
			yaw = _yaw
		elif client_input.has(peer_id):
			var packet: Array = client_input[peer_id]
			move = packet[0]
			yaw = packet[1]
		_yaws[peer_id] = yaw
		_step_body(body, move, yaw, delta)
		_update_walk_animation(int(peer_id),
			Vector2(body.velocity.x, body.velocity.z).length_squared() > 0.04)


## A pose from the host. The local occupant takes the position -- the host is
## the authority on where everyone ended up, here as in the stage, and there is
## no prediction to reconcile -- but not the yaw: the mouse already turned the
## view, and taking the yaw back would drag it round by the round trip.
func apply_occupant_pose(peer_id: int, at: Vector3, yaw: float) -> void:
	var body = _occupants.get(peer_id)
	if body == null:
		return
	# A client simulates nobody, so its bodies carry no velocity to read a walk
	# cycle off. How far this pose moved since the last one is the only thing
	# here that knows whether that character is walking.
	var travelled := Vector2(at.x - body.position.x, at.z - body.position.z)
	body.position = at
	body.velocity = Vector3.ZERO
	if int(peer_id) == _local_id():
		body.rotation.y = _yaw
		_yaws[peer_id] = _yaw
	else:
		body.rotation.y = yaw
		_yaws[peer_id] = yaw
	_update_walk_animation(int(peer_id), travelled.length_squared() > 0.0001)


# -- internals -----------------------------------------------------------------

func _local_id() -> int:
	return session.local_id() if session != null else 1


func _local_move() -> Vector2:
	if debug_input_override:
		return debug_move
	if input_locked or _cursor_free:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func _step_body(body: CharacterBody3D, move: Vector2, yaw: float, delta: float) -> void:
	body.rotation.y = yaw
	var forward := -Basis(Vector3.UP, yaw).z
	var right := Basis(Vector3.UP, yaw).x
	# Limited rather than normalised: `Input.get_vector` already shortens a
	# diagonal to a full stick and leaves a partial deflection partial, and
	# normalising would turn every nonzero input, however small, into a run.
	var wish := (right * move.x + forward * -move.y).limit_length(1.0)
	if body.is_on_floor():
		body.velocity.y = 0.0
	else:
		body.velocity.y -= GRAVITY * delta
	body.velocity.x = move_toward(body.velocity.x, wish.x * WALK_SPEED, ACCELERATION * delta)
	body.velocity.z = move_toward(body.velocity.z, wish.z * WALK_SPEED, ACCELERATION * delta)
	body.move_and_slide()


## The walk clips are authored in place, so the body's own speed stays the
## source of truth -- the same arrangement the stage uses. With no idle clip in
## these files, standing still is the walk held at its first frame.
func _update_walk_animation(peer_id: int, walking: bool) -> void:
	var entry = _animators.get(peer_id)
	if entry == null:
		return
	var player: AnimationPlayer = entry[0]
	var clip: StringName = entry[1]
	if not is_instance_valid(player) or clip.is_empty():
		return
	if walking == bool(entry[2]):
		return
	entry[2] = walking
	if walking:
		player.play(clip)
	else:
		player.play(clip)
		player.seek(0.0, true)
		player.pause()


func _apply_local_look() -> void:
	var body = _occupants.get(_local_id())
	if body != null:
		body.rotation.y = _yaw
		_yaws[_local_id()] = _yaw
	if _camera_pivot != null:
		_camera_pivot.rotation.x = _pitch


func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
		if (input_locked or _cursor_free) else Input.MOUSE_MODE_CAPTURED


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
	# Every one of these is solid now. They were decoration while the players
	# were parked on their seats; the moment one can walk, an open tailgate is
	# a hole in a moving truck.
	_box("Floor", Vector3(0.0, -0.15, 0.0), Vector3(6.4, 0.3, 9.0), Color("30382e"))
	_box("Roof", Vector3(0.0, 4.1, 0.0), Vector3(6.4, 0.25, 9.0), Color("293126"))
	_box("LeftHull", Vector3(-3.1, 2.0, 0.0), Vector3(0.25, 4.0, 9.0), Color("394535"))
	_box("RightHull", Vector3(3.1, 2.0, 0.0), Vector3(0.25, 4.0, 9.0), Color("394535"))
	_box("CabWall", Vector3(0.0, 2.0, -4.4), Vector3(6.4, 4.0, 0.25), Color("252d23"))
	_box("TailGate", Vector3(0.0, 1.6, 4.4), Vector3(6.4, 3.2, 0.25), Color("465641"))
	_box("LeftBench", Vector3(-2.45, 0.55, 0.0), Vector3(1.0, 0.35, 7.2), Color("6c5941"))
	_box("RightBench", Vector3(2.45, 0.55, 0.0), Vector3(1.0, 0.35, 7.2), Color("6c5941"))


## Where the view sits before this peer has an occupant of its own -- a roster
## that has not arrived yet, or a session that has already emptied. Without it
## the truck renders from nowhere for those frames.
func _build_idle_camera() -> void:
	_idle_camera = Node3D.new()
	_idle_camera.name = "IdleView"
	_idle_camera.position = Vector3(0.0, 2.25, 3.4)
	add_child(_idle_camera)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.05
	_idle_camera.add_child(camera)


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
	# Neither button takes keyboard focus. They are clicked with the cursor the
	# `Tab` toggle frees, and a focused Button swallows `Tab` as focus
	# navigation -- which is the key that frees the cursor in the first place,
	# so one click would strand the player with no way back to walking.
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.pressed.connect(func(): start_requested.emit())
	column.add_child(_start_button)
	var leave := Button.new()
	leave.text = "세션 나가기"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func(): leave_requested.emit())
	column.add_child(leave)
	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.modulate = Color(0.75, 0.78, 0.72)
	column.add_child(_hint_label)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 24)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8.0, -16.0)
	layer.add_child(cross)
	_refresh_hint()


func _restore_idle_camera() -> void:
	if _idle_camera == null or _idle_camera.get_child_count() == 0:
		return
	var camera := _idle_camera.get_child(0) as Camera3D
	if camera != null:
		camera.current = true


func _refresh_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.text = "WASD 이동 · 마우스 시점 · Tab 커서 전환 (버튼 조작)" \
		if not _cursor_free else "커서 사용 중 · Tab 으로 다시 걷기"


func _refresh_roster() -> void:
	if session == null or _roster_label == null:
		return
	var assignments := session.seat_assignments()
	for peer_id in _occupants.keys():
		if not assignments.has(peer_id):
			if int(peer_id) == _local_id():
				_camera_pivot = null
				_restore_idle_camera()
			_occupants[peer_id].queue_free()
			_occupants.erase(peer_id)
			_animators.erase(peer_id)
			_yaws.erase(peer_id)
	var lines: Array[String] = []
	var ids: Array = assignments.keys()
	ids.sort_custom(func(a, b): return int(assignments[a]) < int(assignments[b]))
	for peer_id in ids:
		var seat := int(assignments[peer_id])
		lines.push_back("좌석 %d · 플레이어 %d%s" % [seat + 1, peer_id,
			" (방장)" if int(peer_id) == 1 else ""])
		if not _occupants.has(peer_id):
			_spawn_occupant(int(peer_id), seat)
	_roster_label.text = "참가자 %d / 4\n%s" % [assignments.size(), "\n".join(lines)]
	_stage_label.text = "선택: %s" % StageRegistry.display_name(session.selected_stage)
	var host := session.is_server()
	_status_label.text = "%s\n%s" % [session.connection_summary(), session.status()] \
		if host and session.is_online() else session.status()
	_start_button.visible = host
	_start_button.disabled = not host or not session.all_lobby_ready()
	_start_button.tooltip_text = "모든 참가자의 로비 초기화를 기다리는 중" \
		if _start_button.disabled else "1~4인으로 시작"


func _spawn_occupant(peer_id: int, seat: int) -> void:
	var index := seat % CHARACTER_SCENES.size()
	var body := CharacterBody3D.new()
	body.name = "Occupant_%d" % peer_id
	var spawn: Vector3 = SEATS[seat]["position"]
	body.position = Vector3(spawn.x, OCCUPANT_HEIGHT * 0.5, spawn.z)
	body.rotation.y = SEATS[seat]["yaw"]
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = OCCUPANT_RADIUS
	capsule.height = OCCUPANT_HEIGHT
	collision.shape = capsule
	body.add_child(collision)
	add_child(body)
	var visual := CHARACTER_SCENES[index].instantiate() as Node3D
	visual.name = "Character"
	visual.scale = Vector3.ONE * (OCCUPANT_HEIGHT / CHARACTER_HEIGHTS[index])
	visual.position = Vector3(0.0, -OCCUPANT_HEIGHT * 0.5, 0.0)
	# Hidden on the screen of the player wearing it, exactly as the stage hides
	# it in first person: the camera sits at eye height inside this mesh, and
	# an unhidden one is the inside of a head filling the view. Every other
	# peer is looking at a remote occupant and sees it.
	visual.visible = peer_id != _local_id()
	body.add_child(visual)
	_bind_animator(peer_id, visual, index)
	_occupants[peer_id] = body
	_yaws[peer_id] = float(SEATS[seat]["yaw"])
	if peer_id == _local_id():
		_adopt_local(body, seat)
	else:
		var tag := Label3D.new()
		tag.text = "P%d" % peer_id
		tag.font_size = 54
		tag.pixel_size = 0.008
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0.0, OCCUPANT_HEIGHT * 0.5 + 0.45, 0.0)
		body.add_child(tag)


func _bind_animator(peer_id: int, visual: Node3D, index: int) -> void:
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	var suffix: String = CHARACTER_WALKS[index]
	var clip := StringName()
	for candidate in player.get_animation_list():
		if candidate == suffix or candidate.ends_with("/" + suffix):
			clip = StringName(candidate)
			break
	if clip.is_empty():
		return
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	player.seek(0.0, true)
	player.pause()
	# [the player, the clip, whether it is currently running]
	_animators[peer_id] = [player, clip, false]


## This peer's own body carries the camera, so the view walks with it.
func _adopt_local(body: CharacterBody3D, seat: int) -> void:
	_yaw = float(SEATS[seat]["yaw"])
	_pitch = 0.0
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "ViewPivot"
	_camera_pivot.position = Vector3(0.0, EYE_ABOVE_CENTRE, 0.0)
	body.add_child(_camera_pivot)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 78.0
	camera.near = 0.05
	_camera_pivot.add_child(camera)
	_apply_local_look()


func _on_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = "%s\n%s" % [session.connection_summary(), message] \
			if session != null and session.is_server() and session.is_online() else message


func _box(node_name: String, at: Vector3, size: Vector3, color: Color) -> void:
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
	material.roughness = 0.9
	mesh.material_override = material
	holder.add_child(mesh)
	var solid := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	solid.add_child(shape_node)
	holder.add_child(solid)
