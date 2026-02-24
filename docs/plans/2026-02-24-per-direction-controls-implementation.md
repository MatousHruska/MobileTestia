# Per-Direction Controls — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-direction capture in Step 2 and per-direction editing in Step 4 of the sprite pipeline wizard.

**Architecture:** Two independent features in `sprite_pipeline.gd`. Step 2 gets a capture-scope toggle group (`All|Down|Up|Right`) that filters which directions `_capture_animation()` processes. Step 4 gets an "Apply to all directions" CheckButton that filters which directions `_nudge_current_frame()` and `_delete_current_frame()` iterate over.

**Tech Stack:** GDScript, Godot 4 UI (CheckButton, toggle groups)

---

### Task 1: Add capture scope state variable and UI toggle (Step 2)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:104` (add state var after shadow sheets)
- Modify: `scripts/tools/sprite_pipeline.gd:580-598` (`_build_step2`)

**Step 1: Add state variable**

After line 103 (`var _captured_shadow_sheets`), add:

```gdscript
var _capture_scope := "all"  # "all", "down", "up", "right"
```

Also add a reference for the capture button so we can update its label:

```gdscript
var _capture_btn: Button = null
```

**Step 2: Add capture scope toggle group in `_build_step2`**

Between the preview mode toggle (line 594) and the capture button (line 596), insert a capture scope toggle group:

```gdscript
# Capture scope — which directions to capture
var scope_group := _make_toggle_group([
    {"label": "All", "key": "all"},
    {"label": "Down", "key": "down"},
    {"label": "Up", "key": "up"},
    {"label": "Right", "key": "right"},
], func(key: String) -> void:
    _capture_scope = key
    if _capture_btn:
        if key == "all":
            _capture_btn.text = "Capture All"
        else:
            _capture_btn.text = "Capture %s" % key.capitalize()
)
content.add_child(_make_field("Capture", scope_group))
```

Also change the capture button to store a reference:

```gdscript
_capture_btn = _make_primary_button("Capture All")
_capture_btn.pressed.connect(_start_capture)
content.add_child(_capture_btn)
```

(Replace the existing `var capture_btn` lines at 596-598.)

**Step 3: Commit**

```
feat(wizard): add capture scope toggle UI in Step 2
```

---

### Task 2: Wire capture scope into `_start_capture` and `_capture_animation`

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:2376-2388` (`_start_capture`)
- Modify: `scripts/tools/sprite_pipeline.gd:2391-2548` (`_capture_animation`)

**Step 1: Update `_start_capture` to clear only scoped directions**

Replace the three `.clear()` calls (lines 2381-2383) with scoped clearing:

```gdscript
if _capture_scope == "all":
    _captured_sheets.clear()
    _captured_normal_sheets.clear()
    _captured_shadow_sheets.clear()
else:
    _captured_sheets.erase(_capture_scope)
    _captured_normal_sheets.erase(_capture_scope)
    _captured_shadow_sheets.erase(_capture_scope)
```

**Step 2: Update `_capture_animation` to filter directions**

At the top of `_capture_animation()`, after line 2407, compute the filtered directions list:

```gdscript
var directions_to_capture: Array = []
if _capture_scope == "all":
    directions_to_capture = DIRECTIONS.duplicate()
else:
    for d in DIRECTIONS:
        if d["name"] == _capture_scope:
            directions_to_capture.append(d)
            break
```

Replace `for dir_idx in range(DIRECTIONS.size()):` (line 2409) with:

```gdscript
for dir_idx in range(directions_to_capture.size()):
    var dir_config: Dictionary = directions_to_capture[dir_idx]
```

(Remove the old line 2410 that read from DIRECTIONS.)

**Step 3: Update direction preview rects**

The `direction_rects` mapping at line 2407 needs adjustment. Currently it maps by index into DIRECTIONS. With filtered directions, map by name instead. Replace the preview update logic that uses `direction_rects` (currently implicit — the rects are updated in `_update_capture_preview` at the end). No change needed here since `_update_capture_preview()` already checks `sheets.has(dir_names[i])`.

**Step 4: Update status message**

Change line 2548 status message:

```gdscript
if _capture_scope == "all":
    _set_status("Captured all 3 directions. Review and click Next.")
