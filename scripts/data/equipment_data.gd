extends ItemData
class_name EquipmentData
## Equipment item data - weapons, armor, accessories

## What type of equipment this is
@export var equipment_type: EquipmentType = EquipmentType.NONE

## Stat bonuses provided when equipped
@export_group("Stat Bonuses")
@export var bonus_strength: int = 0
@export var bonus_dexterity: int = 0
@export var bonus_intelligence: int = 0
@export var bonus_endurance: int = 0
@export var bonus_luck: int = 0

## Derived stat bonuses
@export_group("Derived Bonuses")
@export var bonus_health: int = 0
@export var bonus_mana: int = 0
@export var bonus_physical_damage: int = 0
@export var bonus_magic_damage: int = 0
@export var bonus_defense: int = 0
@export var bonus_crit_chance: float = 0.0  # Percentage
@export var bonus_crit_damage: float = 0.0  # Percentage
@export var bonus_attack_speed: float = 0.0  # Percentage

## Requirements
@export_group("Requirements")
@export var required_level: int = 1
@export var required_strength: int = 0
@export var required_dexterity: int = 0
@export var required_intelligence: int = 0


func _init() -> void:
	item_type = ItemType.EQUIPMENT
	max_stack = 1


## Get the target equipment slot for this item
func get_target_slot() -> EquipSlot:
	return ItemData.get_slot_for_type(equipment_type)


## Check if this is a two-handed weapon (blocks off-hand)
func is_two_handed() -> bool:
	return equipment_type == EquipmentType.WEAPON_TWO_HANDED


## Get formatted stat bonus text for UI
func get_stat_text() -> String:
	var lines: PackedStringArray = []

	# Primary stats
	if bonus_strength != 0:
		lines.append("+%d Strength" % bonus_strength)
	if bonus_dexterity != 0:
		lines.append("+%d Dexterity" % bonus_dexterity)
	if bonus_intelligence != 0:
		lines.append("+%d Intelligence" % bonus_intelligence)
	if bonus_endurance != 0:
		lines.append("+%d Endurance" % bonus_endurance)
	if bonus_luck != 0:
		lines.append("+%d Luck" % bonus_luck)

	# Derived stats
	if bonus_health != 0:
		lines.append("+%d Health" % bonus_health)
	if bonus_mana != 0:
		lines.append("+%d Mana" % bonus_mana)
	if bonus_physical_damage != 0:
		lines.append("+%d Physical Damage" % bonus_physical_damage)
	if bonus_magic_damage != 0:
		lines.append("+%d Magic Damage" % bonus_magic_damage)
	if bonus_defense != 0:
		lines.append("+%d Defense" % bonus_defense)
	if bonus_crit_chance != 0.0:
		lines.append("+%.1f%% Crit Chance" % bonus_crit_chance)
	if bonus_crit_damage != 0.0:
		lines.append("+%.1f%% Crit Damage" % bonus_crit_damage)
	if bonus_attack_speed != 0.0:
		lines.append("+%.1f%% Attack Speed" % bonus_attack_speed)

	if lines.is_empty():
		return "No bonuses"

	return "\n".join(lines)


## Get equipment type name for display
func get_type_name() -> String:
	match equipment_type:
		EquipmentType.WEAPON_ONE_HANDED:
			return "One-Handed Weapon"
		EquipmentType.WEAPON_TWO_HANDED:
			return "Two-Handed Weapon"
		EquipmentType.WEAPON_RANGED:
			return "Ranged Weapon"
		EquipmentType.HELMET:
			return "Helmet"
		EquipmentType.ARMOR:
			return "Armor"
		EquipmentType.GLOVES:
			return "Gloves"
		EquipmentType.BOOTS:
			return "Boots"
		EquipmentType.RING:
			return "Ring"
		EquipmentType.AMULET:
			return "Amulet"
		EquipmentType.SHIELD:
			return "Shield"
		_:
			return "Equipment"
