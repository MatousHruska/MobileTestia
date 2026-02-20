extends Resource
class_name TalentData
## TalentData - Defines a single talent in the talent tree system
##
## Talents can be either:
## - passive: Grants stat bonuses when learned
## - active: Unlocks an ability that appears in the Skillbook

## Talent type enum
enum TalentType { PASSIVE, ACTIVE }

## Effect type for active talents
enum EffectType { NONE, DAMAGE, HEAL, BUFF, DEBUFF, PROJECTILE, MAGIC_PROJECTILE, MAGIC_PROJECTILE_AOE, SUMMON, TELEPORT, AOE, SELF_BUFF }

#===============================================================================
# IDENTIFICATION
#===============================================================================

## Unique talent identifier (e.g., "tal_noble_powerstrike")
@export var id: String = ""

## Display name
@export var talent_name: String = ""

## Tree this talent belongs to (e.g., "tree_noble_legacy")
@export var tree_id: String = ""

## Position in the tree (row 1 = top, column 1 = left)
@export var row: int = 1
@export var column: int = 1

## Maximum investable points (1-5)
@export var max_points: int = 1

## Talent type (passive or active)
@export var type: TalentType = TalentType.PASSIVE

## Prerequisite talent IDs (must be maxed to unlock this talent)
@export var prerequisite_ids: Array[String] = []

## Icon resource name
@export var icon_name: String = ""

#===============================================================================
# ACTIVE TALENT PROPERTIES (only used when type == ACTIVE)
#===============================================================================

## Skill category (melee, ranged, magic) - determines damage formula
@export var skill_category: String = ""

## Auto-learn: If true, skill is learned automatically at game start
@export var auto_learn: bool = false

## Resource costs
@export var mana_cost: float = 0.0
@export var stamina_cost: float = 0.0

## Cooldown in seconds
@export var cooldown: float = 0.0

## Weapon-based damage (for melee/ranged)
@export var weapon_damage_percent: float = 0.0  # % of weapon damage
@export var flat_damage_bonus: float = 0.0      # Flat damage added

## Magic-based damage (for spells)
@export var base_damage: float = 0.0            # Base spell damage
@export var damage_per_rank: float = 0.0        # Damage increase per skill rank

## Damage type (physical, fire, cold, etc.) - uses shared CombatTypes enum
@export var damage_type: CombatTypes.DamageType = CombatTypes.DamageType.PHYSICAL

## Combat mechanics
@export var lunge_force: float = 0.0            # Lunge force when using skill
@export var recovery_time: float = 0.0          # Time before player can act again
@export var hit_range: float = 50.0             # Attack range in pixels
@export var hit_arc: float = 360.0              # Hit arc in degrees (360 = all around, 90 = forward cone)

## Required weapon category (melee, melee_1h, melee_2h, ranged, magic, or empty for any)
@export var required_weapon_category: String = ""

## Projectile charge settings (for hold-to-charge ranged skills)
@export var min_charge_time: float = 0.5           # Min seconds to charge for full damage
@export var weak_shot_damage_percent: float = 30.0 # Damage % for quick shot (0 = disabled)
@export var weak_shot_range_percent: float = 30.0  # Range % for quick shot

## Magic projectile settings
@export var cast_time: float = 0.0                 # Cast time before firing (magic skills)
@export var explosion_radius: float = 0.0          # AOE explosion radius (magic projectiles)
@export var contact_status_effect: String = ""     # Status effect applied on projectile contact
@export var projectile_speed: float = 0.0          # Projectile travel speed (0 = default)

## Cast bar behavior
@export var can_move_while_casting: bool = false   # Can player move while casting?
@export var interrupt_on_damage: bool = true       # Does taking damage interrupt cast?

## Visual template override (empty = auto-detect from effect_type)
@export var visual_type: String = ""

## Whether to show the weapon during spell casting (e.g., staff visible for fireball)
@export var show_weapon: bool = false

## Per-skill animation overrides (previously hardcoded in templates)
@export var windup_time: float = 0.0              ## Seconds before attack hits (0 = use anim length)
@export var hit_effect: String = ""                ## VFX effect ID per-skill (empty = template default)
@export var hit_count: int = 0                     ## Combo hit count (0 = template default)

## Database-driven timing (previously hardcoded)
@export var max_charge_time: float = 2.0           # Max charge time for full range (ranged)
@export var base_range: float = 150.0              # Base range at minimum charge (ranged)
@export var lunge_duration: float = 0.1            # Lunge movement duration (melee)
@export var explosion_falloff: float = 30.0        # Damage falloff % at explosion edge (magic, 0=no falloff)

## Legacy field (kept for backwards compatibility)
@export var damage_per_point: float = 0.0

## Effect properties
@export var effect_type: EffectType = EffectType.NONE
@export var effect_value: float = 0.0
@export var effect_per_point: float = 0.0
@export var duration: float = 0.0

#===============================================================================
# PASSIVE TALENT PROPERTIES (only used when type == PASSIVE)
#===============================================================================

## Stat bonuses per point (e.g., {"strength": 2, "armor": 5})
@export var stat_bonuses: Dictionary = {}

