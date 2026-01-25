# VISUAL SYSTEM IMPLEMENTATION ROADMAP

> **Philosophy**: Build incrementally. See progress at every step. Minimal assets to test each system.
> **Test Zone**: "The Clearing" - small area to validate everything

---

## OVERVIEW: THE JOURNEY

```
PHASE 1: See Something Render          ████░░░░░░░░░░░░░░░░  Week 1
PHASE 2: Player Moves                  ████████░░░░░░░░░░░░  Week 2
PHASE 3: Equipment Shows               ████████████░░░░░░░░  Week 3
PHASE 4: Player Attacks                ████████████████░░░░  Week 4
PHASE 5: Enemies Exist                 ██████████████████░░  Week 5
PHASE 6: World Objects                 ████████████████████  Week 6
PHASE 7: Lighting & Atmosphere         ████████████████████  Week 7+
PHASE 8: Polish & Effects              ████████████████████  Week 8+
```

---

## PHASE 1: SEE SOMETHING RENDER
> **Goal**: UV lookup shader works. See a colored shape that isn't a placeholder rectangle.

### Step 1.1: Create Basic Shader
**Code to write:**
- `shaders/uv_lookup.gdshader` (simplified version, single skin)

**What to implement:**
```
shaders/
└── uv_lookup.gdshader    ← Basic version, just body skin
```

**Shader (simplified starter):**
```glsl
shader_type canvas_item;

uniform sampler2D skin : hint_default_white, filter_nearest;

void fragment() {
    vec4 motion_data = texture(TEXTURE, UV);
    if (motion_data.a < 0.01) { discard; }

    vec2 skin_uv = vec2(motion_data.r, motion_data.g);
    vec4 skin_color = texture(skin, skin_uv);

    COLOR = vec4(skin_color.rgb, motion_data.a * skin_color.a);
}
```

---

### Step 1.2: Create Test Scene
**Code to write:**
- Simple test scene with Sprite2D using the shader

**Scene structure:**
```
test_uv_shader.tscn
├── Node2D (root)
│   └── Sprite2D
│       ├── texture: [motion map]
│       └── material: ShaderMaterial (uv_lookup.gdshader)
│           └── skin: [skin texture]
```

---

### Step 1.3: Create First Test Assets
**YOUR FIRST ART TASK:**

You need TWO tiny images to test the system:

#### Asset 1: Test Motion Map (32x32 PNG)
**File**: `assets/test/test_motion_map.png`
**Size**: 32x32 pixels
**What to draw**:

This is NOT a character drawing. It's a UV coordinate map.
Each pixel's RED value = X position in skin (0-255 → 0.0-1.0)
Each pixel's GREEN value = Y position in skin (0-255 → 0.0-1.0)

**Easiest approach - gradient fill:**
```
For a 32x32 image:
- Pixel at (0,0): Color RGB(0, 0, 0)
- Pixel at (31,0): Color RGB(255, 0, 0)
- Pixel at (0,31): Color RGB(0, 255, 0)
- Pixel at (31,31): Color RGB(255, 255, 0)

It's a gradient from black→red horizontally, black→green vertically.
```

**Or use this Python script:**
```python
from PIL import Image

size = 32
img = Image.new('RGBA', (size, size))

for y in range(size):
    for x in range(size):
        r = int((x / (size-1)) * 255)
        g = int((y / (size-1)) * 255)
        img.putpixel((x, y), (r, g, 0, 255))

# Cut out a simple shape (circle/diamond) by setting alpha=0 outside
# For now, leave as full square

img.save('test_motion_map.png')
```

#### Asset 2: Test Skin (32x32 PNG)
**File**: `assets/test/test_skin.png`
**Size**: 32x32 pixels
**What to draw**:

This IS a character drawing - your actual art!
Draw a simple character facing down (idle pose).
The motion map will sample colors from this based on UV coordinates.

**Simple test approach:**
- Draw a stick figure
- Or a colored circle with face
- Or just colored regions to verify mapping works

