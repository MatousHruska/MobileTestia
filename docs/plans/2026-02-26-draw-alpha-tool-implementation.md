# Draw Alpha Tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Draw Alpha" brush tool to both the Weapon Pipeline and Attack Composer for painting per-pixel transparency on weapon sprites.

**Architecture:** Both tools get a toggle that activates alpha painting mode with a 5-button row (0/25/50/75/100%). The weapon pipeline saves a separate `alpha_mask.png` alongside `weapon.png`. The attack composer stores per-frame `Image` alpha masks in the CompositionFrame resource. Both use 1px brush painting only on non-transparent weapon pixels.

**Tech Stack:** GDScript, Godot 4 Image/ImageTexture API, FORMAT_R8 single-channel images

---

### Task 1: Add alpha_mask field to CompositionFrame

**Files:**
- Modify: `scripts/tools/attack_composer/composition_frame.gd`

**Step 1: Add the alpha mask property**

Add after the `echo_spacing_px` field (line ~37):

```gdscript
## Per-frame alpha mask for weapon transparency painting.
## Same dimensions as weapon texture. null = fully opaque (no mask).
## FORMAT_R8: 255 = opaque, 0 = fully transparent.
@export var alpha_mask: Image = null
```

**Step 2: Verify**

Run the project and load the Attack Composer. Existing compositions should load without errors since the new field defaults to null.

**Step 3: Commit**

```bash
git add scripts/tools/attack_composer/composition_frame.gd
git commit -m "feat(composition): add per-frame alpha_mask field to CompositionFrame"
```

---

### Task 2: Weapon Pipeline — alpha mask state and UI controls

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd`

**Step 1: Add state variables**

Add near the existing anchor state variables (around line 81-84):

```gdscript
var _alpha_mask_image: Image = null
var _alpha_paint_mode: bool = false
var _alpha_paint_value: int = 128  # Current brush R8 value (0, 64, 128, 191, 255)
var _alpha_buttons: Array[Button] = []
var _alpha_container: VBoxContainer = null
var _clear_mask_btn: Button = null
```

**Step 2: Build the Draw Alpha UI section**

In `_build_step_anchor()`, after the anchor legend / tip label section (around line 661, before the Export section), add a new section:

```gdscript
# ── Draw Alpha Mask ──
var alpha_sec := _make_section("Draw Alpha Mask")
parent.add_child(alpha_sec[0])
_alpha_container = alpha_sec[1]

_alpha_container.add_child(_make_small_label(
    "Paint transparency on weapon pixels. L-click to paint selected alpha level."))

# Alpha level buttons row
var alpha_row := HBoxContainer.new()
alpha_row.add_theme_constant_override("separation", 4)
_alpha_container.add_child(alpha_row)

var alpha_levels := [
    {"label": "0%", "value": 0},
    {"label": "25%", "value": 64},
    {"label": "50%", "value": 128},
    {"label": "75%", "value": 191},
    {"label": "100%", "value": 255},
]
for level in alpha_levels:
    var btn := Button.new()
    btn.text = level["label"]
    btn.add_theme_font_size_override("font_size", FONT_LABEL)
    btn.size_flags_horizontal = SIZE_EXPAND_FILL
    btn.custom_minimum_size.y = 32
    # Visual: tint button background to show opacity
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(1, 1, 1, level["value"] / 255.0)
    sb.border_color = C_TEXT_DIM
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(4)
    sb.content_margin_left = 4
    sb.content_margin_right = 4
    btn.add_theme_stylebox_override("normal", sb)
    var hover_sb := sb.duplicate()
    hover_sb.border_color = C_ACCENT
    hover_sb.set_border_width_all(2)
    btn.add_theme_stylebox_override("hover", hover_sb)
    var pressed_sb := sb.duplicate()
    pressed_sb.border_color = C_ACCENT
    pressed_sb.set_border_width_all(2)
    pressed_sb.bg_color = C_ACCENT.lerp(sb.bg_color, 0.5)
    btn.add_theme_stylebox_override("pressed", pressed_sb)
    btn.add_theme_color_override("font_color", C_TEXT if level["value"] < 128 else Color.BLACK)
    var val: int = level["value"]
    btn.pressed.connect(_on_alpha_level_selected.bind(val, btn))
    alpha_row.add_child(btn)
    _alpha_buttons.append(btn)

# Toggle alpha paint mode button
var toggle_btn := _make_primary_button("Enable Alpha Painting")
toggle_btn.pressed.connect(_on_alpha_paint_toggled.bind(toggle_btn))
_alpha_container.add_child(toggle_btn)

