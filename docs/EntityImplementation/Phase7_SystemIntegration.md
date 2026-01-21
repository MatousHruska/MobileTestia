# Phase 7: System Integration & Verification

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

**Goal**: Verify and complete all connections between new entity types and existing game systems (Quests, Cutscenes, NPCs, etc.)

---

## Overview

This phase is a cross-cutting verification and integration phase. It ensures:

1. All entity types properly connect to the Quest system
2. All entity types properly connect to the Cutscene system
3. Object interactions notify the quest system
4. Missing integration points are implemented
5. End-to-end testing of all connections

---

## Current System Analysis

### What's Already Database-Driven (Working)

| System | Connection | Status |
|--------|------------|--------|
| Quest metadata | `quests.json` | ✅ Working |
| Quest objectives | `quest_objectives.json` | ✅ Working |
| Enemy kill tracking | `NPCManager.enemy_unregistered` → `QuestManager._on_enemy_died()` | ✅ Automatic |
| Item pickup tracking | `Inventory.inventory_changed` → `QuestManager._on_inventory_changed()` | ✅ Automatic |
| Zone entry detection | `Game.zone_changed` → `QuestManager._on_zone_changed()` | ✅ Automatic |
| Cutscene sequences | `cutscenes.json` | ✅ Working |
| Zone-enter cutscenes | `CutsceneManager._on_zone_changed()` | ✅ Automatic |
| Lever → Door linking | Via `linked_door_id` + Persistence | ✅ Working |

### What's Database-Defined But NOT Connected

| Entity | Database Field | Implementation Status |
|--------|---------------|----------------------|
| **Doors** | `quest_required_id`, `quest_required_state` | ⚠️ Phase 3 documents it, verify actual code |
| **TriggerAreas** | `trigger_type`, `target_id`, `require_quest_id` | ❌ No `trigger_area.gd` exists yet |
| **Lootables** | `loot_table_id` | ❌ No `lootable.gd` exists yet |
| **Signs** | `floating_dialogue_id` | ❌ No `sign.gd` exists yet |
| **LoreEchoes** | `audio_id`, `subtitle_text` | ❌ No `lore_echo.gd` exists yet |
| **PressurePlates** | `linked_door_id`, `trigger_mode` | ❌ No `pressure_plate.gd` exists yet |

### Missing Integration Points

| From | To | Required Integration |
|------|-----|---------------------|
| Interactables | QuestManager | Call `on_object_interacted(object_id)` when player interacts |
| Levers | QuestManager | Call `on_object_interacted(lever_id)` when toggled |
| Doors | QuestManager | Call `on_object_interacted(door_id)` when unlocked |
| TriggerAreas | CutsceneManager | Call `play_cutscene(cutscene_id)` for cutscene triggers |
| TriggerAreas | QuestManager | Call quest start/complete for quest triggers |
| TriggerAreas | SpawnSystem | Spawn enemies for spawn triggers |
| Ability usage | QuestManager | Call `on_ability_used(ability_id)` from combat system |

---

## Integration Tasks

### 1. Verify Door Quest Requirements

**File**: `scripts/interactable/unlockable_door.gd`

Check if `_check_quest_requirement()` is implemented and called in `can_interact()` and `_on_interact()`.

**Expected Implementation** (from Phase 3 docs):

```gdscript
func _check_quest_requirement(quest_id: String, required_state: String) -> bool:
    if not QuestManager:
        return true

    match required_state:
        "not_started":
            return not QuestManager.is_quest_active(quest_id) and not QuestManager.is_quest_completed(quest_id)
        "active":
            return QuestManager.is_quest_active(quest_id)
        "completed":
            return QuestManager.is_quest_completed(quest_id)
    return true
```

**Verification Checklist**:
- [ ] `_check_quest_requirement()` function exists
- [ ] Called in `can_interact()` for quest-gated doors
- [ ] Called in `_on_interact()` before unlocking
- [ ] Shows appropriate message when quest requirement not met

---

### 2. Add Object Interaction Quest Callbacks

**File**: `scripts/interactable/interactable_base.gd`

Add quest system notification when any object is interacted with.

**Implementation**:

```gdscript
func _on_interact() -> void:
    ## Override in subclasses
    ## Base implementation notifies quest system
    _notify_quest_system()


func _notify_quest_system() -> void:
    ## Notify quest system of interaction for INTERACT objectives
    var object_id := _get_object_id()
    if not object_id.is_empty() and QuestManager:
        QuestManager.on_object_interacted(object_id)


func _get_object_id() -> String:
    ## Override to return database ID
    return ""
```

Then in each subclass (Door, Lever, Sign, etc.):

```gdscript
func _get_object_id() -> String:
    return database_door_id  # or database_lever_id, etc.
```

**Verification Checklist**:
- [ ] `_notify_quest_system()` added to InteractableBase
- [ ] Each subclass implements `_get_object_id()`
- [ ] `QuestManager.on_object_interacted()` receives notifications
- [ ] INTERACT quest objectives complete when object is used

---

### 3. Verify/Implement TriggerArea System

**File**: `scripts/interactable/trigger_area.gd` (create if missing)

TriggerArea must handle 4 trigger types from database:

| trigger_type | Action |
|--------------|--------|
| `cutscene` | `CutsceneManager.play_cutscene(target_id)` |
| `quest` | Parse `target_id` as `quest_id:action` and call QuestManager |
| `spawn` | Spawn enemy group via AmbushSpawner or SpawnPoint |
| `dialogue` | `FloatingDialogueManager.show_dialogue(target_id, ...)` |

**Implementation**: See Phase 6 documentation for full code.

**Verification Checklist**:
- [ ] `trigger_area.gd` exists
- [ ] Extends Area2D with body_entered detection
- [ ] Loads config from `DatabaseLoader.get_trigger_area()`
- [ ] Checks `require_quest_id` and `require_quest_state`
- [ ] Respects `one_shot` flag with persistence
- [ ] Handles `cooldown` for repeatable triggers
- [ ] Cutscene trigger works
- [ ] Quest trigger works
- [ ] Spawn trigger works (or has TODO)
- [ ] Dialogue trigger works

---

### 4. Add Ability Usage Quest Tracking

**File**: `scripts/combat/` (appropriate combat handler)

When player uses an ability, notify quest system for USE_ABILITY objectives.

**Implementation**:

```gdscript
## In ability execution code
func _execute_ability(ability_id: String) -> void:
    # ... existing ability execution ...

    # Notify quest system
    if QuestManager:
        QuestManager.on_ability_used(ability_id)
```

**Verification Checklist**:
- [ ] Find where player abilities are executed
- [ ] Add `QuestManager.on_ability_used()` call
- [ ] USE_ABILITY quest objectives complete correctly

---

### 5. Cutscene Trigger Types Beyond Zone Entry

**File**: `autoloads/cutscene_manager.gd`

Currently only `zone_enter` triggers work automatically. Add support for manual triggers.

**Current**: Zone-enter cutscenes auto-play via `_on_zone_changed()`

**Needed**: Method to play cutscene by ID (already exists: `play_cutscene()`)

**Verification Checklist**:
- [ ] `play_cutscene(cutscene_id)` method exists and works
- [ ] TriggerArea can call it successfully
- [ ] Quest-conditional cutscenes check quest state before playing

---

### 6. ChunkManager Entity Spawning

Verify ChunkManager has spawn methods for all entity types.

**Required Methods**:
- [ ] `_spawn_door()` - Spawns UnlockableDoor
- [ ] `_spawn_lever()` - Spawns Lever
- [ ] `_spawn_pressure_plate()` - Spawns PressurePlate
- [ ] `_spawn_npc()` - Spawns DatabaseNPC
- [ ] `_spawn_lootable()` - Spawns Lootable
- [ ] `_spawn_sign()` - Spawns Sign
- [ ] `_spawn_lore_echo()` - Spawns LoreEcho
- [ ] `_spawn_trigger_area()` - Spawns TriggerArea

**Verification Checklist**:
- [ ] All spawn methods exist in `chunk_manager.gd`
- [ ] Each reads config from DatabaseLoader
- [ ] Each checks persistence for saved state
- [ ] Each handles one-shot/already-used entities correctly
- [ ] `_spawn_chunk_entities()` calls all spawn methods

---

## Quest Objective Type Support Matrix

