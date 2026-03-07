# Sprite Pipeline Shadow Step — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a shadow configuration step (Step 5) to the sprite pipeline wizard with parameter sliders, alpha mask painting, live preview, and SpriteFrames metadata storage — so each character gets per-animation shadow tuning.

**Architecture:** Insert a new step between Light Preview (old Step 5) and Export (old Step 6). The step provides sliders for overlap/length/offset, preview-only angle/opacity, and an alpha mask painter. On Apply, shadow params + mask are stored as SpriteFrames metadata. CharacterVisuals reads them at runtime and configures SilhouetteShadow.

**Tech Stack:** GDScript, Godot 4 UI (programmatic), SilhouetteShadow shader, SpriteFrames metadata

**Design doc:** `docs/plans/2026-03-07-sprite-shadow-step-design.md`

---

## Reference Files

These files will be needed throughout the tasks:

- `scripts/tools/sprite_pipeline.gd` — The wizard (3234 lines). All UI is built programmatically.
- `scripts/tools/step_indicator.gd` — Step dot indicator (`total_steps := 7` on line 12).
- `scripts/environment/silhouette_shadow.gd` — Shadow node with `apply_params()` and `set_shadow_mask()`.
- `scripts/combat/character_visuals.gd` — Runtime shadow creation (lines 108-112).
- `scripts/tools/decoration_pipeline.gd` — Reference for mask painting pattern (lines 1325-1840).

## Utility functions available in sprite_pipeline.gd

All UI is built with these helpers (same file):
- `_make_section(title) -> [PanelContainer, VBoxContainer]` — styled collapsible section
- `_make_field(label, control) -> VBoxContainer` — label + control row
- `_make_slider_row(min, max, default, step) -> [HBoxContainer, HSlider, Label]`
- `_make_toggle_group(options, callback) -> HBoxContainer` — radio-style button group
- `_make_label(text)`, `_make_small_label(text)` — styled labels
- `_make_primary_button(text)`, `_make_subtle_button(text)` — styled buttons
- `_style_checkbutton_transparent(cb)` — dark-theme checkbox styling
- `_make_collapsible(title, start_open) -> [PanelContainer, VBoxContainer]`

---

### Task 1: Bump step count from 7 to 8

Increase the wizard from 7 steps to 8 so there's room for the new Shadow step at index 5. Export becomes index 6, Apply becomes index 7.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`
- Modify: `scripts/tools/step_indicator.gd:12`

**Step 1: Update step_indicator.gd total_steps**

In `scripts/tools/step_indicator.gd`, line 12, change:
```gdscript
var total_steps := 7
```
to:
```gdscript
var total_steps := 8
```

**Step 2: Update sprite_pipeline.gd step loop and builder calls**

In `scripts/tools/sprite_pipeline.gd`:

1. Line 88: Update comment `# 0-6` → `# 0-7`
2. Line 352: Change `for i in range(7):` → `for i in range(8):`
3. Lines 360-366: Reorder builder calls — insert `_build_step_shadow` at index 5, bump export and apply:
```gdscript
_build_step1(_step_containers[0])
_build_step2(_step_containers[1])
_build_step3(_step_containers[2])
_build_step_frame_editor(_step_containers[3])
_build_step_light_preview(_step_containers[4])
_build_step_shadow(_step_containers[5])       # NEW
_build_step_export(_step_containers[6])        # was index 5
_build_step_apply(_step_containers[7])         # was index 6
```

**Step 3: Update _go_to_step navigation logic**

In `_go_to_step()` (line 1516):

1. Line 1522: `next_button.visible = (step < 7)` (was `< 6`)
2. Line 1525: Export step check `if step == 6:` (was `5`)
3. Lines 1550-1551: Update step_names array and format string:
```gdscript
var step_names := ["Model & Animation", "Capture Preview", "Pixel Art Settings",
    "Frame Editor", "Light Preview", "Shadow", "Export", "Apply to SpriteFrames"]
step_indicator_label.text = "Step %d of 8: %s" % [step + 1, step_names[step]]
```
4. Line 1564: Light preview visibility `(step == 4)` — unchanged, still correct.
5. Add shadow preview visibility toggle (after light preview block):
```gdscript
if _shadow_preview_container:
    _shadow_preview_container.visible = (step == 5)
```
6. Update `match step:` block — old step 5 (export) → 6, old step 6 (apply) → 7, add step 5:
```gdscript
match step:
    0:
        next_button.disabled = (current_anim_player == null)
    1:
        next_button.disabled = _captured_sheets.is_empty()
    2:
        _scan_palettes()
        if _current_preset.has("pixel_art"):
            _apply_pixel_art_preset(_current_preset["pixel_art"])
        _update_pixel_preview()
    3:
        _frame_editor_deleted_count = 0
        _setup_frame_editor()
    4:
        _setup_light_preview()
    5:
        _setup_shadow_preview()
    6:
        _start_export()
    7:
        _scan_export_folders()
```

