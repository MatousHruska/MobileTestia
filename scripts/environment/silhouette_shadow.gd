## Attaches a projected silhouette shadow to a Sprite2D or AnimatedSprite2D.
## Add as a child of either — it reads the parent's texture automatically.
class_name SilhouetteShadow
extends Sprite2D

## How far the shadow stretches (1.0 = same height as sprite).
@export_range(0.1, 3.0) var shadow_length := 1.0
## Rotation angle in radians — rotates the shadow around the trunk base.
@export_range(-3.14, 3.14) var shadow_angle := 0.5
## Extra horizontal offset in pixels.
@export var shadow_offset_x := 0.0
## Extra vertical offset in pixels.
@export var shadow_offset_y := 0.0
## Shadow opacity (0.0 = invisible, 1.0 = solid black).
@export_range(0.0, 1.0) var shadow_opacity := 0.3
## How far up into the tree the shadow starts (fraction of texture height).
@export_range(0.0, 0.5) var shadow_overlap := 0.25

var _shadow_material: ShaderMaterial
var _parent_offset := Vector2.ZERO  ## Parent sprite's offset (for bottom-center anchoring)
var _pending_mask: Texture2D  ## Mask set before _ready() — applied once material exists
var _animated_parent: AnimatedSprite2D  ## Non-null when parent is AnimatedSprite2D

func _ready() -> void:
	add_to_group("shadows")

	var shader := load("res://shaders/silhouette_shadow.gdshader") as Shader
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = shader
	_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, shadow_opacity))
	material = _shadow_material
	show_behind_parent = true

	# Copy texture from parent sprite if we don't have one set
	if texture == null:
		if get_parent() is AnimatedSprite2D:
			_animated_parent = get_parent() as AnimatedSprite2D
			centered = _animated_parent.centered
			_parent_offset = _animated_parent.offset
			_sync_animated_frame()
		elif get_parent() is Sprite2D:
			var parent_sprite := get_parent() as Sprite2D
			texture = parent_sprite.texture
			centered = parent_sprite.centered
			_parent_offset = parent_sprite.offset

	# Self-configure from current ZoneMood (handles late-spawned shadows)
	var env_mgr := get_node_or_null("/root/EnvironmentManager")
	if env_mgr and env_mgr.current_mood:
		shadow_angle = env_mgr.current_mood.shadow_angle
		shadow_opacity = env_mgr.current_mood.shadow_opacity
		_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, shadow_opacity))

	# Apply mask that was set before _ready() (material didn't exist yet)
	if _pending_mask:
		_shadow_material.set_shader_parameter("shadow_mask", _pending_mask)
		_pending_mask = null

	_update_shadow_transform()


## Call this to apply parameter changes at runtime.
func apply_params(params: Dictionary) -> void:
	if params.has("length"): shadow_length = params["length"]
	if params.has("angle"): shadow_angle = params["angle"]
	if params.has("offset_x"): shadow_offset_x = params["offset_x"]
	if params.has("offset_y"): shadow_offset_y = params["offset_y"]
	if params.has("opacity"): shadow_opacity = params["opacity"]
	if params.has("overlap"): shadow_overlap = params["overlap"]
	if _shadow_material:
		_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, shadow_opacity))
	_update_shadow_transform()


## Apply an alpha mask texture to selectively hide parts of the shadow.
## The mask is a grayscale texture where white = opaque, black = transparent.
func set_shadow_mask(mask_texture: Texture2D) -> void:
	if _shadow_material:
		_shadow_material.set_shader_parameter("shadow_mask", mask_texture)
	else:
		_pending_mask = mask_texture


func _process(_delta: float) -> void:
	if _animated_parent:
		_sync_animated_frame()


func _sync_animated_frame() -> void:
	## Copy the current frame texture from the AnimatedSprite2D parent.
	if not _animated_parent or not _animated_parent.sprite_frames:
		return
	var anim := _animated_parent.animation
	var frame_idx := _animated_parent.frame
	var sf := _animated_parent.sprite_frames
	if sf.has_animation(anim) and frame_idx < sf.get_frame_count(anim):
		var frame_tex := sf.get_frame_texture(anim, frame_idx)
		if frame_tex != texture:
			texture = frame_tex
			_update_shadow_transform()


func _update_shadow_transform() -> void:
	if texture == null:
		return

	var tex_height := float(texture.get_height())

	# Move the sprite pivot to the trunk base (bottom of texture) using offset.
	# Shift upward into the tree by shadow_overlap fraction so the shadow starts
	# under the trunk. show_behind_parent hides this overlap.
	var overlap := tex_height * shadow_overlap
	if centered:
		offset = Vector2(0.0, -tex_height / 2.0)
		position = Vector2(shadow_offset_x, tex_height / 2.0 - overlap + shadow_offset_y)
	else:
		# When parent has a custom offset (e.g. bottom-center anchoring), the shadow
		# must position relative to the texture's visual base, not the node origin.
		offset = Vector2(_parent_offset.x, -tex_height)
		position = Vector2(shadow_offset_x, _parent_offset.y + tex_height - overlap + shadow_offset_y)

	# Flip vertically and stretch by shadow_length
	scale = Vector2(1.0, -shadow_length)

	# Rotation pivots around the trunk base (set by offset above)
	rotation = shadow_angle
