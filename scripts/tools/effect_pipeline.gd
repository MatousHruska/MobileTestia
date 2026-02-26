extends Control
## Effect Capture Pipeline Wizard
##
## 5-step tool for importing 3D effect animations (.glb), capturing them
## from 3 directions via SubViewport, converting to pixel art with softer
## defaults tuned for VFX, editing frames, and exporting directional spritesheets.
##
## Steps:
##   1. Model & Animation Selection — pick model, animation, configure camera
##   2. Capture Preview — auto-capture 3 directions, review thumbnails
##   3. Pixel Art Processing — configure processing with effect-tuned defaults
##   4. Frame Editor — preview animation, delete frames across all directions
##   5. Export — save directional spritesheets + metadata.json
##
## Run: scenes/tools/effect_pipeline.tscn (F6)

#===============================================================================
# CONSTANTS
#===============================================================================

const IMPORT_DIR := "res://assets/3d_imports"
const OUTPUT_BASE := "res://assets/sprites/effects"

## Overscan factor for detection pass — renders a wider view to find the full
## effect extent, then re-renders at normal zoom with the camera panned
## to keep the effect centered.
const CAPTURE_OVERSCAN := 1.5

const DIRECTIONS := [
	{ "name": "down", "rotation_y": 0.0 },
	{ "name": "up", "rotation_y": 180.0 },
	{ "name": "right", "rotation_y": 90.0 },
]

#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")
const C_DANGER := Color("#EF5350")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

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
var _capture_frame_count := 0

## Step 3 state
var _preview_direction := "down"

## Step 4 (Frame Editor) state
var _frame_editor_viewport: SubViewport = null
var _frame_editor_container: SubViewportContainer = null
var _frame_editor_sprite: Sprite2D = null
var _frame_editor_onion_sprite: Sprite2D = null
var _frame_editor_frame := 0
var _frame_editor_frame_count := 0
var _frame_editor_playing := false
var _frame_editor_timer := 0.0
var _frame_editor_direction := "down"
var _frame_editor_frame_label: Label = null
var _frame_editor_deleted_count := 0

## Step 5 state
var _export_frame_size := 32

#===============================================================================
# NODE REFERENCES
#===============================================================================

# Step indicator
var step_indicator_label: Label
var step_indicator: Control  # StepIndicator custom control

# Step 1 nodes
var model_dropdown: OptionButton
var anim_dropdown: OptionButton
var anim_info_label: Label
var effect_id_edit: LineEdit
var frame_count_spin: SpinBox
var camera_elevation_slider: HSlider
var camera_elevation_label: Label
var camera_zoom_slider: HSlider
var camera_zoom_label: Label
var camera_target_y_slider: HSlider
var camera_target_y_label: Label
var preview_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var model_slot: Node3D

# Step 2 nodes
var capture_down_rect: TextureRect
var capture_up_rect: TextureRect
var capture_right_rect: TextureRect
var _capture_btn: Button = null
var _capture_frame_count_label: Label = null

# Step 3 nodes
var output_height_spin: SpinBox
var alpha_threshold_slider: HSlider
var alpha_threshold_label: Label
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
var _frame_editor_delete_btn: Button = null
var _frame_editor_deleted_label: Label = null
var _frame_editor_onion_toggle: CheckButton = null
var _frame_editor_fps_spin: SpinBox = null
var _frame_editor_play_btn: Button = null

# Step 5 nodes
var export_log_label: Label
var _export_summary_label: Label = null

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


