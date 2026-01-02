extends Area2D
class_name MagicProjectile
## MagicProjectile - A magic projectile that passes through enemies and explodes at destination
## Used for spells like fireball that apply debuffs on contact and deal AOE damage on explosion

## Preload classes (needed until Godot generates .uid files)
const ExplosionEffectClass = preload("res://scripts/combat/explosion_effect.gd")
const ExplosionTargetIndicatorClass = preload("res://scripts/combat/explosion_target_indicator.gd")

signal hit_target(target: Node2D, projectile: MagicProjectile)
signal exploded(position: Vector2, projectile: MagicProjectile)

#===============================================================================
# CONFIGURATION
#===============================================================================

## Movement
@export var base_speed: float = 350.0   ## Base travel speed in pixels/sec
@export var max_range: float = 300.0    ## Exact travel distance before explosion

## Explosion
@export var explosion_radius: float = 60.0   ## AOE radius on explosion
@export var explosion_damage: float = 0.0    ## Damage dealt by explosion
@export var explodes_on_wall: bool = true    ## Explode immediately on wall hit
@export var explosion_falloff: float = 30.0  ## Damage falloff % at edge (30 = 70% damage at edge, 0 = no falloff)

## Pass-through debuff
@export var pass_through_enemies: bool = true     ## Pass through enemies instead of stopping
@export var contact_status_effect: String = ""    ## Status effect to apply on contact (e.g., "status_burning")
@export var contact_damage: float = 0.0           ## Damage on contact (optional, 0 = none)

## Visual
@export var projectile_color: Color = Color(1.0, 0.5, 0.1, 1.0)  ## Fireball orange
@export var explosion_color: Color = Color(1.0, 0.3, 0.0, 1.0)   ## Explosion red-orange
@export var projectile_size: float = 12.0  ## Radius of projectile visual

## Damage info (set by spawner)
var damage_type: String = "fire"
var source: Node2D = null

#===============================================================================
# STATE
#===============================================================================

## Flight state
var direction: Vector2 = Vector2.RIGHT
var start_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO  ## Where explosion will occur
var travel_distance: float = 0.0
var current_speed: float = 0.0
var is_flying: bool = false

## Contact tracking (for pass-through)
var contacted_targets: Array[Node2D] = []

## Visual components
var collision_shape: CollisionShape2D = null
var target_indicator: Node2D = null  ## Shows explosion radius at target (added to world, not child)
var raycast: RayCast2D = null  ## For wall detection

## Debug
var _frame_count: int = 0


func _ready() -> void:
	print("[FIREBALL] _ready() called")
	_setup_collision()
	_setup_raycast()

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	print("[FIREBALL] Setup complete, is_flying=%s, speed=%s, range=%s" % [is_flying, base_speed, max_range])


func _draw() -> void:
	## Draw the projectile as a visible circle
	if not is_flying:
		return
	# Main projectile body (large red circle)
	draw_circle(Vector2.ZERO, projectile_size, projectile_color)
	# Bright center
	draw_circle(Vector2.ZERO, projectile_size * 0.5, projectile_color.lightened(0.5))
	# White hot core
	draw_circle(Vector2.ZERO, projectile_size * 0.25, Color.WHITE)


func _setup_raycast() -> void:
	## Setup raycast for wall detection
	raycast = RayCast2D.new()
	raycast.name = "WallRaycast"
	raycast.enabled = true
	raycast.collision_mask = 0b00000001  # Layer 1 (walls/obstacles)
	raycast.target_position = Vector2(30, 0)  # Will be updated in physics_process
	add_child(raycast)


func _setup_collision() -> void:
	collision_shape = CollisionShape2D.new()
	collision_shape.name = "CollisionShape"

	var circle := CircleShape2D.new()
	circle.radius = 8.0
	collision_shape.shape = circle
	add_child(collision_shape)

	collision_layer = 0
	collision_mask = 0b00000011  # Walls (layer 1) and enemies (layer 2)


