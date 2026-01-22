# Phase 2: Patrol Waypoints - Runtime Integration

---

## Goal

Update the runtime systems to load patrol waypoints from zone JSON and build patrol paths for spawned enemies.

---

## Overview

```
Zone JSON (patrol_waypoints)
  ↓
ChunkManager loads waypoints into memory
  ↓
SpawnPoint queries waypoints by patrol_group
  ↓
SpawnPoint builds sorted path array
  ↓
Enemy receives path and patrols
```

---

## Task 1: Store Waypoints in ChunkManager

**File:** `autoloads/chunk_manager.gd`

### 1.1 Add waypoint storage

Add variable near other zone data storage:
```gdscript
## Patrol waypoints by group name: { "group_name": [waypoint_dicts sorted by order] }
var _patrol_waypoints: Dictionary = {}
```

### 1.2 Load waypoints when zone loads

In `_load_zone_entities()`, after loading other entities, add:
```gdscript
# Load patrol waypoints
_patrol_waypoints.clear()
var waypoints: Array = _zone_entities.get("patrol_waypoints", [])
for wp in waypoints:
    var group: String = wp.get("patrol_group", "")
    if group.is_empty():
        continue
    if not _patrol_waypoints.has(group):
        _patrol_waypoints[group] = []
    _patrol_waypoints[group].append(wp)

# Sort each group by order
for group in _patrol_waypoints:
    _patrol_waypoints[group].sort_custom(func(a, b): return a.get("order", 0) < b.get("order", 0))

Debug.log("ChunkManager", "Loaded %d patrol groups with %d total waypoints" % [
    _patrol_waypoints.size(),
    waypoints.size()
])
```

### 1.3 Add public method to get patrol path

```gdscript
## Get patrol path for a group as array of Vector2 positions
func get_patrol_path(patrol_group: String) -> Array[Vector2]:
    var path: Array[Vector2] = []
    if not _patrol_waypoints.has(patrol_group):
        return path

    for wp in _patrol_waypoints[patrol_group]:
        var pos: Dictionary = wp.get("position", {})
        path.append(Vector2(pos.get("x", 0), pos.get("y", 0)))

    return path


## Get patrol waypoints with full data (position, wait_time, order)
func get_patrol_waypoints(patrol_group: String) -> Array:
    if not _patrol_waypoints.has(patrol_group):
        return []
    return _patrol_waypoints[patrol_group].duplicate()
```

---

## Task 2: Update SpawnPoint to Use Waypoints

