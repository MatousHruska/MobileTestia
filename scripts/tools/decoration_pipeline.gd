extends Control
## Decoration Pipeline — 6-step wizard for creating pixel art decorations.
##
## Converts 3D models or 2D source images into pixel art sprites with normal maps,
## baked shadows, and auto-traced occluder polygons. Generates an LDtk tileset atlas.

#===============================================================================
# CONSTANTS
#===============================================================================

const IMPORT_DIR := "res://assets/3d_imports"
const DECORATIONS_DIR := "res://assets/decorations"
const ATLAS_DIR := "res://assets/decorations/_atlas"
const TOOLS_MENU_PATH := "res://scenes/tools/tools_menu.tscn"
const CAPTURE_OVERSCAN := 1.5
const ATLAS_TILE_SIZE := 64
const ATLAS_COLUMNS := 8

const STEP_NAMES := [
	"Source Selection",
	"Capture / Import",
	"Pixel Art Processing",
	"Normal & Shadow",
	"Preview & Adjust",
	"Export & Atlas",
]

# 3D capture directions — orbit around Y axis
const ANGLE_CONFIGS := {
	"single": [{ "name": "front", "suffix": "", "rotation_y": 0.0 }],
	"two": [
		{ "name": "front", "suffix": "_front", "rotation_y": 0.0 },
		{ "name": "back", "suffix": "_back", "rotation_y": 180.0 },
	],
	"four": [
		{ "name": "front", "suffix": "_front", "rotation_y": 0.0 },
		{ "name": "back", "suffix": "_back", "rotation_y": 180.0 },
		{ "name": "left", "suffix": "_left", "rotation_y": 270.0 },
		{ "name": "right", "suffix": "_right", "rotation_y": 90.0 },
	],
}

#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3D")
const C_SECTION_BORDER := Color("#33334A")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#66BB6A")
const C_WARN := Color("#FFA726")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

#===============================================================================
# WIZARD STATE
#===============================================================================

var _current_step := 0
var _source_mode := "3d"  # "3d" or "2d"
var _decoration_id := ""
var _angle_mode := "single"  # "single", "two", "four"

# 3D state
var available_models: Array[String] = []
var current_model_path := ""
var current_model_instance: Node = null

# Capture results: angle_name -> Image
var _captured_color: Dictionary = {}
var _captured_normal: Dictionary = {}
var _captured_shadow: Dictionary = {}

# 2D import state
var _imported_image: Image = null

# Processing results: angle_name -> Image
var _processed_color: Dictionary = {}
var _processed_normal: Dictionary = {}
var _processed_shadow: Dictionary = {}
var _processed_occluder_points: Dictionary = {}  # angle_name -> PackedVector2Array

#===============================================================================
# NODE REFERENCES
#===============================================================================

var step_indicator: Control
var step_containers: Array[Control] = []
var preview_container: SubViewportContainer
var _right_preview_rect: TextureRect  # 2D preview in right panel (pixel art, composite, etc.)
var sub_viewport: SubViewport
var camera: Camera3D
var model_slot: Node3D
var status_label: Label
var back_button: Button
var next_button: Button

# Step 1 refs
var model_dropdown: OptionButton
var deco_id_input: LineEdit
var angle_mode_group: HBoxContainer
var _3d_container: VBoxContainer
var _2d_container: VBoxContainer

# Step 1 camera sliders
var _camera_zoom_slider: HSlider
var _camera_elevation_slider: HSlider
var _camera_target_y_slider: HSlider
var camera_target := Vector3(0.0, 1.0, 0.0)
var _2d_info_label: Label
var _2d_file_dialog: FileDialog = null

# Step 2 refs
var _capture_status_label: Label
var _capture_preview_grid: GridContainer

# Step 3 refs
var _output_height_slider: HSlider
var _alpha_threshold_slider: HSlider
var _dither_check: CheckButton
var _dither_strength_slider: HSlider
var _outline_check: CheckButton
var _denoise_check: CheckButton
var _denoise_slider: HSlider
var _palette_dropdown: OptionButton
var _palette_swatch_container: HFlowContainer
var _palette_colors: PackedColorArray = PackedColorArray()
var _palette_file_dialog: FileDialog = null

# Step 4 refs
var _2d_normal_container: VBoxContainer
var _normal_height_slider: HSlider
var _normal_invert_check: CheckButton
var _normal_preview_rect: TextureRect
var _shadow_offset_slider: HSlider
var _shadow_opacity_slider: HSlider
var _shadow_preview_rect: TextureRect
var _occluder_simplify_slider: HSlider
var _occluder_info_label: Label

# Step 5 refs
var _preview_angle_toggle: HBoxContainer
var _show_sprite_check: CheckButton
var _show_normal_check: CheckButton
var _show_shadow_check: CheckButton
var _show_occluder_check: CheckButton
var _composite_preview_rect: TextureRect
var _dimensions_label: Label
var _current_preview_angle := "front"

# Step 6 refs
var _export_log: RichTextLabel

# Capture materials
var _normal_capture_shader: Shader
var _normal_capture_material: ShaderMaterial = null
var _shadow_capture_material: StandardMaterial3D = null
var _saved_unlit_materials: Array[Dictionary] = []

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_build_viewport()
	# Load normal capture shader
	_normal_capture_shader = load("res://shaders/normal_capture.gdshader") as Shader
	if _normal_capture_shader:
		_normal_capture_material = ShaderMaterial.new()
		_normal_capture_material.shader = _normal_capture_shader
	# Create shadow capture material
	_shadow_capture_material = StandardMaterial3D.new()
	_shadow_capture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_capture_material.albedo_color = Color.BLACK
	await get_tree().process_frame
	_scan_models()


func _build_ui() -> void:
	# Apply theme
	theme = _build_theme()

	# Background fill
	var bg_rect := ColorRect.new()
	bg_rect.color = C_BG
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# -- Left panel --
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_PANEL
	panel_sb.border_width_right = 1
	panel_sb.border_color = C_BORDER
	panel.add_theme_stylebox_override("panel", panel_sb)
	root_hbox.add_child(panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(left_vbox)

	# Back to tools button (fixed at top)
	var back_tools_margin := MarginContainer.new()
	back_tools_margin.add_theme_constant_override("margin_top", 8)
	back_tools_margin.add_theme_constant_override("margin_bottom", 4)
	back_tools_margin.add_theme_constant_override("margin_left", 12)
	back_tools_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(back_tools_margin)

	var back_tools_btn := _make_subtle_button("\u2190 Back to Tools")
	back_tools_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(TOOLS_MENU_PATH)
	)
	back_tools_margin.add_child(back_tools_btn)

	# Title
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(title_margin)
	var title := Label.new()
	title.text = "Decoration Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Step indicator (custom draw widget)
	var StepIndicatorScript := load("res://scripts/tools/step_indicator.gd")
	step_indicator = StepIndicatorScript.new()
	step_indicator.total_steps = STEP_NAMES.size()
	step_indicator.step_names = PackedStringArray(STEP_NAMES)
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 8)
	indicator_margin.add_theme_constant_override("margin_right", 8)
	indicator_margin.add_theme_constant_override("margin_bottom", 8)
	left_vbox.add_child(indicator_margin)
	indicator_margin.add_child(step_indicator)

	# Thin separator under indicator
	var top_sep := HSeparator.new()
	left_vbox.add_child(top_sep)

	# Scrollable step content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	# Add padding around step content
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	scroll_vbox.add_child(content_margin)

	var steps_vbox := VBoxContainer.new()
	steps_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	steps_vbox.add_theme_constant_override("separation", 8)
	content_margin.add_child(steps_vbox)

	# Build 6 step containers
	for i in range(STEP_NAMES.size()):
		var step_cont := VBoxContainer.new()
		step_cont.add_theme_constant_override("separation", 10)
		step_cont.visible = (i == 0)
		steps_vbox.add_child(step_cont)
		step_containers.append(step_cont)

	# Build each step's contents (placeholders for now)
	_build_step1(step_containers[0])
	_build_step2(step_containers[1])
	_build_step3(step_containers[2])
	_build_step4(step_containers[3])
	_build_step5(step_containers[4])
	_build_step6(step_containers[5])

	# -- Bottom bar (fixed, not scrolled) --
	var bottom_sep := HSeparator.new()
	left_vbox.add_child(bottom_sep)

	# Navigation row
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_top", 8)
	nav_margin.add_theme_constant_override("margin_bottom", 4)
	nav_margin.add_theme_constant_override("margin_left", 12)
	nav_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(nav_margin)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 8)
	nav_margin.add_child(nav_hbox)

	back_button = _make_subtle_button("\u25c0  Back")
	back_button.disabled = true
	back_button.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(back_button)

	next_button = _make_primary_button("Next  \u25b6")
	next_button.pressed.connect(_on_next_pressed)
	nav_hbox.add_child(next_button)

	# Status bar
	var status_panel := PanelContainer.new()
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = C_SECTION
	status_sb.set_content_margin_all(6)
	status_sb.content_margin_left = 12
	status_sb.content_margin_right = 12
	status_panel.add_theme_stylebox_override("panel", status_sb)
	left_vbox.add_child(status_panel)

	status_label = Label.new()
	status_label.text = "Select a source mode and decoration ID."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", FONT_HINT)
	status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	status_label.max_lines_visible = 2
	status_panel.add_child(status_label)

	# -- Right side -- preview area --
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var right_sb := StyleBoxFlat.new()
	right_sb.bg_color = C_BG
	right_panel.add_theme_stylebox_override("panel", right_sb)
	root_hbox.add_child(right_panel)

	# Wrapper so both the 3D viewport and 2D preview can share the right panel
	var right_stack := Control.new()
	right_stack.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	right_panel.add_child(right_stack)

	preview_container = SubViewportContainer.new()
	preview_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	preview_container.stretch = true
	right_stack.add_child(preview_container)

	_right_preview_rect = TextureRect.new()
	_right_preview_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_right_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_right_preview_rect.visible = false
	right_stack.add_child(_right_preview_rect)


func _build_viewport() -> void:
	sub_viewport = SubViewport.new()
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(512, 512)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.msaa_3d = Viewport.MSAA_4X
	preview_container.add_child(sub_viewport)

	# Camera
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.far = 100.0
	sub_viewport.add_child(camera)
	camera_target = Vector3(0.0, 1.0, 0.0)
	_position_camera(30.0)

	# Environment
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


