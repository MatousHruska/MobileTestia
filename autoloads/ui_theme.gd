extends Node
## Global UI theme loaded from database
## Use this singleton to maintain consistent styling across the entire game UI
## Access via the 'UITheme' autoload singleton
## Press R to reload theme dynamically for live editing

## Emitted when theme is reloaded via F6 (UI can connect to refresh)
signal theme_reloaded

const DATABASE_PATH := "res://databases/exports/ui_theme.json"

#===============================================================================
# UI SCALE - Dynamic scaling for responsive UI across screen sizes
#===============================================================================
# Base design resolution (element sizes defined for this resolution)
const BASE_DESIGN_WIDTH: float = 1280.0
const BASE_DESIGN_HEIGHT: float = 720.0

# Current scale factor (calculated dynamically based on screen size)
# ui_scale = viewport_height / BASE_DESIGN_HEIGHT
var ui_scale: float = 1.0

# Cached screen size for change detection
var _cached_screen_size: Vector2i = Vector2i.ZERO

# Cached viewport size for percentage calculations
var _viewport_size: Vector2 = Vector2(1280, 720)

#===============================================================================
# INTERNAL DATA
#===============================================================================

var _settings: Dictionary = {}
var _color_cache: Dictionary = {}

#===============================================================================
# DEFAULT VALUES (fallbacks if database missing)
#===============================================================================

