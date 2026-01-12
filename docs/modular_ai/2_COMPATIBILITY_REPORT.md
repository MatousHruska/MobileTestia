# Compatibility Report
## System-by-System Analysis for Modular AI Integration

---

## Database System Compatibility

### Current Structure

```
Excel Workbook (TesiaDatabase.xlsm)
    ↓ VBA Macros (.bas files)
JSON Files (29 databases)
    ↓ DatabaseLoader.gd
Runtime Access (Dictionary + Array per database)
```

**Key Characteristics:**
- Flat JSON arrays with `id` field for keying
- String-based references between entities (`ability_ids`, `behavior_profile`)
- Factory methods for creating runtime objects (AbilityData, BehaviorProfileData)

### Strengths

| Strength | How It Helps |
|----------|--------------|
| ID-based linking | Modules can reference abilities/effects by ID |
| Factory pattern | `create_ability_data()` can be extended for modules |
| String parsing | `parse_stat_string()`, `parse_enemy_pool()` already exist |
| Extensible schema | New fields can be added without breaking existing data |

### Limitations

| Limitation | Impact | Solution |
|------------|--------|----------|
| No module definitions | Can't define modules in DB yet | Add `enemy_modules.json` |
| No module configs | No per-enemy module parameters | Add `enemy_module_configs.json` |
| Flat structure | No nested module hierarchies | Use comma-separated module IDs |
| No priority field for modules | Can't order module execution | Add `priority` field |

### Required Changes

**New Database Files:**
```
databases/exports/
├── enemy_modules.json          # Module definitions
├── enemy_module_configs.json   # Per-enemy module overrides
```

**New VBA Modules:**
```
databases/vba/
├── EnemyModuleDatabase.bas     # Module validation/export
├── ModuleConfigDatabase.bas    # Config validation/export
```

### Database Schema Extensions

**enemy_modules.json:**
```json
{
  "enemy_modules": [
    {
      "id": "mod_target_detection",
      "name": "Target Detection",
      "module_type": "detection",
      "description": "Detects and acquires targets within range",
      "context_reads": "global_position,detection_radius",
      "context_writes": "current_target,nearby_enemies,target_distance",
      "default_config": {
        "detection_radius": 120,
        "aggro_on_damage": true,
        "detection_type": "sight"
      },
      "priority": 100
    }
  ]
}
```

**enemies.json Extension:**
```json
{
  "id": "ene_zombie_basic",
  "name": "Zombie",
  "module_ids": "mod_target_detection,mod_basic_chase,mod_melee_attack",
  "module_config_overrides": "detection_radius:150;chase_speed:0.8"
}
```

### Migration Path

1. **Phase 0:** Add new database files with empty arrays
2. **Phase 1:** Define core modules (detection, movement, attack)
3. **Phase 2:** Add `module_ids` field to existing enemies (optional at first)
4. **Phase 3:** Migrate behavior_profile settings to module configs
5. **Phase 4:** Deprecate behavior_profiles for module-based enemies

### Preservation Strategy

- Keep all existing enemy fields (`ability_ids`, `behavior_profile`)
- New `module_ids` field is OPTIONAL - enemies without it use legacy system
- Both systems coexist during migration

---

## Enemy Class Architecture Compatibility

### Current Inheritance

```
CharacterBody2D
└── BaseCharacter
    └── EnemyNPC (900 lines)
        ├── Components (created in _ready)
        │   ├── EnemyBehavior
        │   ├── EnemyAbilityController
        │   ├── StatusEffectComponent
        │   └── ShieldComponent
        └── Direct Logic (hardcoded)
            ├── Health/damage handling
            ├── Loot dropping
            ├── Level scaling
            └── Visual effects
```

### Hardcoded Behaviors

| Behavior | Location | Lines | Extractable? |
|----------|----------|-------|--------------|
| Health management | `take_damage()`, `_on_death()` | 50+ | Yes → HealthModule |
| Loot dropping | `_drop_loot()`, `_drop_from_loot_table()` | 100+ | Yes → LootModule |
| Status effect visual | `_spawn_burning_visual()` | 20+ | Partially |
| Level scaling | `apply_level_scaling()` | 15 | No (factory concern) |
| Hit detection | `_on_hurtbox_area_entered()` | 20 | Yes → CombatModule |

### Extractable Logic (Can Become Modules)

| Logic | Current Location | New Module |
|-------|------------------|------------|
| Target detection | EnemyBehavior._try_acquire_target() | DetectionModule |
| Chase/movement | EnemyBehavior._do_chase() | MovementModule |
| Attack decision | EnemyAbilityController._select_ability() | CombatModule |
| Ability execution | AbilityExecutor | AbilityModule (wrapper) |
| Status effects | StatusEffectComponent | EffectsModule (wrapper) |
| Idle behavior | EnemyBehavior._do_roam() | IdleBehaviorModule |

### Must Preserve (Stay in EnemyNPC)

| Responsibility | Reason |
|----------------|--------|
| Physics/collision | CharacterBody2D requirement |
| Health bar UI | Tightly coupled to display |
| Death/cleanup | Scene tree management |
| Spawner reference | Persistence integration |
| Core signals | API contract with other systems |

