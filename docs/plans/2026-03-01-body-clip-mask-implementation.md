# Body Clip Mask Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace per-weapon alpha masking with body silhouette clipping so one mask per animation frame works for ALL weapons.

**Architecture:** Body clip masks are body-frame-sized binary images (FORMAT_R8, 255=clip/0=pass). They can be auto-generated from body sprite alpha or hand-painted in the Attack Composer. At runtime, weapon pixels overlapping body clip regions are fully hidden via coordinate-space transform. Z-ordering is removed entirely — weapon always renders in front.

**Tech Stack:** GDScript, Godot 4 Image API, Attack Composer tool editor

---

### Task 1: Update CompositionFrame Data Model

**Files:**
- Modify: `scripts/tools/attack_composer/composition_frame.gd:12-13,45-48`

**Step 1: Replace old fields with new body clip mask fields**

Replace the `weapon_z_front` field (line 13) and `alpha_mask` field (lines 45-48) with new body clip mask fields:

```gdscript
# REMOVE these two fields:
# @export var weapon_z_front: bool = true          (line 13)
# @export var alpha_mask: Image = null              (lines 45-48)

# ADD these two fields (in place of alpha_mask, lines 45-48):
## Per-frame body clip mask for weapon occlusion.
## Same dimensions as body sprite frame. null = no clipping.
## FORMAT_R8: 255 = body pixel (clips weapon), 0 = no clip.
@export var body_clip_mask: Image = null

## When true, auto-generate body_clip_mask from body sprite alpha on export/preview.
## When false, use hand-painted body_clip_mask (or null = no clipping).
@export var body_clip_auto: bool = false
```

**Step 2: Commit**

```bash
git add scripts/tools/attack_composer/composition_frame.gd
git commit -m "refactor(data): replace weapon alpha_mask with body_clip_mask in CompositionFrame"
```

---

### Task 2: Update AbilityVisualPlayer Signals and Logic

**Files:**
- Modify: `scripts/combat/ability_visual_player.gd:33-34,45-46,166-167,229,268-276,299-311,403-404,519-520,607`

**Step 1: Replace weapon_z_changed signal with body_clip_masks_changed**

At line 33-34, remove the `weapon_z_changed` signal. At lines 45-46, rename `weapon_alpha_masks_changed` to `body_clip_masks_changed`:

```gdscript
# REMOVE (line 33-34):
# signal weapon_z_changed(in_front: bool)

# RENAME (line 45-46):
## Emitted when composed phase starts with body clip mask data (frame_index → Image)
signal body_clip_masks_changed(masks: Dictionary)
```

**Step 2: Remove `_check_weapon_z_for_current_frame()` and rename `_emit_weapon_alpha_masks()`**

Delete the entire `_check_weapon_z_for_current_frame()` function (lines 268-276).

Rename `_emit_weapon_alpha_masks()` to `_emit_body_clip_masks()` and update it to read `"body_clip_masks"` from context_data (lines 299-311):

```gdscript
func _emit_body_clip_masks() -> void:
	if _frame_timing_phase == null:
		body_clip_masks_changed.emit({})
		return
	var entries: Array = _frame_timing_phase.context_data.get("body_clip_masks", [])
	if entries.is_empty():
		body_clip_masks_changed.emit({})
		return
	var masks: Dictionary = {}
	for entry in entries:
		var img := Image.create_from_data(entry["width"], entry["height"], false, Image.FORMAT_R8, entry["data"])
		masks[entry["frame_index"]] = img
	body_clip_masks_changed.emit(masks)
```

**Step 3: Remove all calls to `_check_weapon_z_for_current_frame()`**

Remove the call at line 229 in `_tick_frame_timing()`.
Remove the call at line 403 in `_execute_phase_in_slot()`.
Remove the call at line 519 in `_execute_phase_single()`.

**Step 4: Rename all calls from `_emit_weapon_alpha_masks()` to `_emit_body_clip_masks()`**

Update calls at lines 404 and 520.

**Step 5: Update cancel() and _finish_sequence() to use new signal name**

At line 166 in `cancel()`:
```gdscript
body_clip_masks_changed.emit({})
```

At line 607 in `_finish_sequence()`:
```gdscript
body_clip_masks_changed.emit({})
```

**Step 6: Commit**

