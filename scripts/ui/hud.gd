extends CanvasLayer
class_name HUD
## HUD - Main game HUD controller
## Manages player stats display and mobile controls

## Preload config class (needed until Godot generates .uid files)
const PlayerFrameConfigClass = preload("res://scripts/ui/player_frame_config.gd")

## Signals
signal menu_button_pressed

## Configuration
@export var player_frame_config: Resource  # PlayerFrameConfig

## References (set in scene or found automatically)
@onready var joystick: VirtualJoystick = $Controls/JoystickArea/VirtualJoystick
@onready var joystick_area: Control = $Controls/JoystickArea
@onready var combat_hud: CombatHUD = $Controls/CombatHUD
@onready var player_frame: Control = $PlayerFrame
@onready var menu_button: Button = $MenuButton/Button

## Joystick base sizes (percentage-based) - 60% larger than original
const JOYSTICK_AREA_WIDTH_PCT := 0.24   ## Was 0.15
const JOYSTICK_AREA_HEIGHT_PCT := 0.40  ## Was 0.25
const JOYSTICK_MARGIN_PCT := 0.02
const JOYSTICK_RADIUS_PCT := 0.064  ## Percentage of screen height (was 0.04)
const KNOB_RADIUS_PCT := 0.032  ## Percentage of screen height (was 0.02)

## Default config path
const DEFAULT_CONFIG_PATH := "res://resources/player_frame_config.tres"

## Resource bars (created dynamically)
var health_bar: ProgressBar
var mana_bar: ProgressBar
var stamina_bar: ProgressBar
var health_label: Label
var mana_label: Label
var stamina_label: Label

## Status effect display
var status_effect_display: StatusEffectDisplay

## Cast bar
var cast_bar: CastBar

## Player reference
var player: PlayerController = null

## Nearby interactable NPC or object
var nearby_npc: Node = null  ## Can be NPC or InteractableBase
var _last_nearby_npc: Node = null
var _connected_pickup: Node = null  ## Track connected LootPickup for signal cleanup


func _ready() -> void:
	Debug.info("UI", "HUD ready")
	_load_or_create_config()
	_setup_resource_bars()
	_setup_cast_bar()
	_connect_to_game_manager()
	_connect_to_player_stats()
	_setup_controls()
	# Apply initial layout
	call_deferred("_apply_hud_layout")
	# Connect to viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)


func _load_or_create_config() -> void:
	if player_frame_config == null:
		if ResourceLoader.exists(DEFAULT_CONFIG_PATH):
			player_frame_config = load(DEFAULT_CONFIG_PATH)
		else:
			player_frame_config = PlayerFrameConfigClass.new()
			Debug.info("UI", "Using default PlayerFrameConfig")


func _on_viewport_resized() -> void:
	_apply_hud_layout()
	_position_cast_bar()


func _apply_hud_layout() -> void:
	## Layout HUD elements using percentage-based positioning
	var screen_size := get_viewport().get_visible_rect().size

	#===========================================================================
	# PLAYER FRAME LAYOUT
	# Position and size from config percentages
	#===========================================================================
	if player_frame and player_frame_config:
		var frame_pos: Vector2 = player_frame_config.get_position(screen_size)
		var frame_size: Vector2 = player_frame_config.get_size(screen_size)

		player_frame.position = frame_pos
		player_frame.custom_minimum_size = frame_size
		player_frame.size = frame_size

		# Update internal layout
		_update_player_frame_layout(frame_size)

	#===========================================================================
	# JOYSTICK AREA LAYOUT
	# Percentage-based positioning from bottom-left
	#===========================================================================
	if joystick_area:
		var margin := JOYSTICK_MARGIN_PCT * screen_size.x
		var area_width := JOYSTICK_AREA_WIDTH_PCT * screen_size.x
		var area_height := JOYSTICK_AREA_HEIGHT_PCT * screen_size.y

		# Keep anchored to bottom-left, adjust offsets
		joystick_area.offset_left = margin
		joystick_area.offset_top = -area_height - margin
		joystick_area.offset_right = margin + area_width
		joystick_area.offset_bottom = -margin

	#===========================================================================
	# VIRTUAL JOYSTICK
	# Scale radii based on screen height
	#===========================================================================
	if joystick:
		joystick.joystick_radius = JOYSTICK_RADIUS_PCT * screen_size.y
		joystick.knob_radius = KNOB_RADIUS_PCT * screen_size.y
		# Update center based on new control size (after layout settles)
		await get_tree().process_frame
		if joystick:
			joystick.joystick_center = joystick.size / 2.0
			if not joystick.is_active:
				joystick.knob_position = joystick.joystick_center
			joystick.queue_redraw()


