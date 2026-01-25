shader_type canvas_item;
render_mode blend_mix;

// Skin texture - the actual appearance
uniform sampler2D skin : hint_default_white, filter_nearest;

// Visual modifiers (for later use)
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Sample the motion map (the sprite's TEXTURE)
    // This contains UV coordinates encoded in R,G channels
    vec4 motion_data = texture(TEXTURE, UV);

    // If alpha is 0, this pixel is transparent in the motion map
    if (motion_data.a < 0.01) {
        discard;
    }

    // R and G channels encode UV coordinates into skin texture
    // Motion map values 0-255 map to 0.0-1.0
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    // Sample the skin texture at the encoded coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Apply tint (for status effects like poison)
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output: skin color with motion map's alpha controlling shape
    COLOR = vec4(final_color.rgb, motion_data.a * skin_color.a);
}
