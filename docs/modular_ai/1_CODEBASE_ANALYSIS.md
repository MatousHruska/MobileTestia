# MobileTestia Codebase Analysis
## Complete Inventory of Existing Systems

---

## Executive Summary

### Current State Assessment
MobileTestia has a **well-structured, database-driven** enemy AI system with clear separation of concerns. The codebase already employs several modular patterns including component-based design, signal-driven communication, and data-driven configuration.

### Feasibility Rating: **HIGH**
The existing architecture is highly compatible with a modular AI system. Key factors:
- ✅ Database-driven configuration already in place
- ✅ Component pattern already used (StatusEffectComponent, ShieldComponent)
- ✅ Signal-based communication widespread (381+ emit/connect calls)
- ✅ Clear separation between AI logic (EnemyBehavior) and ability execution (AbilityExecutor)
- ✅ Resource-based data classes (AbilityData, BehaviorProfileData)

### Estimated Effort: **MEDIUM**
- Phase 0 (Foundation): 2-3 days
- Phase 1 (Simple Conversion): 3-5 days
- Phase 2 (Core Modules): 1-2 weeks
- Phase 3 (Complex Behaviors): 1-2 weeks
- Phase 4 (Full Migration): 1 week

### Recommended Approach
**Evolutionary Migration** - Build the modular system alongside existing code, convert enemies incrementally, and deprecate old systems only after validation.

### Key Decision Points
1. **Context Storage**: Dictionary vs. typed class for EnemyContext?
2. **Module Granularity**: Fine-grained (10+ modules) vs. coarse (5-6 modules)?
3. **Execution Model**: Per-frame evaluation vs. interval-based ticks?
4. **Pack Behavior**: Add new capability or defer?

---

## I. Enemy System Architecture

### Class Hierarchy

```
CharacterBody2D
└── BaseCharacter (scripts/npc/base_character.gd)
    ├── EnemyNPC (scripts/npc/enemy_npc.gd) - Hostile NPCs
    ├── FriendlyNPC (scripts/npc/friendly_npc.gd) - Non-hostile NPCs
    │   └── DatabaseNPC (scripts/npc/database_npc.gd) - DB-driven friendly NPCs
```

### Core Files

| File | Class | Lines | Purpose |
|------|-------|-------|---------|
| `scripts/npc/base_character.gd` | BaseCharacter | ~200 | Physics, animation, movement base |
| `scripts/npc/enemy_npc.gd` | EnemyNPC | ~900 | Hostile NPC with combat, loot, AI |
| `scripts/npc/enemy_behavior.gd` | EnemyBehavior | ~406 | Movement and chase AI |
| `scripts/npc/enemy_ability_controller.gd` | EnemyAbilityController | ~395 | Ability selection brain |
| `scripts/npc/ability_executor.gd` | AbilityExecutor | ~660 | Ability execution with timing |

### EnemyNPC Composition

```
EnemyNPC (CharacterBody2D)
├── EnemyBehavior (Node) - Movement/chase AI
│   └── Signals: target_acquired, target_lost, attack_performed
├── EnemyAbilityController (Node) - Ability selection
│   └── AbilityExecutor (Node) - Execution timing
├── StatusEffectComponent (Node) - DoT/HoT/buffs
├── ShieldComponent (Node) - Damage absorption
├── Hitbox (Area2D) - Deals damage
├── Hurtbox (Area2D) - Receives damage
└── HealthBar (Node2D) - UI display
```

### Enemy Types Implemented

| Type | Database ID | Variants |
|------|-------------|----------|
| Zombie | `ene_zombie_basic` | basic, bloated |
| Skeleton | `ene_skeleton_basic` | basic, archer, warrior |
| Goblin | `ene_goblin_basic` | basic, shaman, brute |

---

## II. Database/Data System

### Database Architecture

```
Excel (TesiaDatabase.xlsm)
    ↓ VBA Export (MasterExport.bas)
JSON Files (databases/exports/*.json)
    ↓ DatabaseLoader.gd
Runtime Dictionaries + Data Classes
```

