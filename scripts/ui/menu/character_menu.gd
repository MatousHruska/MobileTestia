extends CanvasLayer
class_name CharacterMenu
## CharacterMenu - Main character/pause menu with tabbed interface
## Contains: Stats, Inventory (merged Equipment), Skills, Quests, Menu panels

signal menu_opened
signal menu_closed

enum Tab { INVENTORY, STATS, SKILLS, QUESTS, MENU }

## References
@onready var panel_container: Control = $MenuPanel
@onready var tab_bar: HBoxContainer = $MenuPanel/VBox/TabBar
@onready var content_area: Control = $MenuPanel/VBox/ContentArea
@onready var close_button: Button = $MenuPanel/VBox/TabBar/CloseButton

## Tab buttons
@onready var stats_tab: Button = $MenuPanel/VBox/TabBar/StatsTab
@onready var inventory_tab: Button = $MenuPanel/VBox/TabBar/InventoryTab
@onready var skills_tab: Button = $MenuPanel/VBox/TabBar/SkillsTab
@onready var quests_tab: Button = $MenuPanel/VBox/TabBar/QuestsTab
@onready var menu_tab: Button = $MenuPanel/VBox/TabBar/MenuTab

## Content panels
@onready var stats_panel: Control = $MenuPanel/VBox/ContentArea/StatsPanel
@onready var inventory_panel: Control = $MenuPanel/VBox/ContentArea/InventoryPanel
@onready var skills_panel: Control = $MenuPanel/VBox/ContentArea/SkillsPanel
@onready var quests_panel: Control = $MenuPanel/VBox/ContentArea/QuestsPanel
@onready var menu_panel: Control = $MenuPanel/VBox/ContentArea/MenuPanel

## Menu panel buttons
@onready var save_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/SaveButton
@onready var load_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/LoadButton
@onready var exit_to_menu_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/ExitToMenuButton
@onready var exit_game_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/ExitGameButton

## Confirmation popup (created dynamically in _setup_confirm_popup)
var confirm_popup: ConfirmationDialog = null

## Save/Load panel (created dynamically)
var _save_load_panel: SaveLoadPanel = null

## State
var current_tab: Tab = Tab.INVENTORY
var is_open: bool = false

## Tab button references for easy iteration
var _tab_buttons: Array[Button] = []
var _panels: Array[Control] = []

## Tab notification colors - using UITheme for consistency
## BADGE_COLOR uses COLOR_AVAILABLE (golden yellow)
## NORMAL_COLOR uses COLOR_SELECTED (white)

## Inventory panel instance (created dynamically)
var _inventory_panel_instance: InventoryPanel = null

## Stats panel instance (created dynamically)
var _stats_panel_instance: StatsPanel = null

## Quest log panel instance (created dynamically)
var _quest_log_instance = null  # QuestLogPanel

## Skills panel instance (created dynamically)
var _skills_panel_instance: SkillsPanel = null

## Design size for responsive scaling (315x206 for 270p viewport)
const DESIGN_WIDTH := 315.0
const DESIGN_HEIGHT := 206.0


func _ready() -> void:
	Debug.info("UI", "CharacterMenu ready")

	# Allow processing while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Hide on start
	visible = false
	is_open = false

	# Create confirmation popup if not in scene
	_setup_confirm_popup()

	# Setup tab arrays after @onready
	call_deferred("_setup_tabs")

	# Apply responsive sizing
	call_deferred("_apply_responsive_size")

	# Connect to viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_apply_responsive_size()


func _apply_responsive_size() -> void:
	## Constrain panel size to fit viewport on small screens
	## ResponsiveUI handles scaling from 270p base to native resolution
	if not panel_container:
		return

	var responsive_ui := get_node_or_null("/root/ResponsiveUI")
	if responsive_ui:
		responsive_ui.constrain_centered_panel(panel_container, DESIGN_WIDTH, DESIGN_HEIGHT, 0.02)
	else:
		# Fallback if ResponsiveUI not loaded yet
		var vp_size := get_viewport().get_visible_rect().size
		var max_width := vp_size.x * 0.96
		var max_height := vp_size.y * 0.96
		var width := minf(DESIGN_WIDTH, max_width)
		var height := minf(DESIGN_HEIGHT, max_height)
		panel_container.offset_left = -width / 2.0
		panel_container.offset_right = width / 2.0
		panel_container.offset_top = -height / 2.0
		panel_container.offset_bottom = height / 2.0


