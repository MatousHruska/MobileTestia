extends Node
class_name ResponsiveUIManager
## ResponsiveUI - Singleton providing screen size utilities for responsive UI
##
## Provides:
## - Screen size category detection (small/normal/large)
## - Scale factor calculation based on viewport
## - Panel size constraints for modal dialogs
## - Utility functions for responsive layouts

## Screen size categories
enum ScreenCategory { SMALL, NORMAL, LARGE }

## Base design dimensions (480x270 pixel art viewport)
const BASE_WIDTH := 480.0
const BASE_HEIGHT := 270.0

## Scale limits (1.0 = native, higher = larger displays)
const MIN_SCALE := 1.0
const MAX_SCALE := 4.0

## Cached values (updated on resize)
var viewport_size: Vector2 = Vector2(BASE_WIDTH, BASE_HEIGHT)
var scale_factor: float = 1.0
var screen_category: ScreenCategory = ScreenCategory.NORMAL

## Signals
signal viewport_changed(new_size: Vector2, new_scale: float)


func _ready() -> void:
	_update_viewport_info()
	get_viewport().size_changed.connect(_on_viewport_resized)
	Debug.info("UI", "ResponsiveUI initialized", {"scale": scale_factor, "category": ScreenCategory.keys()[screen_category]})


func _on_viewport_resized() -> void:
	_update_viewport_info()
	viewport_changed.emit(viewport_size, scale_factor)


func _update_viewport_info() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	# Set to 1.0 for now - no automatic scaling, elements sized for native resolution
	scale_factor = 1.0

	# Determine screen category (based on 270p base)
	if viewport_size.y < 270:
		screen_category = ScreenCategory.SMALL
	elif viewport_size.y > 540:
		screen_category = ScreenCategory.LARGE
	else:
		screen_category = ScreenCategory.NORMAL


#region Panel Size Utilities

## Get constrained panel size for modal dialogs
## Design sizes are assumed to be for 270p base resolution and will be scaled up
## Ensures panel fits on screen with margins while respecting scaled design size
func get_constrained_panel_size(design_size: Vector2, margin_pct: float = 0.05) -> Vector2:
	# Scale design size for native resolution
	var scaled_size := design_size * scale_factor

	var max_width := viewport_size.x * (1.0 - margin_pct * 2)
	var max_height := viewport_size.y * (1.0 - margin_pct * 2)

	return Vector2(
		minf(scaled_size.x, max_width),
		minf(scaled_size.y, max_height)
	)


## Check if panel needs constraining (viewport too small for scaled design)
func panel_needs_constraining(design_size: Vector2, margin_pct: float = 0.05) -> bool:
	var scaled_size := design_size * scale_factor
	var max_width := viewport_size.x * (1.0 - margin_pct * 2)
	var max_height := viewport_size.y * (1.0 - margin_pct * 2)
	return scaled_size.x > max_width or scaled_size.y > max_height


## Apply size constraints to a centered panel (modifies offsets)
## Design dimensions are for 270p base and will be scaled automatically
func constrain_centered_panel(panel: Control, design_width: float, design_height: float, margin_pct: float = 0.05) -> void:
	var constrained := get_constrained_panel_size(Vector2(design_width, design_height), margin_pct)
	var half_width := constrained.x / 2.0
	var half_height := constrained.y / 2.0

	panel.offset_left = -half_width
	panel.offset_right = half_width
	panel.offset_top = -half_height
	panel.offset_bottom = half_height

#endregion


#region Scaling Utilities

## Scale a pixel value based on current scale factor
func scale_px(value: float) -> float:
	return value * scale_factor


## Scale a Vector2 based on current scale factor
func scale_size(value: Vector2) -> Vector2:
	return value * scale_factor


## Get a font size scaled for current screen
func get_scaled_font_size(base_size: int) -> int:
	return maxi(10, int(base_size * scale_factor))


## Check if we're on a small screen
func is_small_screen() -> bool:
	return screen_category == ScreenCategory.SMALL


## Check if we're on a large screen
func is_large_screen() -> bool:
	return screen_category == ScreenCategory.LARGE

#endregion
