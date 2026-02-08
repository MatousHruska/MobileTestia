shader_type canvas_item;
render_mode blend_mix;

// The UV reference map - each pixel has a unique color
// Position of a color in this texture = UV coordinates for skin lookup
// IMPORTANT: No source_color hint! Must be in same color space as TEXTURE
uniform sampler2D uv_map : filter_nearest;

// Skin texture - the actual appearance (pixel-perfect overlay with uv_map)
uniform sampler2D skin : filter_nearest;

// Size of the UV map in pixels
uniform vec2 uv_map_size = vec2(64.0, 64.0);

// Color matching tolerance - must be LESS than half the minimum color distance
// in the UV map. For tightly-packed colors, use near-zero values.
uniform float color_tolerance : hint_range(0.0, 0.1) = 0.002;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Debug modes: 0=normal, 1=show frame colors, 2=show UV position,
// 3=show match success (green=matched, red=fallback), 4=show skin raw
uniform int debug_mode = 0;

// Find UV coordinates by matching color in the UV map
vec2 find_color_in_uvmap(vec3 target_color, out bool found) {
    found = false;

    for (float y = 0.0; y < uv_map_size.y; y += 1.0) {
        for (float x = 0.0; x < uv_map_size.x; x += 1.0) {
            vec2 sample_uv = vec2(x + 0.5, y + 0.5) / uv_map_size;
            vec4 map_color = texture(uv_map, sample_uv);

            // Only check non-transparent pixels
            if (map_color.a > 0.5) {
                vec3 diff = abs(map_color.rgb - target_color);
                if (diff.r < color_tolerance && diff.g < color_tolerance && diff.b < color_tolerance) {
                    found = true;
                    return sample_uv;
                }
            }
        }
    }

    // Color not found - return center as fallback
    return vec2(0.5, 0.5);
}

void fragment() {
    vec4 anim_color = texture(TEXTURE, UV);

    if (anim_color.a < 0.01) {
        discard;
    }

    // Debug mode 1: Show raw frame/TEXTURE colors (bypass lookup entirely)
    if (debug_mode == 1) {
        COLOR = anim_color;
        return;
    }

    // Find where this color appears in the UV map
    bool matched = false;
    vec2 skin_uv = find_color_in_uvmap(anim_color.rgb, matched);

    // Debug mode 2: Visualize the matched UV position as color
    if (debug_mode == 2) {
        COLOR = vec4(skin_uv.x, skin_uv.y, 0.0, anim_color.a);
        return;
    }

    // Debug mode 3: Show match success (green) vs fallback (red)
    if (debug_mode == 3) {
        if (matched) {
            COLOR = vec4(0.0, 1.0, 0.0, anim_color.a); // green = found
        } else {
            COLOR = vec4(1.0, 0.0, 0.0, anim_color.a); // red = fallback
        }
        return;
    }

    // Sample the skin texture at the found coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Debug mode 4: Show raw skin lookup (no tint/flash)
    if (debug_mode == 4) {
        COLOR = vec4(skin_color.rgb, anim_color.a);
        return;
    }

    // Normal rendering: apply tint and flash
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    COLOR = vec4(final_color.rgb, anim_color.a);
}
