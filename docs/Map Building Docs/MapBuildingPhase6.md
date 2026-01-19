# Map Building Phase 6: Testing, Polish & First Zone

## Session Goal
Build a complete test zone to validate the entire map system, add debug tools, optimize performance, and document the final workflow.

---

## Context

### Previous Phases Completed
- Phase 1: Database schema, autoload stubs
- Phase 2: ChunkManager core with combat/leash locks
- Phase 3: LootManager for drop persistence
- Phase 4: LDtk integration and tile rendering
- Phase 5: Entity integration and spawn system

### Current State
All systems should be functional. This phase focuses on:
1. End-to-end testing
2. Performance optimization
3. Debug tools
4. Building a real zone
5. Final documentation

---

## Tasks for This Phase

### 1. Build Test Zone in LDtk

Create a comprehensive test zone that exercises all features:

#### 1.1 Zone Specifications
```
Zone ID: zone_test_chunks
Size: 4x4 chunks (4096x4096 px)
Terrain variety: All terrain types
Enemy density: Varies by area
Locations: 3-4 named areas
```

#### 1.2 Test Zone Layout
```
┌─────────┬─────────┬─────────┬─────────┐
│ START   │ FOREST  │ FOREST  │ CAVE    │
│ safe    │ low     │ medium  │ entrance│
│ spawn   │ enemies │ enemies │ trans   │
├─────────┼─────────┼─────────┼─────────┤
│ PATH    │ CLEAR   │ DENSE   │ CAVE    │
│ mixed   │ ING     │ FOREST  │ interior│
│ terrain │ water   │ high    │ high    │
├─────────┼─────────┼─────────┼─────────┤
│ MEADOW  │ LAKE    │ FOREST  │ BOSS    │
│ grass   │ water   │ EDGE    │ ARENA   │
│ low     │ none    │ medium  │ mini-   │
│ enemies │ (empty) │         │ boss    │
├─────────┼─────────┼─────────┼─────────┤
│ CAMP    │ BRIDGE  │ RUINS   │ SHRINE  │
│ safe    │ narrow  │ stone   │ safe    │
│ NPCs    │ path    │ chests  │ save    │
└─────────┴─────────┴─────────┴─────────┘
```

#### 1.3 Test Features Per Chunk

| Chunk | Features to Test |
|-------|------------------|
| 0,0 (START) | Player spawn, safe zone, no enemies |
| 1,0 (FOREST) | Basic spawn points, grass terrain |
| 2,0 (FOREST) | Multiple spawn points, pack behavior |
| 3,0 (CAVE ENTRANCE) | Zone transition to cave, terrain change |
| 0,1 (PATH) | Mixed terrain types, movement costs |
| 1,1 (CLEARING) | Water collision, terrain edges |
| 2,1 (DENSE FOREST) | High enemy density, combat lock test |
| 3,1 (CAVE INTERIOR) | Dark lighting preset, different biome |
| 0,2 (MEADOW) | Open area, few enemies, loot test |
| 1,2 (LAKE) | Water body, no spawns, navigation |
| 2,2 (FOREST EDGE) | Location boundary test |
| 3,2 (BOSS ARENA) | Miniboss spawn, leash lock test |
| 0,3 (CAMP) | Safe zone, NPC placeholder |
| 1,3 (BRIDGE) | Narrow path, terrain variety |
| 2,3 (RUINS) | Chests, stone terrain |
| 3,3 (SHRINE) | Save point, safe zone |

#### 1.4 Entities to Place

**Spawn Points:**
- `sp_test_wolves_1` - Forest (1,0)
- `sp_test_wolves_2` - Forest (2,0)
- `sp_test_ghouls_1` - Dense Forest (2,1)
- `sp_test_ghouls_2` - Dense Forest (2,1)
- `sp_test_skeletons` - Ruins (2,3)
- `sp_test_miniboss` - Boss Arena (3,2) - unique enemy

**Chests:**
- `chest_forest_1` - Common, Forest (1,0)
- `chest_ruins_1` - Uncommon, Ruins (2,3)
- `chest_ruins_secret` - Rare, hidden in Ruins

**Transitions:**
- To `zone_test_cave` from Cave Entrance (3,0)
- Back to `zone_test_hub` from Start (0,0)

**Locations:**
- `loc_test_forest` - Covers forest chunks
- `loc_test_camp` - Covers camp area
- `loc_test_ruins` - Covers ruins area

**Player Spawns:**
- `spawn_default` - Start area (0,0)
- `spawn_from_cave` - Cave Entrance (3,0)

