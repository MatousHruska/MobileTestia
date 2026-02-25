# Per-Frame Weapon Z-Index & Multi-Select Frames — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-frame weapon z-index toggle (behind/in-front) and shift-click multi-select with batch property editing to the Attack Composer.

**Architecture:** Two independent features. Feature 1 adds a boolean field to `CompositionFrame` and threads it through the UI/preview/timeline. Feature 2 changes the selection model from a single `int` to an `Array[int]` set, modifies the timeline's click handler, and makes all property change handlers apply to all selected frames.

**Tech Stack:** GDScript, Godot 4 UI system (CheckButton, SpinBox, timeline custom draw)

---

## Part 1: Per-Frame Weapon Z-Index

### Task 1: Add `weapon_z_front` to CompositionFrame

**Files:**
- Modify: `scripts/tools/attack_composer/composition_frame.gd:10`

After `weapon_visible`, add:

```gdscript
## Whether the weapon renders in front of (true, z=1) or behind (false, z=-1) the body
@export var weapon_z_front: bool = true
```

### Task 2: Add "Weapon In Front" CheckButton to Frame Properties

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

Add new UI ref (after `_weapon_check`):
```gdscript
var _weapon_z_front_check: CheckButton
```

In `_build_frame_props_section()`, right after the `_weapon_check` block (after line ~865), add:

```gdscript
_weapon_z_front_check = CheckButton.new()
_weapon_z_front_check.text = "Weapon In Front"
_weapon_z_front_check.add_theme_font_size_override("font_size", FONT_LABEL)
_weapon_z_front_check.add_theme_color_override("font_color", C_TEXT_SEC)
_weapon_z_front_check.toggled.connect(_on_weapon_z_front_toggled)
_frame_props_container.add_child(_weapon_z_front_check)
```

Add handler:

```gdscript
func _on_weapon_z_front_toggled(pressed: bool) -> void:
    if _current_composition == null or _selected_frame < 0:
        return
    _push_undo()
    _current_composition.frames[_selected_frame].weapon_z_front = pressed
    _update_preview_frame()
    _timeline_panel.queue_redraw()
```

### Task 3: Update `_update_frame_props_ui()` to show z-front state

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

In `_update_frame_props_ui()`, after `_weapon_check.set_pressed_no_signal(frame.weapon_visible)`, add:

```gdscript
_weapon_z_front_check.set_pressed_no_signal(frame.weapon_z_front)
```

### Task 4: Apply z-index in preview

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

In `_update_weapon_preview()`, replace the hardcoded line:
```gdscript
_weapon_sprite.z_index = 2
```

With:
```gdscript
_weapon_sprite.z_index = 1 if frame.weapon_z_front else -1
```

