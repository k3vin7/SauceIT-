shader_type canvas_item;

// The wearer's view uses the same stain as the glass seen from outside.
#include "res://scripts/visor_surface.gdshaderinc"

uniform float paint_threshold = 0.00784;
uniform float one_coat_alpha = 0.5;
uniform float two_coat_alpha = 0.8;
uniform float three_coat_alpha = 1.0;

void fragment() {
	float ketchup_share;
	float depth;
	// The mask counts rows upwards, while a Control's UV counts down.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	COLOR = visor_stain(uv, paint_threshold, vec3(one_coat_alpha, two_coat_alpha, three_coat_alpha),
		ketchup_share, depth);
	// The screen overlay has no scene lighting. Tone the paste as it looks on
	// the pavement so opaque patches retain their warm, dark red.
	COLOR.rgb *= mix(1.0, 0.78, ketchup_share);
}
