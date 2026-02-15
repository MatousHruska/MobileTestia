# Phase 4: Wire Player Combat to the Visual Sequencer

> **Goal**: Replace the inline animation/lunge/projectile logic in `CombatHUD` and `PlayerController` with the `AbilityVisualPlayer` sequencer. After this, all player abilities are driven by visual templates.

> **Depends on**: Phase 1 (sequencer exists), Phase 2 (CharacterVisuals exists), Phase 3 (body animations exist)

---

## Context

Currently, `CombatHUD` handles all player skill execution inline:
- **Melee skills** (`DAMAGE` effect_type): Directly calls `player.request_attack()`, then `player.apply_skill_lunge()`, then manually checks enemies in range after a recovery timer.
- **Ranged skills** (`PROJECTILE`): Manages aim indicator, charge time, and spawns `Projectile.create_arrow()` directly.
- **Magic skills** (`MAGIC_PROJECTILE` / `MAGIC_PROJECTILE_AOE`): Calls `player.start_cast()`, waits for `cast_completed` signal, then spawns `MagicProjectile.create_fireball()`.
- **Self-buffs** (`SELF_BUFF`): Uses the cast bar system, then applies stats.

All of this visual orchestration should move to the sequencer. The combat HUD becomes a **trigger** (press button -> look up template -> call visual_player.play()) and a **signal listener** (damage_event -> apply damage, spawn_projectile -> create projectile).

---

## What To Modify

### File 1: `scripts/player/player_controller.gd`

#### Add AbilityVisualPlayer as a child node:

```gdscript
var ability_visual_player: AbilityVisualPlayer = null

func _ready() -> void:
    # ... existing code ...
    _setup_ability_visual_player()

func _setup_ability_visual_player() -> void:
    ability_visual_player = AbilityVisualPlayer.new()
    ability_visual_player.name = "AbilityVisualPlayer"
    add_child(ability_visual_player)

    # Initialize with the sprite
    if animator:
        ability_visual_player.initialize(animator)

    # Connect movement signal — the visual player requests movement,
    # PlayerController executes it
    ability_visual_player.movement_requested.connect(_on_visual_movement_requested)

    # Connect sequence lifecycle
    ability_visual_player.sequence_started.connect(_on_visual_sequence_started)
    ability_visual_player.sequence_finished.connect(_on_visual_sequence_finished)

    # Connect body animation signal to CharacterVisuals
    if character_visuals:
        character_visuals.connect_to_visual_player(ability_visual_player)
```

#### Handle movement requests from the sequencer:

```gdscript
func _on_visual_movement_requested(direction: String, distance: float, duration: float) -> void:
    ## Execute movement requested by the visual sequencer
    var move_dir: Vector2

    match direction:
        "toward_target":
            # Use the facing direction as proxy for "toward target"
            move_dir = _facing_to_vector(current_facing)
        "away_from_target":
            move_dir = -_facing_to_vector(current_facing)
        "facing":
            move_dir = _facing_to_vector(current_facing)
        _:
            move_dir = _facing_to_vector(current_facing)

    # Use the existing lunge system
    _lunge_velocity = move_dir * (distance / max(duration, 0.01))
    _lunge_timer = duration

    Debug.log("Combat", "Visual movement", {"dir": direction, "dist": distance, "dur": duration})
```

#### Handle sequence lifecycle:

```gdscript
func _on_visual_sequence_started(template_id: String) -> void:
    is_attacking = true
    is_locked = true  # Lock movement during ability animation
    attack_started.emit()
    Debug.log("Combat", "Visual sequence started: %s" % template_id)

func _on_visual_sequence_finished(template_id: String) -> void:
    is_attacking = false
    is_locked = false
    attack_ended.emit()
    Debug.log("Combat", "Visual sequence finished: %s" % template_id)
```

#### New method to play ability visuals:

