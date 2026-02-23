# Sprite Pipeline Wizard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a 4-step wizard tool that chains 3D sprite capture and pixel art conversion into a single linear flow with saveable presets.

**Architecture:** A single GDScript tool (`sprite_pipeline.gd`) attached to a minimal scene. The wizard uses a step-based UI where each step is a VBoxContainer shown/hidden via `visible`. Logic is copied from `sprite_capture.gd` (3D capture) and `pixel_art_converter.gd` (image processing) — both remain standalone. Presets are saved as JSON files.

**Tech Stack:** GDScript, Godot 4 Image API, SubViewport for 3D preview, JSON for presets

---

## Reference Files

Before starting any task, read these for context:

- `scripts/tools/sprite_capture.gd` — Source for 3D viewport, camera, model loading, animation capture logic
- `scripts/tools/pixel_art_converter.gd` — Source for image processing pipeline (downscale, threshold, dithering, palette, outline, denoising)
- `scenes/tools/sprite_capture.tscn` — Scene structure pattern (minimal: root Control + script)
- `docs/plans/2026-02-21-sprite-pipeline-wizard-design.md` — Full design doc

## Important Conventions

- GDScript (not C#)
- Tool scenes are run directly with F6
- UI built entirely in code (`_build_ui()`) — no editor-created nodes
- File paths use `res://`; use `ProjectSettings.globalize_path()` for disk I/O
- Use explicit type annotations for variables inferred from Variant (e.g., `var x: float = array[i]`, `var v: Vector2i = queue.pop_back()`)
- Spritesheets are horizontal strips: width = frame_size * frame_count, height = frame_size

---

### Task 1: Scaffold — Scene file + wizard step container + Step 1 UI

**Files:**
- Create: `scenes/tools/sprite_pipeline.tscn`
- Create: `scripts/tools/sprite_pipeline.gd`

**Step 1: Create the scene file**

Create `scenes/tools/sprite_pipeline.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/tools/sprite_pipeline.gd" id="1"]

[node name="SpritePipelineRoot" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

**Step 2: Create the script with wizard framework + Step 1 UI**

Create `scripts/tools/sprite_pipeline.gd` with this structure:

```gdscript
extends Control
## Sprite Pipeline Wizard
##
## Unified tool that chains 3D sprite capture and pixel art conversion
## into a single 4-step wizard flow with saveable presets.
##
## Steps:
##   1. Model & Animation — select model, pick animation, configure camera
##   2. Capture Preview — auto-capture all 3 directions, confirm
##   3. Pixel Art Settings — configure processing, preview result
##   4. Export — process all directions, save final pixel art
##
## Run: scenes/tools/sprite_pipeline.tscn (F6)
```

Constants:
```gdscript
const IMPORT_DIR := "res://assets/3d_imports"
const CAPTURES_DIR := "res://assets/sprites/captures"
const OUTPUT_BASE := "res://assets/sprites/final"
const PALETTE_DIR := "res://assets/palettes"
const PRESETS_DIR := "res://assets/sprites/presets"

const DIRECTIONS := [
    { "name": "down", "rotation_y": 0.0 },
    { "name": "up", "rotation_y": 180.0 },
    { "name": "right", "rotation_y": 90.0 },
]
```

Wizard state:
```gdscript
var _current_step := 0  # 0-3
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

## Preset
var _current_preset: Dictionary = {}
```

Node references — declare all needed for all steps:
```gdscript
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

# Shared
var status_label: Label
var back_button: Button
var next_button: Button
```

`_ready()` → calls `_build_ui()` then `_scan_models()`

`_build_ui()` builds the full layout:
- Root HBoxContainer (full rect)
- Left panel: PanelContainer > ScrollContainer > VBoxContainer with:
  - Title label "Sprite Pipeline"
  - Step indicator label (e.g., "Step 1 of 4: Model & Animation")
  - HSeparator
  - **4 VBoxContainers** (one per step) — only one visible at a time
  - HSeparator
  - Navigation row (HBoxContainer): Back button + Next/Export button
  - Status label (autowrap)
- Right side: split into two areas stacked vertically:
  - Top: SubViewportContainer (for 3D preview in steps 1-2) — wrapped in AspectRatioContainer ratio=1.0
  - Bottom: (reserved for 2D preview in step 3, hidden in steps 1-2)

**Step 1 container** (`_build_step1(parent_vbox)`) builds into its VBoxContainer:
- Model dropdown + label
- Animation dropdown + label
- Frame count SpinBox (min 2, max 60, default 24)
- HSeparator
- Preset status label "(no preset)" / "(preset loaded)"
- Camera settings label + toggle button "Show Camera Settings"
- Camera settings container (VBoxContainer, initially hidden):
  - Elevation slider (10-80, default 40) + value label
  - Zoom slider (0.5-15, default 3.5) + value label
  - Target height slider (0-5, default 1.0) + value label
  - Direction preview buttons (Front/Back/Side)
  - "Save Camera Preset" button

Wire signals:
- `model_dropdown.item_selected` → `_on_model_selected`
- `anim_dropdown.item_selected` → `_on_animation_selected`
- Camera sliders → update camera position + labels in real time
- Toggle camera settings → `camera_settings_container.visible = !visible`
- Save preset button → `_save_preset()`
- Next button → `_go_to_step(1)`
- Back button → `_go_to_step(_current_step - 1)`

`_go_to_step(step: int)`:
```gdscript
func _go_to_step(step: int) -> void:
    _current_step = step
    for i in range(_step_containers.size()):
        _step_containers[i].visible = (i == step)
    # Update navigation buttons
    back_button.visible = step > 0
    next_button.text = "Export" if step == 3 else "Next"
    # Update step indicator
    var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Settings", "Export"]
    step_indicator_label.text = "Step %d of 4: %s" % [step + 1, step_names[step]]
    # Trigger step-specific logic
    match step:
        1: _start_capture()
        3: _start_export()
    # Update preview visibility
    preview_container.get_parent().visible = (step <= 1)
    pixel_preview_rect.get_parent().visible = (step == 2)
```

Copy from `sprite_capture.gd` (adapt to use wizard's variables):
- `_build_viewport()` — SubViewport + Camera3D + lights + model_slot (identical)
- `_scan_models()` — scans `IMPORT_DIR`, populates model_dropdown
- `_on_model_selected(index)` — loads model, applies unlit materials, populates animations, loads preset
- `_clear_model()` — frees model instance
- `_find_animation_player(node)` — recursive search
- `_populate_animations()` — lists animations
- `_on_animation_selected(index)` — plays animation
- `_apply_unlit_materials(node)` — recursive material override
- `_position_camera(elevation_deg)` — positions camera at elevation angle
- Camera slider callbacks

Add preset loading in `_on_model_selected()`:
```gdscript
# After loading model, check for preset
var model_name := current_model_path.get_file().get_basename()
_load_preset(model_name)
```

`_make_label()`, `_set_status()` — same as before.

**Step 3: Verify**

Run the scene (F6):
- UI shows "Step 1 of 4: Model & Animation"
- Model dropdown lists .glb files
- Camera settings toggle works
- 3D preview shows model
- Next button advances (steps 2-4 are empty containers for now)
- Back button returns

**Step 4: Commit**

```bash
git add scenes/tools/sprite_pipeline.tscn scripts/tools/sprite_pipeline.gd
git commit -m "feat: scaffold sprite pipeline wizard with Step 1 UI"
```

---

### Task 2: Preset system — save/load JSON presets

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Implement preset save**

```gdscript
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
    # pixel_art settings saved separately in Step 3

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
```

**Step 2: Implement preset load**

```gdscript
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
```

`_apply_pixel_art_preset()` will be implemented in Task 4 when Step 3 UI exists. For now, make it a stub:
```gdscript
func _apply_pixel_art_preset(settings: Dictionary) -> void:
    pass  # Implemented in Task 4
```

Call `_load_preset(model_name)` at the end of `_on_model_selected()`.

**Step 3: Verify**

- Run, select model, adjust camera, click "Save Camera Preset"
- Check `assets/sprites/presets/` for JSON file
- Close and reopen — preset should auto-load, label shows "(preset loaded)"

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add JSON preset save/load system"
```

---

### Task 3: Step 2 — Capture Preview

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Build Step 2 UI**

`_build_step2(parent_vbox)` adds to its VBoxContainer:
- Label "Capturing 3 directions..."
- For each direction (down/up/right):
  - Label with direction name
  - TextureRect (TEXTURE_FILTER_NEAREST, expand fit width) — `capture_down_rect`, `capture_up_rect`, `capture_right_rect`
- These show the raw captured spritesheets

**Step 2: Implement capture logic**

Copy `_export_animation()` from `sprite_capture.gd` but adapt it to store Images in memory instead of saving to disk. Call it `_capture_animation()`:

```gdscript
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

    # Also save intermediate captures to disk
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
```

**Step 3: Verify**

- Run, select model and animation, click Next
- Step 2 shows 3 captured spritesheet strips
- Back returns to Step 1, Next advances to Step 3

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add Step 2 capture preview with 3 directions"
```

---

### Task 4: Step 3 — Pixel Art Settings + live preview

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Build Step 3 UI**

`_build_step3(parent_vbox)` adds to its VBoxContainer:
- Output height SpinBox (16-256, default 64, step 8) + label
- Alpha threshold slider (0-255, default 128) + value label
- HSeparator
- Palette mode dropdown: items "None", "Load from Palettes", "Generate from Captures"
- Palette file dropdown (initially hidden, shown when "Load from Palettes" selected)
- Max palette colors SpinBox (default 32) + "Generate" button (initially hidden, shown when "Generate from Captures" selected)
- Palette preview swatches (HFlowContainer)
- HSeparator
- Dithering CheckButton + strength slider (0-1, default 0.5) + pattern dropdown (2x2/4x4/8x8)
- Outline CheckButton + color picker (default black)
- Denoising CheckButton + min cluster SpinBox (default 2)
- HSeparator
- "Save Settings to Preset" button
- Show Original CheckButton

Wire all setting changes to `_update_pixel_preview()`.

Palette mode dropdown signal handler:
```gdscript
func _on_palette_mode_changed(index: int) -> void:
    # 0=None, 1=Load from Palettes, 2=Generate from Captures
    palette_file_dropdown.visible = (index == 1)
    generate_palette_button.visible = (index == 2)
    max_palette_colors_spin.visible = (index == 2)
    if index == 0:
        _palette_colors.clear()
        _update_palette_preview()
    _update_pixel_preview()
```

**Step 2: Copy image processing functions from pixel_art_converter.gd**

Copy these functions verbatim (they operate on Image objects with explicit parameters, no UI dependencies once the parameters are extracted):
- `_apply_alpha_threshold(image, threshold)`
- `_apply_ordered_dithering(image, strength, pattern_index)` + Bayer constants
- `_apply_palette_mapping(image)`
- `_find_nearest_palette_color(target)`
- `_color_distance_sq(a, b)`
- `_apply_outline(image, outline_color)`
- `_apply_denoising(image, min_cluster_size)`

Add the combined pipeline:
```gdscript
func _process_image(source: Image) -> Image:
    var result := source.duplicate() as Image

    var target_height := int(output_height_spin.value)
    var scale_factor := float(target_height) / float(result.get_height())
    var target_width := int(float(result.get_width()) * scale_factor)
    result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

    _apply_alpha_threshold(result, int(alpha_threshold_slider.value))

    if dithering_toggle.button_pressed and not _palette_colors.is_empty():
        _apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

    _apply_palette_mapping(result)

    if outline_toggle.button_pressed:
        _apply_outline(result, outline_color_picker.color)

    if denoising_toggle.button_pressed:
        _apply_denoising(result, int(denoising_min_cluster_spin.value))

    return result
```

**Step 3: Implement pixel preview**

```gdscript
func _update_pixel_preview() -> void:
    if not _captured_sheets.has("down"):
        return
    if show_original_toggle.button_pressed:
        var tex := ImageTexture.create_from_image(_captured_sheets["down"])
        pixel_preview_rect.texture = tex
        return
    var processed := _process_image(_captured_sheets["down"])
    var tex := ImageTexture.create_from_image(processed)
    pixel_preview_rect.texture = tex
```

When entering Step 3 (in `_go_to_step`), call `_update_pixel_preview()`. Also scan palettes at this point:
```gdscript
2:
    _scan_palettes()
    _update_pixel_preview()
```

**Step 4: Implement palette loading + generation**

Copy palette logic from `pixel_art_converter.gd`:
- `_scan_palettes()` — scans `PALETTE_DIR`, populates `palette_file_dropdown`
- `_load_palette_from_path(path)` — loads PNG palette
- `_update_palette_preview()` — ColorRect swatches

For palette file dropdown selection:
```gdscript
func _on_palette_file_selected(index: int) -> void:
    if index < 0:
        return
    var palette_name: String = palette_file_dropdown.get_item_text(index)
    var palette_path := "%s/%s" % [PALETTE_DIR, palette_name]
    var global_path := ProjectSettings.globalize_path(palette_path)
    _load_palette_from_path(global_path)
```

For "Generate" button — adapt `_on_generate_palette_pressed()` from `pixel_art_converter.gd` but use `_captured_sheets` instead of scanning disk:
```gdscript
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
```

**Step 5: Implement `_apply_pixel_art_preset()`**

Replace the stub with:
```gdscript
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
```

Add "Save Settings to Preset" button handler:
```gdscript
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
```

**Step 6: Verify**

- Run, go through Steps 1-2, reach Step 3
- All pixel art controls visible and interactive
- Preview updates live as settings change
- Palette generation works using captured sheets
- "Load from Palettes" dropdown lists palettes from assets/palettes/
- "Save Settings to Preset" updates the JSON file
- Back returns to Step 2, Next/Export advances to Step 4

**Step 7: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add Step 3 pixel art settings with live preview"
```

---

### Task 5: Step 4 — Export + Run Again

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Build Step 4 UI**

`_build_step4(parent_vbox)` adds to its VBoxContainer:
- Label "Exporting..."
- `export_log_label` — multi-line label (autowrap) showing progress
- HSeparator
- "Run Again" button → goes back to Step 1 with same model
- "Done" button → resets wizard completely

**Step 2: Implement export**

```gdscript
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


func _append_log(text: String) -> void:
    export_log_label.text += text + "\n"
    print("[SpritePipeline] %s" % text)
```

Wire "Run Again" to:
```gdscript
func _on_run_again_pressed() -> void:
    _captured_sheets.clear()
    _go_to_step(0)
```

Wire "Done" to:
```gdscript
func _on_done_pressed() -> void:
    _captured_sheets.clear()
    _palette_colors.clear()
    _clear_model()
    _go_to_step(0)
    _scan_models()
```

**Step 3: Verify**

- Full wizard flow: Step 1 (select model) → Step 2 (capture) → Step 3 (configure) → Step 4 (export)
- Check `assets/sprites/final/{model}/` for exported pixel art PNGs
- "Run Again" keeps model selected, returns to Step 1 for next animation
- "Done" resets everything

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add Step 4 export with run-again flow"
```

---

### Task 6: Preview visibility + polish

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Fix preview panel visibility per step**

The right side has two preview areas:
- 3D viewport (SubViewportContainer) — visible in Steps 1 and 2
- 2D pixel preview (TextureRect in ScrollContainer) — visible in Step 3
- Neither in Step 4 (or show export log full width)

Update `_go_to_step()` to toggle visibility:
```gdscript
# In _go_to_step():
var viewport_area := preview_container.get_parent()  # AspectRatioContainer
viewport_area.visible = (step <= 1)
pixel_preview_rect.get_parent().visible = (step == 2)
```

Ensure the 2D preview TextureRect is in its own ScrollContainer with TEXTURE_FILTER_NEAREST and proper sizing.

**Step 2: Add step-entry hooks**

In `_go_to_step()`, add entry logic:
```gdscript
match step:
    1:
        _start_capture()  # wrong — capture is step 2
```

Fix the match to:
```gdscript
match step:
    1: await _start_capture()
    2:
        _scan_palettes()
        if _current_preset.has("pixel_art"):
            _apply_pixel_art_preset(_current_preset["pixel_art"])
        _update_pixel_preview()
    3: _start_export()
```

Note: Steps are 0-indexed internally (Step 1 = index 0). Make sure the mapping is correct:
- Index 0 = "Model & Animation" — no special entry logic
- Index 1 = "Capture Preview" — run `_start_capture()`
- Index 2 = "Pixel Art Settings" — scan palettes, apply preset, update preview
- Index 3 = "Export" — run `_start_export()`

**Step 3: Disable Next when no model/animation selected**

```gdscript
# In Step 1, disable Next until model is loaded:
next_button.disabled = (current_anim_player == null)
# Enable when animation selected:
# In _on_animation_selected:
next_button.disabled = false
```

**Step 4: Verify full flow end-to-end**

- Run wizard
- Step 1: select model, adjust camera, save preset
- Next → Step 2: see captured spritesheets for all 3 directions
- Next → Step 3: configure pixel art, preview updates live
- Export → Step 4: files saved, "Run Again" works
- Reopen: preset auto-loads for same model

**Step 5: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: polish wizard flow with preview visibility and step hooks"
```

---

## Summary

| Task | What it adds | Key test |
|------|-------------|----------|
| 1 | Scene + wizard framework + Step 1 (model/camera) | Model loads, camera works, step navigation |
| 2 | Preset save/load (JSON) | Camera preset persists across runs |
| 3 | Step 2 (capture all 3 directions) | Captures appear in preview |
| 4 | Step 3 (pixel art settings + live preview) | All processing effects visible, palette gen works |
| 5 | Step 4 (export + run again) | PNGs saved to final/, run again flow works |
| 6 | Preview visibility + polish | Smooth end-to-end wizard flow |

After all 6 tasks: drop .glb → select animation → frame camera (once) → capture → configure pixel art → export. Done.
