class_name OfficeLobby
extends TruckLobby

## 사무실: 출발 전에 팀이 모이는 곳. 혼자하기도 여기를 거친다.
##
## 몸을 걷게 하고 서로에게 보여 주는 일은 전부 `TruckLobby`의 것이다(호스트가 모든 몸을
## 움직이고 자세를 보내 준다). 여기서 바뀌는 것은 방, 화면, 그리고 할 수 있는 일이다.
##   * 큰 스크린의 지도 -- 방장이 갈 축제를 고른다. 팀원은 보기만 한다.
##   * 사물함 -- 캐릭터를 다시 고른다.
##   * 슬롯머신 -- 팀 돈을 걸고 돌린다. 누구나 할 수 있고 방장이 굴린다(`OfficeSlot`).
##   * 출발 구역 -- 전원이 올라서면 잠깐 센 뒤 떠난다. 지도에는 출발 버튼이 없다.
## 출발 조건은 "전원이 캐릭터를 골랐고(`MayoNet.can_start_stage`) 전원이 구역 위에 있다"이다.
## 누가 구역에 있는지는 각자 자기 화면의 몸 위치로 세고(방장이 보내 준 자세), 실제 출발은
## 방장만 일으킨다.
## 방 자체는 `maps/command.tscn`에 노드로 놓여 있다(에디터에서 직접 고친다). 이 스크립트는
## 그 씬을 불러와 스크린·사물함·시작 자리의 위치만 읽어 간다.

signal character_requested

const CharacterSelectScript := preload("res://scripts/character_select.gd")
const ROOM_SCENE := preload("res://maps/command.tscn")

## 아래 세 값은 방 씬에 해당 노드가 없을 때만 쓰는 기본값이다.
const SCREEN_POSITION := Vector3(0.0, 2.35, -8.65)
const LOCKER_POSITION := Vector3(-8.45, 1.5, 2.5)
const INTERACT_DISTANCE := 4.6
const LOOK_DOT := 0.8
const OFFICE_WALK_SPEED := 5.2
## 전원이 출발 구역에 올라선 뒤 떠나기까지. 한 명이라도 내려서면 처음부터 다시 센다.
const DEPART_COUNTDOWN := 3.0
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

enum Target { NONE, MAP, LOCKER, SLOT }

var _room: Node3D
var _screen_position := SCREEN_POSITION
var _locker_position := LOCKER_POSITION
var _spawns: Array = SPAWNS
## 출발까지 남은 시간(초). 세고 있지 않으면 `DEPART_COUNTDOWN`.
var depart_countdown := DEPART_COUNTDOWN
var _depart_area: Area3D
var _depart_half := Vector2(3.0, 1.3)
var _depart_sign: Label3D
var _depart_hud: Label
var _depart_fired := false
var _slot_position := Vector3.INF
var _slot_layer: CanvasLayer
var _slot_money: Label
var _slot_bet_label: Label
var _slot_reels: Array[Label] = []
var _slot_message: Label
var _slot_spin: Button
var _slot_bet := 10
var _slot_waiting := false
var _slot_tween: Tween
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


func _ready() -> void:
	walk_speed = OFFICE_WALK_SPEED
	_ensure_interact_action()
	super._ready()
	if session != null and not session.slot_result.is_connected(_on_slot_result):
		session.slot_result.connect(_on_slot_result)


func _exit_tree() -> void:
	if session != null and session.slot_result.is_connected(_on_slot_result):
		session.slot_result.disconnect(_on_slot_result)
	super._exit_tree()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_departure(delta)
	var target := _target() if not _busy() else Target.NONE
	if _prompt != null:
		_prompt.visible = target != Target.NONE
		if target == Target.MAP:
			_prompt.text = "[ E ] 축제 지도 보기"
		elif target == Target.LOCKER:
			_prompt.text = "[ E ] 캐릭터 바꾸기"
		elif target == Target.SLOT:
			_prompt.text = "[ E ] 슬롯머신 돌리기"
	if target != Target.NONE and Input.is_action_just_pressed("interact"):
		if target == Target.MAP:
			open_map()
		elif target == Target.SLOT:
			open_slot()
		else:
			character_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_map_open() or is_slot_open():
		if event.is_action_pressed("ui_cancel"):
			close_map()
			close_slot()
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
	# 지도나 슬롯머신을 띄운 채로 메뉴를 열었다 닫으면 커서는 그 화면 것이다.
	if is_map_open() or is_slot_open():
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


