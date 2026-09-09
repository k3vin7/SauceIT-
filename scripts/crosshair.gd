class_name Crosshair
extends Control

## Fixed centre reticle. The strand converges on the point this marks, so it
## reads as the aim point rather than decoration.

@export_range(0.0, 40.0, 1.0, "suffix:px") var arm_length := 9.0
@export_range(0.0, 30.0, 1.0, "suffix:px") var centre_gap := 5.0
@export_range(1.0, 6.0, 1.0, "suffix:px") var thickness := 2.0
@export var arm_color := Color(1.0, 1.0, 1.0, 0.9)
@export var outline_color := Color(0.0, 0.0, 0.0, 0.65)


func _ready() -> void:
	name = "Crosshair"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre := size * 0.5
	# Vertical then horizontal arm pairs, drawn from the gap outwards.
	var arms := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for arm in arms:
		var from: Vector2 = centre + arm * centre_gap
		var to: Vector2 = centre + arm * (centre_gap + arm_length)
		draw_line(from, to, outline_color, thickness + 2.0)
	for arm in arms:
		var from: Vector2 = centre + arm * centre_gap
		var to: Vector2 = centre + arm * (centre_gap + arm_length)
		draw_line(from, to, arm_color, thickness)
