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
	# Connect equipment changes to stats recalculation
	equipment_changed.connect(_on_equipment_changed)
	Debug.info("Inventory", "InventoryManager initialized", "Backpack size: %d" % BACKPACK_SIZE)


func _on_equipment_changed(_slot: ItemData.EquipSlot) -> void:
	_recalculate_equipment_bonuses()


func _recalculate_equipment_bonuses() -> void:
	## Recalculate all equipment bonuses and apply to PlayerStats
	PlayerStats.clear_equipment_bonuses()

	for slot in EQUIPMENT_SLOTS:
		var item_data: Dictionary = equipped[slot]
		if item_data.is_empty():
			continue
		var item: ItemData = item_data.item
		if not item is EquipmentData:
			continue
		var equip: EquipmentData = item as EquipmentData

		# Primary stat bonuses (add to equipment bonuses, not base stats)
		if equip.bonus_strength != 0:
			PlayerStats.set_equipment_bonus("strength", PlayerStats.get_equipment_bonus("strength") + equip.bonus_strength)
		if equip.bonus_dexterity != 0:
			PlayerStats.set_equipment_bonus("dexterity", PlayerStats.get_equipment_bonus("dexterity") + equip.bonus_dexterity)
		if equip.bonus_intelligence != 0:
			PlayerStats.set_equipment_bonus("intelligence", PlayerStats.get_equipment_bonus("intelligence") + equip.bonus_intelligence)
		if equip.bonus_vitality != 0:
			PlayerStats.set_equipment_bonus("vitality", PlayerStats.get_equipment_bonus("vitality") + equip.bonus_vitality)
		if equip.bonus_energy != 0:
			PlayerStats.set_equipment_bonus("energy", PlayerStats.get_equipment_bonus("energy") + equip.bonus_energy)
		if equip.bonus_luck != 0:
			PlayerStats.set_equipment_bonus("luck", PlayerStats.get_equipment_bonus("luck") + equip.bonus_luck)

		# Offensive stat bonuses
		if equip.bonus_attack_power != 0:
			PlayerStats.set_equipment_bonus("attack_power", PlayerStats.get_equipment_bonus("attack_power") + equip.bonus_attack_power)
		if equip.bonus_spell_power != 0:
			PlayerStats.set_equipment_bonus("spell_power", PlayerStats.get_equipment_bonus("spell_power") + equip.bonus_spell_power)
		if equip.bonus_attack_speed != 0.0:
			PlayerStats.set_equipment_bonus("attack_speed", PlayerStats.get_equipment_bonus("attack_speed") + equip.bonus_attack_speed)
		if equip.bonus_crit_chance != 0.0:
			PlayerStats.set_equipment_bonus("crit_chance", PlayerStats.get_equipment_bonus("crit_chance") + equip.bonus_crit_chance)
		if equip.bonus_crit_damage != 0.0:
			PlayerStats.set_equipment_bonus("crit_damage", PlayerStats.get_equipment_bonus("crit_damage") + equip.bonus_crit_damage)

		# Defensive stat bonuses
		if equip.bonus_armor != 0:
			PlayerStats.set_equipment_bonus("armor", PlayerStats.get_equipment_bonus("armor") + equip.bonus_armor)
		if equip.bonus_magic_resistance != 0:
			PlayerStats.set_equipment_bonus("magic_resistance", PlayerStats.get_equipment_bonus("magic_resistance") + equip.bonus_magic_resistance)
		if equip.bonus_dodge_chance != 0.0:
			PlayerStats.set_equipment_bonus("dodge_chance", PlayerStats.get_equipment_bonus("dodge_chance") + equip.bonus_dodge_chance)
		if equip.bonus_health != 0:
			PlayerStats.set_equipment_bonus("health", PlayerStats.get_equipment_bonus("health") + equip.bonus_health)
		if equip.bonus_mana != 0:
			PlayerStats.set_equipment_bonus("mana", PlayerStats.get_equipment_bonus("mana") + equip.bonus_mana)
		if equip.bonus_stamina != 0:
			PlayerStats.set_equipment_bonus("stamina", PlayerStats.get_equipment_bonus("stamina") + equip.bonus_stamina)

		# Utility stat bonuses
		if equip.bonus_movement_speed != 0.0:
			PlayerStats.set_equipment_bonus("movement_speed", PlayerStats.get_equipment_bonus("movement_speed") + equip.bonus_movement_speed)
		if equip.bonus_life_regen != 0.0:
			PlayerStats.set_equipment_bonus("life_regen", PlayerStats.get_equipment_bonus("life_regen") + equip.bonus_life_regen)
		if equip.bonus_mana_regen != 0.0:
			PlayerStats.set_equipment_bonus("mana_regen", PlayerStats.get_equipment_bonus("mana_regen") + equip.bonus_mana_regen)
		if equip.bonus_stamina_regen != 0.0:
			PlayerStats.set_equipment_bonus("stamina_regen", PlayerStats.get_equipment_bonus("stamina_regen") + equip.bonus_stamina_regen)

	Debug.log("Inventory", "Equipment bonuses recalculated")


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

		# Check stat requirements
		if not equip.can_equip():
			Debug.warn("Inventory", "Cannot equip item", "Requirements not met for %s" % item.item_name)
			return false

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


