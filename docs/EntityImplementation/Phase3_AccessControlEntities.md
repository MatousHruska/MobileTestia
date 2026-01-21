# Phase 3: Access Control Entities

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

**Goal**: Implement database-driven Doors, Levers, and Pressure Plates with ChunkManager spawning.

---

## Overview

This phase implements the core access control entities:
- **Doors**: Block passage, unlocked by keys/levers/quests
- **Levers**: Toggle switches that control doors
- **Pressure Plates**: Floor triggers that control doors

All entities will:
1. Load configuration from database
2. Spawn via ChunkManager when chunks load
3. Persist state via PersistenceManager
4. Support cross-zone linking

---

## Entity Architecture

### Inheritance Hierarchy

```
InteractableBase
├── UnlockableDoor    (updated)
├── Lever             (updated)
└── PressurePlate     (new)
```

### Spawn Flow

```
Chunk Loads
    ↓
ChunkManager._spawn_chunk_entities()
    ↓
For each door/lever/plate in zone_entities:
    ↓
Check chunk bounds (is entity in this chunk?)
    ↓
Call _spawn_door() / _spawn_lever() / _spawn_plate()
    ↓
Load config from DatabaseLoader
    ↓
Check Persistence for saved state
    ↓
Create node, configure, add to scene
    ↓
Track in _chunk_entities for cleanup
```

---

## Door Implementation

### unlockable_door.gd Updates

```gdscript
extends InteractableBase
class_name UnlockableDoor

## Database-driven door - blocks passage until unlocked

#===============================================================================
# DATABASE PROPERTIES (loaded from database)
#===============================================================================

## Database door ID - set by ChunkManager
@export var database_door_id: String = ""

## Persistence key - auto-generated from ID + position
var persistence_key: String = ""

## Configuration (loaded from database)
var _config: Dictionary = {}

#===============================================================================
# STATE (runtime)
#===============================================================================

var is_locked: bool = true
var _collision_body: StaticBody2D

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _setup_collision()
    _update_visual()


func _load_from_database() -> void:
    if database_door_id.is_empty():
        push_warning("Door has no database_door_id")
        return

    _config = DatabaseLoader.get_door(database_door_id)
    if _config.is_empty():
        push_warning("Door not found in database: %s" % database_door_id)
        return

    # Apply defaults from database
    is_locked = _config.get("default_locked", true)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("doors", persistence_key)
    if not state.is_empty():
        is_locked = state.get("is_locked", is_locked)


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("doors", persistence_key, {
        "is_locked": is_locked,
        "unlocked_at": Time.get_unix_time_from_system() if not is_locked else 0
    })

#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
    # Can only interact if locked and not lever-controlled
    if not is_locked:
        return false
    if _config.get("lever_controlled", false):
        return false  # Must use lever instead
    return super.can_interact()


func get_interaction_prompt() -> String:
    if not is_locked:
        return ""

    var display_name: String = _config.get("display_name", "Door")
    var key_name: String = _config.get("required_key_name", "")

    if not key_name.is_empty():
        return "Unlock %s (%s)" % [display_name, key_name]
    return "Open %s" % display_name


func _on_interact() -> void:
    if not is_locked:
        return

    # Check for key requirement
    var required_key: String = _config.get("required_key_id", "")
    if not required_key.is_empty():
        var key_index := _find_key_in_inventory(required_key)
        if key_index < 0:
            _show_need_key_message()
            return
        # Consume key
        Inventory.remove_item_at(key_index)

    # Check quest requirement
    var quest_id: String = _config.get("quest_required_id", "")
    if not quest_id.is_empty():
        var required_state: String = _config.get("quest_required_state", "completed")
        if not _check_quest_requirement(quest_id, required_state):
            _show_quest_required_message()
            return

    # Unlock!
    unlock()


func unlock() -> void:
    if not is_locked:
        return

    is_locked = false
    _save_persistence()
    _update_visual()
    _disable_collision()
    door_unlocked.emit()


func lock() -> void:
    if is_locked:
        return

    is_locked = true
    _save_persistence()
    _update_visual()
    _enable_collision()
    door_locked.emit()


func toggle() -> void:
    ## Called by levers/plates
    if is_locked:
        unlock()
    else:
        lock()

#===============================================================================
# HELPERS
#===============================================================================

func _find_key_in_inventory(key_id: String) -> int:
    if not Inventory:
        return -1
    for i in range(Inventory.backpack.size()):
        var item = Inventory.backpack[i]
        if item and item.id == key_id:
            return i
    return -1


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


func _setup_collision() -> void:
    _collision_body = StaticBody2D.new()
    _collision_body.name = "DoorCollision"

    var shape := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = _config.get("collision_size", Vector2(16, 32))
    shape.shape = rect

    _collision_body.add_child(shape)
    add_child(_collision_body)

    if not is_locked:
        _disable_collision()


func _enable_collision() -> void:
    if _collision_body:
        _collision_body.set_collision_layer_value(1, true)


func _disable_collision() -> void:
    if _collision_body:
        _collision_body.set_collision_layer_value(1, false)


func _update_visual() -> void:
    # Update color/sprite based on locked state
    if _visual:
        _visual.color = Color.SADDLE_BROWN if is_locked else Color.DARK_GREEN

#===============================================================================
# SIGNALS
#===============================================================================

signal door_unlocked
signal door_locked
```

