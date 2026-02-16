extends Resource
class_name AbilityData
## AbilityData - Defines an enemy ability with hitbox, timing, and effects
##
## Ability types:
##   - melee: Close-range attack with immediate hitbox
##   - dash_attack: Rush at target, dealing damage on impact
##   - aoe: Area of effect damage around self
##   - projectile: Fires a projectile toward target
##   - pattern: Multi-directional attack pattern (cross, etc.)
##   - teleport_attack: Teleport to target and strike
##   - beam: Sweeping line attack
##
## Hitbox shapes:
##   - circle: Radial area (default)
##   - cone: Arc in facing direction
##   - line: Narrow line attack
##   - cross: Four-directional pattern
##   - ring: Expanding ring around caster

#===============================================================================
# ENUMS
#===============================================================================

enum AbilityType {
	MELEE,
	DASH_ATTACK,
	AOE,
	PROJECTILE,
	PATTERN,
	TELEPORT_ATTACK,
	BEAM
}

enum HitboxShape {
	CIRCLE,
	CONE,
	LINE,
	CROSS,
	RING
}

## DamageType moved to CombatTypes (shared with TalentData)
const DamageType = CombatTypes.DamageType

#===============================================================================
# CORE PROPERTIES
#===============================================================================

@export var id: String = ""
@export var ability_name: String = "Attack"
@export var description: String = ""

#===============================================================================
# ABILITY TYPE & DAMAGE
#===============================================================================

@export var type: AbilityType = AbilityType.MELEE
@export var damage_mult: float = 1.0
@export var damage_type: DamageType = DamageType.PHYSICAL

#===============================================================================
# RANGE & TARGETING
#===============================================================================

@export var cooldown: float = 0.0
@export var range_min: float = 0.0
@export var range_max: float = 30.0

#===============================================================================
# HITBOX
#===============================================================================

@export var shape: HitboxShape = HitboxShape.CIRCLE
@export var shape_size: float = 25.0  ## Radius for circle, length for line/cone
@export var shape_angle: float = 0.0  ## Arc angle for cone, rotation for pattern

#===============================================================================
# TIMING
#===============================================================================

@export var windup: float = 0.2  ## Time before damage is dealt
@export var recovery: float = 0.3  ## Time after attack before next action

#===============================================================================
# ANIMATION & VISUALS
#===============================================================================

@export var animation: String = "attack"

## Visual template override (empty = auto-detect from ability type)
@export var visual_type: String = ""

#===============================================================================
# AI PRIORITY
#===============================================================================

@export var priority: int = 1  ## Higher = AI prefers this ability

#===============================================================================
# CONDITIONS
#===============================================================================

## Conditions for when this ability can be used
## Format: "condition1;condition2" where conditions are:
##   distance>X, distance<X - Target distance check
##   health>X%, health<X% - Self health percent check
##   target_health>X%, target_health<X% - Target health check
@export var conditions: String = ""

#===============================================================================
# EFFECTS
#===============================================================================

## Effects applied on hit
## Format: "effect1;effect2" where effects are:
##   stun:duration - Stuns target
##   knockback:force - Knocks target back
##   burn:duration:damage - Burns target over time
##   slow:duration:percent - Slows target movement
##   lifesteal:percent - Heals caster for % of damage
##   bleed:duration:damage - Bleeds target over time
@export var effects_on_hit: String = ""

#===============================================================================
# MOVEMENT (for dash/teleport abilities)
#===============================================================================

@export var projectile_speed: float = 0.0  ## For projectile abilities
@export var dash_speed: float = 0.0  ## For dash abilities

#===============================================================================
# DIRECTIONAL CONSTRAINTS
#===============================================================================

## If true, attack direction snaps to 4 cardinal directions (up/down/left/right)
## If false, attack can be aimed in any direction including diagonals
@export var cardinal_only: bool = true

#===============================================================================
# AOE EXPLOSION SETTINGS
#===============================================================================

## Damage falloff % at AOE edge (30 = 70% damage at edge, 0 = no falloff)
@export var explosion_falloff: float = 30.0

#===============================================================================
# STATIC HELPERS
#===============================================================================

static func type_from_string(s: String) -> AbilityType:
	match s.to_lower():
		"melee": return AbilityType.MELEE
		"dash_attack": return AbilityType.DASH_ATTACK
		"aoe": return AbilityType.AOE
		"projectile": return AbilityType.PROJECTILE
		"pattern": return AbilityType.PATTERN
		"teleport_attack": return AbilityType.TELEPORT_ATTACK
		"beam": return AbilityType.BEAM
		_: return AbilityType.MELEE


static func shape_from_string(s: String) -> HitboxShape:
	match s.to_lower():
		"circle": return HitboxShape.CIRCLE
		"cone": return HitboxShape.CONE
		"line": return HitboxShape.LINE
		"cross": return HitboxShape.CROSS
		"ring": return HitboxShape.RING
		_: return HitboxShape.CIRCLE


static func damage_type_from_string(s: String) -> CombatTypes.DamageType:
	return CombatTypes.damage_type_from_string(s)


static func type_to_string(t: AbilityType) -> String:
	match t:
		AbilityType.MELEE: return "melee"
		AbilityType.DASH_ATTACK: return "dash_attack"
		AbilityType.AOE: return "aoe"
		AbilityType.PROJECTILE: return "projectile"
		AbilityType.PATTERN: return "pattern"
		AbilityType.TELEPORT_ATTACK: return "teleport_attack"
		AbilityType.BEAM: return "beam"
		_: return "melee"


static func shape_to_string(s: HitboxShape) -> String:
	match s:
		HitboxShape.CIRCLE: return "circle"
		HitboxShape.CONE: return "cone"
		HitboxShape.LINE: return "line"
		HitboxShape.CROSS: return "cross"
		HitboxShape.RING: return "ring"
		_: return "circle"


