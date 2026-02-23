# Sprite Pipeline Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the sprite pipeline wizard with better defaults, UI hints, direction preview in Step 3, working dithering/denoising, and AtlasTexture optimization in the apply script.

**Architecture:** All wizard changes are in `sprite_pipeline.gd` (purely UI code built programmatically). The AtlasTexture change is in `apply_final_walk_sprites.gd` (an EditorScript). No new files needed.

**Tech Stack:** GDScript, Godot 4 SpriteFrames API, AtlasTexture

---

### Task 1: Update Default Values

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:277` (frame count)
- Modify: `scripts/tools/sprite_pipeline.gd:310,316` (elevation slider + label)
- Modify: `scripts/tools/sprite_pipeline.gd:329,334` (zoom slider + label)
- Modify: `scripts/tools/sprite_pipeline.gd:637,641` (camera.size + _position_camera)

**Step 1: Change frame count default**

In `_build_step1`, line 277:
```gdscript
# Old:
frame_count_spin.value = 24
# New:
frame_count_spin.value = 8
```

**Step 2: Change elevation default**

In `_build_step1`, line 310 and 316:
```gdscript
# Old:
camera_elevation_slider.value = 40.0
# ...
camera_elevation_label.text = "40"
# New:
camera_elevation_slider.value = 30.0
# ...
camera_elevation_label.text = "30"
```

**Step 3: Change zoom default**

In `_build_step1`, line 329 and 334:
```gdscript
# Old:
camera_zoom_slider.value = 3.5
# ...
camera_zoom_label.text = "3.5"
# New:
camera_zoom_slider.value = 3.0
# ...
camera_zoom_label.text = "3.0"
```

**Step 4: Change viewport camera defaults**

In `_build_viewport`, line 637 and 641:
```gdscript
# Old:
camera.size = 3.5
# ...
_position_camera(40.0)
# New:
camera.size = 3.0
# ...
_position_camera(30.0)
```

**Step 5: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: update sprite pipeline defaults (frames=8, elevation=30, zoom=3.0)"
```

---

### Task 2: Add Static Hint Labels for Camera Defaults

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — `_build_step1` function, after elevation hbox (line ~318) and after zoom hbox (line ~335)

**Step 1: Add elevation hint label**

After line 318 (`elev_hbox.add_child(camera_elevation_label)`), add:
```gdscript
var elev_hint := Label.new()
elev_hint.text = "(default: 30)"
elev_hint.add_theme_font_size_override("font_size", 10)
elev_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
camera_settings_container.add_child(elev_hint)
```

**Step 2: Add zoom hint label**

After the zoom label is added to zoom_hbox (after the line that has `zoom_hbox.add_child(camera_zoom_label)`), add:
```gdscript
var zoom_hint := Label.new()
zoom_hint.text = "(default: 3.0)"
zoom_hint.add_theme_font_size_override("font_size", 10)
zoom_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
camera_settings_container.add_child(zoom_hint)
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add static hint labels for camera elevation and zoom defaults"
```

---

### Task 3: Add Direction Selector in Step 3

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — add state var (line ~48), modify `_build_step3` (line ~415), modify `_update_pixel_preview` (line ~1243)

**Step 1: Add state variable**

After `var _palette_colors` (line 49), add:
```gdscript
var _preview_direction := "down"
```

**Step 2: Add direction buttons at top of Step 3**

At the beginning of `_build_step3` (after `func _build_step3(parent: VBoxContainer) -> void:`), before the output height section, add:
```gdscript
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
```

**Step 3: Update `_update_pixel_preview` to use `_preview_direction`**

In `_update_pixel_preview` (line 1243), change:
```gdscript
# Old:
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

# New:
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
```

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add direction selector in Step 3 pixel preview"
```

---

### Task 4: Fix Dithering (Auto-Quantize Without Palette)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — `_process_image` (line ~1077), add `_apply_auto_quantize` function

**Step 1: Update `_process_image` to always apply dithering when enabled**

In `_process_image` (line 1077-1098), change the dithering and palette section:
```gdscript
# Old:
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

