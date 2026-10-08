class_name SauceApp
extends Node

enum Flow { TITLE, TUTORIAL, RECRUITMENT, TRUCK_LOBBY, LOADING, STAGE, RESULT }

const TutorialScene := preload("res://tutorial_world.tscn")
const RecruitmentScene := preload("res://recruitment_map.tscn")
const TruckScene := preload("res://truck_lobby.tscn")

@export var save_path_override := ""

@onready var session: MayoNet = $Session
@onready var space_root: Node = $SpaceRoot

var flow: int = Flow.TITLE
var save_store: SauceSaveStore
var current_space: Node
var _title_layer: CanvasLayer
var _options_layer: CanvasLayer
var _pause_layer: CanvasLayer
var _recruitment_layer: CanvasLayer
var _loading_layer: CanvasLayer
var _result_layer: CanvasLayer
var _status_label: Label
var _join_button: Button
var _cancel_join_button: Button
var _address_field: LineEdit
var _port_field: LineEdit
var _code_field: LineEdit
var _open_room: CheckBox
var _volume_slider: HSlider
var _sensitivity_slider: HSlider
var _active_transition := 0
var _notice := ""


func _ready() -> void:
	save_store = SauceSaveStore.new(save_path_override)
	save_store.load_data()
	_apply_options()
	_connect_session()
	_show_title()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _options_layer != null and is_instance_valid(_options_layer):
		_close_options()
	elif _recruitment_layer != null and is_instance_valid(_recruitment_layer):
		_close_recruitment_panel()
	elif _pause_layer != null and is_instance_valid(_pause_layer):
		_close_pause()
	elif flow not in [Flow.TITLE, Flow.LOADING, Flow.RESULT]:
		_open_pause()
	get_viewport().set_input_as_handled()


func _connect_session() -> void:
	session.lobby_joined.connect(_on_lobby_joined)
	session.status_changed.connect(_on_session_status)
	session.transition_requested.connect(_on_transition_requested)
	session.play_authorized.connect(_on_play_authorized)
	session.transition_failed.connect(_on_transition_failed)
	session.result_ready.connect(_on_result_ready)
	session.truck_returned.connect(_show_truck)
	session.session_ended.connect(_on_session_ended)


func _show_title() -> void:
	flow = Flow.TITLE
	_clear_space()
	_clear_all_ui()
	if session.is_online():
		session.leave()
	_set_mouse_visible(true)
	_title_layer = CanvasLayer.new()
	_title_layer.name = "TitleUI"
	add_child(_title_layer)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(38)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "SAUCE IT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color("fff0a8"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "LAN CO-OP FOOD FIGHT"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.72, 0.8, 0.84)
	column.add_child(subtitle)
	column.add_child(_button("게임 시작", _start_game))
	if save_store.tutorial_completed:
		column.add_child(_button("튜토리얼 다시 하기", _show_tutorial))
	column.add_child(_button("옵션", _open_options))
	column.add_child(_button("종료", func(): get_tree().quit()))


func _start_game() -> void:
	_clear_ui(_title_layer)
	if save_store.tutorial_completed:
		_show_recruitment()
	else:
		_show_tutorial()


func _show_tutorial() -> void:
	flow = Flow.TUTORIAL
	_clear_space()
	_clear_all_ui()
	var world = TutorialScene.instantiate()
	world.name = "TutorialWorld"
	world.mouse_sensitivity = save_store.mouse_sensitivity
	world.tutorial_completed.connect(_on_tutorial_completed)
	world.menu_requested.connect(_open_pause)
	space_root.add_child(world)
	current_space = world


func _on_tutorial_completed() -> void:
	if flow != Flow.TUTORIAL:
		return
	var error := save_store.save_progress_complete()
	if error != OK:
		_notice = "튜토리얼 완료 저장 실패 (오류 %d)" % error
	_show_recruitment()


func _show_recruitment(message := "") -> void:
	flow = Flow.RECRUITMENT
	_clear_space()
	_clear_all_ui()
	var hub := RecruitmentScene.instantiate() as RecruitmentMap
	hub.mouse_sensitivity = save_store.mouse_sensitivity
	hub.screen_interacted.connect(_open_recruitment_panel)
	hub.pause_requested.connect(_open_pause)
	space_root.add_child(hub)
	current_space = hub
	_notice = message if not message.is_empty() else _notice


