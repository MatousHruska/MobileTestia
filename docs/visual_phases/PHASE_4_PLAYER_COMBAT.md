# PHASE 4: PLAYER COMBAT ANIMATION

> **Goal**: Attack animation with weapon sprite positioned via anchor system
> **Prerequisites**: Phase 3 complete (equipment visuals working with sector-based shader)
> **Estimated Scope**: Medium-Large - attack animations + weapon sprites + anchor data + combat integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Animation philosophy, hit feedback specs
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Color-lookup shader and weapon anchor system
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Attack animation specs
- `docs/visual_phases/PHASE_3_EQUIPMENT_VISUALS.md` - Sector-based equipment shader

**Key decisions from Art Direction:**
- 3 weapon categories: 1-handed, 2-handed, Bow
- This phase implements 1-handed only (basic strike)
- Attack animation: 4 frames (wind-up, apex, follow-through, recovery)
- Weapon is separate sprite positioned by anchor data per frame
- Weapon is hidden during idle/walk (sheathed on body skin)
- **Color-Lookup System**: Attack animations use same color-lookup as idle/walk

---

## IMPLEMENTATION STEPS

### Step 4.1: Add Weapon Sprite to Animator

**Modify**: `scripts/rendering/uv_character_animator.gd`

Add weapon sprite child and anchor handling:

```gdscript
# Add these variables to uv_character_animator.gd

# Weapon rendering
@onready var weapon_sprite: Sprite2D = $WeaponSprite
var _weapon_texture: Texture2D = null
var _weapon_category: String = "1h"  # 1h, 2h, bow
var _weapon_visible: bool = false

# Anchor data (hardcoded for now, database-driven later)
var _anchor_data: Dictionary = {}


func _ready() -> void:
    _setup_sprite()
    _setup_weapon_sprite()
    _setup_material()
    _load_anchor_data()
    _load_motion_map("idle")
    play("idle", "down")


func _setup_weapon_sprite() -> void:
    if not weapon_sprite:
        weapon_sprite = Sprite2D.new()
        weapon_sprite.name = "WeaponSprite"
        add_child(weapon_sprite)

    weapon_sprite.centered = true
    weapon_sprite.visible = false
    weapon_sprite.z_index = 1  # Render above character


func _load_anchor_data() -> void:
    # Anchor data format: animation_direction -> frame -> {position, rotation, flip_h, visible}
    # Position is offset from sprite center
    # Rotation in degrees
    _anchor_data = {
        "attack_1h_down": {
            0: { "pos": Vector2(8, -8), "rot": -45.0, "flip": false, "show": true },
            1: { "pos": Vector2(12, 4), "rot": 0.0, "flip": false, "show": true },
            2: { "pos": Vector2(8, 12), "rot": 45.0, "flip": false, "show": true },
            3: { "pos": Vector2(4, 8), "rot": 30.0, "flip": false, "show": true },
        },
        "attack_1h_up": {
            0: { "pos": Vector2(-8, 8), "rot": 135.0, "flip": false, "show": true },
            1: { "pos": Vector2(0, -12), "rot": 180.0, "flip": false, "show": true },
            2: { "pos": Vector2(8, -8), "rot": -135.0, "flip": false, "show": true },
            3: { "pos": Vector2(4, -4), "rot": -150.0, "flip": false, "show": true },
        },
        "attack_1h_left": {
            0: { "pos": Vector2(8, -4), "rot": -90.0, "flip": false, "show": true },
            1: { "pos": Vector2(-12, 0), "rot": 180.0, "flip": false, "show": true },
            2: { "pos": Vector2(-8, 8), "rot": 135.0, "flip": false, "show": true },
            3: { "pos": Vector2(-4, 4), "rot": 120.0, "flip": false, "show": true },
        },
        "attack_1h_right": {
            0: { "pos": Vector2(-8, -4), "rot": 90.0, "flip": true, "show": true },
            1: { "pos": Vector2(12, 0), "rot": 0.0, "flip": false, "show": true },
            2: { "pos": Vector2(8, 8), "rot": -45.0, "flip": false, "show": true },
            3: { "pos": Vector2(4, 4), "rot": -60.0, "flip": false, "show": true },
        },
    }


func _advance_frame() -> void:
    var start_frame = _anim_data.get("start", 0)
    var end_frame = _anim_data.get("end", 0)
    var should_loop = _anim_data.get("loop", true)

    _current_frame += 1

    if _current_frame > end_frame:
        if should_loop:
            _current_frame = start_frame
        else:
            _current_frame = end_frame
            _is_playing = false
            _on_animation_finished()
            return

    _update_sprite_region()
    _update_weapon_position()  # NEW
    frame_changed.emit(_current_frame)


func _on_animation_finished() -> void:
    var anim_name = _current_state + "_" + _current_direction
    animation_finished.emit(anim_name)

    # Auto-return to idle after attack
    if _current_state.begins_with("attack"):
        _weapon_visible = false
        weapon_sprite.visible = false
        play("idle", _current_direction)


func _update_weapon_position() -> void:
    if not _weapon_visible or not _weapon_texture:
        weapon_sprite.visible = false
        return

    # Get anchor key
    var anchor_key = _current_state + "_" + _current_direction
    if not _anchor_data.has(anchor_key):
        weapon_sprite.visible = false
        return

    # Get frame-specific anchor (relative frame index)
    var start_frame = _anim_data.get("start", 0)
    var local_frame = _current_frame - start_frame

    if not _anchor_data[anchor_key].has(local_frame):
        weapon_sprite.visible = false
        return

    var anchor = _anchor_data[anchor_key][local_frame]

    weapon_sprite.visible = anchor.get("show", true)
    if weapon_sprite.visible:
        weapon_sprite.position = anchor.get("pos", Vector2.ZERO)
        weapon_sprite.rotation_degrees = anchor.get("rot", 0.0)
        weapon_sprite.flip_h = anchor.get("flip", false)


# =============================================================================
# WEAPON API
# =============================================================================

## Set weapon texture (call when equipment changes)
func set_weapon(texture: Texture2D, category: String = "1h") -> void:
    _weapon_texture = texture
    _weapon_category = category
    weapon_sprite.texture = texture

    if texture == null:
        _weapon_visible = false
        weapon_sprite.visible = false


## Get current weapon category
func get_weapon_category() -> String:
    return _weapon_category


## Play attack animation
func play_attack() -> void:
    if not _weapon_texture:
        # No weapon equipped, still play unarmed attack or skip
        push_warning("No weapon equipped for attack")
        return

    _weapon_visible = true
    var attack_state = "attack_" + _weapon_category  # e.g., "attack_1h"
    play(attack_state, _current_direction)
```