func _setup_confirm_popup() -> void:
	if not confirm_popup:
		confirm_popup = ConfirmationDialog.new()
		confirm_popup.name = "ConfirmPopup"
		confirm_popup.title = "Confirm"
		confirm_popup.dialog_text = "Are you sure?"
		confirm_popup.ok_button_text = "Yes"
		confirm_popup.cancel_button_text = "No"
		add_child(confirm_popup)


func _setup_tabs() -> void:
	_tab_buttons = [inventory_tab, stats_tab, skills_tab, quests_tab, menu_tab]
	_panels = [inventory_panel, stats_panel, skills_panel, quests_panel, menu_panel]

	# Connect tab buttons and apply nav colors (Level 1 - Navigation)
	if stats_tab:
		stats_tab.pressed.connect(_on_tab_pressed.bind(Tab.STATS))
		stats_tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	if inventory_tab:
		inventory_tab.pressed.connect(_on_tab_pressed.bind(Tab.INVENTORY))
		inventory_tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		inventory_tab.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
		inventory_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	if skills_tab:
		skills_tab.pressed.connect(_on_tab_pressed.bind(Tab.SKILLS))
		skills_tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	if quests_tab:
		quests_tab.pressed.connect(_on_tab_pressed.bind(Tab.QUESTS))
		quests_tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		quests_tab.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
		quests_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	if menu_tab:
		menu_tab.pressed.connect(_on_tab_pressed.bind(Tab.MENU))
		menu_tab.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		menu_tab.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
		menu_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)

	# Connect close button
	if close_button:
		close_button.pressed.connect(close_menu)

	# Connect menu panel buttons
	_setup_menu_buttons()

	# Setup the inventory panel (replaces old content)
	_setup_inventory_panel()

	# Setup the stats panel (replaces old content)
	_setup_stats_panel()

	# Setup the quest log panel (replaces old content)
	_setup_quest_panel()

	# Setup the skills panel (replaces old content)
	_setup_skills_panel()

	# Setup notification badges on tabs
	_setup_tab_badges()

	# Connect to PlayerStats for badge updates
	PlayerStats.attribute_points_changed.connect(_on_attribute_points_changed)
	PlayerStats.skill_points_changed.connect(_on_skill_points_changed)
	TalentManager.talent_points_changed.connect(_on_talent_points_changed)

	# Initial badge update
	_update_stats_badge()
	_update_skills_badge()

	# Show default tab
	_switch_to_tab(Tab.INVENTORY)


func _setup_menu_buttons() -> void:
	# Menu buttons use Level 2 - Header colors
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
		save_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		save_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
		save_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
		load_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		load_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
		load_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	if exit_to_menu_button:
		exit_to_menu_button.pressed.connect(_on_exit_to_menu_pressed)
		exit_to_menu_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		exit_to_menu_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
		exit_to_menu_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	if exit_game_button:
		exit_game_button.pressed.connect(_on_exit_game_pressed)
		exit_game_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		exit_game_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
		exit_game_button.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)


func _setup_inventory_panel() -> void:
	if not inventory_panel:
		return

	# Clear old inventory panel content
	for child in inventory_panel.get_children():
		child.queue_free()

	# Create new unified inventory panel
	_inventory_panel_instance = InventoryPanel.new()
	_inventory_panel_instance.name = "UnifiedInventory"
	_inventory_panel_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory_panel_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_panel_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_panel.add_child(_inventory_panel_instance)

	Debug.info("UI", "Unified InventoryPanel created")


func _setup_stats_panel() -> void:
	if not stats_panel:
		return

	# Clear old stats panel content
	for child in stats_panel.get_children():
		child.queue_free()

	# Create new stats panel
	_stats_panel_instance = StatsPanel.new()
	_stats_panel_instance.name = "DynamicStatsPanel"
	_stats_panel_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_panel_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_panel_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(_stats_panel_instance)

	Debug.info("UI", "StatsPanel created")


func _setup_quest_panel() -> void:
	if not quests_panel:
		return

	# Clear old quest panel content
	for child in quests_panel.get_children():
		child.queue_free()

	# Create new quest log panel
	var QuestLogPanelScript = load("res://scripts/ui/quest/quest_log_panel.gd")
	if QuestLogPanelScript:
		_quest_log_instance = QuestLogPanelScript.new()
		_quest_log_instance.name = "QuestLogPanel"
		# VBoxContainer uses size_flags, not anchors
		_quest_log_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_quest_log_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
		quests_panel.add_child(_quest_log_instance)
		Debug.info("UI", "QuestLogPanel created")
	else:
		Debug.warn("UI", "Failed to load QuestLogPanel script")


