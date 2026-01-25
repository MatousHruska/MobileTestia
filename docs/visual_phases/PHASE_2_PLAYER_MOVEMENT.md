# PHASE 2: PLAYER MOVEMENT ANIMATION

> **Goal**: Animated player character with 4-directional movement (idle + walk)
> **Prerequisites**: Phase 1 complete (UV shader working)
> **Estimated Scope**: Medium - animator component + motion maps + integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Animation philosophy ("pixel impressionism")
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Animation system architecture
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Asset specifications
- `docs/visual_phases/PHASE_1_BASIC_SHADER.md` - What was built in Phase 1

**Key decisions from Art Direction:**
- 4 directions: down, up, left, right
- Idle: 4 frames at 6-8 FPS
- Walk: 6 frames at 10-12 FPS
- "Pixel impressionism" - keyframes at apex, let brain interpolate

---

## IMPLEMENTATION STEPS

### Step 2.1: Create VisualAssetManager (Minimal Version)

**File**: `autoloads/visual_asset_manager.gd`

This singleton manages loading and caching visual assets.

```gdscript
extends Node

## Minimal VisualAssetManager for Phase 2
## Will be expanded in later phases

# Texture cache
var _textures: Dictionary = {}

# Animation data (hardcoded for now, database-driven later)
var _animations: Dictionary = {
    "humanoid_idle": {
        "down":  { "start": 0,  "end": 3,  "fps": 6.0, "loop": true },
        "up":    { "start": 4,  "end": 7,  "fps": 6.0, "loop": true },
        "left":  { "start": 8,  "end": 11, "fps": 6.0, "loop": true },
        "right": { "start": 12, "end": 15, "fps": 6.0, "loop": true },
    },
    "humanoid_walk": {
        "down":  { "start": 0,  "end": 5,  "fps": 10.0, "loop": true },
        "up":    { "start": 6,  "end": 11, "fps": 10.0, "loop": true },
        "left":  { "start": 12, "end": 17, "fps": 10.0, "loop": true },
        "right": { "start": 18, "end": 23, "fps": 10.0, "loop": true },
    },
}

# Spritesheet metadata (hardcoded for now)
var _sprite_meta: Dictionary = {
    "humanoid_idle": { "frame_width": 32, "frame_height": 32, "columns": 4 },
    "humanoid_walk": { "frame_width": 32, "frame_height": 32, "columns": 6 },
}


func _ready() -> void:
    print("VisualAssetManager ready")


## Get a texture by relative path from assets/
func get_texture(path: String) -> Texture2D:
    if _textures.has(path):
        return _textures[path]

    var full_path = "res://assets/" + path
    if ResourceLoader.exists(full_path):
        var tex = load(full_path)
        _textures[path] = tex
        return tex

    push_warning("VisualAssetManager: Texture not found: " + full_path)
    return _create_placeholder(32, 32, Color.MAGENTA)


## Get motion map texture
func get_motion_map(id: String) -> Texture2D:
    return get_texture("sprites/characters/player/motion/" + id + ".png")


## Get skin texture
func get_skin(id: String) -> Texture2D:
    return get_texture("sprites/characters/player/skins/" + id + ".png")


## Get animation data for a motion map
func get_animation_data(motion_map_id: String, state: String, direction: String) -> Dictionary:
    var anim_key = motion_map_id.replace("_idle", "").replace("_walk", "")
    anim_key = "humanoid_" + state  # e.g., "humanoid_idle" or "humanoid_walk"

    if _animations.has(anim_key) and _animations[anim_key].has(direction):
        return _animations[anim_key][direction]

    push_warning("VisualAssetManager: Animation not found: " + anim_key + "/" + direction)
    return { "start": 0, "end": 0, "fps": 10.0, "loop": true }


## Get sprite metadata
func get_sprite_meta(motion_map_id: String) -> Dictionary:
    var base_id = motion_map_id.split("_")
    var key = base_id[0] + "_" + base_id[1] if base_id.size() >= 2 else motion_map_id

    if _sprite_meta.has(key):
        return _sprite_meta[key]

    return { "frame_width": 32, "frame_height": 32, "columns": 4 }


## Create placeholder texture for missing assets
func _create_placeholder(width: int, height: int, color: Color) -> Texture2D:
    var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
    image.fill(color)

    # Add border
    var border = color.darkened(0.3)
    for x in range(width):
        image.set_pixel(x, 0, border)
        image.set_pixel(x, height - 1, border)
    for y in range(height):
        image.set_pixel(0, y, border)
        image.set_pixel(width - 1, y, border)

    return ImageTexture.create_from_image(image)
```

