extends Node
## DamageCalculator - Centralized damage calculation utility
##
## Handles all damage formulas for the WoW-style combat system:
## - Melee/Ranged skills: Weapon Damage * % + Flat Bonus + Attack Power
## - Magic skills: Base Damage + (Damage Per Rank * Rank) + Spell Power
## - Critical strike calculations

## Skill categories for damage calculation
enum SkillCategory { MELEE, RANGED, MAGIC }

## DamageType alias - uses shared CombatTypes enum
const DamageType = CombatTypes.DamageType


func _ready() -> void:
	Debug.info("Combat", "DamageCalculator initialized")


#===============================================================================
# MAIN DAMAGE CALCULATION
#===============================================================================

## Calculate damage for a skill based on its category
## Returns a dictionary with damage breakdown
func calculate_skill_damage(talent: TalentData, skill_rank: int = 1) -> Dictionary:
	var category := _get_skill_category(talent)
	var result: Dictionary = {}

	match category:
		SkillCategory.MELEE, SkillCategory.RANGED:
			result = _calculate_weapon_damage(talent, skill_rank)
		SkillCategory.MAGIC:
			result = _calculate_magic_damage(talent, skill_rank)

	return result


## Calculate weapon-based damage (melee/ranged)
## Formula: (Weapon Damage * weapon_damage_percent / 100) + flat_damage_bonus + Attack Power
func _calculate_weapon_damage(talent: TalentData, skill_rank: int) -> Dictionary:
	var weapon_damage := Inventory.get_equipped_weapon_damage()
	var attack_power := PlayerStats.attack_power

	# Get skill modifiers
	var weapon_percent: float = talent.weapon_damage_percent
	var flat_bonus: float = talent.flat_damage_bonus
	var damage_per_rank: float = talent.damage_per_rank

	# Calculate scaled damage
	var weapon_portion := weapon_damage * (weapon_percent / 100.0)
	var rank_bonus := damage_per_rank * (skill_rank - 1)  # Rank 1 = no bonus
	var base_damage := weapon_portion + flat_bonus + rank_bonus + attack_power

	return {
		"base_damage": base_damage,
		"weapon_portion": weapon_portion,
		"flat_bonus": flat_bonus,
		"rank_bonus": rank_bonus,
		"attack_power": attack_power,
		"damage_type": talent.damage_type,
		"category": SkillCategory.MELEE if _get_skill_category(talent) == SkillCategory.MELEE else SkillCategory.RANGED,
	}


## Calculate magic damage (spells)
## Formula: base_damage + (damage_per_rank * (rank - 1)) + Spell Power + Elemental Bonus
func _calculate_magic_damage(talent: TalentData, skill_rank: int) -> Dictionary:
	var spell_power := PlayerStats.spell_power

	var base := talent.base_damage
	var per_rank := talent.damage_per_rank
	var rank_bonus := per_rank * (skill_rank - 1)
	var pre_bonus_damage := base + rank_bonus + spell_power

	# Apply elemental damage bonus (flat, not percentage)
	var elemental_bonus := _get_elemental_bonus(talent.damage_type)
	var total_damage := pre_bonus_damage + elemental_bonus

	return {
		"base_damage": total_damage,
		"skill_base": base,
		"rank_bonus": rank_bonus,
		"spell_power": spell_power,
		"elemental_bonus": elemental_bonus,
		"damage_type": talent.damage_type,
		"category": SkillCategory.MAGIC,
	}


#===============================================================================
# CRITICAL STRIKE
#===============================================================================

## Roll for critical strike and apply multiplier if successful
## Returns dictionary with final damage and crit status
func apply_critical(base_damage: float) -> Dictionary:
	var crit_chance := PlayerStats.critical_chance
	var crit_damage := PlayerStats.critical_damage

	var is_crit := randf() * 100.0 < crit_chance
	var final_damage := base_damage

	if is_crit:
		final_damage = base_damage * (crit_damage / 100.0)

	return {
		"damage": final_damage,
		"is_critical": is_crit,
		"crit_multiplier": crit_damage if is_crit else 100.0,
	}


## Calculate full damage with crit check
func calculate_final_damage(talent: TalentData, skill_rank: int = 1) -> Dictionary:
	var skill_result := calculate_skill_damage(talent, skill_rank)
	var base_damage: float = skill_result.get("base_damage", 0.0)

	var crit_result := apply_critical(base_damage)

	return {
		"final_damage": crit_result.damage,
		"base_damage": base_damage,
		"is_critical": crit_result.is_critical,
		"crit_multiplier": crit_result.crit_multiplier,
		"damage_type": skill_result.get("damage_type", DamageType.PHYSICAL),
		"category": skill_result.get("category", SkillCategory.MELEE),
		"breakdown": skill_result,
	}