```
┌────────────────────────────────┐
│         ████████               │  ← Hair (dark)
│        ██████████              │
│       ████░░░░████             │  ← Face (skin tone)
│       ███░●░░●░███             │  ← Eyes
│       ████░░░░████             │
│        ████████                │
│       ████████████             │  ← Body (shirt color)
│      ██████████████            │
│       ████████████             │
│        ██░░░░░░██              │  ← Legs (pants color)
│        ██░░░░░░██              │
│        ██      ██              │  ← Feet
└────────────────────────────────┘
```

---

### Step 1.3 Validation
**What you should see:**
- The skin texture appears on screen
- It's displayed in the shape of the motion map's alpha channel
- If motion map is a square, you see the whole skin
- Colors match what you drew in the skin

**If it doesn't work:**
- Check shader is applied to material
- Check both textures are assigned
- Check textures are set to "Nearest" filtering (not linear)

---

## PHASE 2: PLAYER MOVES
> **Goal**: Animated character with 4-directional movement

### Step 2.1: Create VisualAssetManager (Minimal)
**Code to write:**
- `autoloads/visual_asset_manager.gd` (start simple, expand later)

**Minimal version:**
```gdscript
extends Node

var _textures: Dictionary = {}

func get_texture(path: String) -> Texture2D:
    if _textures.has(path):
        return _textures[path]

    var full_path = "res://assets/" + path
    if ResourceLoader.exists(full_path):
        _textures[path] = load(full_path)
        return _textures[path]

    push_warning("Texture not found: " + path)
    return null

func get_motion_map(id: String) -> Texture2D:
    return get_texture("sprites/characters/player/motion/" + id + ".png")

func get_skin(id: String) -> Texture2D:
    return get_texture("sprites/characters/player/skins/" + id + ".png")
```

Add to `project.godot` autoloads.

---

### Step 2.2: Create Animation Controller
**Code to write:**
- `scripts/rendering/simple_uv_animator.gd`

**What it does:**
- Manages spritesheet frame switching
- Handles 4 directions
- Plays idle/walk animations

---

### Step 2.3: Create Idle Animation Assets (4 directions)
**YOUR SECOND ART TASK:**

#### Motion Map Spritesheet
**File**: `assets/sprites/characters/player/motion/humanoid_idle.png`
**Size**: 128x128 pixels (4 columns × 4 rows = 16 frames)
**Layout**:
```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: DOWN (frames 0-3)
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: UP (frames 4-7)
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: LEFT (frames 8-11)
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: RIGHT (frames 12-15)
└─────┴─────┴─────┴─────┘

Each cell is 32x32 pixels
```

**What each frame contains:**
- UV gradient data (R=X, G=Y) like before
- But now shaped like a character in that pose/direction
- Alpha channel cuts out the character silhouette

**THE TRICK**: All 16 frames can use the SAME UV mapping initially!
- Draw the UV gradient once
- Cut it into character shapes for each direction
- The shape changes, but the UV mapping stays consistent
- This means the skin texture works for all directions

#### Skin Texture
**File**: `assets/sprites/characters/player/skins/body_default.png`
**Size**: 32x32 pixels (or 64x64 for more detail)
**What to draw**:

A "flattened" view of your character that covers all angles:
```
┌────────────────────────────────┐
│     BACK OF HEAD               │  Top area: back/top view elements
│     ████████                   │
├────────────────────────────────┤
│  LEFT │ FRONT  │ RIGHT         │  Middle: side and front views
│  SIDE │ FACING │ SIDE          │
│   ██  │ ██░░██ │  ██           │
├────────────────────────────────┤
│     BODY / LEGS                │  Bottom: body details
│     ████████                   │
└────────────────────────────────┘
```

**Simpler approach for testing:**
Just draw a single front-facing character. All directions will look the same but system will work.

---

### Step 2.4: Create Walk Animation Assets
**YOUR THIRD ART TASK:**

