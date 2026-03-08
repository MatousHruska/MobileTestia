extends Node
## FootprintManager — spawns fading footprint decals and step particles
## based on terrain type under the player's feet.

#===============================================================================
# CONSTANTS
#===============================================================================

## Distance in pixels between footprint spawns
const STEP_DISTANCE := 16.0

## How long footprints last before fully fading (seconds)
const FADE_DURATION := 8.0

## Horizontal offset from center for left/right foot alternation (pixels)
const FOOT_OFFSET := 3.0

## Maximum concurrent footprints (oldest freed if exceeded)
const MAX_FOOTPRINTS := 50

## Snow puff particle settings
const PUFF_PARTICLE_COUNT := 4
const PUFF_LIFETIME := 0.5

#===============================================================================
# STATE
#===============================================================================

## Cumulative distance since last footprint
var _distance_accumulated := 0.0

## Last player position (for distance tracking)
var _last_position := Vector2.ZERO

## Whether we've initialized the last position
var _tracking := false

## Alternates between left (false) and right (true) foot
var _right_foot := false

## Preloaded footprint texture
var _footprint_texture: Texture2D = null

## Active footprint count (for cleanup)
var _footprint_count := 0

## Reference to the world root node where decals are placed
var _world_root: Node2D = null

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
	var tex_path := "res://assets/effects/footprint.png"
	if ResourceLoader.exists(tex_path):
		_footprint_texture = load(tex_path)


func _process(_delta: float) -> void:
	if not Game or not Game.is_player_valid():
		_tracking = false
		return

	var player_pos: Vector2 = Game.player.global_position

	if not _tracking:
		_last_position = player_pos
		_tracking = true
		return

	# Accumulate movement distance
	var moved := player_pos.distance_to(_last_position)
	if moved < 0.5:
		return  # Standing still or micro-jitter

	var move_dir := _last_position.direction_to(player_pos)
	_distance_accumulated += moved
	_last_position = player_pos

	# Spawn footprint at each step interval
	while _distance_accumulated >= STEP_DISTANCE:
		_distance_accumulated -= STEP_DISTANCE
		_try_spawn_footprint(player_pos, move_dir)


#===============================================================================
# FOOTPRINT SPAWNING
#===============================================================================

func _try_spawn_footprint(pos: Vector2, direction: Vector2) -> void:
	# Query terrain at player feet
	var terrain_id := ChunkManager.get_terrain_at(pos)
	if terrain_id.is_empty():
		return

	var terrain_data: Dictionary = DatabaseLoader.get_terrain_type(terrain_id)
	if terrain_data.is_empty() or not terrain_data.get("has_footprints", false):
		return

	# Find world root (cache it)
	if _world_root == null or not is_instance_valid(_world_root):
		_world_root = _find_world_root()
		if _world_root == null:
			return

	# Parse tint color from terrain data
	var tint_hex: String = terrain_data.get("footprint_tint", "#FFFFFF")
	var tint := Color.from_string(tint_hex, Color.WHITE)
	tint.a = 0.6  # Start semi-transparent

	# Spawn decal
	_spawn_decal(pos, direction, tint)

	# Spawn particle puff
	_spawn_step_puff(pos, tint)


func _spawn_decal(pos: Vector2, direction: Vector2, tint: Color) -> void:
	if _footprint_texture == null:
		return

	# Enforce max footprints
	if _footprint_count >= MAX_FOOTPRINTS:
		_remove_oldest_footprint()

	var decal := Sprite2D.new()
	decal.texture = _footprint_texture
	decal.modulate = tint
	decal.z_index = -1  # Below characters

	# Position with left/right foot offset
	_right_foot = not _right_foot
	var perp := Vector2(-direction.y, direction.x)  # Perpendicular to movement
	var foot_offset := perp * (FOOT_OFFSET if _right_foot else -FOOT_OFFSET)
	decal.global_position = pos + foot_offset

	# Rotate to match movement direction
	decal.rotation = direction.angle() + PI / 2.0  # +90° because sprite points up

	# Flip x for right foot
	if _right_foot:
		decal.flip_h = true

	decal.add_to_group("footprints")
	_world_root.add_child(decal)
	_footprint_count += 1

	# Fade out and free
	var tween := decal.create_tween()
	tween.tween_property(decal, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(func() -> void:
		_footprint_count -= 1
		decal.queue_free()
	)


func _spawn_step_puff(pos: Vector2, tint: Color) -> void:
	var particles := GPUParticles2D.new()
	particles.emitting = false
	particles.amount = PUFF_PARTICLE_COUNT
	particles.lifetime = PUFF_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.z_index = -1

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)  # Upward drift
	mat.spread = 45.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, 10, 0)  # Slight downward pull
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.color = Color(tint.r, tint.g, tint.b, 0.5)
	particles.process_material = mat

	particles.global_position = pos
	_world_root.add_child(particles)
	particles.emitting = true

	# Auto-free after emission completes
	get_tree().create_timer(PUFF_LIFETIME + 0.1).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)


func _remove_oldest_footprint() -> void:
	var footprints := get_tree().get_nodes_in_group("footprints")
	if not footprints.is_empty():
		_footprint_count -= 1
		footprints[0].queue_free()


func _find_world_root() -> Node2D:
	# DualViewport autoload has get_world_root() method
	var dvp := get_node_or_null("/root/DualViewport")
	if dvp and dvp.has_method("get_world_root"):
		return dvp.get_world_root()
	# Fallback: look for world_root in scene tree
	var nodes := get_tree().get_nodes_in_group("world_root")
	if not nodes.is_empty():
		return nodes[0] as Node2D
	return null


#===============================================================================
# CLEANUP
#===============================================================================

## Clear all footprints (call on zone change)
func clear_footprints() -> void:
	for fp in get_tree().get_nodes_in_group("footprints"):
		fp.queue_free()
	_footprint_count = 0
	_tracking = false
	_distance_accumulated = 0.0
