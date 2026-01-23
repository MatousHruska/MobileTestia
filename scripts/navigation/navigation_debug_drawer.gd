class_name NavigationDebugDrawer
extends Node2D
## NavigationDebugDrawer - Debug visualization for pathfinding
## Shows blocked tiles, active paths, and navigation bounds

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

#===============================================================================
# STATE
#===============================================================================

## Whether to show blocked tiles
var show_blocked: bool = true

## Whether to show navigation bounds
var show_bounds: bool = true

## Whether to show active paths
var show_paths: bool = true

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

func _draw() -> void:
	if not _pathfinding_service or not _pathfinding_service.is_debug_enabled():
		return

	if show_bounds:
		_draw_bounds()

	if show_blocked:
		_draw_blocked_tiles()

	if show_paths:
		_draw_paths()

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
	var blocked := _pathfinding_service.get_blocked_tiles()

	# Limit drawing to avoid performance issues
	var max_tiles := 2000
	var drawn := 0

	for tile in blocked:
		if drawn >= max_tiles:
			break

		var world_pos := Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
		var rect := Rect2(world_pos, Vector2(TILE_SIZE, TILE_SIZE))
		draw_rect(rect, COLOR_BLOCKED, true)
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

#===============================================================================
# SIGNAL HANDLERS
#===============================================================================

func _on_navigation_updated() -> void:
	queue_redraw()

func _on_debug_toggled(enabled: bool) -> void:
	visible = enabled
	queue_redraw()
