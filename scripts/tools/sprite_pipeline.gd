extends Control
## Sprite Pipeline Wizard
##
## Unified tool that chains 3D sprite capture and pixel art conversion
## into a single 7-step wizard flow with saveable presets.
##
## Steps:
##   1. Model & Animation — select model, pick animation, configure camera
##   2. Capture Preview — auto-capture all 3 directions, confirm
##   3. Pixel Art Settings — configure processing, preview result
##   4. Light Preview — interactive light/normal map preview
##   5. Export — process all directions, save final pixel art
##   6. Weapon Anchors — place grip/direction pixels on exported frames (optional)
##   7. Apply to SpriteFrames — load exported sheets into player_sprites.tres
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

## Overscan factor for detection pass — renders a wider view to find the full
## character extent, then re-renders at normal zoom with the camera panned
## to keep the character centered. Character size stays the same.
const CAPTURE_OVERSCAN := 1.5

## Known animation folder configs: folder name → {prefix, fps, loop}
## Folders not listed here auto-derive prefix from folder name lowercased.
const KNOWN_ANIM_CONFIG := {
	"Idle": {"prefix": "idle", "fps": 10, "loop": true},
	"Walking": {"prefix": "walk", "fps": 15, "loop": true},
	"Running": {"prefix": "run", "fps": 18, "loop": true},
	"Slash": {"prefix": "attack", "fps": 20, "loop": false},
}
const DEFAULT_APPLY_FPS := 15
const DEFAULT_APPLY_LOOP := false

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

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

#===============================================================================
# WIZARD STATE
#===============================================================================

var _current_step := 0  # 0-6
var _step_containers: Array[VBoxContainer] = []  # one per step

## Step 1 state
var current_model_path: String = ""
var current_model_instance: Node = null
var current_anim_player: AnimationPlayer = null
var available_models: Array[String] = []
var camera_target: Vector3 = Vector3.ZERO

## Step 2 state
var _captured_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
var _captured_normal_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
var _captured_shadow_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }

## Step 3 state
var _palette_colors: PackedColorArray = PackedColorArray()
var _preview_direction := "down"
var _capture_preview_mode := "color"  # "color" or "normal"
var _pixel_preview_mode := "color"  # "color", "normal", "lit"

## Step 4 (Light Preview) state
var _light_preview_viewport: SubViewport = null
var _light_preview_container: SubViewportContainer = null
var _light_preview_sprite: Sprite2D = null
var _light_preview_light: PointLight2D = null
var _light_preview_direction := "down"
var _light_preview_frame := 0
var _light_preview_frame_count := 0
var _light_preview_playing := false
var _light_preview_timer := 0.0

# Light Preview UI nodes
var _light_color_picker: ColorPickerButton = null
var _light_intensity_slider: HSlider = null
var _light_height_slider: HSlider = null
var _light_ambient_slider: HSlider = null
var _light_frame_label: Label = null
var _light_texture_cache: ImageTexture = null  # Cached soft circular light texture

## Step 5 state — actual frame size from export (used by Steps 5/6/7)
var _export_frame_size := FRAME_SIZE

## Step 5 (Anchor Editor) state
var _anchor_enabled := false
var _anchor_images: Dictionary = {}  # {"down": Image, "up": Image, "right": Image}
var _anchor_current_dir := "down"
var _anchor_current_frame := 0
var _anchor_frame_count := 0
var _anchor_tool := "grip"  # "grip", "direction", "erase"
var _anchor_undo_state: Dictionary = {}  # {dir_name: Image} — single-level undo snapshot

## Step 6 (Apply) state
var _apply_groups: Array = []  # Dynamically scanned from OUTPUT_BASE folders
var _exported_folder: String = ""  # Folder name from the most recent export

## Preset
var _current_preset: Dictionary = {}

## Normal map capture shader — loaded once at startup
var _normal_capture_shader: Shader = null
var _normal_capture_material: ShaderMaterial = null
var _shadow_capture_material: StandardMaterial3D = null

#===============================================================================
# NODE REFERENCES
#===============================================================================

# Step indicator
var step_indicator_label: Label
var step_indicator: Control  # StepIndicator custom control

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
var anchor_weapon_anim_toggle: CheckButton  # In export step — gates anchor editor

# Step 5 (Anchor Editor) nodes
var anchor_frame_label: Label
var anchor_info_label: Label
var anchor_log_label: Label
var anchor_frame_display: TextureRect  # In right panel, with gui_input connected
var anchor_grid_toggle: CheckButton
var _anchor_dir_buttons: Dictionary = {}  # {"down": Button, ...}
var _anchor_tool_buttons: Dictionary = {}  # {"grip": Button, ...}

# Step 6 nodes
var apply_log_label: Label
var apply_button: Button
var apply_summary_container: VBoxContainer

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
	# Load normal capture shader
	_normal_capture_shader = load("res://shaders/normal_capture.gdshader") as Shader
	if _normal_capture_shader:
		_normal_capture_material = ShaderMaterial.new()
		_normal_capture_material.shader = _normal_capture_shader
	# Create shadow capture material — flat black, unshaded
	_shadow_capture_material = StandardMaterial3D.new()
	_shadow_capture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_capture_material.albedo_color = Color.BLACK
	await get_tree().process_frame
	_scan_models()


func _process(delta: float) -> void:
	if _light_preview_playing and _current_step == 3:
		_light_preview_timer += delta
		var fps := 15.0
		if _light_preview_timer >= 1.0 / fps:
			_light_preview_timer -= 1.0 / fps
			_light_preview_frame = (_light_preview_frame + 1) % _light_preview_frame_count
			_update_light_preview_frame()


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

	# ── Left panel ──────────────────────────────────────────
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
	title.text = "Sprite Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Step indicator (fixed, custom draw)
	var StepIndicatorScript := load("res://scripts/tools/step_indicator.gd")
	step_indicator = StepIndicatorScript.new()
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 8)
	indicator_margin.add_theme_constant_override("margin_right", 8)
	indicator_margin.add_theme_constant_override("margin_bottom", 8)
	left_vbox.add_child(indicator_margin)
	indicator_margin.add_child(step_indicator)

	# Keep the old label reference working (hidden, updated by _go_to_step)
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

	# Build 7 step containers
	for i in range(7):
		var step_cont := VBoxContainer.new()
		step_cont.add_theme_constant_override("separation", 10)
		step_cont.visible = (i == 0)
		steps_vbox.add_child(step_cont)
		_step_containers.append(step_cont)

	# Build each step's contents
	_build_step1(_step_containers[0])
	_build_step2(_step_containers[1])
	_build_step3(_step_containers[2])
	_build_step_light_preview(_step_containers[3])
	_build_step4(_step_containers[4])
	_build_step_anchors(_step_containers[5])
	_build_step6(_step_containers[6])

	# ── Bottom bar (fixed, not scrolled) ───────────────────
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

	# ── Right side — preview areas ──────────────────────────
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

	# Anchor frame display (Step 5), initially hidden
	anchor_frame_display = TextureRect.new()
	anchor_frame_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anchor_frame_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anchor_frame_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	anchor_frame_display.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_frame_display.size_flags_vertical = SIZE_EXPAND_FILL
	anchor_frame_display.visible = false
	anchor_frame_display.gui_input.connect(_on_anchor_frame_input)
	right_vbox.add_child(anchor_frame_display)

	# Light preview viewport (Step 4), initially hidden
	_light_preview_container = SubViewportContainer.new()
	_light_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	_light_preview_container.stretch = true
	_light_preview_container.visible = false
	right_vbox.add_child(_light_preview_container)


#===============================================================================
# STEP 1 — MODEL & ANIMATION
#===============================================================================

