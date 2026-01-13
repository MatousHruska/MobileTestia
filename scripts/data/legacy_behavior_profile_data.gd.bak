extends Resource
class_name BehaviorProfileData
## BehaviorProfileData - Defines enemy AI behavior patterns
##
## Controls how enemies behave in various situations:
##   - Idle: What they do when no target (roam, stand, patrol)
##   - Detection: How they find targets (sight, on damage only)
##   - Combat: How they fight (aggressive, kiting, hit-and-run)
##   - Flee: When and how they flee
##   - Abilities: Which abilities to use and when

#===============================================================================
# ENUMS
#===============================================================================

enum IdleBehavior {
	STAND,    ## Stay in place
	ROAM,     ## Wander within radius
	PATROL    ## Follow patrol points
}

enum DetectionType {
	SIGHT,    ## Detect by sight range
	NONE      ## Only aggro on damage
}

enum CombatStyle {
	AGGRESSIVE,   ## Charge in and attack
	RANGED,       ## Keep distance, use ranged attacks
	OPPORTUNIST,  ## Mix of tactics, uses abilities strategically
	HIT_RUN       ## Attack then retreat
}

enum ApproachBehavior {
	DIRECT,   ## Walk straight at target
	CHARGE,   ## Rush at increased speed
	KITE,     ## Keep preferred distance
	PHASE,    ## Teleport close to target
	CIRCLE    ## Strafe around target
}

enum AbilityPriorityMode {
	HIGHEST,         ## Always use highest priority available ability
	CONDITIONAL,     ## Use abilities based on their conditions
	RANDOM_WEIGHTED  ## Random selection weighted by priority
}

#===============================================================================
# CORE PROPERTIES
#===============================================================================

@export var id: String = ""
@export var profile_name: String = "Basic"
@export var description: String = ""

#===============================================================================
# IDLE BEHAVIOR
#===============================================================================

@export_group("Idle Behavior")
@export var idle_behavior: IdleBehavior = IdleBehavior.STAND
@export var idle_roam_radius: float = 0.0
@export var idle_roam_speed_mult: float = 0.5
@export var idle_pause_min: float = 2.0
@export var idle_pause_max: float = 5.0
@export var patrol_loop: bool = true

#===============================================================================
# DETECTION & AGGRO
#===============================================================================

@export_group("Detection")
@export var detection_range: float = 150.0
@export var detection_type: DetectionType = DetectionType.SIGHT
@export var aggro_on_damage: bool = true
@export var aggro_memory_time: float = 10.0  ## How long to chase before resetting
@export var leash_range: float = 300.0  ## Max distance from home before returning

#===============================================================================
# COMBAT STYLE
#===============================================================================

@export_group("Combat")
@export var combat_style: CombatStyle = CombatStyle.AGGRESSIVE
@export var approach_behavior: ApproachBehavior = ApproachBehavior.DIRECT
@export var preferred_range: float = 30.0  ## Ideal attack distance
@export var chase_speed_mult: float = 1.0
@export var strafe_chance: float = 0.0  ## Chance to strafe while attacking

#===============================================================================
# KITE/CIRCLE BEHAVIOR
#===============================================================================

@export_group("Advanced Movement")
@export var kite_distance: float = 0.0  ## Distance to maintain when kiting
@export var kite_speed_mult: float = 1.0
@export var circle_direction: String = "random"  ## "left", "right", "random"
@export var attack_retreat_distance: float = 0.0  ## Distance to retreat after attack
@export var attack_retreat_duration: float = 0.0

#===============================================================================
# FLEE BEHAVIOR
#===============================================================================

@export_group("Flee")
@export var flee_health_threshold: float = 0.0  ## Flee below this % (0 = never)
@export var flee_speed_mult: float = 1.2

#===============================================================================
# ABILITY AI
#===============================================================================

