extends Control
class_name CombatHUD
## CombatHUD - Layout manager for combat action buttons
## Positions attack, abilities, dodge, and quick slot based on config

## Preload combat classes (needed until Godot generates .uid files)
const AimIndicatorClass = preload("res://scripts/combat/aim_indicator.gd")
const ProjectileClass = preload("res://scripts/combat/projectile.gd")
const MagicProjectileClass = preload("res://scripts/combat/magic_projectile.gd")

signal attack_pressed
signal ability_pressed(slot_index: int, ability_id: String)
signal dodge_pressed
signal quick_slot_pressed

## Configuration
@export var config: CombatHUDConfig

## Button references (created dynamically)
var attack_button: AbilitySlot
var ability_slots: Array[AbilitySlot] = []
var dodge_button: AbilitySlot
var quick_slot_button: AbilitySlot
var interact_button: Button

## Player reference for dodge stamina check
var player: PlayerController = null

## Main slot skill binding (slot 0 binds to attack button)
var attack_button_talent: TalentData = null

## Ranged aiming
var aim_indicator: Node2D = null  ## AimIndicator instance
var is_aiming: bool = false
var aiming_slot_index: int = -1
var aiming_talent: TalentData = null
var aim_start_time: float = 0.0

## Magic casting
var is_casting: bool = false
var casting_slot_index: int = -1
var casting_talent: TalentData = null
var cast_start_time: float = 0.0
var cast_direction: Vector2 = Vector2.DOWN

## Default charge constants (now database-driven per talent via max_charge_time, base_range)
## These are fallbacks when talent data doesn't specify values
const DEFAULT_MAX_CHARGE_TIME: float = 2.0      ## Default maximum charge time for full range
const DEFAULT_BASE_RANGE: float = 150.0         ## Default range at minimum charge

## Constants
const DEFAULT_CONFIG_PATH := "res://resources/combat_hud_config.tres"


#===============================================================================
# SKILL VALUE CALCULATIONS (applies equipment bonuses)
#===============================================================================

## Calculate final skill value with equipment bonuses applied
## Formula: base_value × (1 + equipment_bonus%)
static func calc_skill_value(base_value: float, stat_name: String) -> float:
	if base_value <= 0:
		return base_value  # Don't modify zero/negative values
	var bonus := PlayerStats.get_equipment_bonus(stat_name)
	return base_value * (1.0 + bonus / 100.0)


## Shorthand getters for common skill properties
static func get_hit_range(talent: TalentData) -> float:
	return calc_skill_value(talent.hit_range, "hit_range")

static func get_hit_arc(talent: TalentData) -> float:
	return calc_skill_value(talent.hit_arc, "hit_arc")

static func get_lunge_force(talent: TalentData) -> float:
	return calc_skill_value(talent.lunge_force, "lunge_force")

static func get_lunge_duration(talent: TalentData) -> float:
	return calc_skill_value(talent.lunge_duration, "lunge_duration")

static func get_explosion_radius(talent: TalentData) -> float:
	return calc_skill_value(talent.explosion_radius, "explosion_radius")

static func get_projectile_speed(talent: TalentData) -> float:
	return calc_skill_value(talent.projectile_speed, "projectile_speed")

static func get_cast_time(talent: TalentData) -> float:
	# cast_speed reduces cast time, so we divide instead of multiply
	var cast_speed_bonus := PlayerStats.get_equipment_bonus("cast_speed")
	if cast_speed_bonus > 0 and talent.cast_time > 0:
		return talent.cast_time / (1.0 + cast_speed_bonus / 100.0)
	return talent.cast_time

static func get_cooldown(talent: TalentData) -> float:
	# cooldown_reduction reduces cooldown
	var cdr := PlayerStats.get_equipment_bonus("cooldown_reduction")
	if cdr > 0 and talent.cooldown > 0:
		return talent.cooldown * (1.0 - minf(cdr, 75.0) / 100.0)  # Cap at 75% CDR
	return talent.cooldown


func _ready() -> void:
	# Load or create config
	if config == null:
		_load_or_create_config()

	# Create all buttons
	_create_buttons()

	# Position buttons
	_layout_buttons()

	# Connect to game manager for player reference
	if Game:
		Game.player_spawned.connect(_on_player_spawned)
		if Game.is_player_valid():
			_on_player_spawned(Game.player)

	# Connect to TalentManager for skill bindings
	_connect_talent_manager()

	Debug.info("Combat", "CombatHUD initialized", {"abilities": config.ability_count})


func _process(_delta: float) -> void:
	# Update aim indicator during aiming
	if is_aiming and aim_indicator and player:
		_update_aiming()

	# Update magic casting
	if is_casting and casting_talent and player:
		_update_casting()


func _connect_talent_manager() -> void:
	## Connect to TalentManager to sync bound skills
	if TalentManager:
		TalentManager.skill_bound.connect(_on_talent_skill_bound)
		TalentManager.skill_unbound.connect(_on_talent_skill_unbound)
		# Sync existing bindings
		call_deferred("_sync_talent_bindings")

	# Connect to Inventory for weapon changes
	if Inventory:
		Inventory.equipment_changed.connect(_on_equipment_changed)


func _sync_talent_bindings() -> void:
	## Sync all bound talents from TalentManager to ability slots
	# Sync main slot (slot 0) to attack button
	var main_talent := TalentManager.get_bound_talent(0)
	if main_talent:
		_bind_talent_to_attack_button(main_talent)
	else:
		_clear_attack_button_binding()

	# Sync secondary slots (1-5) to ability slots (0-4)
	for i in range(ability_slots.size()):
		var talent := TalentManager.get_bound_talent(i + 1)
		if talent:
			_bind_talent_to_slot(i, talent)
		else:
			clear_ability_slot(i)


