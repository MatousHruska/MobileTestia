class_name AbilityVisualTemplates
## AbilityVisualTemplates - Static factory for built-in ability visual templates.
##
## Constructs the standard visual templates in code so abilities can reference
## them by name without needing .tres files during development.
##
## Each template defines the *shape* of the visual sequence. Actual durations
## (windup time, lunge distance, recovery time) come from ability/talent data
## and are applied via the overrides dictionary in AbilityVisualPlayer.play().


## Returns a dictionary of template_id -> AbilityVisualData.
## These are the standard templates that abilities reference by name.
static func get_all() -> Dictionary:
	return {
		"melee_single": _melee_single(),
		"melee_combo_2": _melee_combo_2(),
		"melee_combo_3": _melee_combo_3(),
		"dash_attack": _dash_attack(),
		"ranged_aim": _ranged_aim(),
		"ranged_attack": _ranged_attack(),
		"spell_cast": _spell_cast(),
		"spell_instant": _spell_instant(),
		"throw": _throw(),
		"self_buff": _self_buff(),
		"howl": _howl(),
	}


## Retrieve a single template by ID. Returns null if not found.
static func get_template(template_id: String) -> AbilityVisualData:
	var all_templates := get_all()
	return all_templates.get(template_id) as AbilityVisualData


#===============================================================================
# MELEE TEMPLATES
#===============================================================================

## melee_single - Standard single melee attack
## Weapon visible throughout: raised during windup, swings with strike,
## lingers briefly pointing in attack direction, then hides for recovery.
static func _melee_single() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "melee_single"
	data.display_name = "Melee Single"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon for windup
		AbilityVisualPhase.create_weapon_visibility(true),
		# Phase 1: Windup animation (sword raised behind)
		AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Spawn slash effect (weapon still visible)
		AbilityVisualPhase.create_effect("slash_arc"),
		# Phase 3: Strike starts — 50ms lets sword reach mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 4: Lunge forward (concurrent with damage — follow-through)
		AbilityVisualPhase.create_movement("toward_target", 20.0, 0.08, "lunge", true),
		# Phase 5: Damage fires mid-swing as body lunges
		AbilityVisualPhase.create_damage_event(),
		# Phase 6: Brief linger — sword stays extended in attack direction
		AbilityVisualPhase.create_wait(0.12),
		# Phase 7: Hide weapon
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 8: Return to idle (recovery)
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


## melee_combo_2 - Two-hit melee combo
## Weapon stays visible throughout all hits, hides after last strike linger.
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
		# Phase 2: First slash effect
		AbilityVisualPhase.create_effect("slash_arc"),
		# Phase 3: Strike starts — 50ms lets sword reach mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 4: Lunge (concurrent with damage — follow-through)
		AbilityVisualPhase.create_movement("toward_target", 20.0, 0.08, "lunge", true),
		# Phase 5: First hit damage fires mid-swing
		AbilityVisualPhase.create_damage_event(),
		# Phase 6: Brief pause between hits (weapon stays visible)
		AbilityVisualPhase.create_wait(0.1),
		# Phase 7: Second slash effect (wider for combo)
		AbilityVisualPhase.create_effect("slash_arc_wide"),
		# Phase 8: Second strike — 50ms then damage mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 9: Second hit damage
		AbilityVisualPhase.create_damage_event(),
		# Phase 10: Brief linger — sword extended
		AbilityVisualPhase.create_wait(0.12),
		# Phase 11: Hide weapon
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 12: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


## melee_combo_3 - Three-hit melee combo
## Weapon stays visible throughout all hits, hides after last strike linger.
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
		# Phase 2: First slash effect
		AbilityVisualPhase.create_effect("slash_arc"),
		# Phase 3: Strike starts — 50ms lets sword reach mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 4: Lunge (concurrent with damage — follow-through)
		AbilityVisualPhase.create_movement("toward_target", 20.0, 0.08, "lunge", true),
		# Phase 5: First hit damage fires mid-swing
		AbilityVisualPhase.create_damage_event(),
		# Phase 6: Brief pause (weapon stays visible between hits)
		AbilityVisualPhase.create_wait(0.1),
		# Phase 7: Second slash effect (wider for combo)
		AbilityVisualPhase.create_effect("slash_arc_wide"),
		# Phase 8: Second strike — 50ms then damage mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 9: Second hit damage
		AbilityVisualPhase.create_damage_event(),
		# Phase 10: Brief pause
		AbilityVisualPhase.create_wait(0.1),
		# Phase 11: Third slash effect (wider)
		AbilityVisualPhase.create_effect("slash_arc_wide"),
		# Phase 12: Third strike — 50ms then damage mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 13: Third hit damage
		AbilityVisualPhase.create_damage_event(),
		# Phase 14: Brief linger — sword extended
		AbilityVisualPhase.create_wait(0.12),
		# Phase 15: Hide weapon
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 16: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# DASH TEMPLATE
#===============================================================================