**Step 4: Update _on_next_pressed and _on_back_pressed**

`_on_next_pressed` line 1591: `if _current_step < 7:` (was `< 6`).

`_on_back_pressed` — the spritesheet-loaded shortcut at line 1596 still jumps to step 0 from step 3, no change needed.

**Step 5: Update _process playback timer checks**

In `_process()` (line 248), the light preview check uses `_current_step == 4` which is still correct. Add shadow preview animation check:
```gdscript
if _shadow_preview_playing and _current_step == 5:
    _shadow_preview_timer += delta
    var fps := 15.0
    if _shadow_preview_timer >= 1.0 / fps:
        _shadow_preview_timer -= 1.0 / fps
        _shadow_preview_frame = (_shadow_preview_frame + 1) % _shadow_preview_frame_count
        _update_shadow_preview_frame()
```

**Step 6: Add stub function and state variables**

Add empty stub so the file parses:
```gdscript
# After the light preview state vars (around line 148), add:
## Step 5 (Shadow) state
var _shadow_preview_viewport: SubViewport = null
var _shadow_preview_container: SubViewportContainer = null
var _shadow_preview_sprite: AnimatedSprite2D = null
var _shadow_preview_shadow: SilhouetteShadow = null
var _shadow_preview_playing := false
var _shadow_preview_timer := 0.0
var _shadow_preview_frame := 0
var _shadow_preview_frame_count := 0
var _shadow_preview_direction := "down"

# Shadow parameter sliders
var _shadow_overlap_slider: HSlider = null
var _shadow_length_slider: HSlider = null
var _shadow_offset_x_slider: HSlider = null
var _shadow_offset_y_slider: HSlider = null
var _shadow_angle_slider: HSlider = null
var _shadow_opacity_slider: HSlider = null
var _shadow_frame_label: Label = null

# Shadow alpha mask painting
var _shadow_alpha_mask: Image = null
var _shadow_mask_tex: ImageTexture = null
var _shadow_alpha_overlay: Control = null
var _shadow_alpha_paint_toggle_btn: CheckButton = null
var _shadow_alpha_paint_value: int = 0
var _shadow_alpha_brush_size: int = 3
var _shadow_alpha_buttons: Array[Button] = []
```

Add stubs for the two functions referenced in _go_to_step and _build_ui:
```gdscript
func _build_step_shadow(_parent: VBoxContainer) -> void:
    pass  # Task 2

func _setup_shadow_preview() -> void:
    pass  # Task 3
```

**Step 7: Test — run the scene**

Run: `scenes/tools/sprite_pipeline.tscn` (F6 in Godot)
Expected: Wizard shows 8 steps in the indicator dots. Clicking Next cycles through all 8 steps. Step 5 is empty but visible. Export still runs on step 6. Apply still runs on step 7.

**Step 8: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd scripts/tools/step_indicator.gd
git commit -m "refactor: bump sprite pipeline to 8 steps, insert shadow step slot"
```

---

### Task 2: Build shadow step UI (sliders + mask painting controls)

Build the left-panel controls for Step 5: Shadow. Includes parameter sliders, alpha mask painting controls, and preview-only angle/opacity.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (replace `_build_step_shadow` stub)

**Step 1: Implement _build_step_shadow**

Replace the `_build_step_shadow` stub with the full UI builder. Insert this in the `STEP 5 — SHADOW` section (between Light Preview and Export sections):

```gdscript
#===============================================================================
# STEP 5 — SHADOW (index 5)
#===============================================================================