const DEFAULTS := {
	# Panel backgrounds
	"color_panel_bg": "0.12,0.12,0.14,0.9",
	"color_panel_dark_bg": "0.1,0.1,0.12,0.9",
	"color_panel_border": "0.3,0.3,0.35,1.0",
	# Popup colors
	"color_popup_bg": "0.1,0.1,0.12,0.95",
	"color_popup_border": "0.4,0.4,0.45,1.0",
	# Button/slot backgrounds
	"color_button_bg": "0.2,0.2,0.25,0.8",
	"color_button_bg_active": "0.25,0.3,0.4,0.9",
	"color_button_bg_dark": "0.15,0.15,0.2,1.0",
	# Empty slot
	"color_empty_slot_bg": "0.1,0.1,0.12,0.5",
	"color_empty_slot_border": "0.3,0.3,0.35,0.5",
	# Tab colors
	"color_tab_bg": "0.15,0.15,0.18,1.0",
	"color_tab_bg_active": "0.25,0.25,0.3,1.0",
	"color_tab_border": "0.4,0.4,0.45,1.0",
	# State colors
	"color_locked": "0.4,0.4,0.4,1.0",
	"color_available": "1.0,0.85,0.3,1.0",
	"color_learned": "0.5,1.0,0.5,1.0",
	"color_maxed": "0.3,0.8,1.0,1.0",
	"color_selected": "1.0,1.0,1.0,1.0",
	"color_highlight": "0.55,1.0,0.98,1.0",
	# Text colors
	"color_gold": "1.0,0.85,0.0,1.0",
	"color_text_dim": "0.7,0.7,0.7,1.0",
	"color_section_header": "1.0,0.85,0.3,1.0",
	# Text hierarchy colors
	"color_text_nav": "1.0,1.0,1.0,1.0",
	"color_text_header": "0.85,0.85,0.85,1.0",
	"color_text_label": "0.65,0.65,0.65,1.0",
	"color_text_value": "0.9,0.9,0.9,1.0",
	# Progress/resource bar colors
	"color_xp_bar": "0.3,0.6,0.9,1.0",
	"color_debuff": "0.6,0.1,0.1,0.9",
	"color_drag_highlight": "0.5,1.0,0.5,1.0",
	# Resource colors (for stats, costs, etc.)
	"color_life": "0.9,0.3,0.3,1.0",
	"color_mana": "0.4,0.6,1.0,1.0",
	"color_stamina": "0.4,1.0,0.6,1.0",
	"color_requirement_unmet": "1.0,0.4,0.4,1.0",
	# Font sizes (native 720p pixel values, no scaling)
	"font_size_title": 22,
	"font_size_large": 20,
	"font_size_header": 18,
	"font_size_label": 16,
	"font_size_small": 14,
	"font_size_tiny": 12,
	# Margins (native 720p pixel values)
	"margin_standard": 10,
	"margin_small": 8,
	"margin_tiny": 6,
	# Border widths
	"border_width_normal": 1,
	"border_width_thick": 2,
	"border_width_selected": 2,
	# Corner radii
	"corner_radius_normal": 6,
	"corner_radius_small": 4,
	"corner_radius_popup": 8,
	# Separations
	"separation_normal": 10,
	"separation_small": 6,
	"separation_tiny": 4,
	"separation_grid": 6,
	# Element sizes (native 720p pixel values)
	"button_height_small": 21,
	"button_height_normal": 29,
	"button_height_large": 36,
	"button_width_small": 62,
	"button_width_normal": 94,
	"button_width_large": 130,
	"icon_size_small": 20,
	"icon_size_normal": 31,
	"icon_size_large": 47,
	"slot_size_small": 52,
	"slot_size_normal": 56,
	"slot_size_large": 64,
	"bar_height_thin": 5,
	"bar_height_normal": 10,
	"bar_height_thick": 16,
	"min_touch_target": 36,
	"popup_width_small": 200,
	"popup_width_normal": 280,
	"popup_width_large": 390,
	"label_width_small": 24,
	"label_width_normal": 31,
	"label_width_large": 47,
	"row_height_normal": 26,
	"row_height_large": 36,
	# Additional element sizes
	"close_button_size": 36,
	"status_effect_icon_size": 32,
	"scroll_min_height": 40,
	"popup_height_small": 150,
	"popup_height_normal": 200,
	"popup_height_large": 300,
	"padding_element_small": 2,
	"padding_element_medium": 4,
	"quest_item_min_height": 24,
	"quest_desc_min_height": 40,
	# Popup base widths (720p base, scaled by ui_scale)
	"popup_stat_base_width": 260,
	"popup_skill_base_width": 100,
	"popup_item_base_width": 100,
	# Menu/panel sizes (as percentage of viewport)
	"menu_width_pct": 0.65,      # 65% of viewport width
	"menu_height_pct": 0.90,     # 90% of viewport height
	"save_panel_width_pct": 0.30,  # 30% of viewport width
	"save_panel_height_pct": 0.58, # 58% of viewport height
	# Cast bar
	"color_cast_bar_bg": "0.1,0.1,0.12,0.9",
	"color_cast_bar_fill": "0.8,0.6,0.2,1.0",
	"color_cast_bar_border": "0.4,0.4,0.45,1.0",
	"color_cast_bar_text": "1.0,1.0,1.0,1.0",
	"color_cast_bar_interrupted": "0.8,0.2,0.2,1.0",
	"cast_bar_height": 20,
	"cast_bar_width": 120,
	"cast_bar_y_percent": 0.38,
	# Enemy health bar settings (dimensions as % of enemy size, minimums in pixels)
	"enemy_health_bar_height_percent": 0.25,
	"enemy_health_bar_width_percent": 1.0,
	"enemy_health_bar_y_offset_percent": -0.35,
	"enemy_health_bar_corner_radius_percent": 0.3,
	"enemy_health_bar_min_height": 4,
	"enemy_health_bar_min_width": 20,
	"color_enemy_health_bg": "0.1,0.1,0.12,0.9",
	"color_enemy_health_fill": "0.8,0.2,0.2,1.0",
	"color_enemy_health_border": "0.3,0.3,0.35,0.8",
	"color_enemy_health_damage": "0.95,0.5,0.5,1.0",
	"color_enemy_shield_fill": "0.3,0.7,0.9,0.9",
	"color_enemy_dot_fire": "1.0,0.4,0.1,0.6",
	"color_enemy_dot_poison": "0.3,0.8,0.2,0.6",
	"color_enemy_dot_bleed": "0.8,0.1,0.1,0.6",
	"color_enemy_dot_cold": "0.3,0.7,1.0,0.6",
	"color_enemy_dot_generic": "0.7,0.5,0.3,0.6",
	"enemy_health_bar_lerp_speed": 12.0,
	"enemy_health_bar_dot_preview_alpha": 0.6,
	"enemy_health_bar_show_on_full": false,
	"enemy_health_bar_fade_delay": 2.0,
	"enemy_health_bar_boss_height_percent": 0.4,
	"enemy_health_bar_boss_show_name": true,
}

#===============================================================================
# INITIALIZATION
#===============================================================================

func _ready() -> void:
	_load_theme_settings()
	_update_scale_factor()
	# Connect to screen resize
	get_tree().root.size_changed.connect(_on_screen_resized)