```bash
git add scripts/combat/ability_visual_player.gd
git commit -m "refactor(signals): replace weapon_z/alpha signals with body_clip_masks in AbilityVisualPlayer"
```

---

### Task 3: Update CharacterVisuals — Remove Z-Override, Add Body Clip Algorithm

**Files:**
- Modify: `scripts/combat/character_visuals.gd:53-58,355-494,716-786,827-840`

**Step 1: Replace state variables**

At lines 53-58, replace old variables:

```gdscript
# REMOVE:
# var _weapon_z_override: int = 0                   (line 54)
# var _weapon_alpha_masks: Dictionary = {}           (line 57)
# var _weapon_alpha_cache: Dictionary = {}           (line 58)

# ADD (in place of lines 57-58):
## Per-frame body clip masks for weapon occlusion (from Attack Composer)
var _body_clip_masks: Dictionary = {}   # frame_index → Image (body-frame-sized)
var _body_clip_cache: Dictionary = {}   # frame_index → ImageTexture (pre-composited)
```

**Step 2: Remove z-override logic from `_update_weapon_position()`**

In the rotation path (lines 434-438), replace z-override logic with constant z=1:
```gdscript
		# Weapon always renders in front — body clip mask handles occlusion
		weapon_sprite.z_index = 1
```

In the legacy path (lines 469-473), same replacement:
```gdscript
	# Weapon always renders in front — body clip mask handles occlusion
	weapon_sprite.z_index = 1
```

**Step 3: Replace `_apply_weapon_alpha_mask()` call with `_apply_body_clip_mask()` call**

At line 442, change `_apply_weapon_alpha_mask()` to `_apply_body_clip_mask()`.

**Step 4: Replace `_apply_weapon_alpha_mask()` function with `_apply_body_clip_mask()`**

Replace lines 744-786 with:

```gdscript
## Apply per-frame body clip mask to the weapon texture.
## Body clip masks are body-frame-sized binary images (255=clip, 0=pass).
## For each weapon pixel, we transform it into body-frame coordinates and check
## if it falls on a clipped region. If so, the weapon pixel is fully hidden.
func _apply_body_clip_mask() -> void:
	if _body_clip_masks.is_empty() or body_sprite == null or weapon_sprite == null:
		return
	var current_frame: int = body_sprite.frame
	if not _body_clip_masks.has(current_frame):
		return
	if _body_clip_cache.has(current_frame):
		weapon_sprite.texture = _body_clip_cache[current_frame]
		return

	# Use "right" texture as base (the rotation path always uses "right")
	var right_tex: Texture2D = _weapon_texture_set.get("right")
	if right_tex == null:
		return
	var base_img: Image = right_tex.get_image()
	if base_img == null:
		return
	var mask: Image = _body_clip_masks[current_frame]
	var composited: Image = base_img.duplicate() as Image
	if composited == null:
		return
	if composited.is_compressed():
		composited.decompress()

	# Get body frame size for coordinate transform
	var body_tex: Texture2D = body_sprite.sprite_frames.get_frame_texture(
		body_sprite.animation, current_frame)
	if body_tex == null:
		return
	var body_size := body_tex.get_size()
	var weapon_size := Vector2(composited.get_width(), composited.get_height())

	# Weapon transform parameters (in local-space, centered at body origin)
	var wp_pos: Vector2 = weapon_sprite.position  # anchor position in local-space
	var wp_rot: float = weapon_sprite.rotation
	var wp_ofs: Vector2 = weapon_sprite.offset
	var wp_flip_h: bool = weapon_sprite.flip_h

	# Transform each weapon pixel to body-frame pixel coords
	for wy in range(composited.get_height()):
		for wx in range(composited.get_width()):
			# Skip fully transparent weapon pixels
			var wpx: Color = composited.get_pixel(wx, wy)
			if wpx.a < 0.01:
				continue

			# Weapon pixel in weapon-local space (centered)
			var weapon_local := Vector2(wx, wy) - weapon_size / 2.0 + wp_ofs
			if wp_flip_h:
				weapon_local.x = -weapon_local.x

			# Apply rotation and position to get body-local coords
			var body_local: Vector2 = weapon_local.rotated(wp_rot) + wp_pos

			# Convert to body-frame pixel coords (0,0 = top-left)
			var body_px := Vector2i(
				int(body_local.x + body_size.x / 2.0),
				int(body_local.y + body_size.y / 2.0)
			)

			# Check bounds and mask
			if body_px.x < 0 or body_px.x >= int(body_size.x):
				continue
			if body_px.y < 0 or body_px.y >= int(body_size.y):
				continue
			if body_px.x >= mask.get_width() or body_px.y >= mask.get_height():
				continue

			# If mask says "body here" (clip), hide this weapon pixel
			if mask.get_pixel(body_px.x, body_px.y).r > 0.5:
				wpx.a = 0.0
				composited.set_pixel(wx, wy, wpx)

	var cached_tex := ImageTexture.create_from_image(composited)
	_body_clip_cache[current_frame] = cached_tex
	weapon_sprite.texture = cached_tex
```