func _build_step_shadow(parent: VBoxContainer) -> void:
    # ── Parameter Sliders ─────────────────────────────────────
    var param_sec := _make_section("Shadow Parameters")
    parent.add_child(param_sec[0])
    var param_content: VBoxContainer = param_sec[1]

    param_content.add_child(_make_small_label(
        "Configure shadow shape per-character. These values are saved with the SpriteFrames."))

    # Overlap
    var overlap_data := _make_slider_row(0.0, 0.5, 0.15, 0.01)
    _shadow_overlap_slider = overlap_data[1]
    _shadow_overlap_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    param_content.add_child(_make_field("Overlap", overlap_data[0]))

    # Length
    var length_data := _make_slider_row(0.1, 3.0, 1.0, 0.05)
    _shadow_length_slider = length_data[1]
    _shadow_length_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    param_content.add_child(_make_field("Length", length_data[0]))

    # Offset X
    var ox_data := _make_slider_row(-50.0, 50.0, 0.0, 1.0)
    _shadow_offset_x_slider = ox_data[1]
    _shadow_offset_x_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    param_content.add_child(_make_field("Offset X", ox_data[0]))

    # Offset Y
    var oy_data := _make_slider_row(-50.0, 50.0, 0.0, 1.0)
    _shadow_offset_y_slider = oy_data[1]
    _shadow_offset_y_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    param_content.add_child(_make_field("Offset Y", oy_data[0]))

    # ── Preview-only controls (not exported) ──────────────────
    var preview_sec := _make_collapsible("Preview Controls (not exported)", true)
    parent.add_child(preview_sec[0])
    var preview_content: VBoxContainer = preview_sec[1]

    preview_content.add_child(_make_small_label(
        "These control the preview only. At runtime, angle and opacity come from ZoneMood."))

    # Angle (preview only)
    var angle_data := _make_slider_row(-3.14, 3.14, 0.5, 0.05)
    _shadow_angle_slider = angle_data[1]
    _shadow_angle_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    preview_content.add_child(_make_field("Angle", angle_data[0]))

    # Opacity (preview only)
    var opacity_data := _make_slider_row(0.0, 1.0, 0.3, 0.05)
    _shadow_opacity_slider = opacity_data[1]
    _shadow_opacity_slider.value_changed.connect(func(_v: float) -> void: _update_shadow_preview())
    preview_content.add_child(_make_field("Opacity", opacity_data[0]))

    # ── Direction + Frame nav ─────────────────────────────────
    var nav_sec := _make_section("Animation Preview")
    parent.add_child(nav_sec[0])
    var nav_content: VBoxContainer = nav_sec[1]

    var dir_group := _make_toggle_group([
        {"label": "Down", "key": "down"},
        {"label": "Up", "key": "up"},
        {"label": "Right", "key": "right"},
    ], func(key: String) -> void:
        _shadow_preview_direction = key
        _setup_shadow_preview()
    )
    nav_content.add_child(_make_field("Direction", dir_group))

    var frame_hbox := HBoxContainer.new()
    frame_hbox.add_theme_constant_override("separation", 4)
    nav_content.add_child(frame_hbox)
    var prev_btn := Button.new()
    prev_btn.text = "\u25c0"
    prev_btn.custom_minimum_size.x = 32
    prev_btn.pressed.connect(func() -> void:
        _shadow_preview_frame = max(0, _shadow_preview_frame - 1)
        _update_shadow_preview_frame()
    )
    frame_hbox.add_child(prev_btn)
    _shadow_frame_label = Label.new()
    _shadow_frame_label.text = "Frame 1 / 1"
    _shadow_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _shadow_frame_label.size_flags_horizontal = SIZE_EXPAND_FILL
    frame_hbox.add_child(_shadow_frame_label)
    var next_frame_btn := Button.new()
    next_frame_btn.text = "\u25b6"
    next_frame_btn.custom_minimum_size.x = 32
    next_frame_btn.pressed.connect(func() -> void:
        _shadow_preview_frame = min(_shadow_preview_frame_count - 1, _shadow_preview_frame + 1)
        _update_shadow_preview_frame()
    )
    frame_hbox.add_child(next_frame_btn)
    var play_btn := Button.new()
    play_btn.text = "Play"
    play_btn.pressed.connect(func() -> void:
        _shadow_preview_playing = not _shadow_preview_playing
        play_btn.text = "Stop" if _shadow_preview_playing else "Play"
    )
    frame_hbox.add_child(play_btn)

    # ── Alpha Mask Painting ───────────────────────────────────
    var alpha_sec := _make_collapsible("Alpha Mask Painting", false)
    parent.add_child(alpha_sec[0])
    var alpha_content: VBoxContainer = alpha_sec[1]

    alpha_content.add_child(_make_small_label(
        "Paint transparency on the shadow. Single mask applied to all frames. L-click to paint."))

    # Alpha level buttons
    alpha_content.add_child(_make_label("Alpha Level"))
    var alpha_row := HBoxContainer.new()
    alpha_row.add_theme_constant_override("separation", 4)
    alpha_content.add_child(alpha_row)

    _shadow_alpha_buttons.clear()
    var alpha_levels: Array[Array] = [
        [0, "0%"], [64, "25%"], [128, "50%"], [191, "75%"], [255, "100%"],
    ]
    for entry in alpha_levels:
        var value: int = entry[0]
        var label_text: String = entry[1]
        var btn := Button.new()
        btn.text = label_text
        btn.toggle_mode = true
        btn.button_pressed = (value == 0)
        btn.size_flags_horizontal = SIZE_EXPAND_FILL
        var btn_sb := StyleBoxFlat.new()
        btn_sb.bg_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, maxf(value / 255.0, 0.15))
        btn_sb.set_corner_radius_all(4)
        btn_sb.set_content_margin_all(6)
        btn.add_theme_stylebox_override("normal", btn_sb)
        var active_sb := StyleBoxFlat.new()
        active_sb.bg_color = C_ACCENT
        active_sb.set_corner_radius_all(4)
        active_sb.set_content_margin_all(6)
        btn.add_theme_stylebox_override("pressed", active_sb)
        var btn_hover_sb := StyleBoxFlat.new()
        btn_hover_sb.bg_color = Color(C_ACCENT_HOVER.r, C_ACCENT_HOVER.g, C_ACCENT_HOVER.b, clampf(value / 255.0 + 0.15, 0.0, 1.0))
        btn_hover_sb.set_corner_radius_all(4)
        btn_hover_sb.set_content_margin_all(6)
        btn.add_theme_stylebox_override("hover", btn_hover_sb)
        btn.add_theme_font_size_override("font_size", FONT_HINT)
        alpha_row.add_child(btn)
        _shadow_alpha_buttons.append(btn)

    for i in range(_shadow_alpha_buttons.size()):
        var value: int = alpha_levels[i][0]
        var idx := i
        _shadow_alpha_buttons[i].pressed.connect(func() -> void:
            _shadow_alpha_paint_value = value
            for j in range(_shadow_alpha_buttons.size()):
                _shadow_alpha_buttons[j].button_pressed = (j == idx)
        )

    # Brush size buttons
    alpha_content.add_child(_make_label("Brush Size"))
    var brush_row := HBoxContainer.new()
    brush_row.add_theme_constant_override("separation", 4)
    alpha_content.add_child(brush_row)

    var brush_sizes: Array[Array] = [[1, "1px"], [3, "3px"], [5, "5px"]]
    for entry in brush_sizes:
        var bsize: int = entry[0]
        var label_text: String = entry[1]
        var btn := Button.new()
        btn.text = label_text
        btn.size_flags_horizontal = SIZE_EXPAND_FILL
        btn.toggle_mode = true
        btn.button_pressed = (bsize == 3)
        var btn_sb := StyleBoxFlat.new()
        btn_sb.bg_color = C_SURFACE
        btn_sb.set_corner_radius_all(4)
        btn_sb.set_content_margin_all(6)
        btn.add_theme_stylebox_override("normal", btn_sb)
        var active_sb := StyleBoxFlat.new()
        active_sb.bg_color = C_ACCENT
        active_sb.set_corner_radius_all(4)
        active_sb.set_content_margin_all(6)
        btn.add_theme_stylebox_override("pressed", active_sb)
        btn.add_theme_font_size_override("font_size", FONT_HINT)
        brush_row.add_child(btn)

    var brush_btns: Array[Button] = []
    for child in brush_row.get_children():
        if child is Button:
            brush_btns.append(child as Button)
    for i in range(brush_btns.size()):
        var bsize: int = brush_sizes[i][0]
        var idx := i
        brush_btns[i].pressed.connect(func() -> void:
            _shadow_alpha_brush_size = bsize
            for j in range(brush_btns.size()):
                brush_btns[j].button_pressed = (j == idx)
        )

    # Toggle and clear
    _shadow_alpha_paint_toggle_btn = CheckButton.new()
    _shadow_alpha_paint_toggle_btn.text = "Enable Alpha Painting"
    _style_checkbutton_transparent(_shadow_alpha_paint_toggle_btn)
    _shadow_alpha_paint_toggle_btn.toggled.connect(_on_shadow_alpha_paint_toggled)
    alpha_content.add_child(_shadow_alpha_paint_toggle_btn)

    var clear_alpha_btn := _make_subtle_button("Clear Mask")
    clear_alpha_btn.pressed.connect(_on_shadow_clear_mask)
    alpha_content.add_child(clear_alpha_btn)
