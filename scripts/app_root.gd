class_name SauceApp
extends Node

enum Flow { TITLE, TUTORIAL, OFFICE, LOADING, STAGE, RESULT }
enum OptionsPage { AUDIO, DISPLAY, VIEW, KEYS }

const TutorialScene := preload("res://tutorial_world.tscn")
const OfficeScene := preload("res://office_lobby.tscn")
const OPTIONS_CATEGORIES := ["음량", "화면", "시점·조작", "키 매핑"]
const FPS_REFRESH_SECONDS := 0.25
## What a new room is headed for until the host picks on the office map.
const DEFAULT_STAGE := "stage_2"
## What the session says in its own words, in the player's.
const STATUS_TEXT := {
	"wrong lobby code": "입장 코드가 맞지 않습니다.",
	"room is full": "방이 가득 찼습니다 (최대 4명).",
	"session is already in progress": "이미 출발한 방입니다. 팀이 사무실로 돌아오면 다시 참여할 수 있습니다.",
	"connection failed": "연결하지 못했습니다. IP와 포트를 확인하세요.",
	"connection cancelled": "접속을 취소했습니다.",
	"host closed the session": "방장이 방을 닫았습니다.",
	"game version differs from the host": "방장과 게임 버전이 다릅니다.",
}
const CharacterSelectScript := preload("res://scripts/character_select.gd")
const UI := preload("res://scripts/sauce_ui.gd")

@export var save_path_override := ""

@onready var session: MayoNet = $Session
@onready var space_root: Node = $SpaceRoot
@onready var _title_music: AudioStreamPlayer = $TitleMusic
@onready var _fps_badge: PanelContainer = $FPSOverlay/Badge
@onready var _fps_value: Label = $FPSOverlay/Badge/Value

var flow: int = Flow.TITLE
var save_store: SauceSaveStore
var current_space: Node
var _title_layer: CanvasLayer
var _options_layer: CanvasLayer
var _pause_layer: CanvasLayer
## 같이하기: the make-or-join panel, over the title.
var _party_layer: CanvasLayer
var _practice_bot_count := 0
## The character select: up on the way into the office and from its locker.
var _character_layer: CanvasLayer
## The character this player asked for and has not been given yet.
var _pending_pick := -1
## The arrival shot between loading a stage and playing it.
var _arrival: StageArrival
var _loading_layer: CanvasLayer
var _result_layer: CanvasLayer
var _result_continue_button: Button
var _result_vote_label: Label
var _result_reveal_tween: Tween
var _status_label: Label
var _host_button: Button
var _join_button: Button
var _cancel_join_button: Button
var _address_field: LineEdit
var _port_field: LineEdit
var _code_field: LineEdit
var _open_room: CheckBox
var _volume_slider: HSlider
var _bgm_slider: HSlider
var _sfx_slider: HSlider
var _sensitivity_slider: HSlider
## ESC opens options directly during play. A hidden pause layer keeps solo play
## paused and multiplayer input locked until those options are closed.
var _options_owns_pause := false
var _active_transition := 0
## "Space · 건너뛰기" over a stage's own cold open, while it runs.
var _intro_hint_layer: CanvasLayer
var _notice := ""
var _fps_refresh_left := 0.0
var bot_team: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = int(ProjectSettings.get_setting("application/run/max_fps"))
	save_store = SauceSaveStore.new(save_path_override)
	save_store.load_data()
	_fps_badge.add_theme_stylebox_override("panel", UI.box(UI.SHADE, Color.TRANSPARENT, 5))
	_fps_value.add_theme_color_override("font_color", UI.CREAM)
	_apply_options()
	# A guest is ready when its office is up, not the moment the host lets it
	# in. Picking a character is a separate gate: `MayoNet.can_start_stage`.
	session.defer_lobby_ready = true
	_connect_session()
	_show_title()


func _process(delta: float) -> void:
	if _intro_hint_layer != null and not _stage_intro_active():
		_clear_ui(_intro_hint_layer)
		_intro_hint_layer = null
	if _fps_badge.visible:
		_fps_refresh_left -= delta
		if _fps_refresh_left <= 0.0:
			_fps_refresh_left = FPS_REFRESH_SECONDS
			var text := "%d FPS" % Engine.get_frames_per_second()
			if _fps_value.text != text:
				_fps_value.text = text


## The stage swallows every key while its cold open runs, so the skip is read
## here, ahead of it.
func _input(event: InputEvent) -> void:
	if _options_layer != null and save_store.game_options.capture_key(event):
		get_viewport().set_input_as_handled()
		return
	if not _stage_intro_active() or not _may_skip_stage_intro():
		return
	if event.is_action_pressed("ui_accept") or (InputMap.has_action("jump")
			and event.is_action_pressed("jump")):
		_skip_stage_intro()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _options_layer != null and is_instance_valid(_options_layer):
		_close_options()
	elif _party_layer != null and is_instance_valid(_party_layer):
		_close_party_panel()
	elif _pause_layer != null and is_instance_valid(_pause_layer):
		_close_pause()
	elif _character_layer != null and is_instance_valid(_character_layer):
		# A pause menu on top of the select would unlock the office behind it
		# on the way back. Esc closes a select that may be closed (the locker's);
		# the first one has its own way out (`나가기`).
		if session.has_character(session.local_id()):
			_close_character_select()
	elif flow not in [Flow.TITLE, Flow.LOADING, Flow.RESULT]:
		_open_options_from_game()
	get_viewport().set_input_as_handled()


