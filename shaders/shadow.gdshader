shader_type canvas_item;
render_mode unshaded;

// Shadow direction in radians (points away from light source)
uniform float shadow_angle : hint_range(-3.14159, 3.14159) = 0.785;
// Shadow stretch factor (1.5 = long/close to light, 0.3 = short/far from light)
uniform float shadow_length : hint_range(0.0, 3.0) = 0.6;
// Shadow darkness (0.5 = strong near light, 0.1 = faint far from light)
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	// UV.y: 0 = top (head), 1 = bottom (feet)
	// Anchor feet in place; displace head in shadow direction
	float head_factor = 1.0 - UV.y;

	// Project top vertices outward along shadow angle
	// 24.0 scales shadow_length to pixel displacement (~0.75x sprite height at length 1.0)
	vec2 offset = vec2(cos(shadow_angle), sin(shadow_angle)) * head_factor * shadow_length * 24.0;
	VERTEX += offset;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Dark silhouette — only alpha from the original texture matters
	COLOR = vec4(0.0, 0.0, 0.0, tex.a * shadow_opacity);
}
