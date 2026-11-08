shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform float phase = 0.0;
varying vec3 local_surface;
varying flat vec3 local_camera;

void vertex() {
	local_surface = VERTEX;
	local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yxz + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float tongue(vec3 p, vec2 base, float height, float width, vec2 bend) {
	float rise = clamp(p.y / height, 0.0, 1.0);
	float taper = pow(1.0 - rise, 0.84);
	float radius = width * (0.79 + 0.26 * smoothstep(0.0, 0.22, rise)) * taper;
	vec2 centre = base * (1.0 - rise * 0.45) + bend * rise * rise;
	return min(radius - length((p.xz - centre) * vec2(1.0, 1.16)), (height - p.y) * 1.6);
}

vec4 flame_sample(vec3 p, float t) {
	float h = p.y;
	vec2 sway = vec2(sin(t * 4.1 - h * 8.8), cos(t * 3.4 - h * 7.2)) * 0.23;
	float centre = tongue(p, vec2(-0.045, 0.0), 0.86 + sin(t * 5.1) * 0.075,
		0.62, sway);
	float left = tongue(p, vec2(-0.34, 0.05), 0.55 + sin(t * 4.4 + 2.3) * 0.115,
		0.36, sway + vec2(-0.23, 0.07));
	float right = tongue(p, vec2(0.32, -0.10), 0.68 + sin(t * 5.7 + 3.9) * 0.105,
		0.37, sway + vec2(0.20, -0.04));
	float envelope = max(centre, max(left, right));
	// Moving noise stretches upward inside the volume and breaks the tips into tongues.
	float ripple = noise3(vec3(p.x * 3.9, h * 4.5 - t * 3.3, p.z * 3.9)) - 0.5;
	float fine = noise3(vec3(p.x * 8.5, h * 8.2 - t * 5.0, p.z * 8.5)) - 0.5;
	float contour = envelope + (ripple * 0.22 + fine * 0.075) * smoothstep(0.06, 0.46, h);
	float density = smoothstep(-0.055, 0.16, contour)
		* smoothstep(0.0, 0.072, h) * (1.0 - smoothstep(0.62, 0.98, h));
	float heat = clamp(0.56 * smoothstep(-0.02, 0.25, contour)
		+ 0.50 * (1.0 - h) + ripple * 0.09, 0.0, 1.0);
	vec3 red = vec3(0.96, 0.16, 0.025);
	vec3 orange = vec3(1.0, 0.43, 0.049);
	vec3 yellow = vec3(1.0, 0.77, 0.21);
	vec3 cream = vec3(1.0, 0.94, 0.61);
	vec3 color = mix(red, orange, smoothstep(0.09, 0.48, heat));
	color = mix(color, yellow, smoothstep(0.46, 0.78, heat));
	color = mix(color, cream, smoothstep(0.77, 1.0, heat));
	return vec4(color, density);
}

void fragment() {
	vec3 ray = normalize(local_surface - local_camera);
	vec3 side = step(vec3(0.0), ray);
	vec3 safe_ray = mix(vec3(-1.0), vec3(1.0), side) * max(abs(ray), vec3(0.0001));
	vec3 exits = (side - vec3(0.5) - local_surface) / safe_ray;
	float length_inside = max(0.0, min(exits.x, min(exits.y, exits.z)));
	float stride = length_inside / 28.0;
	vec3 accumulated = vec3(0.0);
	float opacity = 0.0;
	for (int i = 0; i < 28; i++) {
		vec3 point = local_surface + ray * (float(i) + 0.5) * stride;
		vec4 flame = flame_sample(vec3(point.x * 2.0, point.y + 0.5, point.z * 2.0),
			TIME + phase);
		float coverage = 1.0 - exp(-flame.a * stride * 12.0);
		accumulated += (1.0 - opacity) * coverage * flame.rgb;
		opacity += (1.0 - opacity) * coverage;
		if (opacity > 0.99) {
			break;
		}
	}
	if (opacity < 0.01) {
		discard;
	}
	ALBEDO = accumulated / opacity;
	ALPHA = opacity;
}