# Clear mask button
_clear_mask_btn = Button.new()
_clear_mask_btn.text = "Clear Mask"
_clear_mask_btn.add_theme_font_size_override("font_size", FONT_LABEL)
_clear_mask_btn.pressed.connect(_on_clear_alpha_mask)
_alpha_container.add_child(_clear_mask_btn)
```

**Step 3: Implement the signal handlers**

```gdscript
func _on_alpha_level_selected(value: int, btn: Button) -> void:
    _alpha_paint_value = value
    # Highlight selected button
    for b in _alpha_buttons:
        b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    # Visual feedback: thicker border on selected
    _anchor_overlay.queue_redraw()


func _on_alpha_paint_toggled(btn: Button) -> void:
    _alpha_paint_mode = not _alpha_paint_mode
    btn.text = "Disable Alpha Painting" if _alpha_paint_mode else "Enable Alpha Painting"
    if _alpha_paint_mode and _alpha_mask_image == null and _processed_image != null:
        # Initialize mask to fully opaque
        _alpha_mask_image = Image.create(
            _processed_image.get_width(),
            _processed_image.get_height(),
            false, Image.FORMAT_R8)
        _alpha_mask_image.fill(Color(1, 1, 1))  # R8: 255 = opaque
    _anchor_overlay.queue_redraw()


func _on_clear_alpha_mask() -> void:
    if _alpha_mask_image != null:
        _alpha_mask_image.fill(Color(1, 1, 1))  # Reset to fully opaque
        _anchor_overlay.queue_redraw()
```

**Step 4: Verify**

Run the project, open the weapon pipeline, load a weapon, advance to Step 3 (Anchor). The "Draw Alpha Mask" section should appear with 5 buttons and an enable toggle.

**Step 5: Commit**

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): add Draw Alpha UI controls and state"
```

---

### Task 3: Weapon Pipeline — alpha painting input handler

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd`

**Step 1: Extend the existing input handler**

In `_on_anchor_overlay_input()` (around line 906), add alpha painting support. The existing handler checks `_placement_mode` for grip/tip. Add an alpha painting branch:

```gdscript
func _on_anchor_overlay_input(event: InputEvent) -> void:
    # Existing anchor placement code for grip/tip...
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            var local_pos := mb.position
            var px: int = clampi(int(local_pos.x) / ANCHOR_ZOOM, 0, _processed_image.get_width() - 1)
            var py: int = clampi(int(local_pos.y) / ANCHOR_ZOOM, 0, _processed_image.get_height() - 1)

            if _placement_mode != "":
                # Existing grip/tip placement...
                pass
            elif _alpha_paint_mode:
                _paint_alpha_pixel(px, py)
                return

    # Also handle mouse motion for drag-painting
    if event is InputEventMouseMotion and _alpha_paint_mode:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            var local_pos := event.position
            var px: int = clampi(int(local_pos.x) / ANCHOR_ZOOM, 0, _processed_image.get_width() - 1)
            var py: int = clampi(int(local_pos.y) / ANCHOR_ZOOM, 0, _processed_image.get_height() - 1)
            _paint_alpha_pixel(px, py)
```

Note: The exact integration depends on the current function structure. The key change is:
1. When `_alpha_paint_mode` is true and left-click (or drag), call `_paint_alpha_pixel`
2. Handle `InputEventMouseMotion` for continuous drag painting

**Step 2: Implement the painting function**

```gdscript
func _paint_alpha_pixel(px: int, py: int) -> void:
    if _alpha_mask_image == null or _processed_image == null:
        return
    # Only paint on non-transparent weapon pixels
    var weapon_pixel := _processed_image.get_pixel(px, py)
    if weapon_pixel.a < 0.01:
        return  # Skip empty background
    # Paint the alpha value (R8 format: Color.r = value/255)
    _alpha_mask_image.set_pixel(px, py, Color(_alpha_paint_value / 255.0, 0, 0))
    _anchor_overlay.queue_redraw()
```

**Step 3: Verify**

Run the weapon pipeline, load a weapon, enable alpha painting, click on weapon pixels. The overlay should redraw (visualization comes in Task 4).

**Step 4: Commit**

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): implement alpha brush pixel painting with drag support"
```

---

