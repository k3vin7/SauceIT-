shader_type sky;

uniform vec4 horizon_color : source_color = vec4(0.70, 0.84, 0.91, 1.0);
uniform vec4 zenith_color : source_color = vec4(0.16, 0.43, 0.68, 1.0);
uniform vec4 haze_color : source_color = vec4(0.93, 0.87, 0.76, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 cloud_mid : source_color = vec4(0.78, 0.84, 0.86, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.51, 0.62, 0.69, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);

float hash31(vec3 point) {
	point = fract(point * 0.1031);
	point += dot(point, point.yzx + 33.33);
	return fract((point.x + point.y) * point.z);
}

float value_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 local = fract(point);
	vec3 blend = local * local * (3.0 - 2.0 * local);
	float x00 = mix(hash31(cell), hash31(cell + vec3(1.0, 0.0, 0.0)), blend.x);
	float x10 = mix(hash31(cell + vec3(0.0, 1.0, 0.0)), hash31(cell + vec3(1.0, 1.0, 0.0)), blend.x);
	float x01 = mix(hash31(cell + vec3(0.0, 0.0, 1.0)), hash31(cell + vec3(1.0, 0.0, 1.0)), blend.x);
	float x11 = mix(hash31(cell + vec3(0.0, 1.0, 1.0)), hash31(cell + vec3(1.0, 1.0, 1.0)), blend.x);
	return mix(mix(x00, x10, blend.y), mix(x01, x11, blend.y), blend.z);
}

float fbm(vec3 point) {
	float sum = 0.0;
	float weight = 0.52;
	mat3 turn = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(point) * weight;
		point = turn * point * 2.03 + vec3(7.1, 3.7, 5.4);
		weight *= 0.51;
	}
	return sum;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float height = clamp(direction.y, 0.0, 1.0);
	float horizon_haze = exp(-height * 8.5);
	vec3 color = mix(horizon_color.rgb, zenith_color.rgb, pow(height, 0.58));
	color = mix(color, haze_color.rgb, horizon_haze * 0.34);

	vec3 sun_direction = normalize(vec3(-0.35, 0.73, 0.58));
	if (LIGHT0_ENABLED) {
		sun_direction = normalize(LIGHT0_DIRECTION);
	}
	float toward_sun = max(dot(direction, sun_direction), 0.0);
	float sun_glow = pow(toward_sun, 18.0) * 0.22 + pow(toward_sun, 180.0) * 0.82;
	color = mix(color, sun_color.rgb, clamp(sun_glow, 0.0, 0.92));

	if (!AT_CUBEMAP_PASS && direction.y > 0.025) {
		// Three-dimensional noise is sampled on the sky dome, so cloud detail
		// remains continuous around the panorama seam and does not look stamped on.
		vec3 dome = direction * 3.75 + vec3(1.7, 0.2, -2.4);
		float broad = fbm(dome);
		float billow = fbm(direction * 7.4 + vec3(-4.2, 1.3, 6.7));
		float fine = fbm(direction * 15.0 + vec3(8.1, -2.6, 0.7));
		float altitude_mask = smoothstep(0.045, 0.15, height) * (1.0 - smoothstep(0.78, 0.96, height));
		float density = broad * 0.86 + billow * 0.18;
		density += (1.0 - height) * 0.07;
		float cloud = smoothstep(0.525, 0.665, density) * altitude_mask;

		// Sampling slightly toward the sun approximates light penetrating the
		// cloud edge; fine noise keeps the underside from becoming a flat band.
		float lit_sample = fbm(dome + sun_direction * 0.26);
		float edge_light = clamp((density - lit_sample) * 3.2 + 0.46, 0.0, 1.0);
		float underside = clamp(0.34 + height * 0.64 + (fine - 0.5) * 0.16, 0.0, 1.0);
		vec3 cloud_tone = mix(cloud_shadow.rgb, cloud_mid.rgb, underside);
		cloud_tone = mix(cloud_tone, cloud_light.rgb, edge_light * 0.48 + pow(toward_sun, 7.0) * 0.14);
		color = mix(color, cloud_tone, cloud * 0.88);

		// Thin high-altitude streaks break up the empty blue without competing
		// with the heavier cumulus banks near the horizon.
		float cirrus_noise = fbm(vec3(direction.x * 19.0, direction.y * 5.0, direction.z * 3.8) + vec3(2.0, 8.0, -3.0));
		float cirrus = smoothstep(0.71, 0.83, cirrus_noise) * smoothstep(0.40, 0.66, height) * (1.0 - cloud);
		color = mix(color, cloud_light.rgb, cirrus * 0.08);
	}

	COLOR = color;
}
