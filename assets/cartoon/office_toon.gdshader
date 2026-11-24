shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

// 사무실(maps/command.tscn) 전용 툰 재질. 토마티나 마을 재질과 같은 3단 명암을 쓰되,
// 정점 색 대신 `albedo` 한 색으로 칠한다(CSG 상자에 바로 붙일 수 있게).
// pattern: 0 단색 / 1 바닥 타일(윗면) / 2 벽 아랫단 널판(옆면) / 3 잔타일(모든 면)

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 pattern_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform int pattern : hint_range(0, 3) = 0;
uniform float pattern_size = 1.0;
uniform float glow : hint_range(0.0, 2.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

float office_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float office_seam(vec2 cell, float width) {
	vec2 edge = min(fract(cell), 1.0 - fract(cell));
	vec2 mark = 1.0 - smoothstep(vec2(width), vec2(width) + fwidth(cell) * 1.5, edge);
	return max(mark.x, mark.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 color = albedo.rgb;
	vec3 normal = normalize(world_normal);
	float across = abs(normal.x) > abs(normal.z) ? world_position.z : world_position.x;
	if (pattern == 1 && normal.y > 0.5) {
		vec2 cell = world_position.xz / pattern_size;
		float pick = mod(floor(cell.x) + floor(cell.y), 2.0);
		color = mix(albedo.rgb, pattern_color.rgb, pick);
		color *= mix(0.94, 1.05, office_hash(floor(cell)));
		color *= 1.0 - office_seam(cell, 0.012) * 0.28;
	} else if (pattern == 2 && abs(normal.y) < 0.5) {
		if (world_position.y < 1.1) {
			float plank = across / pattern_size;
			color = pattern_color.rgb * mix(0.93, 1.06, office_hash(vec2(floor(plank), 3.0)));
			float edge = min(fract(plank), 1.0 - fract(plank));
			color *= 1.0 - (1.0 - smoothstep(0.02, 0.02 + fwidth(plank) * 1.5, edge)) * 0.3;
		} else if (world_position.y < 1.24) {
			color = pattern_color.rgb * 0.72;
		}
	} else if (pattern == 3) {
		vec2 cell = (abs(normal.y) > 0.5 ? world_position.xz : vec2(across, world_position.y))
			/ pattern_size;
		color *= mix(0.95, 1.04, office_hash(floor(cell)));
		color = mix(color, pattern_color.rgb, office_seam(cell, 0.03));
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
	EMISSION = color * (0.13 + glow);
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = 0.18 * step(0.08, facing)
		+ 0.25 * step(0.35, facing)
		+ 0.31 * step(0.68, facing);
	float lit = smoothstep(0.18, 0.72, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * lit / PI;
}
