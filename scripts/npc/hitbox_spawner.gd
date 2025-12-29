extends Node2D
class_name HitboxSpawner
## HitboxSpawner - Creates and manages ability hitboxes
##
## Spawns temporary Area2D hitboxes for abilities based on shape type:
##   - Circle: Radial area around origin
##   - Cone: Arc in facing direction
##   - Line: Narrow rectangle in facing direction
##   - Cross: Four lines in cardinal/diagonal directions
##   - Ring: Expanding ring outward from origin
##
## Usage:
##   var spawner = HitboxSpawner.new()
##   add_child(spawner)
##   spawner.spawn_hitbox(ability_data, caster, direction)

#===============================================================================
# SIGNALS
#===============================================================================

signal hit_detected(target: Node2D, ability: AbilityData)
signal hitbox_expired(ability: AbilityData)

#===============================================================================
# CONSTANTS
#===============================================================================

const HITBOX_LAYER := 0b00000100  ## Layer for hitboxes
const PLAYER_LAYER := 0b00000001  ## Player layer to detect
const DEBUG_COLOR := Color(1.0, 0.3, 0.3, 0.4)

#===============================================================================
# STATE
#===============================================================================

var active_hitboxes: Array[Area2D] = []
var debug_draw_enabled := false

#===============================================================================
# PUBLIC METHODS
#===============================================================================

func spawn_hitbox(
	ability: AbilityData,
	caster: Node2D,
	direction: Vector2,
	offset: Vector2 = Vector2.ZERO
) -> Area2D:
	## Spawn a hitbox for the given ability
	## Returns the created Area2D for tracking

	var hitbox: Area2D

	match ability.shape:
		AbilityData.HitboxShape.CIRCLE:
			hitbox = _create_circle_hitbox(ability, caster, offset)
		AbilityData.HitboxShape.CONE:
			hitbox = _create_cone_hitbox(ability, caster, direction, offset)
		AbilityData.HitboxShape.LINE:
			hitbox = _create_line_hitbox(ability, caster, direction, offset)
		AbilityData.HitboxShape.CROSS:
			hitbox = _create_cross_hitbox(ability, caster, direction, offset)
		AbilityData.HitboxShape.RING:
			hitbox = _create_ring_hitbox(ability, caster, offset)
		_:
			hitbox = _create_circle_hitbox(ability, caster, offset)

	if hitbox:
		_setup_hitbox_common(hitbox, ability, caster)
		active_hitboxes.append(hitbox)

	return hitbox


func clear_all_hitboxes() -> void:
	## Remove all active hitboxes immediately
	for hitbox in active_hitboxes:
		if is_instance_valid(hitbox):
			hitbox.queue_free()
	active_hitboxes.clear()


#===============================================================================
# HITBOX CREATION - CIRCLE
#===============================================================================

func _create_circle_hitbox(
	ability: AbilityData,
	caster: Node2D,
	offset: Vector2
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset

	var shape := CircleShape2D.new()
	shape.radius = ability.shape_size

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)

	# Debug visualization
	if debug_draw_enabled:
		var debug_node := _create_debug_circle(ability.shape_size)
		area.add_child(debug_node)

	add_child(area)
	return area


#===============================================================================
# HITBOX CREATION - CONE
#===============================================================================

func _create_cone_hitbox(
	ability: AbilityData,
	caster: Node2D,
	direction: Vector2,
	offset: Vector2
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset
	area.rotation = direction.angle()

	# Create cone using polygon
	var shape := ConvexPolygonShape2D.new()
	var points := _generate_cone_points(ability.shape_size, ability.shape_angle)
	shape.points = points

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)

	# Debug visualization
	if debug_draw_enabled:
		var debug_node := _create_debug_polygon(points)
		area.add_child(debug_node)

	add_child(area)
	return area


