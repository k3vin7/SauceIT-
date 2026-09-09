shader_type spatial;
render_mode cull_disabled;

// Marching-squares boundary without blur.
//
// The mask stores one texel per grid cell, 1 where painted. Sampling it with
// bilinear filtering and cutting at exactly 0.5 gives the marching-squares
// contour: between a painted and an unpainted cell centre the interpolated
// value falls 1 -> 0, so the 0.5 crossing lands exactly on the cell boundary,
// and at corners the contour runs diagonally. step() keeps the edge one pixel
// wide, so the boundary stays sharp and its position never drifts from the
// cell the slip test reads.
//
// filter_linear (not *_mipmap) and repeat_disable are required: mipmaps would
// soften the boundary at distance, and repeating would wrap the far edge.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform float clean_roughness = 0.92;
uniform float mayo_roughness = 0.34;

const float THRESHOLD = 0.5;

void fragment() {
	float coverage = texture(mask_texture, UV).r;
	float painted = step(THRESHOLD, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb, painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
