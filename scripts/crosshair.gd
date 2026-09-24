class_name Crosshair
extends Control

## Fixed centre reticle. The strand converges on the point this marks, so it
## reads as the aim point rather than decoration.

@export_range(0.0, 40.0, 1.0, "suffix:px") var arm_length := 9.0
@export_range(0.0, 30.0, 1.0, "suffix:px") var centre_gap := 5.0
@export_range(1.0, 6.0, 1.0, "suffix:px") var thickness := 2.0
@export var arm_color := Color(1.0, 1.0, 1.0, 0.9)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.65)
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


func _ready() -> void:
	name = "Crosshair"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre := size * 0.5
	# Opening outwards rather than closing in: the arms pull back off what they
	# are marking, so the thing being hit is less obscured exactly when it is
	# worth looking at.
	var gap := centre_gap + connected_spread * connection
	var width := thickness + connected_thickness * connection
	var tint := arm_color.lerp(connected_color, connection)
	# Vertical then horizontal arm pairs, drawn from the gap outwards.
	var arms := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for arm in arms:
		var from: Vector2 = centre + arm * gap
		var to: Vector2 = centre + arm * (gap + arm_length)
		draw_line(from, to, outline_color, width + 2.0)
	for arm in arms:
		var from: Vector2 = centre + arm * gap
		var to: Vector2 = centre + arm * (gap + arm_length)
		draw_line(from, to, tint, width)