func _build_step1(parent: VBoxContainer) -> void:
	# Model selector
	var sec := _make_section("Model & Animation")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	content.add_child(_make_field("3D Model", model_dropdown))

	anim_dropdown = OptionButton.new()
	anim_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	anim_dropdown.item_selected.connect(_on_animation_selected)
	content.add_child(_make_field("Animation", anim_dropdown))

	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 2
	frame_count_spin.max_value = 60
	frame_count_spin.value = 8
	frame_count_spin.step = 1
	content.add_child(_make_field("Frames per direction", frame_count_spin))

	# Preset status
	preset_status_label = Label.new()
	preset_status_label.text = "(no preset)"
	preset_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	preset_status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(preset_status_label)

	# Camera settings (collapsible)
	var cam := _make_collapsible("Camera Settings")
	parent.add_child(cam[0])
	camera_settings_container = cam[1]

	# Camera elevation
	var elev_data := _make_slider_row(10.0, 80.0, 30.0, 1.0)
	camera_elevation_slider = elev_data[1]
	camera_elevation_label = elev_data[2]
	camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	camera_settings_container.add_child(_make_field("Elevation (degrees)", elev_data[0]))

	# Camera zoom
	var zoom_data := _make_slider_row(0.5, 15.0, 3.0, 0.1)
	camera_zoom_slider = zoom_data[1]
	camera_zoom_label = zoom_data[2]
	camera_zoom_slider.value_changed.connect(_on_zoom_changed)
	camera_settings_container.add_child(_make_field("Zoom", zoom_data[0]))

	# Camera target height
	var target_data := _make_slider_row(0.0, 5.0, 1.0, 0.05)
	camera_target_y_slider = target_data[1]
	camera_target_y_label = target_data[2]
	camera_target_y_slider.value_changed.connect(_on_target_y_changed)
	camera_settings_container.add_child(_make_field("Target height", target_data[0]))

	# Direction preview buttons
	var dir_group := _make_toggle_group([
		{"label": "Front", "key": "front"},
		{"label": "Back", "key": "back"},
		{"label": "Side", "key": "side"},
	], func(key: String) -> void:
		var angles := {"front": 0.0, "back": 180.0, "side": 90.0}
		_on_preview_direction(angles[key])
	)
	camera_settings_container.add_child(_make_field("Preview direction", dir_group))

	# Save preset button
	var save_preset_btn := Button.new()
	save_preset_btn.text = "Save Camera Preset"
	save_preset_btn.pressed.connect(_save_preset)
	camera_settings_container.add_child(save_preset_btn)


#===============================================================================
# STEP 2 — CAPTURE PREVIEW
#===============================================================================

func _build_step2(parent: VBoxContainer) -> void:
	var sec := _make_section("Capture Preview")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Preview mode toggle
	var mode_group := _make_toggle_group([
		{"label": "Color", "key": "color"},
		{"label": "Normal", "key": "normal"},
		{"label": "Shadow", "key": "shadow"},
	], func(key: String) -> void:
		_capture_preview_mode = key
		_update_capture_preview()
	)
	content.add_child(mode_group)

	content.add_child(_make_small_label("Capturing 3 directions..."))

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
# STEP 3 — PIXEL ART SETTINGS
#===============================================================================

func _build_step3(parent: VBoxContainer) -> void:
	# Main settings section
	var sec := _make_section("Pixel Art Settings")
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

	# Preview mode toggle
	var mode_group := _make_toggle_group([
		{"label": "Color", "key": "color"},
		{"label": "Normal", "key": "normal"},
		{"label": "Lit", "key": "lit"},
	], func(key: String) -> void:
		_pixel_preview_mode = key
		_update_pixel_preview()
	)
	content.add_child(_make_field("Preview mode", mode_group))

	# Output height
	output_height_spin = SpinBox.new()
	output_height_spin.min_value = 16
	output_height_spin.max_value = 256
	output_height_spin.value = 64
	output_height_spin.step = 8
	output_height_spin.value_changed.connect(_on_pixel_setting_changed)
	content.add_child(_make_field("Output height (px)", output_height_spin))

	# Alpha threshold
	var alpha_data := _make_slider_row(0, 255, 128, 1)
	alpha_threshold_slider = alpha_data[1]
	alpha_threshold_label = alpha_data[2]
	alpha_threshold_slider.value_changed.connect(_on_alpha_threshold_changed)
	content.add_child(_make_field("Alpha threshold", alpha_data[0]))

	# Palette section
	var palette_sec := _make_section("Palette")
	parent.add_child(palette_sec[0])
	var palette_content: VBoxContainer = palette_sec[1]

	palette_mode_dropdown = OptionButton.new()
	palette_mode_dropdown.add_item("None")
	palette_mode_dropdown.add_item("Load from Palettes")
	palette_mode_dropdown.add_item("Generate from Captures")
	palette_mode_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_mode_dropdown.item_selected.connect(_on_palette_mode_changed)
	palette_content.add_child(_make_field("Mode", palette_mode_dropdown))

	palette_file_dropdown = OptionButton.new()
	palette_file_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_file_dropdown.visible = false
	palette_file_dropdown.item_selected.connect(_on_palette_file_selected)
	palette_content.add_child(palette_file_dropdown)

	max_palette_colors_spin = SpinBox.new()
	max_palette_colors_spin.min_value = 4
	max_palette_colors_spin.max_value = 128
	max_palette_colors_spin.value = 32
	max_palette_colors_spin.step = 4
	max_palette_colors_spin.visible = false
	palette_content.add_child(_make_field("Max colors", max_palette_colors_spin))

	generate_palette_button = Button.new()
	generate_palette_button.text = "Generate Palette"
	generate_palette_button.visible = false
	generate_palette_button.pressed.connect(_on_generate_palette_pressed)
	palette_content.add_child(generate_palette_button)

	palette_preview_container = HFlowContainer.new()
	palette_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_content.add_child(palette_preview_container)

	# Dithering (collapsible)
	var dither := _make_collapsible("Dithering")
	parent.add_child(dither[0])
	var dither_content: VBoxContainer = dither[1]

	dithering_toggle = CheckButton.new()
	dithering_toggle.text = "Enable"
	dithering_toggle.toggled.connect(_on_pixel_toggle_changed)
	dither_content.add_child(dithering_toggle)

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

	# Outline (collapsible)
	var outline := _make_collapsible("Outline")
	parent.add_child(outline[0])
	var outline_content: VBoxContainer = outline[1]

	outline_toggle = CheckButton.new()
	outline_toggle.text = "Enable"
	outline_toggle.toggled.connect(_on_pixel_toggle_changed)
	outline_content.add_child(outline_toggle)

	var outline_color_hbox := HBoxContainer.new()
	outline_color_hbox.add_theme_constant_override("separation", 8)
	outline_content.add_child(outline_color_hbox)
	outline_color_hbox.add_child(_make_label("Color:"))
	outline_color_picker = ColorPickerButton.new()
	outline_color_picker.color = Color.BLACK
	outline_color_picker.custom_minimum_size = Vector2(40, 30)
	outline_color_picker.color_changed.connect(_on_pixel_color_changed)
	outline_color_hbox.add_child(outline_color_picker)

	# Denoising (collapsible)
	var denoise := _make_collapsible("Denoising")
	parent.add_child(denoise[0])
	var denoise_content: VBoxContainer = denoise[1]

	denoising_toggle = CheckButton.new()
	denoising_toggle.text = "Enable"
	denoising_toggle.toggled.connect(_on_pixel_toggle_changed)
	denoise_content.add_child(denoising_toggle)

	denoising_min_cluster_spin = SpinBox.new()
	denoising_min_cluster_spin.min_value = 1
	denoising_min_cluster_spin.max_value = 50
	denoising_min_cluster_spin.value = 4
	denoising_min_cluster_spin.step = 1
	denoising_min_cluster_spin.value_changed.connect(_on_pixel_setting_changed)
	denoise_content.add_child(_make_field("Min cluster size", denoising_min_cluster_spin))

	# Bottom actions
	var actions_sec := _make_section("Actions")
	parent.add_child(actions_sec[0])
	var actions_content: VBoxContainer = actions_sec[1]

	var save_settings_btn := Button.new()
	save_settings_btn.text = "Save Settings to Preset"
	save_settings_btn.pressed.connect(_save_pixel_art_preset)
	actions_content.add_child(save_settings_btn)

	show_original_toggle = CheckButton.new()
	show_original_toggle.text = "Show Original"
	show_original_toggle.toggled.connect(_on_pixel_toggle_changed)
	actions_content.add_child(show_original_toggle)


#===============================================================================
# STEP 3b — LIGHT PREVIEW
#===============================================================================

