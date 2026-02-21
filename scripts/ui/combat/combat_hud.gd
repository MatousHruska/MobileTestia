extends Control
class_name CombatHUD
## CombatHUD - Layout manager for combat action buttons
##
## Structure:
##   CombatHUD
##   ├── AbilityWheel (Control) - Main combat actions in arc layout
##   │   ├── AttackButton - Main attack (slot 0), can have skill bound
##   │   └── AbilitySlot[1-5] - Skills bound in arc around attack
##   ├── UtilityBar (Control) - Support/utility actions
##   │   ├── DodgeButton - Evasion/roll
##   │   └── QuickSlotButton - Consumable items
##   └── InteractButton - Context-sensitive (Talk, Loot, Open)

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

#region Container References
## AbilityWheel - Groups Attack Button + Ability Slots for unified manipulation
var ability_wheel: Control

## UtilityBar - Groups Dodge + Quick Slot for unified manipulation
var utility_bar: Control
#endregion

#region Button References
## AbilityWheel children
var attack_button: AbilitySlot
var ability_slots: Array[AbilitySlot] = []

## UtilityBar children
var dodge_button: AbilitySlot
var quick_slot_button: AbilitySlot

## Interact Button - Context-sensitive action (standalone)
var interact_button: Button
#endregion

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

## Toggle stance tracking
var _active_stance_slot: int = -1  ## Slot index of currently active toggle stance (-1 = none)
var _active_stance_talent_id: String = ""

## Pending talent for visual sequencer signal-based damage/projectile handling
var _pending_talent: TalentData = null
var _pending_slot_index: int = -1

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
	# Include talent stat bonuses (e.g., Noble's Reach adds hit_range:5 per point)
	var talent_bonuses := TalentManager.get_total_stat_bonuses()
	bonus += talent_bonuses.get(stat_name, 0.0)
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


#===============================================================================
# VISUAL SEQUENCER INTEGRATION
#===============================================================================

## Map TalentData to visual template ID. Delegates to AbilityVisualTemplates.
static func _get_visual_template_for_talent(talent: TalentData) -> String:
	return AbilityVisualTemplates.resolve_template_for_talent(talent)


static func _build_visual_overrides(talent: TalentData) -> Dictionary:
	var overrides := {}

	if talent.lunge_force > 0:
		overrides["lunge_distance"] = get_lunge_force(talent)
	if talent.lunge_duration > 0:
		overrides["lunge_duration"] = talent.lunge_duration
	if talent.recovery_time > 0:
		overrides["recovery_duration"] = talent.recovery_time
	if talent.cast_time > 0:
		overrides["cast_duration"] = get_cast_time(talent)
	if talent.show_weapon:
		overrides["show_weapon"] = true
	if talent.windup_time > 0:
		overrides["windup_duration"] = talent.windup_time
	if not talent.hit_effect.is_empty():
		overrides["hit_effect_id"] = talent.hit_effect

	return overrides


func _connect_visual_signals() -> void:
	if not player or not player.ability_visual_player:
		return
	var vp := player.ability_visual_player

	if not vp.damage_event.is_connected(_on_visual_damage_event):
		vp.damage_event.connect(_on_visual_damage_event)
	if not vp.spawn_projectile_event.is_connected(_on_visual_spawn_projectile):
		vp.spawn_projectile_event.connect(_on_visual_spawn_projectile)
	if not vp.sequence_finished.is_connected(_on_visual_finished):
		vp.sequence_finished.connect(_on_visual_finished)


func _disconnect_visual_signals() -> void:
	if not player or not player.ability_visual_player:
		return
	var vp := player.ability_visual_player
	if vp.damage_event.is_connected(_on_visual_damage_event):
		vp.damage_event.disconnect(_on_visual_damage_event)
	if vp.spawn_projectile_event.is_connected(_on_visual_spawn_projectile):
		vp.spawn_projectile_event.disconnect(_on_visual_spawn_projectile)
	if vp.sequence_finished.is_connected(_on_visual_finished):
		vp.sequence_finished.disconnect(_on_visual_finished)


func _on_visual_damage_event() -> void:
	## The sequencer says "now is the damage frame" — apply damage using existing logic
	if _pending_talent:
		var invested := TalentManager.get_invested_points(_pending_talent.id)
		var damage_result := DamageCalculator.calculate_final_damage(_pending_talent, invested)
		_apply_skill_damage(_pending_talent, damage_result)
	else:
		# Basic attack — enable hitbox briefly
		if player:
			player._on_attack_hit_frame()


