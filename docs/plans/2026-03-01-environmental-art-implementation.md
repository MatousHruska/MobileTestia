# Environmental Art System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the lighting-first environmental art system — zone ambient moods, enhanced PointLight2D with flicker/shadows, decoration entity pipeline with normal maps and occluders, and zone particle effects.

**Architecture:** A new `EnvironmentManager` autoload orchestrates zone mood (CanvasModulate + WorldEnvironment), a `DecorationSpawner` handles decoration entity loading with resource caching, and particles are managed per-zone by `ZoneParticleManager`. All systems configure from `ZoneMood` resource files.

**Tech Stack:** Godot 4 (GDScript), PointLight2D, LightOccluder2D, CanvasModulate, WorldEnvironment, GPUParticles2D, custom Resource classes.

---

### Task 1: ZoneMood Resource

Define the data structure that holds all atmospheric settings for a zone.

**Files:**
- Create: `scripts/environment/zone_mood.gd`

**Step 1: Create the ZoneMood resource class**

```gdscript
@tool
extends Resource
class_name ZoneMood
## Defines the atmospheric mood for a zone — ambient lighting, bloom, particles, shadow mode.

@export_group("Ambient")
@export var ambient_color: Color = Color(0.8, 0.75, 0.7, 1.0)  ## CanvasModulate color

@export_group("Bloom")
@export var bloom_enabled: bool = true
@export var bloom_intensity: float = 0.8
@export var bloom_threshold: float = 0.7  ## Only bright things glow

@export_group("Particles")
@export var particle_type: String = ""  ## "snow", "dust_motes", "embers", or "" for none
@export var particle_tint: Color = Color.WHITE

@export_group("Shadows")
@export var realtime_shadows: bool = false  ## true for caves/interiors, false for outdoor
```

**Step 2: Commit**

```bash
git add scripts/environment/zone_mood.gd
git commit -m "feat(env): add ZoneMood resource class for zone atmosphere config"
```

---

### Task 2: EnvironmentManager Autoload

New singleton that applies a ZoneMood to the scene — creates/updates CanvasModulate and WorldEnvironment.

**Files:**
- Create: `autoloads/environment_manager.gd`
- Modify: `project.godot` (add autoload)

**Step 1: Create EnvironmentManager**

```gdscript
extends Node
class_name EnvironmentManagerClass
## Manages zone atmosphere — applies ZoneMood settings to CanvasModulate and WorldEnvironment.

var _canvas_modulate: CanvasModulate
var _world_env: WorldEnvironment
var _environment: Environment
var current_mood: ZoneMood

func _ready() -> void:
	# Create CanvasModulate for ambient color
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "ZoneAmbient"
	_canvas_modulate.color = Color.WHITE  # neutral until mood is set
	add_child(_canvas_modulate)

	# Create WorldEnvironment for bloom
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CANVAS
	_environment.glow_enabled = false
	_world_env = WorldEnvironment.new()
	_world_env.name = "ZoneBloom"
	_world_env.environment = _environment
	add_child(_world_env)


func apply_mood(mood: ZoneMood) -> void:
	## Apply a ZoneMood to the scene. Call from zone_base._ready().
	current_mood = mood

	# Ambient
	_canvas_modulate.color = mood.ambient_color

	# Bloom
	_environment.glow_enabled = mood.bloom_enabled
	if mood.bloom_enabled:
		_environment.glow_intensity = mood.bloom_intensity
		_environment.glow_bloom = 0.3
		_environment.glow_hdr_threshold = mood.bloom_threshold
		_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	Debug.log("Environment", "Applied mood: ambient=%s, bloom=%s (intensity=%.1f)" % [
		mood.ambient_color, mood.bloom_enabled, mood.bloom_intensity if mood.bloom_enabled else 0.0
	])


func clear_mood() -> void:
	## Reset to neutral — called when leaving a zone.
	current_mood = null
	_canvas_modulate.color = Color.WHITE
	_environment.glow_enabled = false
```

**Step 2: Register as autoload in project.godot**

Add `EnvironmentManager` autoload entry (after InteriorManager or at end of autoloads section).

**Step 3: Commit**

```bash
git add autoloads/environment_manager.gd project.godot
git commit -m "feat(env): add EnvironmentManager autoload for zone mood rendering"
```

---

### Task 3: Wire ZoneMood into ZoneBase

Connect the mood system to zone loading/unloading.

