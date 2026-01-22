# Phase 1: Patrol Waypoints - LDtk Setup & Importer

---

## Goal

Add visual patrol path editing in LDtk by creating PatrolWaypoint entities that link to SpawnPoints via a shared `patrol_group` field.

---

## Overview

**Current workflow:**
```
spawn_points.json → patrol_path: [[100, 200], [150, 200]]  // Hard to maintain
```

**New workflow:**
```
LDtk: SpawnPoint (patrol_group: "guard_1") + PatrolWaypoint entities
  ↓
Importer exports waypoints to zone JSON
  ↓
Runtime: SpawnPoint collects waypoints by group, builds path
```

---

## Task 1: Add PatrolWaypoint Entity to LDtk

**File:** `maps/MobileTestia.ldtk`

Add new entity definition after the existing entities (insert in the `"entities"` array in `"defs"`).

**Entity Definition:**
```json
{
    "identifier": "patrolwaypoint",
    "uid": 100,
    "tags": ["patrol"],
    "exportToToc": false,
    "allowOutOfBounds": false,
    "doc": "Patrol path waypoint - group with SpawnPoints via patrol_group",
    "width": 12,
    "height": 12,
    "resizableX": false,
    "resizableY": false,
    "minWidth": null,
    "maxWidth": null,
    "minHeight": null,
    "maxHeight": null,
    "keepAspectRatio": false,
    "tileOpacity": 1,
    "fillOpacity": 0.3,
    "lineOpacity": 1,
    "hollow": false,
    "color": "#00FFAA",
    "renderMode": "Ellipse",
    "showName": true,
    "tilesetId": null,
    "tileRenderMode": "FitInside",
    "tileRect": null,
    "uiTileRect": null,
    "nineSliceBorders": [],
    "maxCount": 0,
    "limitScope": "PerLevel",
    "limitBehavior": "MoveLastOne",
    "pivotX": 0.5,
    "pivotY": 0.5,
    "fieldDefs": [
        {
            "identifier": "patrol_group",
            "doc": "Group name linking waypoints to a SpawnPoint",
            "__type": "String",
            "uid": 101,
            "type": "F_String",
            "isArray": false,
            "canBeNull": false,
            "arrayMinLength": null,
            "arrayMaxLength": null,
            "editorDisplayMode": "ValueOnly",
            "editorDisplayScale": 1,
            "editorDisplayPos": "Above",
            "editorLinkStyle": "StraightArrow",
            "editorDisplayColor": null,
            "editorAlwaysShow": true,
            "editorShowInWorld": true,
            "editorCutLongValues": true,
            "editorTextSuffix": null,
            "editorTextPrefix": null,
            "useForSmartColor": false,
            "exportToToc": false,
            "searchable": true,
            "min": null,
            "max": null,
            "regex": null,
            "acceptFileTypes": null,
            "defaultOverride": null,
            "textLanguageMode": null,
            "symmetricalRef": false,
            "autoChainRef": true,
            "allowOutOfLevelRef": true,
            "allowedRefs": "OnlySame",
            "allowedRefsEntityUid": null,
            "allowedRefTags": [],
            "tilesetUid": null
        },
        {
            "identifier": "order",
            "doc": "Order in patrol sequence (0, 1, 2...)",
            "__type": "Int",
            "uid": 102,
            "type": "F_Int",
            "isArray": false,
            "canBeNull": false,
            "arrayMinLength": null,
            "arrayMaxLength": null,
            "editorDisplayMode": "ValueOnly",
            "editorDisplayScale": 1,
            "editorDisplayPos": "Above",
            "editorLinkStyle": "StraightArrow",
            "editorDisplayColor": null,
            "editorAlwaysShow": true,
            "editorShowInWorld": true,
            "editorCutLongValues": true,
            "editorTextSuffix": null,
            "editorTextPrefix": null,
            "useForSmartColor": false,
            "exportToToc": false,
            "searchable": false,
            "min": 0,
            "max": null,
            "regex": null,
            "acceptFileTypes": null,
            "defaultOverride": { "id": "V_Int", "params": [0] },
            "textLanguageMode": null,
            "symmetricalRef": false,
            "autoChainRef": true,
            "allowOutOfLevelRef": true,
            "allowedRefs": "OnlySame",
            "allowedRefsEntityUid": null,
            "allowedRefTags": [],
            "tilesetUid": null
        },
        {
            "identifier": "wait_time",
            "doc": "Seconds to wait at this waypoint (0 = no wait)",
            "__type": "Float",
            "uid": 103,
            "type": "F_Float",
            "isArray": false,
            "canBeNull": false,
            "arrayMinLength": null,
            "arrayMaxLength": null,
            "editorDisplayMode": "ValueOnly",
            "editorDisplayScale": 1,
            "editorDisplayPos": "Above",
            "editorLinkStyle": "StraightArrow",
            "editorDisplayColor": null,
            "editorAlwaysShow": false,
            "editorShowInWorld": false,
            "editorCutLongValues": true,
            "editorTextSuffix": "s",
            "editorTextPrefix": null,
            "useForSmartColor": false,
            "exportToToc": false,
            "searchable": false,
            "min": 0,
            "max": null,
            "regex": null,
            "acceptFileTypes": null,
            "defaultOverride": { "id": "V_Float", "params": [0] },
            "textLanguageMode": null,
            "symmetricalRef": false,
            "autoChainRef": true,
            "allowOutOfLevelRef": true,
            "allowedRefs": "OnlySame",
            "allowedRefsEntityUid": null,
            "allowedRefTags": [],
            "tilesetUid": null
        }
    ]
}
```

