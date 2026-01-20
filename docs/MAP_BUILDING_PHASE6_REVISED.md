# Map Building Phase 6: Testing, Polish & Debug Tools (REVISED)

## Session Goal
Add comprehensive debug tools, performance tracking, edge case handling, and documentation to support the map system. You (the developer) will build the test zone in LDTK using existing database entities.

---

## Responsibility Split

### YOU (in LDTK):
- Create `zone_test_chunks` level (4x4 chunks = 4096x4096 px)
- Paint terrain using IntGrid layers
- Place entities using existing database entries:
  - SpawnPoints: starved wolves, skeleton archers
  - ChestSpawns: basic chests from database
  - LocationAreas: tie to database location IDs
  - PlayerSpawns: entry points
  - ZoneTransitions: if connecting to other zones

### CLAUDE (in code):
- Debug overlay visualization (chunk boundaries, states)
- Performance metrics tracking
- Stress test scripts
- Edge case handling (boundary combat, chunk corners)
- Enhanced debug commands
- Documentation updates

---

## LDTK Zone Building Guide

### Zone Specifications
```
Level Identifier: zone_test_chunks
Size: 4096 x 4096 px (4x4 chunks)
Chunk size: 1024 x 1024 px each
```

### Suggested Layout
```
┌─────────┬─────────┬─────────┬─────────┐
│ (0,0)   │ (1,0)   │ (2,0)   │ (3,0)   │
│ START   │ FOREST  │ FOREST  │ CAVE    │
│ safe    │ wolves  │ wolves  │ ENTRY   │
│ spawn   │ low     │ medium  │ trans   │
├─────────┼─────────┼─────────┼─────────┤
│ (0,1)   │ (1,1)   │ (2,1)   │ (3,1)   │
│ PATH    │ CLEAR   │ DENSE   │ ROCKY   │
│ mixed   │ ING     │ wolves+ │ skels   │
│ terrain │ grass   │ skels   │         │
├─────────┼─────────┼─────────┼─────────┤
│ (0,2)   │ (1,2)   │ (2,2)   │ (3,2)   │
│ MEADOW  │ LAKE    │ FOREST  │ RUINS   │
│ grass   │ water   │ EDGE    │ skels   │
│ wolves  │ empty   │ mixed   │ chests  │
├─────────┼─────────┼─────────┼─────────┤
│ (0,3)   │ (1,3)   │ (2,3)   │ (3,3)   │
│ CAMP    │ BRIDGE  │ RUINS   │ SHRINE  │
│ safe    │ narrow  │ chests  │ safe    │
│ no mobs │ path    │ skels   │ save pt │
└─────────┴─────────┴─────────┴─────────┘
```

### Entity Placement Guide

**SpawnPoints** (use existing database IDs):
| Location | Entity ID (from database) | Notes |
|----------|---------------------------|-------|
| (1,0) Forest | Your starved_wolf spawn ID | 2-3 wolves |
| (2,0) Forest | Your starved_wolf spawn ID | 3-4 wolves |
| (2,1) Dense | Wolf + skeleton spawn IDs | Mixed pack |
| (3,1) Rocky | skeleton_archer spawn ID | 2-3 archers |
| (0,2) Meadow | starved_wolf spawn ID | Light patrol |
| (3,2) Ruins | skeleton spawn ID | Guarding area |
| (2,3) Ruins | skeleton spawn ID | Near chests |

**ChestSpawns** (use existing database IDs):
| Location | Chest ID | Type |
|----------|----------|------|
| (1,0) Forest | chest_forest_1 | common |
| (3,2) Ruins | chest_ruins_1 | uncommon |
| (2,3) Ruins | chest_ruins_2 | uncommon |

**LocationAreas** (create matching database entries):
| Location ID | Covers Chunks | Database Entry Needed |
|-------------|---------------|----------------------|
| loc_test_start | (0,0) | is_safe_zone: true |
| loc_test_forest | (1,0), (2,0), (2,2) | discovery_popup: true |
| loc_test_ruins | (2,3), (3,2) | ambient: ruins |
| loc_test_shrine | (3,3) | is_safe_zone: true |