```gdscript
func play_ability_visual(template_id: String, overrides: Dictionary = {}, target_pos: Vector2 = Vector2.ZERO) -> void:
    ## Called by CombatHUD to trigger an ability's visual sequence
    if ability_visual_player.is_playing:
        Debug.warn("Combat", "Tried to play visual while one is active")
        return

    var template: AbilityVisualData = AbilityVisualTemplates.get_all().get(template_id)
    if not template:
        Debug.warn("Combat", "Unknown visual template: %s" % template_id)
        # Fallback to legacy attack
        request_attack()
        return

    # Snap facing if we have input
    if input_direction != Vector2.ZERO:
        _snap_facing_to_cardinal(input_direction)

    ability_visual_player.play(template, target_pos, overrides)
```

---

### File 2: `scripts/player/player_animator.gd`

#### Update to handle body animation signals:

The `AbilityVisualPlayer` emits `play_body_animation` which `CharacterVisuals` handles. But `PlayerAnimator` also needs to know about the sequencer's state to avoid overriding one-shot animations:

```gdscript
## Add reference:
var _visual_player: AbilityVisualPlayer = null

func _ready() -> void:
    # ... existing code ...

    # If parent has an AbilityVisualPlayer, listen to it
    _controller = get_parent() as PlayerController
    if _controller and _controller.ability_visual_player:
        _visual_player = _controller.ability_visual_player
        _visual_player.sequence_started.connect(_on_visual_sequence_started)
        _visual_player.sequence_finished.connect(_on_visual_sequence_finished)

var _in_visual_sequence: bool = false

func _on_visual_sequence_started(_template_id: String) -> void:
    _in_visual_sequence = true

func _on_visual_sequence_finished(_template_id: String) -> void:
    _in_visual_sequence = false
    _play_anim(State.IDLE)
```

#### Don't override animations during visual sequences:

```gdscript
func _process(_delta: float) -> void:
    if not _controller:
        return

    # Don't override during visual sequences or one-shot animations
    if _in_visual_sequence or _current_state == State.ATTACK or _current_state == State.DASH:
        return

    # ... rest of existing movement/idle logic ...
```

---

### File 3: `scripts/ui/combat/combat_hud.gd`

This is the biggest change. The combat HUD currently has deeply embedded animation/movement logic for each skill type. We need to:

1. **Determine the visual template** based on the skill's `effect_type`
2. **Build the overrides dictionary** from the skill's data (lunge_force, recovery_time, cast_time, etc.)
3. **Call `player.play_ability_visual(template_id, overrides, target_pos)`**
4. **Listen to sequencer signals** for damage application and projectile spawning

#### Add template mapping:

```gdscript
## Map TalentData.EffectType to visual template IDs
static func _get_visual_template_for_talent(talent: TalentData) -> String:
    match talent.effect_type:
        TalentData.EffectType.DAMAGE:
            # Melee skill — check if it has multiple hits (future), default single
            return "melee_single"
        TalentData.EffectType.PROJECTILE:
            return "ranged_aim"
        TalentData.EffectType.MAGIC_PROJECTILE, TalentData.EffectType.MAGIC_PROJECTILE_AOE:
            if talent.cast_time > 0:
                return "spell_cast"
            else:
                return "spell_instant"
        TalentData.EffectType.SELF_BUFF:
            return "self_buff"
        TalentData.EffectType.HEAL:
            return "spell_instant"
        TalentData.EffectType.AOE:
            return "spell_cast"
        _:
            return "melee_single"  # Fallback
```

#### Build overrides from talent data:

```gdscript
static func _build_visual_overrides(talent: TalentData) -> Dictionary:
    var overrides := {}

    if talent.lunge_force > 0:
        overrides["lunge_distance"] = get_lunge_force(talent)
    if talent.lunge_duration > 0:
        overrides["lunge_duration"] = talent.lunge_duration
    if talent.recovery_time > 0:
        overrides["recovery_duration"] = talent.recovery_time
    if talent.cast_time > 0:
        overrides["cast_duration"] = talent.cast_time

    return overrides
```

#### Refactor skill activation to use the sequencer:

The core skill activation function (called when an ability slot is pressed) should become:

```gdscript
func _activate_skill(slot_index: int, talent: TalentData) -> void:
    if not player or not talent:
        return

    # Resource cost checks (existing)
    if not _check_and_spend_resources(talent):
        return

    # Cooldown checks (existing)
    if not _check_cooldown(slot_index, talent):
        return

    # Determine visual template
    var template_id := _get_visual_template_for_talent(talent)
    var overrides := _build_visual_overrides(talent)

    # For ranged skills, start aiming instead of immediate play
    if talent.effect_type == TalentData.EffectType.PROJECTILE:
        _start_aiming(slot_index, talent)
        return

    # Find nearest enemy for target position (used by lunge direction)
    var target_pos := _find_nearest_enemy_position()

    # Connect to damage/projectile events for this activation
    _pending_talent = talent
    _connect_visual_signals()

    # Play the visual sequence
    player.play_ability_visual(template_id, overrides, target_pos)

    # Start cooldown
    _start_cooldown(slot_index, talent)
```

#### Signal-based damage and projectile handling:

```gdscript
var _pending_talent: TalentData = null

func _connect_visual_signals() -> void:
    if not player or not player.ability_visual_player:
        return
    var vp := player.ability_visual_player

    # One-shot connections (disconnect after first emission)
    if not vp.damage_event.is_connected(_on_visual_damage_event):
        vp.damage_event.connect(_on_visual_damage_event)
    if not vp.spawn_projectile_event.is_connected(_on_visual_spawn_projectile):
        vp.spawn_projectile_event.connect(_on_visual_spawn_projectile)
    if not vp.sequence_finished.is_connected(_on_visual_finished):
        vp.sequence_finished.connect(_on_visual_finished)

func _disconnect_visual_signals() -> void:
    if not player or not player.ability_visual_player:
        return
    var vp := player.ability_visual_player
    if vp.damage_event.is_connected(_on_visual_damage_event):
        vp.damage_event.disconnect(_on_visual_damage_event)
    if vp.spawn_projectile_event.is_connected(_on_visual_spawn_projectile):
        vp.spawn_projectile_event.disconnect(_on_visual_spawn_projectile)
    if vp.sequence_finished.is_connected(_on_visual_finished):
        vp.sequence_finished.disconnect(_on_visual_finished)

func _on_visual_damage_event() -> void:
    ## The sequencer says "now is the damage frame" — apply damage using existing logic
    if _pending_talent:
        _apply_skill_damage(_pending_talent)

func _on_visual_spawn_projectile() -> void:
    ## The sequencer says "now spawn the projectile" — spawn using existing logic
    if _pending_talent:
        _spawn_skill_projectile(_pending_talent)

func _on_visual_finished(_template_id: String) -> void:
    _pending_talent = null
    _disconnect_visual_signals()
```

#### Extract damage and projectile logic into clean methods:

The existing damage logic in `_apply_skill_mechanics()` should be extracted into `_apply_skill_damage()` without the animation/lunge code (the sequencer handles that now):

```gdscript
func _apply_skill_damage(talent: TalentData) -> void:
    ## Pure damage application — no animation or movement logic
    ## Called by the visual sequencer's damage_event signal
    var hit_range := get_hit_range(talent)
    var hit_arc := get_hit_arc(talent)
    var facing_dir := player._facing_to_vector(player.current_facing)

    # Find enemies in range (existing logic from _apply_skill_mechanics)
    for enemy in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(enemy):
            continue
        var to_enemy := enemy.global_position - player.global_position
        var distance := to_enemy.length()
        if distance > hit_range:
            continue
        # Arc check
        if hit_arc < 360:
            var angle := rad_to_deg(facing_dir.angle_to(to_enemy))
            if abs(angle) > hit_arc / 2.0:
                continue

        # Calculate and apply damage (existing DamageCalculator logic)
        var damage_info := DamageCalculator.calculate_player_skill_damage(talent, PlayerStats)
        if enemy.has_method("take_damage"):
            enemy.take_damage(damage_info.final_damage, player)

    # Notify quest system
    if QuestManager:
        QuestManager.on_ability_used(talent.id)

func _spawn_skill_projectile(talent: TalentData) -> void:
    ## Pure projectile spawning — no animation logic
    ## Called by the visual sequencer's spawn_projectile_event signal
    var facing_dir := player._facing_to_vector(player.current_facing)

    match talent.effect_type:
        TalentData.EffectType.PROJECTILE:
            _spawn_physical_projectile(talent, facing_dir)
        TalentData.EffectType.MAGIC_PROJECTILE:
            _spawn_magic_projectile(talent, facing_dir, false)
        TalentData.EffectType.MAGIC_PROJECTILE_AOE:
            _spawn_magic_projectile(talent, facing_dir, true)
```

