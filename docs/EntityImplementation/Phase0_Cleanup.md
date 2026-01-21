# Phase 0: Legacy Cleanup

---

## Session Start Notes

**Opening prompt for this session:**

```
Please pull [BRANCH_NAME]

This is the newest version of the codebase. Clone it and add [PHASE_NAME] into its name. We will continue our work from here.

Some notes for this session:

CRITICAL: Database Workflow
NEVER EDIT .json FILES DIRECTLY!

The database is managed through Excel with VBA macros. Direct JSON edits will be overwritten.

Correct workflow:

First: Provide updated .bas VBA files for any schema changes
Second: Provide Excel-ready data to paste into sheets
Third: User imports VBA, pastes data, runs ExportAll

When you need to change database structure or data:

Give me the .bas file updates (if schema changes)
Give me tab-separated or table data ready to paste into Excel
I will import/paste and export the JSON myself

IMPORTANT: When changing database schema, always update:

The specific database .bas file (e.g., EnemyDatabase.bas)
MasterExport.bas (ExportAll, ValidateAll, SetupWorkbook functions)
SharedValidation.bas (named ranges, foreign key validations, enum validations)

VBA Naming Convention: Export functions should be named ExportXxxData where Xxx matches the sheet name (e.g., ExportAbilitiesData, ExportEnemyAbilitiesData).

When writing data for a database, be careful about "," and "." characters. If it is incorrectly written, .json files won't work, so always use ".".

Whenever you make an update to stats, add a new stat, create a new way of implementing it, check the StatDescriptionDatabase, and update the appropriate Stat Description.

When creating any layout design choices always prefer dynamic percentual edits against fixed pixels.

When designing various elements (texts, containers, UI) always read UIThemeDatabase where style classes are defined. No text in the game should be classless. No UI wireframe classless.

When planning new features and systems remember that we already have save/load system and implement these into this framework.

When creating or editing enemies, their behaviour or AI consult ENEMY_REFERENCE.md, ABILITY_SYSTEM_REFERENCE.md and QUICK_REFERENCE.md

When working with maps and LDTK consult LDTK_MAP_REFERENCE.md and ZONE_DESIGN_GUIDE.md
```

---

**Goal**: Remove all hardcoded interactables that would conflict with the new database-driven entity system.

---

## Overview

Before implementing the new database-driven entity system, we must remove legacy hardcoded doors, levers, and manually-placed NPCs from zone scenes. This prevents:

1. Duplicate entities (scene + database)
2. Persistence ID conflicts
3. Broken cross-zone references
4. Inconsistent behavior between zones

---

## Legacy Items to Remove

### 1. Doors (3 total)

| Zone | Node Name | Persistence ID | Details |
|------|-----------|----------------|---------|
| `zone_forest.tscn` | OldWoodenDoor | `forest_secret_door` | Key: `key_old_wooden`, in SecretRoom |
| `zone_meadow.tscn` | SecretGateDoor | `meadows_lever_door` | `lever_controlled=true` |
| `zone_crypt.tscn` | (None found) | - | Door referenced but not in scene |

**Files to edit:**
- `scenes/world/zone_forest.tscn` - Lines ~191-198
- `scenes/world/zone_meadow.tscn` - Lines ~139-144

### 2. Levers (1 total)

| Zone | Node Name | Persistence ID | Linked Door |
|------|-----------|----------------|-------------|
| `zone_crypt.tscn` | CryptLever | `crypt_lever_meadows` | `meadows_lever_door` (cross-zone) |

**Files to edit:**
- `scenes/world/zone_crypt.tscn` - Lines ~66-72

### 3. NPCs (Manual Placements)

| Zone | Node Name | Database ID | Notes |
|------|-----------|-------------|-------|
| `zone_test_hub.tscn` | QuestGiver | `npc_quest_giver_main` | Keep for now (hub zone) |
| `test_zone.tscn` | QuestGiver | `npc_quest_giver_main` | Duplicate, remove |

**Decision**: Keep hub NPCs for now since hub zones may not use chunk-based loading. Remove from test_zone.

---

## Reserved Persistence IDs

These IDs are currently in use and MUST be migrated to database entries (not reused with different meanings):

```
DOORS:
- "forest_secret_door"     → door_forest_secret
- "meadows_lever_door"     → door_meadow_gate

LEVERS:
- "crypt_lever_meadows"    → lever_crypt_to_meadow

MISC (Zone Triggers):
- "zone_trigger_*"         → Keep pattern for TriggerAreas
```

