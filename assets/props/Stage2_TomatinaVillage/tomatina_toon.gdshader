shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform bool tomato_wall = false;
uniform bool boundary_wall = false;
varying vec3 wall_position;
varying vec3 wall_normal;
varying vec2 wall_origin;
varying vec2 local_plan;

#include "res://assets/props/Stage2_TomatinaVillage/tomatina_splatter.gdshaderinc"

void vertex() {
	wall_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = MODEL_NORMAL_MATRIX * NORMAL;
	wall_origin = MODEL_MATRIX[3].xz;
	local_plan = VERTEX.xz;
}

void fragment() {
	float value = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mix(COLOR.rgb, vec3(value), 0.24) * 0.68 + vec3(0.046, 0.039, 0.036);
	vec3 normal = normalize(wall_normal);
	float across = abs(normal.x) > abs(normal.z) ? wall_position.z : wall_position.x;
	float bounce = 0.13;
	if (boundary_wall && abs(normal.y) < 0.36) {
		float bay = tomato_hash(floor(wall_origin / 3.7));
		vec3 wash = vec3(1.19, 1.05, 0.85);
		if (bay < 0.25) {
			wash = vec3(0.82, 1.05, 1.25);
		} else if (bay < 0.48) {
			wash = vec3(0.90, 1.17, 0.94);
		} else if (bay < 0.70) {
			wash = vec3(1.24, 0.90, 0.82);
		}
		ALBEDO *= wash * mix(0.92, 1.13, bay);
		if (wall_position.y < 1.13) {
			vec2 block = vec2(across / 0.84, wall_position.y / 0.36);
			block.x += mod(floor(block.y), 2.0) * 0.5;
			vec2 edge = min(fract(block), 1.0 - fract(block));
			vec2 mortar = 1.0 - smoothstep(vec2(0.016), vec2(0.043) + fwidth(block), edge);
			float grain = tomato_hash(floor(block));
			ALBEDO = mix(vec3(0.28, 0.24, 0.20), vec3(0.49, 0.40, 0.32), grain);
			ALBEDO *= 1.0 - max(mortar.x, mortar.y) * 0.26;
		} else if (wall_position.y < 1.29) {
			ALBEDO = vec3(0.43, 0.30, 0.22);
		}
	}
	if (tomato_wall && !boundary_wall && wall_position.y > 6.8 && normal.y > 0.22 && normal.y < 0.995) {
		vec2 tile = vec2(local_plan.y / 0.48, abs(local_plan.x) / 0.40);
		tile.x += mod(floor(tile.y), 2.0) * 0.5;
		vec2 edge = min(fract(tile), 1.0 - fract(tile));
		vec2 aa = fwidth(tile);
		vec2 seam = 1.0 - smoothstep(vec2(0.015), vec2(0.055) + aa, edge);
		float detail = 1.0 - smoothstep(0.08, 0.48, max(aa.x, aa.y));
		float grain = tomato_hash(floor(tile));
		ALBEDO *= mix(1.0, mix(0.90, 1.10, grain) * (1.0 - max(seam.x, seam.y) * 0.20), detail);
		bounce = 0.35;
	}
	if (tomato_wall && wall_position.y < 4.0 && abs(normal.y) < 0.36) {
		float wall = 1.0 - smoothstep(0.10, 0.36, abs(normal.y));
		float height = 1.0 - smoothstep(1.8, 4.0, wall_position.y);
		vec2 at = vec2(across, wall_position.y * 0.82) + vec2(1.93, 0.49);
		float blot = tomato_splat(at, 1.63, 0.66);
		float dots = tomato_splat(at + vec2(3.31, 2.5), 0.63, 0.43);
		float mask = max(blot, dots * 0.83) * height * wall;
		vec3 ketchup = mix(vec3(0.32, 0.032, 0.016), vec3(0.57, 0.063, 0.029),
			tomato_hash(floor(at * 0.69)));
		ALBEDO = mix(ALBEDO, ketchup, mask * 0.91);
	}
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * bounce;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = 0.18 * step(0.08, facing)
		+ 0.25 * step(0.35, facing)
		+ 0.31 * step(0.68, facing);
	float lit = smoothstep(0.18, 0.72, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * lit / PI;
}
