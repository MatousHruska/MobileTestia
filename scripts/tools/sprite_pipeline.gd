extends Control
## Sprite Pipeline Wizard
##
## Unified tool that chains 3D sprite capture and pixel art conversion
## into a single 5-step wizard flow with saveable presets.
##
## Steps:
##   1. Model & Animation — select model, pick animation, configure camera
##   2. Capture Preview — auto-capture all 3 directions, confirm
##   3. Pixel Art Settings — configure processing, preview result
##   4. Export — process all directions, save final pixel art
##   5. Apply to SpriteFrames — load exported sheets into player_sprites.tres
##
## Run: scenes/tools/sprite_pipeline.tscn (F6)

#===============================================================================
# CONSTANTS
#===============================================================================

const IMPORT_DIR := "res://assets/3d_imports"
const CAPTURES_DIR := "res://assets/sprites/captures"
const OUTPUT_BASE := "res://assets/sprites/final"
const PALETTE_DIR := "res://assets/palettes"
const PRESETS_DIR := "res://assets/sprites/presets"

const SPRITEFRAMES_PATH := "res://resources/player_sprites.tres"
const FRAME_SIZE := 64

const APPLY_ANIM_GROUPS := [
	{
		"folder": "Idle",
		"fps": 10,
		"loop": true,
		"sheets": {
			"idle_down": "mixamo_com_down.png",
			"idle_up": "mixamo_com_up.png",
			"idle_right": "mixamo_com_right.png",
		},
	},
	{
		"folder": "Walking",
		"fps": 15,
		"loop": true,
		"sheets": {
			"walk_down": "mixamo_com_down.png",
			"walk_up": "mixamo_com_up.png",
			"walk_right": "mixamo_com_right.png",
		},
	},
	{
		"folder": "Slash",
		"fps": 20,
		"loop": false,
		"sheets": {
			"attack_down": "mixamo_com_down.png",
			"attack_up": "mixamo_com_up.png",
			"attack_right": "mixamo_com_right.png",
		},
	},
]

const ANIMS_TO_REMOVE := [
	"melee_windup_down", "melee_windup_up", "melee_windup_right",
	"melee_strike_down", "melee_strike_up", "melee_strike_right",
	"thrust_down", "thrust_up", "thrust_right",
]

const DIRECTIONS := [
	{ "name": "down", "rotation_y": 0.0 },
	{ "name": "up", "rotation_y": 180.0 },
	{ "name": "right", "rotation_y": 90.0 },
]

#===============================================================================
# WIZARD STATE
#===============================================================================

var _current_step := 0  # 0-4
var _step_containers: Array[VBoxContainer] = []  # one per step

## Step 1 state
var current_model_path: String = ""
var current_model_instance: Node = null
var current_anim_player: AnimationPlayer = null
var available_models: Array[String] = []
var camera_target: Vector3 = Vector3.ZERO

## Step 2 state
var _captured_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }

## Step 3 state
var _palette_colors: PackedColorArray = PackedColorArray()
var _preview_direction := "down"

## Preset
var _current_preset: Dictionary = {}

#===============================================================================
# NODE REFERENCES
#===============================================================================

# Step indicator
var step_indicator_label: Label

# Step 1 nodes
var model_dropdown: OptionButton
var anim_dropdown: OptionButton
var frame_count_spin: SpinBox
var camera_elevation_slider: HSlider
var camera_elevation_label: Label
var camera_zoom_slider: HSlider
var camera_zoom_label: Label
var camera_target_y_slider: HSlider
var camera_target_y_label: Label
var camera_settings_container: VBoxContainer
var preset_status_label: Label
var preview_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var model_slot: Node3D

# Step 2 nodes
var capture_down_rect: TextureRect
var capture_up_rect: TextureRect
var capture_right_rect: TextureRect

# Step 3 nodes
var output_height_spin: SpinBox
var alpha_threshold_slider: HSlider
var alpha_threshold_label: Label
var palette_mode_dropdown: OptionButton
var palette_file_dropdown: OptionButton
var max_palette_colors_spin: SpinBox
var generate_palette_button: Button
var palette_preview_container: HFlowContainer
var dithering_toggle: CheckButton
var dithering_strength_slider: HSlider
var dithering_pattern_dropdown: OptionButton
var outline_toggle: CheckButton
var outline_color_picker: ColorPickerButton
var denoising_toggle: CheckButton
var denoising_min_cluster_spin: SpinBox
var pixel_preview_rect: TextureRect
var show_original_toggle: CheckButton

# Step 4 nodes
var export_log_label: Label

# Step 5 nodes
var apply_log_label: Label
var apply_button: Button

# Shared
var status_label: Label
var back_button: Button
var next_button: Button

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_build_viewport()
	await get_tree().process_frame
	_scan_models()


