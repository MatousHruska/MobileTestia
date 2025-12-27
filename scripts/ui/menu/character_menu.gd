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
@onready var close_button: Button = $MenuPanel/VBox/Header/CloseButton

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

## Confirmation popup
@onready var confirm_popup: ConfirmationDialog = $ConfirmPopup

## State
var current_tab: Tab = Tab.INVENTORY
var is_open: bool = false

## Tab button references for easy iteration
var _tab_buttons: Array[Button] = []
var _panels: Array[Control] = []

## Inventory panel instance (created dynamically)
var _inventory_panel_instance: InventoryPanel = null

## Stats panel instance (created dynamically)
var _stats_panel_instance: StatsPanel = null


func _ready() -> void:
	Debug.info("UI", "CharacterMenu ready")

	# Hide on start
	visible = false
	is_open = false

	# Create confirmation popup if not in scene
	_setup_confirm_popup()

	# Setup tab arrays after @onready
	call_deferred("_setup_tabs")


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

	# Connect tab buttons
	if stats_tab:
		stats_tab.pressed.connect(_on_tab_pressed.bind(Tab.STATS))
	if inventory_tab:
		inventory_tab.pressed.connect(_on_tab_pressed.bind(Tab.INVENTORY))
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

	# Setup the inventory panel (replaces old content)
	_setup_inventory_panel()

	# Setup the stats panel (replaces old content)
	_setup_stats_panel()

	# Show default tab
	_switch_to_tab(Tab.INVENTORY)


func _setup_menu_buttons() -> void:
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if exit_to_menu_button:
		exit_to_menu_button.pressed.connect(_on_exit_to_menu_pressed)
	if exit_game_button:
		exit_game_button.pressed.connect(_on_exit_game_pressed)


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
	_inventory_panel_instance.destroy_requested.connect(_on_destroy_requested)
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
	stats_panel.add_child(_stats_panel_instance)

	Debug.info("UI", "StatsPanel created")


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
	# Inventory panel auto-refreshes via signals
	Debug.log("UI", "Refreshing inventory panel")


func _refresh_skills_panel() -> void:
	# TODO: Populate with skill tree
	Debug.log("UI", "Refreshing skills panel")


func _refresh_quests_panel() -> void:
	# TODO: Populate with active quests
	Debug.log("UI", "Refreshing quests panel")


func _refresh_menu_panel() -> void:
	Debug.log("UI", "Refreshing menu panel")


## Destroy confirmation
func _on_destroy_requested() -> void:
	if not Inventory.has_selection():
		return

	confirm_popup.title = "Destroy Item"
	confirm_popup.dialog_text = "Are you sure you want to destroy\n%s?" % Inventory.selected_item.item_name

	# Disconnect any previous connections
	if confirm_popup.confirmed.is_connected(_on_destroy_confirmed):
		confirm_popup.confirmed.disconnect(_on_destroy_confirmed)

	confirm_popup.confirmed.connect(_on_destroy_confirmed)
	confirm_popup.popup_centered()


func _on_destroy_confirmed() -> void:
	Inventory.destroy_selected()
	Debug.info("UI", "Item destroyed via confirmation")


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
func open_menu(start_tab: Tab = Tab.INVENTORY) -> void:
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

	# Clear inventory selection state
	Inventory.exit_swap_mode()
	Inventory.deselect()

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


## Debug: Add test items to inventory
func debug_add_test_items() -> void:
	Inventory.debug_add_test_items()


## Debug: Add stat points
func debug_add_stat_points(amount: int = 10) -> void:
	PlayerStats.debug_add_points(amount)


## Debug: Add experience
func debug_add_experience(amount: int = 500) -> void:
	PlayerStats.debug_add_experience(amount)
