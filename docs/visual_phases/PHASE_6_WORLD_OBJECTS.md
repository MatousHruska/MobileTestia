# PHASE 6: WORLD OBJECTS & TILESET

> **Goal**: Chests, loot drops, and a proper tileset for the test zone
> **Prerequisites**: Phase 5 complete (enemies working)
> **Estimated Scope**: Medium - static sprites + tileset + LDTK integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Visual style, tile density guidelines
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Object sprite specifications
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Test zone layout
- `docs/LDTK_MAP_REFERENCE.md` - LDTK integration details
- `docs/visual_phases/PHASE_5_ENEMIES.md` - What was built in Phase 5

**Key decisions from Art Direction:**
- Tiles: 16×16 pixels
- Objects: 16×16 pixels (chests, barrels, etc.)
- World objects use static sprites (not UV lookup - no equipment changes)
- 3/4 oblique perspective for objects (see top and front)
- Interactable objects need visual feedback (highlight, glow)

---

## IMPLEMENTATION STEPS

### Step 6.1: Update Chest System for New Sprites

**Modify**: `scripts/interactable/chest_base.gd` (or equivalent)

Add sprite management:

```gdscript
# Add to chest_base.gd or loot_chest.gd

@export var sprite_closed: Texture2D
@export var sprite_open: Texture2D

@onready var sprite: Sprite2D = $Sprite2D

var _is_open: bool = false


func _ready() -> void:
    # ... existing code ...
    _setup_sprite()


func _setup_sprite() -> void:
    if not sprite:
        sprite = Sprite2D.new()
        sprite.name = "Sprite2D"
        add_child(sprite)

    sprite.centered = true

    # Load default sprites if not set in editor
    if not sprite_closed:
        sprite_closed = load("res://assets/sprites/objects/lootables/chest_wooden.png")
    if not sprite_open:
        sprite_open = load("res://assets/sprites/objects/lootables/chest_wooden_open.png")

    sprite.texture = sprite_closed


func open() -> void:
    if _is_open:
        return

    _is_open = true
    sprite.texture = sprite_open

    # Play open animation/effect
    _play_open_effect()

    # ... existing loot spawning code ...


func _play_open_effect() -> void:
    # Simple scale bounce
    var tween = create_tween()
    tween.tween_property(sprite, "scale", Vector2(1.2, 0.8), 0.1)
    tween.tween_property(sprite, "scale", Vector2(0.9, 1.1), 0.1)
    tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.1)


## Highlight when player nearby (for interaction feedback)
func set_highlighted(highlighted: bool) -> void:
    if highlighted:
        sprite.modulate = Color(1.2, 1.2, 1.2)  # Brighten
    else:
        sprite.modulate = Color.WHITE
```

---

### Step 6.2: Update Loot Drop System

**Modify**: `scripts/interactable/loot_pickup.gd`

Add visual polish for dropped items:

```gdscript
# Add/modify in loot_pickup.gd

@onready var sprite: Sprite2D = $Sprite2D
@onready var glow: PointLight2D = $Glow  # Optional

var _bob_offset: float = 0.0
var _rarity: String = "common"


func _ready() -> void:
    # ... existing code ...
    _setup_visuals()
    _start_bob_animation()


func _setup_visuals() -> void:
    # Get item icon for sprite
    var item_data = _get_item_data()
    if item_data:
        sprite.texture = VisualAssets.get_item_icon(item_data.id)
        _rarity = item_data.rarity

    _setup_rarity_glow()


func _setup_rarity_glow() -> void:
    if not glow:
        return

    # Set glow color based on rarity
    match _rarity:
        "common":
            glow.visible = false
        "uncommon":
            glow.color = Color(0.2, 0.8, 0.2)  # Green
            glow.energy = 0.3
            glow.visible = true
        "rare":
            glow.color = Color(0.2, 0.4, 1.0)  # Blue
            glow.energy = 0.5
            glow.visible = true
        "epic":
            glow.color = Color(0.6, 0.2, 0.8)  # Purple
            glow.energy = 0.7
            glow.visible = true
        "legendary":
            glow.color = Color(1.0, 0.6, 0.0)  # Orange/Gold
            glow.energy = 1.0
            glow.visible = true
            _start_legendary_effect()


func _start_bob_animation() -> void:
    # Gentle floating bob
    var tween = create_tween()
    tween.set_loops()
    tween.tween_property(self, "_bob_offset", 2.0, 0.5).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(self, "_bob_offset", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)


func _process(_delta: float) -> void:
    sprite.position.y = -_bob_offset


func _start_legendary_effect() -> void:
    # Particle burst or light beam for legendary items
    # Add particles child or spawn effect
    pass
```

