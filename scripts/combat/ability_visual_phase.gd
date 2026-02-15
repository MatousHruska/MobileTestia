class_name AbilityVisualPhase
extends Resource
## AbilityVisualPhase - Defines a single phase in an ability visual sequence.
##
## Each phase describes one visual beat: a body animation, movement tween,
## damage event, projectile spawn, VFX effect, etc. Phases execute in order
## and can run concurrently with the next phase when concurrent = true.

## Phase type determines behavior
enum PhaseType {
	BODY_ANIM,       ## Play a body animation (e.g., "melee_windup", "cast")
	MOVEMENT,        ## Tween-based movement (lunge, dash, jump_back)
	DAMAGE_EVENT,    ## Signal to apply damage (hitbox check happens externally)
	SPAWN_PROJECTILE,## Signal to spawn a projectile
	WAIT,            ## Pure wait/delay
	WEAPON_VISIBILITY, ## Show/hide weapon layer
	EFFECT,          ## Spawn/trigger a VFX on the effect anchor
}

## What this phase does
@export var type: PhaseType = PhaseType.BODY_ANIM

## Duration in seconds (0 = instant, plays alongside next phase)
## For BODY_ANIM: 0 means "use animation length"
@export var duration: float = 0.0

## --- BODY_ANIM properties ---
## Animation action name (without direction suffix). e.g., "melee_windup"
## The system appends "_{down/up/right}" automatically based on facing.
## Falls back to "attack_{dir}" if the specific animation doesn't exist.
@export var anim_name: String = ""

## --- MOVEMENT properties ---
## Movement direction relative to facing:
##   "toward_target" = lunge toward current target
##   "away_from_target" = jump backward
##   "facing" = move in facing direction
@export var move_direction: String = "toward_target"

## Movement distance in pixels
@export var move_distance: float = 0.0

## --- WEAPON_VISIBILITY ---
@export var weapon_visible: bool = true

## --- EFFECT ---
## Effect identifier (looked up from a registry or spawned by name)
@export var effect_id: String = ""

## --- Timing ---
## If true, this phase runs concurrently with the next phase
## (useful for playing animation + movement at the same time)
@export var concurrent: bool = false

## Override key - if set, play() overrides can patch this phase's duration/distance
## e.g., "windup", "lunge", "recovery", "cast", "charge", "dash"
@export var override_key: String = ""


#===============================================================================
# FACTORY HELPERS
#===============================================================================

static func create_body_anim(anim: String, dur: float = 0.0, key: String = "", is_concurrent: bool = false) -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.BODY_ANIM
	phase.anim_name = anim
	phase.duration = dur
	phase.override_key = key
	phase.concurrent = is_concurrent
	return phase


static func create_movement(dir: String, dist: float, dur: float, key: String = "", is_concurrent: bool = false) -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.MOVEMENT
	phase.move_direction = dir
	phase.move_distance = dist
	phase.duration = dur
	phase.override_key = key
	phase.concurrent = is_concurrent
	return phase


static func create_damage_event() -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.DAMAGE_EVENT
	return phase


static func create_spawn_projectile() -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.SPAWN_PROJECTILE
	return phase


static func create_wait(dur: float, key: String = "") -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.WAIT
	phase.duration = dur
	phase.override_key = key
	return phase


static func create_weapon_visibility(visible: bool) -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.WEAPON_VISIBILITY
	phase.weapon_visible = visible
	return phase


static func create_effect(id: String, dur: float = 0.0, is_concurrent: bool = false) -> AbilityVisualPhase:
	var phase := AbilityVisualPhase.new()
	phase.type = PhaseType.EFFECT
	phase.effect_id = id
	phase.duration = dur
	phase.concurrent = is_concurrent
	return phase
