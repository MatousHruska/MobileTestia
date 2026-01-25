# PHASE 1: BASIC UV LOOKUP SHADER

> **Goal**: Get the UV lookup shader working. See a colored shape render that isn't a placeholder rectangle.
> **Prerequisites**: None - this is the starting point
> **Estimated Scope**: Small - shader + test scene + 2 test textures

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Overall visual style and principles
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Technical architecture and shader code
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Full roadmap and asset specs

**Key technical decisions:**
- UV Lookup system separates motion (animation) from appearance (skin)
- Motion map pixels use R,G channels as UV coordinates into skin texture
- This enables equipment changes without redrawing animations

---

## IMPLEMENTATION STEPS

### Step 1.1: Create Folder Structure

Create the asset directory structure:

```
assets/
├── sprites/
│   └── characters/
│       └── player/
│           ├── motion/
│           └── skins/
├── test/
└── shaders/
```

**Command to run:**
```bash
mkdir -p assets/sprites/characters/player/motion
mkdir -p assets/sprites/characters/player/skins
mkdir -p assets/test
mkdir -p shaders
```

---

### Step 1.2: Create Basic UV Lookup Shader

**File**: `shaders/uv_lookup.gdshader`

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Skin texture - the actual appearance
uniform sampler2D skin : hint_default_white, filter_nearest;

// Visual modifiers (for later use)
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Sample the motion map (the sprite's TEXTURE)
    // This contains UV coordinates encoded in R,G channels
    vec4 motion_data = texture(TEXTURE, UV);

    // If alpha is 0, this pixel is transparent in the motion map
    if (motion_data.a < 0.01) {
        discard;
    }

    // R and G channels encode UV coordinates into skin texture
    // Motion map values 0-255 map to 0.0-1.0
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    // Sample the skin texture at the encoded coordinates
    vec4 skin_color = texture(skin, skin_uv);

    // Apply tint (for status effects like poison)
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output: skin color with motion map's alpha controlling shape
    COLOR = vec4(final_color.rgb, motion_data.a * skin_color.a);
}
```

---

### Step 1.3: Create Test Scene

**File**: `scenes/test/test_uv_shader.tscn`

Create a simple scene to test the shader:

```
Node2D (root)
├── Camera2D
│   └── current: true
├── ColorRect (background)
│   └── color: dark gray
└── Sprite2D (test_sprite)
    ├── texture: [will be motion map]
    ├── material: ShaderMaterial
    │   ├── shader: uv_lookup.gdshader
    │   └── shader_parameter/skin: [will be skin texture]
    └── position: center of screen
```

**GDScript for testing** (attach to root):

```gdscript
# scenes/test/test_uv_shader.gd
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
    # Load test textures
    var motion_map = load("res://assets/test/test_motion_map.png")
    var skin = load("res://assets/test/test_skin.png")

    # Apply to sprite
    sprite.texture = motion_map

    # Apply skin to shader
    var material = sprite.material as ShaderMaterial
    material.set_shader_parameter("skin", skin)

    print("UV Shader test loaded!")
    print("Motion map size: ", motion_map.get_size())
    print("Skin size: ", skin.get_size())

func _input(event: InputEvent) -> void:
    # Test flash on spacebar
    if event.is_action_pressed("ui_accept"):
        _test_flash()

    # Test tint on T key
    if event is InputEventKey and event.pressed and event.keycode == KEY_T:
        _test_tint()

func _test_flash() -> void:
    var material = sprite.material as ShaderMaterial
    material.set_shader_parameter("flash_amount", 1.0)

    var tween = create_tween()
    tween.tween_property(material, "shader_parameter/flash_amount", 0.0, 0.15)
    print("Flash triggered!")

func _test_tint() -> void:
    var material = sprite.material as ShaderMaterial
    var current_tint = material.get_shader_parameter("tint")

    if current_tint == Color.WHITE:
        material.set_shader_parameter("tint", Color(0.5, 1.0, 0.5))  # Green tint
        print("Tint: Green (poisoned)")
    else:
        material.set_shader_parameter("tint", Color.WHITE)
        print("Tint: Normal")
