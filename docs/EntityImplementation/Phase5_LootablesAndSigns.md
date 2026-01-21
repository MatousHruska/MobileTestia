# Phase 5: Lootables & Signs

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

**Goal**: Implement quick-loot containers (Lootables) and readable signs.

---

## Overview

This phase adds two information/reward entities:

1. **Lootables**: Quick-click containers that drop loot on the ground (Diablo 2 style corpses/urns)
2. **Signs**: Readable objects that display floating dialogue when clicked

---

## Lootable Implementation

### Design

| Aspect | Details |
|--------|---------|
| Interaction | Single click = instant loot drop |
| Visual | Static sprite (corpse, urn, barrel, etc.) |
| Loot Source | LootTable database |
| Respawn | Optional, with timer |
| Persistence | Tracks looted state |

### lootable.gd (New File)

```gdscript
extends InteractableBase
class_name Lootable

## Quick-loot container - drops items on the ground when clicked

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_lootable_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var is_looted: bool = false
var looted_at: float = 0.0

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _update_visual()


func _load_from_database() -> void:
    if database_lootable_id.is_empty():
        return

    _config = DatabaseLoader.get_lootable(database_lootable_id)
    if _config.is_empty():
        push_warning("Lootable not found: %s" % database_lootable_id)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("lootables", persistence_key)
    if state.is_empty():
        return

    is_looted = state.get("looted", false)
    looted_at = state.get("looted_at", 0.0)

    # Check respawn
    if is_looted and _config.get("can_respawn", false):
        var respawn_time: float = _config.get("respawn_time", 300.0)
        var elapsed := Time.get_unix_time_from_system() - looted_at
        if elapsed >= respawn_time:
            is_looted = false  # Respawned!


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("lootables", persistence_key, {
        "looted": is_looted,
        "looted_at": looted_at,
        "can_respawn": _config.get("can_respawn", false),
        "respawn_time": _config.get("respawn_time", 300.0)
    })

#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
    if is_looted:
        return false
    return super.can_interact()


func get_interaction_prompt() -> String:
    if is_looted:
        return ""
    var prompt: String = _config.get("interaction_prompt", "Search")
    var display_name: String = _config.get("display_name", "Container")
    return "%s %s" % [prompt, display_name]


func _on_interact() -> void:
    if is_looted:
        return

    _loot()


func _loot() -> void:
    is_looted = true
    looted_at = Time.get_unix_time_from_system()
    _save_persistence()
    _update_visual()

    # Generate and drop loot
    _drop_loot()

    looted.emit()


func _drop_loot() -> void:
    ## Generate loot and spawn pickups on ground

    # Check drop chance
    var drop_chance: float = _config.get("drop_chance", 1.0)
    if randf() > drop_chance:
        Debug.log("Lootable", "No loot (drop chance failed)")
        return

    # Drop gold
    var min_gold: int = _config.get("min_gold", 0)
    var max_gold: int = _config.get("max_gold", 0)
    if max_gold > 0:
        var gold_amount := randi_range(min_gold, max_gold)
        if gold_amount > 0:
            _spawn_gold_pickup(gold_amount)

    # Drop items from loot table
    var loot_table_id: String = _config.get("loot_table_id", "")
    if not loot_table_id.is_empty():
        var items := _generate_items_from_table(loot_table_id)
        for item in items:
            _spawn_item_pickup(item)


func _spawn_gold_pickup(amount: int) -> void:
    ## Spawn gold pickup near this lootable
    var offset := Vector2(randf_range(-16, 16), randf_range(-16, 16))
    var spawn_pos := global_position + offset

    if LootManager:
        LootManager.spawn_gold(spawn_pos, amount)
    else:
        # Fallback: add directly to inventory
        if Inventory:
            Inventory.add_gold(amount)


func _spawn_item_pickup(item: Dictionary) -> void:
    ## Spawn item pickup near this lootable
    var offset := Vector2(randf_range(-20, 20), randf_range(-20, 20))
    var spawn_pos := global_position + offset

    if LootManager:
        LootManager.spawn_item(spawn_pos, item)
    else:
        # Fallback: add directly to inventory
        if Inventory:
            Inventory.add_item(item)


func _generate_items_from_table(table_id: String) -> Array:
    ## Generate items from loot table
    if not DatabaseLoader:
        return []

    var table := DatabaseLoader.get_loot_table(table_id)
    if table.is_empty():
        return []

    var items: Array = []
    var rolls: int = table.get("rolls", 1)

    for _i in rolls:
        var item := _roll_loot_table(table)
        if item:
            items.append(item)

    return items


func _roll_loot_table(table: Dictionary) -> Dictionary:
    ## Roll once on a loot table
    var entries: Array = table.get("entries", [])
    if entries.is_empty():
        return {}

    # Calculate total weight
    var total_weight: float = 0.0
    for entry in entries:
        total_weight += entry.get("weight", 1.0)

    # Roll
    var roll := randf() * total_weight
    var cumulative: float = 0.0

    for entry in entries:
        cumulative += entry.get("weight", 1.0)
        if roll <= cumulative:
            # Create item from entry
            var item_id: String = entry.get("item_id", "")
            if not item_id.is_empty():
                return DatabaseLoader.create_item(item_id)
            return {}

    return {}


func _update_visual() -> void:
    if _visual:
        if is_looted:
            _visual.modulate = Color(0.5, 0.5, 0.5, 0.5)  # Faded
        else:
            _visual.modulate = Color.WHITE

#===============================================================================
# SIGNALS
#===============================================================================

signal looted
```

