extends CanvasLayer
class_name CharacterMenu
## CharacterMenu - Main character/pause menu with tabbed interface
## Contains: Stats, Inventory, Equipment, Skills, Quests, Menu panels

signal menu_opened
signal menu_closed

enum Tab { STATS, INVENTORY, EQUIPMENT, SKILLS, QUESTS, MENU }

## References
@onready var panel_container: Control = $MenuPanel
@onready var tab_bar: HBoxContainer = $MenuPanel/VBox/TabBar
@onready var content_area: Control = $MenuPanel/VBox/ContentArea
@onready var close_button: Button = $MenuPanel/VBox/Header/CloseButton

## Tab buttons
@onready var stats_tab: Button = $MenuPanel/VBox/TabBar/StatsTab
@onready var inventory_tab: Button = $MenuPanel/VBox/TabBar/InventoryTab
@onready var equipment_tab: Button = $MenuPanel/VBox/TabBar/EquipmentTab
@onready var skills_tab: Button = $MenuPanel/VBox/TabBar/SkillsTab
@onready var quests_tab: Button = $MenuPanel/VBox/TabBar/QuestsTab
@onready var menu_tab: Button = $MenuPanel/VBox/TabBar/MenuTab

## Content panels
@onready var stats_panel: Control = $MenuPanel/VBox/ContentArea/StatsPanel
@onready var inventory_panel: Control = $MenuPanel/VBox/ContentArea/InventoryPanel
@onready var equipment_panel: Control = $MenuPanel/VBox/ContentArea/EquipmentPanel
@onready var skills_panel: Control = $MenuPanel/VBox/ContentArea/SkillsPanel
@onready var quests_panel: Control = $MenuPanel/VBox/ContentArea/QuestsPanel
@onready var menu_panel: Control = $MenuPanel/VBox/ContentArea/MenuPanel

## Menu panel buttons
@onready var save_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/SaveButton
@onready var load_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/LoadButton
@onready var exit_to_menu_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/ExitToMenuButton
@onready var exit_game_button: Button = $MenuPanel/VBox/ContentArea/MenuPanel/ButtonsVBox/ExitGameButton

## State
var current_tab: Tab = Tab.STATS
var is_open: bool = false

## Tab button references for easy iteration
var _tab_buttons: Array[Button] = []
var _panels: Array[Control] = []


func _ready() -> void:
	Debug.info("UI", "CharacterMenu ready")

	# Hide on start
	visible = false
	is_open = false

	# Setup tab arrays after @onready
	call_deferred("_setup_tabs")


func _setup_tabs() -> void:
	_tab_buttons = [stats_tab, inventory_tab, equipment_tab, skills_tab, quests_tab, menu_tab]
	_panels = [stats_panel, inventory_panel, equipment_panel, skills_panel, quests_panel, menu_panel]

	# Connect tab buttons
	if stats_tab:
		stats_tab.pressed.connect(_on_tab_pressed.bind(Tab.STATS))
	if inventory_tab:
		inventory_tab.pressed.connect(_on_tab_pressed.bind(Tab.INVENTORY))
	if equipment_tab:
		equipment_tab.pressed.connect(_on_tab_pressed.bind(Tab.EQUIPMENT))
	if skills_tab:
		skills_tab.pressed.connect(_on_tab_pressed.bind(Tab.SKILLS))
	if quests_tab:
		quests_tab.pressed.connect(_on_tab_pressed.bind(Tab.QUESTS))
	if menu_tab:
		menu_tab.pressed.connect(_on_tab_pressed.bind(Tab.MENU))

	# Connect close button
	if close_button:
		close_button.pressed.connect(close_menu)

	# Connect menu panel buttons
	_setup_menu_buttons()

	# Show default tab
	_switch_to_tab(Tab.STATS)


func _setup_menu_buttons() -> void:
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if exit_to_menu_button:
		exit_to_menu_button.pressed.connect(_on_exit_to_menu_pressed)
	if exit_game_button:
		exit_game_button.pressed.connect(_on_exit_game_pressed)


func _input(event: InputEvent) -> void:
	# Close on escape/back
	if event.is_action_pressed("ui_cancel") and is_open:
		close_menu()
		get_viewport().set_input_as_handled()


func _on_tab_pressed(tab: Tab) -> void:
	_switch_to_tab(tab)


func _switch_to_tab(tab: Tab) -> void:
	current_tab = tab

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
		Tab.EQUIPMENT:
			_refresh_equipment_panel()
		Tab.SKILLS:
			_refresh_skills_panel()
		Tab.QUESTS:
			_refresh_quests_panel()
		Tab.MENU:
			_refresh_menu_panel()


func _refresh_stats_panel() -> void:
	# TODO: Populate with actual player stats
	Debug.log("UI", "Refreshing stats panel")


func _refresh_inventory_panel() -> void:
	# TODO: Populate with inventory items
	Debug.log("UI", "Refreshing inventory panel")


func _refresh_equipment_panel() -> void:
	# TODO: Populate with equipped items
	Debug.log("UI", "Refreshing equipment panel")


func _refresh_skills_panel() -> void:
	# TODO: Populate with skill tree
	Debug.log("UI", "Refreshing skills panel")


func _refresh_quests_panel() -> void:
	# TODO: Populate with active quests
	Debug.log("UI", "Refreshing quests panel")


func _refresh_menu_panel() -> void:
	Debug.log("UI", "Refreshing menu panel")


## Menu button handlers
func _on_save_pressed() -> void:
	Debug.info("UI", "Save button pressed")
	# TODO: Implement save functionality
	Debug.warn("UI", "Save not yet implemented")


func _on_load_pressed() -> void:
	Debug.info("UI", "Load button pressed")
	# TODO: Implement load functionality
	Debug.warn("UI", "Load not yet implemented")


func _on_exit_to_menu_pressed() -> void:
	Debug.info("UI", "Exit to menu button pressed")
	# TODO: Implement return to main menu
	Debug.warn("UI", "Exit to menu not yet implemented")


func _on_exit_game_pressed() -> void:
	Debug.info("UI", "Exit game button pressed")
	get_tree().quit()


## Public interface
func open_menu(start_tab: Tab = Tab.STATS) -> void:
	if is_open:
		return

	is_open = true
	visible = true
	_switch_to_tab(start_tab)

	# Pause game
	Game.open_inventory()

	menu_opened.emit()
	Debug.info("UI", "Character menu opened")


func close_menu() -> void:
	if not is_open:
		return

	is_open = false
	visible = false

	# Resume game
	Game.close_inventory()

	menu_closed.emit()
	Debug.info("UI", "Character menu closed")


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