@export_group("Abilities")
@export var ability_use_chance: float = 1.0  ## Chance to use ability vs basic attack
@export var ability_priority_mode: AbilityPriorityMode = AbilityPriorityMode.HIGHEST
@export var ability_ids: Array[String] = []  ## List of ability IDs this profile uses

#===============================================================================
# STATIC HELPERS
#===============================================================================

static func idle_from_string(s: String) -> IdleBehavior:
	match s.to_lower():
		"stand": return IdleBehavior.STAND
		"roam": return IdleBehavior.ROAM
		"patrol": return IdleBehavior.PATROL
		_: return IdleBehavior.STAND


static func detection_from_string(s: String) -> DetectionType:
	match s.to_lower():
		"sight": return DetectionType.SIGHT
		"none": return DetectionType.NONE
		_: return DetectionType.SIGHT


static func combat_from_string(s: String) -> CombatStyle:
	match s.to_lower():
		"aggressive": return CombatStyle.AGGRESSIVE
		"ranged": return CombatStyle.RANGED
		"opportunist": return CombatStyle.OPPORTUNIST
		"hit_run": return CombatStyle.HIT_RUN
		_: return CombatStyle.AGGRESSIVE


static func approach_from_string(s: String) -> ApproachBehavior:
	match s.to_lower():
		"direct": return ApproachBehavior.DIRECT
		"charge": return ApproachBehavior.CHARGE
		"kite": return ApproachBehavior.KITE
		"phase": return ApproachBehavior.PHASE
		"circle": return ApproachBehavior.CIRCLE
		_: return ApproachBehavior.DIRECT


static func priority_mode_from_string(s: String) -> AbilityPriorityMode:
	match s.to_lower():
		"highest": return AbilityPriorityMode.HIGHEST
		"conditional": return AbilityPriorityMode.CONDITIONAL
		"random_weighted": return AbilityPriorityMode.RANDOM_WEIGHTED
		_: return AbilityPriorityMode.HIGHEST


static func idle_to_string(i: IdleBehavior) -> String:
	match i:
		IdleBehavior.STAND: return "stand"
		IdleBehavior.ROAM: return "roam"
		IdleBehavior.PATROL: return "patrol"
		_: return "stand"


static func combat_to_string(c: CombatStyle) -> String:
	match c:
		CombatStyle.AGGRESSIVE: return "aggressive"
		CombatStyle.RANGED: return "ranged"
		CombatStyle.OPPORTUNIST: return "opportunist"
		CombatStyle.HIT_RUN: return "hit_run"
		_: return "aggressive"


static func approach_to_string(a: ApproachBehavior) -> String:
	match a:
		ApproachBehavior.DIRECT: return "direct"
		ApproachBehavior.CHARGE: return "charge"
		ApproachBehavior.KITE: return "kite"
		ApproachBehavior.PHASE: return "phase"
		ApproachBehavior.CIRCLE: return "circle"
		_: return "direct"


#===============================================================================
# BEHAVIOR QUERIES
#===============================================================================

func should_detect_by_sight() -> bool:
	return detection_type == DetectionType.SIGHT and detection_range > 0


func should_flee(health_percent: float) -> bool:
	return flee_health_threshold > 0 and health_percent < flee_health_threshold


func wants_to_kite() -> bool:
	return approach_behavior == ApproachBehavior.KITE or combat_style == CombatStyle.RANGED


func wants_to_circle() -> bool:
	return approach_behavior == ApproachBehavior.CIRCLE or combat_style == CombatStyle.HIT_RUN


func get_circle_dir() -> int:
	## Returns 1 for clockwise, -1 for counter-clockwise
	match circle_direction.to_lower():
		"left": return -1
		"right": return 1
		_: return [-1, 1].pick_random()


#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
	return {
		"id": id,
		"name": profile_name,
		"idle": idle_to_string(idle_behavior),
		"combat": combat_to_string(combat_style),
		"approach": approach_to_string(approach_behavior),
		"detection_range": detection_range,
		"preferred_range": preferred_range,
		"flee_threshold": flee_health_threshold,
		"abilities": ability_ids
	}
