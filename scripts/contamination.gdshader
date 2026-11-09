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

uniform bool paint_only = false;
uniform bool paved = false;
uniform sampler2D pavement_mask : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 pavement_origin;
uniform vec2 pavement_size = vec2(1.0);
varying vec2 pavement_position;

#include "res://assets/props/Stage2_TomatinaVillage/tomatina_splatter.gdshaderinc"

void vertex() {
	pavement_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float coverage = texture(mask_texture, UV).r;
	float painted = step(paint_threshold, coverage);
	if (paint_only && painted < 0.5) {
		discard;
	}

	ivec2 mask_size = textureSize(mask_texture, 0);
	ivec2 texel = clamp(ivec2(UV * vec2(mask_size)), ivec2(0), mask_size - ivec2(1));
	float thickness = texelFetch(mask_texture, texel, 0).r;

	ivec2 lo = clamp(texel - ivec2(1), ivec2(0), mask_size - ivec2(1));
	ivec2 hi = clamp(texel + ivec2(1), ivec2(0), mask_size - ivec2(1));
	// WHICH SAUCE. **This cell's own, whenever this cell has any.**
	//
	// Taking the thickest neighbour's sauce unconditionally -- which is what this
	// did -- is right for the one case it was written for and wrong everywhere
	// else. A cell taken over by a new sauce restarts at one layer, so ketchup
	// laid over a deep mayo slick is a thin red cell beside a twenty-layer cream
	// one: the cream wins "thickest", and every ketchup cell touching the slick was
	// drawn as mayo. The trail came out with a cream halo a cell wide.
	//
	// The borrowing is only for a fragment whose own texel is empty, which is the
	// case it was for: the filtered sample bleeds a cell past the last painted
	// texel, so the edge of a stain is drawn over clean cells, and a clean byte is
	// 0, which unpacks to sauce 0, which is mayo.
	float own = floor(texelFetch(mask_texture, texel, 0).r * 255.0 + 0.5);
	float kind = mod(own, 4.0);
	if (floor(own / 4.0) <= 0.0) {
		// Only a cell with nothing on it borrows: the fragment is in the bleed
		// past the last painted texel, and the sauce to draw there is the sauce of
		// whatever bled into it.
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

	vec3 clean = clean_color.rgb;
	float tomato_marks = 0.0;
	if (paved) {
		vec2 brick = pavement_position / vec2(1.22, 0.81);
		brick.x += mod(floor(brick.y), 2.0) * 0.5;
		vec2 cell = floor(brick);
		vec2 edge = min(fract(brick), 1.0 - fract(brick));
		vec2 aa = fwidth(brick);
		vec2 seam = 1.0 - smoothstep(vec2(0.012), vec2(0.032) + aa, edge);
		float detail = 1.0 - smoothstep(0.08, 0.42, max(aa.x, aa.y));
		float grain = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 mask_uv = (pavement_position - pavement_origin) / pavement_size;
		float on_street = texture(pavement_mask, mask_uv).r;
		if (any(lessThan(mask_uv, vec2(0.0))) || any(greaterThanEqual(mask_uv, vec2(1.0)))) {
			on_street = 0.0;
		}
		vec3 stone = clean * mix(1.0, mix(0.92, 1.08, grain)
			* (1.0 - 0.23 * max(seam.x, seam.y)), detail);
		float large = tomato_splat(pavement_position, 2.7, 0.69);
		float small = tomato_splat(pavement_position + vec2(3.7, 1.1), 1.12, 0.46);
		tomato_marks = max(large, small * 0.81) * on_street;
		vec3 ketchup = mix(vec3(0.43, 0.037, 0.021), vec3(0.68, 0.082, 0.035), grain);
		stone = mix(stone, ketchup, tomato_marks * 0.65);
		clean = mix(vec3(0.18, 0.135, 0.102), stone, on_street);
	}
	vec3 stained = mix(clean, mayo_color.rgb * tint, painted);
	stained = mix(stained, mayo_color_mid.rgb * tint, mid);
	stained = mix(stained, mayo_color_thick.rgb * tint, thick);
	vec3 base_albedo = mix(stained, deep_color.rgb * tint, deep);
	if (paved && kind > 1.5 && kind < 2.5) {
		// Let grey pavers show through the old juice while fresh drops sit on top.
		float wave = sin(pavement_position.x * 1.48 + sin(pavement_position.y * 1.15))
			* cos(pavement_position.y * 2.07) * 0.5 + 0.5;
		vec3 juice = mix(vec3(0.30, 0.045, 0.027), vec3(0.54, 0.14, 0.077), wave);
		juice = mix(juice, vec3(0.39, 0.023, 0.013), tomato_marks * 0.8);
		base_albedo = mix(clean, juice, painted * mix(0.44, 0.68, wave));
	}
	ALBEDO = base_albedo;

	float rough = mix(clean_roughness, mayo_roughness, painted);
	rough = mix(rough, mix(mayo_roughness, deep_roughness, 0.3), mid);
	rough = mix(rough, mix(mayo_roughness, deep_roughness, 0.6), thick);
	ROUGHNESS = mix(rough, deep_roughness, deep);
	if (paved && kind > 1.5 && kind < 2.5) {
		ROUGHNESS = mix(ROUGHNESS, 0.22, painted * 0.86);
	}
	if (paved && kind > 1.5 && kind < 2.5) {
		ROUGHNESS = max(ROUGHNESS, 0.66);
	}
	METALLIC = 0.0;
}