**Files:**
- Modify: `scripts/world/zone_base.gd` (lines 7-17 exports, line 58 init, line 219 cleanup)

**Step 1: Add ZoneMood export to ZoneBase**

At `zone_base.gd:17` (after `use_chunk_system` export), add:

```gdscript
@export_group("Atmosphere")
@export var zone_mood: ZoneMood  ## Zone lighting/bloom/particle preset
```

This lets each zone scene (.tscn) have a ZoneMood resource assigned in the inspector.

**Step 2: Apply mood in _ready()**

In `zone_base.gd`, after the ChunkManager initialization block (after line 64), add:

```gdscript
	# Apply zone atmosphere
	if zone_mood:
		var env_mgr = get_node_or_null("/root/EnvironmentManager")
		if env_mgr:
			env_mgr.apply_mood(zone_mood)
```

**Step 3: Clear mood in _exit_tree()**

In `zone_base.gd`, inside the `_exit_tree()` function (after line 221 ChunkManager cleanup), add:

```gdscript
	# Clear zone atmosphere
	var env_mgr = get_node_or_null("/root/EnvironmentManager")
	if env_mgr:
		env_mgr.clear_mood()
```

**Step 4: Commit**

```bash
git add scripts/world/zone_base.gd
git commit -m "feat(env): wire ZoneMood into ZoneBase ready/exit lifecycle"
```

---

### Task 4: Create Test ZoneMood Resources

Create mood presets for testing.

**Files:**
- Create: `resources/zone_moods/deep_cave.tres`
- Create: `resources/zone_moods/snowy_mountain.tres`
- Create: `resources/zone_moods/lava_cave.tres`
- Create: `resources/zone_moods/town_safe.tres`

**Step 1: Create mood .tres files**

These are Godot Resource files. Create them programmatically or via the inspector. Example for deep_cave:

```tres
[gd_resource type="Resource" script_class="ZoneMood" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/environment/zone_mood.gd" id="1"]

[resource]
script = ExtResource("1")
ambient_color = Color(0.094, 0.094, 0.133, 1)
bloom_enabled = true
bloom_intensity = 1.0
bloom_threshold = 0.6
particle_type = "dust_motes"
particle_tint = Color(1, 0.9, 0.7, 1)
realtime_shadows = true
```

Create similar for:
- `snowy_mountain.tres`: ambient `Color(0.4, 0.47, 0.67)`, bloom intensity 0.5, threshold 0.8, particle "snow", tint white, realtime_shadows false
- `lava_cave.tres`: ambient `Color(0.133, 0.067, 0.067)`, bloom intensity 1.2, threshold 0.5, particle "embers", tint deep orange, realtime_shadows true
- `town_safe.tres`: ambient `Color(0.73, 0.67, 0.6)`, bloom intensity 0.3, threshold 0.9, no particles, realtime_shadows false

**Step 2: Assign a mood to a test zone**

In the zone_ldtk_test.tscn, set the `zone_mood` export to one of these resources for testing.

**Step 3: Commit**

```bash
git add resources/zone_moods/ scenes/world/zone_ldtk_test.tscn
git commit -m "feat(env): add test ZoneMood resources (cave, mountain, lava, town)"
```

---

### Task 5: Enhanced Light Spawning — Flicker Animation

Add light type identification and flicker behavior to existing PointLight2D spawning.

**Files:**
- Modify: `ldtk_importer.gd` (line 755 lightsource match case)
- Modify: `autoloads/chunk_manager.gd` (lines 1756-1789 `_spawn_light`)

**Step 1: Add `light_type` field to LDtk importer**

In `ldtk_importer.gd`, the lightsource extraction (line 755-765), add a `light_type` field:

```gdscript
			"lightsource":
				var color_val = fields.get("light_color", "#FFAA44")
				result.lights.append({
					"zone_id": zone_id,
					"position_x": position.x,
					"position_y": position.y,
					"color": color_val if color_val != null else "#FFAA44",
					"intensity": float(fields.get("intensity", 1.5)),
					"radius": int(fields.get("radius", 128)),
					"height": float(fields.get("height", 50.0)),
					"light_type": fields.get("light_type", "torch")
				})
```

Also add to the export processing in `_export_entities_summary()` (around line 963-969):