## dash_attack - Rush forward then strike
## Weapon visible throughout: during dash, strike, and brief linger after.
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
		# Phase 3: Slash effect (wide — dash attacks hit hard)
		AbilityVisualPhase.create_effect("slash_arc_wide"),
		# Phase 4: Strike starts — 50ms lets sword reach mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", 0.05),
		# Phase 5: Damage fires mid-swing
		AbilityVisualPhase.create_damage_event(),
		# Phase 6: Brief linger — sword extended
		AbilityVisualPhase.create_wait(0.12),
		# Phase 7: Hide weapon
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 8: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
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
		AbilityVisualPhase.create_weapon_visibility(true),
		# Phase 1: Aim/charge animation (held until released externally)
		AbilityVisualPhase.create_body_anim("aim", 0.0, "charge"),
		# Phase 2: Release animation
		AbilityVisualPhase.create_body_anim("aim_release"),
		# Phase 3: Spawn projectile
		AbilityVisualPhase.create_spawn_projectile(),
		# Phase 4: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
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
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 1: Cast animation + cast circle effect (concurrent)
		AbilityVisualPhase.create_body_anim("cast", 0.0, "cast", true),
		AbilityVisualPhase.create_effect("cast_circle"),
		# Phase 3: Release animation
		AbilityVisualPhase.create_body_anim("cast_release"),
		# Phase 4: Spawn projectile (or damage event for non-projectile spells)
		AbilityVisualPhase.create_spawn_projectile(),
		# Phase 5: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
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
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 1: Cast release animation
		AbilityVisualPhase.create_body_anim("cast_release"),
		# Phase 2: Spell burst effect
		AbilityVisualPhase.create_effect("spell_burst"),
		# Phase 3: Damage/heal event (combat system interprets based on ability data)
		AbilityVisualPhase.create_damage_event(),
		# Phase 4: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
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
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 1: Throw windup + show held item (concurrent)
		AbilityVisualPhase.create_body_anim("throw_windup", 0.0, "windup", true),
		AbilityVisualPhase.create_effect("show_held_item"),
		# Phase 3: Throw release animation
		AbilityVisualPhase.create_body_anim("throw_release"),
		# Phase 4: Spawn the thrown projectile
		AbilityVisualPhase.create_spawn_projectile(),
		# Phase 5: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
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
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 1: Cast animation
		AbilityVisualPhase.create_body_anim("cast", 0.0, "cast"),
		# Phase 2: Buff burst effect
		AbilityVisualPhase.create_effect("buff_burst"),
		# Phase 3: Apply buff (combat system applies based on ability data)
		AbilityVisualPhase.create_damage_event(),
		# Phase 4: Return to idle
		AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"),
	]

	return data


#===============================================================================
# ENEMY-SPECIFIC TEMPLATES
#===============================================================================

## ranged_attack - Enemy ranged attack (no aiming, instant fire)
## Windup -> spawn projectile -> recovery
static func _ranged_attack() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "ranged_attack"
	data.display_name = "Ranged Attack"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Windup animation (uses attack_{dir} fallback)
		AbilityVisualPhase.create_body_anim("attack", 0.0, "windup"),
		# Phase 1: Spawn projectile
		AbilityVisualPhase.create_spawn_projectile(),
		# Phase 2: Recovery
		AbilityVisualPhase.create_wait(0.3, "recovery"),
	]

	return data


## howl - Custom ability animation for wolf howl
## Plays howl_{dir} animation, emits effect, then damage
static func _howl() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "howl"
	data.display_name = "Howl"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Howl animation (uses howl_{dir} animations)
		AbilityVisualPhase.create_body_anim("howl", 0.0, "cast"),
		# Phase 1: Howl aura effect
		AbilityVisualPhase.create_effect("howl_aura"),
		# Phase 2: Damage/buff event
		AbilityVisualPhase.create_damage_event(),
		# Phase 3: Recovery
		AbilityVisualPhase.create_wait(0.3, "recovery"),
	]

	return data
