class_name SauceApp
extends Node

enum Flow { TITLE, TUTORIAL, RECRUITMENT, TRUCK_LOBBY, LOADING, STAGE, RESULT }

const TutorialScene := preload("res://tutorial_world.tscn")
const RecruitmentScene := preload("res://recruitment_map.tscn")
const TruckScene := preload("res://truck_lobby.tscn")
const CharacterSelectScript := preload("res://scripts/character_select.gd")
const UI := preload("res://scripts/sauce_ui.gd")

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
## The character select, up between being let into a room and the truck.
var _character_layer: CanvasLayer
var _loading_layer: CanvasLayer
var _result_layer: CanvasLayer
var _status_label: Label
var _join_button: Button
var _cancel_join_button: Button
var _address_field: LineEdit
var _port_field: LineEdit
var _code_field: LineEdit
var _open_room: CheckBox
## The stage dropdown on the host panel. Read when the room is made, so the
## selection travels with `begin_host_room` instead of a hard-coded id.
var _stage_select: OptionButton
var _volume_slider: HSlider
var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _sensitivity_slider: HSlider
var _active_transition := 0
var _notice := ""


func _ready() -> void:
	save_store = SauceSaveStore.new(save_path_override)
	save_store.load_data()
	_apply_options()
	# A guest is ready when its truck is up, which is after it has picked a
	# character -- not the moment the host lets it in.
	session.defer_lobby_ready = true
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
	elif _character_layer != null and is_instance_valid(_character_layer):
		# The select has its own way out (`세션 나가기`). A pause menu on top of
		# it would unlock the office behind it on the way back.
		pass
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
	var backdrop := UI.TitleBackdrop.new()
	_title_layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(centre)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 78)
	centre.add_child(layout)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 470.0
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 10)
	layout.add_child(brand)
	var tag := UI.eyebrow("01–04 PLAYERS   /   CO-OP FOOD FIGHT", UI.CREAM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(tag)
	var title := Label.new()
	title.text = "SAUCE IT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_shadow_color", Color("642e2d"))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 5)
	brand.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "소스를 쏘고, 서로의 사선을 비켜라"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 19)
	brand.add_child(subtitle)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(310.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	layout.add_child(panel)
	var margin := _margin(26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(UI.eyebrow("출격 메뉴"))
	column.add_child(_button("게임 시작", _start_game, true))
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
	_recruitment_layer.layer = 5
	add_child(_recruitment_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_recruitment_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recruitment_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "팀 모집 터미널"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	column.add_child(columns)
	var host := VBoxContainer.new()
	host.add_theme_constant_override("separation", 9)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(host)
	var join := VBoxContainer.new()
	join.add_theme_constant_override("separation", 9)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(join)
	host.add_child(UI.eyebrow("01  방 만들기"))
	join.add_child(UI.eyebrow("02  기존 방에 참여"))
	var stage := OptionButton.new()
	for stage_id in StageRegistry.available_ids():
		stage.add_item(StageRegistry.display_name(stage_id))
		stage.set_item_metadata(stage.item_count - 1, stage_id)
	stage.select(0)
	_stage_select = stage
	host.add_child(_labeled("플레이 스테이지", stage))
	_code_field = LineEdit.new()
	_code_field.placeholder_text = "비우면 5자리 코드 자동 생성"
	_open_room = CheckBox.new()
	_open_room.text = "코드 없이 열기"
	host.add_child(_open_room)
	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	join.add_child(_labeled("호스트 IP", _address_field))
	join.add_child(UI.eyebrow("방장이 알려 준 주소를 입력하세요.", UI.MUTED))
	column.add_child(HSeparator.new())
	var connection := HBoxContainer.new()
	connection.add_theme_constant_override("separation", 22)
	column.add_child(connection)
	var code := _labeled("공통 · 입장 코드", _code_field)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection.add_child(code)
	_port_field = LineEdit.new()
	_port_field.text = str(MayoNet.DEFAULT_PORT)
	connection.add_child(_labeled("공통 · 포트", _port_field))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 22)
	column.add_child(actions)
	var create := _button("방 만들기", _host_room, true)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(create)
	_join_button = _button("참여하기", _join_room, true)
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_join_button)
	_cancel_join_button = _button("접속 취소", _cancel_join)
	_cancel_join_button.visible = false
	column.add_child(_cancel_join_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UI.MUTED)
	_status_label.text = _notice if not _notice.is_empty() else "호스트가 공유한 IP, 포트, 입장 코드가 필요합니다."
	column.add_child(_status_label)
	column.add_child(_button("닫기  (Esc)", _close_recruitment_panel))


func _host_room() -> void:
	if session.begin_host_room(_port(), _code_field.text.strip_edges(),
			_open_room.button_pressed, _selected_stage_id()):
		return
	_status_label.text = session.status()


## The stage the host picked, falling back to stage 1 when the panel is not up.
func _selected_stage_id() -> String:
	if _stage_select == null or not is_instance_valid(_stage_select) \
			or _stage_select.selected < 0:
		return "stage_1"
	var picked = _stage_select.get_item_metadata(_stage_select.selected)
	return str(picked) if picked != null and StageRegistry.has_stage(str(picked)) else "stage_1"


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
		_show_character_select()


## Let into a room, host or guest: pick who to be before climbing in. Shown
## this once per session -- coming back from a stage goes straight to the
## truck (`truck_returned`), wearing what was picked here.
func _show_character_select() -> void:
	if _character_layer != null and is_instance_valid(_character_layer):
		return
	_clear_ui(_recruitment_layer)
	_recruitment_layer = null
	# The office stays behind the select, and stays locked: the panel that led
	# here locked it, but say so again rather than depend on that.
	if current_space is RecruitmentMap:
		(current_space as RecruitmentMap).set_input_locked(true)
	var select := CharacterSelectScript.new()
	select.session = session
	select.character_chosen.connect(_on_character_chosen)
	select.leave_requested.connect(_leave_session)
	add_child(select)
	_character_layer = select
	_set_mouse_visible(true)


func _on_character_chosen(index: int) -> void:
	if flow != Flow.RECRUITMENT or not session.is_online():
		return
	session.choose_character(index)
	_show_truck()


func _show_truck() -> void:
	flow = Flow.TRUCK_LOBBY
	session.bind(null)
	_clear_space()
	_clear_all_ui()
	var truck := TruckScene.instantiate() as TruckLobby
	truck.session = session
	truck.mouse_sensitivity = save_store.mouse_sensitivity
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
	if stage_id == "stage_2":
		world.tomatina_shortcut_open = transition % 2 == 1
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
	_result_layer.layer = 8
	add_child(_result_layer)
	var dim := ColorRect.new()
	dim.color = UI.SHADE
	_result_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
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
	column.add_child(UI.eyebrow("임무 결과", UI.GOLD))
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
		column.add_child(_button("전원 트럭 복귀", func(): session.return_to_truck(), true))
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
	_options_layer.layer = 9
	add_child(_options_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_options_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
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
	_volume_slider = _audio_slider(column, "전체 음량", save_store.master_volume)
	_bgm_slider = _audio_slider(column, "BGM", save_store.bgm_volume)
	_sfx_slider = _audio_slider(column, "효과음", save_store.sfx_volume)
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.02
	_sensitivity_slider.max_value = 0.3
	_sensitivity_slider.step = 0.005
	_sensitivity_slider.value = save_store.mouse_sensitivity
	column.add_child(_labeled("마우스 감도", _sensitivity_slider))
	column.add_child(_button("적용 및 저장", _save_options, true))
	column.add_child(_button("취소", _close_options))
	_set_mouse_visible(true)


func _save_options() -> void:
	save_store.save_options(_volume_slider.value, _sensitivity_slider.value, _bgm_slider.value, _sfx_slider.value)
	_apply_options()
	if current_space is RecruitmentMap:
		(current_space as RecruitmentMap).mouse_sensitivity = save_store.mouse_sensitivity
	elif current_space is TruckLobby:
		(current_space as TruckLobby).mouse_sensitivity = save_store.mouse_sensitivity
	elif current_space != null and current_space.has_method("apply_look"):
		current_space.set("mouse_sensitivity", save_store.mouse_sensitivity)
	_close_options()


func _close_options() -> void:
	_clear_ui(_options_layer)
	_options_layer = null
	_restore_mouse_for_flow()


func _audio_slider(column: VBoxContainer, caption: String, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	var row := _labeled(caption + "  %d%%" % roundi(value * 100), slider)
	column.add_child(row)
	var label := row.get_child(0) as Label
	slider.value_changed.connect(func(amount: float): label.text = caption + "  %d%%" % roundi(amount * 100))
	return slider


func _apply_options() -> void:
	for entry in [["Master", save_store.master_volume], ["Music", save_store.bgm_volume], ["SFX", save_store.sfx_volume]]:
		var bus := AudioServer.get_bus_index(entry[0])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(entry[1], 0.0001)))
			AudioServer.set_bus_mute(bus, entry[1] <= 0.001)


func _open_pause() -> void:
	if _pause_layer != null or flow in [Flow.TITLE, Flow.LOADING, Flow.RESULT]:
		return
	if current_space != null:
		if current_space.has_method("set_gameplay_input_enabled"):
			current_space.call("set_gameplay_input_enabled", false)
		elif current_space.has_method("set_input_locked"):
			current_space.call("set_input_locked", true)
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 8
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_pause_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
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
	column.add_child(_button("계속", _close_pause, true))
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
	_loading_layer.layer = 10
	add_child(_loading_layer)
	var dim := ColorRect.new()
	dim.color = UI.INK
	_loading_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", UI.CREAM)
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
			_character_layer, _loading_layer, _result_layer]:
		_clear_ui(layer)
	_character_layer = null
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


func _button(text_value: String, callback: Callable, important := false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 42.0
	if important:
		UI.primary(button)
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
	for layer in [_options_layer, _pause_layer, _recruitment_layer, _character_layer]:
		if layer != null and is_instance_valid(layer):
			return true
	# The truck is walked through rather than watched, so it holds its own
	# cursor -- captured to look around, released with `Tab` for the host
	# buttons -- and `set_input_locked` hands it back when a panel opens.
	return flow in [Flow.TITLE, Flow.RESULT]
