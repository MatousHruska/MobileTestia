# PHASE 3: EQUIPMENT VISUALS ✓ COMPLETE

> **Goal**: Changing equipment visually updates the character appearance using sector-based slots
> **Prerequisites**: Phase 1 complete (color-lookup shader working)
> **Status**: COMPLETE - Equipment test scene functional with slot toggling

---

## CONTEXT

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Equipment slot definitions
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Sector-based shader code
- `docs/visual_phases/PHASE_1_BASIC_SHADER.md` - Color-lookup foundation

**Key decisions:**
- Equipment slots: Head, Body, Hands, Feet
- Slots determined by POSITION in UV map (sector-based), NOT by color channels
- Each slot has its own lookup texture
- Transparent pixels fall back to base skin

---

## HOW SECTOR-BASED EQUIPMENT WORKS

```
UV MAP SECTORS (32x32):
┌────────────────────────────────┐
│                                │
│        HEAD SECTOR             │  Y: 0.00 - 0.25 (top 8 rows)
│        (skin_head)             │
│                                │
├────────────────┬───────────────┤
│                │               │
│  BODY SECTOR   │ HANDS SECTOR  │  Y: 0.25 - 0.75 (middle 16 rows)
│  (skin_body)   │ (skin_hands)  │
│                │               │
│   X: 0 - 0.5   │  X: 0.5 - 1   │
├────────────────┴───────────────┤
│                                │
│        FEET SECTOR             │  Y: 0.75 - 1.00 (bottom 8 rows)
│        (skin_feet)             │
│                                │
└────────────────────────────────┘

SHADER LOGIC:
1. Find color in UV map (same as basic shader)
2. Get the found position
3. Determine which sector that position falls in
4. Sample the corresponding equipment texture
5. If transparent, fall back to base skin
```

---

## IMPLEMENTED FILES

### Equipment Shader

**`shaders/uv_equipment_lookup.gdshader`**

```glsl
// Key uniforms:
uniform sampler2D uv_map;        // UV reference map
uniform sampler2D skin_base;     // Fallback for all slots
uniform sampler2D skin_head;     // Head equipment
uniform sampler2D skin_body;     // Body equipment
uniform sampler2D skin_hands;    // Hands equipment
uniform sampler2D skin_feet;     // Feet equipment

// Sector boundaries (configurable):
uniform float sector_head_max_y = 0.25;   // Head = Y < 0.25
uniform float sector_feet_min_y = 0.75;   // Feet = Y >= 0.75
uniform float sector_hands_min_x = 0.5;   // Hands = X >= 0.5 (in middle)
// Body = everything else in middle
```

### Test Scene

**`scenes/test/test_equipment_shader.tscn`**

Controls:
```
H - Toggle HEAD slot (on/off)
B - Toggle BODY slot (on/off)
A - Toggle HANDS/ARMS slot (on/off)
L - Toggle LEGS/FEET slot (on/off)
R - Reload all textures from disk
S - Cycle base skin
Space - Test hit flash
T - Toggle poison tint
1-5 - Jump to animation frame
P - Toggle auto-play
```

### Test Assets

Located at: `assets/sprites/characters/player/Tests/`

| File | Purpose |
|------|---------|
| `TestUVMap.png` | UV reference map (shared with basic shader) |
| `TestIdle-Sheet.png` | Animation frames (shared with basic shader) |
| `TestLookupTexture2.png` | Base skin (fallback) |
| `LookupTextureHead.png` | Head equipment slot |
| `LookupTextureBody.png` | Body equipment slot |
| `LookupTextureHands.png` | Hands equipment slot |
| `LookupTextureLegs.png` | Feet equipment slot |

---

## CREATING EQUIPMENT TEXTURES

### Sector Layout Guide

When creating equipment textures, draw ONLY in the relevant sector:

```
HEAD TEXTURE (LookupTextureHead.png):
┌────────────────────────────────┐
│  ████████████████████████████  │  ← Draw head/helmet here
│  ████████████████████████████  │
│  ████████████████████████████  │
│  ████████████████████████████  │
├────────────────────────────────┤
│  (transparent)                 │  ← Leave empty
│                                │
│                                │
│                                │
├────────────────────────────────┤
│  (transparent)                 │  ← Leave empty
└────────────────────────────────┘

BODY TEXTURE (LookupTextureBody.png):
┌────────────────────────────────┐
│  (transparent)                 │
├────────────────┬───────────────┤
│  ████████████  │ (transparent) │  ← Draw body/chest here
│  ████████████  │               │     (LEFT half only)
│  ████████████  │               │
│  ████████████  │               │
├────────────────┴───────────────┤
│  (transparent)                 │
└────────────────────────────────┘

HANDS TEXTURE (LookupTextureHands.png):
┌────────────────────────────────┐
│  (transparent)                 │
├────────────────┬───────────────┤
│ (transparent)  │ ██████████████│  ← Draw hands/arms here
│                │ ██████████████│     (RIGHT half only)
│                │ ██████████████│
│                │ ██████████████│
├────────────────┴───────────────┤
│  (transparent)                 │
└────────────────────────────────┘

FEET TEXTURE (LookupTextureLegs.png):
┌────────────────────────────────┐
│  (transparent)                 │
├────────────────────────────────┤
│  (transparent)                 │
│                                │
│                                │
│                                │
├────────────────────────────────┤
│  ████████████████████████████  │  ← Draw feet/boots here
│  ████████████████████████████  │
└────────────────────────────────┘
```

### Important Rules

1. **Same size as UV Map**: All equipment textures must be 32x32
2. **Pixel alignment**: Position (x,y) in equipment = position (x,y) in UV map
3. **Transparent fallback**: Any transparent pixel shows base skin instead
4. **Sector boundaries matter**: Draw only in the correct region for the slot

---

## VALIDATION CHECKLIST

After running `test_equipment_shader.tscn`:

- [x] Character renders with base skin
- [x] Pressing H toggles head equipment visibility
- [x] Pressing B toggles body equipment visibility
- [x] Pressing A toggles hands equipment visibility
- [x] Pressing L toggles feet equipment visibility
- [x] Multiple slots can be toggled independently
- [x] Disabling a slot shows base skin in that region
- [x] Equipment persists through animation frames
- [x] Hot-reload (R) updates equipment textures

---

## TROUBLESHOOTING

| Problem | Likely Cause | Solution |
|---------|--------------|----------|
| Equipment invisible | Texture not assigned | Check shader parameters |
| Equipment in wrong area | Sector boundaries wrong | Adjust sector uniforms |
| Equipment not changing | Toggle logic error | Check _update_all_slots() |
| Transparent showing wrong | Alpha threshold | Ensure alpha > 0.01 for visible |
| Base skin not showing | skin_base not set | Assign base texture |

---

## INTEGRATION WITH GAME

### Connecting to Inventory System

When implementing actual equipment:

```gdscript
# In equipment manager or player controller:
func equip_item(slot: String, item_id: String) -> void:
    var material := sprite.material as ShaderMaterial
    var texture_path := "res://assets/equipment/" + slot + "/" + item_id + ".png"

    if ResourceLoader.exists(texture_path):
        var tex := load(texture_path)
        match slot:
            "head":
                material.set_shader_parameter("skin_head", tex)
            "body":
                material.set_shader_parameter("skin_body", tex)
            "hands":
                material.set_shader_parameter("skin_hands", tex)
            "feet":
                material.set_shader_parameter("skin_feet", tex)

func unequip_item(slot: String) -> void:
    var material := sprite.material as ShaderMaterial
    # Set to transparent or base skin to "unequip"
    material.set_shader_parameter("skin_" + slot, base_skin_texture)
```

### Equipment Swap Workflow

1. Player opens inventory
2. Player drags armor to chest slot
3. Inventory system calls `equip_item("body", "leather_armor")`
4. Equipment manager loads `LookupTextureBody_leather_armor.png`
5. Shader parameter updated → character appearance changes immediately

---

## CUSTOMIZING SECTOR BOUNDARIES

The sector boundaries can be adjusted per character type:

```gdscript
# For a character with a large head:
material.set_shader_parameter("sector_head_max_y", 0.35)  # More head space

# For a character with long legs:
material.set_shader_parameter("sector_feet_min_y", 0.60)  # More feet space

# For a character with wide arms:
material.set_shader_parameter("sector_hands_min_x", 0.40)  # More hands space
```

Default values work for standard humanoid characters:
- Head: Y < 0.25 (top 25%)
- Feet: Y >= 0.75 (bottom 25%)
- Body: middle-left (Y 0.25-0.75, X < 0.5)
- Hands: middle-right (Y 0.25-0.75, X >= 0.5)

---

## NEXT PHASE

Once validated, proceed to `PHASE_4_PLAYER_COMBAT.md` which adds:
- Attack animations
- Weapon sprite rendering
- Anchor system for weapon positioning
- Combat integration

---

*Phase Status: COMPLETE*
*Document Version: 2.0 - Sector-Based Equipment System*
*Last Updated: Session claude/phase-1-TestingShaders-spp2s*