---

## Lever Implementation

### lever.gd Updates

```gdscript
extends InteractableBase
class_name Lever

## Database-driven lever - toggles linked entities

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_lever_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var is_on: bool = false
var has_been_used: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _update_visual()


func _load_from_database() -> void:
    if database_lever_id.is_empty():
        return

    _config = DatabaseLoader.get_lever(database_lever_id)
    if _config.is_empty():
        push_warning("Lever not found in database: %s" % database_lever_id)
        return

    is_on = _config.get("default_on", false)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("levers", persistence_key)
    if not state.is_empty():
        is_on = state.get("is_on", is_on)
        has_been_used = state.get("has_been_used", false)


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("levers", persistence_key, {
        "is_on": is_on,
        "has_been_used": has_been_used
    })

    # Also update linked door state via persistence (cross-zone support)
    var linked_door: String = _config.get("linked_door_id", "")
    if not linked_door.is_empty():
        Persistence.save_state("doors", linked_door, {
            "is_locked": not is_on,
            "unlocked_by_lever": true
        })

#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
    # One-shot levers can only be used once
    if _config.get("one_shot", false) and has_been_used:
        return false
    return super.can_interact()


func get_interaction_prompt() -> String:
    var display_name: String = _config.get("display_name", "Lever")
    if is_on:
        return "Deactivate %s" % display_name
    return "Activate %s" % display_name


func _on_interact() -> void:
    toggle()


func toggle() -> void:
    is_on = not is_on
    has_been_used = true

    _save_persistence()
    _update_visual()
    _notify_linked_entities()

    lever_toggled.emit(is_on)
    if is_on:
        lever_activated.emit()
    else:
        lever_deactivated.emit()


func _notify_linked_entities() -> void:
    ## Notify linked door (works for same-zone via scene tree search)
    var linked_door_id: String = _config.get("linked_door_id", "")
    if linked_door_id.is_empty():
        return

    # Try to find door in current scene
    var door := _find_door_in_scene(linked_door_id)
    if door:
        door.toggle()
    # Cross-zone doors will read from persistence when they load


func _find_door_in_scene(door_id: String) -> UnlockableDoor:
    ## Search scene tree for door with matching database_door_id
    var doors := get_tree().get_nodes_in_group("doors")
    for node in doors:
        if node is UnlockableDoor and node.database_door_id == door_id:
            return node
    return null


func _update_visual() -> void:
    if _visual:
        _visual.color = Color.ORANGE if is_on else Color.DARK_ORANGE

#===============================================================================
# SIGNALS
#===============================================================================

signal lever_toggled(is_on: bool)
signal lever_activated
signal lever_deactivated
```

---

## Pressure Plate Implementation

### pressure_plate.gd (New File)

