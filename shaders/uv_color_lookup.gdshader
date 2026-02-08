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

// Debug: 0.0=normal, 1.0=frame colors, 2.0=UV position,
// 3.0=match status (green/red), 4.0=raw skin
uniform float debug_mode : hint_range(0.0, 4.0, 1.0) = 0.0;

void fragment() {
    vec4 anim_color = texture(TEXTURE, UV);

    if (anim_color.a < 0.01) {
        discard;
    }

    // Debug mode 1: Show raw frame/TEXTURE colors (bypass lookup entirely)
    if (debug_mode > 0.5 && debug_mode < 1.5) {
        COLOR = anim_color;
        return;
    }

    // Search UV map for matching color
    vec2 skin_uv = vec2(0.5, 0.5); // fallback = center
    float matched = 0.0;

    for (float y = 0.0; y < uv_map_size.y; y += 1.0) {
        for (float x = 0.0; x < uv_map_size.x; x += 1.0) {
            vec2 sample_uv = vec2(x + 0.5, y + 0.5) / uv_map_size;
            vec4 map_color = texture(uv_map, sample_uv);

            if (map_color.a > 0.5) {
                vec3 diff = abs(map_color.rgb - anim_color.rgb);
                if (diff.r < color_tolerance && diff.g < color_tolerance && diff.b < color_tolerance) {
                    skin_uv = sample_uv;
                    matched = 1.0;
                    // Break out of both loops by jumping to end
                    y = uv_map_size.y;
                    break;
                }
            }
        }
    }

    // Debug mode 2: Visualize the matched UV position as color
    if (debug_mode > 1.5 && debug_mode < 2.5) {
        COLOR = vec4(skin_uv.x, skin_uv.y, 0.0, anim_color.a);
        return;
    }

    // Debug mode 3: Show match success (green) vs fallback (red)
    if (debug_mode > 2.5 && debug_mode < 3.5) {
        COLOR = vec4(1.0 - matched, matched, 0.0, anim_color.a);
        return;
    }

    // Sample the skin texture at the found coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Debug mode 4: Show raw skin lookup (no tint/flash)
    if (debug_mode > 3.5 && debug_mode < 4.5) {
        COLOR = vec4(skin_color.rgb, anim_color.a);
        return;
    }

    // Normal rendering: apply tint and flash
    vec3 final_rgb = skin_color.rgb * tint.rgb;
    final_rgb = mix(final_rgb, flash_color.rgb, flash_amount);

    COLOR = vec4(final_rgb, anim_color.a);
}
