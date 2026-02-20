# Phase 5: Complex Mechanics - Phalanx Stance & Father's Last Lesson

## Context

Phase 5 completes the Noble Legacy talent tree. Phases 1-4 implemented: 5-column grid, proc system, 25 talent definitions, Cold Parry with counter-attack, and all passive talent procs. Three talents were deferred to Phase 5:

- **Phalanx Stance** (Row 3, Col 4) - Toggle ability, needs new toggle system
- **Disarming Presence** (Row 4, Col 3) - Already done (stat bonus: dodge_chance:2/pt)
- **Father's Last Lesson** (Row 6, Col 3) - Ultimate ability, needs guaranteed crits + stamina override + AOE slow

## 5A. Phalanx Stance (Toggle Ability)

### Behavior
- Press ability button to enter stance, press again to exit
- While active: 5 stamina/sec drain, 75% damage reduction from front/sides (270 arc), cannot dodge or sprint
- Auto-deactivates when stamina reaches 0
- No cooldown, but has initial stamina cost to activate

### Implementation

**PlayerController changes:**
- Add `is_stance_active: bool`, `_stance_talent: TalentData`
- `activate_stance(talent)` / `deactivate_stance()` methods
- `_process()`: drain stamina while active, auto-deactivate at 0
- `request_dodge()`: return early if stance active

**PlayerStats changes:**
- `damage()`: check stance state, reduce damage by 75% if attack from front/sides (270 arc check using attacker_position, same pattern as parry frontal arc)

**ability_visual_templates.gd:**
- New `toggle_stance` template: show weapon, defensive body anim, hold indefinitely (no auto-finish)

**CombatHUD changes:**
- Detect second press on active stance ability -> call `deactivate_stance()`
- Track which ability is currently in toggle mode

**SkillDatabase.bas:**
- Add `toggle_stance` to valid visual types

### Database Values (already in Excel)
- id: tal_noble_phalanx_stance
- type: active, visual_type: toggle_stance
- stamina_cost: 10 (activation cost), duration: 0 (toggle = infinite)
- effect_type: self_buff

## 5B. Father's Last Lesson (Ultimate)

### Behavior
- Press to activate: play self_buff animation, apply 6s buff
- During buff: guaranteed crits, 0 stamina cost on all abilities, enemies within 200px slowed
- 60s cooldown

### Implementation

**TalentProcSystem changes:**
- Add `is_ultimate_active: bool`, `_ultimate_timer: float`, `_ultimate_no_stamina_cost: bool`
- `activate_ultimate(duration)`: set flags, add 1000 to `bonus_crit_chance`
- `_process()`: tick timer, apply AOE slow every 1s, deactivate on expiry
- `deactivate_ultimate()`: remove crit bonus, clear flags

**PlayerStats changes:**
- `use_stamina()`: if `TalentProcSystem._ultimate_no_stamina_cost`, return true without consuming

**CombatHUD changes:**
- On Father's Last Lesson activation: call `TalentProcSystem.activate_ultimate(6.0)`
- Uses existing `self_buff` template (no new template needed)

### Database Values (already in Excel)
- id: tal_noble_fathers_lesson
- type: active, visual_type: self_buff (or empty for auto)
- cooldown: 60, duration: 6, stamina_cost: 0, mana_cost: 0
- effect_type: self_buff

## Files to Modify

1. `scripts/player/player_controller.gd` - Stance state, stamina drain, dodge block
2. `autoloads/player_stats.gd` - Damage reduction for stance, stamina override for ultimate
3. `scripts/combat/talent_proc_system.gd` - Ultimate timer, slow AOE, no-stamina flag
4. `scripts/combat/ability_visual_templates.gd` - New toggle_stance template
5. `scripts/ui/combat/combat_hud.gd` - Toggle detection, ultimate activation
6. `databases/vba/SkillDatabase.bas` - Add toggle_stance to valid visual types

## Not Needed
- No new database columns
- No VBA schema changes (just visual type list update)
- No DamageCalculator changes (crit works via bonus_crit_chance)
