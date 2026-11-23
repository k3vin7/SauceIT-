class_name StageArrival
extends CanvasLayer

## 도착 연출: 축제 현장 위에서 내려와 플레이어 시점으로 이어지는 짧은 카메라 이동.
##
## 스테이지가 전부 불러와지고 모두가 준비된 뒤(`play_authorized`)에 시작한다. 연출 동안
## 조작은 막혀 있고, 끝나면(`finished`) 앱이 조작을 풀어 준다. 건너뛰기는 방장만 하고
## 전원에게 적용된다 -- 여기서는 키만 받아 `skip_requested`로 알리고, 실제로 끝내는 것은
## 세션(`MayoNet.intro_skipped`)을 거쳐 온 `finish()`다.

signal finished
signal skip_requested

const UI := preload("res://scripts/sauce_ui.gd")

const DURATION := 6.5
const FADE_SECONDS := 0.7
## 시작 지점: 플레이어 조금 앞, 지붕보다 한참 위. 출발 지점 앞은 트인 광장이라 그 위에서
## 곧게 내려오면 건물을 뚫지 않는다(뒤쪽에서 내려오면 출발 지점 뒤 지붕에 걸린다).
const START_AHEAD := 5.0
const START_HEIGHT := 21.0
const START_LOOK_AHEAD := 46.0
const BAR_HEIGHT := 74.0

var world: Node
var can_skip := false
var active := false

var _camera: Camera3D
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _clock := 0.0
var _fade: ColorRect


func _init() -> void:
	name = "StageArrivalUI"
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS


## `stage_name`은 화면 아래에 뜨는 자막. 월드가 연출을 지원하지 않으면 곧바로 끝난다.
func begin(stage_world: Node, stage_name: String, may_skip: bool) -> void:
	world = stage_world
	can_skip = may_skip
	if world == null or not world.has_method("arrival_view_transform"):
		call_deferred("finish")
		return
	_to = world.call("arrival_view_transform")
	var forward := -_to.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var start := _to.origin + forward * START_AHEAD + Vector3.UP * START_HEIGHT
	_from = Transform3D(Basis(), start).looking_at(
		_to.origin + forward * START_LOOK_AHEAD, Vector3.UP)
	_camera = Camera3D.new()
	_camera.name = "ArrivalCamera"
	_camera.fov = 62.0
	_camera.near = 0.05
	world.add_child(_camera)
	_camera.global_transform = _from
	_camera.make_current()
	world.call("set_arrival_view", true)
	_build_overlay(stage_name)
	active = true


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	var t := clampf(_clock / DURATION, 0.0, 1.0)
	# 처음엔 천천히 둘러보고, 뒤로 갈수록 빨리 내려앉는다.
	var eased := t * t * (3.0 - 2.0 * t)
	if is_instance_valid(_camera):
		_camera.global_transform = _from.interpolate_with(_to, eased)
	if _fade != null:
		_fade.color.a = clampf(1.0 - _clock / FADE_SECONDS, 0.0, 1.0)
	if t >= 1.0:
		finish()


func _unhandled_input(event: InputEvent) -> void:
	if not active or not can_skip:
		return
	if event.is_action_pressed("ui_accept") or (InputMap.has_action("jump")
			and event.is_action_pressed("jump")):
		skip_requested.emit()
		get_viewport().set_input_as_handled()


## 연출을 끝내고 화면을 게임 카메라에 돌려준다. 여러 번 불러도 한 번만 일한다.
func finish() -> void:
	var was_active := active
	active = false
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null
	if was_active and is_instance_valid(world):
		world.call("set_arrival_view", false)
	if not is_queued_for_deletion():
		finished.emit()
		queue_free()


func _build_overlay(stage_name: String) -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = BAR_HEIGHT
		else:
			bar.offset_top = -BAR_HEIGHT
		add_child(bar)
	var caption := Label.new()
	caption.theme = UI.theme()
	caption.text = "%s  ·  현장 도착" % stage_name
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", UI.CREAM)
	caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	caption.offset_left = 40.0
	caption.offset_top = -BAR_HEIGHT + 18.0
	caption.offset_bottom = -18.0
	caption.offset_right = 900.0
	add_child(caption)
	var hint := Label.new()
	hint.theme = UI.theme()
	hint.text = "Space · 건너뛰기" if can_skip else "방장이 건너뛸 수 있습니다"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", UI.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -420.0
	hint.offset_right = -40.0
	hint.offset_top = -BAR_HEIGHT + 22.0
	hint.offset_bottom = -18.0
	add_child(hint)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