func _process(delta: float) -> void:
	if _frame_editor_playing and _current_step == 3:
		_frame_editor_timer += delta
		var fps: float = _frame_editor_fps_spin.value if _frame_editor_fps_spin else 15.0
		if fps <= 0.0:
			fps = 15.0
		if _frame_editor_timer >= 1.0 / fps:
			_frame_editor_timer -= 1.0 / fps
			if _frame_editor_frame_count > 0:
				_frame_editor_frame = (_frame_editor_frame + 1) % _frame_editor_frame_count
				_update_frame_editor_frame()


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
	root_hbox.add_child(panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(left_vbox)

	# Title (fixed at top)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_top", 12)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(title_margin)
	var title := Label.new()
	title.text = "Effect Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Step indicator (custom draw widget)
	var StepIndicatorScript := load("res://scripts/tools/step_indicator.gd")
	step_indicator = StepIndicatorScript.new()
	step_indicator.total_steps = 5
	step_indicator.step_names = PackedStringArray([
		"Model & Animation", "Capture Preview", "Pixel Art Processing",
		"Frame Editor", "Export"
	])
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 8)
	indicator_margin.add_theme_constant_override("margin_right", 8)
	indicator_margin.add_theme_constant_override("margin_bottom", 8)
	left_vbox.add_child(indicator_margin)
	indicator_margin.add_child(step_indicator)

	# Hidden label for old reference compat
	step_indicator_label = Label.new()
	step_indicator_label.visible = false
	left_vbox.add_child(step_indicator_label)

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

	# Build 5 step containers
	for i in range(5):
		var step_cont := VBoxContainer.new()
		step_cont.add_theme_constant_override("separation", 10)
		step_cont.visible = (i == 0)
		steps_vbox.add_child(step_cont)
		_step_containers.append(step_cont)

	# Build each step's contents
	_build_step1(_step_containers[0])
	_build_step2(_step_containers[1])
	_build_step3(_step_containers[2])
	_build_step4(_step_containers[3])
	_build_step5(_step_containers[4])

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
	back_button.visible = false
	back_button.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(back_button)

	next_button = _make_primary_button("Next  \u25b6")
	next_button.disabled = true
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
	status_label.text = "Drop .glb files into assets/3d_imports/ and they will appear above."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", FONT_HINT)
	status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	status_label.max_lines_visible = 2
	status_panel.add_child(status_label)

	# -- Right side -- preview areas --
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_hbox.add_child(right_vbox)

	# Top: 3D viewport preview (Steps 0-1)
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

	# 2D pixel preview (Step 2), initially hidden
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

	# Frame editor viewport (Step 3), initially hidden
	_frame_editor_container = SubViewportContainer.new()
	_frame_editor_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_frame_editor_container.size_flags_vertical = SIZE_EXPAND_FILL
	_frame_editor_container.stretch = true
	_frame_editor_container.visible = false
	right_vbox.add_child(_frame_editor_container)

	# Frame counter label directly below the preview viewport
	_frame_editor_frame_label = Label.new()
	_frame_editor_frame_label.text = "Frame 1 / 1"
	_frame_editor_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_frame_editor_frame_label.add_theme_font_size_override("font_size", FONT_LABEL)
	_frame_editor_frame_label.add_theme_color_override("font_color", C_TEXT)
	_frame_editor_frame_label.visible = false
	right_vbox.add_child(_frame_editor_frame_label)


#===============================================================================
# STEP 1 — MODEL & ANIMATION SELECTION
#===============================================================================

func _build_step1(parent: VBoxContainer) -> void:
	var sec := _make_section("Model & Animation")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Model selector
	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	content.add_child(_make_field("3D Model", model_dropdown))

	# Animation selector
	anim_dropdown = OptionButton.new()
	anim_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	anim_dropdown.item_selected.connect(_on_animation_selected)
	content.add_child(_make_field("Animation", anim_dropdown))

	# Anim info
	anim_info_label = Label.new()
	anim_info_label.text = ""
	anim_info_label.add_theme_font_size_override("font_size", FONT_VALUE)
	anim_info_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(anim_info_label)

	# Effect ID
	effect_id_edit = LineEdit.new()
	effect_id_edit.placeholder_text = "e.g. slash_arc"
	effect_id_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(_make_field("Effect ID", effect_id_edit))

	# Frame count
	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 2
	frame_count_spin.max_value = 60
	frame_count_spin.value = 8
	frame_count_spin.step = 1
	content.add_child(_make_field("Frames per direction", frame_count_spin))

	# Camera settings (collapsible)
	var cam := _make_collapsible("Camera Settings")
	parent.add_child(cam[0])
	var cam_content: VBoxContainer = cam[1]

	# Camera elevation
	var elev_data := _make_slider_row(0.0, 90.0, 30.0, 1.0)
	camera_elevation_slider = elev_data[1]
	camera_elevation_label = elev_data[2]
	camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	cam_content.add_child(_make_field("Elevation (degrees)", elev_data[0]))

	# Camera zoom
	var zoom_data := _make_slider_row(1.0, 10.0, 3.0, 0.1)
	camera_zoom_slider = zoom_data[1]
	camera_zoom_label = zoom_data[2]
	camera_zoom_slider.value_changed.connect(_on_zoom_changed)
	cam_content.add_child(_make_field("Zoom", zoom_data[0]))

	# Camera target height
	var target_data := _make_slider_row(0.0, 3.0, 1.0, 0.05)
	camera_target_y_slider = target_data[1]
	camera_target_y_label = target_data[2]
	camera_target_y_slider.value_changed.connect(_on_target_y_changed)
	cam_content.add_child(_make_field("Target height", target_data[0]))

	# Direction preview buttons
	var dir_group := _make_toggle_group([
		{"label": "Front", "key": "front"},
		{"label": "Back", "key": "back"},
		{"label": "Side", "key": "side"},
	], func(key: String) -> void:
		var angles := {"front": 0.0, "back": 180.0, "side": 90.0}
		_on_preview_direction(angles[key])
	)
	cam_content.add_child(_make_field("Preview direction", dir_group))


#===============================================================================
# STEP 2 — CAPTURE PREVIEW
#===============================================================================