#### Ranged aiming integration:

For `ranged_aim` template, the aim phase is held until the player releases. The existing aim indicator logic stays, but on release:

```gdscript
func _on_aim_released(talent: TalentData) -> void:
    # ... existing charge calculation ...

    # Instead of directly spawning projectile:
    var overrides := _build_visual_overrides(talent)
    overrides["charge_percent"] = charge_percent  # custom data for the projectile spawn

    _pending_talent = talent
    _connect_visual_signals()

    # Tell the visual player to release the held aim phase
    player.ability_visual_player.release_held_phase()
```

---

### File 4: `scripts/ui/combat/combat_hud.gd` — basic attack button

The basic attack (no skill bound to slot 0) should also use the sequencer:

```gdscript
func _on_attack_button_pressed() -> void:
    if attack_button_talent:
        _activate_skill(0, attack_button_talent)
    else:
        # Basic attack — use melee_single template with default timings
        if player:
            var overrides := {
                "lunge_distance": player.attack_lunge_force,
                "lunge_duration": player.attack_lunge_duration,
            }
            _pending_talent = null  # No talent — basic attack uses hitbox
            _connect_visual_signals()
            player.play_ability_visual("melee_single", overrides)
```

For basic attack `_on_visual_damage_event`, when `_pending_talent` is null, enable the hitbox briefly (existing `_on_attack_hit_frame()` logic).

---

## Migration Strategy

**Important**: Don't rip out the old code paths all at once. Instead:

1. Add the new sequencer-based path alongside the old code
2. Add a flag or check: `if player.ability_visual_player:` use new path, else fall back to old
3. Once confirmed working, remove the old inline logic in a cleanup pass

This way if something breaks, the fallback still works.

---

## What NOT To Do In This Phase

- Do NOT modify enemy combat code (`enemy_npc.gd`) — that's Phase 5
- Do NOT modify the database schema — that's Phase 6
- Do NOT add new visual templates beyond what Phase 1 defined
- Keep the existing `request_attack()` method functional as a fallback

---

## Testing / Validation

1. Press the basic attack button — player should play the melee_single sequence (melee_windup -> lunge + melee_strike -> damage -> idle).
2. Use a melee skill — same visual flow but with skill-specific lunge force and recovery.
3. Use a ranged skill — aim indicator shows, hold to charge, release fires projectile via the sequencer.
4. Use a magic spell with cast time — cast animation plays, cast bar fills, projectile spawns on completion.
5. Use an instant spell — immediate cast_release animation + effect.
6. Use a self-buff — cast animation + buff applied.
7. Damage numbers should appear at the correct timing (on the damage_event, not before).
8. Movement should be locked during sequences and unlocked after.
9. No regressions in existing combat feel — timing should feel the same or better.

---

## Existing Code Reference

| File | Why |
|------|-----|
| `scripts/ui/combat/combat_hud.gd` | **Primary file to modify** — all skill activation logic lives here |
| `scripts/player/player_controller.gd` | Add AbilityVisualPlayer, handle movement signals |
| `scripts/player/player_animator.gd` | Update to respect visual sequences |
| `scripts/combat/ability_visual_player.gd` | Phase 1 — the sequencer being wired in |
| `scripts/combat/ability_visual_templates.gd` | Phase 1 — template definitions |
| `scripts/combat/character_visuals.gd` | Phase 2 — handles body animation resolution |
| `scripts/combat/projectile.gd` | Projectile spawning (existing, reused) |
| `scripts/combat/magic_projectile.gd` | Magic projectile spawning (existing, reused) |
| `autoloads/damage_calculator.gd` | Damage formulas (existing, reused) |
| `scripts/data/talent_data.gd` | Player skill data — effect_type determines template |

---

*This prompt is Phase 4 of 6 in the Ability Visual System implementation.*