func _build_ui() -> void:
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 12)
	add_child(root_hbox)

	# Left panel — controls
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
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
	title.text = "Sprite Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Step indicator
	step_indicator_label = Label.new()
	step_indicator_label.text = "Step 1 of 5: Model & Animation"
	step_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_indicator_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(step_indicator_label)

	vbox.add_child(HSeparator.new())

	# Build 5 step containers
	var step1 := VBoxContainer.new()
	step1.add_theme_constant_override("separation", 8)
	vbox.add_child(step1)
	_step_containers.append(step1)

	var step2 := VBoxContainer.new()
	step2.add_theme_constant_override("separation", 8)
	step2.visible = false
	vbox.add_child(step2)
	_step_containers.append(step2)

	var step3 := VBoxContainer.new()
	step3.add_theme_constant_override("separation", 8)
	step3.visible = false
	vbox.add_child(step3)
	_step_containers.append(step3)

	var step4 := VBoxContainer.new()
	step4.add_theme_constant_override("separation", 8)
	step4.visible = false
	vbox.add_child(step4)
	_step_containers.append(step4)

	var step5 := VBoxContainer.new()
	step5.add_theme_constant_override("separation", 8)
	step5.visible = false
	vbox.add_child(step5)
	_step_containers.append(step5)

	# Build each step's contents
	_build_step1(step1)
	_build_step2(step2)
	_build_step3(step3)
	_build_step4(step4)
	_build_step5(step5)

	vbox.add_child(HSeparator.new())

	# Navigation row
	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(nav_hbox)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.size_flags_horizontal = SIZE_EXPAND_FILL
	back_button.visible = false
	back_button.pressed.connect(func() -> void: _go_to_step(_current_step - 1))
	nav_hbox.add_child(back_button)

	next_button = Button.new()
	next_button.text = "Next"
	next_button.size_flags_horizontal = SIZE_EXPAND_FILL
	next_button.disabled = true
	next_button.pressed.connect(_on_next_pressed)
	nav_hbox.add_child(next_button)

	vbox.add_child(HSeparator.new())

	# Status
	status_label = Label.new()
	status_label.text = "Drop .glb files into assets/3d_imports/ and they will appear above."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(status_label)

	# Right side — split into two areas stacked vertically
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_hbox.add_child(right_vbox)

	# Top: 3D viewport preview (Steps 1-2)
	var aspect_box := AspectRatioContainer.new()
	aspect_box.ratio = 1.0
	aspect_box.size_flags_horizontal = SIZE_EXPAND_FILL
	aspect_box.size_flags_vertical = SIZE_EXPAND_FILL
	right_vbox.add_child(aspect_box)

	preview_container = SubViewportContainer.new()
	preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	preview_container.stretch = true
	aspect_box.add_child(preview_container)

	# Bottom: 2D pixel preview (Step 3), initially hidden
	var pixel_preview_scroll := ScrollContainer.new()
	pixel_preview_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	pixel_preview_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	pixel_preview_scroll.visible = false
	right_vbox.add_child(pixel_preview_scroll)

	pixel_preview_rect = TextureRect.new()
	pixel_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pixel_preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	pixel_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	pixel_preview_rect.size_flags_vertical = SIZE_EXPAND_FILL
	pixel_preview_scroll.add_child(pixel_preview_rect)


#===============================================================================
# STEP 1 — MODEL & ANIMATION
#===============================================================================

