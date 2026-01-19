extends Resource
class_name ItemData
## Base item data resource - all items inherit from this

## Item rarities
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Item types
enum ItemType { EQUIPMENT, CONSUMABLE, KEY }

## Equipment slots
enum EquipSlot {
	NONE,
	HEAD,
	BODY,
	HANDS,
	BOOTS,
	MAIN_HAND,
	ACCESSORY_1,
	ACCESSORY_2,
	QUICK_SLOT
}

## Equipment subtypes
enum EquipmentType {
	NONE,
	# Weapons
	WEAPON_ONE_HANDED,
	WEAPON_TWO_HANDED,
	WEAPON_RANGED,
	# Armor
	HELMET,
	ARMOR,
	GLOVES,
	BOOTS,
	RING,
	AMULET
}

## Core properties
@export var id: String = ""
@export var item_name: String = "Unknown Item"
@export var description: String = ""
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON
@export var item_type: ItemType = ItemType.EQUIPMENT

## Stack settings (mainly for consumables)
@export var max_stack: int = 1
@export var sell_value: int = 0


## Get rarity color for UI display
static func get_rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.COMMON:
			return Color(0.7, 0.7, 0.7)  # Gray
		Rarity.UNCOMMON:
			return Color(0.2, 0.8, 0.2)  # Green
		Rarity.RARE:
			return Color(0.2, 0.4, 1.0)  # Blue
		Rarity.EPIC:
			return Color(0.6, 0.2, 0.8)  # Purple
		Rarity.LEGENDARY:
			return Color(1.0, 0.6, 0.0)  # Orange
		_:
			return Color.WHITE


## Get rarity name
static func get_rarity_name(r: Rarity) -> String:
	match r:
		Rarity.COMMON:
			return "Common"
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		Rarity.LEGENDARY:
			return "Legendary"
		_:
			return "Unknown"


## Get slot name for display
static func get_slot_name(slot: EquipSlot) -> String:
	match slot:
		EquipSlot.HEAD:
			return "Head"
		EquipSlot.BODY:
			return "Body"
		EquipSlot.HANDS:
			return "Hands"
		EquipSlot.BOOTS:
			return "Boots"
		EquipSlot.MAIN_HAND:
			return "Weapon"
		EquipSlot.ACCESSORY_1:
			return "Ring"
		EquipSlot.ACCESSORY_2:
			return "Amulet"
		EquipSlot.QUICK_SLOT:
			return "Quick Slot"
		_:
			return "None"


## Get the appropriate slot for an equipment type
static func get_slot_for_type(equip_type: EquipmentType) -> EquipSlot:
	match equip_type:
		EquipmentType.HELMET:
			return EquipSlot.HEAD
		EquipmentType.ARMOR:
			return EquipSlot.BODY
		EquipmentType.GLOVES:
			return EquipSlot.HANDS
		EquipmentType.BOOTS:
			return EquipSlot.BOOTS
		EquipmentType.WEAPON_ONE_HANDED, EquipmentType.WEAPON_TWO_HANDED, EquipmentType.WEAPON_RANGED:
			return EquipSlot.MAIN_HAND
		EquipmentType.RING:
			return EquipSlot.ACCESSORY_1  # Default, can also go to ACCESSORY_2
		EquipmentType.AMULET:
			return EquipSlot.ACCESSORY_2  # Amulets use accessory slot
		_:
			return EquipSlot.NONE


#===============================================================================
# SERIALIZATION (for loot persistence across chunk loads)
#===============================================================================

## Serialize item to dictionary for storage
func to_dict() -> Dictionary:
	return {
		"id": id,
		"item_name": item_name,
		"description": description,
		"rarity": rarity,
		"item_type": item_type,
		"max_stack": max_stack,
		"sell_value": sell_value,
		"class_type": "ItemData"
	}


## Deserialize item from dictionary
static func from_dict(data: Dictionary) -> ItemData:
	var class_type: String = data.get("class_type", "ItemData")

	# Handle equipment data
	if class_type == "EquipmentData":
		return EquipmentData.from_dict(data)

	# Handle key items (simple recreation from ID)
	var item_id: String = data.get("id", "")
	if item_id.begins_with("key_"):
		var key_item := ItemData.new()
		key_item.id = item_id
		key_item.item_name = data.get("item_name", "Key")
		key_item.description = data.get("description", "")
		key_item.rarity = data.get("rarity", Rarity.COMMON)
		key_item.item_type = ItemType.KEY
		return key_item

	# Base item data
	var item := ItemData.new()
	item.id = item_id
	item.item_name = data.get("item_name", "Unknown Item")
	item.description = data.get("description", "")
	item.rarity = data.get("rarity", Rarity.COMMON)
	item.item_type = data.get("item_type", ItemType.EQUIPMENT)
	item.max_stack = data.get("max_stack", 1)
	item.sell_value = data.get("sell_value", 0)
	return item
