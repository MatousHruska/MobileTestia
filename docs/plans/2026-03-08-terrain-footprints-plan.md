# Terrain System + Snow Footprints Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire up terrain types from LDtk through the chunk pipeline so any system can query terrain at a position, then use it to spawn fading footprint decals and snow puff particles when walking on snow.

**Architecture:** A `ground` IntGrid layer in LDtk maps terrain types. The importer exports them per-chunk. ChunkManager parses ground data into a Dictionary keyed by `Vector2i` for O(1) lookup and exposes `get_terrain_at(world_pos)`. A new `FootprintManager` autoload tracks player movement distance and spawns decal sprites + particle bursts on footprint-capable terrain.

**Tech Stack:** GDScript, LDtk IntGrid, chunk JSON, GPUParticles2D

---

### Task 1: Add ground layer extraction to LDtk importer

**Files:**
- Modify: `ldtk_importer.gd:268-302` (add ground to `_extract_chunk_tiles`)
- Modify: `ldtk_importer.gd` (add `_extract_ground_tiles` function)

**Context:** The importer processes LDtk layers in `_extract_chunk_tiles()`. Each IntGrid layer has its own extractor (e.g., `_extract_collision_tiles`, `_extract_interior_regions`). Ground follows the same pattern but maps int values to terrain IDs.

**Docs:** `docs/LDTK_MAP_REFERENCE.md` lines 291-310 defines the IntGrid value mapping.

**Step 1: Add ground to the result dict in `_extract_chunk_tiles()`**

In `_extract_chunk_tiles()` (line 270), add `"ground"` to the result:

```gdscript
var result := {
    "collision": [],
    "visual_tiles": [],
    "interior_regions": [],
    "roofs": [],
    "ground": []             # <-- ADD THIS
}
```

**Step 2: Add ground extraction to the layer match**

In the second pass `match layer_id:` block (line 294), add:

```gdscript
"ground":
    result.ground = _extract_ground_tiles(layer, bounds)
```

**Step 3: Add the `_extract_ground_tiles()` function**

Add after `_extract_collision_tiles()` (after line 336). Follows the exact same IntGrid pattern but maps values to terrain IDs:

```gdscript
func _extract_ground_tiles(layer: Dictionary, bounds: Rect2) -> Array:
    ## Extract ground/terrain type tiles within bounds.
    ## IntGrid values map to terrain IDs from terrain_types.json.
    var tiles: Array = []
    var grid_size: int = layer.get("__gridSize", 16)
    var c_wid: int = layer.get("__cWid", 0)
    var csv: Array = layer.get("intGridCsv", [])

    # IntGrid value -> terrain_id mapping (matches LDTK_MAP_REFERENCE.md)
    var value_to_terrain := {
        1: "terrain_grass",
        2: "terrain_dirt",
        3: "terrain_stone",
        4: "terrain_water",
        5: "terrain_wall",
        6: "terrain_sand",
        7: "terrain_snow",
        8: "terrain_void",
    }

    for i in range(csv.size()):
        var value: int = csv[i]
        if value == 0 or not value_to_terrain.has(value):
            continue

        var gx: int = i % c_wid
        var gy: int = int(i / c_wid)
        var px: float = gx * grid_size
        var py: float = gy * grid_size

        if not bounds.has_point(Vector2(px, py)):
            continue

        var local_x: int = int((px - bounds.position.x) / grid_size)
        var local_y: int = int((py - bounds.position.y) / grid_size)

        tiles.append({
            "x": local_x,
            "y": local_y,
            "terrain_id": value_to_terrain[value]
        })

    return tiles
```

**Step 4: Commit**

```
feat: extract ground terrain layer from LDtk IntGrid
```

**Manual step (user):** After this task, the user must add a `ground` IntGrid layer in the LDtk editor with values 1-8 matching the mapping above, then re-run the importer to generate updated chunk JSONs. The code works without this — chunks just have empty `"ground": []`.

---

### Task 2: Add terrain database fields for footprints

**Files:**
- Modify: `databases/vba/TerrainDatabase.bas`
- Modify: `databases/vba/MasterExport.bas` (if needed for schema changes)

**Context:** The terrain database already has 7 columns. We need to add `has_footprints` (bool) and `footprint_tint` (hex color string). Per CLAUDE.md, we provide updated `.bas` files and Excel-ready data — the user imports and runs ExportAll.