func _build_step1(parent: VBoxContainer) -> void:
	# Model selector
	parent.add_child(_make_label("3D Model:"))
	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	parent.add_child(model_dropdown)

	# Animation selector
	parent.add_child(_make_label("Animation:"))
	anim_dropdown = OptionButton.new()
	anim_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	anim_dropdown.item_selected.connect(_on_animation_selected)
	parent.add_child(anim_dropdown)

	# Frame count
	parent.add_child(_make_label("Frames per direction:"))
	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 2
	frame_count_spin.max_value = 60
	frame_count_spin.value = 8
	frame_count_spin.step = 1
	parent.add_child(frame_count_spin)

	parent.add_child(HSeparator.new())

	# Preset status
	preset_status_label = Label.new()
	preset_status_label.text = "(no preset)"
	parent.add_child(preset_status_label)

	# Camera settings toggle
	var cam_toggle_btn := Button.new()
	cam_toggle_btn.text = "Show Camera Settings"
	cam_toggle_btn.pressed.connect(func() -> void:
		camera_settings_container.visible = not camera_settings_container.visible
		cam_toggle_btn.text = "Hide Camera Settings" if camera_settings_container.visible else "Show Camera Settings"
	)
	parent.add_child(cam_toggle_btn)

	# Camera settings container (initially hidden)
	camera_settings_container = VBoxContainer.new()
	camera_settings_container.visible = false
	camera_settings_container.add_theme_constant_override("separation", 8)
	parent.add_child(camera_settings_container)

	# Camera elevation
	camera_settings_container.add_child(_make_label("Camera elevation (degrees):"))
	var elev_hbox := HBoxContainer.new()
	camera_settings_container.add_child(elev_hbox)
	camera_elevation_slider = HSlider.new()
	camera_elevation_slider.min_value = 10.0
	camera_elevation_slider.max_value = 80.0
	camera_elevation_slider.value = 30.0
	camera_elevation_slider.step = 1.0
	camera_elevation_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	elev_hbox.add_child(camera_elevation_slider)
	camera_elevation_label = Label.new()
	camera_elevation_label.text = "30"
	camera_elevation_label.custom_minimum_size.x = 30
	elev_hbox.add_child(camera_elevation_label)
	var elev_hint := Label.new()
	elev_hint.text = "(default: 30)"
	elev_hint.add_theme_font_size_override("font_size", 10)
	elev_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	camera_settings_container.add_child(elev_hint)

	# Camera zoom
	camera_settings_container.add_child(_make_label("Camera zoom:"))
	var zoom_hbox := HBoxContainer.new()
	camera_settings_container.add_child(zoom_hbox)
	camera_zoom_slider = HSlider.new()
	camera_zoom_slider.min_value = 0.5
	camera_zoom_slider.max_value = 15.0
	camera_zoom_slider.value = 3.0
	camera_zoom_slider.step = 0.1
	camera_zoom_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	camera_zoom_slider.value_changed.connect(_on_zoom_changed)
	zoom_hbox.add_child(camera_zoom_slider)
	camera_zoom_label = Label.new()
	camera_zoom_label.text = "3.0"
	camera_zoom_label.custom_minimum_size.x = 40
	zoom_hbox.add_child(camera_zoom_label)
	var zoom_hint := Label.new()
	zoom_hint.text = "(default: 3.0)"
	zoom_hint.add_theme_font_size_override("font_size", 10)
	zoom_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	camera_settings_container.add_child(zoom_hint)

	# Camera target height
	camera_settings_container.add_child(_make_label("Camera target height:"))
	var target_y_hbox := HBoxContainer.new()
	camera_settings_container.add_child(target_y_hbox)
	camera_target_y_slider = HSlider.new()
	camera_target_y_slider.min_value = 0.0
	camera_target_y_slider.max_value = 5.0
	camera_target_y_slider.value = 1.0
	camera_target_y_slider.step = 0.05
	camera_target_y_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	camera_target_y_slider.value_changed.connect(_on_target_y_changed)
	target_y_hbox.add_child(camera_target_y_slider)
	camera_target_y_label = Label.new()
	camera_target_y_label.text = "1.0"
	camera_target_y_label.custom_minimum_size.x = 40
	target_y_hbox.add_child(camera_target_y_label)

	# Direction preview buttons
	camera_settings_container.add_child(_make_label("Preview direction:"))
	var dir_hbox := HBoxContainer.new()
	dir_hbox.add_theme_constant_override("separation", 4)
	camera_settings_container.add_child(dir_hbox)
	var front_btn := Button.new()
	front_btn.text = "Front"
	front_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	front_btn.pressed.connect(_on_preview_direction.bind(0.0))
	dir_hbox.add_child(front_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	back_btn.pressed.connect(_on_preview_direction.bind(180.0))
	dir_hbox.add_child(back_btn)
	var side_btn := Button.new()
	side_btn.text = "Side"
	side_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	side_btn.pressed.connect(_on_preview_direction.bind(90.0))
	dir_hbox.add_child(side_btn)

	# Save preset button
	var save_preset_btn := Button.new()
	save_preset_btn.text = "Save Camera Preset"
	save_preset_btn.pressed.connect(_save_preset)
	camera_settings_container.add_child(save_preset_btn)


#===============================================================================
# STEP 2 — CAPTURE PREVIEW
#===============================================================================

func _build_step2(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Capturing 3 directions..."))

	parent.add_child(_make_label("Down:"))
	capture_down_rect = TextureRect.new()
	capture_down_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_down_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_down_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(capture_down_rect)

	parent.add_child(_make_label("Up:"))
	capture_up_rect = TextureRect.new()
	capture_up_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_up_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_up_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(capture_up_rect)

	parent.add_child(_make_label("Right:"))
	capture_right_rect = TextureRect.new()
	capture_right_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_right_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_right_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(capture_right_rect)


#===============================================================================
# STEP 3 — PIXEL ART SETTINGS
#===============================================================================

func _build_step3(parent: VBoxContainer) -> void:
	# Direction preview selector
	parent.add_child(_make_label("Preview direction:"))
	var dir_btn_hbox := HBoxContainer.new()
	dir_btn_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(dir_btn_hbox)
	var dir_down_btn := Button.new()
	dir_down_btn.text = "Down"
	dir_down_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	dir_down_btn.pressed.connect(func() -> void:
		_preview_direction = "down"
		_update_pixel_preview()
	)
	dir_btn_hbox.add_child(dir_down_btn)
	var dir_up_btn := Button.new()
	dir_up_btn.text = "Up"
	dir_up_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	dir_up_btn.pressed.connect(func() -> void:
		_preview_direction = "up"
		_update_pixel_preview()
	)
	dir_btn_hbox.add_child(dir_up_btn)
	var dir_right_btn := Button.new()
	dir_right_btn.text = "Right"
	dir_right_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	dir_right_btn.pressed.connect(func() -> void:
		_preview_direction = "right"
		_update_pixel_preview()
	)
	dir_btn_hbox.add_child(dir_right_btn)

	parent.add_child(HSeparator.new())

	# Output height
	parent.add_child(_make_label("Output height (px):"))
	output_height_spin = SpinBox.new()
	output_height_spin.min_value = 16
	output_height_spin.max_value = 256
	output_height_spin.value = 64
	output_height_spin.step = 8
	output_height_spin.value_changed.connect(_on_pixel_setting_changed)
	parent.add_child(output_height_spin)

	# Alpha threshold
	parent.add_child(_make_label("Alpha threshold:"))
	var alpha_hbox := HBoxContainer.new()
	parent.add_child(alpha_hbox)
	alpha_threshold_slider = HSlider.new()
	alpha_threshold_slider.min_value = 0
	alpha_threshold_slider.max_value = 255
	alpha_threshold_slider.value = 128
	alpha_threshold_slider.step = 1
	alpha_threshold_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	alpha_threshold_slider.value_changed.connect(_on_alpha_threshold_changed)
	alpha_hbox.add_child(alpha_threshold_slider)
	alpha_threshold_label = Label.new()
	alpha_threshold_label.text = "128"
	alpha_threshold_label.custom_minimum_size.x = 30
	alpha_hbox.add_child(alpha_threshold_label)

	parent.add_child(HSeparator.new())

	# Palette mode
	parent.add_child(_make_label("Palette mode:"))
	palette_mode_dropdown = OptionButton.new()
	palette_mode_dropdown.add_item("None")
	palette_mode_dropdown.add_item("Load from Palettes")
	palette_mode_dropdown.add_item("Generate from Captures")
	palette_mode_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_mode_dropdown.item_selected.connect(_on_palette_mode_changed)
	parent.add_child(palette_mode_dropdown)

	# Palette file dropdown (hidden by default)
	palette_file_dropdown = OptionButton.new()
	palette_file_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_file_dropdown.visible = false
	palette_file_dropdown.item_selected.connect(_on_palette_file_selected)
	parent.add_child(palette_file_dropdown)

	# Generate palette controls (hidden by default)
	parent.add_child(_make_label("Max palette colors:"))
	max_palette_colors_spin = SpinBox.new()
	max_palette_colors_spin.min_value = 4
	max_palette_colors_spin.max_value = 128
	max_palette_colors_spin.value = 32
	max_palette_colors_spin.step = 4
	max_palette_colors_spin.visible = false
	parent.add_child(max_palette_colors_spin)

	generate_palette_button = Button.new()
	generate_palette_button.text = "Generate Palette from Captures"
	generate_palette_button.visible = false
	generate_palette_button.pressed.connect(_on_generate_palette_pressed)
	parent.add_child(generate_palette_button)

	# Palette preview swatches
	palette_preview_container = HFlowContainer.new()
	palette_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(palette_preview_container)

	parent.add_child(HSeparator.new())

	# Dithering
	dithering_toggle = CheckButton.new()
	dithering_toggle.text = "Dithering"
	dithering_toggle.toggled.connect(_on_pixel_toggle_changed)
	parent.add_child(dithering_toggle)

	parent.add_child(_make_label("  Strength:"))
	dithering_strength_slider = HSlider.new()
	dithering_strength_slider.min_value = 0.0
	dithering_strength_slider.max_value = 1.0
	dithering_strength_slider.value = 0.5
	dithering_strength_slider.step = 0.05
	dithering_strength_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	dithering_strength_slider.value_changed.connect(_on_pixel_setting_changed)
	parent.add_child(dithering_strength_slider)

	parent.add_child(_make_label("  Pattern:"))
	dithering_pattern_dropdown = OptionButton.new()
	dithering_pattern_dropdown.add_item("2x2")
	dithering_pattern_dropdown.add_item("4x4")
	dithering_pattern_dropdown.add_item("8x8")
	dithering_pattern_dropdown.selected = 1
	dithering_pattern_dropdown.item_selected.connect(_on_pixel_setting_changed)
	parent.add_child(dithering_pattern_dropdown)

	# Outline
	outline_toggle = CheckButton.new()
	outline_toggle.text = "Outline"
	outline_toggle.toggled.connect(_on_pixel_toggle_changed)
	parent.add_child(outline_toggle)

	var outline_hbox := HBoxContainer.new()
	parent.add_child(outline_hbox)
	outline_hbox.add_child(_make_label("  Color: "))
	outline_color_picker = ColorPickerButton.new()
	outline_color_picker.color = Color.BLACK
	outline_color_picker.custom_minimum_size = Vector2(40, 30)
	outline_color_picker.color_changed.connect(_on_pixel_color_changed)
	outline_hbox.add_child(outline_color_picker)

	# Denoising
	denoising_toggle = CheckButton.new()
	denoising_toggle.text = "Denoising"
	denoising_toggle.toggled.connect(_on_pixel_toggle_changed)
	parent.add_child(denoising_toggle)

	var denoise_hbox := HBoxContainer.new()
	parent.add_child(denoise_hbox)
	denoise_hbox.add_child(_make_label("  Min cluster: "))
	denoising_min_cluster_spin = SpinBox.new()
	denoising_min_cluster_spin.min_value = 1
	denoising_min_cluster_spin.max_value = 50
	denoising_min_cluster_spin.value = 4
	denoising_min_cluster_spin.step = 1
	denoising_min_cluster_spin.value_changed.connect(_on_pixel_setting_changed)
	denoise_hbox.add_child(denoising_min_cluster_spin)

	parent.add_child(HSeparator.new())

	# Save settings to preset
	var save_settings_btn := Button.new()
	save_settings_btn.text = "Save Settings to Preset"
	save_settings_btn.pressed.connect(_save_pixel_art_preset)
	parent.add_child(save_settings_btn)

	# Show original toggle
	show_original_toggle = CheckButton.new()
	show_original_toggle.text = "Show Original"
	show_original_toggle.toggled.connect(_on_pixel_toggle_changed)
	parent.add_child(show_original_toggle)


#===============================================================================
# STEP 4 — EXPORT
#===============================================================================

func _build_step4(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Exporting..."))

	export_log_label = Label.new()
	export_log_label.text = ""
	export_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(export_log_label)

	parent.add_child(HSeparator.new())

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	parent.add_child(run_again_btn)

	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.pressed.connect(_on_done_pressed)
	parent.add_child(done_btn)


#===============================================================================
# STEP 5 — APPLY TO SPRITEFRAMES
#===============================================================================

func _build_step5(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Apply exported sheets to SpriteFrames"))

	var path_label := Label.new()
	path_label.text = "Target: %s" % SPRITEFRAMES_PATH
	path_label.add_theme_font_size_override("font_size", 12)
	path_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(path_label)

	parent.add_child(HSeparator.new())

	# Animation groups summary
	parent.add_child(_make_label("Animations to apply:"))
	for group in APPLY_ANIM_GROUPS:
		var folder: String = group["folder"]
		var fps: int = group["fps"]
		var loop: bool = group["loop"]
		var sheets: Dictionary = group["sheets"]
		var anim_names := ", ".join(sheets.keys())
		var summary := Label.new()
		summary.text = "  %s (fps=%d, loop=%s): %s" % [folder, fps, loop, anim_names]
		summary.add_theme_font_size_override("font_size", 12)
		parent.add_child(summary)

	var remove_label := Label.new()
	remove_label.text = "Will remove: %s" % ", ".join(ANIMS_TO_REMOVE)
	remove_label.add_theme_font_size_override("font_size", 11)
	remove_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	remove_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	remove_label.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(remove_label)

	parent.add_child(HSeparator.new())

	apply_button = Button.new()
	apply_button.text = "Apply to SpriteFrames"
	apply_button.pressed.connect(_apply_to_spriteframes)
	parent.add_child(apply_button)

	apply_log_label = Label.new()
	apply_log_label.text = ""
	apply_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(apply_log_label)

	parent.add_child(HSeparator.new())

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	parent.add_child(run_again_btn)

	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.pressed.connect(_on_done_pressed)
	parent.add_child(done_btn)


#===============================================================================
# WIZARD NAVIGATION
#===============================================================================

func _go_to_step(step: int) -> void:
	_current_step = step
	for i in range(_step_containers.size()):
		_step_containers[i].visible = (i == step)
	# Update navigation buttons
	back_button.visible = step > 0
	next_button.visible = (step < 4)
	next_button.text = "Export" if step == 3 else "Next"
	# Update step indicator
	var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Settings", "Export", "Apply to SpriteFrames"]
	step_indicator_label.text = "Step %d of 5: %s" % [step + 1, step_names[step]]
	# Update preview visibility
	var viewport_area := preview_container.get_parent()  # AspectRatioContainer
	viewport_area.visible = (step <= 1)
	pixel_preview_rect.get_parent().visible = (step == 2)
	# Trigger step-specific logic
	match step:
		0:
			next_button.disabled = (current_anim_player == null)
		1:
			_start_capture()
		2:
			_scan_palettes()
			if _current_preset.has("pixel_art"):
				_apply_pixel_art_preset(_current_preset["pixel_art"])
			_update_pixel_preview()
		3:
			_start_export()
		4:
			pass  # User clicks Apply manually


func _on_next_pressed() -> void:
	if _current_step < 4:
		_go_to_step(_current_step + 1)


#===============================================================================
# 3D VIEWPORT
#===============================================================================

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
		_on_model_selected(0)


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

	current_anim_player = _find_animation_player(current_model_instance)
	_populate_animations()

	_set_status("Loaded: %s" % file_name)

	# Check for preset
	var model_name := current_model_path.get_file().get_basename()
	_load_preset(model_name)

	# Enable next button if we have an animation
	next_button.disabled = (current_anim_player == null)


func _clear_model() -> void:
	if current_model_instance != null:
		current_model_instance.queue_free()
		current_model_instance = null
	current_anim_player = null
	anim_dropdown.clear()


func _find_animation_player(node: Node) -> AnimationPlayer:
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
	next_button.disabled = false


#===============================================================================
# MATERIAL OVERRIDE — UNLIT
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


#===============================================================================
# CAMERA
#===============================================================================

func _position_camera(elevation_deg: float) -> void:
	var elevation_rad := deg_to_rad(elevation_deg)
	var distance := maxf(camera.size * 2.0, 5.0)
	var offset_y := sin(elevation_rad) * distance
	var offset_z := cos(elevation_rad) * distance
	camera.position = camera_target + Vector3(0.0, offset_y, offset_z)
	camera.look_at(camera_target, Vector3.UP)


func _on_elevation_changed(value: float) -> void:
	camera_elevation_label.text = str(int(value))
	_position_camera(value)


func _on_zoom_changed(value: float) -> void:
	camera_zoom_label.text = "%.1f" % value
	camera.size = value
	_position_camera(camera_elevation_slider.value)


func _on_preview_direction(rotation_y: float) -> void:
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = rotation_y


func _on_target_y_changed(value: float) -> void:
	camera_target_y_label.text = "%.2f" % value
	camera_target = Vector3(0.0, value, 0.0)
	_position_camera(camera_elevation_slider.value)


#===============================================================================
# PRESET SYSTEM
#===============================================================================

func _save_preset() -> void:
	var model_name := current_model_path.get_file().get_basename()
	if model_name.is_empty():
		_set_status("ERROR: No model loaded.")
		return

	_current_preset["camera"] = {
		"elevation": camera_elevation_slider.value,
		"zoom": camera_zoom_slider.value,
		"target_y": camera_target_y_slider.value,
	}
	_current_preset["capture"] = {
		"frame_count": int(frame_count_spin.value),
	}

	var global_dir := ProjectSettings.globalize_path(PRESETS_DIR)
	DirAccess.make_dir_recursive_absolute(global_dir)

	var preset_path := "%s/%s.json" % [PRESETS_DIR, model_name]
	var global_path := ProjectSettings.globalize_path(preset_path)

	var file := FileAccess.open(global_path, FileAccess.WRITE)
	if file == null:
		_set_status("ERROR: Could not write preset.")
		return
	file.store_string(JSON.stringify(_current_preset, "\t"))
	file.close()

	preset_status_label.text = "(preset saved)"
	_set_status("Preset saved: %s" % preset_path)


func _load_preset(model_name: String) -> void:
	_current_preset = {}
	var preset_path := "%s/%s.json" % [PRESETS_DIR, model_name]
	var global_path := ProjectSettings.globalize_path(preset_path)

	if not FileAccess.file_exists(global_path):
		preset_status_label.text = "(no preset)"
		return

	var file := FileAccess.open(global_path, FileAccess.READ)
	if file == null:
		preset_status_label.text = "(no preset)"
		return
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		_set_status("WARNING: Could not parse preset file.")
		preset_status_label.text = "(preset error)"
		return

	_current_preset = json.data
	_apply_preset()
	preset_status_label.text = "(preset loaded)"
	_set_status("Loaded preset for %s" % model_name)


func _apply_preset() -> void:
	if _current_preset.has("camera"):
		var cam: Dictionary = _current_preset["camera"]
		if cam.has("elevation"):
			camera_elevation_slider.value = cam["elevation"]
		if cam.has("zoom"):
			camera_zoom_slider.value = cam["zoom"]
		if cam.has("target_y"):
			camera_target_y_slider.value = cam["target_y"]
	if _current_preset.has("capture"):
		var cap: Dictionary = _current_preset["capture"]
		if cap.has("frame_count"):
			frame_count_spin.value = cap["frame_count"]
	if _current_preset.has("pixel_art"):
		_apply_pixel_art_preset(_current_preset["pixel_art"])


func _apply_pixel_art_preset(settings: Dictionary) -> void:
	if settings.has("output_height"):
		output_height_spin.value = settings["output_height"]
	if settings.has("alpha_threshold"):
		alpha_threshold_slider.value = settings["alpha_threshold"]
	if settings.has("dithering_enabled"):
		dithering_toggle.button_pressed = settings["dithering_enabled"]
	if settings.has("dithering_strength"):
		dithering_strength_slider.value = settings["dithering_strength"]
	if settings.has("dithering_pattern"):
		dithering_pattern_dropdown.selected = settings["dithering_pattern"]
	if settings.has("outline_enabled"):
		outline_toggle.button_pressed = settings["outline_enabled"]
	if settings.has("outline_color"):
		outline_color_picker.color = Color(settings["outline_color"])
	if settings.has("denoising_enabled"):
		denoising_toggle.button_pressed = settings["denoising_enabled"]
	if settings.has("denoising_min_cluster"):
		denoising_min_cluster_spin.value = settings["denoising_min_cluster"]


func _save_pixel_art_preset() -> void:
	_current_preset["pixel_art"] = {
		"output_height": int(output_height_spin.value),
		"alpha_threshold": int(alpha_threshold_slider.value),
		"dithering_enabled": dithering_toggle.button_pressed,
		"dithering_strength": dithering_strength_slider.value,
		"dithering_pattern": dithering_pattern_dropdown.selected,
		"outline_enabled": outline_toggle.button_pressed,
		"outline_color": outline_color_picker.color.to_html(),
		"denoising_enabled": denoising_toggle.button_pressed,
		"denoising_min_cluster": int(denoising_min_cluster_spin.value),
	}
	_save_preset()


#===============================================================================
# CAPTURE (Step 2)
#===============================================================================

func _start_capture() -> void:
	if current_anim_player == null:
		_set_status("ERROR: No model or animation loaded.")
		_go_to_step(0)
		return
	_captured_sheets.clear()
	next_button.disabled = true
	back_button.disabled = true
	await _capture_animation()
	next_button.disabled = false
	back_button.disabled = false


func _capture_animation() -> void:
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var frame_count := int(frame_count_spin.value)
	var output_size := 512  # Always capture at 512px

	var original_vp_size := sub_viewport.size
	sub_viewport.size = Vector2i(output_size, output_size)
	preview_container.stretch = false

	var anim := current_anim_player.get_animation(anim_name)
	if anim == null:
		_set_status("ERROR: Animation '%s' not found." % anim_name)
		return

	var anim_length := anim.length
	var direction_rects := [capture_down_rect, capture_up_rect, capture_right_rect]

	for dir_idx in range(DIRECTIONS.size()):
		var dir_config: Dictionary = DIRECTIONS[dir_idx]
		var dir_name: String = dir_config["name"]
		var rot_y: float = dir_config["rotation_y"]

		_set_status("Capturing %s (%d frames)..." % [dir_name, frame_count])

		if current_model_instance is Node3D:
			(current_model_instance as Node3D).rotation_degrees.y = rot_y

		var sheet_width := output_size * frame_count
		var sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)

		for frame_idx in range(frame_count):
			var seek_time: float
			if frame_count == 1:
				seek_time = 0.0
			else:
				seek_time = (float(frame_idx) / float(frame_count)) * anim_length
			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var frame_image := sub_viewport.get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame_image, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

		_captured_sheets[dir_name] = sheet
		# Show preview
		var tex := ImageTexture.create_from_image(sheet)
		direction_rects[dir_idx].texture = tex

	# Save intermediate captures to disk
	var model_name := current_model_path.get_file().get_basename()
	var safe_anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected).replace(" ", "_").replace("/", "_").to_lower()
	var output_dir := "%s/%s" % [CAPTURES_DIR, model_name]
	var global_output_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(global_output_dir)

	for dir_name in _captured_sheets:
		var file_path := "%s/%s_%s.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		_captured_sheets[dir_name].save_png(global_path)

	# Reset model rotation
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0

	sub_viewport.size = original_vp_size
	preview_container.stretch = true

	_set_status("Captured all 3 directions. Review and click Next.")


#===============================================================================
# IMAGE PROCESSING (Step 3)
#===============================================================================

const BAYER_2X2 := [
	[0.0, 2.0],
	[3.0, 1.0],
]

const BAYER_4X4 := [
	[ 0.0,  8.0,  2.0, 10.0],
	[12.0,  4.0, 14.0,  6.0],
	[ 3.0, 11.0,  1.0,  9.0],
	[15.0,  7.0, 13.0,  5.0],
]

const BAYER_8X8 := [
	[ 0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0],
	[48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0],
	[12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0],
	[60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0],
	[ 3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0],
	[51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0],
	[15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0],
	[63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0],
]


func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	_apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	if dithering_toggle.button_pressed:
		_apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	if not _palette_colors.is_empty():
		_apply_palette_mapping(result)
	elif dithering_toggle.button_pressed:
		_apply_auto_quantize(result)

	if outline_toggle.button_pressed:
		_apply_outline(result, outline_color_picker.color)

	if denoising_toggle.button_pressed:
		_apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result


func _apply_alpha_threshold(image: Image, threshold: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if int(color.a * 255.0) >= threshold:
				color.a = 1.0
			else:
				color.a = 0.0
			image.set_pixel(x, y, color)


func _apply_ordered_dithering(image: Image, strength: float, pattern_index: int) -> void:
	var matrix: Array
	var matrix_size: int
	var matrix_max: float
	match pattern_index:
		0:
			matrix = BAYER_2X2
			matrix_size = 2
			matrix_max = 4.0
		1:
			matrix = BAYER_4X4
			matrix_size = 4
			matrix_max = 16.0
		2:
			matrix = BAYER_8X8
			matrix_size = 8
			matrix_max = 64.0
		_:
			return

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var threshold: float = (matrix[y % matrix_size][x % matrix_size] / matrix_max - 0.5) * strength
			color.r = clampf(color.r + threshold, 0.0, 1.0)
			color.g = clampf(color.g + threshold, 0.0, 1.0)
			color.b = clampf(color.b + threshold, 0.0, 1.0)
			image.set_pixel(x, y, color)


func _apply_palette_mapping(image: Image) -> void:
	if _palette_colors.is_empty():
		return
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var nearest := _find_nearest_palette_color(color)
			nearest.a = 1.0
			image.set_pixel(x, y, nearest)


func _apply_auto_quantize(image: Image) -> void:
	## Snap each RGB channel to 5-bit precision (32 levels) to make dithering visible
	## without an explicit palette.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			color.r = snappedf(color.r, 1.0 / 31.0)
			color.g = snappedf(color.g, 1.0 / 31.0)
			color.b = snappedf(color.b, 1.0 / 31.0)
			image.set_pixel(x, y, color)


func _find_nearest_palette_color(target: Color) -> Color:
	var best_color := _palette_colors[0]
	var best_dist := _color_distance_sq(target, best_color)
	for i in range(1, _palette_colors.size()):
		var dist := _color_distance_sq(target, _palette_colors[i])
		if dist < best_dist:
			best_dist = dist
			best_color = _palette_colors[i]
	return best_color


func _color_distance_sq(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db


func _apply_outline(image: Image, outline_color: Color) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var outline_pixels: Array[Vector2i] = []

	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if color.a >= 0.5:
				continue
			var has_opaque_neighbor := false
			if x > 0 and image.get_pixel(x - 1, y).a >= 0.5:
				has_opaque_neighbor = true
			elif x < width - 1 and image.get_pixel(x + 1, y).a >= 0.5:
				has_opaque_neighbor = true
			elif y > 0 and image.get_pixel(x, y - 1).a >= 0.5:
				has_opaque_neighbor = true
			elif y < height - 1 and image.get_pixel(x, y + 1).a >= 0.5:
				has_opaque_neighbor = true
			if has_opaque_neighbor:
				outline_pixels.append(Vector2i(x, y))

	for pos in outline_pixels:
		image.set_pixel(pos.x, pos.y, outline_color)


func _apply_denoising(image: Image, min_cluster_size: int) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}

	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if visited.has(pos):
				continue
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				visited[pos] = true
				continue

			var cluster: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			while not queue.is_empty():
				var current: Vector2i = queue.pop_back()
				if visited.has(current):
					continue
				if current.x < 0 or current.x >= width or current.y < 0 or current.y >= height:
					continue
				if image.get_pixel(current.x, current.y).a < 0.5:
					visited[current] = true
					continue
				visited[current] = true
				cluster.append(current)
				queue.append(Vector2i(current.x + 1, current.y))
				queue.append(Vector2i(current.x - 1, current.y))
				queue.append(Vector2i(current.x, current.y + 1))
				queue.append(Vector2i(current.x, current.y - 1))

			if cluster.size() < min_cluster_size:
				for pixel_pos in cluster:
					image.set_pixel(pixel_pos.x, pixel_pos.y, Color.TRANSPARENT)


#===============================================================================
# PIXEL PREVIEW
#===============================================================================

func _update_pixel_preview() -> void:
	if not _captured_sheets.has(_preview_direction):
		return
	if show_original_toggle.button_pressed:
		var tex := ImageTexture.create_from_image(_captured_sheets[_preview_direction])
		pixel_preview_rect.texture = tex
		return
	var processed := _process_image(_captured_sheets[_preview_direction])
	var tex := ImageTexture.create_from_image(processed)
	pixel_preview_rect.texture = tex


func _on_alpha_threshold_changed(value: float) -> void:
	alpha_threshold_label.text = str(int(value))
	_update_pixel_preview()


func _on_pixel_setting_changed(_value) -> void:
	_update_pixel_preview()


func _on_pixel_toggle_changed(_enabled: bool) -> void:
	_update_pixel_preview()


func _on_pixel_color_changed(_color: Color) -> void:
	_update_pixel_preview()


#===============================================================================
# PALETTE (Step 3)
#===============================================================================

func _on_palette_mode_changed(index: int) -> void:
	# 0=None, 1=Load from Palettes, 2=Generate from Captures
	palette_file_dropdown.visible = (index == 1)
	generate_palette_button.visible = (index == 2)
	max_palette_colors_spin.visible = (index == 2)
	if index == 0:
		_palette_colors.clear()
		_update_palette_preview()
	_update_pixel_preview()


func _on_palette_file_selected(index: int) -> void:
	if index < 0:
		return
	var palette_name: String = palette_file_dropdown.get_item_text(index)
	var palette_path := "%s/%s" % [PALETTE_DIR, palette_name]
	var global_path := ProjectSettings.globalize_path(palette_path)
	_load_palette_from_path(global_path)


func _scan_palettes() -> void:
	palette_file_dropdown.clear()

	var global_dir := ProjectSettings.globalize_path(PALETTE_DIR)
	var dir := DirAccess.open(global_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(global_dir)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".png"):
			palette_file_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


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
	_update_palette_preview()
	_update_pixel_preview()


func _update_palette_preview() -> void:
	for child in palette_preview_container.get_children():
		child.queue_free()
	for color in _palette_colors:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = color
		palette_preview_container.add_child(swatch)


func _on_generate_palette_pressed() -> void:
	if _captured_sheets.is_empty():
		_set_status("ERROR: No captures available. Go back to Step 2.")
		return

	var max_colors := int(max_palette_colors_spin.value)
	var color_counts := {}

	for dir_name in _captured_sheets:
		var img := _captured_sheets[dir_name].duplicate() as Image
		var target_height := int(output_height_spin.value)
		var scale_factor := float(target_height) / float(img.get_height())
		var target_width := int(float(img.get_width()) * scale_factor)
		img.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
		_apply_alpha_threshold(img, int(alpha_threshold_slider.value))

		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var color := img.get_pixel(x, y)
				if color.a < 0.5:
					continue
				var snapped := Color(
					snappedf(color.r, 1.0 / 31.0),
					snappedf(color.g, 1.0 / 31.0),
					snappedf(color.b, 1.0 / 31.0),
					1.0
				)
				if color_counts.has(snapped):
					color_counts[snapped] += 1
				else:
					color_counts[snapped] = 1

	if color_counts.is_empty():
		_set_status("ERROR: No opaque pixels found.")
		return

	var sorted_colors: Array = color_counts.keys()
	sorted_colors.sort_custom(func(a: Color, b: Color) -> bool:
		return color_counts[a] > color_counts[b]
	)

	_palette_colors.clear()
	for i in range(mini(max_colors, sorted_colors.size())):
		_palette_colors.append(sorted_colors[i])

	# Save palette
	var model_name := current_model_path.get_file().get_basename()
	var palette_image := Image.create(_palette_colors.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(_palette_colors.size()):
		palette_image.set_pixel(i, 0, _palette_colors[i])

	var global_dir := ProjectSettings.globalize_path(PALETTE_DIR)
	DirAccess.make_dir_recursive_absolute(global_dir)
	var palette_name := "%s_palette.png" % model_name
	var output_path := "%s/%s" % [PALETTE_DIR, palette_name]
	palette_image.save_png(ProjectSettings.globalize_path(output_path))

	_set_status("Generated palette: %d colors" % _palette_colors.size())
	_update_palette_preview()
	_update_pixel_preview()


#===============================================================================
# EXPORT (Step 4)
#===============================================================================

func _start_export() -> void:
	next_button.visible = false
	back_button.disabled = true
	export_log_label.text = ""

	var model_name := current_model_path.get_file().get_basename()
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var safe_anim_name := anim_name.replace(" ", "_").replace("/", "_").to_lower()
	var output_dir := "%s/%s" % [OUTPUT_BASE, model_name]
	var global_output_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(global_output_dir)

	var count := 0
	for dir_name in _captured_sheets:
		_set_status("Processing %s..." % dir_name)
		var processed := _process_image(_captured_sheets[dir_name])

		var output_path := "%s/%s_%s.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(output_path)
		var err := processed.save_png(global_path)
		if err != OK:
			_append_log("ERROR: Failed to save %s" % output_path)
			continue
		_append_log("Saved: %s" % output_path)
		count += 1

	_append_log("\nExported %d files to %s/" % [count, output_dir])
	_set_status("Export complete! %d files saved." % count)
	back_button.disabled = false
	next_button.visible = true
	next_button.text = "Next"


func _append_log(text: String) -> void:
	export_log_label.text += text + "\n"
	print("[SpritePipeline] %s" % text)


func _on_run_again_pressed() -> void:
	_captured_sheets.clear()
	_go_to_step(0)


func _on_done_pressed() -> void:
	_captured_sheets.clear()
	_palette_colors.clear()
	_clear_model()
	_go_to_step(0)
	_scan_models()


#===============================================================================
# APPLY TO SPRITEFRAMES (Step 5)
#===============================================================================

func _apply_to_spriteframes() -> void:
	apply_button.disabled = true
	apply_log_label.text = ""
	_set_status("Applying sprite sheets to SpriteFrames...")

	var frames := ResourceLoader.load(SPRITEFRAMES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	if frames == null:
		_append_apply_log("ERROR: Could not load SpriteFrames: %s" % SPRITEFRAMES_PATH)
		_set_status("Apply failed — could not load SpriteFrames.")
		apply_button.disabled = false
		return

	# Remove old placeholder melee animations that block fallback to attack_*
	_append_apply_log("--- Removing old melee placeholders ---")
	for anim_name in ANIMS_TO_REMOVE:
		if frames.has_animation(anim_name):
			frames.remove_animation(anim_name)
			_append_apply_log("  Removed: %s" % anim_name)

	var total_anims := 0
	for group in APPLY_ANIM_GROUPS:
		var folder: String = group["folder"]
		var fps: int = group["fps"]
		var loop: bool = group["loop"]
		var sheets: Dictionary = group["sheets"]

		_append_apply_log("--- %s (fps=%d, loop=%s) ---" % [folder, fps, loop])

		for anim_name in sheets:
			var sheet_filename: String = sheets[anim_name]
			var sheet_path := "%s/%s/%s" % [OUTPUT_BASE, folder, sheet_filename]
			var abs_path := ProjectSettings.globalize_path(sheet_path)

			var sheet_image := Image.load_from_file(abs_path)
			if sheet_image == null:
				_append_apply_log("  ERROR: Failed to load: %s" % abs_path)
				continue

			var frame_count := sheet_image.get_width() / FRAME_SIZE
			_append_apply_log("  %s: %d frames from %s" % [anim_name, frame_count, sheet_filename])

			# Remove existing animation and recreate
			if frames.has_animation(anim_name):
				frames.remove_animation(anim_name)
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			frames.set_animation_loop(anim_name, loop)

			# Use AtlasTexture regions from the full sheet
			var sheet_texture := ImageTexture.create_from_image(sheet_image)
			for i in range(frame_count):
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = sheet_texture
				atlas_tex.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim_name, atlas_tex)

			total_anims += 1

	var err := ResourceSaver.save(frames, SPRITEFRAMES_PATH)
	if err != OK:
		_append_apply_log("\nERROR: Failed to save SpriteFrames (error %d)" % err)
		_set_status("Apply failed — could not save SpriteFrames.")
		apply_button.disabled = false
		return

	_append_apply_log("\nDone! %d animations updated in %s" % [total_anims, SPRITEFRAMES_PATH])
	_set_status("Apply complete! %d animations updated." % total_anims)
	apply_button.disabled = false


func _append_apply_log(text: String) -> void:
	apply_log_label.text += text + "\n"
	print("[SpritePipeline] %s" % text)


#===============================================================================
# UTILS
#===============================================================================

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _set_status(text: String) -> void:
	status_label.text = text
	print("[SpritePipeline] %s" % text)