func _on_visual_spawn_projectile(_context: Dictionary = {}) -> void:
	## The sequencer says "now spawn the projectile" — spawn using existing logic
	if _pending_talent:
		_spawn_skill_projectile(_pending_talent)


func _on_visual_finished(_template_id: String) -> void:
	_pending_talent = null
	_pending_slot_index = -1
	_disconnect_visual_signals()


func _spawn_skill_projectile(talent: TalentData) -> void:
	## Pure projectile spawning — no animation logic
	## Called by the visual sequencer's spawn_projectile_event signal
	var facing_dir := _get_player_facing_vector()

	match talent.effect_type:
		TalentData.EffectType.PROJECTILE:
			# For physical projectiles, use existing _fire_projectile logic
			var max_range := get_hit_range(talent)
			_fire_projectile(talent, facing_dir, max_range, 1.0)
		TalentData.EffectType.MAGIC_PROJECTILE:
			_fire_magic_projectile(talent, facing_dir)
		TalentData.EffectType.MAGIC_PROJECTILE_AOE:
			_fire_magic_projectile(talent, facing_dir)


func _find_nearest_enemy_position() -> Vector2:
	## Find the nearest enemy position for lunge targeting
	if not player:
		return Vector2.ZERO

	var nearest_pos := player.global_position + _get_player_facing_vector() * 50.0
	var nearest_dist := INF

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := player.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = enemy.global_position

	return nearest_pos


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
		"icon_name": talent.icon_name,
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
		"icon_name": talent.icon_name,
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


func _get_ability_positions_with_distance(attack_center: Vector2, arc_distance: float) -> Array[Vector2]:
	## Calculate ability positions with a specific arc distance (for responsive scaling)
	var positions: Array[Vector2] = []

	if config.ability_count <= 1:
		var angle_rad := deg_to_rad((config.arc_start_angle + config.arc_end_angle) / 2.0)
		var offset := Vector2(cos(angle_rad), sin(angle_rad)) * arc_distance
		positions.append(attack_center + offset)
		return positions

	var angle_step := (config.arc_end_angle - config.arc_start_angle) / float(config.ability_count - 1)

	for i in config.ability_count:
		var angle_deg := config.arc_start_angle + (angle_step * float(i))
		var angle_rad := deg_to_rad(angle_deg)
		var offset := Vector2(cos(angle_rad), sin(angle_rad)) * arc_distance
		positions.append(attack_center + offset)

	return positions


func _load_or_create_config() -> void:
	if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
		config = load(DEFAULT_CONFIG_PATH) as CombatHUDConfig
	else:
		config = CombatHUDConfig.new()
		Debug.info("Combat", "Using default CombatHUDConfig")


func _create_buttons() -> void:
	# Create AbilityWheel container (Attack + Ability Slots)
	ability_wheel = Control.new()
	ability_wheel.name = "AbilityWheel"
	ability_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ability_wheel)

	# Create UtilityBar container (Dodge + Quick Slot)
	utility_bar = Control.new()
	utility_bar.name = "UtilityBar"
	utility_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(utility_bar)

	# Attack button (child of AbilityWheel)
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
	ability_wheel.add_child(attack_button)

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
		ability_wheel.add_child(slot)
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
	utility_bar.add_child(dodge_button)

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
	utility_bar.add_child(quick_slot_button)

	# Interact button (standard Button, hidden by default) - Level 2 Header
	# Uses anchor-based layout for dynamic scaling (Center Right preset)
	interact_button = Button.new()
	interact_button.name = "InteractButton"
	interact_button.text = "Interact"
	interact_button.visible = false
	interact_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow left
	interact_button.grow_vertical = Control.GROW_DIRECTION_BOTH  # Grow both directions
	interact_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	interact_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	interact_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	add_child(interact_button)


