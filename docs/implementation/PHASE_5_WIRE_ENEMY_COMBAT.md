# Phase 5: Wire Enemy Combat to the Visual Sequencer

> **Goal**: Replace the inline ability execution in `EnemyNPC` with the `AbilityVisualPlayer` sequencer. After this, both player and enemy abilities are driven by the same visual template system.

> **Depends on**: Phase 1 (sequencer), Phase 2 (CharacterVisuals on enemies), Phase 3 (enemy body animations)

---

## Context

Currently, `EnemyNPC` handles ability execution through type-specific methods:
- `_execute_melee_attack()` — calls `play_attack()`, checks range, deals damage
- `_execute_dash_attack()` — tween-based rush, then melee on arrival
- `_execute_ranged_attack()` — calls `play_attack()`, spawns projectile

The visual orchestration (animation timing, movement, damage frame) is hardcoded per ability type. We want to replace this with:
1. Map `AbilityData.type` to a visual template
2. Build overrides from `AbilityData` fields (windup, recovery, dash_speed, etc.)
3. Play through `AbilityVisualPlayer`
4. Listen to signals for damage application and projectile spawning

---

## What To Modify

### File 1: `scripts/npc/base_character.gd`

#### Add AbilityVisualPlayer support:

```gdscript
var ability_visual_player: AbilityVisualPlayer = null

func _ready() -> void:
    # ... existing code ...
    _setup_ability_visual_player()

func _setup_ability_visual_player() -> void:
    ability_visual_player = AbilityVisualPlayer.new()
    ability_visual_player.name = "AbilityVisualPlayer"
    add_child(ability_visual_player)

    if sprite:
        ability_visual_player.initialize(sprite)

    # Connect movement to base character movement system
    ability_visual_player.movement_requested.connect(_on_visual_movement_requested)
    ability_visual_player.sequence_started.connect(_on_visual_sequence_started)
    ability_visual_player.sequence_finished.connect(_on_visual_sequence_finished)

    # Connect to CharacterVisuals if available
    if character_visuals:
        character_visuals.connect_to_visual_player(ability_visual_player)
```

#### Handle sequencer signals:

```gdscript
func _on_visual_movement_requested(direction: String, distance: float, duration: float) -> void:
    ## Execute movement from the visual sequencer
    ## For enemies, use a tween for precise movement control
    var move_dir: Vector2
    match direction:
        "toward_target":
            move_dir = get_direction_to_player()
        "away_from_target":
            move_dir = -get_direction_to_player()
        "facing":
            move_dir = get_facing_vector()
        _:
            move_dir = get_facing_vector()

    # Tween-based movement (consistent with existing dash_attack approach)
    var target_pos := global_position + move_dir * distance
    var tween := create_tween()
    tween.tween_property(self, "global_position", target_pos, duration)

func _on_visual_sequence_started(_template_id: String) -> void:
    is_locked = true
    stop_movement()

func _on_visual_sequence_finished(_template_id: String) -> void:
    is_locked = false
    _set_anim_state(AnimState.IDLE)
```

#### New method for playing ability visuals:

```gdscript
func play_ability_visual(template_id: String, overrides: Dictionary = {}, target_pos: Vector2 = Vector2.ZERO) -> void:
    ## Play a visual template. Called by EnemyNPC ability execution.
    if ability_visual_player and ability_visual_player.is_playing:
        return

    var template: AbilityVisualData = AbilityVisualTemplates.get_all().get(template_id)
    if not template:
        # Fallback to legacy play_attack()
        play_attack()
        return

    ability_visual_player.play(template, target_pos, overrides)
```

---

### File 2: `scripts/npc/enemy_npc.gd`

This is the main file to refactor. The ability execution pipeline needs to route through the sequencer.

#### Add template mapping for enemy abilities:

```gdscript
## Map AbilityData.AbilityType to visual template IDs
static func _get_visual_template_for_ability(ability: AbilityData) -> String:
    match ability.type:
        AbilityData.AbilityType.MELEE:
            return "melee_single"
        AbilityData.AbilityType.DASH_ATTACK:
            return "dash_attack"
        AbilityData.AbilityType.PROJECTILE:
            return "ranged_aim"  # enemies don't "aim" — instant variant
        AbilityData.AbilityType.AOE:
            return "spell_cast"
        AbilityData.AbilityType.TELEPORT_ATTACK:
            return "dash_attack"  # visually similar
        AbilityData.AbilityType.BEAM:
            return "spell_cast"
        AbilityData.AbilityType.PATTERN:
            return "spell_cast"
        _:
            return "melee_single"
```

**Note on enemy ranged**: Enemies don't have a hold-to-aim mechanic. For `PROJECTILE` type abilities, the template should auto-advance through the aim phase without holding. You can either:
- Use a different template `"ranged_instant"` (add this to `AbilityVisualTemplates` if needed)
- Or just use `"melee_single"` and have the projectile spawn on the damage_event signal

The simplest approach: add a `"ranged_attack"` template specifically for enemies:

```
ranged_attack:
  Phase 0: BODY_ANIM("attack"), override_key="windup"  # use existing attack anim
  Phase 1: SPAWN_PROJECTILE
  Phase 2: BODY_ANIM("idle"), override_key="recovery"
```

Add this to `AbilityVisualTemplates.get_all()`.

#### Build overrides from AbilityData:

```gdscript
func _build_ability_overrides(ability: AbilityData) -> Dictionary:
    var overrides := {}

    if ability.windup > 0:
        overrides["windup_duration"] = ability.windup
    if ability.recovery > 0:
        overrides["recovery_duration"] = ability.recovery
    if ability.dash_speed > 0:
        # Convert dash_speed to distance: speed * windup_duration
        overrides["lunge_distance"] = ability.dash_speed * ability.windup
        overrides["lunge_duration"] = ability.windup

    return overrides
```

#### Refactor `_do_execute_ability()` (or equivalent):

The existing ability execution method should become:

```gdscript
func _execute_ability_visual(ability: AbilityData) -> void:
    ## New sequencer-based ability execution

    # Determine template and overrides
    var template_id := _get_visual_template_for_ability(ability)
    var overrides := _build_ability_overrides(ability)
    var target_pos := Vector2.ZERO

    if Game.is_player_valid():
        target_pos = Game.player.global_position

    # Face toward target before executing
    if Game.is_player_valid():
        var dir := global_position.direction_to(Game.player.global_position)
        _update_facing_from_direction(dir)

    # Store pending ability for signal handlers
    _pending_ability = ability

    # Connect signals (one-shot pattern)
    _connect_ability_visual_signals()

    # Play the visual sequence
    play_ability_visual(template_id, overrides, target_pos)
```

#### Signal-based damage and projectile handling:

```gdscript
var _pending_ability: AbilityData = null

func _connect_ability_visual_signals() -> void:
    var vp := ability_visual_player
    if not vp:
        return

    if not vp.damage_event.is_connected(_on_ability_damage_event):
        vp.damage_event.connect(_on_ability_damage_event)
    if not vp.spawn_projectile_event.is_connected(_on_ability_spawn_projectile):
        vp.spawn_projectile_event.connect(_on_ability_spawn_projectile)
    if not vp.sequence_finished.is_connected(_on_ability_sequence_finished):
        vp.sequence_finished.connect(_on_ability_sequence_finished)

func _disconnect_ability_visual_signals() -> void:
    var vp := ability_visual_player
    if not vp:
        return
    if vp.damage_event.is_connected(_on_ability_damage_event):
        vp.damage_event.disconnect(_on_ability_damage_event)
    if vp.spawn_projectile_event.is_connected(_on_ability_spawn_projectile):
        vp.spawn_projectile_event.disconnect(_on_ability_spawn_projectile)
    if vp.sequence_finished.is_connected(_on_ability_sequence_finished):
        vp.sequence_finished.disconnect(_on_ability_sequence_finished)

func _on_ability_damage_event() -> void:
    if not _pending_ability:
        return

    ## Apply damage using existing logic from _execute_melee_attack
    if not Game.is_player_valid():
        return

    var distance := global_position.distance_to(Game.player.global_position)
    if distance > _pending_ability.range_max:
        return  # Missed — player moved out of range

    # Calculate damage
    var damage := DamageCalculator.calculate_enemy_ability_damage(
        _pending_ability, _get_base_damage(), PlayerStats
    )

    Game.player.take_damage(damage.final_damage, self)

    # Apply on-hit effects
    _apply_ability_effects(_pending_ability)

func _on_ability_spawn_projectile() -> void:
    if not _pending_ability:
        return

    ## Spawn projectile using existing logic from _execute_ranged_attack
    _spawn_ability_projectile(_pending_ability)

func _on_ability_sequence_finished(_template_id: String) -> void:
    _pending_ability = null
    _disconnect_ability_visual_signals()
```

