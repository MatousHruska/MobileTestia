extends Node
## TalentManager - Manages player talent investments and skill bindings
##
## This autoload handles:
## - Tracking invested talent points per talent
## - Validating talent prerequisites
## - Managing the skillbook (learned active abilities)
## - Managing skill bindings to ability slots

## Signals
signal talent_learned(talent_id: String, new_points: int)
signal talent_points_changed(total_invested: int, available: int)
signal skillbook_updated(active_talents: Array)
signal skill_bound(slot_index: int, talent_id: String)
signal skill_unbound(slot_index: int)

## Constants
const POINTS_PER_ROW: int = 5  ## Points needed to unlock each row
const MAIN_SLOT_INDEX: int = 0  ## Index of the main ability slot
const MAX_SLOTS: int = 6  ## 1 main + 5 secondary

## Invested points per talent (talent_id -> points)
var invested_talents: Dictionary = {}

## Currently selected tree for display
var current_tree_id: String = ""

## Skill bindings (slot_index -> talent_id), empty string = unbound
var skill_bindings: Array[String] = []

## Cached talent data objects
var _talent_cache: Dictionary = {}


func _ready() -> void:
	Debug.info("Talents", "TalentManager initialized")

	# Initialize skill bindings array
	skill_bindings.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		skill_bindings[i] = ""

	# Wait for databases to load
	if not DatabaseLoader.talent_trees.is_empty():
		_on_databases_loaded()
	else:
		DatabaseLoader.databases_loaded.connect(_on_databases_loaded)


func _on_databases_loaded() -> void:
	# Cache talent data objects
	for talent_dict in DatabaseLoader.talents_list:
		var talent := TalentData.from_dict(talent_dict)
		_talent_cache[talent.id] = talent

	# Set default tree if available
	if not DatabaseLoader.talent_trees_list.is_empty():
		current_tree_id = DatabaseLoader.talent_trees_list[0].get("id", "")

	Debug.info("Talents", "Cached %d talents" % _talent_cache.size())


#===============================================================================
# TALENT POINT QUERIES
#===============================================================================

## Get invested points in a specific talent
func get_invested_points(talent_id: String) -> int:
	return invested_talents.get(talent_id, 0)


## Get total invested points across all talents
func get_total_invested_points() -> int:
	var total: int = 0
	for points in invested_talents.values():
		total += points
	return total


## Get invested points in a specific tree
func get_tree_invested_points(tree_id: String) -> int:
	var total: int = 0
	for talent_id in invested_talents:
		var talent := get_talent(talent_id)
		if talent and talent.tree_id == tree_id:
			total += invested_talents[talent_id]
	return total


## Get available talent points (from PlayerStats minus invested)
func get_available_points() -> int:
	return PlayerStats.skill_points - get_total_invested_points()


## Check if talent is maxed out
func is_talent_maxed(talent_id: String) -> bool:
	var talent := get_talent(talent_id)
	if not talent:
		return false
	return get_invested_points(talent_id) >= talent.max_points


## Check if talent has any points invested
func is_talent_learned(talent_id: String) -> bool:
	return get_invested_points(talent_id) > 0


#===============================================================================
# PREREQUISITE CHECKING
#===============================================================================

## Check if talent can be learned (all prerequisites met)
func can_learn_talent(talent_id: String) -> bool:
	var talent := get_talent(talent_id)
	if not talent:
		return false

	# Check if already maxed
	if is_talent_maxed(talent_id):
		return false

	# Check if we have available points
	if get_available_points() <= 0:
		return false

	# Check row requirement (5 points per row)
	var tree_points := get_tree_invested_points(talent.tree_id)
	var required_points := talent.get_required_row_points()
	if tree_points < required_points:
		return false

	# Check prerequisites (must be maxed)
	for prereq_id in talent.prerequisite_ids:
		if not is_talent_maxed(prereq_id):
			return false

	return true