---

### 2. Create Debug Tools

#### 2.1 ChunkManager Debug Commands

Add to `chunk_manager.gd`:

```gdscript
## Debug commands for testing

func debug_print_state() -> void:
    Debug.snapshot("Chunk", "ChunkManager State", {
        "zone": current_zone_id,
        "player_chunk": player_chunk,
        "loaded_count": loaded_chunks.size(),
        "loaded_chunks": _get_loaded_chunk_summary(),
        "combat_locks": _get_combat_lock_count(),
        "leash_locks": _get_leash_lock_count(),
        "temp_enemy_states": _enemy_temp_states.size()
    })

func _get_loaded_chunk_summary() -> Array:
    var summary: Array = []
    for chunk_id in loaded_chunks:
        var chunk: ChunkData = loaded_chunks[chunk_id]
        summary.append({
            "id": chunk_id,
            "state": ChunkState.keys()[chunk.state],
            "enemies": _get_enemies_in_chunk(chunk_id).size()
        })
    return summary

func _get_combat_lock_count() -> int:
    var count := 0
    for chunk_id in loaded_chunks:
        if _has_combat_lock(chunk_id):
            count += 1
    return count

func _get_leash_lock_count() -> int:
    var count := 0
    for chunk_id in loaded_chunks:
        if _has_leash_lock(chunk_id):
            count += 1
    return count

func debug_teleport_to_chunk(x: int, y: int) -> void:
    ## Teleport player to center of specified chunk
    if not Game.is_player_valid():
        return
    var center := Vector2(
        (x + 0.5) * CHUNK_SIZE_PX,
        (y + 0.5) * CHUNK_SIZE_PX
    )
    Game.player.global_position = center
    Debug.info("Chunk", "Teleported to chunk (%d, %d)" % [x, y])

func debug_force_unload_all() -> void:
    ## Force unload all chunks (bypass safety)
    for chunk_id in loaded_chunks.keys():
        _force_unload_chunk(chunk_id)
    Debug.info("Chunk", "Force unloaded all chunks")

func debug_show_overlay(enabled: bool) -> void:
    ## Toggle chunk boundary visualization
    _debug_overlay_enabled = enabled
    queue_redraw()
```

#### 2.2 Visual Debug Overlay

```gdscript
var _debug_overlay_enabled := false

func _draw() -> void:
    if not _debug_overlay_enabled:
        return

    var viewport := get_viewport()
    var camera := viewport.get_camera_2d()
    if not camera:
        return

    var view_rect := Rect2(
        camera.global_position - viewport.get_visible_rect().size / 2,
        viewport.get_visible_rect().size
    )

    # Draw chunk grid
    var start_chunk := get_chunk_coords(view_rect.position)
    var end_chunk := get_chunk_coords(view_rect.end)

    for cx in range(start_chunk.x - 1, end_chunk.x + 2):
        for cy in range(start_chunk.y - 1, end_chunk.y + 2):
            var chunk_id := get_chunk_id(current_zone_id, Vector2i(cx, cy))
            var chunk_rect := Rect2(
                Vector2(cx, cy) * CHUNK_SIZE_PX,
                Vector2(CHUNK_SIZE_PX, CHUNK_SIZE_PX)
            )

            # Color based on state
            var color := Color.GRAY
            if loaded_chunks.has(chunk_id):
                var state: ChunkState = loaded_chunks[chunk_id].state
                match state:
                    ChunkState.LOADED:
                        color = Color.GREEN
                    ChunkState.COMBAT_LOCKED:
                        color = Color.RED
                    ChunkState.LEASH_LOCKED:
                        color = Color.ORANGE
                    ChunkState.LOADING:
                        color = Color.YELLOW

            color.a = 0.2
            draw_rect(chunk_rect, color)

            # Draw border
            draw_rect(chunk_rect, Color.WHITE, false, 2.0)

            # Draw chunk ID
            var font := ThemeDB.fallback_font
            var text_pos := chunk_rect.position + Vector2(8, 24)
            draw_string(font, text_pos, "(%d,%d)" % [cx, cy], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
```

#### 2.3 Console Commands

Add debug commands accessible from game console (if you have one) or keybinds:

```gdscript
# In a debug manager or Game autoload
func _input(event: InputEvent) -> void:
    if not OS.is_debug_build():
        return

    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_F1:
                ChunkManager.debug_print_state()
            KEY_F2:
                ChunkManager.debug_show_overlay(not ChunkManager._debug_overlay_enabled)
            KEY_F3:
                LootManager.debug_print_state()
            KEY_F4:
                NPCManager.print_state()
```

