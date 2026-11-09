shader_type spatial;
render_mode specular_disabled;

uniform vec4 pigment : source_color = vec4(1.0);
uniform float glow = 0.0;

void fragment() {
	ALBEDO = pigment.rgb * 0.72;
	EMISSION = pigment.rgb * (0.10 + glow);
	ROUGHNESS = 1.0;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float bands = 0.18 * step(0.08, facing)
		+ 0.27 * step(0.34, facing)
		+ 0.35 * step(0.67, facing);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * bands * ATTENUATION / PI;
}