func _build_step_light_preview(parent: VBoxContainer) -> void:
	var sec := _make_section("Light Preview")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label("Drag the light around to test normal maps."))

	# Direction buttons
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_on_light_preview_direction(key)
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
		_light_preview_frame = max(0, _light_preview_frame - 1)
		_update_light_preview_frame()
	)
	frame_hbox.add_child(prev_btn)
	_light_frame_label = Label.new()
	_light_frame_label.text = "Frame 1 / 1"
	_light_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_light_frame_label.size_flags_horizontal = SIZE_EXPAND_FILL
	frame_hbox.add_child(_light_frame_label)
	var next_frame_btn := Button.new()
	next_frame_btn.text = "\u25b6"
	next_frame_btn.custom_minimum_size.x = 32
	next_frame_btn.pressed.connect(func() -> void:
		_light_preview_frame = min(_light_preview_frame_count - 1, _light_preview_frame + 1)
		_update_light_preview_frame()
	)
	frame_hbox.add_child(next_frame_btn)
	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func() -> void:
		_light_preview_playing = not _light_preview_playing
		play_btn.text = "Stop" if _light_preview_playing else "Play"
	)
	frame_hbox.add_child(play_btn)

	# Light controls section
	var light_sec := _make_section("Light Settings")
	parent.add_child(light_sec[0])
	var light_content: VBoxContainer = light_sec[1]

	# Light color
	var color_hbox := HBoxContainer.new()
	color_hbox.add_theme_constant_override("separation", 8)
	light_content.add_child(color_hbox)
	color_hbox.add_child(_make_label("Color:"))
	_light_color_picker = ColorPickerButton.new()
	_light_color_picker.color = Color("#FFAA44")
	_light_color_picker.custom_minimum_size = Vector2(60, 30)
	_light_color_picker.color_changed.connect(func(c: Color) -> void:
		if _light_preview_light:
			_light_preview_light.color = c
	)
	color_hbox.add_child(_light_color_picker)

	# Intensity slider
	var int_data := _make_slider_row(0.0, 3.0, 1.5, 0.1)
	_light_intensity_slider = int_data[1]
	_light_intensity_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.energy = v
	)
	light_content.add_child(_make_field("Intensity", int_data[0]))

	# Height slider
	var height_data := _make_slider_row(0.0, 200.0, 50.0, 5.0)
	_light_height_slider = height_data[1]
	_light_height_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.height = v
	)
	light_content.add_child(_make_field("Height", height_data[0]))

	# Ambient slider
	var amb_data := _make_slider_row(0.0, 1.0, 0.2, 0.05)
	_light_ambient_slider = amb_data[1]
	_light_ambient_slider.value_changed.connect(func(_v: float) -> void:
		_update_light_preview_ambient()
	)
	light_content.add_child(_make_field("Ambient", amb_data[0]))

	# Presets
	var preset_group := _make_toggle_group([
		{"label": "Torch", "key": "torch"},
		{"label": "Sun", "key": "sunlight"},
		{"label": "Moon", "key": "moonlight"},
		{"label": "Spell", "key": "spell"},
	], func(key: String) -> void:
		var presets := {
			"torch": {"color": Color("#FFAA44"), "intensity": 1.5, "height": 50.0, "ambient": 0.2},
			"sunlight": {"color": Color("#FFFDE0"), "intensity": 1.0, "height": 150.0, "ambient": 0.4},
			"moonlight": {"color": Color("#8899CC"), "intensity": 0.8, "height": 120.0, "ambient": 0.15},
			"spell": {"color": Color("#44FFDD"), "intensity": 2.0, "height": 30.0, "ambient": 0.1},
		}
		_apply_light_preset(presets[key])
	)
	light_content.add_child(_make_field("Presets", preset_group))


#===============================================================================
# LIGHT PREVIEW LOGIC
#===============================================================================

func _setup_light_preview() -> void:
	if _light_preview_viewport:
		_light_preview_viewport.queue_free()

	_light_preview_viewport = SubViewport.new()
	_light_preview_viewport.transparent_bg = false
	_light_preview_viewport.size = Vector2i(400, 400)
	_light_preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_light_preview_container.add_child(_light_preview_viewport)

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.size = Vector2(400, 400)
	_light_preview_viewport.add_child(bg)

	# Process color and normal for current direction
	if not _captured_sheets.has(_light_preview_direction):
		_light_preview_direction = "down"
	if not _captured_sheets.has(_light_preview_direction):
		return

	var color_processed := _process_image(_captured_sheets[_light_preview_direction])
	var normal_processed: Image = null
	if _captured_normal_sheets.has(_light_preview_direction):
		normal_processed = PixelArtProcessing.process_normal_map(
			_captured_normal_sheets[_light_preview_direction],
			int(output_height_spin.value),
			int(alpha_threshold_slider.value)
		)

	# Create CanvasTexture pairing diffuse + normal
	var color_tex := ImageTexture.create_from_image(color_processed)
	var canvas_tex := CanvasTexture.new()
	canvas_tex.diffuse_texture = color_tex
	if normal_processed:
		var normal_tex := ImageTexture.create_from_image(normal_processed)
		canvas_tex.normal_texture = normal_tex

	# Calculate frame info
	_light_preview_frame_count = color_processed.get_width() / maxi(int(output_height_spin.value), 1)
	if _light_preview_frame_count < 1:
		_light_preview_frame_count = 1
	_light_preview_frame = 0

	# Create sprite showing single frame via AtlasTexture
	var frame_size := int(output_height_spin.value)
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = canvas_tex
	atlas_tex.region = Rect2(0, 0, frame_size, frame_size)

	_light_preview_sprite = Sprite2D.new()
	_light_preview_sprite.texture = atlas_tex
	_light_preview_sprite.position = Vector2(200, 200)
	_light_preview_sprite.scale = Vector2(3, 3)
	_light_preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_light_preview_viewport.add_child(_light_preview_sprite)

	# Create point light with soft circular texture
	_light_preview_light = PointLight2D.new()
	_light_preview_light.position = Vector2(250, 150)
	_light_preview_light.color = _light_color_picker.color
	_light_preview_light.energy = _light_intensity_slider.value
	_light_preview_light.height = _light_height_slider.value
	# Use cached light texture (generated once, reused across direction changes)
	if _light_texture_cache == null:
		var light_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var dx := (x - 64.0) / 64.0
				var dy := (y - 64.0) / 64.0
				var dist := sqrt(dx * dx + dy * dy)
				var alpha := clampf(1.0 - dist, 0.0, 1.0)
				light_img.set_pixel(x, y, Color(1, 1, 1, alpha))
		_light_texture_cache = ImageTexture.create_from_image(light_img)
	_light_preview_light.texture = _light_texture_cache
	_light_preview_light.texture_scale = 4.0
	_light_preview_viewport.add_child(_light_preview_light)

	_update_light_preview_ambient()
	_update_light_preview_frame()

	if not _light_preview_container.gui_input.is_connected(_on_light_preview_input):
		_light_preview_container.gui_input.connect(_on_light_preview_input)


func _on_light_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _light_preview_light and _light_preview_container:
			var local_pos: Vector2 = (event as InputEventMouseMotion).position
			var container_size := _light_preview_container.size
			var viewport_size := Vector2(_light_preview_viewport.size)
			_light_preview_light.position = Vector2(
				(local_pos.x / container_size.x) * viewport_size.x,
				(local_pos.y / container_size.y) * viewport_size.y
			)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _light_preview_light and _light_preview_container:
			var local_pos: Vector2 = (event as InputEventMouseButton).position
			var container_size := _light_preview_container.size
			var viewport_size := Vector2(_light_preview_viewport.size)
			_light_preview_light.position = Vector2(
				(local_pos.x / container_size.x) * viewport_size.x,
				(local_pos.y / container_size.y) * viewport_size.y
			)


func _on_light_preview_direction(dir_name: String) -> void:
	_light_preview_direction = dir_name
	_setup_light_preview()


func _update_light_preview_frame() -> void:
	if _light_preview_sprite and _light_preview_sprite.texture is AtlasTexture:
		var atlas := _light_preview_sprite.texture as AtlasTexture
		var frame_size := int(output_height_spin.value)
		atlas.region = Rect2(_light_preview_frame * frame_size, 0, frame_size, frame_size)
	if _light_frame_label:
		_light_frame_label.text = "Frame %d / %d" % [_light_preview_frame + 1, _light_preview_frame_count]