## Get the weapon damage from equipped weapon (for combat calculations)
func get_equipped_weapon_damage() -> float:
	var weapon_slot := get_equipped_item(ItemData.EquipSlot.MAIN_HAND)
	if weapon_slot.is_empty():
		return 1.0  # Unarmed base damage
	var weapon: ItemData = weapon_slot.get("item")
	if weapon is EquipmentData:
		return float(weapon.weapon_damage) if weapon.weapon_damage > 0 else 1.0
	return 1.0


## Get the attack speed from equipped weapon
func get_equipped_weapon_attack_speed() -> float:
	var weapon_slot := get_equipped_item(ItemData.EquipSlot.MAIN_HAND)
	if weapon_slot.is_empty():
		return 1.0  # Unarmed attack speed
	var weapon: ItemData = weapon_slot.get("item")
	if weapon is EquipmentData:
		return weapon.weapon_attack_speed if weapon.weapon_attack_speed > 0 else 1.0
	return 1.0


## Get the weapon category from equipped weapon (melee_1h, melee_2h, ranged, magic)
func get_equipped_weapon_category() -> String:
	var weapon_slot := get_equipped_item(ItemData.EquipSlot.MAIN_HAND)
	if weapon_slot.is_empty():
		return ""  # No weapon equipped
	var weapon: ItemData = weapon_slot.get("item")
	if weapon is EquipmentData:
		return weapon.weapon_category
	return ""


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


## DRAG & DROP OPERATIONS

func drag_drop_swap(from_source: String, from_index: int, to_source: String, to_index: int) -> bool:
	## Handle drag & drop swap between any two slots
	Debug.info("Inventory", "Drag drop swap", "%s[%d] -> %s[%d]" % [from_source, from_index, to_source, to_index])

	# Backpack to Backpack
	if from_source == "backpack" and to_source == "backpack":
		return _swap_backpack_slots(from_index, to_index)

	# Backpack to Equipment (equip item)
	if from_source == "backpack" and to_source == "equipment":
		return _drag_equip_item(from_index, to_index as ItemData.EquipSlot)

	# Equipment to Backpack (unequip item)
	if from_source == "equipment" and to_source == "backpack":
		return _drag_unequip_item(from_index as ItemData.EquipSlot, to_index)

	# Equipment to Equipment (swap equipment)
	if from_source == "equipment" and to_source == "equipment":
		return _swap_equipment_slots(from_index as ItemData.EquipSlot, to_index as ItemData.EquipSlot)

	return false


func _swap_backpack_slots(index_a: int, index_b: int) -> bool:
	## Swap two backpack slots
	if index_a < 0 or index_a >= backpack.size():
		return false
	if index_b < 0 or index_b >= backpack.size():
		return false

	var temp: Dictionary = backpack[index_a]
	backpack[index_a] = backpack[index_b]
	backpack[index_b] = temp

	inventory_changed.emit()
	return true


func _drag_equip_item(backpack_idx: int, equip_slot: ItemData.EquipSlot) -> bool:
	## Equip item from backpack via drag, swap if slot occupied
	if backpack_idx < 0 or backpack_idx >= backpack.size():
		return false

	var backpack_data: Dictionary = backpack[backpack_idx]
	if backpack_data.is_empty():
		return false

	var item: ItemData = backpack_data.item
	var charges: int = backpack_data.get("charges", 0)

	# Get currently equipped item
	var equipped_data: Dictionary = equipped[equip_slot]

	# Clear backpack slot
	backpack[backpack_idx] = {}

	# If there was an equipped item, move it to the backpack slot
	if not equipped_data.is_empty():
		backpack[backpack_idx] = equipped_data

	# Equip the new item
	equipped[equip_slot] = {item = item, quantity = 1, charges = charges}

	equipment_changed.emit(equip_slot)
	inventory_changed.emit()
	return true