**Add to project.godot autoloads:**
```
VisualAssets="*res://autoloads/visual_asset_manager.gd"
```

---

### Step 2.2: Create UV Character Animator Component

**File**: `scripts/rendering/uv_character_animator.gd`

```gdscript
class_name UVCharacterAnimator
extends Node2D

## Handles UV lookup animation for a character
## Manages spritesheet frames and animation playback

signal animation_finished(anim_name: String)
signal frame_changed(frame: int)

# Child nodes
@onready var sprite: Sprite2D = $Sprite2D

# Shader material
var _material: ShaderMaterial

# Current state
var _current_motion_base: String = "humanoid"  # Base name without state
var _current_state: String = "idle"            # idle, walk, attack, etc.
var _current_direction: String = "down"        # down, up, left, right
var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = true

# Animation data cache
var _anim_data: Dictionary = {}
var _sprite_meta: Dictionary = {}

# Skin ID
var skin_id: String = "body_default"


func _ready() -> void:
    _setup_sprite()
    _setup_material()
    _load_motion_map("idle")
    play("idle", "down")


func _setup_sprite() -> void:
    if not sprite:
        sprite = Sprite2D.new()
        sprite.name = "Sprite2D"
        add_child(sprite)

    sprite.centered = true
    sprite.region_enabled = true


func _setup_material() -> void:
    _material = ShaderMaterial.new()
    _material.shader = load("res://shaders/uv_lookup.gdshader")
    sprite.material = _material
    _update_skin()


func _load_motion_map(state: String) -> void:
    var motion_id = _current_motion_base + "_" + state
    sprite.texture = VisualAssets.get_motion_map(motion_id)
    _sprite_meta = VisualAssets.get_sprite_meta(motion_id)


func _update_skin() -> void:
    var skin_tex = VisualAssets.get_skin(skin_id)
    _material.set_shader_parameter("skin", skin_tex)


func _process(delta: float) -> void:
    if not _is_playing or _anim_data.is_empty():
        return

    _animation_timer += delta
    var frame_duration = 1.0 / _anim_data.get("fps", 10.0)

    if _animation_timer >= frame_duration:
        _animation_timer -= frame_duration
        _advance_frame()


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
            animation_finished.emit(_current_state + "_" + _current_direction)
            return

    _update_sprite_region()
    frame_changed.emit(_current_frame)


func _update_sprite_region() -> void:
    var fw = _sprite_meta.get("frame_width", 32)
    var fh = _sprite_meta.get("frame_height", 32)
    var cols = _sprite_meta.get("columns", 4)

    var col = _current_frame % cols
    var row = _current_frame / cols

    sprite.region_rect = Rect2(col * fw, row * fh, fw, fh)


# =============================================================================
# PUBLIC API
# =============================================================================

## Play an animation state in a direction
func play(state: String, direction: String = "") -> void:
    if direction.is_empty():
        direction = _current_direction

    # Only reload motion map if state changed
    if state != _current_state:
        _current_state = state
        _load_motion_map(state)

    _current_direction = direction
    _anim_data = VisualAssets.get_animation_data(
        _current_motion_base + "_" + state, state, direction
    )

    _current_frame = _anim_data.get("start", 0)
    _animation_timer = 0.0
    _is_playing = true

    _update_sprite_region()


## Stop animation on current frame
func stop() -> void:
    _is_playing = false


## Resume animation
func resume() -> void:
    _is_playing = true


## Change direction without changing state
func set_direction(direction: String) -> void:
    if direction != _current_direction:
        play(_current_state, direction)


## Get current direction
func get_direction() -> String:
    return _current_direction


## Get current state
func get_state() -> String:
    return _current_state


## Check if animation is playing
func is_playing() -> bool:
    return _is_playing


## Set skin and update shader
func set_skin(new_skin_id: String) -> void:
    skin_id = new_skin_id
    _update_skin()


## Trigger hit flash effect
func flash(duration: float = 0.1, color: Color = Color.WHITE) -> void:
    _material.set_shader_parameter("flash_color", color)
    _material.set_shader_parameter("flash_amount", 1.0)

    var tween = create_tween()
    tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, duration)


## Apply color tint (for status effects)
func set_tint(color: Color) -> void:
    _material.set_shader_parameter("tint", color)


## Clear color tint
func clear_tint() -> void:
    _material.set_shader_parameter("tint", Color.WHITE)
```