```gdscript
		zones_data[zone_id].lights.append({
			"position": {"x": light.get("position_x", 0), "y": light.get("position_y", 0)},
			"color": light.get("color", "#FFAA44"),
			"intensity": light.get("intensity", 1.5),
			"radius": light.get("radius", 128),
			"height": light.get("height", 50.0),
			"light_type": light.get("light_type", "torch")
		})
```

**Step 2: Add flicker + shadow to `_spawn_light` in chunk_manager.gd**

Replace the `_spawn_light` function (lines 1756-1789) to add flicker animation and shadow support:

```gdscript
func _spawn_light(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))

	var light := PointLight2D.new()
	light.name = "Light_%d_%d" % [int(world_pos.x), int(world_pos.y)]
	light.position = world_pos - chunk_origin

	# Color (hex string from LDtk)
	var color_str: String = data.get("color", "#FFAA44")
	light.color = Color.html(color_str)

	# Intensity
	var base_energy: float = float(data.get("intensity", 1.5))
	light.energy = base_energy

	# Height (for normal map interaction)
	light.height = float(data.get("height", 50.0))

	# Texture and scale
	var texture := _get_light_texture()
	light.texture = texture
	var radius: float = float(data.get("radius", 128))
	light.texture_scale = radius / (texture.width * 0.5)

	# Shadow — enabled based on zone mood setting
	var env_mgr = get_node_or_null("/root/EnvironmentManager")
	if env_mgr and env_mgr.current_mood:
		light.shadow_enabled = env_mgr.current_mood.realtime_shadows
	else:
		light.shadow_enabled = false

	# Flicker animation based on light type
	var light_type: String = data.get("light_type", "torch")
	match light_type:
		"torch", "campfire":
			_start_flicker(light, base_energy, 0.15, 0.08)
		"crystal":
			_start_flicker(light, base_energy, 0.08, 2.0)
		"lava":
			_start_flicker(light, base_energy, 0.1, 1.5)
		# "moonlight", "static" — no animation

	# Metadata
	light.set_meta("chunk_spawned", true)
	light.set_meta("chunk_id", chunk_id)
	light.set_meta("world_position", world_pos)
	light.set_meta("light_radius", radius)

	parent.add_child(light)
	light.add_to_group("lights")
	Debug.log("ChunkManager", "Spawned light at %s (type=%s, color=%s, radius=%.0f)" % [world_pos, light_type, color_str, radius])
	return light
```

**Step 3: Add `_start_flicker` helper function**

Add after `_spawn_light` in chunk_manager.gd:

```gdscript
func _start_flicker(light: PointLight2D, base_energy: float, intensity_range: float, speed: float) -> void:
	## Animate light energy with a random flicker effect using a looping tween.
	var tween := create_tween()
	tween.set_loops()
	var min_e := base_energy - intensity_range
	var max_e := base_energy + intensity_range
	tween.tween_property(light, "energy", max_e, speed * randf_range(0.8, 1.2)).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "energy", min_e, speed * randf_range(0.8, 1.2)).set_trans(Tween.TRANS_SINE)
```

**Step 4: Commit**

```bash
git add ldtk_importer.gd autoloads/chunk_manager.gd
git commit -m "feat(env): light flicker animation and shadow support per zone mood"
```

---

### Task 6: Decoration Entity in LDtk Importer

Add the Decoration entity type to the LDtk import pipeline.

**Files:**
- Modify: `ldtk_importer.gd` (lines 80-99 entity dict, line 754+ entity match, lines 1004-1026 zone data init, lines 959-969 export processing, lines 976-1001 summary print)

**Step 1: Add "decorations" array to entity dictionaries**

In `ldtk_importer.gd`, add to `all_entities` (after line 98 `"lights": []`):

```gdscript
		# Decorations
		"decorations": []
```

Add the same to `_ensure_zone_data()` (after line 1025 `"lights": []`):

```gdscript
			# Decorations
			"decorations": []
```

**Step 2: Add decoration entity extraction**

In `_extract_entities()`, after the lightsource match case (line 765), add:

```gdscript
			"decoration":
				result.decorations.append({
					"zone_id": zone_id,
					"position_x": position.x,
					"position_y": position.y,
					"decoration_id": fields.get("decoration_id", ""),
					"scale": float(fields.get("scale", 1.0)),
					"flip_x": fields.get("flip_x", false),
					"z_mode": fields.get("z_mode", "y_sort"),
					"shadow_mode": fields.get("shadow_mode", "baked")
				})
```

**Step 3: Add decoration export processing**

