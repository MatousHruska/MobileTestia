shader_type canvas_item;
render_mode blend_mix;

// The UV reference map - each pixel has a unique color
// Position of a color in this texture = UV coordinates for skin lookup
uniform sampler2D uv_map : hint_default_white, filter_nearest;

// Skin texture - the actual appearance (pixel-perfect overlay with uv_map)
uniform sampler2D skin : hint_default_white, filter_nearest;

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

// Find UV coordinates by matching color in the UV map
vec2 find_color_in_uvmap(vec3 target_color) {
    for (float y = 0.0; y < uv_map_size.y; y += 1.0) {
        for (float x = 0.0; x < uv_map_size.x; x += 1.0) {
            vec2 sample_uv = vec2(x + 0.5, y + 0.5) / uv_map_size;
            vec4 map_color = texture(uv_map, sample_uv);

            if (map_color.a > 0.5) {
                vec3 diff = abs(map_color.rgb - target_color);
                if (diff.r < color_tolerance && diff.g < color_tolerance && diff.b < color_tolerance) {
                    return sample_uv;
                }
            }
        }
    }

    return vec2(-1.0, -1.0);
}

void fragment() {
    vec4 anim_color = texture(TEXTURE, UV);

    if (anim_color.a < 0.01) {
        discard;
    }

    // Find where this color appears in the UV map
    vec2 skin_uv = find_color_in_uvmap(anim_color.rgb);
    float matched = step(0.0, skin_uv.x); // 1.0 if found, 0.0 if -1

    // Use center fallback if not found
    if (skin_uv.x < 0.0) {
        skin_uv = vec2(0.5, 0.5);
    }

    // Sample the skin texture at the found coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Choose output based on debug mode
    vec3 out_rgb = skin_color.rgb * tint.rgb;
    out_rgb = mix(out_rgb, flash_color.rgb, flash_amount);

    // Debug mode 1: raw frame colors
    if (debug_mode > 0.5 && debug_mode < 1.5) {
        out_rgb = anim_color.rgb;
    }
    // Debug mode 2: UV position as color
    if (debug_mode > 1.5 && debug_mode < 2.5) {
        out_rgb = vec3(skin_uv.x, skin_uv.y, 0.0);
    }
    // Debug mode 3: match status (green=ok, red=fallback)
    if (debug_mode > 2.5 && debug_mode < 3.5) {
        out_rgb = vec3(1.0 - matched, matched, 0.0);
    }
    // Debug mode 4: raw skin (no tint/flash)
    if (debug_mode > 3.5 && debug_mode < 4.5) {
        out_rgb = skin_color.rgb;
    }

    COLOR = vec4(out_rgb, anim_color.a);
}
