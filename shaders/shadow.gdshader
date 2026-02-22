shader_type canvas_item;
render_mode unshaded;

// Shadow darkness (0.5 = strong near light, 0.1 = faint far from light)
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Dark silhouette — only alpha from the original texture matters
	COLOR = vec4(0.0, 0.0, 0.0, tex.a * shadow_opacity);
}