func _build_step2(parent: VBoxContainer) -> void:
	var sec := _make_section("Capture Preview")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label("Capture the effect from 3 directions (down, up, right)."))

	_capture_btn = _make_primary_button("Capture All Directions")
	_capture_btn.pressed.connect(_start_capture)
	content.add_child(_capture_btn)

	_capture_frame_count_label = Label.new()
	_capture_frame_count_label.text = ""
	_capture_frame_count_label.add_theme_font_size_override("font_size", FONT_HINT)
	_capture_frame_count_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(_capture_frame_count_label)

	# Direction previews
	content.add_child(_make_label("Down:"))
	capture_down_rect = TextureRect.new()
	capture_down_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_down_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_down_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_down_rect)

	content.add_child(_make_label("Up:"))
	capture_up_rect = TextureRect.new()
	capture_up_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_up_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_up_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_up_rect)

	content.add_child(_make_label("Right:"))
	capture_right_rect = TextureRect.new()
	capture_right_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_right_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_right_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_right_rect)


#===============================================================================
# STEP 3 — PIXEL ART PROCESSING
#===============================================================================

func _build_step3(parent: VBoxContainer) -> void:
	var sec := _make_section("Pixel Art Processing")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Direction preview selector
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_preview_direction = key
		_update_pixel_preview()
	)
	content.add_child(_make_field("Preview direction", dir_group))

	# Output height — effect-tuned default: 32
	output_height_spin = SpinBox.new()
	output_height_spin.min_value = 16
	output_height_spin.max_value = 256
	output_height_spin.value = 32
	output_height_spin.step = 8
	output_height_spin.value_changed.connect(_on_pixel_setting_changed)
	content.add_child(_make_field("Target height (px)", output_height_spin))

	# Alpha threshold — effect-tuned default: 64 (softer, preserves semi-transparency)
	var alpha_data := _make_slider_row(0, 255, 64, 1)
	alpha_threshold_slider = alpha_data[1]
	alpha_threshold_label = alpha_data[2]
	alpha_threshold_slider.value_changed.connect(_on_alpha_threshold_changed)
	content.add_child(_make_field("Alpha threshold", alpha_data[0]))

	# Dithering (collapsible) — effect-tuned default: OFF
	var dither := _make_collapsible("Dithering")
	parent.add_child(dither[0])
	var dither_content: VBoxContainer = dither[1]

	dithering_toggle = CheckButton.new()
	dithering_toggle.text = "Enable"
	dithering_toggle.button_pressed = false  # OFF for effects
	dithering_toggle.toggled.connect(_on_pixel_toggle_changed)
	dither_content.add_child(dithering_toggle)
	_style_checkbutton_transparent(dithering_toggle)

	var strength_data := _make_slider_row(0.0, 1.0, 0.5, 0.05)
	dithering_strength_slider = strength_data[1]
	dithering_strength_slider.value_changed.connect(_on_pixel_setting_changed)
	dither_content.add_child(_make_field("Strength", strength_data[0]))

	dithering_pattern_dropdown = OptionButton.new()
	dithering_pattern_dropdown.add_item("2x2")
	dithering_pattern_dropdown.add_item("4x4")
	dithering_pattern_dropdown.add_item("8x8")
	dithering_pattern_dropdown.selected = 1
	dithering_pattern_dropdown.item_selected.connect(_on_pixel_setting_changed)
	dither_content.add_child(_make_field("Pattern", dithering_pattern_dropdown))

	# Outline (collapsible) — effect-tuned default: OFF
	var outline := _make_collapsible("Outline")
	parent.add_child(outline[0])
	var outline_content: VBoxContainer = outline[1]

	outline_toggle = CheckButton.new()
	outline_toggle.text = "Enable"
	outline_toggle.button_pressed = false  # OFF for effects
	outline_toggle.toggled.connect(_on_pixel_toggle_changed)
	outline_content.add_child(outline_toggle)
	_style_checkbutton_transparent(outline_toggle)

	var outline_color_hbox := HBoxContainer.new()
	outline_color_hbox.add_theme_constant_override("separation", 8)
	outline_content.add_child(outline_color_hbox)
	outline_color_hbox.add_child(_make_label("Color:"))
	outline_color_picker = ColorPickerButton.new()
	outline_color_picker.color = Color.BLACK
	outline_color_picker.custom_minimum_size = Vector2(40, 30)
	outline_color_picker.color_changed.connect(_on_pixel_color_changed)
	outline_color_hbox.add_child(outline_color_picker)

	# Denoising (collapsible) — effect-tuned default: ON, min cluster 2
	var denoise := _make_collapsible("Denoising", true)
	parent.add_child(denoise[0])
	var denoise_content: VBoxContainer = denoise[1]

	denoising_toggle = CheckButton.new()
	denoising_toggle.text = "Enable"
	denoising_toggle.button_pressed = true  # ON for effects
	denoising_toggle.toggled.connect(_on_pixel_toggle_changed)
	denoise_content.add_child(denoising_toggle)
	_style_checkbutton_transparent(denoising_toggle)

	denoising_min_cluster_spin = SpinBox.new()
	denoising_min_cluster_spin.min_value = 1
	denoising_min_cluster_spin.max_value = 50
	denoising_min_cluster_spin.value = 2  # Smaller default for effects
	denoising_min_cluster_spin.step = 1
	denoising_min_cluster_spin.value_changed.connect(_on_pixel_setting_changed)
	denoise_content.add_child(_make_field("Min cluster size", denoising_min_cluster_spin))

	# Show original toggle
	var actions_sec := _make_section("Preview Options")
	parent.add_child(actions_sec[0])
	var actions_content: VBoxContainer = actions_sec[1]

	show_original_toggle = CheckButton.new()
	show_original_toggle.text = "Show Original (before processing)"
	show_original_toggle.toggled.connect(_on_pixel_toggle_changed)
	actions_content.add_child(show_original_toggle)
	_style_checkbutton_transparent(show_original_toggle)