func _setup_skills_panel() -> void:
	if not skills_panel:
		return

	# Clear old skills panel content
	for child in skills_panel.get_children():
		child.queue_free()

	# Create new skills panel
	_skills_panel_instance = SkillsPanel.new()
	_skills_panel_instance.name = "DynamicSkillsPanel"
	_skills_panel_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_panel_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_panel.add_child(_skills_panel_instance)

	Debug.info("UI", "SkillsPanel created")


func _setup_tab_badges() -> void:
	## Set up tab badge system - badges are shown via text + color change
	pass  ## Badges are updated dynamically via _update_*_badge functions


func _update_stats_badge() -> void:
	if not stats_tab:
		return

	var points := PlayerStats.attribute_points
	if points > 0:
		stats_tab.text = "Stats (+%d)" % points
		stats_tab.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
		stats_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_AVAILABLE)
	else:
		stats_tab.text = "Stats"
		stats_tab.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
		stats_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)


func _update_skills_badge() -> void:
	if not skills_tab:
		return

	# Show available (unspent) skill points, not total
	var available := TalentManager.get_available_points()
	if available > 0:
		skills_tab.text = "Skills (+%d)" % available
		skills_tab.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
		skills_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_AVAILABLE)
	else:
		skills_tab.text = "Skills"
		skills_tab.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
		skills_tab.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)


func _on_attribute_points_changed(_points: int) -> void:
	_update_stats_badge()


func _on_skill_points_changed(_points: int) -> void:
	_update_skills_badge()


func _on_talent_points_changed(_total: int, _available: int) -> void:
	_update_skills_badge()


func _input(event: InputEvent) -> void:
	# Close on escape/back
	if event.is_action_pressed("ui_cancel") and is_open:
		close_menu()
		get_viewport().set_input_as_handled()


func _on_tab_pressed(tab: Tab) -> void:
	_switch_to_tab(tab)


func _switch_to_tab(tab: Tab) -> void:
	current_tab = tab

	# Clear inventory selection state when switching tabs
	Inventory.exit_swap_mode()
	Inventory.deselect()

	# Update button states
	for i in range(_tab_buttons.size()):
		var btn := _tab_buttons[i]
		if btn:
			btn.button_pressed = (i == int(tab))

	# Show/hide panels
	for i in range(_panels.size()):
		var panel := _panels[i]
		if panel:
			panel.visible = (i == int(tab))

	Debug.log("UI", "Tab switched", Tab.keys()[tab])

	# Refresh panel data
	_refresh_current_panel()


func _refresh_current_panel() -> void:
	match current_tab:
		Tab.STATS:
			_refresh_stats_panel()
		Tab.INVENTORY:
			_refresh_inventory_panel()
		Tab.SKILLS:
			_refresh_skills_panel()
		Tab.QUESTS:
			_refresh_quests_panel()
		Tab.MENU:
			_refresh_menu_panel()


func _refresh_stats_panel() -> void:
	if _stats_panel_instance:
		_stats_panel_instance.refresh_display()
	Debug.log("UI", "Refreshing stats panel")


func _refresh_inventory_panel() -> void:
	# Force refresh when tab becomes visible
	if _inventory_panel_instance:
		_inventory_panel_instance.refresh()
	Debug.log("UI", "Refreshing inventory panel")


func _refresh_skills_panel() -> void:
	if _skills_panel_instance:
		_skills_panel_instance.refresh()
	Debug.log("UI", "Refreshing skills panel")


func _refresh_quests_panel() -> void:
	if _quest_log_instance and _quest_log_instance.has_method("refresh"):
		_quest_log_instance.refresh()
	Debug.log("UI", "Refreshing quests panel")


func _refresh_menu_panel() -> void:
	Debug.log("UI", "Refreshing menu panel")


## Menu button handlers
func _on_save_pressed() -> void:
	Debug.info("UI", "Save button pressed")
	_show_save_load_panel(SaveLoadPanel.Mode.SAVE)


func _on_load_pressed() -> void:
	Debug.info("UI", "Load button pressed")
	_show_save_load_panel(SaveLoadPanel.Mode.LOAD)