#===============================================================================
# PROC SYSTEM (for conditional/event-driven passive talents)
#===============================================================================

## Event that triggers the proc (e.g., "on_kill", "on_dodge", "on_hit", "on_crit", "on_take_damage", "on_parry", "always")
@export var proc_trigger: String = ""

## Condition that must be met (e.g., "stamina_above_50", "target_full_hp", "target_marked")
@export var proc_condition: String = ""

## Effect to apply when triggered (e.g., "apply_status:status_marked", "buff:attack_speed:15:3")
@export var proc_effect: String = ""

## % chance to trigger (0 = always)
@export var proc_chance: float = 0.0

## Internal cooldown in seconds (0 = no cooldown)
@export var proc_cooldown: float = 0.0

#===============================================================================
# DESCRIPTIONS
#===============================================================================

## Base description
@export var description: String = ""

## Per-rank descriptions (array of strings, one per rank)
@export var rank_descriptions: Array[String] = []


#===============================================================================
# FACTORY METHODS
#===============================================================================

## Create TalentData from database dictionary
static func from_dict(data: Dictionary) -> TalentData:
	var talent := TalentData.new()

	talent.id = data.get("id", "")
	talent.talent_name = data.get("name", "")
	talent.tree_id = data.get("tree", "")
	talent.row = int(data.get("row", 1))
	talent.column = int(data.get("column", 1))
	talent.max_points = int(data.get("max_points", 1))
	talent.icon_name = data.get("icon_name", talent.id)

	# Parse type
	var type_str: String = data.get("type", "passive").to_lower()
	talent.type = TalentType.ACTIVE if type_str == "active" else TalentType.PASSIVE

	# Active skills always have max_points = 1 (unlocked in tree, ranked at trainers)
	if talent.type == TalentType.ACTIVE:
		talent.max_points = 1

	# Parse prerequisites
	var prereqs_str: String = data.get("prerequisite_ids", "")
	if not prereqs_str.is_empty():
		for prereq in prereqs_str.split(","):
			var trimmed := prereq.strip_edges()
			if not trimmed.is_empty():
				talent.prerequisite_ids.append(trimmed)

	# Active talent properties
	talent.skill_category = data.get("skill_category", "")
	talent.auto_learn = _parse_bool(data.get("auto_learn", false))
	talent.mana_cost = float(data.get("mana_cost", 0))
	talent.stamina_cost = float(data.get("stamina_cost", 0))
	talent.cooldown = float(data.get("cooldown", 0))

	# Weapon-based damage (melee/ranged)
	talent.weapon_damage_percent = float(data.get("weapon_damage_percent", 0))
	talent.flat_damage_bonus = float(data.get("flat_damage_bonus", 0))

	# Magic-based damage
	talent.base_damage = float(data.get("base_damage", 0))
	talent.damage_per_rank = float(data.get("damage_per_rank", 0))

	# Damage type (string from database -> enum)
	var damage_type_str: String = str(data.get("damage_type", "physical"))
	talent.damage_type = CombatTypes.damage_type_from_string(damage_type_str)

	# Combat mechanics
	talent.lunge_force = float(data.get("lunge_force", 0))
	talent.recovery_time = float(data.get("recovery_time", 0))
	talent.hit_range = float(data.get("hit_range", 50))
	talent.hit_arc = float(data.get("hit_arc", 360))

	# Required weapon category
	talent.required_weapon_category = data.get("required_weapon_category", "")

	# Projectile charge settings
	talent.min_charge_time = float(data.get("min_charge_time", 0.5))
	talent.weak_shot_damage_percent = float(data.get("weak_shot_damage_percent", 30))
	talent.weak_shot_range_percent = float(data.get("weak_shot_range_percent", 30))

	# Magic projectile settings
	talent.cast_time = float(data.get("cast_time", 0))
	talent.explosion_radius = float(data.get("explosion_radius", 0))
	talent.contact_status_effect = data.get("contact_status_effect", "")
	talent.projectile_speed = float(data.get("projectile_speed", 0))

	# Cast bar behavior
	talent.can_move_while_casting = _parse_bool(data.get("can_move_while_casting", false))
	talent.interrupt_on_damage = _parse_bool(data.get("interrupt_on_damage", true))

	# Visual template override
	talent.visual_type = data.get("visual_type", "")

	# Show weapon during spell casting
	talent.show_weapon = _parse_bool(data.get("show_weapon", false))

	# Per-skill animation overrides
	talent.windup_time = float(data.get("windup_time", 0))
	talent.hit_effect = data.get("hit_effect", "")
	talent.hit_count = int(data.get("hit_count", 0))

	# Database-driven timing (previously hardcoded)
	talent.max_charge_time = float(data.get("max_charge_time", 2.0))
	talent.base_range = float(data.get("base_range", 150.0))
	talent.lunge_duration = float(data.get("lunge_duration", 0.1))
	talent.explosion_falloff = float(data.get("explosion_falloff", 30.0))

	# Legacy fields
	talent.damage_per_point = float(data.get("damage_per_point", 0))

	# Effect properties (for buffs/debuffs, parsed from effect_type string for passives)
	var effect_str: String = data.get("effect_type", "")
	if talent.is_passive() and ":" in effect_str:
		# For passives, effect_type contains stat bonuses like "strength:2;vitality:1"
		talent.stat_bonuses = _parse_stat_bonuses(effect_str)
		talent.effect_type = EffectType.NONE
	else:
		talent.effect_type = _effect_type_from_string(effect_str)

	talent.effect_value = float(data.get("effect_value", 0))
	talent.effect_per_point = float(data.get("effect_per_point", 0))
	talent.duration = float(data.get("duration", 0))

	# Parse stat bonuses for passive talents (from stat_bonuses field, merges with effect_type)
	var bonuses_str: String = data.get("stat_bonuses", "")
	if not bonuses_str.is_empty():
		var additional := _parse_stat_bonuses(bonuses_str)
		for stat in additional:
			talent.stat_bonuses[stat] = additional[stat]

	# Proc system fields
	talent.proc_trigger = data.get("proc_trigger", "")
	talent.proc_condition = data.get("proc_condition", "")
	talent.proc_effect = data.get("proc_effect", "")
	talent.proc_chance = float(data.get("proc_chance", 0))
	talent.proc_cooldown = float(data.get("proc_cooldown", 0))

	# Descriptions
	talent.description = data.get("description", "")
	var ranks_str: String = data.get("rank_descriptions", "")
	if not ranks_str.is_empty():
		for rank_desc in ranks_str.split("|"):
			talent.rank_descriptions.append(rank_desc.strip_edges())

	return talent