#===============================================================================
# STEP 4 — FRAME EDITOR
#===============================================================================

func _build_step4(parent: VBoxContainer) -> void:
	var sec := _make_section("Frame Editor")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label("Preview the processed animation and remove unwanted frames. Deletion applies to ALL 3 directions simultaneously."))

	# Direction buttons
	var dir_group := _make_toggle_group([
		{"label": "D", "key": "down"},
		{"label": "U", "key": "up"},
		{"label": "R", "key": "right"},
	], func(key: String) -> void:
		_on_frame_editor_direction_changed(key)
	)
	content.add_child(_make_field("Direction", dir_group))

	# Frame navigation
	var frame_hbox := HBoxContainer.new()
	frame_hbox.add_theme_constant_override("separation", 4)
	content.add_child(frame_hbox)

	var prev_btn := Button.new()
	prev_btn.text = "\u25c0"
	prev_btn.custom_minimum_size.x = 32
	prev_btn.pressed.connect(func() -> void:
		if _frame_editor_frame_count <= 0:
			return
		_frame_editor_frame = (_frame_editor_frame - 1) % _frame_editor_frame_count
		if _frame_editor_frame < 0:
			_frame_editor_frame += _frame_editor_frame_count
		_update_frame_editor_frame()
	)
	frame_hbox.add_child(prev_btn)

	_frame_editor_play_btn = Button.new()
	_frame_editor_play_btn.text = "Play"
	_frame_editor_play_btn.pressed.connect(func() -> void:
		_frame_editor_playing = not _frame_editor_playing
		_frame_editor_play_btn.text = "Stop" if _frame_editor_playing else "Play"
	)
	frame_hbox.add_child(_frame_editor_play_btn)

	var next_frame_btn := Button.new()
	next_frame_btn.text = "\u25b6"
	next_frame_btn.custom_minimum_size.x = 32
	next_frame_btn.pressed.connect(func() -> void:
		if _frame_editor_frame_count <= 0:
			return
		_frame_editor_frame = (_frame_editor_frame + 1) % _frame_editor_frame_count
		_update_frame_editor_frame()
	)
	frame_hbox.add_child(next_frame_btn)

	# FPS adjustment
	_frame_editor_fps_spin = SpinBox.new()
	_frame_editor_fps_spin.min_value = 1
	_frame_editor_fps_spin.max_value = 60
	_frame_editor_fps_spin.value = 15
	_frame_editor_fps_spin.step = 1
	content.add_child(_make_field("FPS", _frame_editor_fps_spin))

	# Onion skin toggle
	_frame_editor_onion_toggle = CheckButton.new()
	_frame_editor_onion_toggle.text = "Onion Skin (show previous frame)"
	_frame_editor_onion_toggle.toggled.connect(func(_on: bool) -> void:
		_update_frame_editor_frame()
	)
	content.add_child(_frame_editor_onion_toggle)
	_style_checkbutton_transparent(_frame_editor_onion_toggle)

	# Delete Frame button (danger-styled)
	_frame_editor_delete_btn = Button.new()
	_frame_editor_delete_btn.text = "Delete This Frame (all dirs)"
	var del_sb := StyleBoxFlat.new()
	del_sb.bg_color = C_DANGER
	del_sb.set_corner_radius_all(4)
	del_sb.set_content_margin_all(8)
	_frame_editor_delete_btn.add_theme_stylebox_override("normal", del_sb)
	var del_hover := StyleBoxFlat.new()
	del_hover.bg_color = Color("#FF6666")
	del_hover.set_corner_radius_all(4)
	del_hover.set_content_margin_all(8)
	_frame_editor_delete_btn.add_theme_stylebox_override("hover", del_hover)
	_frame_editor_delete_btn.add_theme_color_override("font_color", Color.WHITE)
	_frame_editor_delete_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_frame_editor_delete_btn.pressed.connect(_delete_current_frame)
	content.add_child(_frame_editor_delete_btn)

	# Deleted count label
	_frame_editor_deleted_label = Label.new()
	_frame_editor_deleted_label.text = ""
	_frame_editor_deleted_label.add_theme_font_size_override("font_size", FONT_HINT)
	_frame_editor_deleted_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(_frame_editor_deleted_label)