func _layout_buttons() -> void:
	## Layout all combat buttons using hierarchical positioning:
	## 1. Groups positioned relative to screen via anchor percentages
	## 2. Buttons within groups positioned relative to each other

	var screen_size := get_viewport_rect().size

	# Calculate scale factor for button sizes based on screen height
	var scale_factor := screen_size.y / config.base_screen_height
	scale_factor = clampf(scale_factor * config.user_scale, config.min_scale, config.max_scale)

	# Scale button radii
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

	#===========================================================================
	# ABILITY WHEEL LAYOUT
	# Group anchor determines center, buttons positioned relative to center
	#===========================================================================
	var wheel_center := config.get_ability_wheel_center(screen_size)

	# Attack button at center of AbilityWheel
	attack_button.position = wheel_center - Vector2(scaled_attack_radius, scaled_attack_radius)

	# Ability slots in arc around attack button center
	var min_arc_distance := scaled_attack_radius + scaled_ability_radius + (8.0 * scale_factor)
	var config_arc_distance := config.get_arc_distance(screen_size.y)
	var actual_arc_distance := maxf(min_arc_distance, config_arc_distance)

	var ability_positions := _get_ability_positions_with_distance(wheel_center, actual_arc_distance)
	for i in ability_slots.size():
		if i < ability_positions.size():
			var pos := ability_positions[i]
			ability_slots[i].position = pos - Vector2(scaled_ability_radius, scaled_ability_radius)

	#===========================================================================
	# UTILITY BAR LAYOUT
	# Group anchor determines center, Dodge and QuickSlot arranged horizontally
	# Layout: [QuickSlot] --gap-- [Dodge]  (QuickSlot on left, Dodge on right)
	#===========================================================================
	var utility_center := config.get_utility_bar_center(screen_size)
	var utility_gap := config.get_utility_bar_gap(screen_size.x)

	# Calculate total width of UtilityBar: both buttons + gap between them
	var utility_total_width := (scaled_dodge_radius * 2) + utility_gap + (scaled_quick_slot_radius * 2)

	# Dodge button on the right side of UtilityBar center
	var dodge_offset_x := (utility_total_width / 2.0) - scaled_dodge_radius
	var dodge_pos := Vector2(utility_center.x + dodge_offset_x, utility_center.y)
	dodge_button.position = dodge_pos - Vector2(scaled_dodge_radius, scaled_dodge_radius)

	# QuickSlot button on the left side of UtilityBar center
	var quick_slot_offset_x := (utility_total_width / 2.0) - scaled_quick_slot_radius
	var quick_slot_pos := Vector2(utility_center.x - quick_slot_offset_x, utility_center.y)
	quick_slot_button.position = quick_slot_pos - Vector2(scaled_quick_slot_radius, scaled_quick_slot_radius)

	#===========================================================================
	# INTERACT BUTTON
	# Positioned using anchor-based layout from config
	#===========================================================================
	var interact_pos := config.get_position_from_pct(config.interact_offset_pct, screen_size)
	interact_pos = config.apply_handedness(interact_pos, screen_size.x)

	# Calculate scaled size from config
	var scaled_interact_size := config.interact_size * scale_factor

	interact_button.anchor_left = 1.0
	interact_button.anchor_top = 0.5
	interact_button.anchor_right = 1.0
	interact_button.anchor_bottom = 0.5

	# Use config size for offsets (button grows left from right edge, centered vertically)
	interact_button.offset_left = -scaled_interact_size.x
	interact_button.offset_top = -scaled_interact_size.y / 2.0
	interact_button.offset_right = 0.0
	interact_button.offset_bottom = scaled_interact_size.y / 2.0
	interact_button.custom_minimum_size = scaled_interact_size


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
		_on_ability_activated(-1, attack_button_talent.id)
		return

	# Basic attack — use visual sequencer if available, else legacy
	if player:
		if player.ability_visual_player:
			var overrides := {
				"lunge_distance": player.attack_lunge_force,
				"lunge_duration": player.attack_lunge_duration,
			}
			_pending_talent = null  # No talent — basic attack uses hitbox
			_pending_slot_index = -1
			_connect_visual_signals()
			player.play_ability_visual("melee_single", overrides)
		else:
			player.request_attack()


func _on_ability_activated(slot_index: int, ability_id: String) -> void:
	Debug.log("Combat", "Ability activated", {"slot": slot_index, "ability": ability_id})

	# Get the talent data
	var talent := TalentManager.get_talent(ability_id)
	if not talent:
		Debug.warn("Combat", "Talent not found: %s" % ability_id)
		return

	# Check if this is a deactivation of an active toggle stance
	if _active_stance_slot >= 0 and ability_id == _active_stance_talent_id:
		_deactivate_active_stance()
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

	# --- New sequencer-based path ---
	if player and player.ability_visual_player:
		_activate_skill_via_sequencer(slot_index, talent)
		return

	# --- Legacy fallback path ---
	_activate_skill_legacy(slot_index, talent)


