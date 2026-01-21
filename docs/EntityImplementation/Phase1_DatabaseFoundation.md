# Phase 1: Database Foundation

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

**Goal**: Create all VBA database modules and JSON exports for the new entity types.

---

## Overview

This phase creates the database infrastructure for all new entities. Following the existing pattern (Excel + VBA → JSON export), we need:

1. VBA module files for each entity type
2. Updates to MasterExport.bas
3. Updates to SharedValidation.bas
4. Initial test data entries

---

## New Databases to Create

| Database | VBA File | JSON Output | Purpose |
|----------|----------|-------------|---------|
| Doors | `DoorDatabase.bas` | `doors.json` | Door definitions |
| Levers | `LeverDatabase.bas` | `levers.json` | Lever/switch definitions |
| PressurePlates | `PressurePlateDatabase.bas` | `pressure_plates.json` | Floor triggers |
| Lootables | `LootableDatabase.bas` | `lootables.json` | Quick-loot containers |
| Signs | `SignDatabase.bas` | `signs.json` | Readable objects |
| LoreEchoes | `LoreEchoDatabase.bas` | `lore_echoes.json` | Audio lore objects |
| TriggerAreas | `TriggerAreaDatabase.bas` | `trigger_areas.json` | Event/cutscene triggers |

---

## Database Schemas

### 1. DoorDatabase

**Sheet Name**: `Doors`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID (e.g., `door_forest_secret`) |
| name | String | Yes | Internal name |
| display_name | String | Yes | Shown to player ("Sealed Stone Door") |
| required_key_id | String | No | Item ID needed to unlock (empty = no key) |
| required_key_name | String | No | Display name ("Old Rusty Key") |
| lever_controlled | Boolean | No | If true, only lever can open (default: false) |
| quest_required_id | String | No | Quest that must be active/complete |
| quest_required_state | Enum | No | `not_started`, `active`, `completed` |
| default_locked | Boolean | Yes | Starting state (default: true) |
| sprite_id | String | No | Visual asset reference |
| open_sound_id | String | No | Sound effect on open |
| description | String | No | Flavor text / examine text |

**Validation**:
- `required_key_id` must exist in Items if specified
- `quest_required_id` must exist in Quests if specified
- `quest_required_state` must be valid enum

### 2. LeverDatabase

**Sheet Name**: `Levers`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID (e.g., `lever_crypt_gate`) |
| name | String | Yes | Internal name |
| display_name | String | No | Shown on interact ("Rusty Lever") |
| linked_door_id | String | No | Door this lever controls |
| one_shot | Boolean | No | Can only activate once (default: false) |
| default_on | Boolean | No | Starting state (default: false) |
| sprite_id | String | No | Visual asset reference |
| sound_id | String | No | Sound effect on pull |
| description | String | No | Flavor text |

**Validation**:
- `linked_door_id` must exist in Doors if specified

### 3. PressurePlateDatabase

**Sheet Name**: `PressurePlates`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID |
| name | String | Yes | Internal name |
| linked_door_id | String | No | Door this plate controls |
| trigger_mode | Enum | Yes | `step_on`, `step_off`, `toggle` |
| reset_delay | Float | No | Seconds before auto-reset (0 = no reset) |
| one_shot | Boolean | No | Only triggers once (default: false) |
| sprite_id | String | No | Visual asset |
| sound_id | String | No | Sound on trigger |

**Trigger Modes**:
- `step_on`: Activates while player stands on it
- `step_off`: Activates when player steps off
- `toggle`: Each step toggles state

### 4. LootableDatabase

**Sheet Name**: `Lootables`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID (e.g., `loot_corpse_soldier`) |
| name | String | Yes | Internal name |
| display_name | String | Yes | Shown to player ("Fallen Soldier") |
| loot_table_id | String | No | LootTable reference for items |
| min_gold | Integer | No | Minimum gold drop (default: 0) |
| max_gold | Integer | No | Maximum gold drop (default: 0) |
| drop_chance | Float | No | Chance to have loot (0.0-1.0, default: 1.0) |
| can_respawn | Boolean | No | Can respawn after looted (default: false) |
| respawn_time | Integer | No | Seconds until respawn |
| sprite_id | String | Yes | Visual asset (corpse, urn, barrel, etc.) |
| interaction_prompt | String | No | Action text ("Search", "Loot", "Open") |

