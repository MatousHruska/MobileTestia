extends RefCounted
class_name CombatTypes
## CombatTypes - Shared enums for combat systems (player talents & enemy abilities)
##
## Centralizes damage types and other combat-related enums to avoid duplication
## between TalentData (player skills) and AbilityData (enemy abilities).

#===============================================================================
# DAMAGE TYPES
#===============================================================================

## All damage types used by both player and enemy attacks
enum DamageType {
	PHYSICAL,    # 0 - Standard physical damage
	FIRE,        # 1 - Fire/burn damage
	COLD,        # 2 - Ice/frost damage
	LIGHTNING,   # 3 - Electric damage
	POISON,      # 4 - Poison/toxic damage
	ARCANE,      # 5 - Pure magical damage
	HOLY,        # 6 - Divine/light damage
	SHADOW,      # 7 - Dark/necrotic damage
	BLEED,       # 8 - Physical bleeding (uses physical color)
	NATURE,      # 9 - Nature/druid damage (uses poison color)
	CHAOS,       # 10 - Chaotic/void damage
	PURE         # 11 - Ignores all resistances
}

#===============================================================================
# STRING CONVERSION
#===============================================================================

static func damage_type_from_string(s: String) -> DamageType:
	match s.to_lower():
		"physical": return DamageType.PHYSICAL
		"fire": return DamageType.FIRE
		"cold": return DamageType.COLD
		"lightning": return DamageType.LIGHTNING
		"poison": return DamageType.POISON
		"arcane": return DamageType.ARCANE
		"holy": return DamageType.HOLY
		"shadow": return DamageType.SHADOW
		"bleed": return DamageType.BLEED
		"nature": return DamageType.NATURE
		"chaos": return DamageType.CHAOS
		"pure": return DamageType.PURE
		_: return DamageType.PHYSICAL


static func damage_type_to_string(d: DamageType) -> String:
	match d:
		DamageType.PHYSICAL: return "physical"
		DamageType.FIRE: return "fire"
		DamageType.COLD: return "cold"
		DamageType.LIGHTNING: return "lightning"
		DamageType.POISON: return "poison"
		DamageType.ARCANE: return "arcane"
		DamageType.HOLY: return "holy"
		DamageType.SHADOW: return "shadow"
		DamageType.BLEED: return "bleed"
		DamageType.NATURE: return "nature"
		DamageType.CHAOS: return "chaos"
		DamageType.PURE: return "pure"
		_: return "physical"


#===============================================================================
# VISUAL HELPERS
#===============================================================================

## Get visual color string for damage type (used by HitboxVisual, etc.)
## Some types share colors for visual consistency
static func get_visual_type(d: DamageType) -> String:
	match d:
		DamageType.BLEED: return "physical"  # Bleed uses physical color
		DamageType.NATURE: return "poison"   # Nature uses poison color
		DamageType.CHAOS: return "shadow"    # Chaos uses shadow color
		_: return damage_type_to_string(d)