```

**Step 2: Test — open sprite pipeline**

Run: `scenes/tools/sprite_pipeline.tscn`
Expected: Step 5 shows "Shadow Parameters" section with 4 sliders, "Preview Controls" collapsible with 2 sliders, direction/frame nav, and alpha mask painting collapsible. All sliders move. No crash.

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: build shadow step UI with parameter sliders and mask painting controls"
```

---

### Task 3: Build shadow preview viewport (right panel)

Add a SubViewport to the right panel that shows an AnimatedSprite2D with a live SilhouetteShadow. Wire up the preview to respond to slider changes and frame navigation.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Create shadow preview viewport in _build_ui**

In `_build_ui()`, after the light preview container block (around line 470), add the shadow preview container:

```gdscript
# Shadow preview viewport (Step 5), initially hidden
_shadow_preview_container = SubViewportContainer.new()
_shadow_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
_shadow_preview_container.size_flags_vertical = SIZE_EXPAND_FILL
_shadow_preview_container.stretch = true
_shadow_preview_container.visible = false
right_vbox.add_child(_shadow_preview_container)
```

**Step 2: Implement _setup_shadow_preview**

Replace the stub with the full implementation. This creates a SubViewport with background, an AnimatedSprite2D that loads the captured frame sheets, and a SilhouetteShadow child:

```gdscript
func _setup_shadow_preview() -> void:
    # Clean up previous viewport contents
    if _shadow_preview_viewport:
        _shadow_preview_viewport.queue_free()
        _shadow_preview_viewport = null
        _shadow_preview_sprite = null
        _shadow_preview_shadow = null

    _shadow_preview_viewport = SubViewport.new()
    _shadow_preview_viewport.size = Vector2i(512, 512)
    _shadow_preview_viewport.transparent_bg = false
    _shadow_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _shadow_preview_container.add_child(_shadow_preview_viewport)

    # Green background for contrast
    var bg := ColorRect.new()
    bg.color = Color(0.35, 0.55, 0.3, 1.0)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    _shadow_preview_viewport.add_child(bg)

    # Build an AnimatedSprite2D with the captured frames for current direction
    var dir_name: String = _shadow_preview_direction
    if not _captured_sheets.has(dir_name):
        return

    var sheet_image: Image
    if _loaded_from_spritesheet:
        sheet_image = _captured_sheets[dir_name]
    else:
        sheet_image = _process_image(_captured_sheets[dir_name])

    var frame_size := int(output_height_spin.value)
    var frame_count := sheet_image.get_width() / frame_size
    if frame_count <= 0:
        return

    _shadow_preview_frame_count = frame_count
    _shadow_preview_frame = clampi(_shadow_preview_frame, 0, frame_count - 1)

    # Create SpriteFrames with individual frame textures
    var sf := SpriteFrames.new()
    sf.add_animation("preview")
    sf.set_animation_speed("preview", 15)
    sf.set_animation_loop("preview", true)

    var sheet_tex := ImageTexture.create_from_image(sheet_image)
    for i in range(frame_count):
        var atlas := AtlasTexture.new()
        atlas.atlas = sheet_tex
        atlas.region = Rect2(i * frame_size, 0, frame_size, frame_size)
        sf.add_frame("preview", atlas)

    _shadow_preview_sprite = AnimatedSprite2D.new()
    _shadow_preview_sprite.sprite_frames = sf
    _shadow_preview_sprite.animation = "preview"
    _shadow_preview_sprite.centered = true

    # Scale and position to fit viewport
    var vp_size := Vector2(_shadow_preview_viewport.size)
    var target_size := vp_size.y * 0.4
    var sprite_scale := target_size / float(frame_size)
    _shadow_preview_sprite.scale = Vector2(sprite_scale, sprite_scale)
    _shadow_preview_sprite.position = Vector2(vp_size.x * 0.5, vp_size.y * 0.7)
    _shadow_preview_viewport.add_child(_shadow_preview_sprite)

    # Add SilhouetteShadow child
    _shadow_preview_shadow = SilhouetteShadow.new()
    _shadow_preview_shadow.name = "PreviewShadow"
    _shadow_preview_sprite.add_child(_shadow_preview_shadow)

    # Alpha mask overlay for painting feedback
    if _shadow_alpha_overlay:
        _shadow_alpha_overlay.queue_free()
    _shadow_alpha_overlay = Control.new()
    _shadow_alpha_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shadow_alpha_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
    _shadow_alpha_overlay.draw.connect(_draw_shadow_alpha_overlay)
    _shadow_preview_container.add_child(_shadow_alpha_overlay)

    # Wire up input for mask painting
    _shadow_preview_container.gui_input.connect(_on_shadow_viewport_input)

    _update_shadow_preview()
    _update_shadow_preview_frame()
```

**Step 3: Implement _update_shadow_preview**

Updates shadow params from sliders and applies the alpha mask:

```gdscript
func _update_shadow_preview() -> void:
    if not _shadow_preview_shadow or not is_instance_valid(_shadow_preview_shadow):
        return
    _shadow_preview_shadow.apply_params({
        "overlap": _shadow_overlap_slider.value,
        "length": _shadow_length_slider.value,
        "offset_x": _shadow_offset_x_slider.value,
        "offset_y": _shadow_offset_y_slider.value,
        "angle": _shadow_angle_slider.value,
        "opacity": _shadow_opacity_slider.value,
    })
    # Apply alpha mask
    if _shadow_alpha_mask != null:
        if _shadow_mask_tex == null:
            _shadow_mask_tex = ImageTexture.create_from_image(_shadow_alpha_mask)
        else:
            _shadow_mask_tex.update(_shadow_alpha_mask)
        _shadow_preview_shadow.set_shadow_mask(_shadow_mask_tex)
    else:
        _shadow_preview_shadow.set_shadow_mask(null)
    # Redraw overlay
    if _shadow_alpha_overlay:
        _shadow_alpha_overlay.queue_redraw()
```

**Step 4: Implement _update_shadow_preview_frame**

```gdscript
func _update_shadow_preview_frame() -> void:
    if _shadow_preview_sprite and _shadow_preview_sprite.sprite_frames:
        _shadow_preview_sprite.frame = _shadow_preview_frame
    if _shadow_frame_label:
        _shadow_frame_label.text = "Frame %d / %d" % [_shadow_preview_frame + 1, _shadow_preview_frame_count]
```

