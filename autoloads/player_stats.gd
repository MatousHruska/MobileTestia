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
signal damaged(amount: float, damage_type: String, is_crit: bool)  ## For combat text
signal healed(amount: float)  ## For combat text
signal health_full()  ## Emitted when player reaches max health
signal health_not_full()  ## Emitted when player drops below max health

## Constants (loaded from database, these are fallback defaults)
var POINTS_PER_LEVEL: int = 5  ## Attribute points per level
var SKILL_POINTS_PER_LEVEL: int = 1  ## Skill points per level
var XP_PER_LEVEL: int = 100  ## XP required for each level (flat for testing)

## Base stat values (loaded from database)
var _health_base_flat: float = 80.0
var _mana_base_flat: float = 30.0
var _stamina_base_flat: float = 100.0
var _crit_chance_base: float = 5.0
var _crit_damage_base: float = 150.0

## Stat conversion constants (loaded from database)
var _health_per_vitality: float = 2.0
var _mana_per_energy: float = 1.5
var _crit_damage_per_luck: float = 1.0

## Regeneration bases (loaded from database)
var _base_life_regen: float = 1.0
var _base_mana_regen: float = 0.5
var _base_stamina_regen: float = 10.0

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

## Starting level for testing (set to 50 for talent tree testing)
const DEBUG_STARTING_LEVEL: int = 50

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
		var was_full := is_health_full()
		current_life = clampf(value, 0.0, max_life)
		resource_changed.emit("life", current_life, max_life)
		# Emit health state signals on transitions
		var is_full := is_health_full()
		if is_full and not was_full:
			health_full.emit()
		elif not is_full and was_full:
			health_not_full.emit()

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
var critical_damage: float = 150.0  # Base 150% (recalculated from database)

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

## Whether status effect signals are connected (to avoid duplicate connections)
var _status_signals_connected: bool = false

## Damage tracking (for AI conditions like "player_damaged_recently")
var last_damage_time: float = -1000.0  # Time.get_ticks_msec()/1000 when last damaged


func _ready() -> void:
	add_to_group("saveable")  # Register for auto-discovery save system
	Debug.info("Stats", "PlayerStats initialized")

	# Load base values from database
	_load_base_values_from_database()

	# Set starting level for testing (adds to starting skill points from database)
	if DEBUG_STARTING_LEVEL > 1:
		level = DEBUG_STARTING_LEVEL
		attribute_points = (DEBUG_STARTING_LEVEL - 1) * POINTS_PER_LEVEL
		skill_points += (DEBUG_STARTING_LEVEL - 1) * SKILL_POINTS_PER_LEVEL
		Debug.info("Stats", "Debug starting level: %d (%d attr pts, %d skill pts)" % [
			level, attribute_points, skill_points
		])

	_recalculate_derived()
	# Start with full resources
	current_life = max_life
	current_mana = max_mana
	current_stamina = max_stamina

	# Connect talent signal (player status effect signals connected later via connect_bonus_signals)
	if TalentManager:
		TalentManager.talent_learned.connect(_on_bonus_source_changed.unbind(2))


func _load_base_values_from_database() -> void:
	## Load all base stat values from gameplay_settings.json
	## Uses code defaults as fallback if database values don't exist

	# Primary stat starting values
	strength = int(DatabaseLoader.get_setting("base_strength", strength))
	dexterity = int(DatabaseLoader.get_setting("base_dexterity", dexterity))
	intelligence = int(DatabaseLoader.get_setting("base_intelligence", intelligence))
	vitality = int(DatabaseLoader.get_setting("base_vitality", vitality))
	energy = int(DatabaseLoader.get_setting("base_energy", energy))
	luck = int(DatabaseLoader.get_setting("base_luck", luck))

	# Progression constants
	POINTS_PER_LEVEL = int(DatabaseLoader.get_setting("points_per_level", POINTS_PER_LEVEL))
	SKILL_POINTS_PER_LEVEL = int(DatabaseLoader.get_setting("skill_points_per_level", SKILL_POINTS_PER_LEVEL))
	XP_PER_LEVEL = int(DatabaseLoader.get_setting("xp_per_level", XP_PER_LEVEL))

	# Starting skill points (talent points)
	var starting_skill_pts := int(DatabaseLoader.get_setting("starting_skill_points", 0))
	skill_points = starting_skill_pts

	# Flat base values
	_health_base_flat = DatabaseLoader.get_setting("health_base_flat", _health_base_flat)
	_mana_base_flat = DatabaseLoader.get_setting("mana_base_flat", _mana_base_flat)
	_stamina_base_flat = DatabaseLoader.get_setting("stamina_base_flat", _stamina_base_flat)
	_crit_chance_base = DatabaseLoader.get_setting("crit_chance_base", _crit_chance_base)
	_crit_damage_base = DatabaseLoader.get_setting("crit_damage_base", _crit_damage_base)

	# Stat conversion constants
	_health_per_vitality = DatabaseLoader.get_setting("health_per_vitality", _health_per_vitality)
	_mana_per_energy = DatabaseLoader.get_setting("mana_per_energy", _mana_per_energy)
	_crit_damage_per_luck = DatabaseLoader.get_setting("crit_damage_per_luck", _crit_damage_per_luck)

	# Regeneration rates
	_base_life_regen = DatabaseLoader.get_setting("base_life_regen", _base_life_regen)
	_base_mana_regen = DatabaseLoader.get_setting("base_mana_regen", _base_mana_regen)
	_base_stamina_regen = DatabaseLoader.get_setting("base_stamina_regen", _base_stamina_regen)

	Debug.log("Stats", "Loaded base values from database", {
		"health_base": _health_base_flat,
		"health_per_vit": _health_per_vitality,
		"crit_damage_base": _crit_damage_base
	})


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