static func damage_type_to_string(d: CombatTypes.DamageType) -> String:
	return CombatTypes.damage_type_to_string(d)


static func snap_to_cardinal(direction: Vector2) -> Vector2:
	## Snap a direction vector to the nearest cardinal direction (up/down/left/right)
	if direction.is_zero_approx():
		return Vector2.RIGHT

	# Find which cardinal is closest based on the dominant axis
	if absf(direction.x) >= absf(direction.y):
		# Horizontal dominant
		return Vector2.RIGHT if direction.x >= 0 else Vector2.LEFT
	else:
		# Vertical dominant
		return Vector2.DOWN if direction.y >= 0 else Vector2.UP


static func get_cardinal_alignment_axis(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	## Get which axis to move along to align with target for cardinal attack
	## Returns the perpendicular movement direction to align, or Vector2.ZERO if aligned
	var diff := to_pos - from_pos
	var tolerance := 16.0  # Pixels tolerance for "aligned"

	# Check if already aligned on one axis
	if absf(diff.x) <= tolerance:
		return Vector2.ZERO  # Aligned vertically
	if absf(diff.y) <= tolerance:
		return Vector2.ZERO  # Aligned horizontally

	# Pick axis with shorter distance to align (move perpendicular to attack direction)
	if absf(diff.x) < absf(diff.y):
		# Closer to vertical alignment - move horizontally to match X
		return Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
	else:
		# Closer to horizontal alignment - move vertically to match Y
		return Vector2.DOWN if diff.y > 0 else Vector2.UP


static func is_cardinally_aligned(from_pos: Vector2, to_pos: Vector2, tolerance: float = 16.0) -> bool:
	## Check if two positions are aligned on either X or Y axis
	var diff := to_pos - from_pos
	return absf(diff.x) <= tolerance or absf(diff.y) <= tolerance


#===============================================================================
# CONDITION PARSING
#===============================================================================

func check_conditions(caster: Node2D, target: Node2D) -> bool:
	## Check if all conditions are met for this ability
	if conditions.is_empty():
		return true

	var condition_list := conditions.split(";")
	for condition in condition_list:
		condition = condition.strip_edges()
		if condition.is_empty():
			continue
		if not _check_single_condition(condition, caster, target):
			return false

	return true


func _check_single_condition(condition: String, caster: Node2D, target: Node2D) -> bool:
	## Check a single condition string

	# Distance checks
	if condition.begins_with("distance"):
		var distance := caster.global_position.distance_to(target.global_position)
		if condition.contains(">"):
			var threshold := float(condition.get_slice(">", 1))
			return distance > threshold
		elif condition.contains("<"):
			var threshold := float(condition.get_slice("<", 1))
			return distance < threshold

	# Self health checks
	if condition.begins_with("health"):
		var health_percent := _get_health_percent(caster)
		if condition.contains(">"):
			var threshold := float(condition.get_slice(">", 1).replace("%", ""))
			return health_percent > threshold
		elif condition.contains("<"):
			var threshold := float(condition.get_slice("<", 1).replace("%", ""))
			return health_percent < threshold

	# Target health checks
	if condition.begins_with("target_health"):
		var health_percent := _get_health_percent(target)
		if condition.contains(">"):
			var threshold := float(condition.get_slice(">", 1).replace("%", ""))
			return health_percent > threshold
		elif condition.contains("<"):
			var threshold := float(condition.get_slice("<", 1).replace("%", ""))
			return health_percent < threshold

	return true


func _get_health_percent(node: Node2D) -> float:
	if node.has_method("get_health_percent"):
		return node.get_health_percent() * 100.0
	if "current_health" in node and "max_health" in node:
		if node.max_health > 0:
			return (float(node.current_health) / float(node.max_health)) * 100.0
	return 100.0


#===============================================================================
# EFFECT PARSING
#===============================================================================

func get_parsed_effects() -> Array[Dictionary]:
	## Parse effects_on_hit string into array of effect dictionaries
	var result: Array[Dictionary] = []
	if effects_on_hit.is_empty():
		return result

	var effect_list := effects_on_hit.split(";")
	for effect_str in effect_list:
		effect_str = effect_str.strip_edges()
		if effect_str.is_empty():
			continue

		var parsed := _parse_single_effect(effect_str)
		if not parsed.is_empty():
			result.append(parsed)

	return result


func _parse_single_effect(effect_str: String) -> Dictionary:
	var parts := effect_str.split(":")
	if parts.is_empty():
		return {}

	var effect_type := parts[0].to_lower()
	var result := {"type": effect_type}

	match effect_type:
		"stun":
			result["duration"] = float(parts[1]) if parts.size() > 1 else 1.0
		"knockback":
			result["force"] = float(parts[1]) if parts.size() > 1 else 100.0
		"burn", "bleed", "rot", "poison":
			result["duration"] = float(parts[1]) if parts.size() > 1 else 3.0
			result["damage"] = float(parts[2]) if parts.size() > 2 else 5.0
		"slow":
			result["duration"] = float(parts[1]) if parts.size() > 1 else 2.0
			result["percent"] = float(parts[2].replace("%", "")) if parts.size() > 2 else 30.0
		"lifesteal":
			result["percent"] = float(parts[1].replace("%", "")) if parts.size() > 1 else 50.0

	return result


#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	return {
		"id": id,
		"name": ability_name,
		"type": type_to_string(type),
		"damage_mult": damage_mult,
		"range": "%d-%d" % [range_min, range_max],
		"shape": shape_to_string(shape),
		"cooldown": cooldown,
		"priority": priority
	}
