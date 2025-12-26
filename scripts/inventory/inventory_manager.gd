extends Node
## InventoryManager - Handles all inventory and equipment data logic
## This is an autoload singleton - data is separate from UI

## Signals for UI updates
signal inventory_changed
signal equipment_changed(slot: ItemData.EquipSlot)
signal item_selected(item: ItemData, source: String, index: int)
signal item_deselected
signal gold_changed(new_amount: int)

## Inventory constants
const BACKPACK_SIZE: int = 30
const EQUIPMENT_SLOTS: Array[ItemData.EquipSlot] = [
	ItemData.EquipSlot.HEAD,
	ItemData.EquipSlot.BODY,
	ItemData.EquipSlot.HANDS,
	ItemData.EquipSlot.BOOTS,
	ItemData.EquipSlot.MAIN_HAND,
	ItemData.EquipSlot.ACCESSORY_1,
	ItemData.EquipSlot.ACCESSORY_2,
	ItemData.EquipSlot.QUICK_SLOT
]

## Inventory data
var backpack: Array[Dictionary] = []  # Array of {item: ItemData, quantity: int}
var equipped: Dictionary = {}  # EquipSlot -> {item: ItemData, quantity: int}
var gold: int = 0

## Selection state
var selected_item: ItemData = null
var selected_source: String = ""  # "backpack" or "equipment"
var selected_index: int = -1  # Backpack index or equipment slot


func _ready() -> void:
	_initialize_inventory()
	Debug.info("Inventory", "InventoryManager initialized", "Backpack size: %d" % BACKPACK_SIZE)


func _initialize_inventory() -> void:
	# Initialize empty backpack
	backpack.clear()
	for i in BACKPACK_SIZE:
		backpack.append({})

	# Initialize empty equipment slots
	equipped.clear()
	for slot in EQUIPMENT_SLOTS:
		equipped[slot] = {}


## BACKPACK OPERATIONS

func add_item(item: ItemData, quantity: int = 1) -> bool:
	if item == null or quantity <= 0:
		return false

	Debug.info("Inventory", "Adding item", "%s x%d" % [item.item_name, quantity])

	# Try to stack with existing items first
	if item.max_stack > 1:
		for i in backpack.size():
			var slot: Dictionary = backpack[i]
			if slot.is_empty():
				continue
			if slot.item.id == item.id and slot.quantity < item.max_stack:
				var can_add := mini(quantity, item.max_stack - slot.quantity)
				slot.quantity += can_add
				quantity -= can_add
				if quantity <= 0:
					inventory_changed.emit()
					return true

	# Add remaining to empty slots
	while quantity > 0:
		var empty_slot := _find_empty_backpack_slot()
		if empty_slot == -1:
			Debug.warn("Inventory", "Backpack full, could not add all items")
			inventory_changed.emit()
			return false

		var stack_size := mini(quantity, item.max_stack)
		backpack[empty_slot] = {item = item, quantity = stack_size}
		quantity -= stack_size

	inventory_changed.emit()
	return true


func remove_item_at(index: int, quantity: int = 1) -> bool:
	if index < 0 or index >= backpack.size():
		return false

	var slot: Dictionary = backpack[index]
	if slot.is_empty():
		return false

	Debug.info("Inventory", "Removing item", "%s x%d from slot %d" % [slot.item.item_name, quantity, index])

	slot.quantity -= quantity
	if slot.quantity <= 0:
		backpack[index] = {}

	# Clear selection if this was selected
	if selected_source == "backpack" and selected_index == index:
		deselect()

	inventory_changed.emit()
	return true


func get_backpack_item(index: int) -> Dictionary:
	if index < 0 or index >= backpack.size():
		return {}
	return backpack[index]


func _find_empty_backpack_slot() -> int:
	for i in backpack.size():
		if backpack[i].is_empty():
			return i
	return -1


## EQUIPMENT OPERATIONS