func _activate_skill_via_sequencer(slot_index: int, talent: TalentData) -> void:
	## Sequencer-based skill activation — delegates visuals to AbilityVisualPlayer

	# For ranged skills, start aiming instead of immediate play
	if talent.effect_type == TalentData.EffectType.PROJECTILE:
		_start_aiming(slot_index, talent)
		return

	# Abilities with cast_time use the legacy path which handles the cast bar
	if talent.cast_time > 0:
		_activate_skill_legacy(slot_index, talent)
		return

	# Consume resources
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Determine visual template
	var template_id := _get_visual_template_for_talent(talent)
	var overrides := _build_visual_overrides(talent)

	# For parry_stance: calculate full parry duration (with Deflective Spin) before playing
	var parry_duration: float = 0.0
	if template_id == "parry_stance":
		parry_duration = talent.duration if talent.duration > 0 else 0.5
		if TalentManager.get_invested_points("tal_noble_deflective_spin") > 0:
			parry_duration += 0.2
		overrides["parry_window_duration"] = parry_duration

	# Find nearest enemy for target position (used by lunge direction)
	var target_pos := _find_nearest_enemy_position()

	# Connect to damage/projectile events for this activation
	_pending_talent = talent
	_pending_slot_index = slot_index
	_connect_visual_signals()

	# Play the visual sequence
	player.play_ability_visual(template_id, overrides, target_pos)

	# Start parry window after visual begins
	if template_id == "parry_stance":
		TalentProcSystem.start_parry_window(parry_duration, talent)

	# Start toggle stance if this is a toggle ability
	if template_id == "toggle_stance":
		player.activate_stance(talent)
		_active_stance_slot = slot_index
		_active_stance_talent_id = talent.id

	# Start cooldown
	_start_slot_cooldown(slot_index, talent)

	ability_pressed.emit(slot_index, talent.id)

	# Notify quest system for USE_ABILITY objectives
	if QuestManager:
		QuestManager.on_ability_used(talent.id)

	Debug.log("Combat", "Skill via sequencer: %s (template: %s)" % [talent.talent_name, template_id])


func _start_aiming(slot_index: int, talent: TalentData) -> void:
	## Start aiming for ranged skills (enters hold-to-charge flow)
	## This bridges into the existing _on_ability_hold_started logic
	is_aiming = true
	aiming_slot_index = slot_index
	aiming_talent = talent
	aim_start_time = Time.get_ticks_msec() / 1000.0

	_ensure_aim_indicator()

	var aim_dir := _get_player_facing_vector()
	var final_range := get_hit_range(talent)
	aim_indicator.activate(aim_dir, final_range)
	aim_indicator.global_position = player.global_position

	# Start visual sequence immediately so the bow is visible during charging.
	# Phase 0 (show weapon) and Phase 1 (aim animation) execute, then the
	# sequence holds on Phase 1 until the player releases the button.
	if player and player.ability_visual_player:
		var overrides := _build_visual_overrides(talent)
		_pending_talent = talent
		_pending_slot_index = slot_index
		_connect_visual_signals()

		# Slow down the aim animation so the draw-back matches the charge time.
		# Aim animation is 2 frames at 8fps = 0.25s. Scale to min_charge_time.
		var min_charge := talent.min_charge_time if talent.min_charge_time > 0 else 0.5
		var aim_anim_base_duration := 0.25  # 2 frames at 8fps
		player.character_visuals.set_body_speed_scale(aim_anim_base_duration / min_charge)

		player.play_ability_visual("ranged_aim", overrides)
		player.ability_visual_player.hold_current_phase()

	Debug.log("Combat", "Started aiming %s (via sequencer)" % talent.talent_name)


func _start_slot_cooldown(slot_index: int, talent: TalentData) -> void:
	## Start cooldown on the appropriate slot
	if talent.cooldown > 0:
		if slot_index == -1:
			attack_button.start_cooldown(talent.cooldown)
		elif slot_index >= 0 and slot_index < ability_slots.size():
			ability_slots[slot_index].start_cooldown(talent.cooldown)


