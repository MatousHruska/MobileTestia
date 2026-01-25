# PHASE 5: ENEMIES

> **Goal**: Enemy characters using UV lookup system with skin variants
> **Prerequisites**: Phase 4 complete (player combat working)
> **Estimated Scope**: Medium - enemy shader + motion maps + skin variants + spawner integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Enemy silhouette philosophy, variant approach
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Enemy shader (simplified single-skin)
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Enemy asset specifications
- `docs/visual_phases/PHASE_4_PLAYER_COMBAT.md` - What was built in Phase 4
- `docs/ENEMY_REFERENCE.md` - Existing enemy system documentation

**Key decisions from Art Direction:**
- Enemies use UV lookup but with SINGLE skin (not layered like player)
- Same motion map + different skins = enemy variants
- Silhouettes should be distinct per enemy TYPE (wolf ≠ skeleton ≠ slime)
- COLOR differentiates variants within a type (green slime vs red slime)
- Enemy animations: idle, walk, attack, hit, die (minimum set)

---

## IMPLEMENTATION STEPS

### Step 5.1: Create Enemy UV Shader

**File**: `shaders/uv_lookup_enemy.gdshader`

Simplified single-skin version for enemies:

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Single skin texture for enemy appearance
uniform sampler2D skin : hint_default_white, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Damage/death effects
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hurt_desaturate : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Sample motion map
    vec4 motion_data = texture(TEXTURE, UV);

    if (motion_data.a < 0.01) {
        discard;
    }

    // UV lookup into skin
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);
    vec4 skin_color = texture(skin, skin_uv);

    vec4 final_color = skin_color;

    // Apply tint (for poison, burn, etc.)
    final_color.rgb *= tint.rgb;

    // Hurt desaturation effect
    if (hurt_desaturate > 0.0) {
        float gray = dot(final_color.rgb, vec3(0.299, 0.587, 0.114));
        final_color.rgb = mix(final_color.rgb, vec3(gray), hurt_desaturate);
    }

    // Hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Dissolve effect (for death)
    if (dissolve_amount > 0.0) {
        // Use motion map blue channel or noise for dissolve pattern
        float dissolve_threshold = motion_data.b;
        if (dissolve_threshold < dissolve_amount) {
            discard;
        }
        // Edge glow near dissolve boundary
        if (dissolve_threshold < dissolve_amount + 0.1) {
            final_color.rgb += vec3(1.0, 0.5, 0.0) * 0.5; // Orange edge glow
        }
    }

    COLOR = vec4(final_color.rgb, motion_data.a * skin_color.a);
}
```

---

### Step 5.2: Create Enemy UV Animator

**File**: `scripts/rendering/uv_enemy_animator.gd`

Simplified animator for enemies:

```gdscript
class_name UVEnemyAnimator
extends Node2D

## Handles UV lookup animation for enemies
## Simpler than player - single skin, no equipment

signal animation_finished(anim_name: String)
signal frame_changed(frame: int)

@onready var sprite: Sprite2D = $Sprite2D

# Shader material
var _material: ShaderMaterial

# Enemy type (determines motion map)
var _enemy_type: String = "slime"  # slime, wolf, skeleton, etc.
var _skin_id: String = "slime_green"

# Animation state
var _current_state: String = "idle"
var _current_direction: String = "down"
var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = true

# Cached data
var _anim_data: Dictionary = {}
var _sprite_meta: Dictionary = {}

# Animation definitions per enemy type
var _enemy_animations: Dictionary = {
    "slime": {
        "idle":   { "frames": 4,  "fps": 6.0,  "loop": true },
        "walk":   { "frames": 4,  "fps": 8.0,  "loop": true },
        "attack": { "frames": 4,  "fps": 10.0, "loop": false },
        "hit":    { "frames": 2,  "fps": 12.0, "loop": false },
        "die":    { "frames": 6,  "fps": 8.0,  "loop": false },
    },
    "wolf": {
        "idle":   { "frames": 4,  "fps": 6.0,  "loop": true },
        "walk":   { "frames": 6,  "fps": 10.0, "loop": true },
        "attack": { "frames": 4,  "fps": 12.0, "loop": false },
        "hit":    { "frames": 2,  "fps": 12.0, "loop": false },
        "die":    { "frames": 6,  "fps": 8.0,  "loop": false },
    },
}

