extends Node
class_name InteriorManagerClass
## InteriorManager - Handles interior revelation system
## Manages roof visibility and exterior dimming when player enters/exits interiors

#===============================================================================
# CONSTANTS
#===============================================================================

## Duration of roof fade transition in seconds
const ROOF_FADE_DURATION: float = 0.25

## Duration of exterior dim transition in seconds
const EXTERIOR_DIM_DURATION: float = 0.3

## How dark the exterior gets when player is inside (1.0 = normal, 0.7 = dimmed)
const EXTERIOR_DIM_ALPHA: float = 0.7

## Color of the exterior dimming overlay
const EXTERIOR_DIM_COLOR: Color = Color(0.0, 0.0, 0.0, 0.3)

#===============================================================================
# SIGNALS
#===============================================================================

signal entered_interior(region_value: int)
signal exited_interior(region_value: int)
signal interior_changed(old_region: int, new_region: int)

#===============================================================================
# STATE
#===============================================================================

## Current interior region (0 = outside)
var current_region: int = 0

## Set of all currently revealed regions (includes parent chain)
var _revealed_regions: Array[int] = []

## Active roof fade tweens by region
var _roof_tweens: Dictionary = {}  # region_value -> Tween

## Exterior dim overlay tween
var _dim_tween: Tween = null

## CanvasLayer for exterior dimming effect
var _dim_canvas: CanvasLayer = null

## ColorRect for the actual dimming
var _dim_overlay: ColorRect = null

## Whether the manager is active
var _active: bool = false

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	# Wait for ChunkManager to be available
	_connect_to_chunk_manager.call_deferred()

	# Create exterior dim overlay
	_create_dim_overlay()

	Debug.info("InteriorManager", "InteriorManager initialized")


func _connect_to_chunk_manager() -> void:
	## Connect to ChunkManager signals
	if not ChunkManager:
		Debug.warn("InteriorManager", "ChunkManager not found")
		return

	ChunkManager.interior_region_changed.connect(_on_interior_region_changed)
	ChunkManager.zone_initialized.connect(_on_zone_initialized)
	ChunkManager.zone_cleanup.connect(_on_zone_cleanup)
	Debug.log("InteriorManager", "Connected to ChunkManager")

	# If a zone is already initialized (we connected late), activate now
	if not ChunkManager.current_zone_id.is_empty():
		Debug.log("InteriorManager", "Zone already active, activating now: %s" % ChunkManager.current_zone_id)
		_active = true


var _debug_frame_counter: int = 0

func _process(_delta: float) -> void:
	if not _active:
		return

	# Update player interior region check
	if Game and Game.is_player_valid():
		ChunkManager.update_player_interior_region(Game.player.global_position)

		# Debug: periodically log region detection
		_debug_frame_counter += 1
		if _debug_frame_counter % 60 == 0:  # Every 60 frames (~1 second)
			var region := ChunkManager.get_interior_region_at_position(Game.player.global_position)
			if region > 0 or current_region > 0:
				Debug.log("InteriorManager", "Player at %s, detected region: %d, current: %d" % [Game.player.global_position, region, current_region])


#===============================================================================
# OVERLAY SETUP
#===============================================================================

func _create_dim_overlay() -> void:
	## Create the CanvasLayer and ColorRect for exterior dimming
	_dim_canvas = CanvasLayer.new()
	_dim_canvas.name = "ExteriorDimCanvas"
	_dim_canvas.layer = 5  # Above world (0) but below UI (typically 10+)
	add_child(_dim_canvas)

	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.color = EXTERIOR_DIM_COLOR
	_dim_overlay.color.a = 0.0  # Start fully transparent
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Make it cover the entire screen
	_dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.size = Vector2(4096, 4096)  # Large enough for any viewport
	_dim_overlay.position = Vector2(-2048, -2048)  # Centered

	_dim_canvas.add_child(_dim_overlay)


#===============================================================================
# PUBLIC API
#===============================================================================

## Check if player is currently inside any interior
func is_inside() -> bool:
	return current_region > 0


## Get the current interior region value
func get_current_region() -> int:
	return current_region


## Get list of all revealed region values
func get_revealed_regions() -> Array[int]:
	return _revealed_regions.duplicate()


## Force refresh of roof visibility (e.g., after loading a save)
func refresh_roof_visibility() -> void:
	_apply_region_visibility(0, current_region, true)


#===============================================================================
# INTERIOR REGION HANDLING
#===============================================================================

func _on_interior_region_changed(old_region: int, new_region: int) -> void:
	## Handle player moving between interior regions
	Debug.log("InteriorManager", "Region changed: %d -> %d" % [old_region, new_region])

	current_region = new_region

	_apply_region_visibility(old_region, new_region, false)

	# Emit signals
	if old_region == 0 and new_region > 0:
		entered_interior.emit(new_region)
	elif old_region > 0 and new_region == 0:
		exited_interior.emit(old_region)

	interior_changed.emit(old_region, new_region)