**Step 5: Update signal handlers**

Replace `_on_weapon_z_changed()` and `_on_weapon_alpha_masks_changed()` (lines 716-741):

```gdscript
# REMOVE _on_weapon_z_changed (lines 716-718)

# REPLACE _on_weapon_alpha_masks_changed (lines 735-741):
## Handle body clip mask data from AbilityVisualPlayer
func _on_body_clip_masks_changed(masks: Dictionary) -> void:
	_body_clip_masks = masks
	_body_clip_cache.clear()
	if not masks.is_empty():
		Debug.log("Visuals", "Received %d body clip masks, keys: %s" % [masks.size(), str(masks.keys())])
	else:
		Debug.log("Visuals", "Body clip masks cleared")
```

Update `_on_sequence_finished()` (lines 722-726):
```gdscript
func _on_sequence_finished(_template_id: String) -> void:
	_body_clip_masks.clear()
	_body_clip_cache.clear()
	_composition_anchors.clear()
```

**Step 6: Update `connect_to_visual_player()`**

At lines 827-840, replace signal connections:

```gdscript
func connect_to_visual_player(visual_player: Node) -> void:
	visual_player.weapon_visibility_changed.connect(set_weapon_visible)
	visual_player.play_body_animation.connect(_on_play_body_animation)
	visual_player.effect_event.connect(_on_effect_event)
	if visual_player.has_signal("echo_requested"):
		visual_player.echo_requested.connect(_on_echo_requested)
	# weapon_z_changed removed — weapon always z=1
	if visual_player.has_signal("sequence_finished"):
		visual_player.sequence_finished.connect(_on_sequence_finished)
	if visual_player.has_signal("body_clip_masks_changed"):
		visual_player.body_clip_masks_changed.connect(_on_body_clip_masks_changed)
	if visual_player.has_signal("composition_anchors_changed"):
		visual_player.composition_anchors_changed.connect(_on_composition_anchors_changed)
```

**Step 7: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(runtime): body clip mask algorithm replaces weapon alpha mask + removes z-override"
```

---

### Task 4: Update CompositionConverter Export Pipeline

**Files:**
- Modify: `scripts/tools/attack_composer/composition_converter.gd:24-34,135-149,234-235`

**Step 1: Replace alpha mask collection with body clip mask collection**

Replace lines 24-34 (alpha_mask_data collection):

```gdscript
	# Collect per-frame body clip masks (body occlusion painted/auto-generated in the composer)
	var body_clip_data: Array = []
	for i in range(frames.size()):
		var frame := frames[i]
		var mask: Image = null
		if frame.body_clip_auto and i < frame_images.size():
			# Auto-generate: any body pixel with alpha > 0 becomes a clip pixel
			mask = _generate_body_clip_mask(frame_images[i])
		elif frame.body_clip_mask != null:
			mask = frame.body_clip_mask
		if mask != null:
			body_clip_data.append({
				"frame_index": i,
				"width": mask.get_width(),
				"height": mask.get_height(),
				"data": mask.get_data(),  # PackedByteArray
			})
```

**Step 2: Remove weapon_behind_frames collection and replace alpha mask attachment**

Remove lines 135-141 (weapon_behind_frames collection).

Replace lines 143-149 (alpha mask attachment):

```gdscript
		# Attach body clip masks that fall within this group
		var group_clip_masks: Array = []
		for clip_entry in body_clip_data:
			if clip_entry["frame_index"] >= start_idx and clip_entry["frame_index"] <= end_idx:
				group_clip_masks.append(clip_entry)
		if not group_clip_masks.is_empty():
			body_phase.context_data["body_clip_masks"] = group_clip_masks
