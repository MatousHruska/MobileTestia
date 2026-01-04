extends Control
class_name CharacterMenuPopup
## Base class for all Character Menu popups
##
## Features:
## - Appears at tap position (clamped to screen bounds)
## - Full viewport dimmer background
## - X button to close
## - Tap outside to close
## - Escape key to close
##
## Subclasses should override:
## - _build_content(content_container: VBoxContainer) - Build popup-specific content
## - _get_popup_width() -> int - Override default width
## - _get_popup_min_height() -> int - Override default min height
## - _get_popup_max_height() -> int - Override default max height

#===============================================================================
# SIGNALS
#===============================================================================

signal closed

#===============================================================================
# CONSTANTS (can be overridden by subclasses)
#===============================================================================

const DEFAULT_POPUP_WIDTH := 280
const DEFAULT_POPUP_MIN_HEIGHT_PCT := 0.35  # 35% of viewport height
const DEFAULT_POPUP_MAX_HEIGHT_PCT := 0.75  # 75% of viewport height
const MARGIN := 8
const SCREEN_PADDING := 10
const DIMMER_ALPHA := 0.3

#===============================================================================
# STATE
#===============================================================================

var _is_closing: bool = false

#===============================================================================
# UI REFERENCES
#===============================================================================

var _background: ColorRect
var _panel: PanelContainer
var _close_button: Button
var _header: HBoxContainer
var _header_content: VBoxContainer
var _scroll: ScrollContainer
var _content_container: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_size()


func _on_viewport_size_changed() -> void:
	_update_size()


func _update_size() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	size = viewport_size


#===============================================================================
# VIRTUAL METHODS FOR SUBCLASSES
#===============================================================================

## Override to set custom popup width (in pixels)
func _get_popup_width() -> int:
	return DEFAULT_POPUP_WIDTH


## Override to set custom minimum height (as percentage of viewport, 0.0-1.0)
func _get_popup_min_height_pct() -> float:
	return DEFAULT_POPUP_MIN_HEIGHT_PCT


## Override to set custom maximum height (as percentage of viewport, 0.0-1.0)
func _get_popup_max_height_pct() -> float:
	return DEFAULT_POPUP_MAX_HEIGHT_PCT


## Override to build popup-specific content
## Called during _build_ui, add your content to the container
func _build_content(_content_container: VBoxContainer) -> void:
	pass


## Override to build header content (between icon area and close button)
## Return the header content container to add name/subtitle labels
func _build_header_content() -> VBoxContainer:
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return name_col


## Override to show/hide icon area (default: true)
func _has_icon() -> bool:
	return true


#===============================================================================
# UI BUILDING
#===============================================================================

func _build_ui() -> void:
	# Full screen background for detecting outside clicks
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0, 0, 0, DIMMER_ALPHA)
	_background.gui_input.connect(_on_background_input)
	add_child(_background)

	# Main popup panel
	_panel = PanelContainer.new()
	var viewport_height := get_viewport().get_visible_rect().size.y
	var min_height := int(viewport_height * _get_popup_min_height_pct())
	_panel.custom_minimum_size = Vector2(_get_popup_width(), min_height)
	add_child(_panel)

	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	margin.add_theme_constant_override("margin_top", MARGIN)
	margin.add_theme_constant_override("margin_bottom", MARGIN)
	_panel.add_child(margin)

	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Build header
	_build_header(vbox)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable content area
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 40)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_theme_constant_override("separation", 4)
	_scroll.add_child(_content_container)

	# Let subclass build content
	_build_content(_content_container)


func _build_header(parent: VBoxContainer) -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	parent.add_child(_header)

	# Icon area (optional, controlled by _has_icon)
	if _has_icon():
		var icon_container := _create_icon_container()
		_header.add_child(icon_container)

	# Header content from subclass
	_header_content = _build_header_content()
	_header.add_child(_header_content)

	# Close button
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.pressed.connect(_on_close_pressed)
	_header.add_child(_close_button)

	# Style close button
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.4, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(4)
	_close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.6, 0.2, 0.2, 0.9)
	close_hover.set_corner_radius_all(4)
	_close_button.add_theme_stylebox_override("hover", close_hover)


## Create the icon container - override in subclass if needed
func _create_icon_container() -> Control:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# Icon placeholder background
	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(40, 40)
	icon_bg.color = Color(0.2, 0.2, 0.25, 0.8)
	icon.add_child(icon_bg)
	icon_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_bg.z_index = -1

	return icon


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup at the given screen position
func show_at(screen_pos: Vector2) -> void:
	_is_closing = false
	_update_size()
	_position_popup(screen_pos)
	visible = true


## Close the popup
func close() -> void:
	if _is_closing:
		return
	_is_closing = true
	visible = false
	closed.emit()


## Check if popup is visible
func is_open() -> bool:
	return visible and not _is_closing


#===============================================================================
# POSITIONING
#===============================================================================

func _position_popup(tap_pos: Vector2) -> void:
	# Wait for layout to calculate sizes
	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _panel.size

	# Limit panel height (percentage of viewport)
	var max_height := int(viewport_size.y * _get_popup_max_height_pct())
	if panel_size.y > max_height:
		_panel.custom_minimum_size.y = max_height
		_scroll.custom_minimum_size.y = max_height - 80
		panel_size.y = max_height

	# Start position: slightly to the right and vertically centered on tap
	var pos := tap_pos + Vector2(10, -panel_size.y / 2)

	# Clamp to screen bounds
	pos.x = clampf(pos.x, SCREEN_PADDING, viewport_size.x - panel_size.x - SCREEN_PADDING)
	pos.y = clampf(pos.y, SCREEN_PADDING, viewport_size.y - panel_size.y - SCREEN_PADDING)

	_panel.position = pos


#===============================================================================
# INPUT HANDLING
#===============================================================================

func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			var panel_rect := _panel.get_global_rect()
			var tap_pos: Vector2 = _background.get_global_position() + event.position
			if not panel_rect.has_point(tap_pos):
				close()


func _on_close_pressed() -> void:
	close()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


#===============================================================================
# UTILITY METHODS FOR SUBCLASSES
#===============================================================================

## Add a labeled stat row to a container
func add_stat_row(container: VBoxContainer, label_text: String, value_text: String, value_color: Color = Color(0.9, 0.9, 0.9)) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	container.add_child(row)

	var label := Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", value_color)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value)


## Get the icon TextureRect from header (if exists)
func get_icon() -> TextureRect:
	if _header and _header.get_child_count() > 0:
		var first_child := _header.get_child(0)
		if first_child is TextureRect:
			return first_child
	return null


## Clear all content from the content container
func clear_content() -> void:
	for child in _content_container.get_children():
		child.queue_free()
