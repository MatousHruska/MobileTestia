extends Node
## PlayerStats - Player statistics and attributes singleton
## Manages primary attributes, resources, and derived stats

## Signals
signal stats_changed
signal level_changed(old_level: int, new_level: int)
signal experience_changed(current: int, required: int)
signal resource_changed(resource: String, current: float, maximum: float)
signal attribute_points_changed(points: int)
signal skill_points_changed(points: int)
signal leveled_up(new_level: int)  ## Emitted for level up visual effect

## Constants
const POINTS_PER_LEVEL: int = 5  ## Attribute points per level
const SKILL_POINTS_PER_LEVEL: int = 1  ## Skill points per level
const XP_PER_LEVEL: int = 100  ## XP required for each level (flat for testing)
const BASE_CRIT_DAMAGE: float = 150.0  # Base 150% crit damage

## Primary Attributes - Player allocates these manually
var strength: int = 10:
	set(value):
		strength = value
		_recalculate_derived()
		stats_changed.emit()

var dexterity: int = 10:
	set(value):
		dexterity = value
		_recalculate_derived()
		stats_changed.emit()

var intelligence: int = 10:
	set(value):
		intelligence = value
		_recalculate_derived()
		stats_changed.emit()

var vitality: int = 10:
	set(value):
		vitality = value
		_recalculate_derived()
		stats_changed.emit()

var energy: int = 10:
	set(value):
		energy = value
		_recalculate_derived()
		stats_changed.emit()

var luck: int = 10:
	set(value):
		luck = value
		_recalculate_derived()
		stats_changed.emit()

## Starting level for testing (set to 3 for skill point testing)
const DEBUG_STARTING_LEVEL: int = 3

## Level and Experience
var level: int = 1:
	set(value):
		var old := level
		level = value
		if old != value:
			level_changed.emit(old, value)
			_recalculate_derived()

var experience: int = 0:
	set(value):
		experience = value
		experience_changed.emit(experience, experience_for_next_level)
		_check_level_up()

var attribute_points: int = 0:
	set(value):
		attribute_points = value
		attribute_points_changed.emit(value)

var skill_points: int = 0:
	set(value):
		skill_points = value
		skill_points_changed.emit(value)

## Vital Stats (Resources) - Current values
var current_life: float = 100.0:
	set(value):
		current_life = clampf(value, 0.0, max_life)
		resource_changed.emit("life", current_life, max_life)

var current_mana: float = 50.0:
	set(value):
		current_mana = clampf(value, 0.0, max_mana)
		resource_changed.emit("mana", current_mana, max_mana)

var current_stamina: float = 100.0:
	set(value):
		current_stamina = clampf(value, 0.0, max_stamina)
		resource_changed.emit("stamina", current_stamina, max_stamina)

## Vital Stats (Resources) - Maximum values (derived)
var max_life: float = 100.0
var max_mana: float = 50.0
var max_stamina: float = 100.0

## Offensive Stats (Derived)
var attack_power: float = 0.0  # Flat bonus to weapon-based attacks
var spell_power: float = 0.0   # Flat bonus to spell damage
var attack_speed: float = 0.0  # Percentage bonus
var critical_chance: float = 5.0  # Base 5%
var critical_damage: float = BASE_CRIT_DAMAGE  # Base 150%

## Defensive Stats (Derived)
var armor: float = 0.0
var magic_resistance: float = 0.0
var dodge_chance: float = 0.0

## Utility Stats (Derived)
var movement_speed: float = 0.0  # Percentage bonus
var life_regen: float = 0.0  # Per second
var mana_regen: float = 0.0  # Per second
var stamina_regen: float = 10.0  # Per second (base)

## Equipment bonuses (set by inventory system)
var _equipment_bonuses: Dictionary = {}

## Buff/debuff modifiers
var _buff_modifiers: Dictionary = {}


func _ready() -> void:
	Debug.info("Stats", "PlayerStats initialized")

	# Set starting level for testing
	if DEBUG_STARTING_LEVEL > 1:
		level = DEBUG_STARTING_LEVEL
		attribute_points = (DEBUG_STARTING_LEVEL - 1) * POINTS_PER_LEVEL
		skill_points = (DEBUG_STARTING_LEVEL - 1) * SKILL_POINTS_PER_LEVEL
		Debug.info("Stats", "Debug starting level: %d (%d attr pts, %d skill pts)" % [
			level, attribute_points, skill_points
		])

	_recalculate_derived()
	# Start with full resources
	current_life = max_life
	current_mana = max_mana
	current_stamina = max_stamina


func _process(delta: float) -> void:
	if Game.is_playing:
		_regenerate_resources(delta)


## Experience and Leveling
var experience_for_next_level: int:
	get: return XP_PER_LEVEL  ## Flat 100 XP per level for testing


