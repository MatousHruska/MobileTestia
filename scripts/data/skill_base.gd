extends Resource
class_name SkillBase
## SkillBase - Base class for all skills (player talents and enemy abilities)
##
## Provides shared properties and enums used by both TalentData and AbilityData.
## This unifies damage types, hitbox shapes, and common skill properties.

#===============================================================================
# SHARED ENUMS
#===============================================================================

## Damage types used by both player and enemy attacks
enum DamageType {
	PHYSICAL = 0,
	FIRE = 1,
	COLD = 2,
	LIGHTNING = 3,
	POISON = 4,
	CHAOS = 5,
	PURE = 6
}

## Hitbox shapes for melee attacks
enum HitboxShape {
	CIRCLE,   ## Radius around caster
	CONE,     ## Arc in facing direction
	LINE,     ## Narrow rectangle
	CROSS,    ## Four directional lines
	RING      ## Expanding circle
}

#===============================================================================
# CORE PROPERTIES (Shared by all skills)
#===============================================================================

## Unique identifier
@export var id: String = ""

## Display name
@export var skill_name: String = ""

## Description
@export var description: String = ""

## Damage type
@export var damage_type: DamageType = DamageType.PHYSICAL

## Cooldown in seconds
@export var cooldown: float = 0.0

## Range in pixels
@export var skill_range: float = 50.0

## Status effect to apply on hit (database ID, e.g., "status_burning")
@export var status_effect_on_hit: String = ""

#===============================================================================
# STATIC HELPERS
#===============================================================================

static func damage_type_from_string(s: String) -> DamageType:
	match s.to_lower():
		"physical": return DamageType.PHYSICAL
		"fire": return DamageType.FIRE
		"cold": return DamageType.COLD
		"lightning": return DamageType.LIGHTNING
		"poison": return DamageType.POISON
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
		DamageType.CHAOS: return "chaos"
		DamageType.PURE: return "pure"
		_: return "physical"


static func hitbox_shape_from_string(s: String) -> HitboxShape:
	match s.to_lower():
		"circle": return HitboxShape.CIRCLE
		"cone": return HitboxShape.CONE
		"line": return HitboxShape.LINE
		"cross": return HitboxShape.CROSS
		"ring": return HitboxShape.RING
		_: return HitboxShape.CIRCLE


static func hitbox_shape_to_string(s: HitboxShape) -> String:
	match s:
		HitboxShape.CIRCLE: return "circle"
		HitboxShape.CONE: return "cone"
		HitboxShape.LINE: return "line"
		HitboxShape.CROSS: return "cross"
		HitboxShape.RING: return "ring"
		_: return "circle"


## Get color for damage type (used for visual effects)
static func get_damage_type_color(damage_type: DamageType) -> Color:
	match damage_type:
		DamageType.PHYSICAL: return Color(0.9, 0.85, 0.7)   # Pale yellow
		DamageType.FIRE: return Color(1.0, 0.4, 0.1)       # Orange-red
		DamageType.COLD: return Color(0.4, 0.7, 1.0)       # Ice blue
		DamageType.LIGHTNING: return Color(1.0, 1.0, 0.3)  # Bright yellow
		DamageType.POISON: return Color(0.3, 0.8, 0.2)     # Green
		DamageType.CHAOS: return Color(0.7, 0.2, 0.9)      # Purple
		DamageType.PURE: return Color(1.0, 1.0, 1.0)       # White
		_: return Color(0.8, 0.8, 0.8)


## Get int value for damage type (for compatibility with older code)
static func damage_type_to_int(d: DamageType) -> int:
	return d as int


static func damage_type_from_int(i: int) -> DamageType:
	if i >= 0 and i <= DamageType.PURE:
		return i as DamageType
	return DamageType.PHYSICAL