In `_export_entities_summary()`, after the lights processing block (line 969), add:

```gdscript
	# Process decorations
	for deco in entities.decorations:
		var zone_id: String = deco.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].decorations.append({
			"position": {"x": deco.get("position_x", 0), "y": deco.get("position_y", 0)},
			"decoration_id": deco.get("decoration_id", ""),
			"scale": deco.get("scale", 1.0),
			"flip_x": deco.get("flip_x", false),
			"z_mode": deco.get("z_mode", "y_sort"),
			"shadow_mode": deco.get("shadow_mode", "baked")
		})
```

**Step 4: Update entity count and summary print**

In the summary section (line 983), add decorations to the count:

```gdscript
		entity_count += zd.lights.size() + zd.decorations.size()
```

Add print for decorations:

```gdscript
		if zd.decorations.size() > 0:
			print("    decorations: %d" % [zd.decorations.size()])
```

**Step 5: Commit**

```bash
git add ldtk_importer.gd
git commit -m "feat(env): add Decoration entity type to LDtk importer pipeline"
```

---

### Task 7: DecorationSpawner

Create the runtime decoration loader with resource caching, normal maps, and occluder support.

**Files:**
- Create: `scripts/environment/decoration_spawner.gd`

**Step 1: Create DecorationSpawner**

```gdscript
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
		var mat := CanvasItemMaterial.new()
		sprite.material = mat
		sprite.texture = assets.texture
		# Normal map is set via the sprite's CanvasItem material
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
			node.y_sort_enabled = false  # Parent handles y-sorting
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
```

**Step 2: Commit**

```bash
git add scripts/environment/decoration_spawner.gd
git commit -m "feat(env): add DecorationSpawner with normal map, occluder, and shadow support"
```

---

### Task 8: Wire DecorationSpawner into ChunkManager

Add decoration spawning to the existing entity loop.

**Files:**
- Modify: `autoloads/chunk_manager.gd` (lines 996-1003 after lights spawning)

**Step 1: Add decoration spawning loop**

In `_spawn_chunk_entities()`, after the lights spawning block (line 1003) and before the tracking block (line 1005), add:

```gdscript
	# Spawn decorations
	for deco_data in _zone_entities.get("decorations", []):
		var pos: Dictionary = deco_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := DecorationSpawner.spawn(deco_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)
```

**Step 2: Enable y_sort on chunk root**

In the chunk node creation code (find where chunk_node is created in `_create_chunk_tilemap` or similar), ensure `y_sort_enabled = true` is set on the chunk's parent so decorations sort correctly with characters.

Check if `_chunk_root` already has y_sort. If not, add it in `initialize_for_zone()`:

```gdscript
	_chunk_root.y_sort_enabled = true
```

**Step 3: Commit**

```bash
git add autoloads/chunk_manager.gd
git commit -m "feat(env): wire decoration spawning into ChunkManager entity loop"
```

---

### Task 9: ZoneParticleManager

Create particle systems that activate per zone mood.

**Files:**
- Create: `scripts/environment/zone_particle_manager.gd`
- Modify: `autoloads/environment_manager.gd` (add particle management)

**Step 1: Create ZoneParticleManager**

```gdscript
extends Node2D
class_name ZoneParticleManager
## Manages zone-wide particle effects (snow, dust motes, embers).
## Attaches to the camera to follow the player.

var _active_particles: GPUParticles2D
var _camera: Camera2D


func setup(camera: Camera2D) -> void:
	_camera = camera


func _process(_delta: float) -> void:
	# Follow camera position so particles cover the viewport
	if _camera and is_instance_valid(_camera):
		global_position = _camera.global_position


func activate(particle_type: String, tint: Color) -> void:
	## Start the specified particle system.
	deactivate()

	match particle_type:
		"snow":
			_active_particles = _create_snow(tint)
		"dust_motes":
			_active_particles = _create_dust_motes(tint)
		"embers":
			_active_particles = _create_embers(tint)
		_:
			return

	add_child(_active_particles)


func deactivate() -> void:
	## Stop and remove current particle system.
	if _active_particles and is_instance_valid(_active_particles):
		_active_particles.queue_free()
		_active_particles = null


func _create_snow(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "SnowParticles"
	particles.amount = 60
	particles.lifetime = 5.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.2, 1.0, 0)
	mat.spread = 15.0
	mat.gravity = Vector3(10, 30, 0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 10, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.6)
	particles.process_material = mat

	# Small white dot texture (1x1 stretched)
	particles.texture = _create_dot_texture(Color.WHITE, 4)
	return particles


func _create_dust_motes(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "DustParticles"
	particles.amount = 20
	particles.lifetime = 8.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -0.3, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, -2, 0)
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.scale_min = 0.3
	mat.scale_max = 1.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 250, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.3)
	particles.process_material = mat

	particles.texture = _create_dot_texture(Color.WHITE, 3)
	return particles


func _create_embers(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "EmberParticles"
	particles.amount = 15
	particles.lifetime = 3.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(5, -15, 0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 250, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.7)
	particles.process_material = mat

	particles.texture = _create_dot_texture(Color.WHITE, 3)
	return particles


func _create_dot_texture(color: Color, size: int) -> ImageTexture:
	## Create a small dot texture for particles.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
```