---

### Step 6.3: Create Object Sprites

**USER TASK: Create world object sprites**

#### Asset 1: Wooden Chest (Closed)

**File**: `assets/sprites/objects/lootables/chest_wooden.png`
**Size**: 16×16 pixels

**What to draw** (3/4 oblique view):
```
┌────────────────┐
│    ████████    │  ← Lid (darker wood, metal trim)
│   ██████████   │
│  ████████████  │  ← Front face visible
│  █ ──────── █  │  ← Metal bands
│  █          █  │  ← Keyhole or lock
│  ████████████  │
│   ██████████   │  ← Base shadow
└────────────────┘

Colors:
- Wood main: #8B5A2B
- Wood dark: #5D3A1A
- Wood light: #A67C52
- Metal bands: #4A4A4A
- Metal highlights: #6A6A6A
- Lock: #FFD700 (gold accent)
```

#### Asset 2: Wooden Chest (Open)

**File**: `assets/sprites/objects/lootables/chest_wooden_open.png`
**Size**: 16×16 pixels

**What to draw**:
```
┌────────────────┐
│   ████████     │  ← Lid opened back
│  ██████████    │
│ ████████████   │
│ █          █   │  ← Interior visible
│ █  ★  ★    █   │  ← Sparkles/loot hint
│ ████████████   │
│  ██████████    │
└────────────────┘

Same wood colors, but:
- Interior: darker #3D2A1A
- Sparkles: #FFFFAA
```

#### Asset 3: Barrel

**File**: `assets/sprites/objects/lootables/barrel.png`
**Size**: 16×16 pixels

```
┌────────────────┐
│     ████       │  ← Top (circle, visible from above)
│   ████████     │
│  ██──────██    │  ← Metal band
│  ██      ██    │  ← Wood slats (vertical lines)
│  ██──────██    │  ← Metal band
│   ████████     │
│     ████       │  ← Shadow
└────────────────┘
```

#### Asset 4: Urn/Pot

**File**: `assets/sprites/objects/lootables/urn.png`
**Size**: 16×16 pixels

```
┌────────────────┐
│                │
│      ██        │  ← Lid/top
│     ████       │  ← Neck
│    ██████      │  ← Body (rounded)
│   ████████     │
│    ██████      │
│     ████       │  ← Base
└────────────────┘

Colors: Terracotta
- Main: #C4785A
- Shadow: #8B4A3A
- Highlight: #E8A080
```

---

### Step 6.4: Create Basic Tileset

**USER TASK: Create terrain tileset**

#### Main Terrain Tileset

**File**: `assets/tilesets/terrain/terrain_main.png`
**Size**: 128×128 pixels (8×8 grid of 16×16 tiles)

**Tile Layout**:
```
     Col0   Col1   Col2   Col3   Col4   Col5   Col6   Col7
    ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐
R0  │Grass1│Grass2│Grass3│GrassD│Stone1│Stone2│Stone3│StoneD│
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R1  │Snow1 │Snow2 │Snow3 │SnowD │Path1 │Path2 │Path3 │PathD │
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R2  │Water1│Water2│WatEdg│WatCrn│Ice1  │Ice2  │IceEdg│IceCrn│
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R3  │WallN │WallS │WallE │WallW │WallNE│WallNW│WallSE│WallSW│
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R4  │WallIn│WallTp│Pillar│PilBrk│DoorC │DoorO │Torch │TorchL│
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R5  │Tree1 │Tree2 │TreeSn│Bush1 │Rock1 │Rock2 │RockSn│Bones │
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R6  │FloorW│FloorS│FloorC│FloorR│Carpet│CarpEd│Rug   │RugEd │
    ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
R7  │Bride1│BridgW│BridgE│Stair │SnowPl│SnowDr│Flower│Pebble│
    └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘

Legend:
- D suffix = Decoration variant
- Edg = Edge tile
- Crn = Corner tile
- N/S/E/W = Direction facing
- Sn = Snow-covered variant
- Brk = Broken variant
```

