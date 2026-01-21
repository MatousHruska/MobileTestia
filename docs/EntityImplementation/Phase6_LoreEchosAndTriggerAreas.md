# Phase 6: LoreEchoes & TriggerAreas

**Goal**: Implement audio lore objects and event trigger areas.

---

## Overview

This phase completes the entity system with:

1. **LoreEchoes**: Audio-based lore delivery (stub for future audio)
2. **TriggerAreas**: Invisible areas that trigger events (cutscenes, spawns, quests)

---

## LoreEcho Implementation

### Design

| Aspect | Details |
|--------|---------|
| Interaction | Click = start audio playback |
| Visual | Subtle glow/particle (optional) |
| Audio | Stub for now (shows subtitle text) |
| Duration | Configurable playback time |
| Replay | Configurable (can listen again or one-time) |

### lore_echo.gd (New File)

```gdscript
extends InteractableBase
class_name LoreEcho

## Audio lore object - plays voice/ambient audio when interacted
## Currently a stub - shows subtitle text until audio system exists

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_echo_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_listened: bool = false
var is_playing: bool = false
var _playback_timer: float = 0.0

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    super._ready()
    _load_from_database()
    _restore_persistence()
    _update_visual()


func _process(delta: float) -> void:
    if is_playing:
        _playback_timer -= delta
        if _playback_timer <= 0:
            _on_playback_complete()


func _load_from_database() -> void:
    if database_echo_id.is_empty():
        return

    _config = DatabaseLoader.get_lore_echo(database_echo_id)
    if _config.is_empty():
        push_warning("LoreEcho not found: %s" % database_echo_id)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("echoes", persistence_key)
    if not state.is_empty():
        has_been_listened = state.get("has_been_listened", false)


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("echoes", persistence_key, {
        "has_been_listened": has_been_listened,
        "listened_at": Time.get_unix_time_from_system() if has_been_listened else 0
    })

#===============================================================================
# INTERACTION
#===============================================================================

func can_interact() -> bool:
    if is_playing:
        return false  # Already playing

    # Check if can replay
    if has_been_listened and not _config.get("can_replay", true):
        return false

    return super.can_interact()


func get_interaction_prompt() -> String:
    if is_playing:
        return ""
    if has_been_listened and not _config.get("can_replay", true):
        return ""

    var prompt: String = _config.get("interaction_prompt", "Listen")
    return prompt


func _on_interact() -> void:
    if is_playing:
        return

    _start_playback()


func _start_playback() -> void:
    is_playing = true
    has_been_listened = true
    _save_persistence()
    _update_visual()

    # Set playback duration
    var duration: float = _config.get("duration", 5.0)
    _playback_timer = duration

    # TODO: Play actual audio when audio system exists
    # AudioManager.play_lore(audio_id)

    # For now, show subtitle text
    _show_subtitle_text()

    echo_started.emit()


func _on_playback_complete() -> void:
    is_playing = false
    _update_visual()

    # TODO: Stop audio
    # AudioManager.stop_lore()

    echo_completed.emit()


func _show_subtitle_text() -> void:
    ## Show subtitle as floating text (stub until audio exists)
    var subtitle: String = _config.get("subtitle_text", "...")
    var duration: float = _config.get("duration", 5.0)

    # Use FloatingDialogueManager or custom subtitle system
    if FloatingDialogueManager:
        # Show above player (they're "hearing" it)
        var player = Game.player if Game else null
        var target = player if player else self

        FloatingDialogueManager.show_dialogue(
            database_echo_id,
            target,
            subtitle,
            duration
        )
    else:
        # Fallback: print to console
        print("[LORE] %s" % subtitle)


func _update_visual() -> void:
    if _visual:
        if is_playing:
            # Glowing effect while playing
            _visual.modulate = Color(1.2, 1.2, 1.5, 1.0)
        elif has_been_listened and not _config.get("can_replay", true):
            # Dimmed if already listened and can't replay
            _visual.modulate = Color(0.5, 0.5, 0.5, 0.5)
        else:
            _visual.modulate = Color.WHITE

#===============================================================================
# SIGNALS
#===============================================================================

signal echo_started
signal echo_completed
```

---

## TriggerArea Implementation

### Design

| Aspect | Details |
|--------|---------|
| Trigger | Player enters invisible area |
| Actions | Start cutscene, advance quest, spawn enemies, show dialogue |
| Visual | Invisible in-game (visible in editor/debug) |
| One-shot | Most triggers fire once only |
| Conditions | Quest state requirements |

### trigger_area.gd (New File)