## Health state queries
func is_health_full() -> bool:
	return current_life >= max_life


func get_health_percent() -> float:
	if max_life <= 0:
		return 0.0
	return current_life / max_life


## Resource management
func _regenerate_resources(delta: float) -> void:
	if current_life < max_life:
		current_life += life_regen * delta
	if current_mana < max_mana:
		current_mana += mana_regen * delta
	if current_stamina < max_stamina:
		current_stamina += stamina_regen * delta


func damage(amount: float, damage_type: String = "physical", is_crit: bool = false, attacker_position: Vector2 = Vector2.INF) -> bool:
	# Check Cold Parry - if active, try to negate the damage
	if TalentProcSystem and TalentProcSystem.is_parry_active():
		# Determine attacker position for frontal arc check
		var parry_pos := attacker_position
		if parry_pos == Vector2.INF and Game.player:
			# No explicit attacker position - estimate from nearest enemy
			var enemies := NPCManager.get_enemies_in_radius(Game.player.global_position, 100.0)
			if not enemies.is_empty():
				parry_pos = enemies[0].global_position
		if parry_pos != Vector2.INF and TalentProcSystem.try_parry(parry_pos):
			Debug.log("Combat", "Damage PARRIED! (%.0f %s negated)" % [amount, damage_type])
			return false  # Damage fully negated

	# Check Phalanx Stance — reduce frontal/side damage by 75%
	if Game.player and Game.player.is_stance_active:
		var stance_arc := 270.0  # Front + sides (not directly behind)
		var reduce := true
		# Check if attack is within stance arc
		if attacker_position != Vector2.INF:
			var player_pos: Vector2 = Game.player.global_position
			var to_attacker := (attacker_position - player_pos).normalized()
			var facing_vec := _get_player_facing_vector()
			var angle := rad_to_deg(facing_vec.angle_to(to_attacker))
			if abs(angle) > stance_arc / 2.0:
				reduce = false  # Attack from directly behind — no reduction
		if reduce:
			amount *= 0.25  # 75% damage reduction
			Debug.log("Combat", "Phalanx Stance reduced damage to %.0f" % amount)

	current_life -= amount
	last_damage_time = Time.get_ticks_msec() / 1000.0  # Track when damage occurred
	damaged.emit(amount, damage_type, is_crit)
	Debug.log("Combat", "Damage taken", {"amount": amount, "type": damage_type, "crit": is_crit})
	if current_life <= 0:
		Debug.warn("Combat", "Player died!")
		Game.game_over()
	return true


func get_time_since_last_damage() -> float:
	"""Returns seconds since player last took damage, or -1 if never damaged"""
	if last_damage_time < 0:
		return -1.0
	var current_time: float = Time.get_ticks_msec() / 1000.0
	return current_time - last_damage_time


func heal(amount: float) -> void:
	current_life += amount
	healed.emit(amount)
	Debug.log("Combat", "Healed", amount)


func use_mana(amount: float) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false


func use_stamina(amount: float) -> bool:
	# Ultimate ability waives all stamina costs
	if TalentProcSystem and TalentProcSystem.should_waive_stamina_cost():
		return true
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


## Get talent stat bonus for a given stat (from passive talent stat_bonuses fields)
func _get_talent_bonus(stat: String) -> float:
	if not TalentManager:
		return 0.0
	var bonuses := TalentManager.get_total_stat_bonuses()
	return bonuses.get(stat, 0.0)


