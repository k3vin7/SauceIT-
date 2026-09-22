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
uniform float paint_threshold = 0.00196;

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

void fragment() {
	vec3 about = surface_position - axis_offset;
	vec2 uv = chart_uv(about, normalize(surface_normal).y, body_height);
	float coverage = texture(mask_texture, uv).r;
	float painted = step(paint_threshold, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb, painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
