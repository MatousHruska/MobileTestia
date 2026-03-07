shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.3);
uniform sampler2D shadow_mask : hint_default_white;
// Atlas region in UV space: xy = origin, zw = size. Default (0,0,1,1) = full texture.
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	// Remap atlas UV to frame-local 0-1 so the mask aligns with every frame
	vec2 mask_uv = (UV - frame_uv_rect.xy) / frame_uv_rect.zw;
	float m = texture(shadow_mask, mask_uv).r;
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a * m);
}
