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