### Database Files (29 total)

**Combat-Related:**
- `enemies.json` - Enemy definitions (88 lines)
- `enemy_abilities.json` - Ability definitions (188 lines)
- `behavior_profiles.json` - AI behavior patterns (95 lines)
- `status_effects.json` - Buffs/debuffs (45 lines)
- `loot_tables.json` - Drop tables (122 lines)

**World/Spawning:**
- `spawn_points.json` - Spawn presets (83 lines)
- `zones.json` - Game zones (59 lines)
- `chests.json` - Containers (283 lines)

### Data Schema - Enemies

```json
{
  "id": "ene_zombie_basic",
  "name": "Zombie",
  "type": "Normal|Miniboss|Boss",
  "base_health": 30,
  "base_damage": 5,
  "armor": 0,
  "base_shield": 0,
  "move_speed": 80,
  "attack_speed": 0.8,
  "attack_range": 25,
  "detection_range": 120,
  "xp_reward": 15,
  "loot_table_id": "loot_zombie",
  "ability_ids": "abl_zombie_bite,abl_zombie_slam",
  "behavior_profile": "bhv_zombie_shamble"
}
```

### Data Schema - Abilities

```json
{
  "id": "abl_zombie_bite",
  "name": "Zombie Bite",
  "type": "melee|dash_attack|aoe|projectile|pattern|teleport_attack|beam",
  "damage_mult": 1.0,
  "damage_type": "physical|fire|cold|lightning|poison|arcane|bleed|pure",
  "cooldown": 2,
  "range_min": 0,
  "range_max": 25,
  "shape": "circle|cone|line|cross|ring",
  "shape_size": 20,
  "windup": 0.4,
  "recovery": 0.5,
  "priority": 1,
  "conditions": "distance>50;health<50%",
  "effects_on_hit": "rot:3:3"
}
```

### Data Schema - Behavior Profiles

```json
{
  "id": "bhv_zombie_shamble",
  "idle_behavior": "stand|roam|patrol",
  "detection_range": 120,
  "aggro_on_damage": true,
  "leash_range": 400,
  "combat_style": "aggressive|ranged|opportunist|hit_run",
  "approach_behavior": "direct|charge|kite|phase|circle",
  "preferred_range": 20,
  "ability_priority_mode": "highest|conditional|random_weighted"
}
```

### Runtime Data Classes

| File | Class | Purpose |
|------|-------|---------|
| `scripts/data/ability_data.gd` | AbilityData | Enemy ability with parsing |
| `scripts/data/behavior_profile_data.gd` | BehaviorProfileData | AI behavior config |
| `scripts/data/combat_types.gd` | CombatTypes | Shared damage type enums |

---

## III. Combat & Ability System

### Damage Flow

```
EnemyAbilityController.try_attack(target)
  → _select_ability(target)  [range, cooldown, conditions]
  → AbilityExecutor.execute_ability(ability, target)
    → WINDUP phase (ability.windup)
    → EXECUTE phase
      → HitboxSpawner.spawn_hitbox(shape, size)
      → hit_detected signal for each target
      → _apply_damage_to_target()
        → DamageCalculator.calculate_enemy_ability_damage()
        → target.take_damage(damage)
        → _apply_effects_to_target()
    → RECOVERY phase (ability.recovery)
    → Set cooldown
```

### Damage Calculation

**Location:** `autoloads/damage_calculator.gd` (365 lines)

**Formula:**
```
base_damage × ability.damage_mult
→ Apply armor: damage × (1 - armor / (armor + k × level))
→ Apply AOE falloff (if applicable)
```

### Cooldown System

**Storage:** `AbilityExecutor.ability_cooldowns` Dictionary
**Update:** Every frame in `_update_cooldowns(delta)`
**Check:** `is_on_cooldown(ability)` before use

### Status Effect System

**Component:** `scripts/combat/status_effect_component.gd` (366 lines)