# Sprite metadata per enemy type
var _enemy_sprite_meta: Dictionary = {
    "slime": { "frame_width": 24, "frame_height": 24, "columns": 4 },
    "wolf":  { "frame_width": 32, "frame_height": 32, "columns": 4 },
}


func _ready() -> void:
    _setup_sprite()
    _setup_material()


func _setup_sprite() -> void:
    if not sprite:
        sprite = Sprite2D.new()
        sprite.name = "Sprite2D"
        add_child(sprite)

    sprite.centered = true
    sprite.region_enabled = true


func _setup_material() -> void:
    _material = ShaderMaterial.new()
    _material.shader = load("res://shaders/uv_lookup_enemy.gdshader")
    sprite.material = _material


func _process(delta: float) -> void:
    if not _is_playing or _anim_data.is_empty():
        return

    _animation_timer += delta
    var frame_duration = 1.0 / _anim_data.get("fps", 10.0)

    if _animation_timer >= frame_duration:
        _animation_timer -= frame_duration
        _advance_frame()


func _advance_frame() -> void:
    var total_frames = _anim_data.get("frames", 1)
    var should_loop = _anim_data.get("loop", true)

    _current_frame += 1

    if _current_frame >= total_frames:
        if should_loop:
            _current_frame = 0
        else:
            _current_frame = total_frames - 1
            _is_playing = false
            animation_finished.emit(_current_state)
            return

    _update_sprite_region()
    frame_changed.emit(_current_frame)


func _update_sprite_region() -> void:
    var fw = _sprite_meta.get("frame_width", 24)
    var fh = _sprite_meta.get("frame_height", 24)
    var cols = _sprite_meta.get("columns", 4)

    # Calculate frame position in spritesheet
    # Layout: rows are states, each state has frames × directions
    var state_index = _get_state_index()
    var dir_index = _get_direction_index()
    var frames_per_dir = _anim_data.get("frames", 1)

    var total_frame = (state_index * 4 * frames_per_dir) + (dir_index * frames_per_dir) + _current_frame

    var col = total_frame % cols
    var row = total_frame / cols

    sprite.region_rect = Rect2(col * fw, row * fh, fw, fh)


func _get_state_index() -> int:
    match _current_state:
        "idle": return 0
        "walk": return 1
        "attack": return 2
        "hit": return 3
        "die": return 4
    return 0


func _get_direction_index() -> int:
    match _current_direction:
        "down": return 0
        "up": return 1
        "left": return 2
        "right": return 3
    return 0


# =============================================================================
# PUBLIC API
# =============================================================================

## Initialize enemy with type and skin
func setup(enemy_type: String, skin_id: String) -> void:
    _enemy_type = enemy_type
    _skin_id = skin_id

    # Load motion map
    var motion_path = "res://assets/sprites/characters/enemies/" + enemy_type + "/motion/" + enemy_type + "_all.png"
    if ResourceLoader.exists(motion_path):
        sprite.texture = load(motion_path)
    else:
        push_warning("Enemy motion map not found: " + motion_path)

    # Load skin
    var skin_path = "res://assets/sprites/characters/enemies/" + enemy_type + "/skins/" + skin_id + ".png"
    if ResourceLoader.exists(skin_path):
        _material.set_shader_parameter("skin", load(skin_path))
    else:
        push_warning("Enemy skin not found: " + skin_path)

    # Get metadata
    _sprite_meta = _enemy_sprite_meta.get(enemy_type, { "frame_width": 24, "frame_height": 24, "columns": 4 })

    # Start idle
    play("idle", "down")


