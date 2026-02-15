# Phase 1: AbilityVisual Resource + Phase Sequencer

> **Goal**: Create the core data structure and executor that drives all ability visuals in the game. This is the foundation — everything else builds on it.

---

## Context

We are building a modular attack visual system. Instead of hardcoding animation logic per ability type (as currently done in `combat_hud.gd` and `enemy_npc.gd`), every ability will be driven by a **sequence of visual phases**. Each phase describes what happens visually: body animation, weapon visibility, movement, VFX, damage events, projectile spawning, etc.

This phase does NOT touch existing files. It only creates new files. Later phases will wire them in.

---

## Architecture Overview

The system has two parts:

### 1. `AbilityVisualData` (Resource) — the data

A Godot `Resource` that defines a sequence of phases for one visual template. Saved as `.tres` files or constructed in code.

### 2. `AbilityVisualPlayer` (Node) — the executor

A node attached to any character that reads an `AbilityVisualData`, steps through its phases using timers/tweens, and emits signals at key moments (damage frame, projectile spawn, etc.). The character's existing combat code listens to these signals instead of managing timing itself.

---

## What To Create

### File 1: `scripts/combat/ability_visual_data.gd`

```
class_name AbilityVisualData
extends Resource
```

This resource defines a **visual template** — a named sequence of phases.

#### Properties:

```gdscript
## Unique template ID (e.g., "melee_single", "spell_cast", "throw")
@export var template_id: String = ""

## Human-readable name for editor/debug
@export var display_name: String = ""

## The sequence of phases (executed in order)
@export var phases: Array[AbilityVisualPhase] = []

## Whether the character is movement-locked for the entire sequence
## (individual phases can override this)
@export var locks_movement: bool = true
```

#### Phase Sub-Resource: `AbilityVisualPhase`

Define this as a separate inner resource (or a separate file `scripts/combat/ability_visual_phase.gd` — your choice, but keeping it as a separate class_name resource is cleaner for the inspector):

```gdscript
class_name AbilityVisualPhase
extends Resource
```

Each phase has:

```gdscript
## Phase type determines behavior
enum PhaseType {
    BODY_ANIM,      ## Play a body animation (e.g., "melee_windup", "cast")
    MOVEMENT,        ## Tween-based movement (lunge, dash, jump_back)
    DAMAGE_EVENT,    ## Signal to apply damage (hitbox check happens externally)
    SPAWN_PROJECTILE,## Signal to spawn a projectile
    WAIT,            ## Pure wait/delay
    WEAPON_VISIBILITY, ## Show/hide weapon layer
    EFFECT,          ## Spawn/trigger a VFX on the effect anchor
}

## What this phase does
@export var type: PhaseType = PhaseType.BODY_ANIM

## Duration in seconds (0 = instant, plays alongside next phase)
## For BODY_ANIM: 0 means "use animation length"
@export var duration: float = 0.0

## --- BODY_ANIM properties ---
## Animation action name (without direction suffix). e.g., "melee_windup"
## The system appends "_{down/up/right}" automatically based on facing.
## Falls back to "attack_{dir}" if the specific animation doesn't exist.
@export var anim_name: String = ""

## --- MOVEMENT properties ---
## Movement direction relative to facing:
##   "toward_target" = lunge toward current target
##   "away_from_target" = jump backward
##   "facing" = move in facing direction
@export var move_direction: String = "toward_target"

## Movement distance in pixels
@export var move_distance: float = 0.0

## --- WEAPON_VISIBILITY ---
@export var weapon_visible: bool = true

## --- EFFECT ---
## Effect identifier (looked up from a registry or spawned by name)
@export var effect_id: String = ""

## --- Timing ---
## If true, this phase runs concurrently with the next phase
## (useful for playing animation + movement at the same time)
@export var concurrent: bool = false
```

