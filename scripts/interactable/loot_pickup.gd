extends InteractableBase
class_name LootPickup
## LootPickup - Dropped item that can be picked up by the player
## Spawned when enemies die and drop loot

## Signals
signal pickup_failed  ## Emitted when inventory is full

## The item this pickup contains
var item: ItemData = null

## Visual bobbing animation
var _bob_time: float = 0.0
var _initial_y: float = 0.0
const BOB_SPEED: float = 2.0
const BOB_AMOUNT: float = 3.0


func _init() -> void:
	# Small placeholder for dropped items
	placeholder_size = Vector2(24, 24)
	placeholder_color = Color(0.8, 0.7, 0.2)  # Gold/yellow color
	interaction_radius = 40.0


func _on_ready() -> void:
	_initial_y = position.y
	add_to_group("loot_pickups")

	if item:
		_update_visual_for_item()
		Debug.info("Loot", "LootPickup ready: %s" % item.item_name)


func _process(delta: float) -> void:
	# Simple bobbing animation
	_bob_time += delta * BOB_SPEED
	if _visual:
		_visual.position.y = (-placeholder_size.y / 2) + sin(_bob_time) * BOB_AMOUNT


## Set the item this pickup contains
func set_item(new_item: ItemData) -> void:
	item = new_item
	_update_visual_for_item()


func _update_visual_for_item() -> void:
	if not item or not _visual:
		return

	# Color based on rarity
	match item.rarity:
		ItemData.Rarity.COMMON:
			placeholder_color = Color(0.7, 0.7, 0.7)  # Gray
		ItemData.Rarity.MAGIC:
			placeholder_color = Color(0.3, 0.5, 1.0)  # Blue
		ItemData.Rarity.RARE:
			placeholder_color = Color(1.0, 0.8, 0.2)  # Yellow/Gold
		ItemData.Rarity.UNIQUE:
			placeholder_color = Color(0.8, 0.4, 0.1)  # Orange
		_:
			placeholder_color = Color(0.7, 0.7, 0.7)

	_visual.color = placeholder_color


## Override interaction prompt
func get_interaction_prompt() -> String:
	if item:
		return "Pickup %s" % item.item_name
	return "Pickup"


## Override can_interact to check if we have an item
func can_interact() -> bool:
	return super.can_interact() and item != null


## Override interaction behavior
func _on_interact() -> void:
	if item == null:
		end_interaction()
		return

	# Try to add item to inventory
	var success := InventoryManager.add_item(item)

	if success:
		Debug.info("Loot", "Picked up: %s" % item.item_name)
		# Remove this pickup from the world
		queue_free()
	else:
		Debug.warn("Loot", "Inventory full, cannot pickup: %s" % item.item_name)
		pickup_failed.emit()
		end_interaction()


## Factory method to create a pickup at a position
static func create_at(pos: Vector2, drop_item: ItemData) -> LootPickup:
	var pickup := LootPickup.new()
	pickup.position = pos
	pickup.item = drop_item
	return pickup
