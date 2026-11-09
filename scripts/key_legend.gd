extends Control

const UI := preload("res://scripts/sauce_ui.gd")

## The keys, on screen, with the state of the ones that toggle.
##
## Every switch in this prototype is a key and nothing on screen says so, which
## is fine while you are the person who added it and useless a day later. It
## lists the key, what it does, and -- for anything with two states -- which
## state it is in, so `M` reads as "sound: off" rather than as a key you have to
## press to find out.
##
## Drawn off the view frame rather than the window, like the bars and the map,
## so it sits inside the letterbox instead of under it.
##
## `F4` hides it. It is a development aid and it is meant to be turned off once
## the keys are in the hands.

const MARGIN := 18.0
const LINE_HEIGHT := 19.0
const KEY_COLUMN := 52.0
const PADDING := Vector2(12.0, 9.0)

const KEY_COLOUR := UI.GOLD
const LABEL_COLOUR := UI.CREAM

var world: Node
var _frame := Rect2()
var _font: Font
var _font_size := 13
var _plate := UI.box(Color(0.07, 0.11, 0.14, 0.93), UI.EDGE, 10)


func _ready() -> void:
	name = "KeyLegend"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size


func set_frame(frame: Rect2) -> void:
	_frame = frame
	queue_redraw()


## Redrawn every frame rather than on a signal: half of what it shows is live
## state, and there is no one signal that covers a camera mode, a mute and a
## debug overlay.
func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## key, what it does, and either "" for a plain key or the state it is in.
func _rows() -> Array:
	var rows := [
		["WASD", "이동", ""],
		["Shift", "달리기", ""],
		["Space", "점프", ""],
		["좌클릭", "소스 분사", ""],
		["1~5 / 휠", "장비 선택", ""],
		["E", "토마토 줍기", ""],
		["Shift+1~3", "보급 지점에서 소스 보충", ""],
		["R", "고글 닦기", ""],
		["C", "캐릭터 전환", ""],
	]
	if world == null or not is_instance_valid(world):
		return rows
	if world.map_kind == world.MapKind.TOMATINA:
		return [
			["WASD", "이동", ""], ["Shift", "달리기", ""], ["Space", "점프", ""],
			["좌클릭", "소스 분사 / 토마토 던지기", ""], ["우클릭", "토마토 먹기", ""],
			["1~5 / 휠", "장비 선택", ""], ["E", "가까운 대상과 상호작용", ""],
			["Shift+3", "보급 지점에서 케첩 보충", ""], ["R", "고글 닦기", ""],
			["V", "밀치기", ""], ["F4", "조작표 닫기", ""], ["Esc", "일시 정지", ""],
		]
	if world._local != null:
		rows[8][2] = world.character_name_for(world._local)
	rows.append(["F1", "카메라", "1인칭" if world._first_person else "3인칭"])
	var panel_open: bool = world._net_panel != null and world._net_panel.visible
	rows.append(["F2", "연결 메뉴", "열림" if panel_open else "닫힘"])
	rows.append(["F3", "적 감지 범위", "켜짐" if world.show_enemy_sight else "꺼짐"])
	rows.append(["F4", "조작표 닫기", ""])
	rows.append(["M", "소리", "음소거" if world.muted else "켜짐"])
	rows.append(["Esc", "일시 정지", ""])
	return rows


func _draw() -> void:
	if _font == null:
		return
	var rows := _rows()
	var widest := 0.0
	var key_width := float(KEY_COLUMN)
	for row in rows:
		key_width = maxf(key_width, _font.get_string_size(str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x + 12.0)
		var text: String = row[1]
		if row[2] != "":
			text += ": " + str(row[2])
		widest = maxf(widest, _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x)
	var size := Vector2(key_width + widest + PADDING.x * 2.0,
		float(rows.size()) * LINE_HEIGHT + PADDING.y * 2.0 + 24.0)
	# Bottom left of the view frame: the bars own the bottom middle and the map
	# owns the top right.
	var frame := _frame if _frame.size.x > 1.0 else Rect2(Vector2.ZERO, get_viewport_rect().size)
	var at := Vector2(frame.position.x + MARGIN,
		frame.position.y + frame.size.y - size.y - MARGIN)
	var box := Rect2(at, size)
	draw_style_box(_plate, box)
	draw_string(_font, at + Vector2(PADDING.x, 21.0), "조작표",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, UI.MINT)
	var baseline := at + PADDING + Vector2(0.0, _font.get_ascent(_font_size) + 24.0)
	for row in rows:
		draw_string(_font, baseline, str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_font_size, KEY_COLOUR)
		var label: String = row[1]
		if row[2] != "":
			label += " · " + str(row[2])
		draw_string(_font, baseline + Vector2(key_width, 0.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, LABEL_COLOUR)
		baseline.y += LINE_HEIGHT