func _scan_models() -> void:
	available_models.clear()
	if model_dropdown:
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
		_on_model_selected(0)


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
		if text.begins_with("ERROR") or text.begins_with("Failed"):
			status_label.add_theme_color_override("font_color", C_WARN)
		elif text.begins_with("Done") or text.begins_with("Saved") or text.begins_with("Export"):
			status_label.add_theme_color_override("font_color", C_SUCCESS)
		else:
			status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	print("[DecorationPipeline] %s" % text)


#===============================================================================
# STEP NAVIGATION
#===============================================================================

func _go_to_step(step: int) -> void:
	_current_step = step
	for i in range(step_containers.size()):
		step_containers[i].visible = (i == step)

	# Update navigation buttons
	back_button.disabled = (step == 0)
	var last_step := STEP_NAMES.size() - 1
	next_button.text = "Export  \u25b6" if step == last_step else "Next  \u25b6"

	# Style Next button for export transition
	if step == last_step:
		var warning_sb := StyleBoxFlat.new()
		warning_sb.bg_color = C_WARN
		warning_sb.set_corner_radius_all(4)
		warning_sb.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("normal", warning_sb)
		var warning_hover := StyleBoxFlat.new()
		warning_hover.bg_color = Color(C_WARN, 0.8)
		warning_hover.set_corner_radius_all(4)
		warning_hover.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("hover", warning_hover)
	else:
		var accent_sb := StyleBoxFlat.new()
		accent_sb.bg_color = C_ACCENT
		accent_sb.set_corner_radius_all(4)
		accent_sb.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("normal", accent_sb)
		var accent_hover := StyleBoxFlat.new()
		accent_hover.bg_color = C_ACCENT_HOVER
		accent_hover.set_corner_radius_all(4)
		accent_hover.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("hover", accent_hover)

	# Step-specific entry logic
	match step:
		1:  # Entering Capture step — reset status label
			if _capture_status_label:
				_capture_status_label.text = "Press capture to render from all selected angles."
		2:  # Entering Pixel Art Processing — refresh preview
			_update_pixel_preview()
		3:  # Entering Normal & Shadow — show 2D-only controls if applicable
			if _2d_normal_container:
				_2d_normal_container.visible = (_source_mode == "2d")
		4:  # Entering Preview — refresh angle buttons and composite
			_refresh_preview_angle_buttons()
			_update_composite_preview()

	# Right panel visibility: 3D viewport for steps 0-1, 2D preview for step 2
	var show_3d := (_source_mode == "3d" and step <= 1)
	var show_2d_preview := (step == 2)
	if preview_container:
		preview_container.visible = show_3d
	if _right_preview_rect:
		_right_preview_rect.visible = show_2d_preview

	# Update step indicator
	if step_indicator:
		step_indicator.set_step(step)


func _on_next_pressed() -> void:
	match _current_step:
		0:  # Source Selection — validate inputs before proceeding
			if _decoration_id.strip_edges().is_empty():
				_set_status("Enter a decoration ID first.")
				return
			if _source_mode == "3d" and current_model_instance == null:
				_set_status("Load a 3D model first.")
				return
			if _source_mode == "2d" and _imported_image == null:
				_set_status("Import a 2D image first.")
				return
			if _source_mode == "2d":
				_go_to_step(2)  # Skip capture step
			else:
				_go_to_step(1)
			return
		1:  # Capture — must have captured frames
			if _captured_color.is_empty():
				_set_status("Capture frames first.")
				return
		2:  # Pixel Art Processing — no mandatory validation
			pass
		3:  # Normal & Shadow — must have processed outputs
			if _processed_color.is_empty():
				_set_status("Generate normals/shadows first.")
				return
		4:  # Preview — no validation
			pass
		5:  # Export — trigger export and return
			_start_export()
			return
	_go_to_step(_current_step + 1)


func _on_back_pressed() -> void:
	# 2D mode: skip back over capture step (step 1) — jump from processing (2) to source (0)
	if _current_step == 2 and _source_mode == "2d":
		_go_to_step(0)
		return

	if _current_step > 0:
		_go_to_step(_current_step - 1)


#===============================================================================
# SOURCE MODE & ANGLE MODE HANDLERS
#===============================================================================

func _on_source_mode_changed(mode_key: String) -> void:
	_source_mode = mode_key
	if mode_key == "3d":
		_3d_container.visible = true
		_2d_container.visible = false
		preview_container.visible = true
	else:
		_3d_container.visible = false
		_2d_container.visible = true
		preview_container.visible = false
	# Update Step 4 2D-only normal map controls visibility
	if _2d_normal_container:
		_2d_normal_container.visible = (mode_key == "2d")


func _on_angle_mode_changed(mode_key: String) -> void:
	_angle_mode = mode_key


#===============================================================================
# MODEL LOADING
#===============================================================================

func _on_model_selected(index: int) -> void:
	if index < 0 or index >= available_models.size():
		return

	var file_name: String = available_models[index]
	var res_path := "%s/%s" % [IMPORT_DIR, file_name]
	current_model_path = res_path

	_clear_model()

	var packed_scene := ResourceLoader.load(res_path) as PackedScene
	if packed_scene == null:
		_set_status("ERROR: Could not load %s. Make sure Godot has imported it." % res_path)
		return

	current_model_instance = packed_scene.instantiate()
	model_slot.add_child(current_model_instance)

	_apply_unlit_materials(current_model_instance)

	_set_status("Loaded: %s" % file_name)

	# Auto-suggest decoration ID from filename
	var suggested_id := file_name.get_basename().to_lower().replace(" ", "_").replace("-", "_")
	if deco_id_input and deco_id_input.text.is_empty():
		deco_id_input.text = suggested_id
		_decoration_id = suggested_id


func _clear_model() -> void:
	if current_model_instance != null:
		current_model_instance.queue_free()
		current_model_instance = null


#===============================================================================
# 2D IMAGE IMPORT
#===============================================================================

func _on_2d_browse_pressed() -> void:
	if _2d_file_dialog:
		_2d_file_dialog.popup_centered(Vector2i(800, 600))