```

**Step 3: Remove weapon_behind_frames from debug string**

At line 234-235, remove:
```gdscript
# REMOVE:
# if p.context_data.has("weapon_behind_frames"):
#     desc += " z_behind=%s" % str(p.context_data["weapon_behind_frames"])
```

**Step 4: Add `_generate_body_clip_mask()` helper function**

Add at the end of the file (after `_rgb_approx`):

```gdscript
## Generate a binary body clip mask from a body frame image.
## Any pixel with alpha > 0 becomes a clip pixel (255), otherwise 0.
static func _generate_body_clip_mask(body_img: Image) -> Image:
	var w := body_img.get_width()
	var h := body_img.get_height()
	var mask := Image.create(w, h, false, Image.FORMAT_R8)
	mask.fill(Color(0, 0, 0))  # Default: no clip
	for y in range(h):
		for x in range(w):
			if body_img.get_pixel(x, y).a > 0.01:
				mask.set_pixel(x, y, Color(1, 0, 0))  # R=1 → clip (255)
	return mask
```

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/composition_converter.gd
git commit -m "feat(export): export body_clip_masks instead of weapon_alpha_masks in CompositionConverter"
```

---

### Task 5: Update Attack Composer UI — Body Clip Mask Painting

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

This is the largest task. It touches the UI build, state variables, input handling, painting logic, and preview visualization.

**Step 1: Replace alpha painting state variables (lines 68-75)**

```gdscript
# ── Body clip mask painting state ────────────────────────────────────
var _body_clip_paint_enabled: bool = false
var _body_clip_brush_size: int = 1
var _body_clip_paint_erase: bool = false  # false=paint clip, true=erase clip
var _body_clip_draw_check: CheckButton = null
var _body_clip_auto_check: CheckButton = null
var _body_clip_buttons_container: VBoxContainer = null
var _body_clip_brush_buttons: Array[Button] = []
```

Also remove the `_weapon_z_front_check` variable declaration (line 106).

**Step 2: Replace alpha mask UI build (lines 1072-1077 and 1131-1225)**

Remove the weapon_z_front checkbox build (lines 1072-1077).

Replace the alpha draw section (lines 1131-1225) with:

```gdscript
	_body_clip_draw_check = CheckButton.new()
	_body_clip_draw_check.text = "Body Clip Mask"
	_body_clip_draw_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_body_clip_draw_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_body_clip_draw_check.toggled.connect(_on_body_clip_draw_toggled)
	section.add_child(_body_clip_draw_check)

	_body_clip_buttons_container = VBoxContainer.new()
	_body_clip_buttons_container.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.visible = false
	section.add_child(_body_clip_buttons_container)

	# Auto-generate toggle
	_body_clip_auto_check = CheckButton.new()
	_body_clip_auto_check.text = "Auto from Body"
	_body_clip_auto_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_body_clip_auto_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_body_clip_auto_check.toggled.connect(_on_body_clip_auto_toggled)
	_body_clip_buttons_container.add_child(_body_clip_auto_check)

	# Paint/Erase toggle row
	var clip_mode_hbox := HBoxContainer.new()
	clip_mode_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_mode_hbox)
	var paint_btn := Button.new()
	paint_btn.text = "Paint Clip"
	paint_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	paint_btn.custom_minimum_size.y = 28
	paint_btn.add_theme_font_size_override("font_size", FONT_HINT)
	paint_btn.pressed.connect(func(): _body_clip_paint_erase = false; _update_clip_mode_highlight())
	clip_mode_hbox.add_child(paint_btn)
	var erase_btn := Button.new()
	erase_btn.text = "Erase Clip"
	erase_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	erase_btn.custom_minimum_size.y = 28
	erase_btn.add_theme_font_size_override("font_size", FONT_HINT)
	erase_btn.pressed.connect(func(): _body_clip_paint_erase = true; _update_clip_mode_highlight())
	clip_mode_hbox.add_child(erase_btn)

	# Brush size buttons row
	var clip_brush_label := Label.new()
	clip_brush_label.text = "Brush Size"
	clip_brush_label.add_theme_font_size_override("font_size", FONT_HINT)
	clip_brush_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_body_clip_buttons_container.add_child(clip_brush_label)

	var clip_brush_hbox := HBoxContainer.new()
	clip_brush_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_brush_hbox)

	_body_clip_brush_buttons.clear()
	for bsize in [1, 3, 5]:
		var brush_btn := Button.new()
		brush_btn.text = "%dpx" % bsize
		brush_btn.size_flags_horizontal = SIZE_EXPAND_FILL
		brush_btn.custom_minimum_size.y = 28
		brush_btn.add_theme_font_size_override("font_size", FONT_HINT)
		brush_btn.pressed.connect(_on_body_clip_brush_size.bind(bsize))
		clip_brush_hbox.add_child(brush_btn)
		_body_clip_brush_buttons.append(brush_btn)
	_update_body_clip_brush_highlight()

	# Hint label
	var clip_hint := Label.new()
	clip_hint.text = "L-click on body to paint/erase clip region"
	clip_hint.add_theme_font_size_override("font_size", FONT_HINT)
	clip_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_body_clip_buttons_container.add_child(clip_hint)

	# Action buttons row
	var clip_actions_hbox := HBoxContainer.new()
	clip_actions_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_actions_hbox)

	var clear_clip_btn := _make_button("Clear Mask", _on_clear_body_clip)
	clear_clip_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	clip_actions_hbox.add_child(clear_clip_btn)

	var copy_clip_btn := _make_button("Copy → Next", _on_copy_body_clip_to_next)
	copy_clip_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	clip_actions_hbox.add_child(copy_clip_btn)
```

