class_name AbilityVisualTemplates
## AbilityVisualTemplates - Static factory for built-in ability visual templates.
##
## Constructs the standard visual templates in code so abilities can reference
## them by name without needing .tres files during development.
##
## Each template defines the *shape* of the visual sequence. Actual durations
## (windup time, lunge distance, recovery time) come from ability/talent data
## and are applied via the overrides dictionary in AbilityVisualPlayer.play().

const Phase := AbilityVisualPhase
const PhaseType := AbilityVisualPhase.PhaseType


## Returns a dictionary of template_id -> AbilityVisualData.
## These are the standard templates that abilities reference by name.
static func get_all() -> Dictionary:
	return {
		"melee_single": _melee_single(),
		"melee_combo_2": _melee_combo_2(),
		"melee_combo_3": _melee_combo_3(),
		"dash_attack": _dash_attack(),
		"ranged_aim": _ranged_aim(),
		"spell_cast": _spell_cast(),
		"spell_instant": _spell_instant(),
		"throw": _throw(),
		"self_buff": _self_buff(),
	}


## Retrieve a single template by ID. Returns null if not found.
static func get_template(template_id: String) -> AbilityVisualData:
	var all_templates := get_all()
	return all_templates.get(template_id) as AbilityVisualData


#===============================================================================
# MELEE TEMPLATES
#===============================================================================

## melee_single - Standard single melee attack
## Windup -> lunge + strike -> damage -> return to idle
static func _melee_single() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "melee_single"
	data.display_name = "Melee Single"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon
		Phase.create_weapon_visibility(true),
		# Phase 1: Windup animation (wait for anim to finish)
		Phase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Lunge toward target + strike animation (concurrent)
		Phase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
		# Phase 3: Strike animation (runs concurrently with lunge)
		Phase.create_body_anim("melee_strike"),
		# Phase 4: Damage event (instant)
		Phase.create_damage_event(),
		# Phase 5: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
		# Phase 6: Weapon stays visible
		Phase.create_weapon_visibility(true),
	]

	return data


## melee_combo_2 - Two-hit melee combo
static func _melee_combo_2() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "melee_combo_2"
	data.display_name = "Melee Combo (2-hit)"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon
		Phase.create_weapon_visibility(true),
		# Phase 1: Windup
		Phase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Lunge + strike (concurrent)
		Phase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
		Phase.create_body_anim("melee_strike"),
		# Phase 4: First hit damage
		Phase.create_damage_event(),
		# Phase 5: Brief pause between hits
		Phase.create_wait(0.1),
		# Phase 6: Second strike
		Phase.create_body_anim("melee_strike"),
		# Phase 7: Second hit damage
		Phase.create_damage_event(),
		# Phase 8: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


## melee_combo_3 - Three-hit melee combo
static func _melee_combo_3() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "melee_combo_3"
	data.display_name = "Melee Combo (3-hit)"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon
		Phase.create_weapon_visibility(true),
		# Phase 1: Windup
		Phase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Lunge + strike (concurrent)
		Phase.create_movement("toward_target", 20.0, 0.15, "lunge", true),
		Phase.create_body_anim("melee_strike"),
		# Phase 4: First hit damage
		Phase.create_damage_event(),
		# Phase 5: Brief pause
		Phase.create_wait(0.1),
		# Phase 6: Second strike
		Phase.create_body_anim("melee_strike"),
		# Phase 7: Second hit damage
		Phase.create_damage_event(),
		# Phase 8: Brief pause
		Phase.create_wait(0.1),
		# Phase 9: Third strike
		Phase.create_body_anim("melee_strike"),
		# Phase 10: Third hit damage
		Phase.create_damage_event(),
		# Phase 11: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# DASH TEMPLATE
#===============================================================================

## dash_attack - Rush forward then strike
static func _dash_attack() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "dash_attack"
	data.display_name = "Dash Attack"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon
		Phase.create_weapon_visibility(true),
		# Phase 1: Dash animation + movement (concurrent)
		Phase.create_body_anim("dash", 0.0, "dash", true),
		Phase.create_movement("toward_target", 60.0, 0.25, "dash"),
		# Phase 3: Strike
		Phase.create_body_anim("melee_strike"),
		# Phase 4: Damage
		Phase.create_damage_event(),
		# Phase 5: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# RANGED TEMPLATE
#===============================================================================

## ranged_aim - Hold-to-charge ranged shot
## The "aim" phase is held until the player releases the button.
## CombatHUD calls hold_current_phase() at start and release_held_phase() on release.
static func _ranged_aim() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "ranged_aim"
	data.display_name = "Ranged Aim"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon
		Phase.create_weapon_visibility(true),
		# Phase 1: Aim/charge animation (held until released externally)
		Phase.create_body_anim("aim", 0.0, "charge"),
		# Phase 2: Release animation
		Phase.create_body_anim("aim_release"),
		# Phase 3: Spawn projectile
		Phase.create_spawn_projectile(),
		# Phase 4: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# SPELL TEMPLATES
#===============================================================================

## spell_cast - Cast-time spell (like fireball)
static func _spell_cast() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "spell_cast"
	data.display_name = "Spell Cast"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Hide weapon for casting
		Phase.create_weapon_visibility(false),
		# Phase 1: Cast animation + cast circle effect (concurrent)
		Phase.create_body_anim("cast", 0.0, "cast", true),
		Phase.create_effect("cast_circle"),
		# Phase 3: Release animation
		Phase.create_body_anim("cast_release"),
		# Phase 4: Spawn projectile (or damage event for non-projectile spells)
		Phase.create_spawn_projectile(),
		# Phase 5: Restore weapon
		Phase.create_weapon_visibility(true),
		# Phase 6: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


## spell_instant - Instant-cast spell (like heal)
static func _spell_instant() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "spell_instant"
	data.display_name = "Instant Spell"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Hide weapon
		Phase.create_weapon_visibility(false),
		# Phase 1: Cast release animation
		Phase.create_body_anim("cast_release"),
		# Phase 2: Spell burst effect
		Phase.create_effect("spell_burst"),
		# Phase 3: Damage/heal event (combat system interprets based on ability data)
		Phase.create_damage_event(),
		# Phase 4: Restore weapon
		Phase.create_weapon_visibility(true),
		# Phase 5: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# THROW TEMPLATE
#===============================================================================

## throw - Throw an object (bomb, potion, etc.)
static func _throw() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "throw"
	data.display_name = "Throw"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Hide weapon (hand holds thrown object)
		Phase.create_weapon_visibility(false),
		# Phase 1: Throw windup + show held item (concurrent)
		Phase.create_body_anim("throw_windup", 0.0, "windup", true),
		Phase.create_effect("show_held_item"),
		# Phase 3: Throw release animation
		Phase.create_body_anim("throw_release"),
		# Phase 4: Spawn the thrown projectile
		Phase.create_spawn_projectile(),
		# Phase 5: Restore weapon
		Phase.create_weapon_visibility(true),
		# Phase 6: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# BUFF TEMPLATE
#===============================================================================

## self_buff - Cast a buff on self
static func _self_buff() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "self_buff"
	data.display_name = "Self Buff"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Hide weapon
		Phase.create_weapon_visibility(false),
		# Phase 1: Cast animation
		Phase.create_body_anim("cast", 0.0, "cast"),
		# Phase 2: Buff burst effect
		Phase.create_effect("buff_burst"),
		# Phase 3: Apply buff (combat system applies based on ability data)
		Phase.create_damage_event(),
		# Phase 4: Restore weapon
		Phase.create_weapon_visibility(true),
		# Phase 5: Return to idle
		Phase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data
