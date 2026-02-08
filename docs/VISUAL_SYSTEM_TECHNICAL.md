# VISUAL SYSTEM TECHNICAL IMPLEMENTATION

> **Companion to**: ART_DIRECTION.md
> **Purpose**: Detailed technical specifications for implementing the visual asset system

---

## TABLE OF CONTENTS

1. [System Overview](#system-overview)
2. [Folder Structure](#folder-structure)
3. [Database Schema](#database-schema)
4. [UV Lookup Shader](#uv-lookup-shader)
5. [VisualAssetManager](#visualassetmanager)
6. [Animation System](#animation-system)
7. [Weapon Anchor System](#weapon-anchor-system)
8. [Lighting System](#lighting-system)
9. [Particle System](#particle-system)
10. [Integration Points](#integration-points)
11. [Implementation Phases](#implementation-phases)

---

## SYSTEM OVERVIEW

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VISUAL ASSET SYSTEM                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  Excel/VBA      │    │  JSON Exports   │    │  Runtime        │         │
│  │  Database       │───▶│  (databases/)   │───▶│  Managers       │         │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘         │
│                                                        │                    │
│                                                        ▼                    │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    VisualAssetManager (Autoload)                 │       │
│  ├─────────────────────────────────────────────────────────────────┤       │
│  │  get_motion_map(id) → Texture2D                                 │       │
│  │  get_skin(id) → Texture2D                                       │       │
│  │  get_icon(id) → Texture2D                                       │       │
│  │  get_portrait(id) → Texture2D                                   │       │
│  │  get_animation_data(id) → AnimationData                         │       │
│  │  preload_zone(zone_id) → void                                   │       │
│  │  create_placeholder(type, size, color) → Texture2D              │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                              │                                              │
│           ┌──────────────────┼──────────────────┐                          │
│           ▼                  ▼                  ▼                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                    │
│  │ UV Lookup   │    │  Lighting   │    │  Particles  │                    │
│  │ Shader      │    │  System     │    │  System     │                    │
│  └─────────────┘    └─────────────┘    └─────────────┘                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Animation Sheet** | Spritesheet where each pixel has a unique RGB color that matches a position in the UV Map |
| **UV Map** | 64x64 texture with unique colors per pixel - shader searches this to find UV coordinates |
| **Lookup Texture** | The actual appearance (skin) - sampled at the position found in the UV Map |
| **Color-Lookup** | Shader technique: find animation pixel's color in UV map → use found position to sample skin |
| **Sector-Based Slots** | Equipment system: position in UV map determines which equipment slot texture to use |
| **Anchor** | Position data for attaching weapons to animation frames |
| **Color Tolerance** | How close colors must match (0.002 = ~0.5 RGB units). Must be < half the minimum color distance in the UV map |

### Color-Lookup UV System

Our system uses **color matching** instead of encoding UV in R/G channels:

```
ANIMATION FRAME                      UV MAP (64x64)                    LOOKUP TEXTURE
┌────────────────┐                   ┌────────────────┐                ┌────────────────┐
│  Pixel at (5,3)│                   │                │                │                │
│  Color: #A4B2C3│ ──color match──►  │  #A4B2C3 found │ ──position──►  │  Sample at     │
│                │                   │  at pos (12,8) │                │  UV (12.5/64,  │
└────────────────┘                   └────────────────┘                │     8.5/64)    │
                                                                       └────────────────┘

WORKFLOW:
1. Animation sprite pixel has unique RGB color (e.g., #A4B2C3)
2. Shader searches UV Map for that exact color (within tolerance 0.002)
3. Found at position (12, 8) in UV Map
4. Convert to UV: (12+0.5)/64 = 0.1953125
5. Sample Lookup Texture at that UV coordinate
6. Output: skin color with animation's alpha as mask
```

**Benefits:**
- Full RGB available for artist workflow (no channel restrictions)
- Animation and UV Map are pixel-perfect overlays
- Easy variant creation: same animation + different lookup texture = different skin
- Equipment slots determined by POSITION in UV map, not color encoding

---

## FOLDER STRUCTURE

```
MobileTestia/
├── assets/                          # ALL VISUAL ASSETS
│   ├── sprites/
│   │   ├── characters/
│   │   │   ├── player/
│   │   │   │   ├── motion/          # Motion maps (UV encoded animations)
│   │   │   │   │   ├── humanoid_idle.png
│   │   │   │   │   ├── humanoid_walk.png
│   │   │   │   │   ├── humanoid_attack_1h.png
│   │   │   │   │   ├── humanoid_attack_2h.png
│   │   │   │   │   ├── humanoid_attack_bow.png
│   │   │   │   │   ├── humanoid_dodge.png
│   │   │   │   │   ├── humanoid_hit.png
│   │   │   │   │   └── humanoid_die.png
│   │   │   │   └── skins/           # Appearance textures
│   │   │   │       ├── body/
│   │   │   │       │   ├── body_default.png
│   │   │   │       │   └── body_default_n.png    # Normal map
│   │   │   │       ├── armor/
│   │   │   │       │   ├── armor_none.png        # Transparent (no armor)
│   │   │   │       │   ├── armor_leather.png
│   │   │   │       │   ├── armor_leather_n.png
│   │   │   │       │   ├── armor_chainmail.png
│   │   │   │       │   └── armor_chainmail_n.png
│   │   │   │       ├── helmet/
│   │   │   │       │   ├── helmet_none.png
│   │   │   │       │   ├── helmet_leather.png
│   │   │   │       │   └── helmet_iron.png
│   │   │   │       └── boots/
│   │   │   │           ├── boots_none.png
│   │   │   │           ├── boots_leather.png
│   │   │   │           └── boots_iron.png
│   │   │   │
│   │   │   ├── enemies/
│   │   │   │   ├── wolf/
│   │   │   │   │   ├── motion/
│   │   │   │   │   │   ├── wolf_idle.png
│   │   │   │   │   │   ├── wolf_walk.png
│   │   │   │   │   │   ├── wolf_attack.png
│   │   │   │   │   │   ├── wolf_hit.png
│   │   │   │   │   │   └── wolf_die.png
│   │   │   │   │   └── skins/
│   │   │   │   │       ├── wolf_starved.png
│   │   │   │   │       ├── wolf_white.png
│   │   │   │   │       └── wolf_alpha.png
│   │   │   │   ├── skeleton/
│   │   │   │   │   ├── motion/
│   │   │   │   │   └── skins/
│   │   │   │   └── slime/
│   │   │   │       ├── motion/
│   │   │   │       └── skins/
│   │   │   │
│   │   │   └── npcs/
│   │   │       ├── motion/
│   │   │       │   └── humanoid_npc_idle.png    # Simpler NPC animations
│   │   │       └── skins/
│   │   │           ├── npc_merchant.png
│   │   │           ├── npc_guard.png
│   │   │           └── npc_elder.png
│   │   │
│   │   ├── weapons/                 # Separate weapon sprites (for attacks)
│   │   │   ├── 1h/
│   │   │   │   ├── sword_iron.png
│   │   │   │   ├── sword_iron_n.png
│   │   │   │   ├── axe_iron.png
│   │   │   │   └── dagger_steel.png
│   │   │   ├── 2h/
│   │   │   │   ├── greatsword_iron.png
│   │   │   │   ├── staff_oak.png
│   │   │   │   └── polearm_iron.png
│   │   │   └── bow/
│   │   │       ├── bow_hunting.png
│   │   │       └── bow_longbow.png
│   │   │
│   │   ├── objects/
│   │   │   ├── lootables/
│   │   │   │   ├── chest_wooden.png
│   │   │   │   ├── chest_wooden_open.png
│   │   │   │   ├── barrel.png
│   │   │   │   └── urn.png
│   │   │   ├── doors/
│   │   │   │   ├── door_wooden.png
│   │   │   │   └── door_iron.png
│   │   │   └── interactables/
│   │   │       ├── lever.png
│   │   │       └── sign.png
│   │   │
│   │   └── effects/
│   │       ├── projectiles/
│   │       │   ├── arrow.png
│   │       │   └── magic_bolt.png
│   │       └── impacts/
│   │           ├── hit_slash.png
│   │           └── hit_blunt.png
│   │
│   ├── icons/
│   │   ├── abilities/               # 32x32 ability icons
│   │   │   ├── ability_slash.png
│   │   │   ├── ability_fireball.png
│   │   │   └── ability_heal.png
│   │   ├── items/                   # 32x32 item icons
│   │   │   ├── sword_iron.png
│   │   │   ├── potion_health.png
│   │   │   └── armor_leather.png
│   │   └── status/                  # 16x16 status effect icons
│   │       ├── status_poison.png
│   │       ├── status_burn.png
│   │       └── status_bleed.png
│   │
│   ├── portraits/                   # 64x64 NPC portraits
│   │   ├── player_default.png
│   │   ├── npc_merchant.png
│   │   └── npc_elder.png
│   │
│   ├── tilesets/
│   │   ├── terrain/
│   │   │   ├── grass.png
│   │   │   ├── grass_n.png          # Normal map for tiles
│   │   │   ├── stone.png
│   │   │   ├── snow.png
│   │   │   └── snow_n.png
│   │   └── decorations/
│   │       ├── flowers.png
│   │       ├── rocks.png
│   │       └── trees.png
│   │
│   ├── particles/                   # Particle textures
│   │   ├── snow_flake.png
│   │   ├── dust.png
│   │   ├── blood_drop.png
│   │   └── spark.png
│   │
│   └── ui/
│       ├── frames/
│       │   ├── panel_default.png
│       │   └── button_default.png
│       └── icons/
│           └── ui_icons.png         # UI icon atlas
│
├── shaders/                         # Godot shaders
│   ├── uv_lookup.gdshader           # Core character rendering
│   ├── uv_lookup_lit.gdshader       # With normal map lighting
│   ├── hit_flash.gdshader           # Damage feedback
│   ├── outline.gdshader             # Selection/highlight
│   └── snow_accumulation.gdshader   # Environmental
│
├── databases/
│   ├── vba/
│   │   ├── SpriteDatabase.bas       # NEW: Sprite/motion map definitions
│   │   ├── SkinDatabase.bas         # NEW: Skin texture definitions
│   │   ├── AnimationDatabase.bas    # NEW: Animation data + anchors
│   │   └── ... (existing modules)
│   └── exports/
│       ├── sprites.json             # NEW
│       ├── skins.json               # NEW
│       ├── animations.json          # NEW
│       └── ... (existing exports)
│
└── autoloads/
    └── visual_asset_manager.gd      # NEW: Central asset management
```

---

## DATABASE SCHEMA

### SpriteDatabase.bas

Manages motion maps and static sprites.

**Sheet: Sprites**
| Column | Field | Type | Description |
|--------|-------|------|-------------|
| A | id | string | Unique sprite ID (e.g., `motion_humanoid_idle`) |
| B | name | string | Display name |
| C | type | enum | `motion_map`, `static`, `animated` |
| D | category | enum | `player`, `enemy`, `npc`, `object`, `effect` |
| E | file_path | string | Relative path from assets/ |
| F | frame_width | int | Width of single frame (pixels) |
| G | frame_height | int | Height of single frame (pixels) |
| H | frame_count | int | Total frames in sheet |
| I | columns | int | Columns in spritesheet |
| J | has_normal | bool | Has accompanying _n.png normal map |

**Example Data:**
```
id                      | name           | type       | category | file_path                              | frame_width | frame_height | frame_count | columns | has_normal
------------------------|----------------|------------|----------|----------------------------------------|-------------|--------------|-------------|---------|----------
motion_humanoid_idle    | Humanoid Idle  | motion_map | player   | sprites/characters/player/motion/humanoid_idle.png    | 32 | 32 | 16 | 4 | false
motion_humanoid_walk    | Humanoid Walk  | motion_map | player   | sprites/characters/player/motion/humanoid_walk.png    | 32 | 32 | 24 | 6 | false
motion_wolf_idle        | Wolf Idle      | motion_map | enemy    | sprites/characters/enemies/wolf/motion/wolf_idle.png  | 24 | 24 | 8  | 4 | false
sprite_chest_wooden     | Wooden Chest   | static     | object   | sprites/objects/lootables/chest_wooden.png            | 16 | 16 | 2  | 2 | false
```

---

### SkinDatabase.bas

Manages character skins (appearance textures).

**Sheet: Skins**
| Column | Field | Type | Description |
|--------|-------|------|-------------|
| A | id | string | Unique skin ID (e.g., `skin_body_default`) |
| B | name | string | Display name |
| C | slot | enum | `body`, `armor`, `helmet`, `boots`, `full` (for enemies) |
| D | category | enum | `player`, `enemy`, `npc` |
| E | file_path | string | Relative path from assets/ |
| F | has_normal | bool | Has accompanying normal map |
| G | equipment_id | string | Links to equipment item (optional) |

**Example Data:**
```
id                  | name            | slot   | category | file_path                                          | has_normal | equipment_id
--------------------|-----------------|--------|----------|----------------------------------------------------|------------|-------------
skin_body_default   | Default Body    | body   | player   | sprites/characters/player/skins/body/body_default.png    | true  |
skin_armor_leather  | Leather Armor   | armor  | player   | sprites/characters/player/skins/armor/armor_leather.png  | true  | armor_leather
skin_armor_none     | No Armor        | armor  | player   | sprites/characters/player/skins/armor/armor_none.png     | false |
skin_wolf_starved   | Starved Wolf    | full   | enemy    | sprites/characters/enemies/wolf/skins/wolf_starved.png   | false |
skin_wolf_white     | White Wolf      | full   | enemy    | sprites/characters/enemies/wolf/skins/wolf_white.png     | false |
skin_wolf_alpha     | Alpha Wolf      | full   | enemy    | sprites/characters/enemies/wolf/skins/wolf_alpha.png     | false |
```

---

### AnimationDatabase.bas

Manages animation definitions and weapon anchors.

**Sheet: Animations**
| Column | Field | Type | Description |
|--------|-------|------|-------------|
| A | id | string | Animation ID (e.g., `anim_humanoid_walk_down`) |
| B | motion_map_id | string | FK to Sprites.id |
| C | state | enum | `idle`, `walk`, `attack_1h`, `attack_2h`, `attack_bow`, `dodge`, `hit`, `die` |
| D | direction | enum | `down`, `up`, `left`, `right` |
| E | start_frame | int | First frame index (0-based) |
| F | end_frame | int | Last frame index |
| G | fps | float | Playback speed |
| H | loop | bool | Should animation loop |

**Sheet: WeaponAnchors**
| Column | Field | Type | Description |
|--------|-------|------|-------------|
| A | id | string | Anchor set ID |
| B | animation_id | string | FK to Animations.id |
| C | frame | int | Frame number (0-based within animation) |
| D | anchor_x | int | X position relative to sprite center |
| E | anchor_y | int | Y position relative to sprite center |
| F | rotation | float | Weapon rotation in degrees |
| G | flip_h | bool | Flip weapon horizontally |
| H | visible | bool | Is weapon visible this frame |

**Example Anchor Data:**
```
id                          | animation_id              | frame | anchor_x | anchor_y | rotation | flip_h | visible
----------------------------|---------------------------|-------|----------|----------|----------|--------|--------
anchor_attack_1h_down       | anim_humanoid_attack_1h_down | 0  | 8        | 4        | -45      | false  | true
anchor_attack_1h_down       | anim_humanoid_attack_1h_down | 1  | 12       | 0        | 0        | false  | true
anchor_attack_1h_down       | anim_humanoid_attack_1h_down | 2  | 8        | -4       | 45       | false  | true
anchor_attack_1h_down       | anim_humanoid_attack_1h_down | 3  | 4        | 0        | 90       | false  | true
```

---

## UV COLOR-LOOKUP SHADERS

### Basic Shader: `uv_color_lookup.gdshader`

For single-skin characters (enemies, NPCs, testing):

> **CRITICAL RULES** (learned through debugging):
> 1. **Never use `source_color`** on `uv_map` or `skin` samplers — in canvas_item shaders, TEXTURE is NOT linearized, so uniforms shouldn't be either. Using `source_color` puts them in different color spaces.
> 2. **Tolerance must be tiny** — if UV map colors are gradient-based (adjacent pixels differ by ~5 RGB units), tolerance of 0.02 causes 97% false matches. Use 0.002 (~0.5 RGB units). Rule: tolerance < half the minimum color distance in the UV map.
> 3. **No `out bool` params, no `return` in fragment()** — the mobile renderer rejects these. Use sentinel return values (`vec2(-1,-1)`) and conditional assignment chains instead.
> 4. **Use `hint_default_white, filter_nearest`** on all sampler2D uniforms — bare `filter_nearest` can fail to compile.

See `shaders/uv_color_lookup.gdshader` for the actual working implementation. The shader includes 5 debug modes (switchable via uniform):
- Mode 0: Normal rendering
- Mode 1: Raw frame colors (verify TEXTURE reads correctly)
- Mode 2: Matched UV positions as R=x, G=y color
- Mode 3: Match success — green=found, red=fallback
- Mode 4: Raw skin lookup (no tint/flash)

### Equipment Shader: `uv_equipment_lookup.gdshader`

For player character with equipment slots (sector-based). See `shaders/uv_equipment_lookup.gdshader` for the actual implementation.

Same color-lookup mechanism as the basic shader, but adds position-based sector detection to choose which equipment texture to sample.

> **NOTE**: When adapting this shader, apply the same critical rules as the basic shader (no `source_color` on texture samplers, tight tolerance, mobile-safe control flow).

### Sector Layout for Equipment

```
UV MAP SECTORS (64x64 texture):
┌────────────────────────────────┐
│                                │
│        HEAD SECTOR             │  Y: 0.00 - 0.25
│        (skin_head)             │
│                                │
├────────────────┬───────────────┤
│                │               │
│  BODY SECTOR   │ HANDS SECTOR  │  Y: 0.25 - 0.75
│  (skin_body)   │ (skin_hands)  │
│                │               │
│   X: 0 - 0.5   │  X: 0.5 - 1   │
├────────────────┴───────────────┤
│                                │
│        FEET SECTOR             │  Y: 0.75 - 1.00
│        (skin_feet)             │
│                                │
└────────────────────────────────┘

Each sector's pixels sample from the corresponding equipment texture.
If equipment texture is transparent at that position, falls back to skin_base.
```

### Future: Lit Version (Phase 7)

When implementing lighting with normal maps, extend the color-lookup shader to include:
- Normal map sampling at found UV position
- Ambient light parameter
- Light response calculations

This will be documented in PHASE_7_LIGHTING_ATMOSPHERE.md when implemented.

### Test Scenes

Three test scenes are available for shader development:

**`scenes/test/test_annia_uv_shader.tscn`** - Simplified color-lookup testing (64x64)
- Uses `uv_color_lookup.gdshader`
- Assets: `assets/test/NewTest/` (Frame1.png, AnniaUVsimplified.png, AnniaLookup.png)
- Controls: Space=flash, T=tint, R=reload
- Debug buttons at bottom: Normal, Frame Colors, UV Positions, Match Status, Raw Skin

**`scenes/test/test_custom_uv_shader.tscn`** - Original 32x32 color-lookup testing
- Uses `uv_color_lookup.gdshader`
- Controls: R=reload textures, S=swap skin, Space=flash, T=tint, 1-5=frames

**`scenes/test/test_equipment_shader.tscn`** - Equipment slot testing
- Uses `uv_equipment_lookup.gdshader`
- Controls: H=head, B=body, A=arms/hands, L=legs/feet (toggle slots)

---

## VISUALASSETMANAGER

### `autoloads/visual_asset_manager.gd`

```gdscript
extends Node

## Central manager for all visual assets
## Handles loading, caching, and placeholder generation

# Signals
signal asset_loaded(asset_id: String)
signal zone_preloaded(zone_id: String)

# Cache dictionaries
var _motion_maps: Dictionary = {}      # id -> Texture2D
var _skins: Dictionary = {}            # id -> Texture2D
var _icons: Dictionary = {}            # id -> Texture2D
var _portraits: Dictionary = {}        # id -> Texture2D
var _animation_data: Dictionary = {}   # id -> AnimationData

# Database references (loaded from JSON)
var _sprite_db: Dictionary = {}
var _skin_db: Dictionary = {}
var _animation_db: Dictionary = {}
var _anchor_db: Dictionary = {}

# Placeholder colors for missing assets
const PLACEHOLDER_COLORS = {
    "player": Color(0.2, 0.4, 0.8),      # Blue
    "enemy": Color(0.8, 0.2, 0.2),       # Red
    "npc": Color(0.2, 0.8, 0.4),         # Green
    "object": Color(0.6, 0.5, 0.3),      # Brown
    "icon": Color(0.5, 0.5, 0.5),        # Gray
}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
    _load_databases()


func _load_databases() -> void:
    # Load sprite definitions
    var sprite_file = FileAccess.open("res://databases/exports/sprites.json", FileAccess.READ)
    if sprite_file:
        var json = JSON.new()
        if json.parse(sprite_file.get_as_text()) == OK:
            _sprite_db = json.data.get("sprites", {})
        sprite_file.close()

    # Load skin definitions
    var skin_file = FileAccess.open("res://databases/exports/skins.json", FileAccess.READ)
    if skin_file:
        var json = JSON.new()
        if json.parse(skin_file.get_as_text()) == OK:
            _skin_db = json.data.get("skins", {})
        skin_file.close()

    # Load animation definitions
    var anim_file = FileAccess.open("res://databases/exports/animations.json", FileAccess.READ)
    if anim_file:
        var json = JSON.new()
        if json.parse(anim_file.get_as_text()) == OK:
            _animation_db = json.data.get("animations", {})
            _anchor_db = json.data.get("weapon_anchors", {})
        anim_file.close()

# =============================================================================
# MOTION MAPS
# =============================================================================

## Get a motion map texture by ID
func get_motion_map(id: String) -> Texture2D:
    # Check cache first
    if _motion_maps.has(id):
        return _motion_maps[id]

    # Look up in database
    var sprite_data = _find_sprite(id)
    if sprite_data.is_empty():
        push_warning("VisualAssetManager: Motion map not found: " + id)
        return _create_placeholder("player", Vector2i(32, 32))

    # Load texture
    var path = "res://assets/" + sprite_data.get("file_path", "")
    var texture = _load_texture(path)

    if texture:
        _motion_maps[id] = texture
        return texture

    # Return placeholder if load failed
    return _create_placeholder(sprite_data.get("category", "player"),
        Vector2i(sprite_data.get("frame_width", 32), sprite_data.get("frame_height", 32)))


## Get motion map with SpriteFrames for AnimatedSprite2D
func get_motion_sprite_frames(motion_map_id: String, state: String, direction: String) -> SpriteFrames:
    var frames = SpriteFrames.new()
    var anim_name = state + "_" + direction

    # Find animation data
    var anim_data = _find_animation(motion_map_id, state, direction)
    if anim_data.is_empty():
        push_warning("VisualAssetManager: Animation not found: " + motion_map_id + " " + state + " " + direction)
        return frames

    var texture = get_motion_map(motion_map_id)
    var sprite_data = _find_sprite(motion_map_id)

    var frame_width = sprite_data.get("frame_width", 32)
    var frame_height = sprite_data.get("frame_height", 32)
    var columns = sprite_data.get("columns", 4)

    frames.add_animation(anim_name)
    frames.set_animation_loop(anim_name, anim_data.get("loop", true))
    frames.set_animation_speed(anim_name, anim_data.get("fps", 10.0))

    var start_frame = anim_data.get("start_frame", 0)
    var end_frame = anim_data.get("end_frame", 0)

    for i in range(start_frame, end_frame + 1):
        var atlas = AtlasTexture.new()
        atlas.atlas = texture
        var col = i % columns
        var row = i / columns
        atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
        frames.add_frame(anim_name, atlas)

    return frames

# =============================================================================
# SKINS
# =============================================================================

## Get a skin texture by ID
func get_skin(id: String) -> Texture2D:
    if _skins.has(id):
        return _skins[id]

    var skin_data = _find_skin(id)
    if skin_data.is_empty():
        push_warning("VisualAssetManager: Skin not found: " + id)
        return _create_placeholder("player", Vector2i(64, 64))

    var path = "res://assets/" + skin_data.get("file_path", "")
    var texture = _load_texture(path)

    if texture:
        _skins[id] = texture
        return texture

    return _create_placeholder(skin_data.get("category", "player"), Vector2i(64, 64))


## Get skin normal map if available
func get_skin_normal(id: String) -> Texture2D:
    var skin_data = _find_skin(id)
    if skin_data.is_empty() or not skin_data.get("has_normal", false):
        return null

    var path = "res://assets/" + skin_data.get("file_path", "").replace(".png", "_n.png")
    return _load_texture(path)


## Get skin for equipment item
func get_skin_for_equipment(equipment_id: String, slot: String) -> Texture2D:
    for skin in _skin_db:
        if skin.get("equipment_id", "") == equipment_id and skin.get("slot", "") == slot:
            return get_skin(skin.get("id", ""))

    # Return "none" skin for slot if no equipment match
    return get_skin("skin_" + slot + "_none")

# =============================================================================
# ICONS
# =============================================================================

## Get an icon texture by ID
func get_icon(id: String) -> Texture2D:
    if _icons.has(id):
        return _icons[id]

    var path = "res://assets/icons/" + id + ".png"
    var texture = _load_texture(path)

    if texture:
        _icons[id] = texture
        return texture

    return _create_placeholder("icon", Vector2i(32, 32))


## Get ability icon
func get_ability_icon(ability_id: String) -> Texture2D:
    return get_icon("abilities/" + ability_id)


## Get item icon
func get_item_icon(item_id: String) -> Texture2D:
    return get_icon("items/" + item_id)


## Get status effect icon
func get_status_icon(status_id: String) -> Texture2D:
    return get_icon("status/" + status_id)

# =============================================================================
# PORTRAITS
# =============================================================================

## Get a portrait texture by ID
func get_portrait(id: String) -> Texture2D:
    if _portraits.has(id):
        return _portraits[id]

    var path = "res://assets/portraits/" + id + ".png"
    var texture = _load_texture(path)

    if texture:
        _portraits[id] = texture
        return texture

    return _create_placeholder("npc", Vector2i(64, 64))

# =============================================================================
# WEAPON ANCHORS
# =============================================================================

## Get weapon anchor data for a specific animation and frame
func get_weapon_anchor(animation_id: String, frame: int) -> Dictionary:
    var anchor_key = animation_id + "_" + str(frame)

    for anchor in _anchor_db:
        if anchor.get("animation_id", "") == animation_id and anchor.get("frame", -1) == frame:
            return {
                "position": Vector2(anchor.get("anchor_x", 0), anchor.get("anchor_y", 0)),
                "rotation": anchor.get("rotation", 0.0),
                "flip_h": anchor.get("flip_h", false),
                "visible": anchor.get("visible", true)
            }

    # Default: no anchor data
    return {
        "position": Vector2.ZERO,
        "rotation": 0.0,
        "flip_h": false,
        "visible": false
    }

# =============================================================================
# ZONE PRELOADING
# =============================================================================

## Preload all assets needed for a zone
func preload_zone(zone_id: String) -> void:
    # This would load zone-specific assets
    # Implementation depends on how zones reference their assets
    # Could be defined in zone database or LDTK data

    emit_signal("zone_preloaded", zone_id)


## Clear cache for memory management
func clear_cache() -> void:
    _motion_maps.clear()
    _skins.clear()
    _icons.clear()
    _portraits.clear()

# =============================================================================
# PLACEHOLDERS
# =============================================================================

## Create a placeholder texture for missing assets
func _create_placeholder(category: String, size: Vector2i) -> Texture2D:
    var color = PLACEHOLDER_COLORS.get(category, Color.MAGENTA)

    var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(color)

    # Add border
    var border_color = color.darkened(0.3)
    for x in range(size.x):
        image.set_pixel(x, 0, border_color)
        image.set_pixel(x, size.y - 1, border_color)
    for y in range(size.y):
        image.set_pixel(0, y, border_color)
        image.set_pixel(size.x - 1, y, border_color)

    return ImageTexture.create_from_image(image)


## Create a UV-encoded placeholder motion map
func create_placeholder_motion_map(size: Vector2i) -> Texture2D:
    var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

    # Fill with UV-encoded colors
    # Each pixel's R,G maps to that pixel's position in skin texture
    for y in range(size.y):
        for x in range(size.x):
            var u = float(x) / float(size.x)
            var v = float(y) / float(size.y)
            image.set_pixel(x, y, Color(u, v, 0.0, 1.0))

    return ImageTexture.create_from_image(image)

# =============================================================================
# PRIVATE HELPERS
# =============================================================================

func _load_texture(path: String) -> Texture2D:
    if ResourceLoader.exists(path):
        return load(path)
    return null


func _find_sprite(id: String) -> Dictionary:
    for sprite in _sprite_db:
        if sprite.get("id", "") == id:
            return sprite
    return {}


func _find_skin(id: String) -> Dictionary:
    for skin in _skin_db:
        if skin.get("id", "") == id:
            return skin
    return {}


func _find_animation(motion_map_id: String, state: String, direction: String) -> Dictionary:
    for anim in _animation_db:
        if anim.get("motion_map_id", "") == motion_map_id and \
           anim.get("state", "") == state and \
           anim.get("direction", "") == direction:
            return anim
    return {}
```

---

## ANIMATION SYSTEM

### Character Renderer Component

```gdscript
# scripts/rendering/uv_character_renderer.gd
class_name UVCharacterRenderer
extends Node2D

## Renders a character using UV lookup system

signal animation_finished(anim_name: String)
signal frame_changed(frame: int)

# Node references
@onready var sprite: Sprite2D = $Sprite2D
@onready var weapon_sprite: Sprite2D = $WeaponSprite

# Shader material
var _material: ShaderMaterial

# Current state
var _current_motion_map: String = ""
var _current_state: String = "idle"
var _current_direction: String = "down"
var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = false

# Animation data cache
var _current_anim_data: Dictionary = {}
var _sprite_data: Dictionary = {}

# Skin IDs
var skin_body: String = "skin_body_default"
var skin_armor: String = "skin_armor_none"
var skin_helmet: String = "skin_helmet_none"
var skin_boots: String = "skin_boots_none"

# Weapon
var weapon_sprite_id: String = ""
var _weapon_category: String = "1h"  # 1h, 2h, bow


func _ready() -> void:
    _setup_material()


func _setup_material() -> void:
    _material = ShaderMaterial.new()
    _material.shader = preload("res://shaders/uv_lookup.gdshader")
    sprite.material = _material
    _update_skins()


func _process(delta: float) -> void:
    if not _is_playing:
        return

    _animation_timer += delta
    var frame_duration = 1.0 / _current_anim_data.get("fps", 10.0)

    if _animation_timer >= frame_duration:
        _animation_timer -= frame_duration
        _advance_frame()


func _advance_frame() -> void:
    var start_frame = _current_anim_data.get("start_frame", 0)
    var end_frame = _current_anim_data.get("end_frame", 0)
    var loop = _current_anim_data.get("loop", true)

    _current_frame += 1

    if _current_frame > end_frame:
        if loop:
            _current_frame = start_frame
        else:
            _current_frame = end_frame
            _is_playing = false
            emit_signal("animation_finished", _current_state + "_" + _current_direction)
            return

    _update_sprite_frame()
    _update_weapon_anchor()
    emit_signal("frame_changed", _current_frame)


func _update_sprite_frame() -> void:
    var frame_width = _sprite_data.get("frame_width", 32)
    var frame_height = _sprite_data.get("frame_height", 32)
    var columns = _sprite_data.get("columns", 4)

    var col = _current_frame % columns
    var row = _current_frame / columns

    sprite.region_enabled = true
    sprite.region_rect = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)


func _update_weapon_anchor() -> void:
    if weapon_sprite_id.is_empty():
        weapon_sprite.visible = false
        return

    var anim_id = "anim_humanoid_" + _current_state + "_" + _current_direction
    var local_frame = _current_frame - _current_anim_data.get("start_frame", 0)
    var anchor = VisualAssetManager.get_weapon_anchor(anim_id, local_frame)

    weapon_sprite.visible = anchor.get("visible", false)
    if weapon_sprite.visible:
        weapon_sprite.position = anchor.get("position", Vector2.ZERO)
        weapon_sprite.rotation_degrees = anchor.get("rotation", 0.0)
        weapon_sprite.flip_h = anchor.get("flip_h", false)


func _update_skins() -> void:
    _material.set_shader_parameter("skin_body", VisualAssetManager.get_skin(skin_body))
    _material.set_shader_parameter("skin_armor", VisualAssetManager.get_skin(skin_armor))
    _material.set_shader_parameter("skin_helmet", VisualAssetManager.get_skin(skin_helmet))
    _material.set_shader_parameter("skin_boots", VisualAssetManager.get_skin(skin_boots))

# =============================================================================
# PUBLIC API
# =============================================================================

## Set motion map (character base type)
func set_motion_map(motion_map_id: String) -> void:
    _current_motion_map = motion_map_id
    sprite.texture = VisualAssetManager.get_motion_map(motion_map_id)
    _sprite_data = VisualAssetManager._find_sprite(motion_map_id)


## Play an animation
func play(state: String, direction: String = "") -> void:
    if direction.is_empty():
        direction = _current_direction

    _current_state = state
    _current_direction = direction

    # Get animation data
    _current_anim_data = VisualAssetManager._find_animation(
        _current_motion_map, state, direction
    )

    if _current_anim_data.is_empty():
        push_warning("Animation not found: " + _current_motion_map + " " + state + " " + direction)
        return

    _current_frame = _current_anim_data.get("start_frame", 0)
    _animation_timer = 0.0
    _is_playing = true

    _update_sprite_frame()
    _update_weapon_anchor()


## Stop animation
func stop() -> void:
    _is_playing = false


## Set direction without changing state
func set_direction(direction: String) -> void:
    if direction != _current_direction:
        play(_current_state, direction)


## Equip armor (updates skin)
func equip_armor(equipment_id: String) -> void:
    if equipment_id.is_empty():
        skin_armor = "skin_armor_none"
    else:
        var skin = VisualAssetManager.get_skin_for_equipment(equipment_id, "armor")
        if skin:
            skin_armor = equipment_id
    _update_skins()


## Equip helmet
func equip_helmet(equipment_id: String) -> void:
    if equipment_id.is_empty():
        skin_helmet = "skin_helmet_none"
    else:
        skin_helmet = "skin_helmet_" + equipment_id
    _update_skins()


## Equip boots
func equip_boots(equipment_id: String) -> void:
    if equipment_id.is_empty():
        skin_boots = "skin_boots_none"
    else:
        skin_boots = "skin_boots_" + equipment_id
    _update_skins()


## Set weapon sprite
func set_weapon(weapon_id: String, category: String) -> void:
    weapon_sprite_id = weapon_id
    _weapon_category = category

    if weapon_id.is_empty():
        weapon_sprite.visible = false
    else:
        weapon_sprite.texture = VisualAssetManager.get_icon("weapons/" + category + "/" + weapon_id)


## Hit flash effect
func flash(duration: float = 0.1, color: Color = Color.WHITE) -> void:
    _material.set_shader_parameter("flash_color", color)
    _material.set_shader_parameter("flash_amount", 1.0)

    var tween = create_tween()
    tween.tween_property(_material, "shader_parameter/flash_amount", 0.0, duration)


## Apply tint (for status effects)
func set_tint(color: Color) -> void:
    _material.set_shader_parameter("tint", color)


## Clear tint
func clear_tint() -> void:
    _material.set_shader_parameter("tint", Color.WHITE)
```

---

## WEAPON ANCHOR SYSTEM

### How Anchors Work

```
MOTION MAP FRAME               WEAPON POSITIONED BY ANCHOR
┌────────────────┐             ┌────────────────┐
│                │             │        ╱       │
│    ┌───┐       │             │    ┌──╱┐       │
│    │ O │       │  + anchor   │    │ O │       │
│    ├───┤       │  data   →   │    ├───┤       │
│   ╱│   │╲      │             │   ╱│   │╲      │
│  ╱ │   │ ╲     │             │  ╱ │   │ ╲     │
│    │   │       │             │    │   │       │
└────────────────┘             └────────────────┘

anchor_data = {
    "position": Vector2(8, -4),   # Offset from sprite center
    "rotation": -30,              # Degrees
    "flip_h": false,
    "visible": true
}
```

### Attack Animation Frame Breakdown

```
1H SWORD ATTACK (DOWN) - 4 frames

Frame 0 (Wind-up):        Frame 1 (Apex):          Frame 2 (Follow):        Frame 3 (Recovery):
┌────────────────┐        ┌────────────────┐        ┌────────────────┐        ┌────────────────┐
│          ╲     │        │        │       │        │                │        │                │
│    ┌───┐  ╲    │        │    ┌───┼─      │        │    ┌───┐       │        │    ┌───┐       │
│    │ O │   │   │        │    │ O │       │        │    │ O │       │        │    │ O │       │
│    ├───┤       │        │    ├───┤       │        │    ├───┤  ╱    │        │    ├───┤       │
│   ╱│   │╲      │        │   ╱│   │╲      │        │   ╱│   │╲╱     │        │   ╱│   │╲      │
│    │   │       │        │    │   │       │        │    │   │       │        │    │   │       │
└────────────────┘        └────────────────┘        └────────────────┘        └────────────────┘
anchor: (12, -8)          anchor: (16, 4)          anchor: (12, 8)          anchor: (0, 4)
rotation: -45°            rotation: 0°             rotation: 45°            rotation: 90°
```

---

## LIGHTING SYSTEM

### Setup in Godot

```
Scene Tree:
├── WorldEnvironment
│   └── Environment (resource)
│       ├── Background: Color
│       ├── Ambient Light: Low (0.2-0.3)
│       └── Glow: Enabled
│
├── DirectionalLight2D (optional sun/moon)
│   ├── Color: Based on time/zone
│   └── Energy: 0.5-1.0
│
├── TileMap (with normal maps)
│
├── Entities (Y-sorted)
│   ├── Player (UV shader with normal maps)
│   └── Enemies
│
└── PointLight2D nodes (torches, magic)
    ├── Color: Warm orange for torches
    ├── Energy: 1.0-2.0
    ├── Range: Based on source
    └── Shadow: Enabled for important lights
```

### Light2D Configuration for Different Sources

```gdscript
# Example torch light setup
func create_torch_light() -> PointLight2D:
    var light = PointLight2D.new()
    light.color = Color(1.0, 0.7, 0.3)  # Warm orange
    light.energy = 1.5
    light.texture = preload("res://assets/lights/soft_circle.png")
    light.texture_scale = 2.0
    light.shadow_enabled = true
    light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
    return light

# Example magic glow
func create_magic_light(magic_type: String) -> PointLight2D:
    var light = PointLight2D.new()
    match magic_type:
        "fire":
            light.color = Color(1.0, 0.4, 0.1)
        "ice":
            light.color = Color(0.5, 0.8, 1.0)
        "arcane":
            light.color = Color(0.7, 0.3, 1.0)
        _:
            light.color = Color(0.3, 1.0, 1.0)  # Default cyan
    light.energy = 1.0
    light.shadow_enabled = false
    return light
```

---

## PARTICLE SYSTEM

### Snow Particle Example

```gdscript
# scenes/effects/snow_particles.tscn (GPUParticles2D)

extends GPUParticles2D

func _ready() -> void:
    amount = 200
    lifetime = 8.0
    preprocess = 4.0

    var material = ParticleProcessMaterial.new()
    material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    material.emission_box_extents = Vector3(500, 10, 0)  # Wide spawn area

    material.direction = Vector3(0.2, 1, 0)  # Slight angle
    material.spread = 15.0
    material.gravity = Vector3(0, 50, 0)
    material.initial_velocity_min = 20.0
    material.initial_velocity_max = 40.0

    # Add turbulence for wind effect
    material.turbulence_enabled = true
    material.turbulence_noise_strength = 2.0
    material.turbulence_noise_speed = 0.5

    process_material = material

    # Use snowflake texture
    texture = preload("res://assets/particles/snow_flake.png")
```

### Hit Effect Particle

```gdscript
# scripts/effects/hit_particles.gd

extends GPUParticles2D

func emit_at(pos: Vector2, hit_direction: Vector2, damage_type: String) -> void:
    global_position = pos

    var material = process_material as ParticleProcessMaterial
    material.direction = Vector3(hit_direction.x, hit_direction.y, 0)

    # Color based on damage type
    match damage_type:
        "physical":
            material.color = Color(1.0, 0.2, 0.2)  # Blood red
        "fire":
            material.color = Color(1.0, 0.5, 0.1)
        "ice":
            material.color = Color(0.5, 0.8, 1.0)
        "poison":
            material.color = Color(0.3, 0.8, 0.2)
        _:
            material.color = Color.WHITE

    emitting = true

    # Auto-remove after emission
    await get_tree().create_timer(lifetime).timeout
    queue_free()
```

---

## INTEGRATION POINTS

### With Existing Systems

| System | Integration |
|--------|-------------|
| **DatabaseLoader** | Add loading of sprites.json, skins.json, animations.json |
| **base_character.gd** | Replace placeholder rendering with UVCharacterRenderer |
| **enemy_npc.gd** | Use enemy shader with skin from database |
| **friendly_npc.gd** | Use NPC shader with portrait from database |
| **Inventory** | Equip events trigger skin changes |
| **PlayerStats** | Equipment changes call renderer.equip_*() |
| **CombatText** | Already exists, just needs styling |
| **ChunkManager** | Trigger VisualAssetManager.preload_zone() |

### Modifying base_character.gd

```gdscript
# In base_character.gd, replace placeholder sprite setup with:

var _renderer: UVCharacterRenderer

func _setup_visuals() -> void:
    _renderer = preload("res://scenes/rendering/uv_character_renderer.tscn").instantiate()
    add_child(_renderer)

    # For player
    if is_player:
        _renderer.set_motion_map("motion_humanoid")
        _renderer.skin_body = "skin_body_default"
        # Equipment will be set by inventory system

    # For enemies
    elif is_enemy:
        var enemy_data = DatabaseLoader.get_enemy(enemy_id)
        _renderer.set_motion_map(enemy_data.get("motion_map_id", "motion_humanoid"))
        # Skin comes from enemy variant
        var skin_id = enemy_data.get("skin_id", "")
        _renderer._material.set_shader_parameter("skin", VisualAssetManager.get_skin(skin_id))
```

---

## IMPLEMENTATION PHASES

### Phase 1: Foundation (Week 1)
- [ ] Create folder structure
- [ ] Create `uv_lookup.gdshader` (basic version)
- [ ] Create `VisualAssetManager` autoload
- [ ] Create VBA modules: SpriteDatabase.bas, SkinDatabase.bas
- [ ] Add to project.godot autoloads
- [ ] Create placeholder generator in VisualAssetManager

### Phase 2: Player Rendering (Week 2)
- [ ] Create player motion map placeholder (UV-encoded)
- [ ] Create body skin placeholder
- [ ] Create `UVCharacterRenderer` component
- [ ] Integrate with player_controller.gd
- [ ] Test basic idle/walk animations

### Phase 3: Equipment System (Week 2-3)
- [ ] Create armor/helmet/boots skin slots
- [ ] Create AnimationDatabase.bas with anchors
- [ ] Implement weapon anchor system
- [ ] Connect to Inventory equipment events
- [ ] Test equipment changes update visuals

### Phase 4: Enemy System (Week 3)
- [ ] Create `uv_lookup_enemy.gdshader`
- [ ] Create wolf motion map placeholder
- [ ] Create wolf skin variants (3)
- [ ] Integrate with enemy_npc.gd
- [ ] Test enemy variants spawn correctly

### Phase 5: Lighting (Week 4)
- [ ] Create `uv_lookup_lit.gdshader`
- [ ] Set up WorldEnvironment with glow
- [ ] Create normal map templates
- [ ] Add PointLight2D to torches/sources
- [ ] Test dynamic lighting on characters

### Phase 6: Effects & Polish (Week 4+)
- [ ] Hit flash implementation
- [ ] Screen shake system
- [ ] Hitstop system
- [ ] Basic particle effects (hit, snow)
- [ ] Post-processing setup

---

## APPENDIX: VBA MODULE TEMPLATES

### SpriteDatabase.bas (Header)

```vba
Attribute VB_Name = "SpriteDatabase"
'===============================================================================
' SpriteDatabase Module
' Handles validation and export for Sprites (motion maps, static sprites)
'===============================================================================
Option Explicit

Private Const SHEET_SPRITES As String = "Sprites"

' Column indices (1-based)
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
Private Const COL_TYPE As Integer = 3
Private Const COL_CATEGORY As Integer = 4
Private Const COL_FILE_PATH As Integer = 5
Private Const COL_FRAME_WIDTH As Integer = 6
Private Const COL_FRAME_HEIGHT As Integer = 7
Private Const COL_FRAME_COUNT As Integer = 8
Private Const COL_COLUMNS As Integer = 9
Private Const COL_HAS_NORMAL As Integer = 10

' Valid types
Private validTypes() As String
Private validCategories() As String

Private Sub InitValidLists()
    validTypes = Split("motion_map,static,animated", ",")
    validCategories = Split("player,enemy,npc,object,effect,weapon", ",")
End Sub

' ... (Validate and Export functions follow standard pattern)
```

---

## NOTES FOR ARTISTS

### Color-Lookup System Asset Creation

The color-lookup system requires three types of textures that work together:

#### 1. Animation Sheet
- Contains colored silhouettes of the character
- Each pixel has a unique RGB color
- Colors must match exactly with the UV Map
- Alpha channel defines the visible silhouette

#### 2. UV Map (32x32)
- Contains unique colors at specific positions
- Pixel-perfect overlay with the lookup textures
- The shader searches this to find UV coordinates
- Typically created once and shared across skins

#### 3. Lookup Texture (Skin)
- The actual character appearance
- Same size as UV Map (32x32)
- Pixel-perfect overlay - position X,Y in skin = position X,Y in UV map
- Swap this texture to change character appearance

### Creating Assets - Workflow

```
STEP 1: Create UV Map (32x32)
┌────────────────────────────────┐
│ Each pixel = unique RGB color  │
│ Position matters!              │
│ This is your "palette key"     │
└────────────────────────────────┘

STEP 2: Create Lookup Texture (32x32)
┌────────────────────────────────┐
│ Draw character appearance      │
│ Same size, same pixel grid     │
│ Pixel (5,3) here = pixel (5,3) │
│ in UV Map                      │
└────────────────────────────────┘

STEP 3: Create Animation Sheet
┌────────────────────────────────┐
│ Draw animation frames          │
│ Color each pixel to MATCH      │
│ the UV Map color at the        │
│ position you want to sample    │
└────────────────────────────────┘
```

### Equipment Texture Creation

For the equipment system, you need sector-aligned textures:

```
LOOKUP TEXTURE SECTORS (32x32):
┌────────────────────────────────┐
│       HEAD SECTOR              │  Y: 0-8 pixels (top)
│    (LookupTextureHead.png)     │
├────────────────┬───────────────┤
│  BODY SECTOR   │ HANDS SECTOR  │  Y: 8-24 pixels (middle)
│  (LookupBody)  │ (LookupHands) │
│  X: 0-16       │  X: 16-32     │
├────────────────┴───────────────┤
│       FEET SECTOR              │  Y: 24-32 pixels (bottom)
│    (LookupTextureLegs.png)     │
└────────────────────────────────┘

Create separate lookup textures for each slot:
- LookupTextureHead.png - only draws in head sector region
- LookupTextureBody.png - only draws in body sector region
- LookupTextureHands.png - only draws in hands sector region
- LookupTextureLegs.png - only draws in feet sector region

Transparent pixels in equipment textures fall back to base skin.
```

### Test Assets Location

Test assets are located at:
`assets/sprites/characters/player/Tests/`

- `TestIdle-Sheet.png` - Animation frames with unique colors
- `TestUVMap.png` - 32x32 UV reference map
- `TestLookupTexture.png` - Base skin appearance
- `TestLookupTexture2.png` - Alternate skin appearance
- `LookupTextureHead.png` - Head equipment slot
- `LookupTextureBody.png` - Body equipment slot
- `LookupTextureHands.png` - Hands equipment slot
- `LookupTextureLegs.png` - Feet equipment slot

### Quick Start Workflow

1. **Study the test assets** in the Tests folder
2. **Copy TestUVMap.png** as your base UV reference
3. **Create a new lookup texture** - paint your character appearance
4. **Test in-game** using the test scenes (R to reload textures)
5. **Iterate** - edit textures, press R, see changes immediately

### Important Guidelines

- **All textures must match your UV map size** (currently 64x64 for Annia test, 32x32 for original player test)
- **Use Nearest filtering** — never Linear (causes blurring and color interpolation)
- **Colors must match exactly** — tolerance is 0.002 (~0.5 RGB units). UV map colors must have a minimum distance of at least 2 RGB units between any two pixels
- **Never use smooth gradients in UV maps** — adjacent pixels must have colors far enough apart to avoid false matches during the shader's sequential search
- **Never use `source_color`** on `uv_map` or `skin` sampler uniforms — this causes sRGB-to-linear conversion mismatch with TEXTURE in canvas_item shaders
- **Pixel positions matter** — UV map position = lookup texture position
- **Transparent pixels** work correctly in both UV map and lookup textures

---

## TEST SCENES

### Basic Shader Test: `test_custom_uv_shader.tscn`

Tests the single-skin color-lookup shader.

**Location:** `scenes/test/test_custom_uv_shader.tscn`

**Controls:**
- `R` - Reload all textures from disk (hot-reload for iteration)
- `S` - Swap/cycle between lookup textures (skins)
- `Space` - Test hit flash effect
- `T` - Toggle poison tint (green)
- `1-5` - Jump to specific animation frame
- `Left/Right` - Step through frames manually
- `P` - Toggle auto-play animation

### Equipment Shader Test: `test_equipment_shader.tscn`

Tests the sector-based equipment shader with slot toggling.

**Location:** `scenes/test/test_equipment_shader.tscn`

**Controls:**
- `H` - Toggle HEAD slot (on/off)
- `B` - Toggle BODY slot (on/off)
- `A` - Toggle ARMS/HANDS slot (on/off)
- `L` - Toggle LEGS/FEET slot (on/off)
- `R` - Reload all textures from disk
- `S` - Cycle base skin
- `Space` - Test hit flash
- `T` - Toggle poison tint
- `1-5` - Jump to animation frame
- `P` - Toggle auto-play

---

*Document Version: 4.0 - Updated with verified shader constraints and debug system*
*Companion to: ART_DIRECTION.md*
*Last Updated: Session claude/testingshaders2-branch-lKfTU*