---

### Step 4.2: Update VisualAssetManager for Attack Animations

**Modify**: `autoloads/visual_asset_manager.gd`

Add attack animation data:

```gdscript
# Add to _animations dictionary in visual_asset_manager.gd

var _animations: Dictionary = {
    # ... existing idle and walk ...

    "humanoid_attack_1h": {
        "down":  { "start": 0,  "end": 3,  "fps": 12.0, "loop": false },
        "up":    { "start": 4,  "end": 7,  "fps": 12.0, "loop": false },
        "left":  { "start": 8,  "end": 11, "fps": 12.0, "loop": false },
        "right": { "start": 12, "end": 15, "fps": 12.0, "loop": false },
    },
}

# Add to _sprite_meta dictionary
var _sprite_meta: Dictionary = {
    # ... existing ...
    "humanoid_attack_1h": { "frame_width": 32, "frame_height": 32, "columns": 4 },
}


## Get weapon texture
func get_weapon_texture(weapon_id: String, category: String) -> Texture2D:
    var path = "sprites/weapons/" + category + "/" + weapon_id + ".png"
    return get_texture(path)
```

---

### Step 4.3: Connect to Combat System

**Modify**: `scripts/player/player_controller.gd`

Connect attack input to animation:

```gdscript
# Add to player_controller.gd

var _is_attacking: bool = false


func _ready() -> void:
    # ... existing code ...

    # Connect animation finished signal
    if _animator:
        _animator.animation_finished.connect(_on_attack_finished)


func _input(event: InputEvent) -> void:
    # Basic attack on action button (adapt to your input setup)
    if event.is_action_pressed("attack") and not _is_attacking:
        _perform_attack()


func _perform_attack() -> void:
    if _is_attacking:
        return

    _is_attacking = true

    # Tell animator to play attack
    _animator.play_attack()

    # Your existing hitbox/damage logic here
    # _spawn_hitbox()
    # etc.


func _on_attack_finished(anim_name: String) -> void:
    if anim_name.begins_with("attack"):
        _is_attacking = false


func _update_animation() -> void:
    if not _animator or _is_attacking:
        return  # Don't override attack animation

    # ... existing movement animation logic ...
```

---

### Step 4.4: Set Up Weapon on Equipment Change

**Modify**: Equipment connection code

```gdscript
# Add to player equipment handling

func _on_equipment_changed(slot: String, item: ItemData) -> void:
    if not _animator:
        return

    match slot:
        "weapon", "main_hand":
            if item:
                var category = _get_weapon_category(item)
                var texture = VisualAssets.get_weapon_texture(item.id, category)
                _animator.set_weapon(texture, category)
            else:
                _animator.set_weapon(null)

        # ... existing armor/helmet/boots handling ...


func _get_weapon_category(item: ItemData) -> String:
    # Determine category based on item data
    # Adapt to your item system
    match item.weapon_type:
        "sword", "axe", "mace", "dagger":
            return "1h"
        "greatsword", "staff", "polearm":
            return "2h"
        "bow", "crossbow":
            return "bow"
        _:
            return "1h"
```

