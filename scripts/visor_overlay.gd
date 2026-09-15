class_name VisorOverlay
extends ColorRect

## What the local player sees through their own lenses. The physical lens and
## screen are both 16:9, so this is a straight 1:1 sample of the same mask -- the
## overlay owns no state of its own and cannot drift from what others see.

func bind(visor: VisorContamination) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1.0, 1.0, 1.0, 1.0)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://scripts/visor_overlay.gdshader")
	shader_material.set_shader_parameter("mask_texture", visor.grid.texture)
	shader_material.set_shader_parameter("mayo_color", visor.mayo_color)
	material = shader_material


## The part of the window the mask covers. The whole of it whenever the window is
## a shape the session allows; the rest is behind the bars, and the mask must not
## be stretched over it or the stains would sit where they were not painted.
func set_frame(frame: Rect2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	position = frame.position
	size = frame.size