func _unhandled_input(event: InputEvent) -> void:
	# R to reload theme database (for live editing)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reload_theme()
		get_viewport().set_input_as_handled()


## Reload theme from database without restarting (for live editing)
func reload_theme() -> void:
	Debug.info("UITheme", "=== RELOADING THEME ===")

	# Clear color cache
	_color_cache.clear()

	# Reload from JSON
	_load_theme_settings()

	# Log some key values to verify
	Debug.info("UITheme", "slot_size_small: %s" % _settings.get("slot_size_small", "NOT FOUND"))
	Debug.info("UITheme", "slot_size_normal: %s" % _settings.get("slot_size_normal", "NOT FOUND"))
	Debug.info("UITheme", "font_size_label: %s" % _settings.get("font_size_label", "NOT FOUND"))
	Debug.info("UITheme", "button_height_normal: %s" % _settings.get("button_height_normal", "NOT FOUND"))
	Debug.info("UITheme", "=== THEME RELOADED (ui_scale: %.2f) ===" % ui_scale)

	# Emit signal so UI can refresh if needed
	theme_reloaded.emit()


func _on_screen_resized() -> void:
	_update_scale_factor()


func _update_scale_factor() -> void:
	## Calculate UI scale based on current screen size
	var screen_size := get_tree().root.size
	if screen_size == _cached_screen_size:
		return

	_cached_screen_size = screen_size
	_viewport_size = Vector2(screen_size)

	# Calculate scale factor based on viewport height relative to base design
	# This ensures UI elements scale proportionally across different resolutions
	ui_scale = maxf(0.5, _viewport_size.y / BASE_DESIGN_HEIGHT)

	Debug.log("UITheme", "UI scale updated: %.2f (screen: %s)" % [ui_scale, screen_size])


func _load_theme_settings() -> void:
	Debug.info("UITheme", "=== LOADING THEME SETTINGS ===")
	Debug.info("UITheme", "Database path: %s" % DATABASE_PATH)

	if not FileAccess.file_exists(DATABASE_PATH):
		Debug.warn("UITheme", "ui_theme.json not found (using defaults)")
		_settings = DEFAULTS.duplicate()
		return

	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if not file:
		Debug.warn("UITheme", "Failed to open ui_theme.json (using defaults)")
		_settings = DEFAULTS.duplicate()
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		Debug.warn("UITheme", "JSON parse error: %s (using defaults)" % json.get_error_message())
		_settings = DEFAULTS.duplicate()
		return

	_settings = json.data
	Debug.info("UITheme", "Loaded %d theme settings from JSON" % _settings.size())
	# Log key values to verify database is being read correctly
	Debug.info("UITheme", "  slot_size_small: %s (default: %s)" % [_settings.get("slot_size_small", "MISSING"), DEFAULTS.get("slot_size_small")])
	Debug.info("UITheme", "  slot_size_normal: %s (default: %s)" % [_settings.get("slot_size_normal", "MISSING"), DEFAULTS.get("slot_size_normal")])
	Debug.info("UITheme", "  font_size_label: %s (default: %s)" % [_settings.get("font_size_label", "MISSING"), DEFAULTS.get("font_size_label")])
	Debug.info("UITheme", "=== THEME SETTINGS LOADED ===")


#===============================================================================
# VALUE GETTERS
#===============================================================================

## Get a color value from theme
func get_color(key: String) -> Color:
	if _color_cache.has(key):
		return _color_cache[key]

	var color_str: String = _settings.get(key, DEFAULTS.get(key, "1,1,1,1"))
	var parts := color_str.split(",")
	var color := Color(
		float(parts[0]) if parts.size() > 0 else 1.0,
		float(parts[1]) if parts.size() > 1 else 1.0,
		float(parts[2]) if parts.size() > 2 else 1.0,
		float(parts[3]) if parts.size() > 3 else 1.0
	)
	_color_cache[key] = color
	return color


## Get an integer value from theme (raw, unscaled)
func get_int_raw(key: String) -> int:
	return int(_settings.get(key, DEFAULTS.get(key, 0)))