**Validation**:
- `loot_table_id` must exist in LootTables if specified
- `drop_chance` must be 0.0-1.0

### 5. SignDatabase

**Sheet Name**: `Signs`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID (e.g., `sign_forest_warning`) |
| name | String | Yes | Internal name |
| floating_dialogue_id | String | Yes | FloatingDialogue to show |
| sprite_id | String | No | Visual asset |
| interaction_prompt | String | No | Action text (default: "Read") |

**Validation**:
- `floating_dialogue_id` must exist in FloatingDialogues

### 6. LoreEchoDatabase

**Sheet Name**: `LoreEchoes`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID (e.g., `echo_crypt_builder`) |
| name | String | Yes | Internal name |
| audio_id | String | No | Future: audio file reference |
| subtitle_text | String | Yes | Text shown/spoken (accessibility) |
| duration | Float | No | Playback duration in seconds |
| can_replay | Boolean | No | Can listen again (default: true) |
| sprite_id | String | No | Visual asset (glowing rune, etc.) |
| interaction_prompt | String | No | Action text (default: "Listen") |

### 7. TriggerAreaDatabase

**Sheet Name**: `TriggerAreas`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | String | Yes | Unique ID |
| name | String | Yes | Internal name |
| trigger_type | Enum | Yes | `cutscene`, `quest`, `spawn`, `dialogue` |
| target_id | String | No | Cutscene/Quest/SpawnGroup ID to trigger |
| one_shot | Boolean | No | Only fires once (default: true) |
| require_quest_id | String | No | Quest that must be active |
| require_quest_state | Enum | No | Required quest state |
| cooldown | Float | No | Seconds before can trigger again |

**Trigger Types**:
- `cutscene`: Starts a cutscene from CutsceneDatabase
- `quest`: Starts/advances a quest
- `spawn`: Spawns a group of enemies (ambush)
- `dialogue`: Shows floating dialogue

---

## VBA File Template

Each database module follows this pattern:

```vba
Attribute VB_Name = "DoorDatabase"
'===============================================================================
' DoorDatabase Module
' Exports door definitions to JSON
'===============================================================================
Option Explicit

Public Sub ExportDoorsData()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Doors")

    ' ... standard export logic ...
End Sub

Public Sub ValidateDoorsData()
    ' ... validation logic ...
End Sub
```

---

## MasterExport.bas Updates

Add to `ExportAll()`:
```vba
' Interactables (expanded)
ExportChests
ExportDoorsData
ExportLeversData
ExportPressurePlatesData
ExportLootablesData
ExportSignsData
ExportLoreEchoesData
ExportTriggerAreasData
```

Add to `ValidateAll()`:
```vba
ValidateDoorsData
ValidateLeversData
ValidatePressurePlatesData
ValidateLootablesData
ValidateSignsData
ValidateLoreEchoesData
ValidateTriggerAreasData
```

Add to `SetupWorkbook()`:
```vba
CreateSheetIfNotExists "Doors"
CreateSheetIfNotExists "Levers"
CreateSheetIfNotExists "PressurePlates"
CreateSheetIfNotExists "Lootables"
CreateSheetIfNotExists "Signs"
CreateSheetIfNotExists "LoreEchoes"
CreateSheetIfNotExists "TriggerAreas"
```

---

## SharedValidation.bas Updates

Add named range validations:
```vba
' Door validation
Public Function ValidateDoorId(doorId As String) As Boolean
    ValidateDoorId = ValidateNamedRange(doorId, "Doors", "id")
End Function

' Lever validation
Public Function ValidateLeverId(leverId As String) As Boolean
    ValidateLeverId = ValidateNamedRange(leverId, "Levers", "id")
End Function

' etc.
```

