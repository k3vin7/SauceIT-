shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform vec4 base_color : source_color = vec4(0.72, 0.58, 0.43, 1.0);
uniform bool weathered = false;
uniform bool masonry = false;
varying vec3 wall_position;
varying vec3 wall_normal;

#include "res://assets/props/Stage2_TomatinaVillage/tomatina_splatter.gdshaderinc"

void vertex() {
	wall_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 normal = normalize(wall_normal);
	float value = dot(base_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Match tomatina_toon.gdshader exactly so the replacement facade and the
	// authored HouseHoney behind it resolve to the same on-screen colour.
	vec3 color = mix(base_color.rgb, vec3(value), 0.24) * 0.68 + vec3(0.046, 0.039, 0.036);
	float across = abs(normal.x) > abs(normal.z) ? wall_position.z : wall_position.x;

	if (weathered && abs(normal.y) < 0.36) {
		vec2 at = vec2(across, wall_position.y * 0.82) + vec2(1.93, 0.49);
		float stain = tomato_wall_stain(at) * (1.0 - smoothstep(1.8, 4.0, wall_position.y));
		color = mix(color, tomato_wall_stain_color(at), stain * 0.76);
	}

	if (masonry && abs(normal.y) < 0.36) {
		vec2 block = vec2(across / 0.84, wall_position.y / 0.36);
		block.x += mod(floor(block.y), 2.0) * 0.5;
		vec2 edge = min(fract(block), 1.0 - fract(block));
		vec2 mortar = 1.0 - smoothstep(vec2(0.016), vec2(0.043) + fwidth(block), edge);
		float stone_grain = tomato_hash(floor(block));
		color *= mix(0.78, 1.08, stone_grain);
		color *= 1.0 - max(mortar.x, mortar.y) * 0.28;
	}

	ALBEDO = color;
	ROUGHNESS = 1.0;
	EMISSION = color * 0.13;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = 0.18 * step(0.08, facing)
		+ 0.25 * step(0.35, facing)
		+ 0.31 * step(0.68, facing);
	float lit = smoothstep(0.18, 0.72, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * lit / PI;
}