**Step 3: Replace input handling for alpha painting (lines 2762-2774)**

Replace the weapon alpha painting input block with body clip painting:

```gdscript
	# Body clip mask painting mode (handles click + drag)
	if _body_clip_paint_enabled and not _body_clip_paint_erase_only():
		var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var is_drag: bool = event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if is_click or is_drag:
			var pos: Vector2 = event.position
			var body_px := _viewport_to_body_pixel(pos)
			if body_px != Vector2i(-1, -1):
				if is_click:
					_push_undo()
				_paint_body_clip(body_px.x, body_px.y)
				_viewport_container_ref.accept_event()
			return
```

Note: `_body_clip_paint_erase_only()` returns false — this is just the paint/erase guard. Actually, simplify: always handle click, use `_body_clip_paint_erase` to determine paint vs erase. The condition should just be `_body_clip_paint_enabled`.

**Step 4: Add `_viewport_to_body_pixel()` function**

Add near `_viewport_to_weapon_pixel()`:

```gdscript
func _viewport_to_body_pixel(container_pos: Vector2) -> Vector2i:
	if _preview_sprite == null or _preview_sprite.texture == null:
		return Vector2i(-1, -1)
	var container_size := _viewport_container_ref.size
	var vp_size := Vector2(_preview_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return Vector2i(-1, -1)
	# Container -> viewport coords
	var vp_click := container_pos * (vp_size / container_size)
	# Viewport -> body local space (undo position and scale; body has no rotation)
	var local := (vp_click - _preview_sprite.position) / _preview_sprite.scale
	# Local space -> body frame pixel (undo centering)
	var frame_px := local + Vector2(_frame_size) / 2.0
	var px := int(frame_px.x)
	var py := int(frame_px.y)
	if px < 0 or px >= _frame_size.x or py < 0 or py >= _frame_size.y:
		return Vector2i(-1, -1)
	return Vector2i(px, py)
```

**Step 5: Add `_paint_body_clip()` function**

Replace `_paint_weapon_alpha()`:

```gdscript
func _paint_body_clip(px: int, py: int) -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	# Get body frame to check if pixel has content
	var images: Array = _frame_images.get(_preview_direction, [])
	if _preview_frame_index < 0 or _preview_frame_index >= images.size():
		return
	var body_img: Image = images[_preview_frame_index]
	var w := body_img.get_width()
	var h := body_img.get_height()
	# Only paint on non-transparent body pixels
	if body_img.get_pixel(px, py).a < 0.01:
		return
	# Initialize mask if needed
	if frame.body_clip_mask == null:
		frame.body_clip_mask = Image.create(w, h, false, Image.FORMAT_R8)
		frame.body_clip_mask.fill(Color(0, 0, 0))  # Default: no clip
	var radius := (_body_clip_brush_size - 1) / 2
	var paint_color: Color
	if _body_clip_paint_erase:
		paint_color = Color(0, 0, 0)  # Erase: no clip
	else:
		paint_color = Color(1, 0, 0)  # Paint: clip (R=255)
	for bx in range(px - radius, px + radius + 1):
		for by in range(py - radius, py + radius + 1):
			if bx < 0 or bx >= w or by < 0 or by >= h:
				continue
			if body_img.get_pixel(bx, by).a < 0.01:
				continue  # Only paint on visible body pixels
			frame.body_clip_mask.set_pixel(bx, by, paint_color)
	_update_preview_frame()
```

