# Normal Map Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add normal map capture, processing, interactive light preview, and CanvasTexture-based SpriteFrames integration to the sprite pipeline wizard.

**Architecture:** During Step 2 (Capture), a second render pass captures view-space normals by overriding all mesh materials with a normal-output shader. Normal maps are processed minimally (bilinear downscale + alpha threshold + renormalize). A new Step 4 (Light Preview) provides an interactive SubViewport with a PointLight2D for QA. On export, `_normal.png` files are saved alongside color sheets. In Step 7 (Apply), CanvasTexture wraps diffuse + normal textures so AnimatedSprite2D automatically responds to 2D lights.

**Tech Stack:** Godot 4 GDScript, StandardMaterial3D/ShaderMaterial for normal capture, CanvasTexture + PointLight2D for 2D lighting, SubViewport for light preview

---

## Task 1: Create the Normal Capture Shader

**Files:**
- Create: `shaders/normal_capture.gdshader`

**Step 1: Create the shaders directory and shader file**

```gdshader
// shaders/normal_capture.gdshader
shader_type spatial;
render_mode unshaded;

void fragment() {
	ALBEDO = NORMAL * 0.5 + 0.5;
}
```

This encodes view-space normals as RGB color: (0.5, 0.5, 1.0) means a flat surface facing the camera (the standard "blue" in normal maps). The `unshaded` render mode ensures lighting doesn't affect the output.

**Step 2: Commit**

```bash
git add shaders/normal_capture.gdshader
git commit -m "feat: add normal map capture shader for sprite pipeline"
```

---

## Task 2: Add `process_normal_map()` to PixelArtProcessing

**Files:**
- Modify: `scripts/tools/pixel_art_processing.gd` (add new static method at end of file, after line 181)

**Step 1: Add the `process_normal_map` static function**

Append after the last function (`color_distance_sq` at line 180):

```gdscript
static func process_normal_map(source: Image, target_height: int, alpha_threshold: int) -> Image:
	## Process a raw normal map capture: bilinear downscale, alpha threshold,
	## re-normalize vectors, fill transparent pixels with neutral normal.
	var result := source.duplicate() as Image

	# Downscale using bilinear interpolation (smooth normals, not pixelated)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)

	# Apply alpha threshold to match color sprite silhouette exactly
	apply_alpha_threshold(result, alpha_threshold)

	# Re-normalize vectors (bilinear interpolation may denormalize them)
	# and fill transparent pixels with neutral normal (0.5, 0.5, 1.0)
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var color := result.get_pixel(x, y)
			if color.a < 0.5:
				# Neutral normal facing camera, fully transparent
				result.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.0))
			else:
				# Decode normal from RGB, normalize, re-encode
				var nx := color.r * 2.0 - 1.0
				var ny := color.g * 2.0 - 1.0
				var nz := color.b * 2.0 - 1.0
				var length := sqrt(nx * nx + ny * ny + nz * nz)
				if length > 0.001:
					nx /= length
					ny /= length
					nz /= length
				else:
					# Fallback to camera-facing normal
					nx = 0.0
					ny = 0.0
					nz = 1.0
				result.set_pixel(x, y, Color(
					nx * 0.5 + 0.5,
					ny * 0.5 + 0.5,
					nz * 0.5 + 0.5,
					1.0
				))

	return result
```

**Step 2: Commit**

```bash
git add scripts/tools/pixel_art_processing.gd
git commit -m "feat: add process_normal_map() to PixelArtProcessing utility"
```

---

## Task 3: Add Normal Map State and Capture Pass to Wizard

This is the largest task. It modifies `scripts/tools/sprite_pipeline.gd` to:
1. Add state variables for normal map sheets
2. Load the normal capture shader
3. Add a second render pass during capture
4. Save normal captures to disk alongside color captures

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add state variables for normal maps**

After line 72 (`var _captured_sheets: Dictionary = {}`) add:

```gdscript
var _captured_normal_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
```

After line 95 (`var _current_preset: Dictionary = {}`) add:

```gdscript
## Normal map capture shader — loaded once at startup
var _normal_capture_shader: Shader = null
var _normal_capture_material: ShaderMaterial = null
```

**Step 2: Load the normal capture shader in `_ready()`**

After `_build_viewport()` call (line 174), add shader loading:

```gdscript
func _ready() -> void:
	_build_ui()
	_build_viewport()
	# Load normal capture shader
	_normal_capture_shader = load("res://shaders/normal_capture.gdshader") as Shader
	if _normal_capture_shader:
		_normal_capture_material = ShaderMaterial.new()
		_normal_capture_material.shader = _normal_capture_shader
	await get_tree().process_frame
	_scan_models()
```

**Step 3: Add material override helpers**

After `_apply_unlit_materials()` (line 1421), add two new functions:

```gdscript
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


func _restore_unlit_materials() -> void:
	## Re-apply unlit materials after normal capture pass.
	if current_model_instance:
		_apply_unlit_materials(current_model_instance)
```

**Step 4: Modify `_capture_animation()` to add normal pass**

The current capture loop (lines 1625-1663) captures one frame at a time. After capturing the color frame (line 1663), we need to:
1. Swap to normal materials
2. Re-render the same frame
3. Blit into the normal sheet
4. Swap back to unlit materials

Replace the inner capture loop in `_capture_animation()`. The key section is inside `for frame_idx in range(frame_count):`, after the color blit at line 1663. Insert the normal pass:

```gdscript
		# --- Normal map pass: same camera position, normal capture materials ---
		if _normal_capture_material:
			_apply_normal_capture_materials(current_model_instance)
			# Re-seek animation (material swap may have caused a frame advance)
			current_anim_player.play(anim_name)
			current_anim_player.seek(seek_time, true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw

			var normal_frame := sub_viewport.get_texture().get_image()
			normal_frame.convert(Image.FORMAT_RGBA8)
			normal_sheet.blit_rect(normal_frame, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

			# Restore unlit materials for next color pass
			_apply_unlit_materials(current_model_instance)
```

Also, before the frame loop starts (after `sheet.fill(Color.TRANSPARENT)`), create the normal sheet:

```gdscript
		var normal_sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		normal_sheet.fill(Color(0.5, 0.5, 1.0, 0.0))  # Neutral normal, transparent
```

After `_captured_sheets[dir_name] = sheet`, save the normal sheet:

```gdscript
		_captured_normal_sheets[dir_name] = normal_sheet
```

**Step 5: Save normal captures to disk**

In the section that saves captures to disk (around line 1677-1680), add normal map saving after the color save loop:

```gdscript
	for dir_name in _captured_normal_sheets:
		var file_path := "%s/%s_%s_normal.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		_captured_normal_sheets[dir_name].save_png(global_path)
```

**Step 6: Clear normal sheets when clearing color sheets**

In `_start_capture()` (line 1585), add after `_captured_sheets.clear()`:

```gdscript
	_captured_normal_sheets.clear()
```

Also in `_on_run_again_pressed()` (line 1990) and `_on_done_pressed()` (line 1995), add:

```gdscript
	_captured_normal_sheets.clear()
```

**Step 7: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add normal map capture pass to sprite pipeline wizard"
```

---

## Task 4: Add Normal/Color/Lit Preview Toggle to Step 2 and Step 3

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add Step 2 toggle for Color/Normal preview**

Add a state variable in the wizard state section:

```gdscript
var _capture_preview_mode := "color"  # "color" or "normal"
```

In `_build_step2()` (around line 479), add toggle buttons before the direction previews:

```gdscript
func _build_step2(parent: VBoxContainer) -> void:
	# Preview mode toggle
	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(mode_hbox)
	var color_btn := Button.new()
	color_btn.text = "Color"
	color_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	color_btn.pressed.connect(func() -> void:
		_capture_preview_mode = "color"
		_update_capture_preview()
	)
	mode_hbox.add_child(color_btn)
	var normal_btn := Button.new()
	normal_btn.text = "Normal"
	normal_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	normal_btn.pressed.connect(func() -> void:
		_capture_preview_mode = "normal"
		_update_capture_preview()
	)
	mode_hbox.add_child(normal_btn)

	parent.add_child(_make_label("Capturing 3 directions..."))
	# ... rest of existing code
```

Add the `_update_capture_preview()` function:

```gdscript
func _update_capture_preview() -> void:
	var sheets := _captured_sheets if _capture_preview_mode == "color" else _captured_normal_sheets
	var rects := [capture_down_rect, capture_up_rect, capture_right_rect]
	var dir_names := ["down", "up", "right"]
	for i in range(3):
		if sheets.has(dir_names[i]):
			rects[i].texture = ImageTexture.create_from_image(sheets[dir_names[i]])
