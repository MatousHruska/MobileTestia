extends Control
class_name ItemDetailPopup
## Modal popup displaying item details with action buttons
## Replaces the inline details column for mobile-friendly layout

signal equip_pressed
signal use_pressed
signal quick_slot_pressed
signal swap_pressed
signal destroy_pressed
signal closed

## UI References
var popup_panel: PanelContainer
var icon_rect: TextureRect
var name_label: Label
var type_label: Label
var rarity_label: Label
var description_label: Label
var stats_label: Label
var equip_button: Button
var use_button: Button
var swap_button: Button
var destroy_button: Button
var close_button: Button
var swap_mode_label: Label

## Current item being displayed
var current_item: ItemData = null
var current_source: String = ""
var current_index: int = -1

## Popup sizing
const POPUP_WIDTH := 320.0
const POPUP_HEIGHT := 340.0
const ICON_SIZE := 64.0


func _ready() -> void:
	_build_ui()
	_connect_signals()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_ui() -> void:
	# Full screen dimmer background (click to close)
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_preset(PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.gui_input.connect(_on_dimmer_input)
	add_child(dimmer)

	# Center container
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Main popup panel
	popup_panel = PanelContainer.new()
	popup_panel.name = "PopupPanel"
	popup_panel.custom_minimum_size = Vector2(POPUP_WIDTH, POPUP_HEIGHT)
	center.add_child(popup_panel)

	# Main content container
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	popup_panel.add_child(content)

	# Header row with icon and name
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)

	# Icon with background
	var icon_bg := ColorRect.new()
	icon_bg.name = "IconBg"
	icon_bg.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_bg.color = Color(0.2, 0.2, 0.25, 1)
	header.add_child(icon_bg)

	icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.set_anchors_preset(PRESET_FULL_RECT)
	icon_rect.offset_left = 4
	icon_rect.offset_top = 4
	icon_rect.offset_right = -4
	icon_rect.offset_bottom = -4
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_bg.add_child(icon_rect)

	# Name and type column
	var name_col := VBoxContainer.new()
	name_col.name = "NameColumn"
	name_col.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(name_col)

	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.add_theme_font_size_override("font_size", 16)
	name_col.add_child(name_label)

	type_label = Label.new()
	type_label.name = "TypeLabel"
	type_label.add_theme_font_size_override("font_size", 11)
	type_label.modulate = Color(0.7, 0.7, 0.7)
	name_col.add_child(type_label)

	rarity_label = Label.new()
	rarity_label.name = "RarityLabel"
	rarity_label.add_theme_font_size_override("font_size", 11)
	name_col.add_child(rarity_label)

	# Close button (top right)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Separator
	var sep1 := HSeparator.new()
	content.add_child(sep1)

	# Stats section
	var stats_scroll := ScrollContainer.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(stats_scroll)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.name = "StatsVBox"
	stats_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	stats_scroll.add_child(stats_vbox)

	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(stats_label)

	description_label = Label.new()
	description_label.name = "DescriptionLabel"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 11)
	description_label.modulate = Color(0.8, 0.8, 0.8)
	stats_vbox.add_child(description_label)

	# Separator before buttons
	var sep2 := HSeparator.new()
	content.add_child(sep2)

	# Swap mode indicator
	swap_mode_label = Label.new()
	swap_mode_label.name = "SwapModeLabel"
	swap_mode_label.text = "Select target slot to swap..."
	swap_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	swap_mode_label.modulate = Color(1.0, 0.8, 0.2)
	swap_mode_label.add_theme_font_size_override("font_size", 12)
	swap_mode_label.visible = false
	content.add_child(swap_mode_label)

	# Action buttons - top row (main action)
	var top_buttons := HBoxContainer.new()
	top_buttons.name = "TopButtons"
	top_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	top_buttons.add_theme_constant_override("separation", 8)
	content.add_child(top_buttons)

	equip_button = Button.new()
	equip_button.name = "EquipButton"
	equip_button.text = "Equip"
	equip_button.custom_minimum_size = Vector2(100, 36)
	equip_button.pressed.connect(_on_equip_pressed)
	top_buttons.add_child(equip_button)

	use_button = Button.new()
	use_button.name = "UseButton"
	use_button.text = "Use"
	use_button.custom_minimum_size = Vector2(80, 36)
	use_button.pressed.connect(_on_use_pressed)
	use_button.visible = false
	top_buttons.add_child(use_button)

	# Action buttons - bottom row (secondary actions)
	var bottom_buttons := HBoxContainer.new()
	bottom_buttons.name = "BottomButtons"
	bottom_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_buttons.add_theme_constant_override("separation", 8)
	content.add_child(bottom_buttons)

	swap_button = Button.new()
	swap_button.name = "SwapButton"
	swap_button.text = "Swap"
	swap_button.custom_minimum_size = Vector2(70, 32)
	swap_button.pressed.connect(_on_swap_pressed)
	bottom_buttons.add_child(swap_button)

	destroy_button = Button.new()
	destroy_button.name = "DestroyButton"
	destroy_button.text = "Destroy"
	destroy_button.custom_minimum_size = Vector2(70, 32)
	destroy_button.pressed.connect(_on_destroy_pressed)
	bottom_buttons.add_child(destroy_button)