func equip_item(item: ItemData, from_backpack_index: int = -1) -> bool:
	if item == null:
		return false

	if item.item_type == ItemData.ItemType.CONSUMABLE:
		# Consumables go to quick slot
		return _equip_to_slot(item, ItemData.EquipSlot.QUICK_SLOT, from_backpack_index)

	if item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData
		var target_slot := equip.get_target_slot()

		if target_slot == ItemData.EquipSlot.NONE:
			Debug.warn("Inventory", "Cannot equip item", "No valid slot for %s" % item.item_name)
			return false

		# Handle rings - can go to either accessory slot
		if equip.equipment_type == ItemData.EquipmentType.RING:
			# Try accessory 1 first, then 2
			if equipped[ItemData.EquipSlot.ACCESSORY_1].is_empty():
				target_slot = ItemData.EquipSlot.ACCESSORY_1
			elif equipped[ItemData.EquipSlot.ACCESSORY_2].is_empty():
				target_slot = ItemData.EquipSlot.ACCESSORY_2
			else:
				target_slot = ItemData.EquipSlot.ACCESSORY_1  # Swap with first

		return _equip_to_slot(item, target_slot, from_backpack_index)

	return false


func _equip_to_slot(item: ItemData, slot: ItemData.EquipSlot, from_backpack_index: int) -> bool:
	Debug.info("Inventory", "Equipping item", "%s to %s" % [item.item_name, ItemData.get_slot_name(slot)])

	# Get currently equipped item (if any)
	var old_item: Dictionary = equipped[slot]

	# Remove from backpack if specified
	if from_backpack_index >= 0:
		backpack[from_backpack_index] = {}

	# Equip new item
	equipped[slot] = {item = item, quantity = 1}

	# Put old item in backpack if there was one
	if not old_item.is_empty():
		add_item(old_item.item, old_item.quantity)

	equipment_changed.emit(slot)
	inventory_changed.emit()
	return true


func unequip_item(slot: ItemData.EquipSlot) -> bool:
	var item_data: Dictionary = equipped[slot]
	if item_data.is_empty():
		return false

	Debug.info("Inventory", "Unequipping item", "%s from %s" % [item_data.item.item_name, ItemData.get_slot_name(slot)])

	# Try to add to backpack
	if not add_item(item_data.item, item_data.quantity):
		Debug.warn("Inventory", "Cannot unequip", "Backpack is full")
		return false

	# Clear the slot
	equipped[slot] = {}

	# Clear selection if this was selected
	if selected_source == "equipment" and selected_index == slot:
		deselect()

	equipment_changed.emit(slot)
	return true


func get_equipped_item(slot: ItemData.EquipSlot) -> Dictionary:
	if not equipped.has(slot):
		return {}
	return equipped[slot]


func is_slot_blocked(_slot: ItemData.EquipSlot) -> bool:
	# No slots are blocked in this configuration
	return false


## SELECTION OPERATIONS

func select_backpack_item(index: int) -> void:
	var slot: Dictionary = backpack[index]
	if slot.is_empty():
		deselect()
		return

	selected_item = slot.item
	selected_source = "backpack"
	selected_index = index
	item_selected.emit(selected_item, selected_source, selected_index)
	Debug.log("Inventory", "Selected backpack item", "%s at index %d" % [selected_item.item_name, index])


func select_equipment_item(slot: ItemData.EquipSlot) -> void:
	var item_data: Dictionary = equipped[slot]
	if item_data.is_empty():
		deselect()
		return

	selected_item = item_data.item
	selected_source = "equipment"
	selected_index = slot
	item_selected.emit(selected_item, selected_source, selected_index)
	Debug.log("Inventory", "Selected equipped item", "%s at slot %s" % [selected_item.item_name, ItemData.get_slot_name(slot)])


func deselect() -> void:
	selected_item = null
	selected_source = ""
	selected_index = -1
	item_deselected.emit()
	Debug.log("Inventory", "Deselected item")


func has_selection() -> bool:
	return selected_item != null


## ACTION OPERATIONS

func equip_selected() -> bool:
	if not has_selection():
		return false

	if selected_source != "backpack":
		Debug.warn("Inventory", "Cannot equip", "Item not in backpack")
		return false

	var result := equip_item(selected_item, selected_index)
	if result:
		deselect()
	return result


