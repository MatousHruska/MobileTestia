extends Control
class_name ItemDetailPopup
## Modal popup displaying item details (info only, actions via drag & drop)

signal closed

## UI References
var popup_panel: PanelContainer
var icon_rect: TextureRect
var name_label: Label
var type_label: Label
var rarity_label: Label
var description_label: Label
var stats_label: Label
var close_button: Button

## Current item being displayed
var current_item: ItemData = null
var current_source: String = ""
var current_index: int = -1

## Popup sizing
const POPUP_WIDTH := 280.0
const POPUP_HEIGHT := 200.0
const ICON_SIZE := 64.0


func _ready() -> void:
	_build_ui()
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

	# Main popup panel (positioned manually, not centered)
	popup_panel = PanelContainer.new()
	popup_panel.name = "PopupPanel"
	popup_panel.custom_minimum_size = Vector2(POPUP_WIDTH, 0)  # Fixed width, flexible height
	add_child(popup_panel)

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

	# Hint text for drag & drop
	var hint_label := Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "Drag items to move, equip, or destroy"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.modulate = Color(0.5, 0.5, 0.5)
	content.add_child(hint_label)


## Show popup with item details, centered on the given position
## If at_position is ZERO, keep current position (for updates)
func show_item(item: ItemData, source: String, index: int, at_position: Vector2 = Vector2.ZERO) -> void:
	current_item = item
	current_source = source
	current_index = index

	_update_display()
	visible = true

	# Only reposition if a valid position was given
	if at_position != Vector2.ZERO:
		# Position popup after it's visible so we can get its actual size
		await get_tree().process_frame
		_position_popup(at_position)


## Position the popup centered on target, clamped to screen bounds
func _position_popup(target_pos: Vector2) -> void:
	var screen_size := get_viewport_rect().size
	var popup_size := popup_panel.size

	# Center on target position
	var pos := target_pos - popup_size / 2

	# Clamp to screen bounds with small margin
	var margin := 8.0
	pos.x = clampf(pos.x, margin, screen_size.x - popup_size.x - margin)
	pos.y = clampf(pos.y, margin, screen_size.y - popup_size.y - margin)

	popup_panel.position = pos


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