# -- 슬롯머신 ------------------------------------------------------------------

func is_slot_open() -> bool:
	return _slot_layer != null and is_instance_valid(_slot_layer)


func open_slot() -> void:
	if is_slot_open() or is_map_open() or session == null:
		return
	_build_slot_panel()
	_cursor_free = true
	_apply_mouse_mode()
	_refresh_slot()


func close_slot() -> void:
	if not is_slot_open():
		return
	if _slot_tween != null:
		_slot_tween.kill()
	_slot_layer.queue_free()
	_slot_layer = null
	_slot_reels.clear()
	_slot_waiting = false
	_cursor_free = false
	_apply_mouse_mode()


## 판돈을 정한다. 1부터 팀 돈 전부까지.
func set_slot_bet(amount: int) -> void:
	_slot_bet = clampi(amount, 1, maxi(session.team_money, 1)) if session != null else 1
	_refresh_slot()


## 지금 판돈으로 돌린다. 결과는 `MayoNet.slot_result`로 온다.
func spin_slot() -> bool:
	if session == null or _slot_waiting or not session.request_slot_spin(_slot_bet):
		return false
	_slot_waiting = true
	_refresh_slot()
	return true


func _on_slot_result(peer_id: int, bet: int, won: bool, reels: PackedInt32Array) -> void:
	var who := "나" if peer_id == _local_id() else "P%d" % peer_id
	var text := "%s: %d 걸고 %s" % [who, bet, "당첨! +%d" % bet if won else "꽝  -%d" % bet]
	if not is_slot_open() or peer_id != _local_id():
		# 남이 돌린 것, 또는 화면을 닫은 뒤에 온 결과: 한 줄로만 알린다.
		if is_slot_open():
			_slot_message.text = text
		_refresh_slot()
		return
	# 내가 돌린 것: 칸이 잠깐 돌다가 왼쪽부터 하나씩 멈춘다.
	if _slot_tween != null:
		_slot_tween.kill()
	_slot_tween = create_tween()
	for step in 12:
		_slot_tween.tween_callback(_show_reels.bind(reels, step / 4, step))
		_slot_tween.tween_interval(0.07)
	_slot_tween.tween_callback(func():
		_show_reels(reels, 3, 0)
		_slot_message.text = text
		_slot_message.add_theme_color_override("font_color", UI.MINT if won else UI.GOLD)
		_slot_waiting = false
		_refresh_slot())


## 왼쪽 `settled`칸은 결과 그림, 나머지는 돌아가는 중인 그림.
func _show_reels(reels: PackedInt32Array, settled: int, step: int) -> void:
	for index in _slot_reels.size():
		var symbol := int(reels[index]) if index < settled \
			else (step + index * 2) % OfficeSlot.SYMBOLS.size()
		_slot_reels[index].text = OfficeSlot.SYMBOLS[symbol]
		_slot_reels[index].add_theme_color_override("font_color", OfficeSlot.SYMBOL_COLORS[symbol])


func _refresh_slot() -> void:
	if not is_slot_open() or session == null:
		return
	_slot_bet = clampi(_slot_bet, 1, maxi(session.team_money, 1))
	_slot_money.text = "팀 돈  %d" % session.team_money
	_slot_bet_label.text = "판돈  %d" % _slot_bet
	_slot_spin.disabled = _slot_waiting or session.team_money < 1
	_slot_spin.text = "돌아가는 중…" if _slot_waiting else \
		("돈이 없습니다" if session.team_money < 1 else "돌리기  (%d 걸기)" % _slot_bet)