func _connect_session() -> void:
	session.late_join_waiting.connect(_on_late_join_waiting)
	session.lobby_joined.connect(_on_lobby_joined)
	session.status_changed.connect(_on_session_status)
	session.transition_requested.connect(_on_transition_requested)
	session.play_authorized.connect(_on_play_authorized)
	session.transition_failed.connect(_on_transition_failed)
	session.result_ready.connect(_on_result_ready)
	session.result_votes_changed.connect(_on_result_votes_changed)
	session.truck_returned.connect(_show_office)
	session.session_ended.connect(_on_session_ended)
	session.intro_skipped.connect(_on_intro_skipped)
	session.roster_changed.connect(_settle_character_pick)
	session.team_money_spent.connect(func():
		save_store.parts = session.team_parts
		save_store.set_money(session.team_money, session.team_jackpot))


func _on_late_join_waiting() -> void:
	flow = Flow.LOADING
	_clear_space()
	_show_loading("진행 중인 토마티나에 참가했어요.\n팀이 안전지점에 도착하면 합류합니다.")
	var cancel := Button.new()
	cancel.text = "합류 취소 · 타이틀로"
	cancel.position = Vector2(40, 40)
	cancel.pressed.connect(_leave_session)
	_loading_layer.add_child(cancel)


func _show_title(message := "") -> void:
	flow = Flow.TITLE
	_practice_bot_count = 0
	_clear_space()
	_clear_all_ui()
	# Solo rooms as well as hosted ones: `leave` puts either away.
	session.leave()
	if not _title_music.playing:
		_title_music.play()
	if not message.is_empty():
		_notice = message
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
	column.add_child(_button("혼자하기", _start_solo, true))
	column.add_child(_button("같이하기", _open_party_panel, true))
	column.add_child(_button("튜토리얼", _show_tutorial))
	column.add_child(_button("옵션", _open_options))
	column.add_child(_button("종료", func(): get_tree().quit()))
	if not _notice.is_empty():
		var notice := Label.new()
		notice.name = "TitleNotice"
		notice.text = _status_text(_notice)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.add_theme_color_override("font_color", UI.GOLD)
		column.add_child(notice)
		_notice = ""


func _start_solo() -> void:
	if flow != Flow.TITLE or _party_layer != null:
		return
	session.leave()
	session.begin_solo_room(DEFAULT_STAGE)


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
	_show_title("튜토리얼 완료 저장 실패 (오류 %d)" % error if error != OK else "")


func _open_party_panel() -> void:
	if flow != Flow.TITLE or _party_layer != null:
		return
	_party_layer = CanvasLayer.new()
	_party_layer.name = "PartyUI"
	_party_layer.layer = 5
	add_child(_party_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UI.SHADE
	_party_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.theme = UI.theme()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_party_layer.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	centre.add_child(panel)
	var margin := _margin(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "같이하기"
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
	host.add_child(UI.eyebrow("목적지는 사무실 지도에서 고릅니다.", UI.MUTED))
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
	_host_button = _button("방 만들기", _host_room, true)
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_host_button)
	_join_button = _button("참여하기", _join_room, true)
	_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_join_button)
	_cancel_join_button = _button("접속 취소", session.cancel_join)
	_cancel_join_button.visible = false
	column.add_child(_cancel_join_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UI.MUTED)
	_status_label.text = "참여하려면 방장이 알려 준 IP, 포트, 입장 코드가 필요합니다.\n팀이 사무실에 있는 동안에만 들어갈 수 있습니다."
	column.add_child(_status_label)
	column.add_child(_button("닫기  (Esc)", _close_party_panel))


func _host_room() -> void:
	if not session.begin_host_room(_port(), _code_field.text.strip_edges(),
			_open_room.button_pressed, DEFAULT_STAGE):
		_status_label.text = _status_text(session.status())


func _join_room() -> void:
	session.leave()
	if session.begin_join_room(_address_field.text.strip_edges(), _port(),
			_code_field.text.strip_edges()):
		_host_button.disabled = true
		_join_button.disabled = true
		_cancel_join_button.visible = true
		_status_label.text = "접속 및 입장 코드 인증 중…"
	else:
		_status_label.text = _status_text(session.status())


func _close_party_panel() -> void:
	if _party_layer == null:
		return
	session.cancel_join()
	_clear_ui(_party_layer)
	_party_layer = null
	_status_label = null


## Let into a room -- one made here, one joined, or a solo one: the office.
func _on_lobby_joined() -> void:
	if flow == Flow.TITLE:
		_show_office()