(The `frame` variable is already available in that function — it's `_current_composition.frames[_preview_frame_index]`.)

### Task 5: Show "B" marker on weapon track for behind-body frames

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

In `_draw_weapon_track()`, after the `draw_rect()` call for each frame, add:

```gdscript
if not composition.frames[i].weapon_z_front and composition.frames[i].weapon_visible:
    var label_x := x + 2
    var label_y := y + SUB_TRACK_HEIGHT - 4
    draw_string(_font, Vector2(label_x, label_y), "B",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT)
```

---

## Part 2: Multi-Select Frames

### Task 6: Add multi-select state to Attack Composer

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

Add new state var (after `_selected_frame`):
```gdscript
var _selected_frames: Array[int] = []
```

### Task 7: Add multi-select state and signal to Timeline Panel

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

Add new state (after `selected_frame`):
```gdscript
var selected_frames: Array[int] = []
```

Add new signal (after `frame_selected`):
```gdscript
signal frames_selected(indices: Array[int])
```

### Task 8: Modify timeline click handler for shift-click range select

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

In `_gui_input()`, pass the shift state to `_handle_click`:

Change:
```gdscript
if mb.pressed:
    _handle_click(mb.position)
```
To:
```gdscript
if mb.pressed:
    _handle_click(mb.position, mb.shift_pressed)
```

Update `_handle_click` signature:
```gdscript
func _handle_click(pos: Vector2, shift: bool = false) -> void:
```

Replace the "Normal click → select frame" block with:

```gdscript
# Click → select frame (shift = range select)
var idx := _frame_at_x(pos.x, body_y, BODY_TRACK_HEIGHT, pos.y)
if idx >= 0:
    if shift and selected_frame >= 0:
        # Range select from last selected to clicked
        var from_idx := mini(selected_frame, idx)
        var to_idx := maxi(selected_frame, idx)
        selected_frames.clear()
        for i in range(from_idx, to_idx + 1):
            selected_frames.append(i)
        selected_frame = idx
        frames_selected.emit(selected_frames.duplicate())
    else:
        # Normal click — single select
        selected_frame = idx
        selected_frames = [idx]
        frame_selected.emit(idx)
    queue_redraw()
return
```

### Task 9: Render multi-selection in timeline body track

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

In `_draw_body_track()`, update the block color and selection border logic:

Replace:
```gdscript
var block_color := C_SURFACE if i != selected_frame else C_ACCENT.darkened(0.3)
```
With:
```gdscript
var is_primary := (i == selected_frame)
var is_selected := (i in selected_frames)
var block_color := C_ACCENT.darkened(0.3) if is_primary else (C_ACCENT.darkened(0.5) if is_selected else C_SURFACE)
```

Replace the selection border block:
```gdscript
if i == selected_frame:
    draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), C_ACCENT, false, 2.0)
```
With:
```gdscript
if is_primary:
    draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), C_ACCENT, false, 2.0)
elif is_selected:
    draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), C_ACCENT.darkened(0.2), false, 1.0)
```

### Task 10: Connect `frames_selected` signal and sync multi-select state in Attack Composer

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

In `_build_ui()`, after `_timeline_panel.frame_selected.connect(...)`, add:

```gdscript
_timeline_panel.frames_selected.connect(_on_timeline_frames_selected)
```

Add new handler:

```gdscript
func _on_timeline_frames_selected(indices: Array[int]) -> void:
    _selected_frames = indices
    # Primary frame = last element (the one the user shift-clicked on)
    if not indices.is_empty():
        _selected_frame = indices[-1]
        _preview_frame_index = _selected_frame
        _update_preview_frame()
        _update_frame_props_ui()
    _set_status("%d frames selected." % indices.size())
```

Update `_on_timeline_frame_selected` to also sync `_selected_frames`:

```gdscript
func _on_timeline_frame_selected(index: int) -> void:
    _selected_frame = index
    _selected_frames = [index]
    _preview_frame_index = index
    _update_preview_frame()
    _update_frame_props_ui()
```

### Task 11: Make all frame property handlers apply to all selected frames

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

Add helper function:

```gdscript
func _get_target_frames() -> Array[int]:
    if _selected_frames.size() > 1:
        return _selected_frames
    if _selected_frame >= 0:
        return [_selected_frame]
    return []
```

Update each handler to use `_get_target_frames()`:

**`_on_duration_changed`:**
```gdscript
func _on_duration_changed(value: float) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    for idx in targets:
        _current_composition.frames[idx].duration_ms = int(value)
    _fps_label.text = "~ %.1f fps" % (1000.0 / maxf(value, 1))
    _total_duration_label.text = "Total: %.3fs" % _current_composition.get_total_duration_sec()
    _timeline_panel.queue_redraw()
```

**`_on_weapon_toggled`:**
```gdscript
func _on_weapon_toggled(pressed: bool) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    for idx in targets:
        _current_composition.frames[idx].weapon_visible = pressed
    _update_preview_frame()
    _timeline_panel.queue_redraw()
```

**`_on_weapon_z_front_toggled`** (from Task 2 — update to multi-select):
```gdscript
func _on_weapon_z_front_toggled(pressed: bool) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    for idx in targets:
        _current_composition.frames[idx].weapon_z_front = pressed
    _update_preview_frame()
    _timeline_panel.queue_redraw()
```

**`_on_effect_selected`:**
```gdscript
func _on_effect_selected(index: int) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    var text := _effect_dropdown.get_item_text(index)
    var effect_id := "" if text == "(none)" else text
    for idx in targets:
        _current_composition.frames[idx].effect_id = effect_id
    _timeline_panel.queue_redraw()
```

**`_on_effect_anchor_selected`:**
```gdscript
func _on_effect_anchor_selected(index: int) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    var anchor_text := _effect_anchor_dropdown.get_item_text(index)
    for idx in targets:
        _current_composition.frames[idx].effect_anchor = anchor_text
```

**`_on_effect_offset_changed`:**
```gdscript
func _on_effect_offset_changed(_value: float) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    var offset := Vector2(_effect_offset_x.value, _effect_offset_y.value)
    for idx in targets:
        _current_composition.frames[idx].effect_offset = offset
```

**`_on_echo_toggled`:**
```gdscript
func _on_echo_toggled(pressed: bool) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    for idx in targets:
        _current_composition.frames[idx].echo_enabled = pressed
    _echo_settings_container.visible = pressed
    _timeline_panel.queue_redraw()
```

**`_on_echo_setting_changed`:**
```gdscript
func _on_echo_setting_changed(_value: float) -> void:
    var targets := _get_target_frames()
    if _current_composition == null or targets.is_empty():
        return
    _push_undo()
    for idx in targets:
        var frame := _current_composition.frames[idx]
        frame.echo_count = int(_echo_count_spin.value)
        frame.echo_opacity_start = _echo_opacity_start_slider.value
        frame.echo_opacity_end = _echo_opacity_end_slider.value
        frame.echo_spacing_px = _echo_spacing_spin.value
```

### Task 12: Reset multi-select on single-frame operations

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

Ensure these navigation functions reset to single-select:

In `_on_frame_prev`, `_on_frame_next`, `_on_stop`, `show_frame`, and the `KEY_LEFT`/`KEY_RIGHT`/`KEY_HOME`/`KEY_END` handlers: after setting `_selected_frame`, add:
```gdscript
_selected_frames = [_selected_frame]
_timeline_panel.selected_frames = _selected_frames
```

In `_on_spritesheet_loaded()`, after `_timeline_panel.selected_frame = 0`, add:
```gdscript
_selected_frames = [0]
_timeline_panel.selected_frames = [0]
```

Similarly in `_on_load_pressed()` (after setting `_selected_frame = 0`), `_load_composition()`, and `_undo()`.

---

## Verification

1. Load a spritesheet, select a frame
2. Toggle "Weapon In Front" off → weapon should render behind body (z=-1)
3. Step through frames → verify z-index is per-frame (not global)
4. Check timeline weapon track → "B" marker on frames with weapon behind
5. Click frame 2, shift-click frame 5 → frames 2-5 highlighted
6. Change duration → all 4 selected frames update to same value
7. Toggle "Weapon Visible" → all 4 frames toggled
8. Click frame 3 (no shift) → single select, only frame 3 highlighted
9. Undo → verify batch change is undone in one step
10. Use arrow keys → verify single-select behavior restored
