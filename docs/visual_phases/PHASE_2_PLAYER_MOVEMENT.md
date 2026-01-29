# PHASE 2: PLAYER MOVEMENT ANIMATION

> **Goal**: Animated player character with 4-directional movement (idle + walk)
> **Prerequisites**: Phase 1 complete (UV color-lookup shader working)
> **Estimated Scope**: Medium - animator component + animation sheets + integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Animation philosophy ("pixel impressionism")
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Color-lookup shader architecture
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Asset specifications
- `docs/visual_phases/PHASE_1_BASIC_SHADER.md` - What was built in Phase 1

**Key decisions from Art Direction:**
- 4 directions: down, up, left, right
- Idle: 4 frames at 6-8 FPS
- Walk: 6 frames at 10-12 FPS
- "Pixel impressionism" - keyframes at apex, let brain interpolate
- **Color-Lookup System**: Animation pixels match UV Map colors, shader finds position

---

## COLOR-LOOKUP ANIMATION WORKFLOW

Unlike the old R/G UV encoding, our color-lookup system works like this:

```
ANIMATION SHEET CREATION:
1. Create UV Map (32x32) with unique colors per pixel
2. Create Lookup Texture (32x32) with character appearance
3. Create Animation Sheet where each pixel color MATCHES the UV Map

RUNTIME:
1. Sprite shows current animation frame
2. Shader reads pixel color from animation frame
3. Shader searches UV Map for matching color
4. Found position → sample Lookup Texture at that UV
5. Output: skin appearance in animation silhouette
```

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

# Character configuration
var _character_configs: Dictionary = {
    "test": {
        "motion_path": "sprites/characters/player/Tests/TestIdle-Sheet.png",
        "uv_map_path": "sprites/characters/player/Tests/TestUVMap.png",
        "skin_path": "sprites/characters/player/Tests/TestLookupTexture2.png",
    },
    "player": {
        "motion_path": "sprites/characters/player/motion/humanoid_idle.png",
        "uv_map_path": "sprites/characters/player/uv_map.png",
        "skin_path": "sprites/characters/player/skins/body_default.png",
    },
}

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


## Get character configuration
func get_character_config(config_id: String) -> Dictionary:
    return _character_configs.get(config_id, _character_configs.get("test", {}))


## Get animation sheet (motion map in old terms)
func get_motion_map(id: String) -> Texture2D:
    return get_texture("sprites/characters/player/motion/" + id + ".png")


## Get UV Map texture for color-lookup
func get_uv_map(config_id: String) -> Texture2D:
    var config = get_character_config(config_id)
    return get_texture(config.get("uv_map_path", ""))


## Get skin/lookup texture
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
    # Simple magenta checkerboard
    for y in range(height):
        for x in range(width):
            if (x + y) % 2 == 0:
                image.set_pixel(x, y, color)
            else:
                image.set_pixel(x, y, color.darkened(0.3))
    return ImageTexture.create_from_image(image)
```

**Add to project.godot autoloads:**
```
VisualAssets="*res://autoloads/visual_asset_manager.gd"
```

---

### Step 2.2: Create UV Character Animator Component

**File**: `scripts/rendering/uv_character_animator.gd`

This component uses the color-lookup shader from Phase 1:

```gdscript
class_name UVCharacterAnimator
extends Node2D

## Handles UV color-lookup animation for a character
## Uses the color-lookup shader to render character appearance

signal animation_finished(anim_name: String)
signal frame_changed(frame: int)

# Child nodes
@onready var sprite: Sprite2D = $Sprite2D

# Shader material
var _material: ShaderMaterial

# Current state
var _current_motion_base: String = "test"  # Config ID for character
var _current_state: String = "idle"
var _current_direction: String = "down"
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
    # Use the color-lookup shader
    _material = ShaderMaterial.new()
    _material.shader = load("res://shaders/uv_color_lookup.gdshader")
    sprite.material = _material
    _update_textures()


func _load_motion_map(state: String) -> void:
    var motion_id = _current_motion_base + "_" + state
    sprite.texture = VisualAssets.get_motion_map(motion_id)
    _sprite_meta = VisualAssets.get_sprite_meta(motion_id)


func _update_textures() -> void:
    # Load UV map and skin for color-lookup shader
    var config = VisualAssets.get_character_config(_current_motion_base)

    var uv_map = VisualAssets.get_texture(config.get("uv_map_path", ""))
    var skin = VisualAssets.get_texture(config.get("skin_path", ""))

    _material.set_shader_parameter("uv_map", uv_map)
    _material.set_shader_parameter("skin", skin)


# ... rest of animation logic same as before ...
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

Add the UV animator and connect movement to animation (same as before).

---

### Step 2.5: Create Player Animation Assets

**USER TASK: Create these animation spritesheets using color-lookup method**

#### Asset 1: UV Map (32×32)
**File**: `assets/sprites/characters/player/uv_map.png`
**Size**: 32×32 pixels

Create a UV map with unique colors per pixel. You can copy the test UV map as a starting point:
```
Copy from: assets/sprites/characters/player/Tests/TestUVMap.png
```

#### Asset 2: Body Skin (Lookup Texture)
**File**: `assets/sprites/characters/player/skins/body_default.png`
**Size**: 32×32 pixels

Draw your character's appearance. This is pixel-perfect aligned with the UV map.

#### Asset 3: Idle Animation Sheet
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

**Creating animation frames with color-lookup:**
1. For each frame, draw the character silhouette (alpha channel)
2. For each visible pixel, sample the color from the UV Map at the body position you want
3. The shader will find that color in the UV Map and use that position to sample the skin

**Example workflow:**
```
1. Open UV Map in one window
2. Open animation frame in another window
3. For the head area of the animation:
   - Pick the color from the HEAD region of the UV Map
   - Paint that color in the head area of the animation frame
4. For the body area:
   - Pick the color from the BODY region of the UV Map
   - Paint that color in the body area of the animation frame
5. Repeat for all body parts and all frames
```

#### Asset 4: Walk Animation Sheet
**File**: `assets/sprites/characters/player/motion/humanoid_walk.png`
**Size**: 192×128 pixels (6 columns × 4 rows of 32×32 frames)

Same process as idle, but with 6 frames per direction for walk cycle.

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
- [ ] Skin swap works (if implemented)

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
| Wrong colors | Animation colors don't match UV Map colors |
| Black character | UV Map or Skin not loaded |
| Jumpy animation | FPS too high, or frame count wrong |

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
            ├── uv_map.png               ← USER CREATES
            ├── motion/
            │   ├── humanoid_idle.png    ← USER CREATES
            │   └── humanoid_walk.png    ← USER CREATES
            └── skins/
                └── body_default.png     ← USER CREATES
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_3_EQUIPMENT_VISUALS.md` which adds:
- Sector-based equipment shader
- Equipment slot textures (head, body, hands, feet)
- Equipment test scene
- Visual equipment changes

---

## NOTES FOR IMPLEMENTER

- The animator is designed to be a child node, not replace the character
- Keep the test scenes from Phase 1 for shader debugging
- Use the test assets as reference for creating production assets
- The color-lookup approach allows skin swapping without redrawing animations
- Press R in test scenes to hot-reload textures during development

---

*Document Version: 2.0 - Updated for Color-Lookup System*
*Last Updated: Session claude/phase-1-TestingShaders-spp2s*
