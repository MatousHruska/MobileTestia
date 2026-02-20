extends StaticBody2D
class_name Wall
## Wall - A static wall that blocks movement and projectiles
## Uses Layer 1 (default) for CharacterBody2D collision compatibility
## Added to "walls" group for projectile raycast detection

func _ready() -> void:
	# Keep collision_layer = 1 (default for StaticBody2D)
	# This ensures CharacterBody2D (player/enemies) can collide with walls
	# collision_layer is already 1 by default, no need to set it

	collision_mask = 0  # Walls don't need to detect anything

	# Add to walls group for projectile raycast detection
	add_to_group("walls")