#===============================================================================
# STEP 5 — EXPORT
#===============================================================================

func _build_step5(parent: VBoxContainer) -> void:
	var sec := _make_section("Export")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	_export_summary_label = Label.new()
	_export_summary_label.text = ""
	_export_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_summary_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_export_summary_label.add_theme_font_size_override("font_size", FONT_LABEL)
	_export_summary_label.add_theme_color_override("font_color", C_TEXT)
	content.add_child(_export_summary_label)

	export_log_label = Label.new()
	export_log_label.text = ""
	export_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	export_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	export_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(export_log_label)

	var run_again_btn := Button.new()
	run_again_btn.text = "Start Over"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	content.add_child(run_again_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(_on_done_pressed)
	content.add_child(done_btn)


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
	next_button.text = "Export  \u25b6" if step == 3 else "Next  \u25b6"
	# Style Next button for export transition
	if step == 3:
		var warning_sb := StyleBoxFlat.new()
		warning_sb.bg_color = C_WARNING
		warning_sb.set_corner_radius_all(4)
		warning_sb.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("normal", warning_sb)
		var warning_hover := StyleBoxFlat.new()
		warning_hover.bg_color = Color(C_WARNING, 0.8)
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
	# Update step indicator
	var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Processing",
		"Frame Editor", "Export"]
	step_indicator_label.text = "Step %d of 5: %s" % [step + 1, step_names[step]]
	if step_indicator:
		step_indicator.set_step(step)
	# Update preview visibility
	var viewport_area := preview_container.get_parent()  # AspectRatioContainer
	viewport_area.visible = (step <= 1)
	pixel_preview_rect.get_parent().visible = (step == 2)
	if _frame_editor_container:
		_frame_editor_container.visible = (step == 3)
	if _frame_editor_frame_label:
		_frame_editor_frame_label.visible = (step == 3)
	# Stop frame editor playback when leaving step 3
	if step != 3:
		_frame_editor_playing = false
		if _frame_editor_play_btn:
			_frame_editor_play_btn.text = "Play"
	# Trigger step-specific logic
	match step:
		0:
			next_button.disabled = (current_anim_player == null)
		1:
			next_button.disabled = _captured_sheets.is_empty()
		2:
			_update_pixel_preview()
		3:
			_frame_editor_deleted_count = 0
			_setup_frame_editor()
		4:
			_start_export()


func _on_next_pressed() -> void:
	if _current_step < 4:
		_go_to_step(_current_step + 1)


func _on_back_pressed() -> void:
	if _current_step > 0:
		_go_to_step(_current_step - 1)


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
		if lower.ends_with(".glb") or lower.ends_with(".gltf"):
			available_models.append(file_name)
			model_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if available_models.is_empty():
		_set_status("No models found. Place .glb/.gltf files in assets/3d_imports/")
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

	# Auto-populate effect ID from model name
	var model_base := file_name.get_basename().to_lower().replace(" ", "_")
	effect_id_edit.text = model_base

	# Enable next button if we have an animation
	next_button.disabled = (current_anim_player == null)


func _clear_model() -> void:
	if current_model_instance != null:
		current_model_instance.queue_free()
		current_model_instance = null
	current_anim_player = null
	anim_dropdown.clear()
	anim_info_label.text = ""


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
		anim_info_label.text = ""
		return
	var anim_name: String = anim_dropdown.get_item_text(index)
	current_anim_player.play(anim_name)
	current_anim_player.seek(0.0, true)
	next_button.disabled = false

	# Show source animation length info
	var anim := current_anim_player.get_animation(anim_name)
	if anim != null:
		var length_sec := anim.length
		var step := anim.step
		if step > 0.0:
			var src_frames := int(round(length_sec / step))
			var src_fps := int(round(1.0 / step))
			anim_info_label.text = "%d frames  |  %.2fs  |  %d fps" % [src_frames, length_sec, src_fps]
			frame_count_spin.value = clampi(src_frames, int(frame_count_spin.min_value), int(frame_count_spin.max_value))
		else:
			anim_info_label.text = "%.2fs" % length_sec
	else:
		anim_info_label.text = ""

	# Update effect ID with animation name
	var model_base := current_model_path.get_file().get_basename().to_lower().replace(" ", "_")
	var anim_safe := anim_name.replace(" ", "_").replace("/", "_").to_lower()
	effect_id_edit.text = "%s_%s" % [model_base, anim_safe]


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
	_capture_btn.disabled = true
	await _capture_animation()
	_capture_btn.disabled = false
	next_button.disabled = false
	back_button.disabled = false


