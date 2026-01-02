extends StaticBody2D
class_name Wall
## Wall - A static wall that blocks projectiles
## Automatically sets collision layer 3 and adds to "walls" group

func _ready() -> void:
	# Set collision layer to layer 3 (obstacles/walls)
	collision_layer = 0b00000100  # Layer 3
	collision_mask = 0  # Walls don't detect anything

	# Add to walls group for projectile detection
	add_to_group("walls")
