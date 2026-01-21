# Debug Quick Reference

Quick reference for all debug tools and commands in MobileTestia.

---

## Debug Key Bindings (Numpad)

Press these numpad keys during gameplay (debug builds only). Uses numpad to avoid Godot editor conflicts (F1-F8):

| Key | System | Action |
|-----|--------|--------|
| **Numpad 1** | ChunkManager | Print state snapshot (loaded chunks, states) |
| **Numpad 2** | ChunkManager | Toggle visual overlay (chunk boundaries, colors) |
| **Numpad 3** | LootManager | Print tracked loot drops |
| **Numpad 4** | NPCManager | Print enemy summary (alive, dead, in combat) |
| **Numpad 5** | ChunkManager | Print performance metrics (load times) |
| **Numpad 6** | ChunkManager | Zone naming diagnostic (save/load debug) |
| **Numpad 7** | ChunkManager | Zone resolution trace |
| **Numpad 8** | GameManager | Full game state dump |
| **Numpad 9** | BuffSystem | Test ends_when buff system |

---

## Debug Overlay (Numpad 2)

Toggle visual chunk boundaries:

```
Chunk Colors:
- GREEN   = Loaded normally
- RED     = Combat locked (enemy targeting player)
- ORANGE  = Leash locked (enemy returning home FROM combat)
- YELLOW  = Loading
- WHITE   = Player's current chunk
- GRAY    = Not loaded

HUD shows: zone, player chunk, loaded count, enemies, locks, load time
```

**Note**: ORANGE (Leash) only appears when an enemy was **previously in combat** and is now returning to its home position. Enemies that are idle or roaming but never engaged do NOT show as leash-locked.

---

## Console Commands

### ChunkManager

```gdscript
# State inspection
ChunkManager.debug_print_state()              # Print loaded chunks
ChunkManager.debug_toggle_overlay()           # Toggle visual overlay
ChunkManager.debug_print_perf()               # Performance metrics
ChunkManager.debug_get_summary()              # Get summary dictionary

# Zone diagnostics
ChunkManager.debug_zone_naming_diagnostic()   # Full zone naming report
ChunkManager.debug_trace_zone_resolution()    # Save/load path trace
ChunkManager.debug_check_zone_naming()        # Quick true/false check

# Testing
ChunkManager.debug_teleport_to_chunk(x, y)    # Teleport to chunk center
ChunkManager.debug_force_unload_all()         # Force unload all chunks
ChunkManager.debug_reset_perf()               # Reset performance metrics
ChunkManager.run_stress_test()                # Quick automated stress test

# Entity debugging
ChunkManager.debug_show_chunk_borders(true)   # Show chunk borders
ChunkManager.debug_show_entities(true)        # Show entity markers
ChunkManager.debug_print_zone_entities()      # Print zone entity data
ChunkManager.debug_print_spawned_entities()   # Print spawned entities
ChunkManager.debug_list_enemies_in_chunk("chunk_id")  # List enemies
```

### GameManager

```gdscript
Game.print_state()                  # Quick state snapshot
Game.debug_full_state()             # Comprehensive state dump
Game.is_player_valid()              # Check player reference
Game.get_player_position()          # Get player position
```

### LocationManager

```gdscript
LocationManager.debug_print_state()           # Print current location info
LocationManager.is_in_location()              # Check if in any location
LocationManager.is_in_location_id("loc_id")   # Check specific location
LocationManager.is_current_area_safe()        # Check safe zone
```

### NPCManager

```gdscript
NPCManager.print_state()            # Print all NPC info (if available)
# Or use F4 for enemy summary
```

### Debug System

```gdscript
Debug.info("Category", "Message")           # Log info message
Debug.warn("Category", "Warning")           # Log warning
Debug.err("Category", "Error")              # Log error
Debug.snapshot("Category", "Title", data)   # Log data snapshot
```

---

## Common Debugging Workflows

### "Empty zone after loading save"

1. Press **Numpad 6** - Check zone naming
2. Look for MISMATCH in zone names
3. Fix: Scene's `zone_id` must match LDTK level identifier

### "Chunks not loading"

1. Press **Numpad 6** - Check section 6 (loaded chunks)
2. If 0 chunks, ChunkManager not initialized
3. Check zone scene calls `ChunkManager.initialize_for_zone()`

### "Enemies not appearing"

1. Press **Numpad 4** - Check enemy count
2. Press **Numpad 2** - Look for spawn point markers
3. Check database: spawn_point_id exists
4. Check Persistence: spawn not cleared

### "Chunk won't unload"

1. Press **Numpad 2** - Look for red (combat) or orange (leash)
2. Combat lock: Enemy still targeting player
3. Leash lock: Enemy returning to home position (only after being in combat)
4. Kill enemy or wait for it to reach home

### "All chunks show LEASH even when enemies not engaged"

1. This was a bug - LEASH should only show for enemies returning FROM combat
2. Check that `_is_enemy_returning_home()` only checks `BehaviorState.RETURNING`
3. Enemies idle or roaming should NOT trigger leash locks

### "Enemies spawn at wrong position (off by ~1024px)"

1. Check spawn_point.gd: `add_child()` must come BEFORE `global_position = ...`
2. Godot requires node to be in scene tree for `global_position` to work
3. Setting position before add_child only sets local position

### "Opening one chest makes all similar chests disappear"

1. Chest persistence must use unique keys: `chest_id@x,y`
2. Check that `_save_persistence()` uses `_get_persistence_key()` not `database_chest_id`
3. Multiple chests can share same database ID but need unique persistence keys

### "Slow chunk loading"

1. Press **Numpad 5** - Check avg/max load times
2. Target: < 50ms per chunk
3. Reduce tilemap complexity or enemy count
4. Check for resource loading bottlenecks

### "Save/load breaks game"

1. Press **Numpad 7** - Trace resolution path
2. Compare: Scene filename vs zone_id vs chunk files
3. All must derive from same base name

---

## Performance Targets

| Metric | Target | Warning |
|--------|--------|---------|
| Chunk load time | < 50ms | > 100ms |
| Loaded chunks | ~25 | > 30 |
| Enemies per zone | < 50 | > 100 |
| Frame time | < 16ms | > 33ms |

---

## Debug Output Locations

- **Console**: All Debug.* calls print to Godot console
- **Log file**: `user://logs/game.log` (if implemented)
- **Snapshots**: Stored in Debug system history

---

## Stress Testing

### Quick Test (in-game)
```gdscript
ChunkManager.run_stress_test()
```

### Comprehensive Test
Use `scripts/tools/chunk_stress_test.gd` with `ChunkStressTestRuntime` node.

Tests performed:
1. Rapid chunk transitions (teleport)
2. Boundary walking (chunk corners)
3. Loot persistence
4. Memory stability

---

## Tips

- **Numpad 2 is your friend** - Visual overlay shows most issues at a glance
- **Numpad 6 for save/load issues** - Always run when chunks don't load
- **Numpad 5 for performance** - Check before and after changes
- **Combine keys** - Numpad 2 + Numpad 5 = see overlay while checking performance
