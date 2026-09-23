shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Draw only the painted cells over an imported multi-mesh character. Positions
// are converted from each animated mesh into MayoEnemy's body space, keeping
// the CPU cylindrical grid and visible splat aligned while preserving every
// authored material underneath the overlay.
uniform sampler2D mask_texture : filter_linear, repeat_enable, hint_default_black;
uniform vec4 mayo_color : source_color = vec4(1.0, 0.941, 0.659, 1.0);
uniform float body_height = 4.1;
uniform mat4 world_to_body;

varying vec3 body_position;

void vertex() {
	body_position = (world_to_body * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(
		atan(body_position.x, body_position.z) / TAU + 0.5,
		clamp(body_position.y / body_height + 0.5, 0.0, 1.0));
	if (texture(mask_texture, uv).r < 0.5) {
		discard;
	}
	ALBEDO = mayo_color.rgb;
	ROUGHNESS = 0.34;
	METALLIC = 0.0;
}
