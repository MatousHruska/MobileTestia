extends Node
class_name EnemyAbilityController
## EnemyAbilityController - AI brain for enemy ability selection
##
## Manages ability selection based on behavior profile:
##   - Evaluates which abilities are usable (range, cooldown, conditions)
##   - Selects ability based on priority mode (highest, conditional, random)
##   - Triggers ability execution through AbilityExecutor
##
## Usage:
##   var controller = EnemyAbilityController.new()
##   enemy.add_child(controller)
##   controller.setup(behavior_profile, abilities)
##   controller.try_attack(target)

#===============================================================================
# SIGNALS
#===============================================================================

signal ability_selected(ability: AbilityData)
signal no_ability_available()
signal attack_started()
signal attack_completed()

#===============================================================================
# STATE
#===============================================================================

var _owner: Node2D = null
var _executor: AbilityExecutor = null
var _behavior_profile: BehaviorProfileData = null
var _abilities: Array[AbilityData] = []
var _current_target: Node2D = null

var enabled: bool = true

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_owner = get_parent() as Node2D
	if not _owner:
		Debug.warn("EnemyAbilityController", "Parent is not Node2D")
		return

	# Create executor
	_executor = AbilityExecutor.new()
	_executor.name = "AbilityExecutor"
	add_child(_executor)

	# Connect executor signals
	_executor.ability_started.connect(_on_ability_started)
	_executor.ability_completed.connect(_on_ability_completed)
	_executor.ability_hit.connect(_on_ability_hit)
	_executor.ability_interrupted.connect(_on_ability_interrupted)


func setup(behavior: BehaviorProfileData, abilities: Array[AbilityData]) -> void:
	## Configure the controller with behavior and abilities
	_behavior_profile = behavior
	_abilities = abilities

	Debug.log("EnemyAbilityController", "Setup complete", {
		"behavior": behavior.id if behavior else "none",
		"abilities": abilities.size()
	})


func set_abilities(abilities: Array[AbilityData]) -> void:
	_abilities = abilities


func add_ability(ability: AbilityData) -> void:
	if ability and ability not in _abilities:
		_abilities.append(ability)


#===============================================================================
# ATTACK INTERFACE
#===============================================================================

func try_attack(target: Node2D) -> bool:
	## Try to attack target. Returns true if attack started.

	if not enabled or not target or not _owner:
		return false

	if is_busy():
		return false

	_current_target = target

	# Roll ability use chance
	var use_ability := true
	if _behavior_profile and randf() > _behavior_profile.ability_use_chance:
		use_ability = false

	var ability := _select_ability(target) if use_ability else null

	if ability:
		return _execute_ability(ability, target)
	else:
		no_ability_available.emit()
		return false


func can_attack() -> bool:
	## Check if any ability is available
	if not enabled:
		return false

	if is_busy():
		return false

	return _get_usable_abilities(_current_target).size() > 0


func is_busy() -> bool:
	return _executor and _executor.is_busy()


func is_winding_up() -> bool:
	return _executor and _executor.is_in_windup()


func is_recovering() -> bool:
	return _executor and _executor.is_in_recovery()


func interrupt() -> void:
	if _executor:
		_executor.interrupt()


#===============================================================================
# ABILITY SELECTION
#===============================================================================

func _select_ability(target: Node2D) -> AbilityData:
	## Select an ability to use based on behavior profile

	var usable := _get_usable_abilities(target)
	if usable.is_empty():
		return null

	if not _behavior_profile:
		return usable[0]

	match _behavior_profile.ability_priority_mode:
		BehaviorProfileData.AbilityPriorityMode.HIGHEST:
			return _select_highest_priority(usable)
		BehaviorProfileData.AbilityPriorityMode.CONDITIONAL:
			return _select_conditional(usable, target)
		BehaviorProfileData.AbilityPriorityMode.RANDOM_WEIGHTED:
			return _select_random_weighted(usable)
		_:
			return usable[0]


func _get_usable_abilities(target: Node2D) -> Array[AbilityData]:
	## Get all abilities that can be used right now

	var result: Array[AbilityData] = []

	for ability in _abilities:
		if _can_use_ability(ability, target):
			result.append(ability)

	return result


func _can_use_ability(ability: AbilityData, target: Node2D) -> bool:
	## Check if a specific ability can be used

	if not ability or not _owner:
		return false

	# Check cooldown
	if _executor and _executor.is_on_cooldown(ability):
		return false

	# Check range
	if target:
		var distance := _owner.global_position.distance_to(target.global_position)
		if distance < ability.range_min or distance > ability.range_max:
			return false

	# Check conditions
	if target and not ability.check_conditions(_owner, target):
		return false

	return true