## Get an integer value from theme, scaled for current viewport
## Used for: font sizes, margins, border widths, corner radii, separations
func get_int(key: String) -> int:
	var raw := int(_settings.get(key, DEFAULTS.get(key, 0)))
	# Apply dynamic scale to pixel-based values for native resolution rendering
	if key.begins_with("font_size") or key.begins_with("margin") or \
	   key.begins_with("border") or key.begins_with("corner") or \
	   key.begins_with("separation") or key.ends_with("_height") or \
	   key.ends_with("_width"):
		return maxi(1, int(raw * ui_scale))
	return raw


## Get a float value from theme
func get_float(key: String) -> float:
	return float(_settings.get(key, DEFAULTS.get(key, 0.0)))


## Scale a pixel value for native resolution rendering
## Use this for custom_minimum_size, offsets, and other hardcoded pixel values
func scale_px(value: float) -> float:
	return value * ui_scale


## Scale a pixel value and return as integer
func scale_px_i(value: int) -> int:
	return maxi(1, int(value * ui_scale))


## Get an integer value from theme, explicitly scaled by ui_scale
## Used for element sizes (buttons, icons, slots, etc.)
func _scaled_int(key: String) -> int:
	var raw := int(_settings.get(key, DEFAULTS.get(key, 0)))
	return maxi(1, int(raw * ui_scale))


## Scale a Vector2 for native resolution rendering
func scale_size(size: Vector2) -> Vector2:
	return size * ui_scale


#===============================================================================
# COLOR PROPERTIES (for easy access)
#===============================================================================

var COLOR_PANEL_BG: Color:
	get: return get_color("color_panel_bg")

var COLOR_PANEL_DARK_BG: Color:
	get: return get_color("color_panel_dark_bg")

var COLOR_PANEL_BORDER: Color:
	get: return get_color("color_panel_border")

var COLOR_POPUP_BG: Color:
	get: return get_color("color_popup_bg")

var COLOR_POPUP_BORDER: Color:
	get: return get_color("color_popup_border")

var COLOR_BUTTON_BG: Color:
	get: return get_color("color_button_bg")

var COLOR_BUTTON_BG_ACTIVE: Color:
	get: return get_color("color_button_bg_active")

var COLOR_BUTTON_BG_DARK: Color:
	get: return get_color("color_button_bg_dark")

var COLOR_EMPTY_SLOT_BG: Color:
	get: return get_color("color_empty_slot_bg")

var COLOR_EMPTY_SLOT_BORDER: Color:
	get: return get_color("color_empty_slot_border")

var COLOR_TAB_BG: Color:
	get: return get_color("color_tab_bg")

var COLOR_TAB_BG_ACTIVE: Color:
	get: return get_color("color_tab_bg_active")

var COLOR_TAB_BORDER: Color:
	get: return get_color("color_tab_border")

var COLOR_LOCKED: Color:
	get: return get_color("color_locked")

var COLOR_AVAILABLE: Color:
	get: return get_color("color_available")

var COLOR_LEARNED: Color:
	get: return get_color("color_learned")

var COLOR_MAXED: Color:
	get: return get_color("color_maxed")

var COLOR_SELECTED: Color:
	get: return get_color("color_selected")

var COLOR_HIGHLIGHT: Color:
	get: return get_color("color_highlight")

var COLOR_GOLD: Color:
	get: return get_color("color_gold")

var COLOR_TEXT_DIM: Color:
	get: return get_color("color_text_dim")

var COLOR_SECTION_HEADER: Color:
	get: return get_color("color_section_header")

var COLOR_TEXT_NAV: Color:
	get: return get_color("color_text_nav")

var COLOR_TEXT_HEADER: Color:
	get: return get_color("color_text_header")

var COLOR_TEXT_LABEL: Color:
	get: return get_color("color_text_label")

var COLOR_TEXT_VALUE: Color:
	get: return get_color("color_text_value")

var COLOR_XP_BAR: Color:
	get: return get_color("color_xp_bar")

var COLOR_DEBUFF: Color:
	get: return get_color("color_debuff")

var COLOR_DRAG_HIGHLIGHT: Color:
	get: return get_color("color_drag_highlight")

var COLOR_LIFE: Color:
	get: return get_color("color_life")

var COLOR_MANA: Color:
	get: return get_color("color_mana")

var COLOR_STAMINA: Color:
	get: return get_color("color_stamina")

var COLOR_REQUIREMENT_UNMET: Color:
	get: return get_color("color_requirement_unmet")

#===============================================================================
# SIZE PROPERTIES
#===============================================================================

