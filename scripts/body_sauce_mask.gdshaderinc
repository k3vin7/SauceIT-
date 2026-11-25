// Use the cell's own sauce. A fragment on empty space can borrow a neighbour
// because the filtered silhouette extends past the last painted cell centre.
float sauce_mask_sample(sampler2D mask, vec2 uv, ivec2 size, bool wrap_x) {
	ivec2 cell = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
	float own = floor(texelFetch(mask, cell, 0).r * 255.0 + 0.5);
	if (own >= 4.0) {
		return own;
	}

	float best = 0.0;
	float borrowed = 0.0;
	int top = max(cell.y - 1, 0);
	int bottom = min(cell.y + 1, size.y - 1);
	for (int y = top; y <= bottom; y++) {
		for (int dx = -1; dx <= 1; dx++) {
			int column = cell.x + dx;
			int x = wrap_x ? int(mod(float(column), float(size.x))) : clamp(column, 0, size.x - 1);
			float packed = floor(texelFetch(mask, ivec2(x, y), 0).r * 255.0 + 0.5);
			float depth = floor(packed / 4.0);
			if (depth > best) {
				best = depth;
				borrowed = packed;
			}
		}
	}
	return borrowed;
}
