class_name CharacterMenuTheme
## Shared UI theme constants and factory methods for Character Menu
## Use this class to maintain consistent styling across all Character Menu panels

#===============================================================================
# COLORS
#===============================================================================

## Panel backgrounds
const COLOR_PANEL_BG := Color(0.12, 0.12, 0.14, 0.9)
const COLOR_PANEL_DARK_BG := Color(0.1, 0.1, 0.12, 0.9)
const COLOR_PANEL_BORDER := Color(0.3, 0.3, 0.35)

## Popup colors
const COLOR_POPUP_BG := Color(0.1, 0.1, 0.12, 0.95)
const COLOR_POPUP_BORDER := Color(0.4, 0.4, 0.45)

## Button/slot backgrounds
const COLOR_BUTTON_BG := Color(0.2, 0.2, 0.25, 0.8)
const COLOR_BUTTON_BG_ACTIVE := Color(0.25, 0.3, 0.4, 0.9)
const COLOR_BUTTON_BG_DARK := Color(0.15, 0.15, 0.2)

## Empty slot background
const COLOR_EMPTY_SLOT_BG := Color(0.1, 0.1, 0.12, 0.5)
const COLOR_EMPTY_SLOT_BORDER := Color(0.3, 0.3, 0.35, 0.5)

## Tab colors
const COLOR_TAB_BG := Color(0.15, 0.15, 0.18)
const COLOR_TAB_BG_ACTIVE := Color(0.25, 0.25, 0.3)
const COLOR_TAB_BORDER := Color(0.4, 0.4, 0.45)

## State colors (for talents, skills, etc.)
const COLOR_LOCKED := Color(0.4, 0.4, 0.4)
const COLOR_AVAILABLE := Color(1.0, 0.85, 0.3)
const COLOR_LEARNED := Color(0.5, 1.0, 0.5)
const COLOR_MAXED := Color(0.3, 0.8, 1.0)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0)
const COLOR_HIGHLIGHT := Color(0.55, 1.0, 0.98)  ## Cyan highlight

## Text colors
const COLOR_GOLD := Color(1.0, 0.85, 0.0)
const COLOR_TEXT_DIM := Color(0.7, 0.7, 0.7)

#===============================================================================
# SIZING CONSTANTS
#===============================================================================

## Font sizes
const FONT_SIZE_HEADER := 14
const FONT_SIZE_LABEL := 12
const FONT_SIZE_SMALL := 10
const FONT_SIZE_TINY := 9

## Standard margins
const MARGIN_STANDARD := 8
const MARGIN_SMALL := 6
const MARGIN_TINY := 4

## Border widths
const BORDER_WIDTH_NORMAL := 1
const BORDER_WIDTH_THICK := 2
const BORDER_WIDTH_SELECTED := 3

## Corner radii
const CORNER_RADIUS_NORMAL := 4
const CORNER_RADIUS_SMALL := 3
const CORNER_RADIUS_POPUP := 6

## Separations
const SEPARATION_NORMAL := 8
const SEPARATION_SMALL := 4
const SEPARATION_GRID := 4

#===============================================================================
# STYLEBOX FACTORY METHODS
#===============================================================================

## Create standard content panel style (dark background with border)
static func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create darker panel style (for sub-sections like points display)
static func create_panel_dark_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_DARK_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style


## Create popup panel style
static func create_popup_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_BG
	style.border_color = COLOR_POPUP_BORDER
	style.set_border_width_all(BORDER_WIDTH_THICK)
	style.set_corner_radius_all(CORNER_RADIUS_POPUP)
	return style


## Create button/slot style
static func create_button_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BUTTON_BG_ACTIVE if active else COLOR_BUTTON_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(BORDER_WIDTH_THICK)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create empty slot style (semi-transparent)
static func create_empty_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_EMPTY_SLOT_BG
	style.border_color = COLOR_EMPTY_SLOT_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_NORMAL)
	return style


## Create tab button style
static func create_tab_style(pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TAB_BG_ACTIVE if pressed else COLOR_TAB_BG
	style.border_color = COLOR_AVAILABLE if pressed else COLOR_TAB_BORDER
	style.set_border_width_all(BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(CORNER_RADIUS_SMALL)
	return style


#===============================================================================
# UI ELEMENT FACTORY METHODS
#===============================================================================

## Create a section header label (centered, font size 14)
static func create_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE_HEADER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Create a standard label
static func create_label(text: String, font_size: int = FONT_SIZE_LABEL) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


## Create a margin container with standard margins
static func create_margin_container(
	left: int = MARGIN_STANDARD,
	right: int = MARGIN_STANDARD,
	top: int = MARGIN_STANDARD,
	bottom: int = MARGIN_STANDARD
) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


## Create a styled panel container
static func create_styled_panel(dark: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", create_panel_dark_style() if dark else create_panel_style())
	return panel


## Apply standard vbox separation
static func setup_vbox(vbox: VBoxContainer, separation: int = SEPARATION_NORMAL) -> void:
	vbox.add_theme_constant_override("separation", separation)


## Apply standard hbox separation
static func setup_hbox(hbox: HBoxContainer, separation: int = SEPARATION_NORMAL) -> void:
	hbox.add_theme_constant_override("separation", separation)


## Apply standard grid separation
static func setup_grid(grid: GridContainer, h_sep: int = SEPARATION_GRID, v_sep: int = SEPARATION_GRID) -> void:
	grid.add_theme_constant_override("h_separation", h_sep)
	grid.add_theme_constant_override("v_separation", v_sep)
