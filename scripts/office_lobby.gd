class_name OfficeLobby
extends TruckLobby

## 사무실: 출발 전에 팀이 모이는 곳. 혼자하기도 여기를 거친다.
##
## 몸을 걷게 하고 서로에게 보여 주는 일은 전부 `TruckLobby`의 것이다(호스트가 모든 몸을
## 움직이고 자세를 보내 준다). 여기서 바뀌는 것은 방, 화면, 그리고 할 수 있는 일이다.
##   * 큰 스크린의 지도 -- 방장이 갈 축제를 고르고 출발을 누른다. 팀원은 보기만 한다.
##   * 사물함 -- 캐릭터를 다시 고른다.
## 출발 조건은 "전원이 캐릭터를 골랐다" 하나뿐이다(`MayoNet.can_start_stage`).
## 나중에 판매대·파츠 작업대를 놓을 자리로 양쪽 벽을 비워 두었다.

signal character_requested

const CharacterSelectScript := preload("res://scripts/character_select.gd")

const SCREEN_POSITION := Vector3(0.0, 2.35, -8.65)
const LOCKER_POSITION := Vector3(-8.45, 1.5, 2.5)
const INTERACT_DISTANCE := 4.6
const LOOK_DOT := 0.8
const OFFICE_WALK_SPEED := 5.2
## 네 자리. 문 쪽에 나란히 서서 스크린을 본다.
const SPAWNS := [
	{"position": Vector3(-0.9, 0.0, 5.5), "yaw": 0.0},
	{"position": Vector3(0.9, 0.0, 5.5), "yaw": 0.0},
	{"position": Vector3(-2.7, 0.0, 6.4), "yaw": 0.0},
	{"position": Vector3(2.7, 0.0, 6.4), "yaw": 0.0},
]
const MAP_SIZE := Vector2(540.0, 330.0)
## 지도에서 사무실이 있는 곳(지도 크기에 대한 비율).
const OFFICE_PIN := Vector2(0.12, 0.2)

enum Target { NONE, MAP, LOCKER }

var _info_label: Label
var _prompt: Label
var _screen_label: Label3D
var _map_layer: CanvasLayer
var _map_canvas: MapCanvas
var _map_pins: Dictionary = {}
var _map_title: Label
var _map_place: Label
var _map_blurb: Label
var _map_roster: Label
var _map_reason: Label
var _map_start: Button


func _ready() -> void:
	walk_speed = OFFICE_WALK_SPEED
	_ensure_interact_action()
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var target := _target() if not _busy() else Target.NONE
	if _prompt != null:
		_prompt.visible = target != Target.NONE
		if target == Target.MAP:
			_prompt.text = "[ E ] 축제 지도 보기"
		elif target == Target.LOCKER:
			_prompt.text = "[ E ] 캐릭터 바꾸기"
	if target != Target.NONE and Input.is_action_just_pressed("interact"):
		if target == Target.MAP:
			open_map()
		else:
			character_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_map_open():
		if event.is_action_pressed("ui_cancel"):
			close_map()
			get_viewport().set_input_as_handled()
		return
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw = wrapf(_yaw - deg_to_rad(mouse_sensitivity) * motion.relative.x, -PI, PI)
		_pitch = clampf(_pitch - deg_to_rad(mouse_sensitivity) * motion.relative.y,
			deg_to_rad(-70.0), deg_to_rad(70.0))
		_apply_local_look()


func set_input_locked(locked: bool) -> void:
	super.set_input_locked(locked)
	# 지도를 띄운 채로 메뉴를 열었다 닫으면 커서는 지도 것이다.
	if is_map_open():
		_cursor_free = true
		_apply_mouse_mode()


# -- 지도 ----------------------------------------------------------------------

func is_map_open() -> bool:
	return _map_layer != null and is_instance_valid(_map_layer)


func open_map() -> void:
	if is_map_open() or session == null:
		return
	_build_map_panel()
	_cursor_free = true
	_apply_mouse_mode()
	_refresh_map()


