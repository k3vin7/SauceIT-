class_name Crosshair
extends Control

## Fixed centre reticle. The strand converges on the point this marks, so it
## reads as the aim point rather than decoration.

@export_range(0.0, 40.0, 1.0, "suffix:px") var arm_length := 9.0
@export_range(0.0, 30.0, 1.0, "suffix:px") var centre_gap := 5.0
@export_range(1.0, 6.0, 1.0, "suffix:px") var thickness := 2.0
@export var arm_color := Color(1.0, 1.0, 1.0, 0.9)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.9)
## What it turns into while the stream is actually landing on something alive.
##
## This is the cheapest honest answer to "am I hitting it". The weapon is a
## continuous stream, so there is no hit *event* to flash -- but there is a hit
## *state*, true or false on every frame, and the reticle can simply show it.
## Nothing here is invented: it is on the body or it is not.
@export var connected_color := Color(1.0, 0.86, 0.36, 1.0)
@export_range(0.0, 20.0, 0.5, "suffix:px") var connected_spread := 4.0
@export_range(0.0, 2.0, 0.05, "suffix:px") var connected_thickness := 1.0

## 0 while the stream is off a body, 1 while it is on one. Faded rather than
## switched: the stream lands in points, not continuously, so the raw flag
## flickers several times a second even on a target held perfectly.
var connection := 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if absf(clamped - connection) < 0.002:
			connection = clamped
			return
		connection = clamped
		queue_redraw()


var impact_left := 0.0
var trajectory_segments := PackedVector2Array()
## One opacity per segment pair in `trajectory_segments`; missing means opaque.
var trajectory_alpha := PackedFloat32Array()
## Screen outline of the tomato drawn where a near throw lands, and its leaves.
var landing_marker := PackedVector2Array()
var landing_leaf := PackedVector2Array()
var effective_range := false:
	set(value):
		if effective_range != value:
			effective_range = value
			queue_redraw()
var impact_kill := false
var impact_weak_spot := false
## 0~1: how far the sniper nozzle is pulled in. The small reticle gives way to a
## scope -- a dark surround and hairlines across the glass -- as it rises.
var scope := 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if not is_equal_approx(clamped, scope):
			scope = clamped
			queue_redraw()


func confirm_impact(killed: bool, weak_spot := false) -> void:
	impact_left = 0.24 if killed else 0.18 if weak_spot else 0.12
	impact_kill = killed
	impact_weak_spot = weak_spot
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	impact_left = maxf(impact_left - delta, 0.0)
	queue_redraw()
	if impact_left <= 0.0:
		set_process(false)


func _ready() -> void:
	set_process(false)
	name = "Crosshair"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre := size * 0.5
	for index in range(0, trajectory_segments.size() - 1, 2):
		var from := trajectory_segments[index]
		var to := trajectory_segments[index + 1]
		var pair := index / 2
		var alpha := trajectory_alpha[pair] if pair < trajectory_alpha.size() else 1.0
		draw_line(from, to, Color(0.06, 0.08, 0.09, 0.6 * alpha), 4.0, true)
		draw_line(from, to, Color(0.957, 0.859, 0.51, alpha), 2.0, true)
	# Seen almost edge-on the outline folds flat and will not fill; skip it then.
	if landing_marker.size() >= 3 and not Geometry2D.triangulate_polygon(landing_marker).is_empty():
		draw_colored_polygon(landing_marker, Color(0.88, 0.16, 0.1, 0.8))
		var outline := landing_marker.duplicate()
		outline.append(landing_marker[0])
		draw_polyline(outline, Color(0.25, 0.03, 0.02, 0.9), 2.0, true)
		if landing_leaf.size() >= 3 and not Geometry2D.triangulate_polygon(landing_leaf).is_empty():
			draw_colored_polygon(landing_leaf, Color(0.3, 0.68, 0.2, 0.95))
	if scope > 0.0:
		_draw_scope(centre)
	# Opening outwards rather than closing in: the arms pull back off what they
	# are marking, so the thing being hit is less obscured exactly when it is
	# worth looking at.
	var gap := centre_gap + connected_spread * connection
	var width := thickness + connected_thickness * connection
	var tint := (Color("75e3bc") if effective_range else arm_color).lerp(connected_color, connection)
	tint.a *= 1.0 - scope
	if effective_range and scope <= 0.0:
		draw_circle(centre, 3.5, outline_color)
		draw_circle(centre, 2.0, Color("75e3bc"))
	# Vertical then horizontal arm pairs, drawn from the gap outwards.
	var arms := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for arm in arms:
		var from: Vector2 = centre + arm * gap
		var to: Vector2 = centre + arm * (gap + arm_length)
		draw_line(from, to, Color(outline_color, outline_color.a * (1.0 - scope)), width + 2.0)
	for arm in arms:
		var from: Vector2 = centre + arm * gap
		var to: Vector2 = centre + arm * (gap + arm_length)
		draw_line(from, to, tint, width)

	if impact_left > 0.0:
		var duration := 0.24 if impact_kill else 0.18 if impact_weak_spot else 0.12
		var alpha := clampf(impact_left / duration, 0.0, 1.0)
		var accent := Color(1.0, 0.48, 0.22, alpha) if impact_kill else Color(1.0, 0.92, 0.7, alpha)
		if impact_weak_spot:
			accent = Color(0.42, 0.94, 1.0, alpha)
		for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var direction: Vector2 = diagonal.normalized()
			draw_line(centre + direction * 7.0, centre + direction * (14.0 if impact_kill else 11.0), accent, 2.0)


## The scope: everything outside the glass goes dark, and hairlines cross it
## with a gap at the middle for the dot. The lines take the reticle's colours --
## green in effective range, gold while the shot is on a body.
func _draw_scope(centre: Vector2) -> void:
	var radius := minf(size.x, size.y) * 0.44
	var far := size.length()
	var dark := Color(0.0, 0.0, 0.0, 0.93 * scope)
	var steps := 72
	for step in steps:
		var a := Vector2.from_angle(TAU * float(step) / steps)
		var b := Vector2.from_angle(TAU * float(step + 1) / steps)
		draw_colored_polygon(PackedVector2Array([centre + a * radius, centre + b * radius,
			centre + b * far, centre + a * far]), dark)
	draw_arc(centre, radius, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, scope), 5.0, true)
	var line := (Color("75e3bc") if effective_range else Color(0.05, 0.05, 0.06)).lerp(connected_color, connection)
	line.a = 0.9 * scope
	var gap := 10.0
	for arm in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		# Thin through the glass, thick towards the rim, as on a real reticle.
		draw_line(centre + arm * gap, centre + arm * radius * 0.42, line, 1.5, true)
		draw_line(centre + arm * radius * 0.42, centre + arm * radius, line, 4.0)
	draw_circle(centre, 2.0, Color(0.9, 0.16, 0.12, scope))
