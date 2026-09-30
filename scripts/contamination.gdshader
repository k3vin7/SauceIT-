shader_type spatial;
render_mode cull_disabled;

// Marching-squares boundary without blur, and stepped bands for thickness.
//
// The mask stores one texel per grid cell, holding **how thick the mayo is**
// rather than whether there is any. Two things are read out of that, and they
// are read out differently on purpose.
//
// THE OUTLINE, filtered. Sampling bilinearly and cutting at half a single
// splat's worth gives the marching-squares contour: between a just-painted and
// an unpainted cell centre the interpolated value falls one deposit -> 0, so
// the crossing lands on the cell boundary and corners come out diagonal. step()
// keeps it one pixel wide. That is the look the stains have always had, and the
// outermost cells of a stain are exactly the one-deposit case, so the
// silhouette keeps it.
//
// THE BANDS, unfiltered. `texelFetch` reads the cell's own thickness with no
// interpolation, so a band is drawn on exactly the cells whose stored value is
// over its threshold -- and for the deep band that is exactly the test the
// floor runs when it asks whether someone slips. Filtering would put the drawn
// edge somewhere between two cells and let what you see disagree with what
// trips you.
//
// **Why four steps and not a gradient.** A splat draws a cell white on its
// first hit and the deep band needs twenty-odd, so a stain used to look the
// same at one deposit as at twenty-one: the mayo piling up was invisible right
// up to the moment it flipped. The steps make the pile legible while it is
// still building, so "that patch is nearly dangerous" can be read at a glance
// while running -- which a smooth ramp cannot do, and which is also why each
// step is a hard edge on a cell boundary rather than a blend.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform vec4 mayo_color_mid : source_color = vec4(0.96, 0.88, 0.58, 1.0);
uniform vec4 mayo_color_thick : source_color = vec4(0.90, 0.80, 0.50, 1.0);
uniform vec4 deep_color : source_color = vec4(0.91, 0.81, 0.29, 1.0);
uniform float clean_roughness = 0.92;
uniform float mayo_roughness = 0.34;
// Deep mayo is wet: it is the shine that says "that patch, not this one" from
// across a street, before the colour is even resolvable. The two steps below it
// creep part of the way there, so a patch looks like it is getting wetter
// before it gets dangerous.
uniform float deep_roughness = 0.06;
// Half a single splat's worth, normalised. Not 0.5 any more: a cell with one
// deposit on it is nowhere near the top of the byte.
// Scaled by the sauce bits: a thickness of `t` is stored as `t << 2`, so the
// cut-off moves with it. Left at a thickness of 1's worth of byte, the linear
// blend at a stain's edge would cross it an eighth of a cell in rather than
// half of one, and every boundary on this surface would creep outwards.
uniform float paint_threshold = 0.00784;
// The two middle steps default to the deep threshold, which collapses them onto
// it and leaves the band pattern exactly as it was. Surfaces that want the
// steps -- the floor -- push their own values; a wall or a visor, which nothing
// walks on, is left alone.
uniform float mid_threshold = 0.04706;
uniform float thick_threshold = 0.04706;
uniform float slip_threshold = 0.04706;
// What the mayo ramp is multiplied by where the cell holds another sauce. At
// vec3(1.0) a sauce is drawn exactly as mayo is, which is what the fourth,
// unused kind gets.
uniform vec4 mustard_tint : source_color = vec4(1.00, 0.86, 0.26, 1.0);
uniform vec4 ketchup_tint : source_color = vec4(1.00, 0.34, 0.24, 1.0);

void fragment() {
	float coverage = texture(mask_texture, UV).r;
	float painted = step(paint_threshold, coverage);

	ivec2 mask_size = textureSize(mask_texture, 0);
	ivec2 texel = clamp(ivec2(UV * vec2(mask_size)), ivec2(0), mask_size - ivec2(1));
	float thickness = texelFetch(mask_texture, texel, 0).r;

	// WHICH SAUCE, taken from the thickest of the four texels the linear filter
	// blends rather than from this fragment's own.
	//
	// **Its own is wrong exactly where it shows.** `painted` comes from the
	// filtered sample, so the edge of a stain is drawn over fragments whose own
	// texel is still clean -- and a clean byte is 0, which is thickness 0 and
	// sauce 0, and sauce 0 is mayo. Read locally, every mustard and ketchup
	// stain got a mayo-coloured fringe one cell wide, on the one part of the
	// stain where the eye is already looking.
	//
	// The thickest neighbour is the right answer and not a guess: the fringe is
	// there *because* a painted cell bled into this one, so the sauce to draw is
	// the sauce of whatever did the bleeding. Never filtered, always fetched --
	// a blend of two sauces is not a sauce.
	ivec2 lo = clamp(texel - ivec2(1), ivec2(0), mask_size - ivec2(1));
	ivec2 hi = clamp(texel + ivec2(1), ivec2(0), mask_size - ivec2(1));
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
	// A tint the mayo ramp is multiplied by, rather than a palette per sauce.
	// The bands are what says how deep a patch is, and they are the same four
	// steps whatever is in it; the hue only says which sauce. Three full
	// palettes would let the two drift apart, and there is no reading of this
	// floor where mustard should band differently from mayo.
	vec3 tint = mix(vec3(1.0), mustard_tint.rgb, step(0.5, kind) * step(kind, 1.5));
	tint = mix(tint, ketchup_tint.rgb, step(1.5, kind) * step(kind, 2.5));
	// Only where there is mayo at all: a clean cell is not deep, whatever
	// rounding does at the very bottom of the byte.
	float mid = painted * step(mid_threshold, thickness);
	float thick = painted * step(thick_threshold, thickness);
	float deep = painted * step(slip_threshold, thickness);

	vec3 stained = mix(clean_color.rgb, mayo_color.rgb * tint, painted);
	stained = mix(stained, mayo_color_mid.rgb * tint, mid);
	stained = mix(stained, mayo_color_thick.rgb * tint, thick);
	ALBEDO = mix(stained, deep_color.rgb * tint, deep);

	float rough = mix(clean_roughness, mayo_roughness, painted);
	rough = mix(rough, mix(mayo_roughness, deep_roughness, 0.3), mid);
	rough = mix(rough, mix(mayo_roughness, deep_roughness, 0.6), thick);
	ROUGHNESS = mix(rough, deep_roughness, deep);
	METALLIC = 0.0;
}
