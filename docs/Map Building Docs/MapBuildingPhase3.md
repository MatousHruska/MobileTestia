# Map Building Phase 3: Loot Manager System

## Session Goal
Implement the LootManager to track dropped loot across chunk loading/unloading, ensuring players don't lose items when chunks are managed.

---

## Context

### Previous Phases Completed
- Phase 1: Database schema, autoload stubs
- Phase 2: ChunkManager core with combat/leash locks

### Key Requirements
- Dropped loot must persist when chunks unload
- Loot recreated when chunks reload
- Loot despawns on game save (clean saves)
- Optional: Loot timeout after 10 minutes

### Reference Documentation
- `docs/MAP_BUILDING_REFERENCE.md` - Loot Management section
- `scripts/interactable/loot_pickup.gd` - Existing loot pickup
- `scripts/interactable/gold_pickup.gd` - Existing gold pickup

---

## Tasks for This Phase

### 1. Analyze Existing Loot System

First, read and understand:
- `scripts/interactable/loot_pickup.gd` - How loot pickups work
- `scripts/interactable/gold_pickup.gd` - How gold works
- `scripts/npc/enemy_npc.gd` - `_drop_loot()` function

Current flow:
```
Enemy dies → _drop_loot() → LootPickup.create_at() → Node added to scene
Player interacts → Item added to inventory → Node freed
```

New flow with LootManager:
```
Enemy dies → _drop_loot() → LootManager.register_drop() → LootPickup spawned
Chunk unloads → LootPickup freed → Data persists in LootManager
Chunk loads → LootManager recreates LootPickup nodes
Player picks up → LootManager.remove_drop() → Item to inventory
Game save → LootManager.clear_all() → Clean save
```

---

### 2. Implement LootManager

Update `autoloads/loot_manager.gd`:

#### 2.1 Data Structures

```gdscript
class_name LootManagerClass
extends Node

## Signals
signal drop_registered(drop_id: String, position: Vector2)
signal drop_removed(drop_id: String)
signal drop_expired(drop_id: String)

## Configuration
const LOOT_TIMEOUT := 600.0  # 10 minutes, 0 = no timeout
const MAX_DROPS := 100  # Prevent memory issues

## Drop data structure
class DropData:
    var drop_id: String
    var chunk_id: String
    var position: Vector2
    var item_data: Dictionary  # Full item data for recreation
    var drop_type: String  # "item" or "gold"
    var gold_amount: int  # Only for gold drops
    var timestamp: float  # When dropped (for timeout)
    var node: Node2D  # Reference to visual node (null if chunk unloaded)

## State
var _drops: Dictionary = {}  # drop_id -> DropData
var _next_drop_id: int = 0
var _timeout_timer: float = 0.0
```

#### 2.2 Core Methods

```gdscript
func _ready() -> void:
    add_to_group("saveable")

    # Connect to chunk signals
    if ChunkManager:
        ChunkManager.chunk_unloading.connect(_on_chunk_unloading)
        ChunkManager.chunk_loaded.connect(_on_chunk_loaded)

func _process(delta: float) -> void:
    if LOOT_TIMEOUT > 0:
        _timeout_timer += delta
        if _timeout_timer >= 60.0:  # Check every minute
            _timeout_timer = 0.0
            _check_timeouts()

func register_drop(position: Vector2, item_data: Dictionary, drop_type: String = "item", gold_amount: int = 0) -> String:
    ## Register a new drop, returns drop_id
    if _drops.size() >= MAX_DROPS:
        _remove_oldest_drop()

    var drop := DropData.new()
    drop.drop_id = "drop_%d" % _next_drop_id
    _next_drop_id += 1
    drop.chunk_id = _get_chunk_for_position(position)
    drop.position = position
    drop.item_data = item_data
    drop.drop_type = drop_type
    drop.gold_amount = gold_amount
    drop.timestamp = Time.get_unix_time_from_system()
    drop.node = null  # Set by caller after spawning visual

    _drops[drop.drop_id] = drop
    drop_registered.emit(drop.drop_id, position)

    Debug.log("Loot", "Registered drop: %s at %s" % [drop.drop_id, position])
    return drop.drop_id

func set_drop_node(drop_id: String, node: Node2D) -> void:
    ## Associate visual node with drop
    if _drops.has(drop_id):
        _drops[drop_id].node = node

func remove_drop(drop_id: String) -> void:
    ## Remove drop (player picked it up)
    if _drops.has(drop_id):
        var drop: DropData = _drops[drop_id]
        if drop.node and is_instance_valid(drop.node):
            drop.node.queue_free()
        _drops.erase(drop_id)
        drop_removed.emit(drop_id)
        Debug.log("Loot", "Removed drop: %s" % drop_id)

func get_drops_for_chunk(chunk_id: String) -> Array:
    ## Get all drops in a chunk
    var result: Array = []
    for drop_id in _drops:
        if _drops[drop_id].chunk_id == chunk_id:
            result.append(_drops[drop_id])
    return result

func clear_all_drops() -> void:
    ## Clear all drops (called on save/load)
    for drop_id in _drops.keys():
        var drop: DropData = _drops[drop_id]
        if drop.node and is_instance_valid(drop.node):
            drop.node.queue_free()
    _drops.clear()
    _next_drop_id = 0
    Debug.info("Loot", "All drops cleared")
```