# New:
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
```

**Step 2: Add `_apply_auto_quantize` function**

Add this new function after `_apply_palette_mapping` (after line ~1155):
```gdscript
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
```

**Step 3: Apply the same fix to `pixel_art_converter.gd`**

The standalone converter has the same gating bug at line 382. Apply identical changes:
- In `_process_image` (line 368): remove `and not _palette_colors.is_empty()` from dithering guard
- Add auto-quantize fallback after palette mapping
- Add the same `_apply_auto_quantize` function

File: `scripts/tools/pixel_art_converter.gd`

```gdscript
# In _process_image, replace steps 3-4:
# Old:
	# Step 3: Dithering (before palette mapping)
	if dithering_toggle.button_pressed and not _palette_colors.is_empty():
		_apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	# Step 4: Palette mapping
	_apply_palette_mapping(result)

# New:
	# Step 3: Dithering (before palette mapping / auto-quantize)
	if dithering_toggle.button_pressed:
		_apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	# Step 4: Palette mapping or auto-quantize
	if not _palette_colors.is_empty():
		_apply_palette_mapping(result)
	elif dithering_toggle.button_pressed:
		_apply_auto_quantize(result)
```

Add the `_apply_auto_quantize` function in `pixel_art_converter.gd` after `_apply_palette_mapping`:
```gdscript
func _apply_auto_quantize(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			color.r = snappedf(color.r, 1.0 / 31.0)
			color.g = snappedf(color.g, 1.0 / 31.0)
			color.b = snappedf(color.b, 1.0 / 31.0)
			image.set_pixel(x, y, color)
```

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd scripts/tools/pixel_art_converter.gd
git commit -m "fix: dithering now works without palette via auto-quantize"
```

---

### Task 5: Fix Denoising Default

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:537` (denoising_min_cluster_spin.value)
- Modify: `scripts/tools/pixel_art_converter.gd:224` (same default)

**Step 1: Update default in sprite_pipeline.gd**

Line 537:
```gdscript
# Old:
denoising_min_cluster_spin.value = 2
# New:
denoising_min_cluster_spin.value = 4
```

**Step 2: Update default in pixel_art_converter.gd**

Line 224:
```gdscript
# Old:
denoising_min_cluster_spin.value = 2
# New:
denoising_min_cluster_spin.value = 4
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd scripts/tools/pixel_art_converter.gd
git commit -m "fix: increase denoising default min cluster from 2 to 4"
```

---

### Task 6: AtlasTexture in apply_final_walk_sprites.gd

**Files:**
- Modify: `scripts/tools/apply_final_walk_sprites.gd:93-118` (the sheet loading + frame creation loop)

**Step 1: Replace frame-cutting with AtlasTexture**

Replace lines 93-118 (the inner loop body inside `for anim_name in sheets:`) with:
```gdscript
		for anim_name in sheets:
			var sheet_filename: String = sheets[anim_name]
			var sheet_path := "%s/%s/%s" % [SHEET_DIR, folder, sheet_filename]
			var abs_path := ProjectSettings.globalize_path(sheet_path)

			var sheet_image := Image.load_from_file(abs_path)
			if sheet_image == null:
				push_error("  Failed to load: %s" % abs_path)
				continue

			var frame_count := sheet_image.get_width() / FRAME_SIZE
			print("  %s: %d frames from %s" % [anim_name, frame_count, sheet_filename])

			# Remove existing animation and recreate
			if frames.has_animation(anim_name):
				frames.remove_animation(anim_name)
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			frames.set_animation_loop(anim_name, loop)

			# Use AtlasTexture regions from the full sheet instead of cutting individual frames
			var sheet_texture := ImageTexture.create_from_image(sheet_image)
			for i in range(frame_count):
				var atlas_tex := AtlasTexture.new()
				atlas_tex.atlas = sheet_texture
				atlas_tex.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim_name, atlas_tex)
```

**Step 2: Commit**

```bash
git add scripts/tools/apply_final_walk_sprites.gd
git commit -m "perf: use AtlasTexture regions instead of cutting spritesheet frames"
```

---

## Testing

Since these are tool scripts (run in-editor, not at runtime), testing is manual:

1. **Tasks 1-2:** Open sprite_pipeline.tscn (F6). Verify defaults show 8 frames, 30 elevation, 3.0 zoom. Open Camera Settings and verify hint labels appear.
2. **Task 3:** Capture a model, go to Step 3, click Down/Up/Right buttons and verify the preview switches directions.
3. **Task 4:** In Step 3, enable Dithering without loading any palette. Verify visible banding/pattern appears in the preview.
4. **Task 5:** Enable Denoising — verify default is 4 and small isolated pixel blobs are removed.
5. **Task 6:** Run apply_final_walk_sprites.gd from Editor > Script > Run. Open player_sprites.tres in the inspector and verify animations still play correctly with AtlasTexture frames.