func _update_player_frame_layout(frame_size: Vector2) -> void:
	## Update internal PlayerFrame layout based on new size
	if not player_frame_config:
		return

	var padding: float = player_frame_config.get_padding(frame_size)
	var bar_height: float = player_frame_config.get_bar_height(frame_size.y)
	var bar_gap: float = player_frame_config.get_bar_gap(frame_size.y)
	var bar_corner_radius: int = player_frame_config.get_bar_corner_radius(bar_height)
	var bar_font_size: int = player_frame_config.get_bar_font_size(bar_height)
	var status_icon_size: float = player_frame_config.get_status_icon_size(frame_size.y)

	# Update background
	var bg := player_frame.get_node_or_null("Background")
	if bg is ColorRect:
		bg.offset_left = padding
		bg.offset_top = padding
		bg.offset_right = -padding
		bg.offset_bottom = -padding

	# Update bars container
	var bars_container := player_frame.get_node_or_null("BarsContainer")
	if bars_container is VBoxContainer:
		bars_container.offset_left = padding * 1.5
		bars_container.offset_top = padding * 1.5
		bars_container.offset_right = -padding * 1.5
		bars_container.offset_bottom = -padding * 1.5
		bars_container.add_theme_constant_override("separation", int(bar_gap))

	# Update individual bars
	_update_bar_style(health_bar, bar_height, bar_corner_radius, bar_font_size)
	_update_bar_style(mana_bar, bar_height, bar_corner_radius, bar_font_size)
	_update_bar_style(stamina_bar, bar_height, bar_corner_radius, bar_font_size)

	# Position status effect display below the frame
	if status_effect_display:
		var screen_size: Vector2 = get_viewport().get_visible_rect().size
		var frame_pos: Vector2 = player_frame_config.get_position(screen_size)
		var gap_below: float = player_frame_config.get_bar_gap(frame_size.y)
		status_effect_display.position = Vector2(frame_pos.x, frame_pos.y + frame_size.y + gap_below)
		status_effect_display.custom_minimum_size = Vector2(frame_size.x, status_icon_size)


func _update_bar_style(bar: ProgressBar, height: float, corner_radius: int, font_size: int) -> void:
	## Update a single bar's style based on new dimensions
	if not bar:
		return

	bar.custom_minimum_size = Vector2(0, height)

	# Update fill style corner radius
	var fill_style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		fill_style.set_corner_radius_all(corner_radius)

	# Update background style corner radius
	var bg_style := bar.get_theme_stylebox("background") as StyleBoxFlat
	if bg_style:
		bg_style.set_corner_radius_all(corner_radius)

	# Update label font size
	var label := bar.get_node_or_null("Label") as Label
	if label:
		label.add_theme_font_size_override("font_size", font_size)


func _process(_delta: float) -> void:
	# Only process input when game is in PLAYING state
	if player and joystick and Game.is_playing:
		player.set_input_direction(joystick.get_direction())

	# Check for nearby interactable NPCs
	_update_interact_button()


