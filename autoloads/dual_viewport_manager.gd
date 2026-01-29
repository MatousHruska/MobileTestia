extends Node
## DualViewportManager - Manages the dual viewport system for pixel art + crisp UI
##
## Architecture:
## - Game world renders in a SubViewport at GAME_VIEWPORT_SIZE (480x270)
## - UI renders at native screen resolution (crisp text and buttons)
##
## Usage:
## - Game zones are loaded INTO the game viewport
## - UI elements (CanvasLayers) render outside the SubViewport at native res
##
## Signals:
## - game_viewport_ready: Emitted when the game viewport is ready
## - screen_size_changed(size): Emitted when screen size changes

## Signals
signal game_viewport_ready
signal screen_size_changed(size: Vector2i)

## Constants
const GAME_VIEWPORT_WIDTH: int = 480
const GAME_VIEWPORT_HEIGHT: int = 270
const GAME_VIEWPORT_SIZE: Vector2i = Vector2i(GAME_VIEWPORT_WIDTH, GAME_VIEWPORT_HEIGHT)

## References to viewport nodes (set by main_game scene)
var game_viewport: SubViewport = null
var game_viewport_container: SubViewportContainer = null
var world_root: Node2D = null

## Screen metrics
var screen_size: Vector2i = Vector2i(1920, 1080)
var scale_factor: float = 1.0  # screen_height / GAME_VIEWPORT_HEIGHT

## State
var _initialized: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to window resize
	get_tree().root.size_changed.connect(_on_screen_resized)
	_update_screen_metrics()

	Debug.info("DualViewport", "DualViewportManager initialized", {
		"game_size": GAME_VIEWPORT_SIZE,
		"screen_size": screen_size,
		"scale_factor": scale_factor
	})


func _update_screen_metrics() -> void:
	## Update screen size and scale factor
	screen_size = get_tree().root.size
	scale_factor = float(screen_size.y) / float(GAME_VIEWPORT_HEIGHT)
	Debug.log("DualViewport", "Screen metrics updated: %s, scale=%.2f" % [screen_size, scale_factor])


func _on_screen_resized() -> void:
	_update_screen_metrics()
	screen_size_changed.emit(screen_size)


## Called by main_game scene to register the viewport nodes
func register_viewports(viewport: SubViewport, container: SubViewportContainer, world: Node2D) -> void:
	game_viewport = viewport
	game_viewport_container = container
	world_root = world
	_initialized = true

	Debug.info("DualViewport", "Viewports registered", {
		"viewport": viewport.name,
		"container": container.name,
		"world": world.name
	})

	game_viewport_ready.emit()


## Check if the dual viewport system is initialized
func is_initialized() -> bool:
	return _initialized and game_viewport != null and world_root != null


## Get the game viewport for camera/rendering operations
func get_game_viewport() -> SubViewport:
	return game_viewport


## Get the world root node where zones are loaded
func get_world_root() -> Node2D:
	return world_root


## Load a zone scene into the game viewport
## Returns the instantiated zone node
func load_zone(zone_scene: PackedScene) -> Node:
	if not is_initialized():
		Debug.err("DualViewport", "Cannot load zone - viewport not initialized")
		return null

	# Clear existing zone content
	clear_world()

	# Instantiate and add the zone
	var zone := zone_scene.instantiate()
	world_root.add_child(zone)

	Debug.info("DualViewport", "Zone loaded into game viewport", zone.name)
	return zone


## Load a zone by path into the game viewport
func load_zone_from_path(zone_path: String) -> Node:
	var zone_scene := load(zone_path) as PackedScene
	if zone_scene == null:
		Debug.err("DualViewport", "Failed to load zone scene", zone_path)
		return null
	return load_zone(zone_scene)


## Clear all content from the world root
func clear_world() -> void:
	if world_root == null:
		return

	for child in world_root.get_children():
		child.queue_free()

	Debug.log("DualViewport", "World cleared")


## Get the game viewport's camera (if any)
func get_game_camera() -> Camera2D:
	if game_viewport == null:
		return null

	# Find camera in the viewport
	var cameras := game_viewport.get_tree().get_nodes_in_group("game_camera")
	if cameras.size() > 0:
		return cameras[0] as Camera2D

	# Try finding any Camera2D
	return _find_camera_recursive(game_viewport)


func _find_camera_recursive(node: Node) -> Camera2D:
	if node is Camera2D:
		return node
	for child in node.get_children():
		var cam := _find_camera_recursive(child)
		if cam:
			return cam
	return null


## Convert screen position to game world position
func screen_to_world(screen_pos: Vector2) -> Vector2:
	if game_viewport == null or game_viewport_container == null:
		return screen_pos

	# Get the container's rect
	var container_rect := game_viewport_container.get_global_rect()

	# Calculate position within container (0-1 range)
	var local_pos := (screen_pos - container_rect.position) / container_rect.size

	# Convert to game viewport coordinates
	var viewport_pos := local_pos * Vector2(GAME_VIEWPORT_SIZE)

	# Apply camera transform if there's a camera
	var camera := get_game_camera()
	if camera:
		var canvas_transform := game_viewport.canvas_transform
		viewport_pos = canvas_transform.affine_inverse() * viewport_pos

	return viewport_pos


## Convert game world position to screen position
func world_to_screen(world_pos: Vector2) -> Vector2:
	if game_viewport == null or game_viewport_container == null:
		return world_pos

	# Apply camera transform if there's a camera
	var viewport_pos := world_pos
	var camera := get_game_camera()
	if camera:
		var canvas_transform := game_viewport.canvas_transform
		viewport_pos = canvas_transform * world_pos

	# Convert from game viewport to 0-1 range
	var local_pos := viewport_pos / Vector2(GAME_VIEWPORT_SIZE)

	# Get the container's rect and convert to screen position
	var container_rect := game_viewport_container.get_global_rect()
	var screen_pos := container_rect.position + (local_pos * container_rect.size)

	return screen_pos


## Debug helper
func print_state() -> void:
	print("")
	print("╔════════════════════════════════════════════════════════════════╗")
	print("║            DUAL VIEWPORT STATE                                 ║")
	print("╠════════════════════════════════════════════════════════════════╣")
	print("║   Initialized: %s" % _initialized)
	print("║   Game Viewport: %s" % (game_viewport.name if game_viewport else "null"))
	print("║   Game Viewport Size: %s" % GAME_VIEWPORT_SIZE)
	print("║   Screen Size: %s" % screen_size)
	print("║   Scale Factor: %.2f" % scale_factor)
	print("║   World Root Children: %d" % (world_root.get_child_count() if world_root else 0))
	print("╚════════════════════════════════════════════════════════════════╝")
	print("")
