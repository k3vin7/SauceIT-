shader_type spatial;
render_mode cull_disabled;

// The lenses as everyone else sees them: the sauce on the glass, and nothing
// else.
//
// **Why the clean glass is not drawn.** The lens is a real quad hung 0.54 m in
// front of the head, and it used to fill its clean cells with `lens_color` -- a
// near-black 1.0 x 0.6 m rectangle. The wearer never sees it in first person
// (it is hidden there, and the mask reaches them as the screen overlay), but in
// third person their own camera looks straight through it at their own head, so
// the dark pane sat across the middle of the screen. Glass you can see through
// is also simply what a pair of glasses looks like from the outside.
//
// **A discard rather than an alpha.** Writing ALPHA would move the lens into
// the transparent pass, where it would have to be sorted against the head
// behind it and against every other transparent thing in the street. Discarding
// the clean fragments keeps it opaque: the stains still write depth, which is
// what a stain on a solid object should do.
//
// **Why this is not `contamination.gdshader` with a flag.** A `discard`
// anywhere in a shader costs the whole shader its depth prepass, and that file
// is also the floor's -- the single biggest surface in the game. So the lens
// gets its own, which is no loss of a shared look: the visor leaves that
// shader's four thickness bands collapsed onto one threshold (nothing walks on
// your glasses), and the one step it does use is reproduced here.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color;
uniform vec4 deep_color : source_color = vec4(0.91, 0.81, 0.29, 1.0);
uniform float mayo_roughness = 0.34;
// Deep sauce is wet, and the shine is what says "that one is badly blinded"
// from across a street before the colour is resolvable.
uniform float deep_roughness = 0.06;
// Half a single splat's worth, normalised, scaled by the two sauce bits -- the
// same marching-squares cut the floor uses; see contamination.gdshader.
uniform float paint_threshold = 0.00784;
uniform float deep_threshold = 0.04706;

// What the mayo palette is multiplied by where the cell holds another sauce.
uniform vec4 mustard_tint : source_color = vec4(1.00, 0.86, 0.26, 1.0);
uniform vec4 ketchup_tint : source_color = vec4(1.00, 0.34, 0.24, 1.0);

// This cell's own sauce whenever it has one. A fragment whose own texel is
// empty is in the bleed past the last painted texel -- the filtered sample
// reaches a cell further than the mask does -- so it borrows the sauce of
// whatever bled into it. A clean byte is 0, which unpacks to mayo, so read
// locally every mustard and ketchup splat wore a cream fringe.
vec3 sauce_tint(vec2 at) {
	ivec2 size = textureSize(mask_texture, 0);
	ivec2 middle = clamp(ivec2(at * vec2(size)), ivec2(0), size - ivec2(1));
	ivec2 lo = clamp(middle - ivec2(1), ivec2(0), size - ivec2(1));
	ivec2 hi = clamp(middle + ivec2(1), ivec2(0), size - ivec2(1));
	float own = floor(texelFetch(mask_texture, middle, 0).r * 255.0 + 0.5);
	float kind = mod(own, 4.0);
	if (floor(own / 4.0) <= 0.0) {
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
	// Clean glass: there is nothing on this part of the lens, so nothing is
	// drawn and you see the face behind it.
	if (texture(mask_texture, UV).r < paint_threshold) {
		discard;
	}
	// The cell's own thickness, unfiltered: the band has to start on a cell
	// boundary, exactly where the stored value crosses, and not somewhere
	// between two cells.
	ivec2 mask_size = textureSize(mask_texture, 0);
	ivec2 texel = clamp(ivec2(UV * vec2(mask_size)), ivec2(0), mask_size - ivec2(1));
	float deep = step(deep_threshold, texelFetch(mask_texture, texel, 0).r);

	vec3 tint = sauce_tint(UV);
	ALBEDO = mix(mayo_color.rgb * tint, deep_color.rgb * tint, deep);
	ROUGHNESS = mix(mayo_roughness, deep_roughness, deep);
	METALLIC = 0.0;
}
