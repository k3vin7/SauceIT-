extends PanelContainer
## Each peer presents its own briefing after the entrance, including late joins.
const DISPLAY_SECONDS := 10.0
## Space between the mission card and the radio under it, and the narrowest the
## radio is drawn when the card is narrower.
const GAP := 8.0
const MIN_WIDTH := 300.0
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
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var speaker := Label.new()
	speaker.text = "소세지 박사 · 무전"
	speaker.add_theme_color_override("font_color", Color("efc86b"))
	speaker.add_theme_font_size_override("font_size", 15)
	column.add_child(speaker)
	var message := Label.new()
	message.text = MESSAGE
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
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
	# The radio sits on the left, just under the mission card, as wide as it.
	var frame: Rect2 = world._view_layout
	var card: Control = world.get("_objective_card")
	if is_instance_valid(card) and card.visible:
		position = card.position + Vector2(0.0, card.size.y + GAP)
		size.x = maxf(card.size.x, MIN_WIDTH)
	else:
		position = frame.position + Vector2(20.0, 18.0)
		size.x = minf(MIN_WIDTH, frame.size.x - 40.0)
	size.y = 0.0
