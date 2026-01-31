extends Resource
class_name PlayerFrameConfig
## PlayerFrameConfig - Configuration resource for PlayerFrame layout
##
## Structure:
##   PlayerFrame
##   ├── Background (ColorRect)
##   └── BarsContainer (VBoxContainer)
##       ├── HealthBar (ProgressBar + Label)
##       ├── ManaBar (ProgressBar + Label)
##       ├── StaminaBar (ProgressBar + Label)
##       ├── LevelLabel
##       └── StatusEffectDisplay
##
## Uses percentage-based positioning for multi-device support
## All anchor values are percentages (0.0 to 1.0) from top-left corner

#region Position and Size
@export_group("Position and Size")
## Anchor point for PlayerFrame top-left corner, as percentage from top-left corner
@export var anchor_pct: Vector2 = Vector2(0.01, 0.01)
## Size of PlayerFrame as percentage of screen dimensions (width%, height%)
@export var size_pct: Vector2 = Vector2(0.20, 0.20)
#endregion

#region Visual Style
@export_group("Visual Style")
## Background panel color
@export var background_color: Color = Color(0.08, 0.08, 0.12, 0.85)
## Corner radius as percentage of frame height
@export var corner_radius_pct: float = 0.05
## Padding inside frame as percentage of frame size
@export var padding_pct: float = 0.08
#endregion

#region Resource Bars
@export_group("Resource Bars")
## Bar height as percentage of frame height
@export var bar_height_pct: float = 0.14
## Gap between bars as percentage of frame height
@export var bar_gap_pct: float = 0.04
## Bar corner radius as percentage of bar height
@export var bar_corner_radius_pct: float = 0.3

## Health bar colors
@export var health_fill_color: Color = Color(0.8, 0.2, 0.2)
@export var health_bg_color: Color = Color(0.4, 0.1, 0.1)

## Mana bar colors
@export var mana_fill_color: Color = Color(0.2, 0.4, 0.9)
@export var mana_bg_color: Color = Color(0.1, 0.2, 0.45)

## Stamina bar colors
@export var stamina_fill_color: Color = Color(0.2, 0.7, 0.3)
@export var stamina_bg_color: Color = Color(0.1, 0.35, 0.15)
#endregion

#region Text
@export_group("Text")
## Font size as percentage of bar height
@export var bar_font_size_pct: float = 0.7
## Bar text color
@export var bar_text_color: Color = Color(1.0, 1.0, 1.0)
## Bar text shadow color
@export var bar_text_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.5)
#endregion

#region Status Effects
@export_group("Status Effects")
## Status effect icon size as percentage of frame height (40% larger than original)
@export var status_icon_size_pct: float = 0.21
#endregion


## Get PlayerFrame position in screen coordinates
func get_position(screen_size: Vector2) -> Vector2:
	return Vector2(
		anchor_pct.x * screen_size.x,
		anchor_pct.y * screen_size.y
	)


## Get PlayerFrame size in screen coordinates
func get_size(screen_size: Vector2) -> Vector2:
	return Vector2(
		size_pct.x * screen_size.x,
		size_pct.y * screen_size.y
	)


## Get padding in pixels based on frame size
func get_padding(frame_size: Vector2) -> float:
	return padding_pct * min(frame_size.x, frame_size.y)


## Get bar height in pixels based on frame height
func get_bar_height(frame_height: float) -> float:
	return bar_height_pct * frame_height


## Get bar gap in pixels based on frame height
func get_bar_gap(frame_height: float) -> float:
	return bar_gap_pct * frame_height


## Get bar corner radius in pixels
func get_bar_corner_radius(bar_height: float) -> int:
	return int(bar_corner_radius_pct * bar_height)


## Get corner radius in pixels based on frame height
func get_corner_radius(frame_height: float) -> int:
	return int(corner_radius_pct * frame_height)


## Get bar font size in pixels
func get_bar_font_size(bar_height: float) -> int:
	return int(bar_font_size_pct * bar_height)


## Get status effect icon size in pixels
func get_status_icon_size(frame_height: float) -> float:
	return status_icon_size_pct * frame_height
