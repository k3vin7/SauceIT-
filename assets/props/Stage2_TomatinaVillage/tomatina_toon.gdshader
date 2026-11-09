shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform bool tomato_wall = false;
varying vec3 wall_position;
varying vec3 wall_normal;

#include "res://assets/props/Stage2_TomatinaVillage/tomatina_splatter.gdshaderinc"

void vertex() {
	wall_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wall_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	float value = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mix(COLOR.rgb, vec3(value), 0.24) * 0.68 + vec3(0.046, 0.039, 0.036);
	if (tomato_wall && wall_position.y < 4.0 && abs(normalize(wall_normal).y) < 0.36) {
		vec3 normal = normalize(wall_normal);
		float across = abs(normal.x) > abs(normal.z) ? wall_position.z : wall_position.x;
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
	EMISSION = ALBEDO * 0.13;
}

void light() {
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float band = 0.18 * step(0.08, facing)
		+ 0.25 * step(0.35, facing)
		+ 0.31 * step(0.68, facing);
	float lit = smoothstep(0.18, 0.72, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * lit / PI;
}