```

Update the existing capture preview assignment (at end of direction loop, line 1667-1668) to use this function too. After both loops finish and captures are saved:

```gdscript
	_update_capture_preview()
```

**Step 2: Add Step 3 preview mode toggle (Color/Normal/Lit)**

Add a state variable:

```gdscript
var _pixel_preview_mode := "color"  # "color", "normal", "lit"
```

In `_build_step3()`, after the direction buttons but before the output height (around line 539), add:

```gdscript
	# Preview mode toggle
	parent.add_child(_make_label("Preview mode:"))
	var pmode_hbox := HBoxContainer.new()
	pmode_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(pmode_hbox)
	for mode_name in ["Color", "Normal", "Lit"]:
		var btn := Button.new()
		btn.text = mode_name
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		var mode_key := mode_name.to_lower()
		btn.pressed.connect(func() -> void:
			_pixel_preview_mode = mode_key
			_update_pixel_preview()
		)
		pmode_hbox.add_child(btn)
```

**Step 3: Modify `_update_pixel_preview()` to handle modes**

Replace the current `_update_pixel_preview()` function (lines 1778-1787):

```gdscript
func _update_pixel_preview() -> void:
	if not _captured_sheets.has(_preview_direction):
		return
	if show_original_toggle.button_pressed:
		var source := _captured_sheets[_preview_direction] if _pixel_preview_mode != "normal" else _captured_normal_sheets.get(_preview_direction)
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
			# Simple inline lit preview — process both and show color
			# (Full interactive lighting is in Step 4)
			var processed := _process_image(_captured_sheets[_preview_direction])
			pixel_preview_rect.texture = ImageTexture.create_from_image(processed)
```

Note: The "lit" mode in Step 3 just shows color for now. The full interactive light preview is in the dedicated Step 4.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add color/normal/lit preview toggles to Steps 2 and 3"
```

---

## Task 5: Add the Light Preview Step (New Step 4)

This is the most complex new feature. It creates an interactive SubViewport with a Sprite2D using CanvasTexture and a draggable PointLight2D.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Shift step numbering**

The current step mapping is:
- 0: Model & Animation
- 1: Capture Preview
- 2: Pixel Art Settings
- 3: Export
- 4: Weapon Anchors
- 5: Apply to SpriteFrames

New mapping (7 steps):
- 0: Model & Animation
- 1: Capture Preview
- 2: Pixel Art Settings
- 3: **Light Preview** (NEW)
- 4: Export
- 5: Weapon Anchors
- 6: Apply to SpriteFrames

**Changes required:**
1. `_build_ui()`: Add a 7th step container (step7) between the existing step4 and step5. Reorder `_build_step*` calls.
2. `_go_to_step()`: Update `step_names` array, step count (6 → 7), next_button text condition, visibility logic.
3. `_on_next_pressed()`: Update step indices — export check is now step 4 not 3, anchor skip goes to 6 not 5.
4. `_on_back_pressed()`: Update skip logic — apply step is now 6, check for anchor skip accordingly.
5. All internal references to step indices.

In `_build_ui()`, the 6 step containers become 7. Add after the current step4 (which becomes the light preview step):

```gdscript
	# Build 7 step containers
	# ... existing step1-3 ...

	var step4 := VBoxContainer.new()  # Light Preview (NEW)
	step4.add_theme_constant_override("separation", 8)
	step4.visible = false
	vbox.add_child(step4)
	_step_containers.append(step4)

	var step5 := VBoxContainer.new()  # Export (was step4)
	step5.add_theme_constant_override("separation", 8)
	step5.visible = false
	vbox.add_child(step5)
	_step_containers.append(step5)

	var step6 := VBoxContainer.new()  # Weapon Anchors (was step5)
	step6.add_theme_constant_override("separation", 8)
	step6.visible = false
	vbox.add_child(step6)
	_step_containers.append(step6)

	var step7 := VBoxContainer.new()  # Apply (was step6)
	step7.add_theme_constant_override("separation", 8)
	step7.visible = false
	vbox.add_child(step7)
	_step_containers.append(step7)

	_build_step1(step1)
	_build_step2(step2)
	_build_step3(step3)
	_build_step_light_preview(step4)  # NEW
	_build_step4(step5)               # Export — renamed internally
	_build_step_anchors(step6)
	_build_step6(step7)               # Apply
```

**Step 2: Update `_go_to_step()` navigation**

