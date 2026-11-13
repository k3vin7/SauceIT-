shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform vec4 pigment : source_color = vec4(1.0);
uniform sampler2D pigment_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool vertex_pigment = false;
uniform float glow = 0.0;

void fragment() {
	vec3 color = pigment.rgb * texture(pigment_texture, UV * uv_scale + uv_offset).rgb;
	if (vertex_pigment) {
		color *= COLOR.rgb;
	}
	float grazing = 1.0 - abs(dot(normalize(NORMAL), VIEW));
	ALBEDO = color * mix(0.77, 0.60, smoothstep(0.77, 0.97, grazing));
	EMISSION = color * (0.13 + glow);
	ROUGHNESS = 1.0;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float bands = 0.18 * step(0.08, facing)
		+ 0.27 * step(0.34, facing)
		+ 0.35 * step(0.67, facing);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * bands * ATTENUATION / PI;
}
