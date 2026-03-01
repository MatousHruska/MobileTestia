extends RefCounted
class_name DecorationSpawner
## Loads and spawns decoration entities with normal maps, occluders, and baked shadows.
## Resources are cached per decoration_id for reuse across instances.

const DECORATIONS_DIR := "res://assets/decorations/"

## Cache: decoration_id -> { texture, normal_map, occluder, shadow }
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

	# Main sprite
	var sprite := Sprite2D.new()
	sprite.texture = assets.texture
	if assets.normal_map:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = _get_normal_shader()
		shader_mat.set_shader_parameter("normal_texture", assets.normal_map)
		sprite.material = shader_mat
	node.add_child(sprite)

	# Shadow handling
	var shadow_mode: String = data.get("shadow_mode", "baked")
	match shadow_mode:
		"realtime":
			if assets.occluder:
				var occluder := LightOccluder2D.new()
				occluder.occluder_polygon = assets.occluder
				node.add_child(occluder)
		"baked":
			if assets.shadow:
				var shadow_sprite := Sprite2D.new()
				shadow_sprite.texture = assets.shadow
				shadow_sprite.z_index = -1  # Draw behind the decoration
				node.add_child(shadow_sprite)

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
		"shadow": null
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

	# Baked shadow (optional)
	var shadow_path := base_path + "shadow.png"
	if ResourceLoader.exists(shadow_path):
		assets.shadow = load(shadow_path)

	_cache[deco_id] = assets
	Debug.log("DecorationSpawner", "Loaded assets for '%s': texture=%s, normal=%s, occluder=%s, shadow=%s" % [
		deco_id,
		assets.texture != null,
		assets.normal_map != null,
		assets.occluder != null,
		assets.shadow != null
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
