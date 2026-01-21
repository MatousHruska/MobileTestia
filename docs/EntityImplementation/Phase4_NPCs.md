# Phase 4: NPC Spawning

**Goal**: Implement NPC spawning via ChunkManager, replacing manual scene placement.

---

## Overview

NPCs already have database support via `DatabaseNPC`. This phase:
1. Adds NPC extraction to LDtk importer (done in Phase 2)
2. Adds NPC spawning to ChunkManager
3. Handles NPC lifecycle with chunks
4. Considers special cases (hub NPCs, quest NPCs)

---

## Current NPC System

### Existing Components

| Component | File | Status |
|-----------|------|--------|
| FriendlyNPC | `scripts/npc/friendly_npc.gd` | Base class, working |
| DatabaseNPC | `scripts/npc/database_npc.gd` | Database loading, working |
| NPCDatabase | `databases/vba/NPCDatabase.bas` | VBA export, working |
| npcs.json | `databases/exports/npcs.json` | JSON data, working |
| NPCManager | `autoloads/npc_manager.gd` | Tracking, working |

### Current Placement

NPCs are currently placed manually in zone scenes:
```gdscript
# zone_test_hub.tscn
[node name="QuestGiver" parent="FriendlyNPCs" instance=ExtResource("database_npc.tscn")]
position = Vector2(280, 0)
database_id = "npc_quest_giver_main"
```

---

## ChunkManager NPC Spawning

### Spawn Method

```gdscript
#===============================================================================
# NPC SPAWNING
#===============================================================================

func _spawn_npc(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var npc_id: String = data.get("id", "")
    if npc_id.is_empty():
        Debug.warn("ChunkManager", "NPC has no ID, skipping")
        return null

    # Check if NPC should spawn (quest conditions, etc.)
    if not _should_spawn_npc(npc_id):
        Debug.log("ChunkManager", "NPC spawn conditions not met: %s" % npc_id)
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))

    # Try to load DatabaseNPC scene
    var npc: Node2D = null
    var scene_path := "res://scenes/prefabs/database_npc.tscn"
    if ResourceLoader.exists(scene_path):
        var scene := load(scene_path) as PackedScene
        if scene:
            npc = scene.instantiate()

    if npc == null:
        # Fallback: create programmatically
        npc = _create_npc_programmatic(npc_id)

    if npc == null:
        Debug.warn("ChunkManager", "Could not create NPC: %s" % npc_id)
        return null

    # Configure NPC
    if "database_id" in npc:
        npc.database_id = npc_id

    # Position relative to chunk
    npc.position = world_pos - chunk_origin

    # Mark as chunk-spawned
    npc.set_meta("chunk_spawned", true)
    npc.set_meta("chunk_id", chunk_id)
    npc.set_meta("world_position", world_pos)

    npc.add_to_group("npcs")

    parent.add_child(npc)
    Debug.log("ChunkManager", "Spawned NPC: %s at %s" % [npc_id, world_pos])

    return npc


func _create_npc_programmatic(npc_id: String) -> Node2D:
    var npc_script := load("res://scripts/npc/database_npc.gd")
    if npc_script:
        var node := CharacterBody2D.new()
        node.set_script(npc_script)
        if "database_id" in node:
            node.database_id = npc_id
        return node
    Debug.warn("ChunkManager", "Could not load database_npc.gd")
    return null


func _should_spawn_npc(npc_id: String) -> bool:
    ## Check if NPC should spawn based on quest state, etc.
    var config := DatabaseLoader.get_npc(npc_id)
    if config.is_empty():
        return true  # No config = always spawn

    # Check spawn conditions from database
    var spawn_condition: String = config.get("spawn_condition", "")
    if spawn_condition.is_empty():
        return true

    # Parse condition (format: "quest_id:state" or "flag:value")
    var parts := spawn_condition.split(":")
    if parts.size() != 2:
        return true

    var condition_type: String = parts[0]
    var condition_value: String = parts[1]

    match condition_type:
        "quest_active":
            return QuestManager.is_quest_active(condition_value) if QuestManager else true
        "quest_completed":
            return QuestManager.is_quest_completed(condition_value) if QuestManager else true
        "quest_not_started":
            var active := QuestManager.is_quest_active(condition_value) if QuestManager else false
            var completed := QuestManager.is_quest_completed(condition_value) if QuestManager else false
            return not active and not completed

    return true
```

### Update _spawn_chunk_entities

```gdscript
# Spawn NPCs
for npc_data in _zone_entities.get("npcs", []):
    var pos: Dictionary = npc_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_npc(npc_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)
```

