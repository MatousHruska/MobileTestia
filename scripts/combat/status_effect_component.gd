extends Node
class_name StatusEffectComponent
## StatusEffectComponent - Base class for status effect handling
##
## Used by both PlayerController (via StatusEffectManager) and EnemyNPC
## Provides consistent DoT/HoT/buff/debuff handling across all entities

## Signals
signal effect_applied(effect_type: String, duration: float, show_in_hud: bool, is_debuff: bool)
signal effect_removed(effect_type: String)
signal effect_tick(effect_type: String, damage: float)
signal heal_tick(effect_type: String, heal_amount: float)

## Active effects - key: effect_type, value: effect data
var _active_effects: Dictionary = {}

## Owner reference (set by parent)
var _owner: Node2D = null

#===============================================================================
# INITIALIZATION
#===============================================================================

func setup(effect_owner: Node2D) -> void:
	_owner = effect_owner


#===============================================================================
# PROCESSING
#===============================================================================

func process_effects(delta: float) -> void:
	var expired_effects: Array[String] = []

	for effect_type in _active_effects.keys():
		var effect: Dictionary = _active_effects[effect_type]

		# Update timers
		effect.remaining_duration -= delta
		effect.tick_timer -= delta

		# Check for tick (DoT/HoT effects)
		if effect.tick_timer <= 0:
			if effect.get("damage_per_tick", 0.0) > 0:
				_do_damage_tick(effect_type, effect)
				effect.tick_timer = effect.tick_interval
			elif effect.get("heal_per_tick", 0.0) > 0:
				_do_heal_tick(effect_type, effect)
				effect.tick_timer = effect.tick_interval

		# Check for expiration (duration <= 0 means permanent)
		if effect.max_duration > 0 and effect.remaining_duration <= 0:
			expired_effects.append(effect_type)

	# Remove expired effects
	for effect_type in expired_effects:
		_remove_effect(effect_type)


func _do_damage_tick(effect_type: String, effect: Dictionary) -> void:
	var damage := effect.damage_per_tick as float
	_apply_damage_to_owner(damage)
	effect_tick.emit(effect_type, damage)

	Debug.log("StatusEffect", "DoT tick", {
		"owner": _owner.name if _owner else "unknown",
		"type": effect_type,
		"damage": damage,
		"remaining": effect.remaining_duration
	})


func _do_heal_tick(effect_type: String, effect: Dictionary) -> void:
	var heal_amount := effect.heal_per_tick as float
	_apply_heal_to_owner(heal_amount)
	heal_tick.emit(effect_type, heal_amount)

	Debug.log("StatusEffect", "HoT tick", {
		"owner": _owner.name if _owner else "unknown",
		"type": effect_type,
		"heal": heal_amount,
		"remaining": effect.remaining_duration
	})


## Override in subclass to apply damage to the owner
func _apply_damage_to_owner(damage: float) -> void:
	if _owner and _owner.has_method("take_effect_damage"):
		_owner.take_effect_damage(damage)
	elif _owner and "current_health" in _owner:
		_owner.current_health -= damage


## Override in subclass to apply healing to the owner
func _apply_heal_to_owner(heal_amount: float) -> void:
	if _owner and _owner.has_method("heal"):
		_owner.heal(heal_amount)
	elif _owner and "current_health" in _owner and "max_health" in _owner:
		_owner.current_health = minf(_owner.current_health + heal_amount, _owner.max_health)


func _remove_effect(effect_type: String) -> void:
	if effect_type in _active_effects:
		_active_effects.erase(effect_type)
		effect_removed.emit(effect_type)
		_on_effect_removed(effect_type)
		Debug.log("StatusEffect", "Effect expired", effect_type)


## Override for cleanup (e.g., removing visuals)
func _on_effect_removed(_effect_type: String) -> void:
	pass


#===============================================================================
# APPLY EFFECTS
#===============================================================================

## Apply a DoT effect
func apply_dot(effect_type: String, duration: float, damage_per_tick: float, tick_interval: float = 1.0, show_in_hud: bool = true) -> void:
	if effect_type in _active_effects:
		# Refresh duration if already active (don't stack damage)
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
		# Emit signal so HUD can refresh display
		effect_applied.emit(effect_type, existing.remaining_duration, show_in_hud, true)
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
			"heal_per_tick": 0.0,
			"tick_interval": tick_interval,
			"tick_timer": tick_interval,
			"is_debuff": true,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud, true)
		_on_effect_applied(effect_type, true)
		Debug.log("StatusEffect", "DoT applied", {
			"type": effect_type,
			"duration": duration,
			"damage": damage_per_tick,
			"interval": tick_interval
		})


