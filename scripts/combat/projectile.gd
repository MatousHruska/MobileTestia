extends Area2D
class_name Projectile
## Projectile - A flying projectile that travels in an arc and damages on collision
## Used for ranged attacks (arrows, bolts, etc.)

signal hit_target(target: Node2D, projectile: Projectile)
signal reached_destination(projectile: Projectile)

#===============================================================================
# CONFIGURATION
#===============================================================================

## Movement
@export var base_speed: float = 400.0  ## Base travel speed in pixels/sec
@export var max_range: float = 300.0   ## Maximum travel distance
@export var arc_height: float = 20.0   ## Visual arc height (parabolic)

## Collision
@export var piercing: bool = false     ## If true, continues through targets
@export var max_pierce_count: int = 1  ## Max targets to pierce (if piercing)

## Visual
@export var sprite_rotation_offset: float = 0.0  ## Rotation offset for sprite alignment

## Damage (set by spawner)
var damage: float = 0.0
var damage_type: String = "physical"
var source: Node2D = null  ## Who fired this projectile

#===============================================================================
# STATE
#===============================================================================

## Flight state
var direction: Vector2 = Vector2.RIGHT
var start_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var travel_distance: float = 0.0
var current_speed: float = 0.0
var is_flying: bool = false

## Arc simulation
var flight_progress: float = 0.0  ## 0 to 1, progress along flight path
var base_y_offset: float = 0.0    ## Y offset at start (for arc calculation)

## Pierce tracking
var pierced_targets: Array[Node2D] = []
var pierce_count: int = 0

## Visual components
var sprite: Sprite2D = null
var collision_shape: CollisionShape2D = null
var raycast: RayCast2D = null  ## For wall detection


func _ready() -> void:
	_setup_visuals()
	_setup_collision()
	_setup_raycast()

	# Connect collision signal
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _setup_visuals() -> void:
	## Create arrow sprite placeholder
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	# Create a simple arrow shape using a polygon texture
	var arrow_image := Image.create(24, 8, false, Image.FORMAT_RGBA8)
	arrow_image.fill(Color.TRANSPARENT)

	# Draw arrow shape (pointing right)
	for x in range(18):
		for y in range(8):
			# Arrow shaft
			if y >= 2 and y <= 5 and x < 14:
				arrow_image.set_pixel(x, y, Color(0.6, 0.4, 0.2))  # Brown shaft
			# Arrow head
			elif x >= 14:
				var center_y := 3.5
				var tip_x := 18
				var base_x := 14
				var half_width := 4.0
				# Calculate if point is inside triangle
				var t := float(x - base_x) / float(tip_x - base_x)
				var y_range := half_width * (1.0 - t)
				if abs(y - center_y) <= y_range:
					arrow_image.set_pixel(x, y, Color(0.4, 0.4, 0.4))  # Gray head

	var texture := ImageTexture.create_from_image(arrow_image)
	sprite.texture = texture
	sprite.rotation = sprite_rotation_offset
	add_child(sprite)


func _setup_collision() -> void:
	## Setup collision detection
	collision_shape = CollisionShape2D.new()
	collision_shape.name = "CollisionShape"

	var circle := CircleShape2D.new()
	circle.radius = 6.0
	collision_shape.shape = circle
	add_child(collision_shape)

	# Set collision layers
	collision_layer = 0  # Projectile doesn't block anything
	collision_mask = 0b00000011  # Detect walls (layer 1) and enemies (layer 2)


func _setup_raycast() -> void:
	## Setup raycast for wall detection
	raycast = RayCast2D.new()
	raycast.name = "WallRaycast"
	raycast.enabled = true
	raycast.collision_mask = 0b00000001  # Layer 1 (walls/obstacles)
	raycast.target_position = Vector2(20, 0)  # Will be updated in physics_process
	add_child(raycast)


func _physics_process(delta: float) -> void:
	if not is_flying:
		return

	# Update raycast direction and check for wall hit
	if raycast:
		raycast.target_position = direction * 15.0
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and (collider.is_in_group("walls") or collider.is_in_group("obstacles") or collider is TileMap):
				_hit_obstacle()
				return

	# Move projectile
	var movement := direction * current_speed * delta
	travel_distance += movement.length()
	global_position += movement

	# Update flight progress
	flight_progress = clampf(travel_distance / max_range, 0.0, 1.0)

	# Apply arc offset (parabolic)
	_apply_arc_offset()

	# Rotate sprite to match direction
	sprite.rotation = direction.angle() + sprite_rotation_offset

	# Check if reached max range
	if travel_distance >= max_range:
		_on_reached_destination()


