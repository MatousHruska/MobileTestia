# PHASE 1: BASIC UV COLOR-LOOKUP SHADER ✓ COMPLETE

> **Goal**: Get the UV color-lookup shader working. See a colored character render using the lookup texture system.
> **Prerequisites**: None - this is the starting point
> **Status**: COMPLETE - Test scenes functional with hot-reload

---

## CONTEXT

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Overall visual style and principles
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Technical architecture and shader code
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Full roadmap and asset specs

**Key technical decisions:**
- **Color-Lookup System**: Animation pixels have unique colors that match UV Map
- **Shader searches** UV Map for matching color, uses found position as UV coordinate
- **Lookup Texture** is sampled at found position to get final color
- This enables skin swapping without redrawing animations

---

## HOW COLOR-LOOKUP WORKS

```
ANIMATION FRAME                      UV MAP (64x64)                    LOOKUP TEXTURE
┌────────────────┐                   ┌────────────────┐                ┌────────────────┐
│  Pixel color:  │                   │                │                │                │
│  #A4B2C3       │ ──color match──►  │  #A4B2C3 found │ ──position──►  │  Sample at     │
│                │                   │  at pos (12,8) │                │  UV (12.5/64,  │
└────────────────┘                   └────────────────┘                │     8.5/64)    │
                                                                       └────────────────┘

WORKFLOW:
1. Animation sprite pixel has unique RGB color (e.g., #A4B2C3)
2. Shader searches UV Map for that exact color (within tolerance 0.002)
3. Found at position (12, 8) in UV Map
4. Convert to UV: (12+0.5)/64 = 0.1953125
5. Sample Lookup Texture at that UV coordinate
6. Output: lookup color with animation's alpha as mask
```

---

## IMPLEMENTED FILES

### Shaders

**`shaders/uv_color_lookup.gdshader`** - Basic single-skin shader
- Searches UV map for color matches
- Samples single lookup/skin texture
- Supports tint and flash effects

**`shaders/uv_equipment_lookup.gdshader`** - Multi-slot equipment shader
- Same color-lookup mechanism
- Position-based sectors for equipment slots
- See PHASE_3_EQUIPMENT_VISUALS.md for details

### Test Scenes

**`scenes/test/test_custom_uv_shader.tscn`** - Basic color-lookup testing
```
Controls:
  R          - Reload all textures from disk (hot-reload)
  S          - Swap/cycle lookup texture (skin)
  Space      - Test hit flash (white)
  T          - Toggle poison tint (green)
  1-5        - Jump to frame 1-5
  Left/Right - Step through frames
  P          - Toggle auto-play
```

**`scenes/test/test_equipment_shader.tscn`** - Equipment slot testing
```
Controls:
  H          - Toggle HEAD slot
  B          - Toggle BODY slot
  A          - Toggle HANDS/ARMS slot
  L          - Toggle LEGS/FEET slot
  R          - Reload all textures
  (plus all controls from basic test)
```

### Test Assets

Located at: `assets/sprites/characters/player/Tests/`

| File | Size | Purpose |
|------|------|---------|
| `TestIdle-Sheet.png` | 160×32 | Animation frames (5 frames × 32×32) |
| `TestUVMap.png` | 32×32 | UV reference map with unique colors |
| `TestLookupTexture.png` | 32×32 | Skin/appearance texture |
| `TestLookupTexture2.png` | 32×32 | Alternate skin for testing swap |

---

## CREATING YOUR OWN ASSETS

### Asset 1: UV Map (64×64 PNG)

**Purpose**: Reference texture where each pixel has a unique RGB color.

**Requirements**:
- Every non-transparent pixel must have a distinct RGB value (zero duplicates)
- Minimum color distance between any two pixels must be >= 2 RGB units (so tolerance 0.002 works)
- **Avoid smooth gradients** — they produce colors too close together
- Position matters: pixel (x,y) in UV map = UV coordinate for that color
- Transparent pixels are ignored by shader

