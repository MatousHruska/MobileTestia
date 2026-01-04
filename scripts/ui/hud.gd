extends CanvasLayer
class_name HUD
## HUD - Main game HUD controller
## Manages player stats display and mobile controls

## Signals
signal menu_button_pressed

## References (set in scene or found automatically)
@onready var joystick: VirtualJoystick = $Controls/JoystickArea/VirtualJoystick
@onready var joystick_area: Control = $Controls/JoystickArea
@onready var combat_hud: CombatHUD = $Controls/CombatHUD
@onready var player_frame: Control = $PlayerFrame
@onready var menu_button: Button = $MenuButton/Button

## Base sizes (designed for 720p)
const BASE_SCREEN_HEIGHT := 720.0
const BASE_PLAYER_FRAME_SIZE := Vector2(200, 130)
const BASE_JOYSTICK_AREA_SIZE := Vector2(200, 184)
const BASE_JOYSTICK_RADIUS := 80.0
const BASE_KNOB_RADIUS := 40.0
const MIN_SCALE := 0.7
const MAX_SCALE := 1.4

## Resource bars (created dynamically)
var health_bar: ProgressBar
var mana_bar: ProgressBar
var stamina_bar: ProgressBar
var health_label: Label
var mana_label: Label
var stamina_label: Label
var level_label: Label

## Status effect display
var status_effect_display: StatusEffectDisplay

## Player reference
var player: PlayerController = null

## Nearby interactable NPC or object
var nearby_npc: Node = null  ## Can be NPC or InteractableBase
var _last_nearby_npc: Node = null
var _connected_pickup: Node = null  ## Track connected LootPickup for signal cleanup


func _ready() -> void:
	Debug.info("UI", "HUD ready")
	_setup_resource_bars()
	_connect_to_game_manager()
	_connect_to_player_stats()
	_setup_controls()
	# Apply initial scaling
	call_deferred("_apply_hud_scaling")
	# Connect to viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_apply_hud_scaling()


func _apply_hud_scaling() -> void:
	## Scale HUD elements based on screen size
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_factor := viewport_size.y / BASE_SCREEN_HEIGHT
	scale_factor = clampf(scale_factor, MIN_SCALE, MAX_SCALE)

	# Scale PlayerFrame
	if player_frame:
		var scaled_size := BASE_PLAYER_FRAME_SIZE * scale_factor
		player_frame.custom_minimum_size = scaled_size
		player_frame.size = scaled_size
		# The contents use anchors/margins so they'll adapt

	# Scale JoystickArea
	if joystick_area:
		var scaled_joystick_size := BASE_JOYSTICK_AREA_SIZE * scale_factor
		# Keep anchored to bottom-left, adjust offsets
		joystick_area.offset_left = 16 * scale_factor
		joystick_area.offset_top = -scaled_joystick_size.y - (16 * scale_factor)
		joystick_area.offset_right = 16 * scale_factor + scaled_joystick_size.x
		joystick_area.offset_bottom = -16 * scale_factor

	# Scale VirtualJoystick radii and update center
	if joystick:
		joystick.joystick_radius = BASE_JOYSTICK_RADIUS * scale_factor
		joystick.knob_radius = BASE_KNOB_RADIUS * scale_factor
		# Update center based on new control size (after layout settles)
		await get_tree().process_frame
		if joystick:
			joystick.joystick_center = joystick.size / 2.0
			if not joystick.is_active:
				joystick.knob_position = joystick.joystick_center
			joystick.queue_redraw()


func _process(_delta: float) -> void:
	# Only process input when game is in PLAYING state
	if player and joystick and Game.is_playing:
		player.set_input_direction(joystick.get_direction())

	# Check for nearby interactable NPCs
	_update_interact_button()


