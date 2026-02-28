# Attack Composer: Scrollbar & Per-Direction Sequences — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a horizontal scrollbar to the timeline and convert directions from shared viewpoints into fully independent sequences with an "All" broadcast mode.

**Architecture:** New `DirectionSequence` resource holds per-direction frames and sequence properties. `AttackCompositionData` stores a `direction_sequences` dictionary keyed by direction string. The timeline panel gets an HScrollBar synced bidirectionally with `scroll_offset_ms`. Direction buttons gain an "All" option for broadcast edits.

**Tech Stack:** GDScript, Godot 4 Resource system, custom Control drawing

**Design Doc:** `docs/plans/2026-02-28-attack-composer-scrollbar-and-per-direction-sequences-design.md`

---

## Task 1: Create DirectionSequence Resource

**Files:**
- Create: `scripts/tools/attack_composer/direction_sequence.gd`

**Step 1: Create the new resource class**

```gdscript
class_name DirectionSequence
extends Resource
## Holds per-direction frame timeline and sequence-level properties.
## Each direction (down, up, right) gets its own DirectionSequence.

## Per-frame timeline data for this direction
@export var frames: Array[CompositionFrame] = []

## Movement type: "lunge", "dash", or "" (no movement)
@export var movement_type: String = ""

## Movement distance in pixels
@export var movement_distance: float = 20.0

## Frame index where movement starts (-1 = no movement)
@export var movement_start_frame: int = -1

## Frame index where movement ends (-1 = no movement)
@export var movement_end_frame: int = -1

## Frame index that triggers the damage event (-1 = no damage)
@export var damage_frame: int = -1


## Helper: total duration of all frames in milliseconds
func get_total_duration_ms() -> int:
	var total := 0
	for frame in frames:
		total += frame.duration_ms
	return total


## Helper: total duration in seconds
func get_total_duration_sec() -> float:
	return get_total_duration_ms() / 1000.0


## Factory: create a default sequence with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> DirectionSequence:
	var seq := DirectionSequence.new()
	var ms_per_frame := int(1000.0 / fps)
	for i in frame_count:
		var frame := CompositionFrame.new()
		frame.duration_ms = ms_per_frame
		seq.frames.append(frame)
	return seq
```

**Step 2: Commit**
```
git add scripts/tools/attack_composer/direction_sequence.gd
git commit -m "feat(attack-composer): add DirectionSequence resource class"
```

---

## Task 2: Refactor AttackCompositionData to Use DirectionSequence

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composition_data.gd` (all lines)

**Step 1: Replace flat fields with direction_sequences dict**

Replace the entire file content. Keep shared fields (`composition_id`, `display_name`, `runtime_template_id`, `animation_name`, `locks_movement`). Remove `frames`, `movement_type`, `movement_distance`, `movement_start_frame`, `movement_end_frame`, `damage_frame`. Add `direction_sequences` dictionary and migration helper.

```gdscript
class_name AttackCompositionData
extends Resource
## The editor's native format for attack animation compositions.
## Stores per-direction sequences with timing, weapon, effects, echoes, and movement.
## A converter generates AbilityVisualData from this for runtime playback.

const DIRECTIONS: Array[String] = ["down", "up", "right"]

## Unique composition ID (matches the template ID, e.g., "melee_single")
@export var composition_id: String = ""

## Human-readable name for display in the editor
@export var display_name: String = ""

## Runtime template ID for ability visual lookup.
## If empty, composition_id is used as the runtime filename.
@export var runtime_template_id: String = ""

## Base animation name in SpriteFrames (e.g., "attack")
## Direction suffix (_down, _up, _right) added at runtime.
@export var animation_name: String = "attack"

## Whether the character is movement-locked during the entire sequence
@export var locks_movement: bool = true

## Per-direction sequence data — the core of the composition.
## Keys: "down", "up", "right" → DirectionSequence resources.
@export var direction_sequences: Dictionary = {}

# ── Legacy fields (kept for migration, not used in new compositions) ──
@export var frames: Array[CompositionFrame] = []
@export var movement_type: String = ""
@export var movement_distance: float = 20.0
@export var movement_start_frame: int = -1
@export var movement_end_frame: int = -1
@export var damage_frame: int = -1


## Get the DirectionSequence for a specific direction. Returns null if missing.
func get_sequence(direction: String) -> DirectionSequence:
	if direction_sequences.has(direction):
		return direction_sequences[direction] as DirectionSequence
	return null


