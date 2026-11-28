shader_type spatial;
render_mode cull_disabled;

// Marching-squares boundary without blur, and stepped bands for thickness.
//
// The mask stores one texel per grid cell, holding **how thick the mayo is**
// rather than whether there is any. Two things are read out of that, and they
// are read out differently on purpose.
//
// THE OUTLINE, filtered. Sampling bilinearly and cutting at half a single
// splat's worth gives the marching-squares contour: between a just-painted and
// an unpainted cell centre the interpolated value falls one deposit -> 0, so
// the crossing lands on the cell boundary and corners come out diagonal. step()
// keeps it one pixel wide. That is the look the stains have always had, and the
// outermost cells of a stain are exactly the one-deposit case, so the
// silhouette keeps it.
//
// THE MAYO BANDS, unfiltered on coarse grids. `texelFetch` reads the cell's own thickness with no
// interpolation, so a band is drawn on exactly the cells whose stored value is
// over its threshold -- and for the deep band that is exactly the test the
// floor runs when it asks whether someone slips. Filtering would put the drawn
// edge somewhere between two cells and let what you see disagree with what
// trips you.
//
// **Why four steps and not a gradient.** A splat draws a cell white on its
// first hit and the deep band needs twenty-odd, so a stain used to look the
// same at one deposit as at twenty-one: the mayo piling up was invisible right
// up to the moment it flipped. The steps make the pile legible while it is
// still building, so "that patch is nearly dangerous" can be read at a glance
// while running -- which a smooth ramp cannot do, and which is also why each
// step is a hard edge on a cell boundary rather than a blend.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec2 mask_uv_offset = vec2(0.0);
uniform vec2 mask_uv_scale = vec2(1.0);
uniform vec2 mask_cell_origin = vec2(0.0);
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform vec4 mayo_color_mid : source_color = vec4(0.96, 0.88, 0.58, 1.0);
uniform vec4 mayo_color_thick : source_color = vec4(0.90, 0.80, 0.50, 1.0);
uniform vec4 deep_color : source_color = vec4(0.91, 0.81, 0.29, 1.0);
uniform float clean_roughness = 0.92;
uniform float mayo_roughness = 0.34;
// Deep mayo is wet: it is the shine that says "that patch, not this one" from
// across a street, before the colour is even resolvable. The two steps below it
// creep part of the way there, so a patch looks like it is getting wetter
// before it gets dangerous.
uniform float deep_roughness = 0.06;
// Half a single splat's worth, normalised. Not 0.5 any more: a cell with one
// deposit on it is nowhere near the top of the byte.
// Scaled by the sauce bits: a thickness of `t` is stored as `t << 2`, so the
// cut-off moves with it. Left at a thickness of 1's worth of byte, the linear
// blend at a stain's edge would cross it an eighth of a cell in rather than
// half of one, and every boundary on this surface would creep outwards.
uniform float paint_threshold = 0.00784;
// The two middle steps default to the deep threshold, which collapses them onto
// it and leaves the band pattern exactly as it was. Surfaces that want the
// steps -- the floor -- push their own values; a wall or a visor, which nothing
// walks on, is left alone.
uniform float mid_threshold = 0.04706;
uniform float thick_threshold = 0.04706;
uniform float slip_threshold = 0.04706;
uniform bool paint_only = false;
uniform bool fine_contours = false;
uniform sampler2D contour_texture : filter_linear, repeat_disable, hint_default_black;
uniform bool paved = false;
uniform bool wall_face = false;
uniform bool festival_before_attack = false;
uniform sampler2D pavement_mask : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 pavement_origin;
uniform vec2 pavement_size = vec2(1.0);
uniform int painted_floor_tiles = 0;
varying vec3 surface_position;

#include "res://assets/props/Stage2_TomatinaVillage/tomatina_splatter.gdshaderinc"

#include "res://scripts/sauce_finish.gdshaderinc"
#include "res://scripts/sauce_toon.gdshaderinc"
#include "res://scripts/body_sauce_mask.gdshaderinc"
#include "res://scripts/ketchup_surface.gdshaderinc"

