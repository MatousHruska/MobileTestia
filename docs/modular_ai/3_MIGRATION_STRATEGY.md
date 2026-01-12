# Migration Strategy
## Phased Implementation Plan for Modular AI System

---

## Overview

This document outlines a **5-phase migration strategy** from the current EnemyBehavior/EnemyAbilityController architecture to a fully modular AI system. Each phase is designed to be:

- **Non-breaking:** Old system continues to work
- **Incremental:** Small, testable changes
- **Reversible:** Can roll back if issues arise
- **Validated:** Success criteria before proceeding

---

## Phase 0: Foundation (No Breaking Changes)

### Objectives
- Create module infrastructure without modifying existing enemies
- Establish patterns and conventions
- Build tooling for development

### Steps

1. **Create EnemyContext class**
   ```
   scripts/npc/ai/enemy_context.gd
   ```
   - Shared data structure for module communication
   - All fields documented
   - Serialization for debugging

2. **Create BaseModule class**
   ```
   scripts/npc/ai/base_module.gd
   ```
   - Abstract base with `_process_module(context, delta)` method
   - Configuration loading from database
   - Enable/disable functionality

3. **Create ModuleController class**
   ```
   scripts/npc/ai/module_controller.gd
   ```
   - Loads modules from database config
   - Manages module lifecycle
   - Orchestrates execution order
   - Updates shared context

4. **Add database schema**
   ```
   databases/exports/enemy_modules.json
   databases/exports/enemy_module_configs.json
   databases/vba/EnemyModuleDatabase.bas
   ```
   - Define module metadata
   - Default configurations
   - Validation rules

5. **Create module directory structure**
   ```
   scripts/npc/ai/
   ├── enemy_context.gd
   ├── base_module.gd
   ├── module_controller.gd
   └── modules/
       └── (empty - populated in Phase 2)
   ```

### Success Criteria
- [ ] EnemyContext can store all data needed by current EnemyBehavior
- [ ] BaseModule can be extended
- [ ] ModuleController can load dummy modules
- [ ] Database schema accepted by MasterExport
- [ ] No changes to existing EnemyNPC

### Risks
| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Context design misses fields | Medium | Review all EnemyBehavior/AbilityController state |
| Module interface too rigid | Low | Keep it minimal, extend later |

### Rollback Plan
- Delete new files
- No existing code modified

---

## Phase 1: Simple Enemy Conversion

### Objectives
- Convert ONE simple enemy to modular system
- Prove the concept works
- Behavior must be identical to legacy

### Steps

1. **Choose target enemy:** `ene_zombie_basic`
   - Simplest behavior: roam/chase/attack
   - No special abilities
   - Well-tested baseline

2. **Create test modules:**
   ```
   scripts/npc/ai/modules/
   ├── detection_module.gd    # Target acquisition
   ├── chase_module.gd        # Move toward target
   └── basic_attack_module.gd # Trigger attack when in range
   ```

3. **Add module config to zombie:**
   ```json
   {
     "id": "ene_zombie_basic_modular",
     "module_ids": "mod_detection,mod_chase,mod_basic_attack"
   }
   ```

4. **Create modular EnemyNPC variant:**
   ```
   scripts/npc/modular_enemy_npc.gd
   ```
   - Extends EnemyNPC
   - Uses ModuleController instead of EnemyBehavior
   - Falls back to legacy if no modules configured

5. **Side-by-side testing:**
   - Spawn legacy zombie and modular zombie
   - Compare behavior frame-by-frame
   - Validate identical outcomes

### Success Criteria
- [ ] Modular zombie detects player at same distance
- [ ] Modular zombie chases at same speed
- [ ] Modular zombie attacks at same range
- [ ] Modular zombie returns home correctly
- [ ] No performance regression (profile both)

### Risks
| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Behavior differs subtly | High | Extensive logging, frame comparison |
| Performance worse | Medium | Profile early, optimize hot paths |
| Module communication issues | Medium | Add debug visualization |