```gdscript
extends Area2D
class_name TriggerArea

## Invisible area that triggers events when player enters

#===============================================================================
# DATABASE PROPERTIES
#===============================================================================

@export var database_trigger_id: String = ""
var persistence_key: String = ""
var _config: Dictionary = {}

#===============================================================================
# STATE
#===============================================================================

var has_been_triggered: bool = false
var _cooldown_timer: float = 0.0
var _is_on_cooldown: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    _load_from_database()
    _restore_persistence()
    _setup_collision()
    _connect_signals()


func _process(delta: float) -> void:
    if _is_on_cooldown:
        _cooldown_timer -= delta
        if _cooldown_timer <= 0:
            _is_on_cooldown = false


func _load_from_database() -> void:
    if database_trigger_id.is_empty():
        return

    _config = DatabaseLoader.get_trigger_area(database_trigger_id)
    if _config.is_empty():
        push_warning("TriggerArea not found: %s" % database_trigger_id)


func _restore_persistence() -> void:
    if persistence_key.is_empty():
        return

    var state := Persistence.load_state("triggers", persistence_key)
    if not state.is_empty():
        has_been_triggered = state.get("has_been_triggered", false)


func _save_persistence() -> void:
    if persistence_key.is_empty():
        return

    Persistence.save_state("triggers", persistence_key, {
        "has_been_triggered": has_been_triggered,
        "triggered_at": Time.get_unix_time_from_system() if has_been_triggered else 0
    })


func _setup_collision() -> void:
    # Collision shape should be set from meta data (size from LDtk)
    var size: Vector2 = get_meta("trigger_size", Vector2(64, 64))

    var collision := CollisionShape2D.new()
    var rect := RectangleShape2D.new()
    rect.size = size
    collision.shape = rect
    collision.position = size / 2  # Center the collision

    add_child(collision)

    # Set collision layer/mask for player only
    collision_layer = 0
    collision_mask = 1  # Player layer


func _connect_signals() -> void:
    body_entered.connect(_on_body_entered)

#===============================================================================
# TRIGGER LOGIC
#===============================================================================

func _on_body_entered(body: Node2D) -> void:
    # Only trigger for player
    if not Game or body != Game.player:
        return

    _try_trigger()


func _try_trigger() -> void:
    # Check if already triggered (one-shot)
    if _config.get("one_shot", true) and has_been_triggered:
        return

    # Check cooldown
    if _is_on_cooldown:
        return

    # Check quest requirements
    if not _check_quest_requirements():
        return

    # Trigger!
    _execute_trigger()


func _check_quest_requirements() -> bool:
    var quest_id: String = _config.get("require_quest_id", "")
    if quest_id.is_empty():
        return true

    var required_state: String = _config.get("require_quest_state", "active")

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


func _execute_trigger() -> void:
    has_been_triggered = true
    _save_persistence()

    # Start cooldown if configured
    var cooldown: float = _config.get("cooldown", 0.0)
    if cooldown > 0:
        _is_on_cooldown = true
        _cooldown_timer = cooldown

    # Execute action based on type
    var trigger_type: String = _config.get("trigger_type", "")
    var target_id: String = _config.get("target_id", "")

    match trigger_type:
        "cutscene":
            _trigger_cutscene(target_id)
        "quest":
            _trigger_quest(target_id)
        "spawn":
            _trigger_spawn(target_id)
        "dialogue":
            _trigger_dialogue(target_id)
        _:
            Debug.warn("TriggerArea", "Unknown trigger type: %s" % trigger_type)

    triggered.emit()


func _trigger_cutscene(cutscene_id: String) -> void:
    if cutscene_id.is_empty():
        return

    if CutsceneManager:
        CutsceneManager.play_cutscene(cutscene_id)
    else:
        Debug.warn("TriggerArea", "CutsceneManager not available")


func _trigger_quest(quest_action: String) -> void:
    ## Format: "quest_id:action" where action is start/complete_objective/complete
    if quest_action.is_empty():
        return

    var parts := quest_action.split(":")
    if parts.size() < 2:
        Debug.warn("TriggerArea", "Invalid quest action format: %s" % quest_action)
        return

    var quest_id: String = parts[0]
    var action: String = parts[1]

    if not QuestManager:
        Debug.warn("TriggerArea", "QuestManager not available")
        return

    match action:
        "start":
            QuestManager.start_quest(quest_id)
        "complete":
            QuestManager.complete_quest(quest_id)
        _:
            # Assume it's an objective ID
            QuestManager.complete_objective(quest_id, action)


func _trigger_spawn(spawn_group_id: String) -> void:
    ## Spawn a group of enemies (ambush)
    if spawn_group_id.is_empty():
        return

    # Get spawn configuration from database or use spawn group
    # This would integrate with EnemySpawnPoint or a dedicated AmbushSpawner
    Debug.log("TriggerArea", "Spawn trigger: %s (TODO: implement)" % spawn_group_id)

    # Example implementation:
    # AmbushManager.spawn_group(spawn_group_id, global_position)


func _trigger_dialogue(dialogue_id: String) -> void:
    if dialogue_id.is_empty():
        return

    if FloatingDialogueManager:
        var dialogue := DatabaseLoader.get_floating_dialogue(dialogue_id)
        var player = Game.player if Game else null
        var target = player if player else self

        FloatingDialogueManager.show_dialogue(
            dialogue_id,
            target,
            dialogue.get("text", "..."),
            dialogue.get("duration", 3.0)
        )

#===============================================================================
# SIGNALS
#===============================================================================

signal triggered
```

