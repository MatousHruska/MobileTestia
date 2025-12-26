extends ItemData
class_name ConsumableData
## Consumable item data - potions, scrolls, food

## Effect types
enum EffectType {
	HEAL_HEALTH,
	HEAL_MANA,
	BUFF_STRENGTH,
	BUFF_DEXTERITY,
	BUFF_INTELLIGENCE,
	BUFF_ENDURANCE,
	BUFF_LUCK,
	BUFF_ATTACK_SPEED,
	BUFF_CRIT_CHANCE,
	BUFF_DEFENSE,
	TELEPORT,
	OTHER
}

## What this consumable does
@export var effect_type: EffectType = EffectType.HEAL_HEALTH

## Effect magnitude (heal amount, buff value, etc.)
@export var effect_value: int = 0

## Duration in seconds (0 = instant)
@export var effect_duration: float = 0.0

## Cooldown before can use again (seconds)
@export var cooldown: float = 0.0


func _init() -> void:
	item_type = ItemType.CONSUMABLE
	max_stack = 99  # Consumables can stack by default


## Get formatted effect text for UI
func get_effect_text() -> String:
	var text := ""

	match effect_type:
		EffectType.HEAL_HEALTH:
			text = "Restores %d Health" % effect_value
		EffectType.HEAL_MANA:
			text = "Restores %d Mana" % effect_value
		EffectType.BUFF_STRENGTH:
			text = "+%d Strength" % effect_value
		EffectType.BUFF_DEXTERITY:
			text = "+%d Dexterity" % effect_value
		EffectType.BUFF_INTELLIGENCE:
			text = "+%d Intelligence" % effect_value
		EffectType.BUFF_ENDURANCE:
			text = "+%d Endurance" % effect_value
		EffectType.BUFF_LUCK:
			text = "+%d Luck" % effect_value
		EffectType.BUFF_ATTACK_SPEED:
			text = "+%d%% Attack Speed" % effect_value
		EffectType.BUFF_CRIT_CHANCE:
			text = "+%d%% Crit Chance" % effect_value
		EffectType.BUFF_DEFENSE:
			text = "+%d Defense" % effect_value
		EffectType.TELEPORT:
			text = "Teleports to town"
		EffectType.OTHER:
			text = description

	if effect_duration > 0.0:
		text += " for %.0fs" % effect_duration

	return text


## Check if this can go in the quick slot
func can_quick_slot() -> bool:
	return true  # All consumables can go in quick slot
