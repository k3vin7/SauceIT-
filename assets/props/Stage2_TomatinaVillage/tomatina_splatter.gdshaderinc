float tomato_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// The main blot, torn edges and small satellite drops share a world-space cell.
float tomato_splat(vec2 position, float spacing, float chance) {
	vec2 grid = position / spacing;
	vec2 cell = floor(grid);
	float pick = tomato_hash(cell);
	float aa = clamp(length(fwidth(grid)), 0.004, 0.07);
	vec2 jitter = vec2(tomato_hash(cell + 5.17), tomato_hash(cell - 7.83));
	float size = mix(0.071, 0.265, jitter.x * sqrt(jitter.x));
	// Reserve room for the full outline and its antialiased edge.
	float inset = size * 1.50 + 0.084;
	vec2 centre = mix(vec2(inset), vec2(1.0 - inset), jitter);
	vec2 point = fract(grid);
	float rotation = pick * 6.2831853;
	vec2 axis = vec2(cos(rotation), sin(rotation));
	vec2 side = vec2(-axis.y, axis.x);
	vec2 relative = point - centre;
	vec2 p = vec2(dot(relative, axis), dot(relative, side));
	float angle = atan(p.y + 0.0001, p.x);
	float outline = size * (1.0 + sin(angle * 5.0 + pick * 13.0) * 0.16
		+ sin(angle * 9.0) * 0.10);
	float core = 1.0 - smoothstep(outline - aa, outline + aa, length(p * vec2(0.84, 1.24)));
	vec2 drop_radius = size * vec2(0.22, 0.13);
	vec2 drop1_inset = vec2(drop_radius.x + 0.07);
	vec2 drop2_inset = vec2(drop_radius.y + 0.07);
	vec2 drop1_centre = clamp(centre + axis * (size * 1.64 + 0.023) + side * size * 0.36,
		drop1_inset, vec2(1.0) - drop1_inset);
	vec2 drop2_centre = clamp(centre - axis * size * 0.90 - side * (size * 1.56 + 0.02),
		drop2_inset, vec2(1.0) - drop2_inset);
	float drop1 = 1.0 - smoothstep(drop_radius.x, drop_radius.x + aa, length(point - drop1_centre));
	float drop2 = 1.0 - smoothstep(drop_radius.y, drop_radius.y + aa, length(point - drop2_centre));
	return step(pick, chance) * max(core, max(drop1 * 0.9, drop2 * 0.76));
}

// Use the same world-space pattern on the intact and replacement facades.
float tomato_wall_stain(vec2 position) {
	float blot = tomato_splat(position, 1.43, 0.92);
	float splash = tomato_splat(position + vec2(-1.48, 1.17), 0.86, 0.74);
	float dots = tomato_splat(position + vec2(3.31, 2.5), 0.44, 0.71);
	return max(blot, max(splash * 0.91, dots * 0.80));
}

vec3 tomato_wall_stain_color(vec2 position) {
	float grain = tomato_hash(floor(position * 0.69));
	vec3 ketchup = mix(vec3(0.26, 0.025, 0.017), vec3(0.43, 0.049, 0.028), grain);
	return mix(ketchup, vec3(0.28, 0.13, 0.095), 0.32);
}
