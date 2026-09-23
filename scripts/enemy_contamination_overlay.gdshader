shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

// Draw only the painted cells over the imported hamburger materials.
//
// **Each mesh is mapped from its rest pose, not from where it is now.** The
// colliders the sauce actually lands on do not animate -- they are the burger's
// three tiers and its arms, fixed to the body -- so the painter is recording
// against the rest pose whether it means to or not. Mapping the drawn vertices
// by their animated position instead made the two disagree the moment anything
// moved: through the death clip the parts travel 1.3 m to 3.5 m in the body's
// own space, and the stain slid off the monster as it went over. Walking did a
// milder version of the same thing to the arms.
//
// So the matrix is per mesh and captured once, at build, rather than the body's
// live inverse pushed every frame. It is the mesh's own place in the body, and
// the animation moves the mesh with the stain painted on it.
uniform sampler2D mask_texture : filter_linear, repeat_enable, hint_default_black;
uniform vec4 mayo_color : source_color = vec4(1.0, 0.941, 0.659, 1.0);
uniform float body_height = 4.1;
// Where this mesh sits in the body, in the pose it was imported in.
uniform mat4 rest_to_body;
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

// The caps. The side chart maps a point by its angle and its height and throws
// the radius away, which is exact on a vertical wall and degenerate on a
// horizontal one -- a stain on a flat top draws as a streak from the centre to
// the rim rather than as a blob. So the mask carries three charts stacked in
// the one texture: the underside below the side band, the crown above it, both
// polar, with the radius from the axis standing in for the height. u is the
// angle in all three, so the seam still wraps across the whole texture.
//
// Which chart a fragment reads is decided by the way it faces, exactly as the
// painter decides it. Hard selection, not a blend: a blend would mean painting
// several charts per splat, and the splat is what travels over the wire.
uniform float cap_depth = 0.0;
uniform float cap_normal_cut = 0.7;

// The chart's own v, in metres, for a point and the way it faces.
vec2 chart_uv(vec3 about, float up, float height_of_body) {
	float total = height_of_body + cap_depth * 2.0;
	float v = about.y;
	if (cap_depth > 0.0 && abs(up) >= cap_normal_cut) {
		float rim = min(length(about.xz), cap_depth);
		v = sign(up) * (height_of_body * 0.5 + rim);
	}
	return vec2(
		atan(about.x, about.z) / TAU + 0.5,
		clamp(v / total + 0.5, 0.0, 1.0));
}


varying vec3 body_position;
varying vec3 body_normal;

void vertex() {
	body_position = (rest_to_body * vec4(VERTEX, 1.0)).xyz;
	body_normal = (rest_to_body * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 about = body_position - axis_offset;
	vec2 uv = chart_uv(about, normalize(body_normal).y, body_height);
	if (texture(mask_texture, uv).r < paint_threshold) {
		discard;
	}
	ALBEDO = mayo_color.rgb;
	ROUGHNESS = 0.34;
	METALLIC = 0.0;
}
