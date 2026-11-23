shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform float distress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 color = texture(scene_color, SCREEN_UV).rgb;
	float lightness = dot(color, vec3(0.213, 0.715, 0.072));
	vec3 cold = mix(color, vec3(lightness) * vec3(0.90, 1.03, 1.12), 0.52);
	cold = max(vec3(0.0), (cold - vec3(0.18)) * 1.16 + vec3(0.14));
	vec2 edge = (SCREEN_UV - vec2(0.50, 0.48)) * vec2(1.12, 1.0);
	cold *= 0.86 - 0.49 * smoothstep(0.30, 0.68, length(edge));
	COLOR = vec4(mix(color, cold, distress), 1.0);
}
