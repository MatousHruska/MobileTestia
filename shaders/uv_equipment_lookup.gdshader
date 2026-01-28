shader_type canvas_item;
render_mode blend_mix;

// UV color-lookup shader with equipment slots
// Supports 4 equipment slots + base skin based on body part ID in UV map's Blue channel
//
// Body part IDs (Blue channel):
//   0.00 = Base skin (always visible)
//   0.25 = Head slot
//   0.50 = Body slot
//   0.75 = Hands slot
//   1.00 = Feet slot

// The UV reference map - contains unique colors per body part
// R,G = unique color identifier
// B = body part ID (0.0, 0.25, 0.5, 0.75, 1.0)
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

// Body part ID tolerance (for matching 0.25 increments)
uniform float body_part_tolerance : hint_range(0.0, 0.2) = 0.1;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Find UV coordinates and body part by matching color in the UV map
// Returns: vec3(u, v, body_part_id)
vec3 find_color_in_uvmap(vec3 target_color) {
    for (float y = 0.0; y < uv_map_size.y; y += 1.0) {
        for (float x = 0.0; x < uv_map_size.x; x += 1.0) {
            vec2 sample_uv = vec2(x + 0.5, y + 0.5) / uv_map_size;
            vec4 map_color = texture(uv_map, sample_uv);

            // Only check non-transparent pixels
            if (map_color.a > 0.5) {
                // Check if R,G colors match within tolerance
                vec2 diff = abs(map_color.rg - target_color.rg);
                if (diff.r < color_tolerance && diff.g < color_tolerance) {
                    // Found match - return UV and body part ID from Blue channel
                    return vec3(sample_uv.x, sample_uv.y, map_color.b);
                }
            }
        }
    }

    // Color not found - return center as fallback, base skin
    return vec3(0.5, 0.5, 0.0);
}

// Sample the appropriate equipment texture based on body part ID
vec4 sample_equipment(vec2 uv, float body_part_id) {
    // Determine which slot based on body part ID
    // 0.0 = base, 0.25 = head, 0.5 = body, 0.75 = hands, 1.0 = feet

    if (body_part_id < 0.125) {
        // Base skin (0.0)
        return texture(skin_base, uv);
    } else if (body_part_id < 0.375) {
        // Head (0.25)
        vec4 equip = texture(skin_head, uv);
        if (equip.a > 0.01) return equip;
        return texture(skin_base, uv); // Fallback to base
    } else if (body_part_id < 0.625) {
        // Body (0.5)
        vec4 equip = texture(skin_body, uv);
        if (equip.a > 0.01) return equip;
        return texture(skin_base, uv);
    } else if (body_part_id < 0.875) {
        // Hands (0.75)
        vec4 equip = texture(skin_hands, uv);
        if (equip.a > 0.01) return equip;
        return texture(skin_base, uv);
    } else {
        // Feet (1.0)
        vec4 equip = texture(skin_feet, uv);
        if (equip.a > 0.01) return equip;
        return texture(skin_base, uv);
    }
}

void fragment() {
    // Sample the animation sprite (TEXTURE)
    vec4 anim_color = texture(TEXTURE, UV);

    // If alpha is 0, this pixel is transparent
    if (anim_color.a < 0.01) {
        discard;
    }

    // Find where this color appears in the UV map + get body part ID
    vec3 lookup_result = find_color_in_uvmap(anim_color.rgb);
    vec2 skin_uv = lookup_result.xy;
    float body_part_id = lookup_result.z;

    // Sample the appropriate equipment texture
    vec4 skin_color = sample_equipment(skin_uv, body_part_id);

    // Apply tint (for status effects)
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output: equipment color with animation's alpha controlling shape
    COLOR = vec4(final_color.rgb, anim_color.a * skin_color.a);
}
