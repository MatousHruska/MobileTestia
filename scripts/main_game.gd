extends Control
## MainGame - Root scene for the dual viewport system
##
## This scene manages:
## - Game SubViewport (480x270) for pixel-perfect game rendering
## - UI renders at native screen resolution (crisp text/buttons)
##
## Zone scenes are loaded into the game viewport, while UI elements
## (CanvasLayers) render outside at native resolution.

## References to viewport nodes
@onready var game_viewport_container: SubViewportContainer = $GameViewportContainer
@onready var game_viewport: SubViewport = $GameViewportContainer/GameViewport
@onready var world_root: Node2D = $GameViewportContainer/GameViewport/World
@onready var hud: HUD = $HUD

## Current loaded zone
var current_zone: Node = null

## Starting zone (can be overridden)
@export var starting_zone_path: String = "res://scenes/world/zone_ldtk_test.tscn"


func _ready() -> void:
	Debug.info("MainGame", "Initializing dual viewport system")

	# Register viewports with DualViewportManager
	var dual_viewport = get_node_or_null("/root/DualViewport")
	if dual_viewport:
		dual_viewport.register_viewports(game_viewport, game_viewport_container, world_root)
	else:
		Debug.warn("MainGame", "DualViewport autoload not found")

	# Load the starting zone
	if not starting_zone_path.is_empty():
		call_deferred("_load_starting_zone")


func _load_starting_zone() -> void:
	## Load the initial zone into the game viewport
	Debug.info("MainGame", "Loading starting zone: %s" % starting_zone_path)
	load_zone(starting_zone_path)


func load_zone(zone_path: String) -> Node:
	## Load a zone scene into the game viewport
	## Returns the zone node or null on failure

	# Clear existing zone
	if current_zone and is_instance_valid(current_zone):
		Debug.info("MainGame", "Unloading zone: %s" % current_zone.name)
		current_zone.queue_free()
		current_zone = null
		# Wait for cleanup
		await get_tree().process_frame

	# Load new zone
	var zone_scene := load(zone_path) as PackedScene
	if zone_scene == null:
		Debug.err("MainGame", "Failed to load zone scene", zone_path)
		return null

	var zone := zone_scene.instantiate()

	# Remove the HUD from the zone if it has one (we use our own)
	var zone_hud := zone.get_node_or_null("HUD")
	if zone_hud:
		zone.remove_child(zone_hud)
		zone_hud.queue_free()
		Debug.log("MainGame", "Removed zone's HUD (using main HUD)")

	# Add to world root
	world_root.add_child(zone)
	current_zone = zone

	Debug.info("MainGame", "Zone loaded: %s" % zone.name)
	return zone


func unload_current_zone() -> void:
	## Unload the current zone
	if current_zone and is_instance_valid(current_zone):
		current_zone.queue_free()
		current_zone = null


## Get the game viewport for camera/rendering operations
func get_game_viewport() -> SubViewport:
	return game_viewport