**Step 1: Update column constants in TerrainDatabase.bas**

Add after `COL_TT_CAN_SPAWN_ON` (line 18):

```vba
Private Const COL_TT_HAS_FOOTPRINTS As Integer = 8
Private Const COL_TT_FOOTPRINT_TINT As Integer = 9
```

**Step 2: Add validation for new fields in `ValidateTerrainTypes`**

After the `canSpawnOn` validation block (after line 103), add:

```vba
        ' Validate has_footprints is valid boolean
        Dim hasFootprints As String
        hasFootprints = LCase(Trim(ws.Cells(i, COL_TT_HAS_FOOTPRINTS).Value))
        If Len(hasFootprints) > 0 Then
            If hasFootprints <> "true" And hasFootprints <> "false" And _
               hasFootprints <> "1" And hasFootprints <> "0" And _
               hasFootprints <> "yes" And hasFootprints <> "no" Then
                LogValidationError errors, errorCount, i, "Has Footprints", _
                    "Must be TRUE or FALSE"
            End If
        End If

        ' Validate footprint_tint is hex format
        Dim footprintTint As String
        footprintTint = Trim(ws.Cells(i, COL_TT_FOOTPRINT_TINT).Value)
        If Len(footprintTint) > 0 Then
            If Left(footprintTint, 1) <> "#" Or Len(footprintTint) <> 7 Then
                LogValidationError errors, errorCount, i, "Footprint Tint", _
                    "Color must be hex format: #RRGGBB (e.g., #FFFFFF)"
            End If
        End If
```

**Step 3: Add export for new fields in `ExportTerrainTypesData`**

In the JSON output block (after line 168, after the `can_spawn_on` line), add:

```vba
        ' Handle boolean has_footprints field
        Dim hasFootprints2 As String
        hasFootprints2 = LCase(Trim(ws.Cells(i, COL_TT_HAS_FOOTPRINTS).Value))
        If hasFootprints2 = "true" Or hasFootprints2 = "1" Or hasFootprints2 = "yes" Then
            hasFootprints2 = "true"
        Else
            hasFootprints2 = "false"
        End If

        ' Change the can_spawn_on line to add trailing comma
        ' (line 168 currently has no comma — it's the last field)
```

Update the JSON output lines to include the new fields. The `can_spawn_on` line needs a trailing comma now. Replace the JSON block (lines 161-169) with:

```vba
        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_NAME))) & """," & vbCrLf
        json = json & "      ""placeholder_color"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_PLACEHOLDER_COLOR), "#808080")) & """," & vbCrLf
        json = json & "      ""has_collision"": " & hasCollision & "," & vbCrLf
        json = json & "      ""movement_cost"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TT_MOVEMENT_COST), 1)) & "," & vbCrLf
        json = json & "      ""footstep_sound"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_FOOTSTEP_SOUND))) & """," & vbCrLf
        json = json & "      ""can_spawn_on"": " & canSpawnOn & "," & vbCrLf
        json = json & "      ""has_footprints"": " & hasFootprints2 & "," & vbCrLf
        json = json & "      ""footprint_tint"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_FOOTPRINT_TINT), "#FFFFFF")) & """" & vbCrLf
        json = json & "    }"
```

**Step 4: Update `SetupTerrainTypesSheet` headers**

Update the headers array (line 193):

```vba
    headers = Array("id", "name", "placeholder_color", "has_collision", _
                    "movement_cost", "footstep_sound", "can_spawn_on", _
                    "has_footprints", "footprint_tint")
```

Add comments:

```vba
    SafeAddComment ws.Cells(1, 8), "TRUE/FALSE - Does this terrain leave footprint marks?"
    SafeAddComment ws.Cells(1, 9), "Hex color for footprint tint (#RRGGBB, e.g., #FFFFFF for snow)"
```

**Step 5: Provide Excel data for user to paste**

The user should add these two columns to the TerrainTypes sheet:

| id | has_footprints | footprint_tint |
|----|---------------|----------------|
| terrain_grass | FALSE | #3d6e3d |
| terrain_dirt | TRUE | #6b5344 |
| terrain_stone | FALSE | #666673 |
| terrain_water | FALSE | #334d99 |
| terrain_wall | FALSE | #4d4033 |
| terrain_sand | TRUE | #c4a35a |
| terrain_snow | TRUE | #e0e8f0 |
| terrain_void | FALSE | #1a1a1a |