```gdscript
extends InteractableBase
class_name PressurePlate

## Database-driven pressure plate - triggers when stepped on

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_plate_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var is_pressed: bool = false
var has_been_used: bool = false
var _reset_timer: float = 0.0
var _bodies_on_plate: Array[Node2D] = []

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _setup_detection_area()
    _update_visual()


func _process(delta: float) -> void:
    # Handle auto-reset
    if _reset_timer > 0:
        _reset_timer -= delta
        if _reset_timer <= 0:
            _on_reset_timer_complete()


func _load_from_database() -> void:
    if database_plate_id.is_empty():
        return

    _config = DatabaseLoader.get_pressure_plate(database_plate_id)
    if _config.is_empty():
        push_warning("Pressure plate not found: %s" % database_plate_id)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("plates", persistence_key)
    if not state.is_empty():
        has_been_used = state.get("has_been_used", false)
        # Note: is_pressed is NOT persisted - it's runtime state


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("plates", persistence_key, {
        "has_been_used": has_been_used
    })


func _setup_detection_area() -> void:
    ## Override InteractableBase - plates detect bodies entering, not click
    # Disconnect default interaction signals
    if _detection_area.body_entered.is_connected(_on_body_entered):
        _detection_area.body_entered.disconnect(_on_body_entered)

    # Connect to our handlers
    _detection_area.body_entered.connect(_on_plate_body_entered)
    _detection_area.body_exited.connect(_on_plate_body_exited)

#===============================================================================
# PLATE LOGIC
#===============================================================================

func _on_plate_body_entered(body: Node2D) -> void:
    if not _is_valid_trigger_body(body):
        return

    _bodies_on_plate.append(body)

    var mode: String = _config.get("trigger_mode", "step_on")
    match mode:
        "step_on":
            _activate()
        "toggle":
            _toggle()


func _on_plate_body_exited(body: Node2D) -> void:
    _bodies_on_plate.erase(body)

    var mode: String = _config.get("trigger_mode", "step_on")
    match mode:
        "step_on":
            if _bodies_on_plate.is_empty():
                _deactivate()
        "step_off":
            if _bodies_on_plate.is_empty():
                _activate()


func _is_valid_trigger_body(body: Node2D) -> bool:
    ## Only player (or weighted objects if implemented) can trigger
    if Game and body == Game.player:
        return true
    return false


func _activate() -> void:
    if _config.get("one_shot", false) and has_been_used:
        return

    if is_pressed:
        return

    is_pressed = true
    has_been_used = true
    _save_persistence()
    _update_visual()
    _notify_linked_door(true)

    plate_activated.emit()

    # Start reset timer if configured
    var reset_delay: float = _config.get("reset_delay", 0.0)
    if reset_delay > 0:
        _reset_timer = reset_delay


func _deactivate() -> void:
    if not is_pressed:
        return

    is_pressed = false
    _update_visual()
    _notify_linked_door(false)

    plate_deactivated.emit()


func _toggle() -> void:
    if is_pressed:
        _deactivate()
    else:
        _activate()


func _on_reset_timer_complete() -> void:
    if is_pressed and _bodies_on_plate.is_empty():
        _deactivate()


func _notify_linked_door(open: bool) -> void:
    var linked_door: String = _config.get("linked_door_id", "")
    if linked_door.is_empty():
        return

    # Try same-zone door
    var door := _find_door_in_scene(linked_door)
    if door:
        if open:
            door.unlock()
        else:
            door.lock()

    # Also save to persistence for cross-zone
    Persistence.save_state("doors", linked_door, {
        "is_locked": not open,
        "unlocked_by_plate": true
    })


func _find_door_in_scene(door_id: String) -> UnlockableDoor:
    var doors := get_tree().get_nodes_in_group("doors")
    for node in doors:
        if node is UnlockableDoor and node.database_door_id == door_id:
            return node
    return null


func _update_visual() -> void:
    if _visual:
        _visual.color = Color.DARK_GRAY if is_pressed else Color.GRAY

#===============================================================================
# INTERACTION (plates don't use click interaction)
#===============================================================================

func can_interact() -> bool:
    return false  # Plates are triggered by stepping, not clicking


func get_interaction_prompt() -> String:
    return ""

#===============================================================================
# SIGNALS
#===============================================================================

signal plate_activated
signal plate_deactivated
```

---

## ChunkManager Updates

### Add Spawn Methods

```gdscript
#===============================================================================
# DOOR SPAWNING
#===============================================================================

func _spawn_door(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var door_id: String = data.get("id", "")
    if door_id.is_empty():
        Debug.warn("ChunkManager", "Door has no ID, skipping")
        return null

    # Get position and generate persistence key
    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [door_id, int(world_pos.x), int(world_pos.y)]

    # Create door node
    var door: UnlockableDoor = UnlockableDoor.new()
    door.database_door_id = door_id
    door.persistence_key = persistence_key

    # Set position
    door.position = world_pos - chunk_origin

    # Mark as chunk-spawned
    door.set_meta("chunk_spawned", true)
    door.set_meta("chunk_id", chunk_id)
    door.set_meta("world_position", world_pos)

    # Add to group for searching
    door.add_to_group("doors")

    parent.add_child(door)
    Debug.log("ChunkManager", "Spawned door: %s at %s" % [door_id, world_pos])

    return door


#===============================================================================
# LEVER SPAWNING
#===============================================================================

func _spawn_lever(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var lever_id: String = data.get("id", "")
    if lever_id.is_empty():
        Debug.warn("ChunkManager", "Lever has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [lever_id, int(world_pos.x), int(world_pos.y)]

    var lever: Lever = Lever.new()
    lever.database_lever_id = lever_id
    lever.persistence_key = persistence_key
    lever.position = world_pos - chunk_origin

    lever.set_meta("chunk_spawned", true)
    lever.set_meta("chunk_id", chunk_id)
    lever.set_meta("world_position", world_pos)

    lever.add_to_group("levers")

    parent.add_child(lever)
    Debug.log("ChunkManager", "Spawned lever: %s at %s" % [lever_id, world_pos])

    return lever


#===============================================================================
# PRESSURE PLATE SPAWNING
#===============================================================================

func _spawn_pressure_plate(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var plate_id: String = data.get("id", "")
    if plate_id.is_empty():
        Debug.warn("ChunkManager", "Pressure plate has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [plate_id, int(world_pos.x), int(world_pos.y)]

    var plate: PressurePlate = PressurePlate.new()
    plate.database_plate_id = plate_id
    plate.persistence_key = persistence_key
    plate.position = world_pos - chunk_origin

    plate.set_meta("chunk_spawned", true)
    plate.set_meta("chunk_id", chunk_id)
    plate.set_meta("world_position", world_pos)

    plate.add_to_group("plates")

    parent.add_child(plate)
    Debug.log("ChunkManager", "Spawned pressure plate: %s at %s" % [plate_id, world_pos])

    return plate
```

