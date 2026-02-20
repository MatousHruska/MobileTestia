# Phase 5: Phalanx Stance & Father's Last Lesson — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the Noble Legacy talent tree by implementing the toggle ability system (Phalanx Stance) and ultimate ability (Father's Last Lesson).

**Architecture:** Two independent features that share integration points in PlayerStats and CombatHUD. Phalanx Stance adds a new toggle state to PlayerController with per-frame stamina drain and damage reduction. Father's Last Lesson adds a timed ultimate buff in TalentProcSystem with guaranteed crits, free stamina, and AOE slow.

**Tech Stack:** Godot 4 / GDScript, Excel VBA database pipeline

---

### Task 1: Add toggle_stance visual template

**Files:**
- Modify: `scripts/combat/ability_visual_templates.gd:27-41` (get_all dictionary)
- Modify: `scripts/combat/ability_visual_templates.gd` (add new static function after _parry_stance at line ~227)

**Step 1: Register template in get_all()**

In `scripts/combat/ability_visual_templates.gd`, add `"toggle_stance"` to the `get_all()` dictionary (line 39, after `"parry_stance"`):

```gdscript
		"parry_stance": _parry_stance(),
		"toggle_stance": _toggle_stance(),
		"howl": _howl(),
```

**Step 2: Add the template function**

After `_parry_stance()` (line ~227), add:

```gdscript
## toggle_stance - Toggle defensive stance (Phalanx Stance)
## Shows weapon in guard position and holds indefinitely until deactivated.
## Unlike parry_stance, this does NOT auto-finish — PlayerController manages the state.
static func _toggle_stance() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "toggle_stance"
	data.display_name = "Toggle Stance"
	data.locks_movement = false  # Player can walk (but not sprint/dodge)

	data.phases = [
		# Phase 0: Show weapon (guard position)
		AbilityVisualPhase.create_weapon_visibility(true),
		# Phase 1: Enter defensive pose
		AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Hold indefinitely (PlayerController will cancel this)
		AbilityVisualPhase.create_wait(999.0, "stance_hold"),
		# Phase 3: Hide weapon on deactivation
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 4: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data
```

**Step 3: Add toggle_stance to VBA valid visual types**

In `databases/vba/SkillDatabase.bas`, find the `validVisualTypes` line (search for `validVisualTypes = Split`) and add `toggle_stance`:

```vba
validVisualTypes = Split("melee_single,melee_combo_2,melee_combo_3,dash_attack,ranged_aim,ranged_attack,spell_cast,spell_instant,throw,self_buff,howl,parry_stance,toggle_stance", ",")
```

**Step 4: Commit**

```
feat: add toggle_stance visual template for Phalanx Stance
```

---

### Task 2: Add stance state to PlayerController

**Files:**
- Modify: `scripts/player/player_controller.gd:34-41` (state vars)
- Modify: `scripts/player/player_controller.gd:291` (_process_timers)
- Modify: `scripts/player/player_controller.gd:373` (request_dodge)

**Step 1: Add stance state variables**

After `is_casting` (line 40), add:

```gdscript
var is_stance_active: bool = false  ## Currently in toggle stance (Phalanx Stance)
```

Add internal state after `_cast_interrupt_on_damage` (line 71):

```gdscript
## Stance state (Phalanx Stance toggle)
var _stance_talent: TalentData = null
var _stance_stamina_drain: float = 5.0  ## Stamina drained per second while in stance
```

**Step 2: Add stance signals**

After `cast_interrupted` signal (line 15), add:

```gdscript
signal stance_activated(talent_id: String)
signal stance_deactivated(talent_id: String)
```

**Step 3: Add activate/deactivate methods**

After the `apply_recovery_lockout` method (around line 418), add:

```gdscript
#===============================================================================
# TOGGLE STANCE (Phalanx Stance)
#===============================================================================

func activate_stance(talent: TalentData) -> void:
	## Enter toggle stance mode
	if is_stance_active:
		return
	is_stance_active = true
	_stance_talent = talent
	stance_activated.emit(talent.id)
	Debug.log("Combat", "Stance activated: %s" % talent.talent_name)


func deactivate_stance() -> void:
	## Exit toggle stance mode
	if not is_stance_active:
		return
	is_stance_active = false
	var talent_id := _stance_talent.id if _stance_talent else ""
	_stance_talent = null

	# Cancel the visual sequence so weapon hides and idle resumes
	if ability_visual_player and ability_visual_player.is_playing:
		ability_visual_player.cancel()

	stance_deactivated.emit(talent_id)
	Debug.log("Combat", "Stance deactivated")
```