## Play animation
func play(state: String, direction: String = "") -> void:
    if direction.is_empty():
        direction = _current_direction

    _current_state = state
    _current_direction = direction

    # Get animation data for this enemy type and state
    if _enemy_animations.has(_enemy_type) and _enemy_animations[_enemy_type].has(state):
        _anim_data = _enemy_animations[_enemy_type][state]
    else:
        _anim_data = { "frames": 1, "fps": 10.0, "loop": true }

    _current_frame = 0
    _animation_timer = 0.0
    _is_playing = true

    _update_sprite_region()


## Set direction
func set_direction(direction: String) -> void:
    if direction != _current_direction:
        _current_direction = direction
        _update_sprite_region()


## Stop animation
func stop() -> void:
    _is_playing = false


## Get current state
func get_state() -> String:
    return _current_state


## Hit flash effect
func flash(duration: float = 0.1, color: Color = Color.WHITE) -> void:
    _material.set_shader_parameter("flash_color", color)
    _material.set_shader_parameter("flash_amount", 1.0)

    var tween = create_tween()
    tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, duration)


## Apply tint
func set_tint(color: Color) -> void:
    _material.set_shader_parameter("tint", color)


## Clear tint
func clear_tint() -> void:
    _material.set_shader_parameter("tint", Color.WHITE)


## Play death with dissolve effect
func play_death() -> void:
    play("die", _current_direction)
    _start_dissolve()


func _start_dissolve() -> void:
    # Start dissolve after die animation begins
    await get_tree().create_timer(0.3).timeout

    var tween = create_tween()
    tween.tween_property(_material, "shader_parameter/dissolve_amount", 1.0, 0.5)
```

---

### Step 5.3: Create Enemy Animator Scene

**File**: `scenes/rendering/uv_enemy_animator.tscn`

```
UVEnemyAnimator (Node2D, script: uv_enemy_animator.gd)
└── Sprite2D
```

---

### Step 5.4: Update VisualAssetManager for Enemies

**Modify**: `autoloads/visual_asset_manager.gd`

```gdscript
# Add these methods to visual_asset_manager.gd

## Get enemy motion map
func get_enemy_motion_map(enemy_type: String) -> Texture2D:
    var path = "sprites/characters/enemies/" + enemy_type + "/motion/" + enemy_type + "_all.png"
    return get_texture(path)


## Get enemy skin
func get_enemy_skin(enemy_type: String, skin_id: String) -> Texture2D:
    var path = "sprites/characters/enemies/" + enemy_type + "/skins/" + skin_id + ".png"
    return get_texture(path)


## Get enemy sprite metadata
func get_enemy_sprite_meta(enemy_type: String) -> Dictionary:
    var meta = {
        "slime": { "frame_width": 24, "frame_height": 24, "columns": 4 },
        "wolf":  { "frame_width": 32, "frame_height": 32, "columns": 4 },
        "skeleton": { "frame_width": 32, "frame_height": 32, "columns": 4 },
    }
    return meta.get(enemy_type, { "frame_width": 24, "frame_height": 24, "columns": 4 })
```

---

### Step 5.5: Integrate with Enemy NPC System

**Modify**: `scripts/npc/enemy_npc.gd`

Add UV animator to enemies:

```gdscript
# Add/modify in enemy_npc.gd

var _uv_animator: UVEnemyAnimator


func _ready() -> void:
    # ... existing code ...
    _setup_uv_visuals()


func _setup_uv_visuals() -> void:
    # Get enemy visual data from database
    var enemy_data = DatabaseLoader.get_enemy(_enemy_id)
    var enemy_type = enemy_data.get("visual_type", "slime")  # e.g., "slime", "wolf"
    var skin_id = enemy_data.get("skin_id", "slime_green")   # e.g., "slime_green", "wolf_white"

    # Create UV animator
    _uv_animator = preload("res://scenes/rendering/uv_enemy_animator.tscn").instantiate()
    add_child(_uv_animator)
    _uv_animator.setup(enemy_type, skin_id)

    # Hide old placeholder sprite if exists
    if has_node("Sprite2D"):
        $Sprite2D.visible = false


