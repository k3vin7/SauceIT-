extends PanelContainer
## Each peer presents its own briefing after the entrance, including late joins.
const DISPLAY_SECONDS := 10.0
const MESSAGE := "저 갑옷부터 벗겨야 해요! 호스로 보스의 갑옷을 씻어내세요.\n갑옷이 벗겨지면 드러난 약점에 소스를 쏘세요!"
var world
var seen_boss_id := 0
var remaining := 0.0

func _ready() -> void:
	name = "BossDoctorMessage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://scripts/sauce_ui.gd").theme()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172a32ed")
	style.border_color = Color("efc86b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var speaker := Label.new()
	speaker.text = "소세지 박사 · 무전"
	speaker.add_theme_color_override("font_color", Color("efc86b"))
	speaker.add_theme_font_size_override("font_size", 21)
	column.add_child(speaker)
	var message := Label.new()
	message.text = MESSAGE
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 19)
	column.add_child(message)
	hide()

func _process(delta: float) -> void:
	if not is_instance_valid(world): return
	var boss = world._press_king
	if not is_instance_valid(boss):
		seen_boss_id = 0
		remaining = 0
		hide()
		return
	if not boss.is_alive():
		remaining = 0
		hide()
		return
	if world.is_cinematic_active() or not world._input_enabled:
		hide()
		return
	if seen_boss_id != boss.get_instance_id():
		seen_boss_id = boss.get_instance_id()
		remaining = DISPLAY_SECONDS
	remaining = maxf(0, remaining-delta)
	visible = remaining > 0
	var frame: Rect2 = world._view_layout
	position = frame.position + Vector2(20, frame.size.y * 0.24)
	size.x = minf(490, frame.size.x-40)