func _check_level_up() -> void:
	while experience >= experience_for_next_level:
		experience -= experience_for_next_level
		level += 1
		attribute_points += POINTS_PER_LEVEL
		skill_points += SKILL_POINTS_PER_LEVEL
		Debug.info("Stats", "Level up! Lv.%d (+%d attr, +%d skill)" % [level, POINTS_PER_LEVEL, SKILL_POINTS_PER_LEVEL])
		leveled_up.emit(level)  ## Trigger level up visual effect


func add_experience(amount: int) -> void:
	experience += amount
	Debug.log("Stats", "Experience gained", amount)


## Attribute allocation
func can_allocate_point() -> bool:
	return attribute_points > 0


func allocate_strength() -> bool:
	if not can_allocate_point():
		return false
	strength += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to STR", strength)
	return true


func allocate_dexterity() -> bool:
	if not can_allocate_point():
		return false
	dexterity += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to DEX", dexterity)
	return true


func allocate_intelligence() -> bool:
	if not can_allocate_point():
		return false
	intelligence += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to INT", intelligence)
	return true


func allocate_vitality() -> bool:
	if not can_allocate_point():
		return false
	vitality += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to VIT", vitality)
	return true


func allocate_energy() -> bool:
	if not can_allocate_point():
		return false
	energy += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to ENE", energy)
	return true


func allocate_luck() -> bool:
	if not can_allocate_point():
		return false
	luck += 1
	attribute_points -= 1
	Debug.log("Stats", "Allocated point to LUK", luck)
	return true


## Resource management
func _regenerate_resources(delta: float) -> void:
	if current_life < max_life:
		current_life += life_regen * delta
	if current_mana < max_mana:
		current_mana += mana_regen * delta
	if current_stamina < max_stamina:
		current_stamina += stamina_regen * delta


func damage(amount: float) -> void:
	current_life -= amount
	Debug.log("Combat", "Damage taken", amount)
	if current_life <= 0:
		Debug.warn("Combat", "Player died!")
		Game.game_over()


func heal(amount: float) -> void:
	current_life += amount
	Debug.log("Combat", "Healed", amount)


func use_mana(amount: float) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false


func use_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		return true
	return false


## Equipment bonuses
func set_equipment_bonus(stat: String, value: float) -> void:
	_equipment_bonuses[stat] = value
	_recalculate_derived()


func clear_equipment_bonuses() -> void:
	_equipment_bonuses.clear()
	_recalculate_derived()


func get_equipment_bonus(stat: String) -> float:
	return _equipment_bonuses.get(stat, 0.0)


## Derived stat calculation
func _recalculate_derived() -> void:
	var old_max_life := max_life
	var old_max_mana := max_mana
	var old_max_stamina := max_stamina

	# Base values
	var base_life := 80.0
	var base_mana := 30.0
	var base_stamina := 100.0

	# Total primary stats (base + equipment bonuses)
	var total_vitality := vitality + int(get_equipment_bonus("vitality"))
	var total_energy := energy + int(get_equipment_bonus("energy"))
	var total_luck := luck + int(get_equipment_bonus("luck"))

	# Vitality: +2 Life per point (uses total vitality including equipment)
	max_life = base_life + (total_vitality * 2.0) + get_equipment_bonus("health")

	# Energy: +1.5 Mana per point (uses total energy including equipment)
	max_mana = base_mana + (total_energy * 1.5) + get_equipment_bonus("mana")

	# Stamina is fixed (could add modifiers later)
	max_stamina = base_stamina + get_equipment_bonus("stamina")

	# Critical Damage: Base 150% + 1% per Luck point (uses total luck including equipment)
	critical_damage = BASE_CRIT_DAMAGE + (total_luck * 1.0) + get_equipment_bonus("crit_damage")

	# Offensive stats (from equipment and buffs only)
	attack_power = get_equipment_bonus("attack_power")
	spell_power = get_equipment_bonus("spell_power")
	attack_speed = get_equipment_bonus("attack_speed")
	critical_chance = 5.0 + get_equipment_bonus("crit_chance")

	# Defensive stats
	armor = get_equipment_bonus("armor")
	magic_resistance = get_equipment_bonus("magic_resistance")
	dodge_chance = get_equipment_bonus("dodge_chance")

	# Utility stats
	movement_speed = get_equipment_bonus("movement_speed")
	life_regen = 1.0 + get_equipment_bonus("life_regen")  # Base 1/s
	mana_regen = 0.5 + get_equipment_bonus("mana_regen")  # Base 0.5/s
	stamina_regen = 10.0 + get_equipment_bonus("stamina_regen")  # Base 10/s

	# Adjust current values if max changed and emit resource signals
	if max_life != old_max_life:
		current_life = clampf(current_life, 0.0, max_life)
		resource_changed.emit("life", current_life, max_life)
	if max_mana != old_max_mana:
		current_mana = clampf(current_mana, 0.0, max_mana)
		resource_changed.emit("mana", current_mana, max_mana)
	if max_stamina != old_max_stamina:
		current_stamina = clampf(current_stamina, 0.0, max_stamina)
		resource_changed.emit("stamina", current_stamina, max_stamina)

	stats_changed.emit()