## Get status effect modifier for a given stat (from active buffs/debuffs on player)
func _get_status_effect_modifier(stat: String) -> float:
	if not Game.player or not is_instance_valid(Game.player):
		return 0.0
	if not Game.player.has_node("StatusEffectManager"):
		return 0.0
	return Game.player.status_effect_manager.get_stat_modifier(stat)


## Public method to trigger stat recalculation from external sources
func recalculate_stats() -> void:
	_recalculate_derived()


## Connect to player status effect signals so stats update when buffs/debuffs change
## Called by PlayerController after StatusEffectManager is set up
func connect_bonus_signals() -> void:
	if Game.player and is_instance_valid(Game.player) and Game.player.has_node("StatusEffectManager"):
		var sem: StatusEffectManager = Game.player.status_effect_manager
		if not _status_signals_connected:
			sem.effect_applied.connect(_on_status_effect_changed.unbind(4))
			sem.effect_removed.connect(_on_status_effect_changed.unbind(1))
			_status_signals_connected = true
			_recalculate_derived()


func _on_bonus_source_changed() -> void:
	_recalculate_derived()


func _on_status_effect_changed() -> void:
	_recalculate_derived()


## Derived stat calculation
func _recalculate_derived() -> void:
	var old_max_life := max_life
	var old_max_mana := max_mana
	var old_max_stamina := max_stamina

	# Total primary stats (base + equipment bonuses)
	var total_vitality := vitality + int(get_equipment_bonus("vitality"))
	var total_energy := energy + int(get_equipment_bonus("energy"))
	var total_luck := luck + int(get_equipment_bonus("luck"))

	# Derived stats using database conversion constants:
	# max_health = health_base_flat + (vitality × health_per_vitality) + equipment
	max_life = _health_base_flat + (total_vitality * _health_per_vitality) + get_equipment_bonus("health")

	# max_mana = mana_base_flat + (energy × mana_per_energy) + equipment
	max_mana = _mana_base_flat + (total_energy * _mana_per_energy) + get_equipment_bonus("mana")

	# Stamina uses flat base only (no stat conversion)
	max_stamina = _stamina_base_flat + get_equipment_bonus("stamina")

	# crit_damage = crit_damage_base + (luck × crit_damage_per_luck) + equipment
	critical_damage = _crit_damage_base + (total_luck * _crit_damage_per_luck) + get_equipment_bonus("crit_damage")

	# Offensive stats (equipment + talents + status effects)
	attack_power = get_equipment_bonus("attack_power") + _get_talent_bonus("attack_power") + _get_status_effect_modifier("attack_power")
	spell_power = get_equipment_bonus("spell_power") + _get_talent_bonus("spell_power") + _get_status_effect_modifier("spell_power")
	attack_speed = get_equipment_bonus("attack_speed") + _get_talent_bonus("attack_speed") + _get_status_effect_modifier("attack_speed")
	critical_chance = _crit_chance_base + get_equipment_bonus("crit_chance") + _get_talent_bonus("crit_chance") + _get_status_effect_modifier("crit_chance")

	# Defensive stats (equipment + talents + status effects)
	armor = get_equipment_bonus("armor") + _get_talent_bonus("armor") + _get_status_effect_modifier("armor")
	magic_resistance = get_equipment_bonus("magic_resistance") + _get_talent_bonus("magic_resistance") + _get_status_effect_modifier("magic_resistance")
	dodge_chance = get_equipment_bonus("dodge_chance") + _get_talent_bonus("dodge_chance") + _get_status_effect_modifier("dodge_chance")

	# Utility stats (equipment + talents + status effects + base regen)
	movement_speed = get_equipment_bonus("movement_speed") + _get_talent_bonus("movement_speed") + _get_status_effect_modifier("movement_speed")
	life_regen = _base_life_regen + get_equipment_bonus("life_regen") + _get_talent_bonus("life_regen") + _get_status_effect_modifier("life_regen")
	mana_regen = _base_mana_regen + get_equipment_bonus("mana_regen") + _get_talent_bonus("mana_regen") + _get_status_effect_modifier("mana_regen")
	stamina_regen = _base_stamina_regen + get_equipment_bonus("stamina_regen") + _get_talent_bonus("stamina_regen") + _get_status_effect_modifier("stamina_regen")

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


