# Combat System Architecture

This document provides a comprehensive overview of the combat system, its building blocks, and recommendations for future development.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Skill Categories & Examples](#skill-categories--examples)
3. [Building Blocks Reference](#building-blocks-reference)
4. [Attack Execution Phases](#attack-execution-phases)
5. [Status Effects System](#status-effects-system)
6. [Projectile System](#projectile-system)
7. [Enemy AI and Abilities](#enemy-ai-and-abilities)
8. [Unified Building Blocks](#unified-building-blocks)
9. [Database-Driven Stats & Skills](#database-driven-stats--skills)
10. [Equipment Modifier System](#equipment-modifier-system)
11. [Godot Patterns & Gotchas](#godot-patterns--gotchas)
12. [Adding New Content Guide](#adding-new-content-guide)

---

## System Overview

The combat system is built on a **unified architecture** with shared building blocks:

```
PLAYER COMBAT                          ENEMY COMBAT
─────────────────                      ─────────────────
TalentData (database)                  AbilityData (database)
     ↓                                      ↓
TalentManager (skill bindings)         EnemyAbilityController (AI selection)
     ↓                                      ↓
CombatHUD (input routing)              AbilityExecutor (execution)
     ↓                                      ↓
  ┌──┴──────────────────────────────────────┴──┐
  │        ABILITY VISUAL SEQUENCER             │
  │  AbilityVisualPlayer (phase executor)       │
  │  AbilityVisualTemplates (template library)  │
  │  CharacterVisuals (layered sprite stack)    │
  ├─────────────────────────────────────────────┤
  │           SHARED SYSTEMS                    │
  │  • DamageCalculator (unified damage math)  │
  │  • StatusEffectComponent (buffs/debuffs)   │
  │  • MovementAction (lunge/dash/knockback)   │
  │  • HitboxSpawner (collision detection)     │
  │  • Projectile / MagicProjectile            │
  │  • SkillBase (shared skill properties)     │
  └─────────────────────────────────────────────┘
```

---

## Skill Categories & Examples

The following skill examples demonstrate different combat mechanics. These are **examples, not rigid templates**:
- Not every melee skill needs lunge
- Not every ranged skill needs charge-to-fire
- Not every magic skill fires projectiles
- Skills can mix and match mechanics as needed

Each skill is fully database-driven - properties like range, damage, and effects are configured per-skill in the Talents database.

### 1. MELEE Skills (Example: Basic Strike)

**Player Flow:**
```
Button Press → CombatHUD._on_ability_activated()
  → Validate weapon, resources
  → Apply lunge force (talent.lunge_force)
  → Play attack animation
  → On attack frame: _apply_skill_damage()
    → NPCManager.get_enemies_in_radius(hit_range)
    → Filter by hit_arc (cone check)
    → DamageCalculator.calculate_final_damage()
    → enemy.take_damage()
  → Apply recovery lockout (talent.recovery_time)
  → Start cooldown
```

**Key Properties (TalentData):**
- `effect_type`: DAMAGE (default melee)
- `hit_range`: Distance in pixels
- `hit_arc`: Cone angle in degrees (360 = all around)
- `lunge_force`: Forward momentum applied
- `recovery_time`: Input lock after attack
- `weapon_damage_percent`: Scales with equipped weapon
- `flat_damage_bonus`: Added to final damage

**Files:**
- `scripts/ui/combat/combat_hud.gd` - Input handling
- `scripts/player/player_controller.gd` - Lunge execution
- `autoloads/damage_calculator.gd` - Damage math

---

### 2. RANGED Skills (Example: Basic Shot)

**Player Flow:**
```
Button Hold → CombatHUD._on_ability_hold_started()
  → Create AimIndicator (visual trajectory)
  → Track hold duration

During Hold → _update_aiming()
  → Update direction from input/facing
  → Calculate charge_progress: (hold_time - min_charge) / (max_charge_time - min_charge)
  → Update range: lerp(base_range, hit_range, charge_progress)

Button Release → _on_ability_released()
  → If hold_time < min_charge_time:
      → Fire weak shot (weak_shot_damage_percent, weak_shot_range_percent)
  → Else:
      → Fire full shot with calculated range/damage
  → _fire_projectile() creates Projectile instance
  → Projectile travels, hits enemy or reaches max range
  → Start cooldown
```

**Key Properties (TalentData):**
- `effect_type`: PROJECTILE
- `min_charge_time`: Minimum hold for full power
- `max_charge_time`: Maximum charge time for full range (default 2.0s)
- `base_range`: Range at minimum charge (default 150px)
- `weak_shot_damage_percent`: Damage % if released early
- `weak_shot_range_percent`: Range % if released early
- `projectile_speed`: Travel speed
- `hit_range`: Maximum range at full charge

**Files:**
- `scripts/ui/combat/combat_hud.gd:402-588` - Aiming logic
- `scripts/combat/projectile.gd` - Arrow projectile
- `scripts/ui/combat/aim_indicator.gd` - Visual feedback

---

### 3. MAGIC Skills (Example: Basic Fireball)

**Player Flow:**
```
Button Press → CombatHUD._on_ability_activated()
  → Check effect_type == MAGIC_PROJECTILE
  → Consume mana immediately

  If cast_time > 0:
    → _start_casting() - Begin cast bar
    → During _update_casting(): Track elapsed time
    → When elapsed >= cast_time: _fire_magic_projectile()
  Else:
    → _fire_magic_projectile_instant()

_fire_magic_projectile():
  → Create MagicProjectile instance
  → Set explosion_radius, damage, contact_status_effect
  → Projectile travels toward target position
  → On enemy contact: Apply status effect, continue flying
  → At max range OR wall hit: Explode
    → AOE damage with 30% falloff at edge
    → Apply status effect to all in radius
  → Start cooldown
```

**Key Properties (TalentData):**
- `effect_type`: MAGIC_PROJECTILE
- `cast_time`: Seconds to channel before firing
- `explosion_radius`: AOE size at destination
- `contact_status_effect`: Effect applied on touch/explosion
- `projectile_speed`: Travel speed
- `base_damage`: Spell damage (not weapon-based)
- `damage_type`: fire, cold, lightning, etc.

**Files:**
- `scripts/ui/combat/combat_hud.gd:589-750` - Casting logic
- `scripts/combat/magic_projectile.gd` - Fireball projectile
- `scripts/effects/burning_effect.gd` - DoT visual

---

### 4. SELF-BUFF Skills (Example: Basic Bandage)

**Player Flow:**
```
Button Press → CombatHUD._on_ability_activated()
  → Check effect_type == SELF_BUFF

  If cast_time > 0:
    → _start_casting_self_buff()
    → During _update_self_buff_casting(): Track elapsed time
    → When elapsed >= cast_time: _apply_self_buff()
  Else:
    → _apply_self_buff_instant()

_apply_self_buff():
  → Game.player.status_effect_manager.apply_status_effect(contact_status_effect)
  → StatusEffectManager looks up effect in database
  → Creates HoT/buff based on effect type
  → HUD icon appears with duration timer
  → Start cooldown
```

**Key Properties (TalentData):**
- `effect_type`: SELF_BUFF
- `cast_time`: Channel duration
- `contact_status_effect`: Status effect ID to apply (e.g., "status_bandage")
- `cooldown`: Prevent spam

**Files:**
- `scripts/ui/combat/combat_hud.gd:751-850` - Self-buff logic
- `scripts/player/status_effect_manager.gd` - Effect application
- `scripts/ui/status_effect_display.gd` - HUD icons

---

## Building Blocks Reference

### Unified Components (Use These!)

| Component | Location | Used By | Purpose |
|-----------|----------|---------|---------|
| `StatusEffectComponent` | `scripts/combat/status_effect_component.gd` | Player & Enemy | DoT, HoT, buffs, debuffs |
| `MovementAction` | `scripts/combat/movement_action.gd` | Player & Enemy | Lunge, dash, knockback, charge |
| `DamageCalculator` | `autoloads/damage_calculator.gd` | Player & Enemy | All damage formulas with crit |
| `SkillBase` | `scripts/data/skill_base.gd` | TalentData & AbilityData | Shared enums and properties |
| `HitboxSpawner` | `scripts/npc/hitbox_spawner.gd` | Player & Enemy | Creates Area2D hitboxes for melee attacks |
| `Projectile` | `scripts/combat/projectile.gd` | Player (arrows) | Physical projectile with arc |
| `MagicProjectile` | `scripts/combat/magic_projectile.gd` | Player (spells) | Pass-through + AOE explosion |
| `HitboxVisual` | `scripts/ui/combat/hitbox_visual.gd` | Player & Enemy | Debug/feedback visualization |
| `AimIndicator` | `scripts/ui/combat/aim_indicator.gd` | Player (ranged) | Trajectory preview |

### Hitbox Shapes (HitboxSpawner)

```gdscript
enum HitboxShape { CIRCLE, CONE, LINE, CROSS, RING }

# Usage:
HitboxSpawner.spawn_hitbox(ability, caster, direction)

# Shapes:
CIRCLE - Radius around caster (AOE)
CONE   - Arc in facing direction (melee swipe)
LINE   - Narrow rectangle (thrust/stab)
CROSS  - Four directional lines (cross attack)
RING   - Expanding circle (shockwave)
```

### Projectile Types

```gdscript
# Physical Projectile (arrows)
var arrow = Projectile.create_arrow()
arrow.damage = calculated_damage
arrow.max_range = effective_range
arrow.piercing = true  # Pass through enemies
arrow.launch(spawn_pos, direction, speed_mult)

# Magic Projectile (fireballs)
var fireball = MagicProjectile.new()
fireball.explosion_damage = base_damage
fireball.explosion_radius = 60
fireball.contact_status_effect = "status_burning"
fireball.pass_through_enemies = true
fireball.launch(spawn_pos, direction, 1.0)
```

### Status Effect Application

```gdscript
# Player (via StatusEffectManager - extends StatusEffectComponent)
Game.player.status_effect_manager.apply_status_effect("status_bandage")
Game.player.status_effect_manager.apply_dot("burn", 5.0, 3.0, 1.0)
Game.player.status_effect_manager.apply_hot("regen", 10.0, 5.0, 1.0)

# Enemy (via StatusEffectComponent instance)
enemy.status_effects.apply_status_effect("status_burning")
enemy.status_effects.apply_dot("poison", 8.0, 5.0, 2.0)
enemy.apply_status_effect("status_burning")  # Convenience wrapper
```

---

## Attack Execution Phases

Both player and enemy attacks follow the same **three-phase pattern**, orchestrated by the Ability Visual Sequencer (see next section):

```
┌─────────────────────────────────────────────────────────────┐
│  WINDUP PHASE          EXECUTE PHASE         RECOVERY PHASE │
│  ─────────────         ─────────────         ────────────── │
│  • Warning visual      • Hitbox active       • Vulnerable   │
│  • Can be interrupted  • Damage applied      • Input locked │
│  • Movement locked     • Effects triggered   • Cooldown set │
│                                                              │
│  Player: animation     Player: attack frame  Player: recovery_time │
│  Enemy: ability.windup Enemy: hitbox spawn   Enemy: ability.recovery │
└─────────────────────────────────────────────────────────────┘
```

**Timing Values:**

| Actor | Windup | Execute | Recovery |
|-------|--------|---------|----------|
| Player Melee | Animation frames | ~0.1s (attack frame) | talent.recovery_time |
| Player Ranged | Charge time | Instant (projectile spawns) | 0 |
| Player Magic | cast_time | Instant (projectile spawns) | 0 |
| Enemy Default | 0.2s | Varies | 0.3s |
| Enemy Dash | 0.2s | Dash duration | 0.3s |

---

## Ability Visual Sequencer

The sequencer system replaces hardcoded animation/movement/timing logic with data-driven visual sequences. Each ability is defined as a timeline of phases that the sequencer steps through automatically.

### Architecture

```
TalentData / AbilityData
     ↓
CombatHUD / EnemyNPC (maps effect_type → template_id)
     ↓
AbilityVisualTemplates.get_all()[template_id]  →  AbilityVisualData
     ↓
AbilityVisualPlayer.play(data, target_pos, overrides)
     ↓
┌─────────────────────────────────────────────────┐
│  Phase 0: WEAPON_VISIBILITY(true)     [instant] │
│  Phase 1: BODY_ANIM("melee_windup")   [wait]    │
│  Phase 2: MOVEMENT + BODY_ANIM        [concurrent] │
│  Phase 3: DAMAGE_EVENT                [instant] │
│  Phase 4: BODY_ANIM("idle")           [instant] │
│  ...                                             │
│  → sequence_finished signal                      │
└─────────────────────────────────────────────────┘
     ↓
PlayerController / BaseCharacter unlocks movement
```

### Core Classes

| Class | File | Purpose |
|-------|------|---------|
| `AbilityVisualData` | `scripts/combat/ability_visual_data.gd` | Resource defining a named sequence of phases |
| `AbilityVisualPhase` | `scripts/combat/ability_visual_phase.gd` | Single phase (animation, movement, event, etc.) |
| `AbilityVisualPlayer` | `scripts/combat/ability_visual_player.gd` | Node that executes phases, emits signals |
| `AbilityVisualTemplates` | `scripts/combat/ability_visual_templates.gd` | Static factory for built-in templates |
| `CharacterVisuals` | `scripts/combat/character_visuals.gd` | Layered sprite stack (body, weapon, effects, overlay) |

### Phase Types

| Phase Type | Description | Timing |
|------------|-------------|--------|
| `BODY_ANIM` | Play a body animation (e.g., `"melee_windup"`) | `duration > 0`: timer. `duration = 0`: wait for `animation_finished` (skips if looping). |
| `MOVEMENT` | Lunge/dash via `movement_requested` signal | Timer based on duration |
| `DAMAGE_EVENT` | Emit `damage_event` signal (combat system applies damage) | Instant |
| `SPAWN_PROJECTILE` | Emit `spawn_projectile_event` signal | Instant |
| `WAIT` | Pure delay | Timer |
| `WEAPON_VISIBILITY` | Show/hide weapon layer | Instant |
| `EFFECT` | Trigger VFX via `effect_event` signal | `duration > 0`: timer. Else instant. |

### Concurrency

Phases with `concurrent = true` run alongside the next phase. Both must resolve before advancing. Used for movement + animation combos (e.g., lunge while playing strike animation).

### Templates

Templates define the visual shape of abilities. Actual durations come from talent/ability data via the override system.

| Template | Used For | Phase Sequence |
|----------|----------|----------------|
| `melee_single` | Basic melee attack | weapon show → windup → weapon hide → slash effect → lunge+strike → damage → idle |
| `melee_combo_2` | Two-hit melee | weapon show → windup → weapon hide → slash+lunge+strike → damage → pause → wide slash+strike → damage → idle |
| `melee_combo_3` | Three-hit melee | Same as combo_2 with third hit |
| `dash_attack` | Dash + strike | weapon show → dash+move → weapon hide → wide slash+strike → damage → idle |
| `ranged_aim` | Charge-to-fire ranged | weapon show → aim (held) → release → projectile → idle |
| `spell_cast` | Cast-time spell | cast+effect → release → projectile → idle |
| `spell_instant` | Instant spell | release → effect → damage → idle |
| `throw` | Throw item | windup+item → release → projectile → idle |
| `self_buff` | Self-buff | cast → effect → damage event → idle |
| `ranged_attack` | Enemy ranged | attack anim → projectile → wait |
| `howl` | Wolf howl | howl anim → aura effect → damage → wait |

### Override System

Templates use placeholder durations. Real values come from talent/ability data via override keys:

| Override Key | Source (Player) | Source (Enemy) |
|-------------|-----------------|----------------|
| `windup_duration` | — | `ability.windup` |
| `lunge_distance` | `talent.lunge_force` (with equipment bonus) | `ability.dash_speed * ability.windup` |
| `lunge_duration` | `talent.lunge_duration` | `ability.windup` |
| `recovery_duration` | `talent.recovery_time` | `ability.recovery` |
| `cast_duration` | `talent.cast_time` (with cast_speed bonus) | — |

Built in `CombatHUD._build_visual_overrides()` for player, or equivalent in `EnemyNPC` for enemies.

### Signal Flow

`AbilityVisualPlayer` emits signals at key moments. The character and combat systems listen:

| Signal | Listener | Action |
|--------|----------|--------|
| `sequence_started` | PlayerController | Set `is_attacking=true`, `is_locked=true` |
| `sequence_finished` | PlayerController | Set `is_attacking=false`, `is_locked=false` |
| `damage_event` | CombatHUD | Apply damage to enemies in range/arc |
| `spawn_projectile_event` | CombatHUD | Spawn projectile |
| `play_body_animation` | CharacterVisuals | Resolve and play animation on sprite |
| `movement_requested` | PlayerController | Execute lunge via velocity/timer |
| `weapon_visibility_changed` | CharacterVisuals | Show/hide weapon sprite layer |
| `effect_event` | CharacterVisuals | Spawn VFX on effect anchor |

### Animation Name Resolution

Both `AbilityVisualPlayer` and `CharacterVisuals` resolve animation names using a fallback chain:

1. `{action}_{direction}` — e.g., `melee_windup_down`
2. `{action}` — directionless fallback
3. `attack_{direction}` — legacy fallback
4. `idle_{direction}` — final fallback

Left-facing uses the `right` animations with `flip_h = true`.

**Important:** Looping animations (idle, walk) never emit `animation_finished`. The sequencer detects this and advances immediately instead of waiting.

### Weapon Visibility Model

Weapons are hidden by default and only appear during ability sequences via `WEAPON_VISIBILITY` phases.

**Melee abilities:**
- Weapon visible during **windup** (preparation/dramatic reveal)
- Weapon hidden during **strike** (replaced by slash effect VFX)
- Weapon hidden during **recovery** and **idle**

**Ranged abilities** (future):
- Weapon visible during **aim** and **release**
- Hidden after projectile spawns

**Magic abilities** (future):
- Weapon visible during **cast** (channeling with staff)
- Hidden after release

**No-weapon abilities** (throw, self_buff):
- Weapon hidden throughout

### Combat Effects

Effects are spawned during `EFFECT` phases via the `effect_event` signal. `CharacterVisuals` delegates to `PlaceholderEffectSprites` which generates self-animating Node2D VFX.

Effects are **direction-aware** — they orient and offset based on the character's facing direction.

| Effect | Visual | Lifetime |
|--------|--------|----------|
| `slash_arc` | Arc sweep VFX | 0.15s |
| `slash_arc_wide` | Wider arc for combos | 0.18s |
| `thrust_line` | Directional stab line | 0.12s |
| `impact_spark` | Hit confirmation flash | 0.10s |

### CharacterVisuals (Layered Sprite Stack)

Manages visual layers alongside the body `AnimatedSprite2D`:

```
CharacterVisuals (Node2D)
  ├── WeaponSprite (Sprite2D)     — positioned per-frame at weapon anchor pixel
  ├── EffectAnchor (Node2D)       — parent for VFX nodes
  └── OverlaySprite (AnimatedSprite2D) — hit flashes, shields
```

**Weapon Anchor**: A magenta pixel (`#FF00AA`) in attack frame sprites marks where the weapon sprite should be positioned. `CharacterVisuals` scans for this pixel each frame.

### Routing: Sequencer vs Legacy

`CombatHUD._on_ability_activated()` routes abilities:

| Condition | Path |
|-----------|------|
| `ability_visual_player` exists | Sequencer path (`_activate_skill_via_sequencer`) |
| Otherwise | Legacy path (`_activate_skill_legacy`) |

Within the sequencer path:

| Condition | Action |
|-----------|--------|
| `effect_type == PROJECTILE` | `_start_aiming()` (hold-to-charge) |
| `cast_time > 0` | Delegate to legacy path (handles cast bar) |
| Everything else | Play visual sequence immediately |

### Key Files

| File | Role |
|------|------|
| `scripts/combat/ability_visual_data.gd` | Sequence data resource |
| `scripts/combat/ability_visual_phase.gd` | Phase definition + factory helpers |
| `scripts/combat/ability_visual_player.gd` | Sequencer executor |
| `scripts/combat/ability_visual_templates.gd` | Built-in template definitions |
| `scripts/combat/character_visuals.gd` | Layered sprite stack |
| `scripts/player/player_controller.gd` | Player integration (setup, movement, lock/unlock) |
| `scripts/player/player_animator.gd` | Animator integration (sequence awareness) |
| `scripts/ui/combat/combat_hud.gd` | Template mapping, overrides, signal handling |

---

## Status Effects System

### Effect Types

| Type | Code | Ticks | Example |
|------|------|-------|---------|
| `debuff_dot` | Damage over time | Yes | Burning, Poison, Rot |
| `buff_hot` | Heal over time | Yes | Bandage, Regeneration |
| `buff` | Stat modifier | No | Strength buff, Speed buff |
| `debuff` | Negative modifier | No | Slow, Weakness |

### Database Structure (status_effects.json)

```json
{
  "id": "status_bandage",
  "name": "Bandage",
  "type": "buff_hot",
  "stat_affected": "health",
  "value": 10,
  "duration": 30,
  "tick_interval": 2,
  "show_in_hud": true,
  "ends_when": ""
}
```

### Conditional Removal (ends_when)

Status effects can be configured to automatically end when certain conditions are met, independent of their duration.

| Condition | Description |
|-----------|-------------|
| `player_full_health` | Effect ends when player heals to max HP |
| `player_below_50` | Effect ends when player drops below 50% HP |
| `player_above_50` | Effect ends when player exceeds 50% HP |
| `player_health_above_X` | Parameterized: ends when above X% (e.g., `player_health_above_75`) |
| `player_health_below_X` | Parameterized: ends when below X% (e.g., `player_health_below_25`) |

**Example - Blood Frenzy buff that ends when player heals:**
```json
{
  "id": "status_blood_frenzy",
  "name": "Blood Frenzy",
  "type": "buff",
  "duration": 60,
  "ends_when": "player_full_health"
}
```

**Code Usage:**
```gdscript
# Apply buff that ends when player heals to full
status_effect_manager.apply_buff("blood_frenzy", 60.0, true, "player_full_health")
```

### Player vs Enemy Implementation

Both player and enemies now use the **unified StatusEffectComponent**:

| Feature | Player (StatusEffectManager) | Enemy (StatusEffectComponent) |
|---------|------------------------------|-------------------------------|
| Base Class | Extends StatusEffectComponent | Direct instance |
| Persistence | Yes (saved/loaded across zones) | No |
| Supported | DoT, HoT, Buff, Debuff, Permanent | DoT, HoT, Buff, Debuff, Permanent |
| Signals | Yes (effect_applied, effect_removed, effect_tick) | Yes (same signals) |
| Visual | HUD icons + effects | Effect-specific visuals (burning, etc.) |
| Damage/Heal | Routes through PlayerStats | Direct to current_health |

**Architecture:**
```
StatusEffectComponent (base class)
├── StatusEffectManager (player extension with persistence)
└── Instance on EnemyNPC (via composition)
```

---

## Projectile System

### Collision Layers

| Layer | Bit | Purpose |
|-------|-----|---------|
| 1 | `0b00000001` | Walls/Obstacles |
| 2 | `0b00000010` | Player |
| 3 | `0b00000100` | Enemies |
| 4 | `0b00001000` | Player Hitboxes |
| 5 | `0b00010000` | Enemy Hurtboxes |

### Projectile Configuration

```gdscript
# Regular Projectile (Projectile.gd)
collision_layer = 0        # Doesn't block anything
collision_mask = 0b00000011  # Detects walls + enemies
raycast.mask = 0b00000001   # Wall detection only

# Magic Projectile (MagicProjectile.gd)
collision_layer = 0
collision_mask = 0b00000011
raycast.mask = 0b00000001
pass_through_enemies = true
```

### Wall Detection

Projectiles use **RayCast2D** for wall detection (not Area2D collision) because:
1. Fast projectiles might clip through thin walls
2. RayCast looks ahead by velocity * delta
3. Immediate response on wall hit

```gdscript
func _physics_process(delta):
    raycast.target_position = velocity.normalized() * 20  # Look ahead
    if raycast.is_colliding():
        var collider = raycast.get_collider()
        if collider.is_in_group("walls") or collider is TileMap:
            _hit_wall()
```

---

## Enemy AI and Abilities

> **Note:** The enemy AI system uses a modular architecture. For complete documentation including all modules, configurations, and behavior examples, see `docs/ENEMY_REFERENCE.md`.

### Modular AI Overview

Enemies use a module-based AI system where each module handles one aspect of behavior:

```
ModuleController._process()
  ↓
For each module (by priority, highest first):
  ├─ mod_target_detection (100) - Find targets
  ├─ mod_pack_alert (95) - Alert allies
  ├─ mod_leash (90) - Check distance from home
  ├─ mod_flee (85) - Run if low health
  ├─ mod_chase (80) - Move toward target
  ├─ mod_surround (78) - Spread from allies
  ├─ mod_kite (75) - Maintain distance
  ├─ mod_combat (60) - Execute abilities
  └─ mod_idle (10) - Roam when no target
        ↓
  Each module reads/writes to EnemyContext
        ↓
  EnemyNPC applies context (movement, attacks)
```

### Ability Types

| Type | Description |
|------|-------------|
| `melee` | Close-range hitbox attack |
| `projectile` | Spawns traveling projectile |
| `dash` | Movement + attack (dash_to, dash_away, teleport) |
| `buff` | Self-buff (healing, shields) |
| `debuff` | Apply status to target |

### Ability Conditions

| Condition | When Used |
|-----------|-----------|
| `default` | Always available |
| `opener` | First attack on new target |
| `health_below_X` | Health < X% |
| `target_melee` | Within melee range |
| `target_close_X` | Within X pixels |

See `docs/ENEMY_REFERENCE.md` for complete module configs, behavior examples, and decision trees.

---

## Unified Building Blocks

The following systems are now **unified** and shared between player and enemies:

### StatusEffectComponent (Buffs/Debuffs)

**Files:**
- `scripts/combat/status_effect_component.gd` - Base class
- `scripts/player/status_effect_manager.gd` - Player extension with persistence

**Features:**
- DoT (Damage over Time)
- HoT (Heal over Time)
- Buffs and debuffs
- Signal-based UI updates
- Database-driven effect definitions

**Godot Load Order Note:**
Due to Godot's class_name resolution order, direct `extends StatusEffectComponent` or
`var x: StatusEffectComponent` may fail. Use these patterns instead:

```gdscript
# For inheritance (status_effect_manager.gd):
extends "res://scripts/combat/status_effect_component.gd"
class_name StatusEffectManager

# For composition (enemy_npc.gd):
const StatusEffectComponentScript = preload("res://scripts/combat/status_effect_component.gd")
var status_effects: Node = null  # StatusEffectComponent instance

func _setup_status_effects() -> void:
    status_effects = StatusEffectComponentScript.new()
    status_effects.setup(self)
    add_child(status_effects)
```

**Usage:**
```gdscript
# Player (via StatusEffectManager)
Game.player.status_effect_manager.apply_status_effect("status_bandage")
Game.player.status_effect_manager.apply_dot("burn", 5.0, 3.0, 1.0)

# Enemy (via StatusEffectComponent)
enemy.status_effects.apply_status_effect("status_burning")
enemy.apply_status_effect("status_burning")  # Convenience method
```

---

### MovementAction (Lunge/Dash/Knockback)

**File:** `scripts/combat/movement_action.gd`

**Features:**
- Lunge (short forward burst for melee)
- Dash (move to target position)
- Knockback (forced movement away)
- Charge (extended forward movement)
- Teleport (instant position change)

**Usage:**
```gdscript
# Create a lunge
var lunge = MovementAction.create_lunge(direction, 80.0, 0.1)

# Create a dash
var dash = MovementAction.create_dash(start_pos, target_pos, 400.0)

# Create knockback
var knockback = MovementAction.create_knockback(source_pos, target_pos, 150.0)

# Execute
action.start(current_position)
while action.is_active():
    velocity = action.update(delta, current_position)
```

---

### MovementValidator (Wall Collision)

**File:** `scripts/navigation/movement_validator.gd`

Validates movement abilities against walls before execution. Prevents characters from clipping through walls during dashes, lunges, charges, and knockback.

**Features:**
- Path validation using raycast
- Safe target calculation with 4px wall margin
- Proportional duration adjustment for shortened movements
- Minimum distance threshold (8px) - cancels if too short

**Usage:**
```gdscript
# Validate a dash
var validation = MovementValidator.validate_dash_directional(start_pos, direction, distance)
if validation.blocked:
    # Movement was shortened - use adjusted values
    var safe_end = validation.position
    var safe_distance = validation.distance

# Validate knockback on enemies
func apply_knockback(source_pos: Vector2, force: float, duration: float = 0.2) -> void:
    var direction = source_pos.direction_to(global_position)
    var knockback_distance = force * duration

    var validation = MovementValidator.validate_knockback(global_position, direction, knockback_distance)
    if validation.cancelled:
        return  # Too close to wall

    # Apply with adjusted force if blocked
    var adjusted_force = validation.distance / duration if validation.blocked else force
    _knockback_velocity = direction * adjusted_force
```

**Validation Results:**
| Field | Type | Description |
|-------|------|-------------|
| `position` | Vector2 | Safe end position |
| `distance` | float | Achievable distance |
| `blocked` | bool | True if wall was hit |
| `block_point` | Vector2 | Where collision occurred |
| `cancelled` | bool | (knockback only) True if <8px movement |

**Debug Visualization:**
- Orange/Cyan line: Actual movement path
- Red line: Blocked portion that was prevented

---

### DamageCalculator (Unified Damage Math)

**File:** `autoloads/damage_calculator.gd`

**Player Methods:**
- `calculate_skill_damage(talent, skill_rank)` - Weapon/magic damage
- `calculate_final_damage(talent, skill_rank)` - With crit roll
- `calculate_basic_attack()` - Weapon + attack power

**Enemy Methods:**
- `calculate_enemy_ability_damage(ability, base_damage, level)` - Ability damage
- `calculate_enemy_basic_attack(base_damage, level)` - Basic attack
- `calculate_enemy_damage_taken(damage, armor, resist, type)` - Mitigation

**Usage:**
```gdscript
# Player attack
var result = DamageCalculator.calculate_final_damage(talent, rank)
enemy.take_damage(result.final_damage, player)

# Enemy attack (now goes through DamageCalculator)
var result = DamageCalculator.calculate_enemy_ability_damage(ability, enemy.base_damage, enemy.enemy_level)
player.take_damage(result.final_damage, enemy)
```

---

### SkillBase (Shared Skill Properties)

**File:** `scripts/data/skill_base.gd`

**Shared Enums:**
- `DamageType` - PHYSICAL, FIRE, COLD, LIGHTNING, etc.
- `HitboxShape` - CIRCLE, CONE, LINE, CROSS, RING

**Shared Properties:**
- `id`, `skill_name`, `description`
- `damage_type`, `cooldown`, `skill_range`
- `status_effect_on_hit`

**Helper Methods:**
- `damage_type_from_string()` / `damage_type_to_string()`
- `hitbox_shape_from_string()` / `hitbox_shape_to_string()`
- `get_damage_type_color()` - For visual effects

---

### Other Shared Systems

| System | Files | Notes |
|--------|-------|-------|
| Hitbox Spawning | `hitbox_spawner.gd` | Both use same shapes |
| Projectiles | `projectile.gd`, `magic_projectile.gd` | Player and enemy projectiles |
| Collision Layers | `COLLISION_LAYERS.md` | Documented standard |
| Visual Effects | `hitbox_visual.gd` | Debug visualization |

---

## Godot Patterns & Gotchas

### Class Name Load Order Issues

Godot parses scripts in an unpredictable order. When Script A tries to reference Script B's
`class_name` before Script B has been parsed, you get:

```
Parse Error: Could not find type "ClassName" in the current scope
```

**Solutions:**

#### 1. Path-Based Extends (for inheritance)

Instead of:
```gdscript
extends StatusEffectComponent  # May fail!
class_name StatusEffectManager
```

Use:
```gdscript
extends "res://scripts/combat/status_effect_component.gd"
class_name StatusEffectManager
```

#### 2. Preload Pattern (for composition/instantiation)

Instead of:
```gdscript
var component: StatusEffectComponent = null  # May fail!

func _ready():
    component = StatusEffectComponent.new()  # May fail!
```

Use:
```gdscript
const StatusEffectComponentScript = preload("res://scripts/combat/status_effect_component.gd")
var component: Node = null  # Use Node or untyped

func _ready():
    component = StatusEffectComponentScript.new()  # Works!
```

#### 3. Dynamic Type Annotations

For function parameters and return types, use `Node` or omit the type:
```gdscript
# Instead of: func get_status_effects() -> StatusEffectComponent:
func get_status_effects() -> Node:
    return status_effects
```

### Files Using These Patterns

| File | Pattern | Why |
|------|---------|-----|
| `status_effect_manager.gd` | Path-based extends | Extends StatusEffectComponent |
| `enemy_npc.gd` | Preload + composition | Creates StatusEffectComponent instance |
| `enemy_npc.gd` | Dynamic typing | `ability_controller` and `behavior_profile` vars |

### When This Happens

- Custom classes in `scripts/` referencing each other
- Especially common with component/manager patterns
- Autoloads (in `autoloads/`) are usually safe to reference by class_name

---

## Database-Driven Stats & Skills

The game uses a **3-layer precedence system** for all numeric values:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: Talent/Ability Data (Highest Priority)           │
│  Skills can override any value specifically                 │
│  Example: tal_heavy_slam has lunge_duration: 0.3            │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2: GameplaySettings Database                         │
│  Global defaults for all base values                        │
│  Example: base_lunge_duration: 0.1                          │
├─────────────────────────────────────────────────────────────┤
│  LAYER 3: Code Defaults (Fallback)                          │
│  Hardcoded values if database missing                       │
│  Example: const DEFAULT_LUNGE_DURATION = 0.1                │
└─────────────────────────────────────────────────────────────┘
```

### Value Resolution Example

```gdscript
# When executing a skill:
var lunge_duration: float

# 1. Check talent data first
if talent.lunge_duration > 0:
    lunge_duration = talent.lunge_duration
# 2. Fall back to database setting
elif DatabaseLoader.has_setting("base_lunge_duration"):
    lunge_duration = DatabaseLoader.get_setting("base_lunge_duration", 0.1)
# 3. Use code default
else:
    lunge_duration = 0.1
```

### GameplaySettings Database

All base values are stored in `gameplay_settings.json` and loaded by `DatabaseLoader`:

**Base Stats (Character)**

| Key | Default | Description |
|-----|---------|-------------|
| `base_health_flat` | 80.0 | Starting health before vitality |
| `base_mana_flat` | 30.0 | Starting mana before energy |
| `base_stamina_flat` | 100.0 | Starting stamina |
| `base_crit_chance` | 5.0 | Base critical hit chance % |
| `base_crit_damage` | 150.0 | Base critical damage multiplier % |

**Derived Stat Conversions**

| Key | Default | Description |
|-----|---------|-------------|
| `health_per_vitality` | 2.0 | Health gained per point of vitality |
| `mana_per_energy` | 1.5 | Mana gained per point of energy |
| `crit_damage_per_luck` | 1.0 | Crit damage % gained per point of luck |

**Regeneration Rates**

| Key | Default | Description |
|-----|---------|-------------|
| `base_life_regen` | 1.0 | Health regenerated per second |
| `base_mana_regen` | 0.5 | Mana regenerated per second |
| `base_stamina_regen` | 10.0 | Stamina regenerated per second |

**Movement & Combat**

| Key | Default | Description |
|-----|---------|-------------|
| `base_move_speed` | 150.0 | Default player movement speed |
| `base_dodge_speed` | 300.0 | Dodge roll speed |
| `base_dodge_duration` | 0.3 | Dodge roll duration in seconds |
| `base_dodge_stamina_cost` | 25.0 | Stamina cost for dodge |
| `base_lunge_force` | 80.0 | Default attack lunge force |
| `base_lunge_duration` | 0.1 | Default attack lunge duration |
| `armor_constant` | 50.0 | The "k" in armor formula |

### Derived vs Stored Stats

Some stats are **derived** (calculated) rather than stored:

```gdscript
# Stored in database/character - these are BASE values
var health_base_flat: float = 80.0    # From GameplaySettings
var vitality: int = 10                 # From character/equipment

# Derived at runtime - NEVER stored in database
var max_health: float = health_base_flat + (vitality * health_per_vitality)
var max_mana: float = mana_base_flat + (energy * mana_per_energy)
var critical_damage: float = crit_damage_base + (luck * crit_damage_per_luck)
```

**Why This Matters:**
- Primary stats (STR, DEX, INT) are for item requirements only
- VIT, ENE, LCK directly affect derived stats
- Equipment bonuses stack additively before derivation

### Skill Properties (Per-Talent)

Each skill can define its own values in `talents.json`:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `hit_range` | float | 50 | Melee/projectile range in pixels |
| `hit_arc` | float | 90 | Cone angle for melee (360 = all around) |
| `lunge_force` | float | 80 | Forward momentum on attack |
| `lunge_duration` | float | 0.1 | How long lunge lasts |
| `explosion_radius` | float | 0 | AOE size for magic |
| `projectile_speed` | float | 400 | Speed of projectiles |
| `cast_time` | float | 0 | Channel time before effect |
| `recovery_time` | float | 0.3 | Input lockout after attack |
| `cooldown` | float | 0 | Time before reuse |
| `min_charge_time` | float | 0.5 | Minimum hold for charged attacks |
| `max_charge_time` | float | 2.0 | Maximum charge time |
| `base_range` | float | 150 | Range at minimum charge |
| `weak_shot_damage_percent` | float | 30 | Damage % if released early |

---

## Equipment Modifier System

Equipment can provide percentage bonuses to skill properties. This allows items to enhance specific playstyles.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  FORMULA: final_value = talent_value × (1 + bonus% / 100)  │
└─────────────────────────────────────────────────────────────┘

Example:
- Talent hit_range: 60 pixels
- Equipment bonus: +25% hit_range
- Final: 60 × (1 + 25/100) = 60 × 1.25 = 75 pixels
```

### Available Skill Modifiers

Equipment affixes can modify these skill properties:

| Modifier | Effect | Example |
|----------|--------|---------|
| `hit_range` | Increases melee/projectile range | "+15% Hit Range" |
| `hit_arc` | Wider melee attack arc | "+20% Hit Arc" |
| `lunge_force` | Stronger forward momentum | "+10% Lunge Force" |
| `lunge_duration` | Longer lunge movement | "+25% Lunge Duration" |
| `explosion_radius` | Larger AOE effects | "+30% Explosion Radius" |
| `projectile_speed` | Faster projectiles | "+15% Projectile Speed" |
| `cast_speed` | Faster spell casting | "+20% Cast Speed" (reduces cast_time) |
| `cooldown_reduction` | Lower cooldowns | "+10% Cooldown Reduction" (capped at 75%) |

### Implementation (combat_hud.gd)

```gdscript
# Get modified skill values with equipment bonuses applied
static func calc_skill_value(base_value: float, stat_name: String) -> float:
    if base_value <= 0:
        return base_value
    var bonus := PlayerStats.get_equipment_bonus(stat_name)
    return base_value * (1.0 + bonus / 100.0)

static func get_hit_range(talent: TalentData) -> float:
    return calc_skill_value(talent.hit_range, "hit_range")

static func get_explosion_radius(talent: TalentData) -> float:
    return calc_skill_value(talent.explosion_radius, "explosion_radius")

# Special handling for cast_speed (inverse - faster = less time)
static func get_cast_time(talent: TalentData) -> float:
    var cast_speed_bonus := PlayerStats.get_equipment_bonus("cast_speed")
    if cast_speed_bonus > 0 and talent.cast_time > 0:
        return talent.cast_time / (1.0 + cast_speed_bonus / 100.0)
    return talent.cast_time

# Special handling for cooldown reduction (capped at 75%)
static func get_cooldown(talent: TalentData) -> float:
    var cdr := PlayerStats.get_equipment_bonus("cooldown_reduction")
    if cdr > 0 and talent.cooldown > 0:
        return talent.cooldown * (1.0 - minf(cdr, 75.0) / 100.0)
    return talent.cooldown
```

### Adding Skill Modifiers to Items

In the Excel database, add skill modifiers to the Affixes sheet:

```
ID: pre_extended
Name: Extended
Type: prefix
Stat Modifier: hit_range
Min Value: 10
Max Value: 25
Allowed Tags: weapon,melee
```

This creates items like "Extended Iron Sword" with "+10-25% Hit Range".

### Files Involved

| File | Purpose |
|------|---------|
| `autoloads/player_stats.gd` | Loads base values, calculates equipment bonuses |
| `scripts/ui/combat/combat_hud.gd` | Applies modifiers when using skills |
| `scripts/player/player_controller.gd` | Applies movement-related modifiers |
| `databases/vba/ItemDatabase.bas` | Validates skill modifier affix names |

### Still Hardcoded (Requires Code Changes)

| Category | Values | Location |
|----------|--------|----------|
| Enemy phases defaults | windup=0.2s, recovery=0.3s | ability_executor.gd |
| CDR cap | 75% maximum | combat_hud.gd |

---

## Adding New Content Guide

### Adding a New Melee Skill

1. **Database**: Add to `talents.json` via Excel export
   ```
   effect_type: damage (or empty for melee default)
   skill_category: melee
   hit_range: 50-80
   hit_arc: 90-180
   lunge_force: 40-80
   ```

2. **No code changes needed** - CombatHUD routes automatically

### Adding a New Ranged Skill

1. **Database**: Add to `talents.json`
   ```
   effect_type: projectile
   skill_category: ranged
   min_charge_time: 0.5
   weak_shot_damage_percent: 30
   projectile_speed: 400
   ```

2. **No code changes needed** - Uses existing Projectile system

### Adding a New Magic Skill

1. **Database**: Add to `talents.json`
   ```
   effect_type: magic_projectile
   skill_category: magic
   cast_time: 0.5
   explosion_radius: 60
   contact_status_effect: status_burning
   projectile_speed: 350
   ```

2. **If new status effect**: Add to `status_effects.json`
   ```json
   {
     "id": "status_freeze",
     "type": "debuff",
     "duration": 3,
     "value": -50,
     "stat_affected": "movement_speed"
   }
   ```

3. **If new visual effect**: Create script in `scripts/effects/`

### Adding a New Self-Buff Skill

1. **Database**: Add to `talents.json`
   ```
   effect_type: self_buff
   cast_time: 2
   contact_status_effect: status_newbuff
   cooldown: 60
   ```

2. **Database**: Add status effect to `status_effects.json`
   ```json
   {
     "id": "status_newbuff",
     "type": "buff_hot",
     "value": 10,
     "duration": 30,
     "tick_interval": 2
   }
   ```

### Adding a New Enemy Ability

1. **Database**: Add to enemy's ability list
   ```json
   {
     "id": "ghoul_dash_strike",
     "type": "dash_attack",
     "damage_mult": 1.5,
     "range_max": 150,
     "hitbox_shape": "cone",
     "effects": ["knockback:100"]
   }
   ```

2. **If new ability type**: Extend `AbilityExecutor._complete_windup()` switch

### Adding a New Status Effect Type

1. **Database**: Define in `status_effects.json`

2. **Code**: Add handling in `StatusEffectManager.apply_status_effect()`:
   ```gdscript
   match effect_type:
       "buff_speed":
           apply_speed_buff(effect_name, duration, value)
   ```

3. **Code**: Add visual in `StatusEffectIcon._get_effect_color()`:
   ```gdscript
   "speed":
       return Color(0.3, 0.7, 1.0)  # Light blue
   ```

---

## Quick Reference: File Locations

| System | Key Files |
|--------|-----------|
| **Player Combat** | `scripts/ui/combat/combat_hud.gd` |
| **Player Movement** | `scripts/player/player_controller.gd` |
| **Damage Math** | `autoloads/damage_calculator.gd` |
| **Skill Data** | `scripts/data/talent_data.gd`, `scripts/data/skill_base.gd` |
| **Enemy AI** | `scripts/npc/enemy_behavior.gd` |
| **Enemy Abilities** | `scripts/npc/enemy_ability_controller.gd`, `ability_executor.gd` |
| **Ability Data** | `scripts/data/ability_data.gd` |
| **Projectiles** | `scripts/combat/projectile.gd`, `magic_projectile.gd` |
| **Hitboxes** | `scripts/npc/hitbox_spawner.gd` |
| **Status Effects** | `scripts/combat/status_effect_component.gd`, `scripts/player/status_effect_manager.gd` |
| **Movement Actions** | `scripts/combat/movement_action.gd` |
| **Visual Effects** | `scripts/effects/`, `scripts/ui/combat/hitbox_visual.gd` |
| **Ability Sequencer** | `scripts/combat/ability_visual_player.gd`, `ability_visual_data.gd`, `ability_visual_phase.gd` |
| **Visual Templates** | `scripts/combat/ability_visual_templates.gd` |
| **Character Visuals** | `scripts/combat/character_visuals.gd` |

---

## Version History

| Date | Changes |
|------|---------|
| 2026-01-02 | Initial documentation |
| 2026-01-02 | Unified systems: StatusEffectComponent, MovementAction, DamageCalculator for enemies, SkillBase |
| 2026-01-02 | Added Godot load order patterns (preload/path-based extends) for StatusEffectComponent |
| 2026-01-02 | Major refactor: Database-driven stats system with 3-layer precedence (Talent > GameplaySettings > Code) |
| 2026-01-02 | Added Equipment Modifier System for skill properties (hit_range, explosion_radius, cast_speed, etc.) |
| 2026-01-02 | Clarified skill categories are examples, not rigid templates |
| 2026-01-03 | Fixed skill bind to leftmost slot (slot 0) now binds to Attack button on combat HUD |
| 2026-01-03 | Fixed popup message container blocking clicks on hamburger menu (mouse_filter = IGNORE) |
| 2026-01-03 | Fixed crash when entering crypt (enemy_name vs npc_name property) |
| 2026-01-03 | Fixed status effect HUD not refreshing duration on reapplication (emit signal on refresh) |
| 2026-01-03 | Added database-driven stat descriptions for Stats panel (StatDescriptions sheet) |
| 2026-01-03 | Changed elemental spell damage from percentage to flat bonus (Fire, Cold, Lightning, Poison, Arcane) |
| 2026-02-16 | Added Ability Visual Sequencer section (AbilityVisualPlayer, templates, CharacterVisuals, signal flow) |
| 2026-02-16 | Added weapon placeholder system: direction-aware weapon sprites, melee effect VFX, revised melee templates with cinematic weapon show/hide pattern |