func _physics_process(delta: float) -> void:
	if not is_flying:
		return

	_frame_count += 1

	# Debug every 30 frames
	if _frame_count % 30 == 1:
		print("[FIREBALL] Frame %d: pos=%s, dist=%.1f/%.1f, dir=%s, speed=%s" % [
			_frame_count, global_position, travel_distance, max_range, direction, current_speed
		])

	# Update raycast direction
	if raycast:
		raycast.target_position = direction * 20.0
		raycast.force_raycast_update()

		# Check for wall hit
		if raycast.is_colliding() and explodes_on_wall:
			var collider = raycast.get_collider()
			print("[FIREBALL] Raycast hit: %s (groups: walls=%s, obstacles=%s, is_tilemap=%s)" % [
				collider.name if collider else "null",
				collider.is_in_group("walls") if collider else false,
				collider.is_in_group("obstacles") if collider else false,
				collider is TileMap if collider else false
			])
			if collider and (collider.is_in_group("walls") or collider.is_in_group("obstacles") or collider is TileMap):
				print("[FIREBALL] Exploding due to wall hit!")
				_explode()
				return

	# Move projectile (straight line, no arc)
	var movement := direction * current_speed * delta
	travel_distance += movement.length()
	global_position += movement

	# Redraw projectile
	queue_redraw()

	# Check if reached max range
	if travel_distance >= max_range:
		print("[FIREBALL] Reached max range, exploding!")
		_explode()


#===============================================================================
# PUBLIC API
#===============================================================================

func launch(from: Vector2, dir: Vector2, speed_multiplier: float = 1.0) -> void:
	print("[FIREBALL] launch() called: from=%s, dir=%s, speed_mult=%s" % [from, dir, speed_multiplier])
	print("[FIREBALL] BEFORE: base_speed=%s, max_range=%s, explosion_radius=%s, explosion_damage=%s" % [
		base_speed, max_range, explosion_radius, explosion_damage
	])

	start_position = from
	global_position = from
	direction = dir.normalized()
	current_speed = base_speed * speed_multiplier
	travel_distance = 0.0
	is_flying = true

	# Calculate target position
	target_position = from + direction * max_range

	print("[FIREBALL] AFTER: is_flying=%s, current_speed=%s, target_pos=%s" % [is_flying, current_speed, target_position])
	print("[FIREBALL] Parent node: %s" % (get_parent().name if get_parent() else "NO PARENT"))

	# Create target indicator in the world (not as child)
	_create_target_indicator()

	# Force initial redraw
	queue_redraw()


func _create_target_indicator() -> void:
	## Create target indicator at explosion destination
	if not get_parent():
		return

	target_indicator = ExplosionTargetIndicatorClass.new()
	target_indicator.name = "FireballTarget"
	target_indicator.setup(explosion_radius, explosion_color)
	target_indicator.global_position = target_position
	get_parent().add_child(target_indicator)


func set_explosion_damage(dmg: float) -> void:
	explosion_damage = dmg


func set_contact_effect(status_id: String, dmg: float = 0.0) -> void:
	contact_status_effect = status_id
	contact_damage = dmg


#===============================================================================
# COLLISION HANDLING
#===============================================================================

func _on_body_entered(body: Node2D) -> void:
	_handle_collision(body)


func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent is Node2D:
		_handle_collision(parent)


func _handle_collision(target: Node2D) -> void:
	if not is_flying:
		return

	# Skip already contacted targets
	if target in contacted_targets:
		return

	var is_enemy := target.is_in_group("enemies")
	var is_obstacle := target.is_in_group("obstacles") or target.is_in_group("walls")

	if is_enemy:
		_contact_enemy(target)
	elif is_obstacle and explodes_on_wall:
		Debug.log("Combat", "Fireball hit obstacle via collision")
		_explode()


func _contact_enemy(enemy: Node2D) -> void:
	## Pass through enemy, apply debuff
	contacted_targets.append(enemy)

	# Apply contact damage if any
	if contact_damage > 0 and enemy.has_method("take_damage"):
		enemy.take_damage(contact_damage, source)

	# Apply status effect
	if not contact_status_effect.is_empty() and enemy.has_method("apply_status_effect"):
		enemy.apply_status_effect(contact_status_effect, source)
		Debug.log("Combat", "Applied %s to %s" % [contact_status_effect, enemy.name])

	hit_target.emit(enemy, self)

	# Spawn small hit effect
	_spawn_contact_effect(enemy.global_position)

	# Continue flying (pass-through)


