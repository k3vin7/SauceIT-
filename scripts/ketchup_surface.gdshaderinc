uniform vec4 ketchup_thin_color : source_color = vec4(0.79, 0.31, 0.20, 1.0);
uniform vec4 ketchup_pooled_color : source_color = vec4(0.52, 0.105, 0.075, 1.0);
uniform vec4 ketchup_sheen_color : source_color = vec4(0.94, 0.56, 0.41, 1.0);
uniform vec4 mayo_splat_color : source_color = vec4(0.99, 0.968, 0.902, 1.0);
uniform vec4 mayo_splat_pooled : source_color = vec4(0.90, 0.865, 0.788, 1.0);
uniform vec4 mustard_splat_color : source_color = vec4(0.95, 0.69, 0.20, 1.0);
uniform vec4 mustard_splat_pooled : source_color = vec4(0.85, 0.59, 0.16, 1.0);

// Vertical and curved surfaces get less direct light than a paved floor.
const float KETCHUP_COATING_GAIN = 0.74;
const float KETCHUP_COATING_EMISSION = 0.26;
const float KETCHUP_COATING_SPECULAR = 0.20;

float ketchup_roughness(float fill) {
	return mix(0.48, 0.30, fill);
}

vec2 ketchup_light(vec3 normal, vec3 light, vec3 view, float fill) {
	float facing = max(dot(normal, light), 0.0);
	vec3 half_direction = normalize(light + view);
	float highlight = pow(max(dot(normal, half_direction), 0.0), 36.0);
	return facing * vec2(1.0, highlight * fill * 0.10) / PI;
}

ivec2 ketchup_mask_cell(ivec2 cell, ivec2 size, bool wrap_x) {
	int x = wrap_x ? int(mod(float(cell.x), float(size.x))) : clamp(cell.x, 0, size.x - 1);
	return ivec2(x, clamp(cell.y, 0, size.y - 1));
}

float sauce_outline_texel(sampler2D mask, ivec2 cell, ivec2 size, bool wrap_x, int kind) {
	float packed = floor(texelFetch(mask, ketchup_mask_cell(cell, size, wrap_x), 0).r * 255.0 + 0.5);
	return packed >= 4.0 && (kind < 0 || int(mod(packed, 4.0)) == kind) ? 1.0 : 0.0;
}

vec4 ketchup_spline(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	float inv = 1.0 - t;
	return vec4(inv * inv * inv, 4.0 - 6.0 * t2 + 3.0 * t3,
		1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3, t3) / 6.0;
}

vec4 ketchup_spline_slope(float t) {
	float t2 = t * t;
	float inv = 1.0 - t;
	return vec4(-0.5 * inv * inv, 1.5 * t2 - 2.0 * t,
		0.5 + t - 1.5 * t2, 0.5 * t2);
}

// Filter occupancy separately from the packed thickness and kind. A thick
// drop has the same footprint as a thin one, even beside another sauce.
vec2 sauce_outline(sampler2D mask, vec2 uv, ivec2 size, vec3 position, bool wrap_x, int kind) {
	vec2 at = uv * vec2(size) - 0.5;
	ivec2 cell = ivec2(floor(at));
	vec2 within = fract(at);
	vec4 occupied = vec4(
		sauce_outline_texel(mask, cell, size, wrap_x, kind),
		sauce_outline_texel(mask, cell + ivec2(1, 0), size, wrap_x, kind),
		sauce_outline_texel(mask, cell + ivec2(0, 1), size, wrap_x, kind),
		sauce_outline_texel(mask, cell + ivec2(1, 1), size, wrap_x, kind));
	float count = dot(occupied, vec4(1.0));
	if (count == 0.0 || count == 4.0) {
		return vec2(count * 0.25, 0.0);
	}

	mat4 neighbors;
	for (int column = 0; column < 4; column++) {
		neighbors[0][column] = sauce_outline_texel(mask, cell + ivec2(column - 1, -1), size, wrap_x, kind);
		neighbors[3][column] = sauce_outline_texel(mask, cell + ivec2(column - 1, 2), size, wrap_x, kind);
	}
	neighbors[1] = vec4(sauce_outline_texel(mask, cell + ivec2(-1, 0), size, wrap_x, kind),
		occupied.xy, sauce_outline_texel(mask, cell + ivec2(2, 0), size, wrap_x, kind));
	neighbors[2] = vec4(sauce_outline_texel(mask, cell + ivec2(-1, 1), size, wrap_x, kind),
		occupied.zw, sauce_outline_texel(mask, cell + ivec2(2, 1), size, wrap_x, kind));

	// The spline rounds the silhouette across several cells. A lone cell
	// represents a detached droplet, so give it a circular contour.
	vec4 rows = transpose(neighbors) * ketchup_spline(within.x);
	float coverage = dot(rows, ketchup_spline(within.y));
	vec2 slope = vec2(dot(transpose(neighbors) * ketchup_spline_slope(within.x), ketchup_spline(within.y)),
		dot(rows, ketchup_spline_slope(within.y)));
	if (count == 1.0) {
		vec2 center = vec2(occupied.y + occupied.w, occupied.z + occupied.w);
		ivec2 drop = ivec2(center) + ivec2(1);
		float around = 0.0;
		for (int row = drop.y - 1; row <= drop.y + 1; row++) {
			for (int column = drop.x - 1; column <= drop.x + 1; column++) {
				around += neighbors[row][column];
			}
		}
		if (around == 1.0) {
			vec2 inward = center - within;
			coverage = 1.0 - length(inward);
			slope = inward * 2.0;
		}
	}
	float waviness = sin(dot(position, vec3(12.0, 19.0, 15.0)))
		* cos(dot(position, vec3(27.0, -14.0, 21.0)));
	float edge = 0.47 + 0.065 * waviness;
	float fill = smoothstep(edge - 0.08, edge + 0.08, coverage);

	// Light one side of the wet bead and shade the opposite side.
	float bevel = smoothstep(edge, edge + 0.13, coverage)
		* (1.0 - smoothstep(edge + 0.18, 1.0, coverage));
	float rim_light = dot(slope, vec2(0.58, 0.81)) * bevel;
	return vec2(fill, rim_light);
}