---

## Cleanup Checklist

### Step 1: Document Current State
- [ ] Screenshot/record current door/lever positions in LDtk or notepad
- [ ] Note persistence IDs for migration to database
- [ ] List linked door-lever relationships

### Step 2: Remove Scene Nodes
- [ ] `zone_forest.tscn`: Remove OldWoodenDoor node
- [ ] `zone_meadow.tscn`: Remove SecretGateDoor node
- [ ] `zone_crypt.tscn`: Remove CryptLever node
- [ ] `test_zone.tscn`: Remove QuestGiver node (duplicate)

### Step 3: Clean Up Empty Containers
- [ ] Remove empty "Interactables" Node2D if no children remain
- [ ] Remove empty "FriendlyNPCs" Node2D if no children remain

### Step 4: Verify No Broken References
- [ ] Search for `get_node("*Door*")` or similar paths in scripts
- [ ] Search for hardcoded persistence ID strings
- [ ] Verify no scripts directly reference removed nodes

### Step 5: Create Migration Database Entries
After cleanup, create placeholder entries in databases for:
- [ ] `door_forest_secret` (key-locked door)
- [ ] `door_meadow_gate` (lever-controlled door)
- [ ] `lever_crypt_to_meadow` (one-shot lever)

---

## Scripts to Review for Hardcoded References

### unlockable_door.gd
```gdscript
# Current: Uses hardcoded NodePath for lever reference
@export var linked_lever: NodePath  # REMOVE - will use database linking

# Keep: These work with database system
@export var persistence_id: String
@export var required_key_id: String
@export var lever_controlled: bool
```

### lever.gd
```gdscript
# Current: Uses NodePath for same-scene door
@export var linked_door: NodePath  # REMOVE - will use database linking
@export var linked_nodes: Array[NodePath]  # REMOVE - will use database

# Keep: Cross-zone linking via persistence
@export var linked_door_id: String  # Rename to linked_entity_id in new system
```

---

## Persistence System Updates

### New Categories Needed
Add to `persistence_manager.gd` CATEGORIES constant:

```gdscript
const CATEGORIES := [
    "doors",
    "levers",
    "chests",
    "enemies",
    "spawn_points",
    "quests",
    "npcs",
    "escort_npcs",
    "status_effects",
    "misc",
    # NEW:
    "plates",        # Pressure plates
    "lootables",     # Quick loot containers
    "signs",         # Readable signs (tracks "read" state)
    "echoes",        # Lore echoes (tracks "listened" state)
    "triggers"       # Trigger areas (tracks "fired" state)
]
```

---

## Edge Cases to Handle

### 1. Existing Save Files
Players with existing saves have persistence data for legacy IDs. Options:
- **Option A**: Keep legacy IDs in database (recommended)
- **Option B**: Add migration logic in save_manager

**Recommendation**: Use the same persistence IDs in database entries so existing saves work.

### 2. Cross-Zone Loading Order
When loading a save:
1. Persistence is restored first
2. Zone loads second
3. Entities spawn and read Persistence

This order is correct - no changes needed.

### 3. Chunk Boundary Entities
What if a door/lever visual spans chunk boundaries?
- Entity position = center point
- Only ONE chunk "owns" the entity
- Collision/interaction extends into adjacent chunks naturally

---

## Verification Steps After Cleanup

1. **Start New Game**: Verify zones load without errors
2. **Check Console**: No "node not found" errors
3. **Walk Through Zones**: No visual glitches where entities were
4. **Save/Load Test**: Verify old saves still load (even if doors missing)
5. **Persistence Check**: `Numpad 1` should show empty doors/levers categories

---

## Files Modified in This Phase

| File | Action |
|------|--------|
| `scenes/world/zone_forest.tscn` | Remove OldWoodenDoor |
| `scenes/world/zone_meadow.tscn` | Remove SecretGateDoor |
| `scenes/world/zone_crypt.tscn` | Remove CryptLever |
| `scenes/world/test_zone.tscn` | Remove duplicate QuestGiver |
| `autoloads/persistence_manager.gd` | Add new categories |

---

## Success Criteria

- [ ] All zone scenes load without hardcoded doors/levers
- [ ] No console errors about missing nodes
- [ ] Persistence categories ready for new entities
- [ ] Legacy persistence IDs documented for database migration
- [ ] Game starts and plays normally (without doors/levers temporarily)

---

## Next Phase

After cleanup is complete, proceed to **Phase 1: Database Foundation** to create the VBA database schemas for all new entity types.