---

### Step 2.3: Create Animator Scene

**File**: `scenes/rendering/uv_character_animator.tscn`

```
UVCharacterAnimator (Node2D, script: uv_character_animator.gd)
└── Sprite2D
    └── (texture and material set by script)
```

---

### Step 2.4: Integrate with Player Controller

**Modify**: `scripts/player/player_controller.gd`

Add the UV animator and connect movement to animation:

```gdscript
# Add these to player_controller.gd

# Reference to visual component
var _animator: UVCharacterAnimator

func _ready() -> void:
    # ... existing code ...
    _setup_visuals()


func _setup_visuals() -> void:
    # Instance the animator
    _animator = preload("res://scenes/rendering/uv_character_animator.tscn").instantiate()
    add_child(_animator)

    # If there was an old placeholder sprite, hide or remove it
    if has_node("Sprite2D"):
        $Sprite2D.visible = false


func _process(delta: float) -> void:
    # ... existing movement code ...

    # Update animation based on movement
    _update_animation()


func _update_animation() -> void:
    if not _animator:
        return

    # Determine direction from velocity or input
    var move_dir = _get_movement_direction()  # Your existing method

    if move_dir != Vector2.ZERO:
        # Walking
        var dir_name = _vector_to_direction(move_dir)
        if _animator.get_state() != "walk" or _animator.get_direction() != dir_name:
            _animator.play("walk", dir_name)
    else:
        # Idle
        if _animator.get_state() != "idle":
            _animator.play("idle", _animator.get_direction())


func _vector_to_direction(vec: Vector2) -> String:
    # Convert movement vector to direction name
    # Prioritize vertical for down/up, then horizontal
    if abs(vec.y) > abs(vec.x):
        return "down" if vec.y > 0 else "up"
    else:
        return "right" if vec.x > 0 else "left"
```

---

### Step 2.5: Create Player Animation Assets

**USER TASK: Create these animation spritesheets**

#### Asset 1: Idle Motion Map

**File**: `assets/sprites/characters/player/motion/humanoid_idle.png`
**Size**: 128×128 pixels (4 columns × 4 rows of 32×32 frames)

**Layout**:
```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: Frames 0-3 = DOWN idle
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: Frames 4-7 = UP idle
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: Frames 8-11 = LEFT idle
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: Frames 12-15 = RIGHT idle
└─────┴─────┴─────┴─────┘
```

**Idle animation (4 frames)**:
```
Frame 1: Neutral pose
Frame 2: Slight chest rise (breathing in)
Frame 3: Neutral pose
Frame 4: Slight settle (breathing out)
```

**Creating the UV data**:
Each frame is a 32×32 region with:
- R channel = X coordinate (0 at left of frame, 255 at right)
- G channel = Y coordinate (0 at top of frame, 255 at bottom)
- Alpha channel = character silhouette for that pose/direction

**Important**: The UV gradient is relative to each 32×32 frame, NOT the whole spritesheet.

**Python helper for one frame**:
```python
from PIL import Image

def create_uv_frame(size=32):
    """Create a single UV-mapped frame"""
    img = Image.new('RGBA', (size, size))
    for y in range(size):
        for x in range(size):
            r = int((x / (size - 1)) * 255)
            g = int((y / (size - 1)) * 255)
            img.putpixel((x, y), (r, g, 0, 255))
    return img

# Create and tile into spritesheet
frame = create_uv_frame(32)
sheet = Image.new('RGBA', (128, 128))
for row in range(4):
    for col in range(4):
        sheet.paste(frame, (col * 32, row * 32))
sheet.save('humanoid_idle.png')
```