func _drag_unequip_item(equip_slot: ItemData.EquipSlot, backpack_idx: int) -> bool:
	## Unequip item to backpack via drag, swap if slot occupied
	var equipped_data: Dictionary = equipped[equip_slot]
	if equipped_data.is_empty():
		return false

	if backpack_idx < 0 or backpack_idx >= backpack.size():
		return false

	var backpack_data: Dictionary = backpack[backpack_idx]

	# If backpack slot has item, check if it can be equipped to this slot
	if not backpack_data.is_empty():
		var bp_item: ItemData = backpack_data.item
		# Verify the backpack item can go to this equipment slot
		if not _can_item_equip_to_slot(bp_item, equip_slot):
			return false

	# Swap the items
	backpack[backpack_idx] = equipped_data
	if backpack_data.is_empty():
		equipped[equip_slot] = {}
	else:
		equipped[equip_slot] = backpack_data

	equipment_changed.emit(equip_slot)
	inventory_changed.emit()
	return true


func _swap_equipment_slots(slot_a: ItemData.EquipSlot, slot_b: ItemData.EquipSlot) -> bool:
	## Swap two equipment slots (only works for same-type slots like rings)
	var data_a: Dictionary = equipped[slot_a]
	var data_b: Dictionary = equipped[slot_b]

	# Check if swap is valid
	if not data_a.is_empty() and not _can_item_equip_to_slot(data_a.item, slot_b):
		return false
	if not data_b.is_empty() and not _can_item_equip_to_slot(data_b.item, slot_a):
		return false

	equipped[slot_a] = data_b
	equipped[slot_b] = data_a

	equipment_changed.emit(slot_a)
	equipment_changed.emit(slot_b)
	return true


func _can_item_equip_to_slot(item: ItemData, slot: ItemData.EquipSlot) -> bool:
	## Check if an item can be equipped to a specific slot
	if item == null:
		return true  # Empty can go anywhere

	if item.item_type == ItemData.ItemType.CONSUMABLE:
		return slot == ItemData.EquipSlot.QUICK_SLOT

	if item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData
		var target := equip.get_target_slot()

		# Rings can go to either accessory slot
		if equip.equipment_type == ItemData.EquipmentType.RING:
			return slot == ItemData.EquipSlot.ACCESSORY_1 or slot == ItemData.EquipSlot.ACCESSORY_2

		return target == slot

	return false


func split_stack(source: String, index: int) -> bool:
	## Split a stack in half, putting half in the first empty slot
	var slot_data: Dictionary
	if source == "backpack":
		if index < 0 or index >= backpack.size():
			return false
		slot_data = backpack[index]
	else:
		return false  # Can only split backpack items

	if slot_data.is_empty():
		return false

	var item: ItemData = slot_data.item
	var quantity: int = slot_data.quantity

	# Can't split single items or non-stackables
	if quantity <= 1 or item.max_stack <= 1:
		Debug.warn("Inventory", "Cannot split", "Not a splittable stack")
		return false

	# Find empty slot
	var empty_idx := _find_empty_backpack_slot()
	if empty_idx == -1:
		Debug.warn("Inventory", "Cannot split", "No empty slot")
		return false

	# Split in half
	var split_amount := quantity / 2
	slot_data.quantity = quantity - split_amount
	backpack[empty_idx] = {item = item, quantity = split_amount, charges = 0}

	Debug.info("Inventory", "Split stack", "%s: %d -> %d + %d" % [item.item_name, quantity, slot_data.quantity, split_amount])
	inventory_changed.emit()
	return true


func destroy_item(source: String, index: int, force: bool = false) -> Dictionary:
	## Destroy an item, returns {success: bool, needs_confirm: bool, item: ItemData}
	var slot_data: Dictionary
	var item: ItemData

	if source == "backpack":
		if index < 0 or index >= backpack.size():
			return {success = false}
		slot_data = backpack[index]
	elif source == "equipment":
		var slot := index as ItemData.EquipSlot
		if not equipped.has(slot):
			return {success = false}
		slot_data = equipped[slot]
	else:
		return {success = false}

	if slot_data.is_empty():
		return {success = false}

	item = slot_data.item

	# Check if confirmation needed (rare or better)
	if not force and item.rarity >= ItemData.Rarity.RARE:
		return {success = false, needs_confirm = true, item = item}

	# Destroy the item
	Debug.info("Inventory", "Destroying item", item.item_name)
	if source == "backpack":
		backpack[index] = {}
		inventory_changed.emit()
	else:
		var slot := index as ItemData.EquipSlot
		equipped[slot] = {}
		equipment_changed.emit(slot)

	deselect()
	return {success = true, needs_confirm = false, item = item}


