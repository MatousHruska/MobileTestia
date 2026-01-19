extends ItemData
class_name EquipmentData
## Equipment item data - weapons, armor, accessories

## What type of equipment this is
@export var equipment_type: EquipmentType = EquipmentType.NONE

## Weapon properties (only for weapons)
@export_group("Weapon Stats")
@export var weapon_damage: int = 0         # Total weapon damage (sum of all types)
@export var physical_damage: int = 0       # Physical portion of weapon damage
@export var fire_damage: int = 0           # Fire elemental damage
@export var cold_damage: int = 0           # Cold elemental damage
@export var lightning_damage: int = 0      # Lightning elemental damage
@export var poison_damage: int = 0         # Poison elemental damage
@export var weapon_attack_speed: float = 1.0  # Attacks per second (weapon base)
@export var weapon_category: String = ""   # melee_1h, melee_2h, ranged, magic

## Stat bonuses provided when equipped
@export_group("Stat Bonuses")
@export var bonus_strength: int = 0
@export var bonus_dexterity: int = 0
@export var bonus_intelligence: int = 0
@export var bonus_vitality: int = 0
@export var bonus_energy: int = 0
@export var bonus_luck: int = 0

## Offensive stat bonuses
@export_group("Offensive Bonuses")
@export var bonus_attack_power: int = 0      # Flat bonus added to weapon-based attacks
@export var bonus_spell_power: int = 0       # Flat bonus added to spell damage
@export var bonus_attack_speed: float = 0.0  # Percentage
@export var bonus_crit_chance: float = 0.0   # Percentage
@export var bonus_crit_damage: float = 0.0   # Percentage

## Defensive stat bonuses
@export_group("Defensive Bonuses")
@export var bonus_armor: int = 0
@export var bonus_magic_resistance: int = 0
@export var bonus_dodge_chance: float = 0.0  # Percentage
@export var bonus_health: int = 0
@export var bonus_mana: int = 0
@export var bonus_stamina: int = 0

## Utility stat bonuses
@export_group("Utility Bonuses")
@export var bonus_movement_speed: float = 0.0  # Percentage
@export var bonus_life_regen: float = 0.0  # Per second
@export var bonus_mana_regen: float = 0.0  # Per second
@export var bonus_stamina_regen: float = 0.0  # Per second

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


## Check if this is a two-handed weapon
func is_two_handed() -> bool:
	return equipment_type == EquipmentType.WEAPON_TWO_HANDED


## Get formatted stat bonus text for UI
func get_stat_text() -> String:
	var lines: PackedStringArray = []

	# Weapon damage (only for weapons)
	if weapon_damage > 0:
		var dmg_parts: PackedStringArray = []
		if physical_damage > 0:
			dmg_parts.append("%d Physical" % physical_damage)
		if fire_damage > 0:
			dmg_parts.append("%d Fire" % fire_damage)
		if cold_damage > 0:
			dmg_parts.append("%d Cold" % cold_damage)
		if lightning_damage > 0:
			dmg_parts.append("%d Lightning" % lightning_damage)
		if poison_damage > 0:
			dmg_parts.append("%d Poison" % poison_damage)

		if dmg_parts.size() > 0:
			lines.append("%d Damage (%s)" % [weapon_damage, ", ".join(dmg_parts)])
		else:
			lines.append("%d Damage" % weapon_damage)

		lines.append("%.1f Attacks/sec" % weapon_attack_speed)

	# Primary stats
	if bonus_strength != 0:
		lines.append("+%d STR" % bonus_strength)
	if bonus_dexterity != 0:
		lines.append("+%d DEX" % bonus_dexterity)
	if bonus_intelligence != 0:
		lines.append("+%d INT" % bonus_intelligence)
	if bonus_vitality != 0:
		lines.append("+%d VIT" % bonus_vitality)
	if bonus_energy != 0:
		lines.append("+%d ENE" % bonus_energy)
	if bonus_luck != 0:
		lines.append("+%d LUK" % bonus_luck)

	# Offensive stats
	if bonus_attack_power != 0:
		lines.append("+%d Attack Power" % bonus_attack_power)
	if bonus_spell_power != 0:
		lines.append("+%d Spell Power" % bonus_spell_power)
	if bonus_attack_speed != 0.0:
		lines.append("+%.0f%% Atk Spd" % bonus_attack_speed)
	if bonus_crit_chance != 0.0:
		lines.append("+%.1f%% Crit" % bonus_crit_chance)
	if bonus_crit_damage != 0.0:
		lines.append("+%.0f%% Crit Dmg" % bonus_crit_damage)

	# Defensive stats
	if bonus_armor != 0:
		lines.append("+%d Armor" % bonus_armor)
	if bonus_magic_resistance != 0:
		lines.append("+%d Magic Resist" % bonus_magic_resistance)
	if bonus_dodge_chance != 0.0:
		lines.append("+%.1f%% Dodge" % bonus_dodge_chance)
	if bonus_health != 0:
		lines.append("+%d Health" % bonus_health)
	if bonus_mana != 0:
		lines.append("+%d Mana" % bonus_mana)
	if bonus_stamina != 0:
		lines.append("+%d Stamina" % bonus_stamina)

	# Utility stats
	if bonus_movement_speed != 0.0:
		lines.append("+%.0f%% Move Spd" % bonus_movement_speed)
	if bonus_life_regen != 0.0:
		lines.append("+%.1f Life/s" % bonus_life_regen)
	if bonus_mana_regen != 0.0:
		lines.append("+%.1f Mana/s" % bonus_mana_regen)
	if bonus_stamina_regen != 0.0:
		lines.append("+%.1f Stam/s" % bonus_stamina_regen)

	if lines.is_empty():
		return "No bonuses"

	return "\n".join(lines)


