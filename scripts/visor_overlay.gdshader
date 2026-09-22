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
uniform float paint_threshold = 0.00196;

void fragment() {
	float coverage = texture(mask_texture, vec2(UV.x, 1.0 - UV.y)).r;
	COLOR = vec4(mayo_color.rgb, step(paint_threshold, coverage) * mayo_color.a);
}