## Get reason why talent cannot be learned (for UI feedback)
func get_learn_block_reason(talent_id: String) -> String:
	var talent := get_talent(talent_id)
	if not talent:
		return "Talent not found"

	if is_talent_maxed(talent_id):
		return "Already maxed"

	if get_available_points() <= 0:
		return "No talent points available"

	var tree_points := get_tree_invested_points(talent.tree_id)
	var required_points := talent.get_required_row_points()
	if tree_points < required_points:
		return "Requires %d points in tree (have %d)" % [required_points, tree_points]

	for prereq_id in talent.prerequisite_ids:
		if not is_talent_maxed(prereq_id):
			var prereq := get_talent(prereq_id)
			var prereq_name := prereq.talent_name if prereq else prereq_id
			return "Requires %s to be maxed" % prereq_name

	return ""


#===============================================================================
# LEARNING TALENTS
#===============================================================================

## Learn a talent (add 1 point)
func learn_talent(talent_id: String) -> bool:
	if not can_learn_talent(talent_id):
		Debug.warn("Talents", "Cannot learn talent: %s - %s" % [talent_id, get_learn_block_reason(talent_id)])
		return false

	var current_points := get_invested_points(talent_id)
	invested_talents[talent_id] = current_points + 1

	var new_points := current_points + 1
	Debug.info("Talents", "Learned talent: %s (%d/%d)" % [talent_id, new_points, get_talent(talent_id).max_points])

	talent_learned.emit(talent_id, new_points)
	talent_points_changed.emit(get_total_invested_points(), get_available_points())

	# If this is an active talent and just hit rank 1, add to skillbook
	var talent := get_talent(talent_id)
	if talent and talent.is_active() and new_points == 1:
		_emit_skillbook_update()

	return true


## Reset all talents (for Potion of Forget)
func reset_all_talents() -> void:
	invested_talents.clear()

	# Clear all skill bindings
	for i in range(MAX_SLOTS):
		if skill_bindings[i] != "":
			skill_bindings[i] = ""
			skill_unbound.emit(i)

	talent_points_changed.emit(0, get_available_points())
	_emit_skillbook_update()

	Debug.info("Talents", "All talents reset")


#===============================================================================
# SKILLBOOK (Active Abilities)
#===============================================================================

## Get all learned active talents for the skillbook
func get_skillbook_talents() -> Array[TalentData]:
	var result: Array[TalentData] = []

	for talent_id in invested_talents:
		if invested_talents[talent_id] > 0:
			var talent := get_talent(talent_id)
			if talent and talent.is_active():
				result.append(talent)

	return result


## Check if a talent is in the skillbook
func is_in_skillbook(talent_id: String) -> bool:
	var talent := get_talent(talent_id)
	if not talent or not talent.is_active():
		return false
	return get_invested_points(talent_id) > 0


## Emit skillbook update signal
func _emit_skillbook_update() -> void:
	var talents := get_skillbook_talents()
	var talent_ids: Array = []
	for t in talents:
		talent_ids.append(t.id)
	skillbook_updated.emit(talent_ids)


#===============================================================================
# SKILL BINDINGS
#===============================================================================

## Bind a skill to a slot
func bind_skill(slot_index: int, talent_id: String) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		Debug.warn("Talents", "Invalid slot index: %d" % slot_index)
		return false

	if not is_in_skillbook(talent_id):
		Debug.warn("Talents", "Talent not in skillbook: %s" % talent_id)
		return false

	# Check if already bound elsewhere, unbind first
	for i in range(MAX_SLOTS):
		if skill_bindings[i] == talent_id:
			skill_bindings[i] = ""
			skill_unbound.emit(i)

	skill_bindings[slot_index] = talent_id
	skill_bound.emit(slot_index, talent_id)

	Debug.info("Talents", "Bound skill %s to slot %d" % [talent_id, slot_index])
	return true