#### 2.3 Chunk Integration

```gdscript
func _on_chunk_unloading(chunk_id: String) -> void:
    ## When chunk unloads, clear node references but keep data
    for drop in get_drops_for_chunk(chunk_id):
        if drop.node and is_instance_valid(drop.node):
            drop.node.queue_free()
        drop.node = null
    Debug.log("Loot", "Chunk unloading, preserved %d drops" % get_drops_for_chunk(chunk_id).size())

func _on_chunk_loaded(chunk_id: String) -> void:
    ## When chunk loads, recreate visual nodes
    var drops := get_drops_for_chunk(chunk_id)
    for drop in drops:
        _recreate_drop_visual(drop)
    Debug.log("Loot", "Chunk loaded, recreated %d drops" % drops.size())

func _recreate_drop_visual(drop: DropData) -> void:
    ## Recreate the visual pickup node
    if drop.drop_type == "gold":
        var gold_node := GoldPickup.create_single(drop.position, drop.gold_amount)
        gold_node.set_meta("loot_drop_id", drop.drop_id)
        get_tree().current_scene.add_child(gold_node)
        drop.node = gold_node
    else:  # item
        var item := _recreate_item_from_data(drop.item_data)
        if item:
            var pickup := LootPickup.create_at(drop.position, item)
            pickup.set_meta("loot_drop_id", drop.drop_id)
            get_tree().current_scene.add_child(pickup)
            drop.node = pickup

func _recreate_item_from_data(item_data: Dictionary) -> ItemData:
    ## Recreate ItemData from saved dictionary
    # This depends on your ItemData serialization
    # You may need to add ItemData.from_dict() method
    return null  # TODO: Implement based on ItemData structure
```

#### 2.4 Timeout System

```gdscript
func _check_timeouts() -> void:
    if LOOT_TIMEOUT <= 0:
        return

    var current_time := Time.get_unix_time_from_system()
    var expired: Array = []

    for drop_id in _drops:
        var drop: DropData = _drops[drop_id]
        if current_time - drop.timestamp > LOOT_TIMEOUT:
            expired.append(drop_id)

    for drop_id in expired:
        Debug.log("Loot", "Drop expired: %s" % drop_id)
        drop_expired.emit(drop_id)
        remove_drop(drop_id)

func _remove_oldest_drop() -> void:
    ## Remove oldest drop when at max capacity
    var oldest_id: String = ""
    var oldest_time: float = INF

    for drop_id in _drops:
        if _drops[drop_id].timestamp < oldest_time:
            oldest_time = _drops[drop_id].timestamp
            oldest_id = drop_id

    if not oldest_id.is_empty():
        Debug.warn("Loot", "Max drops reached, removing oldest: %s" % oldest_id)
        remove_drop(oldest_id)
```

#### 2.5 Helper Methods

```gdscript
func _get_chunk_for_position(position: Vector2) -> String:
    if ChunkManager:
        var coords := ChunkManager.get_chunk_coords(position)
        return ChunkManager.get_chunk_id(ChunkManager.current_zone_id, coords)
    return ""

func get_total_drop_count() -> int:
    return _drops.size()

func get_drop_by_id(drop_id: String) -> DropData:
    return _drops.get(drop_id, null)
```

#### 2.6 Saveable Interface

```gdscript
func get_save_key() -> String:
    return "loot_data"

func get_save_priority() -> int:
    return 50  # After persistence, before specific game state

func get_save_data() -> Dictionary:
    ## Loot despawns on save - return empty
    return {}

func load_save_data(_data: Dictionary) -> void:
    ## Clear all drops on load
    clear_all_drops()
```

---

### 3. Modify Enemy Loot Dropping

Update `scripts/npc/enemy_npc.gd` `_drop_loot()` and related methods to use LootManager:

```gdscript
func _spawn_loot_pickup(item_id: String, rarity: int = ItemData.Rarity.COMMON) -> void:
    # ... existing item creation code ...

    if item == null:
        return

    # Register with LootManager
    var item_dict := item.to_dict()  # You may need to implement this
    var drop_id := LootManager.register_drop(global_position, item_dict, "item")

    # Create visual
    var pickup := LootPickup.create_at(global_position, item)
    pickup.set_meta("loot_drop_id", drop_id)
    get_tree().current_scene.add_child(pickup)

    # Link node to LootManager
    LootManager.set_drop_node(drop_id, pickup)
```

