# Combat System Architecture

This document provides a comprehensive overview of the combat system, its building blocks, and recommendations for future development.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [The Four Skill Templates](#the-four-skill-templates)
3. [Building Blocks Reference](#building-blocks-reference)
4. [Attack Execution Phases](#attack-execution-phases)
5. [Status Effects System](#status-effects-system)
6. [Projectile System](#projectile-system)
7. [Enemy AI and Abilities](#enemy-ai-and-abilities)
8. [Unified Building Blocks](#unified-building-blocks)
9. [Godot Patterns & Gotchas](#godot-patterns--gotchas)
10. [Database-Driven vs Hardcoded](#database-driven-vs-hardcoded)
11. [Adding New Content Guide](#adding-new-content-guide)

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

## The Four Skill Templates

### 1. MELEE Skills

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

### 2. RANGED Skills (Hold-to-Charge)

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

### 3. MAGIC Skills (Cast Time + Projectile)

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

### 4. SELF-BUFF Skills (Cast Time + Status Effect)

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

Both player and enemy attacks follow the same **three-phase pattern**:

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
  "show_in_hud": true
}
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

### AI Decision Flow

```
EnemyBehavior._update_behavior()
  ↓
Has target in detection_radius?
  ├─ NO → _do_idle() (roam or stand)
  └─ YES → Check distance to target
              ├─ > attack_radius → _do_chase()
              └─ <= attack_radius → _do_attack()
                    ↓
              EnemyAbilityController._select_ability()
                ├─ Filter by: cooldown, range, conditions
                └─ Select by: priority mode (HIGHEST/CONDITIONAL/RANDOM)
                    ↓
              AbilityExecutor.execute_ability()
                ├─ WINDUP phase (0.2s)
                ├─ EXECUTE phase (spawn hitbox / dash / projectile)
                └─ RECOVERY phase (0.3s)
```

### Ability Selection Modes

| Mode | Behavior |
|------|----------|
| `HIGHEST` | Always pick highest priority ability |
| `CONDITIONAL` | Prefer abilities with matching conditions |
| `RANDOM_WEIGHTED` | Random selection weighted by priority |

### Ability Types (AbilityData)

```gdscript
enum AbilityType {
    MELEE,           # Instant hitbox at position
    DASH_ATTACK,     # Move to target, then hitbox (Ghoul!)
    AOE,             # Circular area damage
    PROJECTILE,      # Launch traveling projectile
    TELEPORT_ATTACK, # Teleport behind target, attack
    PATTERN,         # Multi-directional (cross, etc.)
    BEAM             # Sweeping line attack
}
```

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

## Database-Driven vs Hardcoded

### Database-Driven (Flexible, No Code Changes)

| Category | Examples |
|----------|----------|
| Skill definitions | name, damage, costs, cooldowns, ranges |
| Status effects | duration, tick interval, value |
| Enemy abilities | type, damage mult, hitbox shape |
| Behavior profiles | detection range, ability selection mode |

### Now Database-Driven (Previously Hardcoded)

| Category | Database Field | Default | Notes |
|----------|---------------|---------|-------|
| Max charge time | `max_charge_time` | 2.0s | Per-talent in talents.json |
| Base range | `base_range` | 150px | Per-talent in talents.json |
| Lunge duration | `lunge_duration` | 0.1s | Per-talent in talents.json |
| Explosion falloff | `explosion_falloff` | 30% | Per-talent AND per-enemy-ability |
| Armor constant | `armor_constant` | 50.0 | gameplay_settings.json |
| Effect colors | `icon_color` | (fallback) | Per-effect in status_effects.json |

### gameplay_settings.json Keys

| Key | Default | Description |
|-----|---------|-------------|
| `armor_constant` | 50.0 | The "k" value in armor formula: `armor / (armor + k * level)` |
| `default_crit_multiplier` | 150.0 | Base crit damage multiplier % |
| `player_move_speed` | 150.0 | Default player movement speed |
| `player_dodge_speed` | 300.0 | Dodge roll speed |
| `player_dodge_duration` | 0.3 | Dodge roll duration in seconds |
| `player_dodge_stamina_cost` | 25.0 | Stamina cost for dodge |
| `player_attack_lunge_force` | 80.0 | Default attack lunge force |
| `player_attack_lunge_duration` | 0.1 | Default attack lunge duration |

### Still Hardcoded (Requires Code Changes)

| Category | Values | Location |
|----------|--------|----------|
| Enemy phases defaults | windup=0.2s, recovery=0.3s | ability_executor.gd |

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

---

## Version History

| Date | Changes |
|------|---------|
| 2026-01-02 | Initial documentation |
| 2026-01-02 | Unified systems: StatusEffectComponent, MovementAction, DamageCalculator for enemies, SkillBase |
| 2026-01-02 | Added Godot load order patterns (preload/path-based extends) for StatusEffectComponent |