func close_map() -> void:
	if not is_map_open():
		return
	_map_layer.queue_free()
	_map_layer = null
	_map_pins.clear()
	_cursor_free = false
	_apply_mouse_mode()


## 방장이 지도에서 축제를 고른다. 팀원이 누른 것은 아무 일도 하지 않는다.
func pick_stage(stage_id: String) -> void:
	if session != null:
		session.set_selected_stage(stage_id)
	_refresh_map()


func request_start() -> void:
	if session != null and session.can_start_stage():
		start_requested.emit()


## 가까이에서 바라보고 있는 것. 테스트도 이걸로 묻는다.
func interact_target() -> int:
	return _target()


func _busy() -> bool:
	return input_locked or is_map_open()


func _target() -> int:
	if _camera_pivot == null or not is_instance_valid(_camera_pivot) \
			or _camera_pivot.get_child_count() == 0:
		return Target.NONE
	var camera := _camera_pivot.get_child(0) as Camera3D
	var best := Target.NONE
	var best_dot := LOOK_DOT
	for entry in [[Target.MAP, SCREEN_POSITION], [Target.LOCKER, LOCKER_POSITION]]:
		var to_target: Vector3 = entry[1] - camera.global_position
		if to_target.length() > INTERACT_DISTANCE:
			continue
		var dot := (-camera.global_basis.z).dot(to_target.normalized())
		if dot >= best_dot:
			best_dot = dot
			best = entry[0]
	return best


# -- TruckLobby가 부르는 것 -------------------------------------------------------

func _seat_pose(seat: int) -> Dictionary:
	return SPAWNS[seat % SPAWNS.size()]


func _build_truck() -> void:
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
	add_child(light)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 4.2, 0.0)
	lamp.light_color = Color("ffe7af")
	lamp.light_energy = 3.0
	lamp.omni_range = 16.0
	add_child(lamp)
	_box("Floor", Vector3(0.0, -0.2, 0.0), Vector3(18.0, 0.4, 20.0), Color("394149"))
	_box("Ceiling", Vector3(0.0, 5.2, 0.0), Vector3(18.0, 0.25, 20.0), Color("242b31"))
	_box("LeftWall", Vector3(-9.0, 2.5, 0.0), Vector3(0.35, 5.0, 20.0), Color("59636c"))
	_box("RightWall", Vector3(9.0, 2.5, 0.0), Vector3(0.35, 5.0, 20.0), Color("59636c"))
	_box("BackWall", Vector3(0.0, 2.5, -10.0), Vector3(18.0, 5.0, 0.35), Color("4b555e"))
	_box("FrontWall", Vector3(0.0, 2.5, 10.0), Vector3(18.0, 5.0, 0.35), Color("4b555e"))
	_box("DeskA", Vector3(-5.8, 0.75, -3.0), Vector3(3.8, 1.5, 1.8), Color("76573e"))
	_box("DeskB", Vector3(5.8, 0.75, -1.0), Vector3(3.8, 1.5, 1.8), Color("76573e"))
	_box("ScreenFrame", Vector3(0.0, 2.6, -9.72), Vector3(8.5, 4.1, 0.22), Color("15191d"))
	_box("MapScreen", SCREEN_POSITION, Vector3(7.8, 3.4, 0.12), Color("1d5d77"))
	_screen_label = _sign(SCREEN_POSITION + Vector3(0.0, 0.0, 0.08), 0.0, 56)
	_box("Locker", LOCKER_POSITION + Vector3(-0.1, 0.0, 0.0), Vector3(0.7, 3.0, 2.2), Color("5d7a6b"))
	_sign(LOCKER_POSITION + Vector3(0.28, 0.4, 0.0), PI * 0.5, 40).text = "사물함\n캐릭터 바꾸기"


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme = UI.theme()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	layer.add_child(panel)
	var margin := _pad(14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	column.add_child(UI.eyebrow("출격 준비"))
	var title := Label.new()
	title.text = "사무실"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info_label)
	var hint := Label.new()
	hint.text = "WASD 이동 · Space 점프 · E 상호작용 · Esc 메뉴"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UI.MUTED)
	hint.add_theme_font_size_override("font_size", 14)
	column.add_child(hint)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-200.0, -105.0)
	_prompt.size = Vector2(400.0, 40.0)
	_prompt.visible = false
	layer.add_child(_prompt)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 24)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8.0, -16.0)
	layer.add_child(cross)