func _show_save_load_panel(mode: SaveLoadPanel.Mode) -> void:
	## Show the save/load panel
	# Remove existing panel if any
	if _save_load_panel and is_instance_valid(_save_load_panel):
		_save_load_panel.queue_free()
		_save_load_panel = null

	# Create new panel
	_save_load_panel = SaveLoadPanel.new()
	_save_load_panel.name = "SaveLoadPanel"
	_save_load_panel.set_mode(mode)

	# Size and position
	_save_load_panel.custom_minimum_size = Vector2(400, 420)
	_save_load_panel.set_anchors_preset(Control.PRESET_CENTER)
	_save_load_panel.size = Vector2(400, 420)
	_save_load_panel.position = -_save_load_panel.size / 2.0

	# Connect signals
	_save_load_panel.slot_selected.connect(_on_save_load_slot_selected)
	_save_load_panel.cancelled.connect(_on_save_load_cancelled)

	add_child(_save_load_panel)
	Debug.info("UI", "SaveLoadPanel shown", SaveLoadPanel.Mode.keys()[mode])


func _on_save_load_slot_selected(slot: int) -> void:
	## Handle save/load completion
	Debug.info("UI", "_on_save_load_slot_selected() called", {
		"slot": slot,
		"game_state": Game.GameState.keys()[Game.current_state],
		"tree_paused": get_tree().paused
	})

	# Check mode BEFORE hiding panel (which sets reference to null)
	var was_loading := _save_load_panel and _save_load_panel.mode == SaveLoadPanel.Mode.LOAD
	Debug.info("UI", "was_loading check", was_loading)

	_hide_save_load_panel()

	# If loaded, close the menu to return to gameplay
	if was_loading:
		Debug.info("UI", "Calling close_menu() because was_loading=true")
		close_menu()
	else:
		Debug.info("UI", "NOT calling close_menu() because was_loading=false")


func _on_save_load_cancelled() -> void:
	## Handle save/load cancel
	_hide_save_load_panel()


func _hide_save_load_panel() -> void:
	if _save_load_panel and is_instance_valid(_save_load_panel):
		_save_load_panel.queue_free()
		_save_load_panel = null


func _on_exit_to_menu_pressed() -> void:
	Debug.info("UI", "Exit to menu button pressed")
	# TODO: Implement return to main menu
	Debug.warn("UI", "Exit to menu not yet implemented")


func _on_exit_game_pressed() -> void:
	Debug.info("UI", "Exit game button pressed")
	get_tree().quit()


## Public interface
func open_menu(start_tab: Tab = Tab.INVENTORY) -> void:
	if is_open:
		return

	is_open = true
	visible = true
	_switch_to_tab(start_tab)

	# Pause game
	Game.open_character_menu()

	menu_opened.emit()
	Debug.info("UI", "Character menu opened")


func close_menu() -> void:
	Debug.info("UI", "CharacterMenu.close_menu() called", {
		"is_open": is_open,
		"game_state": Game.GameState.keys()[Game.current_state],
		"tree_paused": get_tree().paused
	})

	if not is_open:
		Debug.warn("UI", "close_menu() - is_open is false, returning early")
		return

	is_open = false
	visible = false

	# Clear inventory selection state
	Inventory.exit_swap_mode()
	Inventory.deselect()

	# Resume game - use direct unpause in case state has changed during load
	if Game.current_state == Game.GameState.CHARACTER_MENU:
		Debug.info("UI", "close_menu() - calling Game.close_character_menu()")
		Game.close_character_menu()
	else:
		# State already changed (e.g., during load), just ensure tree is unpaused
		Debug.warn("UI", "close_menu() - state is not CHARACTER_MENU, directly unpausing", {
			"state": Game.GameState.keys()[Game.current_state],
			"tree_paused_before": get_tree().paused
		})
		get_tree().paused = false
		Debug.info("UI", "close_menu() - tree unpaused directly", {
			"tree_paused_after": get_tree().paused
		})

	menu_closed.emit()
	Debug.info("UI", "Character menu closed", {
		"final_tree_paused": get_tree().paused,
		"final_game_state": Game.GameState.keys()[Game.current_state]
	})


func toggle_menu() -> void:
	if is_open:
		close_menu()
	else:
		open_menu()


## Debug
func print_state() -> void:
	Debug.snapshot("UI", "CharacterMenu State", {
		"is_open": is_open,
		"current_tab": Tab.keys()[current_tab],
	})


## Debug: Add test items to inventory
func debug_add_test_items() -> void:
	Inventory.add_starting_items()


## Debug: Add stat points
func debug_add_stat_points(amount: int = 10) -> void:
	PlayerStats.debug_add_points(amount)


## Debug: Add experience
func debug_add_experience(amount: int = 500) -> void:
	PlayerStats.debug_add_experience(amount)
