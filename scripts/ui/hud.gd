extends CanvasLayer
class_name HUD
## HUD - Main game HUD controller
## Manages player stats display and mobile controls

## Signals
signal menu_button_pressed

## References (set in scene or found automatically)
@onready var joystick: VirtualJoystick = $Controls/JoystickArea/VirtualJoystick
@onready var attack_button: ActionButton = $Controls/ActionButtons/AttackButton
@onready var dodge_button: ActionButton = $Controls/ActionButtons/DodgeButton
@onready var interact_button: Button = $Controls/ActionButtons/InteractButton
@onready var player_frame: Control = $PlayerFrame
@onready var menu_button: Button = $MenuButton/Button

## Resource bars (created dynamically)
var health_bar: ProgressBar
var mana_bar: ProgressBar
var stamina_bar: ProgressBar
var health_label: Label
var mana_label: Label
var stamina_label: Label
var level_label: Label

## Player reference
var player: PlayerController = null

## Character menu reference (set externally)
var character_menu: CharacterMenu = null

## Nearby interactable NPC
var nearby_npc: Node = null
var _last_nearby_npc: Node = null


func _ready() -> void:
	Debug.info("UI", "HUD ready")
	_setup_resource_bars()
	_connect_to_game_manager()
	_connect_to_player_stats()
	_setup_controls()


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
	bg.offset_left = 8
	bg.offset_top = 8
	bg.offset_right = -8
	bg.offset_bottom = -8
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	player_frame.add_child(bg)

	# Bars container
	var bars_container := VBoxContainer.new()
	bars_container.name = "BarsContainer"
	bars_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_container.offset_left = 12
	bars_container.offset_top = 12
	bars_container.offset_right = -12
	bars_container.offset_bottom = -12
	bars_container.add_theme_constant_override("separation", 4)
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
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	bars_container.add_child(level_label)


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
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)

	# Add value label on top of bar
	var label := Label.new()
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
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
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)

	if dodge_button:
		dodge_button.pressed.connect(_on_dodge_pressed)

	if interact_button:
		interact_button.pressed.connect(_on_interact_pressed)

	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)


func _on_attack_pressed() -> void:
	if player and Game.can_player_attack:
		player.request_attack()


func _on_dodge_pressed() -> void:
	if player and Game.can_player_move:
		player.request_dodge()


func _on_interact_pressed() -> void:
	if nearby_npc and nearby_npc.has_method("interact"):
		nearby_npc.interact()


func _on_menu_pressed() -> void:
	Debug.log("UI", "Menu button pressed")
	menu_button_pressed.emit()

	# Open character menu if available
	if character_menu:
		character_menu.toggle_menu()


## Public interface
func set_character_menu(menu: CharacterMenu) -> void:
	character_menu = menu
	Debug.info("UI", "Character menu linked to HUD")


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
	if not interact_button or not Game.is_playing:
		return

	# Find nearby interactable NPCs
	nearby_npc = null

	if NPCManager:
		for npc in NPCManager.all_friendlies:
			if is_instance_valid(npc) and npc.has_method("can_interact") and npc.can_interact():
				nearby_npc = npc
				break

	# Track NPC changes
	if nearby_npc != _last_nearby_npc:
		_last_nearby_npc = nearby_npc

	# Show/hide button based on nearby NPC
	if nearby_npc:
		if not interact_button.visible:
			interact_button.visible = true
	else:
		if interact_button.visible:
			interact_button.visible = false


## Debug
func print_state() -> void:
	Debug.snapshot("UI", "HUD State", {
		"player_connected": player != null,
		"joystick_active": joystick.is_pressed() if joystick else false,
		"joystick_direction": joystick.get_direction() if joystick else Vector2.ZERO,
		"menu_connected": character_menu != null,
	})