#### Motion Map Spritesheet
**File**: `assets/sprites/characters/player/motion/humanoid_walk.png`
**Size**: 192x128 pixels (6 columns × 4 rows = 24 frames)
**Layout**:
```
┌─────┬─────┬─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │ D5  │ D6  │  Row 0: DOWN (6 frames)
├─────┼─────┼─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │ U5  │ U6  │  Row 1: UP
├─────┼─────┼─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │ L5  │ L6  │  Row 2: LEFT
├─────┼─────┼─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │ R5  │ R6  │  Row 3: RIGHT
└─────┴─────┴─────┴─────┴─────┴─────┘
```

**Walk cycle breakdown (6 frames):**
```
Frame 1: Contact (right foot forward)
Frame 2: Down (weight shifts)
Frame 3: Pass (feet pass each other)
Frame 4: Contact (left foot forward)
Frame 5: Down (weight shifts)
Frame 6: Pass (feet pass each other)
```

---

### Step 2.5: Integrate with Player Controller
**Code to modify:**
- `scripts/player/player_controller.gd`
- Add reference to UV animator
- Connect movement to animation states

---

### Step 2.5 Validation
**What you should see:**
- Player character renders with UV shader
- Pressing movement keys changes direction
- Character animates while moving
- Character plays idle when stationary

**Test checklist:**
- [ ] Down direction works
- [ ] Up direction works
- [ ] Left direction works
- [ ] Right direction works
- [ ] Idle plays when stopped
- [ ] Walk plays when moving
- [ ] Transitions are smooth

---

## PHASE 3: EQUIPMENT SHOWS
> **Goal**: Changing armor/helmet/boots updates character appearance

### Step 3.1: Upgrade Shader to Multi-Layer
**Code to modify:**
- `shaders/uv_lookup.gdshader` - add armor, helmet, boots layers

```glsl
uniform sampler2D skin_body : hint_default_white, filter_nearest;
uniform sampler2D skin_armor : hint_default_white, filter_nearest;
uniform sampler2D skin_helmet : hint_default_white, filter_nearest;
uniform sampler2D skin_boots : hint_default_white, filter_nearest;
```

---

### Step 3.2: Create Equipment Skin Assets
**YOUR FOURTH ART TASK:**

#### Armor Skin
**File**: `assets/sprites/characters/player/skins/armor/armor_leather.png`
**Size**: Same as body skin (32x32 or 64x64)
**What to draw**:
- Only the armor parts (chest, shoulders, arms)
- Transparent everywhere else
- This overlays on top of body

```
┌────────────────────────────────┐
│          (transparent)         │
│        ████████████            │  ← Shoulder/collar area
│       ██████████████           │  ← Chest armor
│       ██████████████           │
│        ████████████            │
│          ████████              │  ← Belt area
│          (transparent)         │
└────────────────────────────────┘
```

#### Helmet Skin
**File**: `assets/sprites/characters/player/skins/helmet/helmet_leather.png`
**Size**: Same as body skin
**What to draw**:
- Only the helmet area
- Transparent everywhere else

#### Boots Skin
**File**: `assets/sprites/characters/player/skins/boots/boots_leather.png`
**Size**: Same as body skin
**What to draw**:
- Only the feet/boot area
- Transparent everywhere else

#### "None" Skins (Required!)
**Files**:
- `armor_none.png` - fully transparent 32x32
- `helmet_none.png` - fully transparent 32x32
- `boots_none.png` - fully transparent 32x32

These are used when no equipment is worn.

---

### Step 3.3: Create Equipment Renderer Component
**Code to write:**
- `scripts/rendering/equipment_renderer.gd`

**What it does:**
- Holds references to current equipment skins
- Updates shader parameters when equipment changes
- Connects to inventory/equipment events

---

### Step 3.4: Connect to Inventory System
**Code to modify:**
- Connect equipment changes to renderer updates

```gdscript
# When equipment changes:
func _on_equipment_changed(slot: String, item_id: String) -> void:
    match slot:
        "armor":
            var skin = VisualAssetManager.get_skin("armor/" + item_id)
            _material.set_shader_parameter("skin_armor", skin)
        "helmet":
            # etc...
```