func _refresh_panel(assignments: Dictionary) -> void:
	if session == null:
		return
	# 아직 고르는 중인 사람은 이름표만 떠 있다: 자리 번호로 정한 임시 모습은 남이 이미
	# 고른 캐릭터와 겹쳐 보일 수 있다.
	for peer_id in _occupants:
		var visual := (_occupants[peer_id] as Node).get_node_or_null("Character") as Node3D
		if visual != null:
			visual.visible = int(peer_id) != _local_id() and session.has_character(int(peer_id))
	var stage_name := StageRegistry.display_name(session.selected_stage)
	if _screen_label != null:
		_screen_label.text = "축제 지도\n▶ %s\n%s" % [stage_name,
			"[E] 목적지 고르기 · 출발" if session.is_server() else "[E] 지도 보기"]
	if _info_label != null:
		var lines: Array[String] = []
		if not session.is_online():
			lines.push_back("혼자하기")
		elif session.is_server():
			lines.push_back("같이하기 · 방장")
			lines.push_back(session.connection_summary())
		else:
			lines.push_back("같이하기 · 참가자")
		lines.push_back("")
		lines.push_back(_roster_text(assignments))
		lines.push_back("")
		lines.push_back("목적지: %s" % stage_name)
		_info_label.text = "\n".join(lines)
	_refresh_map()


func _on_status(_message: String) -> void:
	_refresh_roster()


# -- 내부 ----------------------------------------------------------------------

func _roster_text(assignments: Dictionary) -> String:
	var lines: Array[String] = ["참가자 %d / %d" % [assignments.size(), MayoNet.MAX_CLIENTS + 1]]
	var ids: Array = assignments.keys()
	ids.sort_custom(func(a, b): return int(assignments[a]) < int(assignments[b]))
	for peer_id in ids:
		var who := "P%d" % int(peer_id)
		if int(peer_id) == 1:
			who += " (방장)"
		if int(peer_id) == _local_id():
			who += " · 나"
		lines.push_back("%s — %s" % [who,
			CharacterSelectScript.NAMES[session.character_of(int(peer_id))]
			if session.has_character(int(peer_id)) else "캐릭터 고르는 중"])
	return "\n".join(lines)


func _build_map_panel() -> void:
	_map_layer = CanvasLayer.new()
	_map_layer.name = "FestivalMapUI"
	_map_layer.layer = 4
	add_child(_map_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_map_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_layer.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := _pad(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var host := session.is_server()
	column.add_child(UI.eyebrow("출격 브리핑"))
	var heading := Label.new()
	heading.text = "축제 지도"
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	var sub := Label.new()
	sub.text = "갈 축제를 고르고 출발하세요." if host else "방장이 갈 축제를 고릅니다."
	sub.add_theme_color_override("font_color", UI.MUTED)
	column.add_child(sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)
	_map_canvas = MapCanvas.new()
	_map_canvas.custom_minimum_size = MAP_SIZE
	_map_canvas.office = OFFICE_PIN
	body.add_child(_map_canvas)
	for stage_id in StageRegistry.available_ids():
		var pin := Button.new()
		pin.text = "● %s" % StageRegistry.place(stage_id)
		pin.toggle_mode = true
		pin.focus_mode = Control.FOCUS_NONE
		pin.disabled = not host
		pin.pressed.connect(pick_stage.bind(stage_id))
		_map_canvas.add_child(pin)
		pin.position = StageRegistry.map_pin(stage_id) * MAP_SIZE - Vector2(18.0, 20.0)
		_map_pins[stage_id] = pin
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(300.0, 0.0)
	detail.add_theme_constant_override("separation", 8)
	body.add_child(detail)
	detail.add_child(UI.eyebrow("목적지", UI.GOLD))
	_map_title = Label.new()
	_map_title.add_theme_font_size_override("font_size", 22)
	_map_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_map_title)
	_map_place = Label.new()
	_map_place.add_theme_color_override("font_color", UI.MINT)
	detail.add_child(_map_place)
	_map_blurb = Label.new()
	_map_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_blurb.add_theme_color_override("font_color", UI.MUTED)
	detail.add_child(_map_blurb)
	detail.add_child(HSeparator.new())
	_map_roster = Label.new()
	detail.add_child(_map_roster)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	_map_reason = Label.new()
	_map_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_reason.add_theme_color_override("font_color", UI.GOLD)
	detail.add_child(_map_reason)
	_map_start = Button.new()
	_map_start.text = "출발"
	_map_start.custom_minimum_size.y = 46.0
	_map_start.focus_mode = Control.FOCUS_NONE
	_map_start.visible = host
	UI.primary(_map_start)
	_map_start.pressed.connect(request_start)
	detail.add_child(_map_start)
	var close := Button.new()
	close.text = "닫기  (Esc)"
	close.custom_minimum_size.y = 40.0
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_map)
	detail.add_child(close)