func _bind_talent_to_slot(slot_index: int, talent: TalentData) -> void:
	## Bind a talent's ability to an ability slot
	if slot_index < 0 or slot_index >= ability_slots.size():
		return

	var invested := TalentManager.get_invested_points(talent.id)
	var data := {
		"name": talent.talent_name,
		"icon": talent.talent_name.substr(0, 2).to_upper(),
		"mana_cost": talent.mana_cost,
		"stamina_cost": talent.stamina_cost,
		"cooldown": talent.cooldown,
		"damage": talent.get_damage_at_points(invested),
		"effect_type": talent.effect_type,
		"effect_value": talent.get_effect_at_points(invested),
		"duration": talent.duration,
		"talent_id": talent.id,
		"required_weapon_category": talent.required_weapon_category,
	}

	ability_slots[slot_index].bind_ability(talent.id, data)

	# Update weapon validity for this slot
	var weapon_cat: String = Inventory.get_equipped_weapon_category()
	ability_slots[slot_index].update_weapon_validity(weapon_cat)

	Debug.log("Combat", "Bound talent to HUD slot", {"slot": slot_index, "talent": talent.talent_name})


func _bind_talent_to_attack_button(talent: TalentData) -> void:
	## Bind a talent to the attack button (main slot 0)
	attack_button_talent = talent

	var invested := TalentManager.get_invested_points(talent.id)
	var data := {
		"name": talent.talent_name,
		"icon": talent.talent_name.substr(0, 2).to_upper(),
		"mana_cost": talent.mana_cost,
		"stamina_cost": talent.stamina_cost,
		"cooldown": talent.cooldown,
		"damage": talent.get_damage_at_points(invested),
		"effect_type": talent.effect_type,
		"effect_value": talent.get_effect_at_points(invested),
		"duration": talent.duration,
		"talent_id": talent.id,
		"required_weapon_category": talent.required_weapon_category,
	}

	attack_button.bind_ability(talent.id, data)

	# Update weapon validity for attack button
	var weapon_cat: String = Inventory.get_equipped_weapon_category()
	attack_button.update_weapon_validity(weapon_cat)

	Debug.log("Combat", "Bound talent to attack button", {"talent": talent.talent_name})


func _clear_attack_button_binding() -> void:
	## Clear the attack button's skill binding (revert to basic attack)
	attack_button_talent = null
	attack_button.clear_ability()
	attack_button.set_icon("⚔")
	Debug.log("Combat", "Cleared attack button binding")


func _on_talent_skill_bound(slot_index: int, talent_id: String) -> void:
	## Handle skill bound event from TalentManager
	# TalentManager uses slot 0 as main (attack button), 1-5 as secondary (ability slots)
	var talent := TalentManager.get_talent(talent_id)
	if not talent:
		return

	if slot_index == 0:
		# Main slot binds to attack button
		_bind_talent_to_attack_button(talent)
	else:
		# Secondary slots bind to ability slots (slot 1 -> ability_slots[0], etc.)
		var hud_slot := slot_index - 1
		if hud_slot >= 0 and hud_slot < ability_slots.size():
			_bind_talent_to_slot(hud_slot, talent)


func _on_talent_skill_unbound(slot_index: int) -> void:
	## Handle skill unbound event from TalentManager
	if slot_index == 0:
		# Main slot unbinds from attack button
		_clear_attack_button_binding()
	else:
		# Secondary slots unbind from ability slots
		var hud_slot := slot_index - 1
		if hud_slot >= 0 and hud_slot < ability_slots.size():
			clear_ability_slot(hud_slot)


func _on_equipment_changed(slot: ItemData.EquipSlot) -> void:
	## Handle equipment change - update weapon validity for all ability slots
	if slot == ItemData.EquipSlot.MAIN_HAND:
		_update_all_weapon_validity()


func _update_all_weapon_validity() -> void:
	## Update weapon validity state for all ability slots (including attack button)
	var weapon_cat: String = Inventory.get_equipped_weapon_category()

	# Update attack button if it has a skill bound
	if attack_button_talent:
		attack_button.update_weapon_validity(weapon_cat)

	# Update all ability slots
	for slot in ability_slots:
		slot.update_weapon_validity(weapon_cat)


func _load_or_create_config() -> void:
	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		config = load(DEFAULT_CONFIG_PATH) as CombatHUDConfig
	else:
		config = CombatHUDConfig.new()
		Debug.info("Combat", "Using default CombatHUDConfig")