**Step 6: Add callback functions**

Replace the old alpha callback functions with body clip equivalents:

```gdscript
func _on_body_clip_draw_toggled(enabled: bool) -> void:
	_body_clip_paint_enabled = enabled
	_body_clip_buttons_container.visible = enabled
	_update_preview_frame()


func _on_body_clip_auto_toggled(pressed: bool) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.body_clip_auto = pressed)
	_update_preview_frame()


func _on_body_clip_brush_size(bsize: int) -> void:
	_body_clip_brush_size = bsize
	_update_body_clip_brush_highlight()


func _update_body_clip_brush_highlight() -> void:
	for i in _body_clip_brush_buttons.size():
		var btn := _body_clip_brush_buttons[i]
		var sizes := [1, 3, 5]
		if i < sizes.size() and sizes[i] == _body_clip_brush_size:
			btn.add_theme_color_override("font_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")


func _update_clip_mode_highlight() -> void:
	# Visual feedback for paint vs erase mode — implemented inline in UI build
	pass


func _on_clear_body_clip() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	_push_undo()
	var frame := seq.frames[_selected_frame]
	frame.body_clip_mask = null
	frame.body_clip_auto = false
	_update_preview_frame()


func _on_copy_body_clip_to_next() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	if frame.body_clip_mask == null and not frame.body_clip_auto:
		_set_status("No body clip mask on current frame to copy.")
		return
	var next_idx := _selected_frame + 1
	if next_idx >= seq.frames.size():
		_set_status("No next frame to copy to.")
		return
	_push_undo()
	if frame.body_clip_mask != null:
		seq.frames[next_idx].body_clip_mask = frame.body_clip_mask.duplicate()
	seq.frames[next_idx].body_clip_auto = frame.body_clip_auto
	_set_status("Body clip mask copied to frame %d." % next_idx)
```

**Step 7: Update `_update_selected_frame_controls()` to sync body clip UI**

At line 2290, replace `_weapon_z_front_check.set_pressed_no_signal(frame.weapon_z_front)` with:
```gdscript
	if _body_clip_auto_check:
		_body_clip_auto_check.set_pressed_no_signal(frame.body_clip_auto)
```

**Step 8: Update preview visualization — tinted overlay on body clip regions**

In `_update_weapon_preview()`, replace the alpha mask visualization (lines 1855-1874) with body clip overlay logic. Also replace the z-front preview code (lines 1876-1884):

