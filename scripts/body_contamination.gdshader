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

const float THRESHOLD = 0.5;

varying vec3 surface_position;

void vertex() {
	surface_position = VERTEX;
}

void fragment() {
	vec2 uv = vec2(
		atan(surface_position.x, surface_position.z) / TAU + 0.5,
		clamp(surface_position.y / body_height + 0.5, 0.0, 1.0));
	float coverage = texture(mask_texture, uv).r;
	float painted = step(THRESHOLD, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb, painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