### Task 4: Weapon Pipeline — alpha overlay visualization

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd`

**Step 1: Extend the draw overlay function**

In `_on_anchor_overlay_draw()` (around line 935), add alpha mask visualization when in paint mode. After the existing grid/crosshair drawing:

```gdscript
# Draw alpha mask visualization
if _alpha_paint_mode and _alpha_mask_image != null:
    for y in range(_alpha_mask_image.get_height()):
        for x in range(_alpha_mask_image.get_width()):
            var weapon_pixel := _processed_image.get_pixel(x, y)
            if weapon_pixel.a < 0.01:
                continue  # Skip non-weapon pixels
            var mask_val: float = _alpha_mask_image.get_pixel(x, y).r
            if mask_val > 0.99:
                continue  # Fully opaque, no overlay needed
            # Draw a checkerboard tint to show transparency
            var rect := Rect2(x * ANCHOR_ZOOM, y * ANCHOR_ZOOM, ANCHOR_ZOOM, ANCHOR_ZOOM)
            var tint_alpha := (1.0 - mask_val) * 0.6  # Stronger tint = more transparent
            _anchor_overlay.draw_rect(rect, Color(1.0, 0.2, 0.2, tint_alpha))
            # Checkerboard pattern for strong transparency
            if mask_val < 0.5:
                var checker_size := ANCHOR_ZOOM / 2
                for cy in range(2):
                    for cx in range(2):
                        if (cx + cy) % 2 == 0:
                            var check_rect := Rect2(
                                x * ANCHOR_ZOOM + cx * checker_size,
                                y * ANCHOR_ZOOM + cy * checker_size,
                                checker_size, checker_size)
                            _anchor_overlay.draw_rect(check_rect, Color(0, 0, 0, 0.3))
```

**Step 2: Verify**

Run the weapon pipeline, paint alpha on weapon pixels. Should see red tint overlay on painted pixels, with checkerboard on heavily transparent ones.

**Step 3: Commit**

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): add alpha mask visualization overlay with checkerboard"
```

---

### Task 5: Weapon Pipeline — save and load alpha mask

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd`

**Step 1: Save alpha mask in export function**

In `_export_weapon()` (around line 1038), after the weapon.png save (around line 1062), add:

```gdscript
# Save alpha mask if it has any non-255 values
if _alpha_mask_image != null and _has_custom_alpha():
    var alpha_res_path: String = res_dir + "/alpha_mask.png"
    var alpha_global_path: String = ProjectSettings.globalize_path(alpha_res_path)
    var alpha_err := _alpha_mask_image.save_png(alpha_global_path)
    if alpha_err != OK:
        _set_export_status("Failed to save alpha mask: %s" % error_string(alpha_err))
        return
    meta_dict["has_alpha_mask"] = true
```

Add the helper:

```gdscript
func _has_custom_alpha() -> bool:
    if _alpha_mask_image == null:
        return false
    for y in range(_alpha_mask_image.get_height()):
        for x in range(_alpha_mask_image.get_width()):
            if _alpha_mask_image.get_pixel(x, y).r < 0.99:
                return true
    return false
```

**Step 2: Load alpha mask when loading a weapon for re-editing**

If the weapon pipeline has a reload/re-edit flow, load the existing alpha mask:

```gdscript
# When loading processed image for step 3, also load alpha mask
var alpha_path: String = WEAPONS_DIR + "/" + _weapon_id + "/alpha_mask.png"
if FileAccess.file_exists(alpha_path):
    _alpha_mask_image = Image.load_from_file(ProjectSettings.globalize_path(alpha_path))
else:
    _alpha_mask_image = null
```

**Step 3: Verify**

Export a weapon with alpha painted, check that `alpha_mask.png` appears in the weapon folder. Reload and verify the mask persists.

**Step 4: Commit**

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): save/load alpha_mask.png on weapon export"
```

---

### Task 6: Attack Composer — alpha mask state and UI controls

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Add state variables**

Near the existing anchor drawing state (around lines 51-53):

```gdscript
var _alpha_paint_enabled: bool = false
var _alpha_paint_value: int = 128  # R8 value: 0, 64, 128, 191, 255
var _alpha_draw_check: CheckButton = null
var _alpha_buttons_container: VBoxContainer = null
var _alpha_buttons: Array[Button] = []
```

Per-frame alpha masks are stored on `CompositionFrame.alpha_mask` (added in Task 1). No additional storage needed — the composition resource handles serialization.

**Step 2: Add UI to weapon subsection**

In `_build_weapon_subsection()`, after the onion skin container and its children (after the anchor legend, around line 978), add:

```gdscript
# Draw Alpha toggle
_alpha_draw_check = CheckButton.new()
_alpha_draw_check.text = "Draw Alpha"
_alpha_draw_check.add_theme_font_size_override("font_size", FONT_LABEL)
_alpha_draw_check.add_theme_color_override("font_color", C_TEXT_SEC)
_alpha_draw_check.toggled.connect(_on_alpha_draw_toggled)
section.add_child(_alpha_draw_check)

# Alpha controls container (shown when Draw Alpha is on)
_alpha_buttons_container = VBoxContainer.new()
_alpha_buttons_container.add_theme_constant_override("separation", 4)
_alpha_buttons_container.visible = false
section.add_child(_alpha_buttons_container)

# Alpha level buttons row
var alpha_row := HBoxContainer.new()
alpha_row.add_theme_constant_override("separation", 2)
_alpha_buttons_container.add_child(alpha_row)

var alpha_levels := [
    {"label": "0%", "value": 0},
    {"label": "25%", "value": 64},
    {"label": "50%", "value": 128},
    {"label": "75%", "value": 191},
    {"label": "100%", "value": 255},
]
for level in alpha_levels:
    var btn := Button.new()
    btn.text = level["label"]
    btn.add_theme_font_size_override("font_size", FONT_HINT)
    btn.size_flags_horizontal = SIZE_EXPAND_FILL
    btn.custom_minimum_size.y = 28
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(1, 1, 1, level["value"] / 255.0)
    sb.border_color = C_TEXT_DIM
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(3)
    btn.add_theme_stylebox_override("normal", sb)
    var hover_sb := sb.duplicate()
    hover_sb.border_color = C_ACCENT
    hover_sb.set_border_width_all(2)
    btn.add_theme_stylebox_override("hover", hover_sb)
    btn.add_theme_color_override("font_color", C_TEXT if level["value"] < 128 else Color.BLACK)
    var val: int = level["value"]
    btn.pressed.connect(_on_alpha_level_btn.bind(val))
    alpha_row.add_child(btn)
    _alpha_buttons.append(btn)

# Hint label
var alpha_hint := Label.new()
alpha_hint.text = "L-click on weapon to paint alpha"
alpha_hint.add_theme_font_size_override("font_size", FONT_HINT)
alpha_hint.add_theme_color_override("font_color", C_TEXT_DIM)
_alpha_buttons_container.add_child(alpha_hint)

# Action buttons row
var alpha_actions := HBoxContainer.new()
alpha_actions.add_theme_constant_override("separation", 4)
_alpha_buttons_container.add_child(alpha_actions)
var clear_btn := Button.new()
clear_btn.text = "Clear Mask"
clear_btn.add_theme_font_size_override("font_size", FONT_HINT)
clear_btn.size_flags_horizontal = SIZE_EXPAND_FILL
clear_btn.pressed.connect(_on_clear_frame_alpha)
alpha_actions.add_child(clear_btn)
var copy_btn := Button.new()
copy_btn.text = "Copy → Next"
copy_btn.add_theme_font_size_override("font_size", FONT_HINT)
copy_btn.size_flags_horizontal = SIZE_EXPAND_FILL
copy_btn.pressed.connect(_on_copy_alpha_to_next)
alpha_actions.add_child(copy_btn)
```

**Step 3: Implement signal handlers**

```gdscript
func _on_alpha_draw_toggled(enabled: bool) -> void:
    _alpha_paint_enabled = enabled
    _alpha_buttons_container.visible = enabled
    _update_preview_frame()


func _on_alpha_level_btn(value: int) -> void:
    _alpha_paint_value = value


func _on_clear_frame_alpha() -> void:
    if _current_composition == null or _selected_frame < 0:
        return
    _push_undo()
    var frame := _current_composition.frames[_selected_frame]
    frame.alpha_mask = null
    _update_weapon_preview()


func _on_copy_alpha_to_next() -> void:
    if _current_composition == null or _selected_frame < 0:
        return
    var frame := _current_composition.frames[_selected_frame]
    if frame.alpha_mask == null:
        _set_status("No alpha mask on current frame to copy.")
        return
    var next_idx := _selected_frame + 1
    if next_idx >= _current_composition.frames.size():
        _set_status("No next frame to copy to.")
        return
    _push_undo()
    _current_composition.frames[next_idx].alpha_mask = frame.alpha_mask.duplicate()
    _set_status("Alpha mask copied to frame %d." % next_idx)
```

