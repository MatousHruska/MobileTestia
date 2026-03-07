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
var _foot_y := -1.0  ## Bottommost opaque row in texture (image-space), -1 = not computed
var _current_dir := ""  ## Tracked direction for per-direction param/mask switching

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
		# Sync flip_h every frame — flip can change without texture change
		var flip_x := -1.0 if _animated_parent.flip_h else 1.0
		if scale.x != flip_x:
			scale.x = flip_x


func _sync_animated_frame() -> void:
	## Copy the current frame texture from the AnimatedSprite2D parent.
	if not _animated_parent or not _animated_parent.sprite_frames:
		return
	var anim := _animated_parent.animation
	var frame_idx := _animated_parent.frame
	var sf := _animated_parent.sprite_frames

	# Detect direction change from animation name suffix (e.g., "idle_down" → "down")
	var dir := _extract_direction(anim)
	if dir != _current_dir and not dir.is_empty():
		_current_dir = dir
		_apply_per_direction(dir)

	if sf.has_animation(anim) and frame_idx < sf.get_frame_count(anim):
		var frame_tex := sf.get_frame_texture(anim, frame_idx)
		if frame_tex != texture:
			texture = frame_tex
			# Compute foot position once from the first frame we see
			if _foot_y < 0.0:
				_foot_y = _detect_foot_y(frame_tex)
			_update_shadow_transform()


func _detect_foot_y(tex: Texture2D) -> float:
	## Find the bottommost opaque row by scanning the texture's alpha.
	## Unwraps AtlasTexture → CanvasTexture → diffuse chain.
	var img := _get_unwrapped_image(tex)
	if img == null:
		return float(tex.get_height())  # Fallback: assume feet at bottom

	# Scan bottom-up for the first row with any opaque pixel
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.1:
				return float(y + 1)
	return float(tex.get_height())


static func _get_unwrapped_image(tex: Texture2D) -> Image:
	## Unwrap texture chain (AtlasTexture / CanvasTexture) to get pixel data.
	if tex is AtlasTexture:
		var atlas_tex := tex as AtlasTexture
		var atlas_img := _get_unwrapped_image(atlas_tex.atlas)
		if atlas_img:
			var r := atlas_tex.region
			return atlas_img.get_region(Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)))
		return null
	if tex is CanvasTexture:
		var canvas_tex := tex as CanvasTexture
		if canvas_tex.diffuse_texture:
			return _get_unwrapped_image(canvas_tex.diffuse_texture)
		return null
	return tex.get_image()


func _update_shadow_transform() -> void:
	if texture == null:
		return

	var tex_height := float(texture.get_height())

	# foot_y: where the feet actually are in image-space.
	# For static sprites (decorations), feet are at the bottom of the texture.
	# For animated sprites, detected from alpha scan to handle padding.
	var foot_y := _foot_y if _foot_y > 0.0 else tex_height

	# Move the sprite pivot to the foot position using offset.
	# Shift upward by shadow_overlap fraction so the shadow starts under the body.
	var overlap := tex_height * shadow_overlap
	if centered:
		offset = Vector2(0.0, tex_height / 2.0 - foot_y)
		position = Vector2(shadow_offset_x, foot_y - tex_height / 2.0 - overlap + shadow_offset_y)
	else:
		# When parent has a custom offset (e.g. bottom-center anchoring), the shadow
		# must position relative to the texture's visual base, not the node origin.
		offset = Vector2(_parent_offset.x, -foot_y)
		position = Vector2(shadow_offset_x, _parent_offset.y + foot_y - overlap + shadow_offset_y)

	# Flip vertically and stretch by shadow_length.
	# Mirror horizontally when parent AnimatedSprite2D uses flip_h (left-facing).
	var flip_x := -1.0 if (_animated_parent and _animated_parent.flip_h) else 1.0
	scale = Vector2(flip_x, -shadow_length)

	# Rotation pivots around the trunk base (set by offset above)
	rotation = shadow_angle


func _extract_direction(anim: StringName) -> String:
	## Parse direction suffix from animation name (e.g., "idle_down" → "down").
	## Returns "" if no recognized direction suffix found.
	var anim_str := String(anim)
	for dir in ["down", "up", "right", "left"]:
		if anim_str.ends_with("_" + dir):
			# Left reuses right params (flip_h handles mirroring)
			return "right" if dir == "left" else dir
	return ""


func _apply_per_direction(dir: String) -> void:
	## Apply per-direction shadow params and mask from metadata set by CharacterVisuals.
	var params_per_dir: Dictionary = get_meta("shadow_params_per_dir", {})
	if params_per_dir.has(dir):
		apply_params(params_per_dir[dir])

	var masks_per_dir: Dictionary = get_meta("shadow_masks_per_dir", {})
	if masks_per_dir.has(dir):
		set_shadow_mask(masks_per_dir[dir])
	elif _shadow_material:
		# Clear mask if this direction has none
		_shadow_material.set_shader_parameter("shadow_mask", null)
