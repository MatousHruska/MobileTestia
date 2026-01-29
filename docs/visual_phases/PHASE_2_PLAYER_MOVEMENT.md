# PHASE 2: PLAYER MOVEMENT ANIMATION

> **Goal**: Animated player character with 4-directional movement
> **Prerequisites**: Phase 1 complete (UV color-lookup shader working)
> **Status**: CODE COMPLETE - Animation sheets needed

---

## CURRENT STATE

### What's Working
- **player_idle.png** - 5 frame idle animation (horizontal strip)
- **player_uv.png** - UV reference map for color-lookup
- **player_skin.png / player_skin_alt.png** - Skins (cycle with Numpad 9)
- Full animation system integrated with player controller

### Files Location
All player assets are in: `assets/sprites/characters/player/`

---

## ANIMATION SHEETS TO CREATE

Create these files in `assets/sprites/characters/player/`:

### 1. player_walk.png
**Size**: 192×128 pixels (6 columns × 4 rows)
**Frames per direction**: 6
**FPS**: 10
**Looping**: Yes

```
┌─────┬─────┬─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │ D5  │ D6  │  Row 0: DOWN walk (frames 0-5)
├─────┼─────┼─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │ U5  │ U6  │  Row 1: UP walk (frames 6-11)
├─────┼─────┼─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │ L5  │ L6  │  Row 2: LEFT walk (frames 12-17)
├─────┼─────┼─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │ R5  │ R6  │  Row 3: RIGHT walk (frames 18-23)
└─────┴─────┴─────┴─────┴─────┴─────┘
```

**Walk cycle keyframes** (6 frames):
1. Contact (right foot forward)
2. Down (weight shifts to right)
3. Passing (legs cross)
4. Contact (left foot forward)
5. Down (weight shifts to left)
6. Passing (legs cross)

---

### 2. player_attack.png
**Size**: 128×128 pixels (4 columns × 4 rows)
**Frames per direction**: 4
**FPS**: 12
**Looping**: No (returns to idle)

```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: DOWN attack (frames 0-3)
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: UP attack (frames 4-7)
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: LEFT attack (frames 8-11)
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: RIGHT attack (frames 12-15)
└─────┴─────┴─────┴─────┘
```

**Attack keyframes** (4 frames):
1. Wind-up (arm raised)
2. Swing start
3. **Hit frame** (frame 3, index 2) - hitbox activates here
4. Follow-through

---

### 3. player_dodge.png
**Size**: 128×128 pixels (4 columns × 4 rows)
**Frames per direction**: 4
**FPS**: 12
**Looping**: No (returns to idle)

```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: DOWN dodge
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: UP dodge
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: LEFT dodge
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: RIGHT dodge
└─────┴─────┴─────┴─────┘
```

**Dodge keyframes** (4 frames):
1. Crouch/lean into roll
2. Mid-roll (blur/stretch)
3. Coming out of roll
4. Recovery stance

---

### 4. player_hit.png
**Size**: 64×128 pixels (2 columns × 4 rows)
**Frames per direction**: 2
**FPS**: 10
**Looping**: No (returns to idle)

```
┌─────┬─────┐
│ D1  │ D2  │  Row 0: DOWN hit
├─────┼─────┤
│ U1  │ U2  │  Row 1: UP hit
├─────┼─────┤
│ L1  │ L2  │  Row 2: LEFT hit
├─────┼─────┤
│ R1  │ R2  │  Row 3: RIGHT hit
└─────┴─────┘
```

**Hit keyframes** (2 frames):
1. Impact (recoil from hit)
2. Recovery

---

### 5. player_die.png
**Size**: 160×128 pixels (5 columns × 4 rows)
**Frames per direction**: 5
**FPS**: 8
**Looping**: No (stays on last frame)