func _update_light_preview_ambient() -> void:
	if _light_preview_sprite:
		var ambient := _light_ambient_slider.value
		_light_preview_sprite.self_modulate = Color(ambient, ambient, ambient, 1.0)


func _apply_light_preset(preset: Dictionary) -> void:
	_light_color_picker.color = preset["color"]
	_light_intensity_slider.value = preset["intensity"]
	_light_height_slider.value = preset["height"]
	_light_ambient_slider.value = preset["ambient"]
	if _light_preview_light:
		_light_preview_light.color = preset["color"]
		_light_preview_light.energy = preset["intensity"]
		_light_preview_light.height = preset["height"]
	_update_light_preview_ambient()


#===============================================================================
# STEP 4 — EXPORT
#===============================================================================

func _build_step4(parent: VBoxContainer) -> void:
	var sec := _make_section("Export")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	export_log_label = Label.new()
	export_log_label.text = ""
	export_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	export_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	export_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(export_log_label)

	anchor_weapon_anim_toggle = CheckButton.new()
	anchor_weapon_anim_toggle.text = "Weapon Animation (edit anchors next)"
	content.add_child(anchor_weapon_anim_toggle)

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	content.add_child(run_again_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(_on_done_pressed)
	content.add_child(done_btn)


#===============================================================================
# STEP 5 — WEAPON ANCHOR EDITOR (index 5)
#===============================================================================

func _build_step_anchors(parent: VBoxContainer) -> void:
	# Navigation section
	var nav_sec := _make_section("Weapon Anchor Editor")
	parent.add_child(nav_sec[0])
	var nav_content: VBoxContainer = nav_sec[1]

	# Direction selector
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_on_anchor_dir_selected(key)
	)
	nav_content.add_child(_make_field("Direction", dir_group))

	# Frame navigator
	var frame_hbox := HBoxContainer.new()
	frame_hbox.add_theme_constant_override("separation", 4)
	nav_content.add_child(frame_hbox)

	var prev_btn := Button.new()
	prev_btn.text = "\u25c0"
	prev_btn.custom_minimum_size.x = 32
	prev_btn.pressed.connect(func() -> void:
		if _anchor_current_frame > 0:
			_anchor_current_frame -= 1
			_update_anchor_display()
	)
	frame_hbox.add_child(prev_btn)

	anchor_frame_label = Label.new()
	anchor_frame_label.text = "1 / 1"
	anchor_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anchor_frame_label.size_flags_horizontal = SIZE_EXPAND_FILL
	frame_hbox.add_child(anchor_frame_label)

	var next_frame_btn := Button.new()
	next_frame_btn.text = "\u25b6"
	next_frame_btn.custom_minimum_size.x = 32
	next_frame_btn.pressed.connect(func() -> void:
		if _anchor_current_frame < _anchor_frame_count - 1:
			_anchor_current_frame += 1
			_update_anchor_display()
	)
	frame_hbox.add_child(next_frame_btn)

	# Tool selector section
	var tool_sec := _make_section("Tool")
	parent.add_child(tool_sec[0])
	var tool_content: VBoxContainer = tool_sec[1]

	var tool_group := _make_toggle_group([
		{"label": "Grip", "key": "grip"},
		{"label": "Direction", "key": "direction"},
		{"label": "Erase", "key": "erase"},
	], func(key: String) -> void:
		_on_anchor_tool_selected(key)
	)
	tool_content.add_child(tool_group)

	# Color legend
	var legend_hbox := HBoxContainer.new()
	legend_hbox.add_theme_constant_override("separation", 12)
	tool_content.add_child(legend_hbox)
	var grip_legend := Label.new()
	grip_legend.text = "\u25a0 Grip"
	grip_legend.add_theme_color_override("font_color", Color("#FF00AA"))
	grip_legend.add_theme_font_size_override("font_size", FONT_HINT)
	legend_hbox.add_child(grip_legend)
	var dir_legend := Label.new()
	dir_legend.text = "\u25a0 Direction"
	dir_legend.add_theme_color_override("font_color", Color("#00FFFF"))
	dir_legend.add_theme_font_size_override("font_size", FONT_HINT)
	legend_hbox.add_child(dir_legend)

	# Anchor info
	anchor_info_label = Label.new()
	anchor_info_label.text = "Grip: \u2014\nDirection: \u2014\nWeapon dir: \u2014"
	anchor_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anchor_info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_info_label.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_info_label.add_theme_color_override("font_color", C_TEXT_SEC)
	tool_content.add_child(anchor_info_label)

	# Actions section
	var act_sec := _make_section("Actions")
	parent.add_child(act_sec[0])
	var act_content: VBoxContainer = act_sec[1]

	anchor_grid_toggle = CheckButton.new()
	anchor_grid_toggle.text = "Show Grid"
	anchor_grid_toggle.toggled.connect(func(_on: bool) -> void: _update_anchor_display())
	act_content.add_child(anchor_grid_toggle)

	var copy_btn := Button.new()
	copy_btn.text = "Copy to All Frames"
	copy_btn.pressed.connect(_on_anchor_copy_to_all)
	act_content.add_child(copy_btn)

	var undo_btn := Button.new()
	undo_btn.text = "Undo Last Placement"
	undo_btn.pressed.connect(_on_anchor_undo)
	act_content.add_child(undo_btn)

	var save_btn := _make_primary_button("Save Anchor Changes")
	save_btn.pressed.connect(_on_anchor_save)
	act_content.add_child(save_btn)

	# Log
	anchor_log_label = Label.new()
	anchor_log_label.text = ""
	anchor_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anchor_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	act_content.add_child(anchor_log_label)


func _on_anchor_dir_selected(dir_name: String) -> void:
	_anchor_current_dir = dir_name
	_anchor_current_frame = 0
	if _anchor_images.has(dir_name):
		_anchor_frame_count = _anchor_images[dir_name].get_width() / _export_frame_size
	else:
		_anchor_frame_count = 0
	_update_anchor_display()


func _on_anchor_tool_selected(tool_name: String) -> void:
	_anchor_tool = tool_name
	_update_anchor_button_highlights()


func _update_anchor_button_highlights() -> void:
	# Toggle group handles highlighting automatically
	pass


