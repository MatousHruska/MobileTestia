# Phase 2: LDtk Integration

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

**Goal**: Add entity definitions in LDtk and update the importer to extract them.

---

## Overview

This phase adds all new entity types to LDtk and updates `ldtk_importer.gd` to extract them into zone JSON files for ChunkManager consumption.

---

## LDtk Entity Definitions

### Summary Table

| Entity | Identifier | Size | Color | Key Field |
|--------|------------|------|-------|-----------|
| DoorSpawn | `DoorSpawn` | 16x32 | #8B4513 (Brown) | `door_id` |
| LeverSpawn | `LeverSpawn` | 16x16 | #FFA500 (Orange) | `lever_id` |
| PressurePlateSpawn | `PressurePlateSpawn` | 32x32 | #808080 (Gray) | `plate_id` |
| NPCSpawn | `NPCSpawn` | 16x16 | #00CCFF (Cyan) | `npc_id` |
| LootableSpawn | `LootableSpawn` | 16x16 | #DAA520 (Goldenrod) | `lootable_id` |
| SignSpawn | `SignSpawn` | 16x16 | #ADD8E6 (Light Blue) | `sign_id` |
| LoreEchoSpawn | `LoreEchoSpawn` | 16x16 | #9370DB (Purple) | `echo_id` |
| TriggerAreaSpawn | `TriggerAreaSpawn` | Variable | #FF6B6B (Coral) | `trigger_id` |

---

## Entity Field Definitions

### DoorSpawn
```
Identifier: DoorSpawn
Size: 16x32 px (resizable height for double doors)
Color: #8B4513 (SaddleBrown)
Hollow: false

Fields:
  - door_id (String, required)
    Description: Database door ID
    Default: ""
```

### LeverSpawn
```
Identifier: LeverSpawn
Size: 16x16 px
Color: #FFA500 (Orange)
Hollow: false

Fields:
  - lever_id (String, required)
    Description: Database lever ID
    Default: ""
```

### PressurePlateSpawn
```
Identifier: PressurePlateSpawn
Size: 32x32 px (resizable)
Color: #808080 (Gray)
Hollow: false

Fields:
  - plate_id (String, required)
    Description: Database pressure plate ID
    Default: ""
```

### NPCSpawn
```
Identifier: NPCSpawn
Size: 16x16 px
Color: #00CCFF (Cyan)
Hollow: false

Fields:
  - npc_id (String, required)
    Description: Database NPC ID
    Default: ""
```

### LootableSpawn
```
Identifier: LootableSpawn
Size: 16x16 px
Color: #DAA520 (Goldenrod)
Hollow: false

Fields:
  - lootable_id (String, required)
    Description: Database lootable ID
    Default: ""
```

### SignSpawn
```
Identifier: SignSpawn
Size: 16x16 px
Color: #ADD8E6 (LightBlue)
Hollow: false

Fields:
  - sign_id (String, required)
    Description: Database sign ID
    Default: ""
```

### LoreEchoSpawn
```
Identifier: LoreEchoSpawn
Size: 16x16 px
Color: #9370DB (MediumPurple)
Hollow: false

Fields:
  - echo_id (String, required)
    Description: Database lore echo ID
    Default: ""
```

### TriggerAreaSpawn
```
Identifier: TriggerAreaSpawn
Size: 64x64 px (resizable - typically larger areas)
Color: #FF6B6B (Coral)
Hollow: true (shows boundary only)

Fields:
  - trigger_id (String, required)
    Description: Database trigger area ID
    Default: ""
```

---

## ldtk_importer.gd Updates

### 1. Update Entity Storage

In `_extract_entities()`, add new arrays:

```gdscript
var result := {
    "spawn_points": [],
    "chests": [],
    "transitions": [],
    "locations": [],
    "player_spawns": [],
    # NEW:
    "doors": [],
    "levers": [],
    "pressure_plates": [],
    "npcs": [],
    "lootables": [],
    "signs": [],
    "lore_echoes": [],
    "trigger_areas": []
}
```

### 2. Add Entity Type Matching

In the entity type match block, add:

```gdscript
match entity_type:
    # ... existing cases ...

    "doorspawn":
        result.doors.append({
            "id": fields.get("door_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y},
            "size": {"w": entity.get("width", 16), "h": entity.get("height", 32)}
        })

    "leverspawn":
        result.levers.append({
            "id": fields.get("lever_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y}
        })

    "pressureplatespawn":
        result.pressure_plates.append({
            "id": fields.get("plate_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y},
            "size": {"w": entity.get("width", 32), "h": entity.get("height", 32)}
        })

    "npcspawn":
        result.npcs.append({
            "id": fields.get("npc_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y}
        })

    "lootablespawn":
        result.lootables.append({
            "id": fields.get("lootable_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y}
        })

    "signspawn":
        result.signs.append({
            "id": fields.get("sign_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y}
        })

    "loreechospawn":
        result.lore_echoes.append({
            "id": fields.get("echo_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y}
        })

    "triggerareaspawn":
        result.trigger_areas.append({
            "id": fields.get("trigger_id", ""),
            "zone_id": zone_id,
            "position": {"x": position.x, "y": position.y},
            "size": {"w": entity.get("width", 64), "h": entity.get("height", 64)}
        })
```

### 3. Update Export Summary

In `_export_entities_summary()`, add processing for new types:

```gdscript
# Process doors
for d in entities.doors:
    var zone_id: String = d.get("zone_id", "unknown")
    _ensure_zone_data(zones_data, zone_id)
    zones_data[zone_id].doors.append({
        "id": d.get("id", ""),
        "position": {"x": d.get("position", {}).get("x", 0), "y": d.get("position", {}).get("y", 0)},
        "size": d.get("size", {"w": 16, "h": 32})
    })

# Process levers
for l in entities.levers:
    var zone_id: String = l.get("zone_id", "unknown")
    _ensure_zone_data(zones_data, zone_id)
    zones_data[zone_id].levers.append({
        "id": l.get("id", ""),
        "position": {"x": l.get("position", {}).get("x", 0), "y": l.get("position", {}).get("y", 0)}
    })

# ... similar for other types ...
```

