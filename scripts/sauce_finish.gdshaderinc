uniform vec4 sauce_mayo_pigment : source_color = vec4(1.0, 0.955, 0.815, 1.0);
uniform vec4 sauce_mustard_pigment : source_color = vec4(0.96, 0.68, 0.09, 1.0);
uniform vec4 sauce_ketchup_pigment : source_color = vec4(0.79, 0.15, 0.092, 1.0);
uniform vec4 sauce_mayo_reference : source_color = vec4(1.0, 0.941176, 0.658824, 1.0);

vec3 sauce_pigment(int kind) {
	if (kind == 1) {
		return sauce_mustard_pigment.rgb;
	}
	if (kind == 2) {
		return sauce_ketchup_pigment.rgb;
	}
	return sauce_mayo_pigment.rgb;
}

vec3 sauce_coating_pigment(int kind, vec3 mayo) {
	return kind == 0 || kind == 3 ? mayo * (sauce_mayo_pigment.rgb / sauce_mayo_reference.rgb) : sauce_pigment(kind);
}

float sauce_finish_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float sauce_mustard_grain(vec2 grains, vec2 footprint) {
	float resolved = 1.0 - smoothstep(0.30, 0.90, max(footprint.x, footprint.y));
	if (resolved <= 0.0) {
		return 0.0;
	}
	vec2 cell = floor(grains);
	float seed = sauce_finish_hash(cell);
	vec2 centre = 0.24 + 0.52 * vec2(seed, sauce_finish_hash(cell + 13.0));
	vec2 offset = fract(grains) - centre;
	float spot = 1.0 - smoothstep(0.01, 0.0841, dot(offset, offset));
	return spot * smoothstep(0.52, 0.98, seed) * resolved;
}

// Coordinates stay in surface or rest space so the grain follows the stain.
vec2 sauce_grain_position(vec3 position) {
	return (position.xz + position.y * vec2(0.47, -0.86)) * 37.0;
}

vec3 sauce_coating_detail(vec3 color, int kind, vec2 grains, vec2 footprint) {
	if (kind == 1) {
		return color * (1.0 - 0.46 * sauce_mustard_grain(grains, footprint));
	}
	return color;
}

float sauce_coating_roughness(int kind, float mayo) {
	return kind == 1 ? max(0.50, mayo) : mayo;
}
