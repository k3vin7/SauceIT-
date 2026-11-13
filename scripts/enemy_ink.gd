extends RefCounted

const TOON := preload("res://assets/enemies/Stage2_PressKing/press_king_toon.gdshader")
static var _palette := {}


## Share the toon palette across instances while leaving the imported mesh
## resources and the separate sauce overlay available to their other callers.
static func apply(visual: Node3D) -> void:
	for piece: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if piece.mesh == null:
			continue
		for surface in piece.mesh.get_surface_count():
			var source := piece.get_active_material(surface) as BaseMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var key := [source.albedo_color, source.albedo_texture, source.vertex_color_use_as_albedo,
				source.uv1_scale, source.uv1_offset, source.emission_enabled]
			if not _palette.has(key):
				var material := ShaderMaterial.new()
				material.shader = TOON
				material.set_shader_parameter("pigment", source.albedo_color)
				material.set_shader_parameter("vertex_pigment", source.vertex_color_use_as_albedo)
				if source.albedo_texture != null:
					material.set_shader_parameter("pigment_texture", source.albedo_texture)
					material.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
					material.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
				if source.emission_enabled:
					material.set_shader_parameter("glow", 0.26)
				_palette[key] = material
			piece.set_surface_override_material(surface, _palette[key])