func use_item(source: String, index: int) -> Dictionary:
	## Use an item - for consumables, this consumes one charge
	## Returns {success: bool, message: String}
	var slot_data: Dictionary
	var item: ItemData

	if source == "backpack":
		if index < 0 or index >= backpack.size():
			return {success = false, message = "Invalid slot"}
		slot_data = backpack[index]
	elif source == "equipment":
		var slot := index as ItemData.EquipSlot
		if not equipped.has(slot):
			return {success = false, message = "Invalid slot"}
		slot_data = equipped[slot]
	else:
		return {success = false, message = "Invalid source"}

	if slot_data.is_empty():
		return {success = false, message = "Empty slot"}

	item = slot_data.item

	# Handle consumables (potions, etc.)
	if item is ConsumableData:
		var charges: int = slot_data.get("charges", 0)
		if charges <= 0:
			return {success = false, message = "No charges left", item = item}

		# Consume one charge
		slot_data.charges = charges - 1
		Debug.info("Inventory", "Used consumable", "%s (%d charges left)" % [item.item_name, slot_data.charges])

		# Emit change signal to update UI
		if source == "backpack":
			inventory_changed.emit()
		else:
			equipment_changed.emit(index as ItemData.EquipSlot)

		return {success = true, message = "Used %s" % item.item_name, item = item, charges_left = slot_data.charges}

	return {success = false, message = "Cannot use this item", item = item}


## LEGACY SWAP OPERATIONS (kept for compatibility)

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
	Debug.info("Inventory", "swap_with_backpack_slot called", "target=%d swap_mode=%s has_selection=%s selected_source=%s selected_index=%d" % [target_index, swap_mode, has_selection(), selected_source, selected_index])

	if not swap_mode or not has_selection():
		Debug.warn("Inventory", "Swap rejected", "swap_mode=%s has_selection=%s" % [swap_mode, has_selection()])
		return false

	if selected_source != "backpack":
		Debug.warn("Inventory", "Cannot swap", "Source must be in backpack (was %s)" % selected_source)
		exit_swap_mode()
		return false

	if target_index == selected_index:
		Debug.info("Inventory", "Same slot clicked", "Exiting swap mode")
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

func get_total_stat_bonus(stat_name: String) -> float:
	## Returns total equipment bonus for a stat. Uses PlayerStats cache.
	return PlayerStats.get_equipment_bonus(stat_name)


## Add starting items from database (replaces hardcoded test items)
func add_starting_items() -> void:
	Debug.info("Inventory", "Adding starting items from database")

	# Starting equipment from database (common quality base items)
	var starting_items := [
		"wep_sword_iron",      # Basic iron sword
		"wep_bow_short",       # Short bow (for testing ranged)
		"wep_staff_oak",       # Oak staff (for testing magic)
		"arm_helmet_leather",  # Leather cap
		"arm_chest_leather",   # Leather tunic
		"arm_gloves_leather",  # Leather gloves
		"arm_boots_leather",   # Leather boots
		"acc_ring_copper",     # Copper ring
		"acc_amulet_bone",     # Bone amulet
	]

	for item_id in starting_items:
		var item := DatabaseLoader.create_equipment(item_id)
		if item != null:
			add_item(item)
		else:
			Debug.warn("Inventory", "Could not create starting item: %s" % item_id)

	# Consumables (hardcoded until consumables database is added)
	var health_potion := ConsumableData.new()
	health_potion.id = "con_potion_health"
	health_potion.item_name = "Health Potion"
	health_potion.description = "Restores 50 health instantly."
	health_potion.rarity = ItemData.Rarity.COMMON
	health_potion.effect_type = ConsumableData.EffectType.HEAL_HEALTH
	health_potion.effect_value = 50
	health_potion.max_charges = 5
	add_item(health_potion)

	var mana_potion := ConsumableData.new()
	mana_potion.id = "con_potion_mana"
	mana_potion.item_name = "Mana Potion"
	mana_potion.description = "Restores 30 mana instantly."
	mana_potion.rarity = ItemData.Rarity.COMMON
	mana_potion.effect_type = ConsumableData.EffectType.HEAL_MANA
	mana_potion.effect_value = 30
	mana_potion.max_charges = 5
	add_item(mana_potion)

	# Starting gold
	add_gold(100)

	Debug.info("Inventory", "Starting items added")


## DEBUG: Add test items with affixes (for testing magic/rare item generation)
func debug_add_magic_items() -> void:
	Debug.info("Inventory", "Adding magic test items")

	# Generate some magic items with random affixes
	var magic_sword := DatabaseLoader.create_magic_equipment("wep_sword_steel", 5, 2)
	if magic_sword:
		add_item(magic_sword)

	var rare_armor := DatabaseLoader.create_magic_equipment("arm_chest_chainmail", 5, 4)
	if rare_armor:
		rare_armor.rarity = ItemData.Rarity.RARE
		add_item(rare_armor)

	Debug.info("Inventory", "Magic test items added")
