# Map Building Phase 2: Chunk System Core

## Session Goal
Implement the core chunk loading/unloading system with combat lock and leash lock safety mechanisms.

---

## Context

### Previous Phase Completed
Phase 1 established:
- Database schema for chunks and terrain types (VBA files)
- ChunkManager and LootManager autoload stubs
- DatabaseLoader extensions for chunk/terrain data

### Key Specifications
- Chunk size: 64x64 tiles (1024x1024 px)
- Loading radius: 5x5 chunks (25 loaded at once)
- Chunks unload only when safe (combat lock, leash lock)

### Reference Documentation
- `docs/MAP_BUILDING_REFERENCE.md` - Full technical spec
- `docs/QUICK_REFERENCE.md` - Quick reference

---

## Tasks for This Phase

### 1. Implement ChunkManager Core Logic

Update `autoloads/chunk_manager.gd` with full implementation:

#### 1.1 Constants and State
```gdscript
const TILE_SIZE := 16
const CHUNK_TILES := 64
const CHUNK_SIZE_PX := TILE_SIZE * CHUNK_TILES  # 1024
const LOADING_RADIUS := 2  # Results in 5x5 grid

enum ChunkState { UNLOADED, LOADING, LOADED, COMBAT_LOCKED, LEASH_LOCKED, UNLOADING }

var current_zone_id: String = ""
var loaded_chunks: Dictionary = {}  # chunk_id -> ChunkData
var player_chunk: Vector2i = Vector2i.ZERO
var _chunk_root: Node2D = null  # Parent for chunk nodes
```

#### 1.2 Chunk Coordinate Functions
```gdscript
func get_chunk_coords(world_pos: Vector2) -> Vector2i
func get_chunk_id(zone_id: String, coords: Vector2i) -> String
func get_world_position(coords: Vector2i) -> Vector2
func get_chunks_in_radius(center: Vector2i, radius: int = LOADING_RADIUS) -> Array[Vector2i]
```

#### 1.3 Zone Initialization
```gdscript
func initialize_for_zone(zone_id: String) -> void:
    # Clear existing chunks
    # Set current_zone_id
    # Create _chunk_root node
    # Load initial chunks around spawn point
```

#### 1.4 Chunk Update Loop
```gdscript
func _process(delta: float) -> void:
    # Skip if no zone or no player
    # Get player position
    # Calculate player's current chunk
    # If chunk changed, update loaded chunks

func update_chunks(player_position: Vector2) -> void:
    var new_chunk := get_chunk_coords(player_position)
    if new_chunk != player_chunk:
        player_chunk = new_chunk
        _refresh_loaded_chunks()

func _refresh_loaded_chunks() -> void:
    var desired_chunks := get_chunks_in_radius(player_chunk)

    # Load new chunks
    for coords in desired_chunks:
        var chunk_id := get_chunk_id(current_zone_id, coords)
        if chunk_id not in loaded_chunks:
            load_chunk(chunk_id)

    # Unload distant chunks (if safe)
    for chunk_id in loaded_chunks.keys():
        var chunk_coords := _get_coords_from_id(chunk_id)
        if chunk_coords not in desired_chunks:
            if can_chunk_unload(chunk_id):
                unload_chunk(chunk_id)
```

#### 1.5 Chunk Loading/Unloading
```gdscript
func load_chunk(chunk_id: String) -> void:
    # Get chunk data from DatabaseLoader
    # Create chunk container node
    # Emit signal for spawn points to activate
    # Mark as LOADED

func unload_chunk(chunk_id: String) -> void:
    # Save enemy states to temp storage
    # Notify LootManager to preserve loot data
    # Free chunk nodes
    # Remove from loaded_chunks
```

#### 1.6 Safety Lock System

```gdscript
func can_chunk_unload(chunk_id: String) -> bool:
    # Check combat lock
    if _has_combat_lock(chunk_id):
        return false
    # Check leash lock
    if _has_leash_lock(chunk_id):
        return false
    return true

func _has_combat_lock(chunk_id: String) -> bool:
    # Get all enemies in this chunk
    # Check if any are targeting player (has_target and target is player)
    for enemy in _get_enemies_in_chunk(chunk_id):
        if enemy.behavior and enemy.behavior.has_target():
            if enemy.behavior.get_target() == Game.player:
                return true
    return false

func _has_leash_lock(chunk_id: String) -> bool:
    # Check if any enemies are returning to home position
    for enemy in _get_enemies_in_chunk(chunk_id):
        if _is_enemy_returning_home(enemy):
            return true
    return false

func _is_enemy_returning_home(enemy: Node2D) -> bool:
    # Enemy is returning if:
    # - Has no target (lost aggro)
    # - Is not at home position
    # - Is moving toward home
    if enemy.behavior and not enemy.behavior.has_target():
        var dist_to_home := enemy.global_position.distance_to(enemy.home_position)
        if dist_to_home > 16.0:  # Not at home yet
            return true
    return false
```

#### 1.7 Enemy Tracking Per Chunk
```gdscript
func _get_enemies_in_chunk(chunk_id: String) -> Array:
    var chunk_coords := _get_coords_from_id(chunk_id)
    var chunk_bounds := Rect2(
        get_world_position(chunk_coords),
        Vector2(CHUNK_SIZE_PX, CHUNK_SIZE_PX)
    )

    var enemies: Array = []
    for enemy in NPCManager.all_enemies:
        if is_instance_valid(enemy) and not enemy.is_dead:
            if chunk_bounds.has_point(enemy.global_position):
                enemies.append(enemy)
    return enemies
```