func _on_2d_file_selected(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		_2d_info_label.text = "Failed to load image: %s" % path
		_2d_info_label.add_theme_color_override("font_color", C_WARN)
		_imported_image = null
		return

	img.convert(Image.FORMAT_RGBA8)
	_imported_image = img

	_2d_info_label.text = "Loaded: %s (%dx%d)" % [path.get_file(), img.get_width(), img.get_height()]
	_2d_info_label.add_theme_color_override("font_color", C_SUCCESS)

	# Auto-suggest decoration ID from filename
	var suggested_id := path.get_file().get_basename().to_lower().replace(" ", "_").replace("-", "_")
	if deco_id_input and deco_id_input.text.is_empty():
		deco_id_input.text = suggested_id
		_decoration_id = suggested_id

	_set_status("Imported 2D image: %s" % path.get_file())


#===============================================================================
# CAMERA HELPERS
#===============================================================================

func _position_camera(elevation_deg: float) -> void:
	if camera == null:
		return
	var elevation_rad := deg_to_rad(elevation_deg)
	var distance := maxf(camera.size * 2.0, 5.0)
	var offset_y := sin(elevation_rad) * distance
	var offset_z := cos(elevation_rad) * distance
	camera.position = camera_target + Vector3(0.0, offset_y, offset_z)
	camera.look_at(camera_target, Vector3.UP)


func _on_zoom_changed(value: float) -> void:
	if camera:
		camera.size = value
	_position_camera(_camera_elevation_slider.value if _camera_elevation_slider else 30.0)


func _on_elevation_changed(value: float) -> void:
	_position_camera(value)


func _on_target_y_changed(value: float) -> void:
	camera_target = Vector3(0.0, value, 0.0)
	_position_camera(_camera_elevation_slider.value if _camera_elevation_slider else 30.0)


#===============================================================================
# CAPTURE PIPELINE (Step 2)
#===============================================================================

const CAPTURE_OUTPUT_SIZE := 512

func _start_capture() -> void:
	## Entry point for the capture button. Guards, clears, captures, re-enables nav.
	if current_model_instance == null:
		_set_status("ERROR: Load a 3D model in Step 1 first.")
		return

	# Clear previous captures
	_captured_color.clear()
	_captured_normal.clear()
	_captured_shadow.clear()

	# Disable nav buttons during capture
	back_button.disabled = true
	next_button.disabled = true

	_capture_status_label.text = "Capturing..."
	_capture_status_label.add_theme_color_override("font_color", C_TEXT_SEC)

	await _capture_decoration()

	# Re-enable nav buttons
	back_button.disabled = (_current_step == 0)
	next_button.disabled = false

	_capture_status_label.text = "Capture complete — %d angle(s) captured." % _captured_color.size()
	_capture_status_label.add_theme_color_override("font_color", C_SUCCESS)
	_set_status("Capture complete. Review thumbnails, then click Next.")


func _capture_decoration() -> void:
	## For each angle in the current angle mode, perform:
	##   1. Rotate model
	##   2. Detection pass (overscan) to find model bounds
	##   3. Compute camera pan to center model
	##   4. Color pass
	##   5. Normal map pass
	##   6. Shadow pass
	## Results stored in _captured_color / _captured_normal / _captured_shadow.
	var angles: Array = ANGLE_CONFIGS[_angle_mode]
	var output_size := CAPTURE_OUTPUT_SIZE
	var elevation := _camera_elevation_slider.value if _camera_elevation_slider else 30.0
	var original_cam_size := camera.size
	var original_cam_target := camera_target
	var original_vp_size := sub_viewport.size
	preview_container.stretch = false

	for angle_idx in range(angles.size()):
		var angle_config: Dictionary = angles[angle_idx]
		var angle_name: String = angle_config["name"]
		var rotation_y: float = angle_config["rotation_y"]

		_capture_status_label.text = "Capturing %s (%d/%d)..." % [angle_name, angle_idx + 1, angles.size()]

		# 1. Rotate model to this angle
		if current_model_instance is Node3D:
			(current_model_instance as Node3D).rotation_degrees.y = rotation_y

		# 2. Detection pass: render at overscan to find model bounds
		var detect_size := int(output_size * CAPTURE_OVERSCAN)
		sub_viewport.size = Vector2i(detect_size, detect_size)
		camera.size = original_cam_size * CAPTURE_OVERSCAN
		camera_target = original_cam_target
		_position_camera(elevation)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var detect_img := sub_viewport.get_texture().get_image()
		detect_img.convert(Image.FORMAT_RGBA8)

		# 3. Compute camera pan to center model
		var cam_shift := _compute_camera_pan(detect_img, detect_size, original_cam_size * CAPTURE_OVERSCAN)

		# 4. Color pass: normal zoom with centered camera
		sub_viewport.size = Vector2i(output_size, output_size)
		camera.size = original_cam_size
		camera_target = original_cam_target + cam_shift
		_position_camera(elevation)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var color_img := sub_viewport.get_texture().get_image()
		color_img.convert(Image.FORMAT_RGBA8)
		_captured_color[angle_name] = color_img

		# 5. Normal map pass: swap materials, render, restore
		if _normal_capture_material:
			_save_current_materials(current_model_instance)
			_apply_normal_capture_materials(current_model_instance)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var normal_img := sub_viewport.get_texture().get_image()
			normal_img.convert(Image.FORMAT_RGBA8)
			_captured_normal[angle_name] = normal_img

			_restore_saved_materials()

		# 6. Shadow pass: top-down camera, shadow materials, render, restore
		if _shadow_capture_material:
			var shadow_cam := _create_shadow_camera()
			sub_viewport.add_child(shadow_cam)
			shadow_cam.current = true

			_save_current_materials(current_model_instance)
			_apply_shadow_capture_materials(current_model_instance)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var shadow_img := sub_viewport.get_texture().get_image()
			shadow_img.convert(Image.FORMAT_RGBA8)
			_captured_shadow[angle_name] = shadow_img

			_restore_saved_materials()
			shadow_cam.queue_free()
			camera.current = true

	# Restore model rotation and camera settings
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0

	sub_viewport.size = original_vp_size
	camera.size = original_cam_size
	camera_target = original_cam_target
	_position_camera(elevation)
	preview_container.stretch = true

	_update_capture_preview()


func _compute_camera_pan(detect_img: Image, detect_size: int, detect_cam_size: float) -> Vector3:
	## Given a detection-pass render (wider view), find the bounding box of opaque
	## pixels and compute a world-space camera shift to center the model.
	## Returns Vector3.ZERO if no shift is needed.
	var used_rect := detect_img.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return Vector3.ZERO

	# Bounding box center offset from viewport center (in pixels)
	var center_px_x := used_rect.position.x + used_rect.size.x / 2.0
	var center_px_y := used_rect.position.y + used_rect.size.y / 2.0
	var offset_px_x := center_px_x - detect_size / 2.0
	var offset_px_y := center_px_y - detect_size / 2.0

	# If offset is small (model is already centered), skip the shift
	var threshold := detect_size * 0.02  # ~2% of viewport = no meaningful shift
	if absf(offset_px_x) < threshold and absf(offset_px_y) < threshold:
		return Vector3.ZERO

	# Convert pixel offset to world units using the camera's orientation.
	# For orthogonal camera: 1 pixel = cam_size / viewport_size world units.
	var world_per_pixel := detect_cam_size / float(detect_size)
	var cam_right := camera.global_transform.basis.x
	var cam_up := camera.global_transform.basis.y

	# Screen-right = camera-right, screen-down = negative camera-up
	return cam_right * (offset_px_x * world_per_pixel) - cam_up * (offset_px_y * world_per_pixel)


func _create_shadow_camera() -> Camera3D:
	## Create a temporary top-down orthographic camera for shadow capture.
	var shadow_cam := Camera3D.new()
	shadow_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	shadow_cam.size = camera.size  # Match main camera's view width
	shadow_cam.far = 100.0
	shadow_cam.position = camera_target + Vector3(0.0, 10.0, 0.0)  # High above
	shadow_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # Look straight down
	return shadow_cam


func _update_capture_preview() -> void:
	## Clear and rebuild the capture preview grid with thumbnails for each angle.
	# Clear existing children
	for child in _capture_preview_grid.get_children():
		child.queue_free()

	# Add thumbnails for each captured angle
	var angles: Array = ANGLE_CONFIGS[_angle_mode]
	for angle_config in angles:
		var angle_name: String = angle_config["name"]
		if not _captured_color.has(angle_name):
			continue

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = angle_name.capitalize()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", FONT_HINT)
		lbl.add_theme_color_override("font_color", C_TEXT_SEC)
		vbox.add_child(lbl)

		var tex_rect := TextureRect.new()
		tex_rect.texture = ImageTexture.create_from_image(_captured_color[angle_name])
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(120, 120)
		tex_rect.size_flags_horizontal = SIZE_EXPAND_FILL
		vbox.add_child(tex_rect)

		_capture_preview_grid.add_child(vbox)


#===============================================================================
# MATERIAL HELPERS
#===============================================================================

func _apply_unlit_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				var original_mat := mesh_instance.get_active_material(surface_idx)
				var unlit_mat := StandardMaterial3D.new()
				unlit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

				if original_mat is StandardMaterial3D:
					var orig := original_mat as StandardMaterial3D
					unlit_mat.albedo_color = orig.albedo_color
					if orig.albedo_texture != null:
						unlit_mat.albedo_texture = orig.albedo_texture
					unlit_mat.transparency = orig.transparency
					unlit_mat.alpha_scissor_threshold = orig.alpha_scissor_threshold
				elif original_mat is BaseMaterial3D:
					var orig := original_mat as BaseMaterial3D
					unlit_mat.albedo_color = orig.albedo_color
					unlit_mat.transparency = orig.transparency

				mesh_instance.set_surface_override_material(surface_idx, unlit_mat)

	for child in node.get_children():
		_apply_unlit_materials(child)


func _save_current_materials(node: Node) -> void:
	## Save all current surface override materials so they can be restored after capture passes.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				_saved_unlit_materials.append({
					"mesh_instance": mesh_instance,
					"surface_idx": surface_idx,
					"material": mesh_instance.get_surface_override_material(surface_idx),
				})
	for child in node.get_children():
		_save_current_materials(child)


func _restore_saved_materials() -> void:
	## Restore the previously saved surface override materials.
	for entry in _saved_unlit_materials:
		var mi: MeshInstance3D = entry["mesh_instance"]
		mi.set_surface_override_material(entry["surface_idx"], entry["material"])
	_saved_unlit_materials.clear()


func _apply_normal_capture_materials(node: Node) -> void:
	## Override all mesh materials with the normal capture shader.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_idx, _normal_capture_material)
	for child in node.get_children():
		_apply_normal_capture_materials(child)


func _apply_shadow_capture_materials(node: Node) -> void:
	## Override all mesh materials with flat black for shadow silhouette capture.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_idx, _shadow_capture_material)
	for child in node.get_children():
		_apply_shadow_capture_materials(child)


#===============================================================================
# STEP BUILDERS (placeholders — filled in by subsequent tasks)
#===============================================================================

func _build_step1(parent: VBoxContainer) -> void:
	# -- Source mode toggle --
	var mode_group := _make_toggle_group([
		{"label": "3D Model", "key": "3d"},
		{"label": "2D Image", "key": "2d"},
	], _on_source_mode_changed)
	parent.add_child(_make_field("Source Mode", mode_group))

	# -- Decoration ID --
	deco_id_input = LineEdit.new()
	deco_id_input.placeholder_text = "e.g. barrel, torch_wall, crate_large"
	deco_id_input.size_flags_horizontal = SIZE_EXPAND_FILL
	deco_id_input.text_changed.connect(func(text: String) -> void:
		_decoration_id = text.strip_edges()
	)
	parent.add_child(_make_field("Decoration ID", deco_id_input))

	# -- 3D container --
	_3d_container = VBoxContainer.new()
	_3d_container.add_theme_constant_override("separation", 10)
	parent.add_child(_3d_container)

	# Model dropdown
	var model_sec := _make_section("3D Model")
	_3d_container.add_child(model_sec[0])
	var model_content: VBoxContainer = model_sec[1]

	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	model_content.add_child(_make_field("Model File", model_dropdown))

	# View angles toggle
	var angle_group := _make_toggle_group([
		{"label": "Single Front", "key": "single"},
		{"label": "Front + Back", "key": "two"},
		{"label": "4 Directions", "key": "four"},
	], _on_angle_mode_changed)
	_3d_container.add_child(_make_field("View Angles", angle_group))

	# Collapsible camera settings
	var cam := _make_collapsible("Camera Settings")
	_3d_container.add_child(cam[0])
	var cam_content: VBoxContainer = cam[1]

	# Zoom slider
	var zoom_data := _make_slider_row(1.0, 8.0, 3.0, 0.1)
	_camera_zoom_slider = zoom_data[1]
	_camera_zoom_slider.value_changed.connect(_on_zoom_changed)
	cam_content.add_child(_make_field("Zoom", zoom_data[0]))

	# Elevation slider
	var elev_data := _make_slider_row(0.0, 90.0, 30.0, 1.0)
	_camera_elevation_slider = elev_data[1]
	_camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	cam_content.add_child(_make_field("Elevation (degrees)", elev_data[0]))

	# Target Y slider
	var target_data := _make_slider_row(0.0, 3.0, 1.0, 0.05)
	_camera_target_y_slider = target_data[1]
	_camera_target_y_slider.value_changed.connect(_on_target_y_changed)
	cam_content.add_child(_make_field("Target Height", target_data[0]))

	# -- 2D container (initially hidden) --
	_2d_container = VBoxContainer.new()
	_2d_container.add_theme_constant_override("separation", 10)
	_2d_container.visible = false
	parent.add_child(_2d_container)

	var sec_2d := _make_section("2D Image Source")
	_2d_container.add_child(sec_2d[0])
	var content_2d: VBoxContainer = sec_2d[1]

	var browse_btn := _make_primary_button("Browse Image...")
	browse_btn.pressed.connect(_on_2d_browse_pressed)
	content_2d.add_child(browse_btn)

	_2d_info_label = Label.new()
	_2d_info_label.text = "No image selected."
	_2d_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_2d_info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_2d_info_label.add_theme_font_size_override("font_size", FONT_HINT)
	_2d_info_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content_2d.add_child(_2d_info_label)

	# FileDialog for image selection
	_2d_file_dialog = FileDialog.new()
	_2d_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_2d_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_2d_file_dialog.title = "Select Image File"
	_2d_file_dialog.add_filter("*.png", "PNG Images")
	_2d_file_dialog.add_filter("*.jpg", "JPEG Images")
	_2d_file_dialog.add_filter("*.jpeg", "JPEG Images")
	_2d_file_dialog.file_selected.connect(_on_2d_file_selected)
	add_child(_2d_file_dialog)