### 4. Update Zone Data Structure

In `_ensure_zone_data()`:

```gdscript
func _ensure_zone_data(zones_data: Dictionary, zone_id: String) -> void:
    if zone_id not in zones_data:
        zones_data[zone_id] = {
            "spawn_points": [],
            "chests": [],
            "transitions": [],
            "locations": [],
            "player_spawns": [],
            # NEW:
            "doors": [],
            "levers": [],
            "pressure_plates": [],
            "npcs": [],
            "lootables": [],
            "signs": [],
            "lore_echoes": [],
            "trigger_areas": []
        }
```

---

## Zone Entity JSON Format

After import, `maps/entities/zone_ldtk_test.json` will look like:

```json
{
  "spawn_points": [
    {"id": "sp_test_ghouls", "position": {"x": 256, "y": 128}, "spawn_group": ""}
  ],
  "chests": [
    {"id": "chest_test_01", "position": {"x": 512, "y": 256}, "type": "common"}
  ],
  "transitions": [
    {"target_zone": "zone_forest", "target_spawn": "from_test", "position": {"x": 1000, "y": 0}, "size": {"w": 64, "h": 128}}
  ],
  "locations": [],
  "player_spawns": [
    {"id": "default", "position": {"x": 100, "y": 100}}
  ],
  "doors": [
    {"id": "door_forest_secret", "position": {"x": 400, "y": 200}, "size": {"w": 16, "h": 32}}
  ],
  "levers": [
    {"id": "lever_crypt_to_meadow", "position": {"x": 300, "y": 180}}
  ],
  "pressure_plates": [],
  "npcs": [
    {"id": "npc_quest_giver_main", "position": {"x": 150, "y": 150}}
  ],
  "lootables": [
    {"id": "loot_corpse_soldier", "position": {"x": 600, "y": 300}}
  ],
  "signs": [
    {"id": "sign_forest_warning", "position": {"x": 200, "y": 50}}
  ],
  "lore_echoes": [],
  "trigger_areas": [
    {"id": "trigger_ambush_01", "position": {"x": 700, "y": 200}, "size": {"w": 128, "h": 128}}
  ]
}
```

---

## Testing the Importer

### Test Checklist

1. **Add Test Entities in LDtk**
   - [ ] Add one of each new entity type to `zone_ldtk_test`
   - [ ] Fill in database IDs (even if DB entries don't exist yet)
   - [ ] Save LDtk project

2. **Run Importer**
   - [ ] Open `ldtk_importer.gd` in Godot
   - [ ] Run: Script > Run (Ctrl+Shift+X)
   - [ ] Check console for entity counts

3. **Verify JSON Output**
   - [ ] Open `maps/entities/zone_ldtk_test.json`
   - [ ] Verify all new entity arrays are present
   - [ ] Check positions and IDs are correct

4. **Verify No Regressions**
   - [ ] Existing spawn_points still work
   - [ ] Existing chests still work
   - [ ] Existing transitions still work

---

## LDtk Best Practices

### Entity Placement Guidelines

1. **Doors**: Place at passage centers, ensure collision will block path
2. **Levers**: Place on walls near doors they control (visual clarity)
3. **Pressure Plates**: Center on floor tiles, size to match visual
4. **NPCs**: Place with clearance for player interaction (40px radius)
5. **Lootables**: Slight offset from walls (not inside collision)
6. **Signs**: Place at path junctions or zone entries
7. **Lore Echoes**: Place at points of interest, slightly hidden
8. **Trigger Areas**: Large rectangles, invisible in game

### Naming Convention

```
Doors:           door_{zone}_{description}     → door_forest_secret
Levers:          lever_{zone}_{function}       → lever_crypt_gate
Plates:          plate_{zone}_{function}       → plate_crypt_trap
NPCs:            npc_{role}_{name}             → npc_blacksmith_john
Lootables:       loot_{type}_{description}     → loot_corpse_soldier
Signs:           sign_{zone}_{description}     → sign_forest_warning
Echoes:          echo_{zone}_{subject}         → echo_crypt_builder
Triggers:        trigger_{zone}_{event}        → trigger_forest_ambush
```

---

## Checklist

### LDtk Setup
- [ ] Add DoorSpawn entity definition
- [ ] Add LeverSpawn entity definition
- [ ] Add PressurePlateSpawn entity definition
- [ ] Add NPCSpawn entity definition
- [ ] Add LootableSpawn entity definition
- [ ] Add SignSpawn entity definition
- [ ] Add LoreEchoSpawn entity definition
- [ ] Add TriggerAreaSpawn entity definition

### ldtk_importer.gd
- [ ] Add new arrays to result dictionary
- [ ] Add match cases for all new entity types
- [ ] Update _ensure_zone_data with new arrays
- [ ] Add processing in _export_entities_summary
- [ ] Update console output to show new entity counts

### Testing
- [ ] Place test entities in LDtk
- [ ] Run importer successfully
- [ ] Verify JSON output format
- [ ] Confirm no regressions

---

## Success Criteria

- [ ] All 8 entity types defined in LDtk project
- [ ] Importer extracts all entity types
- [ ] JSON output includes all new arrays
- [ ] Positions and IDs correctly captured
- [ ] Existing entities still work

---

## Next Phase

After LDtk integration is complete, proceed to **Phase 3: Access Control Entities** to implement Doors, Levers, and Pressure Plates with ChunkManager spawning.
