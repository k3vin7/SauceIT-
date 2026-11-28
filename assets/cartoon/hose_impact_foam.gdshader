shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

float hash_cell(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float foam_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), t.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), t.x), t.y);
}

void fragment() {
	vec2 at = (UV - vec2(0.5)) * 2.0;
	float radius = length(at);
	vec2 direction = at / max(radius, 0.02);
	float swirl = foam_noise(at * 6.5 - direction * TIME * 2.3);
	float fine = foam_noise(at * 19.0 - direction * TIME * 5.1);
	float edge = 1.0 - smoothstep(0.57, 0.98, radius + (swirl - 0.5) * 0.25);
	float wave = 0.5 + 0.5 * sin(radius * 23.0 - TIME * 20.0 + swirl * 4.3);
	float bubbles = smoothstep(0.45, 0.79, fine * 0.72 + swirl * 0.28);
	float ripples = smoothstep(0.68, 0.98, wave) * smoothstep(0.31, 0.69, swirl);
	float churn = (1.0 - smoothstep(0.04, 0.43, radius)) * (0.43 + 0.54 * fine);
	ALBEDO = mix(vec3(0.77, 0.90, 0.94), vec3(0.98, 0.99, 1.0), bubbles);
	ALPHA = strength * edge * clamp(churn + ripples * 0.41 + bubbles * 0.35, 0.0, 0.87);
}