#===============================================================================
# BASIC ATTACK (no skill, just weapon)
#===============================================================================

## Calculate basic attack damage (weapon + attack power)
func calculate_basic_attack() -> Dictionary:
	var weapon_damage := Inventory.get_equipped_weapon_damage()
	var attack_power := PlayerStats.attack_power
	var base_damage := weapon_damage + attack_power

	var crit_result := apply_critical(base_damage)

	return {
		"final_damage": crit_result.damage,
		"base_damage": base_damage,
		"weapon_damage": weapon_damage,
		"attack_power": attack_power,
		"is_critical": crit_result.is_critical,
		"damage_type": DamageType.PHYSICAL,
	}


#===============================================================================
# DPS CALCULATION
#===============================================================================

## Calculate weapon DPS for display
func get_weapon_dps() -> float:
	var weapon_damage := Inventory.get_equipped_weapon_damage()
	var attack_speed := Inventory.get_equipped_weapon_attack_speed()
	return weapon_damage * attack_speed


## Get formatted weapon stats for UI
func get_weapon_stats_text() -> String:
	var weapon_damage := Inventory.get_equipped_weapon_damage()
	var attack_speed := Inventory.get_equipped_weapon_attack_speed()
	var dps := weapon_damage * attack_speed

	if weapon_damage <= 1.0:
		return "Unarmed (1 DPS)"

	return "%.0f Damage, %.2f Speed (%.1f DPS)" % [weapon_damage, attack_speed, dps]


#===============================================================================
# DAMAGE REDUCTION (for incoming damage)
#===============================================================================

## Calculate damage reduction from armor (physical)
## Uses diminishing returns formula: reduction = armor / (armor + k * level)
func calculate_armor_reduction(incoming_damage: float, attacker_level: int = 1) -> float:
	var armor := PlayerStats.armor
	# k is the armor constant from database (default 50.0)
	var k := DatabaseLoader.get_setting("armor_constant", 50.0)
	var reduction := armor / (armor + k * attacker_level)
	var mitigated := incoming_damage * (1.0 - reduction)
	return maxf(mitigated, 1.0)  # Minimum 1 damage


## Calculate damage reduction from magic resistance
func calculate_magic_reduction(incoming_damage: float, attacker_level: int = 1) -> float:
	var resist := PlayerStats.magic_resistance
	var k := DatabaseLoader.get_setting("armor_constant", 50.0)  # Uses same constant
	var reduction := resist / (resist + k * attacker_level)
	var mitigated := incoming_damage * (1.0 - reduction)
	return maxf(mitigated, 1.0)


## Apply appropriate damage reduction based on damage type
func apply_damage_reduction(incoming_damage: float, damage_type: int, attacker_level: int = 1) -> float:
	match damage_type:
		DamageType.PHYSICAL, DamageType.BLEED:
			return calculate_armor_reduction(incoming_damage, attacker_level)
		DamageType.PURE:
			return incoming_damage  # True damage ignores all reduction
		_:
			# All elemental damage uses magic resistance
			return calculate_magic_reduction(incoming_damage, attacker_level)


#===============================================================================
# UTILITY
#===============================================================================

## Get elemental damage bonus from equipment based on damage type
func _get_elemental_bonus(damage_type: CombatTypes.DamageType) -> float:
	match damage_type:
		DamageType.FIRE:
			return PlayerStats.get_equipment_bonus("fire_spell_damage")
		DamageType.COLD:
			return PlayerStats.get_equipment_bonus("cold_spell_damage")
		DamageType.LIGHTNING:
			return PlayerStats.get_equipment_bonus("lightning_spell_damage")
		DamageType.POISON:
			return PlayerStats.get_equipment_bonus("poison_spell_damage")
		DamageType.ARCANE:
			return PlayerStats.get_equipment_bonus("arcane_spell_damage")
		_:
			return 0.0


## Get skill category from talent data
func _get_skill_category(talent: TalentData) -> SkillCategory:
	var category_str: String = talent.skill_category.to_lower()
	match category_str:
		"melee":
			return SkillCategory.MELEE
		"ranged":
			return SkillCategory.RANGED
		"magic":
			return SkillCategory.MAGIC
		_:
			# Default to melee if unspecified
			return SkillCategory.MELEE


## Get damage type name for display
static func get_damage_type_name(damage_type: int) -> String:
	match damage_type:
		DamageType.PHYSICAL: return "Physical"
		DamageType.FIRE: return "Fire"
		DamageType.COLD: return "Cold"
		DamageType.LIGHTNING: return "Lightning"
		DamageType.POISON: return "Poison"
		DamageType.ARCANE: return "Arcane"
		DamageType.BLEED: return "Bleed"
		DamageType.PURE: return "Pure"
		_: return "Unknown"