---

### Step 4.5: Create Test Scene for Combat

**File**: `scenes/test/test_combat_anim.tscn`

```gdscript
# scenes/test/test_combat_anim.gd
extends Node2D

@onready var animator: UVCharacterAnimator = $UVCharacterAnimator
@onready var label: Label = $UI/Label

var directions = ["down", "up", "left", "right"]
var current_dir = 0


func _ready() -> void:
    # Load a test weapon
    var sword = VisualAssets.get_weapon_texture("sword_iron", "1h")
    animator.set_weapon(sword, "1h")
    _update_label()


func _input(event: InputEvent) -> void:
    # Attack on space
    if event.is_action_pressed("ui_accept"):
        animator.play_attack()

    # Change direction
    if event.is_action_pressed("ui_right"):
        current_dir = (current_dir + 1) % 4
        animator.set_direction(directions[current_dir])
        _update_label()

    if event.is_action_pressed("ui_left"):
        current_dir = (current_dir - 1 + 4) % 4
        animator.set_direction(directions[current_dir])
        _update_label()

    # Toggle walk
    if event.is_action_pressed("ui_up"):
        if animator.get_state() == "idle":
            animator.play("walk", directions[current_dir])
        else:
            animator.play("idle", directions[current_dir])
        _update_label()


func _update_label() -> void:
    label.text = "Direction: %s\nState: %s\n\nSPACE = Attack\n← → = Change direction\n↑ = Toggle walk" % [
        directions[current_dir],
        animator.get_state()
    ]
```

---

### Step 4.6: Create Attack Animation Assets

**USER TASK: Create attack motion map and weapon sprite**

#### Asset 1: Attack Motion Map (1-handed)

**File**: `assets/sprites/characters/player/motion/humanoid_attack_1h.png`
**Size**: 128×128 pixels (4 columns × 4 rows of 32×32 frames)

**Layout**:
```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: Frames 0-3 = DOWN attack
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: Frames 4-7 = UP attack
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: Frames 8-11 = LEFT attack
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: Frames 12-15 = RIGHT attack
└─────┴─────┴─────┴─────┘
```

**Attack animation breakdown (4 frames)**:

```
Frame 1: WIND-UP (Anticipation)
┌────────────────┐
│                │
│    ┌───┐       │  Character pulls back
│    │ O │  \    │  Arm raised/back
│    ├───┤   \   │
│   ╱│   │╲      │
│    │   │       │
└────────────────┘

Frame 2: APEX (Key action frame)
┌────────────────┐
│                │
│    ┌───┐       │  Maximum extension
│    │ O │───    │  Arm fully forward
│    ├───┤       │
│   ╱│   │╲      │
│    │   │       │
└────────────────┘

Frame 3: FOLLOW-THROUGH
┌────────────────┐
│                │
│    ┌───┐       │  Past the strike
│    │ O │       │  Arm continuing motion
│    ├───┤  /    │
│   ╱│   │╲/     │
│    │   │       │
└────────────────┘

Frame 4: RECOVERY
┌────────────────┐
│                │
│    ┌───┐       │  Returning to ready
│    │ O │       │  Weight settling
│    ├───┤       │
│   ╱│   │╲      │
│    │   │       │
└────────────────┘
```

**Color-Lookup data**: Same principle as idle/walk:
1. Each pixel in the animation is colored to match the UV Map
2. The shader searches for that color in the UV Map
3. Found position is used to sample the Lookup Texture (skin)
4. Alpha channel defines the character silhouette

**Important**: Body pose changes between frames! The silhouette should show:
- Frame 1: Character leaning back, arm raised
- Frame 2: Character lunging forward, arm extended
- Frame 3: Character following through
- Frame 4: Character returning to neutral

**Creating attack animation frames:**
1. Draw the character pose for each frame (defines alpha channel silhouette)
2. Color each visible pixel using colors from your UV Map
3. Body parts use colors from corresponding UV Map regions
4. Same UV Map and Lookup Texture as idle/walk animations

#### Asset 2: Weapon Sprite (Iron Sword)

**File**: `assets/sprites/weapons/1h/sword_iron.png`
**Size**: 32×16 pixels (horizontal orientation)

**What to draw**: Sword pointing RIGHT (handle left, tip right)

```
┌────────────────────────────────────────────────────┐
│                                                    │
│ ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▶      │
│ ▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▶        │
│ ▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▶      │
│                                                    │
└────────────────────────────────────────────────────┘
  ↑ Handle (brown/dark)     Blade (gray/silver)  ↑ Tip
```

