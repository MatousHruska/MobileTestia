extends CharacterMenuPopup
class_name StatPopup
## StatPopup - Shows stat/attribute details in a popup at tap position

#===============================================================================
# CONSTANTS
#===============================================================================

const POPUP_WIDTH := 260
const POPUP_MIN_HEIGHT_PCT := 0.15  # 15% of viewport
const POPUP_MAX_HEIGHT_PCT := 0.50  # 50% of viewport

## Colors
const COLOR_TITLE := Color(1.0, 0.9, 0.6)
const COLOR_VALUE := Color(0.9, 0.9, 0.9)
const COLOR_DESCRIPTION := Color(0.8, 0.8, 0.8)

#===============================================================================
# STATE
#===============================================================================

var current_stat_name: String = ""
var current_stat_value: String = ""
var _is_hold_mode: bool = false

#===============================================================================
# UI REFERENCES
#===============================================================================

var _title_label: Label
var _value_label: Label
var _description_label: Label


#===============================================================================
# OVERRIDES
#===============================================================================

func _get_popup_width() -> int:
	return POPUP_WIDTH


func _get_popup_min_height_pct() -> float:
	return POPUP_MIN_HEIGHT_PCT


func _get_popup_max_height_pct() -> float:
	return POPUP_MAX_HEIGHT_PCT


func _has_icon() -> bool:
	return false  # Stats don't need icons


func _build_header_content() -> VBoxContainer:
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	name_col.add_child(_title_label)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 13)
	_value_label.add_theme_color_override("font_color", COLOR_VALUE)
	name_col.add_child(_value_label)

	return name_col


func _build_content(content: VBoxContainer) -> void:
	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.add_theme_font_size_override("font_size", 12)
	_description_label.add_theme_color_override("font_color", COLOR_DESCRIPTION)
	content.add_child(_description_label)


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup for a stat (tap mode - stays open until dismissed)
func show_stat(stat_name: String, stat_value: String, description: String, screen_pos: Vector2) -> void:
	_is_hold_mode = false
	_show_internal(stat_name, stat_value, description, screen_pos)


## Show popup for a stat (hold mode - closes when released)
func show_stat_hold(stat_name: String, stat_value: String, description: String, screen_pos: Vector2) -> void:
	_is_hold_mode = true
	_show_internal(stat_name, stat_value, description, screen_pos)


func _show_internal(stat_name: String, stat_value: String, description: String, screen_pos: Vector2) -> void:
	current_stat_name = stat_name
	current_stat_value = stat_value

	# Update display
	_title_label.text = _format_stat_name(stat_name)
	_value_label.text = stat_value if not stat_value.is_empty() else ""
	_value_label.visible = not stat_value.is_empty()
	_description_label.text = description

	# In hold mode, hide close button and dim less
	_close_button.visible = not _is_hold_mode
	_background.color = Color(0, 0, 0, 0.2) if _is_hold_mode else Color(0, 0, 0, DIMMER_ALPHA)

	show_at(screen_pos)


## Called when hold is released - closes popup if in hold mode
func release_hold() -> void:
	if _is_hold_mode and visible:
		close()


## Check if popup is currently showing in hold mode
func is_hold_mode() -> bool:
	return _is_hold_mode and visible


## Override close to clear state
func close() -> void:
	current_stat_name = ""
	current_stat_value = ""
	_is_hold_mode = false
	super.close()


#===============================================================================
# INPUT HANDLING - Override for hold mode
#===============================================================================

func _on_background_input(event: InputEvent) -> void:
	# In hold mode, don't close on dimmer click (will close on release)
	if _is_hold_mode:
		return
	super._on_background_input(event)


#===============================================================================
# HELPERS
#===============================================================================

func _format_stat_name(stat_name: String) -> String:
	return stat_name.capitalize().replace("_", " ")
