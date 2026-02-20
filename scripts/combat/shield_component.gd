extends Node
class_name ShieldComponent
## ShieldComponent - Manages enemy shield that absorbs damage
##
## Shield absorbs damage before health. When depleted, remaining damage
## passes through to health. Provides API for game mechanics that interact
## with shields (knockback immunity, stun immunity, etc.)

#===============================================================================
# SIGNALS
#===============================================================================

signal shield_changed(current: float, maximum: float)
signal shield_depleted()
signal shield_damaged(amount: float, remaining: float)

#===============================================================================
# PROPERTIES
#===============================================================================

## Maximum shield value
var max_shield: float = 0.0:
	set(value):
		max_shield = maxf(0.0, value)
		shield_changed.emit(current_shield, max_shield)

## Current shield value
var current_shield: float = 0.0:
	set(value):
		var old_shield := current_shield
		current_shield = clampf(value, 0.0, max_shield)
		shield_changed.emit(current_shield, max_shield)
		if old_shield > 0 and current_shield <= 0:
			shield_depleted.emit()

#===============================================================================
# PUBLIC API - Used by game mechanics
#===============================================================================

## Returns true if entity currently has any shield
func has_shield() -> bool:
	return current_shield > 0.0


## Returns shield as percentage (0.0 to 1.0)
func get_shield_percent() -> float:
	if max_shield <= 0:
		return 0.0
	return current_shield / max_shield


## Returns true if shield is at full capacity
func is_shield_full() -> bool:
	return max_shield > 0 and current_shield >= max_shield


## Check if entity is immune to knockback (shielded entities can't be knocked back)
func is_knockback_immune() -> bool:
	return has_shield()


## Check if entity is immune to stun (optional: shielded entities resist stun)
func is_stun_immune() -> bool:
	return has_shield()


## Check if entity is immune to crowd control
func is_cc_immune() -> bool:
	return has_shield()


#===============================================================================
# SHIELD MANAGEMENT
#===============================================================================

## Initialize shield with a value
func setup(shield_amount: float) -> void:
	max_shield = shield_amount
	current_shield = shield_amount
	Debug.log("Combat", "Shield initialized", {"amount": shield_amount})


## Apply damage to shield, returns overflow damage that should go to health
func absorb_damage(damage: float) -> float:
	if damage <= 0 or current_shield <= 0:
		return damage

	var absorbed := minf(damage, current_shield)
	var overflow := damage - absorbed

	current_shield -= absorbed
	shield_damaged.emit(absorbed, current_shield)

	Debug.log("Combat", "Shield absorbed damage", {
		"absorbed": absorbed,
		"overflow": overflow,
		"remaining": current_shield
	})

	return overflow


## Restore shield by amount
func restore_shield(amount: float) -> void:
	if amount <= 0 or max_shield <= 0:
		return
	current_shield = minf(current_shield + amount, max_shield)


## Fully restore shield to maximum
func restore_full() -> void:
	current_shield = max_shield


## Remove all shield
func break_shield() -> void:
	if current_shield > 0:
		current_shield = 0


## Set shield to specific value (for loading saves etc.)
func set_shield(current: float, maximum: float) -> void:
	max_shield = maximum
	current_shield = minf(current, maximum)


#===============================================================================
# SERIALIZATION (for save/load)
#===============================================================================

func get_save_data() -> Dictionary:
	return {
		"current_shield": current_shield,
		"max_shield": max_shield
	}


func load_save_data(data: Dictionary) -> void:
	max_shield = data.get("max_shield", 0.0)
	current_shield = data.get("current_shield", 0.0)
