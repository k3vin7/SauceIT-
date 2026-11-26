shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(dot(n, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	vec3 half_vector = normalize(VIEW + normalize(vec3(-0.4, 0.67, 0.53)));
	float flash = pow(max(dot(n, half_vector), 0.0), 24.0);
	ALBEDO = mix(vec3(0.61, 0.76, 0.81), vec3(0.96, 0.99, 1.0), max(flash, fresnel * 0.58));
	ALPHA = (0.32 + flash * 0.60 + fresnel * 0.23) * smoothstep(0.0, 0.24, facing);
}
