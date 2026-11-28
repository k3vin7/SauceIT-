shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://scripts/sauce_finish.gdshaderinc"

uniform int sauce_kind = 0;
uniform vec4 shadow_color : source_color = vec4(0.737, 0.64, 0.45, 1.0);
uniform vec4 glaze_color : source_color = vec4(1.0, 0.996, 0.946, 1.0);
uniform float sheen : hint_range(0.0, 1.0) = 0.56;
uniform float highlight_width : hint_range(0.04, 0.55) = 0.36;
uniform float fold_strength : hint_range(0.0, 0.4) = 0.15;
uniform float fold_frequency = 7.0;
uniform float scroll_speed = 1.15;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.0;

// UV.x runs across the ribbon; UV.y measures distance along each connected run.
varying float surface_fold;

void vertex() {
	// Interpolate the surface wave across each ribbon section. The ribbon's
	// vertices stay on the collision path, including its caps and final drop.
	float wave = UV.y * fold_frequency + TIME * scroll_speed;
	surface_fold = sin(wave) * fold_strength * 0.45;
}

void fragment() {
	float side = clamp(UV.x * 2.0 - 1.0, -1.0, 1.0);
	float skin = sqrt(max(0.0, 1.0 - side * side));
	float flow = UV.y + TIME * scroll_speed;
	float folds = surface_fold;
	float form = clamp(0.17 + 0.81 * skin - 0.14 * side + folds, 0.0, 1.0);
	vec3 pigmented = mix(shadow_color.rgb, sauce_pigment(sauce_kind), form);

	if (grain_strength > 0.0) {
		vec2 grains = vec2(UV.x * 11.0, flow * 24.0);
		float grain = sauce_mustard_grain(grains, fwidth(grains));
		pigmented = mix(pigmented, shadow_color.rgb, grain * grain_strength);
	}

	float glint_centre = -0.29 + folds * 0.32;
	float ribbon_width = max(highlight_width, fwidth(side) * 0.84);
	float gloss_offset = (side - glint_centre) / ribbon_width;
	float broad_gloss = exp(-gloss_offset * gloss_offset);
	float sharp_gloss = exp(-gloss_offset * gloss_offset * 13.0);
	float reflection = sheen * (broad_gloss * (0.52 + folds) + sharp_gloss * 0.16);
	ALBEDO = mix(pigmented, glaze_color.rgb, min(reflection, 0.85));
}