Add foreign key validations:
```vba
' Lever -> Door link validation
If Not IsEmpty(linkedDoorId) Then
    If Not ValidateDoorId(CStr(linkedDoorId)) Then
        AddError "Lever " & id & " references unknown door: " & linkedDoorId
    End If
End If
```

---

## Initial Test Data

### doors.json (migrated from legacy)
```json
{
  "doors": [
    {
      "id": "door_forest_secret",
      "name": "Forest Secret Door",
      "display_name": "Old Wooden Door",
      "required_key_id": "key_old_wooden",
      "required_key_name": "Old Wooden Key",
      "lever_controlled": false,
      "quest_required_id": "",
      "quest_required_state": "",
      "default_locked": true,
      "sprite_id": "door_wooden",
      "description": "An old door, locked tight."
    },
    {
      "id": "door_meadow_gate",
      "name": "Meadow Secret Gate",
      "display_name": "Hidden Gate",
      "required_key_id": "",
      "required_key_name": "",
      "lever_controlled": true,
      "quest_required_id": "",
      "quest_required_state": "",
      "default_locked": true,
      "sprite_id": "door_iron_gate",
      "description": "A heavy gate. There must be a mechanism nearby."
    }
  ]
}
```

### levers.json (migrated from legacy)
```json
{
  "levers": [
    {
      "id": "lever_crypt_to_meadow",
      "name": "Crypt Gate Lever",
      "display_name": "Rusty Lever",
      "linked_door_id": "door_meadow_gate",
      "one_shot": true,
      "default_on": false,
      "sprite_id": "lever_wall",
      "description": "A lever covered in cobwebs."
    }
  ]
}
```

---

## DatabaseLoader.gd Updates

Add loading functions:

```gdscript
# New data storage
var _doors: Dictionary = {}
var _levers: Dictionary = {}
var _pressure_plates: Dictionary = {}
var _lootables: Dictionary = {}
var _signs: Dictionary = {}
var _lore_echoes: Dictionary = {}
var _trigger_areas: Dictionary = {}

# Load functions
func _load_doors() -> void:
    _doors = _load_json_database("doors.json", "doors")

func _load_levers() -> void:
    _levers = _load_json_database("levers.json", "levers")

# ... etc for each type ...

# Getter functions
func get_door(door_id: String) -> Dictionary:
    return _doors.get(door_id, {})

func get_lever(lever_id: String) -> Dictionary:
    return _levers.get(lever_id, {})

# ... etc ...
```

---

## Checklist

### VBA Files
- [ ] Create `DoorDatabase.bas`
- [ ] Create `LeverDatabase.bas`
- [ ] Create `PressurePlateDatabase.bas`
- [ ] Create `LootableDatabase.bas`
- [ ] Create `SignDatabase.bas`
- [ ] Create `LoreEchoDatabase.bas`
- [ ] Create `TriggerAreaDatabase.bas`

### MasterExport Updates
- [ ] Add export functions to `ExportAll()`
- [ ] Add validation functions to `ValidateAll()`
- [ ] Add sheet creation to `SetupWorkbook()`

### SharedValidation Updates
- [ ] Add ID validation functions
- [ ] Add foreign key validations
- [ ] Add enum validations

### Initial Data
- [ ] Create test entries for each database
- [ ] Migrate legacy door/lever IDs
- [ ] Run export and verify JSON

### DatabaseLoader Updates
- [ ] Add storage dictionaries
- [ ] Add load functions
- [ ] Add getter functions
- [ ] Call load functions in `_ready()`

---

## Success Criteria

- [ ] All 7 VBA modules created and tested
- [ ] ExportAll runs without errors
- [ ] ValidateAll runs without errors
- [ ] All JSON files generated in `databases/exports/`
- [ ] DatabaseLoader can load all new databases
- [ ] `DatabaseLoader.get_door("door_forest_secret")` returns data

---

## Next Phase

After database foundation is complete, proceed to **Phase 2: LDtk Integration** to add entity definitions in LDtk and update the importer.