func _activate_skill_legacy(slot_index: int, talent: TalentData) -> void:
	## Legacy (pre-sequencer) skill activation — inline animation/movement

	# Check if this is a magic projectile (AOE or single-target)
	var is_magic_projectile := talent.effect_type in [
		TalentData.EffectType.MAGIC_PROJECTILE,
		TalentData.EffectType.MAGIC_PROJECTILE_AOE
	]
	if is_magic_projectile:
		if talent.cast_time > 0:
			_start_casting(slot_index, talent)
		else:
			_fire_magic_projectile_instant(slot_index, talent)
		return

	# Check if this is a self-buff (like Bandage)
	if talent.effect_type == TalentData.EffectType.SELF_BUFF:
		if talent.cast_time > 0:
			_start_casting_self_buff(slot_index, talent)
		else:
			_apply_self_buff_instant(slot_index, talent)
		return

	# Consume resources
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Calculate damage
	var invested := TalentManager.get_invested_points(talent.id)
	var damage_result := DamageCalculator.calculate_final_damage(talent, invested)

	# Apply combat mechanics (lunge, animation, recovery)
	_apply_skill_mechanics(talent)

	# Wait for lunge to complete before applying damage
	var lunge_delay := 0.1
	if talent.lunge_force > 0:
		await get_tree().create_timer(lunge_delay).timeout

	# Apply damage to enemies in range/arc (after lunge)
	_apply_skill_damage(talent, damage_result)

	# Start cooldown
	_start_slot_cooldown(slot_index, talent)

	ability_pressed.emit(slot_index, talent.id)

	# Notify quest system for USE_ABILITY objectives
	if QuestManager:
		QuestManager.on_ability_used(talent.id)

	Debug.log("Combat", "Skill executed (legacy): %s" % talent.talent_name, {
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

	# Start aiming (delegates to _start_aiming for shared logic)
	_start_aiming(slot_index, talent)


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

	# Consume resources on release
	if aiming_talent.stamina_cost > 0:
		PlayerStats.use_stamina(aiming_talent.stamina_cost)
	if aiming_talent.mana_cost > 0:
		PlayerStats.use_mana(aiming_talent.mana_cost)

	# Use sequencer path if available (sequence was started in _start_aiming)
	if player and player.ability_visual_player and player.ability_visual_player.is_playing:
		# Reset animation speed and release the held aim phase so the
		# sequence continues: aim_release -> bowstring_snap -> spawn -> hide -> idle
		player.character_visuals.set_body_speed_scale(1.0)
		player.ability_visual_player.release_held_phase()
	elif player:
		# Legacy path — fire projectile directly
		_fire_projectile(aiming_talent, aim_indicator.get_aim_direction(), effective_range, damage_multiplier)

	# Start cooldown
	_start_slot_cooldown(slot_index, aiming_talent)

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
	projectile.damage_type = _get_damage_type_string(talent.damage_type)
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
	if player and player.ability_visual_player and player.ability_visual_player.is_playing:
		player.character_visuals.set_body_speed_scale(1.0)
		player.ability_visual_player.cancel()
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

	# Show weapon during cast if talent requests it (e.g., staff for fireball)
	if talent.show_weapon and player.character_visuals:
		player.character_visuals.set_weapon_visible(true)

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
	## Fire a magic projectile (AOE or single-target)
	print("[CAST] _fire_magic_projectile called for %s, dir=%s" % [talent.talent_name, direction])

	if not player:
		print("[CAST] ERROR: No player!")
		return

	# Check if this is an AOE projectile or single-target
	var is_aoe := talent.effect_type == TalentData.EffectType.MAGIC_PROJECTILE_AOE

	# Calculate damage
	var invested := TalentManager.get_invested_points(talent.id)
	var damage_result := DamageCalculator.calculate_final_damage(talent, invested)
	print("[CAST] Damage calculated: %s (crit=%s), AOE=%s" % [damage_result.final_damage, damage_result.is_critical, is_aoe])

	# Create magic projectile
	var projectile: Area2D = MagicProjectileClass.new()
	projectile.name = talent.talent_name.replace(" ", "")
	print("[CAST] Projectile created: %s" % projectile.name)

	# Set projectile properties from talent (with equipment bonuses applied)
	var final_speed := get_projectile_speed(talent) if talent.projectile_speed > 0 else 350.0
	var final_range := get_hit_range(talent)

	projectile.base_speed = final_speed
	projectile.max_range = final_range
	projectile.damage_type = _get_damage_type_string(talent.damage_type)
	projectile.source = player

	if is_aoe:
		# AOE projectile: passes through enemies, explodes at destination
		var final_radius := get_explosion_radius(talent)
		projectile.explosion_radius = final_radius
		projectile.explosion_falloff = talent.explosion_falloff
		projectile.set_explosion_damage(damage_result.final_damage)
		projectile.pass_through_enemies = true
		print("[CAST] AOE config: radius=%s, damage=%s, falloff=%s%%" % [
			final_radius, damage_result.final_damage, talent.explosion_falloff
		])
	else:
		# Single-target projectile: stops on first hit, no explosion
		projectile.explosion_radius = 0.0
		projectile.explosion_falloff = 0.0
		projectile.set_explosion_damage(0.0)
		projectile.pass_through_enemies = false
		projectile.contact_damage = damage_result.final_damage
		print("[CAST] Single-target config: contact_damage=%s" % damage_result.final_damage)

	print("[CAST] Projectile config: speed=%s, range=%s" % [final_speed, final_range])

	# Set contact status effect
	if not talent.contact_status_effect.is_empty():
		projectile.set_contact_effect(talent.contact_status_effect, 0.0 if is_aoe else damage_result.final_damage)
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
		"is_aoe": is_aoe,
		"explosion_radius": talent.explosion_radius if is_aoe else 0,
		"damage": int(damage_result.final_damage),
		"crit": damage_result.is_critical,
		"status_effect": talent.contact_status_effect
	})


