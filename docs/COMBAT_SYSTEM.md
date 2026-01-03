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
