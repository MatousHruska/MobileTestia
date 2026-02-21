extends Control
## 3D-to-Spritesheet Capture Tool
##
## Run this scene to convert 3D animated models (GLB/FBX from Mixamo) into
## directional pixel-art-ready spritesheets matching the project's conventions.
##
## Workflow:
##   1. Drop .glb/.glb files into assets/3d_imports/
##   2. Run scenes/tools/sprite_capture.tscn
##   3. Select model, animation, configure settings
##   4. Press Export — get {action}_down.png, {action}_up.png, {action}_right.png
##
## Output: Horizontal spritesheets in assets/sprites/captures/{model_name}/

#===============================================================================
# CONSTANTS
#===============================================================================

const IMPORT_DIR := "res://assets/3d_imports"
const OUTPUT_BASE := "res://assets/sprites/captures"

## Direction configs: name, Y rotation in degrees
const DIRECTIONS := [
	{ "name": "down", "rotation_y": 0.0 },
	{ "name": "up", "rotation_y": 180.0 },
	{ "name": "right", "rotation_y": 90.0 },
]

#===============================================================================
# NODE REFERENCES
#===============================================================================

var model_dropdown: OptionButton
var anim_dropdown: OptionButton
var frame_count_spin: SpinBox
var output_size_spin: SpinBox
var camera_elevation_slider: HSlider
var camera_elevation_label: Label
var export_button: Button
var export_all_button: Button
var status_label: Label
var preview_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var model_slot: Node3D

## State
var current_model_path: String = ""
var current_model_instance: Node = null
var current_anim_player: AnimationPlayer = null
var available_models: Array[String] = []

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_build_viewport()
	_scan_models()


func _build_ui() -> void:
	## Build the configuration UI on the left side
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 12)
	add_child(root_hbox)

	# Left panel — controls
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	root_hbox.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Sprite Capture Tool"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Model selector
	vbox.add_child(_make_label("3D Model:"))
	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	vbox.add_child(model_dropdown)

	# Animation selector
	vbox.add_child(_make_label("Animation:"))
	anim_dropdown = OptionButton.new()
	anim_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	anim_dropdown.item_selected.connect(_on_animation_selected)
	vbox.add_child(anim_dropdown)

	vbox.add_child(HSeparator.new())

	# Frame count
	vbox.add_child(_make_label("Frames per direction:"))
	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 2
	frame_count_spin.max_value = 32
	frame_count_spin.value = 8
	frame_count_spin.step = 1
	vbox.add_child(frame_count_spin)

	# Output size — high-res for PixelOver, not final sprite size
	vbox.add_child(_make_label("Output frame size (px):"))
	output_size_spin = SpinBox.new()
	output_size_spin.min_value = 64
	output_size_spin.max_value = 1024
	output_size_spin.value = 512
	output_size_spin.step = 64
	vbox.add_child(output_size_spin)

	# Camera elevation
	vbox.add_child(_make_label("Camera elevation (degrees):"))
	var elev_hbox := HBoxContainer.new()
	vbox.add_child(elev_hbox)
	camera_elevation_slider = HSlider.new()
	camera_elevation_slider.min_value = 10.0
	camera_elevation_slider.max_value = 80.0
	camera_elevation_slider.value = 40.0
	camera_elevation_slider.step = 1.0
	camera_elevation_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	elev_hbox.add_child(camera_elevation_slider)
	camera_elevation_label = Label.new()
	camera_elevation_label.text = "40"
	camera_elevation_label.custom_minimum_size.x = 30
	elev_hbox.add_child(camera_elevation_label)

	vbox.add_child(HSeparator.new())

	# Export buttons
	export_button = Button.new()
	export_button.text = "Export Selected Animation"
	export_button.pressed.connect(_on_export_pressed)
	vbox.add_child(export_button)

	export_all_button = Button.new()
	export_all_button.text = "Export ALL Animations"
	export_all_button.pressed.connect(_on_export_all_pressed)
	vbox.add_child(export_all_button)

	vbox.add_child(HSeparator.new())

	# Rescan button
	var rescan_button := Button.new()
	rescan_button.text = "Rescan Models Folder"
	rescan_button.pressed.connect(_scan_models)
	vbox.add_child(rescan_button)

	vbox.add_child(HSeparator.new())

	# Status
	status_label = Label.new()
	status_label.text = "Drop .glb files into assets/3d_imports/ and they will appear above."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(status_label)

	# Right side — preview viewport takes remaining space
	preview_container = SubViewportContainer.new()
	preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	preview_container.stretch = true
	root_hbox.add_child(preview_container)


func _build_viewport() -> void:
	## Create the SubViewport for rendering with transparent background
	sub_viewport = SubViewport.new()
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(512, 512)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.msaa_3d = Viewport.MSAA_4X
	preview_container.add_child(sub_viewport)

	# Camera
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGRAPHIC
	camera.size = 2.0
	sub_viewport.add_child(camera)
	_position_camera(40.0)

	# Ambient light — fallback for any materials the unlit override misses
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.TRANSPARENT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	# Directional fill light
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_energy = 0.5
	dir_light.shadow_enabled = false
	sub_viewport.add_child(dir_light)

	# Model slot
	model_slot = Node3D.new()
	model_slot.name = "ModelSlot"
	sub_viewport.add_child(model_slot)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