func _build_slot_panel() -> void:
	_slot_layer = CanvasLayer.new()
	_slot_layer.name = "SlotMachineUI"
	_slot_layer.layer = 4
	add_child(_slot_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_slot_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_layer.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := _pad(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 460.0
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(UI.eyebrow("한 방", UI.GOLD))
	var heading := Label.new()
	heading.text = "슬롯머신"
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	var sub := Label.new()
	sub.text = "세 칸이 같으면 건 돈이 두 배. 아니면 건 돈을 잃습니다. 팀 공용 돈을 겁니다."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UI.MUTED)
	column.add_child(sub)
	var reels := HBoxContainer.new()
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	reels.add_theme_constant_override("separation", 12)
	column.add_child(reels)
	for index in 3:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(130.0, 96.0)
		reels.add_child(cell)
		var symbol := Label.new()
		symbol.text = "?"
		symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		symbol.add_theme_font_size_override("font_size", 28)
		cell.add_child(symbol)
		_slot_reels.push_back(symbol)
	_slot_message = Label.new()
	_slot_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_message.add_theme_font_size_override("font_size", 20)
	column.add_child(_slot_message)
	_slot_money = Label.new()
	_slot_money.add_theme_color_override("font_color", UI.GOLD)
	column.add_child(_slot_money)
	_slot_bet_label = Label.new()
	_slot_bet_label.add_theme_font_size_override("font_size", 22)
	column.add_child(_slot_bet_label)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	column.add_child(steps)
	for step in [-10, -1, 1, 10]:
		var change := Button.new()
		change.text = "%+d" % step
		change.focus_mode = Control.FOCUS_NONE
		change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		change.pressed.connect(func(): set_slot_bet(_slot_bet + step))
		steps.add_child(change)
	var half := Button.new()
	half.text = "절반"
	half.focus_mode = Control.FOCUS_NONE
	half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	half.pressed.connect(func(): set_slot_bet(session.team_money / 2))
	steps.add_child(half)
	var all_in := Button.new()
	all_in.text = "전부"
	all_in.focus_mode = Control.FOCUS_NONE
	all_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_in.pressed.connect(func(): set_slot_bet(session.team_money))
	steps.add_child(all_in)
	_slot_spin = Button.new()
	_slot_spin.custom_minimum_size.y = 46.0
	_slot_spin.focus_mode = Control.FOCUS_NONE
	UI.primary(_slot_spin)
	_slot_spin.pressed.connect(spin_slot)
	column.add_child(_slot_spin)
	var close := Button.new()
	close.text = "닫기  (Esc)"
	close.custom_minimum_size.y = 40.0
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_slot)
	column.add_child(close)


## 방장이 지도에서 축제를 고른다. 팀원이 누른 것은 아무 일도 하지 않는다.
func pick_stage(stage_id: String) -> void:
	if session != null:
		session.set_selected_stage(stage_id)
	_refresh_map()


## 지금 바로 떠난다(방장만). 평소에는 출발 구역의 카운트다운이 끝날 때 불린다.
func request_start() -> void:
	if session != null and session.can_start_stage():
		start_requested.emit()


## 출발 구역 한가운데(바닥). 방 씬에 구역이 없으면 원점.
func depart_zone_position() -> Vector3:
	return _depart_area.global_position * Vector3(1.0, 0.0, 1.0) if _depart_area != null \
		else Vector3.ZERO


## 출발 구역 위에 서 있는 사람 수. 높이는 보지 않는다(뛰어도 내려선 것이 아니다).
func occupants_in_depart_zone() -> int:
	if _depart_area == null:
		return 0
	var to_zone := _depart_area.global_transform.affine_inverse()
	var count := 0
	for peer_id in _occupants:
		var at: Vector3 = to_zone * (_occupants[peer_id] as Node3D).global_position
		if absf(at.x) <= _depart_half.x and absf(at.z) <= _depart_half.y:
			count += 1
	return count


func _update_departure(delta: float) -> void:
	var total := _occupants.size()
	var standing := occupants_in_depart_zone()
	var dressed := session == null or (session.all_characters_chosen() and session.all_lobby_ready())
	var message := ""
	if total > 0 and standing == total and dressed:
		depart_countdown = maxf(depart_countdown - delta, 0.0)
		message = "출발까지 %d" % ceili(depart_countdown) if depart_countdown > 0.0 else "출발!"
		if depart_countdown <= 0.0 and not _depart_fired:
			_depart_fired = true
			request_start()
	else:
		depart_countdown = DEPART_COUNTDOWN
		_depart_fired = false
		if standing > 0 and standing < total:
			message = "출발 구역 %d / %d — 모두 올라서면 출발합니다" % [standing, total]
		elif standing > 0:
			message = "아직 캐릭터를 고르는 팀원이 있습니다"
	if _depart_hud != null:
		_depart_hud.text = message
		_depart_hud.visible = message != "" and not is_map_open() and not is_slot_open()
	if _depart_sign != null:
		if total > 0 and standing == total and dressed:
			_depart_sign.text = "출발 %d" % ceili(depart_countdown)
		else:
			_depart_sign.text = "출발 %d/%d" % [standing, total] if standing > 0 else "출발"


## 가까이에서 바라보고 있는 것. 테스트도 이걸로 묻는다.
func interact_target() -> int:
	return _target()


func _busy() -> bool:
	return input_locked or is_map_open() or is_slot_open()