**PlayerSpawns**:
| Spawn ID | Position | Notes |
|----------|----------|-------|
| spawn_default | (0,0) center | Main entry |
| spawn_from_cave | (3,0) center | If adding cave zone |

**ZoneTransitions** (optional):
- From (3,0) to zone_test_cave if you want to test transitions

### Terrain IntGrid Values
```
1 = grass (walkable)
2 = dirt (walkable)
3 = stone (walkable)
4 = water (collision)
5 = wall (collision)
6 = sand (walkable)
7 = snow (walkable)
```

---

## Claude's Implementation Tasks

### 1. Debug Overlay System

Visual overlay showing chunk boundaries and states (toggle with F2):

```gdscript
# Features:
- Chunk grid lines
- Color-coded chunk states:
  - Green = LOADED
  - Red = COMBAT_LOCKED
  - Orange = LEASH_LOCKED
  - Yellow = LOADING
  - Gray = not loaded
- Chunk coordinates displayed
- Player chunk highlighted
```

### 2. Enhanced Debug Commands

```gdscript
# Keyboard shortcuts:
F1  = Print ChunkManager state snapshot
F2  = Toggle chunk overlay visualization
F3  = Print LootManager state
F4  = Print NPCManager/enemy state
F5  = Print performance metrics
F11 = Zone naming diagnostic (already done)
F12 = Zone resolution trace (already done)

# Console/code commands:
ChunkManager.debug_teleport_to_chunk(x, y)
ChunkManager.debug_force_unload_all()
ChunkManager.debug_print_perf()
```

### 3. Performance Metrics

```gdscript
# Track:
- Chunk load times (warn if > 50ms)
- Chunk unload times
- Peak loaded chunk count
- Entity spawn times
- Memory usage estimates
```

### 4. Stress Test Script

```gdscript
# Automated tests:
- Rapid chunk transitions (teleport around)
- Combat lock verification
- Loot persistence across chunk loads
- Save/load during various states
```

### 5. Edge Case Handling

```gdscript
# Handle:
- Player at chunk corner (overlapping 4 chunks)
- Enemy crossing chunk boundary mid-combat
- Save triggered during combat lock
- Rapid movement between chunks
```

### 6. Documentation Updates

- Complete MAP_BUILDING_REFERENCE.md workflow
- Add troubleshooting guide
- Update LDTK_SETUP_GUIDE.md with location workflow
- Create QUICK_REFERENCE.md for common debug commands

---

## Testing Checklist

### After LDTK Zone Built:
- [ ] Run ldtk_importer.gd
- [ ] Create zone_test_chunks.tscn scene
- [ ] Add Location Area2D nodes (matching LDTK positions)
- [ ] Test zone loads without errors

### Debug Tools Testing:
- [ ] F1 shows accurate state
- [ ] F2 overlay renders correctly
- [ ] F5 shows performance data
- [ ] Teleport commands work

### Functionality Testing:
- [ ] Walk through zone, chunks load/unload
- [ ] Enemies spawn at spawn points
- [ ] Combat lock prevents unload
- [ ] Loot persists across chunk loads
- [ ] Locations trigger enter/exit events
- [ ] Save/load works correctly

### Performance Testing:
- [ ] Chunk load time < 50ms
- [ ] No frame drops during transitions
- [ ] Memory stable over extended play

---

## Files Claude Will Modify

1. `autoloads/chunk_manager.gd` - Debug overlay, performance tracking
2. `autoloads/game_manager.gd` - Additional debug key bindings
3. `scripts/tools/chunk_stress_test.gd` - NEW: stress test script
4. `docs/MAP_BUILDING_REFERENCE.md` - Workflow documentation
5. `docs/LDTK_SETUP_GUIDE.md` - Location workflow
6. `docs/DEBUG_QUICK_REFERENCE.md` - NEW: debug command reference

---

## Success Criteria

- [ ] Debug overlay functional and accurate
- [ ] All debug commands working
- [ ] Performance metrics tracking
- [ ] Stress test passes
- [ ] Edge cases handled gracefully
- [ ] Documentation complete
- [ ] Test zone playable (after you build it in LDTK)