---

## NPC Persistence Considerations

### What to Persist

| Data | Persist? | Notes |
|------|----------|-------|
| Position | No | NPCs return to spawn point |
| Dialogue state | Yes | Via QuestManager/DialogueManager |
| Shop inventory | Partial | Changes persist if implemented |
| Quest progress | Yes | Via QuestManager |
| NPC-specific flags | Yes | Via Persistence "npcs" category |

### NPC State Persistence

For NPCs with unique states (talked to, given item, etc.):

```gdscript
# In DatabaseNPC or FriendlyNPC

func _save_npc_state() -> void:
    if database_id.is_empty():
        return

    var state := {
        "has_talked": has_talked,
        "gift_given": gift_given,
        # Add other NPC-specific state
    }

    Persistence.save_state("npcs", database_id, state)


func _restore_npc_state() -> void:
    if database_id.is_empty():
        return

    var state := Persistence.load_state("npcs", database_id)
    if state.is_empty():
        return

    has_talked = state.get("has_talked", false)
    gift_given = state.get("gift_given", false)
```

---

## NPCDatabase Updates

Add spawn condition field:

```
| Column | Type | Description |
|--------|------|-------------|
| spawn_condition | String | Condition for NPC to appear |
```

**Spawn Condition Format:**
- `""` - Always spawn (default)
- `"quest_active:quest_id"` - Only when quest is active
- `"quest_completed:quest_id"` - Only after quest complete
- `"quest_not_started:quest_id"` - Only before quest starts

---

## Special Cases

### 1. Hub Zone NPCs

Hub zones (like towns) may not use chunk loading. Options:
- **Option A**: Hub NPCs remain manually placed in scene
- **Option B**: Hub zones still use ChunkManager but load all chunks permanently
- **Option C**: Separate "zone-level" NPC list that spawns with zone, not chunks

**Recommendation**: Option A for hub zones - keep manual placement for guaranteed presence.

### 2. Quest NPCs

NPCs that appear/disappear based on quest state:
- Use `spawn_condition` in database
- ChunkManager checks condition before spawning
- On quest state change, NPCs respawn on next chunk load/unload cycle

### 3. Escort NPCs

NPCs that follow player during escort quests:
- NOT spawned by ChunkManager
- Spawned by EscortQuestHandler
- Position persisted separately (escort_npcs category)
- Move between chunks with player

### 4. NPC Death/Removal

If NPCs can be killed or removed:
- Mark as dead in Persistence
- ChunkManager skips spawning dead NPCs
- Respawn logic if needed (timer or quest)

---

## NPC Manager Integration

NPCs register with NPCManager on _ready(). No changes needed, but verify:

```gdscript
# In FriendlyNPC._ready()
if NPCManager:
    NPCManager.register_friendly(self)
```

This happens automatically when NPC is added to scene tree.

---

## Testing Checklist

### Basic Spawning
- [ ] NPC spawns at correct position from LDtk data
- [ ] NPC loads data from database (name, type, dialogue)
- [ ] NPC registers with NPCManager
- [ ] NPC visual appears correctly

### Chunk Lifecycle
- [ ] NPC despawns when chunk unloads
- [ ] NPC respawns when chunk reloads
- [ ] NPC state restored from persistence

### Quest Conditions
- [ ] NPC with `quest_active` condition only appears during quest
- [ ] NPC with `quest_completed` condition appears after quest
- [ ] NPC with no condition always appears

### Interaction
- [ ] Player can interact with chunk-spawned NPC
- [ ] Dialogue system works
- [ ] Shop system works
- [ ] Quest giving works

### Edge Cases
- [ ] Multiple NPCs in same chunk all spawn
- [ ] NPC at chunk boundary spawns in correct chunk
- [ ] Save/load preserves NPC state

---

## Files Modified

| File | Changes |
|------|---------|
| `autoloads/chunk_manager.gd` | Add `_spawn_npc()`, update entity spawning |
| `databases/vba/NPCDatabase.bas` | Add spawn_condition field |
| `scripts/npc/database_npc.gd` | Possibly add state persistence |

---

## Success Criteria

- [ ] NPCs spawn from ChunkManager using LDtk data
- [ ] NPCs load all properties from database
- [ ] NPCs register with NPCManager correctly
- [ ] Interaction systems work (dialogue, shop, quest)
- [ ] Quest-conditional spawning works
- [ ] Save/load preserves relevant state

---

## Next Phase

After NPC spawning is complete, proceed to **Phase 5: Lootables & Signs** to implement quick-loot containers and readable signs.