func _build_step2(parent: VBoxContainer) -> void:
	var sec := _make_section("3D Capture")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label(
		"Capture color, normal map, and shadow images from the 3D model at each selected viewing angle."))

	var capture_btn := _make_primary_button("Capture All Angles")
	capture_btn.pressed.connect(_start_capture)
	content.add_child(capture_btn)

	_capture_status_label = Label.new()
	_capture_status_label.text = ""
	_capture_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_capture_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_capture_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_capture_status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(_capture_status_label)

	_capture_preview_grid = GridContainer.new()
	_capture_preview_grid.columns = 2
	_capture_preview_grid.add_theme_constant_override("h_separation", 8)
	_capture_preview_grid.add_theme_constant_override("v_separation", 8)
	_capture_preview_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(_capture_preview_grid)


func _build_step3(parent: VBoxContainer) -> void:
	var sec := _make_section("Pixel Art Settings")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label(
		"Configure downscaling, palette, outline, and dithering settings."))

	# Output height slider (8-512, default 32, step 1)
	var height_data := _make_slider_row(8.0, 512.0, 32.0, 1.0)
	_output_height_slider = height_data[1]
	content.add_child(_make_field("Output Height (px)", height_data[0]))

	# Alpha threshold slider (1-255, default 64, step 1)
	var alpha_data := _make_slider_row(1.0, 255.0, 64.0, 1.0)
	_alpha_threshold_slider = alpha_data[1]
	content.add_child(_make_field("Alpha Threshold", alpha_data[0]))

	# ── Palette ────────────────────────────────────────────────────────
	# Dropdown: saved palettes from res://assets/palettes/
	_palette_dropdown = OptionButton.new()
	_palette_dropdown.add_theme_font_size_override("font_size", FONT_VALUE)
	_palette_dropdown.item_selected.connect(_on_palette_dropdown_selected)
	content.add_child(_make_field("Palette", _palette_dropdown))
	_scan_palettes()

	# Load from file button
	var load_palette_btn := _make_primary_button("Load Palette PNG...")
	load_palette_btn.pressed.connect(_on_load_palette_pressed)
	content.add_child(load_palette_btn)

	# Swatch preview
	_palette_swatch_container = HFlowContainer.new()
	_palette_swatch_container.add_theme_constant_override("h_separation", 2)
	_palette_swatch_container.add_theme_constant_override("v_separation", 2)
	content.add_child(_palette_swatch_container)

	# ── Dithering ──────────────────────────────────────────────────────
	_dither_check = CheckButton.new()
	_dither_check.text = "Ordered Dithering"
	_style_checkbutton_transparent(_dither_check)
	content.add_child(_dither_check)

	# Dither strength slider (0.0-1.0, default 0.3, step 0.05)
	var dither_data := _make_slider_row(0.0, 1.0, 0.3, 0.05)
	_dither_strength_slider = dither_data[1]
	content.add_child(_make_field("Dither Strength", dither_data[0]))

	# Outline checkbox
	_outline_check = CheckButton.new()
	_outline_check.text = "Outline"
	_style_checkbutton_transparent(_outline_check)
	content.add_child(_outline_check)

	# Denoising checkbox (default ON)
	_denoise_check = CheckButton.new()
	_denoise_check.text = "Denoising"
	_denoise_check.button_pressed = true
	_style_checkbutton_transparent(_denoise_check)
	content.add_child(_denoise_check)

	# Min cluster size slider (1-10, default 2, step 1)
	var denoise_data := _make_slider_row(1.0, 10.0, 2.0, 1.0)
	_denoise_slider = denoise_data[1]
	content.add_child(_make_field("Min Cluster Size", denoise_data[0]))

	# Update Preview button — renders into the right panel
	var preview_btn := _make_primary_button("Update Preview")
	preview_btn.pressed.connect(_update_pixel_preview)
	content.add_child(preview_btn)


func _build_step4(parent: VBoxContainer) -> void:
	# ── Normal Map Section ──────────────────────────────────────────────
	var normal_sec := _make_section("Normal Map")
	parent.add_child(normal_sec[0])
	var normal_content: VBoxContainer = normal_sec[1]

	normal_content.add_child(_make_small_label(
		"3D sources use captured normal maps downscaled via bilinear interpolation. " +
		"2D sources generate normals from a Sobel filter on luminance."))

	# 2D-only controls container (hidden for 3D sources)
	_2d_normal_container = VBoxContainer.new()
	_2d_normal_container.add_theme_constant_override("separation", 6)
	_2d_normal_container.visible = (_source_mode == "2d")
	normal_content.add_child(_2d_normal_container)

	# Height Scale slider (0.1-5.0, default 1.0, step 0.1)
	var height_data := _make_slider_row(0.1, 5.0, 1.0, 0.1)
	_normal_height_slider = height_data[1]
	_2d_normal_container.add_child(_make_field("Height Scale", height_data[0]))

	# Invert Heights checkbox
	_normal_invert_check = CheckButton.new()
	_normal_invert_check.text = "Invert Heights"
	_style_checkbutton_transparent(_normal_invert_check)
	_2d_normal_container.add_child(_normal_invert_check)

	# Normal map preview
	_normal_preview_rect = TextureRect.new()
	_normal_preview_rect.custom_minimum_size = Vector2(120, 120)
	_normal_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_normal_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_normal_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	normal_content.add_child(_normal_preview_rect)

	# ── Baked Shadow Section ────────────────────────────────────────────
	var shadow_sec := _make_section("Baked Shadow")
	parent.add_child(shadow_sec[0])
	var shadow_content: VBoxContainer = shadow_sec[1]

	shadow_content.add_child(_make_small_label(
		"Generate a shadow image offset below the sprite. " +
		"3D sources use the captured shadow pass; 2D generates from alpha silhouette."))

	# Shadow Offset Y slider (-8 to 8, default 2, step 1)
	var offset_data := _make_slider_row(-8.0, 8.0, 2.0, 1.0)
	_shadow_offset_slider = offset_data[1]
	shadow_content.add_child(_make_field("Shadow Offset Y", offset_data[0]))

	# Shadow Opacity slider (0.1-1.0, default 0.5, step 0.05)
	var opacity_data := _make_slider_row(0.1, 1.0, 0.5, 0.05)
	_shadow_opacity_slider = opacity_data[1]
	shadow_content.add_child(_make_field("Shadow Opacity", opacity_data[0]))

	# Shadow preview
	_shadow_preview_rect = TextureRect.new()
	_shadow_preview_rect.custom_minimum_size = Vector2(120, 120)
	_shadow_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shadow_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	shadow_content.add_child(_shadow_preview_rect)

	# ── Occluder Polygon Section ────────────────────────────────────────
	var occluder_sec := _make_section("Occluder Polygon")
	parent.add_child(occluder_sec[0])
	var occluder_content: VBoxContainer = occluder_sec[1]

	occluder_content.add_child(_make_small_label(
		"Auto-trace the sprite silhouette into a simplified polygon for light occlusion."))

	# Simplification slider (0.5-5.0, default 2.0, step 0.5)
	var simplify_data := _make_slider_row(0.5, 5.0, 2.0, 0.5)
	_occluder_simplify_slider = simplify_data[1]
	occluder_content.add_child(_make_field("Simplification", simplify_data[0]))

	# Info label for vertex count
	_occluder_info_label = Label.new()
	_occluder_info_label.text = ""
	_occluder_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_occluder_info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_occluder_info_label.add_theme_font_size_override("font_size", FONT_HINT)
	_occluder_info_label.add_theme_color_override("font_color", C_TEXT_SEC)
	occluder_content.add_child(_occluder_info_label)

	# ── Generate Button ─────────────────────────────────────────────────
	parent.add_child(HSeparator.new())

	var gen_btn := _make_primary_button("Generate Normal + Shadow + Occluder")
	gen_btn.pressed.connect(_generate_normal_shadow_occluder)
	parent.add_child(gen_btn)


func _build_step5(parent: VBoxContainer) -> void:
	# ── Composite Preview Section ──────────────────────────────────────
	var preview_sec := _make_section("Composite Preview")
	parent.add_child(preview_sec[0])
	var preview_content: VBoxContainer = preview_sec[1]

	preview_content.add_child(_make_small_label(
		"Preview the final sprite with all generated layers. " +
		"Toggle layers on/off and switch between angles."))

	# Angle selector toggle group — starts with just "front", rebuilt on step entry
	preview_content.add_child(_make_label("Angle"))
	_preview_angle_toggle = HBoxContainer.new()
	_preview_angle_toggle.add_theme_constant_override("separation", 0)
	preview_content.add_child(_preview_angle_toggle)
	# Populate with a default single button
	var default_btn := Button.new()
	default_btn.text = "front"
	default_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_btn.toggle_mode = true
	default_btn.button_pressed = true
	_apply_toggle_style(default_btn, true)
	var default_sb := StyleBoxFlat.new()
	default_sb.bg_color = C_ACCENT
	default_sb.set_border_width_all(1)
	default_sb.border_color = C_ACCENT
	default_sb.set_corner_radius_all(4)
	default_sb.set_content_margin_all(6)
	default_btn.add_theme_stylebox_override("normal", default_sb)
	default_btn.add_theme_stylebox_override("pressed", default_sb)
	_preview_angle_toggle.add_child(default_btn)

	# ── Layer Visibility (collapsible, start open) ─────────────────────
	var layer_col := _make_collapsible("Layer Visibility", true)
	preview_content.add_child(layer_col[0])
	var layer_content: VBoxContainer = layer_col[1]

	_show_sprite_check = CheckButton.new()
	_show_sprite_check.text = "Sprite"
	_show_sprite_check.button_pressed = true
	_style_checkbutton_transparent(_show_sprite_check)
	_show_sprite_check.toggled.connect(func(_on: bool) -> void: _update_composite_preview())
	layer_content.add_child(_show_sprite_check)

	_show_normal_check = CheckButton.new()
	_show_normal_check.text = "Normal Map"
	_show_normal_check.button_pressed = false
	_style_checkbutton_transparent(_show_normal_check)
	_show_normal_check.toggled.connect(func(_on: bool) -> void: _update_composite_preview())
	layer_content.add_child(_show_normal_check)

	_show_shadow_check = CheckButton.new()
	_show_shadow_check.text = "Shadow"
	_show_shadow_check.button_pressed = true
	_style_checkbutton_transparent(_show_shadow_check)
	_show_shadow_check.toggled.connect(func(_on: bool) -> void: _update_composite_preview())
	layer_content.add_child(_show_shadow_check)

	_show_occluder_check = CheckButton.new()
	_show_occluder_check.text = "Occluder Outline"
	_show_occluder_check.button_pressed = true
	_style_checkbutton_transparent(_show_occluder_check)
	_show_occluder_check.toggled.connect(func(_on: bool) -> void: _update_composite_preview())
	layer_content.add_child(_show_occluder_check)

	# ── Composite Preview TextureRect ──────────────────────────────────
	_composite_preview_rect = TextureRect.new()
	_composite_preview_rect.custom_minimum_size = Vector2(200, 200)
	_composite_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_composite_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_composite_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_content.add_child(_composite_preview_rect)

	# ── Dimensions Label ───────────────────────────────────────────────
	_dimensions_label = Label.new()
	_dimensions_label.text = ""
	_dimensions_label.add_theme_font_size_override("font_size", FONT_HINT)
	_dimensions_label.add_theme_color_override("font_color", C_TEXT_SEC)
	_dimensions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_content.add_child(_dimensions_label)


