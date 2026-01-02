extends Control
class_name CombatHUD
## CombatHUD - Layout manager for combat action buttons
## Positions attack, abilities, dodge, and quick slot based on config

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

## Constants
const DEFAULT_CONFIG_PATH := "res://resources/combat_hud_config.tres"


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
	for i in range(ability_slots.size()):
		# TalentManager slot 1-5 maps to ability slots 0-4 (main slot 0 is special)
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
	var weapon_cat := Inventory.get_equipped_weapon_category()
	ability_slots[slot_index].update_weapon_validity(weapon_cat)

	Debug.log("Combat", "Bound talent to HUD slot", {"slot": slot_index, "talent": talent.talent_name})


func _on_talent_skill_bound(slot_index: int, talent_id: String) -> void:
	## Handle skill bound event from TalentManager
	# TalentManager uses slot 0 as main, 1-5 as secondary
	# CombatHUD ability slots are 0-based
	var hud_slot := slot_index - 1  # Convert to HUD slot index
	if hud_slot < 0 or hud_slot >= ability_slots.size():
		return

	var talent := TalentManager.get_talent(talent_id)
	if talent:
		_bind_talent_to_slot(hud_slot, talent)


func _on_talent_skill_unbound(slot_index: int) -> void:
	## Handle skill unbound event from TalentManager
	var hud_slot := slot_index - 1
	if hud_slot >= 0 and hud_slot < ability_slots.size():
		clear_ability_slot(hud_slot)


func _on_equipment_changed(slot: ItemData.EquipSlot) -> void:
	## Handle equipment change - update weapon validity for all ability slots
	if slot == ItemData.EquipSlot.MAIN_HAND:
		_update_all_weapon_validity()


func _update_all_weapon_validity() -> void:
	## Update weapon validity state for all ability slots
	var weapon_cat := Inventory.get_equipped_weapon_category()
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

	# Calculate attack button position using percentage-based offset
	var attack_pos := config.get_position_from_pct(config.attack_offset_pct, screen_size)
	attack_button.position = attack_pos - Vector2(config.attack_radius, config.attack_radius)

	# Calculate attack button center for arc positioning
	var attack_center := attack_pos

	# Position ability slots in arc around attack button
	var ability_positions := config.get_ability_positions(attack_center, screen_size.y)
	for i in ability_slots.size():
		if i < ability_positions.size():
			var pos := ability_positions[i]
			ability_slots[i].position = pos - Vector2(config.ability_radius, config.ability_radius)

	# Position dodge button
	var dodge_pos := config.get_position_from_pct(config.dodge_offset_pct, screen_size)
	dodge_button.position = dodge_pos - Vector2(config.dodge_radius, config.dodge_radius)

	# Position quick slot button
	var quick_slot_pos := config.get_position_from_pct(config.quick_slot_offset_pct, screen_size)
	quick_slot_button.position = quick_slot_pos - Vector2(config.quick_slot_radius, config.quick_slot_radius)

	# Position interact button
	var interact_pos := config.get_position_from_pct(config.interact_offset_pct, screen_size)
	interact_button.position = interact_pos


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Re-layout on screen resize
		call_deferred("_layout_buttons")


## Signal handlers

func _on_attack_activated(_slot_index: int, _ability_id: String) -> void:
	Debug.log("Combat", "Attack activated")
	attack_pressed.emit()

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
		var weapon_cat := Inventory.get_equipped_weapon_category()
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
	if slot_index >= 0 and slot_index < ability_slots.size():
		var slot := ability_slots[slot_index]
		if talent.cooldown > 0:
			slot.start_cooldown(talent.cooldown)

	ability_pressed.emit(slot_index, ability_id)
	Debug.log("Combat", "Skill executed: %s" % talent.talent_name, {
		"damage": int(damage_result.final_damage),
		"crit": damage_result.is_critical,
		"type": DamageCalculator.get_damage_type_name(damage_result.damage_type),
		"range": talent.hit_range,
		"arc": talent.hit_arc,
	})


func _apply_skill_mechanics(talent: TalentData) -> void:
	## Apply lunge, animation, and recovery to player
	if not player:
		return

	# Trigger attack animation for melee skills
	if talent.skill_category.to_lower() == "melee":
		player.request_attack()

	# Apply lunge if specified
	if talent.lunge_force > 0:
		player.apply_skill_lunge(talent.lunge_force)

	# Apply recovery lockout if specified
	if talent.recovery_time > 0:
		player.apply_recovery_lockout(talent.recovery_time)


func _apply_skill_damage(talent: TalentData, damage_result: Dictionary) -> void:
	## Apply skill damage to enemies in range and arc
	if not player:
		return

	# Use hit_range from talent
	var skill_range := talent.hit_range
	var skill_arc := talent.hit_arc

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

	# Configure shape based on arc
	if talent.hit_arc >= 360.0:
		# Full circle
		visual.draw_type = "circle"
		visual.radius = talent.hit_range
	else:
		# Cone shape
		visual.draw_type = "polygon"
		visual.points = _generate_cone_points(talent.hit_range, talent.hit_arc)

	# Set damage type for color (convert from int id to string)
	visual.damage_type = _get_damage_type_string(talent.damage_type_id)

	# Position at player, rotated to facing direction
	visual.global_position = player.global_position

	# Rotate to face direction (only for cones)
	if talent.hit_arc < 360.0:
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