#### Tile Drawing Guide

**Grass Tiles** (16×16):
```
┌────────────────┐
│░░░░░░░░░░░░░░░░│  Base green with subtle texture
│░░░▒░░░░░▒░░░░░░│  Occasional darker spots (variation)
│░░░░░░░░░░░░░░░░│  Maybe tiny flowers/tufts
│░░░░░▒░░░░░░░░░░│
└────────────────┘

Colors:
- Base: #4A7A2F
- Light: #5C8A3F
- Dark: #3A6A1F
- Flowers: #FFAAAA (tiny dots)
```

**Stone Tiles** (16×16):
```
┌────────────────┐
│▓▓▓▓▓░▓▓▓▓▓▓▓▓▓▓│  Gray with crack lines
│▓▓░░▓▓▓▓▓▓░░▓▓▓▓│  Lighter/darker regions
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓▓▓▓░░▓▓▓▓▓▓░▓▓▓│
└────────────────┘

Colors:
- Base: #707070
- Light: #909090
- Dark: #505050
- Cracks: #404040
```

**Snow Tiles** (16×16):
```
┌────────────────┐
│████████████████│  White with subtle blue shadows
│███░░███████░███│  Slight sparkle hints
│████████████████│
│██████░░████████│
└────────────────┘

Colors:
- Base: #F0F0FF
- Highlight: #FFFFFF
- Shadow: #D0D0E8
- Sparkle: #FFFFFF (tiny bright pixels)
```

**Wall Tiles** (3/4 oblique - show top AND front):
```
WALL NORTH (facing camera):
┌────────────────┐
│████████████████│  ← Top surface (stone texture)
│████████████████│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  ← Front face (darker)
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
└────────────────┘
```

---

### Step 6.5: Set Up Tileset in Godot

**Create TileSet Resource**

**File**: `resources/tilesets/terrain_main.tres`

```gdscript
# In Godot Editor:
1. Create new TileSet resource
2. Add TileSetAtlasSource
3. Point to terrain_main.png
4. Set tile size: 16x16
5. For each tile, configure:
   - Physics (collision shapes for walls, water)
   - Terrain sets (for auto-tiling)
   - Custom data (tile_type, is_walkable, etc.)
```

---

### Step 6.6: Update LDTK Integration

**Modify**: `scripts/tools/ldtk_importer.gd` (if custom importer)

Ensure LDTK tileset references map to new Godot tileset:

```gdscript
# Map LDTK tileset IDs to Godot tilesets
var _tileset_map: Dictionary = {
    "terrain": preload("res://resources/tilesets/terrain_main.tres"),
    # Add more as needed
}


func _import_tile_layer(layer_data: Dictionary) -> TileMap:
    var tilemap = TileMap.new()

    var tileset_id = layer_data.get("__tilesetDefUid", "")
    tilemap.tile_set = _get_godot_tileset(tileset_id)

    # ... existing tile placement code ...

    return tilemap
```

---

### Step 6.7: Create Test Zone Map

**LDTK Work**: Create "The Clearing" test zone

**Layout** (20×15 tiles = 320×240 pixels):
```
┌────────────────────────────────────────┐
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  ▓ = Wall
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│  ░ = Grass/Snow floor
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░[CH]░░▓▓│  [CH] = Chest position
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│  [SP] = Spawn point
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│  [SL] = Slime spawn
│▓░░░░░░░░░░░░░░[SL]░░░░░░░░░░░░░░░░░░▓▓│  [TO] = Torch
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│  ═══ = Path
│▓░░░░[SP]░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓░░░░░░░░░░░════════════░░░░░░░[TO]░▓▓│
│▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
└────────────────────────────────────────┘

Entities to place:
- Player spawn point at [SP]
- Wooden chest at [CH]
- Slime enemy spawn at [SL]
- Torch (with light) at [TO]
```

**LDTK Layers**:
1. **Collision** (IntGrid): Wall=1, Floor=0
2. **Ground** (Tiles): Grass/snow base
3. **Decoration** (Tiles): Path, rocks, flowers
4. **Entities**: Spawn points, chests, torches

