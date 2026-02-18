class_name AbilityVisualTemplates
## AbilityVisualTemplates - Static factory for built-in ability visual templates.
##
## Constructs the standard visual templates in code so abilities can reference
## them by name without needing .tres files during development.
##
## Each template defines the *shape* of the visual sequence. Actual durations
## (windup time, lunge distance, recovery time) come from ability/talent data
## and are applied via the overrides dictionary in AbilityVisualPlayer.play().

#===============================================================================
# TIMING & DISTANCE CONSTANTS
#===============================================================================

const STRIKE_LEAD_IN := 0.05       ## Delay after strike anim before damage
const WEAPON_LINGER := 0.12        ## Weapon stays extended after hit
const COMBO_PAUSE := 0.1           ## Beat between combo hits
const DEFAULT_LUNGE_DISTANCE := 20.0
const DEFAULT_LUNGE_DURATION := 0.08
const DASH_DISTANCE := 60.0
const DASH_DURATION := 0.25
const ENEMY_RECOVERY_WAIT := 0.3


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
		"parry_stance": _parry_stance(),
		"howl": _howl(),
	}


## Retrieve a single template by ID. Returns null if not found.
static func get_template(template_id: String) -> AbilityVisualData:
	var all_templates := get_all()
	return all_templates.get(template_id) as AbilityVisualData


#===============================================================================
# TEMPLATE ROUTING
#===============================================================================

## Resolve the visual template ID for a player talent.
## Uses explicit visual_type first, then hit_count for combo selection,
## then auto-detects from effect_type.
static func resolve_template_for_talent(talent: TalentData) -> String:
	# Explicit override from database
	if not talent.visual_type.is_empty():
		return talent.visual_type

	# Hit-count-aware combo selection for melee damage skills
	if talent.hit_count > 0 and talent.effect_type == TalentData.EffectType.DAMAGE:
		match talent.hit_count:
			1: return "melee_single"
			2: return "melee_combo_2"
			3: return "melee_combo_3"
			_: return "melee_single"

	# Auto-detect fallback from effect_type
	match talent.effect_type:
		TalentData.EffectType.DAMAGE:
			return "melee_single"
		TalentData.EffectType.PROJECTILE:
			return "ranged_aim"
		TalentData.EffectType.MAGIC_PROJECTILE, TalentData.EffectType.MAGIC_PROJECTILE_AOE:
			if talent.cast_time > 0:
				return "spell_cast"
			else:
				return "spell_instant"
		TalentData.EffectType.SELF_BUFF:
			return "self_buff"
		TalentData.EffectType.HEAL:
			return "spell_instant"
		TalentData.EffectType.AOE:
			return "spell_cast"
		_:
			return "melee_single"


## Resolve the visual template ID for an enemy ability.
## Uses explicit visual_type, then custom animation name, then ability_type fallback.
static func resolve_template_for_enemy_ability(ability: Dictionary, ability_type: String) -> String:
	# Explicit visual_type override from database takes priority
	var visual_type: String = ability.get("visual_type", "")
	if not visual_type.is_empty():
		return visual_type

	# Check if ability has a custom animation mapping (e.g., "howl")
	var animation: String = ability.get("animation", "attack")
	if animation != "attack" and animation != "":
		if get_all().has(animation):
			return animation

	# Auto-detect fallback from ability type
	match ability_type:
		"melee":
			return "melee_single"
		"dash":
			return "dash_attack"
		"ranged", "projectile":
			return "ranged_attack"
		"buff":
			return "self_buff"
		"debuff":
			return "spell_cast"
		_:
			return "melee_single"


#===============================================================================
# MELEE TEMPLATES
#===============================================================================

## melee_single - Standard single melee attack
static func _melee_single() -> AbilityVisualData:
	return _build_melee_combo(1, ["slash_arc"])


## melee_combo_2 - Two-hit melee combo
static func _melee_combo_2() -> AbilityVisualData:
	return _build_melee_combo(2, ["slash_arc", "slash_arc_wide"])


## melee_combo_3 - Three-hit melee combo
static func _melee_combo_3() -> AbilityVisualData:
	return _build_melee_combo(3, ["slash_arc", "slash_arc_wide", "slash_arc_wide"])


#===============================================================================
# MELEE COMPOSITION HELPERS
#===============================================================================

