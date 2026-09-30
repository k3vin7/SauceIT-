shader_type canvas_item;

// The visor's mask, drawn straight onto the screen.
//
// The physical lens has the same 16:9 shape as the screen, so there is no
// projection here: the mask is sampled 1:1. v is flipped because the grid
// counts upwards and a Control's UV counts down.
//
// The 0.5 cut is the same marching-squares boundary the floor uses; see the
// note in contamination.gdshader.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color;

// Half a single splat's worth, normalised. **Not 0.5.** The mask holds a
// thickness now, 0 to 255, rather than a painted flag that was either 0 or 255
// -- so a cut at 0.5 means a cell has to be hit about 128 times before any of
// it is drawn, which reads as sauce not sticking at all.
// Scaled by the sauce bits: a thickness of `t` is stored as `t << 2`, so the
// cut-off moves with it. Left at a thickness of 1's worth of byte, the linear
// blend at a stain's edge would cross it an eighth of a cell in rather than
// half of one, and every boundary on this surface would creep outwards.
uniform float paint_threshold = 0.00784;

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
	float coverage = texture(mask_texture, vec2(UV.x, 1.0 - UV.y)).r;
	COLOR = vec4(mayo_color.rgb * sauce_tint(vec2(UV.x, 1.0 - UV.y)),
		step(paint_threshold, coverage) * mayo_color.a);
}