**Step 6: Commit**

```
feat: add has_footprints and footprint_tint to terrain database
```

**Manual step (user):** Import updated .bas into Excel, paste column data, run ExportAll.

---

### Task 3: Add `get_terrain_at()` to ChunkManager

**Files:**
- Modify: `autoloads/chunk_manager.gd`

**Context:** Follows the same pattern as `get_interior_region_at_position()` (line 460) but uses a Dictionary keyed by `Vector2i` for O(1) lookup instead of linear scan. Ground data is stored when chunks load in `_create_chunk_tilemap()`.

**Step 1: Add terrain data storage variable**

After `_interior_region_data` declaration (line 143), add:

```gdscript
## Terrain type data per chunk: { chunk_id: Dictionary { Vector2i(x,y): String (terrain_id) } }
var _terrain_data: Dictionary = {}
```

**Step 2: Parse ground data in `_create_chunk_tilemap()`**

After the interior_regions storage block (after line 688), add:

```gdscript
# Store ground/terrain data for this chunk (used by FootprintManager etc.)
var ground_tiles: Array = tile_data.get("ground", [])
if not ground_tiles.is_empty():
    var terrain_lookup := {}
    for tile in ground_tiles:
        var key := Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
        terrain_lookup[key] = tile.get("terrain_id", "")
    _terrain_data[chunk_id] = terrain_lookup
    Debug.log("ChunkManager", "Stored %d terrain tiles for %s" % [ground_tiles.size(), chunk_id])
```

**Step 3: Add `get_terrain_at()` public API**

After `get_current_interior_region()` (after line 500), add:

```gdscript
## Get the terrain type ID at a world position.
## Returns terrain_id string (e.g., "terrain_snow") or "" if no terrain data.
func get_terrain_at(world_pos: Vector2) -> String:
    var chunk_coords := world_to_chunk(world_pos)
    var zone_name := current_zone_id
    if zone_name.begins_with("zone_"):
        zone_name = zone_name.substr(5)
    var chunk_id := "chunk_%s_%d_%d" % [zone_name, chunk_coords.x, chunk_coords.y]

    if not _terrain_data.has(chunk_id):
        return ""

    var chunk_origin := chunk_to_world(chunk_coords)
    var local_pos := world_pos - chunk_origin
    var tile_key := Vector2i(int(local_pos.x / TILE_SIZE), int(local_pos.y / TILE_SIZE))

    return _terrain_data[chunk_id].get(tile_key, "")
```

**Step 4: Clean up terrain data on chunk unload**

Find where `_interior_region_data` is erased on unload (search for `_interior_region_data.erase`). Add the same for `_terrain_data`:

```gdscript
_terrain_data.erase(chunk_id)
```

And in `cleanup_zone()`, add:

```gdscript
_terrain_data.clear()
```

**Step 5: Commit**

```
feat: add get_terrain_at() to ChunkManager for terrain queries
```

---

### Task 4: Create placeholder footprint texture

**Files:**
- Create: `assets/effects/footprint.png`

**Context:** A simple small footprint sprite. Can be generated programmatically as a placeholder — roughly 6×8 pixels, white silhouette of a boot print on transparent background. This will be tinted at runtime by `footprint_tint` from the terrain database.

**Step 1: Generate a placeholder footprint texture programmatically**

Create a tool script or inline code that generates and saves a small footprint image. The image should be:
- ~6×8 pixels
- White pixels on transparent background
- Rough boot/shoe print shape (a few pixels arranged to suggest a footprint)
- Saved to `res://assets/effects/footprint.png`

Simple pixel art approach — manually define pixel positions:

```gdscript
# Generator (run once from editor or tool script):
var img := Image.create(6, 8, false, Image.FORMAT_RGBA8)
img.fill(Color.TRANSPARENT)
# Left footprint silhouette (rough boot shape)
var pixels := [
    Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),           # toe
    Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),  # ball
    Vector2i(2, 2), Vector2i(3, 2),                             # arch gap
    Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),             # mid
    Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),             # mid
    Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),  # heel
    Vector2i(2, 6), Vector2i(3, 6),                             # heel bottom
]
for p in pixels:
    img.set_pixel(p.x, p.y, Color.WHITE)
img.save_png("res://assets/effects/footprint.png")
```

Alternatively, just create a small white oval/blob — it doesn't need to be detailed at 6×8px.