**Effect Types:**
- `debuff_dot` - Damage over time (burn, poison, bleed, rot)
- `buff_hot` - Heal over time
- `buff_stat` / `debuff_stat` - Temporary stat modifiers

**Application Chain:**
```
AbilityData.effects_on_hit → get_parsed_effects()
  → _apply_effects_to_target()
    → match effect.type:
      "stun" → apply_stun(duration)
      "burn" → apply_dot("burn", duration, damage)
      "slow" → apply_slow(duration, percent)
```

---

## IV. Movement & AI Logic

### Current AI System: EnemyBehavior

**Design Philosophy:**
- Evaluate every frame (no intervals)
- Simple priority: Chase when far, Attack when close
- Instant target reactions
- Minimal states

**States:**
```gdscript
enum State { IDLE, ROAMING, COMBAT, RETURNING, DEAD }
```

**Main Loop:**
```gdscript
func _update_behavior(delta):
    if no target:
        _try_acquire_target()
        if still no target: _do_idle(delta)
        return

    # Check leash
    if distance_from_home > leash_radius:
        _lose_target()
        _do_return_home()
        return

    # Combat decision
    if distance_to_target <= attack_radius:
        _do_attack()
    else:
        _do_chase()
```

### Target Detection

**Methods:**
1. **Sight-based:** Distance check against `detection_radius`
2. **Damage-based:** `on_hit(attacker)` triggers aggro

### Movement Control

**BaseCharacter physics:**
```gdscript
if is_locked:
    velocity → friction (can't move during animations)
elif move_direction != ZERO:
    target_velocity = move_direction.normalized() * move_speed
    velocity.move_toward(target_velocity, acceleration * delta)
else:
    velocity.move_toward(ZERO, friction * delta)
```

### Deprecated: AIStateMachine

**Location:** `scripts/npc/ai_state_machine.gd`
**Status:** DEPRECATED - replaced by EnemyBehavior
**States:** IDLE, PATROL, AGGRO, CHASE, ATTACK, FLEE, KITE, BLOCK, STUNNED, DEAD

---

## V. Spawn System

### EnemySpawnPoint (Current)

**Location:** `scripts/npc/spawn_point.gd` (687 lines)

**Features:**
- Weighted enemy pools
- Database preset loading
- Quest condition checking
- Cross-zone persistence
- Respawn control

**Configuration:**
```gdscript
@export var enemy_id: String = ""
@export var enemy_pool: Array[Dictionary] = []
@export var min_level: int = 1
@export var max_level: int = 5
@export var check_interval: float = 10.0
@export var spawn_chance: float = 1.0
@export var max_active_enemies: int = 1
@export var can_respawn: bool = true
@export var respawn_time: float = 300.0
```

### Legacy: EnemySpawner

**Location:** `scripts/npc/enemy_spawner.gd`
**Status:** Legacy, still functional
**Use case:** Wave-based spawning

---

## VI. Existing Modularity Patterns

### 1. Component Pattern (Node-attached)

**Used by:** ShieldComponent, StatusEffectComponent

```gdscript
# Component is self-contained Node
extends Node
class_name ShieldComponent

func setup(shield_amount: float) -> void:
    max_shield = shield_amount
```

**Communication:** Signals + direct method calls

### 2. Signal/Event System

**Usage:** 381+ `.emit()` and `.connect()` calls

**Patterns:**
```gdscript
# Auto-emit on property change
var current_health: float:
    set(value):
        current_health = clampf(value, 0.0, max_health)
        health_changed.emit(current_health, max_health)

# Explicit signal definition
signal effect_applied(effect_type: String, duration: float)
```

### 3. Duck Typing (has_method checks)

```gdscript
if target.has_method("take_damage"):
    target.take_damage(damage)

if _owner.has_method("perform_attack"):
    _owner.perform_attack()
```

### 4. Singleton/Autoload Managers

**Count:** 17 autoload managers

**Key Managers:**
- `GameManager` - Game state
- `PlayerStats` - Player attributes
- `DatabaseLoader` - All game data
- `NPCManager` - NPC registry
- `Persistence` - Session state

