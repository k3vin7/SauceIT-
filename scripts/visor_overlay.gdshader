shader_type canvas_item;

// The visor's mask, drawn straight onto the screen.
//
// The grid is defined in view units -- 16 by 9 across the field of view -- so
// there is no projection here at all: a cell is a piece of the screen. v is
// flipped because the grid counts upwards and a Control's UV counts down.
//
// The 0.5 cut is the same marching-squares boundary the floor uses; see the
// note in contamination.gdshader.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color;

const float THRESHOLD = 0.5;

void fragment() {
	float coverage = texture(mask_texture, vec2(UV.x, 1.0 - UV.y)).r;
	COLOR = vec4(mayo_color.rgb, step(THRESHOLD, coverage) * mayo_color.a);
}
