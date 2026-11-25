shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Sauce on a festival-goer lying in the street, drawn over their own materials.
//
// **Projected straight down from the top of the box they lie in.** The sauce
// lands on a box collider around the body -- see `TomatinaVictimCorpse` -- and
// is always recorded on that box's top face, whatever side the strand came in
// from. A body lying flat is seen from above, so a top-down projection puts the
// stain on the back, the arms and the legs wherever they are; the sides of a
// limb take the same stain as its top, which reads as sauce running down it.
// Undersides are left clean.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color = vec4(1.0, 0.941, 0.659, 1.0);
// World space to the box's own space: centre at the origin, top face at +y.
uniform mat4 world_to_box;
uniform vec3 box_size = vec3(1.65, 0.48, 2.15);
// Half a single splat's worth, normalised -- see the enemy overlay.
uniform float paint_threshold = 0.00784;
uniform vec4 mustard_tint : source_color = vec4(1.00, 0.86, 0.26, 1.0);

#include "res://scripts/sauce_toon.gdshaderinc"
#include "res://scripts/body_sauce_mask.gdshaderinc"
#include "res://scripts/ketchup_surface.gdshaderinc"

varying vec3 box_position;
varying vec3 box_normal;
varying float ketchup_gloss;

void vertex() {
	box_position = (world_to_box * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	box_normal = (world_to_box * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// The top face's grid: u along +x, v along -z, cell (0,0) at the (-u, -v)
// corner -- the same layout `ContaminableObject` paints it in.
vec2 top_uv(vec3 at) {
	return vec2(at.x / box_size.x + 0.5, -at.z / box_size.z + 0.5);
}

void fragment() {
	if (normalize(box_normal).y < -0.2) {
		discard;
	}
	vec2 uv = top_uv(box_position);
	float coverage = texture(mask_texture, uv).r;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || coverage < paint_threshold) {
		discard;
	}
	ivec2 size = textureSize(mask_texture, 0);
	float kind = mod(sauce_mask_sample(mask_texture, uv, size, false), 4.0);
	ketchup_gloss = 0.0;
	if (kind == 2.0) {
		vec2 surface = ketchup_surface(mask_texture, uv, size, box_position, false);
		if (surface.x < 0.5) {
			discard;
		}
		ALBEDO = ketchup_albedo(box_position, surface, coverage) * KETCHUP_COATING_GAIN;
		EMISSION = ALBEDO * KETCHUP_COATING_EMISSION;
		ROUGHNESS = ketchup_roughness(surface.x);
		SPECULAR = KETCHUP_COATING_SPECULAR;
		ketchup_gloss = surface.x;
	} else {
		vec3 tint = kind == 1.0 ? mustard_tint.rgb : vec3(1.0);
		ALBEDO = sauce_toon_finish(mayo_color.rgb * tint, coverage, paint_threshold, uv * vec2(size));
		EMISSION = ALBEDO * 0.28;
		ROUGHNESS = 1.0;
	}
	METALLIC = 0.0;
}

// Toon bands, as the village kit is lit, and a little of the sauce's own colour
// in the shadow so a stain on the dark side still reads.
void light() {
	if (ketchup_gloss > 0.0) {
		vec2 response = ketchup_light(NORMAL, LIGHT, VIEW, ketchup_gloss);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * response.x;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * response.y;
	} else {
		DIFFUSE_LIGHT += sauce_toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, ALBEDO);
	}
}
