shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.3);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a);
}