## The office: where the party gathers, picks who to be, and sets out from. It
## is also where every stage comes back to (`truck_returned`), and while the
## party is standing in it the room is open to join again.
func _show_office() -> void:
	flow = Flow.OFFICE
	_clear_space()
	_clear_all_ui()
	var office := OfficeScene.instantiate() as OfficeLobby
	office.session = session
	office.mouse_sensitivity = save_store.mouse_sensitivity
	office.practice_bot_count = _practice_bot_count
	office.start_requested.connect(session.request_stage_start)
	office.character_requested.connect(_show_character_select)
	# 방의 돈과 전리품은 방장의 저장 파일에서 온다. 축제를 마치고 돌아올 때마다 다시 올린다.
	if session.is_server():
		session.set_team_progress(save_store.money, save_store.trophies, save_store.clears, save_store.jackpot,
			save_store.parts)
	# 캐릭터를 아직 안 골랐으면 곧바로 선택 화면이 뜬다. 사무실이 그 직전에 마우스를 잡으면
	# 커서가 화면 가운데로 끌려갔다가 풀리므로, 처음부터 잠근 채로 들인다.
	office.input_locked = not session.has_character(session.local_id())
	space_root.add_child(office)
	current_space = office
	call_deferred("_report_office_ready")
	# Nobody stands around undressed: a player who has not picked yet picks
	# before they can walk. Coming back from a stage they are still wearing it.
	if not session.has_character(session.local_id()):
		_show_character_select()


func _report_office_ready() -> void:
	if flow == Flow.OFFICE:
		session.report_lobby_initialized()


## Pick who to be. Up on the way into the office, and again from the locker.
## No two players wear the same one, and the host decides who got there first,
## so the select stays up until the session says the pick is this player's.
func _show_character_select() -> void:
	if flow != Flow.OFFICE or (_character_layer != null and is_instance_valid(_character_layer)):
		return
	if current_space is OfficeLobby:
		(current_space as OfficeLobby).close_map()
		(current_space as OfficeLobby).set_input_locked(true)
	var select := CharacterSelectScript.new()
	select.session = session
	select.can_cancel = session.has_character(session.local_id())
	select.character_chosen.connect(_on_character_chosen)
	select.leave_requested.connect(_leave_session)
	select.cancel_requested.connect(_close_character_select)
	add_child(select)
	_character_layer = select
	_pending_pick = -1
	_set_mouse_visible(true)


func _on_character_chosen(index: int) -> void:
	if flow != Flow.OFFICE or not session.lobby_flow:
		return
	if not session.choose_character(index):
		return
	_pending_pick = index
	_settle_character_pick()


## Closes the select once the session agrees the pick is ours. A pick that
## somebody else got to first leaves it up, with that card now marked taken.
func _settle_character_pick() -> void:
	if _pending_pick < 0 or _character_layer == null or not is_instance_valid(_character_layer):
		return
	var mine := session.local_id()
	if session.has_character(mine) and session.character_of(mine) == _pending_pick:
		_close_character_select()
	elif session.character_taken(_pending_pick, mine):
		_pending_pick = -1


func _close_character_select() -> void:
	_pending_pick = -1
	_clear_ui(_character_layer)
	_character_layer = null
	if current_space is OfficeLobby:
		(current_space as OfficeLobby).set_input_locked(false)
	else:
		_restore_mouse_for_flow()