func _create_buttons() -> void:
	# Attack button
	attack_button = AbilitySlot.new()
	attack_button.name = "AttackButton"
	attack_button.slot_type = AbilitySlot.SlotType.ATTACK
	attack_button.slot_index = -1
	attack_button.button_radius = config.attack_radius
	attack_button.normal_color = config.attack_color
	attack_button.pressed_color = config.attack_pressed_color
	attack_button.press_scale = config.press_scale
	attack_button.press_duration = config.press_animation_duration
	attack_button.border_width = config.button_border_width
	attack_button.border_color = config.button_border_color
	attack_button.set_icon("⚔")
	attack_button.ability_activated.connect(_on_attack_activated)
	add_child(attack_button)

	# Ability slots
	for i in config.ability_count:
		var slot := AbilitySlot.new()
		slot.name = "AbilitySlot%d" % (i + 1)
		slot.slot_type = AbilitySlot.SlotType.ABILITY
		slot.slot_index = i
		slot.button_radius = config.ability_radius
		slot.normal_color = config.ability_color
		slot.pressed_color = config.ability_pressed_color
		slot.no_resource_color = config.ability_no_mana_color
		slot.cooldown_color = config.ability_cooldown_color
		slot.press_scale = config.press_scale
		slot.press_duration = config.press_animation_duration
		slot.border_width = config.button_border_width
		slot.border_color = config.button_border_color
		slot.ability_activated.connect(_on_ability_activated)
		slot.ability_hold_started.connect(_on_ability_hold_started)
		slot.ability_released.connect(_on_ability_released)
		slot.ability_ready.connect(_on_ability_ready)
		add_child(slot)
		ability_slots.append(slot)

	# Dodge button
	dodge_button = AbilitySlot.new()
	dodge_button.name = "DodgeButton"
	dodge_button.slot_type = AbilitySlot.SlotType.DODGE
	dodge_button.slot_index = -2
	dodge_button.button_radius = config.dodge_radius
	dodge_button.normal_color = config.dodge_color
	dodge_button.pressed_color = config.dodge_pressed_color
	dodge_button.no_resource_color = config.dodge_no_stamina_color
	dodge_button.press_scale = config.press_scale
	dodge_button.press_duration = config.press_animation_duration
	dodge_button.border_width = config.button_border_width
	dodge_button.border_color = config.button_border_color
	dodge_button.set_icon("💨")
	dodge_button.ability_activated.connect(_on_dodge_activated)
	add_child(dodge_button)

	# Quick slot button
	quick_slot_button = AbilitySlot.new()
	quick_slot_button.name = "QuickSlotButton"
	quick_slot_button.slot_type = AbilitySlot.SlotType.QUICK_SLOT
	quick_slot_button.slot_index = -3
	quick_slot_button.button_radius = config.quick_slot_radius
	quick_slot_button.normal_color = config.quick_slot_color
	quick_slot_button.pressed_color = config.quick_slot_pressed_color
	quick_slot_button.empty_color = config.quick_slot_empty_color
	quick_slot_button.press_scale = config.press_scale
	quick_slot_button.press_duration = config.press_animation_duration
	quick_slot_button.border_width = config.button_border_width
	quick_slot_button.border_color = config.button_border_color
	quick_slot_button.set_icon("🧪")
	quick_slot_button.ability_activated.connect(_on_quick_slot_activated)
	add_child(quick_slot_button)

	# Interact button (standard Button, hidden by default)
	interact_button = Button.new()
	interact_button.name = "InteractButton"
	interact_button.text = "Interact"
	interact_button.visible = false
	interact_button.custom_minimum_size = config.interact_size
	add_child(interact_button)


func _layout_buttons() -> void:
	# Get screen size
	var screen_size := get_viewport_rect().size

	# Calculate scale factor for button sizes based on screen height
	# Base design is 720p - scale buttons proportionally for other resolutions
	var scale_factor := screen_size.y / config.base_screen_height
	scale_factor = clampf(scale_factor * config.user_scale, config.min_scale, config.max_scale)

	# Apply scaled radii to buttons
	var scaled_attack_radius := config.attack_radius * scale_factor
	var scaled_ability_radius := config.ability_radius * scale_factor
	var scaled_dodge_radius := config.dodge_radius * scale_factor
	var scaled_quick_slot_radius := config.quick_slot_radius * scale_factor

	# Update button radii (using set_radius to update size and pivot)
	attack_button.set_radius(scaled_attack_radius)
	for slot in ability_slots:
		slot.set_radius(scaled_ability_radius)
	dodge_button.set_radius(scaled_dodge_radius)
	quick_slot_button.set_radius(scaled_quick_slot_radius)

	# Calculate attack button position using percentage-based offset
	var attack_pos := config.get_position_from_pct(config.attack_offset_pct, screen_size)
	attack_button.position = attack_pos - Vector2(scaled_attack_radius, scaled_attack_radius)

	# Calculate attack button center for arc positioning
	var attack_center := attack_pos

	# Position ability slots in arc around attack button
	var ability_positions := config.get_ability_positions(attack_center, screen_size.y)
	for i in ability_slots.size():
		if i < ability_positions.size():
			var pos := ability_positions[i]
			ability_slots[i].position = pos - Vector2(scaled_ability_radius, scaled_ability_radius)

	# Position dodge button
	var dodge_pos := config.get_position_from_pct(config.dodge_offset_pct, screen_size)
	dodge_button.position = dodge_pos - Vector2(scaled_dodge_radius, scaled_dodge_radius)

	# Position quick slot button
	var quick_slot_pos := config.get_position_from_pct(config.quick_slot_offset_pct, screen_size)
	quick_slot_button.position = quick_slot_pos - Vector2(scaled_quick_slot_radius, scaled_quick_slot_radius)

	# Position interact button (scale its size too)
	var interact_pos := config.get_position_from_pct(config.interact_offset_pct, screen_size)
	interact_button.position = interact_pos
	interact_button.custom_minimum_size = config.interact_size * scale_factor


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Re-layout on screen resize
		call_deferred("_layout_buttons")


## Signal handlers

