shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

// 0: shower particles, 1: coherent jet, 2: airborne mist, 3: airborne droplets.
uniform int flow_type = 1;
uniform float start_radius = 0.05;
uniform float end_radius = 0.23;
uniform float spread_distance = 8.0;
uniform float fan_widening = 0.0;
uniform float flow_duration = 0.0;
uniform float flow_first_age = 0.0;
uniform float flow_last_age = -1.0;
uniform vec3 flow_velocity = vec3(0.0);
uniform float flow_gravity = 9.8;
uniform float flow_drag = 1.0;
uniform vec3 flow_correction = vec3(0.0);
uniform vec3 flow_tip_offset = vec3(0.0);

varying float stream_distance;
varying float total_distance;
varying float back_distance;
varying float droplet_opacity;

float hash_cell(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Wrap around the circumference so the pattern has no seam.
float stream_noise(vec2 uv, float columns) {
	vec2 cell = floor(uv);
	vec2 sub = fract(uv);
	vec2 t = sub * sub * (3.0 - 2.0 * sub);
	float x = mod(cell.x, columns);
	float next_x = mod(cell.x + 1.0, columns);
	float a = mix(hash_cell(vec2(x, cell.y)), hash_cell(vec2(next_x, cell.y)), t.x);
	float b = mix(hash_cell(vec2(x, cell.y + 1.0)), hash_cell(vec2(next_x, cell.y + 1.0)), t.x);
	return mix(a, b, t.y);
}

void vertex() {
	// The shower emitter already positions and rotates each droplet.
	stream_distance = 0.0;
	total_distance = 0.0;
	back_distance = 0.0;
	droplet_opacity = 1.0;
	if (flow_type != 0) {
		float along = VERTEX.y + 0.5;
		float seed = 0.0;
		float turn = 0.0;
		droplet_opacity = 1.0;
		if (flow_type == 3) {
			float id = float(INSTANCE_ID);
			seed = hash_cell(vec2(id, 11.0));
			turn = TAU * hash_cell(vec2(id, 30.0));
			along = fract(hash_cell(vec2(id, 7.0)) + TIME * mix(0.48, 1.25, seed));
			droplet_opacity = smoothstep(0.0, 0.17, along) * (1.0 - smoothstep(0.78, 1.0, along));
		}
		float last_age = flow_last_age < 0.0 ? flow_duration : flow_last_age;
		float age = mix(flow_first_age, last_age, along);
		float progress = age / max(flow_duration, 0.001);
		float drag = exp(-flow_drag * age);
		vec3 settling = vec3(0.0, -flow_gravity / flow_drag, 0.0);
		vec3 relative_velocity = flow_velocity - settling;
		vec3 centre = relative_velocity * ((1.0 - drag) / flow_drag) + settling * age;
		centre += flow_tip_offset * (1.0 - progress);
		vec3 tangent = normalize(relative_velocity * drag + settling + (flow_correction - flow_tip_offset) / max(flow_duration, 0.001));
		vec3 around = normalize(cross(vec3(1.0, 0.0, 0.0), tangent));
		stream_distance = length(flow_velocity) * ((1.0 - drag) / flow_drag);
		total_distance = length(flow_velocity) * ((1.0 - exp(-flow_drag * last_age)) / flow_drag);
		back_distance = length(flow_velocity) * ((1.0 - exp(-flow_drag * flow_first_age)) / flow_drag);
		float width = mix(start_radius, end_radius, clamp(stream_distance / spread_distance, 0.0, 1.0));
		// Gradually flare across the jet, keeping the vertical spread rounder.
		float fan = 1.0 + fan_widening * smoothstep(0.0, spread_distance * 2.2, stream_distance);
		if (flow_type == 3) {
			vec3 spread = vec3(cos(turn) * fan, 0.0, 0.0) + around * sin(turn);
			float separation = width * mix(0.24, 0.96, seed) * smoothstep(0.0, 3.4, stream_distance);
			centre += spread * separation;
			float scale = mix(0.48, 1.66, seed);
			NORMAL = vec3(NORMAL.x, 0.0, 0.0) + tangent * NORMAL.y + around * NORMAL.z;
			VERTEX = centre + flow_correction * progress + scale *
				(vec3(VERTEX.x, 0.0, 0.0) + tangent * VERTEX.y + around * VERTEX.z);
		} else {
			float axial = stream_distance - TIME * 15.0;
			float wake = stream_noise(vec2(UV.x * 9.0, axial * 3.0), 9.0) - 0.5;
			width *= 1.0 + wake * (0.12 + 0.22 * smoothstep(1.5, 8.0, stream_distance));
			vec3 rim_offset = vec3(VERTEX.x * fan, 0.0, 0.0) + around * VERTEX.z;
			NORMAL = vec3(NORMAL.x / fan, 0.0, 0.0) + around * NORMAL.z;
			VERTEX = centre + flow_correction * progress + rim_offset * width;
		}
	}
}

vec4 whitewater(vec3 pale_water, float bubbles, float flash, float fresnel) {
	// Alpha lets the scene show through the bubble gaps in the same pass.
	float opacity = clamp(0.69 + 0.30 * bubbles + 0.21 * flash + 0.20 * fresnel, 0.0, 1.0);
	vec3 foam_tint = mix(pale_water * 0.89, vec3(1.0), bubbles * 0.67 + flash * 0.33);
	return vec4(foam_tint, opacity);
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	float facing = clamp(dot(normal, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	vec3 half_vector = normalize(VIEW + normalize(vec3(-0.4, 0.67, 0.53)));
	float flash = pow(max(dot(normal, half_vector), 0.0), 28.0);
	vec3 pale_water = vec3(0.90, 0.96, 0.98);
	if (flow_type == 0) {
		float aeration = stream_noise(vec2(UV.x * 7.0, UV.y * 3.2 - TIME * 2.3), 7.0);
		float bubbles = smoothstep(0.27, 0.74, aeration);
		vec4 water = whitewater(pale_water, bubbles, flash, fresnel);
		ALBEDO = water.rgb;
		ALPHA = water.a * (0.62 + 0.29 * bubbles + 0.08 * flash) * smoothstep(0.01, 0.28, facing);
	} else if (flow_type == 3) {
		ALBEDO = mix(pale_water * 0.93, vec3(1.0), max(flash, fresnel * 0.55));
		ALPHA = (0.67 + 0.30 * flash) * smoothstep(0.0, 0.26, facing) * droplet_opacity;
	} else {
		float travel = stream_distance - TIME * 16.0;
		float long_ridges = stream_noise(vec2(UV.x * 14.0, travel * 1.7), 14.0);
		float grit = flow_type == 1
			? stream_noise(vec2(UV.x * 32.0 + long_ridges, travel * 8.0), 32.0)
			: long_ridges;
		float strands = smoothstep(0.30, 0.83, long_ridges * 0.63 + grit * 0.37);
		float far_water = smoothstep(2.0, 13.0, stream_distance);
		float tail = smoothstep(0.02, mix(0.22, 1.1, far_water), total_distance - stream_distance);
		float cutoff = flow_first_age > 0.0 ? smoothstep(0.0, 0.45, stream_distance - back_distance) : 1.0;
		if (flow_type == 1) {
			float bubbles = smoothstep(0.31, 0.77, long_ridges * 0.64 + grit * 0.36);
			vec4 water = whitewater(pale_water, bubbles, flash, fresnel);
			ALBEDO = water.rgb;
			float breakup = mix(0.92 + 0.08 * bubbles, 0.52 + 0.40 * strands, far_water);
			float front = mix(0.07 + 0.22 * strands, 1.0, tail);
			ALPHA = water.a * breakup * front * cutoff * smoothstep(0.02, 0.27, facing);
		} else {
			float volume = smoothstep(0.28, 0.85, facing);
			float entrance = smoothstep(0.0, 2.4, stream_distance);
			ALBEDO = mix(pale_water, vec3(1.0), flash * 0.38);
			ALPHA = 0.24 * (0.10 + 0.90 * strands) * volume * entrance * tail * cutoff;
		}
	}
}