**Step 2: Commit**

```bash
git add scripts/environment/zone_particle_manager.gd
git commit -m "feat(env): add ZoneParticleManager with snow, dust motes, and embers"
```

---

### Task 10: Wire Particles into EnvironmentManager

Connect particle activation to mood application.

**Files:**
- Modify: `autoloads/environment_manager.gd`

**Step 1: Add particle management to EnvironmentManager**

Add a `_particle_manager` member and create/manage it alongside mood:

```gdscript
var _particle_manager: ZoneParticleManager

func apply_mood(mood: ZoneMood) -> void:
	current_mood = mood

	# Ambient
	_canvas_modulate.color = mood.ambient_color

	# Bloom
	_environment.glow_enabled = mood.bloom_enabled
	if mood.bloom_enabled:
		_environment.glow_intensity = mood.bloom_intensity
		_environment.glow_bloom = 0.3
		_environment.glow_hdr_threshold = mood.bloom_threshold
		_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Particles
	if not mood.particle_type.is_empty():
		_ensure_particle_manager()
		_particle_manager.activate(mood.particle_type, mood.particle_tint)
	elif _particle_manager:
		_particle_manager.deactivate()

	Debug.log("Environment", "Applied mood: ambient=%s, bloom=%s, particles=%s" % [
		mood.ambient_color, mood.bloom_enabled, mood.particle_type
	])


func clear_mood() -> void:
	current_mood = null
	_canvas_modulate.color = Color.WHITE
	_environment.glow_enabled = false
	if _particle_manager:
		_particle_manager.deactivate()


func _ensure_particle_manager() -> void:
	if _particle_manager and is_instance_valid(_particle_manager):
		return
	_particle_manager = ZoneParticleManager.new()
	_particle_manager.name = "ZoneParticles"
	add_child(_particle_manager)
	# Find the game camera
	var camera := get_viewport().get_camera_2d()
	if camera:
		_particle_manager.setup(camera)
```

**Step 2: Commit**

```bash
git add autoloads/environment_manager.gd
git commit -m "feat(env): wire ZoneParticleManager into EnvironmentManager mood lifecycle"
```

---

### Task 11: Torch Spark Particles (Per-Light)

Add small spark particle emitters to torch/campfire light sources.

**Files:**
- Modify: `autoloads/chunk_manager.gd` (in `_spawn_light` function)

**Step 1: Add spark emitter to torch lights**

In the `_spawn_light` function, after the flicker setup and before the metadata block, add:

```gdscript
	# Torch spark particles
	if light_type in ["torch", "campfire"]:
		var sparks := _create_torch_sparks()
		light.add_child(sparks)
```

**Step 2: Add `_create_torch_sparks` function**

```gdscript
func _create_torch_sparks() -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "TorchSparks"
	particles.amount = 5
	particles.lifetime = 1.0
	particles.visibility_rect = Rect2(-32, -64, 64, 80)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(0, -20, 0)
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 25.0
	mat.scale_min = 0.3
	mat.scale_max = 0.8

	# Orange to red fade
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.7, 0.2, 0.9))
	gradient.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	particles.process_material = mat

	# Tiny dot texture
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	particles.texture = ImageTexture.create_from_image(img)

	return particles
```

**Step 3: Commit**

```bash
git add autoloads/chunk_manager.gd
git commit -m "feat(env): add torch spark particle emitters to torch/campfire lights"
```

---

### Task 12: Placeholder Decoration Assets for Testing

Create a few simple placeholder decoration folders so the pipeline can be tested end-to-end.

