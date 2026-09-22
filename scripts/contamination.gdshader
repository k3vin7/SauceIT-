shader_type spatial;
render_mode cull_disabled;

// Marching-squares boundary without blur, and a hard second band for deep mayo.
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
// THE DEEP BAND, unfiltered. `texelFetch` reads the cell's own thickness with
// no interpolation, so the band is drawn on exactly the cells whose stored
// value is over the threshold -- which is exactly the test the floor runs when
// it asks whether someone slips. Filtering it would put the drawn edge
// somewhere between two cells and let what you see disagree with what trips
// you. Blocky is also the right answer here: it has to be readable at a glance
// while running, and a hard edge is what reads.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform vec4 deep_color : source_color = vec4(0.91, 0.81, 0.29, 1.0);
uniform float clean_roughness = 0.92;
uniform float mayo_roughness = 0.34;
// Deep mayo is wet: it is the shine that says "that patch, not this one" from
// across a street, before the colour is even resolvable.
uniform float deep_roughness = 0.06;
// Half a single splat's worth, normalised. Not 0.5 any more: a cell with one
// deposit on it is nowhere near the top of the byte.
uniform float paint_threshold = 0.00196;
uniform float slip_threshold = 0.01176;

void fragment() {
	float coverage = texture(mask_texture, UV).r;
	float painted = step(paint_threshold, coverage);

	ivec2 mask_size = textureSize(mask_texture, 0);
	ivec2 texel = clamp(ivec2(UV * vec2(mask_size)), ivec2(0), mask_size - ivec2(1));
	float thickness = texelFetch(mask_texture, texel, 0).r;
	// Only where there is mayo at all: a clean cell is not deep, whatever
	// rounding does at the very bottom of the byte.
	float deep = painted * step(slip_threshold, thickness);

	vec3 stained = mix(clean_color.rgb, mayo_color.rgb, painted);
	ALBEDO = mix(stained, deep_color.rgb, deep);
	ROUGHNESS = mix(mix(clean_roughness, mayo_roughness, painted), deep_roughness, deep);
	METALLIC = 0.0;
}
