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

## Swap mode state
var swap_mode: bool = false
signal swap_mode_changed(active: bool)


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

func add_item(item: ItemData, quantity: int = 1, charges: int = -1) -> bool:
	if item == null or quantity <= 0:
		return false

	Debug.info("Inventory", "Adding item", "%s x%d" % [item.item_name, quantity])

	# Handle consumables with charges
	if item is ConsumableData:
		var consumable: ConsumableData = item as ConsumableData
		# If charges not specified, use max charges
		if charges < 0:
			charges = consumable.max_charges

		# Each consumable takes one slot (no stacking, uses charges instead)
		for i in quantity:
			var empty_slot := _find_empty_backpack_slot()
			if empty_slot == -1:
				Debug.warn("Inventory", "Backpack full, could not add all items")
				inventory_changed.emit()
				return false
			backpack[empty_slot] = {item = item, quantity = 1, charges = charges}

		inventory_changed.emit()
		return true

	# Try to stack with existing items first (non-consumables)
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
		backpack[empty_slot] = {item = item, quantity = stack_size, charges = 0}
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

	# Get charges from backpack slot if consumable
	var item_charges := 0
	if from_backpack_index >= 0:
		var backpack_slot: Dictionary = backpack[from_backpack_index]
		if backpack_slot.has("charges"):
			item_charges = backpack_slot.charges
		backpack[from_backpack_index] = {}

	# Equip new item (preserve charges for consumables)
	equipped[slot] = {item = item, quantity = 1, charges = item_charges}

	# Put old item in backpack if there was one
	if not old_item.is_empty():
		var old_charges: int = old_item.get("charges", 0)
		if old_item.item is ConsumableData:
			add_item(old_item.item, 1, old_charges)
		else:
			add_item(old_item.item, old_item.quantity)

	equipment_changed.emit(slot)
	inventory_changed.emit()
	return true


func unequip_item(slot: ItemData.EquipSlot) -> bool:
	var item_data: Dictionary = equipped[slot]
	if item_data.is_empty():
		return false

	Debug.info("Inventory", "Unequipping item", "%s from %s" % [item_data.item.item_name, ItemData.get_slot_name(slot)])

	# Try to add to backpack (preserve charges for consumables)
	var item_charges: int = item_data.get("charges", 0)
	if item_data.item is ConsumableData:
		if not add_item(item_data.item, 1, item_charges):
			Debug.warn("Inventory", "Cannot unequip", "Backpack is full")
			return false
	else:
		if not add_item(item_data.item, item_data.quantity):
			Debug.warn("Inventory", "Cannot unequip", "Backpack is full")
			return false

	# Clear the slot
	equipped[slot] = {}

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

	var item_to_equip := selected_item
	var target_slot := _get_equip_target_slot(item_to_equip)

	var result := equip_item(selected_item, selected_index)
	if result and target_slot != ItemData.EquipSlot.NONE:
		# Select the item in its new equipment slot
		select_equipment_item(target_slot)
	return result


func _get_equip_target_slot(item: ItemData) -> ItemData.EquipSlot:
	## Helper to determine which slot an item will be equipped to
	if item.item_type == ItemData.ItemType.CONSUMABLE:
		return ItemData.EquipSlot.QUICK_SLOT

	if item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData
		var target_slot := equip.get_target_slot()

		# Handle rings - check which slot is available
		if equip.equipment_type == ItemData.EquipmentType.RING:
			if equipped[ItemData.EquipSlot.ACCESSORY_1].is_empty():
				return ItemData.EquipSlot.ACCESSORY_1
			elif equipped[ItemData.EquipSlot.ACCESSORY_2].is_empty():
				return ItemData.EquipSlot.ACCESSORY_2
			else:
				return ItemData.EquipSlot.ACCESSORY_1

		return target_slot

	return ItemData.EquipSlot.NONE


func unequip_selected() -> bool:
	if not has_selection():
		return false

	if selected_source != "equipment":
		Debug.warn("Inventory", "Cannot unequip", "Item not equipped")
		return false

	var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
	var item_to_unequip := selected_item

	# Find where the item will go in backpack
	var target_backpack_index := _find_empty_backpack_slot()

	var result := unequip_item(slot)
	if result and target_backpack_index >= 0:
		# Select the item in its new backpack slot
		select_backpack_item(target_backpack_index)
	return result


func use_selected() -> bool:
	if not has_selection():
		return false

	if selected_item.item_type != ItemData.ItemType.CONSUMABLE:
		Debug.warn("Inventory", "Cannot use", "Item is not consumable")
		return false

	# Check if consumable has charges
	var current_charges := 0
	if selected_source == "backpack":
		current_charges = backpack[selected_index].get("charges", 0)
	elif selected_source == "equipment":
		var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
		current_charges = equipped[slot].get("charges", 0)

	if current_charges <= 0:
		Debug.warn("Inventory", "Cannot use", "No charges remaining")
		return false

	Debug.info("Inventory", "Using item", "%s (charges: %d -> %d)" % [selected_item.item_name, current_charges, current_charges - 1])
	# TODO: Apply consumable effect

	# Decrement charges (item stays even at 0 charges)
	if selected_source == "backpack":
		backpack[selected_index].charges = current_charges - 1
		inventory_changed.emit()
	elif selected_source == "equipment":
		var slot: ItemData.EquipSlot = selected_index as ItemData.EquipSlot
		equipped[slot].charges = current_charges - 1
		equipment_changed.emit(slot)

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


## SWAP OPERATIONS