---

## Sign Implementation

### Design

| Aspect | Details |
|--------|---------|
| Interaction | Click = display floating dialogue |
| Visual | Static sprite (sign post, tablet, etc.) |
| Dialogue Source | FloatingDialogue database |
| Persistence | Optional "read" tracking |

### sign.gd (New File)

```gdscript
extends InteractableBase
class_name Sign

## Readable sign - displays floating dialogue when interacted

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_sign_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_read: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _update_visual()


func _load_from_database() -> void:
    if database_sign_id.is_empty():
        return

    _config = DatabaseLoader.get_sign(database_sign_id)
    if _config.is_empty():
        push_warning("Sign not found: %s" % database_sign_id)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("signs", persistence_key)
    if not state.is_empty():
        has_been_read = state.get("has_been_read", false)


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("signs", persistence_key, {
        "has_been_read": has_been_read
    })

#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
    return super.can_interact()  # Signs can always be read again


func get_interaction_prompt() -> String:
    var prompt: String = _config.get("interaction_prompt", "Read")
    return prompt


func _on_interact() -> void:
    _read_sign()


func _read_sign() -> void:
    has_been_read = true
    _save_persistence()

    # Get floating dialogue ID
    var dialogue_id: String = _config.get("floating_dialogue_id", "")
    if dialogue_id.is_empty():
        Debug.warn("Sign", "No floating_dialogue_id for sign: %s" % database_sign_id)
        return

    # Show floating dialogue above player (protagonist "reads" it)
    _show_floating_dialogue(dialogue_id)

    sign_read.emit()


func _show_floating_dialogue(dialogue_id: String) -> void:
    ## Display the sign's text as floating dialogue
    if not FloatingDialogueManager:
        push_warning("FloatingDialogueManager not available")
        return

    # Get dialogue data
    var dialogue := DatabaseLoader.get_floating_dialogue(dialogue_id)
    if dialogue.is_empty():
        Debug.warn("Sign", "Floating dialogue not found: %s" % dialogue_id)
        return

    # Show above player (they're "reading" it)
    var player = Game.player if Game else null
    if player:
        FloatingDialogueManager.show_dialogue(
            dialogue_id,
            player,
            dialogue.get("text", "..."),
            dialogue.get("duration", 3.0)
        )
    else:
        # Fallback: show above sign
        FloatingDialogueManager.show_dialogue(
            dialogue_id,
            self,
            dialogue.get("text", "..."),
            dialogue.get("duration", 3.0)
        )


func _update_visual() -> void:
    # Signs don't change appearance when read
    pass

#===============================================================================
# SIGNALS
#===============================================================================

signal sign_read
```

---

## ChunkManager Spawn Methods

### Lootable Spawning

```gdscript
func _spawn_lootable(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var lootable_id: String = data.get("id", "")
    if lootable_id.is_empty():
        Debug.warn("ChunkManager", "Lootable has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [lootable_id, int(world_pos.x), int(world_pos.y)]

    # Check if already looted and can't respawn
    var state := Persistence.load_state("lootables", persistence_key)
    if not state.is_empty() and state.get("looted", false):
        if not state.get("can_respawn", false):
            Debug.log("ChunkManager", "Lootable already looted (permanent): %s" % persistence_key)
            return null

        # Check respawn timer
        var looted_at: float = state.get("looted_at", 0.0)
        var respawn_time: float = state.get("respawn_time", 300.0)
        var elapsed := Time.get_unix_time_from_system() - looted_at
        if elapsed < respawn_time:
            Debug.log("ChunkManager", "Lootable not respawned yet: %s" % persistence_key)
            return null

    var lootable := Lootable.new()
    lootable.database_lootable_id = lootable_id
    lootable.persistence_key = persistence_key
    lootable.position = world_pos - chunk_origin

    lootable.set_meta("chunk_spawned", true)
    lootable.set_meta("chunk_id", chunk_id)
    lootable.set_meta("world_position", world_pos)

    lootable.add_to_group("lootables")

    parent.add_child(lootable)
    Debug.log("ChunkManager", "Spawned lootable: %s at %s" % [lootable_id, world_pos])

    return lootable
```

