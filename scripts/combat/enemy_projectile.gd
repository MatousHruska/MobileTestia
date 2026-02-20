extends Area2D
class_name EnemyProjectile
## EnemyProjectile - Simple projectile for enemy ranged attacks
## All parameters (speed, damage, etc.) come from the ability database

#===============================================================================
# PROPERTIES SET BY SPAWNER
#===============================================================================

## Direction to travel (normalized)
var direction: Vector2 = Vector2.RIGHT

## Travel speed in pixels/second (from ability's projectile_speed)
var speed: float = 200.0

## Damage to deal on hit (from base_damage * damage_mult)
var damage: float = 10.0

## The enemy that fired this projectile
var owner_node: Node2D = null

#===============================================================================
# INTERNAL STATE
#===============================================================================

var _traveled_distance: float = 0.0
var _max_distance: float = 500.0  # Safety limit
var _is_active: bool = true

## Visual components
var _sprite: Sprite2D = null
var _collision: CollisionShape2D = null


func _ready() -> void:
	_setup_visual()
	_setup_collision()

	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _setup_visual() -> void:
	"""Create arrow visual placeholder"""
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"

	# Create simple arrow texture
	var img := Image.create(20, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Arrow shaft (brown)
	for x in range(14):
		for y in range(2, 4):
			img.set_pixel(x, y, Color(0.55, 0.35, 0.15))

	# Arrow head (gray triangle)
	for x in range(14, 20):
		var center_y := 2.5
		var progress := float(x - 14) / 6.0
		var half_height := 3.0 * (1.0 - progress)
		for y in range(6):
			if abs(y - center_y) <= half_height:
				img.set_pixel(x, y, Color(0.5, 0.5, 0.55))

	# Fletching (feathers at back)
	for x in range(3):
		img.set_pixel(x, 0, Color(0.7, 0.7, 0.7))
		img.set_pixel(x, 5, Color(0.7, 0.7, 0.7))

	var texture := ImageTexture.create_from_image(img)
	_sprite.texture = texture
	add_child(_sprite)


func _setup_collision() -> void:
	"""Setup collision shape"""
	_collision = CollisionShape2D.new()
	_collision.name = "Collision"

	var circle := CircleShape2D.new()
	circle.radius = 5.0
	_collision.shape = circle
	add_child(_collision)

	# Projectile layer - detect player (Layer 2)
	collision_layer = 0
	collision_mask = 0b00000010  # Layer 2 = Player Body


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	# Move in direction
	var movement := direction * speed * delta
	global_position += movement
	_traveled_distance += movement.length()

	# Rotate sprite to face direction
	_sprite.rotation = direction.angle()

	# Destroy if traveled too far
	if _traveled_distance >= _max_distance:
		_destroy()


func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)


func _on_area_entered(area: Area2D) -> void:
	# Check parent of area
	var parent := area.get_parent()
	if parent is Node2D:
		_handle_hit(parent)


func _handle_hit(target: Node2D) -> void:
	"""Handle hitting something"""
	if not _is_active:
		return

	# Skip if we hit our own owner
	if target == owner_node:
		return

	# Check if it's the player
	if target.is_in_group("player") or target.name == "Player":
		# Check for Cold Parry projectile reflection (Deflective Spin)
		if TalentProcSystem and TalentProcSystem.can_reflect_projectiles():
			_reflect_projectile()
			return

		# Deal damage via PlayerStats (parry check happens inside damage())
		if PlayerStats:
			PlayerStats.damage(damage, "physical", false, global_position)
			Debug.log("Combat", "Enemy projectile hit player for %.0f damage" % damage)
		_destroy()
		return

	# Check if damageable
	if target.has_method("take_damage"):
		target.take_damage(damage, owner_node)
		Debug.log("Combat", "Enemy projectile hit %s for %.0f damage" % [target.name, damage])
		_destroy()


func _reflect_projectile() -> void:
	## Reverse the projectile back at the attacker at 150% damage
	direction = -direction
	damage *= 1.5
	_traveled_distance = 0.0

	# Switch ownership so it can hit enemies
	owner_node = Game.player

	# Update collision mask to hit enemies instead of player
	collision_mask = 0b00000100  # Layer 3 = Enemies

	# Consume the parry window without triggering melee counter-attack
	# Still fire on_parry procs (Master's Riposte heal, etc.)
	TalentProcSystem.on_parry_success(null)
	TalentProcSystem.cancel_parry_window()

	# Visual feedback
	modulate = Color(1.0, 0.85, 0.2)  # Gold tint
	if CombatText and Game.player:
		CombatText.show_custom(Game.player, "REFLECT!", Color(1.0, 0.85, 0.2), 16)

	Debug.log("Combat", "Projectile REFLECTED! Damage: %.0f" % damage)


func _destroy() -> void:
	"""Clean up and remove"""
	_is_active = false

	# Quick fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(queue_free)