func _enter_anchor_editor() -> void:
	_anchor_images.clear()
	_anchor_undo_state.clear()
	_anchor_current_dir = "down"
	_anchor_current_frame = 0
	_anchor_frame_count = 0
	anchor_log_label.text = ""

	var model_name := current_model_path.get_file().get_basename()
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var safe_anim_name := anim_name.replace(" ", "_").replace("/", "_").to_lower()

	for dir_info in DIRECTIONS:
		var dir_name: String = dir_info["name"]
		var file_path := "%s/%s/%s_%s.png" % [OUTPUT_BASE, model_name, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		var img := Image.load_from_file(global_path)
		if img:
			_anchor_images[dir_name] = img
			_append_anchor_log("Loaded: %s" % file_path)
		else:
			_append_anchor_log("WARNING: Could not load %s" % file_path)

	if _anchor_images.has("down"):
		_anchor_frame_count = _anchor_images["down"].get_width() / _export_frame_size
	elif not _anchor_images.is_empty():
		var first_key: String = _anchor_images.keys()[0]
		_anchor_current_dir = first_key
		_anchor_frame_count = _anchor_images[first_key].get_width() / _export_frame_size

	_append_anchor_log("Frames per direction: %d" % _anchor_frame_count)
	_append_anchor_log("Note: Re-exporting will overwrite anchor changes.")
	_update_anchor_display()


func _update_anchor_display() -> void:
	_update_anchor_button_highlights()

	if not _anchor_images.has(_anchor_current_dir) or _anchor_frame_count == 0:
		anchor_frame_label.text = "0 / 0"
		anchor_info_label.text = "Grip: —\nDirection: —\nWeapon dir: —"
		anchor_frame_display.texture = null
		return

	anchor_frame_label.text = "%d / %d" % [_anchor_current_frame + 1, _anchor_frame_count]

	var sheet: Image = _anchor_images[_anchor_current_dir]
	var region := Rect2i(_anchor_current_frame * _export_frame_size, 0, _export_frame_size, _export_frame_size)
	var frame_img := sheet.get_region(region)

	# Scan for existing anchor pixels
	var grip_pos := Vector2(-1, -1)
	var dir_pos := Vector2(-1, -1)
	var grip_color := Color("#FF00AA")
	var dir_color := Color("#00FFFF")
	for y in range(frame_img.get_height()):
		for x in range(frame_img.get_width()):
			var pixel := frame_img.get_pixel(x, y)
			if pixel.is_equal_approx(grip_color):
				grip_pos = Vector2(x, y)
			elif pixel.is_equal_approx(dir_color):
				dir_pos = Vector2(x, y)

	# Update info label
	var grip_text := "(%d, %d)" % [int(grip_pos.x), int(grip_pos.y)] if grip_pos.x >= 0 else "—"
	var dir_text := "(%d, %d)" % [int(dir_pos.x), int(dir_pos.y)] if dir_pos.x >= 0 else "—"
	var weapon_dir_text := "—"
	if grip_pos.x >= 0 and dir_pos.x >= 0:
		var angle_deg := rad_to_deg(atan2(dir_pos.y - grip_pos.y, dir_pos.x - grip_pos.x))
		if angle_deg >= 30.0 and angle_deg <= 150.0:
			weapon_dir_text = "down (%.0f°)" % angle_deg
		elif angle_deg >= -150.0 and angle_deg <= -30.0:
			weapon_dir_text = "up (%.0f°)" % angle_deg
		else:
			weapon_dir_text = "right (%.0f°)" % angle_deg
	elif grip_pos.x >= 0:
		weapon_dir_text = "(position heuristic)"
	anchor_info_label.text = "Grip: %s\nDirection: %s\nWeapon dir: %s" % [grip_text, dir_text, weapon_dir_text]

	# Create display image (scaled up for visibility)
	var display := frame_img.duplicate() as Image

	# Draw grid overlay if enabled
	if anchor_grid_toggle.button_pressed:
		var grid_color := Color(1.0, 1.0, 1.0, 0.15)
		for x in range(0, _export_frame_size, 8):
			for y in range(_export_frame_size):
				display.set_pixel(x, y, display.get_pixel(x, y).blend(grid_color))
		for y in range(0, _export_frame_size, 8):
			for x in range(_export_frame_size):
				display.set_pixel(x, y, display.get_pixel(x, y).blend(grid_color))

	# Draw crosshair markers around anchor pixels for visibility
	if grip_pos.x >= 0:
		_draw_crosshair(display, int(grip_pos.x), int(grip_pos.y), grip_color)
	if dir_pos.x >= 0:
		_draw_crosshair(display, int(dir_pos.x), int(dir_pos.y), dir_color)

	var tex := ImageTexture.create_from_image(display)
	anchor_frame_display.texture = tex


func _draw_crosshair(img: Image, cx: int, cy: int, color: Color) -> void:
	## Draw a small crosshair around the given pixel for visibility.
	var offsets: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(2, 0),
					Vector2i(0, -2), Vector2i(0, -1), Vector2i(0, 1), Vector2i(0, 2)]
	for ofs in offsets:
		var px: int = cx + ofs.x
		var py: int = cy + ofs.y
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, color)


func _on_anchor_frame_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if not _anchor_images.has(_anchor_current_dir) or _anchor_frame_count == 0:
		return

	# Convert click position to pixel coordinates
	# anchor_frame_display uses STRETCH_KEEP_ASPECT_CENTERED
	var display_size := anchor_frame_display.size
	var tex := anchor_frame_display.texture
	if tex == null:
		return

	var tex_size := tex.get_size()
	var tex_aspect := tex_size.x / tex_size.y
	var display_aspect := display_size.x / display_size.y

	var drawn_w: float
	var drawn_h: float
	var offset_x: float
	var offset_y: float

	if tex_aspect > display_aspect:
		# Texture wider than display — letterboxed vertically
		drawn_w = display_size.x
		drawn_h = display_size.x / tex_aspect
		offset_x = 0.0
		offset_y = (display_size.y - drawn_h) / 2.0
	else:
		# Texture taller — pillarboxed horizontally
		drawn_h = display_size.y
		drawn_w = display_size.y * tex_aspect
		offset_x = (display_size.x - drawn_w) / 2.0
		offset_y = 0.0

	var click := mb.position
	var rel_x := (click.x - offset_x) / drawn_w
	var rel_y := (click.y - offset_y) / drawn_h

	if rel_x < 0.0 or rel_x > 1.0 or rel_y < 0.0 or rel_y > 1.0:
		return

	var pixel_x := int(rel_x * _export_frame_size)
	var pixel_y := int(rel_y * _export_frame_size)
	pixel_x = clampi(pixel_x, 0, _export_frame_size - 1)
	pixel_y = clampi(pixel_y, 0, _export_frame_size - 1)

	_place_anchor_pixel(pixel_x, pixel_y)


func _place_anchor_pixel(x: int, y: int) -> void:
	if not _anchor_images.has(_anchor_current_dir):
		return
	# Save undo snapshot before modifying
	_anchor_undo_state[_anchor_current_dir] = (_anchor_images[_anchor_current_dir] as Image).duplicate()
	var sheet: Image = _anchor_images[_anchor_current_dir]
	var grip_color := Color("#FF00AA")
	var dir_color := Color("#00FFFF")

	match _anchor_tool:
		"grip":
			_clear_color_from_frame(sheet, _anchor_current_frame, grip_color)
			sheet.set_pixel(_anchor_current_frame * _export_frame_size + x, y, grip_color)
		"direction":
			_clear_color_from_frame(sheet, _anchor_current_frame, dir_color)
			sheet.set_pixel(_anchor_current_frame * _export_frame_size + x, y, dir_color)
		"erase":
			var pixel := sheet.get_pixel(_anchor_current_frame * _export_frame_size + x, y)
			if pixel.is_equal_approx(grip_color) or pixel.is_equal_approx(dir_color):
				sheet.set_pixel(_anchor_current_frame * _export_frame_size + x, y, Color.TRANSPARENT)

	_update_anchor_display()


func _clear_color_from_frame(sheet: Image, frame_idx: int, color: Color) -> void:
	var start_x := frame_idx * _export_frame_size
	for y in range(_export_frame_size):
		for x in range(start_x, start_x + _export_frame_size):
			if sheet.get_pixel(x, y).is_equal_approx(color):
				sheet.set_pixel(x, y, Color.TRANSPARENT)


func _on_anchor_copy_to_all() -> void:
	if not _anchor_images.has(_anchor_current_dir) or _anchor_frame_count == 0:
		return
	# Save undo snapshot before copy-to-all
	_anchor_undo_state[_anchor_current_dir] = (_anchor_images[_anchor_current_dir] as Image).duplicate()
	var sheet: Image = _anchor_images[_anchor_current_dir]
	var grip_color := Color("#FF00AA")
	var dir_color := Color("#00FFFF")

	# Find anchor positions in current frame
	var grip_pos := Vector2i(-1, -1)
	var dir_pos := Vector2i(-1, -1)
	var start_x := _anchor_current_frame * _export_frame_size
	for y in range(_export_frame_size):
		for x in range(start_x, start_x + _export_frame_size):
			var pixel := sheet.get_pixel(x, y)
			if pixel.is_equal_approx(grip_color):
				grip_pos = Vector2i(x - start_x, y)
			elif pixel.is_equal_approx(dir_color):
				dir_pos = Vector2i(x - start_x, y)

	# Apply to all other frames
	for i in range(_anchor_frame_count):
		if i == _anchor_current_frame:
			continue
		_clear_color_from_frame(sheet, i, grip_color)
		_clear_color_from_frame(sheet, i, dir_color)
		if grip_pos.x >= 0:
			sheet.set_pixel(i * _export_frame_size + grip_pos.x, grip_pos.y, grip_color)
		if dir_pos.x >= 0:
			sheet.set_pixel(i * _export_frame_size + dir_pos.x, dir_pos.y, dir_color)

	_append_anchor_log("Copied anchors to all %d frames (%s)" % [_anchor_frame_count, _anchor_current_dir])
	_update_anchor_display()