func _generate_cone_points(length: float, angle_deg: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half_angle := deg_to_rad(angle_deg / 2.0)
	var segments := 8  ## Number of segments for arc

	# Start at origin
	points.append(Vector2.ZERO)

	# Arc points
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var current_angle := -half_angle + t * half_angle * 2
		var point := Vector2(cos(current_angle), sin(current_angle)) * length
		points.append(point)

	return points


#===============================================================================
# HITBOX CREATION - LINE
#===============================================================================

func _create_line_hitbox(
	ability: AbilityData,
	caster: Node2D,
	direction: Vector2,
	offset: Vector2
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset
	area.rotation = direction.angle()

	# Create narrow rectangle
	var shape := RectangleShape2D.new()
	var width := 20.0  ## Fixed width for line attacks
	shape.size = Vector2(ability.shape_size, width)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(ability.shape_size / 2.0, 0)  ## Center along line
	area.add_child(collision)

	# Debug visualization
	if debug_draw_enabled:
		var debug_node := _create_debug_rect(ability.shape_size, width)
		area.add_child(debug_node)

	add_child(area)
	return area


#===============================================================================
# HITBOX CREATION - CROSS
#===============================================================================

func _create_cross_hitbox(
	ability: AbilityData,
	caster: Node2D,
	direction: Vector2,
	offset: Vector2
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset
	area.rotation = deg_to_rad(ability.shape_angle)

	var line_width := 15.0

	# Create 4 lines in cross pattern
	var angles := [0.0, 90.0, 180.0, 270.0]
	for angle in angles:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(ability.shape_size, line_width)

		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.rotation = deg_to_rad(angle)
		collision.position = Vector2(ability.shape_size / 2.0, 0).rotated(deg_to_rad(angle))
		area.add_child(collision)

	# Debug visualization
	if debug_draw_enabled:
		var debug_node := _create_debug_cross(ability.shape_size, line_width)
		area.add_child(debug_node)

	add_child(area)
	return area


#===============================================================================
# HITBOX CREATION - RING
#===============================================================================

func _create_ring_hitbox(
	ability: AbilityData,
	caster: Node2D,
	offset: Vector2
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset

	# Ring is created as an expanding circle
	# Start small, tween to full size
	var shape := CircleShape2D.new()
	shape.radius = 10.0  ## Start small

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)

	# Animate expansion
	var tween := create_tween()
	tween.tween_property(shape, "radius", ability.shape_size, 0.3)

	# Debug visualization
	if debug_draw_enabled:
		var debug_node := _create_debug_ring(ability.shape_size)
		area.add_child(debug_node)

	add_child(area)
	return area


#===============================================================================
# COMMON SETUP
#===============================================================================

func _setup_hitbox_common(hitbox: Area2D, ability: AbilityData, caster: Node2D) -> void:
	## Common setup for all hitbox types

	# Set collision layers
	hitbox.collision_layer = HITBOX_LAYER
	hitbox.collision_mask = PLAYER_LAYER
	hitbox.monitoring = true
	hitbox.monitorable = false

	# Store metadata
	hitbox.set_meta("ability", ability)
	hitbox.set_meta("caster", caster)
	hitbox.set_meta("hit_targets", [])

	# Connect signals
	hitbox.body_entered.connect(_on_hitbox_body_entered.bind(hitbox, ability))
	hitbox.area_entered.connect(_on_hitbox_area_entered.bind(hitbox, ability))

	# Auto-cleanup after a short duration (handle lingering hitboxes)
	var cleanup_timer := get_tree().create_timer(0.5)
	cleanup_timer.timeout.connect(_cleanup_hitbox.bind(hitbox, ability))


func _on_hitbox_body_entered(body: Node2D, hitbox: Area2D, ability: AbilityData) -> void:
	_process_hit(body, hitbox, ability)


func _on_hitbox_area_entered(area: Area2D, hitbox: Area2D, ability: AbilityData) -> void:
	# Check if area's parent is a valid target
	var parent := area.get_parent()
	if parent is Node2D:
		_process_hit(parent, hitbox, ability)


func _process_hit(target: Node2D, hitbox: Area2D, ability: AbilityData) -> void:
	## Process a potential hit

	# Skip if already hit this target
	var hit_targets: Array = hitbox.get_meta("hit_targets", [])
	if target in hit_targets:
		return

	# Skip if target is caster
	var caster: Node2D = hitbox.get_meta("caster")
	if target == caster:
		return

	# Skip if target doesn't have health (not damageable)
	if not target.has_method("take_damage") and not "current_health" in target:
		return

	# Record hit
	hit_targets.append(target)
	hitbox.set_meta("hit_targets", hit_targets)

	# Emit signal
	hit_detected.emit(target, ability)


func _cleanup_hitbox(hitbox: Area2D, ability: AbilityData) -> void:
	if is_instance_valid(hitbox):
		active_hitboxes.erase(hitbox)
		hitbox.queue_free()
		hitbox_expired.emit(ability)


#===============================================================================
# DEBUG VISUALIZATION
#===============================================================================

func set_debug_draw(enabled: bool) -> void:
	debug_draw_enabled = enabled


func _create_debug_circle(radius: float) -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://scripts/npc/hitbox_debug_draw.gd"))
	node.set_meta("draw_type", "circle")
	node.set_meta("radius", radius)
	node.set_meta("color", DEBUG_COLOR)
	return node


func _create_debug_polygon(points: PackedVector2Array) -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://scripts/npc/hitbox_debug_draw.gd"))
	node.set_meta("draw_type", "polygon")
	node.set_meta("points", points)
	node.set_meta("color", DEBUG_COLOR)
	return node


func _create_debug_rect(length: float, width: float) -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://scripts/npc/hitbox_debug_draw.gd"))
	node.set_meta("draw_type", "rect")
	node.set_meta("length", length)
	node.set_meta("width", width)
	node.set_meta("color", DEBUG_COLOR)
	return node


func _create_debug_cross(length: float, width: float) -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://scripts/npc/hitbox_debug_draw.gd"))
	node.set_meta("draw_type", "cross")
	node.set_meta("length", length)
	node.set_meta("width", width)
	node.set_meta("color", DEBUG_COLOR)
	return node


func _create_debug_ring(radius: float) -> Node2D:
	var node := Node2D.new()
	node.set_script(preload("res://scripts/npc/hitbox_debug_draw.gd"))
	node.set_meta("draw_type", "ring")
	node.set_meta("radius", radius)
	node.set_meta("color", DEBUG_COLOR)
	return node
