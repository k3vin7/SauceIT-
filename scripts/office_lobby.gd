class_name OfficeLobby
extends TruckLobby

## 사무실: 출발 전에 팀이 모이는 곳. 혼자하기도 여기를 거친다.
##
## 몸을 걷게 하고 서로에게 보여 주는 일은 전부 `TruckLobby`의 것이다(호스트가 모든 몸을
## 움직이고 자세를 보내 준다). 여기서 바뀌는 것은 방, 화면, 그리고 할 수 있는 일이다.
##   * 큰 스크린의 지도 -- 갈 축제와 토마티나 연습 봇을 고른다.
##   * 사물함 -- 캐릭터를 다시 고른다.
##   * 슬롯머신 -- 팀 돈을 걸고 돌린다. 누구나 할 수 있고 방장이 굴린다. 배당과 잭팟은
##     `OfficeSlot`, 사무실에 놓인 기계의 움직임과 소리는 `OfficeSlotShow`.
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
## 디버그용: 사무실에서 이 키를 누를 때마다 팀 돈이 `DEBUG_MONEY_STEP`만큼 늘어난다(방장·혼자하기만).
## 출시 전에 `DEBUG_MONEY_STEP`을 0으로 바꾸면 키도 안내 문구도 사라진다.
const DEBUG_MONEY_KEY := KEY_F9
const DEBUG_MONEY_STEP := 100
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
var practice_bot_count := 0
var _depart_area: Area3D
var _depart_half := Vector2(3.0, 1.3)
var _depart_sign: Label3D
var _depart_hud: Label
var _depart_fired := false
var _slot_position := Vector3.INF
var _slot_layer: CanvasLayer
var _slot_money: Label
var _slot_bet_label: Label
var _slot_reels: Array[SauceBottle] = []
var _slot_message: Label
var _slot_spin: Button
var _slot_bet := 10
var _slot_waiting := false
var _slot_show: OfficeSlotShow
var _slot_jackpot: Label
var _slot_flash: ColorRect
var _slot_coins: CPUParticles2D
var _slot_banner: Label
## 지금 화면에서 돌아가고 있는 한 판(reels, text, tier, gain, pot, elapsed, stopped, ticks). 없으면 빈 사전.
var _slot_spinning: Dictionary = {}
## 화면에 적혀 있는 돈과 잭팟. 칸이 다 멈출 때까지는 돌리기 전 값이고, 멈추면 세어 올라간다.
var _slot_shown_money := 0
var _slot_shown_jackpot := 0
var _slot_count_tween: Tween
var _slot_announce: Label
var _slot_announce_left := 0.0
var _info_label: Label
var _prompt: Label
var _screen_label: Label3D
var _map_layer: CanvasLayer
var _map_bots: HBoxContainer
var _map_bot_buttons: Array[Button] = []
var _map_subtitle: Label
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


func stop_music() -> void:
	$LobbyMusic.stop()


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
	if input_locked:
		return
	if DEBUG_MONEY_STEP > 0 and session != null and event is InputEventKey and event.pressed \
			and not event.echo and (event as InputEventKey).keycode == DEBUG_MONEY_KEY:
		session.add_team_money(DEBUG_MONEY_STEP)
		get_viewport().set_input_as_handled()
		return
	if is_map_open() or is_slot_open():
		if event.is_action_pressed("ui_cancel"):
			close_map()
			close_slot()
			get_viewport().set_input_as_handled()
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
	_map_bot_buttons.clear()
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
	if _slot_count_tween != null:
		_slot_count_tween.kill()
	_slot_spinning = {}
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
	if session == null or _slot_waiting or not is_slot_open():
		return false
	# 방장은 요청하는 자리에서 바로 결과가 나온다. 그 전에 "돌리는 중"과 돌리기 전 금액을 잡아 둔다.
	if _slot_count_tween != null:
		_slot_count_tween.kill()
	_slot_shown_money = session.team_money
	_slot_shown_jackpot = session.team_jackpot
	_slot_waiting = true
	if not session.request_slot_spin(_slot_bet):
		_slot_waiting = false
		return false
	_slot_message.text = ""
	if _slot_show != null:
		_slot_show.play("lever")
	_refresh_slot()
	return true


