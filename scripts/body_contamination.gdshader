shader_type spatial;

// The body's mask, sampled from the surface position rather than from the
// mesh's own UVs.
//
// The grid is the body unwrapped around its own axis: u is the angle about Y,
// v is the height. Deriving the coordinate here from the same local position
// the CPU paints with means the stain lands where the strand hit it, whatever
// UVs the mesh happens to carry -- a capsule's own UVs distribute v across the
// caps, which would slide every splat toward the middle.
//
// repeat_enable, unlike the wall shader: u is a loop, so a stain crossing the
// seam has to interpolate across it rather than clamp. See the boundary note in
// contamination.gdshader for the rest, which is unchanged.
uniform sampler2D mask_texture : filter_linear, repeat_enable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform float body_height = 1.28;
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

// The axis the unwrap turns about, in body space. Not always the origin: the
// burger monster's body sits a third of a metre back of its own node, so
// measuring the angle about (0,0) skews a stain by up to ten degrees around
// its sides -- worst exactly where a player aims, on the flanks.
uniform vec3 axis_offset = vec3(0.0);

// The caps. The side chart maps a point by its angle and its height and throws
// the radius away, which is exact on a vertical wall and degenerate on a
// horizontal one -- a stain on a flat top draws as a streak from the centre to
// the rim rather than as a blob. So the mask carries three charts stacked in
// the one texture: the underside below the side band, the crown above it, both
// polar, with the radius from the axis standing in for the height. u is the
// angle in all three, so the seam still wraps across the whole texture.
//
// Which chart a fragment reads is decided by the way it faces, exactly as the
// painter decides it. Hard selection, not a blend: a blend would mean painting
// several charts per splat, and the splat is what travels over the wire.
uniform float cap_depth = 0.0;
uniform float cap_normal_cut = 0.7;

// The chart's own v, in metres, for a point and the way it faces.
vec2 chart_uv(vec3 about, float up, float height_of_body) {
	float total = height_of_body + cap_depth * 2.0;
	float v = about.y;
	if (cap_depth > 0.0 && abs(up) >= cap_normal_cut) {
		float rim = min(length(about.xz), cap_depth);
		v = sign(up) * (height_of_body * 0.5 + rim);
	}
	return vec2(
		atan(about.x, about.z) / TAU + 0.5,
		clamp(v / total + 0.5, 0.0, 1.0));
}


varying vec3 surface_position;
varying vec3 surface_normal;

void vertex() {
	surface_position = VERTEX;
	surface_normal = NORMAL;
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
	// This cell's own sauce whenever it has one. Borrowing the thickest
	// neighbour's unconditionally drew every thin cell beside a thick one in the
	// thick one's sauce -- ketchup over a deep mayo slick restarts at one layer,
	// so the slick won "thickest" and the trail wore a cream halo.
	float own = floor(texelFetch(mask_texture, middle, 0).r * 255.0 + 0.5);
	float kind = mod(own, 4.0);
	if (floor(own / 4.0) <= 0.0) {
		// Empty: this fragment is in the bleed past the last painted texel, so it
		// takes the sauce of whatever bled into it.
		float best = -1.0;
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
	}
	vec3 tint = mix(vec3(1.0), mustard_tint.rgb, step(0.5, kind) * step(kind, 1.5));
	return mix(tint, ketchup_tint.rgb, step(1.5, kind) * step(kind, 2.5));
}

void fragment() {
	vec3 about = surface_position - axis_offset;
	vec2 uv = chart_uv(about, normalize(surface_normal).y, body_height);
	float coverage = texture(mask_texture, uv).r;
	float painted = step(paint_threshold, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb * sauce_tint(uv), painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
