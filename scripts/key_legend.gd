extends Control

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

const BACKING := Color(0.04, 0.05, 0.06, 0.72)
const EDGE := Color(0.86, 0.90, 0.94, 0.22)
const KEY_COLOUR := Color("ffe9a8")
const LABEL_COLOUR := Color(0.88, 0.91, 0.94, 0.92)
## What a toggle currently reads as: on is worth noticing, off is not.
const STATE_ON := Color("7fd4a0")
const STATE_OFF := Color(0.62, 0.66, 0.70, 0.85)

var world: Node
var _frame := Rect2()
var _font: Font
var _font_size := 13


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
		["WASD", "move", ""],
		["Shift", "run", ""],
		["Space", "jump", ""],
		["LMB", "spray", ""],
		["E", "refill at a stall", ""],
		["R", "wipe your glasses", ""],
	]
	if world == null or not is_instance_valid(world):
		return rows
	rows.append(["F1", "camera", "first person" if world._first_person else "over the shoulder"])
	var panel_open: bool = world._net_panel != null and world._net_panel.visible
	rows.append(["F2", "LAN panel", "open" if panel_open else "closed"])
	rows.append(["F3", "enemy sight rings", "on" if world.show_enemy_sight else "off"])
	rows.append(["F4", "this list", "on"])
	rows.append(["M", "sound", "muted" if world.muted else "on"])
	rows.append(["Esc", "quit", ""])
	return rows


func _draw() -> void:
	if _font == null:
		return
	var rows := _rows()
	var widest := 0.0
	for row in rows:
		var text: String = row[1]
		if row[2] != "":
			text += ": " + str(row[2])
		widest = maxf(widest, _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x)
	var size := Vector2(KEY_COLUMN + widest + PADDING.x * 2.0,
		float(rows.size()) * LINE_HEIGHT + PADDING.y * 2.0)
	# Bottom left of the view frame: the bars own the bottom middle and the map
	# owns the top right.
	var frame := _frame if _frame.size.x > 1.0 else Rect2(Vector2.ZERO, get_viewport_rect().size)
	var at := Vector2(frame.position.x + MARGIN,
		frame.position.y + frame.size.y - size.y - MARGIN)
	var box := Rect2(at, size)
	draw_rect(box, BACKING, true)
	draw_rect(box, EDGE, false, 1.0)

	var baseline := at + PADDING + Vector2(0.0, _font.get_ascent(_font_size))
	for row in rows:
		draw_string(_font, baseline, str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_font_size, KEY_COLOUR)
		var label: String = row[1]
		draw_string(_font, baseline + Vector2(KEY_COLUMN, 0.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, LABEL_COLOUR)
		if row[2] != "":
			var state := str(row[2])
			var used := _font.get_string_size(label + ": ", HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, _font_size).x
			var lit := state == "on" or state == "open"
			draw_string(_font, baseline + Vector2(KEY_COLUMN, 0.0),
				label + ": ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, LABEL_COLOUR)
			draw_string(_font, baseline + Vector2(KEY_COLUMN + used, 0.0), state,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size,
				STATE_ON if lit else STATE_OFF)
		baseline.y += LINE_HEIGHT
