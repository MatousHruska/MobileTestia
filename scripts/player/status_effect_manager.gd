extends Node
class_name StatusEffectManager
## StatusEffectManager - Handles status effects (DoTs, buffs, debuffs) on the player
## Persists across zone changes via PersistenceManager

## Signals
signal effect_applied(effect_type: String, duration: float, show_in_hud: bool)
signal effect_removed(effect_type: String)
signal effect_tick(effect_type: String, damage: float)

## Active effects - key: effect_type, value: effect data
var _active_effects: Dictionary = {}


func _ready() -> void:
	# Load persisted effects from previous zone/session
	_load_persisted_effects()


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

		# Check for tick (DoT effects only)
		if effect.get("damage_per_tick", 0.0) > 0 and effect.tick_timer <= 0:
			_do_effect_tick(effect_type, effect)
			effect.tick_timer = effect.tick_interval

		# Check for expiration (duration <= 0 means permanent)
		if effect.max_duration > 0 and effect.remaining_duration <= 0:
			expired_effects.append(effect_type)

	# Remove expired effects
	for effect_type in expired_effects:
		_remove_effect(effect_type)

	# Persist after processing (throttled - only if changes occurred)
	if not expired_effects.is_empty():
		_save_persisted_effects()


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
		_save_persisted_effects()
		Debug.log("StatusEffect", "Effect expired", effect_type)


#===============================================================================
# APPLY EFFECTS
#===============================================================================

## Apply a DoT effect
## Format: apply_dot("rot", 5.0, 3.0) = rot for 5 seconds, 3 damage per tick
func apply_dot(effect_type: String, duration: float, damage_per_tick: float, tick_interval: float = 1.0) -> void:
	var show_in_hud := _get_show_in_hud(effect_type)

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
			"max_duration": duration,
			"damage_per_tick": damage_per_tick,
			"tick_interval": tick_interval,
			"tick_timer": tick_interval,
			"is_debuff": true,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud)
		Debug.log("StatusEffect", "DoT applied", {
			"type": effect_type,
			"duration": duration,
			"damage": damage_per_tick,
			"interval": tick_interval
		})

	_save_persisted_effects()


## Apply a buff effect (positive, no damage)
func apply_buff(effect_type: String, duration: float) -> void:
	var show_in_hud := _get_show_in_hud(effect_type)

	if effect_type in _active_effects:
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
	else:
		_active_effects[effect_type] = {
			"remaining_duration": duration,
			"max_duration": duration,
			"damage_per_tick": 0.0,
			"tick_interval": 1.0,
			"tick_timer": 1.0,
			"is_debuff": false,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud)
		Debug.log("StatusEffect", "Buff applied", {
			"type": effect_type,
			"duration": duration
		})

	_save_persisted_effects()


## Apply a permanent effect (duration = 0 means never expires)
func apply_permanent(effect_type: String, is_debuff: bool = false) -> void:
	var show_in_hud := _get_show_in_hud(effect_type)

	if effect_type not in _active_effects:
		_active_effects[effect_type] = {
			"remaining_duration": 0.0,
			"max_duration": 0.0,  # 0 = permanent
			"damage_per_tick": 0.0,
			"tick_interval": 1.0,
			"tick_timer": 1.0,
			"is_debuff": is_debuff,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, 0.0, show_in_hud)
		Debug.log("StatusEffect", "Permanent effect applied", effect_type)
		_save_persisted_effects()


#===============================================================================
# QUERIES
#===============================================================================

## Check if an effect is active
func has_effect(effect_type: String) -> bool:
	return effect_type in _active_effects


## Get remaining duration of an effect
func get_remaining_duration(effect_type: String) -> float:
	if effect_type in _active_effects:
		return _active_effects[effect_type].remaining_duration
	return 0.0


## Get all active effect types
func get_active_effects() -> Array[String]:
	var result: Array[String] = []
	for key in _active_effects.keys():
		result.append(key)
	return result


## Get full effect data (for Stats tab display)
func get_all_effect_data() -> Dictionary:
	return _active_effects.duplicate(true)


## Get only effects that should show in HUD
func get_hud_visible_effects() -> Dictionary:
	var result: Dictionary = {}
	for effect_type in _active_effects:
		var effect: Dictionary = _active_effects[effect_type]
		if effect.get("show_in_hud", true):
			result[effect_type] = effect.duplicate()
	return result


#===============================================================================
# CLEAR EFFECTS
#===============================================================================

## Clear a specific effect
func clear_effect(effect_type: String) -> void:
	_remove_effect(effect_type)


## Clear all effects
func clear_all_effects() -> void:
	for effect_type in _active_effects.keys():
		effect_removed.emit(effect_type)
	_active_effects.clear()
	_save_persisted_effects()
	Debug.log("StatusEffect", "All effects cleared")


#===============================================================================
# PERSISTENCE
#===============================================================================

func _load_persisted_effects() -> void:
	var persisted := Persistence.load_status_effects()
	if persisted.is_empty():
		return

	for effect_type in persisted:
		var effect_data: Dictionary = persisted[effect_type]
		_active_effects[effect_type] = effect_data.duplicate()
		# Emit signal for UI to pick up
		var show_in_hud: bool = effect_data.get("show_in_hud", true)
		effect_applied.emit(effect_type, effect_data.remaining_duration, show_in_hud)

	Debug.log("StatusEffect", "Loaded persisted effects", persisted.keys())


func _save_persisted_effects() -> void:
	Persistence.save_status_effects(_active_effects.duplicate(true))


## Check database for show_in_hud flag
func _get_show_in_hud(effect_type: String) -> bool:
	# Look up in database - effect_type maps to status_id like "status_rot" for "rot"
	var status_id := "status_" + effect_type
	if Database.status_effects.has(status_id):
		return Database.status_effects[status_id].get("show_in_hud", true)
	return true  # Default to showing in HUD