### 5. Data-Driven Architecture

**Resource classes extend Resource:**
```gdscript
extends Resource
class_name AbilityData

@export var id: String = ""
@export var damage_mult: float = 1.0
```

**Loaded from JSON, used to drive behavior.**

### 6. Group/Tag System

```gdscript
add_to_group("saveable")
if area.is_in_group("player_attack"):
    take_damage(amount)
```

---

## VII. Strengths & Weaknesses

### Strengths

| Strength | Evidence | Benefit for Modular AI |
|----------|----------|------------------------|
| Database-driven | 29 JSON files, DatabaseLoader | Modules can load config from DB |
| Component pattern | ShieldComponent, StatusEffect | Pattern already proven |
| Signal-based comm | 381+ signals | Loose coupling ready |
| Separation of concerns | EnemyBehavior vs AbilityExecutor | Clear module boundaries |
| Data classes | AbilityData, BehaviorProfileData | Typed configs available |
| Factory methods | DatabaseLoader.create_enemy() | Standardized creation |

### Weaknesses

| Weakness | Evidence | Impact on Modular AI |
|----------|----------|---------------------|
| No shared context | Each system tracks own state | Need to create EnemyContext |
| Direct coupling | EnemyNPC directly creates components | Need abstraction layer |
| No module registry | Components hardcoded in _ready() | Need dynamic module loading |
| Limited pack behavior | Only spawner groups enemies | Pack modules needed |
| Mixed responsibilities | EnemyNPC has 900 lines | Needs decomposition |

---

## VIII. File Manifest

### Core Enemy Files
```
scripts/npc/
├── base_character.gd      (BaseCharacter - physics base)
├── enemy_npc.gd           (EnemyNPC - hostile NPCs)
├── friendly_npc.gd        (FriendlyNPC - non-hostile)
├── database_npc.gd        (DatabaseNPC - DB-driven friendly)
├── enemy_behavior.gd      (EnemyBehavior - movement AI)
├── enemy_ability_controller.gd (Ability selection)
├── ability_executor.gd    (Ability execution timing)
├── hitbox_spawner.gd      (Hitbox creation)
├── spawn_point.gd         (EnemySpawnPoint)
├── enemy_spawner.gd       (Legacy spawner)
├── enemy_presets.gd       (Factory fallbacks)
└── ai_state_machine.gd    (DEPRECATED)
```

### Data Files
```
scripts/data/
├── ability_data.gd        (AbilityData resource)
├── behavior_profile_data.gd (BehaviorProfileData resource)
├── combat_types.gd        (Shared damage enums)
├── talent_data.gd         (Player skills)
└── equipment_data.gd      (Items)
```

### Combat Files
```
scripts/combat/
├── status_effect_component.gd (DoT/HoT/buffs)
├── shield_component.gd    (Damage absorption)
└── movement_action.gd     (Lunge/dash/knockback)
```

### Autoloads
```
autoloads/
├── database_loader.gd     (All game data)
├── damage_calculator.gd   (Damage formulas)
├── npc_manager.gd         (NPC registry)
├── player_stats.gd        (Player state)
├── persistence.gd         (Save state)
└── game_manager.gd        (Game state)
```

---

## IX. Conclusion

The MobileTestia codebase is **well-prepared** for modular AI migration:

1. **Database infrastructure** already handles enemy configs, abilities, and behaviors
2. **Component pattern** is proven with StatusEffectComponent and ShieldComponent
3. **Signal-based communication** provides loose coupling foundation
4. **Separation of concerns** between EnemyBehavior (movement) and AbilityExecutor (combat)
5. **Resource-based data classes** can be extended for module configs

**Primary gaps to address:**
- Create shared EnemyContext for module communication
- Build module loader/orchestrator
- Add module database schema
- Design pack/social behavior modules

The architecture supports an **incremental migration** strategy where new modular enemies can coexist with legacy enemies during transition.
