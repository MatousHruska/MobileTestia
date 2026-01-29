# PHASE 2: PLAYER MOVEMENT ANIMATION

> **Goal**: Animated player character with 4-directional movement (idle + walk)
> **Prerequisites**: Phase 1 complete (UV color-lookup shader working)
> **Status**: CODE COMPLETE - Awaiting humanoid UV map asset

---

## IMPLEMENTATION STATUS

### Code Components - COMPLETE

| Component | Status | File |
|-----------|--------|------|
| VisualAssetManager | Complete | `autoloads/visual_asset_manager.gd` |
| UVCharacterAnimator | Complete | `scripts/rendering/uv_character_animator.gd` |
| Animator Scene | Complete | `scenes/rendering/uv_character_animator.tscn` |
| Player Integration | Complete | `scripts/player/player_controller.gd` |
| Humanoid Config | Complete | In VisualAssetManager |

### Asset Components - PARTIAL

| Asset | Status | Path |
|-------|--------|------|
| humanoid_idle.png | Exists | `assets/sprites/characters/player/motion/` |
| humanoid_walk.png | Exists | `assets/sprites/characters/player/motion/` |
| body_default.png | Exists | `assets/sprites/characters/player/skins/` |
| humanoid_uv.png | **NEEDED** | `assets/sprites/characters/player/uv_maps/` |

---

## WHAT'S WORKING

The full animation system is implemented and integrated:

1. **VisualAssetManager** manages texture loading with configs for "test" and "humanoid"
2. **UVCharacterAnimator** handles 4-directional animation with state machine
3. **Player Controller** updates animator based on movement
4. **Animation data** defined for: idle, walk, attack, dodge, hit, die

### Switching Between Test and Humanoid

The player has a debug method to toggle between motion bases:
- Press **Numpad 9** in-game to toggle between "test" and "humanoid"
- "test" uses the Phase 1 test assets (working)
- "humanoid" uses the humanoid assets (needs UV map)

---

## USER TASK: Create Humanoid UV Map

To complete Phase 2, create the UV map that matches your humanoid animation sheets.

### File Details

**File**: `assets/sprites/characters/player/uv_maps/humanoid_uv.png`
**Size**: 32x32 pixels

### How to Create

The UV map is a reference texture where:
- Each pixel has a unique RGB color
- Position matters: pixel at (x,y) corresponds to UV coordinate (x/32, y/32)
- Animation frames use these colors to reference body parts

**Option 1: Copy Test UV Map**
```
cp assets/sprites/characters/player/Tests/TestUVMap.png \
   assets/sprites/characters/player/uv_maps/humanoid_uv.png
```
Then modify to match your humanoid art style.

**Option 2: Create from Scratch**
1. Create 32x32 image with unique colors per pixel
2. Organize colors by body region (head top, body middle, feet bottom)
3. Match colors to those used in your animation sheets

### Verify Your Assets Work Together

1. Animation sheet pixel color must match UV map pixel color
2. UV map position corresponds to lookup texture (skin) position
3. Use test scenes to verify: `scenes/test/test_custom_uv_shader.tscn`

---

## ANIMATION DATA REFERENCE

Current animation definitions in VisualAssetManager:

### Idle Animation (6 FPS, looping)
```
Layout: 4 columns x 4 rows (128x128 total)
- Row 0: DOWN  frames 0-3
- Row 1: UP    frames 4-7
- Row 2: LEFT  frames 8-11
- Row 3: RIGHT frames 12-15
```

### Walk Animation (10 FPS, looping)
```
Layout: 6 columns x 4 rows (192x128 total)
- Row 0: DOWN  frames 0-5
- Row 1: UP    frames 6-11
- Row 2: LEFT  frames 12-17
- Row 3: RIGHT frames 18-23
```

### Attack Animation (12 FPS, non-looping)
```
Layout: 4 columns x 4 rows (128x128 total)
- Row 0: DOWN  frames 0-3
- Row 1: UP    frames 4-7
- Row 2: LEFT  frames 8-11
- Row 3: RIGHT frames 12-15
```

### Additional Animations Defined

- **dodge**: 4 frames per direction, 12 FPS
- **hit**: 3 frames per direction, 10 FPS
- **die**: 5 frames per direction, 8 FPS

---

## VALIDATION CHECKLIST

After creating the humanoid UV map:

- [ ] Player spawns with UV-rendered character (not placeholder)
- [ ] Character shows colors from body_default.png skin
- [ ] Idle animation plays when standing still
- [ ] Walk animation plays when moving
- [ ] All 4 directions render correctly
- [ ] Direction changes are smooth
- [ ] Stopping returns to idle facing last direction
- [ ] Flash effect works (Space in test scene)
- [ ] Tint effect works (T in test scene)

**Test each direction**:
```
Press DOWN  -> Character faces down, walks down
Press UP    -> Character faces up, walks up
Press LEFT  -> Character faces left, walks left
Press RIGHT -> Character faces right, walks right
Stop moving -> Returns to idle facing last direction
```

---

## TROUBLESHOOTING

| Problem | Likely Cause | Solution |
|---------|--------------|----------|
| Black/invisible character | UV map not found | Create humanoid_uv.png |
| Wrong colors | Colors don't match | Ensure animation colors match UV map |
| Placeholder texture | Missing asset | Check console for path errors |
| Animation not changing | State machine issue | Check _current_state in animator |

### Debug Commands

In-game debug options:
- **Numpad 9**: Toggle between test/humanoid motion base
- **Test Scene (R)**: Hot-reload textures
- **Test Scene (S)**: Cycle skins

---

## FILES FOR THIS PHASE

### Created by Code (Complete)

```
autoloads/
  visual_asset_manager.gd     <- Manages assets and configs

scripts/
  rendering/
    uv_character_animator.gd  <- Animation controller

scenes/
  rendering/
    uv_character_animator.tscn <- Animator scene template
```

### User-Created Assets

```
assets/sprites/characters/player/
  uv_maps/
    humanoid_uv.png           <- NEEDED: UV reference map
  motion/
    humanoid_idle.png         <- EXISTS: Idle animation sheet
    humanoid_walk.png         <- EXISTS: Walk animation sheet
  skins/
    body_default.png          <- EXISTS: Character skin
```

---

## NEXT PHASE

Once humanoid UV map is created and validated, proceed to `PHASE_3_EQUIPMENT_VISUALS.md`:
- Sector-based equipment shader (already implemented)
- Equipment slot textures (head, body, hands, feet)
- Connection to inventory system
- Visual equipment changes

---

## TECHNICAL NOTES

### Left Direction Flipping

The animator reuses RIGHT animation frames for LEFT direction by flipping:
- `sprite.flip_h = true` for left direction
- This reduces art requirements by 25%
- Can be disabled by creating dedicated LEFT animations

### Motion Base System

Characters can have different motion bases:
- "test" - Phase 1 test character
- "humanoid" - Player character (default)

Each motion base has its own:
- Animation sheets (motion maps)
- UV map for color-lookup
- Skin/lookup texture

### State Machine

Animation states: `idle`, `walk`, `attack`, `dodge`, `hit`, `die`
- Looping states: idle, walk
- One-shot states: attack, dodge, hit, die (auto-return to idle)

---

*Document Version: 3.0 - Implementation Complete*
*Last Updated: Session claude/phase-2-player-movement-B3STv*