func _setup_resource_bars() -> void:
	if not player_frame:
		return

	# Clear existing children
	for child in player_frame.get_children():
		child.queue_free()

	# Background panel
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = UITheme.MARGIN_STANDARD
	bg.offset_top = UITheme.MARGIN_STANDARD
	bg.offset_right = -UITheme.MARGIN_STANDARD
	bg.offset_bottom = -UITheme.MARGIN_STANDARD
	bg.color = UITheme.COLOR_PANEL_BG
	player_frame.add_child(bg)

	# Bars container
	var bars_container := VBoxContainer.new()
	bars_container.name = "BarsContainer"
	bars_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_container.offset_left = UITheme.MARGIN_STANDARD + 4
	bars_container.offset_top = UITheme.MARGIN_STANDARD + 4
	bars_container.offset_right = -(UITheme.MARGIN_STANDARD + 4)
	bars_container.offset_bottom = -(UITheme.MARGIN_STANDARD + 4)
	bars_container.add_theme_constant_override("separation", UITheme.SEPARATION_SMALL)
	player_frame.add_child(bars_container)

	# Health bar
	health_bar = _create_resource_bar("Health", Color(0.8, 0.2, 0.2), Color(0.4, 0.1, 0.1))
	health_label = health_bar.get_node("Label")
	bars_container.add_child(health_bar)

	# Mana bar
	mana_bar = _create_resource_bar("Mana", Color(0.2, 0.4, 0.9), Color(0.1, 0.2, 0.45))
	mana_label = mana_bar.get_node("Label")
	bars_container.add_child(mana_bar)

	# Stamina bar
	stamina_bar = _create_resource_bar("Stamina", Color(0.2, 0.7, 0.3), Color(0.1, 0.35, 0.15))
	stamina_label = stamina_bar.get_node("Label")
	bars_container.add_child(stamina_bar)

	# Level label
	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Lv. 1"
	level_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	level_label.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	bars_container.add_child(level_label)

	# Status effect display (DoTs, buffs, debuffs)
	status_effect_display = StatusEffectDisplay.new()
	status_effect_display.name = "StatusEffectDisplay"
	status_effect_display.custom_minimum_size = Vector2(0, 32)
	bars_container.add_child(status_effect_display)


func _create_resource_bar(bar_name: String, fill_color: Color, bg_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = bar_name + "Bar"
	bar.custom_minimum_size = Vector2(0, 18)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false

	# Style the bar
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	bar.add_theme_stylebox_override("background", bg_style)

	# Add value label on top of bar
	var label := Label.new()
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", UITheme.COLOR_SELECTED)
	label.add_theme_color_override("font_shadow_color", UITheme.COLOR_PANEL_DARK_BG)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.text = "100 / 100"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)

	return bar


func _connect_to_player_stats() -> void:
	PlayerStats.resource_changed.connect(_on_resource_changed)
	PlayerStats.level_changed.connect(_on_level_changed)
	PlayerStats.stats_changed.connect(_on_stats_changed)
	# Initialize with current values
	_refresh_all_resources()


func _refresh_all_resources() -> void:
	update_health(PlayerStats.current_life, PlayerStats.max_life)
	update_mana(PlayerStats.current_mana, PlayerStats.max_mana)
	update_stamina(PlayerStats.current_stamina, PlayerStats.max_stamina)
	_update_level_label()


func _on_resource_changed(resource: String, current: float, maximum: float) -> void:
	match resource:
		"life":
			update_health(current, maximum)
		"mana":
			update_mana(current, maximum)
		"stamina":
			update_stamina(current, maximum)


func _on_level_changed(_old_level: int, _new_level: int) -> void:
	_update_level_label()


func _on_stats_changed() -> void:
	# Max values might have changed, refresh all
	_refresh_all_resources()


func _update_level_label() -> void:
	if level_label:
		level_label.text = "Lv. %d" % PlayerStats.level


func _connect_to_game_manager() -> void:
	if Game:
		Game.player_spawned.connect(_on_player_spawned)
		if Game.is_player_valid():
			_on_player_spawned(Game.player)


func _on_player_spawned(new_player: Node2D) -> void:
	if new_player is PlayerController:
		player = new_player as PlayerController
		Debug.info("UI", "HUD connected to player")


func _setup_controls() -> void:
	if combat_hud:
		combat_hud.interact_button.pressed.connect(_on_interact_pressed)

	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)


func _on_interact_pressed() -> void:
	if nearby_npc == null:
		return

	# Handle chest interaction via UIManager
	if nearby_npc is ChestBase:
		var chest: ChestBase = nearby_npc as ChestBase
		chest.interact_with_ui_manager()
	elif nearby_npc.has_method("interact"):
		nearby_npc.interact()


func _on_menu_pressed() -> void:
	Debug.log("UI", "Menu button pressed")
	menu_button_pressed.emit()

	# Open character menu via UIManager
	UIManager.toggle_character_menu()