#### Extract projectile and effect logic:

Move the existing projectile spawning from `_execute_ranged_attack()` into a clean method:

```gdscript
func _spawn_ability_projectile(ability: AbilityData) -> void:
    ## Spawn a projectile for a ranged ability
    if not Game.is_player_valid():
        return

    var direction := global_position.direction_to(Game.player.global_position)
    var speed := ability.projectile_speed if ability.projectile_speed > 0 else 150.0

    # Use existing projectile creation (Projectile.create_arrow or similar)
    var projectile := ProjectileClass.create_arrow()  # Or enemy-specific factory
    projectile.global_position = global_position
    projectile.initialize(direction, speed, ability.range_max, ability.damage_mult * _get_base_damage())
    get_tree().current_scene.add_child(projectile)

func _apply_ability_effects(ability: AbilityData) -> void:
    ## Apply on-hit effects (stun, knockback, DoTs, etc.)
    var effects := ability.get_parsed_effects()
    for effect in effects:
        match effect.get("type", ""):
            "stun":
                if Game.player.has_method("apply_stun"):
                    Game.player.apply_stun(effect.get("duration", 1.0))
            "knockback":
                var dir := Game.player.global_position - global_position
                if dir != Vector2.ZERO:
                    Game.player.velocity = dir.normalized() * effect.get("force", 100.0)
            "burn", "bleed", "rot", "poison":
                if Game.player.has_method("apply_dot"):
                    Game.player.apply_dot(effect["type"], effect.get("duration", 3.0), effect.get("damage", 5.0))
            "slow":
                if Game.player.has_method("apply_slow"):
                    Game.player.apply_slow(effect.get("duration", 2.0), effect.get("percent", 30.0) / 100.0)
```

#### Migration: Keep legacy execution as fallback:

```gdscript
func _do_execute_ability(ability: AbilityData) -> void:
    # Try new sequencer path
    if ability_visual_player:
        _execute_ability_visual(ability)
        return

    # Legacy fallback (existing code, unchanged)
    match ability.type:
        AbilityData.AbilityType.MELEE:
            _execute_melee_attack(ability)
        AbilityData.AbilityType.DASH_ATTACK:
            _execute_dash_attack(ability)
        # ... etc
```

---

### File 3: `scripts/combat/ability_visual_templates.gd`

Add the `ranged_attack` template for enemies:

```gdscript
static func _ranged_attack() -> AbilityVisualData:
    ## Enemy ranged attack — no aiming, just windup -> projectile -> recovery
    var data := AbilityVisualData.new()
    data.template_id = "ranged_attack"
    data.display_name = "Ranged Attack"
    data.locks_movement = true

    var windup := AbilityVisualPhase.new()
    windup.type = AbilityVisualPhase.PhaseType.BODY_ANIM
    windup.anim_name = "attack"  # Falls back to existing attack_{dir}
    windup.duration = 0  # Use animation length
    windup.override_key = "windup"

    var spawn := AbilityVisualPhase.new()
    spawn.type = AbilityVisualPhase.PhaseType.SPAWN_PROJECTILE

    var recovery := AbilityVisualPhase.new()
    recovery.type = AbilityVisualPhase.PhaseType.WAIT
    recovery.duration = 0.3
    recovery.override_key = "recovery"

    data.phases = [windup, spawn, recovery]
    return data
```