---

### 2. Implement Chunk State Machine

Create internal ChunkData class or dictionary structure:

```gdscript
class ChunkData:
    var chunk_id: String
    var coords: Vector2i
    var state: ChunkState
    var node: Node2D  # Container for chunk content
    var enemy_temp_states: Array  # Saved enemy states for reload
    var load_time: float  # When chunk was loaded
```

State transitions:
```
UNLOADED → LOADING → LOADED
LOADED → COMBAT_LOCKED (enemy targeting player)
LOADED → LEASH_LOCKED (enemy returning home)
COMBAT_LOCKED → LOADED (enemy dies or loses target)
LEASH_LOCKED → LOADED (enemy reaches home)
LOADED → UNLOADING → UNLOADED (when outside radius and safe)
```

---

### 3. Integrate with Zone System

Update `scripts/world/zone_base.gd`:

```gdscript
func _ready() -> void:
    # Existing code...

    # Initialize chunk system for this zone
    if ChunkManager:
        ChunkManager.initialize_for_zone(zone_id)
```

Add to zone cleanup:
```gdscript
func _exit_tree() -> void:
    if ChunkManager:
        ChunkManager.cleanup_zone()
```

---

### 4. Add Signals

ChunkManager signals for other systems to react:

```gdscript
signal chunk_loading(chunk_id: String)
signal chunk_loaded(chunk_id: String)
signal chunk_unloading(chunk_id: String)
signal chunk_unloaded(chunk_id: String)
signal chunk_state_changed(chunk_id: String, old_state: ChunkState, new_state: ChunkState)
```

---

### 5. Temp Enemy State Storage

When chunk unloads, save enemy states:

```gdscript
var _enemy_temp_storage: Dictionary = {}  # chunk_id -> Array[EnemyState]

class EnemyTempState:
    var enemy_id: String
    var spawn_point_id: String
    var position: Vector2
    var health_percent: float
    var was_in_combat: bool

func _save_enemy_states(chunk_id: String) -> void:
    var states: Array = []
    for enemy in _get_enemies_in_chunk(chunk_id):
        var state := EnemyTempState.new()
        state.enemy_id = enemy.enemy_id
        state.spawn_point_id = enemy.get_meta("spawn_point_id", "")
        state.position = enemy.global_position
        state.health_percent = enemy.get_health_percent()
        state.was_in_combat = enemy.behavior.has_target() if enemy.behavior else false
        states.append(state)
    _enemy_temp_storage[chunk_id] = states

func _restore_enemy_states(chunk_id: String) -> void:
    # Called after chunk loads
    # SpawnPoints check this storage before spawning fresh
    pass
```

---

### 6. Debug Tools

Add debug methods:

```gdscript
func debug_print_state() -> void:
    Debug.snapshot("Chunk", "ChunkManager State", {
        "zone": current_zone_id,
        "player_chunk": player_chunk,
        "loaded_count": loaded_chunks.size(),
        "chunks": loaded_chunks.keys()
    })

func debug_force_unload(chunk_id: String) -> void:
    # Bypass safety checks for testing

func debug_show_chunk_borders(enabled: bool) -> void:
    # Visual debug overlay showing chunk boundaries
```

---

## Files to Reference

Before starting, read these files:
- `autoloads/chunk_manager.gd` - Your Phase 1 stub
- `autoloads/npc_manager.gd` - Enemy tracking patterns
- `autoloads/location_manager.gd` - Similar update patterns
- `scripts/world/zone_base.gd` - Zone initialization
- `scripts/npc/enemy_npc.gd` - Enemy state (home_position, behavior)
- `scripts/npc/modules/mod_leash.gd` - Leash behavior reference

---

## Deliverables

1. Fully implemented `autoloads/chunk_manager.gd`:
   - Chunk coordinate calculations
   - 5x5 loading radius management
   - Combat lock detection
   - Leash lock detection
   - Enemy temp state storage
   - Signals for other systems

2. Updated `scripts/world/zone_base.gd`:
   - ChunkManager initialization
   - Cleanup on exit

3. Debug tools for testing

---

## Success Criteria

- [ ] ChunkManager tracks player chunk position correctly
- [ ] Chunks load when player approaches
- [ ] Chunks unload when player leaves (and safe)
- [ ] Combat lock prevents unload while enemy targets player
- [ ] Leash lock prevents unload while enemy returns home
- [ ] Enemy states saved on unload, restored on reload
- [ ] Debug tools work for testing
- [ ] No performance issues with 25 chunks loaded
- [ ] Integrates with existing zone system without breaking it

---

## Testing Scenarios

1. **Basic Loading**: Walk around, verify chunks load/unload
2. **Combat Lock**: Engage enemy, walk away, verify chunk stays loaded
3. **Leash Lock**: Aggro enemy, run past leash, verify chunk stays until enemy returns
4. **Chunk Boundary**: Fight enemy on chunk boundary, verify no issues
5. **Zone Transition**: Leave zone, return, verify clean state