func _open_recruitment_panel() -> void:
	if flow != Flow.RECRUITMENT or _recruitment_layer != null:
		return
	(current_space as RecruitmentMap).set_input_locked(true)
	_recruitment_layer = CanvasLayer.new()
	_recruitment_layer.name = "RecruitmentUI"
	add_child(_recruitment_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.03, 0.78)
	_recruitment_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recruitment_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "CREW TERMINAL"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var stage := OptionButton.new()
	stage.add_item(StageRegistry.display_name("stage_1"))
	stage.set_item_metadata(0, "stage_1")
	stage.disabled = true
	column.add_child(_labeled("플레이 스테이지", stage))
	_code_field = LineEdit.new()
	_code_field.placeholder_text = "비우면 5자리 코드 자동 생성"
	column.add_child(_labeled("입장 코드 (방 검색 코드가 아닌 인증 코드)", _code_field))
	_open_room = CheckBox.new()
	_open_room.text = "코드 없이 열기"
	column.add_child(_open_room)
	_port_field = LineEdit.new()
	_port_field.text = str(MayoNet.DEFAULT_PORT)
	column.add_child(_labeled("포트", _port_field))
	column.add_child(_button("방 만들기", _host_room))
	column.add_child(HSeparator.new())
	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	column.add_child(_labeled("호스트 IP (코드만으로 방 검색 불가)", _address_field))
	_join_button = _button("참여하기", _join_room)
	column.add_child(_join_button)
	_cancel_join_button = _button("접속 취소", _cancel_join)
	_cancel_join_button.visible = false
	column.add_child(_cancel_join_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = _notice if not _notice.is_empty() else "호스트가 공유한 IP, 포트, 입장 코드가 필요합니다."
	column.add_child(_status_label)
	column.add_child(_button("닫기  (Esc)", _close_recruitment_panel))


func _host_room() -> void:
	if session.begin_host_room(_port(), _code_field.text.strip_edges(),
			_open_room.button_pressed, "stage_1"):
		return
	_status_label.text = session.status()


func _join_room() -> void:
	if session.begin_join_room(_address_field.text.strip_edges(), _port(),
			_code_field.text.strip_edges()):
		_join_button.disabled = true
		_cancel_join_button.visible = true
		_status_label.text = "접속 및 입장 코드 인증 중…"
	else:
		_status_label.text = session.status()


func _cancel_join() -> void:
	session.cancel_join()
	_join_button.disabled = false
	_cancel_join_button.visible = false
	_status_label.text = session.status()


func _close_recruitment_panel() -> void:
	if session.is_online() and not session.all_lobby_ready():
		session.cancel_join()
	_clear_ui(_recruitment_layer)
	_recruitment_layer = null
	if current_space is RecruitmentMap:
		(current_space as RecruitmentMap).set_input_locked(false)


func _on_lobby_joined() -> void:
	if flow == Flow.RECRUITMENT:
		_show_truck()


func _show_truck() -> void:
	flow = Flow.TRUCK_LOBBY
	session.bind(null)
	_clear_space()
	_clear_all_ui()
	var truck := TruckScene.instantiate() as TruckLobby
	truck.session = session
	truck.start_requested.connect(_request_start)
	truck.leave_requested.connect(_leave_session)
	space_root.add_child(truck)
	current_space = truck
	call_deferred("_report_truck_ready")


func _report_truck_ready() -> void:
	if flow == Flow.TRUCK_LOBBY:
		session.report_lobby_initialized()


func _request_start() -> void:
	session.request_stage_start()


func _on_transition_requested(stage_id: String, transition: int) -> void:
	if not StageRegistry.has_stage(stage_id):
		_on_transition_failed("unknown stage: %s" % stage_id)
		return
	flow = Flow.LOADING
	_active_transition = transition
	_show_loading("%s 로딩 중…\n모든 참가자를 기다립니다." % StageRegistry.display_name(stage_id))
	_clear_space()
	var packed := load(StageRegistry.scene_path(stage_id)) as PackedScene
	if packed == null:
		_on_transition_failed("stage scene could not be loaded")
		return
	var world = packed.instantiate()
	world.external_net = session
	world.mouse_sensitivity = save_store.mouse_sensitivity
	world.stage_cleared.connect(_on_stage_cleared)
	world.menu_requested.connect(_open_pause)
	space_root.add_child(world)
	current_space = world
	session.attach_play_world(world)
	session.report_world_loaded(transition)


func _on_play_authorized(transition: int) -> void:
	if flow != Flow.LOADING or transition != _active_transition or current_space == null:
		return
	flow = Flow.STAGE
	_clear_ui(_loading_layer)
	_loading_layer = null
	current_space.set_gameplay_input_enabled(true)


func _on_transition_failed(reason: String) -> void:
	_notice = reason
	_show_truck()


func _on_stage_cleared() -> void:
	if flow != Flow.STAGE or not session.is_server():
		return
	session.finish_stage({"title": "STAGE CLEAR",
		"stage": StageRegistry.display_name(session.selected_stage),
		"players": session.seat_assignments().size()})


func _on_result_ready(summary: Dictionary) -> void:
	flow = Flow.RESULT
	if current_space != null and current_space.has_method("set_gameplay_input_enabled"):
		current_space.call("set_gameplay_input_enabled", false)
	_clear_ui(_loading_layer)
	_result_layer = CanvasLayer.new()
	add_child(_result_layer)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = str(summary.get("title", "STAGE CLEAR"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	column.add_child(title)
	var detail := Label.new()
	detail.text = "%s\n참가자 %d명" % [summary.get("stage", ""), summary.get("players", 1)]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	if session.is_server():
		column.add_child(_button("전원 트럭 복귀", func(): session.return_to_truck()))
	else:
		var waiting := Label.new()
		waiting.text = "방장이 트럭 복귀를 선택할 때까지 기다리는 중…"
		column.add_child(waiting)
	column.add_child(_button("세션 나가기", _leave_session))
	_set_mouse_visible(true)


func _leave_session() -> void:
	if session.is_online():
		session.leave()
	_show_recruitment("세션에서 나왔습니다.")


func _on_session_ended(reason: String) -> void:
	_show_recruitment(reason)


func _on_session_status(message: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = message
		if not session.is_online():
			_join_button.disabled = false
			_cancel_join_button.visible = false


func _open_options() -> void:
	if _options_layer != null:
		return
	_options_layer = CanvasLayer.new()
	add_child(_options_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.015, 0.025, 1.0)
	_options_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "옵션"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = save_store.master_volume
	column.add_child(_labeled("전체 음량", _volume_slider))
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.02
	_sensitivity_slider.max_value = 0.3
	_sensitivity_slider.step = 0.005
	_sensitivity_slider.value = save_store.mouse_sensitivity
	column.add_child(_labeled("마우스 감도", _sensitivity_slider))
	column.add_child(_button("적용 및 저장", _save_options))
	column.add_child(_button("취소", _close_options))
	_set_mouse_visible(true)


func _save_options() -> void:
	save_store.save_options(_volume_slider.value, _sensitivity_slider.value)
	_apply_options()
	if current_space is RecruitmentMap:
		(current_space as RecruitmentMap).mouse_sensitivity = save_store.mouse_sensitivity
	elif current_space != null and current_space.has_method("apply_look"):
		current_space.set("mouse_sensitivity", save_store.mouse_sensitivity)
	_close_options()


func _close_options() -> void:
	_clear_ui(_options_layer)
	_options_layer = null
	_restore_mouse_for_flow()


func _apply_options() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(save_store.master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, save_store.master_volume <= 0.001)


func _open_pause() -> void:
	if _pause_layer != null or flow in [Flow.TITLE, Flow.LOADING, Flow.RESULT]:
		return
	if current_space != null:
		if current_space.has_method("set_gameplay_input_enabled"):
			current_space.call("set_gameplay_input_enabled", false)
		elif current_space.has_method("set_input_locked"):
			current_space.call("set_input_locked", true)
	_pause_layer = CanvasLayer.new()
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.015, 0.025, 0.86)
	_pause_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "메뉴"
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	column.add_child(_button("계속", _close_pause))
	column.add_child(_button("옵션", _open_options))
	if session.is_online():
		column.add_child(_button("세션 나가기", _leave_session))
	column.add_child(_button("타이틀로", _show_title))
	column.add_child(_button("게임 종료", func(): get_tree().quit()))
	_set_mouse_visible(true)


func _close_pause() -> void:
	_clear_ui(_pause_layer)
	_pause_layer = null
	if current_space != null:
		if current_space.has_method("set_gameplay_input_enabled"):
			current_space.call("set_gameplay_input_enabled", true)
		elif current_space.has_method("set_input_locked"):
			current_space.call("set_input_locked", false)
	_restore_mouse_for_flow()


func _show_loading(message: String) -> void:
	_clear_all_ui()
	_loading_layer = CanvasLayer.new()
	add_child(_loading_layer)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(label)
	_set_mouse_visible(true)


func _port() -> int:
	var value := _port_field.text.strip_edges().to_int()
	return value if value > 0 and value <= 65535 else MayoNet.DEFAULT_PORT


func _clear_space() -> void:
	session.bind(null)
	if current_space != null and is_instance_valid(current_space):
		# A space can request its own replacement from inside `_physics_process`
		# (the tutorial completion signal does exactly that). Removing it from the
		# tree in that callback leaves the rest of its current physics tick running
		# against nodes that no longer have a World3D. Disable future callbacks, but
		# keep the tree/world valid until queue_free removes it at frame end.
		current_space.process_mode = Node.PROCESS_MODE_DISABLED
		current_space.queue_free()
	current_space = null


func _clear_all_ui() -> void:
	for layer in [_title_layer, _options_layer, _pause_layer, _recruitment_layer,
			_loading_layer, _result_layer]:
		_clear_ui(layer)
	_title_layer = null
	_options_layer = null
	_pause_layer = null
	_recruitment_layer = null
	_loading_layer = null
	_result_layer = null
	_status_label = null


func _clear_ui(layer: CanvasLayer) -> void:
	if layer != null and is_instance_valid(layer):
		layer.queue_free()


func _button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 42.0
	button.pressed.connect(callback)
	return button


func _margin(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, amount)
	return margin


func _labeled(text_value: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text_value
	box.add_child(label)
	box.add_child(control)
	return box


func _set_mouse_visible(visible: bool) -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func _restore_mouse_for_flow() -> void:
	_set_mouse_visible(_mouse_should_be_visible())


func _mouse_should_be_visible() -> bool:
	# Options can be opened on top of the pause menu. Closing only that top
	# layer must not capture the cursor while the pause menu is still active.
	for layer in [_options_layer, _pause_layer, _recruitment_layer]:
		if layer != null and is_instance_valid(layer):
			return true
	return flow in [Flow.TITLE, Flow.TRUCK_LOBBY, Flow.RESULT]