```gdscript
	# Apply body clip mask visualization
	var clip_mask: Image = null
	if frame.body_clip_auto:
		# Auto-generate from body frame alpha
		var body_images: Array = _frame_images.get(_preview_direction, [])
		if _preview_frame_index >= 0 and _preview_frame_index < body_images.size():
			clip_mask = CompositionConverter._generate_body_clip_mask(body_images[_preview_frame_index])
	elif frame.body_clip_mask != null:
		clip_mask = frame.body_clip_mask

	if clip_mask != null:
		# Clip weapon preview: hide weapon pixels that overlap body clip region
		var base_img := weapon_tex.get_image()
		if base_img != null:
			var composited := base_img.duplicate()
			var body_size := Vector2(_frame_size)
			var wp_rot := _weapon_sprite.rotation
			var wp_ofs := _weapon_sprite.offset
			# Weapon position relative to body center (in pixel space)
			var wp_pos := grip_px - body_size / 2.0
			for wy in range(composited.get_height()):
				for wx in range(composited.get_width()):
					var wpx: Color = composited.get_pixel(wx, wy)
					if wpx.a < 0.01:
						continue
					var weapon_local := Vector2(wx, wy) - Vector2(composited.get_width(), composited.get_height()) / 2.0 + wp_ofs
					var body_local: Vector2 = weapon_local.rotated(wp_rot) + wp_pos
					var body_px := Vector2i(
						int(body_local.x + body_size.x / 2.0),
						int(body_local.y + body_size.y / 2.0)
					)
					if body_px.x < 0 or body_px.x >= int(body_size.x):
						continue
					if body_px.y < 0 or body_px.y >= int(body_size.y):
						continue
					if body_px.x >= clip_mask.get_width() or body_px.y >= clip_mask.get_height():
						continue
					if clip_mask.get_pixel(body_px.x, body_px.y).r > 0.5:
						wpx.a = 0.0
						composited.set_pixel(wx, wy, wpx)
			_weapon_sprite.texture = ImageTexture.create_from_image(composited)

	# Also render tinted overlay on body sprite to show clip regions
	if _body_clip_paint_enabled and clip_mask != null:
		var body_images_for_overlay: Array = _frame_images.get(_preview_direction, [])
		if _preview_frame_index >= 0 and _preview_frame_index < body_images_for_overlay.size():
			var body_img: Image = body_images_for_overlay[_preview_frame_index].duplicate()
			for y in range(mini(body_img.get_height(), clip_mask.get_height())):
				for x in range(mini(body_img.get_width(), clip_mask.get_width())):
					if clip_mask.get_pixel(x, y).r > 0.5:
						var px: Color = body_img.get_pixel(x, y)
						# Tint clipped body pixels red
						px = px.lerp(Color(1.0, 0.2, 0.2, px.a), 0.4)
						body_img.set_pixel(x, y, px)
			_preview_sprite.texture = ImageTexture.create_from_image(body_img)

	# Weapon always in front — no z-ordering toggle
	_weapon_sprite.z_index = 1
	_weapon_sprite.modulate = Color(1.0, 1.0, 1.0, 0.9)
```

**Step 9: Update frame copy logic (around line 292)**

Replace `alpha_mask` duplication with `body_clip_mask`:
```gdscript
			if frame.body_clip_mask != null:
				frame_copy.body_clip_mask = frame.body_clip_mask.duplicate()
			frame_copy.body_clip_auto = frame.body_clip_auto
```

**Step 10: Remove `_on_weapon_z_front_toggled()` function (lines 2396-2399)**

Delete the function entirely.

**Step 11: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(composer): body clip mask painting UI with auto-generate and tinted overlay"
```

---

### Task 6: Clean Up Remaining References

**Files:**
- Search all GDScript files for remaining references to old names

**Step 1: Search for stale references**

Search for: `weapon_z_front`, `weapon_z_changed`, `_weapon_z_override`, `weapon_alpha_masks`, `_weapon_alpha_masks`, `_weapon_alpha_cache`, `alpha_mask` (in combat-related files only — effect_alpha_mask is unrelated and should be kept).

**Step 2: Fix any remaining references found**

Update any remaining references in files not covered by Tasks 1-5.

**Step 3: Verify no `.tres` resource files reference old field names**

Check `resources/compositions/` and `resources/sequences/` for serialized `weapon_z_front` or `alpha_mask` fields. If found, note that Godot will silently ignore unknown fields, so existing `.tres` files are safe but may produce warnings on load.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: clean up stale weapon alpha mask and z-order references"
```

---

### Task 7: Manual Smoke Test

**No code changes — verification only.**

**Step 1: Open Godot and run the project**

Verify no errors on startup related to removed signals or fields.

**Step 2: Open Attack Composer (Project > Tools > Attack Composer)**

- Load a composition
- Verify the "Body Clip Mask" toggle appears (not "Draw Alpha")
- Verify the "Weapon In Front" checkbox is gone
- Toggle "Body Clip Mask" on → verify sub-controls appear (Auto from Body, Paint/Erase, brush sizes, Clear/Copy)
- Toggle "Auto from Body" → verify body pixels get tinted overlay and weapon is clipped
- Paint custom clip regions → verify overlay and weapon clipping update
- Use "Clear Mask" → verify clip resets
- Use "Copy → Next" → verify mask copies to next frame

**Step 3: Test runtime playback**

- Export/save a composition with body clip masks
- Trigger the ability in-game
- Verify weapon is clipped correctly during the animation
- Verify weapon always renders in front (no more z-index toggling)

**Step 4: Test with different weapons**

- Equip a different weapon
- Trigger the same ability
- Verify the same body clip mask works correctly with the new weapon shape