**Important design notes:**
- `duration = 0` on a `BODY_ANIM` phase means "wait for the animation to finish" (use `animation_finished` signal). This is the common case.
- `concurrent = true` means "start this phase AND the next phase at the same time." This lets you combine a body animation with a lunge movement in a single visual beat.
- Phases with `duration > 0` use a timer. Phases with `duration = 0` on non-BODY_ANIM types are instant (execute and immediately move to next).

---

### File 2: `scripts/combat/ability_visual_player.gd`

```gdscript
class_name AbilityVisualPlayer
extends Node
```

This node is added as a child of any character (player or enemy). It orchestrates playback.

#### Signals:

```gdscript
## Emitted when the full sequence starts
signal sequence_started(template_id: String)

## Emitted when the full sequence finishes (all phases done)
signal sequence_finished(template_id: String)

## Emitted on DAMAGE_EVENT phase — the combat system listens to this
signal damage_event()

## Emitted on SPAWN_PROJECTILE phase — combat system spawns projectile
signal spawn_projectile_event()

## Emitted on EFFECT phase — VFX system spawns effect
signal effect_event(effect_id: String)

## Emitted on WEAPON_VISIBILITY phase
signal weapon_visibility_changed(visible: bool)

## Emitted when any body animation phase starts (for the sprite system)
signal play_body_animation(anim_name: String)

## Emitted on MOVEMENT phase (for the character controller to execute)
signal movement_requested(direction: String, distance: float, duration: float)
```

#### Key Properties:

```gdscript
## Whether a sequence is currently playing
var is_playing: bool = false

## Current sequence being played
var _current_data: AbilityVisualData = null

## Current phase index
var _current_phase_index: int = -1

## Timer for timed phases
var _phase_timer: float = 0.0

## Whether we're waiting for an animation to finish
var _waiting_for_anim: bool = false

## Reference to the character's AnimatedSprite2D (set via initialize())
var _sprite: AnimatedSprite2D = null

## Target position for "toward_target" / "away_from_target" movement
var _target_position: Vector2 = Vector2.ZERO
```

#### Key Methods:

```gdscript
## Call once to wire up the sprite reference
func initialize(sprite: AnimatedSprite2D) -> void

## Start playing a visual sequence. Optionally provide a target position
## for directional movement phases.
func play(data: AbilityVisualData, target_pos: Vector2 = Vector2.ZERO) -> void

## Stop/cancel the current sequence
func cancel() -> void

## Called every frame (from _process or _physics_process)
func _process(delta: float) -> void
```

#### Execution Logic (pseudocode):

```
func play(data, target_pos):
    _current_data = data
    _target_position = target_pos
    _current_phase_index = -1
    is_playing = true
    sequence_started.emit(data.template_id)
    _advance_to_next_phase()

func _advance_to_next_phase():
    _current_phase_index += 1

    if _current_phase_index >= _current_data.phases.size():
        _finish_sequence()
        return

    var phase = _current_data.phases[_current_phase_index]
    _execute_phase(phase)

    # If concurrent, also start the next phase immediately
    if phase.concurrent and _current_phase_index + 1 < _current_data.phases.size():
        # Don't increment — _advance handles it. Instead, queue next.
        # Use call_deferred or handle concurrency via a list of "active phases"
        pass  # See concurrency note below

func _execute_phase(phase):
    match phase.type:
        BODY_ANIM:
            play_body_animation.emit(phase.anim_name)
            if phase.duration > 0:
                _phase_timer = phase.duration
                _waiting_for_anim = false
            else:
                _waiting_for_anim = true
                # Connect to sprite.animation_finished (one-shot)
        MOVEMENT:
            movement_requested.emit(phase.move_direction, phase.move_distance, phase.duration)
            _phase_timer = phase.duration
        DAMAGE_EVENT:
            damage_event.emit()
            _advance_to_next_phase()  # Instant
        SPAWN_PROJECTILE:
            spawn_projectile_event.emit()
            _advance_to_next_phase()  # Instant
        WEAPON_VISIBILITY:
            weapon_visibility_changed.emit(phase.weapon_visible)
            _advance_to_next_phase()  # Instant
        EFFECT:
            effect_event.emit(phase.effect_id)
            if phase.duration > 0:
                _phase_timer = phase.duration
            else:
                _advance_to_next_phase()
        WAIT:
            _phase_timer = phase.duration

func _process(delta):
    if not is_playing:
        return
    if _phase_timer > 0:
        _phase_timer -= delta
        if _phase_timer <= 0:
            _advance_to_next_phase()
    # _waiting_for_anim is resolved by the animation_finished callback

func _on_animation_finished():
    if _waiting_for_anim:
        _waiting_for_anim = false
        _advance_to_next_phase()

func _finish_sequence():
    is_playing = false
    sequence_finished.emit(_current_data.template_id)
```