func _build_step6(parent: VBoxContainer) -> void:
	# ── Export Section ─────────────────────────────────────────────────
	var export_sec := _make_section("Export Decoration")
	parent.add_child(export_sec[0])
	var export_content: VBoxContainer = export_sec[1]

	export_content.add_child(_make_small_label(
		"Exports processed sprites (color, normal, shadow) and occluder polygons " +
		"to the decorations asset folder. Each angle variant is saved as a separate " +
		"sub-folder under assets/decorations/."))

	var export_btn := _make_primary_button("Export Decoration")
	export_btn.pressed.connect(_start_export)
	export_content.add_child(export_btn)

	# ── Atlas Section ──────────────────────────────────────────────────
	var atlas_sec := _make_section("Atlas Generation")
	parent.add_child(atlas_sec[0])
	var atlas_content: VBoxContainer = atlas_sec[1]

	atlas_content.add_child(_make_small_label(
		"Regenerates the LDtk tileset atlas from all decorations in the asset folder. " +
		"Run this after exporting to update the atlas with the new decoration."))

	var atlas_btn := _make_primary_button("Regenerate Atlas")
	atlas_btn.pressed.connect(func() -> void: _regenerate_atlas())
	atlas_content.add_child(atlas_btn)

	# ── Export Log ─────────────────────────────────────────────────────
	_export_log = RichTextLabel.new()
	_export_log.bbcode_enabled = true
	_export_log.scroll_following = true
	_export_log.custom_minimum_size = Vector2(0, 150)
	_export_log.add_theme_font_size_override("normal_font_size", FONT_HINT)
	_export_log.add_theme_color_override("default_color", C_TEXT)
	_export_log.size_flags_horizontal = SIZE_EXPAND_FILL
	var log_sb := StyleBoxFlat.new()
	log_sb.bg_color = C_SURFACE
	log_sb.set_corner_radius_all(4)
	log_sb.set_content_margin_all(6)
	_export_log.add_theme_stylebox_override("normal", log_sb)
	parent.add_child(_export_log)

	# ── Action Buttons Row ─────────────────────────────────────────────
	parent.add_child(HSeparator.new())

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	parent.add_child(action_row)

	var another_btn := _make_subtle_button("Process Another")
	another_btn.pressed.connect(func() -> void: _go_to_step(0))
	action_row.add_child(another_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(TOOLS_MENU_PATH)
	)
	action_row.add_child(done_btn)


#===============================================================================
# EXPORT & ATLAS GENERATION
#===============================================================================

func _start_export() -> void:
	_export_log.clear()
	_append_log("[b]Starting export...[/b]")

	var angles: Array
	if _source_mode == "3d":
		angles = ANGLE_CONFIGS[_angle_mode]
	else:
		angles = [{"name": "front", "suffix": ""}]

	for angle_config in angles:
		var angle_name: String = angle_config["name"]
		var suffix: String = angle_config.get("suffix", "")
		var deco_id := _decoration_id + suffix

		if not _processed_color.has(angle_name):
			_append_log("[color=yellow]Skipping %s — no processed image.[/color]" % angle_name)
			continue

		# Create output directory
		var output_dir := "%s/%s" % [DECORATIONS_DIR, deco_id]
		var global_dir := ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(global_dir)

		# Save sprite.png
		var global_sprite := ProjectSettings.globalize_path(output_dir + "/sprite.png")
		_processed_color[angle_name].save_png(global_sprite)
		_append_log("Saved: %s/sprite.png" % deco_id)

		# Save normal.png
		if _processed_normal.has(angle_name):
			var global_normal := ProjectSettings.globalize_path(output_dir + "/normal.png")
			_processed_normal[angle_name].save_png(global_normal)
			_append_log("Saved: %s/normal.png" % deco_id)

		# Save shadow.png
		if _processed_shadow.has(angle_name):
			var global_shadow := ProjectSettings.globalize_path(output_dir + "/shadow.png")
			_processed_shadow[angle_name].save_png(global_shadow)
			_append_log("Saved: %s/shadow.png" % deco_id)

		# Save occluder.tres
		if _processed_occluder_points.has(angle_name):
			var points: PackedVector2Array = _processed_occluder_points[angle_name]
			if points.size() >= 3:
				var occluder := OccluderPolygon2D.new()
				occluder.polygon = points
				ResourceSaver.save(occluder, output_dir + "/occluder.tres")
				_append_log("Saved: %s/occluder.tres (%d vertices)" % [deco_id, points.size()])

	# Collect just-exported images so the atlas can use them from memory
	# instead of re-reading from disk.
	var exported_images: Dictionary = {}  # { deco_id: Image }
	for angle_config in angles:
		var angle_name: String = angle_config["name"]
		var suffix: String = angle_config.get("suffix", "")
		var deco_id := _decoration_id + suffix
		if _processed_color.has(angle_name):
			exported_images[deco_id] = _processed_color[angle_name]

	_append_log("")
	_append_log("[b]Export complete.[/b] Now regenerating atlas...")
	_regenerate_atlas(exported_images)


func _append_log(text: String) -> void:
	_export_log.append_text(text + "\n")


func _regenerate_atlas(cached_images: Dictionary = {}) -> void:
	var global_decos_dir := ProjectSettings.globalize_path(DECORATIONS_DIR)
	var dir := DirAccess.open(global_decos_dir)
	if dir == null:
		_append_log("[color=red]ERROR: Cannot open decorations directory.[/color]")
		return

	# Scan all decoration folders (skip _atlas and hidden folders)
	var deco_entries: Array[Dictionary] = []
	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and folder_name != "_atlas" and not folder_name.begins_with("."):
			# Use in-memory image if available, otherwise load from disk
			var img: Image = null
			if cached_images.has(folder_name):
				img = cached_images[folder_name]
			else:
				var global_sprite := ProjectSettings.globalize_path(
					"%s/%s/sprite.png" % [DECORATIONS_DIR, folder_name])
				img = Image.load_from_file(global_sprite)
			if img:
				deco_entries.append({
					"decoration_id": folder_name,
					"image": img,
					"width": img.get_width(),
					"height": img.get_height(),
					"has_normal": FileAccess.file_exists(ProjectSettings.globalize_path("%s/%s/normal.png" % [DECORATIONS_DIR, folder_name])),
					"has_shadow": FileAccess.file_exists(ProjectSettings.globalize_path("%s/%s/shadow.png" % [DECORATIONS_DIR, folder_name])),
					"has_occluder": FileAccess.file_exists(ProjectSettings.globalize_path("%s/%s/occluder.tres" % [DECORATIONS_DIR, folder_name])),
				})
		folder_name = dir.get_next()
	dir.list_dir_end()

	deco_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["decoration_id"] < b["decoration_id"]
	)

	if deco_entries.is_empty():
		_append_log("[color=yellow]No decorations found to atlas.[/color]")
		return

	# Build atlas grid
	var columns := mini(deco_entries.size(), ATLAS_COLUMNS)
	var rows := ceili(float(deco_entries.size()) / float(columns))
	var atlas_width := columns * ATLAS_TILE_SIZE
	var atlas_height := rows * ATLAS_TILE_SIZE
	var atlas := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)

	var metadata := {
		"tile_size": ATLAS_TILE_SIZE,
		"columns": columns,
		"rows": rows,
		"decorations": []
	}

	for i in range(deco_entries.size()):
		var entry: Dictionary = deco_entries[i]
		var tile_x := i % columns
		var tile_y := i / columns
		var dest_x := tile_x * ATLAS_TILE_SIZE
		var dest_y := tile_y * ATLAS_TILE_SIZE

		# Scale sprite to fit within tile, centered
		var img: Image = entry["image"].duplicate() as Image
		var scale := minf(
			float(ATLAS_TILE_SIZE) / float(img.get_width()),
			float(ATLAS_TILE_SIZE) / float(img.get_height())
		)
		if scale < 1.0:
			img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_NEAREST)
		var offset_x := (ATLAS_TILE_SIZE - img.get_width()) / 2
		var offset_y := (ATLAS_TILE_SIZE - img.get_height()) / 2
		atlas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()),
			Vector2i(dest_x + offset_x, dest_y + offset_y))

		metadata["decorations"].append({
			"decoration_id": entry["decoration_id"],
			"tile_x": tile_x,
			"tile_y": tile_y,
			"source_width": entry["width"],
			"source_height": entry["height"],
			"has_normal": entry["has_normal"],
			"has_shadow": entry["has_shadow"],
			"has_occluder": entry["has_occluder"],
		})

	# Save atlas
	var atlas_dir_global := ProjectSettings.globalize_path(ATLAS_DIR)
	DirAccess.make_dir_recursive_absolute(atlas_dir_global)

	var atlas_png := ProjectSettings.globalize_path(ATLAS_DIR + "/decoration_atlas.png")
	atlas.save_png(atlas_png)
	_append_log("Atlas: %s (%dx%d, %d decorations)" % ["decoration_atlas.png", atlas_width, atlas_height, deco_entries.size()])

	# Save metadata JSON
	var json_path := ProjectSettings.globalize_path(ATLAS_DIR + "/decoration_atlas.json")
	var json_string := JSON.stringify(metadata, "  ")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		_append_log("Metadata: decoration_atlas.json")

	_append_log("[color=green][b]Atlas generation complete![/b][/color]")
	_set_status("Export and atlas generation complete.")


