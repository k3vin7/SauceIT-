shader_type spatial;
// A canopy is a sheet, so both of its sides are there to be seen: without this
// the roof vanishes when you walk under the stall and look up, because the only
// faces it has point outwards.
render_mode cull_disabled;

// The roof's mask, sampled by unrolling the cone flat.
//
// A cone is *developable*: it can be laid out flat with no distortion at all,
// unlike a sphere or a capsule's caps. The classic net is a sector -- cut the
// cone up one side and flatten it -- and a point at slant distance s from the
// apex and angle t lands at polar (s, t * R/L), where L is the slant length.
// Distances survive that exactly, so a splat that is 0.4 m across on the roof
// is 0.4 m across in the grid.
//
// What was here before mapped (angle, height) the way a body does, which is
// right for a capsule and wrong for a cone: every angle meets at the apex, so a
// splat was a wedge that was the right width at the base and tapered to nothing
// at the point. A roof with a few shots on it came out as a sunburst.
uniform sampler2D mask_texture : filter_linear, repeat_disable, hint_default_black;
uniform vec4 clean_color : source_color;
uniform vec4 mayo_color : source_color;
uniform float cone_radius = 1.0;
uniform float cone_height = 1.0;
// The unrolled sector fits a square this many metres on a side.
uniform float grid_extent = 1.0;
uniform float clean_roughness = 0.75;
uniform float mayo_roughness = 0.34;

const float THRESHOLD = 0.5;

varying vec3 surface_position;

void vertex() {
	surface_position = VERTEX;
}

void fragment() {
	float slant = sqrt(cone_radius * cone_radius + cone_height * cone_height);
	// Height is what places a point on the cone, not its distance from the
	// axis: the two agree on the surface, and height is defined on the apex.
	float from_apex = slant * clamp(
		(cone_height * 0.5 - surface_position.y) / cone_height, 0.0, 1.0);
	float around = atan(surface_position.x, surface_position.z) * (cone_radius / slant);
	vec2 flat_position = vec2(from_apex * cos(around), from_apex * sin(around));
	vec2 uv = flat_position / grid_extent + 0.5;
	float coverage = texture(mask_texture, uv).r;
	float painted = step(THRESHOLD, coverage);
	ALBEDO = mix(clean_color.rgb, mayo_color.rgb, painted);
	ROUGHNESS = mix(clean_roughness, mayo_roughness, painted);
	METALLIC = 0.0;
}
