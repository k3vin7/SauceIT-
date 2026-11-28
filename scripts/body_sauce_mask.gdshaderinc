ivec2 sauce_mask_cell(ivec2 cell, ivec2 size, bool wrap_x) {
	int x = wrap_x ? (cell.x + size.x) % size.x : clamp(cell.x, 0, size.x - 1);
	return ivec2(x, clamp(cell.y, 0, size.y - 1));
}

float sauce_mask_byte(sampler2D mask, ivec2 cell) {
	return floor(texelFetch(mask, cell, 0).r * 255.0 + 0.5);
}

// An empty cell can borrow only from the three other taps of the filtered mask.
float sauce_mask_kind(sampler2D mask, vec2 at, ivec2 size, bool wrap_x, float own) {
	if (own >= 4.0) {
		return mod(own, 4.0);
	}
	ivec2 base = ivec2(floor(at - 0.5));
	ivec2 cell = ivec2(floor(at));
	ivec2 offset = ivec2(1) - 2 * (cell - base);
	float horizontal = sauce_mask_byte(mask, sauce_mask_cell(cell + ivec2(offset.x, 0), size, wrap_x));
	float vertical = sauce_mask_byte(mask, sauce_mask_cell(cell + ivec2(0, offset.y), size, wrap_x));
	float diagonal = sauce_mask_byte(mask, sauce_mask_cell(cell + offset, size, wrap_x));
	vec2 fraction = abs(fract(at) - 0.5);
	float horizontal_weight = horizontal * fraction.x * (1.0 - fraction.y);
	float vertical_weight = vertical * fraction.y * (1.0 - fraction.x);
	float diagonal_weight = diagonal * fraction.x * fraction.y;
	float best = horizontal_weight >= vertical_weight ? horizontal : vertical;
	if (diagonal_weight > max(horizontal_weight, vertical_weight)) {
		best = diagonal;
	}
	return mod(best, 4.0);
}

float sauce_mask_sample(sampler2D mask, vec2 uv, ivec2 size, bool wrap_x) {
	vec2 at = uv * vec2(size);
	float own = sauce_mask_byte(mask, sauce_mask_cell(ivec2(floor(at)), size, wrap_x));
	return sauce_mask_kind(mask, at, size, wrap_x, own);
}

// Blend the sauce colours between texel centres instead of switching colour
// at the square edge of a gameplay cell. Empty neighbours contribute no hue.
vec3 sauce_mask_blend(sampler2D mask, vec2 at, ivec2 size) {
	vec2 sample_pos = at - 0.5;
	ivec2 base = ivec2(floor(sample_pos));
	vec2 blend = fract(sample_pos);
	vec4 packed = vec4(
		sauce_mask_byte(mask, sauce_mask_cell(base, size, false)),
		sauce_mask_byte(mask, sauce_mask_cell(base + ivec2(1, 0), size, false)),
		sauce_mask_byte(mask, sauce_mask_cell(base + ivec2(0, 1), size, false)),
		sauce_mask_byte(mask, sauce_mask_cell(base + ivec2(1, 1), size, false)));
	vec4 weight = vec4((1.0 - blend.x) * (1.0 - blend.y), blend.x * (1.0 - blend.y),
		(1.0 - blend.x) * blend.y, blend.x * blend.y) * step(vec4(4.0), packed);
	vec4 kinds = mod(packed, 4.0);
	float mustard = dot(weight, 1.0 - step(vec4(0.5), abs(kinds - 1.0)));
	float ketchup = dot(weight, 1.0 - step(vec4(0.5), abs(kinds - 2.0)));
	float total = dot(weight, vec4(1.0));
	return total > 0.0 ? vec3(max(0.0, total - mustard - ketchup), mustard, ketchup) / total
		: vec3(1.0, 0.0, 0.0);
}