func _capture_animation() -> void:
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var frame_count := int(frame_count_spin.value)
	var output_size := 512  # Final frame size in pixels

	var original_vp_size := sub_viewport.size
	var original_cam_size := camera.size
	var original_cam_target := camera_target
	preview_container.stretch = false

	var anim := current_anim_player.get_animation(anim_name)
	if anim == null:
		_set_status("ERROR: Animation '%s' not found." % anim_name)
		return

	var anim_length := anim.length

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

			# --- Detection pass: wide-angle render to find effect extent ---
			var detect_size := int(output_size * CAPTURE_OVERSCAN)
			sub_viewport.size = Vector2i(detect_size, detect_size)
			camera.size = original_cam_size * CAPTURE_OVERSCAN
			camera_target = original_cam_target
			_position_camera(camera_elevation_slider.value)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var detect_img := sub_viewport.get_texture().get_image()
			detect_img.convert(Image.FORMAT_RGBA8)

			# Find bounding box center offset from viewport center
			var cam_shift := _compute_camera_pan(detect_img, detect_size, original_cam_size * CAPTURE_OVERSCAN)

			# --- Final pass: normal zoom with camera panned to center effect ---
			sub_viewport.size = Vector2i(output_size, output_size)
			camera.size = original_cam_size
			camera_target = original_cam_target + cam_shift
			_position_camera(camera_elevation_slider.value)

			# Re-seek the animation to the same time
			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var frame_image := sub_viewport.get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame_image, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

		_captured_sheets[dir_name] = sheet

	_capture_frame_count = frame_count
	_update_capture_preview()

	# Restore camera and viewport
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0

	sub_viewport.size = original_vp_size
	camera.size = original_cam_size
	camera_target = original_cam_target
	_position_camera(camera_elevation_slider.value)
	preview_container.stretch = true

	_capture_frame_count_label.text = "Captured %d frames x 3 directions." % frame_count
	_set_status("Captured all 3 directions. Review and click Next.")


func _compute_camera_pan(detect_img: Image, detect_size: int, detect_cam_size: float) -> Vector3:
	## Given a detection-pass render (wider view), find the bounding box of opaque
	## pixels and compute a world-space camera shift to center the effect.
	## Returns Vector3.ZERO if no shift is needed.
	var w := detect_img.get_width()
	var h := detect_img.get_height()
	var min_x := w
	var min_y := h
	var max_x := 0
	var max_y := 0

	for y in range(h):
		for x in range(w):
			if detect_img.get_pixel(x, y).a > 0.1:
				if x < min_x:
					min_x = x
				if x > max_x:
					max_x = x
				if y < min_y:
					min_y = y
				if y > max_y:
					max_y = y

	# No opaque pixels — no shift needed
	if max_x < min_x:
		return Vector3.ZERO

	# Bounding box center offset from viewport center (in pixels)
	var center_px_x := (min_x + max_x) / 2.0
	var center_px_y := (min_y + max_y) / 2.0
	var offset_px_x := center_px_x - detect_size / 2.0
	var offset_px_y := center_px_y - detect_size / 2.0

	# If offset is small (effect is already centered), skip the shift
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


func _update_capture_preview() -> void:
	var rects: Array[TextureRect] = [capture_down_rect, capture_up_rect, capture_right_rect]
	var dir_names := ["down", "up", "right"]
	for i in range(3):
		if _captured_sheets.has(dir_names[i]):
			rects[i].texture = ImageTexture.create_from_image(_captured_sheets[dir_names[i]])


#===============================================================================
# IMAGE PROCESSING (Step 3) — delegates to PixelArtProcessing utility
#===============================================================================

func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	# Downscale
	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	# Alpha threshold
	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	# Dithering (default OFF for effects)
	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	# Palette mapping — effects don't use palette by default, but keep auto-quantize for dithered
	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_auto_quantize(result)

	# Outline (default OFF for effects)
	if outline_toggle.button_pressed:
		PixelArtProcessing.apply_outline(result, outline_color_picker.color)

	# Denoising (default ON for effects)
	if denoising_toggle.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result


#===============================================================================
# PIXEL PREVIEW (Step 3)
#===============================================================================

func _update_pixel_preview() -> void:
	if not _captured_sheets.has(_preview_direction):
		return
	if show_original_toggle.button_pressed:
		var source: Image = _captured_sheets[_preview_direction]
		if source:
			pixel_preview_rect.texture = ImageTexture.create_from_image(source)
		return

	var processed := _process_image(_captured_sheets[_preview_direction])
	pixel_preview_rect.texture = ImageTexture.create_from_image(processed)


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
# FRAME EDITOR LOGIC (Step 4)
#===============================================================================

