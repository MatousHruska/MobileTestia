extends StatusEffectComponent
class_name StatusEffectManager
## StatusEffectManager - Player-specific status effect handling
##
## Extends StatusEffectComponent with player-specific features:
## - Persistence across zone changes
## - Integration with PlayerStats for damage/healing
## - HUD visibility control


func _ready() -> void:
	# Load persisted effects from previous zone/session
	_load_persisted_effects()


func _process(delta: float) -> void:
	if not Game.is_playing:
		return

	process_effects(delta)


## Override damage application to use PlayerStats
func _apply_damage_to_owner(damage: float) -> void:
	PlayerStats.damage(damage)


## Override healing application to use PlayerStats
func _apply_heal_to_owner(heal_amount: float) -> void:
	PlayerStats.heal(heal_amount)


#===============================================================================
# OVERRIDES WITH PERSISTENCE
#===============================================================================

## Override apply_dot to add persistence
func apply_dot(effect_type: String, duration: float, damage_per_tick: float, tick_interval: float = 1.0, show_in_hud: bool = true) -> void:
	super.apply_dot(effect_type, duration, damage_per_tick, tick_interval, show_in_hud)
	_save_persisted_effects()


## Override apply_hot to add persistence
func apply_hot(effect_type: String, duration: float, heal_per_tick: float, tick_interval: float = 1.0, show_in_hud: bool = true) -> void:
	super.apply_hot(effect_type, duration, heal_per_tick, tick_interval, show_in_hud)
	_save_persisted_effects()


## Override apply_buff to add persistence
func apply_buff(effect_type: String, duration: float, show_in_hud: bool = true) -> void:
	super.apply_buff(effect_type, duration, show_in_hud)
	_save_persisted_effects()


## Override apply_debuff to add persistence
func apply_debuff(effect_type: String, duration: float, show_in_hud: bool = true) -> void:
	super.apply_debuff(effect_type, duration, show_in_hud)
	_save_persisted_effects()


## Override apply_permanent to add persistence
func apply_permanent(effect_type: String, is_debuff: bool = false, show_in_hud: bool = true) -> void:
	super.apply_permanent(effect_type, is_debuff, show_in_hud)
	_save_persisted_effects()


## Override clear_effect to add persistence
func clear_effect(effect_type: String) -> void:
	super.clear_effect(effect_type)
	_save_persisted_effects()


## Override clear_all_effects to add persistence
func clear_all_effects() -> void:
	super.clear_all_effects()
	_save_persisted_effects()


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
		var is_debuff: bool = effect_data.get("is_debuff", true)
		effect_applied.emit(effect_type, effect_data.remaining_duration, show_in_hud, is_debuff)

	Debug.log("StatusEffect", "Loaded persisted effects", persisted.keys())


func _save_persisted_effects() -> void:
	Persistence.save_status_effects(_active_effects.duplicate(true))


## Check database for show_in_hud flag (player-specific helper)
func _get_show_in_hud(effect_type: String) -> bool:
	# Look up in database - effect_type maps to status_id like "status_rot" for "rot"
	var status_id := "status_" + effect_type
	if DatabaseLoader.status_effects.has(status_id):
		return DatabaseLoader.status_effects[status_id].get("show_in_hud", true)
	return true  # Default to showing in HUD
