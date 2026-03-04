## Attaches a projected silhouette shadow to a Sprite2D.
## Add as a child of any Sprite2D — it reads the parent's texture automatically.
class_name SilhouetteShadow
extends Sprite2D

## How far the shadow stretches (1.0 = same height as sprite).
@export_range(0.1, 3.0) var shadow_length := 1.0
## Skew angle in radians — controls shadow cast direction.
## Positive = shadow falls to the right. ~0.5-0.8 looks good for isometric.
@export_range(-1.5, 1.5) var shadow_skew := 0.5
## Shadow opacity (0.0 = invisible, 1.0 = solid black).
@export_range(0.0, 1.0) var shadow_opacity := 0.3

var _shadow_material: ShaderMaterial

func _ready() -> void:
	var shader := load("res://shaders/silhouette_shadow.gdshader") as Shader
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = shader
	_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, shadow_opacity))
	material = _shadow_material
	z_index = -1

	# Copy texture from parent Sprite2D if we don't have one set
	if texture == null and get_parent() is Sprite2D:
		texture = (get_parent() as Sprite2D).texture
		centered = (get_parent() as Sprite2D).centered

	_update_shadow_transform()


func _update_shadow_transform() -> void:
	if texture == null:
		return

	var tex_height := float(texture.get_height())

	# Flip vertically and stretch by shadow_length
	scale = Vector2(1.0, -shadow_length)

	# Apply skew for directional projection
	skew = shadow_skew

	# Position the shadow so it starts at the parent sprite's base.
	# For a centered sprite, the base is at +tex_height/2 relative to origin.
	# The flipped shadow center needs to be at base + tex_height/2 (so the
	# flipped top edge aligns with the base).
	if centered:
		position = Vector2(0.0, tex_height)
	else:
		# For non-centered sprites (offset = bottom-center or top-left), adjust
		position = Vector2(0.0, 0.0)