---

## ChunkManager Spawn Methods

### LoreEcho Spawning

```gdscript
func _spawn_lore_echo(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var echo_id: String = data.get("id", "")
    if echo_id.is_empty():
        Debug.warn("ChunkManager", "LoreEcho has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [echo_id, int(world_pos.x), int(world_pos.y)]

    # Check if already listened and can't replay
    var config := DatabaseLoader.get_lore_echo(echo_id)
    if not config.is_empty():
        var state := Persistence.load_state("echoes", persistence_key)
        if state.get("has_been_listened", false) and not config.get("can_replay", true):
            Debug.log("ChunkManager", "LoreEcho already listened (no replay): %s" % persistence_key)
            return null

    var echo := LoreEcho.new()
    echo.database_echo_id = echo_id
    echo.persistence_key = persistence_key
    echo.position = world_pos - chunk_origin

    echo.set_meta("chunk_spawned", true)
    echo.set_meta("chunk_id", chunk_id)
    echo.set_meta("world_position", world_pos)

    echo.add_to_group("echoes")

    parent.add_child(echo)
    Debug.log("ChunkManager", "Spawned lore echo: %s at %s" % [echo_id, world_pos])

    return echo
```

### TriggerArea Spawning

```gdscript
func _spawn_trigger_area(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
    var trigger_id: String = data.get("id", "")
    if trigger_id.is_empty():
        Debug.warn("ChunkManager", "TriggerArea has no ID, skipping")
        return null

    var pos: Dictionary = data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    var persistence_key := "%s@%d,%d" % [trigger_id, int(world_pos.x), int(world_pos.y)]

    # Check if already triggered (one-shot)
    var config := DatabaseLoader.get_trigger_area(trigger_id)
    if not config.is_empty() and config.get("one_shot", true):
        var state := Persistence.load_state("triggers", persistence_key)
        if state.get("has_been_triggered", false):
            Debug.log("ChunkManager", "TriggerArea already triggered: %s" % persistence_key)
            return null

    var trigger := TriggerArea.new()
    trigger.database_trigger_id = trigger_id
    trigger.persistence_key = persistence_key
    trigger.position = world_pos - chunk_origin

    # Pass size from LDtk data
    var size: Dictionary = data.get("size", {"w": 64, "h": 64})
    trigger.set_meta("trigger_size", Vector2(size.get("w", 64), size.get("h", 64)))

    trigger.set_meta("chunk_spawned", true)
    trigger.set_meta("chunk_id", chunk_id)
    trigger.set_meta("world_position", world_pos)

    trigger.add_to_group("triggers")

    parent.add_child(trigger)
    Debug.log("ChunkManager", "Spawned trigger area: %s at %s" % [trigger_id, world_pos])

    return trigger
```

### Update _spawn_chunk_entities

```gdscript
# Spawn lore echoes
for echo_data in _zone_entities.get("lore_echoes", []):
    var pos: Dictionary = echo_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_lore_echo(echo_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)

# Spawn trigger areas
for trigger_data in _zone_entities.get("trigger_areas", []):
    var pos: Dictionary = trigger_data.get("position", {})
    var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
    if chunk_bounds.has_point(world_pos):
        var entity := _spawn_trigger_area(trigger_data, chunk_node, chunk_origin, chunk_id)
        if entity:
            spawned_entities.append(entity)
```

---

## Database Samples

### lore_echoes.json