else:
    _set_status("Captured %s direction. Review and click Next." % _capture_scope)
```

**Step 5: Update file saving to only save captured directions**

The file saving loop (lines 2523-2536) already iterates over `_captured_sheets` keys, so it will naturally save only existing directions. No change needed.

**Step 6: Commit**

```
feat(wizard): wire capture scope to only capture selected directions
```

---

### Task 3: Add "Apply to all directions" toggle (Step 4 Frame Editor)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:124` (add state var)
- Modify: `scripts/tools/sprite_pipeline.gd:789-934` (`_build_step_frame_editor`)

**Step 1: Add state variable**

After line 126 (`var _frame_editor_onion_sprite`), add:

```gdscript
var _frame_editor_all_directions_toggle: CheckButton = null
```

**Step 2: Add CheckButton in `_build_step_frame_editor`**

After the onion skin toggle block (line 850), insert:

```gdscript
# Apply to all directions toggle
_frame_editor_all_directions_toggle = CheckButton.new()
_frame_editor_all_directions_toggle.text = "Apply to all directions"
_frame_editor_all_directions_toggle.button_pressed = true  # Default ON
content.add_child(_frame_editor_all_directions_toggle)
```

**Step 3: Commit**

```
feat(wizard): add 'Apply to all directions' toggle to Frame Editor
```

---

### Task 4: Wire per-direction toggle into nudge logic

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:1030-1058` (`_nudge_current_frame`)

**Step 1: Update direction iteration in `_nudge_current_frame`**

Replace the inner loop `for dir_name in sheet_dict.keys():` (line 1039) with:

```gdscript
var apply_all := _frame_editor_all_directions_toggle and _frame_editor_all_directions_toggle.button_pressed
var dirs_to_edit: Array = sheet_dict.keys() if apply_all else [_frame_editor_direction]
for dir_name in dirs_to_edit:
    if not sheet_dict.has(dir_name):
        continue
```

This keeps the rest of the nudge logic identical — it just filters which directions are iterated.

**Step 2: Commit**

```
feat(wizard): nudge respects per-direction toggle
```

---

### Task 5: Wire per-direction toggle into delete logic

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:1061-1097` (`_delete_current_frame`)

**Step 1: Update direction iteration in `_delete_current_frame`**

Replace the inner loop `for dir_name in sheet_dict.keys():` (line 1069) with:

```gdscript
var apply_all := _frame_editor_all_directions_toggle and _frame_editor_all_directions_toggle.button_pressed
var dirs_to_edit: Array = sheet_dict.keys() if apply_all else [_frame_editor_direction]
for dir_name in dirs_to_edit:
    if not sheet_dict.has(dir_name):
        continue
```

Note: The `_frame_editor_frame_count` update at line 1091 stays as-is since it tracks the count for the current direction being viewed.

**Step 2: Update `_setup_frame_editor` to handle per-direction frame counts**

Since directions can now have different frame counts after per-direction deletion, `_setup_frame_editor()` already correctly computes `_frame_editor_frame_count` from the current direction's processed sheet width (line 967). No change needed here — it naturally handles divergent counts.

**Step 3: Commit**

```
feat(wizard): delete frame respects per-direction toggle
```

---

### Task 6: Test manually

**Step 1: Run the sprite pipeline wizard**

Open `scenes/tools/sprite_pipeline.tscn` (F6 in Godot).

**Step 2: Test Step 2 per-direction capture**

1. Load a model and animation in Step 1
2. In Step 2, verify "Capture" toggle group shows `All | Down | Up | Right`
3. Capture with "All" — verify all 3 direction previews appear
4. Switch to "Up", click "Capture Up" — verify only "Up" preview updates, others stay
5. Switch to "Down", capture — verify only "Down" updates

**Step 3: Test Step 4 per-direction editing**

1. Navigate to Step 4 (Frame Editor)
2. Verify "Apply to all directions" checkbox is present and ON by default
3. With toggle ON: nudge a frame, switch directions — verify nudge applied to all
4. Toggle OFF: nudge a frame, switch directions — verify nudge applied only to selected direction
5. Toggle OFF: delete a frame from one direction, switch directions — verify other directions kept that frame

**Step 4: Final commit**

```
feat(wizard): add per-direction capture and editing controls
```