---

### Step 3.4 Validation
**What you should see:**
- Character renders with base body
- Equipping leather armor shows armor overlay
- Equipping helmet shows helmet
- Unequipping returns to base appearance
- Multiple equipment pieces combine correctly

**Test checklist:**
- [ ] Body renders alone (no equipment)
- [ ] Armor overlays correctly
- [ ] Helmet overlays correctly
- [ ] Boots overlay correctly
- [ ] All three combined look right
- [ ] Unequipping removes overlay

---

## PHASE 4: PLAYER ATTACKS
> **Goal**: Attack animation with weapon sprite and anchoring

### Step 4.1: Create Attack Animation Assets
**YOUR FIFTH ART TASK:**

#### Attack Motion Map (1-handed)
**File**: `assets/sprites/characters/player/motion/humanoid_attack_1h.png`
**Size**: 128x128 pixels (4 columns × 4 rows = 16 frames, 4 per direction)
**Layout**:
```
┌─────┬─────┬─────┬─────┐
│ D1  │ D2  │ D3  │ D4  │  Row 0: DOWN attack (4 frames)
├─────┼─────┼─────┼─────┤
│ U1  │ U2  │ U3  │ U4  │  Row 1: UP attack
├─────┼─────┼─────┼─────┤
│ L1  │ L2  │ L3  │ L4  │  Row 2: LEFT attack
├─────┼─────┼─────┼─────┤
│ R1  │ R2  │ R3  │ R4  │  Row 3: RIGHT attack
└─────┴─────┴─────┴─────┘
```

**Attack animation breakdown (4 frames):**
```
Frame 1: Wind-up (anticipation)
Frame 2: Swing (apex - weapon fully extended)
Frame 3: Follow-through
Frame 4: Recovery (returning to idle)
```

---

### Step 4.2: Create Weapon Sprite
**YOUR SIXTH ART TASK:**