```gdscript
func _go_to_step(step: int) -> void:
	_current_step = step
	for i in range(_step_containers.size()):
		_step_containers[i].visible = (i == step)
	back_button.visible = step > 0
	next_button.visible = (step < 6)
	next_button.text = "Export" if step == 4 else "Next"
	var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Settings",
		"Light Preview", "Export", "Weapon Anchors", "Apply to SpriteFrames"]
	step_indicator_label.text = "Step %d of 7: %s" % [step + 1, step_names[step]]
	var viewport_area := preview_container.get_parent()
	viewport_area.visible = (step <= 1)
	pixel_preview_rect.get_parent().visible = (step == 2)
	if anchor_frame_display:
		anchor_frame_display.visible = (step == 5)
	# Light preview viewport visibility
	if _light_preview_container:
		_light_preview_container.visible = (step == 3)
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
```

**Step 3: Update `_on_next_pressed()` and `_on_back_pressed()`**

```gdscript
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
```

**Step 4: Add Light Preview state variables**

In the wizard state section, add:

```gdscript
## Step 3 (Light Preview) state
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
```

**Step 5: Build the Light Preview step UI**

Add new function `_build_step_light_preview()`:

```gdscript
func _build_step_light_preview(parent: VBoxContainer) -> void:
	parent.add_child(_make_label("Light Preview"))
	parent.add_child(_make_label("Drag the light around to test normal maps."))

	# Direction buttons
	parent.add_child(_make_label("Direction:"))
	var dir_hbox := HBoxContainer.new()
	dir_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(dir_hbox)
	for dir_name in ["down", "up", "right"]:
		var btn := Button.new()
		btn.text = dir_name.capitalize()
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.pressed.connect(_on_light_preview_direction.bind(dir_name))
		dir_hbox.add_child(btn)

	# Frame navigation
	var frame_hbox := HBoxContainer.new()
	frame_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(frame_hbox)
	var prev_btn := Button.new()
	prev_btn.text = "<"
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
	next_frame_btn.text = ">"
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

	parent.add_child(HSeparator.new())

	# Light controls
	parent.add_child(_make_label("Light Color:"))
	_light_color_picker = ColorPickerButton.new()
	_light_color_picker.color = Color("#FFAA44")  # Warm torch default
	_light_color_picker.custom_minimum_size = Vector2(60, 30)
	_light_color_picker.color_changed.connect(func(c: Color) -> void:
		if _light_preview_light:
			_light_preview_light.color = c
	)
	parent.add_child(_light_color_picker)

	parent.add_child(_make_label("Intensity:"))
	_light_intensity_slider = HSlider.new()
	_light_intensity_slider.min_value = 0.0
	_light_intensity_slider.max_value = 3.0
	_light_intensity_slider.value = 1.5
	_light_intensity_slider.step = 0.1
	_light_intensity_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_intensity_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.energy = v
	)
	parent.add_child(_light_intensity_slider)

	parent.add_child(_make_label("Height:"))
	_light_height_slider = HSlider.new()
	_light_height_slider.min_value = 0.0
	_light_height_slider.max_value = 200.0
	_light_height_slider.value = 50.0
	_light_height_slider.step = 5.0
	_light_height_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_height_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.height = v
	)
	parent.add_child(_light_height_slider)

	parent.add_child(_make_label("Ambient:"))
	_light_ambient_slider = HSlider.new()
	_light_ambient_slider.min_value = 0.0
	_light_ambient_slider.max_value = 1.0
	_light_ambient_slider.value = 0.2
	_light_ambient_slider.step = 0.05
	_light_ambient_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_ambient_slider.value_changed.connect(func(_v: float) -> void:
		_update_light_preview_ambient()
	)
	parent.add_child(_light_ambient_slider)

	parent.add_child(HSeparator.new())

	# Presets
	parent.add_child(_make_label("Light presets:"))
	var preset_hbox := HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 4)
	parent.add_child(preset_hbox)

	var presets := {
		"Torch": {"color": Color("#FFAA44"), "intensity": 1.5, "height": 50.0, "ambient": 0.2},
		"Sunlight": {"color": Color("#FFFDE0"), "intensity": 1.0, "height": 150.0, "ambient": 0.4},
		"Moonlight": {"color": Color("#8899CC"), "intensity": 0.8, "height": 120.0, "ambient": 0.15},
		"Spell": {"color": Color("#44FFDD"), "intensity": 2.0, "height": 30.0, "ambient": 0.1},
	}
	for preset_name in presets:
		var btn := Button.new()
		btn.text = preset_name
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		var preset_data: Dictionary = presets[preset_name]
		btn.pressed.connect(_apply_light_preset.bind(preset_data))
		preset_hbox.add_child(btn)
```