**Step 5: Test — navigate to shadow step with captured frames**

Run pipeline, capture an animation (or load spritesheet), advance to Step 5.
Expected: Right panel shows the character sprite with a shadow underneath. Sliders update shadow in real-time. Frame navigation works. Play button animates.

**Step 6: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add live shadow preview viewport with AnimatedSprite2D"
```

---

### Task 4: Alpha mask painting on the shadow preview

Port the mask painting system from decoration_pipeline to the sprite pipeline shadow step. Paint on the viewport to modify the shadow alpha mask.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Implement mask painting callbacks**

Add these functions (same pattern as decoration_pipeline lines 1704-1840):

```gdscript
#===============================================================================
# SHADOW ALPHA MASK PAINTING
#===============================================================================

func _on_shadow_alpha_paint_toggled(on: bool) -> void:
    if on and _shadow_alpha_mask == null:
        var frame_size := int(output_height_spin.value)
        _shadow_alpha_mask = Image.create(frame_size, frame_size, false, Image.FORMAT_R8)
        _shadow_alpha_mask.fill(Color(1, 1, 1))
    if _shadow_alpha_overlay:
        _shadow_alpha_overlay.queue_redraw()


func _on_shadow_clear_mask() -> void:
    if _shadow_alpha_mask != null:
        _shadow_alpha_mask.fill(Color(1, 1, 1))
        _update_shadow_preview()


func _on_shadow_viewport_input(event: InputEvent) -> void:
    if not _shadow_alpha_paint_toggle_btn or not _shadow_alpha_paint_toggle_btn.button_pressed:
        return
    if _shadow_alpha_mask == null:
        return

    var mouse_pos: Vector2
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
            return
        mouse_pos = mb.position
    elif event is InputEventMouseMotion:
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            return
        mouse_pos = (event as InputEventMouseMotion).position
    else:
        return

    if not _shadow_preview_sprite:
        return

    var container_size := _shadow_preview_container.size
    var vp_size := Vector2(_shadow_preview_viewport.size)
    var vp_mouse := mouse_pos * (vp_size / container_size)

    var sprite_pos := _shadow_preview_sprite.position
    var sprite_scale := _shadow_preview_sprite.scale
    var frame_size := int(output_height_spin.value)
    var tex_size := Vector2(frame_size, frame_size)
    var tex_origin := sprite_pos - (tex_size * sprite_scale * 0.5)
    var local_pos := (vp_mouse - tex_origin) / sprite_scale

    # Get current frame image for alpha check
    var current_tex := _shadow_preview_sprite.sprite_frames.get_frame_texture("preview", _shadow_preview_frame)
    var current_img := SilhouetteShadow._get_unwrapped_image(current_tex)
    if current_img == null:
        return

    var half_brush := _shadow_alpha_brush_size / 2
    var painted := false
    for by in range(-half_brush, half_brush + 1):
        for bx in range(-half_brush, half_brush + 1):
            var px := int(local_pos.x) + bx
            var py := int(local_pos.y) + by
            if px < 0 or px >= frame_size or py < 0 or py >= frame_size:
                continue
            if current_img.get_pixel(px, py).a < 0.01:
                continue
            _shadow_alpha_mask.set_pixel(px, py, Color(_shadow_alpha_paint_value / 255.0, 0, 0))
            painted = true

    if painted:
        _update_shadow_preview()
```

**Step 2: Implement _draw_shadow_alpha_overlay**

```gdscript
func _draw_shadow_alpha_overlay() -> void:
    if not _shadow_alpha_paint_toggle_btn or not _shadow_alpha_paint_toggle_btn.button_pressed:
        return
    if _shadow_alpha_mask == null or not _shadow_preview_sprite:
        return

    var frame_size := int(output_height_spin.value)
    var container_size := _shadow_preview_container.size
    var vp_size := Vector2(_shadow_preview_viewport.size)
    var sprite_pos := _shadow_preview_sprite.position
    var sprite_scale := _shadow_preview_sprite.scale
    var tex_size := Vector2(frame_size, frame_size)
    var tex_origin := sprite_pos - (tex_size * sprite_scale * 0.5)
    var vp_to_container := container_size / vp_size
    var pixel_w := sprite_scale.x * vp_to_container.x
    var pixel_h := sprite_scale.y * vp_to_container.y

    # Get current frame for alpha check
    var current_tex := _shadow_preview_sprite.sprite_frames.get_frame_texture("preview", _shadow_preview_frame)
    var current_img := SilhouetteShadow._get_unwrapped_image(current_tex)
    if current_img == null:
        return

    var img_w := _shadow_alpha_mask.get_width()
    var img_h := _shadow_alpha_mask.get_height()

    for y in range(img_h):
        for x in range(img_w):
            if current_img.get_pixel(x, y).a < 0.01:
                continue
            var mask_val: float = _shadow_alpha_mask.get_pixel(x, y).r
            if mask_val > 0.99:
                continue
            var screen_x := (tex_origin.x + x * sprite_scale.x) * vp_to_container.x
            var screen_y := (tex_origin.y + y * sprite_scale.y) * vp_to_container.y
            var rect := Rect2(screen_x, screen_y, pixel_w, pixel_h)
            _shadow_alpha_overlay.draw_rect(rect, Color(1.0, 0.2, 0.2, (1.0 - mask_val) * 0.6))