## Apply a HoT (Heal over Time) effect
func apply_hot(effect_type: String, duration: float, heal_per_tick: float, tick_interval: float = 1.0, show_in_hud: bool = true) -> void:
	if effect_type in _active_effects:
		# Refresh duration if already active (don't stack healing)
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
		# Emit signal so HUD can refresh display
		effect_applied.emit(effect_type, existing.remaining_duration, show_in_hud, false)
		Debug.log("StatusEffect", "HoT refreshed", {
			"type": effect_type,
			"duration": existing.remaining_duration
		})
	else:
		# Apply new effect
		_active_effects[effect_type] = {
			"remaining_duration": duration,
			"max_duration": duration,
			"damage_per_tick": 0.0,
			"heal_per_tick": heal_per_tick,
			"tick_interval": tick_interval,
			"tick_timer": tick_interval,
			"is_debuff": false,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud, false)
		_on_effect_applied(effect_type, false)
		Debug.log("StatusEffect", "HoT applied", {
			"type": effect_type,
			"duration": duration,
			"heal": heal_per_tick,
			"interval": tick_interval
		})


## Apply a buff effect (positive, no tick damage/heal)
func apply_buff(effect_type: String, duration: float, show_in_hud: bool = true) -> void:
	if effect_type in _active_effects:
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
		# Emit signal so HUD can refresh display
		effect_applied.emit(effect_type, existing.remaining_duration, show_in_hud, false)
	else:
		_active_effects[effect_type] = {
			"remaining_duration": duration,
			"max_duration": duration,
			"damage_per_tick": 0.0,
			"heal_per_tick": 0.0,
			"tick_interval": 1.0,
			"tick_timer": 1.0,
			"is_debuff": false,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud, false)
		_on_effect_applied(effect_type, false)
		Debug.log("StatusEffect", "Buff applied", {
			"type": effect_type,
			"duration": duration
		})


## Apply a debuff effect (negative, no tick damage)
func apply_debuff(effect_type: String, duration: float, show_in_hud: bool = true) -> void:
	if effect_type in _active_effects:
		var existing: Dictionary = _active_effects[effect_type]
		existing.remaining_duration = maxf(existing.remaining_duration, duration)
		# Emit signal so HUD can refresh display
		effect_applied.emit(effect_type, existing.remaining_duration, show_in_hud, true)
	else:
		_active_effects[effect_type] = {
			"remaining_duration": duration,
			"max_duration": duration,
			"damage_per_tick": 0.0,
			"heal_per_tick": 0.0,
			"tick_interval": 1.0,
			"tick_timer": 1.0,
			"is_debuff": true,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, duration, show_in_hud, true)
		_on_effect_applied(effect_type, true)
		Debug.log("StatusEffect", "Debuff applied", {
			"type": effect_type,
			"duration": duration
		})


## Apply a permanent effect (never expires)
func apply_permanent(effect_type: String, is_debuff: bool = false, show_in_hud: bool = true) -> void:
	if effect_type not in _active_effects:
		_active_effects[effect_type] = {
			"remaining_duration": 0.0,
			"max_duration": 0.0,  # 0 = permanent
			"damage_per_tick": 0.0,
			"heal_per_tick": 0.0,
			"tick_interval": 1.0,
			"tick_timer": 1.0,
			"is_debuff": is_debuff,
			"show_in_hud": show_in_hud
		}
		effect_applied.emit(effect_type, 0.0, show_in_hud, is_debuff)
		_on_effect_applied(effect_type, is_debuff)
		Debug.log("StatusEffect", "Permanent effect applied", effect_type)


## Apply status effect from database by ID
func apply_status_effect(effect_id: String) -> void:
	if not DatabaseLoader.status_effects.has(effect_id):
		Debug.warn("StatusEffect", "Unknown status effect: %s" % effect_id)
		return

	var effect_data: Dictionary = DatabaseLoader.status_effects[effect_id]
	var effect_type: String = effect_data.get("type", "")
	var duration: float = effect_data.get("duration", 0.0)
	var value: float = effect_data.get("value", 0.0)
	var tick_interval: float = effect_data.get("tick_interval", 1.0)
	var show_in_hud: bool = effect_data.get("show_in_hud", true)

	# Strip "status_" prefix for effect type name
	var effect_name: String = effect_id.replace("status_", "")

	match effect_type:
		"debuff_dot":
			apply_dot(effect_name, duration, absf(value), tick_interval, show_in_hud)
		"buff_hot":
			apply_hot(effect_name, duration, absf(value), tick_interval, show_in_hud)
		"buff":
			apply_buff(effect_name, duration, show_in_hud)
		"debuff":
			apply_debuff(effect_name, duration, show_in_hud)
		_:
			Debug.warn("StatusEffect", "Unknown effect type: %s" % effect_type)


## Override for visual effect spawning
func _on_effect_applied(_effect_type: String, _is_debuff: bool) -> void:
	pass


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


## Get full effect data
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
		_on_effect_removed(effect_type)
	_active_effects.clear()
	Debug.log("StatusEffect", "All effects cleared")


## Clear all debuffs only
func clear_all_debuffs() -> void:
	var to_remove: Array[String] = []
	for effect_type in _active_effects:
		if _active_effects[effect_type].get("is_debuff", false):
			to_remove.append(effect_type)
	for effect_type in to_remove:
		_remove_effect(effect_type)


## Clear all buffs only
func clear_all_buffs() -> void:
	var to_remove: Array[String] = []
	for effect_type in _active_effects:
		if not _active_effects[effect_type].get("is_debuff", false):
			to_remove.append(effect_type)
	for effect_type in to_remove:
		_remove_effect(effect_type)