## Ensure all 3 directions have sequences (creates empty ones if missing).
func ensure_all_directions() -> void:
	for dir_name in DIRECTIONS:
		if not direction_sequences.has(dir_name):
			direction_sequences[dir_name] = DirectionSequence.new()


## Migrate from legacy flat format (old .tres files).
## Copies the shared frames array into all 3 directions.
func migrate_from_legacy() -> void:
	if direction_sequences.is_empty() and not frames.is_empty():
		for dir_name in DIRECTIONS:
			var seq := DirectionSequence.new()
			seq.movement_type = movement_type
			seq.movement_distance = movement_distance
			seq.movement_start_frame = movement_start_frame
			seq.movement_end_frame = movement_end_frame
			seq.damage_frame = damage_frame
			for frame in frames:
				seq.frames.append(frame.duplicate())
			direction_sequences[dir_name] = seq
		# Clear legacy fields after migration
		frames.clear()


## Helper: total duration of a specific direction in seconds
func get_total_duration_sec(direction: String = "down") -> float:
	var seq := get_sequence(direction)
	if seq:
		return seq.get_total_duration_sec()
	return 0.0


## Helper: create a default composition with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> AttackCompositionData:
	var data := AttackCompositionData.new()
	for dir_name in DIRECTIONS:
		data.direction_sequences[dir_name] = DirectionSequence.create_default(frame_count, fps)
	return data
```

**Step 2: Commit**
```
git commit -m "refactor(attack-composer): move per-frame and sequence data into DirectionSequence"
```

---

## Task 3: Add HScrollBar to Timeline Panel

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd` (lines 7, 47-48, 369-381)
- Modify: `scripts/tools/attack_composer/attack_composer.gd` (lines 608-627 — timeline section building)

**Step 1: Add scroll_changed signal and scrollbar sync methods to TimelinePanel**

In `timeline_panel.gd`, add a new signal after line 13:

```gdscript
signal scroll_changed(offset_ms: float, total_ms: float, visible_ms: float)
```

Add a method to get the visible window width in ms (after the `_get_total_ms` function around line 105):

```gdscript
func get_visible_ms() -> float:
	return (size.x - LABEL_WIDTH) / pixels_per_ms


func set_scroll_from_scrollbar(value_ms: float) -> void:
	scroll_offset_ms = clampf(value_ms, 0.0, maxf(0.0, _get_total_ms() - get_visible_ms()))
	queue_redraw()
```

**Step 2: Emit scroll_changed on scroll and zoom**

In the mouse wheel handler (lines 369-381), after each `queue_redraw()`, emit the signal:

```gdscript
elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
	if mb.shift_pressed:
		scroll_offset_ms = maxf(0, scroll_offset_ms - 50)
	else:
		pixels_per_ms = minf(pixels_per_ms * 1.15, 10.0)
	_emit_scroll_changed()
	queue_redraw()
elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
	if mb.shift_pressed:
		scroll_offset_ms = minf(_get_total_ms(), scroll_offset_ms + 50)
	else:
		pixels_per_ms = maxf(pixels_per_ms / 1.15, 0.3)
	_emit_scroll_changed()
	queue_redraw()
```

Add the helper:

```gdscript
func _emit_scroll_changed() -> void:
	scroll_changed.emit(scroll_offset_ms, _get_total_ms(), get_visible_ms())
```

**Step 3: Add HScrollBar in attack_composer.gd**

In `attack_composer.gd`, after the timeline panel is added to the container (around line 627), add:

```gdscript
_timeline_scrollbar = HScrollBar.new()
_timeline_scrollbar.custom_minimum_size.y = 16
_timeline_scrollbar.min_value = 0
_timeline_scrollbar.max_value = 1000  # Updated dynamically
_timeline_scrollbar.page = 500
_timeline_scrollbar.value_changed.connect(_on_timeline_scrollbar_changed)
_right_vbox.add_child(_timeline_scrollbar)
```

Add the variable declaration near the other UI vars (around line 75):
```gdscript
var _timeline_scrollbar: HScrollBar
```

**Step 4: Wire up bidirectional sync**

Connect the timeline's `scroll_changed` signal:
```gdscript
_timeline_panel.scroll_changed.connect(_on_timeline_scroll_changed)
```

Add the handler functions:

```gdscript
func _on_timeline_scrollbar_changed(value: float) -> void:
	_timeline_panel.set_scroll_from_scrollbar(value)


func _on_timeline_scroll_changed(offset_ms: float, total_ms: float, visible_ms: float) -> void:
	_timeline_scrollbar.max_value = maxf(total_ms, visible_ms)
	_timeline_scrollbar.page = visible_ms
	_timeline_scrollbar.set_value_no_signal(offset_ms)
```

**Step 5: Commit**
```
git commit -m "feat(attack-composer): add horizontal scrollbar to timeline"
```

---

## Task 4: Update TimelinePanel for DirectionSequence

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd` (throughout)

The timeline panel currently accesses `composition.frames` and `composition.movement_*` / `composition.damage_frame` directly. It needs to work with a `DirectionSequence` instead.

**Step 1: Replace composition with sequence reference**

Change the state variable at line 42:

```gdscript
# Old:
var composition: AttackCompositionData = null
# New:
var sequence: DirectionSequence = null
```

**Step 2: Update all frame references**

Search-and-replace throughout the file:
- `composition.frames` → `sequence.frames`
- `composition.movement_start_frame` → `sequence.movement_start_frame`
- `composition.movement_end_frame` → `sequence.movement_end_frame`
- `composition.damage_frame` → `sequence.damage_frame`
- `composition.movement_type` → `sequence.movement_type`
- `composition == null` → `sequence == null`

The `_draw()` null/empty check (line 69):
```gdscript
if sequence == null or sequence.frames.is_empty():
```

`_get_total_ms()` (line 101):
```gdscript
func _get_total_ms() -> float:
	if sequence == null:
		return 0.0
	return float(sequence.get_total_duration_ms())
```

The `_handle_sub_track_click` damage handler (line 479):
```gdscript
sequence.damage_frame = idx
```

**Step 3: Commit**
```
git commit -m "refactor(attack-composer): update TimelinePanel to use DirectionSequence"
```

---

## Task 5: Add "All" Direction Button and Direction State

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Add direction state variables**

Near the existing direction vars (around lines 36-37):

```gdscript
var _edit_all_directions: bool = false  # When true, edits apply to all directions
```

**Step 2: Add "All" button to direction buttons**

In the direction button creation code (around line 556), add the "All" button before the direction loop:

```gdscript
# "All" button
_all_directions_btn = _make_button("All", _on_all_directions_pressed)
_all_directions_btn.custom_minimum_size.x = 40
controls_inner.add_child(_all_directions_btn)

# Direction buttons
for dir_name in DIRECTIONS:
	var short: String = dir_name.substr(0, 1).to_upper()
	var btn := _make_button(short, _on_direction_pressed.bind(dir_name))
	btn.custom_minimum_size.x = 32
	_direction_buttons.append(btn)
	controls_inner.add_child(btn)
```

Add variable declaration:
```gdscript
var _all_directions_btn: Button
```

**Step 3: Implement the "All" toggle and direction switch handlers**

```gdscript
func _on_all_directions_pressed() -> void:
	_edit_all_directions = true
	_preview_direction = "down"  # Show down as reference in All mode
	_switch_to_direction("down")
	_update_direction_highlight()


func _on_direction_pressed(dir: String) -> void:
	_edit_all_directions = false
	_preview_direction = dir
	_switch_to_direction(dir)
	_update_direction_highlight()
```

**Step 4: Implement _switch_to_direction helper**

This sets the timeline's sequence, clamps frame selection, and refreshes UI:

```gdscript
func _switch_to_direction(dir: String) -> void:
	if _current_composition == null:
		return
	var seq := _current_composition.get_sequence(dir)
	if seq == null:
		return
	_timeline_panel.sequence = seq
	_timeline_panel.frame_thumbnails = _get_thumbnails_for_direction(dir)
	# Clamp selection to new direction's frame count
	var max_idx := seq.frames.size() - 1
	if _selected_frame > max_idx:
		_selected_frame = maxi(0, max_idx)
		_selected_frames = [_selected_frame]
		_preview_frame_index = _selected_frame
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()
```

**Step 5: Update direction highlight**

Update `_update_direction_highlight()` to handle the "All" button with a distinct gold color:

```gdscript
func _update_direction_highlight() -> void:
	# Reset all direction buttons
	for btn in _direction_buttons:
		btn.add_theme_color_override("font_color", C_TEXT)
	_all_directions_btn.add_theme_color_override("font_color", C_TEXT)

	if _edit_all_directions:
		_all_directions_btn.add_theme_color_override("font_color", Color("#FFD700"))  # Gold
	else:
		for i in DIRECTIONS.size():
			if DIRECTIONS[i] == _preview_direction:
				_direction_buttons[i].add_theme_color_override("font_color", C_ACCENT)