### Rollback Plan
- Keep legacy zombie as default
- Modular zombie is a separate entry
- Delete modular files if needed

---

## Phase 2: Core Module Library

### Objectives
- Build reusable module library
- Convert multiple enemy types
- Establish module patterns

### Steps

1. **Extract core modules from EnemyBehavior:**
   ```
   modules/
   ├── detection/
   │   ├── sight_detection_module.gd
   │   └── damage_aggro_module.gd
   ├── movement/
   │   ├── chase_module.gd
   │   ├── roam_module.gd
   │   ├── return_home_module.gd
   │   └── patrol_module.gd
   ├── combat/
   │   ├── melee_attack_module.gd
   │   ├── ability_combat_module.gd
   │   └── ranged_attack_module.gd
   └── utility/
       ├── leash_module.gd
       └── facing_module.gd
   ```

2. **Database entries for each module:**
   ```json
   [
     {"id": "mod_sight_detection", "type": "detection", "priority": 100},
     {"id": "mod_chase", "type": "movement", "priority": 80},
     {"id": "mod_melee_attack", "type": "combat", "priority": 60}
   ]
   ```

3. **Convert additional enemies:**
   - `ene_skeleton_basic` (fast, low health)
   - `ene_goblin_basic` (fast roamer)
   - Validate all behave correctly

4. **Create module composition presets:**
   ```json
   {
     "preset_melee_aggressive": ["mod_sight_detection", "mod_chase", "mod_melee_attack"],
     "preset_roamer_melee": ["mod_sight_detection", "mod_roam", "mod_chase", "mod_melee_attack"]
   }
   ```

5. **Add module debug overlay:**
   - Show active modules
   - Show context state
   - Show module decisions

### Success Criteria
- [ ] 3+ enemy types use modular system
- [ ] Modules are reusable across enemies
- [ ] Module presets simplify configuration
- [ ] Debug tools functional
- [ ] All tests pass

### Risks
| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Module granularity wrong | Medium | Start coarse, split later |
| Context pollution (too many fields) | Medium | Group related fields |
| Module dependencies complex | Low | Avoid direct module coupling |

### Rollback Plan
- Legacy enemies remain functional
- Can mix legacy and modular
- Modules can be removed individually

---

## Phase 3: Complex Behaviors

### Objectives
- Tackle advanced AI patterns
- Add pack/social behavior
- Convert special enemies

### Steps

1. **Create advanced modules:**
   ```
   modules/
   ├── combat/
   │   ├── kite_module.gd
   │   ├── flee_module.gd
   │   └── ability_combo_module.gd
   ├── social/
   │   ├── pack_alert_module.gd
   │   ├── pack_formation_module.gd
   │   └── ally_awareness_module.gd
   ├── special/
   │   ├── teleport_module.gd
   │   ├── summon_module.gd
   │   └── phase_transition_module.gd
   ```

2. **Implement pack behavior:**
   - PackAlertModule: When one enemy aggros, alert nearby allies
   - PackFormationModule: Maintain spacing from allies
   - AllyAwarenessModule: Track nearby allied enemies

3. **Convert complex enemies:**
   - `ene_skeleton_archer` (ranged, kiting)
   - `ene_goblin_shaman` (spellcaster, summons)
   - Boss enemies with phase transitions

4. **Extend context for social behavior:**
   ```gdscript
   # EnemyContext additions
   var nearby_allies: Array[EnemyNPC] = []
   var pack_target: Node2D = null
   var pack_alert_received: bool = false
   var formation_position: Vector2 = Vector2.ZERO
   ```

5. **Module priority system:**
   - High priority: Flee (if health critical)
   - Medium priority: Combat
   - Low priority: Social/formation

### Success Criteria
- [ ] Pack enemies alert each other
- [ ] Ranged enemies kite correctly
- [ ] Boss phase transitions work
- [ ] Module priorities respected
- [ ] No deadlocks or conflicts

### Risks
| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Pack behavior causes lag | Medium | Limit ally checks, spatial partitioning |
| Module conflicts | High | Clear priority system, debug tools |
| Context bloat | Medium | Namespace context fields |