```json
{
  "lore_echoes": [
    {
      "id": "echo_crypt_builder",
      "name": "Builder's Memory",
      "audio_id": "audio_lore_crypt_01",
      "subtitle_text": "We built this crypt to honor the fallen... but something else took residence in these halls.",
      "duration": 8.0,
      "can_replay": true,
      "sprite_id": "echo_glowing_rune",
      "interaction_prompt": "Listen"
    },
    {
      "id": "echo_forest_guardian",
      "name": "Guardian's Warning",
      "audio_id": "audio_lore_forest_01",
      "subtitle_text": "The forest remembers those who came before. Tread carefully, traveler.",
      "duration": 5.0,
      "can_replay": false,
      "sprite_id": "echo_spirit_whisper",
      "interaction_prompt": "Listen"
    }
  ]
}
```

### trigger_areas.json

```json
{
  "trigger_areas": [
    {
      "id": "trigger_forest_ambush",
      "name": "Forest Ambush",
      "trigger_type": "spawn",
      "target_id": "ambush_forest_ghouls",
      "one_shot": true,
      "require_quest_id": "",
      "require_quest_state": "",
      "cooldown": 0
    },
    {
      "id": "trigger_crypt_cutscene",
      "name": "Crypt Entrance Cutscene",
      "trigger_type": "cutscene",
      "target_id": "cutscene_crypt_intro",
      "one_shot": true,
      "require_quest_id": "quest_explore_crypt",
      "require_quest_state": "active",
      "cooldown": 0
    },
    {
      "id": "trigger_quest_complete_area",
      "name": "Quest Completion Zone",
      "trigger_type": "quest",
      "target_id": "quest_explore_forest:obj_reach_clearing",
      "one_shot": true,
      "require_quest_id": "quest_explore_forest",
      "require_quest_state": "active",
      "cooldown": 0
    }
  ]
}
```

---

## Testing Checklist

### LoreEcho Tests
- [ ] LoreEcho spawns at correct position
- [ ] Click interaction starts "playback"
- [ ] Subtitle text displays
- [ ] Duration timer works
- [ ] "has_been_listened" persists
- [ ] Replay works (or doesn't) based on config
- [ ] Visual feedback during playback

### TriggerArea Tests
- [ ] TriggerArea spawns at correct position and size
- [ ] Triggers when player enters
- [ ] One-shot triggers don't repeat
- [ ] Quest requirements work
- [ ] Cooldown works for repeatable triggers
- [ ] Cutscene trigger starts cutscene
- [ ] Quest trigger advances quest
- [ ] Spawn trigger creates enemies
- [ ] Dialogue trigger shows dialogue

### Integration Tests
- [ ] TriggerArea + Cutscene flow works
- [ ] TriggerArea + Quest advancement works
- [ ] Save/load preserves trigger states
- [ ] Chunk unload/reload handles triggers correctly

---

## Future: Audio System Integration

When audio system is implemented:

```gdscript
# In LoreEcho._start_playback()
func _start_playback() -> void:
    is_playing = true
    has_been_listened = true
    _save_persistence()
    _update_visual()

    var audio_id: String = _config.get("audio_id", "")
    if not audio_id.is_empty() and AudioManager:
        # Play actual audio
        AudioManager.play_lore(audio_id)
        # Connect to completion signal
        AudioManager.lore_completed.connect(_on_audio_complete, CONNECT_ONE_SHOT)
    else:
        # Fallback to subtitle
        var duration: float = _config.get("duration", 5.0)
        _playback_timer = duration
        _show_subtitle_text()

    echo_started.emit()


func _on_audio_complete() -> void:
    is_playing = false
    _update_visual()
    echo_completed.emit()
```

---

## Success Criteria

- [ ] LoreEchoes spawn and show subtitle text
- [ ] LoreEchoes persist "listened" state
- [ ] TriggerAreas spawn with correct size
- [ ] TriggerAreas fire appropriate actions
- [ ] Quest-conditional triggers work
- [ ] One-shot triggers don't repeat
- [ ] Save/load preserves all states

---

## Phase Complete!

After this phase, all entity types are implemented:

| Entity | Status |
|--------|--------|
| Doors | Complete |
| Levers | Complete |
| Pressure Plates | Complete |
| NPCs | Complete |
| Lootables | Complete |
| Signs | Complete |
| Lore Echoes | Complete |
| Trigger Areas | Complete |

### Next Steps

1. **Integration Testing**: Full playthrough with all entity types
2. **Performance Testing**: Many entities in same zone
3. **Polish**: Visual effects, sounds, UI feedback
4. **Documentation**: Update LDTK_MAP_REFERENCE.md with new entities
