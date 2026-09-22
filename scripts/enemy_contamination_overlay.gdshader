shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Draw only the painted cells over the imported hamburger materials. Positions
// are converted from each animated mesh into MayoEnemy's body space, keeping
// the CPU's cylindrical grid and the visible splat in the same coordinate
// system even though the model is split into many skinned pieces.
uniform sampler2D mask_texture : filter_linear, repeat_enable, hint_default_black;
uniform vec4 mayo_color : source_color = vec4(1.0, 0.941, 0.659, 1.0);
uniform float body_height = 4.1;
uniform mat4 world_to_body;
// Half a single splat's worth, normalised. **Not 0.5.** The mask holds a
// thickness now, 0 to 255, rather than a painted flag that was either 0 or 255
// -- so a cut at 0.5 means a cell has to be hit about 128 times before any of
// it is drawn, which reads as sauce not sticking at all.
uniform float paint_threshold = 0.00196;

// The axis the unwrap turns about, in body space. Not always the origin: the
// burger monster's body sits a third of a metre back of its own node, so
// measuring the angle about (0,0) skews a stain by up to ten degrees around
// its sides -- worst exactly where a player aims, on the flanks.
uniform vec3 axis_offset = vec3(0.0);

varying vec3 body_position;

void vertex() {
	body_position = (world_to_body * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 about = body_position - axis_offset;
	vec2 uv = vec2(
		atan(about.x, about.z) / TAU + 0.5,
		clamp(body_position.y / body_height + 0.5, 0.0, 1.0));
	if (texture(mask_texture, uv).r < paint_threshold) {
		discard;
	}
	ALBEDO = mayo_color.rgb;
	ROUGHNESS = 0.34;
	METALLIC = 0.0;
}