**Files:**
- Create: `assets/decorations/test_rock/sprite.png` (simple gray rock shape)
- Create: `assets/decorations/test_pillar/sprite.png` (simple pillar shape)

**Step 1: Create placeholder decorations via a tool script**

Create a small tool script that generates simple placeholder decoration sprites (colored shapes on transparent backgrounds) for testing the pipeline:

```gdscript
# scripts/tools/generate_placeholder_decorations.gd
@tool
extends EditorScript

func _run() -> void:
	_create_decoration("test_rock", Color(0.4, 0.4, 0.45), Vector2i(24, 18))
	_create_decoration("test_pillar", Color(0.5, 0.48, 0.45), Vector2i(12, 32))
	print("Placeholder decorations generated!")

func _create_decoration(deco_id: String, color: Color, size: Vector2i) -> void:
	var dir_path := "res://assets/decorations/%s" % deco_id
	DirAccess.make_dir_recursive_absolute(dir_path)

	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	# Simple filled shape with slight edge darkening
	for y in range(size.y):
		for x in range(size.x):
			var edge_factor := 1.0 - (0.2 * (1.0 - smoothstep(0.0, 3.0, min(x, size.x - 1 - x, y, size.y - 1 - y))))
			img.set_pixel(x, y, Color(color.r * edge_factor, color.g * edge_factor, color.b * edge_factor, 1.0))

	img.save_png(dir_path + "/sprite.png")
	print("  Created %s/sprite.png (%dx%d)" % [deco_id, size.x, size.y])

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
```

**Step 2: Run the tool script in Godot editor**

Run via: Script Editor → File → Run (the script above).

**Step 3: Commit**

```bash
git add scripts/tools/generate_placeholder_decorations.gd assets/decorations/
git commit -m "feat(env): add placeholder decoration generator and test assets"
```

---

### Task 13: Debug Menu — Environment Controls

Add environment debug controls to the debug menu for testing mood presets at runtime.

**Files:**
- Modify: `scripts/ui/debug/debug_menu.gd`

**Step 1: Add Environment section to debug menu**

Following the existing pattern (use `_add_action_button()`), add buttons to cycle through mood presets:

```gdscript
# In the appropriate section setup method:
_add_section("Environment")
_add_action_button("Deep Cave Mood", func():
	var mood := load("res://resources/zone_moods/deep_cave.tres") as ZoneMood
	if mood:
		EnvironmentManager.apply_mood(mood)
)
_add_action_button("Snowy Mountain Mood", func():
	var mood := load("res://resources/zone_moods/snowy_mountain.tres") as ZoneMood
	if mood:
		EnvironmentManager.apply_mood(mood)
)
_add_action_button("Lava Cave Mood", func():
	var mood := load("res://resources/zone_moods/lava_cave.tres") as ZoneMood
	if mood:
		EnvironmentManager.apply_mood(mood)
)
_add_action_button("Clear Mood", func():
	EnvironmentManager.clear_mood()
)
```

**Step 2: Commit**

```bash
git add scripts/ui/debug/debug_menu.gd
git commit -m "feat(env): add environment mood controls to debug menu"
```

---

### Task 14: Integration Testing

Verify the full pipeline works end-to-end in the test zone.

**Steps:**
1. Open the project in Godot editor
2. Run the test zone (zone_ldtk_test)
3. Open debug menu (eye icon)
4. Test each mood preset — verify:
   - CanvasModulate changes ambient color
   - Bloom glows on light sources
   - Particles appear (snow, dust, embers)
   - Light flicker animation is visible on torches
5. If lights have shadow_enabled, verify shadows cast from any nearby decoration or tile edges
6. Place a test decoration entity in LDtk, re-import, verify it spawns with correct position

**Verification checklist:**
- [ ] Deep cave mood: very dark ambient, bright bloom on torches, dust motes visible
- [ ] Snowy mountain mood: cool blue ambient, subtle bloom, snow particles falling
- [ ] Lava cave mood: dark red ambient, strong bloom, embers rising
- [ ] Clear mood: neutral white ambient, no bloom, no particles
- [ ] Torch lights flicker
- [ ] Crystal lights pulse (slower)
- [ ] Decorations spawn at correct positions from LDtk data
- [ ] Decorations clean up when chunks unload

**Step 1: Commit any test fixes**

```bash
git add -A
git commit -m "fix(env): integration test fixes"
```
