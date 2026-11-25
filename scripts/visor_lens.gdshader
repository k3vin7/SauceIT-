shader_type spatial;
render_mode cull_disabled;

// Only the sauce is drawn. Retain depth writes to keep the stain in front of
// the face when the wearer turns or lifts their glasses.
#include "res://scripts/visor_surface.gdshaderinc"

uniform float paint_threshold = 0.00784;
uniform float mayo_roughness = 0.34;
uniform float deep_roughness = 0.06;

void fragment() {
	float ketchup_share;
	float depth;
	vec4 stain = visor_stain(UV, paint_threshold, vec3(1.0), ketchup_share, depth);
	if (stain.a < 0.5) {
		discard;
	}
	ALBEDO = stain.rgb * mix(1.0, KETCHUP_COATING_GAIN, ketchup_share);
	EMISSION = ALBEDO * (ketchup_share * KETCHUP_COATING_EMISSION);
	float roughness = mix(mayo_roughness, deep_roughness, smoothstep(2.0, 3.0, depth));
	ROUGHNESS = mix(roughness, ketchup_roughness(stain.a), ketchup_share);
	SPECULAR = mix(0.5, KETCHUP_COATING_SPECULAR, ketchup_share);
	METALLIC = 0.0;
}