**Step 4: Verify**

Run the attack composer. In the Weapon section, "Draw Alpha" toggle should appear after anchor controls. Toggling it shows the alpha level buttons.

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add Draw Alpha UI controls in weapon section"
```

---

### Task 7: Attack Composer — alpha painting input handler

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

This is the most complex task. When the user clicks on the weapon in the viewport, we must convert viewport coordinates to weapon texture pixels, accounting for rotation, scale, and offset.

**Step 1: Extend `_on_preview_viewport_input()` for alpha painting**

At the top of `_on_preview_viewport_input()` (around line 2037), add a branch for alpha painting that runs BEFORE the anchor placement code. Alpha painting should handle both click and drag:

```gdscript
func _on_preview_viewport_input(event: InputEvent) -> void:
    # Alpha painting mode (handles click + drag)
    if _alpha_paint_enabled:
        var is_click := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
        var is_drag := event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
        if is_click or is_drag:
            var pos: Vector2 = event.position
            var weapon_px := _viewport_to_weapon_pixel(pos)
            if weapon_px != Vector2i(-1, -1):
                if is_click:
                    _push_undo()
                _paint_weapon_alpha(weapon_px.x, weapon_px.y)
                _viewport_container_ref.accept_event()
            return

    # Existing anchor placement code below...
    if not _anchor_draw_enabled:
        return
    # ... rest of existing code
```

**Step 2: Implement viewport → weapon pixel coordinate conversion**

```gdscript
func _viewport_to_weapon_pixel(container_pos: Vector2) -> Vector2i:
    ## Convert a container click position to weapon texture pixel coordinates.
    ## Returns Vector2i(-1, -1) if the click is outside the weapon.
    if _weapon_sprite == null or not _weapon_sprite.visible or _weapon_sprite.texture == null:
        return Vector2i(-1, -1)

    var container_size := _viewport_container_ref.size
    var vp_size := Vector2(_preview_viewport.size)
    if container_size.x <= 0 or container_size.y <= 0:
        return Vector2i(-1, -1)

    # Container → viewport coords
    var vp_click := container_pos * (vp_size / container_size)

    # Viewport → weapon local space (undo position, rotation, scale)
    var local := (vp_click - _weapon_sprite.position).rotated(-_weapon_sprite.rotation) / _weapon_sprite.scale

    # Local space → texture pixel (undo offset and centering)
    var tex_size := Vector2(_weapon_sprite.texture.get_size())
    var tex_px := local - _weapon_sprite.offset + tex_size / 2.0
    var px := int(tex_px.x)
    var py := int(tex_px.y)

    # Bounds check
    if px < 0 or px >= int(tex_size.x) or py < 0 or py >= int(tex_size.y):
        return Vector2i(-1, -1)

    return Vector2i(px, py)
```

**Step 3: Implement the painting function**

```gdscript
func _paint_weapon_alpha(px: int, py: int) -> void:
    if _current_composition == null or _selected_frame < 0:
        return
    var frame := _current_composition.frames[_selected_frame]

    # Get weapon texture to check if pixel has content
    var weapon_tex: Texture2D = _weapon_set.get("right")
    if weapon_tex == null:
        return
    var weapon_img := weapon_tex.get_image()
    if weapon_img == null:
        return
    if px < 0 or px >= weapon_img.get_width() or py < 0 or py >= weapon_img.get_height():
        return
    # Only paint on non-transparent weapon pixels
    if weapon_img.get_pixel(px, py).a < 0.01:
        return

    # Initialize mask if needed
    if frame.alpha_mask == null:
        frame.alpha_mask = Image.create(
            weapon_img.get_width(), weapon_img.get_height(),
            false, Image.FORMAT_R8)
        frame.alpha_mask.fill(Color(1, 1, 1))  # Start fully opaque

    # Paint the alpha value
    frame.alpha_mask.set_pixel(px, py, Color(_alpha_paint_value / 255.0, 0, 0))
    _update_weapon_preview()
```

**Step 4: Verify**

Run the attack composer, load a composition with a weapon, enable Draw Alpha, click on the weapon sprite. The painting should work even with rotated weapons.

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): implement alpha painting with rotated weapon coordinate conversion"
```

---

### Task 8: Attack Composer — alpha mask preview visualization

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Update `_update_weapon_preview()` to apply alpha mask**

In `_update_weapon_preview()`, after the weapon texture is set and positioned (around line 1404), before the z-index section, add alpha visualization:

```gdscript
# Apply per-frame alpha mask visualization
if _alpha_paint_enabled and frame.alpha_mask != null:
    # Create a composited texture: base weapon with mask applied
    var base_img := weapon_tex.get_image()
    if base_img != null:
        var composited := base_img.duplicate()
        var mask := frame.alpha_mask
        for y in range(mini(composited.get_height(), mask.get_height())):
            for x in range(mini(composited.get_width(), mask.get_width())):
                var mask_val: float = mask.get_pixel(x, y).r
                if mask_val < 0.99:
                    var px := composited.get_pixel(x, y)
                    px.a *= mask_val
                    composited.set_pixel(x, y, px)
        _weapon_sprite.texture = ImageTexture.create_from_image(composited)
```

This replaces the weapon texture with a composited version that shows the alpha mask effect in real-time. When alpha paint mode is OFF, the original texture is used.

**Step 2: Verify**

Run the attack composer, paint some alpha on the weapon. The weapon should visually show transparency where painted.

**Step 3: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): visualize alpha mask on weapon preview in real-time"
```

---

### Task 9: Attack Composer — undo support for alpha masks

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Update `_push_undo()` to snapshot alpha masks**

The existing undo snapshots composition frames via `frame.duplicate()`. Since `alpha_mask` is an `@export var alpha_mask: Image`, Godot's `Resource.duplicate()` should handle shallow duplication. However, `Image` needs explicit `.duplicate()` to deep-copy pixel data.

In `_push_undo()` (around line 252), after `comp_snapshot.frames.append(frame.duplicate())`, ensure the alpha mask is deep-copied:

```gdscript
for frame in _current_composition.frames:
    var frame_copy := frame.duplicate()
    if frame.alpha_mask != null:
        frame_copy.alpha_mask = frame.alpha_mask.duplicate()
    comp_snapshot.frames.append(frame_copy)
```

Replace the existing simpler line (`comp_snapshot.frames.append(frame.duplicate())`) with this block.

**Step 2: Verify**

Paint alpha, undo, verify the mask reverts.

**Step 3: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): deep-copy alpha masks in undo snapshots"
```

---

### Task 10: Weapon loading — load global alpha mask from weapon assets

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Update `_load_weapon_from_folder()` to load alpha mask**

In `_load_weapon_from_folder()` (around line 2284), after loading weapon.png and metadata.json, check for and load alpha_mask.png:

```gdscript
# Load global alpha mask if present
var alpha_mask: Image = null
var alpha_path: String = dir_path + "/alpha_mask.png"
if FileAccess.file_exists(alpha_path):
    alpha_mask = Image.load_from_file(ProjectSettings.globalize_path(alpha_path))

# Return same format as PlaceholderWeaponSprites sets.
return {
    "down": tex, "up": tex, "right": tex,
    "grip_down": grip, "grip_up": grip, "grip_right": grip,
    "tip_down": tip, "tip_up": tip, "tip_right": tip,
    "alpha_mask": alpha_mask,
}
```

**Step 2: Apply global alpha mask to weapon texture on load**

In `_update_weapon_preview()`, when rendering the weapon, combine the global alpha mask (from weapon asset) with the per-frame mask (from composition). Update the compositing code from Task 8:

```gdscript
# Get masks
var global_mask: Image = _weapon_set.get("alpha_mask")
var frame_mask: Image = frame.alpha_mask if _alpha_paint_enabled else null

if global_mask != null or frame_mask != null:
    var base_img := weapon_tex.get_image()
    if base_img != null:
        var composited := base_img.duplicate()
        for y in range(composited.get_height()):
            for x in range(composited.get_width()):
                var alpha_mult := 1.0
                if global_mask != null and x < global_mask.get_width() and y < global_mask.get_height():
                    alpha_mult *= global_mask.get_pixel(x, y).r
                if frame_mask != null and x < frame_mask.get_width() and y < frame_mask.get_height():
                    alpha_mult *= frame_mask.get_pixel(x, y).r
                if alpha_mult < 0.99:
                    var px := composited.get_pixel(x, y)
                    px.a *= alpha_mult
                    composited.set_pixel(x, y, px)
        _weapon_sprite.texture = ImageTexture.create_from_image(composited)
```

**Step 3: Verify**

Export a weapon with alpha mask from the pipeline, load it in the attack composer. The hilt should show transparency from the global mask.

**Step 4: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): load and apply global alpha mask from weapon assets"
```
