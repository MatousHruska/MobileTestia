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

	preview_container = SubViewportContainer.new()
	preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	preview_container.stretch = true
	right_panel.add_child(preview_container)


func _build_viewport() -> void:
	pass  # Will be built in Task 3


func _scan_models() -> void:
	pass  # Will be built in Task 3


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

	# Update step indicator
	if step_indicator:
		step_indicator.set_step(step)


func _on_next_pressed() -> void:
	var last_step := STEP_NAMES.size() - 1

	# 2D mode: skip capture step (step 1) — jump from source (0) to processing (2)
	if _current_step == 0 and _source_mode == "2d":
		_go_to_step(2)
		return

	# Last step: trigger export
	if _current_step == last_step:
		_set_status("Exporting...")
		# Export logic will be implemented in Task 8
		return

	if _current_step < last_step:
		_go_to_step(_current_step + 1)


func _on_back_pressed() -> void:
	# 2D mode: skip back over capture step (step 1) — jump from processing (2) to source (0)
	if _current_step == 2 and _source_mode == "2d":
		_go_to_step(0)
		return

	if _current_step > 0:
		_go_to_step(_current_step - 1)


#===============================================================================
# STEP BUILDERS (placeholders — filled in by subsequent tasks)
#===============================================================================

func _build_step1(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 1: Source Selection (placeholder)"))
	parent.add_child(_make_small_label(
		"Choose 3D model or 2D image source, set decoration ID and angle mode."))


func _build_step2(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 2: Capture / Import (placeholder)"))
	parent.add_child(_make_small_label(
		"Capture color, normal, and shadow images from 3D model at selected angles."))


func _build_step3(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 3: Pixel Art Processing (placeholder)"))
	parent.add_child(_make_small_label(
		"Configure downscaling, palette, outline, and dithering settings."))


func _build_step4(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 4: Normal & Shadow (placeholder)"))
	parent.add_child(_make_small_label(
		"Generate and adjust normal maps and baked shadow images."))


func _build_step5(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 5: Preview & Adjust (placeholder)"))
	parent.add_child(_make_small_label(
		"Preview final sprites with lighting, adjust occluder polygons."))


func _build_step6(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 6: Export & Atlas (placeholder)"))
	parent.add_child(_make_small_label(
		"Export sprites, normal maps, shadows, occluder data, and update LDtk atlas."))


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
