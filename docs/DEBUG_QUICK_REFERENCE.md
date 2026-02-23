# Debug Quick Reference

Quick reference for all debug tools and commands in MobileTestia.

---

## Debug Menu (HUD Eye Icon)

All debug actions are available through the **debug menu**, accessible via the **eye icon (👁)** button next to the hamburger menu (☰) in the top-right corner of the HUD.

The debug menu is **only visible in debug builds** and provides tappable buttons organized into sections:

### Overlays (toggles)
| Button | What it does |
|--------|-------------|
| Chunk Borders | Toggle visual overlay showing chunk boundaries and colors |
| AI Debug | Toggle AI debug panel showing nearest 5 enemies, states, flags |
| Quest Debug | Toggle quest debug panel showing active quests, objectives, event log |
| Pathfinding | Toggle pathfinding grid visualization |

### Snapshots (print to console)
| Button | What it does |
|--------|-------------|
| Chunk State | Print loaded chunks, their states, enemy counts |
| Loot State | Print tracked loot drops and timeout settings |
| Enemy Summary | Print alive/dead/in-combat enemy counts |
| Chunk Perf | Print avg/max load/unload times, peak counts |
| Game State | Full game state dump (GameState, paused, player, zone, UI) |
| Chest Persistence | Print all tracked chest states with timestamps |
| Debug Settings | Print current log level, verbose flags, disabled categories |

### Diagnostics
| Button | What it does |
|--------|-------------|
| Zone Naming | Zone name mismatch diagnostic for save/load issues |
| Zone Resolution | Trace zone resolution path through save/load cycle |
| Test Pathfinding | Test pathfinding from player position |
| Test ends_when Buff | Apply a test buff that ends when player heals to full |

### Log Settings
| Button | What it does |
|--------|-------------|
| Cycle Log Level | Toggle between INFO and DEBUG log levels |
| All Verbose | Toggle all verbose modes (NPC, chunks, spawn, saveload) |
| NPC Verbose | Toggle NPC movement spam specifically |

---

## Debug Overlay (Chunk Borders)

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

## Pathfinding Debug

Toggle the pathfinding overlay to visualize navigation grid and blocked tiles.

| Key | Action |
|-----|--------|
| **L** | Cycle navigation layer view (All → Ground → Flying → Jumping → Ghost) |

```
Layer Colors (blocked tiles):
- ALL LAYERS: Shows walkability for all movement types
- GROUND:     Red = blocked for ground enemies
- FLYING:     Blue = blocked for flying enemies
- JUMPING:    Green = blocked for jumping enemies
- GHOST:      Purple = blocked for ghost enemies (only walls)

Grid shows 16x16 tile cells with blocked tiles highlighted.
```

**When to use:**
- Debugging enemy pathfinding issues
- Verifying terrain is set up correctly
- Checking which tiles specific enemy types can traverse

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
```

### Debug System

```gdscript
# Standard logging (respects log_level)
Debug.info("Category", "Message")           # Log info message (always shown at INFO+)
Debug.log("Category", "Message")            # Log debug message (shown at DEBUG+)
Debug.warn("Category", "Warning")           # Log warning
Debug.err("Category", "Error")              # Log error
Debug.snapshot("Category", "Title", data)   # Log data snapshot

# Verbose logging (respects verbose flags, independent of log_level)
Debug.log_verbose("npc", "Category", "Msg") # Only if verbose_npc is true
Debug.print_saveload("[SAVELOAD] ...")      # Only if verbose_saveload is true
Debug.print_chunk("[ChunkDebug] ...")       # Only if verbose_chunks is true
Debug.print_spawn("[SPAWN] ...")            # Only if verbose_spawn is true

# Runtime control
Debug.set_level(Debug.LogLevel.DEBUG)       # Change log level
Debug.verbose_npc = true                    # Enable NPC movement spam
Debug.verbose_chunks = true                 # Enable chunk loading details
Debug.verbose_spawn = true                  # Enable spawn point details
Debug.verbose_saveload = true               # Enable save/load tracing
```

---

## Common Debugging Workflows

### "Empty zone after loading save"

1. Open debug menu → **Zone Naming** diagnostic
2. Look for MISMATCH in zone names
3. Fix: Scene's `zone_id` must match LDTK level identifier

### "Chunks not loading"

1. Open debug menu → **Zone Naming** (check section 6 for loaded chunks)
2. If 0 chunks, ChunkManager not initialized
3. Check zone scene calls `ChunkManager.initialize_for_zone()`

### "Enemies not appearing"

1. Open debug menu → **Enemy Summary** - Check enemy count
2. Open debug menu → Toggle **Chunk Borders** - Look for spawn point markers
3. Check database: spawn_point_id exists
4. Check Persistence: spawn not cleared

### "Chunk won't unload"

1. Toggle **Chunk Borders** - Look for red (combat) or orange (leash)
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

1. Open debug menu → **Chunk Perf** - Check avg/max load times
2. Target: < 50ms per chunk
3. Reduce tilemap complexity or enemy count
4. Check for resource loading bottlenecks

### "Save/load breaks game"

1. Open debug menu → **Zone Resolution** - Trace resolution path
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

- **Chunk Borders overlay is your friend** - Visual overlay shows most issues at a glance
- **Zone Naming for save/load issues** - Always run when chunks don't load
- **Chunk Perf for performance** - Check before and after changes
- **Combine overlays** - Chunk Borders + Chunk Perf = see overlay while checking performance
