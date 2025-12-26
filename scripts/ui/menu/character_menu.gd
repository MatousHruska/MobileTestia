extends CanvasLayer
class_name CharacterMenu
## CharacterMenu - Main character/pause menu with tabbed interface
## Contains: Stats, Inventory, Equipment, Skills panels

signal menu_opened
signal menu_closed

enum Tab { STATS, INVENTORY, EQUIPMENT, SKILLS }

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

## Content panels
@onready var stats_panel: Control = $MenuPanel/VBox/ContentArea/StatsPanel
@onready var inventory_panel: Control = $MenuPanel/VBox/ContentArea/InventoryPanel
@onready var equipment_panel: Control = $MenuPanel/VBox/ContentArea/EquipmentPanel
@onready var skills_panel: Control = $MenuPanel/VBox/ContentArea/SkillsPanel

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
	_tab_buttons = [stats_tab, inventory_tab, equipment_tab, skills_tab]
	_panels = [stats_panel, inventory_panel, equipment_panel, skills_panel]

	# Connect tab buttons
	if stats_tab:
		stats_tab.pressed.connect(_on_tab_pressed.bind(Tab.STATS))
	if inventory_tab:
		inventory_tab.pressed.connect(_on_tab_pressed.bind(Tab.INVENTORY))
	if equipment_tab:
		equipment_tab.pressed.connect(_on_tab_pressed.bind(Tab.EQUIPMENT))
	if skills_tab:
		skills_tab.pressed.connect(_on_tab_pressed.bind(Tab.SKILLS))

	# Connect close button
	if close_button:
		close_button.pressed.connect(close_menu)

	# Show default tab
	_switch_to_tab(Tab.STATS)


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