func _target() -> int:
	if _camera_pivot == null or not is_instance_valid(_camera_pivot) \
			or _camera_pivot.get_child_count() == 0:
		return Target.NONE
	var camera := _camera_pivot.get_child(0) as Camera3D
	var best := Target.NONE
	var best_dot := LOOK_DOT
	for entry in [[Target.MAP, _screen_position], [Target.LOCKER, _locker_position],
			[Target.SLOT, _slot_position]]:
		if entry[1] == Vector3.INF:
			continue
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
	return _spawns[seat % _spawns.size()]


func _build_truck() -> void:
	_room = ROOM_SCENE.instantiate() as Node3D
	_room.name = "Room"
	add_child(_room)
	var screen := _room.get_node_or_null("MapScreen/Screen") as Node3D
	if screen != null:
		_screen_position = screen.global_position
	_screen_label = _room.get_node_or_null("MapScreen/Label") as Label3D
	var locker := _room.get_node_or_null("Locker/Body") as Node3D
	if locker != null:
		_locker_position = locker.global_position
	var spawn_root := _room.get_node_or_null("Spawns")
	if spawn_root != null:
		var spawns: Array = []
		for child in spawn_root.get_children():
			var marker := child as Node3D
			if marker != null:
				spawns.push_back({"position": marker.global_position,
					"yaw": marker.global_rotation.y})
		if not spawns.is_empty():
			_spawns = spawns
	var slot := _room.get_node_or_null("SlotMachine/Upper") as Node3D
	if slot != null:
		_slot_position = slot.global_position
	_depart_area = _room.get_node_or_null("Departure/DepartArea") as Area3D
	_depart_sign = _room.get_node_or_null("Departure/Label") as Label3D
	if _depart_area != null:
		var shape_node := _depart_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			var size := (shape_node.shape as BoxShape3D).size
			_depart_half = Vector2(size.x, size.z) * 0.5


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
	hint.text = "WASD 이동 · Space 점프 · E 상호작용 · Esc 메뉴\n모두 출발 구역에 올라서면 떠납니다"
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
	_depart_hud = Label.new()
	_depart_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_depart_hud.add_theme_font_size_override("font_size", 34)
	_depart_hud.add_theme_color_override("font_color", UI.GOLD)
	_depart_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_depart_hud.position = Vector2(-400.0, 96.0)
	_depart_hud.size = Vector2(800.0, 48.0)
	_depart_hud.visible = false
	layer.add_child(_depart_hud)
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
			"[E] 목적지 고르기" if session.is_server() else "[E] 지도 보기"]
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
		lines.push_back("팀 돈: %d" % session.team_money)
		_info_label.text = "\n".join(lines)
	_refresh_progress()
	_refresh_slot()
	_refresh_map()


## 진열장과 기록판: 팀이 가진 전리품만 보이고, 기록판에는 돈과 완료 횟수가 적힌다.
## 진열장의 `Trophy_<전리품 id>` 노드가 그 전리품의 자리다(`FestivalRewards.TROPHIES`).
func _refresh_progress() -> void:
	if _room == null or session == null:
		return
	var shelf := _room.get_node_or_null("TrophyShelf")
	if shelf != null:
		for child in shelf.get_children():
			var trophy_name := String(child.name)
			if trophy_name.begins_with("Trophy_") and child is Node3D:
				(child as Node3D).visible = session.team_trophies.has(trophy_name.trim_prefix("Trophy_"))
	var records := _room.get_node_or_null("RecordBoard/Records") as Label3D
	if records != null:
		var lines: Array[String] = ["팀 돈  %d" % session.team_money]
		for stage_id in StageRegistry.available_ids():
			lines.push_back("%s  %d회" % [StageRegistry.place(stage_id),
				int(session.team_clears.get(stage_id, 0))])
		lines.push_back("전리품  %d / %d" % [session.team_trophies.size(),
			FestivalRewards.TROPHIES.size()])
		records.text = "\n".join(lines)


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
	sub.text = "갈 축제를 고르세요. 모두 출발 구역에 올라서면 떠납니다." if host \
		else "방장이 갈 축제를 고릅니다."
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
	if not session.all_characters_chosen():
		_map_reason.text = "아직 캐릭터를 고르는 팀원이 있습니다."
	elif not session.all_lobby_ready():
		_map_reason.text = "입장 중인 팀원이 있습니다."
	else:
		_map_reason.text = "모두 출발 구역에 올라서면 떠납니다."


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