## Unbind a skill from a slot
func unbind_skill(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return

	if skill_bindings[slot_index] != "":
		var old_talent := skill_bindings[slot_index]
		skill_bindings[slot_index] = ""
		skill_unbound.emit(slot_index)
		Debug.info("Talents", "Unbound skill %s from slot %d" % [old_talent, slot_index])


## Get talent bound to a slot
func get_bound_talent(slot_index: int) -> TalentData:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return null

	var talent_id := skill_bindings[slot_index]
	if talent_id.is_empty():
		return null

	return get_talent(talent_id)


## Check if a talent is bound to any slot
func is_talent_bound(talent_id: String) -> bool:
	return talent_id in skill_bindings


## Get slot index where talent is bound (-1 if not bound)
func get_talent_slot(talent_id: String) -> int:
	return skill_bindings.find(talent_id)


## Get all bound talents as array
func get_all_bound_talents() -> Array[TalentData]:
	var result: Array[TalentData] = []
	for i in range(MAX_SLOTS):
		var talent := get_bound_talent(i)
		if talent:
			result.append(talent)
	return result


#===============================================================================
# TALENT DATA ACCESS
#===============================================================================

## Get talent data by ID (cached)
func get_talent(talent_id: String) -> TalentData:
	return _talent_cache.get(talent_id, null)


## Get all talents for a tree
func get_talents_for_tree(tree_id: String) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for talent in _talent_cache.values():
		if talent.tree_id == tree_id:
			result.append(talent)
	return result


## Get talents at a specific row in a tree
func get_talents_at_row(tree_id: String, row: int) -> Array[TalentData]:
	var result: Array[TalentData] = []
	for talent in _talent_cache.values():
		if talent.tree_id == tree_id and talent.row == row:
			result.append(talent)
	# Sort by column
	result.sort_custom(func(a, b): return a.column < b.column)
	return result


## Get maximum row in a tree
func get_max_row(tree_id: String) -> int:
	var max_row: int = 0
	for talent in _talent_cache.values():
		if talent.tree_id == tree_id and talent.row > max_row:
			max_row = talent.row
	return max_row


#===============================================================================
# STAT BONUSES
#===============================================================================

## Calculate total stat bonuses from all invested passive talents
func get_total_stat_bonuses() -> Dictionary:
	var result: Dictionary = {}

	for talent_id in invested_talents:
		var points: int = invested_talents[talent_id]
		if points <= 0:
			continue

		var talent := get_talent(talent_id)
		if not talent or not talent.is_passive():
			continue

		var bonuses := talent.get_stat_bonuses_at_points(points)
		for stat in bonuses:
			if not result.has(stat):
				result[stat] = 0
			result[stat] += bonuses[stat]

	return result


#===============================================================================
# PERSISTENCE
#===============================================================================

## Get save data for persistence
func get_save_data() -> Dictionary:
	return {
		"invested_talents": invested_talents.duplicate(),
		"skill_bindings": skill_bindings.duplicate(),
	}


## Load save data
func load_save_data(data: Dictionary) -> void:
	invested_talents = data.get("invested_talents", {})

	var bindings: Array = data.get("skill_bindings", [])
	for i in range(min(bindings.size(), MAX_SLOTS)):
		skill_bindings[i] = bindings[i]

	talent_points_changed.emit(get_total_invested_points(), get_available_points())
	_emit_skillbook_update()

	# Emit binding signals
	for i in range(MAX_SLOTS):
		if skill_bindings[i] != "":
			skill_bound.emit(i, skill_bindings[i])

	Debug.info("Talents", "Loaded save data: %d talents invested" % invested_talents.size())


#===============================================================================
# DEBUG
#===============================================================================

## Debug: Add talent points
func debug_add_points(amount: int = 10) -> void:
	PlayerStats.debug_add_skill_points(amount)


## Debug: Learn all talents in a tree
func debug_learn_all_in_tree(tree_id: String) -> void:
	for talent in get_talents_for_tree(tree_id):
		while can_learn_talent(talent.id):
			learn_talent(talent.id)


## Print current state
func print_state() -> void:
	Debug.snapshot("Talents", "TalentManager State", {
		"total_invested": get_total_invested_points(),
		"available_points": get_available_points(),
		"invested_talents": invested_talents,
		"skill_bindings": skill_bindings,
		"skillbook_size": get_skillbook_talents().size(),
	})