func _setup_resource_bars() -> void:
	if not player_frame or not player_frame_config:
		return

	# Clear existing children
	for child in player_frame.get_children():
		child.queue_free()

	# Background panel
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = player_frame_config.background_color
	player_frame.add_child(bg)

	# Bars container
	var bars_container := VBoxContainer.new()
	bars_container.name = "BarsContainer"
	bars_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	player_frame.add_child(bars_container)

	# Health bar
	health_bar = _create_resource_bar("Health",
		player_frame_config.health_fill_color,
		player_frame_config.health_bg_color)
	health_label = health_bar.get_node("Label")
	bars_container.add_child(health_bar)

	# Mana bar
	mana_bar = _create_resource_bar("Mana",
		player_frame_config.mana_fill_color,
		player_frame_config.mana_bg_color)
	mana_label = mana_bar.get_node("Label")
	bars_container.add_child(mana_bar)

	# Stamina bar
	stamina_bar = _create_resource_bar("Stamina",
		player_frame_config.stamina_fill_color,
		player_frame_config.stamina_bg_color)
	stamina_label = stamina_bar.get_node("Label")
	bars_container.add_child(stamina_bar)

	# Status effect display (DoTs, buffs, debuffs) - positioned below frame, left-aligned
	status_effect_display = StatusEffectDisplay.new()
	status_effect_display.name = "StatusEffectDisplay"
	status_effect_display.alignment = BoxContainer.ALIGNMENT_BEGIN  # Left-align icons
	add_child(status_effect_display)  # Add to HUD, not player_frame


func _setup_cast_bar() -> void:
	## Create and position the cast bar UI
	cast_bar = CastBar.new()
	cast_bar.name = "CastBar"

	# Position will be set in _position_cast_bar after viewport is ready
	add_child(cast_bar)
	call_deferred("_position_cast_bar")
	Debug.log("UI", "CastBar created")


func _position_cast_bar() -> void:
	## Position cast bar above character using percentage-based positioning
	if not cast_bar:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var bar_width := UITheme.CAST_BAR_WIDTH

	# Use percentage-based positioning (centered horizontally, Y from theme)
	var y_percent := UITheme.CAST_BAR_Y_PERCENT
	cast_bar.position = Vector2(
		(viewport_size.x - bar_width) / 2.0,
		viewport_size.y * y_percent
	)


func _create_resource_bar(bar_name: String, fill_color: Color, bg_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = bar_name + "Bar"
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false

	# Style the bar (corner radius will be set in _update_bar_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bar.add_theme_stylebox_override("background", bg_style)

	# Add value label on top of bar (font size will be set in _update_bar_style)
	var label := Label.new()
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", player_frame_config.bar_text_color)
	label.add_theme_color_override("font_shadow_color", player_frame_config.bar_text_shadow_color)
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


func _on_resource_changed(resource: String, current: float, maximum: float) -> void:
	match resource:
		"life":
			update_health(current, maximum)
		"mana":
			update_mana(current, maximum)
		"stamina":
			update_stamina(current, maximum)


func _on_level_changed(_old_level: int, _new_level: int) -> void:
	# Level display removed from PlayerFrame
	pass


func _on_stats_changed() -> void:
	# Max values might have changed, refresh all
	_refresh_all_resources()


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

	# Check for lootables
	if nearby_npc == null:
		var lootables := get_tree().get_nodes_in_group("lootables")
		for lootable in lootables:
			if is_instance_valid(lootable) and lootable.has_method("can_interact") and lootable.can_interact():
				nearby_npc = lootable
				break

	# Check for signs
	if nearby_npc == null:
		var signs := get_tree().get_nodes_in_group("signs")
		for sign_node in signs:
			if is_instance_valid(sign_node) and sign_node.has_method("can_interact") and sign_node.can_interact():
				nearby_npc = sign_node
				break

	# Check for lore echoes
	if nearby_npc == null:
		var echoes := get_tree().get_nodes_in_group("echoes")
		for echo in echoes:
			if is_instance_valid(echo) and echo.has_method("can_interact") and echo.can_interact():
				nearby_npc = echo
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