Also add to the `get_all()` dictionary:
```gdscript
"ranged_attack": _ranged_attack(),
```

---

## The Wolf Howl — Custom Ability Animation

The wolf has `howl_{dir}` animations that were generated in Phase 3 (or earlier, by the existing wolf generator). The howl ability (`Blood Howl`) should use a custom template:

```gdscript
static func _howl() -> AbilityVisualData:
    var data := AbilityVisualData.new()
    data.template_id = "howl"
    data.display_name = "Howl"
    data.locks_movement = true

    var howl_anim := AbilityVisualPhase.new()
    howl_anim.type = AbilityVisualPhase.PhaseType.BODY_ANIM
    howl_anim.anim_name = "howl"  # Uses howl_{dir} animations
    howl_anim.duration = 0  # Full animation
    howl_anim.override_key = "cast"

    var effect := AbilityVisualPhase.new()
    effect.type = AbilityVisualPhase.PhaseType.EFFECT
    effect.effect_id = "howl_aura"

    var damage := AbilityVisualPhase.new()
    damage.type = AbilityVisualPhase.PhaseType.DAMAGE_EVENT

    var recovery := AbilityVisualPhase.new()
    recovery.type = AbilityVisualPhase.PhaseType.WAIT
    recovery.duration = 0.3
    recovery.override_key = "recovery"

    data.phases = [howl_anim, effect, damage, recovery]
    return data
```

Add to `get_all()`:
```gdscript
"howl": _howl(),
```

This mapping is done in `EnemyNPC._get_visual_template_for_ability()` based on the ability's `animation` field:

```gdscript
## Check if ability has a custom animation mapping
if ability.animation != "attack" and ability.animation != "":
    # Custom animation — check if a template exists for it
    var custom_template := AbilityVisualTemplates.get_all().get(ability.animation)
    if custom_template:
        return ability.animation
```

This way, the wolf's Blood Howl ability (which has `animation: "howl"` in the database) automatically maps to the `"howl"` visual template, which plays `howl_{dir}` animations. The `AbilityData.animation` field that was previously unused finally has a purpose.

---

## What NOT To Do In This Phase

- Do NOT modify `combat_hud.gd` — that was Phase 4
- Do NOT modify the database schema — that's Phase 6
- Do NOT add new enemy sprite generators
- Keep all existing enemy behavior modules functional

---

## Testing / Validation

1. Spawn a Starved Wolf — it should attack using the sequencer (melee_windup -> lunge -> melee_strike -> damage).
2. Wolf's Blood Howl should play the `howl_{dir}` animation (this was impossible before Phase 5).
3. Enemy projectile attacks should fire on the SPAWN_PROJECTILE phase, not before.
4. Enemy dash attacks should move the enemy via the sequencer's MOVEMENT phase.
5. Damage timing should match the DAMAGE_EVENT phase — no early/late hits.
6. Enemies should be locked during ability execution and unlock after.
7. If `ability_visual_player` is missing for any reason, the legacy fallback should still work.
8. No regressions in enemy AI behavior (pathing, aggro, target selection all unchanged).

---

## Existing Code Reference

| File | Why |
|------|-----|
| `scripts/npc/enemy_npc.gd` | **Primary file to modify** — ability execution pipeline |
| `scripts/npc/base_character.gd` | Add AbilityVisualPlayer, handle signals |
| `scripts/data/ability_data.gd` | Enemy ability data — type, windup, recovery, animation fields |
| `scripts/combat/ability_visual_player.gd` | Phase 1 — the sequencer |
| `scripts/combat/ability_visual_templates.gd` | Phase 1 — add ranged_attack and howl templates |
| `scripts/combat/character_visuals.gd` | Phase 2 — handles animation resolution |
| `scripts/combat/projectile.gd` | Existing projectile system |
| `autoloads/damage_calculator.gd` | Enemy damage formulas |
| `databases/exports/abilities.json` | Enemy ability definitions (animation field) |
| `databases/exports/enemy_abilities.json` | Which enemies have which abilities |

---

*This prompt is Phase 5 of 6 in the Ability Visual System implementation.*