func _on_transition_requested(stage_id: String, transition: int) -> void:
	if not StageRegistry.has_stage(stage_id):
		_on_transition_failed("unknown stage: %s" % stage_id)
		return
	if current_space is OfficeLobby:
		_practice_bot_count = (current_space as OfficeLobby).practice_bot_count
	flow = Flow.LOADING
	_active_transition = transition
	_show_loading("%s 로딩 중…\n모든 참가자를 기다립니다." % StageRegistry.display_name(stage_id))
	_clear_space()
	# 스테이지를 읽는 동안 화면이 멈춘다. 로딩 화면이 먼저 그려지도록 두 프레임을 넘긴 뒤에
	# 읽는다 -- 그러지 않으면 멈춘 화면이 사무실의 마지막 장면("출발까지 1")이다.
	await get_tree().process_frame
	await get_tree().process_frame
	if flow != Flow.LOADING or _active_transition != transition:
		return
	var scene_path := StageRegistry.scene_path(stage_id)
	var packed: PackedScene
	if ResourceLoader.has_cached(scene_path):
		packed = ResourceLoader.load(scene_path) as PackedScene
	else:
		var request := ResourceLoader.load_threaded_request(scene_path)
		if request == OK or request == ERR_BUSY:
			var status := ResourceLoader.load_threaded_get_status(scene_path)
			while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
				if flow != Flow.LOADING or _active_transition != transition:
					return
				status = ResourceLoader.load_threaded_get_status(scene_path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				packed = ResourceLoader.load_threaded_get(scene_path) as PackedScene
			elif ResourceLoader.has_cached(scene_path):
				packed = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		_on_transition_failed("stage scene could not be loaded")
		return
	var world = packed.instantiate()
	if stage_id == "stage_2":
		world.tomatina_shortcut_open = false
		world.staged_loading = true
	world.external_net = session
	world.mouse_sensitivity = save_store.mouse_sensitivity
	world.stage_cleared.connect(_on_stage_cleared)
	# 사무실 작업대에서 해금한 파츠만 피난처 상점에 나온다.
	if "unlocked_parts" in world:
		world.unlocked_parts = session.team_parts
	world.menu_requested.connect(_open_pause)
	current_space = world
	space_root.add_child(world)
	while is_instance_valid(world) and current_space == world and not world.load_complete:
		await get_tree().process_frame
		if flow != Flow.LOADING or _active_transition != transition:
			return
	if not is_instance_valid(world) or current_space != world:
		return
	save_store.game_options.apply_world(world)
	session.attach_play_world(world)
	if stage_id == "stage_2" and not session.is_online() and _practice_bot_count > 0:
		bot_team = preload("res://scripts/player_bot_team.gd").new()
		world.add_child(bot_team)
		bot_team.configure(world, false, _practice_bot_count)
		world.fixed_party_size += _practice_bot_count
		world.rescale_enemies()
	if stage_id == "stage_2":
		await world.prepare_stage_intro()
		if not is_instance_valid(world) or current_space != world or _active_transition != transition:
			return
		await world.warm_stage_materials()
		if not is_instance_valid(world) or current_space != world or _active_transition != transition:
			return
	session.report_world_loaded(transition)


## Everybody has the stage loaded. The arrival shot plays first -- every time,
## a retry included -- and play begins when it ends or the host skips it.
func _on_play_authorized(transition: int) -> void:
	if flow != Flow.LOADING or transition != _active_transition or current_space == null:
		return
	_clear_ui(_loading_layer)
	_loading_layer = null
	# A stage with a cold open of its own (Tomatina's truck ride in) plays that;
	# it hands input over itself when it ends. Any other stage gets the short
	# camera descent.
	if current_space.has_method("has_stage_intro") and current_space.has_stage_intro():
		flow = Flow.STAGE
		current_space.play_stage_intro()
		_show_intro_hint()
		return
	_arrival = StageArrival.new()
	add_child(_arrival)
	_arrival.finished.connect(_on_arrival_finished.bind(transition))
	_arrival.skip_requested.connect(func(): session.request_intro_skip())
	_arrival.begin(current_space, StageRegistry.display_name(session.selected_stage),
		session.is_server())


func _on_arrival_finished(transition: int) -> void:
	if _arrival == null:
		return
	_arrival = null
	if flow != Flow.LOADING or transition != _active_transition or current_space == null:
		return
	flow = Flow.STAGE
	current_space.set_gameplay_input_enabled(true)


## Whether a stage's own cold open is on screen.
func _stage_intro_active() -> bool:
	return flow == Flow.STAGE and current_space != null and is_instance_valid(current_space) \
		and current_space.has_method("tomatina_intro_active") \
		and current_space.tomatina_intro_active()


## The host's to skip in a room (everybody lands together); anybody's when
## there is no room at all (bot practice).
func _may_skip_stage_intro() -> bool:
	return not session.lobby_flow or session.is_server()


func _skip_stage_intro() -> void:
	if not _stage_intro_active() or not _may_skip_stage_intro():
		return
	if session.lobby_flow:
		session.request_intro_skip()
	else:
		current_space.skip_stage_intro()


## The one line of text over a stage's cold open: who can cut it short.
func _show_intro_hint() -> void:
	_clear_ui(_intro_hint_layer)
	_intro_hint_layer = null
	if not _stage_intro_active():
		return
	_intro_hint_layer = CanvasLayer.new()
	_intro_hint_layer.name = "IntroHintUI"
	_intro_hint_layer.layer = 9
	add_child(_intro_hint_layer)
	var hint := Label.new()
	hint.theme = UI.theme()
	hint.text = "Space · 건너뛰기" if _may_skip_stage_intro() else "방장이 건너뛸 수 있습니다"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", UI.MUTED)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -420.0
	hint.offset_right = -40.0
	hint.offset_top = -56.0
	hint.offset_bottom = -22.0
	_intro_hint_layer.add_child(hint)


func _on_intro_skipped(transition: int) -> void:
	if transition != _active_transition:
		return
	if _arrival != null and is_instance_valid(_arrival):
		_arrival.finish()
	elif _stage_intro_active():
		current_space.skip_stage_intro()


## Puts the arrival shot away without starting play: the screen goes back to
## the game camera, and whoever asked decides what happens next.
func _drop_arrival() -> void:
	var arrival := _arrival
	_arrival = null
	if arrival != null and is_instance_valid(arrival):
		arrival.finish()


func _on_transition_failed(reason: String) -> void:
	_notice = reason
	_show_office()


func _on_stage_cleared() -> void:
	if flow != Flow.STAGE or not session.is_server():
		return
	var summary := {"title": "STAGE CLEAR",
		"stage": StageRegistry.display_name(session.selected_stage),
		"players": session.seat_assignments().size()}
	if current_space != null and current_space.has_method("party_size"):
		summary.players = current_space.party_size()
	if current_space != null and current_space.has_method("damage_report"):
		summary["damage"] = current_space.call("damage_report")
	if current_space != null and current_space.has_method("mission_report"):
		summary["statistics"] = current_space.call("mission_report")
	if not is_instance_valid(bot_team):
		summary["reward"] = _settle_reward(int(summary.players))
	session.finish_stage(summary)


## 축제를 마친 방장이 번 것을 셈해 자기 저장 파일에 더한다. 결과 화면에 보여 줄 것을 돌려준다.
func _settle_reward(players: int) -> Dictionary:
	var tomatoes := 0
	if current_space != null and current_space.has_method("carried_tomato_count"):
		tomatoes = int(current_space.call("carried_tomato_count"))
	var coins := 0
	if current_space != null and current_space.has_method("leftover_coin_count"):
		coins = int(current_space.call("leftover_coin_count"))
	var reward := FestivalRewards.settle(session.selected_stage, tomatoes, players, coins)
	reward["owned"] = save_store.trophies.has(str(reward.trophy))
	var error := save_store.add_reward(session.selected_stage, int(reward.money), str(reward.trophy))
	if error != OK:
		push_warning("보상 저장 실패 (오류 %d)" % error)
	reward["total"] = save_store.money
	return reward


static func reward_text(reward: Dictionary) -> String:
	var lines: Array[String] = ["보상  돈 +%d  (보유 %d)" % [int(reward.get("money", 0)),
		int(reward.get("total", 0))]]
	if int(reward.get("coins", 0)) > 0:
		lines.push_back("남긴 코인 %d 포함" % int(reward.get("coins", 0)))
	var needed := int(reward.get("needed", 0))
	var trophy := str(reward.get("trophy", ""))
	if needed > 0:
		var carried := "가져온 토마토 %d / %d개" % [int(reward.get("tomatoes", 0)), needed]
		if trophy.is_empty():
			lines.push_back("전리품 없음 · %s" % carried)
		elif bool(reward.get("owned", false)):
			lines.push_back("전리품 %s (이미 진열 중) · %s" % [FestivalRewards.trophy_name(trophy), carried])
		else:
			lines.push_back("전리품 획득! %s · %s" % [FestivalRewards.trophy_name(trophy), carried])
	return "\n".join(lines)


func _on_result_ready(summary: Dictionary) -> void:
	# A result that lands during the arrival shot takes the screen from it.
	_drop_arrival()
	flow = Flow.RESULT
	if current_space != null and current_space.has_method("set_gameplay_input_enabled"):
		current_space.call("set_gameplay_input_enabled", false)
	_clear_ui(_loading_layer)
	_result_layer = CanvasLayer.new()
	_result_layer.name = "ResultUI"
	_result_layer.layer = 8
	add_child(_result_layer)
	var dim := ColorRect.new()
	dim.name = "ResultBackdropTint"
	# Keep the travelling fire-engine shot legible instead of replacing it with
	# a nearly opaque result backdrop.
	dim.color = Color(0.025, 0.04, 0.05, 0.24)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_margin := MarginContainer.new()
	safe_margin.name = "ResultSafeMargin"
	safe_margin.theme = UI.theme()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override("margin_left", 36)
	safe_margin.add_theme_constant_override("margin_top", 36)
	safe_margin.add_theme_constant_override("margin_right", 36)
	safe_margin.add_theme_constant_override("margin_bottom", 36)
	_result_layer.add_child(safe_margin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	safe_margin.add_child(row)
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.custom_minimum_size = Vector2(590.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
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
	if summary.get("reward") is Dictionary:
		var reward_label := Label.new()
		reward_label.name = "RewardLabel"
		reward_label.text = reward_text(summary.reward)
		reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward_label.add_theme_color_override("font_color", UI.GOLD)
		column.add_child(reward_label)
	var has_statistics: bool = not summary.get("statistics", {}).is_empty()
	if has_statistics:
		preload("res://scripts/mission_statistics.gd").build(column, summary.statistics)
	else:
		_add_damage_lineup(column, summary.get("damage", []))
	_result_vote_label = Label.new()
	_result_vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_vote_label.text = "스탯 공개 중…"
	column.add_child(_result_vote_label)
	_result_continue_button = _button("스탯 공개 중…", _vote_result_continue, true)
	_result_continue_button.disabled = true
	column.add_child(_result_continue_button)
	column.add_child(_button("세션 나가기", _leave_session))
	if has_statistics:
		var tabs := column.get_child(column.get_child_count() - 4) as TabContainer
		_begin_stat_reveal(tabs)
	else:
		call_deferred("_finish_stat_reveal")
	_set_mouse_visible(true)


func _begin_stat_reveal(tabs: TabContainer) -> void:
	if tabs == null or tabs.get_tab_count() == 0:
		call_deferred("_finish_stat_reveal")
		return
	for index in tabs.get_tab_count():
		tabs.set_tab_hidden(index, true)
	_result_reveal_tween = create_tween()
	for index in tabs.get_tab_count():
		_result_reveal_tween.tween_interval(0.62)
		_result_reveal_tween.tween_callback(_reveal_stat.bind(tabs, index))
	_result_reveal_tween.tween_interval(0.35)
	_result_reveal_tween.tween_callback(_finish_stat_reveal)


func _reveal_stat(tabs: TabContainer, index: int) -> void:
	if not is_instance_valid(tabs) or index >= tabs.get_tab_count():
		return
	tabs.set_tab_hidden(index, false)
	tabs.current_tab = index
	if is_instance_valid(_result_vote_label):
		_result_vote_label.text = "스탯 %d/%d" % [index + 1, tabs.get_tab_count()]


func _finish_stat_reveal() -> void:
	if not is_instance_valid(_result_continue_button):
		return
	_result_continue_button.disabled = false
	_result_continue_button.text = "다음으로 넘어가기 동의"
	var status := session.result_continue_status()
	_result_vote_label.text = "다음 이동 동의 %d/%d" % [status.x, status.y]


func _vote_result_continue() -> void:
	if not is_instance_valid(_result_continue_button) or _result_continue_button.disabled:
		return
	_result_continue_button.disabled = true
	_result_continue_button.text = "동의 완료"
	if not session.request_result_continue():
		_result_continue_button.disabled = false
		_result_continue_button.text = "다음으로 넘어가기 동의"


func _on_result_votes_changed(ready: int, total: int) -> void:
	if flow == Flow.RESULT and is_instance_valid(_result_vote_label) \
			and is_instance_valid(_result_continue_button) \
			and not _result_continue_button.text.begins_with("스탯 공개"):
		_result_vote_label.text = "다음 이동 동의 %d/%d" % [ready, total]


## The party stood in a row, each over what they dealt: their own character,
## the number, and a bar against the best of them, most damage first. The rows
## come from the host -- see `MayoPrototype.damage_report` -- and anything that
## is not the numbers it should be is passed over rather than trusted.
func _retry_current_stage() -> void:
	session.replay_stage()


func _add_damage_lineup(column: VBoxContainer, rows) -> void:
	if not rows is Array:
		return
	var best := 1.0
	var total := 0.0
	var clean: Array = []
	for row in rows:
		if not row is Array or (row as Array).size() < 3:
			continue
		var amount := maxf(float(row[2]), 0.0)
		var character := int(row[3]) if (row as Array).size() > 3 else int(row[1])
		clean.push_back([int(row[0]), int(row[1]), amount,
			posmod(character, TruckLobby.CHARACTER_SCENES.size())])
		best = maxf(best, amount)
		total += amount
	if clean.is_empty():
		return
	column.add_child(UI.eyebrow("딜량", UI.MINT))
	var lineup := HBoxContainer.new()
	lineup.alignment = BoxContainer.ALIGNMENT_CENTER
	lineup.add_theme_constant_override("separation", 14)
	column.add_child(lineup)
	for row in clean:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		card.custom_minimum_size = Vector2(150.0, 0.0)
		lineup.add_child(card)
		var holder := SubViewportContainer.new()
		holder.stretch = true
		holder.custom_minimum_size = Vector2(150.0, 190.0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(holder)
		var view := SubViewport.new()
		view.own_world_3d = true
		view.transparent_bg = true
		view.msaa_3d = Viewport.MSAA_4X
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		holder.add_child(view)
		_stand_character(view, int(row[3]))
		var who := Label.new()
		who.text = "플레이어 %d%s" % [int(row[1]) + 1, " (나)" if int(row[0]) == session.local_id() else ""]
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(who)
		var amount_label := Label.new()
		amount_label.text = str(roundi(float(row[2])))
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 26)
		amount_label.add_theme_color_override("font_color", UI.GOLD if float(row[2]) >= best else UI.CREAM)
		card.add_child(amount_label)
		var bar := ProgressBar.new()
		bar.max_value = best
		bar.value = float(row[2])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 10.0)
		card.add_child(bar)
		var share := Label.new()
		share.text = "%d%%" % roundi(float(row[2]) / maxf(total, 1.0) * 100.0)
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		share.add_theme_color_override("font_color", UI.MUTED)
		card.add_child(share)


## One character, stood facing the camera in a little world of its own -- the
## same light and the same first frame of its walk the character select uses.
func _stand_character(view: SubViewport, index: int) -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.0, 0.0, 0.0, 0.0)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d8dccb")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	view.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 1.25
	view.add_child(key)
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.05
	camera.position = Vector3(0.0, 1.45, 5.3)
	view.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.22, 0.0), Vector3.UP)
	camera.current = true
	var model := TruckLobby.CHARACTER_SCENES[index].instantiate() as Node3D
	if model == null:
		return
	model.scale = Vector3.ONE * (CharacterSelectScript.PREVIEW_HEIGHT
		/ float(TruckLobby.CHARACTER_HEIGHTS[index]) * float(CharacterSelectScript.PREVIEW_SCALE[index]))
	model.rotation.y = deg_to_rad(-18.0)
	view.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var animator := players[0] as AnimationPlayer
	var suffix: String = TruckLobby.CHARACTER_WALKS[index]
	for candidate in animator.get_animation_list():
		if String(candidate).ends_with(suffix):
			animator.play(candidate)
			animator.seek(0.0, true)
			animator.pause()
			break


