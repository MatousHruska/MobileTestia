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

## Track if we're connected to PlayerStats signals (for ends_when conditions)
var _player_signals_connected: bool = false

#===============================================================================
# INITIALIZATION
#===============================================================================

func setup(effect_owner: Node2D) -> void:
	_owner = effect_owner
	_connect_player_signals()


func _connect_player_signals() -> void:
	## Connect to PlayerStats signals for ends_when conditions
	if _player_signals_connected:
		return

	# Check if PlayerStats autoload exists
	if not Engine.has_singleton("PlayerStats") and not has_node("/root/PlayerStats"):
		# Try deferred connection
		call_deferred("_connect_player_signals")
		return

	var player_stats = get_node_or_null("/root/PlayerStats")
	if player_stats:
		if player_stats.has_signal("health_full"):
			player_stats.health_full.connect(_on_player_health_full)
			_player_signals_connected = true
			Debug.log("StatusEffect", "Connected to PlayerStats health signals")


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

		# Check ends_when conditions (for conditional removal)
		if _check_ends_when_condition(effect):
			if effect_type not in expired_effects:
				expired_effects.append(effect_type)

	# Remove expired effects
	for effect_type in expired_effects:
		_remove_effect(effect_type)


func _check_ends_when_condition(effect: Dictionary) -> bool:
	## Check if effect should end based on its ends_when condition
	var ends_when: String = effect.get("ends_when", "")
	if ends_when.is_empty():
		return false

	var player_stats = get_node_or_null("/root/PlayerStats")

	match ends_when:
		"player_full_health":
			if player_stats and player_stats.has_method("is_health_full"):
				return player_stats.is_health_full()
		"player_below_50":
			if player_stats and player_stats.has_method("get_health_percent"):
				return player_stats.get_health_percent() < 0.5
		"player_above_50":
			if player_stats and player_stats.has_method("get_health_percent"):
				return player_stats.get_health_percent() > 0.5
		_:
			# Handle parameterized conditions like "player_health_above_75"
			if ends_when.begins_with("player_health_above_"):
				var threshold := ends_when.replace("player_health_above_", "").to_float() / 100.0
				if player_stats and player_stats.has_method("get_health_percent"):
					return player_stats.get_health_percent() > threshold
			elif ends_when.begins_with("player_health_below_"):
				var threshold := ends_when.replace("player_health_below_", "").to_float() / 100.0
				if player_stats and player_stats.has_method("get_health_percent"):
					return player_stats.get_health_percent() < threshold

	return false


func _on_player_health_full() -> void:
	## Called when player reaches full health - check for effects that should end
	var to_remove: Array[String] = []
	for effect_type in _active_effects:
		var effect: Dictionary = _active_effects[effect_type]
		if effect.get("ends_when", "") == "player_full_health":
			to_remove.append(effect_type)
			Debug.log("StatusEffect", "Effect ending (player full health)", effect_type)

	for effect_type in to_remove:
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
## ends_when: Optional condition for automatic removal (e.g., "player_full_health")
func apply_buff(effect_type: String, duration: float, show_in_hud: bool = true, ends_when: String = "") -> void:
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
			"show_in_hud": show_in_hud,
			"ends_when": ends_when
		}
		effect_applied.emit(effect_type, duration, show_in_hud, false)
		_on_effect_applied(effect_type, false)
		Debug.log("StatusEffect", "Buff applied", {
			"type": effect_type,
			"duration": duration,
			"ends_when": ends_when if not ends_when.is_empty() else "none"
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
	var ends_when: String = effect_data.get("ends_when", "")
	var stat_affected: String = effect_data.get("stat_affected", "")

	# Strip "status_" prefix for effect type name
	var effect_name: String = effect_id.replace("status_", "")

	match effect_type:
		"debuff_dot":
			apply_dot(effect_name, duration, absf(value), tick_interval, show_in_hud)
		"buff_hot":
			apply_hot(effect_name, duration, absf(value), tick_interval, show_in_hud)
		"buff":
			apply_buff(effect_name, duration, show_in_hud, ends_when)
		"debuff":
			apply_debuff(effect_name, duration, show_in_hud)
		_:
			Debug.warn("StatusEffect", "Unknown effect type: %s" % effect_type)

	# If ends_when was specified and effect was added, update it
	if not ends_when.is_empty() and effect_name in _active_effects:
		_active_effects[effect_name]["ends_when"] = ends_when

	# Store stat modifier if specified
	if not stat_affected.is_empty() and effect_name in _active_effects:
		_active_effects[effect_name]["stat_affected"] = stat_affected
		_active_effects[effect_name]["stat_value"] = value
		Debug.log("StatusEffect", "Effect %s modifies %s by %s" % [effect_name, stat_affected, value])


## Apply effect - wrapper for compatibility with code that expects this method name
## source_node is optional and ignored (kept for API compatibility)
func apply_effect(effect_id: String, _source_node: Node2D = null) -> void:
	apply_status_effect(effect_id)


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


## Get total stat modifier for a specific stat from all active effects
## Returns percentage modifier (e.g., 30 means +30%)
func get_stat_modifier(stat_name: String) -> float:
	var total: float = 0.0
	for effect_type in _active_effects:
		var effect: Dictionary = _active_effects[effect_type]
		if effect.get("stat_affected", "") == stat_name:
			total += effect.get("stat_value", 0.0)
	return total


## Get stat multiplier for a specific stat (1.0 = no change, 1.3 = +30%)
func get_stat_multiplier(stat_name: String) -> float:
	var modifier: float = get_stat_modifier(stat_name)
	return 1.0 + (modifier / 100.0)


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