## Check if player meets stat requirements to equip this item
func can_equip() -> bool:
	if PlayerStats.level < required_level:
		return false
	if PlayerStats.strength < required_strength:
		return false
	if PlayerStats.dexterity < required_dexterity:
		return false
	if PlayerStats.intelligence < required_intelligence:
		return false
	return true


## Get requirement text for UI (shows unmet requirements in red)
func get_requirement_text() -> String:
	var lines: PackedStringArray = []

	if required_level > 1:
		var met := PlayerStats.level >= required_level
		var color := "green" if met else "red"
		lines.append("[color=%s]Requires Level %d[/color]" % [color, required_level])
	if required_strength > 0:
		var met := PlayerStats.strength >= required_strength
		var color := "green" if met else "red"
		lines.append("[color=%s]Requires %d STR[/color]" % [color, required_strength])
	if required_dexterity > 0:
		var met := PlayerStats.dexterity >= required_dexterity
		var color := "green" if met else "red"
		lines.append("[color=%s]Requires %d DEX[/color]" % [color, required_dexterity])
	if required_intelligence > 0:
		var met := PlayerStats.intelligence >= required_intelligence
		var color := "green" if met else "red"
		lines.append("[color=%s]Requires %d INT[/color]" % [color, required_intelligence])

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
		_:
			return "Equipment"


#===============================================================================
# SERIALIZATION (for loot persistence across chunk loads)
#===============================================================================

## Serialize equipment to dictionary for storage
func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["class_type"] = "EquipmentData"
	data["equipment_type"] = equipment_type

	# Weapon stats
	data["weapon_damage"] = weapon_damage
	data["physical_damage"] = physical_damage
	data["fire_damage"] = fire_damage
	data["cold_damage"] = cold_damage
	data["lightning_damage"] = lightning_damage
	data["poison_damage"] = poison_damage
	data["weapon_attack_speed"] = weapon_attack_speed
	data["weapon_category"] = weapon_category

	# Stat bonuses
	data["bonus_strength"] = bonus_strength
	data["bonus_dexterity"] = bonus_dexterity
	data["bonus_intelligence"] = bonus_intelligence
	data["bonus_vitality"] = bonus_vitality
	data["bonus_energy"] = bonus_energy
	data["bonus_luck"] = bonus_luck

	# Offensive bonuses
	data["bonus_attack_power"] = bonus_attack_power
	data["bonus_spell_power"] = bonus_spell_power
	data["bonus_attack_speed"] = bonus_attack_speed
	data["bonus_crit_chance"] = bonus_crit_chance
	data["bonus_crit_damage"] = bonus_crit_damage

	# Defensive bonuses
	data["bonus_armor"] = bonus_armor
	data["bonus_magic_resistance"] = bonus_magic_resistance
	data["bonus_dodge_chance"] = bonus_dodge_chance
	data["bonus_health"] = bonus_health
	data["bonus_mana"] = bonus_mana
	data["bonus_stamina"] = bonus_stamina

	# Utility bonuses
	data["bonus_movement_speed"] = bonus_movement_speed
	data["bonus_life_regen"] = bonus_life_regen
	data["bonus_mana_regen"] = bonus_mana_regen
	data["bonus_stamina_regen"] = bonus_stamina_regen

	# Requirements
	data["required_level"] = required_level
	data["required_strength"] = required_strength
	data["required_dexterity"] = required_dexterity
	data["required_intelligence"] = required_intelligence

	return data


