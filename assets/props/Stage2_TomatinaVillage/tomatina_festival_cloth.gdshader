shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

void vertex() {
	float sway = sin(TIME * 3.1 + VERTEX.x * 0.62 + VERTEX.z * 0.39);
	float ripple = sin(TIME * 5.6 - UV.y * 2.9 + VERTEX.z * 0.71);
	VERTEX += NORMAL * (sway * 0.15 + ripple * 0.075) * UV.y * UV.y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	EMISSION = COLOR.rgb * 0.12;
}