func _end_casting() -> void:
	## Clean up after casting completes
	# Hide weapon if it was shown during cast
	if casting_talent and casting_talent.show_weapon and player and player.character_visuals:
		player.character_visuals.set_weapon_visible(false)
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

	# Notify quest system for USE_ABILITY objectives
	if QuestManager:
		QuestManager.on_ability_used(talent.id)

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
	## Start casting a self-buff spell with cast time using PlayerController's cast system
	print("[CAST] _start_casting_self_buff called for %s" % talent.talent_name)

	if not player:
		return

	# Get cast parameters from talent database
	var can_move := talent.can_move_while_casting
	var interrupt_on_damage := talent.interrupt_on_damage
	var cast_time := get_cast_time(talent)

	# Try to start casting via PlayerController (which emits signals for CastBar)
	if not player.start_cast(talent.id, cast_time, can_move, interrupt_on_damage):
		Debug.log("Combat", "Failed to start self-buff cast: %s" % talent.talent_name)
		return

	# Consume resources immediately
	if talent.mana_cost > 0:
		PlayerStats.use_mana(talent.mana_cost)
	if talent.stamina_cost > 0:
		PlayerStats.use_stamina(talent.stamina_cost)

	# Store casting info for completion handling
	casting_slot_index = slot_index
	casting_talent = talent

	# Connect to cast_completed signal (one-shot)
	if not player.cast_completed.is_connected(_on_self_buff_cast_completed):
		player.cast_completed.connect(_on_self_buff_cast_completed)
	if not player.cast_interrupted.is_connected(_on_self_buff_cast_interrupted):
		player.cast_interrupted.connect(_on_self_buff_cast_interrupted)

	print("[CAST] Self-buff casting started via PlayerController: cast_time=%s" % cast_time)


func _on_self_buff_cast_completed(skill_id: String) -> void:
	## Called when PlayerController completes a cast
	if not casting_talent or casting_talent.id != skill_id:
		return

	# Only handle self-buff completions here
	if casting_talent.effect_type != TalentData.EffectType.SELF_BUFF:
		return

	# Apply the buff
	_apply_self_buff(casting_talent)

	# Start cooldown
	if casting_talent.cooldown > 0:
		if casting_slot_index == -1:
			attack_button.start_cooldown(casting_talent.cooldown)
		elif casting_slot_index >= 0 and casting_slot_index < ability_slots.size():
			ability_slots[casting_slot_index].start_cooldown(casting_talent.cooldown)

	# Clean up
	_end_casting()


func _on_self_buff_cast_interrupted(skill_id: String, _reason: String) -> void:
	## Called when PlayerController's cast is interrupted
	if not casting_talent or casting_talent.id != skill_id:
		return

	# Only handle self-buff interruptions here
	if casting_talent.effect_type != TalentData.EffectType.SELF_BUFF:
		return

	# Clean up without applying buff
	_end_casting()