func _leave_session() -> void:
	_show_title("방에서 나왔습니다.")


func _on_session_ended(reason: String) -> void:
	if _party_layer == null:
		_show_title(reason)


func _status_text(message: String) -> String:
	return str(STATUS_TEXT.get(message, message))


func _on_session_status(message: String) -> void:
	if _status_label != null and is_instance_valid(_status_label):
		_status_label.text = _status_text(message)
		if not session.is_online():
			_host_button.disabled = false
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
	panel.custom_minimum_size.x = 760.0
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
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 150.0
	navigation.add_theme_constant_override("separation", 8)
	body.add_child(navigation)
	body.add_child(VSeparator.new())
	var tabs := TabContainer.new()
	tabs.name = "OptionPages"
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.add_child(tabs)
	var pages: Array[VBoxContainer] = []
	var buttons: Array[Button] = []
	var category_group := ButtonGroup.new()
	for category in OPTIONS_CATEGORIES:
		var index := pages.size()
		var button := _button(category, func(): tabs.current_tab = index)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = category_group
		navigation.add_child(button)
		buttons.append(button)
		pages.append(_add_options_page(tabs, category))
	# DEBUG: 개발용 실행에서만 "디버그" 분류가 하나 더 붙는다 -- `scripts/debug_tools.gd`.
	if SauceDebug.available():
		var debug_index := pages.size()
		var debug_button := _button("디버그", func(): tabs.current_tab = debug_index)
		debug_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		debug_button.toggle_mode = true
		debug_button.button_group = category_group
		navigation.add_child(debug_button)
		buttons.append(debug_button)
		SauceDebug.build_page(_add_options_page(tabs, "디버그"), self)
	# /DEBUG
	buttons[OptionsPage.AUDIO].set_pressed_no_signal(true)
	tabs.tab_changed.connect(func(index: int):
		save_store.game_options.cancel_key_capture()
		for i in buttons.size():
			buttons[i].set_pressed_no_signal(i == index))
	var audio := pages[OptionsPage.AUDIO]
	_volume_slider = _audio_slider(audio, "전체 음량", save_store.master_volume)
	_bgm_slider = _audio_slider(audio, "BGM", save_store.bgm_volume)
	_sfx_slider = _audio_slider(audio, "효과음", save_store.sfx_volume)
	var view := pages[OptionsPage.VIEW]
	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.02
	_sensitivity_slider.max_value = 0.3
	_sensitivity_slider.step = 0.005
	_sensitivity_slider.value = save_store.mouse_sensitivity
	view.add_child(_labeled("마우스 감도", _sensitivity_slider))
	save_store.game_options.build(pages[OptionsPage.DISPLAY], view, pages[OptionsPage.KEYS])
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	if _options_owns_pause:
		footer.add_child(_button("나가기 / 게임 종료 메뉴", _show_pause_from_options))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(_button("닫기", _close_options))
	footer.add_child(_button("적용 및 저장", _save_options, true))
	_set_mouse_visible(true)


