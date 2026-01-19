# Map Building Phase 5: Entity Integration & Spawn System

## Session Goal
Connect the chunk system with existing spawn points, transitions, and other entities. Ensure enemies spawn correctly when chunks load and despawn cleanly when chunks unload.

---

## Context

### Previous Phases Completed
- Phase 1: Database schema, autoload stubs
- Phase 2: ChunkManager core with combat/leash locks
- Phase 3: LootManager for drop persistence
- Phase 4: LDtk integration and tile rendering

### Current State
- Chunks load/unload based on player position
- Tiles render from LDtk data
- Entities extracted from LDtk but not yet spawned at runtime

### Reference Documentation
- `docs/MAP_BUILDING_REFERENCE.md` - Spawn Points section
- `docs/ENEMY_REFERENCE.md` - Enemy spawn system
- `scripts/npc/spawn_point.gd` - Current spawn point implementation

---

## Tasks for This Phase

### 1. Understand Current Spawn System

Read and understand the existing spawn point system:
- `scripts/npc/spawn_point.gd` - EnemySpawnPoint class
- `autoloads/npc_manager.gd` - Spawn point tracking
- `autoloads/persistence_manager.gd` - Spawn cleared states

Current flow:
```
Zone loads → SpawnPoint._ready() → Registers with NPCManager
                                → Checks Persistence for cleared state
                                → Spawns enemies if not cleared
```

New flow with chunks:
```
Chunk loads → ChunkManager creates SpawnPoint nodes from data
           → SpawnPoint._ready() → Same as before
Chunk unloads → SpawnPoint._exit_tree() → Unregisters
             → Enemies despawned (with temp state saved)
```

---

### 2. Update ChunkManager Entity Spawning

Add entity spawning to `autoloads/chunk_manager.gd`:

#### 2.1 Entity Data Storage

```gdscript
## Entity data extracted from LDtk (loaded once at zone init)
var _zone_entities: Dictionary = {}  # zone_id -> entities data

func _load_zone_entities(zone_id: String) -> void:
    var path := "res://maps/entities/%s.json" % zone_id
    if FileAccess.file_exists(path):
        var file := FileAccess.open(path, FileAccess.READ)
        var json := JSON.new()
        if json.parse(file.get_as_text()) == OK:
            _zone_entities[zone_id] = json.data
        file.close()
```

#### 2.2 Entity Spawning on Chunk Load

```gdscript
const SpawnPointScene := preload("res://scenes/npc/enemy_spawn_point.tscn")
const ZoneTransitionScene := preload("res://scenes/world/zone_transition.tscn")
const ChestSpawnScene := preload("res://scenes/interactable/chest_spawn.tscn")

func _spawn_chunk_entities(chunk_id: String, chunk_node: Node2D) -> void:
    var chunk_data: ChunkData = loaded_chunks[chunk_id]
    var chunk_bounds := _get_chunk_bounds(chunk_data.coords)

    var zone_ents: Dictionary = _zone_entities.get(current_zone_id, {})

    # Spawn enemy spawn points
    for sp_data in zone_ents.get("spawn_points", []):
        var pos := Vector2(sp_data.position.x, sp_data.position.y)
        if chunk_bounds.has_point(pos):
            _spawn_spawn_point(sp_data, chunk_node, chunk_bounds.position)

    # Spawn chests
    for chest_data in zone_ents.get("chests", []):
        var pos := Vector2(chest_data.position.x, chest_data.position.y)
        if chunk_bounds.has_point(pos):
            _spawn_chest(chest_data, chunk_node, chunk_bounds.position)

    # Spawn zone transitions
    for trans_data in zone_ents.get("transitions", []):
        var pos := Vector2(trans_data.position.x, trans_data.position.y)
        if chunk_bounds.has_point(pos):
            _spawn_transition(trans_data, chunk_node, chunk_bounds.position)

func _spawn_spawn_point(data: Dictionary, parent: Node2D, chunk_origin: Vector2) -> void:
    var sp_id: String = data.get("id", "")
    if sp_id.is_empty():
        return

    # Get spawn point config from database
    var sp_config: Dictionary = DatabaseLoader.get_spawn_point(sp_id)
    if sp_config.is_empty():
        Debug.warn("Chunk", "Unknown spawn point: %s" % sp_id)
        return

    var spawn_point: Node2D
    if SpawnPointScene:
        spawn_point = SpawnPointScene.instantiate()
    else:
        # Create programmatically if no scene
        spawn_point = _create_spawn_point_node(sp_config)

    # Set position relative to chunk
    var world_pos := Vector2(data.position.x, data.position.y)
    spawn_point.position = world_pos - chunk_origin

    # Configure from database
    spawn_point.spawn_point_id = sp_id
    if data.has("group"):
        spawn_point.spawn_group = data.group

    # Mark as chunk-spawned for proper cleanup
    spawn_point.set_meta("chunk_spawned", true)
    spawn_point.set_meta("chunk_id", _get_chunk_id_for_position(world_pos))

    parent.add_child(spawn_point)
    Debug.log("Chunk", "Spawned spawn point: %s" % sp_id)
```

