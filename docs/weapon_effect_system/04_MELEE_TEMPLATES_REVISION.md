# Phase 4: Melee Templates Revision

## Context

This is the integration phase where everything comes together. The ability visual templates (`AbilityVisualTemplates`) define the phase sequences for each ability type. Currently the melee templates show the weapon at the start and keep it visible through the entire sequence.

The new design follows the cinematic pattern:
1. **Weapon visible during windup** (dramatic preparation).
2. **Weapon hidden during strike** — replaced by a slash effect VFX.
3. **Weapon hidden during recovery/idle** — weapon is a prop, not permanent.

This phase also wires up `CharacterVisuals._on_effect_event()` to actually spawn placeholder effects using `PlaceholderEffectSprites`.

## Prerequisites

- **Phase 2** (CharacterVisuals weapon set support) — texture set API must exist.
- **Phase 3** (PlaceholderEffectSprites) — effect creation must exist.

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/combat/ability_visual_templates.gd` | The file being modified — all template definitions |
| `scripts/combat/ability_visual_phase.gd` | Phase types, factory helpers, understanding concurrent phases |
| `scripts/combat/ability_visual_player.gd` | How phases execute, signal flow, concurrency system |
| `scripts/combat/character_visuals.gd` | The effect_event handler that needs wiring |
| `scripts/combat/placeholder_effect_sprites.gd` | The effect factory from Phase 3 |

## Implementation Prompt

### Part A: Update CharacterVisuals Effect Wiring

Modify `CharacterVisuals._on_effect_event()` to spawn actual placeholder effects instead of just logging.

**Current code:**
```gdscript
func _on_effect_event(effect_id: String) -> void:
    Debug.log("Visuals", "Effect requested: %s" % effect_id)
```

**New code:**
```gdscript
func _on_effect_event(effect_id: String) -> void:
    Debug.log("Visuals", "Effect requested: %s" % effect_id)
    var effect_node := PlaceholderEffectSprites.create_effect(effect_id, current_direction)
    if effect_node:
        spawn_effect(effect_node)
```

This calls the factory from Phase 3, which returns a self-animating Node2D, and adds it to the effect_anchor. The effect handles its own lifecycle (tween + queue_free).

**Important**: If PlaceholderEffectSprites is not found at parse time due to Godot's class loading order, use the preload pattern:

```gdscript
const PlaceholderEffectSpritesScript = preload("res://scripts/combat/placeholder_effect_sprites.gd")

func _on_effect_event(effect_id: String) -> void:
    Debug.log("Visuals", "Effect requested: %s" % effect_id)
    var effect_node: Node2D = PlaceholderEffectSpritesScript.create_effect(effect_id, current_direction)
    if effect_node:
        spawn_effect(effect_node)
```

### Part B: Revise Melee Templates

Update the melee templates in `AbilityVisualTemplates` to follow the new weapon/effect pattern.

#### melee_single (revised)

**Current:**
```
Show weapon → windup → lunge+strike → damage → idle (weapon stays visible)
```

**New:**
```
Show weapon → windup → hide weapon → slash effect + lunge + strike → damage → idle
```

```gdscript
static func _melee_single() -> AbilityVisualData:
    var data := AbilityVisualData.new()
    data.template_id = "melee_single"
    data.display_name = "Melee Single"
    data.locks_movement = true

    data.phases = [
        # Phase 0: Show weapon for windup
        AbilityVisualPhase.create_weapon_visibility(true),
        # Phase 1: Windup animation (sword raised — wait for anim)
        AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
        # Phase 2: Hide weapon before slash
        AbilityVisualPhase.create_weapon_visibility(false),
        # Phase 3: Slash effect (concurrent with lunge+strike)
        AbilityVisualPhase.create_effect("slash_arc", 0.0, true),
        # Phase 4: Lunge toward target (concurrent with strike)
        AbilityVisualPhase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
        # Phase 5: Strike animation
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 6: Damage event
        AbilityVisualPhase.create_damage_event(),
        # Phase 7: Return to idle (recovery)
        AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
    ]

    return data
```

**Key changes from current:**
- Added `WEAPON_VISIBILITY(false)` before strike — sword disappears.
- Added `EFFECT("slash_arc")` concurrent with the lunge+strike — slash VFX replaces the sword.
- Removed the final `WEAPON_VISIBILITY(true)` — weapon stays hidden after attack.

**Concurrency note:** Phase 3 (effect) has `concurrent=true`, which means it runs alongside Phase 4. Phase 4 (movement) also has `concurrent=true`, which means it runs alongside Phase 5 (strike body anim). The result: **all three** (effect + lunge + strike) run simultaneously. Both the effect and lunge resolve by timer, the strike resolves when its animation finishes. The sequence advances past Phase 5 only when ALL have resolved.

Wait — the current concurrency system only pairs two adjacent phases. We can't have three-way concurrency directly. Let me restructure:

**Corrected approach** — the effect is instant (duration=0, not concurrent), then lunge+strike are concurrent:

```gdscript
    data.phases = [
        # Phase 0: Show weapon for windup
        AbilityVisualPhase.create_weapon_visibility(true),
        # Phase 1: Windup animation (sword raised)
        AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
        # Phase 2: Hide weapon before slash
        AbilityVisualPhase.create_weapon_visibility(false),
        # Phase 3: Spawn slash effect (instant — fires and forgets)
        AbilityVisualPhase.create_effect("slash_arc"),
        # Phase 4: Lunge toward target (concurrent with strike)
        AbilityVisualPhase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
        # Phase 5: Strike animation (runs alongside lunge)
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 6: Damage event
        AbilityVisualPhase.create_damage_event(),
        # Phase 7: Return to idle (recovery)
        AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
    ]
