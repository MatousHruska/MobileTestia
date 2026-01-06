extends InteractableBase
class_name ChestBase
## ChestBase - Base class for all chest types
## Handles chest states, visuals, and loot generation framework

## Chest states
enum ChestState { CLOSED, OPENING, OPEN, LOOTED }

## Chest tiers - affects loot quality and gold
enum ChestTier { WOODEN, IRON, GOLDEN }

## Tier colors for visual distinction
const TIER_COLORS := {
	ChestTier.WOODEN: Color(0.55, 0.35, 0.15, 1.0),   # Brown wood
	ChestTier.IRON: Color(0.5, 0.5, 0.55, 1.0),       # Gray metal
	ChestTier.GOLDEN: Color(0.85, 0.65, 0.15, 1.0),   # Gold
}

## Tier names for display
const TIER_NAMES := {
	ChestTier.WOODEN: "Wooden",
	ChestTier.IRON: "Iron",
	ChestTier.GOLDEN: "Golden",
}

## Signals
signal chest_opened(contents: Dictionary)
signal chest_looted

## Chest configuration
@export_group("Chest Settings")
@export var chest_id: String = ""  ## Unique ID for persistence
@export var chest_tier: ChestTier = ChestTier.WOODEN
@export var display_name: String = "Chest"

## Current state
var current_state: ChestState = ChestState.CLOSED

## Zone level (set by spawn point or zone)
var zone_level: int = 1


func _on_ready() -> void:
	_update_visual_for_tier()
	_update_interaction_prompt()

	# Check persistence - restore state if chest was previously looted
	if not chest_id.is_empty():
		_check_persistence()

	Debug.log("Chest", "Chest ready: %s (tier: %s)" % [display_name, TIER_NAMES[chest_tier]])


func _update_visual_for_tier() -> void:
	placeholder_size = Vector2(32, 28)  # Chest-like proportions
	set_visual_size(placeholder_size)
	set_visual_color(TIER_COLORS[chest_tier])


func _update_interaction_prompt() -> void:
	match current_state:
		ChestState.CLOSED:
			interaction_prompt = "Open %s Chest" % TIER_NAMES[chest_tier]
		ChestState.OPEN:
			interaction_prompt = "Loot %s Chest" % TIER_NAMES[chest_tier]
		ChestState.LOOTED:
			interaction_prompt = "Empty"


## Override interaction check
func can_interact() -> bool:
	if current_state == ChestState.LOOTED:
		return false
	if current_state == ChestState.OPENING:
		return false
	return super.can_interact()


## Handle interaction based on state
func _on_interact() -> void:
	match current_state:
		ChestState.CLOSED:
			_open_chest()
		ChestState.OPEN:
			_loot_chest()
		_:
			end_interaction()


func _open_chest() -> void:
	current_state = ChestState.OPENING

	# Visual feedback - slightly lighter color while opening
	var base_color: Color = TIER_COLORS[chest_tier]
	set_visual_color(base_color.lightened(0.2))

	# Brief delay for opening animation
	await get_tree().create_timer(0.3).timeout

	current_state = ChestState.OPEN
	_update_interaction_prompt()

	# Generate contents
	var contents := _generate_contents()
	chest_opened.emit(contents)

	Debug.info("Chest", "Opened %s chest (zone level: %d)" % [TIER_NAMES[chest_tier], zone_level])

	# Auto-loot if no UI needed
	if _should_auto_loot():
		_loot_chest()
	else:
		end_interaction()


func _loot_chest() -> void:
	var contents := _generate_contents()
	_give_contents_to_player(contents)

	current_state = ChestState.LOOTED
	_update_interaction_prompt()

	# Visual - darker, empty look
	var looted_color: Color = TIER_COLORS[chest_tier]
	set_visual_color(looted_color.darkened(0.4))

	chest_looted.emit()
	Debug.info("Chest", "Looted %s chest" % TIER_NAMES[chest_tier])

	_on_chest_looted()
	end_interaction()


## Override in subclasses - generate loot contents
func _generate_contents() -> Dictionary:
	# Base implementation returns gold based on tier and zone level
	return {
		"gold": _calculate_gold(),
		"items": []
	}


## Calculate gold based on tier and zone level
func _calculate_gold() -> int:
	# Base gold by tier
	var tier_base := {
		ChestTier.WOODEN: 5,
		ChestTier.IRON: 15,
		ChestTier.GOLDEN: 40,
	}

	# Tier multiplier (how much better each tier is)
	var tier_mult := {
		ChestTier.WOODEN: 1.0,
		ChestTier.IRON: 2.0,
		ChestTier.GOLDEN: 4.0,
	}

	# Zone level scaling: each level adds ~50% more gold
	var level_mult := 1.0 + ((zone_level - 1) * 0.5)

	var base: int = tier_base[chest_tier]
	var mult: float = tier_mult[chest_tier] * level_mult

	# Add some randomness (±30%)
	var variance := randf_range(0.7, 1.3)

	return int(base * mult * variance)