#===============================================================================
# PIXEL ART PROCESSING
#===============================================================================

## Process a source image through the pixel art pipeline using current slider values.
func _process_decoration_image(source: Image) -> Image:
	var target_height := int(_output_height_slider.value)
	var result := source.duplicate() as Image
	# Downscale with nearest-neighbor interpolation
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
	# Alpha threshold
	PixelArtProcessing.apply_alpha_threshold(result, int(_alpha_threshold_slider.value))
	# Dithering (if enabled)
	if _dither_check.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, _dither_strength_slider.value, 1)  # 4x4 Bayer
		PixelArtProcessing.apply_auto_quantize(result)
	# Palette mapping (if a palette is loaded)
	if not _palette_colors.is_empty():
		PixelArtProcessing.apply_palette_mapping(result, _palette_colors)
	# Outline (if enabled)
	if _outline_check.button_pressed:
		PixelArtProcessing.apply_outline(result, Color.BLACK)
	# Denoising (if enabled)
	if _denoise_check.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(_denoise_slider.value))
	# Crop transparent border so bottom-center anchoring aligns with the actual sprite
	result = _crop_transparent_border(result)
	return result


## Crop transparent padding around the sprite to its used rect.
func _crop_transparent_border(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return image  # Fully transparent — nothing to crop
	if used == Rect2i(Vector2i.ZERO, image.get_size()):
		return image  # Already tight — no crop needed
	var cropped := Image.create(used.size.x, used.size.y, false, image.get_format())
	cropped.blit_rect(image, used, Vector2i.ZERO)
	return cropped


## Update the pixel art preview with the processed source image.
func _update_pixel_preview() -> void:
	# Get source image: first captured angle (3D) or imported image (2D)
	var source: Image = null
	if _source_mode == "3d":
		if not _captured_color.is_empty():
			source = _captured_color.values()[0]
	else:
		source = _imported_image
	if source == null:
		_set_status("No source image to process.")
		return
	var processed := _process_decoration_image(source)
	_right_preview_rect.texture = ImageTexture.create_from_image(processed)
	_set_status("Preview: %dx%d px" % [processed.get_width(), processed.get_height()])


#===============================================================================
# PALETTE LOADING
#===============================================================================

const PALETTE_DIR := "res://assets/palettes"


func _scan_palettes() -> void:
	_palette_dropdown.clear()
	_palette_dropdown.add_item("(none)")

	var global_dir := ProjectSettings.globalize_path(PALETTE_DIR)
	var dir := DirAccess.open(global_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(global_dir)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".png"):
			_palette_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _on_palette_dropdown_selected(index: int) -> void:
	if index == 0:
		_palette_colors.clear()
		_update_palette_swatch()
		return
	var palette_name: String = _palette_dropdown.get_item_text(index)
	var global_path := ProjectSettings.globalize_path("%s/%s" % [PALETTE_DIR, palette_name])
	_load_palette_from_path(global_path)


func _on_load_palette_pressed() -> void:
	if _palette_file_dialog == null:
		_palette_file_dialog = FileDialog.new()
		_palette_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_palette_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_palette_file_dialog.filters = PackedStringArray(["*.png ; PNG Palette"])
		_palette_file_dialog.file_selected.connect(_on_palette_file_selected)
		add_child(_palette_file_dialog)
	_palette_file_dialog.popup_centered(Vector2i(600, 400))


func _on_palette_file_selected(path: String) -> void:
	_load_palette_from_path(path)


func _load_palette_from_path(path: String) -> void:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		_set_status("ERROR: Could not load palette from %s" % path)
		return

	_palette_colors.clear()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a > 0.5 and not _palette_colors.has(color):
				_palette_colors.append(color)

	_set_status("Loaded palette: %d colors" % _palette_colors.size())
	_update_palette_swatch()


func _update_palette_swatch() -> void:
	for child in _palette_swatch_container.get_children():
		child.queue_free()
	for color in _palette_colors:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = color
		_palette_swatch_container.add_child(swatch)


#===============================================================================
# NORMAL MAP, SHADOW & OCCLUDER GENERATION
#===============================================================================

## Master generation — processes all angles to produce normal maps, shadows, and occluder polygons.
func _generate_normal_shadow_occluder() -> void:
	# Determine which angles to process
	var angles: Array
	if _source_mode == "3d":
		angles = ANGLE_CONFIGS[_angle_mode]
	else:
		# 2D mode: use just the front angle config
		angles = [ANGLE_CONFIGS["single"][0]]

	# Clear previous results
	_processed_color.clear()
	_processed_normal.clear()
	_processed_shadow.clear()
	_processed_occluder_points.clear()

	var target_height := int(_output_height_slider.value)
	var alpha_thresh := int(_alpha_threshold_slider.value)
	var simplification := _occluder_simplify_slider.value
	var total_occluder_verts := 0

	for angle_cfg in angles:
		var angle_name: String = angle_cfg["name"]
		_set_status("Processing angle: %s..." % angle_name)

		# 1. Get source color image
		var source_color: Image = null
		if _source_mode == "3d":
			if _captured_color.has(angle_name):
				source_color = _captured_color[angle_name]
		else:
			source_color = _imported_image
		if source_color == null:
			_set_status("Missing source for angle '%s'. Run capture/import first." % angle_name)
			return

		# 2. Process color through pixel art pipeline
		var processed_color := _process_decoration_image(source_color)
		_processed_color[angle_name] = processed_color

		# 3. Process normal map
		var processed_normal: Image
		if _source_mode == "3d":
			# 3D: use captured normal map + PixelArtProcessing downscale
			if _captured_normal.has(angle_name):
				processed_normal = PixelArtProcessing.process_normal_map(
					_captured_normal[angle_name], target_height, alpha_thresh)
			else:
				# Fallback: generate from luminance if no captured normal
				processed_normal = _generate_normal_from_luminance(
					processed_color,
					_normal_height_slider.value,
					_normal_invert_check.button_pressed)
		else:
			# 2D: Sobel filter on luminance
			processed_normal = _generate_normal_from_luminance(
				processed_color,
				_normal_height_slider.value,
				_normal_invert_check.button_pressed)
		_processed_normal[angle_name] = processed_normal

		# 4. Process shadow
		var processed_shadow: Image
		if _source_mode == "3d" and _captured_shadow.has(angle_name):
			processed_shadow = _apply_shadow_styling(_captured_shadow[angle_name], target_height)
		else:
			processed_shadow = _generate_shadow_from_alpha(processed_color)
		_processed_shadow[angle_name] = processed_shadow

		# 5. Trace occluder polygon
		var occluder_poly := _trace_occluder_polygon(processed_color, simplification)
		_processed_occluder_points[angle_name] = occluder_poly
		total_occluder_verts += occluder_poly.size()

	# Update preview thumbnails with first angle results
	var first_angle: String = (angles[0] as Dictionary)["name"]
	if _processed_normal.has(first_angle):
		_normal_preview_rect.texture = ImageTexture.create_from_image(_processed_normal[first_angle])
	if _processed_shadow.has(first_angle):
		_shadow_preview_rect.texture = ImageTexture.create_from_image(_processed_shadow[first_angle])

	# Update occluder info
	var angle_count := angles.size()
	if angle_count == 1:
		_occluder_info_label.text = "Occluder: %d vertices" % total_occluder_verts
	else:
		_occluder_info_label.text = "Occluder: %d angles, %d total vertices (avg %.0f/angle)" % [
			angle_count, total_occluder_verts, float(total_occluder_verts) / float(angle_count)]

	_set_status("Generated normals, shadows, and occluders for %d angle(s)." % angle_count)


#-------------------------------------------------------------------------------
# Sobel-filter normal map (for 2D sources)
#-------------------------------------------------------------------------------

## Generate a normal map from sprite luminance using a Sobel filter.
## Transparent pixels receive a neutral normal (0.5, 0.5, 1.0) with alpha 0.
func _generate_normal_from_luminance(sprite: Image, height_scale: float, invert: bool) -> Image:
	var w := sprite.get_width()
	var h := sprite.get_height()
	var result := Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			var center_color := sprite.get_pixel(x, y)
			if center_color.a < 0.5:
				# Transparent pixel — neutral normal, transparent
				result.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.0))
				continue

			# Sample 3x3 neighborhood luminance
			var tl := _get_luminance(sprite, x - 1, y - 1, invert)
			var tc := _get_luminance(sprite, x,     y - 1, invert)
			var tr := _get_luminance(sprite, x + 1, y - 1, invert)
			var ml := _get_luminance(sprite, x - 1, y,     invert)
			var mr := _get_luminance(sprite, x + 1, y,     invert)
			var bl := _get_luminance(sprite, x - 1, y + 1, invert)
			var bc := _get_luminance(sprite, x,     y + 1, invert)
			var br := _get_luminance(sprite, x + 1, y + 1, invert)

			# Sobel X kernel: right column minus left column (weighted)
			var dx := ((tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)) * height_scale
			# Sobel Y kernel: bottom row minus top row (weighted)
			var dy := ((bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)) * height_scale

			# Normal vector: (-dx, -dy, 1.0), then normalize
			var normal := Vector3(-dx, -dy, 1.0).normalized()

			# Encode to color: map [-1,1] to [0,1]
			var nx := normal.x * 0.5 + 0.5
			var ny := normal.y * 0.5 + 0.5
			var nz := normal.z * 0.5 + 0.5
			result.set_pixel(x, y, Color(nx, ny, nz, 1.0))

	return result


## Get luminance of a pixel, clamping coordinates to image bounds.
## Returns 0.5 (neutral) for transparent pixels.
func _get_luminance(image: Image, x: int, y: int, invert: bool) -> float:
	x = clampi(x, 0, image.get_width() - 1)
	y = clampi(y, 0, image.get_height() - 1)
	var color := image.get_pixel(x, y)
	if color.a < 0.5:
		return 0.5  # Neutral for transparent
	var lum := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	if invert:
		lum = 1.0 - lum
	return lum