**File:** Wherever spawn point logic lives (likely in ChunkManager's `_spawn_spawn_point` or a SpawnPoint class)

### 2.1 Get patrol_group from spawn data

When spawning from zone entities, the spawn data now includes `patrol_group`:
```gdscript
var patrol_group: String = spawn_data.get("patrol_group", "")
```

### 2.2 Build patrol path and pass to enemy

```gdscript
# If spawn has a patrol group, get the path
var patrol_path: Array[Vector2] = []
if not patrol_group.is_empty():
    patrol_path = ChunkManager.get_patrol_path(patrol_group)
    if patrol_path.is_empty():
        Debug.warn("SpawnPoint", "No waypoints found for patrol_group: %s" % patrol_group)

# When spawning enemy, pass the path
if not patrol_path.is_empty():
    enemy.set_patrol_path(patrol_path)
```

---

## Task 3: Update Enemy Patrol Behavior

**File:** `scripts/npc/modular_enemy_npc.gd` or patrol module

### 3.1 Add patrol path property

```gdscript
## Patrol path (array of world positions)
var patrol_path: Array[Vector2] = []
var patrol_index: int = 0
var patrol_direction: int = 1  # 1 = forward, -1 = backward (for ping-pong)


## Set patrol path (called by spawn system)
func set_patrol_path(path: Array[Vector2]) -> void:
    patrol_path = path
    patrol_index = 0
    if not path.is_empty():
        Debug.log("Enemy", "%s received patrol path with %d waypoints" % [enemy_name, path.size()])
```

### 3.2 Update patrol logic to use path

In patrol behavior (likely in a patrol module or state):
```gdscript
func get_next_patrol_target() -> Vector2:
    if patrol_path.is_empty():
        # Fallback to database-defined path or random wander
        return _get_database_patrol_target()

    # Get current waypoint
    var target := patrol_path[patrol_index]
    return target


func advance_patrol_index() -> void:
    if patrol_path.is_empty():
        return

    # Move to next waypoint
    patrol_index += patrol_direction

    # Handle loop modes
    var patrol_loop: bool = _config.get("patrol_loop", true)
    var patrol_pingpong: bool = _config.get("patrol_pingpong", false)

    if patrol_index >= patrol_path.size():
        if patrol_pingpong:
            patrol_direction = -1
            patrol_index = patrol_path.size() - 2
        elif patrol_loop:
            patrol_index = 0
        else:
            patrol_index = patrol_path.size() - 1  # Stay at end
    elif patrol_index < 0:
        if patrol_pingpong:
            patrol_direction = 1
            patrol_index = 1
        elif patrol_loop:
            patrol_index = patrol_path.size() - 1
        else:
            patrol_index = 0
```

---

## Task 4: Optional - Support Wait Times

If you want enemies to wait at waypoints:

### 4.1 Store full waypoint data

Instead of just positions, store the full waypoint info:
```gdscript
var patrol_waypoints: Array = []  # Full waypoint dicts with wait_time

func set_patrol_waypoints(waypoints: Array) -> void:
    patrol_waypoints = waypoints
    # Also build simple path for compatibility
    patrol_path.clear()
    for wp in waypoints:
        var pos: Dictionary = wp.get("position", {})
        patrol_path.append(Vector2(pos.get("x", 0), pos.get("y", 0)))
```

### 4.2 Get wait time for current waypoint

```gdscript
func get_current_waypoint_wait_time() -> float:
    if patrol_waypoints.is_empty() or patrol_index >= patrol_waypoints.size():
        return 0.0
    return patrol_waypoints[patrol_index].get("wait_time", 0.0)
```

### 4.3 Update patrol state to wait

```gdscript
# In patrol state
if reached_waypoint:
    var wait_time := get_current_waypoint_wait_time()
    if wait_time > 0:
        _start_wait(wait_time)
    else:
        advance_patrol_index()
```

---

## Database Integration

The spawn_points.json still controls patrol behavior settings:

```json
{
    "id": "spawn_forest_guard",
    "patrol_speed": 50,
    "patrol_loop": true,
    "patrol_pingpong": false,
    "patrol_wait_default": 2.0
}
```

But now `patrol_path` coordinates come from LDtk waypoints, not the database.

---

## Full Data Flow

```
1. Designer places in LDtk:
   - SpawnPoint (id: "spawn_guard", patrol_group: "guard_north")
   - PatrolWaypoint (patrol_group: "guard_north", order: 0, pos: 100,200)
   - PatrolWaypoint (patrol_group: "guard_north", order: 1, pos: 150,200)
   - PatrolWaypoint (patrol_group: "guard_north", order: 2, pos: 150,250)

2. Importer exports to zone_forest.json:
   {
     "spawn_points": [{"id": "spawn_guard", "patrol_group": "guard_north", ...}],
     "patrol_waypoints": [
       {"patrol_group": "guard_north", "order": 0, "position": {"x": 100, "y": 200}},
       {"patrol_group": "guard_north", "order": 1, "position": {"x": 150, "y": 200}},
       {"patrol_group": "guard_north", "order": 2, "position": {"x": 150, "y": 250}}
     ]
   }

3. ChunkManager loads zone:
   - Stores waypoints grouped by patrol_group
   - Sorts each group by order

4. SpawnPoint spawns enemy:
   - Gets patrol_group from spawn data
   - Calls ChunkManager.get_patrol_path("guard_north")
   - Passes path to enemy

5. Enemy patrols:
   - Uses patrol_path array for movement targets
   - Loops/pingpongs based on database config
```

---

## Testing Checklist

- [ ] Place SpawnPoint with patrol_group in LDtk
- [ ] Place 3-4 PatrolWaypoints with same group
- [ ] Run importer, verify zone JSON
- [ ] Load zone in game
- [ ] Verify enemy spawns and patrols the path
- [ ] Test loop behavior
- [ ] Test wait times at waypoints
- [ ] Save/load - patrol should resume correctly

---

## Documentation Updates

After implementation, update:
- `LDTK_MAP_REFERENCE.md` - Add PatrolWaypoint entity
- `ZONE_DESIGN_GUIDE.md` - Add patrol path placement guide
- `ENEMY_REFERENCE.md` - Update patrol behavior docs

---

## Checklist

- [ ] Add waypoint storage to ChunkManager
- [ ] Add waypoint loading in _load_zone_entities
- [ ] Add get_patrol_path() method
- [ ] Update spawn point to pass patrol_group
- [ ] Update enemy to receive and use patrol path
- [ ] Optional: Implement wait times
- [ ] Test end-to-end
- [ ] Update documentation
- [ ] Commit and push