func _add_options_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 24)
	page.add_child(heading)
	return page


func _open_options_from_game() -> void:
	_open_pause()
	if _pause_layer == null:
		return
	_pause_layer.visible = false
	_options_owns_pause = true
	_open_options()


func _save_options() -> void:
	save_store.game_options.commit()
	save_store.save_options(_volume_slider.value, _sensitivity_slider.value, _bgm_slider.value, _sfx_slider.value)
	_apply_options()
	save_store.game_options.apply_world(current_space)
	if current_space is RecruitmentMap:
		(current_space as RecruitmentMap).mouse_sensitivity = save_store.mouse_sensitivity
	elif current_space is TruckLobby:
		(current_space as TruckLobby).mouse_sensitivity = save_store.mouse_sensitivity
	elif current_space != null and current_space.has_method("apply_look"):
		current_space.set("mouse_sensitivity", save_store.mouse_sensitivity)
	_close_options()


func _close_options() -> void:
	_save_audio_options()
	save_store.game_options.cancel_key_capture()
	_clear_ui(_options_layer)
	_options_layer = null
	if _options_owns_pause:
		_options_owns_pause = false
		_close_pause()
	else:
		_restore_mouse_for_flow()


func _show_pause_from_options() -> void:
	_save_audio_options()
	save_store.game_options.cancel_key_capture()
	_options_owns_pause = false
	_clear_ui(_options_layer)
	_options_layer = null
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.visible = true
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
	slider.value_changed.connect(func(amount: float):
		label.text = caption + "  %d%%" % roundi(amount * 100)
		_preview_audio_options())
	return slider