#-------------------------------------------------------------------------------
# Shadow generation
#-------------------------------------------------------------------------------

## Generate a shadow image from sprite alpha silhouette (for 2D sources).
## Creates a dark offset copy of the sprite's opaque regions.
func _generate_shadow_from_alpha(sprite: Image) -> Image:
	var w := sprite.get_width()
	var h := sprite.get_height()
	var offset_y := int(_shadow_offset_slider.value)
	var opacity := _shadow_opacity_slider.value

	# Create image with extra space for the offset
	var extra := absi(offset_y)
	var shadow_h := h + extra
	var result := Image.create(w, shadow_h, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))

	# Compute y-shift: positive offset pushes shadow downward
	var y_shift := extra if offset_y >= 0 else 0

	for y in range(h):
		for x in range(w):
			if sprite.get_pixel(x, y).a >= 0.5:
				var dest_y := y + y_shift
				if dest_y >= 0 and dest_y < shadow_h:
					result.set_pixel(x, dest_y, Color(0.0, 0.0, 0.0, opacity))

	return result


## Style a 3D-captured shadow image: downscale, offset, and apply opacity.
func _apply_shadow_styling(shadow_source: Image, target_height: int) -> Image:
	var offset_y := int(_shadow_offset_slider.value)
	var opacity := _shadow_opacity_slider.value

	# Downscale the captured shadow to match target pixel art size
	var source := shadow_source.duplicate() as Image
	var scale_factor := float(target_height) / float(source.get_height())
	var target_width := int(float(source.get_width()) * scale_factor)
	source.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	var w := source.get_width()
	var h := source.get_height()
	var extra := absi(offset_y)
	var shadow_h := h + extra
	var result := Image.create(w, shadow_h, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))

	var y_shift := extra if offset_y >= 0 else 0

	for y in range(h):
		for x in range(w):
			var color := source.get_pixel(x, y)
			if color.a >= 0.5:
				var dest_y := y + y_shift
				if dest_y >= 0 and dest_y < shadow_h:
					# Use the darkness from the captured shadow, apply opacity
					var darkness := 1.0 - color.r  # shadow pass is dark = shadow
					result.set_pixel(x, dest_y, Color(0.0, 0.0, 0.0, darkness * opacity))

	return result


#-------------------------------------------------------------------------------
# Occluder polygon tracing
#-------------------------------------------------------------------------------

## Trace the silhouette of a sprite into a simplified polygon for light occlusion.
## Returns a PackedVector2Array of vertex positions in pixel coordinates.
func _trace_occluder_polygon(sprite: Image, simplification: float) -> PackedVector2Array:
	var w := sprite.get_width()
	var h := sprite.get_height()

	# 1. Find all edge pixels (opaque with at least one transparent 4-connected neighbor)
	var edge_pixels: Array[Vector2] = []
	for y in range(h):
		for x in range(w):
			if sprite.get_pixel(x, y).a < 0.5:
				continue
			# Check 4-connected neighbors for transparency
			var is_edge := false
			if x == 0 or sprite.get_pixel(x - 1, y).a < 0.5:
				is_edge = true
			elif x == w - 1 or sprite.get_pixel(x + 1, y).a < 0.5:
				is_edge = true
			elif y == 0 or sprite.get_pixel(x, y - 1).a < 0.5:
				is_edge = true
			elif y == h - 1 or sprite.get_pixel(x, y + 1).a < 0.5:
				is_edge = true
			if is_edge:
				edge_pixels.append(Vector2(x, y))

	if edge_pixels.size() < 3:
		return PackedVector2Array(edge_pixels)

	# 2. Compute centroid of edge pixels
	var centroid := Vector2.ZERO
	for p in edge_pixels:
		centroid += p
	centroid /= float(edge_pixels.size())

	# 3. Sort edge pixels by angle from centroid (convex hull approximation)
	edge_pixels.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var angle_a := (a - centroid).angle()
		var angle_b := (b - centroid).angle()
		return angle_a < angle_b
	)

	var sorted := PackedVector2Array(edge_pixels)

	# 4. Apply Douglas-Peucker simplification
	var simplified := _douglas_peucker(sorted, simplification)
	return simplified


## Douglas-Peucker recursive line simplification.
## Reduces the number of points in a polygon while preserving shape.
func _douglas_peucker(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points

	# Find the point with the maximum distance from the line between first and last
	var max_dist := 0.0
	var max_idx := 0
	var first := points[0]
	var last := points[points.size() - 1]

	for i in range(1, points.size() - 1):
		var dist := _point_line_distance(points[i], first, last)
		if dist > max_dist:
			max_dist = dist
			max_idx = i

	# If max distance exceeds epsilon, recurse on both halves
	if max_dist > epsilon:
		var left_half := PackedVector2Array()
		for i in range(max_idx + 1):
			left_half.append(points[i])
		var right_half := PackedVector2Array()
		for i in range(max_idx, points.size()):
			right_half.append(points[i])

		var left_result := _douglas_peucker(left_half, epsilon)
		var right_result := _douglas_peucker(right_half, epsilon)

		# Combine, removing duplicate junction point
		var combined := PackedVector2Array()
		for i in range(left_result.size() - 1):
			combined.append(left_result[i])
		for i in range(right_result.size()):
			combined.append(right_result[i])
		return combined
	else:
		# All points are close enough to the line — keep only endpoints
		var result := PackedVector2Array()
		result.append(first)
		result.append(last)
		return result


## Perpendicular distance from a point to a line segment defined by two endpoints.
func _point_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec := line_end - line_start
	var line_len_sq := line_vec.length_squared()

	if line_len_sq < 0.0001:
		# Degenerate line segment — just return distance to the start point
		return point.distance_to(line_start)

	# Project point onto line, clamping t to [0, 1]
	var t := clampf((point - line_start).dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection := line_start + line_vec * t
	return point.distance_to(projection)


#===============================================================================
# STEP 5 — COMPOSITE PREVIEW LOGIC
#===============================================================================

## Called when the user taps an angle button in step 5.
func _on_preview_angle_changed(angle_key: String) -> void:
	_current_preview_angle = angle_key
	_update_composite_preview()


## Rebuild the angle toggle buttons to match the current angle mode.
func _refresh_preview_angle_buttons() -> void:
	# Determine available angles from current config
	var angles: Array
	if _source_mode == "3d":
		angles = ANGLE_CONFIGS[_angle_mode]
	else:
		angles = [ANGLE_CONFIGS["single"][0]]

	# Clear existing children
	for child in _preview_angle_toggle.get_children():
		child.queue_free()

	# Build new toggle buttons
	var buttons: Array[Button] = []
	for i in range(angles.size()):
		var angle_cfg: Dictionary = angles[i]
		var angle_name: String = angle_cfg["name"]
		var btn := Button.new()
		btn.text = angle_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		_apply_toggle_style(btn, i == 0)

		var normal_sb := StyleBoxFlat.new()
		normal_sb.bg_color = C_SURFACE
		normal_sb.set_border_width_all(1)
		normal_sb.border_color = C_BORDER
		normal_sb.set_corner_radius_all(0)
		normal_sb.set_content_margin_all(6)
		if i == 0:
			normal_sb.corner_radius_top_left = 4
			normal_sb.corner_radius_bottom_left = 4
		if i == angles.size() - 1:
			normal_sb.corner_radius_top_right = 4
			normal_sb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", normal_sb)

		var active_sb := normal_sb.duplicate()
		active_sb.bg_color = C_ACCENT
		active_sb.border_color = C_ACCENT
		btn.add_theme_stylebox_override("pressed", active_sb)

		var hover_sb := normal_sb.duplicate()
		hover_sb.bg_color = C_SURFACE_HOVER
		btn.add_theme_stylebox_override("hover", hover_sb)

		buttons.append(btn)
		_preview_angle_toggle.add_child(btn)

	# Wire callbacks (separate loop to capture button array)
	for i in range(buttons.size()):
		var idx := i
		var angle_cfg: Dictionary = angles[i]
		var angle_name: String = angle_cfg["name"]
		buttons[i].pressed.connect(func() -> void:
			for j in range(buttons.size()):
				buttons[j].button_pressed = (j == idx)
				_apply_toggle_style(buttons[j], j == idx)
			_on_preview_angle_changed(angle_name)
		)

	# Set current angle to first
	if angles.size() > 0:
		_current_preview_angle = (angles[0] as Dictionary)["name"]
	else:
		_current_preview_angle = "front"


## Build the composite preview image from all enabled layers for the current angle.
func _update_composite_preview() -> void:
	if _processed_color.is_empty():
		_dimensions_label.text = "No processed data. Run Step 4 first."
		_composite_preview_rect.texture = null
		return

	# Get the processed color for the current angle
	var angle_key := _current_preview_angle
	if not _processed_color.has(angle_key):
		# Fallback to first available angle
		angle_key = _processed_color.keys()[0] as String

	var color_img: Image = _processed_color[angle_key]
	var sprite_w := color_img.get_width()
	var sprite_h := color_img.get_height()

	# Determine shadow bounds to size the composite
	var shadow_img: Image = null
	if _processed_shadow.has(angle_key):
		shadow_img = _processed_shadow[angle_key]

	# Composite size: slightly larger than sprite to show shadow offset
	var shadow_offset_y := 0
	if shadow_img:
		shadow_offset_y = int(_shadow_offset_slider.value) if _shadow_offset_slider else 2
	var comp_w := sprite_w + 4  # 2px padding each side
	var comp_h := sprite_h + absi(shadow_offset_y) + 4  # padding + shadow room
	var composite := Image.create(comp_w, comp_h, false, Image.FORMAT_RGBA8)

	# Fill with dark background
	composite.fill(Color(0.2, 0.2, 0.3, 1.0))

	# Origin offset: center the sprite horizontally, add top padding
	var origin_x := 2
	var origin_y := 2 + (absi(shadow_offset_y) if shadow_offset_y < 0 else 0)

	# Layer 1: Shadow (offset is already baked into the shadow image pixels)
	if _show_shadow_check.button_pressed and shadow_img:
		var sx := origin_x
		var sy := origin_y - (absi(shadow_offset_y) if shadow_offset_y < 0 else 0)
		_alpha_blend_image(composite, shadow_img, sx, sy)

	# Layer 2: Sprite (color)
	if _show_sprite_check.button_pressed:
		_alpha_blend_image(composite, color_img, origin_x, origin_y)

	# Layer 3: Normal map (replaces sprite pixels where both are opaque)
	if _show_normal_check.button_pressed and _processed_normal.has(angle_key):
		var normal_img: Image = _processed_normal[angle_key]
		composite.blend_rect(normal_img, Rect2i(Vector2i.ZERO, normal_img.get_size()),
			Vector2i(origin_x, origin_y))

	# Layer 4: Occluder outline (yellow polygon lines via Bresenham)
	if _show_occluder_check.button_pressed and _processed_occluder_points.has(angle_key):
		var occluder_pts: PackedVector2Array = _processed_occluder_points[angle_key]
		if occluder_pts.size() >= 2:
			var outline_color := Color(1.0, 1.0, 0.0, 1.0)  # Yellow
			for i in range(occluder_pts.size()):
				var from := occluder_pts[i] + Vector2(origin_x, origin_y)
				var to := occluder_pts[(i + 1) % occluder_pts.size()] + Vector2(origin_x, origin_y)
				_draw_line_on_image(composite, from, to, outline_color)

	# Display the composite
	_composite_preview_rect.texture = ImageTexture.create_from_image(composite)

	# Update dimensions label
	_dimensions_label.text = "%dx%d px (angle: %s)" % [sprite_w, sprite_h, angle_key]


## Alpha-blend a source image onto a destination at the given offset.
func _alpha_blend_image(dest: Image, src: Image, offset_x: int, offset_y: int) -> void:
	dest.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(offset_x, offset_y))


## Draw a line on an image using Bresenham's algorithm.
func _draw_line_on_image(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var x0 := int(from.x)
	var y0 := int(from.y)
	var x1 := int(to.x)
	var y1 := int(to.y)
	var w := image.get_width()
	var h := image.get_height()

	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy  # Note: dy is negative

	while true:
		# Draw pixel if within bounds
		if x0 >= 0 and x0 < w and y0 >= 0 and y0 < h:
			image.set_pixel(x0, y0, color)

		# Check for end of line
		if x0 == x1 and y0 == y1:
			break

		var e2 := 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy


#===============================================================================
# THEME BUILDER
#===============================================================================

func _build_theme() -> Theme:
	var t := Theme.new()

	# --- PanelContainer ---
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_PANEL
	panel_sb.set_corner_radius_all(0)
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	# --- Button: normal ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_SURFACE
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = C_BORDER
	btn_normal.set_corner_radius_all(4)
	btn_normal.set_content_margin_all(8)
	t.set_stylebox("normal", "Button", btn_normal)

	# --- Button: hover ---
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = C_SURFACE_HOVER
	btn_hover.set_border_width_all(1)
	btn_hover.border_color = C_BORDER
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(8)
	t.set_stylebox("hover", "Button", btn_hover)

	# --- Button: pressed ---
	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = C_ACCENT
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.set_content_margin_all(8)
	t.set_stylebox("pressed", "Button", btn_pressed)

	# --- Button: disabled ---
	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(C_SURFACE, 0.3)
	btn_disabled.set_corner_radius_all(4)
	btn_disabled.set_content_margin_all(8)
	t.set_stylebox("disabled", "Button", btn_disabled)

	# --- Button: focus ---
	var btn_focus := StyleBoxEmpty.new()
	t.set_stylebox("focus", "Button", btn_focus)

	# --- Button colors ---
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", C_TEXT_DIM)

	# --- OptionButton ---
	t.set_stylebox("normal", "OptionButton", btn_normal)
	t.set_stylebox("hover", "OptionButton", btn_hover)
	t.set_stylebox("pressed", "OptionButton", btn_pressed)
	t.set_stylebox("focus", "OptionButton", btn_focus)
	t.set_color("font_color", "OptionButton", C_TEXT)
	t.set_color("font_hover_color", "OptionButton", C_TEXT)

	# --- CheckButton ---
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_color("font_hover_color", "CheckButton", C_TEXT)
	t.set_color("font_pressed_color", "CheckButton", C_ACCENT)

	# --- Label ---
	t.set_color("font_color", "Label", C_TEXT)
	t.set_font_size("font_size", "Label", FONT_LABEL)

	# --- HSlider ---
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = C_BORDER
	slider_bg.set_content_margin_all(0)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider_bg)

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = C_ACCENT
	slider_fill.set_content_margin_all(0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", slider_fill)

	# --- LineEdit / SpinBox ---
	var line_edit_sb := StyleBoxFlat.new()
	line_edit_sb.bg_color = C_SURFACE
	line_edit_sb.set_border_width_all(1)
	line_edit_sb.border_color = C_BORDER
	line_edit_sb.set_corner_radius_all(4)
	line_edit_sb.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", line_edit_sb)
	t.set_stylebox("focus", "LineEdit", line_edit_sb)
	t.set_color("font_color", "LineEdit", C_TEXT)

	# --- ScrollContainer ---
	var scroll_sb := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_sb)

	# --- HSeparator ---
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_BORDER
	sep_sb.set_content_margin_all(0)
	sep_sb.content_margin_top = 4
	sep_sb.content_margin_bottom = 4
	t.set_stylebox("separator", "HSeparator", sep_sb)
	t.set_constant("separation", "HSeparator", 1)

	return t


#===============================================================================
# STYLED HELPERS
#===============================================================================

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", FONT_LABEL)
	return l


func _make_small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_HINT)
	l.add_theme_color_override("font_color", C_TEXT_SEC)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	return l