func update_health(current: float, maximum: float) -> void:
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current
	if health_label:
		health_label.text = "%d / %d" % [int(current), int(maximum)]


func update_mana(current: float, maximum: float) -> void:
	if mana_bar:
		mana_bar.max_value = maximum
		mana_bar.value = current
	if mana_label:
		mana_label.text = "%d / %d" % [int(current), int(maximum)]


func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current
	if stamina_label:
		stamina_label.text = "%d / %d" % [int(current), int(maximum)]


## Interaction handling
func _update_interact_button() -> void:
	if not combat_hud or not Game.is_playing:
		return

	var interact_button := combat_hud.interact_button

	# Find nearby interactable object (NPC or chest)
	nearby_npc = null

	# Check friendly NPCs first
	if NPCManager:
		for npc in NPCManager.all_friendlies:
			if is_instance_valid(npc) and npc.has_method("can_interact") and npc.can_interact():
				nearby_npc = npc
				break

	# If no NPC found, check for chests and other interactables
	if nearby_npc == null:
		var chests := get_tree().get_nodes_in_group("loot_chests")
		for chest in chests:
			if is_instance_valid(chest) and chest.has_method("can_interact") and chest.can_interact():
				nearby_npc = chest
				break

	# Also check quest chests
	if nearby_npc == null:
		var quest_chests := get_tree().get_nodes_in_group("quest_chests")
		for chest in quest_chests:
			if is_instance_valid(chest) and chest.has_method("can_interact") and chest.can_interact():
				nearby_npc = chest
				break

	# Check for loot pickups on ground
	if nearby_npc == null:
		var pickups := get_tree().get_nodes_in_group("loot_pickups")
		for pickup in pickups:
			if is_instance_valid(pickup) and pickup.has_method("can_interact") and pickup.can_interact():
				nearby_npc = pickup
				break

	# Check for doors
	if nearby_npc == null:
		var doors := get_tree().get_nodes_in_group("doors")
		for door in doors:
			if is_instance_valid(door) and door.has_method("can_interact") and door.can_interact():
				nearby_npc = door
				break

	# Check for levers
	if nearby_npc == null:
		var levers := get_tree().get_nodes_in_group("levers")
		for lever in levers:
			if is_instance_valid(lever) and lever.has_method("can_interact") and lever.can_interact():
				nearby_npc = lever
				break

	# Track changes
	if nearby_npc != _last_nearby_npc:
		# Disconnect from old pickup if any
		if _connected_pickup and is_instance_valid(_connected_pickup):
			if _connected_pickup.has_signal("pickup_failed"):
				_connected_pickup.pickup_failed.disconnect(_on_pickup_failed)
			_connected_pickup = null

		_last_nearby_npc = nearby_npc

		# Connect to new pickup if it's a LootPickup
		if nearby_npc and nearby_npc is LootPickup:
			_connected_pickup = nearby_npc
			nearby_npc.pickup_failed.connect(_on_pickup_failed)

		# Update button text based on what's nearby
		if nearby_npc and nearby_npc.has_method("get_interaction_prompt"):
			interact_button.text = nearby_npc.get_interaction_prompt()
		else:
			interact_button.text = "Interact"

	# Show/hide button based on nearby interactable
	if nearby_npc:
		if not interact_button.visible:
			interact_button.visible = true
	else:
		if interact_button.visible:
			interact_button.visible = false


## Loot pickup feedback
func _on_pickup_failed() -> void:
	Debug.log("UI", "Inventory full - flashing interact button")
	_flash_interact_button_red()


func _flash_interact_button_red() -> void:
	if not combat_hud or not combat_hud.interact_button:
		return

	var btn := combat_hud.interact_button

	# Store original modulate
	var original_color: Color = btn.modulate

	# Flash red a few times
	var tween := create_tween()
	for i in 3:
		tween.tween_property(btn, "modulate", Color(1.0, 0.3, 0.3), 0.1)
		tween.tween_property(btn, "modulate", original_color, 0.1)


## Debug
func print_state() -> void:
	Debug.snapshot("UI", "HUD State", {
		"player_connected": player != null,
		"joystick_active": joystick.is_pressed() if joystick else false,
		"joystick_direction": joystick.get_direction() if joystick else Vector2.ZERO,
	})