### Sign Spawning

```gdscript
func _spawn_sign(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var sign_id: String = data.get("id", "")
    if sign_id.is_empty():
        Debug.warn("ChunkManager", "Sign has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [sign_id, int(world_pos.x), int(world_pos.y)]

    var sign := Sign.new()
    sign.database_sign_id = sign_id
    sign.persistence_key = persistence_key
    sign.position = world_pos - chunk_origin

    sign.set_meta("chunk_spawned", true)
    sign.set_meta("chunk_id", chunk_id)
    sign.set_meta("world_position", world_pos)

    sign.add_to_group("signs")

    parent.add_child(sign)
    Debug.log("ChunkManager", "Spawned sign: %s at %s" % [sign_id, world_pos])

    return sign
```

### Update _spawn_chunk_entities

```gdscript
# Spawn lootables
for lootable_data in _zone_entities.get("lootables", []):
    var pos: Dictionary = lootable_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_lootable(lootable_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)

# Spawn signs
for sign_data in _zone_entities.get("signs", []):
    var pos: Dictionary = sign_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_sign(sign_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)
```

---

## Persistence Categories

Ensure these are in `persistence_manager.gd`:

```gdscript
const CATEGORIES := [
    # ... existing ...
    "lootables",  # Tracks looted state
    "signs",      # Tracks read state (optional)
]
```

---

## Database Samples

### lootables.json

```json
{
  "lootables": [
    {
      "id": "loot_corpse_soldier",
      "name": "Fallen Soldier",
      "display_name": "Soldier's Remains",
      "loot_table_id": "lt_corpse_common",
      "min_gold": 5,
      "max_gold": 25,
      "drop_chance": 0.8,
      "can_respawn": false,
      "respawn_time": 0,
      "sprite_id": "corpse_soldier",
      "interaction_prompt": "Search"
    },
    {
      "id": "loot_urn_dusty",
      "name": "Dusty Urn",
      "display_name": "Dusty Urn",
      "loot_table_id": "",
      "min_gold": 1,
      "max_gold": 10,
      "drop_chance": 0.5,
      "can_respawn": true,
      "respawn_time": 600,
      "sprite_id": "urn_clay",
      "interaction_prompt": "Break"
    }
  ]
}
```

### signs.json

```json
{
  "signs": [
    {
      "id": "sign_forest_warning",
      "name": "Forest Warning Sign",
      "floating_dialogue_id": "fdlg_sign_forest_danger",
      "sprite_id": "sign_wooden_post",
      "interaction_prompt": "Read"
    },
    {
      "id": "sign_crypt_entrance",
      "name": "Crypt Entrance Marker",
      "floating_dialogue_id": "fdlg_sign_crypt_warning",
      "sprite_id": "sign_stone_tablet",
      "interaction_prompt": "Examine"
    }
  ]
}
```

---

## Testing Checklist

### Lootable Tests
- [ ] Lootable spawns at correct position
- [ ] Click interaction triggers loot drop
- [ ] Gold drops as pickup (if LootManager available)
- [ ] Items drop from loot table
- [ ] Looted state persists (can't loot again)
- [ ] Respawnable lootables respawn after timer
- [ ] Non-respawnable lootables stay looted
- [ ] Visual changes when looted

### Sign Tests
- [ ] Sign spawns at correct position
- [ ] Click shows floating dialogue
- [ ] Dialogue appears above player
- [ ] Sign can be read multiple times
- [ ] "has_been_read" persists (for achievements)
- [ ] Different signs show different dialogues

### Integration Tests
- [ ] Lootable with loot table generates correct items
- [ ] Save/load preserves looted states
- [ ] Chunk unload/reload handles lootables correctly
- [ ] Multiple lootables in same area work

---

## Success Criteria

- [ ] Lootables spawn and function correctly
- [ ] Signs spawn and display dialogue
- [ ] Persistence works for both types
- [ ] Integration with LootManager/FloatingDialogueManager
- [ ] Visual feedback for states

---

## Next Phase

After Lootables & Signs are complete, proceed to **Phase 6: LoreEchoes & TriggerAreas** to implement audio lore objects and event triggers.