**Step 2: Commit**

```
feat: add placeholder footprint texture
```

---

### Task 5: Create FootprintManager autoload

**Files:**
- Create: `autoloads/footprint_manager.gd`
- Modify: `project.godot` (add autoload entry)

**Context:** This autoload tracks the player's movement and spawns footprint decals + snow puff particles on terrain that has `has_footprints: true`. It queries `ChunkManager.get_terrain_at()` and `DatabaseLoader.get_terrain_type()` to determine behavior.

**Step 1: Create the FootprintManager script**

```gdscript
extends Node
## FootprintManager — spawns fading footprint decals and step particles
## based on terrain type under the player's feet.

#===============================================================================
# CONSTANTS
#===============================================================================

## Distance in pixels between footprint spawns
const STEP_DISTANCE := 16.0

## How long footprints last before fully fading (seconds)
const FADE_DURATION := 8.0

## Horizontal offset from center for left/right foot alternation (pixels)
const FOOT_OFFSET := 3.0

## Maximum concurrent footprints (oldest freed if exceeded)
const MAX_FOOTPRINTS := 50

## Snow puff particle settings
const PUFF_PARTICLE_COUNT := 4
const PUFF_LIFETIME := 0.5

#===============================================================================
# STATE
#===============================================================================

## Cumulative distance since last footprint
var _distance_accumulated := 0.0

## Last player position (for distance tracking)
var _last_position := Vector2.ZERO

## Whether we've initialized the last position
var _tracking := false

## Alternates between left (false) and right (true) foot
var _right_foot := false

## Preloaded footprint texture
var _footprint_texture: Texture2D = null

## Active footprint count (for cleanup)
var _footprint_count := 0

## Reference to the world root node where decals are placed
var _world_root: Node2D = null

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    # Load footprint texture
    var tex_path := "res://assets/effects/footprint.png"
    if ResourceLoader.exists(tex_path):
        _footprint_texture = load(tex_path)


func _process(_delta: float) -> void:
    if not Game or not Game.is_player_valid():
        _tracking = false
        return

    var player_pos: Vector2 = Game.player.global_position

    if not _tracking:
        _last_position = player_pos
        _tracking = true
        return

    # Accumulate movement distance
    var moved := player_pos.distance_to(_last_position)
    if moved < 0.5:
        return  # Standing still or micro-jitter

    var move_dir := (_last_position.direction_to(player_pos))
    _distance_accumulated += moved
    _last_position = player_pos

    # Spawn footprint at each step interval
    while _distance_accumulated >= STEP_DISTANCE:
        _distance_accumulated -= STEP_DISTANCE
        _try_spawn_footprint(player_pos, move_dir)


#===============================================================================
# FOOTPRINT SPAWNING
#===============================================================================

func _try_spawn_footprint(pos: Vector2, direction: Vector2) -> void:
    # Query terrain at player feet
    var terrain_id := ChunkManager.get_terrain_at(pos)
    if terrain_id.is_empty():
        return

    var terrain_data: Dictionary = DatabaseLoader.get_terrain_type(terrain_id)
    if terrain_data.is_empty() or not terrain_data.get("has_footprints", false):
        return

    # Find world root (cache it)
    if _world_root == null or not is_instance_valid(_world_root):
        _world_root = _find_world_root()
        if _world_root == null:
            return

    # Parse tint color from terrain data
    var tint_hex: String = terrain_data.get("footprint_tint", "#FFFFFF")
    var tint := Color.from_string(tint_hex, Color.WHITE)
    tint.a = 0.6  # Start semi-transparent

    # Spawn decal
    _spawn_decal(pos, direction, tint)

    # Spawn particle puff
    _spawn_step_puff(pos, tint)


func _spawn_decal(pos: Vector2, direction: Vector2, tint: Color) -> void:
    if _footprint_texture == null:
        return

    # Enforce max footprints
    if _footprint_count >= MAX_FOOTPRINTS:
        _remove_oldest_footprint()

    var decal := Sprite2D.new()
    decal.texture = _footprint_texture
    decal.modulate = tint
    decal.z_index = -1  # Below characters

    # Position with left/right foot offset
    _right_foot = not _right_foot
    var perp := Vector2(-direction.y, direction.x)  # Perpendicular to movement
    var foot_offset := perp * (FOOT_OFFSET if _right_foot else -FOOT_OFFSET)
    decal.global_position = pos + foot_offset

    # Rotate to match movement direction
    decal.rotation = direction.angle() + PI / 2.0  # +90° because sprite points up

    # Flip x for right foot
    if _right_foot:
        decal.flip_h = true

    decal.add_to_group("footprints")
    _world_root.add_child(decal)
    _footprint_count += 1

    # Fade out and free
    var tween := decal.create_tween()
    tween.tween_property(decal, "modulate:a", 0.0, FADE_DURATION)
    tween.tween_callback(func() -> void:
        _footprint_count -= 1
        decal.queue_free()
    )


func _spawn_step_puff(pos: Vector2, tint: Color) -> void:
    var particles := GPUParticles2D.new()
    particles.emitting = false
    particles.amount = PUFF_PARTICLE_COUNT
    particles.lifetime = PUFF_LIFETIME
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.z_index = -1

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, -1, 0)  # Upward drift
    mat.spread = 45.0
    mat.initial_velocity_min = 8.0
    mat.initial_velocity_max = 15.0
    mat.gravity = Vector3(0, 10, 0)  # Slight downward pull
    mat.scale_min = 0.5
    mat.scale_max = 1.5
    mat.color = Color(tint.r, tint.g, tint.b, 0.5)
    particles.process_material = mat

    particles.global_position = pos
    _world_root.add_child(particles)
    particles.emitting = true

    # Auto-free after emission completes
    get_tree().create_timer(PUFF_LIFETIME + 0.1).timeout.connect(func() -> void:
        if is_instance_valid(particles):
            particles.queue_free()
    )


func _remove_oldest_footprint() -> void:
    var footprints := get_tree().get_nodes_in_group("footprints")
    if not footprints.is_empty():
        _footprint_count -= 1
        footprints[0].queue_free()


func _find_world_root() -> Node2D:
    # Find the world_root node inside the game viewport
    var dvp := get_node_or_null("/root/DualViewport")
    if dvp and dvp.has_method("get_world_root"):
        return dvp.get_world_root()
    # Fallback: look for world_root in scene tree
    var nodes := get_tree().get_nodes_in_group("world_root")
    if not nodes.is_empty():
        return nodes[0] as Node2D
    return null


#===============================================================================
# CLEANUP
#===============================================================================

## Clear all footprints (call on zone change)
func clear_footprints() -> void:
    for fp in get_tree().get_nodes_in_group("footprints"):
        fp.queue_free()
    _footprint_count = 0
    _tracking = false
    _distance_accumulated = 0.0
```