func _process(delta: float) -> void:
    # ... existing code ...
    _update_animation()


func _update_animation() -> void:
    if not _uv_animator:
        return

    # Update direction based on movement
    if velocity.length() > 0.1:
        var dir = _velocity_to_direction(velocity)
        _uv_animator.set_direction(dir)

        if _uv_animator.get_state() != "walk":
            _uv_animator.play("walk")
    else:
        if _uv_animator.get_state() == "walk":
            _uv_animator.play("idle")


func _velocity_to_direction(vel: Vector2) -> String:
    if abs(vel.y) > abs(vel.x):
        return "down" if vel.y > 0 else "up"
    else:
        return "right" if vel.x > 0 else "left"


func _on_attack() -> void:
    # Called when enemy attacks
    if _uv_animator:
        _uv_animator.play("attack")


func _on_hit(damage: float) -> void:
    # Called when enemy takes damage
    if _uv_animator:
        _uv_animator.flash(0.1)
        _uv_animator.play("hit")


func _on_death() -> void:
    # Called when enemy dies
    if _uv_animator:
        _uv_animator.play_death()
```

---

### Step 5.6: Update Enemy Database

**Database changes needed** (provide to user for Excel):

Add fields to Enemies sheet:
- `visual_type` (string): "slime", "wolf", "skeleton", etc.
- `skin_id` (string): "slime_green", "wolf_white", etc.

**Example enemy entries:**
```
id              | name           | visual_type | skin_id
----------------|----------------|-------------|---------------
enemy_slime_01  | Green Slime    | slime       | slime_green
enemy_slime_02  | Red Slime      | slime       | slime_red
enemy_slime_03  | Blue Slime     | slime       | slime_blue
enemy_wolf_01   | Starved Wolf   | wolf        | wolf_starved
enemy_wolf_02   | White Wolf     | wolf        | wolf_white
enemy_wolf_03   | Alpha Wolf     | wolf        | wolf_alpha
```

---

### Step 5.7: Create Test Scene for Enemies

**File**: `scenes/test/test_enemy_visuals.tscn`

```gdscript
# scenes/test/test_enemy_visuals.gd
extends Node2D

@onready var label: Label = $UI/Label

var enemy_configs = [
    { "type": "slime", "skin": "slime_green", "name": "Green Slime" },
    { "type": "slime", "skin": "slime_red", "name": "Red Slime" },
    { "type": "slime", "skin": "slime_blue", "name": "Blue Slime" },
]
var current_config = 0
var animator: UVEnemyAnimator


func _ready() -> void:
    _spawn_enemy()
    _update_label()


func _spawn_enemy() -> void:
    # Remove old
    if animator:
        animator.queue_free()

    # Create new
    animator = preload("res://scenes/rendering/uv_enemy_animator.tscn").instantiate()
    add_child(animator)
    animator.position = Vector2(240, 135)  # Center of 480x270

    var config = enemy_configs[current_config]
    animator.setup(config.type, config.skin)


func _input(event: InputEvent) -> void:
    # Cycle enemies
    if event.is_action_pressed("ui_right"):
        current_config = (current_config + 1) % enemy_configs.size()
        _spawn_enemy()
        _update_label()

    if event.is_action_pressed("ui_left"):
        current_config = (current_config - 1 + enemy_configs.size()) % enemy_configs.size()
        _spawn_enemy()
        _update_label()

    # Test animations
    if event.is_action_pressed("ui_accept"):
        animator.play("attack")

    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_W:
                animator.play("walk", animator._current_direction)
            KEY_I:
                animator.play("idle", animator._current_direction)
            KEY_H:
                animator.flash()
                animator.play("hit")
            KEY_D:
                animator.play_death()


func _update_label() -> void:
    var config = enemy_configs[current_config]
    label.text = "%s\n\n← → = Change enemy\nSPACE = Attack\nW = Walk\nI = Idle\nH = Hit\nD = Die" % config.name