---

### 3. Performance Testing

#### 3.1 Performance Metrics

Add performance tracking to ChunkManager:

```gdscript
var _perf_chunk_load_times: Array[float] = []
var _perf_chunk_unload_times: Array[float] = []
var _perf_frame_times: Array[float] = []

func _load_chunk_with_perf(chunk_id: String) -> void:
    var start := Time.get_ticks_msec()
    load_chunk(chunk_id)
    var elapsed := Time.get_ticks_msec() - start
    _perf_chunk_load_times.append(elapsed)

    if elapsed > 50:  # Warn if load takes > 50ms
        Debug.warn("Chunk", "Slow chunk load: %s took %dms" % [chunk_id, elapsed])

func debug_print_perf() -> void:
    var avg_load := _array_average(_perf_chunk_load_times)
    var avg_unload := _array_average(_perf_chunk_unload_times)

    Debug.snapshot("Chunk", "Performance", {
        "avg_load_ms": avg_load,
        "max_load_ms": _perf_chunk_load_times.max() if not _perf_chunk_load_times.is_empty() else 0,
        "avg_unload_ms": avg_unload,
        "loaded_chunks": loaded_chunks.size(),
        "total_enemies": NPCManager.all_enemies.size()
    })
```

#### 3.2 Stress Test Scenarios

Create test scripts:

```gdscript
# scripts/tools/chunk_stress_test.gd
extends Node

func run_stress_test() -> void:
    print("=== Chunk Stress Test ===")

    # Test 1: Rapid chunk transitions
    print("Test 1: Rapid transitions...")
    for i in range(50):
        ChunkManager.debug_teleport_to_chunk(randi() % 4, randi() % 4)
        await get_tree().process_frame

    ChunkManager.debug_print_perf()

    # Test 2: Combat lock with many enemies
    print("Test 2: Combat lock...")
    ChunkManager.debug_teleport_to_chunk(2, 1)  # Dense forest
    await get_tree().create_timer(2.0).timeout
    # Walk away, verify lock holds
    ChunkManager.debug_teleport_to_chunk(0, 0)
    ChunkManager.debug_print_state()

    # Test 3: Loot persistence
    print("Test 3: Loot persistence...")
    LootManager.debug_spawn_test_loot(Vector2(500, 500))
    ChunkManager.debug_teleport_to_chunk(3, 3)
    await get_tree().create_timer(1.0).timeout
    ChunkManager.debug_teleport_to_chunk(0, 0)
    LootManager.debug_print_state()

    print("=== Stress Test Complete ===")
```

---

### 4. Edge Case Handling

#### 4.1 Chunk Boundary Combat

Handle enemies that cross chunk boundaries:

```gdscript
func _get_enemy_chunk(enemy: Node2D) -> String:
    var coords := get_chunk_coords(enemy.global_position)
    return get_chunk_id(current_zone_id, coords)

func _handle_enemy_chunk_change(enemy: Node2D, old_chunk: String, new_chunk: String) -> void:
    # Enemy moved between chunks
    # If old chunk was only kept loaded for this enemy, recheck unload
    if old_chunk != new_chunk:
        call_deferred("_recheck_chunk_unload", old_chunk)
```

#### 4.2 Player at Chunk Corner

Handle player standing at corner of 4 chunks:

```gdscript
func _get_all_player_chunks() -> Array[String]:
    ## Get all chunks the player overlaps (could be 1-4 chunks at corners)
    var player_pos := Game.player.global_position
    var player_radius := 16.0  # Player collision radius

    var chunks: Array[String] = []
    var corners := [
        player_pos + Vector2(-player_radius, -player_radius),
        player_pos + Vector2(player_radius, -player_radius),
        player_pos + Vector2(-player_radius, player_radius),
        player_pos + Vector2(player_radius, player_radius),
    ]

    for corner in corners:
        var chunk_id := get_chunk_id(current_zone_id, get_chunk_coords(corner))
        if chunk_id not in chunks:
            chunks.append(chunk_id)

    return chunks
```

#### 4.3 Save During Combat Lock

```gdscript
# In SaveManager or ChunkManager
func prepare_for_save() -> void:
    ## Release all locks and clean up before save
    # Force all enemies to their spawn points
    for enemy in NPCManager.all_enemies:
        if is_instance_valid(enemy):
            enemy.global_position = enemy.home_position

    # Clear temp states
    clear_enemy_temp_states()

    # Clear loot
    LootManager.clear_all_drops()
```