```

**Step 3: Test — paint mask in shadow step**

Navigate to shadow step, toggle "Enable Alpha Painting", paint on the sprite. Red overlay appears. Shadow updates in real-time. Clear button resets.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add alpha mask painting to sprite shadow step"
```

---

### Task 5: Store shadow params + mask as SpriteFrames metadata on Apply

When the user clicks Apply (Step 7), store `shadow_params` dict and optional `shadow_mask` PNG bytes as metadata on the SpriteFrames resource.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (in `_apply_to_spriteframes`, around line 2831)

**Step 1: Add shadow metadata storage after animation frames are written**

In `_apply_to_spriteframes()`, after the animation loop ends and before the "Saving phase" comment (around line 2831), add:

```gdscript
    # Store shadow params as metadata
    var shadow_params := {
        "overlap": _shadow_overlap_slider.value if _shadow_overlap_slider else 0.15,
        "length": _shadow_length_slider.value if _shadow_length_slider else 1.0,
        "offset_x": _shadow_offset_x_slider.value if _shadow_offset_x_slider else 0.0,
        "offset_y": _shadow_offset_y_slider.value if _shadow_offset_y_slider else 0.0,
    }
    frames.set_meta("shadow_params", shadow_params)
    _append_apply_log("--- Shadow params saved: %s ---" % str(shadow_params))

    # Store shadow mask as PNG bytes (if painted)
    if _shadow_alpha_mask != null and _has_shadow_mask_painted():
        var mask_bytes := _shadow_alpha_mask.save_png_to_buffer()
        frames.set_meta("shadow_mask", mask_bytes)
        _append_apply_log("  Shadow mask saved (%d bytes)" % mask_bytes.size())
    elif frames.has_meta("shadow_mask"):
        frames.remove_meta("shadow_mask")
        _append_apply_log("  Shadow mask cleared")
```

**Step 2: Add _has_shadow_mask_painted helper**

```gdscript
func _has_shadow_mask_painted() -> bool:
    if _shadow_alpha_mask == null:
        return false
    for y in range(_shadow_alpha_mask.get_height()):
        for x in range(_shadow_alpha_mask.get_width()):
            if _shadow_alpha_mask.get_pixel(x, y).r < 0.99:
                return true
    return false
```

**Step 3: Test — apply and verify metadata**

Run pipeline end-to-end, apply to SpriteFrames. Check log output shows shadow params saved. Open the `.tres` file in a text editor and search for `shadow_params` — it should appear in the metadata section.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: store shadow params and mask as SpriteFrames metadata on Apply"
```

---

### Task 6: Read shadow metadata at runtime in CharacterVisuals

When CharacterVisuals initializes, read `shadow_params` and `shadow_mask` from the SpriteFrames resource and configure the SilhouetteShadow accordingly.

**Files:**
- Modify: `scripts/combat/character_visuals.gd:108-114`

**Step 1: Update initialize() to read shadow metadata**

Replace the current shadow block (lines 108-112):

```gdscript
# Shadow — silhouette projected from body sprite, angle/opacity from ZoneMood
var shadow := SilhouetteShadow.new()
shadow.name = "Shadow"
shadow.shadow_overlap = 0.15
body_sprite.add_child(shadow)
```

With:

```gdscript
# Shadow — silhouette projected from body sprite
var shadow := SilhouetteShadow.new()
shadow.name = "Shadow"
# Read per-character shadow params from SpriteFrames metadata (set by sprite pipeline)
var shadow_params: Dictionary = body_sprite.sprite_frames.get_meta("shadow_params", {})
if shadow_params.is_empty():
    shadow.shadow_overlap = 0.15  # Default for sprites without metadata
else:
    shadow.apply_params(shadow_params)
body_sprite.add_child(shadow)
# Apply shadow mask if stored
var mask_bytes: PackedByteArray = body_sprite.sprite_frames.get_meta("shadow_mask", PackedByteArray())
if not mask_bytes.is_empty():
    var mask_img := Image.new()
    mask_img.load_png_from_buffer(mask_bytes)
    var mask_tex := ImageTexture.create_from_image(mask_img)
    shadow.set_shadow_mask(mask_tex)
