extends RefCounted

const INK := Color("111a20")
const PANEL := Color("202d35")
const PANEL_RAISED := Color("2b3b44")
const EDGE := Color("43545b")
const CREAM := Color("fff2dd")
const MUTED := Color("b7c5c5")
const ACCENT := Color("ff8065")
const MINT := Color("85dac0")
const GOLD := Color("f5cc77")
const SHADE := Color(0.04, 0.065, 0.08, 0.79)

static var _theme: Theme


static func box(color: Color, border := Color.TRANSPARENT, radius := 10, padding := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.60
	style.content_margin_bottom = padding * 0.60
	return style


static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 17
	_theme.set_color("font_color", "Label", CREAM)
	_theme.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 14))
	_theme.set_stylebox("panel", "PopupMenu", box(PANEL, EDGE, 8, 8.0))
	_theme.set_stylebox("hover", "PopupMenu", box(PANEL_RAISED, EDGE, 6, 8.0))
	for type in ["Button", "OptionButton"]:
		_theme.set_stylebox("normal", type, box(PANEL_RAISED, EDGE, 8, 14.0))
		_theme.set_stylebox("hover", type, box(Color("384c55"), MINT, 8, 14.0))
		_theme.set_stylebox("pressed", type, box(INK, MINT, 8, 14.0))
		_theme.set_stylebox("disabled", type, box(Color("26333a"), Color("34444a"), 8, 14.0))
		_theme.set_stylebox("focus", type, box(Color.TRANSPARENT, GOLD, 8))
		_theme.set_color("font_color", type, CREAM)
		_theme.set_color("font_hover_color", type, CREAM)
		_theme.set_color("font_pressed_color", type, CREAM)
		_theme.set_color("font_focus_color", type, CREAM)
		_theme.set_color("font_disabled_color", type, Color("94a5aa"))
	_theme.set_stylebox("normal", "LineEdit", box(INK, EDGE, 8, 12.0))
	_theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, MINT, 8))
	_theme.set_color("font_color", "LineEdit", CREAM)
	_theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	_theme.set_color("font_color", "PopupMenu", CREAM)
	_theme.set_color("font_hover_color", "PopupMenu", CREAM)
	_theme.set_stylebox("slider", "HSlider", box(INK, EDGE, 6, 5.0))
	_theme.set_stylebox("grabber_area", "HSlider", box(MINT, Color.TRANSPARENT, 6, 5.0))
	_theme.set_stylebox("grabber_area_highlight", "HSlider", box(MINT.lightened(0.18), Color.TRANSPARENT, 6, 5.0))
	return _theme


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(ACCENT, Color.TRANSPARENT, 8, 14.0))
	button.add_theme_stylebox_override("hover", box(Color("ff9a80"), Color.TRANSPARENT, 8, 14.0))
	button.add_theme_stylebox_override("pressed", box(Color("e46f58"), Color.TRANSPARENT, 8, 14.0))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)


static func eyebrow(text_value: String, tint := MINT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", 14)
	return label


class TitleBackdrop extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), INK)
		var mark := size * Vector2(0.36, 0.47)
		var scale_factor := minf(size.x, size.y) / 720.0
		for ring in [225.0, 251.0, 278.0]:
			draw_arc(mark, ring * scale_factor, 0.0, TAU, 96, Color("344950"), 1.4, true)
		var splash := PackedVector2Array()
		for i in 48:
			var angle := TAU * float(i) / 48.0
			var reach := 171.0 + 18.0 * sin(angle * 5.0) + 9.0 * cos(angle * 11.0)
			splash.append(mark + Vector2.from_angle(angle) * reach * scale_factor)
		draw_colored_polygon(splash, Color("a83d36"))
		for drop in [Vector3(-175, -151, 15), Vector3(171, -122, 10),
				Vector3(-198, 102, 8), Vector3(138, 155, 22)]:
			draw_circle(mark + Vector2(drop.x, drop.y) * scale_factor,
				drop.z * scale_factor, Color("a83d36"), true, -1.0, true)
		draw_line(Vector2(48.0, 52.0), Vector2(size.x - 48.0, 52.0), EDGE, 1.0)
		draw_line(Vector2(48.0, size.y - 52.0), Vector2(size.x - 48.0, size.y - 52.0), EDGE, 1.0)
