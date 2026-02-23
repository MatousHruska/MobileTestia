# Sprite Wizard UI Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the sprite pipeline wizard from raw Godot defaults to a polished dark-theme tool with proper visual hierarchy, step indicator, and section grouping.

**Architecture:** Add color/style constants and theme-building infrastructure at the top of `sprite_pipeline.gd`. Create styled helper methods that replace raw `Label.new()` / `Button.new()` calls. Add a custom `StepIndicator` control drawn with `_draw()`. Refactor each `_build_step*()` function to use the new helpers. Navigation bar and status bar move outside the scroll container.

**Tech Stack:** GDScript, Godot 4 Theme/StyleBox system, custom `_draw()` for step indicator.

**Design doc:** `docs/plans/2026-02-23-sprite-wizard-ui-redesign-design.md`

**Important:** This is a UI-only refactor. No functional logic changes. Verify each task by running the scene with F6 (`scenes/tools/sprite_pipeline.tscn`).

---

### Task 1: Add Color Constants and Theme Builder

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:18-57` (constants section)
- Modify: `scripts/tools/sprite_pipeline.gd:2819-2834` (helpers section)

**Step 1: Add color and style constants after existing constants (before WIZARD STATE section)**

Add these constants after line 57 (after `DIRECTIONS`):

```gdscript
#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12
```

**Step 2: Add theme builder function at the end of the file (after `_set_status`)**

```gdscript
func _build_theme() -> Theme:
	var theme := Theme.new()

	# --- PanelContainer (default panel background) ---
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_PANEL
	panel_sb.set_corner_radius_all(0)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	# --- Section panel (used via add_theme_stylebox_override) ---
	# (Created per-instance in _make_section)

	# --- Button: normal ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_SURFACE
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = C_BORDER
	btn_normal.set_corner_radius_all(4)
	btn_normal.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", btn_normal)

	# --- Button: hover ---
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = C_SURFACE_HOVER
	btn_hover.set_border_width_all(1)
	btn_hover.border_color = C_BORDER
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(8)
	theme.set_stylebox("hover", "Button", btn_hover)

	# --- Button: pressed ---
	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = C_ACCENT
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.set_content_margin_all(8)
	theme.set_stylebox("pressed", "Button", btn_pressed)

	# --- Button: disabled ---
	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(C_SURFACE, 0.3)
	btn_disabled.set_corner_radius_all(4)
	btn_disabled.set_content_margin_all(8)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	# --- Button: focus (remove default focus rect) ---
	var btn_focus := StyleBoxEmpty.new()
	theme.set_stylebox("focus", "Button", btn_focus)

	# --- Button colors ---
	theme.set_color("font_color", "Button", C_TEXT)
	theme.set_color("font_hover_color", "Button", C_TEXT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", C_TEXT_DIM)

	# --- OptionButton inherits Button styles ---
	theme.set_stylebox("normal", "OptionButton", btn_normal)
	theme.set_stylebox("hover", "OptionButton", btn_hover)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed)
	theme.set_stylebox("focus", "OptionButton", btn_focus)
	theme.set_color("font_color", "OptionButton", C_TEXT)
	theme.set_color("font_hover_color", "OptionButton", C_TEXT)

	# --- CheckButton ---
	theme.set_color("font_color", "CheckButton", C_TEXT)
	theme.set_color("font_hover_color", "CheckButton", C_TEXT)
	theme.set_color("font_pressed_color", "CheckButton", C_ACCENT)

	# --- Label ---
	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_font_size("font_size", "Label", FONT_LABEL)

	# --- HSlider ---
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = C_BORDER
	slider_bg.set_content_margin_all(0)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", slider_bg)

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = C_ACCENT
	slider_fill.set_content_margin_all(0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)

	# --- SpinBox (inherits LineEdit) ---
	var line_edit_sb := StyleBoxFlat.new()
	line_edit_sb.bg_color = C_SURFACE
	line_edit_sb.set_border_width_all(1)
	line_edit_sb.border_color = C_BORDER
	line_edit_sb.set_corner_radius_all(4)
	line_edit_sb.set_content_margin_all(6)
	theme.set_stylebox("normal", "LineEdit", line_edit_sb)
	theme.set_stylebox("focus", "LineEdit", line_edit_sb)
	theme.set_color("font_color", "LineEdit", C_TEXT)

	# --- ScrollContainer (invisible scrollbar background) ---
	var scroll_sb := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll_sb)

	# --- HSeparator ---
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_BORDER
	sep_sb.set_content_margin_all(0)
	sep_sb.content_margin_top = 4
	sep_sb.content_margin_bottom = 4
	theme.set_stylebox("separator", "HSeparator", sep_sb)
	theme.set_constant("separation", "HSeparator", 1)

	return theme
```

**Step 3: Run scene with F6 to verify it loads without errors**

No visual change yet since the theme isn't applied. Just verify no syntax errors.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): add UI theme constants and theme builder"
```

---

### Task 2: Add Styled Helper Methods

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (helpers section, after `_set_status`)

**Step 1: Replace `_make_label` and `_make_small_label`, and add new styled helpers**

Replace the existing `_make_label` and `_make_small_label` functions and add new helpers after `_set_status`:

```gdscript
func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", FONT_LABEL)
	return l


func _make_small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_HINT)
	l.add_theme_color_override("font_color", C_TEXT_SEC)
	return l


## Create a section container with a styled header label.
## Returns [section_container, content_vbox] — add controls to content_vbox.
func _make_section(title: String) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	# Header row
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", FONT_SECTION)
	header.add_theme_color_override("font_color", C_ACCENT)
	outer.add_child(header)

	# Content panel
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SECTION
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	outer.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	return [outer, content]


## Create a label-above-control field pair.
func _make_field(label_text: String, control: Control) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	var lbl := _make_label(label_text)
	vbox.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(control)
	return vbox


## Create a collapsible section that starts collapsed.
## Returns [outer_container, content_vbox, toggle_button].
func _make_collapsible(title: String, start_open: bool = false) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	# Toggle button styled as a header
	var toggle_btn := Button.new()
	toggle_btn.text = "%s %s" % ["\u25be" if start_open else "\u25b8", title]
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var toggle_sb := StyleBoxFlat.new()
	toggle_sb.bg_color = Color(C_SECTION, 0.5)
	toggle_sb.set_corner_radius_all(4)
	toggle_sb.set_content_margin_all(6)
	toggle_btn.add_theme_stylebox_override("normal", toggle_sb)
	var toggle_hover := StyleBoxFlat.new()
	toggle_hover.bg_color = Color(C_SECTION, 0.8)
	toggle_hover.set_corner_radius_all(4)
	toggle_hover.set_content_margin_all(6)
	toggle_btn.add_theme_stylebox_override("hover", toggle_hover)
	toggle_btn.add_theme_color_override("font_color", C_ACCENT)
	toggle_btn.add_theme_font_size_override("font_size", FONT_SECTION)
	outer.add_child(toggle_btn)

	# Content
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.visible = start_open
	outer.add_child(content)

	# Toggle logic
	toggle_btn.pressed.connect(func() -> void:
		content.visible = not content.visible
		var arrow := "\u25be" if content.visible else "\u25b8"
		toggle_btn.text = "%s %s" % [arrow, title]
	)

	return [outer, content, toggle_btn]


## Create a segmented toggle button group. Returns the HBoxContainer.
## `options` is Array of {"label": String, "key": String}.
## `callback` receives the selected key.
## The first option is selected by default.
func _make_toggle_group(options: Array, callback: Callable) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	var buttons: Array[Button] = []

	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = opt["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)

		# Style: active gets accent, inactive gets surface
		_apply_toggle_style(btn, i == 0)

		# Corner radius: first gets left corners, last gets right, middle gets none
		var normal_sb := StyleBoxFlat.new()
		normal_sb.bg_color = C_SURFACE
		normal_sb.set_border_width_all(1)
		normal_sb.border_color = C_BORDER
		normal_sb.set_corner_radius_all(0)
		normal_sb.set_content_margin_all(6)
		if i == 0:
			normal_sb.corner_radius_top_left = 4
			normal_sb.corner_radius_bottom_left = 4
		if i == options.size() - 1:
			normal_sb.corner_radius_top_right = 4
			normal_sb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", normal_sb)

		var active_sb := normal_sb.duplicate()
		active_sb.bg_color = C_ACCENT
		active_sb.border_color = C_ACCENT
		btn.add_theme_stylebox_override("pressed", active_sb)

		var hover_sb := normal_sb.duplicate()
		hover_sb.bg_color = C_SURFACE_HOVER
		btn.add_theme_stylebox_override("hover", hover_sb)

		buttons.append(btn)
		hbox.add_child(btn)

	# Wire toggling: when one is pressed, deactivate others
	for i in range(buttons.size()):
		var idx := i
		var opt: Dictionary = options[i]
		buttons[i].pressed.connect(func() -> void:
			for j in range(buttons.size()):
				buttons[j].button_pressed = (j == idx)
				_apply_toggle_style(buttons[j], j == idx)
			callback.call(opt["key"])
		)

	return hbox


func _apply_toggle_style(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_TEXT)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)


## Create a slider with inline value label. Returns [HBoxContainer, HSlider, Label].
func _make_slider_row(min_val: float, max_val: float, default_val: float, step_val: float) -> Array:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var val_label := Label.new()
	val_label.text = str(default_val)
	val_label.custom_minimum_size.x = 40
	val_label.add_theme_font_size_override("font_size", FONT_VALUE)
	val_label.add_theme_color_override("font_color", C_TEXT_SEC)
	hbox.add_child(val_label)

	# Auto-update label
	slider.value_changed.connect(func(v: float) -> void:
		if step_val >= 1.0:
			val_label.text = str(int(v))
		else:
			val_label.text = "%.2f" % v
	)

	return [hbox, slider, val_label]


## Create a styled primary (accent) button.
func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = C_ACCENT_HOVER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn


## Create a styled subtle (outline) button.
func _make_subtle_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_border_width_all(1)
	sb.border_color = C_BORDER
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(C_SURFACE, 0.5)
	hover_sb.set_border_width_all(1)
	hover_sb.border_color = C_BORDER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover_sb)
	return btn
```

**Step 2: Run scene with F6 to verify no syntax errors**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): add styled UI helper methods"
```

---

### Task 3: Create Step Indicator Control

**Files:**
- Create: `scripts/tools/step_indicator.gd`

**Step 1: Create the custom control**

```gdscript
extends Control
## Horizontal step progress indicator drawn with _draw().
## Shows numbered circles connected by lines. Completed = green,
## current = accent blue, future = dim.

const C_SUCCESS := Color("#5BCC7F")
const C_ACCENT := Color("#5B9CF5")
const C_TEXT_DIM := Color("#555570")
const C_TEXT := Color("#E0E0EC")
const C_BG := Color("#252536")

var total_steps := 7
var current_step := 0  # 0-indexed
var step_names: PackedStringArray = [
	"Model & Animation", "Capture Preview", "Pixel Art Settings",
	"Light Preview", "Export", "Weapon Anchors", "Apply to SpriteFrames"
]

func _ready() -> void:
	custom_minimum_size.y = 56