**Step 4: Add stamina drain in _process_timers**

In `_process_timers(delta)` (line 291), add at the end of the function:

```gdscript
	# Drain stamina while in toggle stance
	if is_stance_active:
		var drain := _stance_stamina_drain * delta
		if PlayerStats.current_stamina <= drain:
			# Not enough stamina — auto-deactivate
			PlayerStats.current_stamina = 0.0
			deactivate_stance()
		else:
			PlayerStats.current_stamina -= drain
```

**Step 5: Block dodge during stance**

In `request_dodge()` (line 373), add at the very top:

```gdscript
	if is_stance_active:
		return
```

**Step 6: Reset stance in load_save_data and on death**

In the existing save/load methods (search for `load_save_data` or the death handler), ensure stance is reset. Also add to `_on_visual_sequence_finished`:

No changes needed for sequence_finished since we cancel the sequence on deactivate. But ensure stance is cleared on death — add to any existing death/reset handler.

**Step 7: Commit**

```
feat: add toggle stance state to PlayerController with stamina drain
```

---

### Task 3: Add stance damage reduction to PlayerStats

**Files:**
- Modify: `autoloads/player_stats.gd:334-355` (damage function)

**Step 1: Add damage reduction after parry check**

In `PlayerStats.damage()` (line 334), after the parry check block (line 346) and before `current_life -= amount` (line 348), add:

```gdscript
	# Check Phalanx Stance — reduce frontal/side damage by 75%
	if Game.player and Game.player.is_stance_active:
		var stance_arc := 270.0  # Front + sides (not directly behind)
		var reduce := true
		# Check if attack is within stance arc
		if attacker_position != Vector2.INF:
			var player_pos: Vector2 = Game.player.global_position
			var to_attacker := (attacker_position - player_pos).normalized()
			var facing_vec := _get_player_facing_vector()
			var angle := rad_to_deg(facing_vec.angle_to(to_attacker))
			if abs(angle) > stance_arc / 2.0:
				reduce = false  # Attack from directly behind — no reduction
		if reduce:
			amount *= 0.25  # 75% damage reduction
			Debug.log("Combat", "Phalanx Stance reduced damage to %.0f" % amount)
```

**Step 2: Add facing vector helper**

Add a `_get_player_facing_vector()` helper to PlayerStats (at the bottom, before save/load section). This mirrors the one in TalentProcSystem:

```gdscript
func _get_player_facing_vector() -> Vector2:
	if not Game.player:
		return Vector2.DOWN
	match Game.player.current_facing:
		PlayerController.Facing.DOWN: return Vector2.DOWN
		PlayerController.Facing.UP: return Vector2.UP
		PlayerController.Facing.LEFT: return Vector2.LEFT
		PlayerController.Facing.RIGHT: return Vector2.RIGHT
		_: return Vector2.DOWN
```

**Step 3: Commit**

```
feat: add Phalanx Stance 75% damage reduction in PlayerStats
```

---

### Task 4: Add toggle detection to CombatHUD

**Files:**
- Modify: `scripts/ui/combat/combat_hud.gd:669-764` (_on_ability_activated and _activate_skill_via_sequencer)

**Step 1: Add stance tracking variable**

Near the top of the CombatHUD class (with other state vars), add:

```gdscript
## Toggle stance tracking
var _active_stance_slot: int = -1  ## Slot index of currently active toggle stance (-1 = none)
var _active_stance_talent_id: String = ""
```

**Step 2: Add toggle check in _on_ability_activated**

In `_on_ability_activated` (line 669), after getting the talent data (line 673) and before the `is_locked` check (line 679), add:

```gdscript
	# Check if this is a deactivation of an active toggle stance
	if _active_stance_slot >= 0 and ability_id == _active_stance_talent_id:
		_deactivate_active_stance()
		return
```

**Step 3: Add stance activation in _activate_skill_via_sequencer**