func _connect_signals() -> void:
	Inventory.swap_mode_changed.connect(_on_swap_mode_changed)


## Show popup with item details
func show_item(item: ItemData, source: String, index: int) -> void:
	current_item = item
	current_source = source
	current_index = index

	_update_display()
	_update_buttons()
	visible = true


## Hide and clear popup
func hide_popup() -> void:
	visible = false
	current_item = null
	current_source = ""
	current_index = -1


## Update the display with current item info
func _update_display() -> void:
	if not current_item:
		return

	# Icon
	icon_rect.texture = current_item.icon

	# Name with rarity color
	name_label.text = current_item.item_name
	name_label.modulate = ItemData.get_rarity_color(current_item.rarity)

	# Rarity
	rarity_label.text = ItemData.get_rarity_name(current_item.rarity)
	rarity_label.modulate = ItemData.get_rarity_color(current_item.rarity)

	# Type-specific display
	if current_item is EquipmentData:
		var equip: EquipmentData = current_item as EquipmentData
		type_label.text = equip.get_type_name()
		stats_label.text = equip.get_stat_text()
	elif current_item is ConsumableData:
		var consumable: ConsumableData = current_item as ConsumableData
		type_label.text = "Consumable"
		stats_label.text = consumable.get_effect_text()
	else:
		type_label.text = "Item"
		stats_label.text = ""

	# Description
	if current_item.description and current_item.description.length() > 0:
		description_label.text = current_item.description
		description_label.visible = true
	else:
		description_label.visible = false


## Update button visibility based on item type and location
func _update_buttons() -> void:
	if not current_item:
		equip_button.visible = false
		use_button.visible = false
		swap_button.visible = false
		destroy_button.visible = false
		return

	var is_in_backpack := current_source == "backpack"
	var is_equipped := current_source == "equipment"

	# Equipment items
	if current_item.item_type == ItemData.ItemType.EQUIPMENT:
		equip_button.visible = true
		use_button.visible = false
		if is_in_backpack:
			equip_button.text = "Equip"
		else:
			equip_button.text = "Unequip"
	else:
		# Consumables
		equip_button.visible = is_in_backpack  # Quick Slot option
		use_button.visible = true
		if is_in_backpack:
			equip_button.text = "Quick Slot"

	# Swap only for backpack items
	swap_button.visible = is_in_backpack

	# Destroy always available
	destroy_button.visible = true


## Input handlers

func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_close_pressed()


func _on_close_pressed() -> void:
	hide_popup()
	Inventory.deselect()
	closed.emit()


func _on_equip_pressed() -> void:
	equip_pressed.emit()
	# Keep popup open to show updated state after equip/unequip
	_update_buttons()


func _on_use_pressed() -> void:
	use_pressed.emit()
	# Close popup after use (item may be consumed)
	hide_popup()


func _on_swap_pressed() -> void:
	swap_pressed.emit()
	# Close popup - swap mode will be active, user picks target slot
	hide_popup()


func _on_destroy_pressed() -> void:
	destroy_pressed.emit()
	# Parent handles confirmation, popup stays open


func _on_swap_mode_changed(active: bool) -> void:
	swap_mode_label.visible = active
	if active:
		# Hide action buttons during swap mode
		equip_button.visible = false
		use_button.visible = false
		swap_button.visible = false
		destroy_button.visible = false
	else:
		_update_buttons()