func _on_attack_activated(_slot_index: int, _ability_id: String) -> void:
	Debug.log("Combat", "Attack activated")
	attack_pressed.emit()

	# If a skill is bound to the attack button, execute it
	if attack_button_talent:
		# Use slot index -1 for the attack button (special handling in _on_ability_activated)
		_on_ability_activated(-1, attack_button_talent.id)
		return

	# Basic attack uses the player's request_attack which triggers animation
	if player:
		player.request_attack()


func _on_ability_activated(slot_index: int, ability_id: String) -> void:
	Debug.log("Combat", "Ability activated", {"slot": slot_index, "ability": ability_id})

	# Get the talent data
	var talent := TalentManager.get_talent(ability_id)
	if not talent:
		Debug.warn("Combat", "Talent not found: %s" % ability_id)
		return

	# Check if player can act (not in recovery)
	if player and player.is_locked:
		Debug.log("Combat", "Player is locked, cannot use %s" % talent.talent_name)
		return

	# Check weapon requirement
	if talent.has_weapon_requirement():
		var weapon_cat: String = Inventory.get_equipped_weapon_category()
		if not talent.matches_weapon_category(weapon_cat):
			Debug.log("Combat", "Wrong weapon for %s (requires %s, have %s)" % [
				talent.talent_name, talent.required_weapon_category, weapon_cat if weapon_cat else "none"
			])
			return

	# Check resource costs
	if talent.mana_cost > 0 and PlayerStats.current_mana < talent.mana_cost:
		Debug.log("Combat", "Not enough mana for %s" % talent.talent_name)
		return
	if talent.stamina_cost > 0 and PlayerStats.current_stamina < talent.stamina_cost:
		Debug.log("Combat", "Not enough stamina for %s" % talent.talent_name)
		return

	# Check if this is a magic projectile
	print("[ABILITY] Checking magic projectile: effect_type=%s (MAGIC_PROJECTILE=%s), cast_time=%s" % [
		talent.effect_type, TalentData.EffectType.MAGIC_PROJECTILE, talent.cast_time
	])
	if talent.effect_type == TalentData.EffectType.MAGIC_PROJECTILE:
		print("[ABILITY] Detected magic projectile!")
		if talent.cast_time > 0:
			# Has cast time - start casting sequence
			_start_casting(slot_index, talent)
		else:
			# No cast time - fire immediately
			_fire_magic_projectile_instant(slot_index, talent)
		return

	# Check if this is a self-buff (like Bandage)
	if talent.effect_type == TalentData.EffectType.SELF_BUFF:
		print("[ABILITY] Detected self-buff!")
		if talent.cast_time > 0:
			# Has cast time - start casting sequence
			_start_casting_self_buff(slot_index, talent)
		else:
			# No cast time - apply immediately
			_apply_self_buff_instant(slot_index, talent)
		return

	# Consume resources
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Calculate damage
	var invested := TalentManager.get_invested_points(ability_id)
	var damage_result := DamageCalculator.calculate_final_damage(talent, invested)

	# Apply combat mechanics (lunge, animation, recovery)
	_apply_skill_mechanics(talent)

	# Wait for lunge to complete before applying damage
	var lunge_delay := 0.1  # Match player's attack_lunge_duration
	if talent.lunge_force > 0:
		await get_tree().create_timer(lunge_delay).timeout

	# Apply damage to enemies in range/arc (after lunge)
	_apply_skill_damage(talent, damage_result)

	# Start cooldown
	if talent.cooldown > 0:
		if slot_index == -1:
			# Attack button (main slot)
			attack_button.start_cooldown(talent.cooldown)
		elif slot_index >= 0 and slot_index < ability_slots.size():
			# Regular ability slots
			ability_slots[slot_index].start_cooldown(talent.cooldown)

	ability_pressed.emit(slot_index, ability_id)
	Debug.log("Combat", "Skill executed: %s" % talent.talent_name, {
		"damage": int(damage_result.final_damage),
		"crit": damage_result.is_critical,
		"type": DamageCalculator.get_damage_type_name(damage_result.damage_type),
		"range": talent.hit_range,
		"arc": talent.hit_arc,
	})


func _on_ability_hold_started(slot_index: int, ability_id: String) -> void:
	## Handle hold-to-release skill start (projectile skills)
	Debug.log("Combat", "Ability hold started", {"slot": slot_index, "ability": ability_id})

	var talent := TalentManager.get_talent(ability_id)
	if not talent:
		Debug.warn("Combat", "Talent not found: %s" % ability_id)
		return

	# Check if player can act
	if player and player.is_locked:
		Debug.log("Combat", "Player is locked, cannot aim")
		return

	# Check weapon requirement
	if talent.has_weapon_requirement():
		var weapon_cat: String = Inventory.get_equipped_weapon_category()
		if not talent.matches_weapon_category(weapon_cat):
			Debug.log("Combat", "Wrong weapon for %s" % talent.talent_name)
			return

	# Check stamina (ranged skills use stamina)
	if talent.stamina_cost > 0 and PlayerStats.current_stamina < talent.stamina_cost:
		Debug.log("Combat", "Not enough stamina for %s" % talent.talent_name)
		return

	# Start aiming
	is_aiming = true
	aiming_slot_index = slot_index
	aiming_talent = talent
	aim_start_time = Time.get_ticks_msec() / 1000.0

	# Create aim indicator if needed
	_ensure_aim_indicator()

	# Get aim direction from player facing
	var aim_dir := _get_player_facing_vector()

	# Activate aim indicator (use talent's hit_range with equipment bonus as max range)
	var final_range := get_hit_range(talent)
	aim_indicator.activate(aim_dir, final_range)
	aim_indicator.global_position = player.global_position

	Debug.log("Combat", "Started aiming %s" % talent.talent_name)