func _on_slot_result(peer_id: int, bet: int, gain: int, reels: PackedInt32Array, pot: int) -> void:
	var mine := peer_id == _local_id() and is_slot_open()
	var who := "나" if peer_id == _local_id() else "P%d" % peer_id
	var tier := OfficeSlot.tier_of(reels)
	var outcome := "당첨! +%d" % gain if gain > 0 else ("본전" if gain == 0 else "꽝  %d" % gain)
	var text := "%s%s: %d 걸고 %s" % [["", "소스 둘 · ", "황금 둘! ", "소스 셋! ", "황금 셋!! "][tier], who, bet, outcome]
	if pot > 0:
		text += "  (잭팟 %d 포함)" % pot
	# 사무실에 놓인 기계는 누가 돌렸든 움직인다. 내 화면으로 보는 판은 기계 소리를 겹치지 않는다.
	if _slot_show != null:
		_slot_show.spin(reels, mine)
	if not mine:
		# 남이 돌린 것, 또는 화면을 닫은 뒤에 온 결과: 한 줄로만 알린다. 황금 셋은 모두에게 크게.
		if is_slot_open() and not _slot_waiting:
			_slot_message.text = text
		if tier == 4:
			var shout := create_tween()
			shout.tween_interval(OfficeSlot.stop_times(reels)[2])
			shout.tween_callback(_announce.bind("%s 잭팟!  +%d" % [who, gain], 5.0))
		_refresh_slot()
		return
	_slot_spinning = {"reels": reels, "text": text, "tier": tier, "gain": gain, "pot": pot,
		"elapsed": 0.0, "stopped": 0, "ticks": 0}


func _process(delta: float) -> void:
	if _slot_announce_left > 0.0:
		_slot_announce_left -= delta
		if _slot_announce_left <= 0.0 and _slot_announce != null:
			_slot_announce.visible = false
	if _slot_spinning.is_empty() or not is_slot_open():
		return
	# 세 칸이 돌다가 왼쪽부터 하나씩 멈춘다. 앞의 두 칸이 같으면 마지막 칸은 느려지며 한참 끈다.
	_slot_spinning.elapsed += delta
	var elapsed: float = _slot_spinning.elapsed
	var reels: PackedInt32Array = _slot_spinning.reels
	var stops := OfficeSlot.stop_times(reels)
	var stopped := 0
	for index in 3:
		if elapsed >= stops[index]:
			_slot_reels[index].symbol = reels[index]
			stopped += 1
		else:
			_slot_reels[index].symbol = (index + OfficeSlot.spin_ticks(index, reels, elapsed)) \
				% OfficeSlot.SYMBOLS.size()
	var ticks := OfficeSlot.spin_ticks(2, reels, elapsed)
	if ticks != int(_slot_spinning.ticks) and stopped < 3:
		_slot_spinning.ticks = ticks
		# 빨리 돌 때는 두 칸에 한 번, 끄는 동안은 칸마다 딸깍.
		if _slot_show != null and (stopped == 2 or ticks % 2 == 0):
			_slot_show.play("tick")
	if stopped > int(_slot_spinning.stopped):
		for index in range(int(_slot_spinning.stopped), stopped):
			_pop_reel(_slot_reels[index])
		_slot_spinning.stopped = stopped
		if _slot_show != null:
			_slot_show.play("stop")
	if stopped == 3:
		_finish_slot_spin()