Then use an image editor to cut character silhouettes into the alpha channel for each pose.

#### Asset 2: Walk Motion Map

**File**: `assets/sprites/characters/player/motion/humanoid_walk.png`
**Size**: 192×128 pixels (6 columns × 4 rows of 32×32 frames)

**Layout**:
```
┌─────┬─────┬─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │ D5  │ D6  │  Row 0: Frames 0-5 = DOWN walk
├─────┼─────┼─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │ U5  │ U6  │  Row 1: Frames 6-11 = UP walk
├─────┼─────┼─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │ L5  │ L6  │  Row 2: Frames 12-17 = LEFT walk
├─────┼─────┼─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │ R5  │ R6  │  Row 3: Frames 18-23 = RIGHT walk
└─────┴─────┴─────┴─────┴─────┴─────┘
```

**Walk cycle (6 frames)**:
```
Frame 1: Contact (right foot forward)
Frame 2: Down (weight on right foot)
Frame 3: Passing (legs passing)
Frame 4: Contact (left foot forward)
Frame 5: Down (weight on left foot)
Frame 6: Passing (legs passing)
```

#### Asset 3: Body Skin

**File**: `assets/sprites/characters/player/skins/body_default.png`
**Size**: 32×32 pixels (or 64×64 for more detail)

**What to draw**: Your character's actual appearance!

This is the "paper craft template" - a flattened view that the UV coordinates sample from.

**Simple approach for testing**: Draw a front-facing character. All directions will look similar but system works.

**Proper approach**: Divide the 32×32 into regions:
```
┌────────────────────────────────┐
│       BACK OF HEAD             │  Top: Elements seen from behind/above
│                                │
├────────────────────────────────┤
│ LEFT  │   FRONT    │  RIGHT    │  Middle: Side and front views
│ SIDE  │   FACE     │  SIDE     │
├────────────────────────────────┤
│       BODY / LEGS              │  Bottom: Torso and legs
│                                │
└────────────────────────────────┘
```

The motion map's UV values point to these regions based on what should be visible from each direction.

---

## VALIDATION CHECKLIST

After implementation, verify:

- [ ] VisualAssetManager autoload is registered
- [ ] UVCharacterAnimator scene/script works
- [ ] Player spawns with UV-rendered character
- [ ] Idle animation plays when standing still
- [ ] Walk animation plays when moving
- [ ] DOWN direction shows correct frames
- [ ] UP direction shows correct frames
- [ ] LEFT direction shows correct frames
- [ ] RIGHT direction shows correct frames
- [ ] Direction changes are smooth
- [ ] Stopping returns to idle

**Test each direction**:
```
Press DOWN  → Character faces down, walks down
Press UP    → Character faces up, walks up
Press LEFT  → Character faces left, walks left
Press RIGHT → Character faces right, walks right
Stop moving → Returns to idle facing last direction
```

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| No animation | _is_playing is false, or _anim_data is empty |
| Wrong frames | Frame indices don't match spritesheet layout |
| Jumpy animation | FPS too high, or frame count wrong |
| Same pose all directions | Motion map not varying by direction |
| Skin not showing | Skin texture not loaded or shader param not set |

---

## FILES CREATED THIS PHASE

```
autoloads/
└── visual_asset_manager.gd

scripts/
└── rendering/
    └── uv_character_animator.gd

scenes/
└── rendering/
    └── uv_character_animator.tscn

assets/
└── sprites/
    └── characters/
        └── player/
            ├── motion/
            │   ├── humanoid_idle.png    ← USER CREATES
            │   └── humanoid_walk.png    ← USER CREATES
            └── skins/
                └── body_default.png     ← USER CREATES
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_3_EQUIPMENT_VISUALS.md` which adds:
- Multi-layer shader (body + armor + helmet + boots)
- Equipment skin textures
- Connection to inventory/equipment system
- Visual equipment changes

---

## NOTES FOR IMPLEMENTER

- The animator is designed to be a child node, not replace the character
- Old placeholder sprites should be hidden, not deleted (useful for debugging)
- Keep the test scene from Phase 1 for shader debugging
- If user struggles with spritesheets, they can start with single-frame placeholders
- Left/Right animations can be mirrored versions of each other to reduce art workload