func _on_ability_released(slot_index: int, ability_id: String, hold_duration: float) -> void:
	## Handle hold-to-release skill release (fire projectile)
	Debug.log("Combat", "Ability released", {"slot": slot_index, "ability": ability_id, "duration": hold_duration})

	if not is_aiming or slot_index != aiming_slot_index:
		return

	# Get charge settings from talent (database-driven, with equipment bonuses on range)
	var min_charge := aiming_talent.min_charge_time
	var max_charge := aiming_talent.max_charge_time if aiming_talent.max_charge_time > 0 else DEFAULT_MAX_CHARGE_TIME
	var base_range := aiming_talent.base_range if aiming_talent.base_range > 0 else DEFAULT_BASE_RANGE
	var max_range := get_hit_range(aiming_talent)  # hit_range with equipment bonus
	var weak_damage_pct := aiming_talent.weak_shot_damage_percent
	var weak_range_pct := aiming_talent.weak_shot_range_percent

	var is_weak_shot := hold_duration < min_charge
	var damage_multiplier := 1.0
	var effective_range := max_range

	if is_weak_shot:
		# Check if weak shot is enabled (damage > 0)
		if weak_damage_pct <= 0:
			Debug.log("Combat", "Charge too short, weak shot disabled")
			_cancel_aiming()
			return

		# Fire weak shot with reduced damage and range
		damage_multiplier = weak_damage_pct / 100.0
		effective_range = max_range * (weak_range_pct / 100.0)
		Debug.log("Combat", "Weak shot fired", {"damage%": weak_damage_pct, "range%": weak_range_pct})
	else:
		# Calculate charge progress (0-1) for full shots
		var charge_progress := clampf((hold_duration - min_charge) / (max_charge - min_charge), 0.0, 1.0)
		effective_range = lerpf(base_range, max_range, charge_progress)

	# Fire the projectile
	_fire_projectile(aiming_talent, aim_indicator.get_aim_direction(), effective_range, damage_multiplier)

	# Start cooldown
	if aiming_talent.cooldown > 0 and slot_index >= 0 and slot_index < ability_slots.size():
		ability_slots[slot_index].start_cooldown(aiming_talent.cooldown)

	# End aiming
	_end_aiming()


func _ensure_aim_indicator() -> void:
	## Create aim indicator if it doesn't exist
	if aim_indicator:
		return

	aim_indicator = AimIndicatorClass.new()
	aim_indicator.name = "AimIndicator"

	# Add to world (not UI) so it moves with the player
	if player and player.get_parent():
		player.get_parent().add_child(aim_indicator)


func _update_aiming() -> void:
	## Update aim indicator position and direction during aiming
	if not aim_indicator or not player:
		return

	# Update position to follow player
	aim_indicator.global_position = player.global_position

	# Update direction based on player input or facing
	var aim_dir := Vector2.ZERO
	if player.input_direction.length_squared() > 0.01:
		aim_dir = player.input_direction.normalized()
	else:
		aim_dir = _get_player_facing_vector()

	aim_indicator.update_direction(aim_dir)

	# Update charge progress (use talent's charge times from database)
	var current_time := Time.get_ticks_msec() / 1000.0
	var hold_duration := current_time - aim_start_time
	var min_charge := aiming_talent.min_charge_time if aiming_talent else 0.5
	var max_charge := aiming_talent.max_charge_time if aiming_talent and aiming_talent.max_charge_time > 0 else DEFAULT_MAX_CHARGE_TIME
	var charge_progress := clampf((hold_duration - min_charge) / (max_charge - min_charge), 0.0, 1.0)
	aim_indicator.update_charge(charge_progress)


func _fire_projectile(talent: TalentData, direction: Vector2, range_dist: float, damage_multiplier: float) -> void:
	## Fire a projectile in the given direction
	if not player:
		return

	# Consume stamina
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Calculate damage with multiplier (for weak shots)
	var invested := TalentManager.get_invested_points(talent.id)
	var damage_result := DamageCalculator.calculate_final_damage(talent, invested)
	var final_damage: float = damage_result.final_damage * damage_multiplier

	# Create projectile
	var projectile: Area2D = ProjectileClass.create_arrow()
	projectile.max_range = range_dist
	projectile.damage = final_damage
	projectile.damage_type = _get_damage_type_string(talent.damage_type_id)
	projectile.source = player

	# Speed multiplier based on damage (weak shots are slower)
	var speed_mult := lerpf(0.7, 1.0, damage_multiplier)

	# Add to world
	if player.get_parent():
		player.get_parent().add_child(projectile)

	# Launch projectile
	var spawn_pos := player.global_position
	projectile.launch(spawn_pos, direction, speed_mult)

	# Apply recovery lockout
	if talent.recovery_time > 0:
		player.apply_recovery_lockout(talent.recovery_time)

	Debug.log("Combat", "Fired projectile: %s" % talent.talent_name, {
		"direction": direction,
		"range": range_dist,
		"damage": int(final_damage),
		"crit": damage_result.is_critical,
		"multiplier": damage_multiplier
	})


func _cancel_aiming() -> void:
	## Cancel aiming without firing
	_end_aiming()
	Debug.log("Combat", "Aiming cancelled")


func _end_aiming() -> void:
	## Clean up after aiming (success or cancel)
	is_aiming = false
	aiming_slot_index = -1
	aiming_talent = null

	if aim_indicator:
		aim_indicator.deactivate()


