shader_type canvas_item;
render_mode blend_mix;

// UV color-lookup shader with equipment slots
// Supports 4 equipment slots + base skin based on POSITION in UV map
//
// Body part sectors (configurable via uniforms):
//   - Head: top region
//   - Body: middle-left region
//   - Hands: middle-right region
//   - Feet: bottom region
//
// You keep full RGB colors for visual work - body part is determined by WHERE
// the pixel is located in the UV map, not by color channel.

// The UV reference map - contains unique colors per body part
uniform sampler2D uv_map : hint_default_white, filter_nearest;

// Equipment slot textures (pixel-perfect overlays with uv_map)
uniform sampler2D skin_base : hint_default_white, filter_nearest;
uniform sampler2D skin_head : hint_default_transparent, filter_nearest;
uniform sampler2D skin_body : hint_default_transparent, filter_nearest;
uniform sampler2D skin_hands : hint_default_transparent, filter_nearest;
uniform sampler2D skin_feet : hint_default_transparent, filter_nearest;

// Size of the UV map for searching
uniform vec2 uv_map_size = vec2(32.0, 32.0);

// Color matching tolerance (for anti-aliasing/compression artifacts)
uniform float color_tolerance : hint_range(0.0, 0.1) = 0.01;

// Sector boundaries (normalized 0-1, configurable per character)
// Default layout:
//   Head: Y 0.0-0.25 (top)
//   Body: Y 0.25-0.75, X 0.0-0.5 (middle-left)
//   Hands: Y 0.25-0.75, X 0.5-1.0 (middle-right)
//   Feet: Y 0.75-1.0 (bottom)
uniform float sector_head_max_y : hint_range(0.0, 1.0) = 0.25;
uniform float sector_feet_min_y : hint_range(0.0, 1.0) = 0.75;
uniform float sector_hands_min_x : hint_range(0.0, 1.0) = 0.5;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Determine body part based on UV position (sector-based)
// Returns: 0=base, 1=head, 2=body, 3=hands, 4=feet
int get_body_part_from_position(vec2 uv) {
    // Head: top sector
    if (uv.y < sector_head_max_y) {
        return 1; // Head
    }
    // Feet: bottom sector
    if (uv.y >= sector_feet_min_y) {
        return 4; // Feet
    }
    // Middle region: split into Body (left) and Hands (right)
    if (uv.x >= sector_hands_min_x) {
        return 3; // Hands
    }
    return 2; // Body
}

// Find UV coordinates by matching color in the UV map
vec2 find_color_in_uvmap(vec3 target_color) {
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

// Sample the appropriate equipment texture based on body part
vec4 sample_equipment(vec2 uv, int body_part) {
    vec4 equip;

    if (body_part == 1) {
        // Head
        equip = texture(skin_head, uv);
        if (equip.a > 0.01) return equip;
    } else if (body_part == 2) {
        // Body
        equip = texture(skin_body, uv);
        if (equip.a > 0.01) return equip;
    } else if (body_part == 3) {
        // Hands
        equip = texture(skin_hands, uv);
        if (equip.a > 0.01) return equip;
    } else if (body_part == 4) {
        // Feet
        equip = texture(skin_feet, uv);
        if (equip.a > 0.01) return equip;
    }

    // Fallback to base skin
    return texture(skin_base, uv);
}

void fragment() {
    // Sample the animation sprite (TEXTURE)
    vec4 anim_color = texture(TEXTURE, UV);

    // If alpha is 0, this pixel is transparent
    if (anim_color.a < 0.01) {
        discard;
    }

    // Find where this color appears in the UV map
    vec2 skin_uv = find_color_in_uvmap(anim_color.rgb);

    // Determine body part based on POSITION in UV map (sector-based)
    int body_part = get_body_part_from_position(skin_uv);

    // Sample the appropriate equipment texture
    vec4 skin_color = sample_equipment(skin_uv, body_part);

    // Apply tint (for status effects)
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output: equipment color with animation's alpha controlling shape
    COLOR = vec4(final_color.rgb, anim_color.a * skin_color.a);
}
