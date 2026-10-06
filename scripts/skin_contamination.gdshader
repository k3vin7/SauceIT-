shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// **Sauce read back through the model's own UV.**
//
// No chart and no unwrap: the mask was painted at the UV the artist laid out, so
// it is sampled at the UV the mesh already carries. That is what pins a stain to
// the skin -- the body can move, bend and wave its arms, and the texel a piece of
// skin reads stays the texel it was painted on.
//
// Drawn as an overlay over the authored material, so the monster keeps its own
// colours everywhere the sauce has not reached.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color = vec4(1.0, 0.941, 0.659, 1.0);
// Half a layer, in the bytes the mask stores: a thickness of `t` is kept as
// `t << 2`, so the cut-off is scaled the same way. See `ContaminationGrid`.
uniform float paint_threshold = 0.00784;
uniform float mayo_roughness = 0.34;

void fragment() {
	float coverage = texture(mask_texture, UV).r;
	float painted = step(paint_threshold, coverage);
	if (painted < 0.5) {
		// Nothing here: let the authored material show through untouched.
		discard;
	}
	ALBEDO = mayo_color.rgb;
	ROUGHNESS = mayo_roughness;
	METALLIC = 0.0;
}