#===============================================================================
# MODEL SCANNING & LOADING
#===============================================================================

func _scan_models() -> void:
	available_models.clear()
	model_dropdown.clear()

	var global_dir := ProjectSettings.globalize_path(IMPORT_DIR)
	var dir := DirAccess.open(global_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(global_dir)
		_set_status("Created %s — drop your .glb files there and restart." % IMPORT_DIR)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var lower := file_name.to_lower()
		if lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".fbx"):
			available_models.append(file_name)
			model_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if available_models.is_empty():
		_set_status("No models found. Place .glb/.gltf/.fbx files in assets/3d_imports/")
	else:
		_set_status("Found %d model(s). Select one to begin." % available_models.size())
		# Auto-select first
		_on_model_selected(0)


func _on_model_selected(index: int) -> void:
	if index < 0 or index >= available_models.size():
		return

	var file_name: String = available_models[index]
	var res_path := "%s/%s" % [IMPORT_DIR, file_name]
	current_model_path = res_path

	# Clear previous model
	_clear_model()

	# Load and instance the model
	var packed_scene := ResourceLoader.load(res_path) as PackedScene
	if packed_scene == null:
		_set_status("ERROR: Could not load %s. Make sure Godot has imported it." % res_path)
		return

	current_model_instance = packed_scene.instantiate()
	model_slot.add_child(current_model_instance)

	# Apply unlit material to all meshes
	_apply_unlit_materials(current_model_instance)

	# Find AnimationPlayer
	current_anim_player = _find_animation_player(current_model_instance)
	_populate_animations()

	# Auto-fit the camera
	_auto_fit_camera()

	_set_status("Loaded: %s" % file_name)


func _clear_model() -> void:
	if current_model_instance != null:
		current_model_instance.queue_free()
		current_model_instance = null
	current_anim_player = null
	anim_dropdown.clear()


func _find_animation_player(node: Node) -> AnimationPlayer:
	## Recursively find the first AnimationPlayer in the scene tree
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


func _populate_animations() -> void:
	anim_dropdown.clear()
	if current_anim_player == null:
		_set_status("WARNING: No AnimationPlayer found in model.")
		return

	var anims := current_anim_player.get_animation_list()
	for anim_name in anims:
		# Skip the default RESET animation
		if anim_name == "RESET":
			continue
		anim_dropdown.add_item(anim_name)

	if anim_dropdown.item_count > 0:
		_on_animation_selected(0)


func _on_animation_selected(index: int) -> void:
	if current_anim_player == null or index < 0:
		return
	var anim_name: String = anim_dropdown.get_item_text(index)
	current_anim_player.play(anim_name)
	current_anim_player.seek(0.0, true)


#===============================================================================
# MATERIAL OVERRIDE — UNLIT
#===============================================================================

func _apply_unlit_materials(node: Node) -> void:
	## Recursively set all MeshInstance3D materials to unlit (preserving albedo texture)
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				var original_mat := mesh_instance.get_active_material(surface_idx)
				var unlit_mat := StandardMaterial3D.new()
				unlit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNLIT

				# Preserve albedo from original material
				if original_mat is StandardMaterial3D:
					var orig := original_mat as StandardMaterial3D
					unlit_mat.albedo_color = orig.albedo_color
					if orig.albedo_texture != null:
						unlit_mat.albedo_texture = orig.albedo_texture
					# Preserve transparency settings
					unlit_mat.transparency = orig.transparency
					unlit_mat.alpha_scissor_threshold = orig.alpha_scissor_threshold
				elif original_mat is BaseMaterial3D:
					var orig := original_mat as BaseMaterial3D
					unlit_mat.albedo_color = orig.albedo_color
					unlit_mat.transparency = orig.transparency

				mesh_instance.set_surface_override_material(surface_idx, unlit_mat)

	for child in node.get_children():
		_apply_unlit_materials(child)


#===============================================================================
# CAMERA
#===============================================================================

func _position_camera(elevation_deg: float) -> void:
	## Position camera at given elevation angle looking at origin
	var elevation_rad := deg_to_rad(elevation_deg)
	var distance := 3.0
	var y := sin(elevation_rad) * distance
	var z := cos(elevation_rad) * distance
	camera.position = Vector3(0.0, y, z)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _on_elevation_changed(value: float) -> void:
	camera_elevation_label.text = str(int(value))
	_position_camera(value)