### Rollback Plan
- Complex modules are optional
- Legacy system handles any enemy
- Can disable social modules

---

## Phase 4: Full Migration

### Objectives
- Convert all remaining enemies
- Remove legacy code
- Optimize and polish

### Steps

1. **Convert remaining enemies:**
   - Create checklist of all enemies
   - Convert each with validation
   - Track any requiring special handling

2. **Deprecate legacy systems:**
   ```gdscript
   # In EnemyBehavior
   @deprecated("Use ModularEnemyNPC with modules")
   class_name EnemyBehavior
   ```

3. **Update EnemyNPC to modular-first:**
   ```gdscript
   func _setup_ai() -> void:
       if _has_module_config():
           _setup_modules()
       else:
           push_warning("Enemy %s using legacy behavior" % enemy_id)
           _setup_legacy_behavior()
   ```

4. **Remove dead code:**
   - Delete EnemyBehavior (after full migration)
   - Delete AIStateMachine (already deprecated)
   - Clean up EnemyNPC

5. **Performance optimization:**
   - Profile module execution
   - Batch context updates
   - Optimize hot paths

6. **Documentation:**
   - Module creation guide
   - Context field reference
   - Migration examples

### Success Criteria
- [ ] 100% enemies use modular system
- [ ] Legacy code removed
- [ ] Performance equal or better
- [ ] Documentation complete
- [ ] No regressions

### Risks
| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Edge cases missed | High | Extensive playtesting |
| Performance regression | Medium | Profile before/after |
| Breaking save compatibility | Low | Handle missing modules gracefully |

### Rollback Plan
- Git history preserves legacy code
- Can revert specific enemies
- Save system handles gracefully

---

## Timeline Overview

```
Phase 0: Foundation        [2-3 days]
    └─> Phase 1: Simple Conversion  [3-5 days]
            └─> Phase 2: Core Modules  [1-2 weeks]
                    └─> Phase 3: Complex Behaviors  [1-2 weeks]
                            └─> Phase 4: Full Migration  [1 week]
```

**Total Estimated Time:** 4-6 weeks

---

## Migration Checklist

### Phase 0 Deliverables
- [ ] `enemy_context.gd` created
- [ ] `base_module.gd` created
- [ ] `module_controller.gd` created
- [ ] `enemy_modules.json` schema defined
- [ ] `EnemyModuleDatabase.bas` created
- [ ] Unit tests for context/controller

### Phase 1 Deliverables
- [ ] `detection_module.gd` working
- [ ] `chase_module.gd` working
- [ ] `basic_attack_module.gd` working
- [ ] `modular_enemy_npc.gd` created
- [ ] Zombie side-by-side test passing

### Phase 2 Deliverables
- [ ] 10+ modules created
- [ ] 3+ enemy types converted
- [ ] Module presets defined
- [ ] Debug overlay functional
- [ ] All tests passing

### Phase 3 Deliverables
- [ ] Pack behavior modules working
- [ ] Kite/flee modules working
- [ ] Boss transitions working
- [ ] Complex enemies converted
- [ ] Priority system validated

### Phase 4 Deliverables
- [ ] 100% enemy coverage
- [ ] Legacy code removed
- [ ] Performance validated
- [ ] Documentation complete
- [ ] Release ready

---

## Go/No-Go Criteria

### Before Phase 1
- Context covers all EnemyBehavior state
- Module interface finalized
- Database schema approved

### Before Phase 2
- Zombie behavior identical
- No performance regression
- Debug tools working

### Before Phase 3
- Core modules stable
- Multiple enemies working
- Team familiar with system

### Before Phase 4
- All complex behaviors working
- Pack behavior tested
- No blocking issues

---

## Communication Plan

1. **Phase Start:** Brief stakeholders on objectives
2. **Daily:** Log progress in commit messages
3. **Phase End:** Demo + retrospective
4. **Blockers:** Escalate immediately

This migration strategy ensures a smooth transition while maintaining system stability throughout the process.
