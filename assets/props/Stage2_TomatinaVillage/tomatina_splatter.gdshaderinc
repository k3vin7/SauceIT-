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
	vec2 centre = vec2(tomato_hash(cell + 5.17), tomato_hash(cell - 7.83));
	vec2 p = fract(grid) - mix(vec2(0.30), vec2(0.70), centre);
	float rotation = pick * 6.2831853;
	vec2 axis = vec2(cos(rotation), sin(rotation));
	p = vec2(dot(p, axis), dot(p, vec2(-axis.y, axis.x)));
	float angle = atan(p.y + 0.0001, p.x);
	float size = mix(0.043, 0.21, centre.x * centre.x);
	float outline = size * (1.0 + sin(angle * 5.0 + pick * 13.0) * 0.16
		+ sin(angle * 9.0) * 0.10);
	float core = 1.0 - smoothstep(outline - aa, outline + aa, length(p * vec2(0.84, 1.24)));
	float d1 = length(p - vec2(size * 1.64 + 0.023, size * 0.36));
	float d2 = length(p + vec2(size * 0.9, size * 1.56 + 0.02));
	float drop1 = 1.0 - smoothstep(size * 0.22, size * 0.22 + aa, d1);
	float drop2 = 1.0 - smoothstep(size * 0.13, size * 0.13 + aa, d2);
	return step(pick, chance) * max(core, max(drop1 * 0.9, drop2 * 0.76));
}