func _apply_region_visibility(old_region: int, new_region: int, instant: bool) -> void:
	## Apply roof visibility and exterior dim based on region change

	# Build set of regions that should be revealed
	var old_revealed := _get_region_chain(old_region)
	var new_revealed := _get_region_chain(new_region)

	# Find regions to show (were revealed, now hidden)
	var regions_to_show: Array[int] = []
	for r in old_revealed:
		if r not in new_revealed:
			regions_to_show.append(r)

	# Find regions to hide (now revealed, were hidden)
	var regions_to_hide: Array[int] = []
	for r in new_revealed:
		if r not in old_revealed:
			regions_to_hide.append(r)

	# Apply roof visibility changes
	for region_value in regions_to_show:
		_fade_roof(region_value, 1.0, instant)  # Show roof

	for region_value in regions_to_hide:
		_fade_roof(region_value, 0.0, instant)  # Hide roof

	# Update revealed regions list
	_revealed_regions = new_revealed

	# Apply exterior dimming
	if new_region > 0:
		_fade_exterior_dim(EXTERIOR_DIM_COLOR.a, instant)
	else:
		_fade_exterior_dim(0.0, instant)


func _get_region_chain(region_value: int) -> Array[int]:
	## Get the full parent chain for a region (including the region itself)
	## For nested interiors, returns [innermost, parent, grandparent, ...]
	var chain: Array[int] = []

	if region_value == 0:
		return chain

	chain.append(region_value)

	# Get parent chain from database
	if not DatabaseLoader:
		return chain

	var zone_id := ""
	if ChunkManager:
		zone_id = ChunkManager.current_zone_id

	var region_data: Dictionary = DatabaseLoader.get_interior_region_by_value(zone_id, region_value)
	while not region_data.is_empty():
		var parent_value: int = region_data.get("parent_region_value", 0)
		if parent_value == 0:
			break
		chain.append(parent_value)
		region_data = DatabaseLoader.get_interior_region_by_value(zone_id, parent_value)

	return chain


#===============================================================================
# FADE TRANSITIONS
#===============================================================================

func _fade_roof(region_value: int, target_alpha: float, instant: bool) -> void:
	## Fade roof visibility for a region

	# Kill existing tween for this region
	if _roof_tweens.has(region_value):
		var old_tween: Tween = _roof_tweens[region_value]
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	if instant:
		ChunkManager.set_roof_alpha_for_region(region_value, target_alpha)
		return

	# Create new tween
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# We need to tween via a method since ChunkManager manages multiple layers
	var current_alpha := 1.0 - target_alpha  # Inverse of target is start
	tween.tween_method(
		func(alpha: float): ChunkManager.set_roof_alpha_for_region(region_value, alpha),
		current_alpha,
		target_alpha,
		ROOF_FADE_DURATION
	)

	_roof_tweens[region_value] = tween


func _fade_exterior_dim(target_alpha: float, instant: bool) -> void:
	## Fade the exterior dimming overlay

	if not _dim_overlay:
		return

	# Kill existing tween
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()

	if instant:
		_dim_overlay.color.a = target_alpha
		return

	# Create new tween
	_dim_tween = create_tween()
	_dim_tween.set_ease(Tween.EASE_OUT)
	_dim_tween.set_trans(Tween.TRANS_QUAD)
	_dim_tween.tween_property(_dim_overlay, "color:a", target_alpha, EXTERIOR_DIM_DURATION)


#===============================================================================
# ZONE EVENTS
#===============================================================================

func _on_zone_initialized(_zone_id: String) -> void:
	## Called when a new zone is initialized
	_active = true
	current_region = 0
	_revealed_regions.clear()

	# Reset exterior dim
	if _dim_overlay:
		_dim_overlay.color.a = 0.0

	Debug.log("InteriorManager", "Activated for zone: %s" % _zone_id)


func _on_zone_cleanup() -> void:
	## Called when zone is being cleaned up
	_active = false
	current_region = 0
	_revealed_regions.clear()

	# Kill all tweens
	for region_value in _roof_tweens:
		var tween: Tween = _roof_tweens[region_value]
		if tween and tween.is_valid():
			tween.kill()
	_roof_tweens.clear()

	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()

	Debug.log("InteriorManager", "Deactivated")


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	## Print current interior manager state
	Debug.info("InteriorManager", "=== Interior Manager State ===")
	Debug.info("InteriorManager", "  Active: %s" % _active)
	Debug.info("InteriorManager", "  Current region: %d" % current_region)
	Debug.info("InteriorManager", "  Revealed regions: %s" % str(_revealed_regions))
	Debug.info("InteriorManager", "  Dim overlay alpha: %.2f" % (_dim_overlay.color.a if _dim_overlay else 0.0))