```

**Step 6: Commit**
```
git commit -m "feat(attack-composer): add All/D/U/R direction buttons with toggle"
```

---

## Task 6: Update Frame and Sequence Property Editors for Direction-Aware Editing

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

This is the core change: every property edit must go through the active direction's sequence (or all directions in "All" mode).

**Step 1: Add helper to get active sequence(s)**

```gdscript
## Returns the active DirectionSequence for the current preview direction.
func _active_sequence() -> DirectionSequence:
	if _current_composition == null:
		return null
	return _current_composition.get_sequence(_preview_direction)


## Returns direction keys to edit: all 3 if "All" mode, else just the active one.
func _edit_directions() -> Array[String]:
	if _edit_all_directions:
		return AttackCompositionData.DIRECTIONS.duplicate()
	return [_preview_direction]
```

**Step 2: Update _get_target_frames to be direction-aware**

The existing `_get_target_frames()` stays the same (returns frame indices), but callers must now apply edits per-direction. Add a helper for multi-direction frame edits:

```gdscript
func _apply_to_target_frames(callable: Callable) -> void:
	var indices := _get_target_frames()
	if indices.is_empty():
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		for idx in indices:
			if idx < seq.frames.size():
				callable.call(seq.frames[idx])
```

**Step 3: Update all property change handlers**

Example — `_on_duration_changed` (line 2001):
```gdscript
func _on_duration_changed(value: float) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.duration_ms = int(value))
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(value, 1))
	var seq := _active_sequence()
	if seq:
		_total_duration_label.text = "Total: %.3fs" % seq.get_total_duration_sec()
	_timeline_panel.queue_redraw()
	_timeline_panel._emit_scroll_changed()
```

Apply the same pattern to all frame-property handlers:
- `_on_weapon_visible_toggled` → `_apply_to_target_frames(func(f): f.weapon_visible = value)`
- `_on_weapon_z_front_toggled` → `_apply_to_target_frames(func(f): f.weapon_z_front = value)`
- `_on_echo_toggled` → `_apply_to_target_frames(func(f): f.echo_enabled = value)`
- `_on_echo_count_changed` → `_apply_to_target_frames(func(f): f.echo_count = int(value))`
- `_on_echo_opacity_start_changed` → `_apply_to_target_frames(func(f): f.echo_opacity_start = value)`
- `_on_echo_opacity_end_changed` → `_apply_to_target_frames(func(f): f.echo_opacity_end = value)`
- `_on_echo_spacing_changed` → `_apply_to_target_frames(func(f): f.echo_spacing_px = value)`
- `_on_effect_selected` → apply effect_id per direction
- `_on_effect_anchor_selected` → `_apply_to_target_frames(func(f): f.effect_anchor = text)`
- `_on_effect_offset_x_changed` / `_on_effect_offset_y_changed` → apply per direction
- `_on_effect_z_changed` → `_apply_to_target_frames(func(f): f.effect_z_index = int(value))`
- `_on_effect_rotation_changed` → `_apply_to_target_frames(func(f): f.effect_rotation_deg = value)`

**Step 4: Update sequence-level property handlers**

For sequence properties (movement, damage frame), apply to all directions if in "All" mode:

```gdscript
func _on_seq_prop_changed(_value: float = 0) -> void:
	if _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		seq.movement_distance = _movement_distance_spin.value
		seq.movement_start_frame = int(_movement_start_spin.value)
		seq.movement_end_frame = int(_movement_end_spin.value)
	_timeline_panel.queue_redraw()


func _on_movement_type_selected(index: int) -> void:
	if _current_composition == null:
		return
	_push_undo()
	var mt: String = _movement_type_dropdown.get_item_text(index)
	if mt == "none":
		mt = ""
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		seq.movement_type = mt
	_timeline_panel.queue_redraw()


func _on_damage_frame_changed(value: float) -> void:
	if _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		seq.damage_frame = int(value)
	_timeline_panel.queue_redraw()
