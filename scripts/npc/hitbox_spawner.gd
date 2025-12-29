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

#===============================================================================
# STATE
#===============================================================================

var active_hitboxes: Array[Area2D] = []
var show_visuals := true  ## Show attack visuals

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
	var visual_info := {}

	match ability.shape:
		AbilityData.HitboxShape.CIRCLE:
			hitbox = _create_circle_hitbox(ability, caster, offset)
			visual_info = {"type": "circle", "radius": ability.shape_size}
		AbilityData.HitboxShape.CONE:
			var points := _generate_cone_points(ability.shape_size, ability.shape_angle)
			hitbox = _create_cone_hitbox(ability, caster, direction, offset, points)
			visual_info = {"type": "polygon", "points": points}
		AbilityData.HitboxShape.LINE:
			hitbox = _create_line_hitbox(ability, caster, direction, offset)
			visual_info = {"type": "rect", "length": ability.shape_size, "width": 20.0}
		AbilityData.HitboxShape.CROSS:
			hitbox = _create_cross_hitbox(ability, caster, direction, offset)
			visual_info = {"type": "cross", "length": ability.shape_size, "width": 15.0}
		AbilityData.HitboxShape.RING:
			hitbox = _create_ring_hitbox(ability, caster, offset)
			visual_info = {"type": "ring", "radius": ability.shape_size}
		_:
			hitbox = _create_circle_hitbox(ability, caster, offset)
			visual_info = {"type": "circle", "radius": ability.shape_size}

	if hitbox:
		_setup_hitbox_common(hitbox, ability, caster)
		if show_visuals:
			_add_visual(hitbox, ability, visual_info)
		active_hitboxes.append(hitbox)

	return hitbox


func clear_all_hitboxes() -> void:
	## Remove all active hitboxes immediately
	for hitbox in active_hitboxes:
		if is_instance_valid(hitbox):
			hitbox.queue_free()
	active_hitboxes.clear()


func spawn_hit_effect(pos: Vector2, damage_type: String = "physical") -> void:
	## Spawn a hit particle effect
	HitboxVisual.spawn_hit_effect(self, pos, damage_type)


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

	add_child(area)
	return area


#===============================================================================
# HITBOX CREATION - CONE
#===============================================================================

func _create_cone_hitbox(
	ability: AbilityData,
	caster: Node2D,
	direction: Vector2,
	offset: Vector2,
	points: PackedVector2Array
) -> Area2D:
	var area := Area2D.new()
	area.global_position = caster.global_position + offset
	area.rotation = direction.angle()

	# Create cone using polygon
	var shape := ConvexPolygonShape2D.new()
	shape.points = points

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child(collision)

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

	add_child(area)
	return area


#===============================================================================
# VISUAL SYSTEM
#===============================================================================

func _add_visual(hitbox: Area2D, ability: AbilityData, info: Dictionary) -> void:
	## Add animated visual to hitbox
	var visual := HitboxVisual.new()
	visual.draw_type = info.get("type", "circle")
	visual.damage_type = AbilityData.DamageType.keys()[ability.damage_type].to_lower() if ability.damage_type != null else "physical"

	match visual.draw_type:
		"circle":
			visual.radius = info.get("radius", 25.0)
		"polygon":
			visual.points = info.get("points", PackedVector2Array())
		"rect":
			visual.length = info.get("length", 100.0)
			visual.width = info.get("width", 20.0)
		"cross":
			visual.length = info.get("length", 100.0)
			visual.width = info.get("width", 15.0)
		"ring":
			visual.radius = info.get("radius", 80.0)

	visual.setup(ability, 0.0)  # No windup - already in active phase
	hitbox.add_child(visual)


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

	# Spawn hit effect at target position
	var dmg_type_str: String = AbilityData.DamageType.keys()[ability.damage_type].to_lower()
	spawn_hit_effect(target.global_position, dmg_type_str)

	# Emit signal
	hit_detected.emit(target, ability)


func _cleanup_hitbox(hitbox: Area2D, ability: AbilityData) -> void:
	if is_instance_valid(hitbox):
		active_hitboxes.erase(hitbox)
		hitbox.queue_free()
		hitbox_expired.emit(ability)


#===============================================================================
# DEBUG
#===============================================================================

func set_debug_draw(enabled: bool) -> void:
	## For backwards compatibility
	show_visuals = enabled