| Objective Type | Trigger Source | Auto/Manual | Status |
|----------------|---------------|-------------|--------|
| `kill_named` | Enemy death signal | Auto | ✅ |
| `kill_count` | Enemy death signal | Auto | ✅ |
| `gather` | Inventory signal | Auto | ✅ |
| `reach_location` | Zone changed signal | Auto | ✅ |
| `talk` | HubUI quest button | Manual | ✅ |
| `interact` | Object interaction | Manual | ⚠️ Need to add |
| `use_ability` | Combat system | Manual | ⚠️ Need to add |
| `delivery` | NPC interaction | Manual | ✅ |
| `escort` | Escort NPC arrival | Manual | ✅ |
| `defend` | Timer/wave system | Manual | ✅ |
| `defeat_no_kill` | Enemy HP threshold | Manual | ✅ |
| `race` | Timer system | Manual | ✅ |

---

## Testing Scenarios

### Scenario 1: Quest-Gated Door

1. Create door with `quest_required_id: "test_quest"`, `quest_required_state: "active"`
2. Try to open door without quest active → Should fail with message
3. Start quest
4. Try to open door → Should succeed
5. Save/load → Door should remain openable

### Scenario 2: TriggerArea Cutscene

1. Create trigger area with `trigger_type: "cutscene"`, `target_id: "test_cutscene"`
2. Walk into area → Cutscene should play
3. Walk out and back in → Should NOT play again (one_shot)
4. Save/load → Trigger should still be marked as triggered

### Scenario 3: TriggerArea Quest Conditional

1. Create trigger with `require_quest_id: "test_quest"`, `require_quest_state: "active"`
2. Walk into area without quest → Should NOT trigger
3. Start quest
4. Walk into area → Should trigger

### Scenario 4: Object Interaction Quest

1. Create quest with INTERACT objective for "lever_test"
2. Pull lever → Quest objective should complete
3. Verify `on_object_interacted("lever_test")` was called

### Scenario 5: Lever Controls Cross-Zone Door

1. Place lever in Zone A linked to `door_zone_b_gate`
2. Place door in Zone B with `database_door_id: "door_zone_b_gate"`
3. Pull lever in Zone A
4. Travel to Zone B
5. Door should be unlocked

### Scenario 6: Complete Quest Flow

1. Start quest with multiple objectives:
   - Kill 3 ghouls (kill_count)
   - Find ancient key (gather)
   - Pull lever in crypt (interact)
   - Reach boss chamber (reach_location)
2. Complete all objectives in any order
3. Quest should complete
4. Save/load at each step → Progress preserved

---

## Success Criteria

- [ ] All entity types can notify quest system of interactions
- [ ] Quest-gated doors check requirements correctly
- [ ] TriggerAreas handle all 4 trigger types
- [ ] Ability usage tracking works for USE_ABILITY objectives
- [ ] All ChunkManager spawn methods implemented
- [ ] Save/load preserves all entity and quest states
- [ ] Cross-zone interactions work correctly
- [ ] End-to-end quest flow works

---

## Files to Modify/Create

### Modify
- `scripts/interactable/interactable_base.gd` - Add quest notification
- `scripts/interactable/unlockable_door.gd` - Verify quest checking
- `scripts/interactable/lever.gd` - Add `_get_object_id()`
- `autoloads/chunk_manager.gd` - Add missing spawn methods
- Combat ability handler - Add ability usage notification

### Create (if missing)
- `scripts/interactable/trigger_area.gd`
- `scripts/interactable/pressure_plate.gd`
- `scripts/interactable/lootable.gd`
- `scripts/interactable/sign.gd`
- `scripts/interactable/lore_echo.gd`

---

## Phase Complete Checklist

- [ ] Door quest requirements verified/implemented
- [ ] Object interaction quest callbacks added
- [ ] TriggerArea system implemented
- [ ] Ability usage quest tracking added
- [ ] All ChunkManager spawn methods verified
- [ ] All test scenarios pass
- [ ] Documentation updated

---

## Next Steps

After Phase 7, the entity system is fully integrated. Focus shifts to:

1. **Content Creation**: Design actual quests, doors, triggers for zones
2. **Polish**: Visual effects, sounds, feedback
3. **Performance Testing**: Many entities in one zone
4. **Balance**: Quest difficulty, item rewards, etc.
