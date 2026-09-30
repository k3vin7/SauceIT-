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

void fragment() {
	float coverage = texture(mask_texture, vec2(UV.x, 1.0 - UV.y)).r;
	COLOR = vec4(mayo_color.rgb, step(paint_threshold, coverage) * mayo_color.a);
}