In `_activate_skill_via_sequencer` (line 709), after playing the visual sequence (line 749) and the parry_stance check (line 752-753), add:

```gdscript
	# Start toggle stance if this is a toggle ability
	if template_id == "toggle_stance":
		player.activate_stance(talent)
		_active_stance_slot = slot_index
		_active_stance_talent_id = talent.id
```

**Step 4: Add deactivation helper method**

Add near the parry methods:

```gdscript
func _deactivate_active_stance() -> void:
	## Deactivate the currently active toggle stance
	if _active_stance_slot < 0:
		return
	if player:
		player.deactivate_stance()
	_active_stance_slot = -1
	_active_stance_talent_id = ""
```

**Step 5: Connect stance_deactivated signal**

In `_on_player_spawned` (search for it), connect to the player's stance signal:

```gdscript
	if not player.stance_deactivated.is_connected(_on_stance_deactivated):
		player.stance_deactivated.connect(_on_stance_deactivated)
```

Add the handler:

```gdscript
func _on_stance_deactivated(_talent_id: String) -> void:
	## Called when stance auto-deactivates (e.g., ran out of stamina)
	_active_stance_slot = -1
	_active_stance_talent_id = ""
```

**Step 6: Commit**

```
feat: add toggle stance detection in CombatHUD for Phalanx Stance
```

---

### Task 5: Add ultimate system to TalentProcSystem

**Files:**
- Modify: `scripts/combat/talent_proc_system.gd:35-39` (state vars)
- Modify: `scripts/combat/talent_proc_system.gd:84-108` (_process)
- Modify: `scripts/combat/talent_proc_system.gd:546-558` (save/load)

**Step 1: Add ultimate state variables**

After the parry state vars (line 39), add:

```gdscript
## Ultimate ability state (Father's Last Lesson)
var _ultimate_active: bool = false
var _ultimate_timer: float = 0.0
var _ultimate_crit_bonus: float = 1000.0  ## Added to bonus_crit_chance during ultimate
var _ultimate_no_stamina_cost: bool = false
var _ultimate_slow_tick: float = 0.0  ## Timer for periodic AOE slow
const ULTIMATE_SLOW_INTERVAL: float = 1.0  ## Apply slow every 1s
const ULTIMATE_SLOW_RADIUS: float = 200.0  ## Radius for enemy slow
```

**Step 2: Add ultimate methods**

After the parry section (after `_find_attacker_at_position`, around line 531), add:

```gdscript
#===============================================================================
# ULTIMATE ABILITY (Father's Last Lesson)
#===============================================================================

## Activate ultimate buff for the given duration
func activate_ultimate(duration: float) -> void:
	_ultimate_active = true
	_ultimate_timer = duration
	_ultimate_no_stamina_cost = true
	_ultimate_slow_tick = 0.0
	bonus_crit_chance += _ultimate_crit_bonus
	Debug.log("Procs", "ULTIMATE ACTIVATED! (%.1fs) Guaranteed crits, no stamina cost" % duration)


## Check if ultimate is currently active
func is_ultimate_active() -> bool:
	return _ultimate_active


## Check if stamina costs should be waived (during ultimate)
func should_waive_stamina_cost() -> bool:
	return _ultimate_no_stamina_cost


## Deactivate ultimate (called on expiry or forced cancel)
func deactivate_ultimate() -> void:
	if not _ultimate_active:
		return
	_ultimate_active = false
	_ultimate_timer = 0.0
	_ultimate_no_stamina_cost = false
	bonus_crit_chance -= _ultimate_crit_bonus
	if bonus_crit_chance < 0:
		bonus_crit_chance = 0.0
	Debug.log("Procs", "Ultimate expired")
```

**Step 3: Add ultimate processing to _process()**

In `_process(delta)` (line 84), after the parry window timer block (line 105) and before `_update_always_procs()` (line 108), add:

```gdscript
	# Tick ultimate timer
	if _ultimate_active:
		_ultimate_timer -= delta
		if _ultimate_timer <= 0:
			deactivate_ultimate()
		else:
			# Apply AOE slow to nearby enemies periodically
			_ultimate_slow_tick -= delta
			if _ultimate_slow_tick <= 0:
				_ultimate_slow_tick = ULTIMATE_SLOW_INTERVAL
				_apply_ultimate_slow()


func _apply_ultimate_slow() -> void:
	## Apply slow debuff to all enemies within radius during ultimate
	if not Game.player:
		return
	var enemies := NPCManager.get_enemies_in_radius(Game.player.global_position, ULTIMATE_SLOW_RADIUS)
	for enemy in enemies:
		if is_instance_valid(enemy) and "status_effects" in enemy and enemy.status_effects:
			enemy.status_effects.apply_status_effect("status_slow")
```

