class_name NavigationDebugDrawer
extends Node2D
## NavigationDebugDrawer - Debug visualization for pathfinding
## Shows blocked tiles, active paths, and navigation bounds
## Supports multiple navigation layers with cycling (press L to cycle)

#===============================================================================
# CONSTANTS
#===============================================================================

## Color for blocked tiles
const COLOR_BLOCKED := Color(1.0, 0.2, 0.2, 0.3)

## Color for walkable tiles within bounds
const COLOR_WALKABLE := Color(0.2, 1.0, 0.2, 0.1)

## Color for navigation bounds
const COLOR_BOUNDS := Color(0.2, 0.6, 1.0, 0.5)

## Color for active paths
const COLOR_PATH := Color(1.0, 1.0, 0.0, 0.8)

## Tile size for drawing
const TILE_SIZE := 16

## Navigation layer colors for different layers
const LAYER_COLORS := {
	1: Color(0.2, 0.8, 0.2, 0.3),   # Ground - green
	2: Color(0.2, 0.6, 1.0, 0.3),   # Flying - blue
	4: Color(1.0, 0.8, 0.2, 0.3),   # Jumping - yellow
	8: Color(0.8, 0.2, 0.8, 0.3),   # Ghost - purple
}

#===============================================================================
# STATE
#===============================================================================

## Whether to show blocked tiles
var show_blocked: bool = true

## Whether to show navigation bounds
var show_bounds: bool = true

## Whether to show active paths
var show_paths: bool = true

## Current navigation layer to display (cycles through: ground, flying, jumping, ghost)
var debug_nav_layer: int = 1  # NavigationGrid.NAV_GROUND

## Available layers for cycling
var _available_layers: Array[int] = [1, 2, 4, 8]  # NAV_GROUND, NAV_FLYING, NAV_JUMPING, NAV_GHOST

## Current layer index
var _layer_index: int = 0

## Reference to pathfinding service
var _pathfinding_service: PathfindingServiceClass

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	# Get reference to pathfinding service
	_pathfinding_service = get_node_or_null("/root/PathfindingService")

	if _pathfinding_service:
		_pathfinding_service.navigation_updated.connect(_on_navigation_updated)
		_pathfinding_service.debug_toggled.connect(_on_debug_toggled)

	# Render above most things
	z_index = 99

func _process(_delta: float) -> void:
	# Redraw if visible (for path updates)
	if visible and show_paths:
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Cycle through navigation layers with L key when debug is enabled
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_cycle_nav_layer()

func _cycle_nav_layer() -> void:
	"""Cycle through available navigation layers for visualization"""
	_layer_index = (_layer_index + 1) % _available_layers.size()
	debug_nav_layer = _available_layers[_layer_index]
	var layer_name := _layer_to_name(debug_nav_layer)
	print("[NavDebug] Showing layer: %s (%d)" % [layer_name, debug_nav_layer])
	queue_redraw()

func _layer_to_name(layer: int) -> String:
	"""Convert layer bitmask to human-readable name"""
	match layer:
		1: return "ground"
		2: return "flying"
		4: return "jumping"
		8: return "ghost"
		_: return "unknown"

func _draw() -> void:
	if not _pathfinding_service or not _pathfinding_service.is_debug_enabled():
		return

	if show_bounds:
		_draw_bounds()

	if show_blocked:
		_draw_blocked_tiles()

	if show_paths:
		_draw_paths()

	# Draw layer indicator
	_draw_layer_indicator()

#===============================================================================
# DRAWING METHODS
#===============================================================================

func _draw_bounds() -> void:
	var bounds := _pathfinding_service.get_nav_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	var world_pos := Vector2(bounds.position.x * TILE_SIZE, bounds.position.y * TILE_SIZE)
	var world_size := Vector2(bounds.size.x * TILE_SIZE, bounds.size.y * TILE_SIZE)

	var rect := Rect2(world_pos, world_size)
	draw_rect(rect, COLOR_BOUNDS, false, 2.0)

	# Draw corner markers
	var marker_size := 8.0
	draw_line(world_pos, world_pos + Vector2(marker_size, 0), COLOR_BOUNDS, 3.0)
	draw_line(world_pos, world_pos + Vector2(0, marker_size), COLOR_BOUNDS, 3.0)

func _draw_blocked_tiles() -> void:
	# Get blocked tiles for the current debug layer
	var blocked := _pathfinding_service.get_blocked_tiles_for_layer(debug_nav_layer)

	# Limit drawing to avoid performance issues
	var max_tiles := 2000
	var drawn := 0

	# Use layer-specific color
	var blocked_color: Color = COLOR_BLOCKED
	if LAYER_COLORS.has(debug_nav_layer):
		blocked_color = LAYER_COLORS[debug_nav_layer]
		blocked_color.a = 0.4  # Slightly more opaque for blocked

	for tile in blocked:
		if drawn >= max_tiles:
			break

		var world_pos := Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
		var rect := Rect2(world_pos, Vector2(TILE_SIZE, TILE_SIZE))
		draw_rect(rect, blocked_color, true)
		drawn += 1

func _draw_paths() -> void:
	var paths := _pathfinding_service.get_cached_paths()

	for path in paths:
		if path.size() < 2:
			continue

		# Draw path line
		for i in range(path.size() - 1):
			draw_line(path[i], path[i + 1], COLOR_PATH, 2.0)

		# Draw waypoint markers
		for i in range(path.size()):
			var point := path[i]
			if i == 0:
				# Start point - square
				draw_rect(Rect2(point - Vector2(4, 4), Vector2(8, 8)), Color.GREEN, true)
			elif i == path.size() - 1:
				# End point - circle
				draw_circle(point, 5.0, Color.RED)
			else:
				# Intermediate - small circle
				draw_circle(point, 3.0, COLOR_PATH)


func _draw_layer_indicator() -> void:
	"""Draw current layer indicator in screen space"""
	# Get camera to convert to screen position
	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	var screen_pos := camera.global_position - get_viewport_rect().size * 0.5
	var indicator_pos := screen_pos + Vector2(10, 10)

	# Get layer info
	var layer_name := _layer_to_name(debug_nav_layer)
	var layer_color: Color = LAYER_COLORS.get(debug_nav_layer, Color.WHITE)

	# Draw background box
	var text := "Nav Layer: %s (L to cycle)" % layer_name
	var box_size := Vector2(200, 24)
	draw_rect(Rect2(indicator_pos, box_size), Color(0, 0, 0, 0.7), true)
	draw_rect(Rect2(indicator_pos, box_size), layer_color, false, 2.0)

	# Draw color indicator square
	draw_rect(Rect2(indicator_pos + Vector2(4, 4), Vector2(16, 16)), layer_color, true)

#===============================================================================
# SIGNAL HANDLERS
#===============================================================================

func _on_navigation_updated() -> void:
	queue_redraw()

func _on_debug_toggled(enabled: bool) -> void:
	visible = enabled
	queue_redraw()