func _explode() -> void:
	## Explode at current position, dealing AOE damage
	print("[FIREBALL] _explode() called at pos=%s, is_flying=%s" % [global_position, is_flying])

	if not is_flying:
		print("[FIREBALL] Already exploded (is_flying=false), skipping")
		return

	is_flying = false

	print("[FIREBALL] EXPLODING! pos=%s, radius=%s, damage=%s" % [global_position, explosion_radius, explosion_damage])

	# Deal AOE damage to all enemies in radius
	_apply_explosion_damage()

	# Spawn explosion visual
	print("[FIREBALL] Spawning explosion effect...")
	_spawn_explosion_effect()

	exploded.emit(global_position, self)

	# Remove target indicator
	_remove_target_indicator()

	# Destroy projectile
	print("[FIREBALL] Destroying projectile...")
	_destroy()


func _apply_explosion_damage() -> void:
	## Find all enemies in explosion radius and damage them
	if explosion_damage <= 0:
		return

	# Get all bodies in explosion radius using a physics query
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = explosion_radius
	query.shape = circle
	query.transform = Transform2D(0, global_position)
	query.collision_mask = 0b00000010  # Enemies only

	var results := space_state.intersect_shape(query, 32)

	for result in results:
		var collider = result.get("collider")
		if collider and collider.is_in_group("enemies"):
			if collider.has_method("take_damage"):
				# Calculate damage falloff based on distance (database-driven)
				var dist := global_position.distance_to(collider.global_position)
				var falloff_pct := explosion_falloff / 100.0  # Convert % to decimal
				var falloff := 1.0 - (dist / explosion_radius) * falloff_pct if explosion_falloff > 0 else 1.0
				var final_dmg := explosion_damage * falloff

				collider.take_damage(final_dmg, source)
				Debug.log("Combat", "Explosion hit %s for %.0f damage (falloff: %.0f%%)" % [collider.name, final_dmg, (1.0 - falloff) * 100])

			# Apply burning to enemies hit by explosion (if not already contacted)
			if not contact_status_effect.is_empty() and collider.has_method("apply_status_effect"):
				if collider not in contacted_targets:
					collider.apply_status_effect(contact_status_effect, source)
					Debug.log("Combat", "Explosion applied %s to %s" % [contact_status_effect, collider.name])


func _spawn_contact_effect(pos: Vector2) -> void:
	## Small effect when passing through enemy
	if get_parent():
		HitboxVisual.spawn_hit_effect(get_parent(), pos, damage_type)


func _spawn_explosion_effect() -> void:
	## Spawn explosion visual at current position
	if not get_parent():
		return

	# Create explosion visual
	var explosion := ExplosionEffectClass.new()
	explosion.radius = explosion_radius
	explosion.color = explosion_color
	explosion.global_position = global_position
	get_parent().add_child(explosion)


func _remove_target_indicator() -> void:
	## Remove target indicator from world
	if target_indicator and is_instance_valid(target_indicator):
		target_indicator.queue_free()
		target_indicator = null


func _destroy() -> void:
	is_flying = false
	_remove_target_indicator()

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(queue_free)


#===============================================================================
# FACTORY
#===============================================================================

static func create_fireball() -> MagicProjectile:
	var fireball := MagicProjectile.new()
	fireball.name = "Fireball"
	fireball.base_speed = 350.0
	fireball.max_range = 300.0
	fireball.explosion_radius = 60.0
	fireball.pass_through_enemies = true
	fireball.explodes_on_wall = true
	fireball.projectile_color = Color(1.0, 0.5, 0.1, 1.0)
	fireball.explosion_color = Color(1.0, 0.3, 0.0, 1.0)
	fireball.damage_type = "fire"
	return fireball