func _setup_frame_editor() -> void:
	if _frame_editor_viewport:
		_frame_editor_viewport.queue_free()

	_frame_editor_viewport = SubViewport.new()
	_frame_editor_viewport.transparent_bg = false
	_frame_editor_viewport.size = Vector2i(400, 400)
	_frame_editor_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_frame_editor_container.add_child(_frame_editor_viewport)

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.size = Vector2(400, 400)
	_frame_editor_viewport.add_child(bg)

	# Process color sheet for current direction
	if not _captured_sheets.has(_frame_editor_direction):
		_frame_editor_direction = "down"
	if not _captured_sheets.has(_frame_editor_direction):
		return

	var color_processed := _process_image(_captured_sheets[_frame_editor_direction])
	var color_tex := ImageTexture.create_from_image(color_processed)

	# Calculate frame info
	var frame_size := int(output_height_spin.value)
	_frame_editor_frame_count = color_processed.get_width() / maxi(frame_size, 1)
	if _frame_editor_frame_count < 1:
		_frame_editor_frame_count = 1
	_frame_editor_frame = clampi(_frame_editor_frame, 0, _frame_editor_frame_count - 1)

	# Create sprite showing single frame via AtlasTexture
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = color_tex
	atlas_tex.region = Rect2(0, 0, frame_size, frame_size)

	# Onion skin sprite (previous frame, semi-transparent) — added first so it draws behind
	var onion_atlas := AtlasTexture.new()
	onion_atlas.atlas = color_tex
	onion_atlas.region = Rect2(0, 0, frame_size, frame_size)
	_frame_editor_onion_sprite = Sprite2D.new()
	_frame_editor_onion_sprite.texture = onion_atlas
	_frame_editor_onion_sprite.position = Vector2(200, 200)
	_frame_editor_onion_sprite.scale = Vector2(3, 3)
	_frame_editor_onion_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame_editor_onion_sprite.self_modulate = Color(1, 0.4, 0.4, 0.35)
	_frame_editor_onion_sprite.visible = false
	_frame_editor_viewport.add_child(_frame_editor_onion_sprite)

	# Current frame sprite
	_frame_editor_sprite = Sprite2D.new()
	_frame_editor_sprite.texture = atlas_tex
	_frame_editor_sprite.position = Vector2(200, 200)
	_frame_editor_sprite.scale = Vector2(3, 3)
	_frame_editor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame_editor_viewport.add_child(_frame_editor_sprite)

	_update_frame_editor_frame()
	# Update delete button state
	_frame_editor_delete_btn.disabled = (_frame_editor_frame_count <= 1)
	if _frame_editor_deleted_count > 0:
		_frame_editor_deleted_label.text = "%d frame(s) deleted" % _frame_editor_deleted_count
	else:
		_frame_editor_deleted_label.text = ""


func _update_frame_editor_frame() -> void:
	var frame_size := int(output_height_spin.value)
	if _frame_editor_sprite and _frame_editor_sprite.texture is AtlasTexture:
		var atlas := _frame_editor_sprite.texture as AtlasTexture
		atlas.region = Rect2(_frame_editor_frame * frame_size, 0, frame_size, frame_size)
	# Onion skin — show previous frame behind the current one
	if _frame_editor_onion_sprite and _frame_editor_onion_sprite.texture is AtlasTexture:
		var show_onion := _frame_editor_onion_toggle and _frame_editor_onion_toggle.button_pressed
		var prev_frame := (_frame_editor_frame - 1) % _frame_editor_frame_count
		if prev_frame < 0:
			prev_frame += _frame_editor_frame_count
		_frame_editor_onion_sprite.visible = show_onion and _frame_editor_frame_count > 1
		var onion_atlas := _frame_editor_onion_sprite.texture as AtlasTexture
		onion_atlas.region = Rect2(prev_frame * frame_size, 0, frame_size, frame_size)
	if _frame_editor_frame_label:
		_frame_editor_frame_label.text = "Frame %d / %d" % [_frame_editor_frame + 1, _frame_editor_frame_count]


func _on_frame_editor_direction_changed(dir_name: String) -> void:
	_frame_editor_direction = dir_name
	_setup_frame_editor()