### Refactoring Complexity: **MEDIUM**

**Easy extractions:**
- Detection logic (self-contained)
- Idle behaviors (isolated state machine)
- Basic movement (direction setting)

**Moderate extractions:**
- Combat logic (depends on abilities)
- Status effects (existing component)

**Difficult extractions:**
- Health/damage (many integrations)
- Loot (persistence dependencies)

### Recommended Approach

```
EnemyNPC (Simplified)
├── Core Properties (health, position, refs)
├── ModuleController (new)
│   ├── EnemyContext (shared state)
│   └── Module[] (loaded from DB)
├── Legacy Components (optional, for migration)
│   ├── EnemyBehavior (deprecated path)
│   └── EnemyAbilityController (deprecated path)
└── Essential Logic
    ├── take_damage() (routes to modules)
    ├── die() (triggers module cleanup)
    └── signals (health_changed, died, etc.)
```

---

## Ability & Combat System Compatibility

### Ability Execution Flow

```
Current Flow:
EnemyAbilityController → AbilityExecutor → HitboxSpawner → DamageCalculator

Modular Flow:
CombatModule → reads context.should_attack
            → calls AbilityExecutor (reused!)
            → writes context.attack_completed
```

### Integration Points

| Point | Current | Modular | Change Required |
|-------|---------|---------|-----------------|
| Ability selection | EnemyAbilityController | CombatModule.select_ability() | Wrap existing logic |
| Ability execution | AbilityExecutor | AbilityExecutor (reused) | None |
| Cooldown tracking | AbilityExecutor | AbilityExecutor (reused) | None |
| Damage calculation | DamageCalculator | DamageCalculator (reused) | None |
| Effect application | AbilityExecutor | EffectsModule | Route through context |

### Cooldown System

**Current:** `AbilityExecutor.ability_cooldowns: Dictionary`

**Compatibility:** ✅ Excellent
- Cooldowns are per-ability, not per-module
- AbilityExecutor can be reused directly by CombatModule
- No changes needed to cooldown logic

### Buff/Debuff System

**Current:** `StatusEffectComponent` with `_active_effects` Dictionary

**Compatibility:** ✅ Good
- Already a component (can be wrapped by module)
- Signals for effect_applied, effect_removed, effect_tick
- Module just needs to read/write context flags

### Required Adaptations

1. **CombatModule wraps AbilityController:**
   ```gdscript
   func _process_module(context: EnemyContext) -> void:
       if context.should_attack and not context.attack_in_progress:
           var success = _ability_controller.try_attack(context.current_target)
           context.attack_in_progress = success
   ```

2. **Context reads from existing systems:**
   ```gdscript
   context.has_active_buff = status_effects.has_buff("shield")
   context.is_on_cooldown = ability_executor.is_busy()
   ```

---

## AI & Movement System Compatibility

### Current Decision-Making

```
EnemyBehavior._update_behavior(delta):
    if no target → _do_idle(delta)
    if beyond leash → _do_return_home()
    if in attack range → _do_attack()
    else → _do_chase()
```

### State Management

**Current:** Simple enum in EnemyBehavior
```gdscript
enum State { IDLE, ROAMING, COMBAT, RETURNING, DEAD }
```

**Modular Equivalent:** Context flags
```gdscript
context.has_target = true
context.is_in_attack_range = true
context.is_beyond_leash = false
```

### Movement Control

**Current:** `_owner.set_move_direction(direction)`

**Modular:** Same! Context writes desired_direction, EnemyNPC reads it
```gdscript
# MovementModule writes:
context.desired_direction = direction_to_target

# EnemyNPC reads:
set_move_direction(context.desired_direction)
```

### Reusable Components

| Component | Reuse Strategy |
|-----------|----------------|
| EnemyBehavior._do_chase() | Extract to ChaseModule |
| EnemyBehavior._do_roam() | Extract to RoamModule |
| EnemyBehavior._try_acquire_target() | Extract to DetectionModule |
| AbilityData cardinal alignment | Keep as static utility |

### New Requirements

| Feature | Current Status | Module Needed |
|---------|----------------|---------------|
| Pack coordination | Not implemented | PackBehaviorModule |
| Formation movement | Not implemented | FormationModule |
| Flee behavior | In legacy AIStateMachine | FleeModule |
| Kiting | In legacy AIStateMachine | KiteModule |

---

## Summary Matrix

| System | Compatibility | Effort | Strategy |
|--------|---------------|--------|----------|
| Database | ✅ High | Low | Add new tables, extend existing |
| Enemy Classes | 🟡 Medium | Medium | Wrapper pattern, incremental extraction |
| Ability System | ✅ High | Low | Reuse AbilityExecutor, wrap controller |
| Combat/Damage | ✅ High | Low | Reuse DamageCalculator |
| Status Effects | ✅ High | Low | Wrap StatusEffectComponent |
| Movement | ✅ High | Low | Write to context, read in EnemyNPC |
| AI Decision | 🟡 Medium | Medium | Extract to modules, deprecate behavior |
| Spawn System | ✅ High | Low | No changes needed |

### Overall Compatibility Score: **85%**

The codebase is well-suited for modular migration with minimal breaking changes required.