func _select_highest_priority(abilities: Array[AbilityData]) -> AbilityData:
	## Select ability with highest priority

	var best: AbilityData = null
	var best_priority := -1

	for ability in abilities:
		if ability.priority > best_priority:
			best = ability
			best_priority = ability.priority

	return best


func _select_conditional(abilities: Array[AbilityData], target: Node2D) -> AbilityData:
	## Select ability based on conditions, falling back to priority

	# First try to find abilities with matching conditions
	var conditional_matches: Array[AbilityData] = []

	for ability in abilities:
		if not ability.conditions.is_empty():
			conditional_matches.append(ability)

	if not conditional_matches.is_empty():
		return _select_highest_priority(conditional_matches)

	# Fall back to highest priority
	return _select_highest_priority(abilities)


func _select_random_weighted(abilities: Array[AbilityData]) -> AbilityData:
	## Select random ability weighted by priority

	var total_weight := 0.0
	for ability in abilities:
		total_weight += ability.priority

	if total_weight <= 0:
		return abilities.pick_random()

	var roll := randf() * total_weight
	var cumulative := 0.0

	for ability in abilities:
		cumulative += ability.priority
		if roll <= cumulative:
			return ability

	return abilities[-1]


#===============================================================================
# EXECUTION
#===============================================================================

func _execute_ability(ability: AbilityData, target: Node2D) -> bool:
	if not _executor:
		return false

	var success := _executor.execute_ability(ability, target)

	if success:
		ability_selected.emit(ability)
		Debug.log("EnemyAbilityController", "Executing ability", {
			"ability": ability.id,
			"target": target.name if target else "none"
		})

	return success


#===============================================================================
# CALLBACKS
#===============================================================================

func _on_ability_started(_ability: AbilityData) -> void:
	attack_started.emit()


func _on_ability_completed(_ability: AbilityData) -> void:
	attack_completed.emit()


func _on_ability_hit(target: Node2D, ability: AbilityData, damage: float) -> void:
	Debug.log("EnemyAbilityController", "Ability hit", {
		"target": target.name,
		"ability": ability.id,
		"damage": damage
	})


func _on_ability_interrupted(_ability: AbilityData) -> void:
	pass


#===============================================================================
# RANGE CHECKING
#===============================================================================

func get_best_attack_range() -> float:
	## Get the ideal attack range for current abilities

	if _abilities.is_empty():
		return 30.0

	# Find ability with best range that's not on cooldown
	var best_range := 30.0
	var found := false

	for ability in _abilities:
		if _executor and _executor.is_on_cooldown(ability):
			continue
		if not found or ability.range_max < best_range:
			best_range = ability.range_max
			found = true

	return best_range


func get_max_attack_range() -> float:
	## Get the maximum attack range of any ability

	var max_range := 0.0
	for ability in _abilities:
		if ability.range_max > max_range:
			max_range = ability.range_max

	return max_range if max_range > 0 else 30.0


func is_in_attack_range(target: Node2D) -> bool:
	## Check if target is in range of any usable ability

	if not target or not _owner:
		return false

	var distance := _owner.global_position.distance_to(target.global_position)

	for ability in _abilities:
		if _executor and _executor.is_on_cooldown(ability):
			continue
		if distance >= ability.range_min and distance <= ability.range_max:
			return true

	return false


#===============================================================================
# COOLDOWNS
#===============================================================================

func reset_all_cooldowns() -> void:
	if _executor:
		_executor.reset_cooldowns()


func reset_cooldown(ability_id: String) -> void:
	if _executor:
		_executor.reset_cooldown(ability_id)


#===============================================================================
# DEBUG
#===============================================================================

func set_debug_hitboxes(enabled_val: bool) -> void:
	if _executor:
		_executor.set_debug_hitboxes(enabled_val)


func get_debug_info() -> Dictionary:
	var info := {
		"enabled": enabled,
		"abilities": [],
		"behavior": _behavior_profile.id if _behavior_profile else "none",
		"busy": is_busy()
	}

	for ability in _abilities:
		var ability_info := {
			"id": ability.id,
			"priority": ability.priority,
			"range": "%d-%d" % [ability.range_min, ability.range_max],
			"on_cooldown": _executor.is_on_cooldown(ability) if _executor else false
		}
		if _executor and _executor.is_on_cooldown(ability):
			ability_info["cooldown_remaining"] = _executor.get_cooldown_remaining(ability)
		info.abilities.append(ability_info)

	if _executor:
		info["executor"] = _executor.get_debug_info()

	return info
