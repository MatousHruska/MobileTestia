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

	Debug.info("Combat", "CombatHUD initialized", {"abilities": config.ability_count})


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

	# Calculate attack button position (bottom-right offset)
	var attack_pos := Vector2(
		screen_size.x + config.attack_offset.x,
		screen_size.y + config.attack_offset.y
	)
	attack_button.position = attack_pos - Vector2(config.attack_radius, config.attack_radius)

	# Calculate attack button center for arc positioning
	var attack_center := attack_pos

	# Position ability slots in arc around attack button
	var ability_positions := config.get_ability_positions(attack_center)
	for i in ability_slots.size():
		if i < ability_positions.size():
			var pos := ability_positions[i]
			ability_slots[i].position = pos - Vector2(config.ability_radius, config.ability_radius)

	# Position dodge button
	var dodge_pos := Vector2(
		screen_size.x + config.dodge_offset.x,
		screen_size.y + config.dodge_offset.y
	)
	dodge_button.position = dodge_pos - Vector2(config.dodge_radius, config.dodge_radius)

	# Position quick slot button
	var quick_slot_pos := Vector2(
		screen_size.x + config.quick_slot_offset.x,
		screen_size.y + config.quick_slot_offset.y
	)
	quick_slot_button.position = quick_slot_pos - Vector2(config.quick_slot_radius, config.quick_slot_radius)

	# Position interact button
	var interact_pos := Vector2(
		screen_size.x + config.interact_offset.x,
		screen_size.y + config.interact_offset.y
	)
	interact_button.position = interact_pos


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Re-layout on screen resize
		call_deferred("_layout_buttons")


## Signal handlers

func _on_attack_activated(_slot_index: int, _ability_id: String) -> void:
	Debug.log("Combat", "Attack activated")
	attack_pressed.emit()

	# TODO: Connect to player attack system
	# For now, trigger the debug kill
	if NPCManager:
		NPCManager.debug_kill_all_enemies()


func _on_ability_activated(slot_index: int, ability_id: String) -> void:
	Debug.log("Combat", "Ability activated", {"slot": slot_index, "ability": ability_id})
	ability_pressed.emit(slot_index, ability_id)

	# TODO: Connect to player ability system
	# For now, just start a test cooldown
	if slot_index >= 0 and slot_index < ability_slots.size():
		var slot := ability_slots[slot_index]
		var cooldown := slot.ability_data.get("cooldown", 5.0) as float
		slot.start_cooldown(cooldown)


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
