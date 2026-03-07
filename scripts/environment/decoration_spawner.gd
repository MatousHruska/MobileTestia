class_name DecorationSpawner
extends RefCounted
## Loads and spawns decoration entities with normal maps and occluders.
## Resources are cached per decoration_id for reuse across instances.

const DECORATIONS_DIR := "res://assets/decorations/"
const HIDE_BEHIND_OPACITY := 0.3
const HIDE_BEHIND_FADE_DURATION := 0.2

## Cache: decoration_id -> { texture, normal_map, occluder }
static var _cache: Dictionary = {}


static func spawn(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
	var deco_id: String = data.get("decoration_id", "")

	if deco_id.is_empty():
		Debug.warn("DecorationSpawner", "Empty decoration_id at %s" % world_pos)
		return null

	var assets := _load_assets(deco_id)
	if assets.texture == null:
		Debug.warn("DecorationSpawner", "No sprite.png found for decoration '%s'" % deco_id)
		return null

	# Root node
	var node := Node2D.new()
	node.name = "Deco_%s_%d_%d" % [deco_id, int(world_pos.x), int(world_pos.y)]
	node.position = world_pos - chunk_origin

	# Scale and flip
	var deco_scale: float = data.get("scale", 1.0)
	var flip_x: bool = data.get("flip_x", false)
	node.scale = Vector2(-deco_scale if flip_x else deco_scale, deco_scale)

	# Anchor offset: bottom-center so the node position = ground contact point.
	# All child sprites and occluders use this offset for consistency.
	var tex_size := Vector2(assets.texture.get_size())
	var anchor_offset := Vector2(-tex_size.x / 2.0, -tex_size.y)

	# Main sprite — anchored at bottom-center
	var sprite := Sprite2D.new()
	sprite.texture = assets.texture
	sprite.centered = false
	sprite.offset = anchor_offset
	if assets.normal_map:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _get_normal_shader()
		shader_mat.set_shader_parameter("normal_texture", assets.normal_map)
		sprite.material = shader_mat
	node.add_child(sprite)

	# Light occluder (blocks light for 2D lighting)
	if assets.occluder:
		var occluder := LightOccluder2D.new()
		occluder.occluder = assets.occluder
		# Occluder polygon is in image-space (top-left origin),
		# offset to match the bottom-center anchored sprite.
		occluder.position = anchor_offset
		node.add_child(occluder)

	# Shadow (per-decoration params from shadow.json, global angle/opacity from ZoneMood)
	if assets.shadow_params != null:
		var shadow := SilhouetteShadow.new()
		shadow.name = "Shadow"
		sprite.add_child(shadow)  # Child of Sprite2D — reads parent texture in _ready()
		shadow.apply_params(assets.shadow_params)
		if assets.shadow_mask:
			shadow.set_shadow_mask(assets.shadow_mask)

	# Hide-behind: fade decoration when player walks behind it
	var hide_behind: bool = assets.shadow_params.get("hide_behind", false) if assets.shadow_params else false
	if hide_behind and assets.occluder:
		var area := Area2D.new()
		area.name = "HideBehindArea"
		area.collision_layer = 0
		area.collision_mask = 2  # Detect player body (layer 2)
		var col_poly := CollisionPolygon2D.new()
		col_poly.polygon = assets.occluder.polygon
		area.add_child(col_poly)
		# Occluder polygon is in image-space; offset to match bottom-center anchor
		area.position = anchor_offset
		node.add_child(area)

		area.body_entered.connect(func(_body: Node2D) -> void:
			var tw := sprite.create_tween()
			tw.tween_property(sprite, "self_modulate:a", HIDE_BEHIND_OPACITY, HIDE_BEHIND_FADE_DURATION)
		)
		area.body_exited.connect(func(_body: Node2D) -> void:
			var tw := sprite.create_tween()
			tw.tween_property(sprite, "self_modulate:a", 1.0, HIDE_BEHIND_FADE_DURATION)
		)

	# Z-sorting / depth mode
	var z_mode: String = data.get("z_mode", "y_sort")
	match z_mode:
		"y_sort":
			node.z_index = 0
		"fixed_back":
			node.z_index = -5
		"fixed_front":
			node.z_index = 10

	# Metadata
	node.set_meta("chunk_spawned", true)
	node.set_meta("chunk_id", chunk_id)
	node.set_meta("decoration_id", deco_id)

	parent.add_child(node)
	node.add_to_group("decorations")
	return node


static func _load_assets(deco_id: String) -> Dictionary:
	## Load or retrieve cached decoration assets.
	if _cache.has(deco_id):
		return _cache[deco_id]

	var base_path := DECORATIONS_DIR + deco_id + "/"
	var assets := {
		"texture": null,
		"normal_map": null,
		"occluder": null,
		"shadow_params": null,
		"shadow_mask": null,
	}

	# Sprite (required)
	var sprite_path := base_path + "sprite.png"
	if ResourceLoader.exists(sprite_path):
		assets.texture = load(sprite_path)

	# Normal map (optional)
	var normal_path := base_path + "normal.png"
	if ResourceLoader.exists(normal_path):
		assets.normal_map = load(normal_path)

	# Occluder (optional)
	var occluder_path := base_path + "occluder.tres"
	if ResourceLoader.exists(occluder_path):
		assets.occluder = load(occluder_path)

	# Shadow params (optional JSON)
	var shadow_path := base_path + "shadow.json"
	if FileAccess.file_exists(shadow_path):
		var file := FileAccess.open(shadow_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				assets.shadow_params = json.data

	# Shadow alpha mask (optional grayscale PNG)
	var mask_path := base_path + "shadow_mask.png"
	if ResourceLoader.exists(mask_path):
		var mask_tex := load(mask_path) as Texture2D
		if mask_tex:
			assets.shadow_mask = mask_tex

	_cache[deco_id] = assets
	Debug.log("DecorationSpawner", "Loaded assets for '%s': texture=%s, normal=%s, occluder=%s, shadow=%s, mask=%s" % [
		deco_id,
		assets.texture != null,
		assets.normal_map != null,
		assets.occluder != null,
		assets.shadow_params != null,
		assets.shadow_mask != null,
	])
	return assets


## Shared normal map shader — renders sprite with normal map for 2D lighting interaction.
static var _normal_shader: Shader
static func _get_normal_shader() -> Shader:
	if _normal_shader:
		return _normal_shader
	_normal_shader = Shader.new()
	_normal_shader.code = """
shader_type canvas_item;

uniform sampler2D normal_texture : hint_normal;

void fragment() {
	COLOR = texture(TEXTURE, UV);
	NORMAL_MAP = texture(normal_texture, UV).rgb;
}
"""
	return _normal_shader