var FONT_SIZE_TITLE: int:
	get: return get_int("font_size_title")

var FONT_SIZE_LARGE: int:
	get: return get_int("font_size_large")

var FONT_SIZE_HEADER: int:
	get: return get_int("font_size_header")

var FONT_SIZE_LABEL: int:
	get: return get_int("font_size_label")

var FONT_SIZE_SMALL: int:
	get: return get_int("font_size_small")

var FONT_SIZE_TINY: int:
	get: return get_int("font_size_tiny")

var MARGIN_STANDARD: int:
	get: return get_int("margin_standard")

var MARGIN_SMALL: int:
	get: return get_int("margin_small")

var MARGIN_TINY: int:
	get: return get_int("margin_tiny")

var BORDER_WIDTH_NORMAL: int:
	get: return get_int("border_width_normal")

var BORDER_WIDTH_THICK: int:
	get: return get_int("border_width_thick")

var BORDER_WIDTH_SELECTED: int:
	get: return get_int("border_width_selected")

var CORNER_RADIUS_NORMAL: int:
	get: return get_int("corner_radius_normal")

var CORNER_RADIUS_SMALL: int:
	get: return get_int("corner_radius_small")

var CORNER_RADIUS_POPUP: int:
	get: return get_int("corner_radius_popup")

var SEPARATION_NORMAL: int:
	get: return get_int("separation_normal")

var SEPARATION_SMALL: int:
	get: return get_int("separation_small")

var SEPARATION_TINY: int:
	get: return get_int("separation_tiny")

var SEPARATION_GRID: int:
	get: return get_int("separation_grid")

#===============================================================================
# ELEMENT SIZE PROPERTIES (base values × ui_scale for responsive sizing)
#===============================================================================

var BUTTON_HEIGHT_SMALL: int:
	get: return _scaled_int("button_height_small")

var BUTTON_HEIGHT_NORMAL: int:
	get: return _scaled_int("button_height_normal")

var BUTTON_HEIGHT_LARGE: int:
	get: return _scaled_int("button_height_large")

var BUTTON_WIDTH_SMALL: int:
	get: return _scaled_int("button_width_small")

var BUTTON_WIDTH_NORMAL: int:
	get: return _scaled_int("button_width_normal")

var BUTTON_WIDTH_LARGE: int:
	get: return _scaled_int("button_width_large")

var ICON_SIZE_SMALL: int:
	get: return _scaled_int("icon_size_small")

var ICON_SIZE_NORMAL: int:
	get: return _scaled_int("icon_size_normal")

var ICON_SIZE_LARGE: int:
	get: return _scaled_int("icon_size_large")

var SLOT_SIZE_SMALL: int:
	get: return _scaled_int("slot_size_small")

var SLOT_SIZE_NORMAL: int:
	get: return _scaled_int("slot_size_normal")

var SLOT_SIZE_LARGE: int:
	get: return _scaled_int("slot_size_large")

var BAR_HEIGHT_THIN: int:
	get: return _scaled_int("bar_height_thin")

var BAR_HEIGHT_NORMAL: int:
	get: return _scaled_int("bar_height_normal")

var BAR_HEIGHT_THICK: int:
	get: return _scaled_int("bar_height_thick")

var MIN_TOUCH_TARGET: int:
	get: return _scaled_int("min_touch_target")

var POPUP_WIDTH_SMALL: int:
	get: return _scaled_int("popup_width_small")

var POPUP_WIDTH_NORMAL: int:
	get: return _scaled_int("popup_width_normal")

var POPUP_WIDTH_LARGE: int:
	get: return _scaled_int("popup_width_large")

var LABEL_WIDTH_SMALL: int:
	get: return _scaled_int("label_width_small")

var LABEL_WIDTH_NORMAL: int:
	get: return _scaled_int("label_width_normal")

var LABEL_WIDTH_LARGE: int:
	get: return _scaled_int("label_width_large")

var ROW_HEIGHT_NORMAL: int:
	get: return _scaled_int("row_height_normal")

var ROW_HEIGHT_LARGE: int:
	get: return _scaled_int("row_height_large")

var CLOSE_BUTTON_SIZE: int:
	get: return _scaled_int("close_button_size")

var STATUS_EFFECT_ICON_SIZE: int:
	get: return _scaled_int("status_effect_icon_size")