```

The slash effect spawns (instant, no duration, no concurrent — it fires and the effect animates on its own via its internal tween). Then the lunge+strike are the concurrent pair.

#### melee_combo_2 (revised)

Two-hit combo. Weapon visible during initial windup only. Each hit gets its own slash effect.

```gdscript
static func _melee_combo_2() -> AbilityVisualData:
    var data := AbilityVisualData.new()
    data.template_id = "melee_combo_2"
    data.display_name = "Melee Combo (2-hit)"
    data.locks_movement = true

    data.phases = [
        # Phase 0: Show weapon for windup
        AbilityVisualPhase.create_weapon_visibility(true),
        # Phase 1: Windup
        AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
        # Phase 2: Hide weapon
        AbilityVisualPhase.create_weapon_visibility(false),
        # Phase 3: First slash effect
        AbilityVisualPhase.create_effect("slash_arc"),
        # Phase 4: Lunge + strike (concurrent)
        AbilityVisualPhase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 6: First hit damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 7: Brief pause between hits
        AbilityVisualPhase.create_wait(0.1),
        # Phase 8: Second slash effect (wider for combo)
        AbilityVisualPhase.create_effect("slash_arc_wide"),
        # Phase 9: Second strike
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 10: Second hit damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 11: Return to idle
        AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
    ]

    return data
```

#### melee_combo_3 (revised)

Same pattern as combo_2 with a third hit. Third hit uses `slash_arc_wide` again.

```gdscript
static func _melee_combo_3() -> AbilityVisualData:
    var data := AbilityVisualData.new()
    data.template_id = "melee_combo_3"
    data.display_name = "Melee Combo (3-hit)"
    data.locks_movement = true

    data.phases = [
        # Phase 0: Show weapon for windup
        AbilityVisualPhase.create_weapon_visibility(true),
        # Phase 1: Windup
        AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
        # Phase 2: Hide weapon
        AbilityVisualPhase.create_weapon_visibility(false),
        # Phase 3: First slash effect
        AbilityVisualPhase.create_effect("slash_arc"),
        # Phase 4: Lunge + strike (concurrent)
        AbilityVisualPhase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 6: First hit damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 7: Brief pause
        AbilityVisualPhase.create_wait(0.1),
        # Phase 8: Second slash effect
        AbilityVisualPhase.create_effect("slash_arc_wide"),
        # Phase 9: Second strike
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 10: Second hit damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 11: Brief pause
        AbilityVisualPhase.create_wait(0.1),
        # Phase 12: Third slash effect
        AbilityVisualPhase.create_effect("slash_arc_wide"),
        # Phase 13: Third strike
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 14: Third hit damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 15: Return to idle
        AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
    ]

    return data
```

#### dash_attack (revised)

Dash forward then strike. Weapon visible during dash, hidden during strike (slash effect).

```gdscript
static func _dash_attack() -> AbilityVisualData:
    var data := AbilityVisualData.new()
    data.template_id = "dash_attack"
    data.display_name = "Dash Attack"
    data.locks_movement = true

    data.phases = [
        # Phase 0: Show weapon for dash
        AbilityVisualPhase.create_weapon_visibility(true),
        # Phase 1: Dash animation + movement (concurrent)
        AbilityVisualPhase.create_body_anim("dash", 0.0, "dash", true),
        AbilityVisualPhase.create_movement("toward_target", 60.0, 0.25, "dash"),
        # Phase 3: Hide weapon for slash
        AbilityVisualPhase.create_weapon_visibility(false),
        # Phase 4: Slash effect
        AbilityVisualPhase.create_effect("slash_arc_wide"),
        # Phase 5: Strike
        AbilityVisualPhase.create_body_anim("melee_strike"),
        # Phase 6: Damage
        AbilityVisualPhase.create_damage_event(),
        # Phase 7: Return to idle
        AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
    ]

    return data
```

### Part C: Templates NOT Changed (This Phase)

The following templates are NOT melee and should remain as-is for now. They will be updated in future phases when ranged/magic weapon visuals are implemented:

- `ranged_aim` — ranged (bow), future phase
- `spell_cast` — magic (staff), future phase
- `spell_instant` — magic (staff), future phase
- `throw` — no weapon, already correct
- `self_buff` — no weapon, already correct
- `ranged_attack` — enemy, no weapon layer
- `howl` — enemy, no weapon layer

### What NOT to Change in This Phase

- `AbilityVisualPhase` — no new phase types needed. Existing `EFFECT` and `WEAPON_VISIBILITY` phases are sufficient.
- `AbilityVisualPlayer` — the executor doesn't change, only the template data it reads.
- `AbilityVisualData` — no structural changes.

## Acceptance Criteria

1. `CharacterVisuals._on_effect_event()` spawns actual VFX nodes via `PlaceholderEffectSprites.create_effect()`.
2. `melee_single` template: weapon shows during windup, hides before strike, slash effect fires, weapon hidden after recovery.
3. `melee_combo_2` template: weapon shows during windup, hides before first strike. Each hit fires its own slash effect. Second hit uses `slash_arc_wide`.
4. `melee_combo_3` template: same as combo_2 pattern with third hit.
5. `dash_attack` template: weapon shows during dash, hides before slash+strike.
6. Non-melee templates (`ranged_aim`, `spell_cast`, `spell_instant`, `throw`, `self_buff`, `ranged_attack`, `howl`) are unchanged.
7. Slash effects are visible during gameplay when melee abilities are used.
8. No phase execution errors — concurrency pairs work correctly (lunge+strike).
9. Effects auto-remove after their lifetime (no orphaned nodes).

---

*Phase 4 of 7 — Depends on Phase 2 and Phase 3*