#### Concurrency Handling:

When a phase has `concurrent = true`, both it and the next phase execute simultaneously. The simplest approach:
- Track a list of "active timed phases" instead of a single timer.
- When all active phases have resolved (timers expired or anim finished), advance past the concurrent block.
- For Phase 1 implementation, a simpler two-slot approach is fine: `_primary_timer` and `_concurrent_timer`. Advance when both reach zero.

---

### File 3: `scripts/combat/ability_visual_templates.gd`

A static helper that constructs the built-in visual templates in code. This avoids needing `.tres` files for every template during development.

```gdscript
class_name AbilityVisualTemplates

## Returns a dictionary of template_id -> AbilityVisualData
## These are the standard templates that abilities reference by name.
static func get_all() -> Dictionary:
    return {
        "melee_single": _melee_single(),
        "melee_combo_2": _melee_combo_2(),
        "melee_combo_3": _melee_combo_3(),
        "dash_attack": _dash_attack(),
        "ranged_aim": _ranged_aim(),
        "spell_cast": _spell_cast(),
        "spell_instant": _spell_instant(),
        "throw": _throw(),
        "self_buff": _self_buff(),
    }
```

Each factory function builds an `AbilityVisualData` with the appropriate phases. Here are the exact phase sequences for each template:

#### `melee_single` — Standard melee attack
```
Phase 0: WEAPON_VISIBILITY(visible=true), concurrent=false        # instant
Phase 1: BODY_ANIM("melee_windup", duration=0), concurrent=true   # play anim, wait for finish
         + WAIT(duration from ability windup time — overridden at play time)
Phase 2: MOVEMENT("toward_target", distance=lunge_force, duration=0.15), concurrent=true
         + BODY_ANIM("melee_strike", duration=0)
Phase 3: DAMAGE_EVENT                                              # instant
Phase 4: BODY_ANIM("idle", duration=0)                            # return to idle
Phase 5: WEAPON_VISIBILITY(visible=true)                           # weapon stays visible
```

**NOTE on timing overrides:** The templates define the *shape* of the sequence. Actual durations (windup time, lunge distance, recovery time) come from the ability data (`TalentData` or `AbilityData`). The `play()` call should accept an optional `Dictionary` of overrides that patch phase durations before execution. Define this as:

```gdscript
## In AbilityVisualPlayer:
func play(data: AbilityVisualData, target_pos: Vector2 = Vector2.ZERO, overrides: Dictionary = {}) -> void
```

Overrides dictionary keys:
- `"windup_duration"` — replaces duration of first BODY_ANIM or WAIT phase
- `"lunge_distance"` — replaces move_distance of MOVEMENT phases
- `"lunge_duration"` — replaces duration of MOVEMENT phases
- `"recovery_duration"` — replaces duration of final WAIT/BODY_ANIM phase

The template factory functions should **tag phases** with override keys so the player knows which phase to patch. Add a property to `AbilityVisualPhase`:

```gdscript
## Override key — if set, play() overrides can patch this phase's duration/distance
## e.g., "windup", "lunge", "recovery"
@export var override_key: String = ""
```