#### 2.3 Entity Cleanup on Chunk Unload

```gdscript
func _cleanup_chunk_entities(chunk_id: String) -> void:
    var chunk_data: ChunkData = loaded_chunks.get(chunk_id)
    if not chunk_data or not chunk_data.node:
        return

    # Enemies are handled separately (with temp state saving)
    # SpawnPoints, chests, transitions are just freed with chunk node
    # They will be recreated when chunk loads again
```

---

### 3. Update SpawnPoint for Chunk Awareness

Modify `scripts/npc/spawn_point.gd`:

#### 3.1 Chunk Integration

```gdscript
## Called when spawned by ChunkManager
func setup_from_chunk(sp_id: String, config: Dictionary) -> void:
    spawn_point_id = sp_id

    # Apply database config
    enemy_pool = config.get("enemy_pool", "")
    min_level = config.get("min_level", 1)
    max_level = config.get("max_level", 1)
    max_active_enemies = config.get("max_active_enemies", 1)
    respawn_time = config.get("respawn_time", 60)
    spawn_radius = config.get("spawn_radius", 32)
    spawn_group = config.get("spawn_group", "")
    can_respawn = config.get("can_respawn", true)

    # Quest conditions
    require_quest_active = config.get("require_quest_active", "")
    require_quest_completed = config.get("require_quest_completed", "")
    disable_after_quest = config.get("disable_after_quest", "")
    disable_during_quest = config.get("disable_during_quest", "")

    # Module injection
    modules_to_inject = config.get("modules_to_inject", "")
    module_config_override = config.get("module_config_override", {})
```

#### 3.2 Enemy State Restoration

```gdscript
func _ready() -> void:
    # Existing registration code...

    # Check if ChunkManager has saved enemy states for this spawn point
    if has_meta("chunk_spawned") and ChunkManager:
        var saved_states: Array = ChunkManager.get_enemy_states_for_spawn(spawn_point_id)
        if not saved_states.is_empty():
            _restore_enemies_from_states(saved_states)
            return  # Don't do normal spawn

    # Normal spawn logic
    _check_and_spawn()

func _restore_enemies_from_states(states: Array) -> void:
    for state in states:
        var enemy := _spawn_single_enemy()
        if enemy:
            enemy.global_position = state.position
            enemy.current_health = enemy.max_health * state.health_percent
            # Don't restore combat state - let AI re-evaluate
```

---

### 4. Update ChunkManager Enemy State Management

Enhance temp state storage in `chunk_manager.gd`:

```gdscript
## Enemy states saved when chunks unload
var _enemy_temp_states: Dictionary = {}  # spawn_point_id -> Array[EnemyTempState]

class EnemyTempState:
    var enemy_id: String
    var spawn_point_id: String
    var position: Vector2
    var health_percent: float
    var home_position: Vector2

func save_enemy_states_for_chunk(chunk_id: String) -> void:
    var enemies := _get_enemies_in_chunk(chunk_id)

    for enemy in enemies:
        if enemy.is_dead:
            continue

        var sp_id: String = enemy.get_meta("spawn_point_id", "")
        if sp_id.is_empty():
            continue

        var state := EnemyTempState.new()
        state.enemy_id = enemy.enemy_id
        state.spawn_point_id = sp_id
        state.position = enemy.global_position
        state.health_percent = enemy.get_health_percent()
        state.home_position = enemy.home_position

        if not _enemy_temp_states.has(sp_id):
            _enemy_temp_states[sp_id] = []
        _enemy_temp_states[sp_id].append(state)

    Debug.log("Chunk", "Saved %d enemy states for chunk %s" % [enemies.size(), chunk_id])

func get_enemy_states_for_spawn(spawn_point_id: String) -> Array:
    var states: Array = _enemy_temp_states.get(spawn_point_id, [])
    _enemy_temp_states.erase(spawn_point_id)  # Clear after retrieval
    return states

func clear_enemy_temp_states() -> void:
    _enemy_temp_states.clear()
```

---

### 5. Zone Transition Integration

Update zone transitions to work with chunks:

```gdscript
# In ChunkManager._spawn_transition()
func _spawn_transition(data: Dictionary, parent: Node2D, chunk_origin: Vector2) -> void:
    var transition: Area2D
    if ZoneTransitionScene:
        transition = ZoneTransitionScene.instantiate()
    else:
        transition = _create_transition_node()

    var world_pos := Vector2(data.position.x, data.position.y)
    transition.position = world_pos - chunk_origin

    transition.target_zone = "res://scenes/world/%s.tscn" % data.target_zone
    transition.spawn_point_id = data.target_spawn

    # Set collision shape size
    var size := Vector2(data.size.w, data.size.h)
    var shape := transition.get_node("CollisionShape2D")
    if shape and shape.shape is RectangleShape2D:
        shape.shape.size = size

    transition.set_meta("chunk_spawned", true)
    parent.add_child(transition)
```

