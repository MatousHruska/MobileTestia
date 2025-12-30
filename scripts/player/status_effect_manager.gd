extends Node
class_name StatusEffectManager
## StatusEffectManager - Handles status effects (DoTs, buffs, debuffs) on the player

## Signals
signal effect_applied(effect_type: String, duration: float)
signal effect_removed(effect_type: String)
signal effect_tick(effect_type: String, damage: float)

## Active effects - key: effect_type, value: effect data
var _active_effects: Dictionary = {}


func _process(delta: float) -> void:
	if not Game.is_playing:
		return

	_process_effects(delta)


func _process_effects(delta: float) -> void:
	var expired_effects: Array[String] = []

	for effect_type in _active_effects.keys():
		var effect: Dictionary = _active_effects[effect_type]

		# Update timers
		effect.remaining_duration -= delta
		effect.tick_timer -= delta

		# Check for tick
		if effect.tick_timer <= 0:
			_do_effect_tick(effect_type, effect)
			effect.tick_timer = effect.tick_interval

		# Check for expiration
		if effect.remaining_duration <= 0:
			expired_effects.append(effect_type)

	# Remove expired effects
	for effect_type in expired_effects:
		_remove_effect(effect_type)


func _do_effect_tick(effect_type: String, effect: Dictionary) -> void:
	var damage := effect.damage_per_tick as float

	# Apply damage through PlayerStats
	PlayerStats.damage(damage)
	effect_tick.emit(effect_type, damage)

	Debug.log("StatusEffect", "DoT tick", {
		"type": effect_type,
		"damage": damage,
		"remaining": effect.remaining_duration
	})


func _remove_effect(effect_type: String) -> void:
	if effect_type in _active_effects:
		_active_effects.erase(effect_type)
		effect_removed.emit(effect_type)
		Debug.log("StatusEffect", "Effect expired", effect_type)


## Apply a DoT effect
## Format: apply_dot("rot", 5.0, 3.0) = rot for 5 seconds, 3 damage per tick (1 second intervals)
func apply_dot(effect_type: String, duration: float, damage_per_tick: float, tick_interval: float = 1.0) -> void:
	if effect_type in _active_effects:
		# Refresh duration if already active (don't stack damage)
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
		Debug.log("StatusEffect", "DoT refreshed", {
			"type": effect_type,
			"duration": existing.remaining_duration
		})
	else:
		# Apply new effect
		_active_effects[effect_type] = {
			"remaining_duration": duration,
			"damage_per_tick": damage_per_tick,
			"tick_interval": tick_interval,
			"tick_timer": tick_interval  # First tick after interval
		}
		effect_applied.emit(effect_type, duration)
		Debug.log("StatusEffect", "DoT applied", {
			"type": effect_type,
			"duration": duration,
			"damage": damage_per_tick,
			"interval": tick_interval
		})


## Check if an effect is active
func has_effect(effect_type: String) -> bool:
	return effect_type in _active_effects


## Get remaining duration of an effect
func get_remaining_duration(effect_type: String) -> float:
	if effect_type in _active_effects:
		return _active_effects[effect_type].remaining_duration
	return 0.0


## Clear a specific effect
func clear_effect(effect_type: String) -> void:
	_remove_effect(effect_type)


## Clear all effects
func clear_all_effects() -> void:
	for effect_type in _active_effects.keys():
		effect_removed.emit(effect_type)
	_active_effects.clear()
	Debug.log("StatusEffect", "All effects cleared")


## Get all active effect types
func get_active_effects() -> Array[String]:
	var result: Array[String] = []
	for key in _active_effects.keys():
		result.append(key)
	return result
