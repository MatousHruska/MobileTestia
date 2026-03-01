# Decoration Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a 6-step wizard tool that converts 3D models or 2D images into pixel-art decoration assets with normal maps, shadows, occluders, and an LDtk tileset atlas.

**Architecture:** Unified wizard (`decoration_pipeline.gd`) following the Effect Pipeline dual-source pattern. Reuses `PixelArtProcessing` for image processing, Sprite Pipeline viewport patterns for 3D capture, and adds new algorithms for 2D normal generation, shadow synthesis, occluder tracing, and atlas building. Outputs to `assets/decorations/{id}/` folder structure consumed by `DecorationSpawner`.

**Tech Stack:** GDScript (Godot 4), SubViewport for 3D capture, `PixelArtProcessing` static class, `OccluderPolygon2D` for occluder export, Image API for atlas generation.

---

## Task 1: Create Scene File & Register in Tools Menu

**Files:**
- Create: `scenes/tools/decoration_pipeline.tscn`
- Modify: `scripts/tools/tools_menu.gd:30-51`

**Step 1: Create the minimal scene file**

Create `scenes/tools/decoration_pipeline.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/tools/decoration_pipeline.gd" id="1"]

[node name="DecorationPipeline" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

**Step 2: Add entry to tools menu**

In `scripts/tools/tools_menu.gd`, add a new entry at the end of the `TOOLS` array (after the Attack Composer entry at line 50):

```gdscript
	{
		"label": "Decoration Pipeline",
		"description": "Convert 3D models or 2D images into pixel art decorations with LDtk atlas",
		"scene": "res://scenes/tools/decoration_pipeline.tscn",
	},
```

**Step 3: Create skeleton script**

Create `scripts/tools/decoration_pipeline.gd` with the minimal structure that launches without errors:

```gdscript
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
	# Placeholder — will be built in subsequent tasks
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	status_label = Label.new()
	status_label.text = "Decoration Pipeline — skeleton loaded"
	status_label.add_theme_color_override("font_color", C_TEXT)
	status_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	add_child(status_label)


func _build_viewport() -> void:
	pass  # Will be built in Task 3


func _scan_models() -> void:
	pass  # Will be built in Task 3


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
```

**Step 4: Verify the tool launches**

Run the Godot project with the tools menu scene (F6 on `scenes/tools/tools_menu.tscn`). Verify:
- "Decoration Pipeline" appears as the 5th entry
- Clicking it navigates to the decoration pipeline scene
- The placeholder text "Decoration Pipeline — skeleton loaded" is visible
- No errors in the console

**Step 5: Commit**

```bash
git add scenes/tools/decoration_pipeline.tscn scripts/tools/decoration_pipeline.gd scripts/tools/tools_menu.gd
git commit -m "feat(tools): add decoration pipeline skeleton and menu entry"
```

---

## Task 2: Build Full UI Layout & Step Navigation

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

This task replaces the placeholder `_build_ui()` with the full wizard layout matching the established pattern: left panel (300px) with step indicator, scrollable step content, and navigation bar; right panel (expanding) for previews.

**Step 1: Build the main layout**

Replace the `_build_ui()` function with the full implementation. The layout follows the exact same pattern as `sprite_pipeline.gd` and `effect_pipeline.gd`:

```gdscript
func _build_ui() -> void:
	var theme := _build_theme()
	self.theme = theme

	# Full-screen background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Main split: left panel (300px) + right preview (expand)
	var hsplit := HBoxContainer.new()
	hsplit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(hsplit)

	# ── Left Panel ──
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 300
	left_panel.size_flags_horizontal = SIZE_FILL
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = C_PANEL
	left_style.border_color = C_BORDER
	left_style.border_width_right = 1
	left_panel.add_theme_stylebox_override("panel", left_style)
	hsplit.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 0)
	left_panel.add_child(left_vbox)

	# Back to tools button
	var back_tools := _make_subtle_button("← Back to Tools")
	back_tools.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(TOOLS_MENU_PATH)
	)
	left_vbox.add_child(back_tools)

	# Step indicator
	step_indicator = StepIndicator.new()
	step_indicator.setup(STEP_NAMES)
	step_indicator.set_current(0)
	left_vbox.add_child(step_indicator)

	# Scrollable step content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var steps_vbox := VBoxContainer.new()
	steps_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	steps_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(steps_vbox)

	# Build each step container (all hidden except step 0)
	for i in range(STEP_NAMES.size()):
		var container := VBoxContainer.new()
		container.size_flags_horizontal = SIZE_EXPAND_FILL
		container.add_theme_constant_override("separation", 8)
		container.visible = (i == 0)
		steps_vbox.add_child(container)
		step_containers.append(container)

	# Build step content
	_build_step1(step_containers[0])
	_build_step2(step_containers[1])
	_build_step3(step_containers[2])
	_build_step4(step_containers[3])
	_build_step5(step_containers[4])
	_build_step6(step_containers[5])

	# Fixed navigation bar at bottom
	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 8)
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 8)
	nav_margin.add_theme_constant_override("margin_right", 8)
	nav_margin.add_theme_constant_override("margin_bottom", 8)
	nav_margin.add_theme_constant_override("margin_top", 4)
	nav_margin.add_child(nav_bar)
	left_vbox.add_child(nav_margin)

	back_button = _make_subtle_button("◄ Back")
	back_button.pressed.connect(_on_back_pressed)
	back_button.disabled = true
	nav_bar.add_child(back_button)

	next_button = _make_primary_button("Next ►")
	next_button.size_flags_horizontal = SIZE_EXPAND_FILL
	next_button.pressed.connect(_on_next_pressed)
	nav_bar.add_child(next_button)

	# Status bar
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", FONT_HINT)
	status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 8)
	status_margin.add_theme_constant_override("margin_right", 8)
	status_margin.add_theme_constant_override("margin_bottom", 4)
	status_margin.add_child(status_label)
	left_vbox.add_child(status_margin)

	# ── Right Panel (preview) ──
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = Color("#111122")
	right_panel.add_theme_stylebox_override("panel", right_style)
	hsplit.add_child(right_panel)

	# Preview areas will be added inside right_panel by individual steps
	# SubViewportContainer for 3D, TextureRect for 2D/processed previews
	preview_container = SubViewportContainer.new()
	preview_container.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	preview_container.stretch = true
	right_panel.add_child(preview_container)
```

**Step 2: Add step navigation logic**

```gdscript
func _go_to_step(step: int) -> void:
	if step < 0 or step >= STEP_NAMES.size():
		return
	_current_step = step
	step_indicator.set_current(step)
	for i in range(step_containers.size()):
		step_containers[i].visible = (i == step)
	back_button.disabled = (step == 0)
	# Update next button text for last step
	if step == STEP_NAMES.size() - 1:
		next_button.text = "Export"
	else:
		next_button.text = "Next ►"


func _on_next_pressed() -> void:
	match _current_step:
		0:
			# Validate source selection before proceeding
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
				_go_to_step(2)  # Skip capture for 2D
				return
		1:
			# After capture — validate captures exist
			if _captured_color.is_empty():
				_set_status("Capture frames first.")
				return
		5:
			# Export step — trigger export
			_start_export()
			return
	_go_to_step(_current_step + 1)


func _on_back_pressed() -> void:
	if _current_step == 2 and _source_mode == "2d":
		_go_to_step(0)  # Skip capture step when going back in 2D mode
		return
	_go_to_step(_current_step - 1)