## Create a section container with a styled header label.
## Returns [section_container, content_vbox] -- add controls to content_vbox.
func _make_section(title: String) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", FONT_SECTION)
	header.add_theme_color_override("font_color", C_ACCENT)
	outer.add_child(header)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SECTION
	sb.set_border_width_all(1)
	sb.border_color = C_SECTION_BORDER
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	outer.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	return [outer, content]


## Create a label-above-control field pair.
func _make_field(label_text: String, control: Control) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var lbl := _make_label(label_text)
	vbox.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(control)
	return vbox


## Create a collapsible section that starts collapsed.
## Returns [outer_container, content_vbox, toggle_button].
func _make_collapsible(title: String, start_open: bool = false) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	var toggle_btn := Button.new()
	toggle_btn.text = "%s %s" % ["\u25be" if start_open else "\u25b8", title]
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var toggle_sb := StyleBoxFlat.new()
	toggle_sb.bg_color = Color(C_SECTION, 0.5)
	toggle_sb.set_corner_radius_all(4)
	toggle_sb.set_content_margin_all(6)
	toggle_btn.add_theme_stylebox_override("normal", toggle_sb)
	var toggle_hover := StyleBoxFlat.new()
	toggle_hover.bg_color = Color(C_SECTION, 0.8)
	toggle_hover.set_corner_radius_all(4)
	toggle_hover.set_content_margin_all(6)
	toggle_btn.add_theme_stylebox_override("hover", toggle_hover)
	toggle_btn.add_theme_color_override("font_color", C_ACCENT)
	toggle_btn.add_theme_font_size_override("font_size", FONT_SECTION)
	outer.add_child(toggle_btn)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.visible = start_open
	outer.add_child(content)

	toggle_btn.pressed.connect(func() -> void:
		content.visible = not content.visible
		var arrow := "\u25be" if content.visible else "\u25b8"
		toggle_btn.text = "%s %s" % [arrow, title]
	)

	return [outer, content, toggle_btn]


## Create a segmented toggle button group.
func _make_toggle_group(options: Array, callback: Callable) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	var buttons: Array[Button] = []

	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = opt["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)

		_apply_toggle_style(btn, i == 0)

		var normal_sb := StyleBoxFlat.new()
		normal_sb.bg_color = C_SURFACE
		normal_sb.set_border_width_all(1)
		normal_sb.border_color = C_BORDER
		normal_sb.set_corner_radius_all(0)
		normal_sb.set_content_margin_all(6)
		if i == 0:
			normal_sb.corner_radius_top_left = 4
			normal_sb.corner_radius_bottom_left = 4
		if i == options.size() - 1:
			normal_sb.corner_radius_top_right = 4
			normal_sb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", normal_sb)

		var active_sb := normal_sb.duplicate()
		active_sb.bg_color = C_ACCENT
		active_sb.border_color = C_ACCENT
		btn.add_theme_stylebox_override("pressed", active_sb)

		var hover_sb := normal_sb.duplicate()
		hover_sb.bg_color = C_SURFACE_HOVER
		btn.add_theme_stylebox_override("hover", hover_sb)

		buttons.append(btn)
		hbox.add_child(btn)

	for i in range(buttons.size()):
		var idx := i
		var opt: Dictionary = options[i]
		buttons[i].pressed.connect(func() -> void:
			for j in range(buttons.size()):
				buttons[j].button_pressed = (j == idx)
				_apply_toggle_style(buttons[j], j == idx)
			callback.call(opt["key"])
		)

	return hbox


func _apply_toggle_style(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_TEXT)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)


func _style_checkbutton_transparent(cb: CheckButton) -> void:
	## Remove background fill from CheckButton so only the indicator shows state.
	for state in ["normal", "pressed", "hover", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.set_content_margin_all(4)
		cb.add_theme_stylebox_override(state, sb)


## Create a slider with inline value label. Returns [HBoxContainer, HSlider, Label].
func _make_slider_row(min_val: float, max_val: float, default_val: float, step_val: float) -> Array:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var val_label := Label.new()
	val_label.text = str(default_val)
	val_label.custom_minimum_size.x = 40
	val_label.add_theme_font_size_override("font_size", FONT_VALUE)
	val_label.add_theme_color_override("font_color", C_TEXT_SEC)
	hbox.add_child(val_label)

	slider.value_changed.connect(func(v: float) -> void:
		if step_val >= 1.0:
			val_label.text = str(int(v))
		else:
			val_label.text = "%.2f" % v
	)

	return [hbox, slider, val_label]


## Create a styled primary (accent) button.
func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = C_ACCENT_HOVER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	hover_sb.content_margin_top = 12
	hover_sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn


## Create a styled subtle (outline) button.
func _make_subtle_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_border_width_all(1)
	sb.border_color = C_BORDER
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(C_SURFACE, 0.5)
	hover_sb.set_border_width_all(1)
	hover_sb.border_color = C_BORDER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	hover_sb.content_margin_top = 12
	hover_sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("hover", hover_sb)
	return btn