## 칸이 멈출 때 통이 한 번 튄다.
func _pop_reel(bottle: SauceBottle) -> void:
	bottle.pivot_offset = bottle.size * 0.5
	bottle.scale = Vector2.ONE * 1.28
	create_tween().tween_property(bottle, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 세 칸이 다 멈췄다: 결과를 알리고, 돈이 세어 올라가고, 등급에 맞게 터진다.
func _finish_slot_spin() -> void:
	var spin := _slot_spinning
	_slot_spinning = {}
	var tier: int = spin.tier
	_slot_message.text = spin.text
	_slot_message.add_theme_color_override("font_color",
		UI.MUTED if tier == 0 else (UI.MINT if tier == 1 else UI.GOLD))
	if _slot_show != null:
		_slot_show.play(OfficeSlotShow.TIER_SFX[tier])
	_slot_waiting = false
	_count_slot_money([0.25, 0.5, 0.9, 1.1, 2.2][tier])
	if tier >= 2:
		_celebrate_slot(tier, int(spin.pot))
	_refresh_slot()


## 화면의 돈과 잭팟이 지금 값까지 세어 올라간다(내려간다).
func _count_slot_money(seconds: float) -> void:
	if _slot_count_tween != null:
		_slot_count_tween.kill()
	_slot_count_tween = create_tween().set_parallel(true)
	_slot_count_tween.tween_method(func(value: float):
		_slot_shown_money = roundi(value)
		_write_slot_money(), float(_slot_shown_money), float(session.team_money), seconds)
	_slot_count_tween.tween_method(func(value: float):
		_slot_shown_jackpot = roundi(value)
		_write_slot_money(), float(_slot_shown_jackpot), float(session.team_jackpot), seconds)


func _write_slot_money() -> void:
	if is_slot_open():
		_slot_money.text = "팀 돈  %d" % _slot_shown_money
		_slot_jackpot.text = "잭팟  %d" % _slot_shown_jackpot


## 2배 이상: 화면이 번쩍이고 동전이 쏟아지고 큰 글자가 튀어나온다. 등급이 높을수록 크고 길다.
func _celebrate_slot(tier: int, pot: int) -> void:
	var view := get_viewport().get_visible_rect().size
	_slot_flash.color = Color(1.0, 0.82, 0.3, [0.0, 0.0, 0.32, 0.45, 0.75][tier])
	create_tween().tween_property(_slot_flash, "color:a", 0.0, [0.0, 0.0, 0.5, 0.7, 1.4][tier])
	_slot_coins.position = view * Vector2(0.5, 0.58)
	_slot_coins.amount = [1, 1, 40, 80, 240][tier]
	_slot_coins.lifetime = 2.6 if tier == 4 else 1.7
	_slot_coins.restart()
	_slot_coins.emitting = true
	_slot_banner.text = ["", "", "2배!", "4배!", "잭팟!  10배"][tier]
	if pot > 0:
		_slot_banner.text += "\n+ 잭팟 %d" % pot
	_slot_banner.pivot_offset = view * 0.5
	_slot_banner.scale = Vector2.ONE * 0.3
	_slot_banner.modulate.a = 1.0
	_slot_banner.visible = true
	var pop := create_tween()
	pop.tween_property(_slot_banner, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_interval(2.4 if tier == 4 else 0.9)
	pop.tween_property(_slot_banner, "modulate:a", 0.0, 0.35)
	pop.tween_callback(func(): _slot_banner.visible = false)


## 사무실 화면 위쪽에 잠깐 뜨는 알림(누군가 황금 셋을 터뜨렸을 때).
func _announce(message: String, seconds: float) -> void:
	if _slot_announce == null:
		return
	_slot_announce.text = message
	_slot_announce.visible = true
	_slot_announce_left = seconds


func _refresh_slot() -> void:
	if not is_slot_open() or session == null:
		return
	_slot_bet = clampi(_slot_bet, 1, maxi(session.team_money, 1))
	# 돌아가는 중이거나 세어 올라가는 중이면 화면의 금액은 그쪽이 쥐고 있다.
	if not _slot_waiting and (_slot_count_tween == null or not _slot_count_tween.is_running()):
		_slot_shown_money = session.team_money
		_slot_shown_jackpot = session.team_jackpot
	_write_slot_money()
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
	sub.text = "황금 소스통 셋 10배 · 같은 소스 셋 4배 · 황금 둘 2배 · 같은 소스 둘 1.1배 · 다 다르면 꽝.\n팀 공용 돈을 겁니다."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UI.MUTED)
	column.add_child(sub)
	var reels := HBoxContainer.new()
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	reels.add_theme_constant_override("separation", 12)
	column.add_child(reels)
	for index in 3:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(130.0, 150.0)
		reels.add_child(cell)
		var bottle := SauceBottle.new()
		bottle.symbol = index
		cell.add_child(bottle)
		_slot_reels.push_back(bottle)
	_slot_message = Label.new()
	_slot_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_message.add_theme_font_size_override("font_size", 20)
	column.add_child(_slot_message)
	_slot_jackpot = Label.new()
	_slot_jackpot.add_theme_color_override("font_color", UI.GOLD)
	_slot_jackpot.add_theme_font_size_override("font_size", 24)
	column.add_child(_slot_jackpot)
	_slot_money = Label.new()
	_slot_money.add_theme_color_override("font_color", UI.MINT)
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
	_slot_flash = ColorRect.new()
	_slot_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_flash.color = Color(1.0, 0.82, 0.3, 0.0)
	_slot_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_layer.add_child(_slot_flash)
	_slot_coins = CPUParticles2D.new()
	_slot_coins.emitting = false
	_slot_coins.one_shot = true
	_slot_coins.explosiveness = 0.8
	_slot_coins.direction = Vector2.UP
	_slot_coins.spread = 70.0
	_slot_coins.initial_velocity_min = 320.0
	_slot_coins.initial_velocity_max = 780.0
	_slot_coins.gravity = Vector2(0.0, 1300.0)
	_slot_coins.scale_amount_min = 7.0
	_slot_coins.scale_amount_max = 13.0
	_slot_coins.color = UI.GOLD
	_slot_layer.add_child(_slot_coins)
	_slot_banner = Label.new()
	_slot_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slot_banner.add_theme_font_size_override("font_size", 84)
	_slot_banner.add_theme_color_override("font_color", Color("fff3c4"))
	_slot_banner.add_theme_color_override("font_outline_color", Color("7a3b12"))
	_slot_banner.add_theme_constant_override("outline_size", 18)
	_slot_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_banner.visible = false
	_slot_layer.add_child(_slot_banner)


## 방장이 지도에서 축제를 고른다. 팀원이 누른 것은 아무 일도 하지 않는다.
func pick_stage(stage_id: String) -> void:
	if session != null:
		session.set_selected_stage(stage_id)
	_refresh_map()


func _can_add_bots() -> bool:
	return session != null and not session.is_online() and session.selected_stage == "stage_2"


func _pick_bot_count(count: int) -> void:
	if _can_add_bots():
		practice_bot_count = count
		_refresh_panel(session.seat_assignments())


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
	_slot_show = OfficeSlotShow.new()
	_slot_show.name = "SlotShow"
	add_child(_slot_show)
	_slot_show.setup(_room)
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
	hint.text = "WASD 이동 · Space 점프 · E 상호작용 · Esc 메뉴\n축제 지도에서 출격 준비\n모두 출발 구역에 올라서면 출발"
	if DEBUG_MONEY_STEP > 0:
		hint.text += "\n[디버그] %s: 팀 돈 +%d" % [OS.get_keycode_string(DEBUG_MONEY_KEY), DEBUG_MONEY_STEP]
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
	_slot_announce = Label.new()
	_slot_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_announce.add_theme_font_size_override("font_size", 38)
	_slot_announce.add_theme_color_override("font_color", Color("fff3c4"))
	_slot_announce.add_theme_color_override("font_outline_color", Color("7a3b12"))
	_slot_announce.add_theme_constant_override("outline_size", 10)
	_slot_announce.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slot_announce.position = Vector2(-400.0, 150.0)
	_slot_announce.size = Vector2(800.0, 54.0)
	_slot_announce.visible = false
	layer.add_child(_slot_announce)
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
		_screen_label.text = "축제 지도\n▶ %s\n[E] 지도 열기" % stage_name
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
	var slot_sign := _room.get_node_or_null("SlotMachine/Label") as Label3D
	if slot_sign != null:
		slot_sign.text = "슬롯머신\n잭팟 %d" % session.team_jackpot
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
	if _can_add_bots() and practice_bot_count > 0:
		lines.push_back("연습 봇 %d명 · 출발 시 합류" % practice_bot_count)
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
	_map_subtitle = Label.new()
	_map_subtitle.add_theme_color_override("font_color", UI.MUTED)
	column.add_child(_map_subtitle)
	_map_bots = HBoxContainer.new()
	_map_bots.add_theme_constant_override("separation", 10)
	column.add_child(_map_bots)
	var bot_label := UI.eyebrow("연습 봇")
	bot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_map_bots.add_child(bot_label)
	var bot_group := ButtonGroup.new()
	for count in range(MayoNet.MAX_CLIENTS + 1):
		var button := Button.new()
		button.text = "%d명" % count
		button.toggle_mode = true
		button.button_group = bot_group
		button.custom_minimum_size.y = 42.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_pick_bot_count.bind(count))
		_map_bots.add_child(button)
		_map_bot_buttons.append(button)
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
	_map_bots.visible = _can_add_bots()
	for count in _map_bot_buttons.size():
		_map_bot_buttons[count].set_pressed_no_signal(count == practice_bot_count)
	_map_subtitle.text = "갈 축제를 고르세요." if session.is_server() else "방장이 갈 축제를 고릅니다."
	if not session.is_online() and not _map_bots.visible:
		_map_subtitle.text = "연습 봇은 토마티나에서 추가할 수 있습니다."
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