**Step 4: Reset ultimate state in load_save_data**

In `load_save_data` (line 550), add:

```gdscript
	_ultimate_active = false
	_ultimate_timer = 0.0
	_ultimate_no_stamina_cost = false
	_ultimate_slow_tick = 0.0
```

**Step 5: Commit**

```
feat: add ultimate ability system to TalentProcSystem
```

---

### Task 6: Add stamina cost waiver to PlayerStats

**Files:**
- Modify: `autoloads/player_stats.gd:379-383` (use_stamina)

**Step 1: Add ultimate check to use_stamina**

Modify `use_stamina()` (line 379) to check for ultimate:

```gdscript
func use_stamina(amount: float) -> bool:
	# Ultimate ability waives all stamina costs
	if TalentProcSystem and TalentProcSystem.should_waive_stamina_cost():
		return true
	if current_stamina >= amount:
		current_stamina -= amount
		return true
	return false
```

**Step 2: Commit**

```
feat: waive stamina costs during Father's Last Lesson ultimate
```

---

### Task 7: Wire Father's Last Lesson in CombatHUD

**Files:**
- Modify: `scripts/ui/combat/combat_hud.gd` (_apply_self_buff or _on_visual_damage_event)

**Step 1: Detect Father's Last Lesson activation**

The talent uses `self_buff` effect type, so it flows through the existing self-buff path. Modify `_apply_self_buff` (line 1361) to detect the ultimate:

```gdscript
func _apply_self_buff(talent: TalentData) -> void:
	## Apply the self-buff effect to the player
	print("[CAST] Applying self-buff: %s" % talent.talent_name)

	# Check if this is Father's Last Lesson (ultimate ability)
	if talent.id == "tal_noble_fathers_lesson":
		var duration := talent.duration if talent.duration > 0 else 6.0
		TalentProcSystem.activate_ultimate(duration)
		Debug.log("Combat", "Father's Last Lesson ultimate activated for %.1fs" % duration)
		return

	# Apply status effect from contact_status_effect field
	if not talent.contact_status_effect.is_empty():
		if Game.player and Game.player.status_effect_manager:
			Game.player.status_effect_manager.apply_status_effect(talent.contact_status_effect)
			Debug.log("Combat", "Self-buff applied: %s -> %s" % [talent.talent_name, talent.contact_status_effect])
		else:
			Debug.warn("Combat", "Cannot apply self-buff: no status_effect_manager")
```

**Step 2: Commit**

```
feat: wire Father's Last Lesson ultimate activation in CombatHUD
```

---

### Task 8: Final integration and commit

**Step 1: Verify database values**

Check `databases/exports/talents.json` to confirm `tal_noble_phalanx_stance` has:
- `visual_type: "toggle_stance"` (may need Excel update)
- `stamina_cost: 10`
- `effect_type: "self_buff"`
- `cooldown: 0`

Check `tal_noble_fathers_lesson` has:
- `effect_type: "self_buff"`
- `cooldown: 60`
- `duration: 6`

If the database values need updating, provide TSV paste data for the user.

**Step 2: Full commit**

If separate task commits weren't made, do one combined commit:

```
feat: implement Phase 5 - Phalanx Stance toggle and Father's Last Lesson ultimate

Phalanx Stance (toggle ability):
- Add toggle_stance visual template (hold indefinitely until deactivated)
- Add stance state to PlayerController with 5/sec stamina drain
- Block dodge during active stance
- 75% damage reduction from front/sides (270° arc) in PlayerStats
- CombatHUD detects second press to deactivate

Father's Last Lesson (ultimate):
- Add ultimate timer system to TalentProcSystem
- Guaranteed crits via +1000 bonus_crit_chance
- Waive all stamina costs during 6s duration
- AOE slow applied to nearby enemies every 1s
- Wire activation through existing self_buff path in CombatHUD
```
