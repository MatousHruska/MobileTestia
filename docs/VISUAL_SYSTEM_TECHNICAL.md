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
| **Motion Map** | Spritesheet where RGB values encode UV coordinates into skin texture using **body-part mapping** |
| **Skin** | Static 64x64 "paper doll" texture divided into body-part regions (head, torso, arms, legs) |
| **Body-Part Mapping** | Each body part in motion map samples from its dedicated region in skin texture |
| **Anchor** | Position data for attaching weapons to animation frames |
| **Normal Map** | Per-sprite depth information for dynamic lighting |

### Body-Part UV Mapping System

Unlike simple gradient UV mapping (where R=X, G=Y), our system uses **body-part mapping**:

```
MOTION MAP FRAME                    SKIN TEXTURE (64x64)
┌────────────────┐                  ┌────────┬────────┬────────┬────────┐
│    ┌─────┐     │                  │ HEAD   │ HEAD   │ TORSO  │ TORSO  │
│    │HEAD │────────UV──────────────│ FRONT  │ BACK   │ FRONT  │ BACK   │
│    └─────┘     │                  ├────────┼────────┼────────┼────────┤
│    ┌─────┐     │                  │ L-ARM  │ L-ARM  │ R-ARM  │ R-ARM  │
│    │TORSO│────────UV──────────────│ FRONT  │ BACK   │ FRONT  │ BACK   │
│    └─────┘     │                  ├────────┼────────┼────────┼────────┤
│   ┌┴┐   ┌┴┐    │                  │ L-LEG  │ L-LEG  │ R-LEG  │ R-LEG  │
│   │L│   │R│─────UV────────────────│ FRONT  │ BACK   │ FRONT  │ BACK   │
│   └─┘   └─┘    │                  ├────────┼────────┼────────┼────────┤
└────────────────┘                  │ FEET   │ HANDS  │ EXTRA  │ EXTRA  │
                                    └────────┴────────┴────────┴────────┘

Each body part's pixels in the motion map have UV values that sample
from that part's specific 16x16 region in the skin texture.
```

**Benefits:**
- Different body parts can have different appearances (front arm vs back arm)
- Enables 3D-like depth effects (back arm darker than front arm)
- Single skin texture controls entire character appearance
- Easy to create character variants by swapping skins

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

## UV LOOKUP SHADER

### Core Shader: `uv_lookup.gdshader`

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Skin texture layers
uniform sampler2D skin_body : hint_default_white, filter_nearest;
uniform sampler2D skin_armor : hint_default_white, filter_nearest;
uniform sampler2D skin_helmet : hint_default_white, filter_nearest;
uniform sampler2D skin_boots : hint_default_white, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Sample the motion map (the sprite's TEXTURE)
    vec4 motion_data = texture(TEXTURE, UV);

    // If alpha is 0, discard (transparent pixel in motion map)
    if (motion_data.a < 0.01) {
        discard;
    }

    // R and G channels encode UV coordinates into skin texture
    // Motion map uses 0-255 mapped to 0.0-1.0
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    // Sample all skin layers
    vec4 body_color = texture(skin_body, skin_uv);
    vec4 armor_color = texture(skin_armor, skin_uv);
    vec4 helmet_color = texture(skin_helmet, skin_uv);
    vec4 boots_color = texture(skin_boots, skin_uv);

    // Composite layers (armor over body, helmet over that, etc.)
    vec4 final_color = body_color;
    final_color = mix(final_color, armor_color, armor_color.a);
    final_color = mix(final_color, helmet_color, helmet_color.a);
    final_color = mix(final_color, boots_color, boots_color.a);

    // Apply tint (for status effects like poison)
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output with motion map's alpha controlling shape
    COLOR = vec4(final_color.rgb, motion_data.a * final_color.a);
}
```

### Lit Version: `uv_lookup_lit.gdshader`

```glsl
shader_type canvas_item;
render_mode blend_mix, light_only;

// Skin textures
uniform sampler2D skin_body : hint_default_white, filter_nearest;
uniform sampler2D skin_armor : hint_default_white, filter_nearest;
uniform sampler2D skin_helmet : hint_default_white, filter_nearest;
uniform sampler2D skin_boots : hint_default_white, filter_nearest;