#### Weapon Sprite
**File**: `assets/sprites/weapons/1h/sword_iron.png`
**Size**: 32x16 pixels (or 32x32)
**What to draw**:
- Sword pointing RIGHT (we'll rotate it)
- Handle on left, blade on right
- This sprite will be positioned/rotated by anchor data

```
┌────────────────────────────────┐
│ ▓▓░░░░░░░░░░░░░░░░░░░░░░░░▶  │
│ ▓▓▓▓░░░░░░░░░░░░░░░░░░░░░▶   │  Handle → Blade → Tip
│ ▓▓░░░░░░░░░░░░░░░░░░░░░░░░▶  │
└────────────────────────────────┘
```

---

### Step 4.3: Create Weapon Anchor Data
**Data to define** (will go in database):

```
# Attack Down - 4 frames
Frame 0: position(8, -8), rotation(-45°), visible(true)   # Wind-up (sword behind)
Frame 1: position(12, 4), rotation(0°), visible(true)     # Swing (sword forward)
Frame 2: position(8, 12), rotation(45°), visible(true)    # Follow-through (sword down)
Frame 3: position(4, 8), rotation(30°), visible(true)     # Recovery

# Attack Up - 4 frames
Frame 0: position(-8, 8), rotation(135°), visible(true)
Frame 1: position(0, -12), rotation(180°), visible(true)
Frame 2: position(8, -8), rotation(-135°), visible(true)
Frame 3: position(4, -4), rotation(-150°), visible(true)

# Attack Left - 4 frames
Frame 0: position(8, -4), rotation(-90°), visible(true)
Frame 1: position(-12, 0), rotation(180°), visible(true)
Frame 2: position(-8, 8), rotation(135°), visible(true)
Frame 3: position(-4, 4), rotation(120°), visible(true)

# Attack Right - 4 frames
Frame 0: position(-8, -4), rotation(90°), visible(true)
Frame 1: position(12, 0), rotation(0°), visible(true)
Frame 2: position(8, 8), rotation(-45°), visible(true)
Frame 3: position(4, 4), rotation(-60°), visible(true)
```

---

### Step 4.4: Implement Weapon Anchor System
**Code to write:**
- Add weapon sprite child to character renderer
- Update weapon position/rotation each frame based on anchor data

---

### Step 4.5: Connect to Combat System
**Code to modify:**
- Trigger attack animation on basic attack
- Sync hitbox timing with animation

---

### Step 4.5 Validation
**What you should see:**
- Attack input triggers attack animation
- Weapon sprite appears during attack
- Weapon follows anchor positions through swing
- Animation returns to idle after attack

**Test checklist:**
- [ ] Attack down shows weapon swinging down
- [ ] Attack up shows weapon swinging up
- [ ] Attack left shows weapon swinging left
- [ ] Attack right shows weapon swinging right
- [ ] Weapon hidden during idle/walk
- [ ] Attack animation has impact feel

---

## PHASE 5: ENEMIES EXIST
> **Goal**: Enemy with UV lookup system and skin variants

### Step 5.1: Create Enemy Shader
**Code to write:**
- `shaders/uv_lookup_enemy.gdshader` (single skin version)

Same as basic shader but named differently for clarity.

---

### Step 5.2: Create Enemy Motion Maps
**YOUR SEVENTH ART TASK:**

Choose a simple enemy: **Slime** (easiest) or **Wolf**

#### Slime Motion Maps
**Why slime is easiest:**
- No limbs to animate
- Simple blob shape
- Squash and stretch for movement
- One "attack" motion (lunge)

**File**: `assets/sprites/characters/enemies/slime/motion/slime_idle.png`
**Size**: 96x96 (4 columns × 4 rows, 24x24 per frame)
**Layout**: Same as player (4 directions × 4 frames)

**Slime idle animation:**
```
Frame 1: Normal blob shape
Frame 2: Slightly taller (stretch up)
Frame 3: Normal blob shape
Frame 4: Slightly wider (squash down)
```

**File**: `assets/sprites/characters/enemies/slime/motion/slime_walk.png`
(Slimes don't walk, they hop - same as idle but bouncier)

**File**: `assets/sprites/characters/enemies/slime/motion/slime_attack.png`
**Attack animation:**
```
Frame 1: Squash (wind-up)
Frame 2: Stretch forward (lunge)
Frame 3: Impact/extended
Frame 4: Return to blob
```

---

### Step 5.3: Create Enemy Skin Variants
**YOUR EIGHTH ART TASK:**

#### Three Slime Skins
**Files**:
- `assets/sprites/characters/enemies/slime/skins/slime_green.png`
- `assets/sprites/characters/enemies/slime/skins/slime_red.png`
- `assets/sprites/characters/enemies/slime/skins/slime_blue.png`

**Size**: 24x24 (matches motion map frame size)
**What to draw**:
- Each is the same slime shape
- Different colors: green (basic), red (fire), blue (ice)
- Maybe different eye expressions

```
GREEN SLIME:          RED SLIME:           BLUE SLIME:
┌──────────────┐      ┌──────────────┐     ┌──────────────┐
│    ████      │      │    ████      │     │    ████      │
│  ████████    │      │  ████████    │     │  ████████    │
│ ██ ●  ● ██   │      │ ██ ●  ● ██   │     │ ██ ●  ● ██   │
│  ████████    │      │  ████████    │     │  ████████    │
│    ████      │      │    ████      │     │    ████      │
└──────────────┘      └──────────────┘     └──────────────┘
 (green tones)         (red/orange)         (blue/cyan)
```

---

### Step 5.4: Integrate with Enemy System
**Code to modify:**
- `scripts/npc/enemy_npc.gd` - use UV renderer
- Read skin_id from enemy database
- Same motion map, different skin = different variant

---

### Step 5.4 Validation
**What you should see:**
- Enemy spawns with UV shader rendering
- Green slime uses green skin
- Red slime uses red skin (same animation)
- Blue slime uses blue skin
- Enemies animate (idle, move toward player, attack)

**Test checklist:**
- [ ] Slime renders with UV shader
- [ ] Green variant works
- [ ] Red variant works
- [ ] Blue variant works
- [ ] Idle animation plays
- [ ] Movement animation plays
- [ ] Attack animation plays
- [ ] Death animation plays

---

## PHASE 6: WORLD OBJECTS
> **Goal**: Chest, loot drops, basic tileset

### Step 6.1: Create Chest Sprites
**YOUR NINTH ART TASK:**

#### Chest (Static Sprite, not UV lookup)
**Files**:
- `assets/sprites/objects/lootables/chest_wooden.png` (closed)
- `assets/sprites/objects/lootables/chest_wooden_open.png` (open)

**Size**: 16x16 pixels
**What to draw**:
```
CLOSED:                OPEN:
┌────────────────┐     ┌────────────────┐
│ ██████████████ │     │   ████████     │ ← Lid (opened back)
│ █ ────────── █ │     │  ██████████    │
│ █            █ │     │ █          █   │
│ █     ◆      █ │     │ █  ★ ★ ★   █   │ ← Loot visible!
│ ██████████████ │     │ ██████████████ │
└────────────────┘     └────────────────┘
```

---

### Step 6.2: Create Loot Drop Sprites
**YOUR TENTH ART TASK:**

#### Item on Ground
**File**: `assets/sprites/objects/loot_drop.png`
**Size**: 16x16 (or use item icon scaled down)

Or reuse item icons from inventory system.

---

### Step 6.3: Create Basic Tileset
**YOUR ELEVENTH ART TASK:**

#### Terrain Tiles (for test zone)
**File**: `assets/tilesets/terrain/test_terrain.png`
**Size**: 64x64 (4×4 grid of 16×16 tiles)

**Tile layout:**
```
┌─────┬─────┬─────┬─────┐
│Grass│Grass│Stone│Stone│  Row 0: Basic terrain
│  1  │  2  │  1  │  2  │
├─────┼─────┼─────┼─────┤
│Snow │Snow │Water│Water│  Row 1: More terrain
│  1  │  2  │  1  │  2  │
├─────┼─────┼─────┼─────┤
│Wall │Wall │Wall │Wall │  Row 2: Walls (top, bottom, left, right)
│ top │ bot │ lft │ rgt │
├─────┼─────┼─────┼─────┤
│ Corn│ Corn│Door │Door │  Row 3: Corners, door
│ TL  │ TR  │close│open │
└─────┴─────┴─────┴─────┘
```

**Tile drawing guide:**
```
GRASS:              STONE:              SNOW:
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│░░░░░░░░░░░░░░│    │▓▓▓▓▓▓▓▓▓▓▓▓▓▓│    │██████████████│
│░░░░░░░░░░░░░░│    │▓▓░░▓▓▓▓░░▓▓▓▓│    │██░░██████░░██│
│░░░▒░░░░░▒░░░░│    │▓▓▓▓▓▓▓▓▓▓▓▓▓▓│    │██████████████│
│░░░░░░░░░░░░░░│    │▓▓▓▓░░▓▓▓▓▓▓▓▓│    │██████████████│
└──────────────┘    └──────────────┘    └──────────────┘
 (green tones)       (gray tones)        (white/blue)
```

---

### Step 6.4: Update LDTK with New Tileset
**Work to do:**
- Import new tileset into LDTK
- Update test zone map with actual tiles

---

### Step 6.4 Validation
**What you should see:**
- Test zone renders with actual tiles (not placeholders)
- Chest appears in world
- Chest opens when interacted
- Loot drops appear on ground
- Loot can be picked up

**Test checklist:**
- [ ] Grass tiles render
- [ ] Stone tiles render
- [ ] Snow tiles render
- [ ] Wall tiles render correctly
- [ ] Chest renders (closed)
- [ ] Chest opens on interaction
- [ ] Loot drops from chest
- [ ] Loot pickup works

---

## PHASE 7: LIGHTING & ATMOSPHERE
> **Goal**: Dynamic lighting with normal maps, snow particles

### Step 7.1: Create Lit Shader Version
**Code to write:**
- `shaders/uv_lookup_lit.gdshader`

---

### Step 7.2: Create Normal Maps
**YOUR TWELFTH ART TASK:**

#### Body Normal Map
**File**: `assets/sprites/characters/player/skins/body_default_n.png`
**Size**: Same as body skin
**What to draw**:

Normal maps encode surface direction:
- R = 128 for flat, <128 = left, >128 = right
- G = 128 for flat, <128 = down, >128 = up
- B = 255 (pointing out)

**Simple approach:**
```
- Flat areas: RGB(128, 128, 255) - neutral blue
- Left-facing edges: RGB(100, 128, 255) - slightly red-shifted
- Right-facing edges: RGB(156, 128, 255) - more red
- Top edges: RGB(128, 156, 255) - more green
- Bottom edges: RGB(128, 100, 255) - less green
```

**Even simpler**: Use a normal map generator tool on your skin texture.

---

### Step 7.3: Set Up Lighting Scene
**Work to do:**
- Add WorldEnvironment with glow
- Add PointLight2D nodes
- Configure light colors

---

### Step 7.4: Create Snow Particles
**YOUR THIRTEENTH ART TASK:**

#### Snowflake Texture
**File**: `assets/particles/snow_flake.png`
**Size**: 4x4 or 8x8 pixels
**What to draw**:
- Simple white/light blue dot or tiny snowflake shape
- Soft edges (anti-aliased)

```
4x4 simple:     8x8 detailed:
┌────┐          ┌────────┐
│░██░│          │░░░██░░░│
│████│          │░░████░░│
│████│          │████████│
│░██░│          │░░████░░│
└────┘          │░░░██░░░│
                └────────┘
```

---

### Step 7.5: Implement Snow Particle System
**Code to write:**
- GPUParticles2D configuration for falling snow
- Wind effect on particles

---

### Step 7.5 Validation
**What you should see:**
- Character responds to nearby lights
- Torch light casts warm glow on character
- Snow particles falling
- Snow affected by wind
- Atmospheric, moody lighting

**Test checklist:**
- [ ] Character has depth under light
- [ ] Multiple lights blend correctly
- [ ] Areas without light are darker
- [ ] Snow particles fall naturally
- [ ] Snow responds to wind
- [ ] Overall atmosphere feels "HLD-like"

---

## PHASE 8: POLISH & EFFECTS
> **Goal**: Hit feedback, screen effects, combat juice

### Step 8.1: Implement Hit Flash
**Code to modify:**
- Add flash_amount uniform animation
- Trigger on damage taken

---

### Step 8.2: Implement Screen Shake
**Code to write:**
- Camera shake system
- Trigger on heavy hits

---

### Step 8.3: Implement Hitstop
**Code to write:**
- Brief time freeze on significant hits
- Makes combat feel impactful

---

### Step 8.4: Create Hit Particles
**YOUR FOURTEENTH ART TASK:**

#### Hit Spark/Blood Sprites
**File**: `assets/particles/hit_spark.png`
**Size**: 8x8 pixels
**What to draw**: Small bright spark/splash

---

### Step 8.5 Final Validation
**What you should see:**
- Hitting enemy causes flash + particles
- Screen shakes on heavy hits
- Brief freeze on kills
- Combat feels JUICY

---

## TEST ZONE: "THE CLEARING"

### Map Layout
```
Size: 20x15 tiles (320x240 pixels)

┌────────────────────────────────────────┐
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░CHEST░░▓│ ← Chest in corner
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░SLIME░░░░░░░░░░░░░░░░░░░░▓▓│ ← Enemy patrol area
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░SPAWN░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│ ← Player spawn
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░TORCH░▓▓│ ← Light source
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
└────────────────────────────────────────┘
▓ = Wall tiles (collision)
░ = Grass/snow floor tiles
```

### Test Zone Requirements by Phase

| Phase | What's in Zone |
|-------|----------------|
| 1-2 | Just player spawn point |
| 3 | Add equipment items to test |
| 4 | Add dummy target (or use enemy) |
| 5 | Add slime spawn point |
| 6 | Add chest, proper tiles |
| 7 | Add torch, snow particles |
| 8 | Full combat testing |

---

## ASSET CHECKLIST SUMMARY

### Phase 1 (Minimal)
- [ ] `test/test_motion_map.png` (32x32)
- [ ] `test/test_skin.png` (32x32)

### Phase 2 (Player Movement)
- [ ] `player/motion/humanoid_idle.png` (128x128, 16 frames)
- [ ] `player/motion/humanoid_walk.png` (192x128, 24 frames)
- [ ] `player/skins/body_default.png` (32x32 or 64x64)

### Phase 3 (Equipment)
- [ ] `player/skins/armor/armor_leather.png`
- [ ] `player/skins/armor/armor_none.png` (transparent)
- [ ] `player/skins/helmet/helmet_leather.png`
- [ ] `player/skins/helmet/helmet_none.png`
- [ ] `player/skins/boots/boots_leather.png`
- [ ] `player/skins/boots/boots_none.png`

### Phase 4 (Combat)
- [ ] `player/motion/humanoid_attack_1h.png` (128x128, 16 frames)
- [ ] `weapons/1h/sword_iron.png` (32x16)

### Phase 5 (Enemies)
- [ ] `enemies/slime/motion/slime_idle.png` (96x96)
- [ ] `enemies/slime/motion/slime_walk.png` (96x96)
- [ ] `enemies/slime/motion/slime_attack.png` (96x96)
- [ ] `enemies/slime/skins/slime_green.png` (24x24)
- [ ] `enemies/slime/skins/slime_red.png` (24x24)
- [ ] `enemies/slime/skins/slime_blue.png` (24x24)

### Phase 6 (World)
- [ ] `objects/lootables/chest_wooden.png` (16x16)
- [ ] `objects/lootables/chest_wooden_open.png` (16x16)
- [ ] `tilesets/terrain/test_terrain.png` (64x64)

### Phase 7 (Lighting)
- [ ] `player/skins/body_default_n.png` (normal map)
- [ ] `particles/snow_flake.png` (4x4 or 8x8)

### Phase 8 (Effects)
- [ ] `particles/hit_spark.png` (8x8)

---

## TIPS FOR ASSET CREATION

### Tools You Might Use
- **Aseprite** - Best pixel art tool, has animation features
- **Piskel** - Free, browser-based pixel art
- **GraphicsGale** - Free, good for spritesheets
- **Photoshop/GIMP** - Work but not specialized

### UV Motion Map Workflow
1. Draw your character animation normally first (reference)
2. Create new file, same size
3. Fill with UV gradient (R=X position, G=Y position)
4. Use your reference to mask out the character shape in alpha
5. The UV data inside the shape maps to skin texture

### Skin Texture Workflow
1. Think of it as a "paper craft template"
2. All angles/views flattened onto one texture
3. Motion map's UV data points to locations on this texture
4. Start simple (front view only), expand later

### Quick Placeholder Strategy
If you're stuck on an asset:
1. Create solid color version first (proves system works)
2. Add basic shapes second (readable silhouette)
3. Add details last (polish)

---

## WHEN YOU'RE STUCK

**Can't figure out UV mapping?**
→ Use the Python script to generate a test motion map
→ Or create identity mapping (pixel 0,0 maps to 0,0 on skin)

**Art looks bad?**
→ Keep it simple - fewer details = cleaner look
→ Use reference from HLD screenshots
→ Solid colors with 1px outlines = clean pixel art

**Shader not working?**
→ Check texture filter is "Nearest" not "Linear"
→ Check both textures are assigned
→ Check alpha channel exists in motion map

**Animation looks wrong?**
→ Check frame order and frame size
→ Check FPS isn't too fast/slow
→ Reduce frames - quality over quantity

---

*Document Version: 1.0*
*This is your guided path from nothing to a fully rendered visual system.*