func enter_swap_mode() -> void:
	if not has_selection():
		return
	swap_mode = true
	swap_mode_changed.emit(true)
	Debug.info("Inventory", "Swap mode entered", "Select target slot")


func exit_swap_mode() -> void:
	swap_mode = false
	swap_mode_changed.emit(false)
	Debug.info("Inventory", "Swap mode exited")


func swap_with_backpack_slot(target_index: int) -> bool:
	if not swap_mode or not has_selection():
		return false

	if selected_source != "backpack":
		Debug.warn("Inventory", "Cannot swap", "Source must be in backpack")
		exit_swap_mode()
		return false

	if target_index == selected_index:
		# Clicked same slot, just exit swap mode
		exit_swap_mode()
		return false

	Debug.info("Inventory", "Swapping items", "Slot %d <-> Slot %d" % [selected_index, target_index])

	# Swap the two slots
	var temp: Dictionary = backpack[selected_index]
	backpack[selected_index] = backpack[target_index]
	backpack[target_index] = temp

	# Select the item in its new position
	exit_swap_mode()
	inventory_changed.emit()
	select_backpack_item(target_index)

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


## DEBUG: Add test items - one for each equipment slot
func debug_add_test_items() -> void:
	Debug.info("Inventory", "Adding debug test items for all slots")

	# HEAD - Helmet
	var helmet := EquipmentData.new()
	helmet.id = "test_helmet"
	helmet.item_name = "Iron Helm"
	helmet.description = "A sturdy iron helmet."
	helmet.rarity = ItemData.Rarity.UNCOMMON
	helmet.equipment_type = ItemData.EquipmentType.HELMET
	helmet.bonus_defense = 5
	helmet.bonus_endurance = 2
	add_item(helmet)

	# BODY - Armor
	var armor := EquipmentData.new()
	armor.id = "test_armor"
	armor.item_name = "Chainmail"
	armor.description = "Interlocking metal rings provide solid protection."
	armor.rarity = ItemData.Rarity.UNCOMMON
	armor.equipment_type = ItemData.EquipmentType.ARMOR
	armor.bonus_defense = 10
	armor.bonus_health = 20
	add_item(armor)

	# HANDS - Gloves
	var gloves := EquipmentData.new()
	gloves.id = "test_gloves"
	gloves.item_name = "Leather Gloves"
	gloves.description = "Supple leather gloves that improve grip."
	gloves.rarity = ItemData.Rarity.COMMON
	gloves.equipment_type = ItemData.EquipmentType.GLOVES
	gloves.bonus_dexterity = 3
	gloves.bonus_attack_speed = 5.0
	add_item(gloves)

	# BOOTS - Boots
	var boots := EquipmentData.new()
	boots.id = "test_boots"
	boots.item_name = "Traveler's Boots"
	boots.description = "Well-worn boots made for long journeys."
	boots.rarity = ItemData.Rarity.COMMON
	boots.equipment_type = ItemData.EquipmentType.BOOTS
	boots.bonus_dexterity = 2
	boots.bonus_defense = 2
	add_item(boots)

	# MAIN_HAND - Weapon
	var sword := EquipmentData.new()
	sword.id = "test_sword"
	sword.item_name = "Steel Longsword"
	sword.description = "A well-balanced blade forged from quality steel."
	sword.rarity = ItemData.Rarity.RARE
	sword.equipment_type = ItemData.EquipmentType.WEAPON_ONE_HANDED
	sword.bonus_physical_damage = 12
	sword.bonus_strength = 3
	sword.bonus_crit_chance = 5.0
	add_item(sword)

	# ACCESSORY_1 - Ring
	var ring := EquipmentData.new()
	ring.id = "test_ring"
	ring.item_name = "Ruby Ring"
	ring.description = "A gold ring set with a fiery ruby."
	ring.rarity = ItemData.Rarity.RARE
	ring.equipment_type = ItemData.EquipmentType.RING
	ring.bonus_strength = 4
	ring.bonus_crit_damage = 10.0
	add_item(ring)

	# ACCESSORY_2 - Amulet
	var amulet := EquipmentData.new()
	amulet.id = "test_amulet"
	amulet.item_name = "Sapphire Pendant"
	amulet.description = "A silver pendant with a deep blue sapphire."
	amulet.rarity = ItemData.Rarity.EPIC
	amulet.equipment_type = ItemData.EquipmentType.AMULET
	amulet.bonus_intelligence = 5
	amulet.bonus_mana = 30
	amulet.bonus_magic_damage = 8
	add_item(amulet)

	# QUICK_SLOT - Consumable (Health Potion) - 5/5 charges
	var potion := ConsumableData.new()
	potion.id = "health_potion"
	potion.item_name = "Health Potion"
	potion.description = "Restores 50 health instantly."
	potion.rarity = ItemData.Rarity.COMMON
	potion.effect_type = ConsumableData.EffectType.HEAL_HEALTH
	potion.effect_value = 50
	potion.max_charges = 5
	add_item(potion)  # Adds with 5/5 charges

	# Extra consumable - Mana Potion - 5/5 charges
	var mana_potion := ConsumableData.new()
	mana_potion.id = "mana_potion"
	mana_potion.item_name = "Mana Potion"
	mana_potion.description = "Restores 30 mana instantly."
	mana_potion.rarity = ItemData.Rarity.COMMON
	mana_potion.effect_type = ConsumableData.EffectType.HEAL_MANA
	mana_potion.effect_value = 30
	mana_potion.max_charges = 5
	add_item(mana_potion)  # Adds with 5/5 charges

	# Add some gold
	add_gold(250)