```

---

### Step 5.8: Create Enemy Assets

**USER TASK: Create slime enemy assets**

We'll use **Slime** as the first enemy (simplest to animate).

#### Asset 1: Slime Motion Map (All Animations)

**File**: `assets/sprites/characters/enemies/slime/motion/slime_all.png`
**Size**: 96×120 pixels (4 columns × 5 rows of 24×24 frames)

**Spritesheet Layout**:
```
             Col0   Col1   Col2   Col3
           ┌──────┬──────┬──────┬──────┐
Row 0:     │ I-D  │ I-U  │ I-L  │ I-R  │  IDLE (4 frames total, 1 per direction)
           │ frm0 │ frm0 │ frm0 │ frm0 │  (or 4 frames × 4 dirs = needs more rows)
           ├──────┼──────┼──────┼──────┤
Row 1:     │ W-D  │ W-U  │ W-L  │ W-R  │  WALK
           ├──────┼──────┼──────┼──────┤
Row 2:     │ A-D  │ A-U  │ A-L  │ A-R  │  ATTACK
           ├──────┼──────┼──────┼──────┤
Row 3:     │ H-D  │ H-U  │ H-L  │ H-R  │  HIT
           ├──────┼──────┼──────┼──────┤
Row 4:     │ D1   │ D2   │ D3   │ D4   │  DIE (not directional)
           └──────┴──────┴──────┴──────┘
```

**Alternative simpler layout** (slimes look same from all directions):
```
             Col0   Col1   Col2   Col3
           ┌──────┬──────┬──────┬──────┐
Row 0:     │ Idle1│ Idle2│ Idle3│ Idle4│  IDLE (4 frames)
           ├──────┼──────┼──────┼──────┤
Row 1:     │ Walk1│ Walk2│ Walk3│ Walk4│  WALK (4 frames)
           ├──────┼──────┼──────┼──────┤
Row 2:     │ Atk1 │ Atk2 │ Atk3 │ Atk4 │  ATTACK (4 frames)
           ├──────┼──────┼──────┼──────┤
Row 3:     │ Hit1 │ Hit2 │      │      │  HIT (2 frames)
           ├──────┼──────┼──────┼──────┤
Row 4:     │ Die1 │ Die2 │ Die3 │ Die4 │  DIE (4+ frames)
           ├──────┼──────┼──────┼──────┤
Row 5:     │ Die5 │ Die6 │      │      │  DIE continued
           └──────┴──────┴──────┴──────┘
```

**Animation descriptions for slime**:

```
IDLE (4 frames) - Gentle breathing/pulsing
Frame 1: Normal blob shape
Frame 2: Slightly taller (stretch up)
Frame 3: Normal blob shape
Frame 4: Slightly wider (squash)

WALK (4 frames) - Hopping motion
Frame 1: Squash (preparing to hop)
Frame 2: Stretch up (leaving ground)
Frame 3: In air (compact)
Frame 4: Landing (squash on impact)

ATTACK (4 frames) - Lunge forward
Frame 1: Pull back (wind-up)
Frame 2: Stretch forward (lunge)
Frame 3: Maximum extension (impact)
Frame 4: Return to normal

HIT (2 frames) - React to damage
Frame 1: Squash/flatten
Frame 2: Wobble