func unequip_selected() -> bool:
	if not has_selection():
		return false

	if selected_source != "equipment":
		Debug.warn("Inventory", "Cannot unequip", "Item not equipped")
		return false

	var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
	return unequip_item(slot)


func use_selected() -> bool:
	if not has_selection():
		return false

	if selected_item.item_type != ItemData.ItemType.CONSUMABLE:
		Debug.warn("Inventory", "Cannot use", "Item is not consumable")
		return false

	Debug.info("Inventory", "Using item", selected_item.item_name)
	# TODO: Apply consumable effect

	# Remove one from stack
	if selected_source == "backpack":
		remove_item_at(selected_index, 1)
	elif selected_source == "equipment":
		var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
		var item_data: Dictionary = equipped[slot]
		item_data.quantity -= 1
		if item_data.quantity <= 0:
			equipped[slot] = {}
			equipment_changed.emit(slot)
		deselect()

	return true


func destroy_selected() -> bool:
	if not has_selection():
		return false

	Debug.info("Inventory", "Destroying item", selected_item.item_name)

	if selected_source == "backpack":
		backpack[selected_index] = {}
		inventory_changed.emit()
	elif selected_source == "equipment":
		var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
		equipped[slot] = {}
		equipment_changed.emit(slot)

	deselect()
	return true


## GOLD OPERATIONS

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
	Debug.info("Inventory", "Gold added", "+%d (Total: %d)" % [amount, gold])


func remove_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	Debug.info("Inventory", "Gold removed", "-%d (Total: %d)" % [amount, gold])
	return true


## UTILITY

func get_total_stat_bonus(stat_name: String) -> int:
	var total := 0
	for slot in EQUIPMENT_SLOTS:
		var item_data: Dictionary = equipped[slot]
		if item_data.is_empty():
			continue
		var item: ItemData = item_data.item
		if item is EquipmentData:
			var equip: EquipmentData = item as EquipmentData
			match stat_name:
				"strength":
					total += equip.bonus_strength
				"dexterity":
					total += equip.bonus_dexterity
				"intelligence":
					total += equip.bonus_intelligence
				"endurance":
					total += equip.bonus_endurance
				"luck":
					total += equip.bonus_luck
				"health":
					total += equip.bonus_health
				"mana":
					total += equip.bonus_mana
				"physical_damage":
					total += equip.bonus_physical_damage
				"magic_damage":
					total += equip.bonus_magic_damage
				"defense":
					total += equip.bonus_defense
	return total


## DEBUG: Add test items
func debug_add_test_items() -> void:
	Debug.info("Inventory", "Adding debug test items")

	# Create a test sword
	var sword := EquipmentData.new()
	sword.id = "test_sword"
	sword.item_name = "Iron Sword"
	sword.description = "A sturdy iron blade."
	sword.rarity = ItemData.Rarity.COMMON
	sword.equipment_type = ItemData.EquipmentType.WEAPON_ONE_HANDED
	sword.bonus_physical_damage = 5
	sword.bonus_strength = 2
	add_item(sword)

	# Create a test helmet
	var helmet := EquipmentData.new()
	helmet.id = "test_helmet"
	helmet.item_name = "Leather Cap"
	helmet.description = "Basic head protection."
	helmet.rarity = ItemData.Rarity.COMMON
	helmet.equipment_type = ItemData.EquipmentType.HELMET
	helmet.bonus_defense = 3
	add_item(helmet)

	# Create a test potion
	var potion := ConsumableData.new()
	potion.id = "health_potion_small"
	potion.item_name = "Small Health Potion"
	potion.description = "Restores a small amount of health."
	potion.rarity = ItemData.Rarity.COMMON
	potion.effect_type = ConsumableData.EffectType.HEAL_HEALTH
	potion.effect_value = 50
	add_item(potion, 5)

	# Create a rare ring
	var ring := EquipmentData.new()
	ring.id = "test_ring"
	ring.item_name = "Ring of Power"
	ring.description = "A ring imbued with ancient power."
	ring.rarity = ItemData.Rarity.RARE
	ring.equipment_type = ItemData.EquipmentType.RING
	ring.bonus_strength = 3
	ring.bonus_crit_chance = 2.5
	add_item(ring)

	# Add some gold
	add_gold(100)