```

---

### Step 1.4: Create Test Assets

**USER TASK: Create these two test images**

#### Asset 1: Test Motion Map

**File**: `assets/test/test_motion_map.png`
**Size**: 32×32 pixels
**Format**: PNG with alpha channel

**What this is**: NOT a character drawing. It's a UV coordinate map where:
- Red channel (R) = X coordinate in skin texture
- Green channel (G) = Y coordinate in skin texture
- Alpha channel = shape of the sprite

**How to create (gradient method)**:
```
For each pixel at position (x, y):
    R = (x / 31) * 255    // 0 at left, 255 at right
    G = (y / 31) * 255    // 0 at top, 255 at bottom
    B = 0                  // Not used
    A = 255                // Fully opaque (or cut out a shape)
```

**Python script to generate**:
```python
from PIL import Image

size = 32
img = Image.new('RGBA', (size, size))

for y in range(size):
    for x in range(size):
        r = int((x / (size - 1)) * 255)
        g = int((y / (size - 1)) * 255)
        # Create a simple character silhouette
        # Head (top center)
        # Body (middle)
        # Legs (bottom)

        # For now, just make it a full square
        img.putpixel((x, y), (r, g, 0, 255))

# Optional: cut out a character shape by setting alpha=0 outside
# For first test, leave as full square to verify mapping works

img.save('test_motion_map.png')
print("Created test_motion_map.png")
```

**Alternative - manual in image editor**:
1. Create 32×32 image
2. Use gradient tool: Red gradient left→right
3. Use gradient tool: Green gradient top→bottom
4. Blend mode: Add or multiply to combine
5. Result should be: black top-left, red top-right, green bottom-left, yellow bottom-right

#### Asset 2: Test Skin

**File**: `assets/test/test_skin.png`
**Size**: 32×32 pixels
**Format**: PNG

**What this is**: The actual character appearance. Draw anything!

**Simple test approach**:
```
┌────────────────────────────────┐
│                                │
│         ████████               │  ← Hair (brown/black)
│        ██████████              │
│       ████░░░░████             │  ← Face (skin tone)
│       ███░●░░●░███             │  ← Eyes (black dots)
│       ████░░░░████             │
│        ██░▼▼▼░██               │  ← Mouth area
│       ████████████             │  ← Shirt (any color)
│      ██████████████            │
│       ████████████             │
│        ██░░░░░░██              │  ← Pants (different color)
│        ██░░░░░░██              │
│        ██      ██              │  ← Feet
│                                │
└────────────────────────────────┘
```

**Even simpler test**: Just draw colored regions to verify mapping:
- Top-left quadrant: Red
- Top-right quadrant: Green
- Bottom-left quadrant: Blue
- Bottom-right quadrant: Yellow

This will confirm the UV mapping is working correctly.

---

### Step 1.5: Configure Texture Import Settings

**IMPORTANT**: In Godot, select each test texture and set:

1. Select `test_motion_map.png` in FileSystem
2. Go to Import tab
3. Set **Filter**: `Nearest` (not Linear!)
4. Click "Reimport"

Repeat for `test_skin.png`.

Linear filtering will blur the UV coordinates and break the system.

---

## VALIDATION CHECKLIST

After implementation, verify:

- [ ] Shader file exists at `shaders/uv_lookup.gdshader`
- [ ] Test scene runs without errors
- [ ] Sprite renders (not invisible)
- [ ] Sprite shows the skin texture colors
- [ ] Colors are NOT blurry (nearest filtering works)
- [ ] Pressing Space triggers white flash
- [ ] Pressing T toggles green tint
- [ ] Flash fades back to normal

**What you should see**:
- If motion map is a full square gradient and skin is a character drawing, you'll see the entire skin texture displayed
- If you cut a character shape in the motion map's alpha, the skin will be masked to that shape

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| Black sprite | Skin texture not assigned to shader |
| Blurry/smeared | Texture filter is Linear, not Nearest |
| Nothing renders | Motion map has 0 alpha, or shader error |
| Wrong colors | R/G channels swapped in motion map |

---

## FILES CREATED THIS PHASE

```
shaders/
└── uv_lookup.gdshader

assets/
├── test/
│   ├── test_motion_map.png    ← USER CREATES
│   └── test_skin.png          ← USER CREATES

scenes/
└── test/
    ├── test_uv_shader.tscn
    └── test_uv_shader.gd
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_2_PLAYER_MOVEMENT.md` which adds:
- Animation controller
- 4-directional idle animation
- 4-directional walk animation
- Integration with player controller

---

## NOTES FOR IMPLEMENTER

- Keep the test scene even after moving forward - useful for debugging
- The shader will be expanded in Phase 3 to support multiple skin layers
- Don't worry about normal maps or lighting yet - that's Phase 7
- If user struggles with motion map creation, provide the Python script or create a procedural generator in GDScript