void vertex() {
	// Clean floor batches tag each tile in UV2. Collapse the covered triangles
	// when the independently textured tile takes over the same surface.
	if (painted_floor_tiles != 0 && (painted_floor_tiles & (1 << int(UV2.x))) != 0) {
		VERTEX = vec3(0.0);
	}
	surface_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pavement_position = surface_position.xz;
	vec2 brick_size = vec2(1.22, 0.81);
	vec2 aa = fwidth(pavement_position / brick_size);
	vec2 grains = sauce_grain_position(surface_position);
	vec2 grain_footprint = fwidth(grains);
	vec2 mask_uv = UV * mask_uv_scale + mask_uv_offset;
	float coverage = festival_before_attack ? 0.0 : texture(mask_texture, mask_uv).r;
	float fill = fine_contours && !festival_before_attack ? stain_contour(contour_texture, mask_uv) : step(paint_threshold, coverage);
	bool painted = fill > 0.0;
	if (paint_only && fill < 0.50) {
		discard;
	}

	vec2 mask_position = vec2(0.0);
	ivec2 mask_size = ivec2(1);
	float own = 0.0;
	int kind = 0;
	if (painted) {
		mask_size = textureSize(mask_texture, 0);
		mask_position = mask_uv * vec2(mask_size);
		ivec2 cell = sauce_mask_cell(ivec2(floor(mask_position)), mask_size, false);
		own = sauce_mask_byte(mask_texture, cell);
		kind = int(sauce_mask_kind(mask_texture, mask_position, mask_size, false, own));
	}
	bool ketchup = kind == 2;

	vec3 clean = clean_color.rgb;
	if (paved && (fill < 1.0 || ketchup)) {
		vec2 brick = pavement_position / brick_size;
		float stagger = mod(floor(brick.y), 2.0) * 0.5;
		brick.x += stagger;
		vec2 cell = floor(brick);
		vec2 edge = min(fract(brick), 1.0 - fract(brick));
		vec2 seam = 1.0 - smoothstep(vec2(0.012), vec2(0.032) + aa, edge);
		float detail = 1.0 - smoothstep(0.08, 0.42, max(aa.x, aa.y));
		float grain = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 mask_uv = (pavement_position - pavement_origin) / pavement_size;
		float on_street = texture(pavement_mask, mask_uv).r;
		if (any(lessThan(mask_uv, vec2(0.0))) || any(greaterThanEqual(mask_uv, vec2(1.0)))) {
			on_street = 0.0;
		}
		vec2 brick_center = (cell + vec2(0.5) - vec2(stagger, 0.0)) * brick_size;
		float patch = tomato_hash(floor(brick_center / vec2(5.5, 4.4)));
		vec3 grey = clean * mix(0.79, 1.15, grain);
		grey *= mix(vec3(0.91, 0.97, 1.04), vec3(1.08, 1.01, 0.92), patch);
		vec3 clay = clean * vec3(1.02, 0.66, 0.49) * mix(0.87, 1.12, grain);
		float brick_cutoff = mix(0.96, 0.68, smoothstep(0.60, 0.93, patch));
		vec3 paving = mix(grey, clay, step(brick_cutoff, grain));
		vec3 stone = mix(clean, paving * (1.0 - 0.23 * max(seam.x, seam.y)), detail);
		if (festival_before_attack && on_street > 0.0) {
			float large = tomato_splat(pavement_position, 2.36, 0.93);
			float medium = tomato_splat(pavement_position + vec2(-1.6, 2.8), 1.34, 0.74);
			float small = tomato_splat(pavement_position + vec2(3.7, 1.1), 0.80, 0.76);
			float tomato_marks = max(large, max(medium * 0.90, small * 0.81));
			tomato_marks *= on_street * 0.35;
			vec3 dried_tomato = mix(vec3(0.24, 0.072, 0.049), vec3(0.37, 0.126, 0.080), grain);
			stone = mix(stone, dried_tomato, tomato_marks * 0.73);
		}
		clean = mix(vec3(0.18, 0.135, 0.102), stone, on_street);
	}
	ALBEDO = clean;
	ROUGHNESS = clean_roughness;
	if (painted && !ketchup) {
		bool near_detail = dot(VERTEX, VERTEX) < 2304.0;
		float base_roughness = sauce_coating_roughness(kind, mayo_roughness);
		float rough;
		if (kind == 1) {
			// Filter over neighbouring mask texels, then shade at the grain scale.
			// The packed thickness and the stain contour still drive gameplay and coverage.
			float coats = max(0.0, coverage * 63.75 - 0.25);
			float buildup = coats / (coats + 3.0);
			ALBEDO = sauce_pigment(kind) * (1.0 - 0.065 * buildup);
			if (near_detail) {
				float grain = sauce_mustard_grain(grains * 1.35, grain_footprint * 1.35);
				ALBEDO *= 1.0 - mix(0.34, 0.41, buildup) * grain;
				if (!fine_contours) {
					ALBEDO *= 1.0 - 0.32 * sauce_ink(coverage, paint_threshold);
				}
			}
			rough = mix(base_roughness, 0.42, buildup);
		} else {
			float thickness = fine_contours ? coverage : own / 255.0;
			float mid = fine_contours ? smoothstep(mid_threshold - 0.008, mid_threshold + 0.008, thickness) : step(mid_threshold, thickness);
			float thick = fine_contours ? smoothstep(thick_threshold - 0.008, thick_threshold + 0.008, thickness) : step(thick_threshold, thickness);
			float deep = fine_contours ? smoothstep(slip_threshold - 0.008, slip_threshold + 0.008, thickness) : step(slip_threshold, thickness);
			vec3 pigment = sauce_coating_pigment(kind, mayo_color.rgb);
			pigment = mix(pigment, mayo_color_mid.rgb, mid);
			pigment = mix(pigment, mayo_color_thick.rgb, thick);
			ALBEDO = mix(pigment, deep_color.rgb, deep);
			rough = mix(base_roughness, deep_roughness, 0.3 * mid);
			rough = mix(rough, mix(base_roughness, deep_roughness, 0.6), thick);
			rough = mix(rough, deep_roughness, deep);
			if (near_detail && !fine_contours) {
				ALBEDO = sauce_toon_finish(ALBEDO, coverage, paint_threshold, mask_position + mask_cell_origin);
			}
		}
		float visible_fill = paint_only ? 1.0 : fill;
		ALBEDO = mix(clean, ALBEDO, visible_fill);
		ROUGHNESS = mix(clean_roughness, rough, visible_fill);
	}
	if (ketchup) {
		vec3 position = paved ? vec3(pavement_position.x, 0.0, pavement_position.y) : surface_position;
		vec2 surface = fine_contours ? vec2(fill, 0.0) : ketchup_surface(mask_texture, mask_uv, mask_size, position, false);
		float ketchup_fill = surface.x;
		vec3 paste = ketchup_albedo(position, surface, coverage) * (paved ? 0.57 : KETCHUP_COATING_GAIN);
		if (paint_only) {
			if (ketchup_fill < 0.5) {
				discard;
			}
			ALBEDO = paste;
		} else {
			ALBEDO = mix(clean, paste, ketchup_fill * 0.96);
		}
		if (wall_face) {
			EMISSION = paste * (ketchup_fill * KETCHUP_COATING_EMISSION);
		}
		ROUGHNESS = mix(clean_roughness, ketchup_roughness(ketchup_fill), ketchup_fill);
		SPECULAR = mix(0.5, paved ? 0.29 : KETCHUP_COATING_SPECULAR, ketchup_fill);
	}
	if (paved && painted && kind == 0) {
		float wetness = fine_contours ? smoothstep(2.5, 3.5, coverage * 63.75) : step(3.0, floor(own / 4.0));
		if (wetness > 0.0) {
			float stripe = smoothstep(0.55, 0.72, sin((pavement_position.x + pavement_position.y) * 9.0));
			ALBEDO = mix(ALBEDO, vec3(0.95, 0.72, 0.15), stripe * wetness * 0.16);
			ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.12), wetness);
		}
	}
	METALLIC = 0.0;
}