func _apply_arc_offset() -> void:
	## Apply parabolic arc to sprite (visual only, doesn't affect collision)
	## Formula: arc_offset = arc_height * 4 * t * (1-t) where t = 0→1
	var t := flight_progress
	var arc_offset := arc_height * 4.0 * t * (1.0 - t)

	# Apply offset perpendicular to travel direction (upward in screen space)
	# For a horizontal shot, this moves the sprite up then down
	sprite.position.y = -arc_offset


#===============================================================================
# PUBLIC API
#===============================================================================

func launch(from: Vector2, dir: Vector2, speed_multiplier: float = 1.0, range_multiplier: float = 1.0) -> void:
	## Launch the projectile from a position in a direction
	start_position = from
	global_position = from
	direction = dir.normalized()

	current_speed = base_speed * speed_multiplier
	max_range *= range_multiplier

	travel_distance = 0.0
	flight_progress = 0.0
	is_flying = true

	Debug.log("Combat", "Projectile launched", {
		"from": from,
		"direction": direction,
		"speed": current_speed,
		"max_range": max_range
	})


func launch_to_target(from: Vector2, to: Vector2, speed_multiplier: float = 1.0) -> void:
	## Launch projectile toward a specific target position
	start_position = from
	target_position = to
	global_position = from
	direction = (to - from).normalized()

	# Calculate actual range (clamped to max)
	var dist := from.distance_to(to)
	max_range = minf(dist, max_range)

	current_speed = base_speed * speed_multiplier
	travel_distance = 0.0
	flight_progress = 0.0
	is_flying = true


func set_damage_info(dmg: float, dmg_type: String, src: Node2D) -> void:
	## Set damage information for this projectile
	damage = dmg
	damage_type = dmg_type
	source = src


#===============================================================================
# COLLISION HANDLING
#===============================================================================

func _on_body_entered(body: Node2D) -> void:
	_handle_collision(body)


func _on_area_entered(area: Area2D) -> void:
	# Check if the area's parent is a valid target
	var parent := area.get_parent()
	if parent is Node2D:
		_handle_collision(parent)


func _handle_collision(target: Node2D) -> void:
	## Handle collision with a target
	if not is_flying:
		return

	# Skip if we've already hit this target (for piercing)
	if target in pierced_targets:
		return

	# Check if target is damageable
	var is_enemy := target.is_in_group("enemies")
	var is_obstacle := target.is_in_group("obstacles") or target.is_in_group("walls")

	if is_enemy:
		_hit_enemy(target)
	elif is_obstacle:
		_hit_obstacle()


func _hit_enemy(enemy: Node2D) -> void:
	## Handle hitting an enemy
	pierced_targets.append(enemy)
	pierce_count += 1

	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, source)
		Debug.log("Combat", "Projectile hit enemy", {
			"target": enemy.name,
			"damage": damage
		})

	# Emit hit signal
	hit_target.emit(enemy, self)

	# Spawn hit effect
	_spawn_hit_effect(enemy.global_position)

	# Check if should continue (piercing)
	if piercing and pierce_count < max_pierce_count:
		return  # Continue flying

	# Stop and destroy
	_destroy()


func _hit_obstacle() -> void:
	## Handle hitting an obstacle/wall
	Debug.log("Combat", "Projectile hit obstacle")
	_spawn_hit_effect(global_position)
	_destroy()


func _on_reached_destination() -> void:
	## Called when projectile reaches max range
	Debug.log("Combat", "Projectile reached max range")
	reached_destination.emit(self)
	_destroy()


func _spawn_hit_effect(pos: Vector2) -> void:
	## Spawn a hit particle effect
	if get_parent():
		HitboxVisual.spawn_hit_effect(get_parent(), pos, damage_type)


func _destroy() -> void:
	## Clean up and remove projectile
	is_flying = false

	# Quick fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(queue_free)


#===============================================================================
# FACTORY
#===============================================================================

static func create_arrow() -> Projectile:
	## Factory method to create a basic arrow projectile
	var arrow := Projectile.new()
	arrow.name = "Arrow"
	arrow.base_speed = 400.0
	arrow.max_range = 300.0
	arrow.arc_height = 20.0
	arrow.piercing = false
	return arrow