## Parse boolean from various formats (true, false, 1, 0, "true", "false")
static func _parse_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is String:
		return value.to_lower() in ["true", "1", "yes"]
	return false


## Parse stat bonuses string "stat:value;stat2:value2" into dictionary
static func _parse_stat_bonuses(bonuses_str: String) -> Dictionary:
	var result: Dictionary = {}
	if bonuses_str.is_empty():
		return result

	for pair in bonuses_str.split(";"):
		var kv := pair.split(":")
		if kv.size() == 2:
			var key := kv[0].strip_edges()
			var value := kv[1].strip_edges()
			if value.is_valid_float():
				result[key] = float(value)
			elif value.is_valid_int():
				result[key] = int(value)

	return result


## Parse effect type string to enum
static func _effect_type_from_string(type_str: String) -> EffectType:
	match type_str.to_lower():
		"damage": return EffectType.DAMAGE
		"heal": return EffectType.HEAL
		"buff": return EffectType.BUFF
		"debuff": return EffectType.DEBUFF
		"projectile": return EffectType.PROJECTILE
		"magic_projectile": return EffectType.MAGIC_PROJECTILE
		"magic_projectile_aoe": return EffectType.MAGIC_PROJECTILE_AOE
		"summon": return EffectType.SUMMON
		"teleport": return EffectType.TELEPORT
		"aoe": return EffectType.AOE
		"self_buff": return EffectType.SELF_BUFF
		_: return EffectType.NONE


#===============================================================================
# UTILITY METHODS
#===============================================================================

## Check if this talent is active type
func is_active() -> bool:
	return type == TalentType.ACTIVE


## Check if this talent is passive type
func is_passive() -> bool:
	return type == TalentType.PASSIVE


## Check if this talent has proc/trigger data
func has_proc() -> bool:
	return not proc_trigger.is_empty() and not proc_effect.is_empty()


## Get damage at a specific point investment
func get_damage_at_points(points: int) -> float:
	return base_damage + (damage_per_point * points)


## Get effect value at a specific point investment
func get_effect_at_points(points: int) -> float:
	return effect_value + (effect_per_point * points)


## Get stat bonuses at a specific point investment
func get_stat_bonuses_at_points(points: int) -> Dictionary:
	var result: Dictionary = {}
	for stat in stat_bonuses:
		result[stat] = stat_bonuses[stat] * points
	return result


## Get description for a specific rank (0-indexed)
func get_rank_description(rank: int) -> String:
	if rank >= 0 and rank < rank_descriptions.size():
		return rank_descriptions[rank]
	return description


## Get the required row points to unlock this talent's row
## Row 1 = 0 points, Row 2 = 5 points, Row 3 = 10 points, etc.
func get_required_row_points() -> int:
	return (row - 1) * 5


## Check if this talent has prerequisites
func has_prerequisites() -> bool:
	return not prerequisite_ids.is_empty()


## Check if this talent requires a specific weapon category
func has_weapon_requirement() -> bool:
	return not required_weapon_category.is_empty()


## Check if a weapon category matches this talent's requirement
## "melee" matches both "melee_1h" and "melee_2h"
func matches_weapon_category(weapon_cat: String) -> bool:
	if required_weapon_category.is_empty():
		return true  # No requirement, any weapon works
	if weapon_cat.is_empty():
		return false  # No weapon equipped, but requirement exists

	# Exact match
	if required_weapon_category == weapon_cat:
		return true

	# "melee" matches melee_1h and melee_2h
	if required_weapon_category == "melee" and weapon_cat.begins_with("melee"):
		return true

	return false
