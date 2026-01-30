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

const BASE_POPUP_WIDTH := 100  # Base width for 270p, scaled to native
const DEFAULT_POPUP_MIN_HEIGHT_PCT := 0.35  # 35% of viewport height
const DEFAULT_POPUP_MAX_HEIGHT_PCT := 0.75  # 75% of viewport height
const BASE_SCREEN_PADDING := 4  # Base padding for 270p, scaled to native
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

## Override to set custom popup width (in base 270p pixels, will be scaled)
func _get_popup_width() -> int:
	return UITheme.scale_px_i(BASE_POPUP_WIDTH)


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
	_panel.add_theme_stylebox_override("panel", UITheme.create_popup_style())

	# Margin container
	var margin := UITheme.create_margin_container()
	_panel.add_child(margin)

	# Main VBox
	var vbox := VBoxContainer.new()
	UITheme.setup_vbox(vbox, UITheme.MARGIN_SMALL)
	margin.add_child(vbox)

	# Build header
	_build_header(vbox)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable content area
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, UITheme.SCROLL_MIN_HEIGHT)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(_content_container, UITheme.SEPARATION_SMALL)
	_scroll.add_child(_content_container)

	# Let subclass build content
	_build_content(_content_container)


func _build_header(parent: VBoxContainer) -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL)
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
	_close_button.custom_minimum_size = Vector2(UITheme.BUTTON_HEIGHT_SMALL, UITheme.BUTTON_HEIGHT_SMALL)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.pressed.connect(_on_close_pressed)
	_header.add_child(_close_button)

	# Style close button
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = UITheme.COLOR_DEBUFF
	close_style.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	_close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = UITheme.COLOR_DEBUFF.lightened(0.2)
	close_hover.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	_close_button.add_theme_stylebox_override("hover", close_hover)


## Create the icon container - override in subclass if needed
func _create_icon_container() -> Control:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(UITheme.ICON_SIZE_SMALL, UITheme.ICON_SIZE_SMALL)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# Icon placeholder background
	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(UITheme.ICON_SIZE_SMALL, UITheme.ICON_SIZE_SMALL)
	icon_bg.color = UITheme.COLOR_BUTTON_BG
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
	# Update panel width from current UITheme values (allows live reload)
	var viewport_height := get_viewport().get_visible_rect().size.y
	var min_height := int(viewport_height * _get_popup_min_height_pct())
	_panel.custom_minimum_size = Vector2(_get_popup_width(), min_height)
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
		# Reserve space for header (margins + header row + separator)
		var header_space := UITheme.MARGIN_STANDARD * 4 + UITheme.ROW_HEIGHT_NORMAL + UITheme.SEPARATION_NORMAL
		_scroll.custom_minimum_size.y = max_height - header_space
		panel_size.y = max_height

	# Start position: slightly to the right and vertically centered on tap
	var pos := tap_pos + Vector2(10, -panel_size.y / 2)

	# Clamp to screen bounds (scale padding for native resolution)
	var screen_padding := UITheme.scale_px(BASE_SCREEN_PADDING)
	pos.x = clampf(pos.x, screen_padding, viewport_size.x - panel_size.x - screen_padding)
	pos.y = clampf(pos.y, screen_padding, viewport_size.y - panel_size.y - screen_padding)

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
func add_stat_row(container: VBoxContainer, label_text: String, value_text: String, value_color: Color = Color.WHITE) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.SEPARATION_SMALL)
	container.add_child(row)

	var label := Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	value.add_theme_color_override("font_color", value_color if value_color != Color.WHITE else UITheme.COLOR_SELECTED)
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