```

**Step 5: Update _update_frame_props_ui**

The UI sync function (line 1926) must read from the active direction's sequence:

```gdscript
func _update_frame_props_ui() -> void:
	var seq := _active_sequence()
	var has_data := seq != null and _selected_frame >= 0 and _selected_frame < seq.frames.size()
	_frame_section_wrapper.visible = has_data
	var seq_wrapper := _seq_props_container.get_parent()
	seq_wrapper.visible = has_data
	if not has_data:
		return

	var frame := seq.frames[_selected_frame]
	# ... (rest of UI sync uses `frame` as before, and reads seq props from `seq`)

	# Sequence props section:
	var max_idx := seq.frames.size() - 1
	_movement_start_spin.max_value = max_idx
	_movement_end_spin.max_value = max_idx
	_damage_frame_spin.max_value = max_idx
	_movement_distance_spin.set_value_no_signal(seq.movement_distance)
	_movement_start_spin.set_value_no_signal(seq.movement_start_frame)
	_movement_end_spin.set_value_no_signal(seq.movement_end_frame)
	_damage_frame_spin.set_value_no_signal(seq.damage_frame)

	var mt := seq.movement_type
	for i in _movement_type_dropdown.item_count:
		if _movement_type_dropdown.get_item_text(i) == (mt if mt != "" else "none"):
			_movement_type_dropdown.select(i)
			break

	_total_duration_label.text = "Total: %.3fs" % seq.get_total_duration_sec()
```

**Step 6: Commit**
```
git commit -m "feat(attack-composer): direction-aware frame and sequence property editing"
```

---

## Task 7: Update Undo/Redo System

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd` (lines 254-327)

**Step 1: Update _push_undo to snapshot all direction sequences**

```gdscript
func _push_undo() -> void:
	if _current_composition == null:
		return
	var comp_snapshot := AttackCompositionData.new()
	comp_snapshot.composition_id = _current_composition.composition_id
	comp_snapshot.display_name = _current_composition.display_name
	comp_snapshot.runtime_template_id = _current_composition.runtime_template_id
	comp_snapshot.animation_name = _current_composition.animation_name
	comp_snapshot.locks_movement = _current_composition.locks_movement

	# Deep-copy all direction sequences
	for dir_name in AttackCompositionData.DIRECTIONS:
		var src_seq := _current_composition.get_sequence(dir_name)
		if src_seq == null:
			continue
		var seq_copy := DirectionSequence.new()
		seq_copy.movement_type = src_seq.movement_type
		seq_copy.movement_distance = src_seq.movement_distance
		seq_copy.movement_start_frame = src_seq.movement_start_frame
		seq_copy.movement_end_frame = src_seq.movement_end_frame
		seq_copy.damage_frame = src_seq.damage_frame
		for frame in src_seq.frames:
			var frame_copy := frame.duplicate()
			if frame.alpha_mask != null:
				frame_copy.alpha_mask = frame.alpha_mask.duplicate()
			seq_copy.frames.append(frame_copy)
		comp_snapshot.direction_sequences[dir_name] = seq_copy

	var entry: Dictionary = {"composition": comp_snapshot}

	# Snapshot frame images when anchor/alpha drawing is active
	if _anchor_draw_enabled and not _frame_images.is_empty():
		var images_snapshot: Dictionary = {}
		for dir_name in _frame_images:
			var originals: Array = _frame_images[dir_name]
			var copies: Array[Image] = []
			for img: Image in originals:
				copies.append(img.duplicate())
			images_snapshot[dir_name] = copies
		entry["images"] = images_snapshot

	_undo_stack.append(entry)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.remove_at(0)
	_update_undo_button()
```

**Step 2: Update _undo to restore all direction sequences**