func _preview_audio_options() -> void:
	if not _audio_sliders_ready():
		return
	_apply_audio_values(_volume_slider.value, _bgm_slider.value, _sfx_slider.value)


func _save_audio_options() -> void:
	if not _audio_sliders_ready():
		return
	save_store.save_options(_volume_slider.value, save_store.mouse_sensitivity,
		_bgm_slider.value, _sfx_slider.value)
	_apply_audio_values(save_store.master_volume, save_store.bgm_volume, save_store.sfx_volume)


func _audio_sliders_ready() -> bool:
	return _volume_slider != null and is_instance_valid(_volume_slider) \
		and _bgm_slider != null and is_instance_valid(_bgm_slider) \
		and _sfx_slider != null and is_instance_valid(_sfx_slider)


func _apply_options() -> void:
	save_store.game_options.apply_window(get_window())
	_fps_badge.visible = bool(save_store.game_options.settings.show_fps)
	_fps_refresh_left = 0.0
	_apply_audio_values(save_store.master_volume, save_store.bgm_volume, save_store.sfx_volume)


func _apply_audio_values(master: float, music: float, effects: float) -> void:
	for entry in [["Master", master], ["Music", music], ["SFX", effects]]:
		var bus := AudioServer.get_bus_index(entry[0])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(entry[1], 0.0001)))
			AudioServer.set_bus_mute(bus, entry[1] <= 0.001)