func _auto_fit_camera() -> void:
	## Attempt to auto-fit the orthographic camera to the model's bounding box
	if current_model_instance == null:
		return

	var aabb := _get_combined_aabb(current_model_instance)
	if aabb.size == Vector3.ZERO:
		return

	# Center the model so the AABB center is at origin
	var center := aabb.get_center()
	current_model_instance.position = -center

	# Set orthographic size to fit the model with some padding
	var max_extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	camera.size = max_extent * 1.3

	_position_camera(camera_elevation_slider.value)


func _get_combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true

	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var node_aabb := vi.get_aabb()
		# Transform AABB to global space
		var global_transform := vi.global_transform
		var corners: Array[Vector3] = []
		for i in range(8):
			var corner := Vector3(
				node_aabb.position.x + node_aabb.size.x * (1 if (i & 1) else 0),
				node_aabb.position.y + node_aabb.size.y * (1 if (i & 2) else 0),
				node_aabb.position.z + node_aabb.size.z * (1 if (i & 4) else 0)
			)
			corners.append(global_transform * corner)
		for c in corners:
			if first:
				result = AABB(c, Vector3.ZERO)
				first = false
			else:
				result = result.expand(c)

	for child in node.get_children():
		var child_aabb := _get_combined_aabb(child)
		if child_aabb.size != Vector3.ZERO:
			if first:
				result = child_aabb
				first = false
			else:
				result = result.merge(child_aabb)

	return result


#===============================================================================
# EXPORT
#===============================================================================

func _on_export_pressed() -> void:
	if current_anim_player == null:
		_set_status("ERROR: No model or animation loaded.")
		return

	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	export_button.disabled = true
	export_all_button.disabled = true
	await _export_animation(anim_name)
	export_button.disabled = false
	export_all_button.disabled = false


func _on_export_all_pressed() -> void:
	if current_anim_player == null:
		_set_status("ERROR: No model or animation loaded.")
		return

	export_button.disabled = true
	export_all_button.disabled = true

	for i in range(anim_dropdown.item_count):
		var anim_name: String = anim_dropdown.get_item_text(i)
		await _export_animation(anim_name)

	_set_status("All animations exported!")
	export_button.disabled = false
	export_all_button.disabled = false


func _export_animation(anim_name: String) -> void:
	## Export one animation as 3 directional spritesheets
	var frame_count := int(frame_count_spin.value)
	var output_size := int(output_size_spin.value)
	var model_name := current_model_path.get_file().get_basename()
	var output_dir := "%s/%s" % [OUTPUT_BASE, model_name]
	var global_output_dir := ProjectSettings.globalize_path(output_dir)

	DirAccess.make_dir_recursive_absolute(global_output_dir)

	# Set the viewport to the exact output size for crisp pixel capture
	var original_vp_size := sub_viewport.size
	sub_viewport.size = Vector2i(output_size, output_size)

	# Temporarily disable the preview stretch to avoid size conflicts
	preview_container.stretch = false

	var anim := current_anim_player.get_animation(anim_name)
	if anim == null:
		_set_status("ERROR: Animation '%s' not found." % anim_name)
		return

	var anim_length := anim.length

	for dir_config in DIRECTIONS:
		var dir_name: String = dir_config["name"]
		var rot_y: float = dir_config["rotation_y"]

		_set_status("Capturing %s_%s (%d frames)..." % [anim_name, dir_name, frame_count])

		# Rotate model
		if current_model_instance is Node3D:
			(current_model_instance as Node3D).rotation_degrees.y = rot_y

		# Create the spritesheet image
		var sheet_width := output_size * frame_count
		var sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)

		for frame_idx in range(frame_count):
			# Seek to the correct position in the animation
			var seek_time: float
			if frame_count == 1:
				seek_time = 0.0
			else:
				seek_time = (float(frame_idx) / float(frame_count)) * anim_length

			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)

			# Wait 2 frames — first settles the pose, second gives a clean render
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			# Capture
			var frame_image := sub_viewport.get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGBA8)

			# Blit into spritesheet
			var dest_pos := Vector2i(frame_idx * output_size, 0)
			sheet.blit_rect(
				frame_image,
				Rect2i(0, 0, output_size, output_size),
				dest_pos
			)

		# Save spritesheet
		# Clean the animation name for file safety (replace spaces, special chars)
		var safe_anim_name := anim_name.replace(" ", "_").replace("/", "_").to_lower()
		var file_path := "%s/%s_%s.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		var err := sheet.save_png(global_path)
		if err != OK:
			_set_status("ERROR: Failed to save %s (error %d)" % [file_path, err])
			# Restore viewport
			sub_viewport.size = original_vp_size
			preview_container.stretch = true
			return

		print("Saved: %s (%d frames)" % [file_path, frame_count])

	# Reset model rotation
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0

	# Restore viewport for preview
	sub_viewport.size = original_vp_size
	preview_container.stretch = true

	_set_status("Exported: %s (3 directions x %d frames) -> %s/" % [anim_name, frame_count, output_dir])


#===============================================================================
# UTILS
#===============================================================================

func _set_status(text: String) -> void:
	status_label.text = text
	print("[SpritCapture] %s" % text)