### Update _spawn_chunk_entities

```gdscript
func _spawn_chunk_entities(chunk_id: String, chunk_node: Node2D, chunk_coords: Vector2i) -> void:
    # ... existing spawn points, chests, transitions ...

    # Spawn doors
    for door_data in _zone_entities.get("doors", []):
        var pos: Dictionary = door_data.get("position", {})
        var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
        if chunk_bounds.has_point(world_pos):
            var entity := _spawn_door(door_data, chunk_node, chunk_origin, chunk_id)
            if entity:
                spawned_entities.append(entity)

    # Spawn levers
    for lever_data in _zone_entities.get("levers", []):
        var pos: Dictionary = lever_data.get("position", {})
        var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
        if chunk_bounds.has_point(world_pos):
            var entity := _spawn_lever(lever_data, chunk_node, chunk_origin, chunk_id)
            if entity:
                spawned_entities.append(entity)

    # Spawn pressure plates
    for plate_data in _zone_entities.get("pressure_plates", []):
        var pos: Dictionary = plate_data.get("position", {})
        var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
        if chunk_bounds.has_point(world_pos):
            var entity := _spawn_pressure_plate(plate_data, chunk_node, chunk_origin, chunk_id)
            if entity:
                spawned_entities.append(entity)

    # ... rest of function ...
```

---

## Cross-Zone Linking

### How It Works

1. **Lever in Zone A** controls **Door in Zone B**
2. Lever saves door state to Persistence: `Persistence.save_state("doors", "door_id", {is_locked: false})`
3. When Zone B loads, door reads from Persistence
4. Door sees `is_locked: false` and spawns unlocked

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Lever pulled, door chunk not loaded | Door loads unlocked later |
| Door chunk loads first, lever not pulled | Door loads locked (default) |
| Both in same chunk | Direct method call works |
| Save/load cycle | Persistence restored, both work |

---

## Testing Checklist

### Door Tests
- [ ] Door spawns at correct position
- [ ] Door blocks movement when locked
- [ ] Key unlock works (consumes key)
- [ ] Lever-controlled door ignores key
- [ ] Quest-locked door checks quest state
- [ ] Save/load preserves door state

### Lever Tests
- [ ] Lever spawns at correct position
- [ ] Toggle changes visual
- [ ] One-shot lever can't be reused
- [ ] Linked door toggles in same zone
- [ ] Linked door state saved for cross-zone
- [ ] Save/load preserves lever state

### Pressure Plate Tests
- [ ] Plate spawns at correct position
- [ ] `step_on` mode activates while standing
- [ ] `step_off` mode activates on exit
- [ ] `toggle` mode alternates each step
- [ ] Reset delay works
- [ ] One-shot plate can't retrigger
- [ ] Linked door responds

### Integration Tests
- [ ] Lever in Zone A unlocks door in Zone B
- [ ] Plate in Zone A unlocks door in Zone B
- [ ] Multiple levers can control same door
- [ ] Save during puzzle, load, puzzle state preserved

---

## Success Criteria

- [ ] All three entity types spawn from ChunkManager
- [ ] All load configuration from database
- [ ] All persist state correctly
- [ ] Cross-zone linking works via Persistence
- [ ] No regressions in existing entities
- [ ] Visual feedback for states

---

## Next Phase

After access control entities are complete, proceed to **Phase 4: NPCs** to implement NPC spawning via ChunkManager.