func _refresh_map() -> void:
	if not is_map_open() or session == null:
		return
	var stage_id := session.selected_stage
	for id in _map_pins:
		(_map_pins[id] as Button).set_pressed_no_signal(id == stage_id)
	_map_canvas.destination = StageRegistry.map_pin(stage_id)
	_map_canvas.queue_redraw()
	_map_title.text = StageRegistry.display_name(stage_id)
	_map_place.text = StageRegistry.place(stage_id)
	_map_blurb.text = StageRegistry.blurb(stage_id)
	_map_roster.text = _roster_text(session.seat_assignments())
	var host := session.is_server()
	_map_start.disabled = not session.can_start_stage()
	if not session.all_characters_chosen():
		_map_reason.text = "아직 캐릭터를 고르는 팀원이 있습니다."
	elif not session.all_lobby_ready():
		_map_reason.text = "입장 중인 팀원이 있습니다."
	else:
		_map_reason.text = "" if host else "방장이 출발을 누르면 떠납니다."


func _sign(at: Vector3, yaw: float, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.font_size = font_size
	label.pixel_size = 0.012
	label.modulate = Color("d9f7ff")
	label.position = at
	label.rotation.y = yaw
	add_child(label)
	return label


func _pad(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, amount)
	return margin


func _ensure_interact_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	InputMap.action_add_event("interact", key)


## 지도 그림: 바다, 땅덩이 몇 개, 그리고 사무실에서 목적지까지의 점선.
class MapCanvas extends Control:
	var office := Vector2(0.12, 0.2)
	var destination := Vector2(0.5, 0.5)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("16323f"))
		for blob in [[Vector2(0.26, 0.5), 0.2, Color("3d6b52")],
				[Vector2(0.66, 0.4), 0.24, Color("46745a")],
				[Vector2(0.86, 0.78), 0.12, Color("3d6b52")],
				[Vector2(0.12, 0.2), 0.1, Color("46745a")]]:
			var outline := PackedVector2Array()
			for index in 28:
				var angle := TAU * float(index) / 28.0
				var reach: float = blob[1] * (1.0 + 0.16 * sin(angle * 3.0 + blob[0].x * 9.0)
					+ 0.09 * cos(angle * 5.0))
				outline.append((blob[0] as Vector2) * size
					+ Vector2(cos(angle) * 1.25, sin(angle)) * reach * size.y)
			draw_colored_polygon(outline, blob[2])
		for line in 5:
			var x := size.x * float(line + 1) / 6.0
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(1.0, 1.0, 1.0, 0.05), 1.0)
		for line in 3:
			var y := size.y * float(line + 1) / 4.0
			draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.05), 1.0)
		var from := office * size
		var to := destination * size
		draw_dashed_line(from, to, Color("fff2dd"), 2.0, 9.0)
		draw_circle(from, 6.0, Color("f5cc77"))
		draw_string(ThemeDB.fallback_font, from + Vector2(10.0, 5.0), "사무실",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("fff2dd"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("43545b"), false, 2.0)