---

### 6. Chest Spawn Integration

```gdscript
func _spawn_chest(data: Dictionary, parent: Node2D, chunk_origin: Vector2) -> void:
    var chest_id: String = data.get("id", "")
    var chest_type: String = data.get("type", "common")

    # Check persistence - is chest already looted?
    if Persistence.is_chest_looted(chest_id):
        return  # Don't spawn looted chests

    var chest: Node2D
    if ChestSpawnScene:
        chest = ChestSpawnScene.instantiate()
    else:
        chest = _create_chest_node()

    var world_pos := Vector2(data.position.x, data.position.y)
    chest.position = world_pos - chunk_origin

    chest.chest_id = chest_id
    chest.chest_type = chest_type

    chest.set_meta("chunk_spawned", true)
    parent.add_child(chest)
```

---

### 7. Location Area Integration

Location areas should NOT be chunk-spawned - they exist at the zone level. However, we need to export their data for reference:

```gdscript
# Update LDtk importer to export location areas to locations.json format
# These are used by LocationManager, not ChunkManager

func _export_locations_from_ldtk(zone_id: String, locations: Array) -> void:
    var location_entries: Array = []

    for loc in locations:
        location_entries.append({
            "id": loc.id,
            "zone_id": zone_id,
            "name": loc.id.replace("loc_", "").replace("_", " ").capitalize(),
            "location_type": "poi",
            "is_safe_zone": null,
            "is_pvp_enabled": null,
            "status_effect_id": "",
            "music_track": "",
            "ambient_sound": "",
            "discovery_popup": true,
            "description": "",
            # Position data for scene placement
            "_editor_x": loc.position.x,
            "_editor_y": loc.position.y,
            "_editor_w": loc.size.w,
            "_editor_h": loc.size.h
        })

    # Merge with existing locations.json or create new
```

---

### 8. Player Spawn Integration

Player spawns are used by the zone transition system:

```gdscript
func _register_player_spawns(zone_id: String, spawns: Array) -> void:
    # Store player spawn positions for zone
    # Used by Game.change_zone() to position player

    for spawn in spawns:
        var spawn_id: String = spawn.id
        var position := Vector2(spawn.position.x, spawn.position.y)

        # Register with zone or a spawn registry
        # The zone_base.gd will use this when spawning player
```

---

### 9. Debug Visualization

Add entity debug overlay:

```gdscript
func debug_show_entities(enabled: bool) -> void:
    _show_entity_debug = enabled
    queue_redraw()

func _draw() -> void:
    if not _show_entity_debug:
        return

    # Draw spawn point locations
    for chunk_id in loaded_chunks:
        var chunk: ChunkData = loaded_chunks[chunk_id]
        for sp in _get_spawn_points_in_chunk(chunk_id):
            var color := Color.RED if sp.is_active else Color.GRAY
            draw_circle(sp.global_position, 8, color)

    # Draw transition areas
    # Draw chest locations
```

---

## Files to Reference

Before starting, read these files:
- `autoloads/chunk_manager.gd` - Your Phase 2-4 implementation
- `scripts/npc/spawn_point.gd` - Current spawn point system
- `scripts/world/zone_transition.gd` - Zone transition system
- `scripts/interactable/chest_spawn_point.gd` - Chest spawning
- `autoloads/persistence_manager.gd` - State persistence

---

## Deliverables

1. Updated `autoloads/chunk_manager.gd`:
   - Entity spawning on chunk load
   - Enemy state save/restore
   - Spawn point, chest, transition creation

2. Updated `scripts/npc/spawn_point.gd`:
   - Chunk awareness
   - State restoration from ChunkManager

3. Updated LDtk importer:
   - Entity export to separate JSON
   - Location area handling

4. Debug visualization for entities

---

## Success Criteria

- [ ] Spawn points created when chunk loads
- [ ] Enemies spawn from chunk-created spawn points
- [ ] Enemy states saved when chunk unloads
- [ ] Enemy states restored when chunk reloads
- [ ] Chests spawn correctly (and respect persistence)
- [ ] Zone transitions work from chunk-spawned nodes
- [ ] Location areas exported for manual scene placement
- [ ] Debug overlay shows entity positions
- [ ] No duplicate spawns on chunk reload

---

## Testing Scenarios

1. **Basic Spawn**: Load chunk, verify enemies spawn
2. **Chunk Reload**: Unload chunk, reload, verify enemies restore
3. **Damaged Enemy**: Damage enemy, leave chunk, return, verify health preserved
4. **Persistence**: Kill enemy, save, reload, verify stays dead
5. **Chest**: Loot chest, leave chunk, return, verify chest gone
6. **Transition**: Use zone transition from chunk-spawned node
7. **Combat Lock**: Verify enemies don't despawn mid-combat