```gdscript
func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	var entry: Dictionary = _undo_stack.pop_back()
	var snapshot: AttackCompositionData = entry["composition"]

	_current_composition.composition_id = snapshot.composition_id
	_current_composition.display_name = snapshot.display_name
	_current_composition.runtime_template_id = snapshot.runtime_template_id
	_current_composition.animation_name = snapshot.animation_name
	_current_composition.locks_movement = snapshot.locks_movement

	# Restore all direction sequences
	_current_composition.direction_sequences.clear()
	for dir_name in snapshot.direction_sequences:
		_current_composition.direction_sequences[dir_name] = snapshot.direction_sequences[dir_name]

	# Restore frame images if snapshot includes them
	if entry.has("images"):
		var images_snapshot: Dictionary = entry["images"]
		for dir_name in images_snapshot:
			_frame_images[dir_name] = images_snapshot[dir_name]
			var new_textures: Array[ImageTexture] = []
			for img: Image in images_snapshot[dir_name]:
				new_textures.append(ImageTexture.create_from_image(img))
			_frame_textures[dir_name] = new_textures

	# Adjust selection to active direction
	var seq := _active_sequence()
	if seq:
		_selected_frame = clampi(_selected_frame, 0, maxi(0, seq.frames.size() - 1))
	else:
		_selected_frame = 0
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame
	_switch_to_direction(_preview_direction)
	# ... rest of undo refresh (update buttons, UI, etc.)
```

**Step 3: Commit**
```
git commit -m "refactor(attack-composer): update undo system for per-direction sequences"
```

---

## Task 8: Update Load/Save and Default Composition Creation

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Update spritesheet loading / default composition creation**

Where `AttackCompositionData.create_default(frame_count)` is called (around line 1460), it already returns a composition with all 3 directions initialized. Ensure the follow-up code sets the initial direction:

```gdscript
_current_composition = AttackCompositionData.create_default(frame_count)
_current_composition.animation_name = anim_folder.to_lower()
_current_composition.composition_id = "%s_%s" % [model_name, anim_folder.to_lower()]
_current_composition.display_name = "%s %s" % [model_name, anim_folder]

_preview_direction = "down"
_edit_all_directions = false
_preview_frame_index = 0
_selected_frame = 0
_selected_frames = [0]
_undo_stack.clear()
_update_undo_button()
_switch_to_direction("down")
```

**Step 2: Update composition loading with migration**

In `_on_load_composition_pressed` (around line 2244), after loading the resource, add migration:

```gdscript
var comp: AttackCompositionData = loaded
# Migrate old format if needed
comp.migrate_from_legacy()
comp.ensure_all_directions()
```

Then update all the post-load code to use the new direction system:
- Replace `_timeline_panel.composition = _current_composition` with `_switch_to_direction("down")`
- Replace references to `_current_composition.frames` with `_active_sequence().frames`

**Step 3: Update save — no structural changes needed**

The save function (`_on_save_composition`, line 2174) just calls `ResourceSaver.save(_current_composition, path)`. Since `AttackCompositionData` now stores `direction_sequences`, this works automatically. Godot's Resource serializer handles nested Resources.

**Step 4: Commit**
```
git commit -m "feat(attack-composer): update load/save with legacy migration support"
```

---

## Task 9: Update CompositionConverter for Per-Direction Conversion

**Files:**
- Modify: `scripts/tools/attack_composer/composition_converter.gd`

**Step 1: Make convert() direction-aware**

The converter needs to accept a direction parameter and pull from the appropriate `DirectionSequence`:

```gdscript
## Convert a specific direction of an AttackCompositionData into an AbilityVisualData.
static func convert(comp: AttackCompositionData, direction: String = "down") -> AbilityVisualData:
	var data := AbilityVisualData.new()
	data.template_id = comp.composition_id
	data.display_name = comp.display_name
	data.locks_movement = comp.locks_movement

	var seq := comp.get_sequence(direction)
	if seq == null or seq.frames.is_empty():
		data.phases = []
		return data

	var phases: Array[AbilityVisualPhase] = []
	var frames := seq.frames

	# Group consecutive frames by weapon_visible state
	var groups := _group_frames_by_weapon(frames)

	var prev_weapon_visible := false
	for group in groups:
		var start_idx: int = group["start"]
		var end_idx: int = group["end"]
		var weapon_visible: bool = group["weapon_visible"]

		if weapon_visible != prev_weapon_visible:
			phases.append(AbilityVisualPhase.create_weapon_visibility(weapon_visible))
		prev_weapon_visible = weapon_visible

		# ... (rest of phase building uses `seq.movement_*` and `seq.damage_frame`
		#      instead of `comp.movement_*` and `comp.damage_frame`)

	# ... (rest unchanged, just using `seq` for movement/damage references)
```

Replace all `comp.movement_*` and `comp.damage_frame` references with `seq.movement_*` and `seq.damage_frame`.

**Step 2: Update save runtime data to export all 3 directions**

In `attack_composer.gd`, wherever runtime data is saved (the save runtime button handler), loop over all directions:

```gdscript
for dir_name in AttackCompositionData.DIRECTIONS:
	var runtime_data := CompositionConverter.convert(_current_composition, dir_name)
	var runtime_id := _template_id_input.text if not _template_id_input.text.is_empty() else _current_composition.composition_id
	var path := "%s/%s_%s.tres" % [SEQUENCES_DIR, runtime_id, dir_name]
	ResourceSaver.save(runtime_data, path)
```

**Step 3: Commit**
```
git commit -m "feat(attack-composer): direction-aware composition conversion and export"
```

---

## Task 10: Update Remaining References (Preview, Playback, Frame Operations)

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

This task covers all remaining places that reference `_current_composition.frames` or the old flat sequence properties. These need to go through `_active_sequence()`.

**Step 1: Global search and replace pattern**

Every instance of `_current_composition.frames` must become `_active_sequence().frames` (with null checks). Every instance of `_current_composition.movement_*` or `_current_composition.damage_frame` must become `_active_sequence().movement_*` etc.

Key locations to update:
- `_update_preview_frame()` (line 1501) — already uses `_frame_textures[_preview_direction]`, but frame count reference
- `_on_timeline_frame_selected` (line 1830) — fine as-is (uses indices)
- `_on_timeline_duration_changed` — update total duration label from active sequence
- `_delete_selected_frame` — delete from active sequence (or all in "All" mode)
- `_on_add_frame` — add to active sequence (or all in "All" mode)
- Playback `_process()` — use active sequence's total duration for looping
- Frame thumbnail generation — `_get_thumbnails_for_direction(dir)` helper needed
- Alpha mask painting — uses `_current_composition.frames[idx].alpha_mask`, update to use active sequence

**Step 2: Implement `_get_thumbnails_for_direction`**

```gdscript
func _get_thumbnails_for_direction(dir: String) -> Array[ImageTexture]:
	if not _frame_textures.has(dir):
		return []
	var textures: Array = _frame_textures[dir]
	var thumbnails: Array[ImageTexture] = []
	for tex in textures:
		thumbnails.append(tex)
	return thumbnails
```

**Step 3: Update delete frame**

When deleting a frame, delete from all directions in "All" mode, or just the active direction:

```gdscript
func _delete_selected_frame() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	if seq.frames.size() <= 1:
		_set_status("Cannot delete the last frame.")
		return
	_push_undo()
	for dir_name in _edit_directions():
		var s := _current_composition.get_sequence(dir_name)
		if s and _selected_frame < s.frames.size() and s.frames.size() > 1:
			s.frames.remove_at(_selected_frame)
			# Adjust sequence-level indices
			if s.damage_frame >= s.frames.size():
				s.damage_frame = -1
			if s.movement_start_frame >= s.frames.size():
				s.movement_start_frame = -1
			if s.movement_end_frame >= s.frames.size():
				s.movement_end_frame = -1
	# Refresh
	seq = _active_sequence()
	_selected_frame = clampi(_selected_frame, 0, maxi(0, seq.frames.size() - 1))
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame
	_switch_to_direction(_preview_direction)
```

**Step 4: Update playback loop**

In `_process()`, where it checks `_playback_ms >= total_duration`, use active sequence:

```gdscript
var seq := _active_sequence()
if seq == null:
	return
var total_ms := float(seq.get_total_duration_ms())
if _playback_ms >= total_ms:
	_playback_ms = 0.0
```

**Step 5: Commit**
```
git commit -m "feat(attack-composer): update all remaining frame references for per-direction model"
```

---

## Task 11: Verification

**Step 1: Open the attack composer in Godot editor**

Run the tools scene and verify:
- Timeline scrollbar appears below the timeline and scrolls the view
- Mouse wheel zoom still works, scrollbar thumb resizes accordingly
- "All | D | U | R" buttons appear below the preview viewport
- Clicking D/U/R switches direction and shows that direction's frames
- Clicking "All" highlights gold, shows "down" reference
- Editing a frame property in "All" mode affects all directions
- Editing in single direction mode only affects that direction
- Undo works correctly across direction switches
- Loading old compositions migrates properly
- Saving and reloading preserves per-direction data
- Frame delete in "All" mode works (skips directions with fewer frames)
- Playback loops correctly per active direction's duration

**Step 2: Final commit if any fixes needed**
```
git commit -m "fix(attack-composer): address issues found during verification"
```