## 슬롯머신 한 칸: 소스통 하나를 그린다. `symbol`은 `OfficeSlot.SYMBOLS` 번호.
## 짜는 통 모양 -- 뾰족한 뚜껑, 어깨, 몸통, 가운데 띠지 -- 에 소스마다 색과 띠지 그림이 다르다.
class SauceBottle extends Control:
	var symbol := 0:
		set(value):
			symbol = value
			queue_redraw()

	var _origin := Vector2.ZERO
	var _unit := 1.0

	## 통 그림 좌표(가로 가운데가 0, 뚜껑 끝이 세로 0, 통 높이 약 118)를 화면 좌표로.
	func _at(x: float, y: float) -> Vector2:
		return _origin + Vector2(x, y) * _unit

	func _draw() -> void:
		var body: Color = OfficeSlot.SYMBOL_COLORS[symbol]
		var cap: Color = OfficeSlot.SYMBOL_CAPS[symbol]
		var shade := body.darkened(0.22)
		var unit := minf(size.x / 100.0, size.y / 150.0)
		var origin := Vector2(size.x * 0.5, size.y * 0.5 - 68.0 * unit)
		_origin = origin
		_unit = unit
		# 뚜껑: 뾰족한 노즐과 그 밑동.
		draw_colored_polygon(PackedVector2Array([_at(-4, 0), _at(4, 0), _at(9, 22), _at(-9, 22)]), cap)
		draw_rect(Rect2(_at(-13, 22), Vector2(26, 9) * unit), cap.darkened(0.12))
		# 어깨와 몸통.
		draw_colored_polygon(PackedVector2Array([_at(-13, 31), _at(13, 31), _at(27, 52), _at(-27, 52)]), body)
		var trunk := StyleBoxFlat.new()
		trunk.bg_color = body
		trunk.set_corner_radius_all(int(9.0 * unit))
		trunk.corner_radius_top_left = 0
		trunk.corner_radius_top_right = 0
		draw_style_box(trunk, Rect2(_at(-27, 51), Vector2(54, 67) * unit))
		# 오른쪽 그늘과 왼쪽 반사광.
		draw_rect(Rect2(_at(17, 54), Vector2(10, 56) * unit), shade)
		draw_rect(Rect2(_at(-22, 56), Vector2(5, 50) * unit), body.lightened(0.35))
		# 띠지와 그 위의 그림.
		var label := Color("fff8ea") if symbol != 2 else Color("5b8fc2")
		draw_rect(Rect2(_at(-27, 68), Vector2(54, 30) * unit), label)
		var mark := _at(0, 83)
		if symbol == 0:
			# 케찹: 토마토.
			draw_circle(mark, 10.0 * unit, Color("c2433a"))
			draw_rect(Rect2(mark + Vector2(-5, -13) * unit, Vector2(10, 4) * unit), Color("4f9a55"))
		elif symbol == 1:
			# 머스터드: 겨자씨 세 알.
			for offset in [Vector2(-10, 3), Vector2(0, -4), Vector2(10, 3)]:
				draw_circle(mark + offset * unit, 5.0 * unit, Color("b9872a"))
		elif symbol == 2:
			# 마요네즈: 달걀.
			draw_circle(mark, 11.0 * unit, Color("fff8ea"))
			draw_circle(mark, 5.0 * unit, Color("f0b93a"))
		else:
			# 황금 소스통: 별.
			var star := PackedVector2Array()
			for point in 10:
				var reach := (12.0 if point % 2 == 0 else 5.0) * unit
				var angle := -PI * 0.5 + TAU * point / 10.0
				star.append(mark + Vector2(cos(angle), sin(angle)) * reach)
			draw_colored_polygon(star, Color("c2433a"))
		var caption: String = OfficeSlot.SYMBOLS[symbol]
		var font := ThemeDB.fallback_font
		var text_size := int(13.0 * unit)
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size).x
		draw_string(font, Vector2(size.x * 0.5 - width * 0.5, origin.y + 138.0 * unit), caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, text_size, Color("d8dfe3"))


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