#===============================================================================
# MAGIC CASTING
#===============================================================================

func _start_casting(slot_index: int, talent: TalentData) -> void:
	## Start casting a magic projectile spell
	print("[CAST] _start_casting called for %s" % talent.talent_name)

	if not player:
		print("[CAST] ERROR: No player!")
		return

	# Consume resources immediately
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Set up casting state
	is_casting = true
	casting_slot_index = slot_index
	casting_talent = talent
	cast_start_time = Time.get_ticks_msec() / 1000.0
	cast_direction = _get_player_facing_vector()

	print("[CAST] Casting started: cast_time=%s, direction=%s" % [talent.cast_time, cast_direction])


func _update_casting() -> void:
	## Update casting state - check completion and update direction
	if not is_casting or not casting_talent:
		return

	# Handle different casting types
	if casting_talent.effect_type == TalentData.EffectType.SELF_BUFF:
		_update_self_buff_casting()
		return

	# Update cast direction based on player input (for directional spells)
	if player.input_direction.length_squared() > 0.01:
		cast_direction = player.input_direction.normalized()
	else:
		cast_direction = _get_player_facing_vector()

	# Check if cast time has completed
	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed := current_time - cast_start_time

	if elapsed >= casting_talent.cast_time:
		# Cast complete, fire the magic projectile
		_fire_magic_projectile(casting_talent, cast_direction)

		# Start cooldown
		if casting_talent.cooldown > 0:
			if casting_slot_index == -1:
				attack_button.start_cooldown(casting_talent.cooldown)
			elif casting_slot_index >= 0 and casting_slot_index < ability_slots.size():
				ability_slots[casting_slot_index].start_cooldown(casting_talent.cooldown)

		# End casting
		_end_casting()


func _fire_magic_projectile(talent: TalentData, direction: Vector2) -> void:
	## Fire a magic projectile (fireball etc)
	print("[CAST] _fire_magic_projectile called for %s, dir=%s" % [talent.talent_name, direction])

	if not player:
		print("[CAST] ERROR: No player!")
		return

	# Calculate damage
	var invested := TalentManager.get_invested_points(talent.id)
	var damage_result := DamageCalculator.calculate_final_damage(talent, invested)
	print("[CAST] Damage calculated: %s (crit=%s)" % [damage_result.final_damage, damage_result.is_critical])

	# Create magic projectile
	var projectile: Area2D = MagicProjectileClass.new()
	projectile.name = talent.talent_name.replace(" ", "")
	print("[CAST] Projectile created: %s" % projectile.name)

	# Set projectile properties from talent (with equipment bonuses applied)
	var final_speed := get_projectile_speed(talent) if talent.projectile_speed > 0 else 350.0
	var final_range := get_hit_range(talent)
	var final_radius := get_explosion_radius(talent)

	projectile.base_speed = final_speed
	projectile.max_range = final_range
	projectile.explosion_radius = final_radius
	projectile.explosion_falloff = talent.explosion_falloff  # Damage falloff stays as-is (percentage)
	projectile.set_explosion_damage(damage_result.final_damage)
	projectile.damage_type = _get_damage_type_string(talent.damage_type_id)
	projectile.source = player

	print("[CAST] Projectile config: speed=%s, range=%s, radius=%s, damage=%s, falloff=%s%%" % [
		final_speed, final_range, final_radius, damage_result.final_damage, talent.explosion_falloff
	])

	# Set contact status effect
	if not talent.contact_status_effect.is_empty():
		projectile.set_contact_effect(talent.contact_status_effect, 0.0)
		print("[CAST] Contact effect set: %s" % talent.contact_status_effect)

	# Add to world
	if player.get_parent():
		player.get_parent().add_child(projectile)
		print("[CAST] Projectile added to world: %s" % player.get_parent().name)
	else:
		print("[CAST] ERROR: Player has no parent!")

	# Launch projectile
	var spawn_pos := player.global_position
	print("[CAST] Launching from %s in direction %s" % [spawn_pos, direction])
	projectile.launch(spawn_pos, direction)

	# Apply recovery lockout after firing
	if talent.recovery_time > 0:
		player.apply_recovery_lockout(talent.recovery_time)

	print("[CAST] Projectile launched successfully!")
	Debug.log("Combat", "Fired magic projectile: %s" % talent.talent_name, {
		"direction": direction,
		"range": talent.hit_range,
		"explosion_radius": talent.explosion_radius,
		"damage": int(damage_result.final_damage),
		"crit": damage_result.is_critical,
		"status_effect": talent.contact_status_effect
	})


func _end_casting() -> void:
	## Clean up after casting completes
	is_casting = false
	casting_slot_index = -1
	casting_talent = null


func _fire_magic_projectile_instant(slot_index: int, talent: TalentData) -> void:
	## Fire a magic projectile instantly (no cast time)
	print("[CAST] _fire_magic_projectile_instant called for %s" % talent.talent_name)

	# Consume resources
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Get direction from player facing
	var direction := _get_player_facing_vector()

	# Fire the projectile
	_fire_magic_projectile(talent, direction)

	# Start cooldown
	if talent.cooldown > 0:
		if slot_index == -1:
			attack_button.start_cooldown(talent.cooldown)
		elif slot_index >= 0 and slot_index < ability_slots.size():
			ability_slots[slot_index].start_cooldown(talent.cooldown)


#===============================================================================
# SELF-BUFF CASTING (Bandage, etc.)
#===============================================================================

