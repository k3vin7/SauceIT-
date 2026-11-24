shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, world_vertex_coords;

// 사무실 박사 홀로그램. 평소에는 주사선이 흘러내리며 조용히 떠 있다가, 몇 초에 한 번
// 잠깐 "지지직" 한다: 몸이 가로 띠 단위로 좌우로 어긋나고, 밝기가 튀고, 순간 꺼졌다 켜진다.
// 터지는 간격은 `glitch_period` 안팎에서 매번 다르고(±`glitch_jitter`), 가끔 두 번 연달아 튄다.
// 띠와 주사선은 월드 높이로 잡으므로 박사의 여러 조각에 걸쳐 이어진다.

uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float rim_glow : hint_range(0.0, 2.0) = 0.7;
uniform float scanline_density = 46.0;
uniform float scanline_speed = 2.4;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.35;
// 지지직 사이의 평균 간격(초)과, 그 간격이 앞뒤로 흔들리는 폭(초).
uniform float glitch_period = 5.0;
uniform float glitch_jitter = 2.0;
// 한 번 지지직거리는 길이(초).
uniform float glitch_duration = 0.28;
// 띠가 좌우로 어긋나는 최대 거리(m).
uniform float glitch_shift = 0.22;
// 어긋나는 가로 띠의 높이(m).
uniform float glitch_band = 0.11;
// 켜면 계속 지지직거린다(에디터에서 모양을 볼 때).
uniform bool glitch_preview = false;

varying float world_height;
varying float glitch_now;
varying float glitch_tick;

float holo_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 지금 지지직거리는 중이면 1.
float holo_glitch(float time) {
	float period = max(glitch_period, 0.5);
	float slot = floor(time / period);
	float start = slot * period + holo_hash(vec2(slot, 1.0)) * clamp(glitch_jitter, 0.0, period - glitch_duration);
	float burst = step(start, time) * step(time, start + glitch_duration);
	// 열 번에 세 번쯤은 숨 돌릴 틈 없이 한 번 더 튄다.
	float again = start + glitch_duration + 0.16;
	float second = step(0.7, holo_hash(vec2(slot, 7.0)))
		* step(again, time) * step(time, again + glitch_duration * 0.6);
	return max(burst, second);
}

void vertex() {
	world_height = VERTEX.y;
	glitch_now = glitch_preview ? 1.0 : holo_glitch(TIME);
	// 지지직거리는 동안 어긋남은 초당 30번 바뀐다.
	glitch_tick = floor(TIME * 30.0);
	float band = floor(VERTEX.y / max(glitch_band, 0.01));
	float pick = holo_hash(vec2(band, glitch_tick));
	float shift = (holo_hash(vec2(band + 31.0, glitch_tick)) - 0.5) * 2.0 * glitch_shift;
	VERTEX += INV_VIEW_MATRIX[0].xyz * shift * step(0.45, pick) * glitch_now;
}

void fragment() {
	float scan = 0.5 + 0.5 * sin(world_height * scanline_density - TIME * scanline_speed);
	float alpha = opacity * (1.0 - scanline_depth * scan);
	alpha *= 0.94 + 0.06 * sin(TIME * 13.0);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	vec3 color = tint.rgb * (1.0 + rim * rim_glow);
	// 지지직: 프레임마다 확 밝아지거나 거의 꺼지고, 띠 몇 줄은 하얗게 튄다.
	float flash = holo_hash(vec2(glitch_tick, 3.0));
	float band = floor(world_height / max(glitch_band, 0.01));
	float spark = step(0.8, holo_hash(vec2(band, glitch_tick + 5.0)));
	alpha *= mix(1.0, flash < 0.3 ? 0.08 : 1.7, glitch_now);
	color = mix(color, vec3(1.0), spark * glitch_now * 0.7);
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