func _open_pause() -> void:
	if _pause_layer != null or flow in [Flow.TITLE, Flow.LOADING, Flow.RESULT]:
		return
	if current_space != null:
		if current_space.has_method("tomatina_intro_active") and current_space.tomatina_intro_active():
			return
		if session.seat_assignments().size() <= 1:
			current_space.process_mode = Node.PROCESS_MODE_PAUSABLE
			get_tree().paused = true
		if current_space.has_method("set_menu_input_enabled"):
			current_space.call("set_menu_input_enabled", false)
		elif current_space.has_method("set_gameplay_input_enabled"):
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
	if session.seat_assignments().size() > 1:
		var warning := Label.new()
		warning.text = "멀티플레이는 메뉴 중에도 계속됩니다."
		column.add_child(warning)
	column.add_child(_button("계속", _close_pause, true))
	column.add_child(_button("옵션", _open_options))
	if session.is_online():
		column.add_child(_button("방 나가기", _leave_session))
	column.add_child(_button("타이틀로", func(): _show_title()))
	column.add_child(_button("게임 종료", func(): get_tree().quit()))
	_set_mouse_visible(true)


func _close_pause() -> void:
	get_tree().paused = false
	_clear_ui(_pause_layer)
	_pause_layer = null
	if current_space != null:
		if current_space.has_method("set_menu_input_enabled"):
			current_space.call("set_menu_input_enabled", true)
		elif current_space.has_method("set_gameplay_input_enabled"):
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
	bot_team = null
	get_tree().paused = false
	session.bind(null)
	if current_space != null and is_instance_valid(current_space):
		if current_space is OfficeLobby:
			(current_space as OfficeLobby).stop_music()
		# A space can request its own replacement from inside `_physics_process`
		# (the tutorial completion signal does exactly that). Removing it from the
		# tree in that callback leaves the rest of its current physics tick running
		# against nodes that no longer have a World3D. Disable future callbacks, but
		# keep the tree/world valid until queue_free removes it at frame end.
		current_space.process_mode = Node.PROCESS_MODE_DISABLED
		current_space.queue_free()
	current_space = null


func _clear_all_ui() -> void:
	if flow != Flow.TITLE:
		_title_music.stop()
	if _result_reveal_tween != null and _result_reveal_tween.is_valid():
		_result_reveal_tween.kill()
	_result_reveal_tween = null
	_drop_arrival()
	if _options_layer != null:
		save_store.game_options.cancel_key_capture()
	for layer in [_title_layer, _options_layer, _pause_layer, _party_layer,
			_character_layer, _loading_layer, _result_layer, _intro_hint_layer]:
		_clear_ui(layer)
	_intro_hint_layer = null
	_character_layer = null
	_pending_pick = -1
	_title_layer = null
	_options_layer = null
	_options_owns_pause = false
	_pause_layer = null
	_party_layer = null
	_loading_layer = null
	_result_layer = null
	_result_continue_button = null
	_result_vote_label = null
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
	for layer in [_options_layer, _pause_layer, _party_layer, _character_layer]:
		if layer != null and is_instance_valid(layer):
			return true
	# The office is walked through rather than watched, so it holds its own
	# cursor -- captured to look around, released while its map is open -- and
	# `set_input_locked` hands it back when a panel opens.
	return flow in [Flow.TITLE, Flow.RESULT]