#### `melee_combo_2` — Two-hit melee combo
```
Phase 0: WEAPON_VISIBILITY(visible=true)
Phase 1: BODY_ANIM("melee_windup"), override_key="windup"
Phase 2: MOVEMENT("toward_target") + BODY_ANIM("melee_strike"), concurrent, override_key="lunge"
Phase 3: DAMAGE_EVENT
Phase 4: WAIT(0.1)  # brief pause between hits
Phase 5: BODY_ANIM("melee_strike")  # second strike (reuses same anim)
Phase 6: DAMAGE_EVENT
Phase 7: BODY_ANIM("idle"), override_key="recovery"
```

#### `melee_combo_3` — Three-hit melee combo
Same pattern as combo_2 with an additional strike+damage pair.

#### `dash_attack` — Rush forward then strike
```
Phase 0: WEAPON_VISIBILITY(visible=true)
Phase 1: BODY_ANIM("dash") + MOVEMENT("toward_target"), concurrent, override_key="dash"
Phase 2: BODY_ANIM("melee_strike")
Phase 3: DAMAGE_EVENT
Phase 4: BODY_ANIM("idle"), override_key="recovery"
```

#### `ranged_aim` — Hold-to-charge ranged shot
```
Phase 0: WEAPON_VISIBILITY(visible=true)
Phase 1: BODY_ANIM("aim"), override_key="charge"  # held until released externally
Phase 2: BODY_ANIM("aim_release")
Phase 3: SPAWN_PROJECTILE
Phase 4: BODY_ANIM("idle"), override_key="recovery"
```

**Note:** The "aim" phase is special — it runs until the player releases the button. The CombatHUD will call a method like `advance_held_phase()` on release. For Phase 1, implement this with a flag:

```gdscript
## Set to true to hold the current phase until release
var _phase_held: bool = false

func hold_current_phase() -> void
func release_held_phase() -> void
```

#### `spell_cast` — Cast-time spell (like fireball)
```
Phase 0: WEAPON_VISIBILITY(visible=false)  # hide weapon for casting
Phase 1: BODY_ANIM("cast") + EFFECT("cast_circle"), concurrent, override_key="cast"
Phase 2: BODY_ANIM("cast_release")
Phase 3: SPAWN_PROJECTILE  # or DAMAGE_EVENT for non-projectile spells
Phase 4: WEAPON_VISIBILITY(visible=true)  # restore weapon
Phase 5: BODY_ANIM("idle"), override_key="recovery"
```

#### `spell_instant` — Instant-cast spell (like heal)
```
Phase 0: WEAPON_VISIBILITY(visible=false)
Phase 1: BODY_ANIM("cast_release")
Phase 2: EFFECT("spell_burst")
Phase 3: DAMAGE_EVENT  # or heal event — combat system interprets based on ability data
Phase 4: WEAPON_VISIBILITY(visible=true)
Phase 5: BODY_ANIM("idle"), override_key="recovery"
```

#### `throw` — Throw an object (bomb, potion, etc.)
```
Phase 0: WEAPON_VISIBILITY(visible=false)  # weapon hidden, hand holds object
Phase 1: BODY_ANIM("throw_windup") + EFFECT("show_held_item"), concurrent, override_key="windup"
Phase 2: BODY_ANIM("throw_release")
Phase 3: SPAWN_PROJECTILE  # the thrown object
Phase 4: WEAPON_VISIBILITY(visible=true)
Phase 5: BODY_ANIM("idle"), override_key="recovery"
```

#### `self_buff` — Cast a buff on self
```
Phase 0: WEAPON_VISIBILITY(visible=false)
Phase 1: BODY_ANIM("cast"), override_key="cast"
Phase 2: EFFECT("buff_burst")
Phase 3: DAMAGE_EVENT  # combat system applies the buff (not damage)
Phase 4: WEAPON_VISIBILITY(visible=true)
Phase 5: BODY_ANIM("idle"), override_key="recovery"
```

---

## Animation Name Fallback Chain

When `play_body_animation` is emitted with an `anim_name` like `"melee_windup"`, the sprite system should try:

1. `melee_windup_{direction}` (e.g., `melee_windup_down`) — ideal
2. `melee_windup` — directionless fallback
3. `attack_{direction}` (e.g., `attack_down`) — legacy fallback
4. `idle_{direction}` — final fallback

This fallback chain is critical because **in Phase 1, we won't have the new body animations yet** (those come in Phase 3). So the system will gracefully fall back to existing `attack_{dir}` animations until the sprite generators are updated. This means the sequencer is testable immediately.

Implement this fallback in `AbilityVisualPlayer` by having the `play_body_animation` signal handler (on the character side) do the lookup. Or put a helper method on `AbilityVisualPlayer` itself:

```gdscript
func _resolve_animation_name(base_name: String, direction: String) -> String:
    ## Try specific, then directionless, then "attack", then "idle"
    var candidates := [
        "%s_%s" % [base_name, direction],
        base_name,
        "attack_%s" % direction,
        "idle_%s" % direction,
    ]
    for candidate in candidates:
        if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(candidate):
            return candidate
    return "idle_%s" % direction  # absolute last resort
```

---

## Folder Structure

Create these files:
```
scripts/combat/ability_visual_phase.gd     # AbilityVisualPhase resource
scripts/combat/ability_visual_data.gd      # AbilityVisualData resource
scripts/combat/ability_visual_player.gd    # AbilityVisualPlayer node
scripts/combat/ability_visual_templates.gd # Static template factory
```

---

## What NOT To Do In This Phase

- Do NOT modify `base_character.gd`, `player_controller.gd`, `player_animator.gd`, `combat_hud.gd`, or `enemy_npc.gd`. Those are wired in Phases 4 and 5.
- Do NOT modify the sprite generators. That's Phase 3.
- Do NOT modify the database VBA/JSON. That's Phase 6.
- Do NOT create the CharacterVisuals layered sprite stack. That's Phase 2.

This phase is purely about creating the new resource types and the sequencer node. They should be fully functional but disconnected from the rest of the game until later phases wire them in.

---

## Testing / Validation

After creating the files, verify:
1. The scripts parse without errors (no syntax issues, all class_names resolve).
2. `AbilityVisualTemplates.get_all()` returns a dictionary of valid `AbilityVisualData` resources.
3. Each template's phases have sensible defaults.
4. The `AbilityVisualPlayer` can be instantiated, `initialize()`d with a mock sprite, and `play()` called without crashing.
5. The signal flow works: playing a melee_single template emits `sequence_started`, `play_body_animation`, `movement_requested`, `damage_event`, `sequence_finished` in the correct order.

You can add a simple test or print statements to verify signal flow if helpful, but formal unit tests are not required.

---

## Existing Code Reference

These files are relevant context (READ them before starting):

| File | Why |
|------|-----|
| `scripts/data/ability_data.gd` | Enemy ability data — has `windup`, `recovery`, `animation`, `dash_speed` fields that map to override keys |
| `scripts/data/talent_data.gd` | Player talent data — has `lunge_force`, `lunge_duration`, `recovery_time`, `cast_time`, `effect_type` fields |
| `scripts/npc/base_character.gd` | Current animation system — `AnimState` enum, `play_attack()`, `_get_animation_name()` |
| `scripts/player/player_animator.gd` | Player animation — `State` enum, `_play_anim()`, weapon anchor scanning |
| `scripts/player/player_controller.gd` | Player combat — `request_attack()`, `apply_skill_lunge()`, casting system |
| `scripts/ui/combat/combat_hud.gd` | Skill execution — `_apply_skill_mechanics()`, projectile spawning, aim indicator |
| `scripts/combat/projectile.gd` | Physical projectile — `Projectile.create_arrow()` |
| `scripts/combat/magic_projectile.gd` | Magic projectile — `MagicProjectile.create_fireball()` |
| `scenes/player/player.tscn` | Player scene tree structure |

---

*This prompt is Phase 1 of 6 in the Ability Visual System implementation.*