func _on_anchor_save() -> void:
	if _anchor_images.is_empty():
		_append_anchor_log("Nothing to save.")
		return

	var model_name := current_model_path.get_file().get_basename()
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var safe_anim_name := anim_name.replace(" ", "_").replace("/", "_").to_lower()
	var saved := 0

	for dir_name in _anchor_images:
		var file_path := "%s/%s/%s_%s.png" % [OUTPUT_BASE, model_name, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		var err := (_anchor_images[dir_name] as Image).save_png(global_path)
		if err == OK:
			_append_anchor_log("Saved: %s" % file_path)
			saved += 1
		else:
			_append_anchor_log("ERROR: Failed to save %s" % file_path)

	_append_anchor_log("Saved %d/%d direction sheets." % [saved, _anchor_images.size()])


func _on_anchor_undo() -> void:
	if not _anchor_undo_state.has(_anchor_current_dir):
		_append_anchor_log("Nothing to undo for %s." % _anchor_current_dir)
		return
	_anchor_images[_anchor_current_dir] = _anchor_undo_state[_anchor_current_dir]
	_anchor_undo_state.erase(_anchor_current_dir)
	_anchor_frame_count = _anchor_images[_anchor_current_dir].get_width() / _export_frame_size
	_append_anchor_log("Undid last change to %s." % _anchor_current_dir)
	_update_anchor_display()


func _append_anchor_log(text: String) -> void:
	anchor_log_label.text += text + "\n"
	print("[SpritePipeline:Anchors] %s" % text)


#===============================================================================
# STEP 6 — APPLY TO SPRITEFRAMES (index 6)
#===============================================================================

func _build_step6(parent: VBoxContainer) -> void:
	var sec := _make_section("Apply to SpriteFrames")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	var path_label := Label.new()
	path_label.text = "Target: %s" % SPRITEFRAMES_PATH
	path_label.add_theme_font_size_override("font_size", FONT_HINT)
	path_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(path_label)

	# Dynamic summary
	content.add_child(_make_label("Animations to apply:"))
	apply_summary_container = VBoxContainer.new()
	apply_summary_container.add_theme_constant_override("separation", 2)
	content.add_child(apply_summary_container)

	apply_button = _make_primary_button("Apply to SpriteFrames")
	apply_button.pressed.connect(_apply_to_spriteframes)
	content.add_child(apply_button)

	apply_log_label = Label.new()
	apply_log_label.text = ""
	apply_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	apply_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	apply_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(apply_log_label)

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
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
	next_button.visible = (step < 6)
	next_button.text = "Export  \u25b6" if step == 4 else "Next  \u25b6"
	# Style Next button for Export step
	if step == 4:
		# Export step — style Next/Export button as warning
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
		# Reset to primary accent style
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
	var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Settings",
		"Light Preview", "Export", "Weapon Anchors", "Apply to SpriteFrames"]
	step_indicator_label.text = "Step %d of 7: %s" % [step + 1, step_names[step]]
	if step_indicator:
		step_indicator.set_step(step)
	# Update preview visibility
	var viewport_area := preview_container.get_parent()  # AspectRatioContainer
	viewport_area.visible = (step <= 1)
	pixel_preview_rect.get_parent().visible = (step == 2)
	if anchor_frame_display:
		anchor_frame_display.visible = (step == 5)
	if _light_preview_container:
		_light_preview_container.visible = (step == 3)
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
			_setup_light_preview()
		4:
			_start_export()
		5:
			_enter_anchor_editor()
		6:
			_scan_export_folders()


func _on_next_pressed() -> void:
	if _current_step == 4:
		# After export: check if anchor editor is enabled
		if anchor_weapon_anim_toggle and anchor_weapon_anim_toggle.button_pressed:
			_anchor_enabled = true
			_go_to_step(5)  # Weapon Anchors
		else:
			_anchor_enabled = false
			_go_to_step(6)  # Skip to Apply
	elif _current_step < 6:
		_go_to_step(_current_step + 1)


func _on_back_pressed() -> void:
	if _current_step == 6 and not _anchor_enabled:
		_go_to_step(4)  # Anchors were skipped — go back to export
	elif _current_step > 0:
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


var _saved_unlit_materials: Array[Dictionary] = []  # [{mesh_instance, surface_idx, material}]


func _save_current_materials(node: Node) -> void:
	## Save all current surface override materials so they can be restored
	## after the normal capture pass (since _apply_unlit_materials reads
	## the current material to derive properties, it can't restore after
	## a ShaderMaterial override).
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
# CAMERA
#===============================================================================

func _position_camera(elevation_deg: float) -> void:
	var elevation_rad := deg_to_rad(elevation_deg)
	var distance := maxf(camera.size * 2.0, 5.0)
	var offset_y := sin(elevation_rad) * distance
	var offset_z := cos(elevation_rad) * distance
	camera.position = camera_target + Vector3(0.0, offset_y, offset_z)
	camera.look_at(camera_target, Vector3.UP)