---

### 5. Final Workflow Documentation

#### 5.1 Update MAP_BUILDING_REFERENCE.md

Add final workflow section:

```markdown
## Complete Workflow

### Creating a New Zone

1. **Design in LDtk**
   - Create new level in MobileTestia.ldtk
   - Set level identifier (becomes zone_id)
   - Paint terrain on Ground layer
   - Add collision on Collision layer
   - Place entities (spawn points, chests, transitions)
   - Define location areas

2. **Export from LDtk**
   - File > Save Project
   - JSON files auto-generated

3. **Run Importer in Godot**
   - Open Script: scripts/tools/ldtk_importer.gd
   - Script > Run
   - Check Output panel for errors

4. **Update Databases**
   - Add zone entry to Zones sheet in Excel
   - Add location entries to Locations sheet
   - Add spawn point configs to SpawnPoints sheet
   - Run ExportAll macro

5. **Create Zone Scene**
   - Create scenes/world/zone_{id}.tscn
   - Add ZoneBase root node
   - Set zone_id export variable
   - Place Location Area2D nodes (use exported positions)
   - Test in editor

6. **Test In-Game**
   - Run game
   - Use debug overlay (F2) to verify chunks
   - Test all spawn points
   - Verify transitions work
   - Check loot persistence
```

#### 5.2 Create Troubleshooting Guide

```markdown
## Troubleshooting

### Chunks Not Loading
- Check zone_id matches database
- Verify ChunkManager.initialize_for_zone() called
- Check chunk JSON files exist in maps/chunk_tiles/

### Enemies Not Spawning
- Verify spawn_point_id matches database
- Check Persistence - is spawn cleared?
- Enable debug overlay to see spawn point locations

### Combat Lock Not Working
- Verify enemy has behavior component
- Check enemy.behavior.has_target() returns true
- Ensure enemy is in correct chunk bounds

### Loot Disappearing
- Check LootManager.debug_print_state()
- Verify loot_drop_id meta is set on pickup nodes
- Confirm chunk_loaded signal fires on reload

### Performance Issues
- Check ChunkManager.debug_print_perf()
- Reduce enemy count per chunk
- Verify chunks are unloading (not accumulating)
```

---

## Files to Reference

Before starting:
- All previous phase implementations
- `docs/MAP_BUILDING_REFERENCE.md`
- `docs/ZONE_DESIGN_GUIDE.md`
- Existing test zones in scenes/world/

---

## Deliverables

1. **Test Zone**
   - LDtk file with zone_test_chunks
   - All exported JSON files
   - Zone scene file
   - Database entries

2. **Debug Tools**
   - ChunkManager debug commands
   - Visual overlay
   - Performance tracking
   - Stress test script

3. **Documentation Updates**
   - Complete workflow in MAP_BUILDING_REFERENCE.md
   - Troubleshooting guide
   - Updated QUICK_REFERENCE.md

4. **Edge Case Fixes**
   - Chunk boundary handling
   - Save preparation

---

## Success Criteria

- [ ] Test zone fully playable
- [ ] All 16 chunks load/unload correctly
- [ ] All entity types spawn properly
- [ ] Combat lock prevents premature unload
- [ ] Leash lock works correctly
- [ ] Loot persists across chunk loads
- [ ] Zone transitions work
- [ ] Debug overlay shows accurate state
- [ ] Performance acceptable (<50ms chunk load)
- [ ] No memory leaks on extended play
- [ ] Save/load works cleanly
- [ ] Documentation complete and accurate

---

## Final Testing Checklist

### Functionality
- [ ] Walk through entire zone, all chunks load
- [ ] Leave area, chunks unload
- [ ] Return to area, chunks reload
- [ ] Enemies spawn at spawn points
- [ ] Kill enemy, loot drops
- [ ] Leave and return, loot persists
- [ ] Pick up loot, removed from manager
- [ ] Save game, loot cleared
- [ ] Combat lock holds chunk during fight
- [ ] Enemy returns to leash, chunk stays until arrived
- [ ] Zone transition works
- [ ] Location enter/exit triggers

### Performance
- [ ] Chunk load time <50ms
- [ ] No frame drops during chunk transitions
- [ ] Memory stable over 10+ minutes
- [ ] 25 chunks loaded simultaneously OK

### Edge Cases
- [ ] Player at chunk corner
- [ ] Enemy crosses chunk boundary
- [ ] Save during combat
- [ ] Rapid movement between chunks
- [ ] Zone exit and re-entry