func _start_casting_self_buff(slot_index: int, talent: TalentData) -> void:
	## Start casting a self-buff spell with cast time
	print("[CAST] _start_casting_self_buff called for %s" % talent.talent_name)

	if not player:
		return

	# Consume resources immediately
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Set up casting state (reuse the same casting variables)
	is_casting = true
	casting_slot_index = slot_index
	casting_talent = talent
	cast_start_time = Time.get_ticks_msec() / 1000.0
	# Self-buff doesn't need direction
	cast_direction = Vector2.ZERO

	print("[CAST] Self-buff casting started: cast_time=%s" % talent.cast_time)


func _update_self_buff_casting() -> void:
	## Update self-buff casting state - check completion
	if not is_casting or not casting_talent:
		return

	# Self-buffs don't update direction

	# Check if cast time has completed
	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed := current_time - cast_start_time

	if elapsed >= casting_talent.cast_time:
		# Cast complete, apply the buff
		_apply_self_buff(casting_talent)

		# Start cooldown
		if casting_talent.cooldown > 0:
			if casting_slot_index == -1:
				attack_button.start_cooldown(casting_talent.cooldown)
			elif casting_slot_index >= 0 and casting_slot_index < ability_slots.size():
				ability_slots[casting_slot_index].start_cooldown(casting_talent.cooldown)

		# End casting
		_end_casting()


func _apply_self_buff_instant(slot_index: int, talent: TalentData) -> void:
	## Apply a self-buff instantly (no cast time)
	print("[CAST] _apply_self_buff_instant called for %s" % talent.talent_name)

	# Consume resources
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Apply the buff
	_apply_self_buff(talent)

	# Start cooldown
	if talent.cooldown > 0:
		if slot_index == -1:
			attack_button.start_cooldown(talent.cooldown)
		elif slot_index >= 0 and slot_index < ability_slots.size():
			ability_slots[slot_index].start_cooldown(talent.cooldown)


func _apply_self_buff(talent: TalentData) -> void:
	## Apply the self-buff effect to the player
	print("[CAST] Applying self-buff: %s" % talent.talent_name)

	# Apply status effect from contact_status_effect field
	if not talent.contact_status_effect.is_empty():
		if Game.player and Game.player.status_effect_manager:
			Game.player.status_effect_manager.apply_status_effect(talent.contact_status_effect)
			Debug.log("Combat", "Self-buff applied: %s -> %s" % [talent.talent_name, talent.contact_status_effect])
		else:
			Debug.warn("Combat", "Cannot apply self-buff: no status_effect_manager")


func _apply_skill_mechanics(talent: TalentData) -> void:
	## Apply lunge, animation, and recovery to player
	if not player:
		return

	# Trigger attack animation for melee skills
	if talent.skill_category.to_lower() == "melee":
		player.request_attack()

	# Apply lunge if specified (with equipment bonuses applied)
	if talent.lunge_force > 0:
		var final_lunge_force := get_lunge_force(talent)
		var final_lunge_duration := get_lunge_duration(talent)
		player.apply_skill_lunge(final_lunge_force, final_lunge_duration)

	# Apply recovery lockout if specified
	if talent.recovery_time > 0:
		player.apply_recovery_lockout(talent.recovery_time)


func _apply_skill_damage(talent: TalentData, damage_result: Dictionary) -> void:
	## Apply skill damage to enemies in range and arc
	if not player:
		return

	# Use hit_range and hit_arc with equipment bonuses applied
	var skill_range := get_hit_range(talent)
	var skill_arc := get_hit_arc(talent)

	# Spawn visual hitbox indicator
	_spawn_skill_visual(talent, damage_result)

	# Find enemies in range
	var enemies := NPCManager.get_enemies_in_radius(player.global_position, skill_range)

	# Get player facing direction for arc check
	var facing_vector := _get_player_facing_vector()

	for enemy in enemies:
		# Check if enemy is within hit arc (skip if arc is 360 = all around)
		if skill_arc < 360.0:
			var enemy_pos: Vector2 = enemy.global_position
			var to_enemy: Vector2 = (enemy_pos - player.global_position).normalized()
			var angle: float = rad_to_deg(facing_vector.angle_to(to_enemy))
			if abs(angle) > skill_arc / 2.0:
				continue  # Enemy is outside hit arc

		if enemy.has_method("take_damage"):
			# Apply armor/resistance reduction on enemy
			var final_damage: float = damage_result.final_damage
			if enemy.has_method("_calculate_damage_after_armor"):
				final_damage = enemy._calculate_damage_after_armor(final_damage)

			enemy.take_damage(final_damage, player)

			# Spawn hit effect on enemy
			_spawn_hit_effect(enemy.global_position, _get_damage_type_string(talent.damage_type_id))

			# Log crit hits
			if damage_result.is_critical:
				Debug.log("Combat", "CRITICAL %s on %s!" % [talent.talent_name, enemy.enemy_name], "%.0f damage" % final_damage)


func _spawn_skill_visual(talent: TalentData, _damage_result: Dictionary) -> void:
	## Spawn visual indicator for skill hitbox
	var visual := HitboxVisual.new()

	# Get range and arc with equipment bonuses
	var final_range := get_hit_range(talent)
	var final_arc := get_hit_arc(talent)

	# Configure shape based on arc
	if final_arc >= 360.0:
		# Full circle
		visual.draw_type = "circle"
		visual.radius = final_range
	else:
		# Cone shape
		visual.draw_type = "polygon"
		visual.points = _generate_cone_points(final_range, final_arc)

	# Set damage type for color (convert from int id to string)
	visual.damage_type = _get_damage_type_string(talent.damage_type_id)

	# Position at player, rotated to facing direction
	visual.global_position = player.global_position

	# Rotate to face direction (only for cones)
	if final_arc < 360.0:
		var facing := _get_player_facing_vector()
		visual.rotation = facing.angle()

	# Setup with no windup (instant)
	visual.setup(null, 0.0)

	# Add to world (not UI)
	player.get_parent().add_child(visual)