Similarly update gold dropping in `GoldPickup.spawn_coins()` or create a new method:

```gdscript
# In GoldPickup or enemy_npc.gd
static func spawn_tracked_gold(parent: Node, position: Vector2, amount: int) -> void:
    var drop_id := LootManager.register_drop(position, {}, "gold", amount)
    var gold_node := GoldPickup.create_single(position, amount)
    gold_node.set_meta("loot_drop_id", drop_id)
    parent.add_child(gold_node)
    LootManager.set_drop_node(drop_id, gold_node)
```

---

### 4. Modify Pickup Interaction

Update `scripts/interactable/loot_pickup.gd` to notify LootManager on pickup:

```gdscript
func _on_picked_up() -> void:
    # ... existing pickup logic (add to inventory) ...

    # Notify LootManager
    if has_meta("loot_drop_id"):
        var drop_id: String = get_meta("loot_drop_id")
        LootManager.remove_drop(drop_id)

    queue_free()
```

Same for `gold_pickup.gd`:

```gdscript
func _on_collected() -> void:
    # ... existing gold collection logic ...

    if has_meta("loot_drop_id"):
        var drop_id: String = get_meta("loot_drop_id")
        LootManager.remove_drop(drop_id)

    queue_free()
```

---

### 5. ItemData Serialization

You may need to add serialization to `ItemData`:

```gdscript
# In ItemData class
func to_dict() -> Dictionary:
    return {
        "item_id": item_id,
        "item_name": item_name,
        "rarity": rarity,
        "stack_count": stack_count,
        # ... other properties
        "affixes": _serialize_affixes()  # If applicable
    }

static func from_dict(data: Dictionary) -> ItemData:
    var item := ItemData.new()
    item.item_id = data.get("item_id", "")
    item.item_name = data.get("item_name", "")
    # ... restore other properties
    return item
```

---

### 6. Debug Tools

Add to LootManager:

```gdscript
func debug_print_state() -> void:
    Debug.snapshot("Loot", "LootManager State", {
        "total_drops": _drops.size(),
        "next_id": _next_drop_id,
        "drops": _get_drop_summary()
    })

func _get_drop_summary() -> Array:
    var summary: Array = []
    for drop_id in _drops:
        var drop: DropData = _drops[drop_id]
        summary.append({
            "id": drop_id,
            "type": drop.drop_type,
            "chunk": drop.chunk_id,
            "has_node": drop.node != null
        })
    return summary

func debug_spawn_test_loot(position: Vector2) -> void:
    ## Spawn test loot for debugging
    var test_item := {"item_id": "test_item", "item_name": "Debug Item"}
    register_drop(position, test_item, "item")
```

---

## Files to Reference

Before starting, read these files:
- `autoloads/loot_manager.gd` - Your Phase 1 stub
- `autoloads/chunk_manager.gd` - Chunk signals to connect to
- `scripts/interactable/loot_pickup.gd` - Current loot pickup
- `scripts/interactable/gold_pickup.gd` - Current gold pickup
- `scripts/npc/enemy_npc.gd` - `_drop_loot()` and related
- `scripts/inventory/item_data.gd` - Item data structure

---

## Deliverables

1. Fully implemented `autoloads/loot_manager.gd`:
   - Drop registration and tracking
   - Chunk load/unload handling
   - Visual node recreation
   - Timeout system
   - Saveable interface (clears on save)

2. Updated `scripts/npc/enemy_npc.gd`:
   - Loot drops register with LootManager

3. Updated `scripts/interactable/loot_pickup.gd`:
   - Notifies LootManager on pickup

4. Updated `scripts/interactable/gold_pickup.gd`:
   - Notifies LootManager on collection

5. ItemData serialization if needed

---

## Success Criteria

- [ ] Dropped loot persists when chunk unloads
- [ ] Loot recreated when chunk reloads
- [ ] Player can pick up recreated loot
- [ ] Loot despawns on game save
- [ ] Timeout removes old loot (if enabled)
- [ ] Max drop limit prevents memory issues
- [ ] No duplicate loot on chunk reload
- [ ] Gold and items both work correctly
- [ ] Debug tools functional

---

## Testing Scenarios

1. **Basic Drop**: Kill enemy, verify loot appears and is tracked
2. **Pickup**: Pick up loot, verify removed from LootManager
3. **Chunk Unload**: Drop loot, walk away, return, verify loot still there
4. **Save/Load**: Drop loot, save game, load, verify loot gone (clean save)
5. **Timeout**: Drop loot, wait 10+ minutes, verify expired
6. **Max Drops**: Spawn 100+ drops, verify oldest removed
7. **Mixed Types**: Test both items and gold work correctly