// Normal maps for each layer
uniform sampler2D normal_body : hint_normal, filter_nearest;
uniform sampler2D normal_armor : hint_normal, filter_nearest;
uniform sampler2D normal_helmet : hint_normal, filter_nearest;
uniform sampler2D normal_boots : hint_normal, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Ambient light (so sprites aren't pure black without lights)
uniform vec4 ambient_color : source_color = vec4(0.3, 0.3, 0.4, 1.0);

varying vec2 skin_uv_varying;

void vertex() {
    // Pass through
}

void fragment() {
    vec4 motion_data = texture(TEXTURE, UV);

    if (motion_data.a < 0.01) {
        discard;
    }

    vec2 skin_uv = vec2(motion_data.r, motion_data.g);
    skin_uv_varying = skin_uv;

    // Sample colors
    vec4 body_color = texture(skin_body, skin_uv);
    vec4 armor_color = texture(skin_armor, skin_uv);
    vec4 helmet_color = texture(skin_helmet, skin_uv);
    vec4 boots_color = texture(skin_boots, skin_uv);

    // Composite
    vec4 final_color = body_color;
    final_color = mix(final_color, armor_color, armor_color.a);
    final_color = mix(final_color, helmet_color, helmet_color.a);
    final_color = mix(final_color, boots_color, boots_color.a);

    // Apply tint and flash
    final_color.rgb *= tint.rgb;
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Add ambient
    final_color.rgb += ambient_color.rgb * ambient_color.a;

    COLOR = vec4(final_color.rgb, motion_data.a * final_color.a);

    // Composite normal maps for lighting
    vec3 body_normal = texture(normal_body, skin_uv).rgb;
    vec3 armor_normal = texture(normal_armor, skin_uv).rgb;
    vec3 helmet_normal = texture(normal_helmet, skin_uv).rgb;
    vec3 boots_normal = texture(normal_boots, skin_uv).rgb;

    // Blend normals based on alpha (simplified)
    vec3 final_normal = body_normal;
    final_normal = mix(final_normal, armor_normal, armor_color.a);
    final_normal = mix(final_normal, helmet_normal, helmet_color.a);
    final_normal = mix(final_normal, boots_normal, boots_color.a);

    NORMAL_MAP = vec4(final_normal, 1.0);
}

void light() {
    // Godot's built-in 2D lighting will use NORMAL_MAP
    LIGHT = LIGHT_COLOR.rgb * LIGHT_ENERGY * max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
}
```

### Enemy Shader (Simplified): `uv_lookup_enemy.gdshader`

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Single skin for enemies
uniform sampler2D skin : hint_default_white, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 motion_data = texture(TEXTURE, UV);

    if (motion_data.a < 0.01) {
        discard;
    }

    vec2 skin_uv = vec2(motion_data.r, motion_data.g);
    vec4 skin_color = texture(skin, skin_uv);

    // Apply modifiers
    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    COLOR = vec4(final_color.rgb, motion_data.a * skin_color.a);
}
```

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

### Body-Part Skin Texture Layout

The skin texture is a 64x64 "paper doll" divided into 16x16 regions:

```
SKIN TEXTURE LAYOUT (64x64, 4x4 grid of 16x16 regions):
┌────────┬────────┬────────┬────────┐
│ HEAD   │ HEAD   │ TORSO  │ TORSO  │
│ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 0 (y: 0-15)
│(0,0)   │(16,0)  │(32,0)  │(48,0)  │
├────────┼────────┼────────┼────────┤
│ L-ARM  │ L-ARM  │ R-ARM  │ R-ARM  │
│ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 1 (y: 16-31)
│(0,16)  │(16,16) │(32,16) │(48,16) │
├────────┼────────┼────────┼────────┤
│ L-LEG  │ L-LEG  │ R-LEG  │ R-LEG  │
│ FRONT  │ BACK   │ FRONT  │ BACK   │  Row 2 (y: 32-47)
│(0,32)  │(16,32) │(32,32) │(48,32) │
├────────┼────────┼────────┼────────┤
│ FEET   │ HANDS  │ EXTRA  │ EXTRA  │
│        │        │        │        │  Row 3 (y: 48-63)
│(0,48)  │(16,48) │(32,48) │(48,48) │
└────────┴────────┴────────┴────────┘
```

**Creating Skins:**
1. Start with the generated template (`body_default.png`)
2. Paint each 16x16 region with that body part's appearance
3. Use FRONT regions for what's visible when facing DOWN
4. Use BACK regions for what's visible when facing UP (can be darker for depth)
5. Side views use a mix (near arm = front, far arm = back)

### Creating Motion Maps

Motion maps define the CHARACTER SILHOUETTE and UV MAPPING to skin regions.

**Method 1: Use the Generator (Recommended)**
1. Open the project in Godot editor
2. Go to `scripts/tools/motion_map_generator.gd`
3. Run: Script > Run (Ctrl+Shift+X)
4. Edit the generated files to adjust silhouette shapes

**Method 2: Manual Creation**
1. Create a spritesheet (e.g., 128x128 for 4x4 grid of 32x32 frames)
2. For each pixel in a body part:
   - R channel = U coordinate (0-255 mapped to 0.0-1.0)
   - G channel = V coordinate (0-255 mapped to 0.0-1.0)
   - B channel = unused (set to 0)
   - A channel = silhouette (255 = visible, 0 = transparent)
3. Body part regions map as follows:
   - Head front:  UV (0.00-0.25, 0.00-0.25)
   - Head back:   UV (0.25-0.50, 0.00-0.25)
   - Torso front: UV (0.50-0.75, 0.00-0.25)
   - Torso back:  UV (0.75-1.00, 0.00-0.25)
   - etc.

**Editing Motion Maps:**
- Adjust ALPHA to change character silhouette shape
- Don't change R/G values unless you want to remap body parts
- Back arm/leg should be drawn FIRST (behind body)
- Front arm/leg drawn LAST (in front of body)

### Animation Frame Layout

Motion maps use this standard frame layout:

```
IDLE (4x4 = 16 frames):          WALK (6x4 = 24 frames):
┌───┬───┬───┬───┐                ┌───┬───┬───┬───┬───┬───┐
│ D │ D │ D │ D │ Row 0: DOWN    │ D │ D │ D │ D │ D │ D │
├───┼───┼───┼───┤                ├───┼───┼───┼───┼───┼───┤
│ U │ U │ U │ U │ Row 1: UP      │ U │ U │ U │ U │ U │ U │
├───┼───┼───┼───┤                ├───┼───┼───┼───┼───┼───┤
│ L │ L │ L │ L │ Row 2: LEFT    │ L │ L │ L │ L │ L │ L │
├───┼───┼───┼───┤                ├───┼───┼───┼───┼───┼───┤
│ R │ R │ R │ R │ Row 3: RIGHT   │ R │ R │ R │ R │ R │ R │
└───┴───┴───┴───┘                └───┴───┴───┴───┴───┴───┘
```

### Quick Start Workflow

1. **Run the generator** to create template assets
2. **Edit `body_default.png`** in your image editor - paint each body part region
3. **Test in-game** - character should show your painted skin
4. **Refine motion maps** if needed - adjust alpha for better silhouettes
5. **Create skin variants** - copy `body_default.png` and repaint for different characters

### Normal Map Guidelines

1. Use 128,128,255 (flat blue) as neutral
2. Red channel: left(-) / right(+)
3. Green channel: down(-) / up(+)
4. Keep consistent light direction (top-left recommended)

---

## MOTION MAP GENERATOR TOOL

Located at: `scripts/tools/motion_map_generator.gd`

**Usage:**
1. Open in Godot editor
2. Script > Run (Ctrl+Shift+X)

**Generates:**
- `assets/sprites/characters/player/skins/body_default.png` - 64x64 skin template
- `assets/sprites/characters/player/motion/humanoid_idle.png` - 128x128 idle animation
- `assets/sprites/characters/player/motion/humanoid_walk.png` - 192x128 walk animation

**Customization:**
Edit the generator to adjust:
- `FRAME_SIZE` - size of each animation frame (default: 32)
- `_get_*_bounds()` functions - body part positions and sizes
- Walk cycle offsets in `_draw_character_frame()`

---

*Document Version: 2.0 - Updated for body-part mapping system*
*Companion to: ART_DIRECTION.md*