func _delete_current_frame() -> void:
	if _frame_editor_frame_count <= 1:
		return  # Don't delete the last frame

	# Delete from ALL 3 directions simultaneously
	for dir_name in _captured_sheets.keys():
		var src: Image = _captured_sheets[dir_name]
		var src_w := src.get_width()
		var src_h := src.get_height()
		var frame_w := src_w / _frame_editor_frame_count
		if frame_w <= 0:
			continue
		# Create new image without the deleted frame
		var new_w := src_w - frame_w
		if new_w <= 0:
			continue
		var new_img := Image.create(new_w, src_h, false, src.get_format())
		# Copy frames before the deleted one
		var x_before := _frame_editor_frame * frame_w
		if x_before > 0:
			new_img.blit_rect(src, Rect2i(0, 0, x_before, src_h), Vector2i.ZERO)
		# Copy frames after the deleted one
		var x_after := (_frame_editor_frame + 1) * frame_w
		if x_after < src_w:
			new_img.blit_rect(src, Rect2i(x_after, 0, src_w - x_after, src_h), Vector2i(x_before, 0))
		_captured_sheets[dir_name] = new_img

	_frame_editor_frame_count -= 1
	_frame_editor_deleted_count += 1
	_frame_editor_frame = clampi(_frame_editor_frame, 0, _frame_editor_frame_count - 1)

	# Rebuild the preview
	_setup_frame_editor()


#===============================================================================
# EXPORT (Step 5)
#===============================================================================

func _start_export() -> void:
	next_button.visible = false
	back_button.disabled = true
	export_log_label.text = ""

	_export_frame_size = int(output_height_spin.value)
	var effect_id := effect_id_edit.text.strip_edges()
	if effect_id.is_empty():
		effect_id = "unnamed_effect"

	# Summary
	var fps: float = _frame_editor_fps_spin.value if _frame_editor_fps_spin else 15.0
	var frame_count := _frame_editor_frame_count
	if frame_count <= 0:
		# Compute from captured sheets if frame editor was never entered
		if _captured_sheets.has("down"):
			var sheet: Image = _captured_sheets["down"]
			var raw_frame_w := sheet.get_height()  # Square frames: height = frame side
			frame_count = sheet.get_width() / raw_frame_w if raw_frame_w > 0 else 0

	var duration_ms := int((float(frame_count) / fps) * 1000.0) if fps > 0 else 0
	_export_summary_label.text = "Effect: %s\nFrames: %d  |  Size: %dpx  |  FPS: %d  |  Duration: %dms" % [
		effect_id, frame_count, _export_frame_size, int(fps), duration_ms]

	var output_dir := "%s/%s" % [OUTPUT_BASE, effect_id]
	var global_output_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(global_output_dir)

	var count := 0
	for dir_name in _captured_sheets:
		_set_status("Processing %s..." % dir_name)
		var processed := _process_image(_captured_sheets[dir_name])

		var output_path := "%s/%s_%s.png" % [output_dir, effect_id, dir_name]
		var global_path := ProjectSettings.globalize_path(output_path)
		var err := processed.save_png(global_path)
		if err != OK:
			_append_log("ERROR: Failed to save %s" % output_path)
			continue
		_append_log("Saved: %s" % output_path)
		count += 1

	# Write metadata.json
	var metadata := {
		"effect_id": effect_id,
		"frame_count": frame_count,
		"frame_size": _export_frame_size,
		"duration_ms": duration_ms,
		"fps": fps,
		"anchor_offset": [0, 0],
		"processing": {
			"target_height": _export_frame_size,
			"alpha_threshold": int(alpha_threshold_slider.value),
			"dithering_enabled": dithering_toggle.button_pressed,
			"outline_enabled": outline_toggle.button_pressed,
			"denoising_enabled": denoising_toggle.button_pressed,
		}
	}

	var metadata_path := "%s/metadata.json" % output_dir
	var global_meta_path := ProjectSettings.globalize_path(metadata_path)
	var meta_file := FileAccess.open(global_meta_path, FileAccess.WRITE)
	if meta_file != null:
		meta_file.store_string(JSON.stringify(metadata, "\t"))
		meta_file.close()
		_append_log("Saved: %s" % metadata_path)
		count += 1
	else:
		_append_log("ERROR: Could not write metadata.json")

	_append_log("\nExported %d files to %s/" % [count, output_dir])
	_set_status("Export complete! %d files saved." % count)
	back_button.disabled = false


func _append_log(text: String) -> void:
	export_log_label.text += text + "\n"
	print("[EffectPipeline] %s" % text)


func _on_run_again_pressed() -> void:
	_captured_sheets.clear()
	_go_to_step(0)


func _on_done_pressed() -> void:
	_captured_sheets.clear()
	_clear_model()
	_go_to_step(0)
	_scan_models()


#===============================================================================
# UTILS
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


func _set_status(text: String) -> void:
	status_label.text = text
	if text.begins_with("ERROR") or text.begins_with("Failed"):
		status_label.add_theme_color_override("font_color", C_WARNING)
	elif text.begins_with("Done") or text.begins_with("Saved") or text.begins_with("Export"):
		status_label.add_theme_color_override("font_color", C_SUCCESS)
	else:
		status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	print("[EffectPipeline] %s" % text)


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

## Create a section container with a styled header label.
## Returns [section_container, content_vbox] — add controls to content_vbox.
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