## Get damage type color for UI
static func get_damage_type_color(damage_type: int) -> Color:
	match damage_type:
		DamageType.PHYSICAL: return Color(0.9, 0.9, 0.9)  # White/gray
		DamageType.FIRE: return Color(1.0, 0.4, 0.1)  # Orange
		DamageType.COLD: return Color(0.3, 0.7, 1.0)  # Light blue
		DamageType.LIGHTNING: return Color(1.0, 1.0, 0.3)  # Yellow
		DamageType.POISON: return Color(0.3, 0.8, 0.2)  # Green
		DamageType.ARCANE: return Color(0.7, 0.3, 1.0)  # Purple
		DamageType.BLEED: return Color(0.8, 0.1, 0.1)  # Dark red
		DamageType.PURE: return Color(1.0, 1.0, 1.0)  # Pure white (ignores armor/resist)
		_: return Color.WHITE


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_skill_damage(talent: TalentData, skill_rank: int = 1) -> void:
	var result := calculate_final_damage(talent, skill_rank)
	Debug.snapshot("Combat", "Skill Damage: %s (Rank %d)" % [talent.talent_name, skill_rank], {
		"final_damage": result.final_damage,
		"base_damage": result.base_damage,
		"is_critical": result.is_critical,
		"category": SkillCategory.keys()[result.category],
		"damage_type": get_damage_type_name(result.damage_type),
	})


#===============================================================================
# ENEMY DAMAGE CALCULATION
#===============================================================================

## Calculate enemy ability damage
## This routes enemy damage through the same system as player damage
## for consistency and to enable enemy crits, elemental bonuses, etc.
func calculate_enemy_ability_damage(ability: AbilityData, enemy_base_damage: float, enemy_level: int = 1, enable_crit: bool = false, crit_chance: float = 0.0, crit_multiplier: float = 150.0) -> Dictionary:
	var base_damage := enemy_base_damage * ability.damage_mult
	var damage_type := ability.damage_type as int

	var is_crit := false
	var final_damage := base_damage

	# Optional critical strikes for enemies
	if enable_crit and crit_chance > 0:
		is_crit = randf() * 100.0 < crit_chance
		if is_crit:
			final_damage = base_damage * (crit_multiplier / 100.0)

	return {
		"final_damage": final_damage,
		"base_damage": base_damage,
		"is_critical": is_crit,
		"crit_multiplier": crit_multiplier if is_crit else 100.0,
		"damage_type": damage_type,
		"enemy_base_damage": enemy_base_damage,
		"damage_mult": ability.damage_mult,
		"enemy_level": enemy_level
	}


## Calculate enemy basic attack damage (no ability, just base damage)
func calculate_enemy_basic_attack(enemy_base_damage: float, enemy_level: int = 1, damage_type: int = DamageType.PHYSICAL, enable_crit: bool = false, crit_chance: float = 0.0, crit_multiplier: float = 150.0) -> Dictionary:
	var is_crit := false
	var final_damage := enemy_base_damage

	if enable_crit and crit_chance > 0:
		is_crit = randf() * 100.0 < crit_chance
		if is_crit:
			final_damage = enemy_base_damage * (crit_multiplier / 100.0)

	return {
		"final_damage": final_damage,
		"base_damage": enemy_base_damage,
		"is_critical": is_crit,
		"crit_multiplier": crit_multiplier if is_crit else 100.0,
		"damage_type": damage_type,
		"enemy_level": enemy_level
	}


## Calculate damage reduction for enemy taking damage (player attacking enemy)
## Enemies use their own armor stat
func calculate_enemy_damage_taken(incoming_damage: float, enemy_armor: float, enemy_magic_resist: float, damage_type: int, attacker_level: int = 1) -> float:
	var k := DatabaseLoader.get_setting("armor_constant", 50.0)

	match damage_type:
		DamageType.PHYSICAL, DamageType.BLEED:
			var reduction := enemy_armor / (enemy_armor + k * attacker_level)
			return maxf(incoming_damage * (1.0 - reduction), 1.0)
		DamageType.PURE:
			return incoming_damage
		_:
			var reduction := enemy_magic_resist / (enemy_magic_resist + k * attacker_level)
			return maxf(incoming_damage * (1.0 - reduction), 1.0)


## Get damage after enemy armor/resist (convenience method)
func get_damage_after_enemy_mitigation(incoming_damage: float, enemy: Node2D, damage_type: int, attacker_level: int = 1) -> float:
	var armor: float = enemy.armor if "armor" in enemy else 0.0
	var magic_resist: float = enemy.magic_resistance if "magic_resistance" in enemy else 0.0
	return calculate_enemy_damage_taken(incoming_damage, armor, magic_resist, damage_type, attacker_level)