## Build phases for one melee hit beat: effect -> strike -> lunge+damage.
## override_key "hit" enables per-skill hit_effect override (Step 6).
static func _melee_hit_phases(effect_id: String, override_key: String = "hit") -> Array[AbilityVisualPhase]:
	var effect_phase := AbilityVisualPhase.create_effect(effect_id)
	effect_phase.override_key = override_key
	return [
		effect_phase,
		AbilityVisualPhase.create_body_anim("melee_strike", STRIKE_LEAD_IN),
		AbilityVisualPhase.create_movement("toward_target", DEFAULT_LUNGE_DISTANCE, DEFAULT_LUNGE_DURATION, "lunge", true),
		AbilityVisualPhase.create_damage_event(),
	]


## Build a full melee combo: weapon show -> windup -> N hits with pauses -> linger -> weapon hide -> recovery.
## hit_count: number of hits (1-10). effects: array of effect IDs per hit (cycled if shorter than hit_count).
static func _build_melee_combo(hit_count: int, effects: Array) -> AbilityVisualData:
	var data := AbilityVisualData.new()

	match hit_count:
		1:
			data.template_id = "melee_single"
			data.display_name = "Melee Single"
		2:
			data.template_id = "melee_combo_2"
			data.display_name = "Melee Combo (2-hit)"
		3:
			data.template_id = "melee_combo_3"
			data.display_name = "Melee Combo (3-hit)"
		_:
			data.template_id = "melee_combo_%d" % hit_count
			data.display_name = "Melee Combo (%d-hit)" % hit_count

	data.locks_movement = true

	var phases: Array[AbilityVisualPhase] = []

	# Weapon show + windup
	phases.append(AbilityVisualPhase.create_weapon_visibility(true))
	phases.append(AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"))

	# N hits with pauses between
	for i in hit_count:
		if i > 0:
			phases.append(AbilityVisualPhase.create_wait(COMBO_PAUSE))
		var effect_id: String = effects[i % effects.size()]
		phases.append_array(_melee_hit_phases(effect_id))

	# Linger + weapon hide + recovery
	phases.append(AbilityVisualPhase.create_wait(WEAPON_LINGER))
	phases.append(AbilityVisualPhase.create_weapon_visibility(false))
	phases.append(AbilityVisualPhase.create_body_anim("idle", 0.0, "recovery"))

	data.phases = phases
	return data


#===============================================================================
# PARRY TEMPLATE
#===============================================================================

## parry_stance - Defensive stance with a timed parry window
## Weapon raised in guard position, waits for the parry window duration,
## then returns to idle. If hit during the window, the combat system
## cancels this sequence and triggers a counter-attack.
static func _parry_stance() -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = "parry_stance"
	data.display_name = "Parry Stance"
	data.locks_movement = true

	data.phases = [
		# Phase 0: Show weapon (guard position)
		AbilityVisualPhase.create_weapon_visibility(true),
		# Phase 1: Enter parry stance animation
		AbilityVisualPhase.create_body_anim("melee_windup", 0.0, "windup"),
		# Phase 2: Hold parry window (duration overridden by talent data)
		AbilityVisualPhase.create_wait(0.5, "parry_window"),
		# Phase 3: Parry window expired — hide weapon and return to idle
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 4: Return to idle (recovery)
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
		AbilityVisualPhase.create_movement("toward_target", DASH_DISTANCE, DASH_DURATION, "dash"),
		# Phase 3: Slash effect (wide — dash attacks hit hard)
		AbilityVisualPhase.create_effect("slash_arc_wide"),
		# Phase 4: Strike starts — brief lead-in lets sword reach mid-arc
		AbilityVisualPhase.create_body_anim("melee_strike", STRIKE_LEAD_IN),
		# Phase 5: Damage fires mid-swing
		AbilityVisualPhase.create_damage_event(),
		# Phase 6: Brief linger — sword extended
		AbilityVisualPhase.create_wait(WEAPON_LINGER),
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
		# Phase 0: Show weapon (bow appears)
		AbilityVisualPhase.create_weapon_visibility(true),
		# Phase 1: Aim/charge animation (held until released externally)
		AbilityVisualPhase.create_body_anim("aim", 0.0, "charge"),
		# Phase 2: Release animation
		AbilityVisualPhase.create_body_anim("aim_release"),
		# Phase 3: Bowstring snap effect at string position
		AbilityVisualPhase.create_effect("bowstring_snap"),
		# Phase 4: Spawn projectile
		AbilityVisualPhase.create_spawn_projectile(),
		# Phase 5: Hide weapon (bow disappears after shot)
		AbilityVisualPhase.create_weapon_visibility(false),
		# Phase 6: Return to idle
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
		AbilityVisualPhase.create_wait(ENEMY_RECOVERY_WAIT, "recovery"),
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
		AbilityVisualPhase.create_wait(ENEMY_RECOVERY_WAIT, "recovery"),
	]

	return data
