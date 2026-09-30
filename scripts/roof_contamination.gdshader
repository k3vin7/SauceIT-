shader_type spatial;
// A canopy is a sheet, so both of its sides are there to be seen: without this
// the roof vanishes when you walk under the stall and look up, because the only
// faces it has point outwards.
render_mode cull_disabled;

// The roof's mask, sampled by unrolling the cone flat.
//
// A cone is *developable*: it can be laid out flat with no distortion at all,
// unlike a sphere or a capsule's caps. The classic net is a sector -- cut the
// cone up one side and flatten it -- and a point at slant distance s from the
// apex and angle t lands at polar (s, t * R/L), where L is the slant length.
// Distances survive that exactly, so a splat that is 0.4 m across on the roof
// is 0.4 m across in the grid.
//
// What was here before mapped (angle, height) the way a body does, which is
// right for a capsule and wrong for a cone: every angle meets at the apex, so a
// splat was a wedge that was the right width at the base and tapered to nothing
// at the point. A roof with a few shots on it came out as a sunburst.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform float cone_radius = 1.0;
uniform float cone_height = 1.0;
// The unrolled sector fits a square this many metres on a side.
uniform float grid_extent = 1.0;
uniform float clean_roughness = 0.75;
uniform float mayo_roughness = 0.34;

// Half a single splat's worth, normalised. **Not 0.5.** The mask holds a
// thickness now, 0 to 255, rather than a painted flag that was either 0 or 255
// -- so a cut at 0.5 means a cell has to be hit about 128 times before any of
// it is drawn, which reads as sauce not sticking at all.
// Scaled by the sauce bits: a thickness of `t` is stored as `t << 2`, so the
// cut-off moves with it. Left at a thickness of 1's worth of byte, the linear
// blend at a stain's edge would cross it an eighth of a cell in rather than
// half of one, and every boundary on this surface would creep outwards.
uniform float paint_threshold = 0.00784;

varying vec3 surface_position;

void vertex() {
	surface_position = VERTEX;
}

// What the mayo palette is multiplied by where the cell holds another sauce, and
// how the sauce is found: the thickest of the nine texels around this fragment,
// never the filtered sample.
//
// **The thickest neighbour rather than this fragment's own texel.** `painted`
// here comes from a `filter_linear` sample, so the edge of a stain is drawn over
// texels that are still clean -- and a clean byte is 0, which unpacks to sauce 0,
// which is mayo. Read locally, every mustard and ketchup stain wore a
// mayo-coloured fringe exactly where the eye goes first. The fringe is there
// because a painted cell bled into this one, so the sauce to draw is the sauce of
// whatever bled.
uniform vec4 mustard_tint : source_color = vec4(1.00, 0.86, 0.26, 1.0);
uniform vec4 ketchup_tint : source_color = vec4(1.00, 0.34, 0.24, 1.0);

vec3 sauce_tint(vec2 at) {
	ivec2 size = textureSize(mask_texture, 0);
	ivec2 middle = clamp(ivec2(at * vec2(size)), ivec2(0), size - ivec2(1));
	// Clamped rather than wrapped, which on a grid that wraps is wrong for the one
	// column either side of the seam -- and wrong only about the tint of a fringe
	// pixel there, which is a cheaper error than a branch per fragment.
	ivec2 lo = clamp(middle - ivec2(1), ivec2(0), size - ivec2(1));
	ivec2 hi = clamp(middle + ivec2(1), ivec2(0), size - ivec2(1));
	float best = -1.0;
	float kind = 0.0;
	for (int y = lo.y; y <= hi.y; y++) {
		for (int x = lo.x; x <= hi.x; x++) {
			float byte = floor(texelFetch(mask_texture, ivec2(x, y), 0).r * 255.0 + 0.5);
			float depth = floor(byte / 4.0);
			if (depth > best) {
				best = depth;
				kind = mod(byte, 4.0);
			}
		}
	}
	vec3 tint = mix(vec3(1.0), mustard_tint.rgb, step(0.5, kind) * step(kind, 1.5));
	return mix(tint, ketchup_tint.rgb, step(1.5, kind) * step(kind, 2.5));
}

void fragment() {
	float slant = sqrt(cone_radius * cone_radius + cone_height * cone_height);
	// Height is what places a point on the cone, not its distance from the
	// axis: the two agree on the surface, and height is defined on the apex.
	float from_apex = slant * clamp(
		(cone_height * 0.5 - surface_position.y) / cone_height, 0.0, 1.0);
	float around = atan(surface_position.x, surface_position.z) * (cone_radius / slant);
	vec2 flat_position = vec2(from_apex * cos(around), from_apex * sin(around));
	vec2 uv = flat_position / grid_extent + 0.5;
	float coverage = texture(mask_texture, uv).r;
	float painted = step(paint_threshold, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb * sauce_tint(uv), painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