func _update_self_buff_casting() -> void:
	## Self-buff casting is now handled by PlayerController signals
	## This method is kept for compatibility but does nothing
	pass


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

	# Notify quest system for USE_ABILITY objectives
	if QuestManager:
		QuestManager.on_ability_used(talent.id)

	# Start cooldown
	if talent.cooldown > 0:
		if slot_index == -1:
			attack_button.start_cooldown(talent.cooldown)
		elif slot_index >= 0 and slot_index < ability_slots.size():
			ability_slots[slot_index].start_cooldown(talent.cooldown)


func _apply_self_buff(talent: TalentData) -> void:
	## Apply the self-buff effect to the player
	print("[CAST] Applying self-buff: %s" % talent.talent_name)

	# Check if this is Father's Last Lesson (ultimate ability)
	if talent.id == "tal_noble_fathers_lesson":
		var duration := talent.duration if talent.duration > 0 else 6.0
		TalentProcSystem.activate_ultimate(duration)
		Debug.log("Combat", "Father's Last Lesson ultimate activated for %.1fs" % duration)
		return

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

	# Fire on_hit procs BEFORE damage loop so conditions (e.g., target_full_hp)
	# are checked while enemies are still at full HP and the bonus is available
	# for consume_next_attack_bonus() inside the loop.
	var first_target: Node2D = null
	for enemy in enemies:
		if skill_arc < 360.0:
			var enemy_pos: Vector2 = enemy.global_position
			var to_enemy: Vector2 = (enemy_pos - player.global_position).normalized()
			var angle: float = rad_to_deg(facing_vector.angle_to(to_enemy))
			if abs(angle) > skill_arc / 2.0:
				continue
		if enemy.has_method("take_damage"):
			first_target = enemy
			break

	if first_target:
		TalentProcSystem.on_player_hit_enemy(first_target, damage_result, talent)

	# Track first-hit data for debug breakdown
	var breakdown_target_name: String = ""
	var breakdown_proc_bonus: float = 0.0
	var breakdown_final_damage: float = 0.0
	var breakdown_hit := false

	for enemy in enemies:
		# Check if enemy is within hit arc (skip if arc is 360 = all around)
		if skill_arc < 360.0:
			var enemy_pos: Vector2 = enemy.global_position
			var to_enemy: Vector2 = (enemy_pos - player.global_position).normalized()
			var angle: float = rad_to_deg(facing_vector.angle_to(to_enemy))
			if abs(angle) > skill_arc / 2.0:
				continue  # Enemy is outside hit arc

		if enemy.has_method("take_damage"):
			# Apply proc damage bonus (from talents like Closing the Gap, First Blood)
			var final_damage: float = damage_result.final_damage
			var proc_bonus := TalentProcSystem.consume_next_attack_bonus()
			if proc_bonus > 0:
				final_damage *= (1.0 + proc_bonus / 100.0)

			# Apply armor/resistance reduction on enemy
			if enemy.has_method("_calculate_damage_after_armor"):
				final_damage = enemy._calculate_damage_after_armor(final_damage)

			# Capture first hit for debug breakdown
			if not breakdown_hit:
				breakdown_hit = true
				breakdown_target_name = enemy.enemy_name if "enemy_name" in enemy else enemy.name
				breakdown_proc_bonus = proc_bonus
				breakdown_final_damage = final_damage

			enemy.take_damage(final_damage, player)

			# Apply contact status effect to enemy (stagger, slow, bleed, etc.)
			if not talent.contact_status_effect.is_empty() and "status_effects" in enemy and enemy.status_effects:
				enemy.status_effects.apply_status_effect(talent.contact_status_effect)

			# Stagger: interrupt enemy ability + small knockback
			if talent.contact_status_effect == "status_stagger":
				if enemy.has_method("interrupt_ability"):
					enemy.interrupt_ability()
				if enemy.has_method("apply_knockback") and player:
					enemy.apply_knockback(player.global_position, 80.0, 0.15)

			# Notify proc system of hit for non-first targets
			if enemy != first_target:
				TalentProcSystem.on_player_hit_enemy(enemy, damage_result, talent)

			# Spawn hit effect on enemy
			_spawn_hit_effect(enemy.global_position, _get_damage_type_string(talent.damage_type))

			# Log crit hits
			if damage_result.is_critical:
				Debug.log("Combat", "CRITICAL %s on %s!" % [talent.talent_name, enemy.enemy_name], "%.0f damage" % final_damage)

	# Report damage breakdown for debug overlay
	if breakdown_hit:
		TalentProcSystem.report_damage_breakdown({
			"skill_name": talent.talent_name,
			"target_name": breakdown_target_name,
			"base_damage": damage_result.final_damage,
			"proc_bonus_pct": breakdown_proc_bonus,
			"final_damage": breakdown_final_damage,
			"is_critical": damage_result.get("is_critical", false),
		})


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
	visual.damage_type = _get_damage_type_string(talent.damage_type)

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