**Example approach**:
```
Create a 64×64 image where:
- Use well-spaced colors (not smooth gradients!)
- Each pixel is visually distinct with >= 2 RGB unit spacing
- The layout can represent your character's body regions
```

### Asset 2: Lookup Texture (64×64 PNG)

**Purpose**: The actual character appearance.

**Requirements**:
- Same size as UV Map (64×64)
- Pixel positions align with UV Map
- This is what the character looks like!
- Can be swapped to change character appearance

**Example approach**:
```
Draw your character "flattened":
- Head colors in the head region
- Body colors in the body region
- Arms, legs, etc. in their regions
- Position must match UV Map positions
```

### Asset 3: Animation Sheet

**Purpose**: Animated silhouettes colored with UV Map colors.

**Requirements**:
- Each frame is 32×32 (or your chosen size)
- Pixels are colored to MATCH the UV Map colors
- Alpha channel defines visible shape
- Colors must match within tolerance (~0.02, about 5 RGB values)

**Example approach**:
```
For each animation frame:
1. Draw the character silhouette (alpha channel)
2. For each visible pixel, pick the RGB color from UV Map
   that corresponds to the body part at that position
3. The shader will find that color in UV Map and sample
   the lookup texture at the found position
```

---

## VALIDATION CHECKLIST

After running `test_custom_uv_shader.tscn`:

- [x] Character renders (not invisible or black)
- [x] Character shows colors from lookup texture
- [x] Pressing R reloads textures (see console output)
- [x] Pressing S cycles through lookup textures
- [x] Pressing Space triggers white flash
- [x] Pressing T toggles green tint
- [x] Animation plays through frames
- [x] Frame stepping with 1-5 and arrows works

---

## TROUBLESHOOTING

| Problem | Likely Cause | Solution |
|---------|--------------|----------|
| Black/invisible character | Textures not assigned | Check shader parameters in scene |
| Wrong colors | Colors don't match UV map | Ensure animation colors exactly match UV map |
| Blurry output | Linear filtering | Set texture filter to "Nearest" |
| Shader error / "version is null" | Shader compilation failure | Check for `out bool`, `return` in fragment(), `break` in loops — mobile renderer rejects these |
| Colors match wrong positions | Tolerance too high | Reduce `color_tolerance` to 0.002. Verify min color distance in UV map > 2x tolerance |
| All dark / wrong colors after adding `source_color` | Color space mismatch | Never use `source_color` on `uv_map` or `skin` samplers in canvas_item shaders |
| Hot-reload not working | Path mismatch | Verify paths in test script |

---

## KEY CONCEPTS

### Color Tolerance
The shader has a `color_tolerance` parameter (default 0.002, ~0.5 RGB units). This must be:
- **Less than half** the minimum color distance between any two UV map pixels
- Very small for gradient-based UV maps (where adjacent pixels differ by only a few RGB units)
- A value of 0.02 (the old default) caused 97% false matches with tightly-packed gradient colors

**CRITICAL**: If the UV map has colors only 1 RGB unit apart, tolerance must be < 0.004 (0.002 is safe).

### Pixel-Perfect Overlay
All three textures (Animation, UV Map, Lookup) work on the same pixel grid:
- Position (5, 3) in UV Map corresponds to position (5, 3) in Lookup Texture
- Animation pixel with color from position (5, 3) of UV Map will sample (5, 3) from Lookup

### Hot-Reload Workflow
The test scenes support live texture editing:
1. Run test scene
2. Edit textures in external editor
3. Save textures
4. Press R in running game
5. Changes appear immediately

---

## NEXT PHASE

Once validated, proceed to `PHASE_2_PLAYER_MOVEMENT.md` which adds:
- Animation controller for state management
- 4-directional idle/walk animations
- Integration with player controller

---

*Phase Status: COMPLETE*
*Document Version: 3.0 - Updated with verified shader constraints and debug system*
*Last Updated: Session claude/testingshaders2-branch-lKfTU*