## Stat descriptions for UI
static func get_stat_description(stat_name: String) -> String:
	match stat_name:
		# Primary Attributes
		"strength":
			return "Physical Mastery\nRequired to equip heavy Armor, Swords, Axes, and Maces.\nDoes not increase damage directly."
		"dexterity":
			return "Agility Mastery\nRequired to equip light Armor, Bows, Daggers, and precision gear.\nDoes not increase damage directly."
		"intelligence":
			return "Arcane Mastery\nRequired to equip Robes, Staves, Wands, and magical accessories.\nDoes not increase damage directly."
		"vitality":
			return "Life Force\nDirectly increases Maximum Health.\n+2 Life per point."
		"energy":
			return "Magical Capacity\nDirectly increases Maximum Mana.\n+1.5 Mana per point."
		"luck":
			return "Fortune\nIncreases Critical Damage.\n+1% Critical Damage per point."
		# Resources
		"life":
			return "Health Points\nThe character's survival gauge.\nDeath occurs at 0."
		"mana":
			return "Magic Points\nConsumed to cast Spells and use active Abilities."
		"stamina":
			return "Endurance\nConsumed by Sprinting and Dodging.\nRegenerates quickly when inactive."
		# Offensive - Weapon
		"weapon_damage":
			return "Weapon Damage\nBase damage of your equipped weapon.\nMelee and ranged skills scale from this value."
		"weapon_dps":
			return "Weapon DPS\nDamage per second from basic attacks.\nCalculated as Weapon Damage × Attack Speed."
		# Offensive - Player
		"attack_power":
			return "Attack Power\nFlat damage bonus added to weapon-based attacks.\nAffects melee and ranged skills."
		"spell_power":
			return "Spell Power\nFlat damage bonus added to spell damage.\nAffects magic skills (not weapon-based)."
		"attack_speed":
			return "Attack Speed\nFinal attacks per second.\nCalculated from weapon speed + bonuses."
		"critical_chance":
			return "Critical Chance\nThe percentage probability of an attack dealing bonus damage."
		"critical_damage":
			return "Critical Damage\nThe multiplier applied on a Critical Hit.\nBase 150%, scales with Luck."
		# Elemental Spell Damage
		"fire_spell_damage":
			return "Fire Spell Damage\nPercentage bonus to Fire spell damage.\nFrom equipment and buffs."
		"cold_spell_damage":
			return "Cold Spell Damage\nPercentage bonus to Cold/Frost spell damage.\nFrom equipment and buffs."
		"lightning_spell_damage":
			return "Lightning Spell Damage\nPercentage bonus to Lightning spell damage.\nFrom equipment and buffs."
		"poison_spell_damage":
			return "Poison Spell Damage\nPercentage bonus to Poison spell damage.\nFrom equipment and buffs."
		"arcane_spell_damage":
			return "Arcane Spell Damage\nPercentage bonus to Arcane spell damage.\nFrom equipment and buffs."
		# Defensive
		"armor":
			return "Armor\nReduces incoming Physical Damage from enemy attacks."
		"magic_resistance":
			return "Magic Resistance\nReduces incoming damage from Spells and Elemental sources."
		"dodge_chance":
			return "Dodge Chance\nThe percentage chance to completely evade an attack, negating all damage."
		# Utility
		"movement_speed":
			return "Movement Speed\nIncreases the character's movement velocity."
		"life_regen":
			return "Life Regeneration\nAmount of Health recovered per second."
		"mana_regen":
			return "Mana Regeneration\nAmount of Mana recovered per second."
		"stamina_regen":
			return "Stamina Regeneration\nAmount of Stamina recovered per second."
		_:
			return "Unknown stat."


## Debug
func print_state() -> void:
	Debug.snapshot("Stats", "PlayerStats State", {
		"level": level,
		"experience": "%d / %d" % [experience, experience_for_next_level],
		"attribute_points": attribute_points,
		"skill_points": skill_points,
		"STR": strength,
		"DEX": dexterity,
		"INT": intelligence,
		"VIT": vitality,
		"ENE": energy,
		"LUK": luck,
		"life": "%d / %d" % [int(current_life), int(max_life)],
		"mana": "%d / %d" % [int(current_mana), int(max_mana)],
		"stamina": "%d / %d" % [int(current_stamina), int(max_stamina)],
	})


## Debug: Give test stats
func debug_add_points(amount: int = 10) -> void:
	attribute_points += amount
	Debug.info("Stats", "Debug: Added attribute points", amount)


func debug_add_experience(amount: int = 500) -> void:
	add_experience(amount)
	Debug.info("Stats", "Debug: Added experience", amount)


func debug_add_skill_points(amount: int = 10) -> void:
	skill_points += amount
	skill_points_changed.emit(skill_points)
	Debug.info("Stats", "Debug: Added skill points", amount)