vec2 ketchup_surface(sampler2D mask, vec2 uv, ivec2 size, vec3 position, bool wrap_x) {
	return sauce_outline(mask, uv, size, position, wrap_x, 2);
}

// Four bilinear taps reconstruct a cubic B-spline in the transition band.
vec4 stain_cubic_weights(float t) {
	float s = 1.0 - t;
	return vec4(s * s * s, 4.0 - 6.0 * t * t + 3.0 * t * t * t,
		4.0 - 6.0 * s * s + 3.0 * s * s * s, t * t * t) / 6.0;
}

float stain_contour(sampler2D field, vec2 uv) {
	float linear_value = texture(field, uv).r;
	float width = clamp(fwidth(linear_value) * 0.72, 0.005, 0.15);
	if (linear_value <= 0.12 || linear_value >= 0.88) {
		return step(0.5, linear_value);
	}
	vec2 size = vec2(textureSize(field, 0));
	vec2 sample_pos = uv * size - 0.5;
	vec2 base = floor(sample_pos);
	vec2 offset = fract(sample_pos);
	vec4 wx = stain_cubic_weights(offset.x);
	vec4 wy = stain_cubic_weights(offset.y);
	vec2 low_weight = vec2(wx.x + wx.y, wy.x + wy.y);
	vec2 high_weight = vec2(wx.z + wx.w, wy.z + wy.w);
	vec2 low = (base - 0.5 + vec2(wx.y, wy.y) / low_weight) / size;
	vec2 high = (base + 1.5 + vec2(wx.w, wy.w) / high_weight) / size;
	float a = texture(field, low).r * low_weight.x + texture(field, vec2(high.x, low.y)).r * high_weight.x;
	float b = texture(field, vec2(low.x, high.y)).r * low_weight.x + texture(field, high).r * high_weight.x;
	return smoothstep(0.5 - width, 0.5 + width, a * low_weight.y + b * high_weight.y);
}

float ketchup_noise(vec2 position) {
	vec2 cell = floor(position);
	vec2 within = smoothstep(vec2(0.0), vec2(1.0), fract(position));
	float lower = mix(sauce_hash(cell), sauce_hash(cell + vec2(1.0, 0.0)), within.x);
	float upper = mix(sauce_hash(cell + vec2(0.0, 1.0)), sauce_hash(cell + 1.0), within.x);
	return mix(lower, upper, within.y);
}

// A thinner, warmer edge surrounds the thicker tomato paste. Subtle variation
// stays attached to the surface in world space or in the character's rest pose.
vec3 ketchup_albedo(vec3 position, vec2 surface, float packed_coverage) {
	vec2 field = position.xz + position.y * vec2(0.47, -0.86);
	float pulp = ketchup_noise(field * 7.0);
	float thickness = packed_coverage * 255.0;
	float pooled = smoothstep(5.5, 23.0, thickness);
	vec3 paste = mix(sauce_pigment(2), ketchup_pooled_color.rgb, mix(pulp * 0.34, 0.82, pooled));
	float thin = (1.0 - smoothstep(3.0, 6.0, thickness)) * 0.55;
	vec3 color = mix(paste, ketchup_thin_color.rgb, max(thin, (1.0 - surface.x) * 0.55));
	color *= 1.0 - max(-surface.y, 0.0) * 0.20;
	return mix(color, ketchup_sheen_color.rgb, max(surface.y, 0.0) * 0.32);
}

vec3 sauce_splat_albedo(vec3 position, vec2 surface, float coverage, vec3 sauces,
		float ketchup_gain, float coat_gain) {
	vec3 color = vec3(0.0);
	if (sauces.z > 0.0) {
		color += sauces.z * ketchup_albedo(position, surface, coverage) * ketchup_gain;
	}
	if (sauces.x + sauces.y > 0.0) {
		vec2 field = position.xz + position.y * vec2(0.47, -0.86);
		float texture_grain = ketchup_noise(field * 7.0);
		float layers = coverage * 63.75;
		float buildup = layers / (layers + 3.0);
		float depth = mix(texture_grain * 0.30, 0.72, buildup);
		vec3 light = sauces.x * mayo_splat_color.rgb + sauces.y * mustard_splat_color.rgb;
		vec3 thick = sauces.x * mayo_splat_pooled.rgb + sauces.y * mustard_splat_pooled.rgb;
		vec3 paste = mix(light, thick, depth);
		float rim = clamp((1.0 - surface.x) * 0.48 + max(surface.y, 0.0) * 0.30, 0.0, 1.0);
		color += mix(paste * (1.0 - max(-surface.y, 0.0) * 0.13), light, rim) * coat_gain;
	}
	return color;
}