**Design breakdown**:
```
HANDLE (left ~8px):
- Dark brown grip: #4A3728
- Lighter wood grain: #6B4423
- Maybe a simple crossguard

BLADE (middle ~20px):
- Base steel: #A0A0A0
- Edge highlight: #D0D0D0
- Fuller (groove) darker: #707070

TIP (right ~4px):
- Pointed, same colors as blade
- Slight highlight at edge
```

**The sprite will be rotated by the anchor system**, so:
- Draw it horizontal, pointing right
- Anchor rotation values will orient it correctly for each attack frame

---

## ANCHOR TUNING GUIDE

The anchor data provided is a starting point. You'll likely need to tune it:

**To adjust anchors:**
1. Run test_combat_anim scene
2. Trigger attack, observe weapon position
3. If weapon is off:
   - `pos.x` positive = right, negative = left
   - `pos.y` positive = down, negative = up
   - `rot` in degrees, 0° = pointing right
4. Edit `_load_anchor_data()` values
5. Repeat until it looks good

**Visual reference for rotation**:
```
rot = 0°    → pointing right
rot = 90°   → pointing down
rot = 180°  → pointing left
rot = -90°  → pointing up
rot = 45°   → pointing down-right
```

**Frame timing tip**: If attack feels slow/fast, adjust FPS in animation data.

---

## VALIDATION CHECKLIST

After implementation, verify:

- [ ] Attack motion map loads
- [ ] Weapon sprite loads
- [ ] Pressing attack plays animation
- [ ] Weapon appears during attack
- [ ] Weapon positioned correctly frame 1 (wind-up)
- [ ] Weapon positioned correctly frame 2 (apex)
- [ ] Weapon positioned correctly frame 3 (follow-through)
- [ ] Weapon positioned correctly frame 4 (recovery)
- [ ] Weapon hidden after attack ends
- [ ] Returns to idle after attack
- [ ] Attack works in all 4 directions
- [ ] Can't spam attacks (is_attacking flag works)
- [ ] Equipment armor still shows during attack

**Direction-specific tests**:
```
Attack DOWN  → Weapon swings downward
Attack UP    → Weapon swings upward
Attack LEFT  → Weapon swings left
Attack RIGHT → Weapon swings right
```

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| Weapon not visible | _weapon_visible not set, or texture null |
| Weapon in wrong place | Anchor pos values need tuning |
| Weapon wrong angle | Anchor rot values need tuning |
| Weapon on wrong side | flip_h might need toggling |
| Animation too fast/slow | fps value in animation data |
| Attack never ends | loop should be false for attacks |
| Can attack while attacking | _is_attacking flag not working |

---

## FILES CREATED THIS PHASE

```
autoloads/
└── visual_asset_manager.gd       ← MODIFIED (attack animations, weapon loading)

scripts/
└── rendering/
    └── uv_character_animator.gd  ← MODIFIED (weapon sprite, anchors, attack)

scripts/
└── player/
    └── player_controller.gd      ← MODIFIED (attack input, animation connection)

scenes/
└── test/
    ├── test_combat_anim.tscn
    └── test_combat_anim.gd

assets/
└── sprites/
    ├── characters/
    │   └── player/
    │       └── motion/
    │           └── humanoid_attack_1h.png   ← USER CREATES
    └── weapons/
        └── 1h/
            └── sword_iron.png               ← USER CREATES
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_5_ENEMIES.md` which adds:
- Enemy UV shader (simplified single-skin)
- Enemy motion maps (slime or wolf)
- Skin variants for enemy types
- Integration with enemy spawning system

---

## NOTES FOR IMPLEMENTER

- Weapon sprites draw OVER the character (z_index = 1)
- For complex attacks, you might need weapon to go BEHIND character some frames
- Anchor data will eventually move to database - this is hardcoded for testing
- The attack animation doesn't include the hitbox logic - that's your existing combat system
- 2-handed and bow attacks will need different anchor sets (Phase 4 is 1h only)
- Consider adding attack "trails" or "swoosh" effects later (Phase 8 polish)
- **Color-Lookup Note**: Attack animations use the same UV Map and skin as idle/walk

---

## HIT FEEDBACK PREVIEW

While not the focus of Phase 4, you can test hit flash:

```gdscript
# When enemy takes damage:
enemy_animator.flash(0.1, Color.WHITE)

# When player takes damage:
player_animator.flash(0.1, Color.WHITE)
```

Screen shake and hitstop come in Phase 8 (Polish).

---

*Document Version: 2.0 - Updated for Color-Lookup System*
*Last Updated: Session claude/phase-1-TestingShaders-spp2s*