func _generate_cone_points(length: float, angle_deg: float) -> PackedVector2Array:
	## Generate cone polygon points for visual
	var points := PackedVector2Array()
	var half_angle := deg_to_rad(angle_deg / 2.0)
	var segments := 12  # Smooth arc

	# Start at origin
	points.append(Vector2.ZERO)

	# Arc points
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var current_angle := -half_angle + t * half_angle * 2
		var point := Vector2(cos(current_angle), sin(current_angle)) * length
		points.append(point)

	return points


func _spawn_hit_effect(pos: Vector2, damage_type: String) -> void:
	## Spawn particle effect when hitting an enemy
	if player and player.get_parent():
		HitboxVisual.spawn_hit_effect(player.get_parent(), pos, damage_type)


func _get_damage_type_string(damage_type_id: int) -> String:
	## Convert damage type ID to string for visuals
	match damage_type_id:
		0: return "physical"
		1: return "fire"
		2: return "cold"
		3: return "lightning"
		4: return "poison"
		5: return "arcane"
		6: return "holy"
		7: return "shadow"
		8: return "physical"  # Bleed = physical color
		9: return "poison"    # Nature = poison color
		_: return "physical"


func _get_player_facing_vector() -> Vector2:
	## Get player's facing direction as a vector
	if not player:
		return Vector2.DOWN

	match player.current_facing:
		PlayerController.Facing.DOWN:
			return Vector2.DOWN
		PlayerController.Facing.UP:
			return Vector2.UP
		PlayerController.Facing.LEFT:
			return Vector2.LEFT
		PlayerController.Facing.RIGHT:
			return Vector2.RIGHT

	return Vector2.DOWN


func _on_ability_ready(slot_index: int) -> void:
	Debug.log("Combat", "Ability ready", {"slot": slot_index})
	# Could play a sound or show a visual indicator


func _on_dodge_activated(_slot_index: int, _ability_id: String) -> void:
	Debug.log("Combat", "Dodge activated")
	dodge_pressed.emit()

	if player and Game.can_player_move:
		player.request_dodge()
		# Start dodge cooldown
		dodge_button.start_cooldown(1.0)


func _on_quick_slot_activated(_slot_index: int, _ability_id: String) -> void:
	Debug.log("Combat", "Quick slot activated")
	quick_slot_pressed.emit()

	# TODO: Use consumable from quick slot
	# For now, just test cooldown
	quick_slot_button.start_cooldown(3.0)


func _on_player_spawned(new_player: Node2D) -> void:
	if new_player is PlayerController:
		player = new_player as PlayerController
		Debug.info("Combat", "CombatHUD connected to player")


## Public API

func bind_ability_to_slot(slot_index: int, ability_id: String, data: Dictionary = {}) -> void:
	if slot_index < 0 or slot_index >= ability_slots.size():
		Debug.warn("Combat", "Invalid slot index", {"slot": slot_index})
		return

	ability_slots[slot_index].bind_ability(ability_id, data)


func clear_ability_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= ability_slots.size():
		return

	ability_slots[slot_index].clear_ability()


func bind_quick_slot(item_id: String, data: Dictionary = {}) -> void:
	quick_slot_button.bind_ability(item_id, data)


func clear_quick_slot() -> void:
	quick_slot_button.clear_ability()


func get_ability_slot(slot_index: int) -> AbilitySlot:
	if slot_index < 0 or slot_index >= ability_slots.size():
		return null
	return ability_slots[slot_index]


func start_ability_cooldown(slot_index: int, duration: float) -> void:
	if slot_index < 0 or slot_index >= ability_slots.size():
		return
	ability_slots[slot_index].start_cooldown(duration)


## Interact button management

func show_interact_button(prompt: String = "Interact") -> void:
	interact_button.text = prompt
	interact_button.visible = true


func hide_interact_button() -> void:
	interact_button.visible = false


func is_interact_visible() -> bool:
	return interact_button.visible


## Layout customization stubs (for future implementation)

func set_user_scale(scale: float) -> void:
	## Stub: Adjust overall HUD scale
	config.user_scale = clampf(scale, config.min_scale, config.max_scale)
	# TODO: Apply scale to all buttons
	Debug.log("Combat", "User scale set (stub)", {"scale": scale})


func set_left_handed_mode(enabled: bool) -> void:
	## Stub: Mirror layout for left-handed players
	config.left_handed_mode = enabled
	# TODO: Re-layout with mirrored positions
	Debug.log("Combat", "Left-handed mode set (stub)", {"enabled": enabled})


func set_layout_preset(preset_name: String) -> void:
	## Stub: Switch to a different layout preset
	config.layout_preset = preset_name
	# TODO: Load preset config and apply
	Debug.log("Combat", "Layout preset set (stub)", {"preset": preset_name})


func reset_to_default() -> void:
	## Stub: Reset all customizations to default
	config.user_scale = 1.0
	config.left_handed_mode = false
	config.layout_preset = "default"
	_layout_buttons()
	Debug.log("Combat", "Layout reset to default (stub)")
