shader_type sky;

uniform vec4 horizon_color : source_color = vec4(0.69, 0.88, 0.91, 1.0);
uniform vec4 zenith_color : source_color = vec4(0.20, 0.52, 0.79, 1.0);
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.97, 0.91, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.66, 0.78, 0.89, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.92, 0.72, 1.0);

float ellipse(vec2 point, vec2 center, vec2 radius) {
	vec2 offset = (point - center) / radius;
	return 1.0 - dot(offset, offset);
}

vec2 cloud_bank(vec2 sky_angle, vec2 center, vec2 scale, float opacity) {
	// Wrap azimuth so a cloud crossing the panorama seam stays continuous.
	vec2 delta = sky_angle - center;
	delta.x = mod(delta.x + PI, TAU) - PI;
	vec2 point = delta / scale;
	if (abs(point.x) > 1.08 || abs(point.y) > 0.94) {
		return vec2(0.0);
	}

	// Rounded tops and a broad, flat base give each bank two readable tones.
	float body = ellipse(point, vec2(0.0, -0.20), vec2(0.98, 0.37));
	body = max(body, ellipse(point, vec2(-0.54, -0.03), vec2(0.38, 0.40)));
	body = max(body, ellipse(point, vec2(-0.16, 0.26), vec2(0.47, 0.57)));
	body = max(body, ellipse(point, vec2(0.38, 0.10), vec2(0.44, 0.46)));
	float silhouette = smoothstep(-0.045, 0.05, body);
	float upper_edge = point.y + 0.10 - 0.09 * sin(point.x * 4.5 + 0.30);
	float light = smoothstep(-0.022, 0.034, upper_edge);
	float alpha = opacity * silhouette;
	return vec2(alpha * light, alpha);
}

vec3 draw_cloud(vec3 background, vec2 angle, vec2 center, vec2 scale, float opacity) {
	vec2 cloud = cloud_bank(angle, center, scale, opacity);
	return mix(background, cloud_shade.rgb, cloud.y)
			+ (cloud_lit.rgb - cloud_shade.rgb) * cloud.x;
}

void sky() {
	float height = max(EYEDIR.y, 0.0);
	vec3 color = mix(horizon_color.rgb, zenith_color.rgb, pow(height, 0.65));
	if (!AT_CUBEMAP_PASS && EYEDIR.y > 0.0) {
		if (LIGHT0_ENABLED) {
			float toward_sun = dot(EYEDIR, LIGHT0_DIRECTION);
			float halo = smoothstep(0.935, 0.998, toward_sun);
			float disk = smoothstep(0.9980, 0.99835, toward_sun);
			color = mix(color, sun_color.rgb, max(disk, halo * 0.26));
		}

		vec2 angle = vec2(atan(EYEDIR.x, EYEDIR.z), asin(clamp(EYEDIR.y, -1.0, 1.0)));
		color = draw_cloud(color, angle, vec2(-2.56, 0.17), vec2(0.23, 0.10), 0.79);
		color = draw_cloud(color, angle, vec2(-1.97, 0.37), vec2(0.38, 0.18), 0.95);
		color = draw_cloud(color, angle, vec2(-1.14, 0.22), vec2(0.24, 0.08), 0.82);
		color = draw_cloud(color, angle, vec2(-0.65, 0.41), vec2(-0.43, 0.15), 0.98);
		color = draw_cloud(color, angle, vec2(0.37, 0.25), vec2(0.34, 0.12), 0.88);
		color = draw_cloud(color, angle, vec2(1.16, 0.49), vec2(0.40, 0.19), 0.95);
		color = draw_cloud(color, angle, vec2(1.98, 0.27), vec2(-0.38, 0.12), 0.92);
		color = draw_cloud(color, angle, vec2(2.85, 0.44), vec2(0.48, 0.18), 0.96);
	}
	COLOR = color;
}