**Also update `nextUid`** at line 14 from `100` to `104`.

**Also add `patrol_group` field to SpawnPoint entity** (uid 10) to link spawn points to waypoints:
- Add new field definition with uid 12 (since 11 is used by spawn_point_id)

---

## Task 2: Update LDtk Importer

**File:** `scripts/tools/ldtk_importer.gd`

### 2.1 Add patrol_waypoints to entity arrays

In `_run()` around line 69, add to `all_entities`:
```gdscript
"patrol_waypoints": [],
```

In `_ensure_zone_data()` around line 835, add:
```gdscript
"patrol_waypoints": [],
```

In `_extract_level_entities()` around line 471, add:
```gdscript
"patrol_waypoints": [],
```

### 2.2 Add waypoint extraction

In `_extract_level_entities()`, add case in the match statement (around line 499):
```gdscript
"patrolwaypoint":
    result.patrol_waypoints.append({
        "patrol_group": fields.get("patrol_group", ""),
        "order": int(fields.get("order", 0)),
        "wait_time": float(fields.get("wait_time", 0.0)),
        "zone_id": zone_id,
        "position_x": position.x,
        "position_y": position.y
    })
```

### 2.3 Process waypoints into zone data

In `_organize_by_zone()`, add after processing other entities (around line 800):
```gdscript
# Process patrol waypoints
for wp in entities.patrol_waypoints:
    var zone_id: String = wp.get("zone_id", "unknown")
    _ensure_zone_data(zones_data, zone_id)
    zones_data[zone_id].patrol_waypoints.append({
        "patrol_group": wp.get("patrol_group", ""),
        "order": wp.get("order", 0),
        "wait_time": wp.get("wait_time", 0.0),
        "position": {"x": wp.get("position_x", 0), "y": wp.get("position_y", 0)}
    })
```

### 2.4 Update print statements

Update the summary print to include waypoints count.

---

## Task 3: Update SpawnPoint Entity in LDtk

Add `patrol_group` field to the existing SpawnPoint entity (uid 10):

```json
{
    "identifier": "patrol_group",
    "doc": "Links to PatrolWaypoint entities with same group name",
    "__type": "String",
    "uid": 12,
    "type": "F_String",
    "isArray": false,
    "canBeNull": true,
    "arrayMinLength": null,
    "arrayMaxLength": null,
    "editorDisplayMode": "ValueOnly",
    "editorDisplayScale": 1,
    "editorDisplayPos": "Beneath",
    "editorLinkStyle": "StraightArrow",
    "editorDisplayColor": null,
    "editorAlwaysShow": false,
    "editorShowInWorld": true,
    "editorCutLongValues": true,
    "editorTextSuffix": null,
    "editorTextPrefix": "patrol:",
    "useForSmartColor": false,
    "exportToToc": false,
    "searchable": true,
    "min": null,
    "max": null,
    "regex": null,
    "acceptFileTypes": null,
    "defaultOverride": null,
    "textLanguageMode": null,
    "symmetricalRef": false,
    "autoChainRef": true,
    "allowOutOfLevelRef": true,
    "allowedRefs": "OnlySame",
    "allowedRefsEntityUid": null,
    "allowedRefTags": [],
    "tilesetUid": null
}
```

---

## Expected Zone JSON Output

After running importer, zone JSON will include:

```json
{
    "spawn_points": [
        {
            "id": "spawn_forest_guard",
            "position": {"x": 100, "y": 200},
            "patrol_group": "guard_north"
        }
    ],
    "patrol_waypoints": [
        {
            "patrol_group": "guard_north",
            "order": 0,
            "wait_time": 2.0,
            "position": {"x": 150, "y": 200}
        },
        {
            "patrol_group": "guard_north",
            "order": 1,
            "wait_time": 0,
            "position": {"x": 150, "y": 250}
        },
        {
            "patrol_group": "guard_north",
            "order": 2,
            "wait_time": 2.0,
            "position": {"x": 100, "y": 250}
        }
    ]
}
```

---

## Visual in LDtk

```
    [WP:0]----[WP:1]
    guard_n   guard_n
       |         |
   [Spawn]    [WP:2]
   guard_n    guard_n
       |         |
    [WP:4]----[WP:3]
    guard_n   guard_n
```

Small green circles (PatrolWaypoint) showing the patrol path.
Red square (SpawnPoint) with `patrol_group: "guard_n"`.

---

## Checklist

- [ ] Add PatrolWaypoint entity definition to LDtk
- [ ] Add patrol_group field to SpawnPoint entity in LDtk
- [ ] Update nextUid in LDtk
- [ ] Update importer to extract patrol_waypoints
- [ ] Update importer to organize waypoints by zone
- [ ] Test: Place waypoints in LDtk
- [ ] Test: Run importer, verify JSON output
- [ ] Commit and push

---

## Next Phase

Phase 2 will implement runtime support:
- ChunkManager loads waypoints
- SpawnPoint builds patrol path from waypoints
- Enemy patrol behavior uses the path