var SCROLL_MIN_HEIGHT: int:
	get: return _scaled_int("scroll_min_height")

var POPUP_HEIGHT_SMALL: int:
	get: return _scaled_int("popup_height_small")

var POPUP_HEIGHT_NORMAL: int:
	get: return _scaled_int("popup_height_normal")

var POPUP_HEIGHT_LARGE: int:
	get: return _scaled_int("popup_height_large")

var PADDING_ELEMENT_SMALL: int:
	get: return _scaled_int("padding_element_small")

var PADDING_ELEMENT_MEDIUM: int:
	get: return _scaled_int("padding_element_medium")

var QUEST_ITEM_MIN_HEIGHT: int:
	get: return _scaled_int("quest_item_min_height")

var QUEST_DESC_MIN_HEIGHT: int:
	get: return _scaled_int("quest_desc_min_height")

var POPUP_STAT_BASE_WIDTH: int:
	get: return _scaled_int("popup_stat_base_width")

var POPUP_SKILL_BASE_WIDTH: int:
	get: return _scaled_int("popup_skill_base_width")

var POPUP_ITEM_BASE_WIDTH: int:
	get: return _scaled_int("popup_item_base_width")

#===============================================================================
# MENU/PANEL SIZE PROPERTIES (percentage-based, returns actual pixels)
#===============================================================================

var MENU_WIDTH: int:
	get: return int(_viewport_size.x * get_float("menu_width_pct"))

var MENU_HEIGHT: int:
	get: return int(_viewport_size.y * get_float("menu_height_pct"))

var SAVE_PANEL_WIDTH: int:
	get: return int(_viewport_size.x * get_float("save_panel_width_pct"))

var SAVE_PANEL_HEIGHT: int:
	get: return int(_viewport_size.y * get_float("save_panel_height_pct"))


#===============================================================================
# CAST BAR PROPERTIES
#===============================================================================

var COLOR_CAST_BAR_BG: Color:
	get: return get_color("color_cast_bar_bg")

var COLOR_CAST_BAR_FILL: Color:
	get: return get_color("color_cast_bar_fill")

var COLOR_CAST_BAR_BORDER: Color:
	get: return get_color("color_cast_bar_border")

var COLOR_CAST_BAR_TEXT: Color:
	get: return get_color("color_cast_bar_text")

var COLOR_CAST_BAR_INTERRUPTED: Color:
	get: return get_color("color_cast_bar_interrupted")

var CAST_BAR_HEIGHT: int:
	get: return get_int("cast_bar_height")

var CAST_BAR_WIDTH: int:
	get: return get_int("cast_bar_width")

var CAST_BAR_Y_PERCENT: float:
	get: return get_float("cast_bar_y_percent")


#===============================================================================
# ENEMY HEALTH BAR PROPERTIES (percentage-based for scaling)
#===============================================================================

var ENEMY_HEALTH_BAR_HEIGHT_PERCENT: float:
	get: return get_float("enemy_health_bar_height_percent")

var ENEMY_HEALTH_BAR_WIDTH_PERCENT: float:
	get: return get_float("enemy_health_bar_width_percent")

var ENEMY_HEALTH_BAR_Y_OFFSET_PERCENT: float:
	get: return get_float("enemy_health_bar_y_offset_percent")

var ENEMY_HEALTH_BAR_CORNER_RADIUS_PERCENT: float:
	get: return get_float("enemy_health_bar_corner_radius_percent")

var ENEMY_HEALTH_BAR_MIN_HEIGHT: int:
	get: return get_int("enemy_health_bar_min_height")

var ENEMY_HEALTH_BAR_MIN_WIDTH: int:
	get: return get_int("enemy_health_bar_min_width")

var COLOR_ENEMY_HEALTH_BG: Color:
	get: return get_color("color_enemy_health_bg")

var COLOR_ENEMY_HEALTH_FILL: Color:
	get: return get_color("color_enemy_health_fill")

var COLOR_ENEMY_HEALTH_BORDER: Color:
	get: return get_color("color_enemy_health_border")

var COLOR_ENEMY_HEALTH_DAMAGE: Color:
	get: return get_color("color_enemy_health_damage")

var COLOR_ENEMY_SHIELD_FILL: Color:
	get: return get_color("color_enemy_shield_fill")

var COLOR_ENEMY_DOT_FIRE: Color:
	get: return get_color("color_enemy_dot_fire")