func _create_shadow_camera() -> Camera3D:
	## Create a temporary top-down orthographic camera for shadow capture.
	var shadow_cam := Camera3D.new()
	shadow_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	shadow_cam.size = camera.size  # Match main camera's view width
	shadow_cam.position = camera_target + Vector3(0.0, 10.0, 0.0)  # High above
	shadow_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # Look straight down
	return shadow_cam


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
	_captured_normal_sheets.clear()
	_captured_shadow_sheets.clear()
	next_button.disabled = true
	back_button.disabled = true
	await _capture_animation()
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

		var normal_sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		normal_sheet.fill(Color(0.5, 0.5, 1.0, 0.0))  # Neutral normal, transparent

		var shadow_sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		shadow_sheet.fill(Color.TRANSPARENT)

		for frame_idx in range(frame_count):
			var seek_time: float
			if frame_count == 1:
				seek_time = 0.0
			else:
				seek_time = (float(frame_idx) / float(frame_count)) * anim_length
			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)

			# --- Detection pass: wide-angle render to find character extent ---
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

			# --- Final pass: normal zoom with camera panned to center character ---
			sub_viewport.size = Vector2i(output_size, output_size)
			camera.size = original_cam_size
			camera_target = original_cam_target + cam_shift
			_position_camera(camera_elevation_slider.value)

			# Re-seek the animation to the same time (detection pass may have advanced it)
			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var frame_image := sub_viewport.get_texture().get_image()
			frame_image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(frame_image, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

			# --- Normal map pass: same camera position, normal capture materials ---
			if _normal_capture_material:
				_save_current_materials(current_model_instance)
				_apply_normal_capture_materials(current_model_instance)
				# Re-seek animation (material swap may have caused a frame advance)
				current_anim_player.play(anim_name)
				current_anim_player.seek(seek_time, true)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw

				var normal_frame := sub_viewport.get_texture().get_image()
				normal_frame.convert(Image.FORMAT_RGBA8)
				normal_sheet.blit_rect(normal_frame, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

				# Restore original unlit materials for next color pass
				_restore_saved_materials()

			# --- Shadow capture pass: top-down silhouette ---
			if _shadow_capture_material:
				# Swap main camera for top-down shadow camera
				var shadow_cam := _create_shadow_camera()
				sub_viewport.add_child(shadow_cam)
				shadow_cam.current = true

				_save_current_materials(current_model_instance)
				_apply_shadow_capture_materials(current_model_instance)
				# Re-seek animation
				current_anim_player.play(anim_name)
				current_anim_player.seek(seek_time, true)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw

				var shadow_frame := sub_viewport.get_texture().get_image()
				shadow_frame.convert(Image.FORMAT_RGBA8)
				shadow_sheet.blit_rect(shadow_frame, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

				_restore_saved_materials()
				# Restore main camera
				shadow_cam.queue_free()
				camera.current = true

		_captured_sheets[dir_name] = sheet
		_captured_normal_sheets[dir_name] = normal_sheet
		_captured_shadow_sheets[dir_name] = shadow_sheet

	_update_capture_preview()

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

	for dir_name in _captured_normal_sheets:
		var file_path := "%s/%s_%s_normal.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		_captured_normal_sheets[dir_name].save_png(global_path)

	for dir_name in _captured_shadow_sheets:
		var file_path := "%s/%s_%s_shadow.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		_captured_shadow_sheets[dir_name].save_png(global_path)

	# Restore camera and viewport
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0

	sub_viewport.size = original_vp_size
	camera.size = original_cam_size
	camera_target = original_cam_target
	_position_camera(camera_elevation_slider.value)
	preview_container.stretch = true

	_set_status("Captured all 3 directions. Review and click Next.")


func _compute_camera_pan(detect_img: Image, detect_size: int, detect_cam_size: float) -> Vector3:
	## Given a detection-pass render (wider view), find the bounding box of opaque
	## pixels and compute a world-space camera shift to center the character.
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

	# If offset is small (character is already centered), skip the shift
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
	var sheets: Dictionary
	match _capture_preview_mode:
		"color":
			sheets = _captured_sheets
		"normal":
			sheets = _captured_normal_sheets
		"shadow":
			sheets = _captured_shadow_sheets
		_:
			sheets = _captured_sheets
	var rects := [capture_down_rect, capture_up_rect, capture_right_rect]
	var dir_names := ["down", "up", "right"]
	for i in range(3):
		if sheets.has(dir_names[i]):
			rects[i].texture = ImageTexture.create_from_image(sheets[dir_names[i]])


#===============================================================================
# IMAGE PROCESSING (Step 3) — delegates to PixelArtProcessing utility
#===============================================================================

func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	if not _palette_colors.is_empty():
		PixelArtProcessing.apply_palette_mapping(result, _palette_colors)
	elif dithering_toggle.button_pressed:
		PixelArtProcessing.apply_auto_quantize(result)

	if outline_toggle.button_pressed:
		PixelArtProcessing.apply_outline(result, outline_color_picker.color)

	if denoising_toggle.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result


#===============================================================================
# PIXEL PREVIEW
#===============================================================================

func _update_pixel_preview() -> void:
	if not _captured_sheets.has(_preview_direction):
		return
	if show_original_toggle.button_pressed:
		var source: Image = _captured_sheets[_preview_direction] if _pixel_preview_mode != "normal" else _captured_normal_sheets.get(_preview_direction)
		if source:
			pixel_preview_rect.texture = ImageTexture.create_from_image(source)
		return

	match _pixel_preview_mode:
		"color":
			var processed := _process_image(_captured_sheets[_preview_direction])
			pixel_preview_rect.texture = ImageTexture.create_from_image(processed)
		"normal":
			if _captured_normal_sheets.has(_preview_direction):
				var processed := PixelArtProcessing.process_normal_map(
					_captured_normal_sheets[_preview_direction],
					int(output_height_spin.value),
					int(alpha_threshold_slider.value)
				)
				pixel_preview_rect.texture = ImageTexture.create_from_image(processed)
		"lit":
			# Simple inline lit preview — shows color for now
			# Full interactive lighting is in the dedicated Light Preview step
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
	if index <= 0:
		# "(none)" or invalid — clear palette
		_palette_colors.clear()
		_update_palette_preview()
		_update_pixel_preview()
		return
	var palette_name: String = palette_file_dropdown.get_item_text(index)
	var palette_path := "%s/%s" % [PALETTE_DIR, palette_name]
	var global_path := ProjectSettings.globalize_path(palette_path)
	_load_palette_from_path(global_path)


func _scan_palettes() -> void:
	palette_file_dropdown.clear()
	palette_file_dropdown.add_item("(none)")

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
		PixelArtProcessing.apply_alpha_threshold(img, int(alpha_threshold_slider.value))

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
	_export_frame_size = int(output_height_spin.value)

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

	# Export normal maps
	var normal_count := 0
	for dir_name in _captured_normal_sheets:
		_set_status("Processing normal map %s..." % dir_name)
		var processed_normal := PixelArtProcessing.process_normal_map(
			_captured_normal_sheets[dir_name],
			int(output_height_spin.value),
			int(alpha_threshold_slider.value)
		)
		var output_path := "%s/%s_%s_normal.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(output_path)
		var err := processed_normal.save_png(global_path)
		if err != OK:
			_append_log("ERROR: Failed to save normal map %s" % output_path)
			continue
		_append_log("Saved normal: %s" % output_path)
		normal_count += 1

	# Export shadow maps
	var shadow_count := 0
	for dir_name in _captured_shadow_sheets:
		_set_status("Processing shadow %s..." % dir_name)
		# Shadow processing: just downscale + alpha threshold (no dithering/palette/outline)
		var shadow_source: Image = _captured_shadow_sheets[dir_name]
		var result := shadow_source.duplicate() as Image
		var target_height := int(output_height_spin.value)
		var scale_factor := float(target_height) / float(result.get_height())
		var target_width := int(float(result.get_width()) * scale_factor)
		result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
		PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

		var output_path := "%s/%s_%s_shadow.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(output_path)
		var err := result.save_png(global_path)
		if err != OK:
			_append_log("ERROR: Failed to save shadow %s" % output_path)
			continue
		_append_log("Saved shadow: %s" % output_path)
		shadow_count += 1

	_append_log("\nExported %d color + %d normal + %d shadow files to %s/" % [count, normal_count, shadow_count, output_dir])
	_set_status("Export complete! %d files saved." % (count + normal_count + shadow_count))
	_exported_folder = model_name
	back_button.disabled = false
	next_button.visible = true
	next_button.text = "Next"


func _append_log(text: String) -> void:
	export_log_label.text += text + "\n"
	print("[SpritePipeline] %s" % text)


func _on_run_again_pressed() -> void:
	_captured_sheets.clear()
	_captured_normal_sheets.clear()
	_captured_shadow_sheets.clear()
	_go_to_step(0)


func _on_done_pressed() -> void:
	_captured_sheets.clear()
	_captured_normal_sheets.clear()
	_captured_shadow_sheets.clear()
	_palette_colors.clear()
	_clear_model()
	_go_to_step(0)
	_scan_models()


#===============================================================================
# APPLY TO SPRITEFRAMES (Step 6)
#===============================================================================

func _scan_export_folders() -> void:
	_apply_groups.clear()
	for child in apply_summary_container.get_children():
		child.queue_free()
	apply_log_label.text = ""

	if _exported_folder.is_empty():
		apply_summary_container.add_child(_make_label("  (no export was run this session)"))
		apply_button.disabled = true
		return

	_try_add_export_folder(_exported_folder)

	if _apply_groups.is_empty():
		apply_summary_container.add_child(_make_label("  (no sheets found in %s/)" % _exported_folder))
		apply_button.disabled = true
	else:
		apply_button.disabled = false
		# Build editable rows per folder
		for group in _apply_groups:
			var row_vbox := VBoxContainer.new()
			row_vbox.add_theme_constant_override("separation", 2)
			apply_summary_container.add_child(row_vbox)

			# Folder name + animation names
			var anim_names := ", ".join((group["sheets"] as Dictionary).keys())
			var name_label := Label.new()
			name_label.text = "%s: %s" % [group["folder"], anim_names]
			name_label.add_theme_font_size_override("font_size", 12)
			row_vbox.add_child(name_label)

			# FPS + Loop controls on one row
			var controls_hbox := HBoxContainer.new()
			controls_hbox.add_theme_constant_override("separation", 8)
			row_vbox.add_child(controls_hbox)

			controls_hbox.add_child(_make_small_label("  FPS:"))
			var fps_spin := SpinBox.new()
			fps_spin.min_value = 1
			fps_spin.max_value = 60
			fps_spin.value = group["fps"]
			fps_spin.step = 1
			fps_spin.custom_minimum_size.x = 70
			controls_hbox.add_child(fps_spin)
			group["fps_spin"] = fps_spin

			var loop_toggle := CheckButton.new()
			loop_toggle.text = "Loop"
			loop_toggle.button_pressed = group["loop"]
			controls_hbox.add_child(loop_toggle)
			group["loop_toggle"] = loop_toggle

			apply_summary_container.add_child(HSeparator.new())

		_set_status("Found %d animation group(s). Adjust settings and click Apply." % _apply_groups.size())


func _try_add_export_folder(folder_name: String) -> void:
	var folder_path := "%s/%s" % [OUTPUT_BASE, folder_name]
	var global_folder := ProjectSettings.globalize_path(folder_path)
	var sub_dir := DirAccess.open(global_folder)
	if sub_dir == null:
		return

	# Find sheets for each direction
	var direction_files := {}  # "down" -> "filename.png"
	sub_dir.list_dir_begin()
	var file_name := sub_dir.get_next()
	while file_name != "":
		if file_name.ends_with(".png") and not file_name.ends_with(".png.import") and not file_name.ends_with("_normal.png") and not file_name.ends_with("_shadow.png"):
			for dir_info in DIRECTIONS:
				var dir_name: String = dir_info["name"]
				if file_name.ends_with("_%s.png" % dir_name):
					direction_files[dir_name] = file_name
					break
		file_name = sub_dir.get_next()
	sub_dir.list_dir_end()

	if direction_files.is_empty():
		return

	# Determine animation config from known mappings or auto-derive
	var config: Dictionary = KNOWN_ANIM_CONFIG.get(folder_name, {})
	var prefix: String = config.get("prefix", folder_name.to_lower())
	var fps: int = config.get("fps", DEFAULT_APPLY_FPS)
	var loop: bool = config.get("loop", DEFAULT_APPLY_LOOP)

	# Build sheets mapping: {anim_name -> filename}
	var sheets := {}
	for dir_name in direction_files:
		sheets["%s_%s" % [prefix, dir_name]] = direction_files[dir_name]

	_apply_groups.append({
		"folder": folder_name,
		"fps": fps,
		"loop": loop,
		"sheets": sheets,
	})


func _apply_to_spriteframes() -> void:
	apply_button.disabled = true
	apply_log_label.text = ""
	_set_status("Applying sprite sheets to SpriteFrames...")

	if _apply_groups.is_empty():
		_append_apply_log("ERROR: No animation groups to apply.")
		_set_status("Apply failed — no groups found.")
		apply_button.disabled = false
		return

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
	for group in _apply_groups:
		var folder: String = group["folder"]
		var fps: int = int((group["fps_spin"] as SpinBox).value)
		var loop: bool = (group["loop_toggle"] as CheckButton).button_pressed
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

			var frame_count := sheet_image.get_width() / _export_frame_size
			_append_apply_log("  %s: %d frames from %s" % [anim_name, frame_count, sheet_filename])

			# Remove existing animation and recreate
			if frames.has_animation(anim_name):
				frames.remove_animation(anim_name)
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			frames.set_animation_loop(anim_name, loop)

			# Check for corresponding normal map
			var normal_filename := sheet_filename.get_basename() + "_normal.png"
			var normal_path := "%s/%s/%s" % [OUTPUT_BASE, folder, normal_filename]
			var normal_abs_path := ProjectSettings.globalize_path(normal_path)
			var normal_image: Image = null
			if FileAccess.file_exists(normal_abs_path):
				normal_image = Image.load_from_file(normal_abs_path)

			# Check for corresponding shadow map
			var shadow_filename := sheet_filename.get_basename() + "_shadow.png"
			var shadow_path := "%s/%s/%s" % [OUTPUT_BASE, folder, shadow_filename]
			var shadow_abs_path := ProjectSettings.globalize_path(shadow_path)
			var shadow_image: Image = null
			if FileAccess.file_exists(shadow_abs_path):
				shadow_image = Image.load_from_file(shadow_abs_path)

			# Build texture: CanvasTexture if normal exists, plain ImageTexture otherwise
			var sheet_texture := ImageTexture.create_from_image(sheet_image)
			var atlas_source: Texture2D

			if normal_image:
				var normal_texture := ImageTexture.create_from_image(normal_image)
				var canvas_tex := CanvasTexture.new()
				canvas_tex.diffuse_texture = sheet_texture
				canvas_tex.normal_texture = normal_texture
				atlas_source = canvas_tex
				_append_apply_log("    + normal map: %s" % normal_filename)
			else:
				atlas_source = sheet_texture

			for i in range(frame_count):
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = atlas_source
				atlas_tex.region = Rect2(i * _export_frame_size, 0, _export_frame_size, _export_frame_size)
				frames.add_frame(anim_name, atlas_tex)

			total_anims += 1

			# Create shadow animation if shadow map exists
			if shadow_image:
				var shadow_anim_name: String = anim_name + "_shadow"
				if frames.has_animation(shadow_anim_name):
					frames.remove_animation(shadow_anim_name)
				frames.add_animation(shadow_anim_name)
				frames.set_animation_speed(shadow_anim_name, fps)
				frames.set_animation_loop(shadow_anim_name, loop)

				var shadow_texture := ImageTexture.create_from_image(shadow_image)
				for i in range(frame_count):
					var atlas_tex := AtlasTexture.new()
					atlas_tex.atlas = shadow_texture
					atlas_tex.region = Rect2(i * _export_frame_size, 0, _export_frame_size, _export_frame_size)
					frames.add_frame(shadow_anim_name, atlas_tex)

				_append_apply_log("    + shadow: %s (%s)" % [shadow_filename, shadow_anim_name])
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
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", FONT_LABEL)
	return l


func _make_small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_HINT)
	l.add_theme_color_override("font_color", C_TEXT_SEC)
	return l


func _set_status(text: String) -> void:
	status_label.text = text
	# Color based on content
	if text.begins_with("Error") or text.begins_with("Failed"):
		status_label.add_theme_color_override("font_color", C_WARNING)
	elif text.begins_with("Done") or text.begins_with("Saved") or text.begins_with("Export"):
		status_label.add_theme_color_override("font_color", C_SUCCESS)
	else:
		status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	print("[SpritePipeline] %s" % text)


#===============================================================================
# THEME BUILDER
#===============================================================================

func _build_theme() -> Theme:
	var theme := Theme.new()

	# --- PanelContainer ---
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_PANEL
	panel_sb.set_corner_radius_all(0)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	# --- Button: normal ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_SURFACE
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = C_BORDER
	btn_normal.set_corner_radius_all(4)
	btn_normal.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", btn_normal)

	# --- Button: hover ---
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = C_SURFACE_HOVER
	btn_hover.set_border_width_all(1)
	btn_hover.border_color = C_BORDER
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(8)
	theme.set_stylebox("hover", "Button", btn_hover)

	# --- Button: pressed ---
	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = C_ACCENT
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.set_content_margin_all(8)
	theme.set_stylebox("pressed", "Button", btn_pressed)

	# --- Button: disabled ---
	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(C_SURFACE, 0.3)
	btn_disabled.set_corner_radius_all(4)
	btn_disabled.set_content_margin_all(8)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	# --- Button: focus ---
	var btn_focus := StyleBoxEmpty.new()
	theme.set_stylebox("focus", "Button", btn_focus)

	# --- Button colors ---
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", C_TEXT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", C_TEXT_DIM)

	# --- OptionButton ---
	theme.set_stylebox("normal", "OptionButton", btn_normal)
	theme.set_stylebox("hover", "OptionButton", btn_hover)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed)
	theme.set_stylebox("focus", "OptionButton", btn_focus)
	theme.set_color("font_color", "OptionButton", C_TEXT)
	theme.set_color("font_hover_color", "OptionButton", C_TEXT)

	# --- CheckButton ---
	theme.set_color("font_color", "CheckButton", C_TEXT)
	theme.set_color("font_hover_color", "CheckButton", C_TEXT)
	theme.set_color("font_pressed_color", "CheckButton", C_ACCENT)

	# --- Label ---
	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_font_size("font_size", "Label", FONT_LABEL)

	# --- HSlider ---
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = C_BORDER
	slider_bg.set_content_margin_all(0)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", slider_bg)

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = C_ACCENT
	slider_fill.set_content_margin_all(0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)

	# --- LineEdit / SpinBox ---
	var line_edit_sb := StyleBoxFlat.new()
	line_edit_sb.bg_color = C_SURFACE
	line_edit_sb.set_border_width_all(1)
	line_edit_sb.border_color = C_BORDER
	line_edit_sb.set_corner_radius_all(4)
	line_edit_sb.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", line_edit_sb)
	theme.set_stylebox("focus", "LineEdit", line_edit_sb)
	theme.set_color("font_color", "LineEdit", C_TEXT)

	# --- ScrollContainer ---
	var scroll_sb := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll_sb)

	# --- HSeparator ---
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_BORDER
	sep_sb.set_content_margin_all(0)
	sep_sb.content_margin_top = 4
	sep_sb.content_margin_bottom = 4
	theme.set_stylebox("separator", "HSeparator", sep_sb)
	theme.set_constant("separation", "HSeparator", 1)

	return theme


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
