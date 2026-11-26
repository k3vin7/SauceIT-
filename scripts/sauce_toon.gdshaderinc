// The cartoon finish on a sauce stain, shared by every surface sauce sticks to:
// a dark ink line round the edge of a stain, and a few flecks of shine on the
// thick of it. The overlays, which draw nothing but sauce, also light it in the
// village kit's toon bands -- see `SAUCE_TOON_LIGHT` below.
//
// `coverage` is the filtered mask sample the surface already decides "painted"
// on; it ramps up from nothing across the edge of a stain, so the stretch of
// it just past the cut-off is the edge, and that is where the line goes.
// `cells` is the fragment's position in mask cells, which is what the flecks
// are scattered over, so they stay put on the surface.

float sauce_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 at the very edge of a stain, 0 a little way in.
float sauce_ink(float coverage, float threshold) {
	return 1.0 - smoothstep(threshold, threshold * 1.85, coverage);
}

// A small oval fleck in about one cell in five, only where the sauce is thick.
float sauce_shine(vec2 cells, float coverage, float thick_from) {
	if (coverage < thick_from) {
		return 0.0;
	}
	vec2 cell = floor(cells);
	if (sauce_hash(cell) < 0.8) {
		return 0.0;
	}
	vec2 centre = cell + vec2(0.3) + 0.4 * vec2(sauce_hash(cell + 7.13), sauce_hash(cell + 3.71));
	float d = length((cells - centre) * vec2(1.0, 1.7));
	return 1.0 - smoothstep(0.13, 0.2, d);
}

vec3 sauce_toon_finish(vec3 albedo, float coverage, float threshold, vec2 cells) {
	float ink = sauce_ink(coverage, threshold);
	vec3 inked = mix(albedo, albedo * 0.48, ink);
	float shine = sauce_shine(cells, coverage, threshold * 5.0) * (1.0 - ink);
	return mix(inked, vec3(1.0, 0.82, 0.76), shine * 0.75);
}

// The village kit's toon bands (tomatina_toon.gdshader), for a material that
// is all sauce: `DIFFUSE_LIGHT += sauce_toon_light(NORMAL, LIGHT, ATTENUATION,
// LIGHT_COLOR, ALBEDO);` in its `light()`.
vec3 sauce_toon_light(vec3 normal, vec3 light, float attenuation, vec3 light_color, vec3 albedo) {
	float facing = max(dot(normal, light), 0.0);
	float band = 0.30 * step(0.06, facing) + 0.28 * step(0.38, facing) + 0.26 * step(0.72, facing);
	float lit = smoothstep(0.18, 0.72, attenuation);
	return albedo * light_color * band * lit / PI;
}