## Stat descriptions for UI - loads from database with hardcoded fallback
func get_stat_description(stat_name: String) -> String:
	# Try database first
	var db_desc := DatabaseLoader.get_stat_description(stat_name)
	if not db_desc.is_empty():
		return db_desc

	# Fallback to hardcoded descriptions if database not available
	match stat_name:
		# Primary Attributes
		"strength":
			return "Physical Mastery. Required for heavy armor, swords, axes, and maces. Does not directly increase damage."
		"dexterity":
			return "Agility Mastery. Required for light armor, bows, daggers, and precision gear. Does not directly increase damage."
		"intelligence":
			return "Arcane Mastery. Required for robes, staves, wands, and magical items. Does not directly increase damage."
		"vitality":
			return "Life Force. Each point increases Maximum Health by 2."
		"energy":
			return "Magical Capacity. Each point increases Maximum Mana (scaling from database)."
		"luck":
			return "Fortune. Each point increases Critical Damage by 1%."
		# Resources
		"life":
			return "Health Points. You die when this reaches 0. Regenerates over time."
		"mana":
			return "Magic Points. Consumed when casting spells and using abilities."
		"stamina":
			return "Endurance. Consumed by sprinting and dodging. Regenerates quickly."
		# Offensive - Weapon
		"weapon_damage":
			return "Base damage of your equipped weapon. Physical and ranged skills scale from this."
		"weapon_dps":
			return "Damage per second from basic attacks. Equals Weapon Damage × Attack Speed."
		# Offensive - Player
		"attack_power":
			return "Flat bonus damage added to all weapon-based attacks."
		"spell_power":
			return "Flat bonus damage added to all spell damage."
		"attack_speed":
			return "Attacks per second. Determined by weapon speed plus any bonuses."
		"critical_chance":
			return "Percentage chance for attacks to deal bonus damage. Base: 5%."
		"critical_damage":
			return "Damage multiplier on critical hits. Base: 150%, scales with Luck."
		# Elemental Spell Damage
		"fire_spell_damage":
			return "Flat bonus to Fire spell damage from equipment."
		"cold_spell_damage":
			return "Flat bonus to Cold/Frost spell damage from equipment."
		"lightning_spell_damage":
			return "Flat bonus to Lightning spell damage from equipment."
		"poison_spell_damage":
			return "Flat bonus to Poison spell damage from equipment."
		"arcane_spell_damage":
			return "Flat bonus to Arcane spell damage from equipment."
		# Defensive
		"armor":
			return "Reduces incoming physical damage from attacks."
		"magic_resistance":
			return "Reduces incoming damage from spells and elemental sources."
		"dodge_chance":
			return "Percentage chance to completely evade an attack."
		# Utility
		"movement_speed":
			return "Percentage bonus to movement velocity."
		"life_regen":
			return "Health recovered per second. Base: 1/s."
		"mana_regen":
			return "Mana recovered per second. Base: 0.5/s."
		"stamina_regen":
			return "Stamina recovered per second. Base: 10/s."
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


func _get_player_facing_vector() -> Vector2:
	if not Game.player:
		return Vector2.DOWN
	match Game.player.current_facing:
		PlayerController.Facing.DOWN: return Vector2.DOWN
		PlayerController.Facing.UP: return Vector2.UP
		PlayerController.Facing.LEFT: return Vector2.LEFT
		PlayerController.Facing.RIGHT: return Vector2.RIGHT
		_: return Vector2.DOWN


#===============================================================================
# PERSISTENCE (Saveable interface)
#===============================================================================

func get_save_key() -> String:
	## Unique key for save data - used by auto-discovery system
	return "player_stats"


func get_save_priority() -> int:
	## Load priority (lower = earlier). PlayerStats loads first.
	return 10


func get_save_data() -> Dictionary:
	## Get all player stats for saving
	return {
		# Level and progression
		"level": level,
		"experience": experience,
		"attribute_points": attribute_points,
		"skill_points": skill_points,

		# Primary attributes
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"vitality": vitality,
		"energy": energy,
		"luck": luck,

		# Current resources (save current state)
		"current_life": current_life,
		"current_mana": current_mana,
		"current_stamina": current_stamina,
	}


func load_save_data(data: Dictionary) -> void:
	## Load player stats from save data

	# Level and progression (set level first to establish base state)
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	attribute_points = data.get("attribute_points", 0)
	skill_points = data.get("skill_points", 0)

	# Primary attributes (these trigger _recalculate_derived via setters)
	strength = data.get("strength", 10)
	dexterity = data.get("dexterity", 10)
	intelligence = data.get("intelligence", 10)
	vitality = data.get("vitality", 10)
	energy = data.get("energy", 10)
	luck = data.get("luck", 10)

	# Force recalculate derived stats
	_recalculate_derived()

	# Restore current resources (after max values are calculated)
	current_life = data.get("current_life", max_life)
	current_mana = data.get("current_mana", max_mana)
	current_stamina = data.get("current_stamina", max_stamina)

	Debug.info("Stats", "Loaded save data", {
		"level": level,
		"experience": experience,
		"attributes": "STR:%d DEX:%d INT:%d VIT:%d ENE:%d LUK:%d" % [
			strength, dexterity, intelligence, vitality, energy, luck
		]
	})
