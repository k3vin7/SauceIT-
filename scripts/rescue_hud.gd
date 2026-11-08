class_name RescueHud
extends Control

## What a downed player and the player about to pick them up are told.
##
## Before this, going down on the Tomatina stage put nothing on the screen at
## all: the body lay there, the camera stayed where it was, and whether a
## teammate was coming, how long there was to wait, or that [E] beside the body
## did anything was known only to whoever had read the code. The rescue is a
## pair of facts -- a clock on the downed side and a one-second hold on the
## standing side -- and both are drawn here, off `world.rescue_hud_state()`.
##
## **Downed:** a banner, the seconds left before the checkpoint takes them, a
## bar of that time running out, and the crawl hint once the body can move. If
## a teammate is already on them the clock gives way to the rescue's own bar.
## If nobody is left standing the banner says so: there is no rescue to wait
## for, only the respawn.
##
## **Standing:** a tag over every downed teammate with their clock on it, so
## the one with least time left is the one you run to; a prompt when you are in
## reach; the hold's own bar while you are on them.
##
## Drawn off the view frame, not the window, so it sits inside the letterbox.

const BANNER_SIZE := 40
const LINE_SIZE := 20
const TAG_SIZE := 16
const BAR := Vector2(360.0, 14.0)
const TAG_LIFT := 1.3
const TAG_DRAW_RANGE := 40.0

const BACKING := Color(0.04, 0.05, 0.06, 0.78)
const EDGE := Color(0.86, 0.90, 0.94, 0.5)
const DOWN := Color("ff6a5a")
const WAIT := Color("fff0a8")
const RESCUE := Color("6fd38a")
const SHADOW := Color(0.0, 0.0, 0.0, 0.75)

var world: Node3D
var frame := Rect2()


func _ready() -> void:
	name = "RescueHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_frame(new_frame: Rect2) -> void:
	frame = new_frame
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or frame.size.x <= 0.0:
		return
	var state: Dictionary = world.rescue_hud_state()
	if state.is_empty():
		return
	if state.get("downed", false):
		_draw_downed(state)
	else:
		_draw_standing(state)


func _draw_downed(state: Dictionary) -> void:
	var centre := frame.get_center()
	_text(Vector2(centre.x, centre.y - 70.0), "쓰러졌다", BANNER_SIZE, DOWN)
	var line := ""
	var fraction := 0.0
	var colour := WAIT
	if state.get("rescue_progress", -1.0) >= 0.0:
		line = "구조 중…"
		fraction = float(state["rescue_progress"])
		colour = RESCUE
	elif state.get("standing_teammate", false):
		line = "구조 대기 %d초" % ceili(float(state.get("left", 0.0)))
		fraction = float(state.get("left", 0.0)) / maxf(float(state.get("window", 1.0)), 0.001)
	else:
		line = "팀 전원 쓰러짐 · 체크포인트로 복귀"
		fraction = 0.0
		colour = DOWN
	_text(Vector2(centre.x, centre.y - 28.0), line, LINE_SIZE, colour)
	var bar := Rect2(Vector2(centre.x - BAR.x * 0.5, centre.y - 10.0), BAR)
	_bar(bar, fraction, colour)
	if state.get("crawling", false):
		_text(Vector2(centre.x, centre.y + 32.0), "WASD · 팀원 쪽으로 기어가기", LINE_SIZE, WAIT)


func _draw_standing(state: Dictionary) -> void:
	var camera := world.get("_camera") as Camera3D
	var downed: Array = state.get("downed_teammates", [])
	if camera != null and is_instance_valid(camera):
		for entry in downed:
			var at: Vector3 = entry["position"] + Vector3.UP * TAG_LIFT
			if camera.is_position_behind(at) \
					or camera.global_position.distance_to(at) > TAG_DRAW_RANGE:
				continue
			var screen := camera.unproject_position(at)
			if not frame.has_point(screen):
				continue
			var tag := "쓰러진 팀원 · %d초" % ceili(float(entry["left"]))
			if entry.get("in_reach", false):
				tag = "[E] 구조 · %d초" % ceili(float(entry["left"]))
			_text(screen, tag, TAG_SIZE, RESCUE if entry.get("in_reach", false) else DOWN)
	var centre := frame.get_center()
	if state.get("rescue_progress", -1.0) >= 0.0:
		_text(Vector2(centre.x, centre.y + 70.0), "구조 중 · 가만히", LINE_SIZE, RESCUE)
		var bar := Rect2(Vector2(centre.x - BAR.x * 0.5, centre.y + 84.0), BAR)
		_bar(bar, float(state["rescue_progress"]), RESCUE)
	elif state.get("in_reach", false):
		_text(Vector2(centre.x, centre.y + 70.0), "[E] 구조 (1초, 사격·이동 금지)", LINE_SIZE, RESCUE)


func _text(at: Vector2, text: String, size: int, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var origin := Vector2(at.x - width * 0.5, at.y)
	draw_string(font, origin + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, SHADOW)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, colour)


func _bar(rect: Rect2, fraction: float, colour: Color) -> void:
	draw_rect(rect, BACKING)
	var fill := Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y))
	if fill.size.x > 0.0:
		draw_rect(fill, colour)
	draw_rect(rect, EDGE, false, 1.0)
