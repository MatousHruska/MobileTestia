# Sprite Wizard Enhancements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add "Load from Spritesheet" to Step 1, fix onion skin CheckButton visual bug, and improve anchor editor UX with left/right click + arrow keys.

**Architecture:** All three changes are in `scripts/tools/sprite_pipeline.gd`. The spritesheet loader adds a new button + loading function that populates the same state dictionaries as the capture pipeline, plus a flag to bypass image processing. The visual fix is a pure styling change. The anchor UX changes modify the existing input handler.

**Tech Stack:** GDScript, Godot 4 UI, Image API

---

### Task 1: Fix Onion Skin CheckButton Visual Bug

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:866-878`

**Step 1: Add transparent StyleBox helper function**

Add after `_apply_toggle_style()` (line 3577):

```gdscript
func _style_checkbutton_transparent(cb: CheckButton) -> void:
	## Remove background fill from CheckButton so only the indicator shows state.
	for state in ["normal", "pressed", "hover", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.TRANSPARENT
		sb.set_content_margin_all(4)
		cb.add_theme_stylebox_override(state, sb)
```

**Step 2: Apply transparent styling to the three CheckButtons in Frame Editor**

In `_build_step_frame_editor()`, after creating each CheckButton (lines 867-878), call the helper:

```gdscript
# After line 872 (onion toggle creation):
_style_checkbutton_transparent(_frame_editor_onion_toggle)

# After line 878 (all directions toggle creation):
_style_checkbutton_transparent(_frame_editor_all_directions_toggle)
```

Also apply to `_frame_editor_nudge_all_toggle` (line 936-938):
```gdscript
_style_checkbutton_transparent(_frame_editor_nudge_all_toggle)
```

**Step 3: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "fix(wizard): transparent CheckButton backgrounds in Frame Editor"
```

---

### Task 2: Add "Load from Spritesheet" State Variable and Button

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:88` (state), `scripts/tools/sprite_pipeline.gd:510-588` (Step 1 UI)

**Step 1: Add state variable**

After line 164 (`var _exported_folder: String = ""`), add:

```gdscript
var _loaded_from_spritesheet := false  # True when sheets loaded from export dir (skip processing)
```

Also add a node reference after line 226 (`var anchor_weapon_anim_toggle`):

```gdscript
var _load_spritesheet_btn: Button = null
var _load_spritesheet_status: Label = null
```

**Step 2: Add button to Step 1 UI**

In `_build_step1()`, after the preset_status_label section (after line 544) and before the Camera Settings collapsible (line 546), add:

```gdscript
# Load from spritesheet
var load_sheet_sec := _make_section("Load Existing Spritesheet")
parent.add_child(load_sheet_sec[0])
var load_sheet_content: VBoxContainer = load_sheet_sec[1]
load_sheet_content.add_child(_make_small_label("Load already-exported spritesheets and skip to Frame Editor."))

_load_spritesheet_btn = Button.new()
_load_spritesheet_btn.text = "Load from Spritesheet"
_load_spritesheet_btn.disabled = true  # Enabled when model+anim selected
_load_spritesheet_btn.pressed.connect(_on_load_spritesheet)
load_sheet_content.add_child(_load_spritesheet_btn)

_load_spritesheet_status = Label.new()
_load_spritesheet_status.text = ""
_load_spritesheet_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
_load_spritesheet_status.size_flags_horizontal = SIZE_EXPAND_FILL
_load_spritesheet_status.add_theme_font_size_override("font_size", FONT_HINT)
_load_spritesheet_status.add_theme_color_override("font_color", C_TEXT_SEC)
load_sheet_content.add_child(_load_spritesheet_status)
```

**Step 3: Enable/disable the button when animation changes**

Find `_on_animation_selected()` and add at the end:

```gdscript
if _load_spritesheet_btn:
	_load_spritesheet_btn.disabled = (current_anim_player == null)
```

Also find `_on_model_selected()` — when model changes and animation resets, disable the button:

```gdscript
if _load_spritesheet_btn:
	_load_spritesheet_btn.disabled = true
	_load_spritesheet_status.text = ""
```

**Step 4: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(wizard): add Load from Spritesheet button UI in Step 1"
```

---

### Task 3: Implement Spritesheet Loading Logic

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (new function + frame editor bypass)

**Step 1: Add the loading function**

Add near the export section (before `_start_export()` around line 2918):

```gdscript
func _on_load_spritesheet() -> void:
	_loaded_from_spritesheet = false
	_load_spritesheet_status.text = ""
	_captured_sheets.clear()
	_captured_normal_sheets.clear()
	_captured_shadow_sheets.clear()

	var model_name := current_model_path.get_file().get_basename()
	var anim_name: String = anim_dropdown.get_item_text(anim_dropdown.selected)
	var safe_anim_name := anim_name.replace(" ", "_").replace("/", "_").to_lower()
	var base_dir := "%s/%s" % [OUTPUT_BASE, model_name]

	var color_count := 0
	var normal_count := 0
	var shadow_count := 0
	var detected_frame_size := 0

	for dir_info in DIRECTIONS:
		var dir_name: String = dir_info["name"]
		# Color sheet
		var color_path := "%s/%s_%s.png" % [base_dir, safe_anim_name, dir_name]
		var global_color := ProjectSettings.globalize_path(color_path)
		var color_img := Image.load_from_file(global_color)
		if color_img:
			_captured_sheets[dir_name] = color_img
			color_count += 1
			if detected_frame_size == 0:
				detected_frame_size = color_img.get_height()
		# Normal map
		var normal_path := "%s/%s_%s_normal.png" % [base_dir, safe_anim_name, dir_name]
		var global_normal := ProjectSettings.globalize_path(normal_path)
		var normal_img := Image.load_from_file(global_normal)
		if normal_img:
			_captured_normal_sheets[dir_name] = normal_img
			normal_count += 1
		# Shadow map
		var shadow_path := "%s/%s_%s_shadow.png" % [base_dir, safe_anim_name, dir_name]
		var global_shadow := ProjectSettings.globalize_path(shadow_path)
		var shadow_img := Image.load_from_file(global_shadow)
		if shadow_img:
			_captured_shadow_sheets[dir_name] = shadow_img
			shadow_count += 1

	if color_count == 0:
		_load_spritesheet_status.text = "No exported sheets found for %s/%s" % [model_name, safe_anim_name]
		return

	# Set frame size from detected image height
	if detected_frame_size > 0:
		output_height_spin.value = detected_frame_size
		_export_frame_size = detected_frame_size

	_loaded_from_spritesheet = true
	_load_spritesheet_status.text = "Loaded %d color + %d normal + %d shadow sheets (%dpx frames)" % [
		color_count, normal_count, shadow_count, detected_frame_size]

	# Jump directly to Frame Editor (step 3)
	_go_to_step(3)
```

**Step 2: Bypass `_process_image()` in Frame Editor when loaded from spritesheet**

In `_setup_frame_editor()` (line 990), replace:

```gdscript
var color_processed := _process_image(_captured_sheets[_frame_editor_direction])
```

with:

```gdscript
var color_processed: Image
if _loaded_from_spritesheet:
	color_processed = _captured_sheets[_frame_editor_direction]
else:
	color_processed = _process_image(_captured_sheets[_frame_editor_direction])
```

**Step 3: Bypass `_process_image()` in export when loaded from spritesheet**

In `_start_export()` (line 2936), replace:

```gdscript
var processed := _process_image(_captured_sheets[dir_name])
```

with:

```gdscript
var processed: Image
if _loaded_from_spritesheet:
	processed = _captured_sheets[dir_name]
else:
	processed = _process_image(_captured_sheets[dir_name])
```

Similarly for normal maps (line 2951-2955), replace:

```gdscript
var processed_normal := PixelArtProcessing.process_normal_map(
	_captured_normal_sheets[dir_name],
	int(output_height_spin.value),
	int(alpha_threshold_slider.value)
)
```

with:

```gdscript
var processed_normal: Image
if _loaded_from_spritesheet:
	processed_normal = _captured_normal_sheets[dir_name]
else:
	processed_normal = PixelArtProcessing.process_normal_map(
		_captured_normal_sheets[dir_name],
		int(output_height_spin.value),
		int(alpha_threshold_slider.value)
	)
```

And for shadow maps (line 2970-2976), wrap the processing block:

```gdscript
var result: Image
if _loaded_from_spritesheet:
	result = shadow_source
else:
	result = shadow_source.duplicate() as Image
	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))
```

**Step 4: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(wizard): implement spritesheet loading with processing bypass"
```

---

### Task 4: Fix Navigation for Spritesheet-Loaded Flow

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:1993-2010` (navigation), `scripts/tools/sprite_pipeline.gd:3000-3004` (reset)

**Step 1: Update back navigation**

In `_on_back_pressed()` (line 2006), add a case for going back from Frame Editor to Step 1 when loaded from spritesheet:

```gdscript
func _on_back_pressed() -> void:
	if _current_step == 3 and _loaded_from_spritesheet:
		_go_to_step(0)  # Spritesheet loaded — skip back over capture/pixel art
	elif _current_step == 7 and not _anchor_enabled:
		_go_to_step(5)  # Anchors were skipped — go back to export
	elif _current_step > 0:
		_go_to_step(_current_step - 1)
```

**Step 2: Reset flag on Run Again / Done**

In `_on_run_again_pressed()` (line 3000) and `_on_done_pressed()` (line 3007), add:

```gdscript
_loaded_from_spritesheet = false
```

**Step 3: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(wizard): handle back navigation for spritesheet-loaded flow"
```

---

### Task 5: Anchor Editor — Left/Right Click for Grip/Direction

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:1682-1732` (`_on_anchor_frame_input`)

**Step 1: Modify input handler to support right-click**

Replace `_on_anchor_frame_input()` (lines 1682-1732):

```gdscript
func _on_anchor_frame_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	# Left click = grip, Right click = direction
	var tool_override := ""
	if mb.button_index == MOUSE_BUTTON_LEFT:
		tool_override = "grip"
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		tool_override = "direction"
	else:
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
		drawn_w = display_size.x
		drawn_h = display_size.x / tex_aspect
		offset_x = 0.0
		offset_y = (display_size.y - drawn_h) / 2.0
	else:
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

	_place_anchor_pixel(pixel_x, pixel_y, tool_override)
```

**Step 2: Update `_place_anchor_pixel` to accept optional tool override**

Modify `_place_anchor_pixel` (line 1735) to accept an optional tool parameter:

```gdscript
func _place_anchor_pixel(x: int, y: int, tool_name: String = "") -> void:
	if not _anchor_images.has(_anchor_current_dir):
		return
	var active_tool := tool_name if tool_name != "" else _anchor_tool
	# Save undo snapshot before modifying
	_anchor_undo_state[_anchor_current_dir] = (_anchor_images[_anchor_current_dir] as Image).duplicate()
	var sheet: Image = _anchor_images[_anchor_current_dir]
	var grip_color := Color("#FF00AA")
	var dir_color := Color("#00FFFF")

	match active_tool:
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
```

**Step 3: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(wizard): left-click=grip, right-click=direction in anchor editor"
```

---

### Task 6: Anchor Editor — Arrow Key Frame Navigation

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (add `_unhandled_input`)

**Step 1: Add `_unhandled_input` method**

Add after the `_process()` function (around line 290):

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _current_step != 6:
		return
	if not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_LEFT:
			if _anchor_current_frame > 0:
				_anchor_current_frame -= 1
				_update_anchor_display()
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if _anchor_current_frame < _anchor_frame_count - 1:
				_anchor_current_frame += 1
				_update_anchor_display()
				get_viewport().set_input_as_handled()
```

**Step 2: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(wizard): arrow key frame navigation in anchor editor"
```

---

### Task 7: Final Review

**Step 1: Read through all changes**

Review the full file for consistency — ensure no typos, no broken references, and the flag resets properly.

**Step 2: Final commit (if any cleanup needed)**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "chore(wizard): cleanup sprite wizard enhancements"
```
