#include "res://scripts/sauce_finish.gdshaderinc"
#include "res://scripts/sauce_toon.gdshaderinc"
#include "res://scripts/ketchup_surface.gdshaderinc"

uniform sampler2D mask_texture : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 lens_size;
uniform bool fine_contours = false;
uniform sampler2D contour_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 mayo_color : source_color;
uniform vec4 mayo_color_mid : source_color = vec4(0.96, 0.88, 0.58, 1.0);
uniform vec4 deep_color : source_color = vec4(0.91, 0.81, 0.29, 1.0);

float visor_mask_byte(ivec2 cell, ivec2 size) {
	return floor(texelFetch(mask_texture, clamp(cell, ivec2(0), size - ivec2(1)), 0).r * 255.0 + 0.5);
}

// Decode the four cells first. Filtering the packed bytes would mix sauce IDs
// into the coat count, and taking the nearest cell would draw rectangular steps.
vec4 visor_stain(vec2 uv, float paint_threshold, vec3 coat_opacity,
		out float ketchup_share, out float depth) {
	ivec2 size = textureSize(mask_texture, 0);
	vec2 mask_position = uv * vec2(size);
	vec3 position = vec3((uv - 0.5) * lens_size, 0.0);
	vec2 grains = sauce_grain_position(position);
	vec2 grain_footprint = fwidth(grains);
	vec2 at = mask_position - 0.5;
	ivec2 cell = ivec2(floor(at));
	vec2 t = fract(at);
	vec4 weights = vec4((1.0 - t.x) * (1.0 - t.y), t.x * (1.0 - t.y),
		(1.0 - t.x) * t.y, t.x * t.y);
	vec4 packed = vec4(visor_mask_byte(cell, size), visor_mask_byte(cell + ivec2(1, 0), size),
		visor_mask_byte(cell + ivec2(0, 1), size), visor_mask_byte(cell + ivec2(1, 1), size));
	vec4 layers = floor(packed * 0.25);
	vec4 painted = weights * step(vec4(1.0), layers);
	float coverage = dot(painted, vec4(1.0));
	ketchup_share = 0.0;
	depth = 0.0;
	if (coverage <= 0.0) {
		return vec4(0.0);
	}

	vec4 opacity = painted * mix(vec4(coat_opacity.x), vec4(coat_opacity.y), step(vec4(2.0), layers));
	opacity = mix(opacity, painted * coat_opacity.z, step(vec4(3.0), layers));
	float total_opacity = dot(opacity, vec4(1.0));
	depth = dot(painted, layers) / coverage;

	vec4 kind = mod(packed, 4.0);
	vec4 ketchup_cells = step(vec4(1.5), kind) * (1.0 - step(vec4(2.5), kind));
	vec4 ketchup_weights = painted * ketchup_cells;
	float ketchup_coverage = dot(ketchup_weights, vec4(1.0));
	float other_coverage = coverage - ketchup_coverage;
	ketchup_share = dot(opacity, ketchup_cells) / max(total_opacity, 0.00001);

	float fill = fine_contours ? stain_contour(contour_texture, uv) : smoothstep(0.22, 0.73, coverage);
	vec3 color = vec3(0.0);
	if (other_coverage > 0.00001) {
		vec4 other = painted * (1.0 - ketchup_cells);
		vec4 mustard_cells = step(vec4(0.5), kind) * (1.0 - step(vec4(1.5), kind));
		float mustard_share = dot(other, mustard_cells) / other_coverage;
		float coats = dot(other, layers) / other_coverage;
		vec3 mayo = mix(sauce_coating_pigment(0, mayo_color.rgb), mayo_color_mid.rgb, smoothstep(1.0, 2.0, coats));
		mayo = mix(mayo, deep_color.rgb, smoothstep(2.0, 3.0, coats));
		vec3 mustard = sauce_coating_detail(sauce_pigment(1), 1, grains, grain_footprint);
		mayo = mix(mayo, mustard * mix(1.0, 0.72, smoothstep(1.0, 3.0, coats)), mustard_share);
		float strength = coverage * min(coats, 3.0) * (4.0 / 255.0);
		color = fine_contours ? mayo : sauce_toon_finish(mayo, strength, paint_threshold, mask_position * 2.0);
	}
	if (ketchup_coverage > 0.0) {
		vec2 surface = fine_contours ? vec2(fill, 0.0) : ketchup_surface(mask_texture, uv, size, position, false);
		float coats = dot(ketchup_weights, layers) / ketchup_coverage;
		// Keep the paste texture visible in already opaque patches.
		float strength = ketchup_coverage * (4.0 * min(coats, 3.0) + 2.0) / 255.0;
		vec3 ketchup = ketchup_albedo(position, surface, strength);
		color = mix(color, ketchup, ketchup_share);
		// Adjacent sauces fill the join where their cells touch.
		fill = mix(fill, surface.x, 1.0 - smoothstep(0.0, 0.25, other_coverage));
	}
	return vec4(color, fill * total_opacity / coverage);
}