```
┌─────┬─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │ D5  │  Row 0: DOWN die
├─────┼─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │ U5  │  Row 1: UP die
├─────┼─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │ L5  │  Row 2: LEFT die
├─────┼─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │ R5  │  Row 3: RIGHT die
└─────┴─────┴─────┴─────┴─────┘
```

**Death keyframes** (5 frames):
1. Hit reaction
2. Stagger
3. Falling
4. Hitting ground
5. Lying still (final pose)

---

## CREATING ANIMATION SHEETS

### Color-Lookup Reminder
Each pixel in your animation sheet must use colors from your UV map:
1. Open TestUVMap.png for reference
2. For each body part in your animation frame, pick the color from the corresponding position in the UV map
3. The shader will then sample TestLookupTexture at that UV position

### Quick Workflow
1. Create animation in Aseprite (or your preferred tool)
2. For each frame, color pixels using UV map colors
3. Export as PNG with the exact dimensions specified above
4. Test in-game - character should show your skin colors through the animation

### LEFT Direction Note
Currently, LEFT animations use RIGHT frames flipped horizontally. You can:
- **Option A**: Create identical LEFT row (will be flipped anyway)
- **Option B**: Create unique LEFT poses if asymmetric details matter

---

## PRIORITY ORDER

Create animations in this order (most important first):

1. **player_walk.png** - Essential for movement
2. **player_attack.png** - Essential for combat
3. **player_dodge.png** - Core combat mechanic
4. **player_hit.png** - Damage feedback
5. **player_die.png** - Death state

Until each animation exists, the system falls back to idle animation.

---

## TESTING

### In-Game Testing
- Move around to test walk/idle transitions
- Attack (default key) to test attack animation
- Dodge (default key) to test dodge animation

### Debug Keys
- **Numpad 9**: Cycle between available skins (default/alt)

### Verify Checklist
- [ ] Walk animation plays when moving
- [ ] Idle animation plays when stopped
- [ ] Attack animation plays and returns to idle
- [ ] Dodge animation plays and returns to idle
- [ ] All 4 directions render correctly
- [ ] Skin colors appear correctly (not UV map colors)

---

## QUICK REFERENCE TABLE

| Animation | File | Size | Cols×Rows | Frames/Dir | FPS | Loop |
|-----------|------|------|-----------|------------|-----|------|
| Idle | player_idle.png | 160×32 | 5×1 | 5 | 6 | Yes |
| Walk | player_walk.png | 192×128 | 6×4 | 6 | 10 | Yes |
| Attack | player_attack.png | 128×128 | 4×4 | 4 | 12 | No |
| Dodge | player_dodge.png | 128×128 | 4×4 | 4 | 12 | No |
| Hit | player_hit.png | 64×128 | 2×4 | 2 | 10 | No |
| Die | player_die.png | 160×128 | 5×4 | 5 | 8 | No |

---

## FILES SUMMARY

### Existing (Working)
```
assets/sprites/characters/player/
├── player_idle.png         # Idle animation (160×32)
├── player_uv.png           # UV reference map (32×32)
├── player_skin.png         # Default skin (32×32)
├── player_skin_alt.png     # Alt skin (32×32)
├── player_equip_head.png   # Equipment slot (Phase 3)
├── player_equip_body.png   # Equipment slot (Phase 3)
├── player_equip_hands.png  # Equipment slot (Phase 3)
└── player_equip_legs.png   # Equipment slot (Phase 3)
```

### To Create
```
assets/sprites/characters/player/
├── player_walk.png         # 192×128 (6 cols × 4 rows)
├── player_attack.png       # 128×128 (4 cols × 4 rows)
├── player_dodge.png        # 128×128 (4 cols × 4 rows)
├── player_hit.png          # 64×128  (2 cols × 4 rows)
└── player_die.png          # 160×128 (5 cols × 4 rows)
```

---

*Document Version: 4.0 - Cleaned up for actual implementation*
*Last Updated: Session claude/phase-2-player-movement-B3STv*