```

**Step 3: Add placeholder step builders**

Add empty step builder stubs for steps 1-6 (they'll be filled in subsequent tasks):

```gdscript
func _build_step1(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 1: Source Selection (placeholder)"))

func _build_step2(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 2: Capture / Import (placeholder)"))

func _build_step3(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 3: Pixel Art Processing (placeholder)"))

func _build_step4(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 4: Normal & Shadow (placeholder)"))

func _build_step5(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 5: Preview & Adjust (placeholder)"))

func _build_step6(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Step 6: Export & Atlas (placeholder)"))
```

**Step 4: Add UI helper functions**

Copy the standard UI helper functions from the Effect Pipeline (identical pattern used by all tools):

```gdscript
#===============================================================================
# UI HELPERS
#===============================================================================

func _build_theme() -> Theme:
	var t := Theme.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = C_PANEL
	t.set_stylebox("panel", "PanelContainer", panel_style)
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_SURFACE
	btn_normal.set_corner_radius_all(4)
	btn_normal.set_content_margin_all(6)
	t.set_stylebox("normal", "Button", btn_normal)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = C_SURFACE_HOVER
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(6)
	t.set_stylebox("hover", "Button", btn_hover)
	var btn_pressed := btn_hover.duplicate()
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_font_size("font_size", "Button", FONT_LABEL)
	t.set_font_size("font_size", "Label", FONT_LABEL)
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = C_SURFACE
	le_style.set_corner_radius_all(4)
	le_style.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", le_style)
	return t

func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_LABEL)
	lbl.add_theme_color_override("font_color", C_TEXT)
	return lbl

func _make_small_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_HINT)
	lbl.add_theme_color_override("font_color", C_TEXT_SEC)
	return lbl

func _make_section(title: String) -> Array:
	var outer := PanelContainer.new()
	outer.size_flags_horizontal = SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = C_SECTION
	style.border_color = C_SECTION_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	outer.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	outer.add_child(vbox)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", FONT_SECTION)
	lbl.add_theme_color_override("font_color", C_ACCENT)
	vbox.add_child(lbl)
	return [outer, vbox]

func _make_field(label_text: String, control: Control) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", FONT_HINT)
	lbl.add_theme_color_override("font_color", C_TEXT_SEC)
	vbox.add_child(lbl)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(control)
	return vbox

func _make_collapsible(title: String, start_open: bool = false) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	var toggle_btn := Button.new()
	toggle_btn.text = ("▼ " if start_open else "► ") + title
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_btn.add_theme_font_size_override("font_size", FONT_LABEL)
	outer.add_child(toggle_btn)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.visible = start_open
	outer.add_child(content)
	toggle_btn.pressed.connect(func() -> void:
		content.visible = not content.visible
		toggle_btn.text = ("▼ " if content.visible else "► ") + title
	)
	return [outer, content, toggle_btn]

func _make_toggle_group(options: Array, callback: Callable) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		_apply_toggle_style(btn, i == 0)
		btn.pressed.connect(func() -> void:
			for child in hbox.get_children():
				if child is Button:
					child.button_pressed = (child == btn)
					_apply_toggle_style(child, child == btn)
			callback.call(options[hbox.get_children().find(btn)])
		)
		hbox.add_child(btn)
	return hbox

func _apply_toggle_style(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT if active else C_SURFACE
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color.WHITE if active else C_TEXT_SEC)

func _make_slider_row(min_val: float, max_val: float, default_val: float, step_val: float) -> Array:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step_val
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(slider)
	var value_label := Label.new()
	value_label.text = str(default_val)
	value_label.add_theme_font_size_override("font_size", FONT_VALUE)
	value_label.add_theme_color_override("font_color", C_TEXT)
	value_label.custom_minimum_size.x = 40
	hbox.add_child(value_label)
	slider.value_changed.connect(func(val: float) -> void:
		value_label.text = str(val)
	)
	return [hbox, slider, value_label]

func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	var style := StyleBoxFlat.new()
	style.bg_color = C_ACCENT
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_ACCENT.lightened(0.15)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func _make_subtle_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_HINT)
	btn.add_theme_color_override("font_color", C_TEXT_SEC)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", style)
	return btn

func _style_checkbutton_transparent(cb: CheckButton) -> void:
	cb.add_theme_font_size_override("font_size", FONT_LABEL)
	cb.add_theme_color_override("font_color", C_TEXT)
```

**Step 5: Verify wizard navigation works**

Launch the tool, verify:
- Step indicator shows 6 steps
- Next/Back buttons navigate between steps
- Step containers show/hide correctly
- Back button disabled on step 0
- Status label updates

**Step 6: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): build decoration pipeline UI layout and step navigation"
```

---

## Task 3: Step 1 — Source Selection (3D Model + 2D Image)

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Reference:** Effect Pipeline `_build_step1()` (lines 1-300) for dual-source pattern.

**Step 1: Build Step 1 UI**

Replace the placeholder `_build_step1()` with the full implementation:

```gdscript
func _build_step1(parent: VBoxContainer) -> void:
	# Source mode toggle: 3D Model | 2D Image
	var mode_section := _make_section("Source Type")
	parent.add_child(mode_section[0])
	var mode_toggle := _make_toggle_group(["3D Model", "2D Image"], _on_source_mode_changed)
	mode_section[1].add_child(mode_toggle)

	# Decoration ID (shared between modes)
	var id_section := _make_section("Decoration ID")
	parent.add_child(id_section[0])
	deco_id_input = LineEdit.new()
	deco_id_input.placeholder_text = "e.g. stone_pillar"
	deco_id_input.text_changed.connect(func(text: String) -> void:
		_decoration_id = text.strip_edges()
	)
	id_section[1].add_child(_make_field("Unique identifier for this decoration", deco_id_input))

	# ── 3D Mode Container ──
	_3d_container = VBoxContainer.new()
	_3d_container.add_theme_constant_override("separation", 8)
	parent.add_child(_3d_container)

	var model_section := _make_section("3D Model")
	_3d_container.add_child(model_section[0])
	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	model_section[1].add_child(_make_field("Select .glb/.gltf model", model_dropdown))

	# View angles selector (3D only)
	var angle_section := _make_section("View Angles")
	_3d_container.add_child(angle_section[0])
	angle_mode_group = _make_toggle_group(
		["Single Front", "Front + Back", "4 Directions"],
		_on_angle_mode_changed
	)
	angle_section[1].add_child(angle_mode_group)
	angle_section[1].add_child(_make_small_label(
		"Single: one sprite. Multi: creates suffixed IDs (e.g. statue_front, statue_back)."
	))

	# Camera settings (collapsible, 3D only)
	var cam_coll := _make_collapsible("Camera Settings", false)
	_3d_container.add_child(cam_coll[0])

	var zoom_row := _make_slider_row(1.0, 8.0, 3.0, 0.1)
	cam_coll[1].add_child(_make_field("Zoom (camera size)", zoom_row[0]))
	_camera_zoom_slider = zoom_row[1]
	zoom_row[1].value_changed.connect(_on_zoom_changed)

	var elev_row := _make_slider_row(0.0, 90.0, 30.0, 1.0)
	cam_coll[1].add_child(_make_field("Elevation (degrees)", elev_row[0]))
	_camera_elevation_slider = elev_row[1]
	elev_row[1].value_changed.connect(_on_elevation_changed)

	var target_y_row := _make_slider_row(0.0, 3.0, 1.0, 0.05)
	cam_coll[1].add_child(_make_field("Target height (Y)", target_y_row[0]))
	_camera_target_y_slider = target_y_row[1]
	target_y_row[1].value_changed.connect(_on_target_y_changed)

	# ── 2D Mode Container ──
	_2d_container = VBoxContainer.new()
	_2d_container.add_theme_constant_override("separation", 8)
	_2d_container.visible = false
	parent.add_child(_2d_container)

	var import_section := _make_section("2D Image")
	_2d_container.add_child(import_section[0])

	var browse_btn := _make_primary_button("Browse Image...")
	browse_btn.pressed.connect(_on_2d_browse_pressed)
	import_section[1].add_child(browse_btn)

	_2d_info_label = _make_small_label("No image loaded")
	import_section[1].add_child(_2d_info_label)
```

**Step 2: Add source mode switching and 3D model loading**

```gdscript
# Additional state variables (add to WIZARD STATE section):
var _camera_zoom_slider: HSlider
var _camera_elevation_slider: HSlider
var _camera_target_y_slider: HSlider
var camera_target := Vector3(0.0, 1.0, 0.0)
var _2d_info_label: Label


func _on_source_mode_changed(mode_text: String) -> void:
	if mode_text == "3D Model":
		_source_mode = "3d"
		_3d_container.visible = true
		_2d_container.visible = false
		preview_container.visible = true
	else:
		_source_mode = "2d"
		_3d_container.visible = false
		_2d_container.visible = true
		preview_container.visible = false


func _on_angle_mode_changed(mode_text: String) -> void:
	match mode_text:
		"Single Front":
			_angle_mode = "single"
		"Front + Back":
			_angle_mode = "two"
		"4 Directions":
			_angle_mode = "four"
```

**Step 3: Implement `_build_viewport()` and model scanning**

Reuse the Sprite Pipeline viewport pattern:

```gdscript
func _build_viewport() -> void:
	sub_viewport = SubViewport.new()
	sub_viewport.transparent_bg = true
	sub_viewport.size = Vector2i(512, 512)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.msaa_3d = Viewport.MSAA_4X
	preview_container.add_child(sub_viewport)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.far = 100.0
	sub_viewport.add_child(camera)
	camera_target = Vector3(0.0, 1.0, 0.0)
	_position_camera(30.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.TRANSPARENT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	sub_viewport.add_child(world_env)

	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-45, 30, 0)
	dir_light.light_energy = 0.5
	dir_light.shadow_enabled = false
	sub_viewport.add_child(dir_light)

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


func _on_model_selected(index: int) -> void:
	if index < 0 or index >= available_models.size():
		return
	var file_name: String = available_models[index]
	var res_path := "%s/%s" % [IMPORT_DIR, file_name]
	current_model_path = res_path
	_clear_model()

	var packed_scene := ResourceLoader.load(res_path) as PackedScene
	if packed_scene == null:
		_set_status("ERROR: Could not load %s" % res_path)
		return
	current_model_instance = packed_scene.instantiate()
	model_slot.add_child(current_model_instance)
	_apply_unlit_materials(current_model_instance)

	# Auto-suggest decoration ID from model name
	var base_name := file_name.get_basename().to_lower().replace(" ", "_").replace("-", "_")
	deco_id_input.text = base_name
	_decoration_id = base_name
	_set_status("Model loaded: %s" % file_name)


func _clear_model() -> void:
	if current_model_instance:
		current_model_instance.queue_free()
		current_model_instance = null
```

**Step 4: Implement 2D browse and import**

```gdscript
func _on_2d_browse_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg ; JPEG Images"])
	dialog.size = Vector2i(800, 500)
	dialog.file_selected.connect(_on_2d_file_selected)
	add_child(dialog)
	dialog.popup_centered()


func _on_2d_file_selected(path: String) -> void:
	_imported_image = Image.load_from_file(path)
	if _imported_image == null:
		_set_status("ERROR: Could not load image: %s" % path)
		return
	_imported_image.convert(Image.FORMAT_RGBA8)

	# Auto-suggest decoration ID from file name
	var base_name := path.get_file().get_basename().to_lower().replace(" ", "_").replace("-", "_")
	deco_id_input.text = base_name
	_decoration_id = base_name

	_2d_info_label.text = "%s (%dx%d)" % [path.get_file(), _imported_image.get_width(), _imported_image.get_height()]
	_set_status("Image loaded: %dx%d" % [_imported_image.get_width(), _imported_image.get_height()])
```

**Step 5: Add camera and material helpers**

```gdscript
func _position_camera(elevation_deg: float) -> void:
	var elevation_rad := deg_to_rad(elevation_deg)
	var distance := maxf(camera.size * 2.0, 5.0)
	var offset_y := sin(elevation_rad) * distance
	var offset_z := cos(elevation_rad) * distance
	camera.position = camera_target + Vector3(0.0, offset_y, offset_z)
	camera.look_at(camera_target, Vector3.UP)

func _on_zoom_changed(value: float) -> void:
	camera.size = value
	_position_camera(_camera_elevation_slider.value)

func _on_elevation_changed(value: float) -> void:
	_position_camera(value)

func _on_target_y_changed(value: float) -> void:
	camera_target.y = value
	_position_camera(_camera_elevation_slider.value)

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
	for entry in _saved_unlit_materials:
		var mi: MeshInstance3D = entry["mesh_instance"]
		mi.set_surface_override_material(entry["surface_idx"], entry["material"])
	_saved_unlit_materials.clear()

func _apply_normal_capture_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_idx, _normal_capture_material)
	for child in node.get_children():
		_apply_normal_capture_materials(child)

func _apply_shadow_capture_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_idx, _shadow_capture_material)
	for child in node.get_children():
		_apply_shadow_capture_materials(child)
```

**Step 6: Verify Step 1 works**

Launch the tool, verify:
- Mode toggle switches between 3D and 2D containers
- 3D mode: model dropdown populates, model loads into viewport, camera controls work
- 2D mode: browse opens file dialog, image loads, info label updates
- Decoration ID auto-populates from selection
- Next validates required inputs

**Step 7: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 1 — source selection"
```

---

## Task 4: Step 2 — 3D Capture (Color + Normal + Shadow)

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Reference:** Sprite Pipeline `_capture_animation()` (lines 2127-2296) — same detection pass → panning pass → multi-pass capture pattern, but for a single static frame instead of animation frames.

**Step 1: Build Step 2 UI**

Replace the placeholder `_build_step2()`:

```gdscript
func _build_step2(parent: VBoxContainer) -> void:
	var section := _make_section("3D Capture")
	parent.add_child(section[0])

	var capture_btn := _make_primary_button("Capture All Angles")
	capture_btn.pressed.connect(_start_capture)
	section[1].add_child(capture_btn)

	_capture_status_label = _make_small_label("Press capture to render from all selected angles.")
	section[1].add_child(_capture_status_label)

	# Thumbnail preview grid for captured angles
	_capture_preview_grid = GridContainer.new()
	_capture_preview_grid.columns = 2
	_capture_preview_grid.add_theme_constant_override("h_separation", 8)
	_capture_preview_grid.add_theme_constant_override("v_separation", 8)
	section[1].add_child(_capture_preview_grid)

# Add to state variables:
var _capture_status_label: Label
var _capture_preview_grid: GridContainer
```

**Step 2: Implement capture logic**

This is the core 3D capture. For decorations, we capture a **single static frame** (no animation) per angle, with 3 render passes: color, normal, shadow.

```gdscript
func _start_capture() -> void:
	if current_model_instance == null:
		_set_status("ERROR: No model loaded.")
		return
	_captured_color.clear()
	_captured_normal.clear()
	_captured_shadow.clear()
	next_button.disabled = true
	back_button.disabled = true
	await _capture_decoration()
	next_button.disabled = false
	back_button.disabled = false


func _capture_decoration() -> void:
	var output_size := 512
	var angles: Array = ANGLE_CONFIGS[_angle_mode]
	var original_vp_size := sub_viewport.size
	var original_cam_size := camera.size
	var original_cam_target := camera_target
	preview_container.stretch = false

	for angle_config in angles:
		var angle_name: String = angle_config["name"]
		var rot_y: float = angle_config["rotation_y"]

		_set_status("Capturing %s..." % angle_name)
		_capture_status_label.text = "Capturing %s..." % angle_name

		if current_model_instance is Node3D:
			(current_model_instance as Node3D).rotation_degrees.y = rot_y

		# --- Detection pass: overscan render to find model bounds ---
		var detect_size := int(output_size * CAPTURE_OVERSCAN)
		sub_viewport.size = Vector2i(detect_size, detect_size)
		camera.size = original_cam_size * CAPTURE_OVERSCAN
		camera_target = original_cam_target
		_position_camera(_camera_elevation_slider.value)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var detect_img := sub_viewport.get_texture().get_image()
		detect_img.convert(Image.FORMAT_RGBA8)
		var cam_shift := _compute_camera_pan(detect_img, detect_size, original_cam_size * CAPTURE_OVERSCAN)

		# --- Color pass: normal zoom, centered ---
		sub_viewport.size = Vector2i(output_size, output_size)
		camera.size = original_cam_size
		camera_target = original_cam_target + cam_shift
		_position_camera(_camera_elevation_slider.value)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var color_image := sub_viewport.get_texture().get_image()
		color_image.convert(Image.FORMAT_RGBA8)
		_captured_color[angle_name] = color_image

		# --- Normal map pass ---
		if _normal_capture_material:
			_save_current_materials(current_model_instance)
			_apply_normal_capture_materials(current_model_instance)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var normal_image := sub_viewport.get_texture().get_image()
			normal_image.convert(Image.FORMAT_RGBA8)
			_captured_normal[angle_name] = normal_image
			_restore_saved_materials()

		# --- Shadow pass ---
		if _shadow_capture_material:
			var shadow_cam := _create_shadow_camera()
			sub_viewport.add_child(shadow_cam)
			shadow_cam.current = true
			_save_current_materials(current_model_instance)
			_apply_shadow_capture_materials(current_model_instance)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var shadow_image := sub_viewport.get_texture().get_image()
			shadow_image.convert(Image.FORMAT_RGBA8)
			_captured_shadow[angle_name] = shadow_image
			_restore_saved_materials()
			shadow_cam.queue_free()
			camera.current = true

	# Restore camera
	if current_model_instance is Node3D:
		(current_model_instance as Node3D).rotation_degrees.y = 0.0
	sub_viewport.size = original_vp_size
	camera.size = original_cam_size
	camera_target = original_cam_target
	_position_camera(_camera_elevation_slider.value)
	preview_container.stretch = true

	_update_capture_preview()
	_set_status("Captured %d angle(s). Review and click Next." % angles.size())
	_capture_status_label.text = "Captured %d angles." % angles.size()


func _compute_camera_pan(detect_img: Image, detect_size: int, detect_cam_size: float) -> Vector3:
	var w := detect_img.get_width()
	var h := detect_img.get_height()
	var min_x := w
	var min_y := h
	var max_x := 0
	var max_y := 0
	for y in range(h):
		for x in range(w):
			if detect_img.get_pixel(x, y).a > 0.1:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x <= min_x or max_y <= min_y:
		return Vector3.ZERO
	var center_x := (min_x + max_x) / 2.0
	var center_y := (min_y + max_y) / 2.0
	var pixel_offset_x := center_x - w / 2.0
	var pixel_offset_y := center_y - h / 2.0
	var world_per_pixel := detect_cam_size / float(detect_size)
	return Vector3(pixel_offset_x * world_per_pixel, -pixel_offset_y * world_per_pixel, 0.0)


func _create_shadow_camera() -> Camera3D:
	var shadow_cam := Camera3D.new()
	shadow_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	shadow_cam.size = camera.size
	shadow_cam.far = 100.0
	# Top-down view for shadow
	shadow_cam.position = camera_target + Vector3(0.0, 10.0, 0.0)
	shadow_cam.rotation_degrees = Vector3(-90, 0, 0)
	return shadow_cam


func _update_capture_preview() -> void:
	# Clear existing previews
	for child in _capture_preview_grid.get_children():
		child.queue_free()
	# Add thumbnail for each captured angle
	for angle_name in _captured_color:
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		var lbl := _make_small_label(angle_name)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(120, 120)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = ImageTexture.create_from_image(_captured_color[angle_name])
		vbox.add_child(tex_rect)
		_capture_preview_grid.add_child(vbox)
```

**Step 3: Verify 3D capture works**

Launch with a 3D model, set angle mode, click "Capture All Angles". Verify:
- Detection pass centers the model
- Color, normal, and shadow images are captured per angle
- Thumbnail previews appear in the grid
- Next button navigates to Step 3

**Step 4: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 2 — 3D capture"
```

---

## Task 5: Step 3 — Pixel Art Processing

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Reference:** Effect Pipeline `_build_step3()` and `_process_image()` — identical pixel art processing controls.

**Step 1: Build Step 3 UI**

Replace the placeholder `_build_step3()`:

```gdscript
func _build_step3(parent: VBoxContainer) -> void:
	var section := _make_section("Pixel Art Settings")
	parent.add_child(section[0])

	# Output height
	var height_row := _make_slider_row(8, 128, 32, 1)
	section[1].add_child(_make_field("Output Height (px)", height_row[0]))
	_output_height_slider = height_row[1]
	height_row[1].value_changed.connect(_on_pixel_setting_changed)

	# Alpha threshold
	var alpha_row := _make_slider_row(1, 255, 64, 1)
	section[1].add_child(_make_field("Alpha Threshold", alpha_row[0]))
	_alpha_threshold_slider = alpha_row[1]
	alpha_row[1].value_changed.connect(_on_pixel_setting_changed)

	# Dithering
	var dither_check := CheckButton.new()
	dither_check.text = "Ordered Dithering"
	_style_checkbutton_transparent(dither_check)
	dither_check.toggled.connect(func(_v: bool) -> void: _on_pixel_setting_changed(0))
	section[1].add_child(dither_check)
	_dither_check = dither_check

	var dither_strength_row := _make_slider_row(0.0, 1.0, 0.3, 0.05)
	section[1].add_child(_make_field("Dither Strength", dither_strength_row[0]))
	_dither_strength_slider = dither_strength_row[1]
	dither_strength_row[1].value_changed.connect(_on_pixel_setting_changed)

	# Outline
	var outline_check := CheckButton.new()
	outline_check.text = "Outline"
	_style_checkbutton_transparent(outline_check)
	outline_check.toggled.connect(func(_v: bool) -> void: _on_pixel_setting_changed(0))
	section[1].add_child(outline_check)
	_outline_check = outline_check

	# Denoising
	var denoise_check := CheckButton.new()
	denoise_check.text = "Denoising"
	denoise_check.button_pressed = true
	_style_checkbutton_transparent(denoise_check)
	denoise_check.toggled.connect(func(_v: bool) -> void: _on_pixel_setting_changed(0))
	section[1].add_child(denoise_check)
	_denoise_check = denoise_check

	var denoise_row := _make_slider_row(1, 10, 2, 1)
	section[1].add_child(_make_field("Min Cluster Size", denoise_row[0]))
	_denoise_slider = denoise_row[1]
	denoise_row[1].value_changed.connect(_on_pixel_setting_changed)

	# Preview button
	var preview_btn := _make_primary_button("Update Preview")
	preview_btn.pressed.connect(_update_pixel_preview)
	section[1].add_child(preview_btn)

	# Preview thumbnail
	_pixel_preview_rect = TextureRect.new()
	_pixel_preview_rect.custom_minimum_size = Vector2(200, 200)
	_pixel_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pixel_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	section[1].add_child(_pixel_preview_rect)

# Add to state variables:
var _output_height_slider: HSlider
var _alpha_threshold_slider: HSlider
var _dither_check: CheckButton
var _dither_strength_slider: HSlider
var _outline_check: CheckButton
var _denoise_check: CheckButton
var _denoise_slider: HSlider
var _pixel_preview_rect: TextureRect
```

**Step 2: Implement image processing**

```gdscript
func _process_decoration_image(source: Image) -> Image:
	var target_height := int(_output_height_slider.value)
	var result := source.duplicate() as Image
	# Downscale with nearest-neighbor
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
	# Alpha threshold
	PixelArtProcessing.apply_alpha_threshold(result, int(_alpha_threshold_slider.value))
	# Dithering
	if _dither_check.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, _dither_strength_slider.value, 1)
		PixelArtProcessing.apply_auto_quantize(result)
	# Outline
	if _outline_check.button_pressed:
		PixelArtProcessing.apply_outline(result, Color.BLACK)
	# Denoising
	if _denoise_check.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(_denoise_slider.value))
	return result


func _on_pixel_setting_changed(_value: float) -> void:
	pass  # Debounce — user clicks "Update Preview" to see changes


func _update_pixel_preview() -> void:
	# Process the first available captured/imported image
	var source_image: Image = null
	if _source_mode == "3d":
		if not _captured_color.is_empty():
			source_image = _captured_color.values()[0]
	else:
		source_image = _imported_image

	if source_image == null:
		_set_status("No source image to process.")
		return

	var processed := _process_decoration_image(source_image)
	_pixel_preview_rect.texture = ImageTexture.create_from_image(processed)
	_set_status("Preview updated: %dx%d" % [processed.get_width(), processed.get_height()])
```

**Step 3: Verify pixel art processing**

Load a 3D model, capture, navigate to Step 3. Adjust sliders and click "Update Preview". Verify:
- Image downscales correctly
- Alpha threshold, dithering, outline, denoising all work
- Preview shows the processed result

**Step 4: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 3 — pixel art processing"
```

---

## Task 6: Step 4 — Normal Map & Shadow Generation

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

This step processes captured normals/shadows (3D) or generates them from the sprite (2D).

**Step 1: Build Step 4 UI**

```gdscript
func _build_step4(parent: VBoxContainer) -> void:
	# Normal map section
	var normal_section := _make_section("Normal Map")
	parent.add_child(normal_section[0])

	# 2D-only: height scale for generated normals
	_2d_normal_container = VBoxContainer.new()
	_2d_normal_container.visible = (_source_mode == "2d")
	normal_section[1].add_child(_2d_normal_container)
	var height_row := _make_slider_row(0.1, 5.0, 1.0, 0.1)
	_2d_normal_container.add_child(_make_field("Height Scale (bumpiness)", height_row[0]))
	_normal_height_slider = height_row[1]

	var invert_check := CheckButton.new()
	invert_check.text = "Invert Heights (dark = raised)"
	_style_checkbutton_transparent(invert_check)
	_2d_normal_container.add_child(invert_check)
	_normal_invert_check = invert_check

	_normal_preview_rect = TextureRect.new()
	_normal_preview_rect.custom_minimum_size = Vector2(120, 120)
	_normal_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_normal_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	normal_section[1].add_child(_normal_preview_rect)

	# Shadow section
	var shadow_section := _make_section("Baked Shadow")
	parent.add_child(shadow_section[0])

	var offset_row := _make_slider_row(-8, 8, 2, 1)
	shadow_section[1].add_child(_make_field("Shadow Offset Y (px)", offset_row[0]))
	_shadow_offset_slider = offset_row[1]

	var opacity_row := _make_slider_row(0.1, 1.0, 0.5, 0.05)
	shadow_section[1].add_child(_make_field("Shadow Opacity", opacity_row[0]))
	_shadow_opacity_slider = opacity_row[1]

	_shadow_preview_rect = TextureRect.new()
	_shadow_preview_rect.custom_minimum_size = Vector2(120, 120)
	_shadow_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shadow_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow_section[1].add_child(_shadow_preview_rect)

	# Occluder section
	var occluder_section := _make_section("Occluder Polygon")
	parent.add_child(occluder_section[0])

	var simplify_row := _make_slider_row(0.5, 5.0, 2.0, 0.5)
	occluder_section[1].add_child(_make_field("Simplification (higher = fewer vertices)", simplify_row[0]))
	_occluder_simplify_slider = simplify_row[1]

	_occluder_info_label = _make_small_label("Occluder not generated yet.")
	occluder_section[1].add_child(_occluder_info_label)

	# Generate all button
	var gen_btn := _make_primary_button("Generate Normal + Shadow + Occluder")
	gen_btn.pressed.connect(_generate_normal_shadow_occluder)
	parent.add_child(gen_btn)

# Add to state variables:
var _2d_normal_container: VBoxContainer
var _normal_height_slider: HSlider
var _normal_invert_check: CheckButton
var _normal_preview_rect: TextureRect
var _shadow_offset_slider: HSlider
var _shadow_opacity_slider: HSlider
var _shadow_preview_rect: TextureRect
var _occluder_simplify_slider: HSlider
var _occluder_info_label: Label
```

**Step 2: Implement normal/shadow/occluder generation**

```gdscript
func _generate_normal_shadow_occluder() -> void:
	var angles: Array = ANGLE_CONFIGS[_angle_mode] if _source_mode == "3d" else [{ "name": "front", "suffix": "" }]
	_processed_color.clear()
	_processed_normal.clear()
	_processed_shadow.clear()
	_processed_occluder_points.clear()

	for angle_config in angles:
		var angle_name: String = angle_config["name"]

		# Get source image for this angle
		var source_color: Image
		if _source_mode == "3d":
			source_color = _captured_color.get(angle_name)
		else:
			source_color = _imported_image
		if source_color == null:
			continue

		# Process color
		var processed_color := _process_decoration_image(source_color)
		_processed_color[angle_name] = processed_color

		# Process normal map
		if _source_mode == "3d" and _captured_normal.has(angle_name):
			# 3D: downscale captured normal using bilinear interpolation
			var processed_normal := PixelArtProcessing.process_normal_map(
				_captured_normal[angle_name],
				processed_color.get_height(),
				int(_alpha_threshold_slider.value)
			)
			_processed_normal[angle_name] = processed_normal
		else:
			# 2D: generate normal map from luminance
			var generated_normal := _generate_normal_from_luminance(
				processed_color,
				_normal_height_slider.value,
				_normal_invert_check.button_pressed
			)
			_processed_normal[angle_name] = generated_normal

		# Process shadow
		if _source_mode == "3d" and _captured_shadow.has(angle_name):
			# 3D: downscale captured shadow
			var shadow := _captured_shadow[angle_name].duplicate() as Image
			var target_h := processed_color.get_height()
			var scale_f := float(target_h) / float(shadow.get_height())
			var target_w := int(float(shadow.get_width()) * scale_f)
			shadow.resize(target_w, target_h, Image.INTERPOLATE_NEAREST)
			PixelArtProcessing.apply_alpha_threshold(shadow, int(_alpha_threshold_slider.value))
			_processed_shadow[angle_name] = _apply_shadow_styling(shadow)
		else:
			# 2D: generate shadow from alpha silhouette
			_processed_shadow[angle_name] = _generate_shadow_from_alpha(processed_color)

		# Generate occluder polygon
		_processed_occluder_points[angle_name] = _trace_occluder_polygon(
			processed_color, _occluder_simplify_slider.value
		)

	# Update previews with first angle
	if not _processed_normal.is_empty():
		_normal_preview_rect.texture = ImageTexture.create_from_image(_processed_normal.values()[0])
	if not _processed_shadow.is_empty():
		_shadow_preview_rect.texture = ImageTexture.create_from_image(_processed_shadow.values()[0])
	if not _processed_occluder_points.is_empty():
		var points: PackedVector2Array = _processed_occluder_points.values()[0]
		_occluder_info_label.text = "Occluder: %d vertices" % points.size()

	_set_status("Generated normals, shadows, and occluders for %d angle(s)." % _processed_color.size())
```

**Step 3: Implement 2D normal map generation (Sobel filter)**

```gdscript
func _generate_normal_from_luminance(sprite: Image, height_scale: float, invert: bool) -> Image:
	## Generate a normal map from sprite luminance using Sobel filter.
	## Bright pixels = raised (or recessed if inverted).
	var w := sprite.get_width()
	var h := sprite.get_height()
	var normal := Image.create(w, h, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 0.0))  # Neutral normal, transparent

	for y in range(h):
		for x in range(w):
			if sprite.get_pixel(x, y).a < 0.5:
				continue
			# Sample luminance in 3x3 neighborhood
			var tl := _get_luminance(sprite, x - 1, y - 1)
			var tc := _get_luminance(sprite, x, y - 1)
			var tr := _get_luminance(sprite, x + 1, y - 1)
			var ml := _get_luminance(sprite, x - 1, y)
			var mr := _get_luminance(sprite, x + 1, y)
			var bl := _get_luminance(sprite, x - 1, y + 1)
			var bc := _get_luminance(sprite, x, y + 1)
			var br := _get_luminance(sprite, x + 1, y + 1)

			if invert:
				tl = 1.0 - tl; tc = 1.0 - tc; tr = 1.0 - tr
				ml = 1.0 - ml; mr = 1.0 - mr
				bl = 1.0 - bl; bc = 1.0 - bc; br = 1.0 - br

			# Sobel X and Y gradients
			var dx := (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)
			var dy := (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)
			dx *= height_scale
			dy *= height_scale

			# Compute normal vector
			var nx := -dx
			var ny := -dy
			var nz := 1.0
			var length := sqrt(nx * nx + ny * ny + nz * nz)
			if length > 0.001:
				nx /= length
				ny /= length
				nz /= length

			# Encode to RGB
			normal.set_pixel(x, y, Color(
				nx * 0.5 + 0.5,
				ny * 0.5 + 0.5,
				nz * 0.5 + 0.5,
				1.0
			))
	return normal


func _get_luminance(image: Image, x: int, y: int) -> float:
	x = clampi(x, 0, image.get_width() - 1)
	y = clampi(y, 0, image.get_height() - 1)
	var c := image.get_pixel(x, y)
	if c.a < 0.5:
		return 0.5  # Neutral for transparent pixels
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
```

**Step 4: Implement shadow generation from alpha**

```gdscript
func _generate_shadow_from_alpha(sprite: Image) -> Image:
	## Generate a baked shadow from the sprite's alpha silhouette.
	var w := sprite.get_width()
	var h := sprite.get_height()
	var offset_y := int(_shadow_offset_slider.value)
	var opacity := _shadow_opacity_slider.value
	var shadow := Image.create(w, h + abs(offset_y), false, Image.FORMAT_RGBA8)
	shadow.fill(Color.TRANSPARENT)

	for y in range(h):
		for x in range(w):
			if sprite.get_pixel(x, y).a >= 0.5:
				var sy := y + offset_y
				if sy >= 0 and sy < shadow.get_height():
					shadow.set_pixel(x, sy, Color(0, 0, 0, opacity))
	return shadow


func _apply_shadow_styling(shadow: Image) -> Image:
	## Apply shadow offset and opacity to an existing shadow image.
	var offset_y := int(_shadow_offset_slider.value)
	var opacity := _shadow_opacity_slider.value
	var w := shadow.get_width()
	var h := shadow.get_height()
	var result := Image.create(w, h, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	for y in range(h):
		for x in range(w):
			var c := shadow.get_pixel(x, y)
			if c.a > 0.1:
				var sy := y + offset_y
				if sy >= 0 and sy < h:
					result.set_pixel(x, sy, Color(0, 0, 0, opacity))
	return result
```

**Step 5: Implement occluder polygon tracing**

```gdscript
func _trace_occluder_polygon(sprite: Image, simplification: float) -> PackedVector2Array:
	## Trace the alpha outline of a sprite and return a simplified polygon.
	## Uses a simple edge-following algorithm + Douglas-Peucker simplification.
	var w := sprite.get_width()
	var h := sprite.get_height()
	var points: PackedVector2Array = PackedVector2Array()

	# Find all edge pixels (opaque with at least one transparent neighbor)
	var edge_pixels: Array[Vector2] = []
	for y in range(h):
		for x in range(w):
			if sprite.get_pixel(x, y).a < 0.5:
				continue
			var is_edge := (
				x == 0 or x == w - 1 or y == 0 or y == h - 1
				or sprite.get_pixel(x - 1, y).a < 0.5
				or sprite.get_pixel(x + 1, y).a < 0.5
				or sprite.get_pixel(x, y - 1).a < 0.5
				or sprite.get_pixel(x, y + 1).a < 0.5
			)
			if is_edge:
				edge_pixels.append(Vector2(x, y))

	if edge_pixels.is_empty():
		return points

	# Order edge pixels by angle from centroid (convex hull approximation)
	var centroid := Vector2.ZERO
	for p in edge_pixels:
		centroid += p
	centroid /= edge_pixels.size()

	edge_pixels.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a - centroid).angle() < (b - centroid).angle()
	)

	# Douglas-Peucker simplification
	points = PackedVector2Array(edge_pixels)
	points = _douglas_peucker(points, simplification)
	return points


func _douglas_peucker(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	# Find the point with max distance from the line between first and last
	var max_dist := 0.0
	var max_idx := 0
	var start := points[0]
	var end := points[points.size() - 1]
	for i in range(1, points.size() - 1):
		var dist := _point_line_distance(points[i], start, end)
		if dist > max_dist:
			max_dist = dist
			max_idx = i
	if max_dist > epsilon:
		var left := _douglas_peucker(points.slice(0, max_idx + 1), epsilon)
		var right := _douglas_peucker(points.slice(max_idx), epsilon)
		var result := PackedVector2Array()
		for i in range(left.size() - 1):
			result.append(left[i])
		for p in right:
			result.append(p)
		return result
	else:
		return PackedVector2Array([start, end])


func _point_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec := line_end - line_start
	var line_len := line_vec.length()
	if line_len < 0.001:
		return point.distance_to(line_start)
	var t := clampf((point - line_start).dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	var projection := line_start + t * line_vec
	return point.distance_to(projection)
```

**Step 6: Verify normal/shadow/occluder generation**

Test with both 3D and 2D sources:
- 3D: normals from capture, shadow from silhouette capture
- 2D: normals from Sobel filter, shadow from alpha
- Occluder polygon traces correctly with adjustable simplification
- Previews update

**Step 7: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 4 — normal/shadow/occluder generation"
```

---

## Task 7: Step 5 — Preview & Adjust

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Build Step 5 UI**

```gdscript
func _build_step5(parent: VBoxContainer) -> void:
	var section := _make_section("Composite Preview")
	parent.add_child(section[0])

	# Angle selector (for multi-angle)
	_preview_angle_toggle = _make_toggle_group(["front"], _on_preview_angle_changed)
	section[1].add_child(_preview_angle_toggle)

	# Layer toggles
	var layers_coll := _make_collapsible("Layer Visibility", true)
	section[1].add_child(layers_coll[0])

	_show_sprite_check = CheckButton.new()
	_show_sprite_check.text = "Sprite"
	_show_sprite_check.button_pressed = true
	_style_checkbutton_transparent(_show_sprite_check)
	_show_sprite_check.toggled.connect(func(_v: bool) -> void: _update_composite_preview())
	layers_coll[1].add_child(_show_sprite_check)

	_show_normal_check = CheckButton.new()
	_show_normal_check.text = "Normal Map"
	_show_normal_check.button_pressed = false
	_style_checkbutton_transparent(_show_normal_check)
	_show_normal_check.toggled.connect(func(_v: bool) -> void: _update_composite_preview())
	layers_coll[1].add_child(_show_normal_check)

	_show_shadow_check = CheckButton.new()
	_show_shadow_check.text = "Shadow"
	_show_shadow_check.button_pressed = true
	_style_checkbutton_transparent(_show_shadow_check)
	_show_shadow_check.toggled.connect(func(_v: bool) -> void: _update_composite_preview())
	layers_coll[1].add_child(_show_shadow_check)

	_show_occluder_check = CheckButton.new()
	_show_occluder_check.text = "Occluder Outline"
	_show_occluder_check.button_pressed = true
	_style_checkbutton_transparent(_show_occluder_check)
	_show_occluder_check.toggled.connect(func(_v: bool) -> void: _update_composite_preview())
	layers_coll[1].add_child(_show_occluder_check)

	# Composite preview image
	_composite_preview_rect = TextureRect.new()
	_composite_preview_rect.custom_minimum_size = Vector2(200, 200)
	_composite_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_composite_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	section[1].add_child(_composite_preview_rect)

	# Dimensions info
	_dimensions_label = _make_small_label("")
	section[1].add_child(_dimensions_label)

# Add to state variables:
var _preview_angle_toggle: HBoxContainer
var _show_sprite_check: CheckButton
var _show_normal_check: CheckButton
var _show_shadow_check: CheckButton
var _show_occluder_check: CheckButton
var _composite_preview_rect: TextureRect
var _dimensions_label: Label
var _current_preview_angle := "front"
```

**Step 2: Implement composite preview rendering**

```gdscript
func _on_preview_angle_changed(angle_name: String) -> void:
	_current_preview_angle = angle_name.to_lower()
	_update_composite_preview()


func _update_composite_preview() -> void:
	var angle := _current_preview_angle
	var color_img: Image = _processed_color.get(angle)
	if color_img == null:
		return

	var w := color_img.get_width()
	var h := color_img.get_height()
	# Create composite slightly larger to show shadow
	var composite := Image.create(w + 8, h + 8, false, Image.FORMAT_RGBA8)
	composite.fill(Color(0.2, 0.2, 0.3, 1.0))  # Dark background for visibility

	var offset := Vector2i(4, 4)

	# Shadow layer (behind sprite)
	if _show_shadow_check.button_pressed and _processed_shadow.has(angle):
		var shadow_img: Image = _processed_shadow[angle]
		for y in range(shadow_img.get_height()):
			for x in range(shadow_img.get_width()):
				var sc := shadow_img.get_pixel(x, y)
				if sc.a > 0.1:
					var px := x + offset.x
					var py := y + offset.y
					if px >= 0 and px < composite.get_width() and py >= 0 and py < composite.get_height():
						var bg := composite.get_pixel(px, py)
						var blended := Color(
							bg.r * (1.0 - sc.a) + sc.r * sc.a,
							bg.g * (1.0 - sc.a) + sc.g * sc.a,
							bg.b * (1.0 - sc.a) + sc.b * sc.a,
							1.0
						)
						composite.set_pixel(px, py, blended)

	# Sprite layer
	if _show_sprite_check.button_pressed:
		for y in range(h):
			for x in range(w):
				var c := color_img.get_pixel(x, y)
				if c.a >= 0.5:
					composite.set_pixel(x + offset.x, y + offset.y, Color(c.r, c.g, c.b, 1.0))

	# Normal map overlay (tinted visualization)
	if _show_normal_check.button_pressed and _processed_normal.has(angle):
		var normal_img: Image = _processed_normal[angle]
		for y in range(normal_img.get_height()):
			for x in range(normal_img.get_width()):
				var nc := normal_img.get_pixel(x, y)
				if nc.a >= 0.5:
					composite.set_pixel(x + offset.x, y + offset.y, Color(nc.r, nc.g, nc.b, 1.0))

	# Occluder outline overlay
	if _show_occluder_check.button_pressed and _processed_occluder_points.has(angle):
		var points: PackedVector2Array = _processed_occluder_points[angle]
		if points.size() >= 2:
			for i in range(points.size()):
				var from := points[i] + Vector2(offset)
				var to := points[(i + 1) % points.size()] + Vector2(offset)
				_draw_line_on_image(composite, from, to, Color.YELLOW)

	_composite_preview_rect.texture = ImageTexture.create_from_image(composite)
	_dimensions_label.text = "Sprite: %dx%d px" % [w, h]


func _draw_line_on_image(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	## Bresenham's line drawing on an Image.
	var x0 := int(from.x)
	var y0 := int(from.y)
	var x1 := int(to.x)
	var y1 := int(to.y)
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		if x0 >= 0 and x0 < image.get_width() and y0 >= 0 and y0 < image.get_height():
			image.set_pixel(x0, y0, color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
```

**Step 3: Update `_go_to_step()` to refresh preview on entering Step 5**

Add to `_go_to_step()`:

```gdscript
# In _go_to_step(), after updating visibility:
if step == 4:  # Step 5 (0-indexed = 4)
	# Update angle toggle buttons to match current angle mode
	_refresh_preview_angle_buttons()
	_update_composite_preview()
```

```gdscript
func _refresh_preview_angle_buttons() -> void:
	# Rebuild the angle toggle with current angle names
	var angles: Array = ANGLE_CONFIGS[_angle_mode] if _source_mode == "3d" else [{ "name": "front" }]
	var names: Array = []
	for a in angles:
		names.append(a["name"])
	# Clear and rebuild
	for child in _preview_angle_toggle.get_children():
		child.queue_free()
	var new_toggle := _make_toggle_group(names, _on_preview_angle_changed)
	# Re-parent children from new_toggle to existing container
	var children: Array[Node] = []
	for child in new_toggle.get_children():
		children.append(child)
	for child in children:
		new_toggle.remove_child(child)
		_preview_angle_toggle.add_child(child)
	_current_preview_angle = names[0] if names.size() > 0 else "front"
```

**Step 4: Verify preview works**

Navigate to Step 5, toggle layers on/off. Check:
- Sprite shows correctly
- Normal map overlay works
- Shadow renders behind sprite
- Occluder outline draws in yellow
- Switching angles updates preview

**Step 5: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 5 — composite preview"
```

---

## Task 8: Step 6 — Export & LDtk Atlas Generation

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Build Step 6 UI**

```gdscript
func _build_step6(parent: VBoxContainer) -> void:
	var section := _make_section("Export")
	parent.add_child(section[0])

	section[1].add_child(_make_small_label(
		"Exports sprite, normal, shadow, and occluder to assets/decorations/{id}/"
	))

	var export_btn := _make_primary_button("Export Decoration")
	export_btn.pressed.connect(_start_export)
	section[1].add_child(export_btn)

	# Atlas section
	var atlas_section := _make_section("LDtk Tileset Atlas")
	parent.add_child(atlas_section[0])

	atlas_section[1].add_child(_make_small_label(
		"Regenerates the decoration atlas from all assets/decorations/ folders."
	))

	var atlas_btn := _make_primary_button("Regenerate Atlas")
	atlas_btn.pressed.connect(_regenerate_atlas)
	atlas_section[1].add_child(atlas_btn)

	# Export log
	_export_log = RichTextLabel.new()
	_export_log.custom_minimum_size.y = 150
	_export_log.bbcode_enabled = true
	_export_log.scroll_following = true
	_export_log.add_theme_font_size_override("normal_font_size", FONT_HINT)
	parent.add_child(_export_log)

	# Done / Run Again buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	parent.add_child(btn_row)

	var again_btn := _make_subtle_button("Process Another")
	again_btn.pressed.connect(func() -> void: _go_to_step(0))
	btn_row.add_child(again_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(TOOLS_MENU_PATH)
	)
	btn_row.add_child(done_btn)

# Add to state variables:
var _export_log: RichTextLabel
```

**Step 2: Implement per-decoration export**

```gdscript
func _start_export() -> void:
	_export_log.clear()
	_append_log("[b]Starting export...[/b]")

	var angles: Array = ANGLE_CONFIGS[_angle_mode] if _source_mode == "3d" else [{ "name": "front", "suffix": "" }]

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
		var sprite_path := "%s/sprite.png" % output_dir
		var global_sprite := ProjectSettings.globalize_path(sprite_path)
		_processed_color[angle_name].save_png(global_sprite)
		_append_log("Saved: %s/sprite.png" % deco_id)

		# Save normal.png
		if _processed_normal.has(angle_name):
			var normal_path := "%s/normal.png" % output_dir
			var global_normal := ProjectSettings.globalize_path(normal_path)
			_processed_normal[angle_name].save_png(global_normal)
			_append_log("Saved: %s/normal.png" % deco_id)

		# Save shadow.png
		if _processed_shadow.has(angle_name):
			var shadow_path := "%s/shadow.png" % output_dir
			var global_shadow := ProjectSettings.globalize_path(shadow_path)
			_processed_shadow[angle_name].save_png(global_shadow)
			_append_log("Saved: %s/shadow.png" % deco_id)

		# Save occluder.tres
		if _processed_occluder_points.has(angle_name):
			var points: PackedVector2Array = _processed_occluder_points[angle_name]
			if points.size() >= 3:
				var occluder := OccluderPolygon2D.new()
				occluder.polygon = points
				var occluder_path := "%s/occluder.tres" % output_dir
				ResourceSaver.save(occluder, occluder_path)
				_append_log("Saved: %s/occluder.tres (%d vertices)" % [deco_id, points.size()])

	_append_log("")
	_append_log("[b]Export complete.[/b] Now regenerating atlas...")
	_regenerate_atlas()


func _append_log(text: String) -> void:
	_export_log.append_text(text + "\n")
```

**Step 3: Implement atlas generation**

```gdscript
const ATLAS_TILE_SIZE := 64  # Pixels per cell in the atlas grid
const ATLAS_COLUMNS := 8     # Max columns in the atlas

func _regenerate_atlas() -> void:
	var global_decos_dir := ProjectSettings.globalize_path(DECORATIONS_DIR)
	var dir := DirAccess.open(global_decos_dir)
	if dir == null:
		_append_log("[color=red]ERROR: Cannot open decorations directory.[/color]")
		return

	# Scan all decoration folders
	var deco_entries: Array[Dictionary] = []
	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and folder_name != "_atlas" and not folder_name.begins_with("."):
			var sprite_path := "%s/%s/sprite.png" % [DECORATIONS_DIR, folder_name]
			var global_sprite := ProjectSettings.globalize_path(sprite_path)
			var img := Image.load_from_file(global_sprite)
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

	# Sort by ID for stable ordering
	deco_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["decoration_id"] < b["decoration_id"]
	)

	if deco_entries.is_empty():
		_append_log("[color=yellow]No decorations found to atlas.[/color]")
		return

	# Calculate atlas dimensions
	var columns := mini(deco_entries.size(), ATLAS_COLUMNS)
	var rows := ceili(float(deco_entries.size()) / float(columns))
	var atlas_width := columns * ATLAS_TILE_SIZE
	var atlas_height := rows * ATLAS_TILE_SIZE

	# Create atlas image
	var atlas := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)

	# Build metadata
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

	var atlas_png_path := ProjectSettings.globalize_path(ATLAS_DIR + "/decoration_atlas.png")
	atlas.save_png(atlas_png_path)
	_append_log("Atlas saved: %s (%dx%d, %d decorations)" % [
		"_atlas/decoration_atlas.png", atlas_width, atlas_height, deco_entries.size()])

	# Save metadata JSON
	var json_path := ProjectSettings.globalize_path(ATLAS_DIR + "/decoration_atlas.json")
	var json_string := JSON.stringify(metadata, "  ")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		_append_log("Metadata saved: _atlas/decoration_atlas.json")

	_append_log("[color=green][b]Atlas generation complete![/b][/color]")
	_set_status("Export and atlas generation complete.")
```

**Step 4: Verify export and atlas generation**

Full end-to-end test:
1. Load a 3D model or 2D image
2. Step through all 6 steps
3. Export creates folder in `assets/decorations/{id}/` with all 4 files
4. Atlas regeneration creates `_atlas/decoration_atlas.png` + `.json`
5. Multi-angle creates suffixed folders correctly
6. Log shows all operations

**Step 5: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): implement decoration pipeline step 6 — export and LDtk atlas generation"
```

---

## Task 9: Wire Up Step Transitions & Polish

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

This task handles all the step transition logic — making sure data flows correctly between steps, the 2D path skips Step 2, and the preview refreshes when entering each step.

**Step 1: Update `_go_to_step()` with per-step entry logic**

```gdscript
func _go_to_step(step: int) -> void:
	if step < 0 or step >= STEP_NAMES.size():
		return
	_current_step = step
	step_indicator.set_current(step)
	for i in range(step_containers.size()):
		step_containers[i].visible = (i == step)
	back_button.disabled = (step == 0)
	next_button.text = "Export" if step == STEP_NAMES.size() - 1 else "Next ►"

	# Per-step entry logic
	match step:
		1:  # Capture step
			_capture_status_label.text = "Press capture to render from all selected angles."
		2:  # Pixel art processing
			_update_pixel_preview()
		3:  # Normal & Shadow
			_2d_normal_container.visible = (_source_mode == "2d")
		4:  # Preview
			_refresh_preview_angle_buttons()
			_update_composite_preview()
```

**Step 2: Update `_on_next_pressed()` with auto-processing triggers**

```gdscript
func _on_next_pressed() -> void:
	match _current_step:
		0:  # Source Selection → Capture/Import (or skip for 2D)
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
				_go_to_step(2)  # Skip capture for 2D
			else:
				_go_to_step(1)
			return
		1:  # Capture → Processing
			if _captured_color.is_empty():
				_set_status("Capture frames first.")
				return
		2:  # Processing → Normal/Shadow
			pass  # Processing done on-demand via preview button
		3:  # Normal/Shadow → Preview
			if _processed_color.is_empty():
				_set_status("Generate normals/shadows first.")
				return
		4:  # Preview → Export
			pass
		5:  # Export
			_start_export()
			return
	_go_to_step(_current_step + 1)
```

**Step 3: Ensure 3D viewport visibility toggles correctly**

The 3D viewport should only be visible during steps 0-1 (when in 3D mode). During processing/preview steps, the right panel should show 2D previews instead.

```gdscript
# In _go_to_step(), add viewport visibility management:
preview_container.visible = (_source_mode == "3d" and step <= 1)
```

**Step 4: Verify full wizard flow**

Test both paths end-to-end:
- **3D path**: Step 1 → 2 → 3 → 4 → 5 → 6 (all steps)
- **2D path**: Step 1 → 3 → 4 → 5 → 6 (skips Step 2)
- Back navigation works correctly for both paths
- Data persists between steps
- Status messages are helpful

**Step 5: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(tools): wire up decoration pipeline step transitions and polish"
```

---

## Task 10: Integration Testing & Documentation

**Files:**
- Modify: `docs/LDTK_MAP_REFERENCE.md` (add Decoration entity spec)

**Step 1: Test with real 3D model**

1. Place a `.glb` model in `assets/3d_imports/`
2. Launch Decoration Pipeline from Tools Menu
3. Select 3D Model, pick the model, set "4 Directions"
4. Capture → Process → Generate normals/shadow → Preview → Export
5. Verify all 4 suffixed folders created with complete asset sets
6. Verify atlas generated correctly

**Step 2: Test with 2D image**

1. Launch Decoration Pipeline
2. Switch to "2D Image" mode, browse a PNG
3. Process → Generate normals (Sobel) → Preview → Export
4. Verify decoration folder + atlas updated

**Step 3: Test atlas with existing decorations**

1. Ensure `test_pillar` and `test_rock` are included in atlas
2. Verify atlas PNG shows all decorations in grid
3. Verify JSON metadata is correct

**Step 4: Update LDtk Map Reference documentation**

Add a Decoration entity section to `docs/LDTK_MAP_REFERENCE.md`:

```markdown
### Decoration

Environmental decoration entity. Asset files are generated by the Decoration Pipeline tool.

**Fields:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `decoration_id` | String | (required) | Folder name in `assets/decorations/` |
| `scale` | Float | 1.0 | Size multiplier |
| `flip_x` | Boolean | false | Horizontal flip |
| `z_mode` | Enum | "y_sort" | Depth mode: "y_sort", "fixed_back", "fixed_front" |
| `shadow_mode` | Enum | "baked" | Shadow type: "baked", "realtime" |

**Asset Structure:**
```
assets/decorations/{decoration_id}/
├── sprite.png     (required)
├── normal.png     (optional — 2D lighting)
├── shadow.png     (optional — baked shadow)
└── occluder.tres  (optional — realtime shadow polygon)
```

**Tileset Atlas:**
The Decoration Pipeline generates `assets/decorations/_atlas/decoration_atlas.png` — a visual grid of all decorations. Register this as a tileset in LDtk to see decoration previews when placing entities.
```

**Step 5: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd docs/LDTK_MAP_REFERENCE.md
git commit -m "docs: add decoration entity spec and complete decoration pipeline"
```