var COLOR_ENEMY_DOT_POISON: Color:
	get: return get_color("color_enemy_dot_poison")

var COLOR_ENEMY_DOT_BLEED: Color:
	get: return get_color("color_enemy_dot_bleed")

var COLOR_ENEMY_DOT_COLD: Color:
	get: return get_color("color_enemy_dot_cold")

var COLOR_ENEMY_DOT_GENERIC: Color:
	get: return get_color("color_enemy_dot_generic")

var ENEMY_HEALTH_BAR_LERP_SPEED: float:
	get: return get_float("enemy_health_bar_lerp_speed")

var ENEMY_HEALTH_BAR_DOT_PREVIEW_ALPHA: float:
	get: return get_float("enemy_health_bar_dot_preview_alpha")

var ENEMY_HEALTH_BAR_SHOW_ON_FULL: bool:
	get: return get_int("enemy_health_bar_show_on_full") == 1

var ENEMY_HEALTH_BAR_FADE_DELAY: float:
	get: return get_float("enemy_health_bar_fade_delay")

var ENEMY_HEALTH_BAR_BOSS_HEIGHT_PERCENT: float:
	get: return get_float("enemy_health_bar_boss_height_percent")

var ENEMY_HEALTH_BAR_BOSS_SHOW_NAME: bool:
	get: return get_int("enemy_health_bar_boss_show_name") == 1


#===============================================================================
# STYLEBOX FACTORY METHODS
#===============================================================================

## Create standard content panel style (dark background with border)
func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create darker panel style (for sub-sections like points display)
func create_panel_dark_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_DARK_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style


## Create popup panel style
func create_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_BG
	style.border_color = COLOR_POPUP_BORDER
	style.set_border_width_all(BORDER_WIDTH_THICK)
	style.set_corner_radius_all(CORNER_RADIUS_POPUP)
	return style


## Create button/slot style
func create_button_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BUTTON_BG_ACTIVE if active else COLOR_BUTTON_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_THICK)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create empty slot style (semi-transparent)
func create_empty_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_EMPTY_SLOT_BG
	style.border_color = COLOR_EMPTY_SLOT_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create tab button style
func create_tab_style(pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TAB_BG_ACTIVE if pressed else COLOR_TAB_BG
	style.border_color = COLOR_AVAILABLE if pressed else COLOR_TAB_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style


#===============================================================================
# UI ELEMENT FACTORY METHODS
#===============================================================================

## Create a section header label (centered, font size 14, colored)
func create_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	label.add_theme_color_override("font_color", COLOR_TEXT_HEADER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Create a standard label (uses text_label color by default)
func create_label(text: String, font_size: int = -1) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size if font_size > 0 else FONT_SIZE_LABEL)
	label.add_theme_color_override("font_color", COLOR_TEXT_LABEL)
	return label


## Create a value label (for displaying stat values, numbers, item names)
func create_value_label(text: String, font_size: int = -1) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size if font_size > 0 else FONT_SIZE_LABEL)
	label.add_theme_color_override("font_color", COLOR_TEXT_VALUE)
	return label


## Create a margin container with standard margins
func create_margin_container(
	left: int = -1,
	right: int = -1,
	top: int = -1,
	bottom: int = -1
) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left if left >= 0 else MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_right", right if right >= 0 else MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_top", top if top >= 0 else MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_bottom", bottom if bottom >= 0 else MARGIN_STANDARD)
	return margin


## Create a styled panel container
func create_styled_panel(dark: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", create_panel_dark_style() if dark else create_panel_style())
	return panel


## Apply standard vbox separation
func setup_vbox(vbox: VBoxContainer, separation: int = -1) -> void:
	vbox.add_theme_constant_override("separation", separation if separation >= 0 else SEPARATION_NORMAL)


## Apply standard hbox separation
func setup_hbox(hbox: HBoxContainer, separation: int = -1) -> void:
	hbox.add_theme_constant_override("separation", separation if separation >= 0 else SEPARATION_NORMAL)


## Apply standard grid separation
func setup_grid(grid: GridContainer, h_sep: int = -1, v_sep: int = -1) -> void:
	grid.add_theme_constant_override("h_separation", h_sep if h_sep >= 0 else SEPARATION_GRID)
	grid.add_theme_constant_override("v_separation", v_sep if v_sep >= 0 else SEPARATION_GRID)
