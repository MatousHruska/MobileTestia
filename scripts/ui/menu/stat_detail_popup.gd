extends Control
class_name StatDetailPopup
## Popup displaying stat details - supports tap (stays open) and hold (closes on release)

signal closed

## UI References
var popup_panel: PanelContainer
var title_label: Label
var value_label: Label
var description_label: Label
var close_button: Button

## Current stat being displayed
var current_stat_name: String = ""
var current_stat_value: String = ""

## Hold behavior tracking
var _is_hold_mode: bool = false

## Popup sizing
const POPUP_WIDTH := 260.0


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

	# Main popup panel
	popup_panel = PanelContainer.new()
	popup_panel.name = "PopupPanel"
	popup_panel.custom_minimum_size = Vector2(POPUP_WIDTH, 0)
	add_child(popup_panel)

	# Main content container
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	popup_panel.add_child(content)

	# Header row with title and close button
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)

	# Title column
	var title_col := VBoxContainer.new()
	title_col.name = "TitleColumn"
	title_col.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title_col)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.modulate = Color(1.0, 0.9, 0.6)
	title_col.add_child(title_label)

	value_label = Label.new()
	value_label.name = "ValueLabel"
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.modulate = Color(0.9, 0.9, 0.9)
	title_col.add_child(value_label)

	# Close button (top right)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Separator
	var sep := HSeparator.new()
	content.add_child(sep)

	# Description section
	description_label = Label.new()
	description_label.name = "DescriptionLabel"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 12)
	description_label.modulate = Color(0.8, 0.8, 0.8)
	content.add_child(description_label)


## Show popup for a stat (tap mode - stays open until dismissed)
func show_stat(stat_name: String, stat_value: String, description: String, at_position: Vector2) -> void:
	_is_hold_mode = false
	_show_internal(stat_name, stat_value, description, at_position)


## Show popup for a stat (hold mode - closes when released)
func show_stat_hold(stat_name: String, stat_value: String, description: String, at_position: Vector2) -> void:
	_is_hold_mode = true
	_show_internal(stat_name, stat_value, description, at_position)


func _show_internal(stat_name: String, stat_value: String, description: String, at_position: Vector2) -> void:
	current_stat_name = stat_name
	current_stat_value = stat_value

	# Update display
	title_label.text = _format_stat_name(stat_name)
	value_label.text = stat_value if not stat_value.is_empty() else ""
	value_label.visible = not stat_value.is_empty()
	description_label.text = description

	# In hold mode, hide close button and dim less
	close_button.visible = not _is_hold_mode
	var dimmer := get_node_or_null("Dimmer") as ColorRect
	if dimmer:
		dimmer.color = Color(0, 0, 0, 0.3) if _is_hold_mode else Color(0, 0, 0, 0.5)

	visible = true

	# Position popup after it's visible so we can get its actual size
	await get_tree().process_frame
	_position_popup(at_position)


## Called when hold is released - closes popup if in hold mode
func release_hold() -> void:
	if _is_hold_mode and visible:
		hide_popup()


## Format stat name for display
func _format_stat_name(stat_name: String) -> String:
	return stat_name.capitalize().replace("_", " ")


## Position the popup at tap spot, stretching upward and to the right
func _position_popup(target_pos: Vector2) -> void:
	var screen_size := get_viewport_rect().size
	var popup_size := popup_panel.size
	var margin := 8.0

	# Bottom-left corner at tap position
	var pos := Vector2(target_pos.x, target_pos.y - popup_size.y)

	# Clamp to screen bounds
	pos.x = clampf(pos.x, margin, screen_size.x - popup_size.x - margin)
	pos.y = clampf(pos.y, margin, screen_size.y - popup_size.y - margin)

	popup_panel.position = pos


## Hide and clear popup
func hide_popup() -> void:
	visible = false
	current_stat_name = ""
	current_stat_value = ""
	_is_hold_mode = false
	closed.emit()


## Check if popup is currently showing in hold mode
func is_hold_mode() -> bool:
	return _is_hold_mode and visible


## Input handlers

func _on_dimmer_input(event: InputEvent) -> void:
	# In hold mode, don't close on dimmer click (will close on release)
	if _is_hold_mode:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_close_pressed()


func _on_close_pressed() -> void:
	hide_popup()