DIE (6 frames) - Splatter
Frame 1: Flatten
Frame 2: Start breaking apart
Frame 3: Splitting
Frame 4: Pieces separating
Frame 5: Dissolving
Frame 6: Nearly gone
```

**UV encoding**: Same as player - R,G channels are UV coordinates.

#### Asset 2: Slime Skins (3 variants)

**Files**:
- `assets/sprites/characters/enemies/slime/skins/slime_green.png`
- `assets/sprites/characters/enemies/slime/skins/slime_red.png`
- `assets/sprites/characters/enemies/slime/skins/slime_blue.png`

**Size**: 24×24 pixels each

**What to draw**: A slime blob with face

```
GREEN SLIME:                RED SLIME:                 BLUE SLIME:
┌──────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│                      │    │                      │    │                      │
│       ██████         │    │       ██████         │    │       ██████         │
│     ██████████       │    │     ██████████       │    │     ██████████       │
│    ████░░░░████      │    │    ████░░░░████      │    │    ████░░░░████      │
│   ████ ●  ● ████     │   │   ████ ●  ● ████     │    │   ████ ●  ● ████     │
│    ████░░░░████      │    │    ████░░░░████      │    │    ████░░░░████      │
│     ██████████       │    │     ██████████       │    │     ██████████       │
│       ██████         │    │       ██████         │    │       ██████         │
│                      │    │                      │    │                      │
└──────────────────────┘    └──────────────────────┘    └──────────────────────┘

Colors:                     Colors:                     Colors:
- Body: #44AA44, #66CC66    - Body: #AA4444, #CC6666    - Body: #4444AA, #6666CC
- Highlight: #88EE88        - Highlight: #EE8888        - Highlight: #8888EE
- Shadow: #226622           - Shadow: #662222           - Shadow: #222266
- Eyes: #000000             - Eyes: #000000             - Eyes: #000000
- Eye shine: #FFFFFF        - Eye shine: #FFFFFF        - Eye shine: #FFFFFF
```

**Expression ideas for variants**:
- Green: Neutral, curious expression
- Red: Angry, furrowed brow
- Blue: Sleepy, half-closed eyes

---

## VALIDATION CHECKLIST

After implementation, verify:

- [ ] Enemy shader compiles without errors
- [ ] UVEnemyAnimator loads and displays
- [ ] Slime renders with green skin
- [ ] Slime renders with red skin (variant)
- [ ] Slime renders with blue skin (variant)
- [ ] Idle animation plays
- [ ] Walk animation plays
- [ ] Attack animation plays
- [ ] Hit animation plays with flash
- [ ] Death animation plays with dissolve
- [ ] Direction changes work
- [ ] Enemy spawner creates UV-animated enemies
- [ ] Enemy AI triggers correct animations

**Test each variant**:
```
Green Slime → Uses slime_green.png skin
Red Slime   → Uses slime_red.png skin (same animation!)
Blue Slime  → Uses slime_blue.png skin (same animation!)
```

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| Enemy invisible | Motion map or skin not loading |
| Wrong color | skin_id not matching file name |
| Animation wrong | Frame count or row calculation off |
| Dissolve not working | Blue channel not set up in motion map |
| No direction change | _update_sprite_region() not accounting for direction |

---

## FILES CREATED THIS PHASE

```
shaders/
└── uv_lookup_enemy.gdshader

scripts/
└── rendering/
    └── uv_enemy_animator.gd

scenes/
└── rendering/
    └── uv_enemy_animator.tscn

scenes/
└── test/
    ├── test_enemy_visuals.tscn
    └── test_enemy_visuals.gd

assets/
└── sprites/
    └── characters/
        └── enemies/
            └── slime/
                ├── motion/
                │   └── slime_all.png       ← USER CREATES
                └── skins/
                    ├── slime_green.png     ← USER CREATES
                    ├── slime_red.png       ← USER CREATES
                    └── slime_blue.png      ← USER CREATES

scripts/
└── npc/
    └── enemy_npc.gd                        ← MODIFIED
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_6_WORLD_OBJECTS.md` which adds:
- Chest sprites (open/closed states)
- Loot drop visuals
- Basic tileset creation
- LDTK integration with new tiles

---

## NOTES FOR IMPLEMENTER

- Slimes are chosen because they're direction-agnostic (look same from all angles)
- For directional enemies (wolf, skeleton), you'll need more frames per animation
- The dissolve effect uses the blue channel of motion map as a noise pattern
- Enemy variant system is key for content scaling - same animations, many looks
- Database integration assumes `visual_type` and `skin_id` fields exist on enemies
- Consider adding enemy-specific animation callbacks for attack timing (hitbox spawning)