## Deserialize equipment from dictionary
static func from_dict(data: Dictionary) -> EquipmentData:
	var equip := EquipmentData.new()

	# Base item properties
	equip.id = data.get("id", "")
	equip.item_name = data.get("item_name", "Unknown Equipment")
	equip.description = data.get("description", "")
	equip.rarity = data.get("rarity", Rarity.COMMON)
	equip.item_type = ItemType.EQUIPMENT
	equip.max_stack = 1
	equip.sell_value = data.get("sell_value", 0)

	# Equipment type
	equip.equipment_type = data.get("equipment_type", EquipmentType.NONE)

	# Weapon stats
	equip.weapon_damage = data.get("weapon_damage", 0)
	equip.physical_damage = data.get("physical_damage", 0)
	equip.fire_damage = data.get("fire_damage", 0)
	equip.cold_damage = data.get("cold_damage", 0)
	equip.lightning_damage = data.get("lightning_damage", 0)
	equip.poison_damage = data.get("poison_damage", 0)
	equip.weapon_attack_speed = data.get("weapon_attack_speed", 1.0)
	equip.weapon_category = data.get("weapon_category", "")

	# Stat bonuses
	equip.bonus_strength = data.get("bonus_strength", 0)
	equip.bonus_dexterity = data.get("bonus_dexterity", 0)
	equip.bonus_intelligence = data.get("bonus_intelligence", 0)
	equip.bonus_vitality = data.get("bonus_vitality", 0)
	equip.bonus_energy = data.get("bonus_energy", 0)
	equip.bonus_luck = data.get("bonus_luck", 0)

	# Offensive bonuses
	equip.bonus_attack_power = data.get("bonus_attack_power", 0)
	equip.bonus_spell_power = data.get("bonus_spell_power", 0)
	equip.bonus_attack_speed = data.get("bonus_attack_speed", 0.0)
	equip.bonus_crit_chance = data.get("bonus_crit_chance", 0.0)
	equip.bonus_crit_damage = data.get("bonus_crit_damage", 0.0)

	# Defensive bonuses
	equip.bonus_armor = data.get("bonus_armor", 0)
	equip.bonus_magic_resistance = data.get("bonus_magic_resistance", 0)
	equip.bonus_dodge_chance = data.get("bonus_dodge_chance", 0.0)
	equip.bonus_health = data.get("bonus_health", 0)
	equip.bonus_mana = data.get("bonus_mana", 0)
	equip.bonus_stamina = data.get("bonus_stamina", 0)

	# Utility bonuses
	equip.bonus_movement_speed = data.get("bonus_movement_speed", 0.0)
	equip.bonus_life_regen = data.get("bonus_life_regen", 0.0)
	equip.bonus_mana_regen = data.get("bonus_mana_regen", 0.0)
	equip.bonus_stamina_regen = data.get("bonus_stamina_regen", 0.0)

	# Requirements
	equip.required_level = data.get("required_level", 1)
	equip.required_strength = data.get("required_strength", 0)
	equip.required_dexterity = data.get("required_dexterity", 0)
	equip.required_intelligence = data.get("required_intelligence", 0)

	return equip