---

### Step 6.8: Create Test Scene

**File**: `scenes/test/test_world_objects.tscn`

```gdscript
# scenes/test/test_world_objects.gd
extends Node2D

@onready var chest: Node2D = $Chest
@onready var label: Label = $UI/Label

var items_to_drop = ["sword_iron", "potion_health", "armor_leather"]
var current_item = 0


func _ready() -> void:
    _update_label()


func _input(event: InputEvent) -> void:
    # Open chest
    if event.is_action_pressed("ui_accept"):
        if chest.has_method("open"):
            chest.open()

    # Spawn loot drop
    if event is InputEventKey and event.pressed and event.keycode == KEY_L:
        _spawn_loot()

    # Cycle rarity
    if event.is_action_pressed("ui_right"):
        current_item = (current_item + 1) % items_to_drop.size()
        _update_label()


func _spawn_loot() -> void:
    var loot = preload("res://scenes/interactable/loot_pickup.tscn").instantiate()
    loot.position = Vector2(240, 135) + Vector2(randf_range(-20, 20), randf_range(-20, 20))
    # Set item data here based on current_item
    add_child(loot)


func _update_label() -> void:
    label.text = "SPACE = Open chest\nL = Spawn loot\n→ = Cycle item\n\nCurrent: %s" % items_to_drop[current_item]
```

---

## VALIDATION CHECKLIST

After implementation, verify:

**Chests:**
- [ ] Chest renders with closed sprite
- [ ] Interacting opens chest (sprite changes)
- [ ] Open animation plays (scale bounce)
- [ ] Chest spawns loot when opened
- [ ] Highlight effect when player nearby

**Loot Drops:**
- [ ] Loot item renders with correct icon
- [ ] Common items have no glow
- [ ] Uncommon items have green glow
- [ ] Rare items have blue glow
- [ ] Epic items have purple glow
- [ ] Legendary items have orange glow + effect
- [ ] Loot bobs up and down
- [ ] Loot can be picked up

**Tileset:**
- [ ] Grass tiles render correctly
- [ ] Stone tiles render correctly
- [ ] Snow tiles render correctly
- [ ] Wall tiles show 3/4 perspective
- [ ] Path tiles connect properly
- [ ] Water has collision

**Test Zone:**
- [ ] Map loads without errors
- [ ] Player spawns at spawn point
- [ ] Can walk on floor tiles
- [ ] Walls block movement
- [ ] Chest is interactable
- [ ] Slime spawns and moves

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| Tiles look blurry | Texture filter not set to Nearest |
| Chest won't open | Interaction system not detecting |
| Loot invisible | Icon path wrong or texture not loading |
| Glow not showing | PointLight2D not enabled or energy=0 |
| Map loads wrong | LDTK tileset ID not mapped correctly |

---

## FILES CREATED THIS PHASE

```
assets/
├── sprites/
│   └── objects/
│       └── lootables/
│           ├── chest_wooden.png        ← USER CREATES
│           ├── chest_wooden_open.png   ← USER CREATES
│           ├── barrel.png              ← USER CREATES
│           └── urn.png                 ← USER CREATES
└── tilesets/
    └── terrain/
        └── terrain_main.png            ← USER CREATES

resources/
└── tilesets/
    └── terrain_main.tres               ← Configure in Editor

scripts/
└── interactable/
    ├── chest_base.gd                   ← MODIFIED
    └── loot_pickup.gd                  ← MODIFIED

scenes/
└── test/
    ├── test_world_objects.tscn
    └── test_world_objects.gd
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_7_LIGHTING_ATMOSPHERE.md` which adds:
- Normal map lighting for characters
- WorldEnvironment with glow/bloom
- Point lights for torches
- Snow particle system
- Atmospheric post-processing

---

## NOTES FOR IMPLEMENTER

- Keep tiles simple at first - can add detail later
- Auto-tiling in LDTK saves huge time for walls/terrain edges
- Loot glow uses PointLight2D - may need light texture (soft circle)
- Test zone is intentionally small - just enough to validate systems
- Consider adding more lootable variants later (corpse, crate, bookshelf)
- For better looking chests, consider 2-frame open animation instead of instant swap
