shader_type canvas_item;
render_mode blend_mix;

// The UV reference map - each pixel has a unique color
// Position of a color in this texture = UV coordinates for skin lookup
uniform sampler2D uv_map : hint_default_white, filter_nearest;

// Skin texture - the actual appearance (pixel-perfect overlay with uv_map)
uniform sampler2D skin : hint_default_white, filter_nearest;

// Size of the UV map for searching
uniform vec2 uv_map_size = vec2(32.0, 32.0);

// Color matching tolerance (for anti-aliasing/compression artifacts)
uniform float color_tolerance : hint_range(0.0, 0.1) = 0.01;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Find UV coordinates by matching color in the UV map
vec2 find_color_in_uvmap(vec3 target_color) {
    // Search through UV map to find matching color
    // Returns the normalized UV position where the color is found

    for (float y = 0.0; y < uv_map_size.y; y += 1.0) {
        for (float x = 0.0; x < uv_map_size.x; x += 1.0) {
            vec2 sample_uv = vec2(x + 0.5, y + 0.5) / uv_map_size;
            vec4 map_color = texture(uv_map, sample_uv);

            // Only check non-transparent pixels
            if (map_color.a > 0.5) {
                // Check if colors match within tolerance
                vec3 diff = abs(map_color.rgb - target_color);
                if (diff.r < color_tolerance && diff.g < color_tolerance && diff.b < color_tolerance) {
                    return sample_uv;
                }
            }
        }
    }

    // Color not found - return center as fallback
    return vec2(0.5, 0.5);
}

void fragment() {
    // Sample the animation sprite (TEXTURE)
    // This contains colored pixels matching the UV map
    vec4 anim_color = texture(TEXTURE, UV);

    // If alpha is 0, this pixel is transparent
    if (anim_color.a < 0.01) {
        discard;
    }

    // Find where this color appears in the UV map
    vec2 skin_uv = find_color_in_uvmap(anim_color.rgb);

    // Sample the skin texture at the found coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Apply tint (for status effects)
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output: skin color with animation's alpha controlling shape
    COLOR = vec4(final_color.rgb, anim_color.a);
}
