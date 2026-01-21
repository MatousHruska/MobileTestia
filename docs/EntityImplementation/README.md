# Entity Implementation Plan

Database-driven entity system for MobileTestia using LDtk + ChunkManager.

---

## Overview

This document series describes the implementation of a unified, database-driven entity system. All interactable world objects will:

1. Be defined in databases (Excel/VBA → JSON)
2. Be placed in LDtk as spawn markers with database IDs
3. Be spawned by ChunkManager when chunks load
4. Persist state via PersistenceManager
5. Support cross-zone interactions

---

## Entity Types

| Entity | Purpose | Interaction |
|--------|---------|-------------|
| **Door** | Block passage | Key/Lever/Quest unlock |
| **Lever** | Toggle switch | Click to toggle |
| **PressurePlate** | Floor trigger | Step on/off |
| **NPC** | Characters | Dialogue/Shop/Quest |
| **Lootable** | Quick loot (corpses, urns) | Click = drops items |
| **Sign** | Readable text | Click = floating dialogue |
| **LoreEcho** | Audio lore | Click = plays audio |
| **TriggerArea** | Event trigger | Walk into = fires event |

---

## Phases

### [Phase 0: Cleanup](Phase0_Cleanup.md)
Remove legacy hardcoded interactables to prevent conflicts.

**Key Tasks:**
- Remove hardcoded doors from zone scenes
- Remove hardcoded levers from zone scenes
- Document existing persistence IDs
- Add new persistence categories

**Files Modified:**
- `zone_forest.tscn`, `zone_meadow.tscn`, `zone_crypt.tscn`
- `persistence_manager.gd`

---

### [Phase 1: Database Foundation](Phase1_DatabaseFoundation.md)
Create VBA database modules for all new entity types.

**Key Tasks:**
- Create 7 new VBA modules
- Update MasterExport.bas
- Update SharedValidation.bas
- Create initial test data

**New Files:**
- `DoorDatabase.bas`
- `LeverDatabase.bas`
- `PressurePlateDatabase.bas`
- `LootableDatabase.bas`
- `SignDatabase.bas`
- `LoreEchoDatabase.bas`
- `TriggerAreaDatabase.bas`

---

### [Phase 2: LDtk Integration](Phase2_LDtkIntegration.md)
Add entity definitions in LDtk and update the importer.

**Key Tasks:**
- Define 8 new entity types in LDtk
- Update ldtk_importer.gd extraction
- Update zone entity JSON format

**Files Modified:**
- `MobileTestia.ldtk`
- `ldtk_importer.gd`

---

### [Phase 3: Access Control Entities](Phase3_AccessControlEntities.md)
Implement Doors, Levers, and Pressure Plates.

**Key Tasks:**
- Update door script for database loading
- Update lever script for database loading
- Create pressure plate script
- Add ChunkManager spawn methods
- Implement cross-zone linking via persistence

**Files Modified:**
- `unlockable_door.gd`
- `lever.gd`
- `chunk_manager.gd`
- `database_loader.gd`

**New Files:**
- `pressure_plate.gd`

---

### [Phase 4: NPCs](Phase4_NPCs.md)
Implement NPC spawning via ChunkManager.

**Key Tasks:**
- Add NPC spawning to ChunkManager
- Handle quest-conditional spawning
- Integrate with existing DatabaseNPC

**Files Modified:**
- `chunk_manager.gd`
- `NPCDatabase.bas` (add spawn_condition field)

---

### [Phase 5: Lootables & Signs](Phase5_LootablesAndSigns.md)
Implement quick-loot containers and readable signs.

**Key Tasks:**
- Create Lootable script
- Create Sign script
- Add ChunkManager spawn methods
- Integrate with LootManager and FloatingDialogueManager

**New Files:**
- `lootable.gd`
- `sign.gd`

---

### [Phase 6: LoreEchoes & TriggerAreas](Phase6_LoreEchosAndTriggerAreas.md)
Implement audio lore objects and event triggers.

**Key Tasks:**
- Create LoreEcho script (audio stub)
- Create TriggerArea script
- Add ChunkManager spawn methods
- Integrate with CutsceneManager, QuestManager

**New Files:**
- `lore_echo.gd`
- `trigger_area.gd`

---

## Architecture

### Data Flow

```
Excel Databases
      ↓ VBA Export
JSON Files (databases/exports/)
      ↓ DatabaseLoader
Runtime Dictionaries
      ↓
LDtk Level Design
      ↓ ldtk_importer.gd
Zone Entity JSON (maps/entities/)
      ↓
ChunkManager Spawning
      ↓
Entity Instances
      ↓
PersistenceManager (state)
      ↓
SaveManager (save/load)
```

### Persistence Strategy

All entities use position-qualified persistence keys:
```
{database_id}@{x},{{y}
Example: door_forest_secret@400,200
```

This allows multiple instances of the same database entry at different positions.

### Cross-Zone Linking

Entities in different zones communicate via Persistence:

1. Lever in Zone A saves door state: `Persistence.save_state("doors", "door_id", {is_locked: false})`
2. Door in Zone B loads state on spawn: `Persistence.load_state("doors", "door_id")`
3. Result: Lever controls door across zones

---

## Persistence Categories

```gdscript
const CATEGORIES := [
    "doors",        # Door locked state
    "levers",       # Lever on/off state
    "chests",       # Chest opened state (existing)
    "enemies",      # Boss kill tracking (existing)
    "spawn_points", # Cleared spawn points (existing)
    "quests",       # Quest progress (existing)
    "npcs",         # NPC-specific state
    "escort_npcs",  # Escort quest state (existing)
    "status_effects", # Player buffs (existing)
    "misc",         # Catch-all (existing)
    "plates",       # Pressure plate state
    "lootables",    # Lootable looted state
    "signs",        # Sign read state
    "echoes",       # LoreEcho listened state
    "triggers"      # TriggerArea fired state
]
```

---

## Implementation Order

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
  |          |          |          |          |          |          |
Cleanup   Database   LDtk      Access    NPCs    Loot/    Echo/
Legacy     VBA      Import    Control           Signs   Trigger
```

**Estimated Sessions:** 4-6 sessions depending on testing thoroughness

---

## Critical Considerations

### 1. Persistence ID Collisions
- Always use position-qualified keys for chunk-spawned entities
- Reserve simple IDs (e.g., "door_forest_secret") for unique entities

### 2. Chunk Boundary Entities
- Entity position determines which chunk "owns" it
- Collision/interaction naturally extends beyond chunk boundaries

### 3. Save Compatibility
- Legacy saves will have empty new categories
- Entities default to "not interacted" state

### 4. Cross-Zone Timing
- Lever saves state immediately
- Door reads state only on spawn
- Order doesn't matter due to persistence

### 5. Hub Zones
- Hub NPCs may remain manually placed
- Or use ChunkManager with all chunks loaded

---

## Testing Strategy

Each phase includes specific test checklists. Key integration tests:

1. **Door/Lever Cross-Zone**: Lever in Zone A unlocks door in Zone B
2. **Save/Load Cycle**: All entity states preserved
3. **Chunk Unload/Reload**: Entities restore correctly
4. **Quest Conditions**: Conditional spawning works
5. **Performance**: Many entities don't degrade performance

---

## Related Documentation

- [LDTK_MAP_REFERENCE.md](../LDTK_MAP_REFERENCE.md) - Technical map system reference
- [ZONE_DESIGN_GUIDE.md](../ZONE_DESIGN_GUIDE.md) - Zone design guidelines
- [QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - General game reference