```

**Step 2: Test — run the game**

Play the game. Character shadow should appear with the pipeline-configured overlap/length/offset values. If a mask was painted, it should be applied.

**Step 3: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat: read shadow params and mask from SpriteFrames metadata at runtime"
```

---

### Task 7: Load existing shadow metadata when re-entering shadow step

When the user re-enters Step 5, load any previously-stored shadow_params and shadow_mask from the existing SpriteFrames resource to pre-populate sliders and mask.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add metadata loading at start of _setup_shadow_preview**

At the beginning of `_setup_shadow_preview()`, before creating the viewport, load existing metadata:

```gdscript
# Load existing shadow metadata from SpriteFrames (re-edit support)
var existing_frames := ResourceLoader.load(SPRITEFRAMES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
if existing_frames:
    var params: Dictionary = existing_frames.get_meta("shadow_params", {})
    if not params.is_empty():
        if _shadow_overlap_slider and params.has("overlap"):
            _shadow_overlap_slider.value = params["overlap"]
        if _shadow_length_slider and params.has("length"):
            _shadow_length_slider.value = params["length"]
        if _shadow_offset_x_slider and params.has("offset_x"):
            _shadow_offset_x_slider.value = params["offset_x"]
        if _shadow_offset_y_slider and params.has("offset_y"):
            _shadow_offset_y_slider.value = params["offset_y"]

    # Load existing mask
    if _shadow_alpha_mask == null:
        var mask_bytes: PackedByteArray = existing_frames.get_meta("shadow_mask", PackedByteArray())
        if not mask_bytes.is_empty():
            var mask_img := Image.new()
            mask_img.load_png_from_buffer(mask_bytes)
            if mask_img.get_format() != Image.FORMAT_R8:
                mask_img.convert(Image.FORMAT_R8)
            _shadow_alpha_mask = mask_img
            _shadow_mask_tex = null  # Force re-create on next preview update
```

**Step 2: Test — re-enter shadow step**

Run pipeline, set shadow params, apply. Close and reopen pipeline, advance to step 5. Sliders should show previously saved values. If mask was painted, it should be restored.

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: load existing shadow metadata when re-entering shadow step"
```

---

### Task 8: Disconnect signals on re-setup to prevent stacking

Each time `_setup_shadow_preview` runs (e.g., changing direction), it currently connects `gui_input` and `draw` signals again, which would stack callbacks. Fix this.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Track and disconnect signals**

In `_setup_shadow_preview`, before connecting signals, disconnect any previous connections. The simplest approach: track whether we've already connected and skip re-connection, or disconnect first.

Replace the alpha overlay + input wiring block with:

```gdscript
    # Alpha mask overlay — reuse or create
    if _shadow_alpha_overlay and is_instance_valid(_shadow_alpha_overlay):
        _shadow_alpha_overlay.queue_free()
    _shadow_alpha_overlay = Control.new()
    _shadow_alpha_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _shadow_alpha_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
    _shadow_alpha_overlay.draw.connect(_draw_shadow_alpha_overlay)
    _shadow_preview_container.add_child(_shadow_alpha_overlay)

    # Wire up input — disconnect any previous connection first
    if _shadow_preview_container.gui_input.is_connected(_on_shadow_viewport_input):
        _shadow_preview_container.gui_input.disconnect(_on_shadow_viewport_input)
    _shadow_preview_container.gui_input.connect(_on_shadow_viewport_input)
```

**Step 2: Test**

Switch directions multiple times in shadow step. Painting should work correctly without double-applying strokes.

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "fix: prevent signal stacking on shadow preview re-setup"
```

---

### Task 9: Update header comment and clean up

Update the file header comment to reflect the new 8-step flow and ensure everything is consistent.

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:1-16`

**Step 1: Update header comment**

Change lines 4-15 to:

```gdscript
## Unified tool that chains 3D sprite capture and pixel art conversion
## into a single 8-step wizard flow with saveable presets.
##
## Steps:
##   1. Model & Animation — select model, pick animation, configure camera
##   2. Capture Preview — auto-capture all 3 directions, confirm
##   3. Pixel Art Settings — configure processing, preview result
##   4. Frame Editor — preview processed animation, delete unwanted frames
##   5. Light Preview — interactive light/normal map preview
##   6. Shadow — configure shadow overlap/length/offset, paint alpha mask
##   7. Export — process all directions, save final pixel art
##   8. Apply to SpriteFrames — load exported sheets into player_sprites.tres
```

**Step 2: Test — full end-to-end**

1. Open sprite pipeline
2. Select model, capture animation
3. Configure pixel art settings
4. Review frames in frame editor
5. Check light preview
6. Configure shadow: adjust sliders, paint mask
7. Export
8. Apply to SpriteFrames
9. Play game — character shadow uses pipeline values

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "docs: update sprite pipeline header for 8-step wizard"
```