func set_step(step: int) -> void:
	current_step = clampi(step, 0, total_steps - 1)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var padding := 20.0
	var usable := w - padding * 2
	var spacing := usable / float(total_steps - 1) if total_steps > 1 else 0.0
	var y_center := 16.0
	var radius := 6.0
	var line_y := y_center

	# Draw connecting lines first (behind circles)
	for i in range(total_steps - 1):
		var x1 := padding + i * spacing + radius
		var x2 := padding + (i + 1) * spacing - radius
		var color: Color
		if i < current_step:
			color = C_SUCCESS
		else:
			color = Color(C_TEXT_DIM, 0.4)
		draw_line(Vector2(x1, line_y), Vector2(x2, line_y), color, 2.0, true)

	# Draw circles
	for i in range(total_steps):
		var cx := padding + i * spacing
		var cy := y_center
		var pos := Vector2(cx, cy)

		if i < current_step:
			# Completed — filled green
			draw_circle(pos, radius, C_SUCCESS)
			# Checkmark (small V shape)
			var check_size := 3.0
			draw_line(pos + Vector2(-check_size, 0), pos + Vector2(-1, check_size), Color.WHITE, 1.5, true)
			draw_line(pos + Vector2(-1, check_size), pos + Vector2(check_size, -check_size + 1), Color.WHITE, 1.5, true)
		elif i == current_step:
			# Current — accent blue, slightly larger
			draw_circle(pos, radius + 2, Color(C_ACCENT, 0.25))
			draw_circle(pos, radius, C_ACCENT)
			# Number
			_draw_number(pos, i + 1, Color.WHITE)
		else:
			# Future — hollow dim
			draw_arc(pos, radius, 0, TAU, 32, C_TEXT_DIM, 1.5, true)
			_draw_number(pos, i + 1, C_TEXT_DIM)

	# Step name label
	var name_y := y_center + radius + 14.0
	var font := ThemeDB.fallback_font
	var font_size := 12
	var step_name: String = step_names[current_step] if current_step < step_names.size() else ""
	var text_size := font.get_string_size(step_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_x := (w - text_size.x) / 2.0
	draw_string(font, Vector2(text_x, name_y), step_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, C_TEXT)


func _draw_number(pos: Vector2, number: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 9
	var text := str(number)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
```

**Step 2: Run scene with F6 to verify no load errors (the control isn't used yet)**

**Step 3: Commit**

```bash
git add scripts/tools/step_indicator.gd
git commit -m "feat(sprite-wizard): add StepIndicator custom control"
```

---

### Task 4: Refactor _build_ui() Scaffold

This is the core structural change. The left panel layout changes from:

```
PanelContainer
  ScrollContainer
    VBoxContainer
      Title
      StepLabel
      Separator
      [Step containers 1-7]
      Separator
      NavHBox (Back/Next)
      Separator
      StatusLabel
```

To:

```
PanelContainer
  VBoxContainer  (outer, no scroll)
    Title
    StepIndicator (custom draw)
    ScrollContainer  (scrolls only step content)
      VBoxContainer
        [Step containers 1-7]
    HSeparator
    NavHBox (Back/Next) — fixed at bottom
    StatusBar — fixed at bottom
```

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:127-197` (node references — add step_indicator)
- Modify: `scripts/tools/sprite_pipeline.gd:202-216` (\_ready — apply theme)
- Modify: `scripts/tools/sprite_pipeline.gd:228-398` (\_build\_ui — full rewrite)
- Modify: `scripts/tools/sprite_pipeline.gd:1558-1569` (\_go\_to\_step — update step indicator)

**Step 1: Add node reference for step indicator**

At line ~132 (after `step_indicator_label`), add:

```gdscript
var step_indicator: Control  # StepIndicator custom control
```

Keep `step_indicator_label` for now (remove later once step indicator is wired).

**Step 2: Rewrite `_build_ui()` function**

Replace the entire `_build_ui()` function (lines 228-398) with the new version. The key structural changes:

1. Apply theme to root: `theme = _build_theme()`
2. Root gets a `ColorRect` background in `C_BG`
3. Left panel: `PanelContainer` → `VBoxContainer` with Title + StepIndicator (fixed) + ScrollContainer (scrollable step content) + NavBar + StatusBar (fixed)
4. Title styled with `FONT_TITLE`, centered
5. Step indicator is the new custom control
6. Navigation bar: `_make_subtle_button("Back")` and `_make_primary_button("Next")`
7. Status bar: styled with `C_SECTION` background, `FONT_HINT` size, `C_TEXT_SEC` color
8. Right side: unchanged structure (just add `C_BG` background)

```gdscript
func _build_ui() -> void:
	# Apply theme
	theme = _build_theme()

	# Background fill
	var bg_rect := ColorRect.new()
	bg_rect.color = C_BG
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# ── Left panel ──────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	root_hbox.add_child(panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(left_vbox)

	# Title (fixed at top)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_top", 12)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(title_margin)
	var title := Label.new()
	title.text = "Sprite Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Step indicator (fixed, custom draw)
	var StepIndicatorScript := load("res://scripts/tools/step_indicator.gd")
	step_indicator = StepIndicatorScript.new()
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 8)
	indicator_margin.add_theme_constant_override("margin_right", 8)
	indicator_margin.add_theme_constant_override("margin_bottom", 8)
	left_vbox.add_child(indicator_margin)
	indicator_margin.add_child(step_indicator)

	# Keep the old label reference working (hidden, updated by _go_to_step)
	step_indicator_label = Label.new()
	step_indicator_label.visible = false
	left_vbox.add_child(step_indicator_label)

	# Thin separator under indicator
	var top_sep := HSeparator.new()
	left_vbox.add_child(top_sep)

	# Scrollable step content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	# Add padding around step content
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	scroll_vbox.add_child(content_margin)

	var steps_vbox := VBoxContainer.new()
	steps_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	steps_vbox.add_theme_constant_override("separation", 8)
	content_margin.add_child(steps_vbox)

	# Build 7 step containers
	for i in range(7):
		var step_cont := VBoxContainer.new()
		step_cont.add_theme_constant_override("separation", 10)
		step_cont.visible = (i == 0)
		steps_vbox.add_child(step_cont)
		_step_containers.append(step_cont)

	# Build each step's contents
	_build_step1(_step_containers[0])
	_build_step2(_step_containers[1])
	_build_step3(_step_containers[2])
	_build_step_light_preview(_step_containers[3])
	_build_step4(_step_containers[4])
	_build_step_anchors(_step_containers[5])
	_build_step6(_step_containers[6])

	# ── Bottom bar (fixed, not scrolled) ───────────────────
	var bottom_sep := HSeparator.new()
	left_vbox.add_child(bottom_sep)

	# Navigation row
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_top", 8)
	nav_margin.add_theme_constant_override("margin_bottom", 4)
	nav_margin.add_theme_constant_override("margin_left", 12)
	nav_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(nav_margin)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 8)
	nav_margin.add_child(nav_hbox)

	back_button = _make_subtle_button("\u25c0  Back")
	back_button.visible = false
	back_button.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(back_button)

	next_button = _make_primary_button("Next  \u25b6")
	next_button.disabled = true
	next_button.pressed.connect(_on_next_pressed)
	nav_hbox.add_child(next_button)

	# Status bar
	var status_panel := PanelContainer.new()
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = C_SECTION
	status_sb.set_content_margin_all(6)
	status_sb.content_margin_left = 12
	status_sb.content_margin_right = 12
	status_panel.add_theme_stylebox_override("panel", status_sb)
	left_vbox.add_child(status_panel)

	status_label = Label.new()
	status_label.text = "Drop .glb files into assets/3d_imports/ and they will appear above."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", FONT_HINT)
	status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	status_panel.add_child(status_label)

	# ── Right side — preview areas ──────────────────────────
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_hbox.add_child(right_vbox)

	# Top: 3D viewport preview (Steps 1-2)
	var aspect_box := AspectRatioContainer.new()
	aspect_box.ratio = 1.0
	aspect_box.size_flags_horizontal = SIZE_EXPAND_FILL
	aspect_box.size_flags_vertical = SIZE_EXPAND_FILL
	right_vbox.add_child(aspect_box)

	preview_container = SubViewportContainer.new()
	preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	preview_container.stretch = true
	aspect_box.add_child(preview_container)

	# Bottom: 2D pixel preview (Step 3), initially hidden
	var pixel_preview_scroll := ScrollContainer.new()
	pixel_preview_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	pixel_preview_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	pixel_preview_scroll.visible = false
	right_vbox.add_child(pixel_preview_scroll)

	pixel_preview_rect = TextureRect.new()
	pixel_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pixel_preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	pixel_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	pixel_preview_rect.size_flags_vertical = SIZE_EXPAND_FILL
	pixel_preview_scroll.add_child(pixel_preview_rect)

	# Anchor frame display (Step 5), initially hidden
	anchor_frame_display = TextureRect.new()
	anchor_frame_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anchor_frame_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anchor_frame_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	anchor_frame_display.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_frame_display.size_flags_vertical = SIZE_EXPAND_FILL
	anchor_frame_display.visible = false
	anchor_frame_display.gui_input.connect(_on_anchor_frame_input)
	right_vbox.add_child(anchor_frame_display)

	# Light preview viewport (Step 4), initially hidden
	_light_preview_container = SubViewportContainer.new()
	_light_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_light_preview_container.size_flags_vertical = SIZE_EXPAND_FILL
	_light_preview_container.stretch = true
	_light_preview_container.visible = false
	right_vbox.add_child(_light_preview_container)
```

**Step 3: Update `_go_to_step()` to use step indicator**

In `_go_to_step()`, after the existing `step_indicator_label.text = ...` line, add:

```gdscript
	if step_indicator:
		step_indicator.set_step(step)
```

**Step 4: Run scene with F6**

Verify: dark background visible, left panel has dark panel color, step indicator draws at top with circles, nav buttons at bottom outside scroll, status bar at very bottom. Step content should still work as before.

**Step 5: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd scripts/tools/step_indicator.gd
git commit -m "feat(sprite-wizard): refactor scaffold with theme, step indicator, and fixed nav bar"
```

---

### Task 5: Restyle Step 1 — Model & Animation

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step1` (lines 404-537)

**Step 1: Rewrite `_build_step1` to use styled helpers**

Replace the entire `_build_step1` function:

```gdscript
func _build_step1(parent: VBoxContainer) -> void:
	# Model selector
	var sec := _make_section("Model & Animation")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(_on_model_selected)
	content.add_child(_make_field("3D Model", model_dropdown))

	anim_dropdown = OptionButton.new()
	anim_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	anim_dropdown.item_selected.connect(_on_animation_selected)
	content.add_child(_make_field("Animation", anim_dropdown))

	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 2
	frame_count_spin.max_value = 60
	frame_count_spin.value = 8
	frame_count_spin.step = 1
	content.add_child(_make_field("Frames per direction", frame_count_spin))

	# Preset status
	preset_status_label = Label.new()
	preset_status_label.text = "(no preset)"
	preset_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	preset_status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(preset_status_label)

	# Camera settings (collapsible)
	var cam := _make_collapsible("Camera Settings")
	parent.add_child(cam[0])
	camera_settings_container = cam[1]

	# Camera elevation
	var elev_data := _make_slider_row(10.0, 80.0, 30.0, 1.0)
	camera_elevation_slider = elev_data[1]
	camera_elevation_label = elev_data[2]
	camera_elevation_slider.value_changed.connect(_on_elevation_changed)
	camera_settings_container.add_child(_make_field("Elevation (degrees)", elev_data[0]))

	# Camera zoom
	var zoom_data := _make_slider_row(0.5, 15.0, 3.0, 0.1)
	camera_zoom_slider = zoom_data[1]
	camera_zoom_label = zoom_data[2]
	camera_zoom_slider.value_changed.connect(_on_zoom_changed)
	camera_settings_container.add_child(_make_field("Zoom", zoom_data[0]))

	# Camera target height
	var target_data := _make_slider_row(0.0, 5.0, 1.0, 0.05)
	camera_target_y_slider = target_data[1]
	camera_target_y_label = target_data[2]
	camera_target_y_slider.value_changed.connect(_on_target_y_changed)
	camera_settings_container.add_child(_make_field("Target height", target_data[0]))

	# Direction preview buttons
	var dir_group := _make_toggle_group([
		{"label": "Front", "key": "front"},
		{"label": "Back", "key": "back"},
		{"label": "Side", "key": "side"},
	], func(key: String) -> void:
		var angles := {"front": 0.0, "back": 180.0, "side": 90.0}
		_on_preview_direction(angles[key])
	)
	camera_settings_container.add_child(_make_field("Preview direction", dir_group))

	# Save preset button
	var save_preset_btn := Button.new()
	save_preset_btn.text = "Save Camera Preset"
	save_preset_btn.pressed.connect(_save_preset)
	camera_settings_container.add_child(save_preset_btn)
```

**Step 2: Run scene with F6**

Verify Step 1 shows: section header "Model & Animation" in accent blue, fields with labels above controls, collapsible "Camera Settings" section that expands/collapses, slider rows with value readouts.

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 1 — Model & Animation"
```

---

### Task 6: Restyle Step 2 — Capture Preview

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step2` (lines 543-595)

**Step 1: Rewrite `_build_step2`**

```gdscript
func _build_step2(parent: VBoxContainer) -> void:
	var sec := _make_section("Capture Preview")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Preview mode toggle
	var mode_group := _make_toggle_group([
		{"label": "Color", "key": "color"},
		{"label": "Normal", "key": "normal"},
		{"label": "Shadow", "key": "shadow"},
	], func(key: String) -> void:
		_capture_preview_mode = key
		_update_capture_preview()
	)
	content.add_child(mode_group)

	content.add_child(_make_small_label("Capturing 3 directions..."))

	# Direction previews
	content.add_child(_make_label("Down:"))
	capture_down_rect = TextureRect.new()
	capture_down_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_down_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_down_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_down_rect)

	content.add_child(_make_label("Up:"))
	capture_up_rect = TextureRect.new()
	capture_up_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_up_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_up_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_up_rect)

	content.add_child(_make_label("Right:"))
	capture_right_rect = TextureRect.new()
	capture_right_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	capture_right_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	capture_right_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_child(capture_right_rect)
```

**Step 2: Run scene with F6, navigate to Step 2**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 2 — Capture Preview"
```

---

### Task 7: Restyle Step 3 — Pixel Art Settings

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step3` (lines 601-789)

**Step 1: Rewrite `_build_step3`**

This is the most control-dense step. Organize into: main section (direction, mode, output height, alpha, palette) + collapsible subsections (dithering, outline, denoising).

```gdscript
func _build_step3(parent: VBoxContainer) -> void:
	# Main settings section
	var sec := _make_section("Pixel Art Settings")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Direction preview selector
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_preview_direction = key
		_update_pixel_preview()
	)
	content.add_child(_make_field("Preview direction", dir_group))

	# Preview mode toggle
	var mode_group := _make_toggle_group([
		{"label": "Color", "key": "color"},
		{"label": "Normal", "key": "normal"},
		{"label": "Lit", "key": "lit"},
	], func(key: String) -> void:
		_pixel_preview_mode = key
		_update_pixel_preview()
	)
	content.add_child(_make_field("Preview mode", mode_group))

	# Output height
	output_height_spin = SpinBox.new()
	output_height_spin.min_value = 16
	output_height_spin.max_value = 256
	output_height_spin.value = 64
	output_height_spin.step = 8
	output_height_spin.value_changed.connect(_on_pixel_setting_changed)
	content.add_child(_make_field("Output height (px)", output_height_spin))

	# Alpha threshold
	var alpha_data := _make_slider_row(0, 255, 128, 1)
	alpha_threshold_slider = alpha_data[1]
	alpha_threshold_label = alpha_data[2]
	alpha_threshold_slider.value_changed.connect(_on_alpha_threshold_changed)
	content.add_child(_make_field("Alpha threshold", alpha_data[0]))

	# Palette section
	var palette_sec := _make_section("Palette")
	parent.add_child(palette_sec[0])
	var palette_content: VBoxContainer = palette_sec[1]

	palette_mode_dropdown = OptionButton.new()
	palette_mode_dropdown.add_item("None")
	palette_mode_dropdown.add_item("Load from Palettes")
	palette_mode_dropdown.add_item("Generate from Captures")
	palette_mode_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_mode_dropdown.item_selected.connect(_on_palette_mode_changed)
	palette_content.add_child(_make_field("Mode", palette_mode_dropdown))

	palette_file_dropdown = OptionButton.new()
	palette_file_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_file_dropdown.visible = false
	palette_file_dropdown.item_selected.connect(_on_palette_file_selected)
	palette_content.add_child(palette_file_dropdown)

	max_palette_colors_spin = SpinBox.new()
	max_palette_colors_spin.min_value = 4
	max_palette_colors_spin.max_value = 128
	max_palette_colors_spin.value = 32
	max_palette_colors_spin.step = 4
	max_palette_colors_spin.visible = false
	palette_content.add_child(_make_field("Max colors", max_palette_colors_spin))

	generate_palette_button = Button.new()
	generate_palette_button.text = "Generate Palette"
	generate_palette_button.visible = false
	generate_palette_button.pressed.connect(_on_generate_palette_pressed)
	palette_content.add_child(generate_palette_button)

	palette_preview_container = HFlowContainer.new()
	palette_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_content.add_child(palette_preview_container)

	# Dithering (collapsible)
	var dither := _make_collapsible("Dithering")
	parent.add_child(dither[0])
	var dither_content: VBoxContainer = dither[1]

	dithering_toggle = CheckButton.new()
	dithering_toggle.text = "Enable"
	dithering_toggle.toggled.connect(_on_pixel_toggle_changed)
	dither_content.add_child(dithering_toggle)

	var strength_data := _make_slider_row(0.0, 1.0, 0.5, 0.05)
	dithering_strength_slider = strength_data[1]
	dithering_strength_slider.value_changed.connect(_on_pixel_setting_changed)
	dither_content.add_child(_make_field("Strength", strength_data[0]))

	dithering_pattern_dropdown = OptionButton.new()
	dithering_pattern_dropdown.add_item("2x2")
	dithering_pattern_dropdown.add_item("4x4")
	dithering_pattern_dropdown.add_item("8x8")
	dithering_pattern_dropdown.selected = 1
	dithering_pattern_dropdown.item_selected.connect(_on_pixel_setting_changed)
	dither_content.add_child(_make_field("Pattern", dithering_pattern_dropdown))

	# Outline (collapsible)
	var outline := _make_collapsible("Outline")
	parent.add_child(outline[0])
	var outline_content: VBoxContainer = outline[1]

	outline_toggle = CheckButton.new()
	outline_toggle.text = "Enable"
	outline_toggle.toggled.connect(_on_pixel_toggle_changed)
	outline_content.add_child(outline_toggle)

	var outline_color_hbox := HBoxContainer.new()
	outline_color_hbox.add_theme_constant_override("separation", 8)
	outline_content.add_child(outline_color_hbox)
	outline_color_hbox.add_child(_make_label("Color:"))
	outline_color_picker = ColorPickerButton.new()
	outline_color_picker.color = Color.BLACK
	outline_color_picker.custom_minimum_size = Vector2(40, 30)
	outline_color_picker.color_changed.connect(_on_pixel_color_changed)
	outline_color_hbox.add_child(outline_color_picker)

	# Denoising (collapsible)
	var denoise := _make_collapsible("Denoising")
	parent.add_child(denoise[0])
	var denoise_content: VBoxContainer = denoise[1]

	denoising_toggle = CheckButton.new()
	denoising_toggle.text = "Enable"
	denoising_toggle.toggled.connect(_on_pixel_toggle_changed)
	denoise_content.add_child(denoising_toggle)

	denoising_min_cluster_spin = SpinBox.new()
	denoising_min_cluster_spin.min_value = 1
	denoising_min_cluster_spin.max_value = 50
	denoising_min_cluster_spin.value = 4
	denoising_min_cluster_spin.step = 1
	denoising_min_cluster_spin.value_changed.connect(_on_pixel_setting_changed)
	denoise_content.add_child(_make_field("Min cluster size", denoising_min_cluster_spin))

	# Bottom actions
	var actions_sec := _make_section("Actions")
	parent.add_child(actions_sec[0])
	var actions_content: VBoxContainer = actions_sec[1]

	var save_settings_btn := Button.new()
	save_settings_btn.text = "Save Settings to Preset"
	save_settings_btn.pressed.connect(_save_pixel_art_preset)
	actions_content.add_child(save_settings_btn)

	show_original_toggle = CheckButton.new()
	show_original_toggle.text = "Show Original"
	show_original_toggle.toggled.connect(_on_pixel_toggle_changed)
	actions_content.add_child(show_original_toggle)
```

**Step 2: Run scene with F6, navigate to Step 3**

Verify: sections with headers, collapsible dithering/outline/denoising, segmented toggle groups for direction and mode.

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 3 — Pixel Art Settings"
```

---

### Task 8: Restyle Step 4 — Light Preview

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step_light_preview` (lines 795-913)

**Step 1: Rewrite `_build_step_light_preview`**

```gdscript
func _build_step_light_preview(parent: VBoxContainer) -> void:
	var sec := _make_section("Light Preview")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	content.add_child(_make_small_label("Drag the light around to test normal maps."))

	# Direction buttons
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_on_light_preview_direction(key)
	)
	content.add_child(_make_field("Direction", dir_group))

	# Frame navigation
	var frame_hbox := HBoxContainer.new()
	frame_hbox.add_theme_constant_override("separation", 4)
	content.add_child(frame_hbox)
	var prev_btn := Button.new()
	prev_btn.text = "\u25c0"
	prev_btn.custom_minimum_size.x = 32
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
	next_frame_btn.text = "\u25b6"
	next_frame_btn.custom_minimum_size.x = 32
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

	# Light controls section
	var light_sec := _make_section("Light Settings")
	parent.add_child(light_sec[0])
	var light_content: VBoxContainer = light_sec[1]

	# Light color
	var color_hbox := HBoxContainer.new()
	color_hbox.add_theme_constant_override("separation", 8)
	light_content.add_child(color_hbox)
	color_hbox.add_child(_make_label("Color:"))
	_light_color_picker = ColorPickerButton.new()
	_light_color_picker.color = Color("#FFAA44")
	_light_color_picker.custom_minimum_size = Vector2(60, 30)
	_light_color_picker.color_changed.connect(func(c: Color) -> void:
		if _light_preview_light:
			_light_preview_light.color = c
	)
	color_hbox.add_child(_light_color_picker)

	# Intensity slider
	var int_data := _make_slider_row(0.0, 3.0, 1.5, 0.1)
	_light_intensity_slider = int_data[1]
	_light_intensity_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.energy = v
	)
	light_content.add_child(_make_field("Intensity", int_data[0]))

	# Height slider
	var height_data := _make_slider_row(0.0, 200.0, 50.0, 5.0)
	_light_height_slider = height_data[1]
	_light_height_slider.value_changed.connect(func(v: float) -> void:
		if _light_preview_light:
			_light_preview_light.height = v
	)
	light_content.add_child(_make_field("Height", height_data[0]))

	# Ambient slider
	var amb_data := _make_slider_row(0.0, 1.0, 0.2, 0.05)
	_light_ambient_slider = amb_data[1]
	_light_ambient_slider.value_changed.connect(func(_v: float) -> void:
		_update_light_preview_ambient()
	)
	light_content.add_child(_make_field("Ambient", amb_data[0]))

	# Presets
	var preset_group := _make_toggle_group([
		{"label": "Torch", "key": "torch"},
		{"label": "Sun", "key": "sunlight"},
		{"label": "Moon", "key": "moonlight"},
		{"label": "Spell", "key": "spell"},
	], func(key: String) -> void:
		var presets := {
			"torch": {"color": Color("#FFAA44"), "intensity": 1.5, "height": 50.0, "ambient": 0.2},
			"sunlight": {"color": Color("#FFFDE0"), "intensity": 1.0, "height": 150.0, "ambient": 0.4},
			"moonlight": {"color": Color("#8899CC"), "intensity": 0.8, "height": 120.0, "ambient": 0.15},
			"spell": {"color": Color("#44FFDD"), "intensity": 2.0, "height": 30.0, "ambient": 0.1},
		}
		_apply_light_preset(presets[key])
	)
	light_content.add_child(_make_field("Presets", preset_group))
```

**Step 2: Run scene with F6, navigate to Step 4**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 4 — Light Preview"
```

---

### Task 9: Restyle Step 5 — Export

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step4` (lines 1062-1088)

**Step 1: Rewrite `_build_step4`**

```gdscript
func _build_step4(parent: VBoxContainer) -> void:
	var sec := _make_section("Export")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	export_log_label = Label.new()
	export_log_label.text = ""
	export_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	export_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	export_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(export_log_label)

	anchor_weapon_anim_toggle = CheckButton.new()
	anchor_weapon_anim_toggle.text = "Weapon Animation (edit anchors next)"
	content.add_child(anchor_weapon_anim_toggle)

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	content.add_child(run_again_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(_on_done_pressed)
	content.add_child(done_btn)
```

**Step 2: Run scene with F6, navigate to Step 5 (Export)**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 5 — Export"
```

---

### Task 10: Restyle Step 6 — Weapon Anchors

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step_anchors` (lines 1094-1208)

**Step 1: Rewrite `_build_step_anchors`**

```gdscript
func _build_step_anchors(parent: VBoxContainer) -> void:
	# Navigation section
	var nav_sec := _make_section("Weapon Anchor Editor")
	parent.add_child(nav_sec[0])
	var nav_content: VBoxContainer = nav_sec[1]

	# Direction selector
	var dir_group := _make_toggle_group([
		{"label": "Down", "key": "down"},
		{"label": "Up", "key": "up"},
		{"label": "Right", "key": "right"},
	], func(key: String) -> void:
		_on_anchor_dir_selected(key)
	)
	nav_content.add_child(_make_field("Direction", dir_group))
	# Store references — we need to highlight the active direction button
	# The toggle group already handles visual state via button_pressed

	# Frame navigator
	var frame_hbox := HBoxContainer.new()
	frame_hbox.add_theme_constant_override("separation", 4)
	nav_content.add_child(frame_hbox)

	var prev_btn := Button.new()
	prev_btn.text = "\u25c0"
	prev_btn.custom_minimum_size.x = 32
	prev_btn.pressed.connect(func() -> void:
		if _anchor_current_frame > 0:
			_anchor_current_frame -= 1
			_update_anchor_display()
	)
	frame_hbox.add_child(prev_btn)

	anchor_frame_label = Label.new()
	anchor_frame_label.text = "1 / 1"
	anchor_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anchor_frame_label.size_flags_horizontal = SIZE_EXPAND_FILL
	frame_hbox.add_child(anchor_frame_label)

	var next_frame_btn := Button.new()
	next_frame_btn.text = "\u25b6"
	next_frame_btn.custom_minimum_size.x = 32
	next_frame_btn.pressed.connect(func() -> void:
		if _anchor_current_frame < _anchor_frame_count - 1:
			_anchor_current_frame += 1
			_update_anchor_display()
	)
	frame_hbox.add_child(next_frame_btn)

	# Tool selector section
	var tool_sec := _make_section("Tool")
	parent.add_child(tool_sec[0])
	var tool_content: VBoxContainer = tool_sec[1]

	var tool_group := _make_toggle_group([
		{"label": "Grip", "key": "grip"},
		{"label": "Direction", "key": "direction"},
		{"label": "Erase", "key": "erase"},
	], func(key: String) -> void:
		_on_anchor_tool_selected(key)
	)
	tool_content.add_child(tool_group)

	# Color legend
	var legend_hbox := HBoxContainer.new()
	legend_hbox.add_theme_constant_override("separation", 12)
	tool_content.add_child(legend_hbox)
	var grip_legend := Label.new()
	grip_legend.text = "\u25a0 Grip"
	grip_legend.add_theme_color_override("font_color", Color("#FF00AA"))
	grip_legend.add_theme_font_size_override("font_size", FONT_HINT)
	legend_hbox.add_child(grip_legend)
	var dir_legend := Label.new()
	dir_legend.text = "\u25a0 Direction"
	dir_legend.add_theme_color_override("font_color", Color("#00FFFF"))
	dir_legend.add_theme_font_size_override("font_size", FONT_HINT)
	legend_hbox.add_child(dir_legend)

	# Anchor info
	anchor_info_label = Label.new()
	anchor_info_label.text = "Grip: \u2014\nDirection: \u2014\nWeapon dir: \u2014"
	anchor_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anchor_info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_info_label.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_info_label.add_theme_color_override("font_color", C_TEXT_SEC)
	tool_content.add_child(anchor_info_label)

	# Actions section
	var act_sec := _make_section("Actions")
	parent.add_child(act_sec[0])
	var act_content: VBoxContainer = act_sec[1]

	anchor_grid_toggle = CheckButton.new()
	anchor_grid_toggle.text = "Show Grid"
	anchor_grid_toggle.toggled.connect(func(_on: bool) -> void: _update_anchor_display())
	act_content.add_child(anchor_grid_toggle)

	var copy_btn := Button.new()
	copy_btn.text = "Copy to All Frames"
	copy_btn.pressed.connect(_on_anchor_copy_to_all)
	act_content.add_child(copy_btn)

	var undo_btn := Button.new()
	undo_btn.text = "Undo Last Placement"
	undo_btn.pressed.connect(_on_anchor_undo)
	act_content.add_child(undo_btn)

	var save_btn := _make_primary_button("Save Anchor Changes")
	save_btn.pressed.connect(_on_anchor_save)
	act_content.add_child(save_btn)

	# Log
	anchor_log_label = Label.new()
	anchor_log_label.text = ""
	anchor_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anchor_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	act_content.add_child(anchor_log_label)
```

**Important:** The old code stored buttons in `_anchor_dir_buttons` and `_anchor_tool_buttons` dictionaries for highlight updates. With the new toggle group, highlighting is handled by the toggle group itself. Check that `_update_anchor_button_highlights()` (line ~1225) doesn't break. If it does, make it a no-op:

```gdscript
func _update_anchor_button_highlights() -> void:
	# Toggle group handles highlighting automatically
	pass
```

**Step 2: Run scene with F6, navigate to Step 6 (Anchors)**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 6 — Weapon Anchors"
```

---

### Task 11: Restyle Step 7 — Apply to SpriteFrames

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — function `_build_step6` (lines 1511-1552)

**Step 1: Rewrite `_build_step6`**

```gdscript
func _build_step6(parent: VBoxContainer) -> void:
	var sec := _make_section("Apply to SpriteFrames")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	var path_label := Label.new()
	path_label.text = "Target: %s" % SPRITEFRAMES_PATH
	path_label.add_theme_font_size_override("font_size", FONT_HINT)
	path_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(path_label)

	# Dynamic summary
	content.add_child(_make_label("Animations to apply:"))
	apply_summary_container = VBoxContainer.new()
	apply_summary_container.add_theme_constant_override("separation", 2)
	content.add_child(apply_summary_container)

	apply_button = _make_primary_button("Apply to SpriteFrames")
	apply_button.pressed.connect(_apply_to_spriteframes)
	content.add_child(apply_button)

	apply_log_label = Label.new()
	apply_log_label.text = ""
	apply_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_log_label.size_flags_horizontal = SIZE_EXPAND_FILL
	apply_log_label.add_theme_font_size_override("font_size", FONT_HINT)
	apply_log_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(apply_log_label)

	var run_again_btn := Button.new()
	run_again_btn.text = "Run Again"
	run_again_btn.pressed.connect(_on_run_again_pressed)
	content.add_child(run_again_btn)

	var done_btn := _make_primary_button("Done")
	done_btn.pressed.connect(_on_done_pressed)
	content.add_child(done_btn)
```

**Step 2: Run scene with F6, navigate to Step 7**

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): restyle Step 7 — Apply to SpriteFrames"
```

---

### Task 12: Update Navigation Logic for New Step Indicator

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` — `_go_to_step` function (~line 1558), `_set_status` function

**Step 1: Update `_go_to_step` to update step indicator and style the Next button for Export step**

The existing code at line 1565 changes `next_button.text`. Update it to also style the Export button with warning color:

```gdscript
# In _go_to_step, after the next_button.text line:
	if step == 4:
		# Export step — style Next/Export button as warning
		var warning_sb := StyleBoxFlat.new()
		warning_sb.bg_color = C_WARNING
		warning_sb.set_corner_radius_all(4)
		warning_sb.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("normal", warning_sb)
		var warning_hover := StyleBoxFlat.new()
		warning_hover.bg_color = Color(C_WARNING, 0.8)
		warning_hover.set_corner_radius_all(4)
		warning_hover.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("hover", warning_hover)
	else:
		# Reset to primary accent style
		var accent_sb := StyleBoxFlat.new()
		accent_sb.bg_color = C_ACCENT
		accent_sb.set_corner_radius_all(4)
		accent_sb.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("normal", accent_sb)
		var accent_hover := StyleBoxFlat.new()
		accent_hover.bg_color = C_ACCENT_HOVER
		accent_hover.set_corner_radius_all(4)
		accent_hover.set_content_margin_all(10)
		next_button.add_theme_stylebox_override("hover", accent_hover)
```

And add the step indicator update:
```gdscript
	if step_indicator:
		step_indicator.set_step(step)
```

**Step 2: Update `_set_status` to color success/error messages**

```gdscript
func _set_status(text: String) -> void:
	status_label.text = text
	# Color based on content
	if text.begins_with("Error") or text.begins_with("Failed"):
		status_label.add_theme_color_override("font_color", C_WARNING)
	elif text.begins_with("Done") or text.begins_with("Saved") or text.begins_with("Export"):
		status_label.add_theme_color_override("font_color", C_SUCCESS)
	else:
		status_label.add_theme_color_override("font_color", C_TEXT_SEC)
	print("[SpritePipeline] %s" % text)
```

**Step 3: Run scene with F6, navigate through all steps**

Verify: step indicator updates, Export step shows warning-colored button, status messages show colored text.

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(sprite-wizard): update navigation and status styling"
```

---

### Task 13: Final Verification and Cleanup

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd` (if needed)

**Step 1: Run through the full wizard flow with F6**

Test each step:
1. Step 1: Select a model, verify dropdowns/sliders styled correctly, toggle Camera Settings
2. Step 2: Verify capture preview with Color/Normal/Shadow toggle group
3. Step 3: Verify all controls — direction toggle, mode toggle, sliders, collapsible sections
4. Step 4: Test light preview — direction toggle, frame nav, light controls, presets
5. Step 5: Verify export step — log label, weapon anim toggle, Done button
6. Step 6: Test anchor editor — direction toggle, frame nav, tool toggle, actions
7. Step 7: Verify apply step — summary, apply button, log

**Step 2: Fix any issues found during testing**

Common things to check:
- All signal connections still work (callbacks, value_changed, pressed)
- `_update_anchor_button_highlights()` doesn't error (should be no-op or removed)
- Scroll container scrolls properly with new padding
- Step indicator draws correctly at different window sizes
- Collapsible sections expand/collapse properly

**Step 3: Final commit**

```bash
git add scripts/tools/sprite_pipeline.gd scripts/tools/step_indicator.gd
git commit -m "feat(sprite-wizard): complete UI redesign — final polish"
```