func _get_damage_type_string(damage_type: CombatTypes.DamageType) -> String:
	## Convert damage type enum to visual string (uses CombatTypes)
	return CombatTypes.get_visual_type(damage_type)


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
		# Connect parry success signal for counter-attack
		if TalentProcSystem and not TalentProcSystem.parry_succeeded.is_connected(_on_parry_succeeded):
			TalentProcSystem.parry_succeeded.connect(_on_parry_succeeded)
		# Connect stance deactivated signal for auto-deactivation sync
		if not player.stance_deactivated.is_connected(_on_stance_deactivated):
			player.stance_deactivated.connect(_on_stance_deactivated)
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

func set_user_scale(scale_value: float) -> void:
	## Stub: Adjust overall HUD scale
	config.user_scale = clampf(scale_value, config.min_scale, config.max_scale)
	# TODO: Apply scale to all buttons
	Debug.log("Combat", "User scale set (stub)", {"scale": scale_value})


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


#===============================================================================
# TOGGLE STANCE
#===============================================================================

func _deactivate_active_stance() -> void:
	## Deactivate the currently active toggle stance
	if _active_stance_slot < 0:
		return
	if player:
		player.deactivate_stance()
	_active_stance_slot = -1
	_active_stance_talent_id = ""


func _on_stance_deactivated(_talent_id: String) -> void:
	## Called when stance auto-deactivates (e.g., ran out of stamina)
	_active_stance_slot = -1
	_active_stance_talent_id = ""


#===============================================================================
# COLD PARRY COUNTER-ATTACK
#===============================================================================

func _on_parry_succeeded(attacker: Node2D) -> void:
	## Called when TalentProcSystem signals a successful parry.
	## Cancel the parry stance visual and execute a counter-attack.
	if not player:
		return

	# Cancel the parry stance visual sequence
	if player.ability_visual_player and player.ability_visual_player.is_playing:
		player.ability_visual_player.cancel()

	# Get the Cold Parry talent for counter-attack damage
	var parry_talent := TalentProcSystem.get_parry_talent()
	if not parry_talent:
		return

	# Face the attacker
	if attacker and is_instance_valid(attacker):
		var dir := (attacker.global_position - player.global_position).normalized()
		_snap_player_facing(dir)

	# Calculate counter-attack damage (uses Cold Parry's weapon_damage_percent)
	var invested := TalentManager.get_invested_points(parry_talent.id)
	var damage_result := DamageCalculator.calculate_final_damage(parry_talent, invested)

	# Play counter-attack visual (quick melee strike)
	_pending_talent = parry_talent
	_pending_slot_index = -1
	_connect_visual_signals()
	var counter_overrides := {
		"lunge_distance": 15.0,
		"lunge_duration": 0.06,
	}
	player.play_ability_visual("melee_single", counter_overrides, attacker.global_position if attacker and is_instance_valid(attacker) else player.global_position)

	# Show parry text feedback
	if player and CombatText:
		CombatText.show_custom(player, "PARRY!", Color(1.0, 0.85, 0.2), 16)

	Debug.log("Combat", "Parry counter-attack! %s damage" % damage_result.final_damage)


func _snap_player_facing(direction: Vector2) -> void:
	## Snap the player's facing toward a direction vector
	if not player:
		return
	# Determine cardinal direction
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			player.current_facing = PlayerController.Facing.RIGHT
		else:
			player.current_facing = PlayerController.Facing.LEFT
	else:
		if direction.y > 0:
			player.current_facing = PlayerController.Facing.DOWN
		else:
			player.current_facing = PlayerController.Facing.UP
	player.facing_changed.emit(player.current_facing)