**Step 2: Register the autoload in project.godot**

Add after the EnvironmentManager line (line 51):

```
FootprintManager="*res://autoloads/footprint_manager.gd"
```

**Step 3: Commit**

```
feat: add FootprintManager autoload with decals and snow puff particles
```

---

### Task 6: Wire FootprintManager cleanup into zone lifecycle

**Files:**
- Modify: `autoloads/chunk_manager.gd` (or wherever zone cleanup happens)

**Context:** When the player changes zones, all footprints should be cleared. Find where `zone_cleanup` is emitted or where `cleanup_zone()` is called, and add `FootprintManager.clear_footprints()`.

**Step 1: Add cleanup call in `cleanup_zone()`**

In ChunkManager's `cleanup_zone()` function, after existing cleanup code, add:

```gdscript
var fp_mgr := get_node_or_null("/root/FootprintManager")
if fp_mgr:
    fp_mgr.clear_footprints()
```

**Step 2: Commit**

```
feat: clear footprints on zone cleanup
```

---

### Task 7: Verify end-to-end

**Step 1: Manual test checklist**

1. Add `ground` IntGrid layer in LDtk with snow tiles (value 7) painted over the test zone
2. Run the LDtk importer — verify chunk JSONs now have `"ground"` arrays
3. Update terrain database with `has_footprints` and `footprint_tint` columns, run ExportAll
4. Run the game, walk on snow — verify footprint decals appear behind player
5. Verify footprints alternate left/right and rotate with movement direction
6. Verify footprints fade out after ~8 seconds
7. Verify snow puff particles appear at each step
8. Walk on non-snow terrain (grass/stone) — verify NO footprints appear
9. Walk back to snow — verify footprints resume
10. Change zone — verify footprints are cleaned up

**Step 2: Final commit**

```
feat: terrain system with snow footprint decals and step particles
```