**Step 6: Add light preview viewport to the right panel**

In `_build_ui()`, after the anchor_frame_display is added to `right_vbox` (line 333), add:

```gdscript
	# Light preview viewport (Step 3 — Light Preview), initially hidden
	_light_preview_container = SubViewportContainer.new()
	_light_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	_light_preview_container.stretch = true
	_light_preview_container.visible = false
	right_vbox.add_child(_light_preview_container)
```

**Step 7: Add the light preview setup and interaction functions**

```gdscript
func _setup_light_preview() -> void:
	## Build or update the light preview SubViewport with current processed sprites.
	# Clean up previous viewport contents
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
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
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
	_light_preview_frame_count = color_processed.get_width() / int(output_height_spin.value)
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
	_light_preview_sprite.position = Vector2(200, 200)  # Center of viewport
	_light_preview_sprite.scale = Vector2(3, 3)  # Scale up for visibility
	_light_preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_light_preview_viewport.add_child(_light_preview_sprite)

	# Create point light
	_light_preview_light = PointLight2D.new()
	_light_preview_light.position = Vector2(250, 150)
	_light_preview_light.color = _light_color_picker.color
	_light_preview_light.energy = _light_intensity_slider.value
	_light_preview_light.height = _light_height_slider.value
	# Create a soft circular light texture
	var light_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var dx := (x - 64.0) / 64.0
			var dy := (y - 64.0) / 64.0
			var dist := sqrt(dx * dx + dy * dy)
			var alpha := clampf(1.0 - dist, 0.0, 1.0)
			light_img.set_pixel(x, y, Color(1, 1, 1, alpha))
	_light_preview_light.texture = ImageTexture.create_from_image(light_img)
	_light_preview_light.texture_scale = 4.0
	_light_preview_viewport.add_child(_light_preview_light)

	_update_light_preview_ambient()
	_update_light_preview_frame()

	# Connect input for dragging
	_light_preview_container.gui_input.connect(_on_light_preview_input)


func _on_light_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _light_preview_light and _light_preview_container:
			var local_pos := event.position
			# Convert container coordinates to viewport coordinates
			var container_size := _light_preview_container.size
			var viewport_size := Vector2(_light_preview_viewport.size)
			_light_preview_light.position = Vector2(
				(local_pos.x / container_size.x) * viewport_size.x,
				(local_pos.y / container_size.y) * viewport_size.y
			)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _light_preview_light and _light_preview_container:
			var local_pos := event.position
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
	## Simulate ambient light by setting the sprite's self_modulate.
	## With ambient=0.2, the sprite is 20% visible even in unlit areas.
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
```

**Step 8: Add animation playback in `_process()`**

Add or modify `_process()` to handle light preview animation:

```gdscript
func _process(delta: float) -> void:
	if _light_preview_playing and _current_step == 3:
		_light_preview_timer += delta
		var fps := 15.0  # Default preview FPS
		if _light_preview_timer >= 1.0 / fps:
			_light_preview_timer -= 1.0 / fps
			_light_preview_frame = (_light_preview_frame + 1) % _light_preview_frame_count
			_update_light_preview_frame()
```

**Step 9: Disconnect light preview input when leaving step**

In `_setup_light_preview()`, guard against double-connecting by checking if already connected:

```gdscript
	if not _light_preview_container.gui_input.is_connected(_on_light_preview_input):
		_light_preview_container.gui_input.connect(_on_light_preview_input)
```

**Step 10: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add interactive light preview step to sprite pipeline wizard"
```

---

## Task 6: Update Export Step to Save Normal Maps

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — `_start_export()` function (around line 1949)

**Step 1: Add normal map export alongside color export**

In `_start_export()`, after the color export loop, add:

```gdscript
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

	_append_log("\nExported %d color + %d normal files to %s/" % [count, normal_count, output_dir])
```

**Step 2: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: export normal map PNGs alongside color sheets"
```

---

## Task 7: Update Apply to SpriteFrames with CanvasTexture

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — `_try_add_export_folder()` and `_apply_to_spriteframes()` functions

**Step 1: Filter out `_normal.png` from direction file scanning**

In `_try_add_export_folder()` (around line 2074-2082), modify the file scanning to exclude normal maps from the direction_files dict:

```gdscript
	while file_name != "":
		if file_name.ends_with(".png") and not file_name.ends_with(".png.import") and not file_name.ends_with("_normal.png"):
			for dir_info in DIRECTIONS:
				var dir_name: String = dir_info["name"]
				if file_name.ends_with("_%s.png" % dir_name):
					direction_files[dir_name] = file_name
					break
		file_name = sub_dir.get_next()
```

**Step 2: Modify `_apply_to_spriteframes()` to use CanvasTexture**

In the animation application loop (around line 2140-2166), replace the simple ImageTexture with a CanvasTexture:

```gdscript
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

			if frames.has_animation(anim_name):
				frames.remove_animation(anim_name)
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			frames.set_animation_loop(anim_name, loop)

			# Check for corresponding normal map
			var normal_filename := sheet_filename.replace(".png", "_normal.png") \
				if not sheet_filename.ends_with("_normal.png") \
				else ""
			# Actually: normal file is e.g. "walk_down_normal.png" for "walk_down.png"
			# The color file is "{anim}_{dir}.png", normal is "{anim}_{dir}_normal.png"
			var normal_path := "%s/%s/%s" % [OUTPUT_BASE, folder, normal_filename]
			var normal_abs_path := ProjectSettings.globalize_path(normal_path)
			var normal_image: Image = null
			if not normal_filename.is_empty():
				normal_image = Image.load_from_file(normal_abs_path)

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
```

The key change: instead of `atlas_tex.atlas = sheet_texture` (plain ImageTexture), we now set it to a `CanvasTexture` that pairs diffuse + normal. The `AtlasTexture.region` still works the same — it slices from the CanvasTexture's diffuse, and Godot automatically applies the same region to the normal texture.

**Step 3: Derive normal filename correctly**

The normal filename needs careful construction. For a color file like `slash_down.png`, the normal file is `slash_down_normal.png`. The current code derives the direction from the filename suffix (`_down.png`). The normal equivalent just inserts `_normal` before `.png`:

```gdscript
			var normal_filename := sheet_filename.get_basename() + "_normal.png"
```

This is cleaner. Use `.get_basename()` which strips the extension.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: apply CanvasTexture (diffuse + normal) to SpriteFrames"
```

---

## Task 8: Update Documentation

**Files:**
- Modify: `docs/PLACEHOLDER_SPRITES.md`

**Step 1: Add Normal Map section to documentation**

Add a section covering:
- Normal map capture (automatic during Step 2)
- Normal map processing (clean bilinear normals)
- Light preview step (Step 4)
- File output format (`_normal.png` files)
- CanvasTexture integration (automatic in Step 7)
- How to add Light2D nodes to game zones to see lighting in-game

**Step 2: Update the step numbering**

The doc currently references 6 steps. Update to 7 steps, inserting Light Preview as Step 4.

**Step 3: Commit**

```bash
git add docs/PLACEHOLDER_SPRITES.md
git commit -m "docs: update sprite pipeline documentation for normal map integration"
```

---

## Task 9: Manual Testing Checklist

This task is not code — it's a verification checklist. Run through the complete wizard with a 3D model.

**Pre-requisites:**
- A `.glb` or `.fbx` file in `assets/3d_imports/`
- The project running in the Godot editor

**Test cases:**

1. **Step 1:** Select model, select animation — should work as before
2. **Step 2:** Capture should now take slightly longer (two passes). Toggle between Color/Normal views. Normal captures should show blue/purple/green colors.
3. **Step 3:** Toggle between Color/Normal/Lit preview modes. Normal mode shows the processed normal map. Color mode works as before.
4. **Step 4 (Light Preview):**
   - Sprite should appear with dark background
   - Drag mouse — light should follow cursor
   - Frame navigation (< / >) should step through frames
   - Play button should animate
   - Light presets (Torch/Sunlight/Moonlight/Spell) should change color/intensity
   - Ambient slider should brighten/darken unlit areas
   - Direction buttons should switch between down/up/right
5. **Step 5 (Export):** Should save both `_normal.png` and color `.png` files
6. **Step 6 (Weapon Anchors):** Should work unchanged
7. **Step 7 (Apply):** Log should show `+ normal map:` lines. SpriteFrames resource should contain CanvasTexture sub-resources.

**Verification:** After applying, add a `PointLight2D` to a game zone scene and confirm the character sprite responds to the light.