## Give contents to player
func _give_contents_to_player(contents: Dictionary) -> void:
	# Add gold
	var gold: int = contents.get("gold", 0)
	if gold > 0:
		Game.player_gold += gold
		Debug.log("Chest", "Gave player %d gold" % gold)

	# Add items
	var items: Array = contents.get("items", [])
	for item in items:
		if item is ItemData:
			Inventory.add_item(item)
			Debug.log("Chest", "Gave player item: %s" % item.item_name)


## Override to skip loot UI
func _should_auto_loot() -> bool:
	return false  # Use chest menu instead of auto-loot


## Interact with chest via UIManager
func interact_with_ui_manager() -> void:
	if current_state == ChestState.CLOSED:
		# Open chest first
		current_state = ChestState.OPENING

		# Visual feedback
		var base_color: Color = TIER_COLORS[chest_tier]
		set_visual_color(base_color.lightened(0.2))

		# Brief delay for opening animation
		await get_tree().create_timer(0.2).timeout

		current_state = ChestState.OPEN
		_update_interaction_prompt()

	if current_state == ChestState.OPEN:
		# Generate contents and open menu via UIManager
		var contents := _generate_contents()

		# Use call_deferred to avoid load order issues with UIManager
		_open_chest_menu_deferred.call_deferred(contents)


func _open_chest_menu_deferred(contents: Dictionary) -> void:
	# Called deferred to ensure UIManager is loaded
	if not UIManager:
		Debug.warn("Chest", "UIManager not available")
		return

	UIManager.open_chest_menu(self, contents)

	# Connect to menu closed signal to check if items remain
	var menu = UIManager.chest_menu
	if menu and menu.has_signal("chest_closed") and not menu.chest_closed.is_connected(_on_menu_closed):
		menu.chest_closed.connect(_on_menu_closed)


func _on_menu_closed() -> void:
	# Check if any items remain in the chest
	var remaining: Array = get_meta("remaining_items", [])
	if remaining.is_empty():
		# Mark as looted
		current_state = ChestState.LOOTED
		_update_interaction_prompt()

		var looted_color: Color = TIER_COLORS[chest_tier]
		set_visual_color(looted_color.darkened(0.4))

		_on_chest_looted()
		Debug.info("Chest", "Chest looted completely: %s" % display_name)
	else:
		Debug.info("Chest", "Chest still has %d items: %s" % [remaining.size(), display_name])


## Override for custom behavior after looting
func _on_chest_looted() -> void:
	_save_persistence()


#===============================================================================
# PERSISTENCE
#===============================================================================

func _check_persistence() -> void:
	## Check if this chest was previously looted and restore state
	if Persistence.has_state("chests", chest_id):
		var state := Persistence.load_state("chests", chest_id)
		if state.get("looted", false):
			set_opened(true)
			Debug.log("Chest", "Restored looted state for: %s" % chest_id)


func _save_persistence() -> void:
	## Save chest looted state to persistence
	if chest_id.is_empty():
		return

	Persistence.save_state("chests", chest_id, {
		"looted": true,
		"tier": chest_tier,
	})
	Debug.log("Chest", "Saved looted state for: %s" % chest_id)


## Get tier multiplier for loot calculations
func get_tier_multiplier() -> float:
	match chest_tier:
		ChestTier.WOODEN:
			return 1.0
		ChestTier.IRON:
			return 1.5
		ChestTier.GOLDEN:
			return 2.5
	return 1.0


## Get zone-adjusted item level for loot generation
func get_loot_item_level() -> int:
	# Tier bonus: wooden +0, iron +1, golden +2
	var tier_bonus := int(chest_tier)
	return zone_level + tier_bonus


## Get rarity weights adjusted for tier
func get_rarity_weights() -> Dictionary:
	# Higher tier = better chance for rare items
	match chest_tier:
		ChestTier.WOODEN:
			return {
				"common": 70,
				"uncommon": 25,
				"rare": 5,
				"legendary": 0,
			}
		ChestTier.IRON:
			return {
				"common": 40,
				"uncommon": 40,
				"rare": 18,
				"legendary": 2,
			}
		ChestTier.GOLDEN:
			return {
				"common": 15,
				"uncommon": 35,
				"rare": 40,
				"legendary": 10,
			}
	return {"common": 100}


## Check if this chest has been opened (for persistence)
func is_opened() -> bool:
	return current_state != ChestState.CLOSED


## Force chest to opened state (for loading saved games)
func set_opened(looted: bool = true) -> void:
	var color: Color = TIER_COLORS[chest_tier]
	if looted:
		current_state = ChestState.LOOTED
		set_visual_color(color.darkened(0.4))
	else:
		current_state = ChestState.OPEN
		set_visual_color(color.lightened(0.2))
	_update_interaction_prompt()
