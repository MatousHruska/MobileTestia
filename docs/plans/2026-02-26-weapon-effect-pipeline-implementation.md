# Weapon & Effect Asset Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build two standalone Godot tool scenes — a Weapon Sprite Pipeline (2D→pixel art with anchor placement) and an Effect Capture Pipeline (3D→directional pixel art spritesheets) — then integrate both into the Attack Composer and runtime CharacterVisuals.

**Architecture:** Two new wizard-style tools (`weapon_pipeline.tscn`, `effect_pipeline.tscn`) following the same scene-per-tool pattern as the existing `sprite_pipeline.tscn` and `attack_composer.tscn`. Both reuse `PixelArtProcessing` (static utility at `scripts/tools/pixel_art_processing.gd`). The Attack Composer gets folder-scanning dropdowns for weapons/effects, falling back to existing placeholder systems. Runtime integration updates `WeaponTextureLoader` and `CharacterVisuals` to load real assets first.

**Tech Stack:** Godot 4, GDScript, SubViewport (for 3D capture), `PixelArtProcessing` static methods, JSON metadata files

**Key Reference Files:**
- Design doc: `docs/plans/2026-02-26-weapon-effect-pipeline-design.md`
- Pixel art processing: `scripts/tools/pixel_art_processing.gd` (226 lines)
- Sprite pipeline (pattern reference): `scripts/tools/sprite_pipeline.gd` (3343 lines)
- Attack composer: `scripts/tools/attack_composer/attack_composer.gd` (2227 lines)
- Character visuals: `scripts/combat/character_visuals.gd` (695 lines)
- Weapon texture loader: `scripts/combat/weapon_texture_loader.gd` (97 lines)
- Placeholder weapons: `scripts/combat/placeholder_weapon_sprites.gd` (560 lines)
- Placeholder effects: `scripts/combat/placeholder_effect_sprites.gd` (552 lines)

---

## Task 1: Weapon Pipeline — Scene Skeleton & Step Navigation

**Files:**
- Create: `scenes/tools/weapon_pipeline.tscn`
- Create: `scripts/tools/weapon_pipeline.gd`

### Step 1: Create the weapon pipeline script with wizard skeleton

Create `scripts/tools/weapon_pipeline.gd` with the 3-step wizard framework. This mirrors the pattern in `sprite_pipeline.gd` (step containers, navigation buttons, dark theme) but is much simpler — no SubViewport, no 3D scene.

```gdscript
extends Control

# ── Constants ────────────────────────────────────────────
const WEAPONS_DIR := "res://assets/sprites/weapons"
const PRESETS_DIR := "res://assets/sprites/presets"

# Theme (matches sprite_pipeline / attack_composer)
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#2A2A3E")
const C_SECTION := Color("#252538")
const C_SURFACE := Color("#363650")
const C_SURFACE_HOVER := Color("#454568")
const C_BORDER := Color("#4A4A6A")
const C_TEXT := Color("#E0E0F0")
const C_TEXT_DIM := Color("#8888AA")
const C_ACCENT := Color("#5B9CF5")
const C_SUCCESS := Color("#66BB6A")
const C_WARNING := Color("#FFA726")
const C_DANGER := Color("#EF5350")
const C_GRIP := Color("#FF00AA")    # Magenta — grip marker
const C_TIP := Color("#00FFFF")     # Cyan — tip marker

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_BODY := 13

const STEP_NAMES: Array[String] = [
	"Load & Preview",
	"Pixel Art Processing",
	"Anchor Placement & Export",
]

# ── State ────────────────────────────────────────────────
var _current_step: int = 0
var _step_containers: Array[VBoxContainer] = []

# Step 1 state
var _source_image: Image = null
var _source_texture: ImageTexture = null
var _weapon_id: String = ""
var _weapon_category: String = "melee_1h"

# Step 2 state
var _processed_image: Image = null
var _processed_texture: ImageTexture = null
var _target_height: int = 24
var _alpha_threshold: int = 128
var _dithering_enabled: bool = false
var _dithering_strength: float = 0.5
var _dithering_pattern: int = 1
var _palette_enabled: bool = false
var _palette_colors: PackedColorArray = PackedColorArray()
var _outline_enabled: bool = false
var _outline_color: Color = Color.BLACK
var _denoising_enabled: bool = true
var _denoising_min_cluster: int = 2

# Step 3 state
var _grip_point: Vector2i = Vector2i(-1, -1)
var _tip_point: Vector2i = Vector2i(-1, -1)
var _anchor_zoom: float = 12.0

# ── UI References ────────────────────────────────────────
var _step_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _main_container: VBoxContainer = null


func _ready() -> void:
	_build_ui()
	_show_step(0)


func _build_ui() -> void:
	# Root setup
	var root_style := StyleBoxFlat.new()
	root_style.bg_color = C_BG
	add_theme_stylebox_override("panel", root_style)
	custom_minimum_size = Vector2(1024, 768)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# Title bar
	_build_title_bar(root_vbox)

	# Step navigation bar
	_build_nav_bar(root_vbox)

	# Main content area
	_main_container = VBoxContainer.new()
	_main_container.size_flags_vertical = SIZE_EXPAND_FILL
	_main_container.add_theme_constant_override("separation", 8)
	root_vbox.add_child(_main_container)

	# Build each step's container
	for i in STEP_NAMES.size():
		var step_cont := VBoxContainer.new()
		step_cont.size_flags_vertical = SIZE_EXPAND_FILL
		step_cont.visible = false
		_main_container.add_child(step_cont)
		_step_containers.append(step_cont)

	_build_step_0(_step_containers[0])
	_build_step_1(_step_containers[1])
	_build_step_2(_step_containers[2])


func _build_title_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = C_PANEL
	bar_style.content_margin_left = 16
	bar_style.content_margin_right = 16
	bar_style.content_margin_top = 10
	bar_style.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", bar_style)
	parent.add_child(bar)

	var title := Label.new()
	title.text = "Weapon Sprite Pipeline"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	bar.add_child(title)


func _build_nav_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = C_SECTION
	bar_style.content_margin_left = 16
	bar_style.content_margin_right = 16
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6

	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	parent.add_child(bar_panel)
	bar_panel.add_child(bar)

	_prev_btn = Button.new()
	_prev_btn.text = "< Back"
	_prev_btn.pressed.connect(_on_prev_step)
	bar.add_child(_prev_btn)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", FONT_SECTION)
	_step_label.add_theme_color_override("font_color", C_TEXT)
	_step_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_step_label)

	_next_btn = Button.new()
	_next_btn.text = "Next >"
	_next_btn.pressed.connect(_on_next_step)
	bar.add_child(_next_btn)


func _show_step(step: int) -> void:
	_current_step = clampi(step, 0, STEP_NAMES.size() - 1)
	for i in _step_containers.size():
		_step_containers[i].visible = (i == _current_step)
	_step_label.text = "Step %d/%d — %s" % [_current_step + 1, STEP_NAMES.size(), STEP_NAMES[_current_step]]
	_prev_btn.disabled = (_current_step == 0)
	_next_btn.text = "Export" if _current_step == STEP_NAMES.size() - 1 else "Next >"


func _on_prev_step() -> void:
	_show_step(_current_step - 1)


func _on_next_step() -> void:
	if _current_step == STEP_NAMES.size() - 1:
		_export_weapon()
	else:
		if _current_step == 0 and _source_image == null:
			push_warning("WeaponPipeline: Load an image first")
			return
		if _current_step == 0:
			_process_pixel_art()
		_show_step(_current_step + 1)


# ── Step 0: Load & Preview ──────────────────────────────
func _build_step_0(_container: VBoxContainer) -> void:
	pass  # Placeholder — implemented in Task 2


# ── Step 1: Pixel Art Processing ─────────────────────────
func _build_step_1(_container: VBoxContainer) -> void:
	pass  # Placeholder — implemented in Task 3


# ── Step 2: Anchor Placement & Export ────────────────────
func _build_step_2(_container: VBoxContainer) -> void:
	pass  # Placeholder — implemented in Task 4


func _process_pixel_art() -> void:
	pass  # Placeholder — implemented in Task 3


func _export_weapon() -> void:
	pass  # Placeholder — implemented in Task 4
```

### Step 2: Create the scene file

Create `scenes/tools/weapon_pipeline.tscn` — a minimal scene with just the root Control node pointing to the script. The entire UI is built programmatically (same pattern as attack_composer.tscn).

The scene should be:
- Root node: `Control` named "WeaponPipeline"
- Script: `res://scripts/tools/weapon_pipeline.gd`
- Layout: Full rect anchor preset

### Step 3: Verify the skeleton runs

Run the scene with F6 in Godot (set `weapon_pipeline.tscn` as main scene temporarily, or run it directly). Verify:
- Dark themed window appears
- Title bar shows "Weapon Sprite Pipeline"
- Navigation shows "Step 1/3 — Load & Preview"
- Back/Next buttons work (Next disabled validation, Back disabled on step 1)

### Step 4: Commit

```bash
git add scripts/tools/weapon_pipeline.gd scenes/tools/weapon_pipeline.tscn
git commit -m "feat(weapon-pipeline): scaffold 3-step wizard with navigation"
```

---

## Task 2: Weapon Pipeline — Step 1: Load & Preview

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd` (the `_build_step_0` function)

### Step 1: Implement the Load & Preview step

Replace the `_build_step_0` placeholder with a UI that has:
- A **file dialog button** that opens `FileDialog` filtered to `*.png, *.jpg, *.jpeg`
- A **weapon ID** text field (LineEdit) — auto-populated from filename sans extension
- A **weapon category** dropdown (OptionButton) with options: `melee_1h`, `melee_2h`, `dagger`, `ranged`, `magic`
- A **source preview** panel showing the loaded image at fit-to-container scale
- A status label showing image dimensions

Key implementation details:
- Use `FileDialog` with `access = ACCESS_FILESYSTEM` to load from anywhere on disk
- Load image via `Image.load(path)` — works for PNG and JPG
- Create `ImageTexture.create_from_image()` for display
- Store in `_source_image` and `_source_texture`
- Auto-populate `_weapon_id` from the filename (e.g., `sword_iron.png` → `sword_iron`)

Layout: left column (300px) for controls, right panel for preview — same split as attack_composer.

### Step 2: Test the load step

Run the scene, click the load button, select a PNG image file. Verify:
- Image appears in the preview panel
- Weapon ID is auto-populated
- Category dropdown is functional
- Image dimensions shown in status label

### Step 3: Commit

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): add Step 1 — image loading and preview"
```

---

## Task 3: Weapon Pipeline — Step 2: Pixel Art Processing

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd` (the `_build_step_1` and `_process_pixel_art` functions)

**Reference:** `scripts/tools/pixel_art_processing.gd` — all static methods are reused here.

### Step 1: Build the processing UI

Replace `_build_step_1` with a UI containing:
- **Target height** SpinBox (range 8–128, default 24, step 1)
- **Alpha threshold** SpinBox (range 0–255, default 128)
- **Dithering** section: CheckButton toggle, strength HSlider (0.0–1.0), pattern OptionButton (2×2, 4×4, 8×8)
- **Palette** section: CheckButton toggle, file picker for palette PNG
- **Outline** section: CheckButton toggle, ColorPickerButton (default black)
- **Denoising** section: CheckButton toggle, min cluster SpinBox (default 2)
- **Preview panel** showing source (left) and processed (right) side-by-side, both zoomed to fill

Every control change triggers `_process_pixel_art()` for real-time preview.

### Step 2: Implement `_process_pixel_art()`

```gdscript
func _process_pixel_art() -> void:
	if _source_image == null:
		return

	# Downscale
	var src_w: int = _source_image.get_width()
	var src_h: int = _source_image.get_height()
	var scale_factor: float = float(_target_height) / float(src_h)
	var target_w: int = maxi(1, roundi(src_w * scale_factor))

	_processed_image = _source_image.duplicate()
	_processed_image.resize(target_w, _target_height, Image.INTERPOLATE_BILINEAR)

	# Apply processing pipeline (same order as sprite_pipeline)
	PixelArtProcessing.apply_alpha_threshold(_processed_image, _alpha_threshold)

	if _dithering_enabled:
		PixelArtProcessing.apply_ordered_dithering(_processed_image, _dithering_strength, _dithering_pattern)

	if _palette_enabled and _palette_colors.size() > 0:
		PixelArtProcessing.apply_palette_mapping(_processed_image, _palette_colors)

	if _outline_enabled:
		PixelArtProcessing.apply_outline(_processed_image, _outline_color)

	if _denoising_enabled:
		PixelArtProcessing.apply_denoising(_processed_image, _denoising_min_cluster)

	_processed_texture = ImageTexture.create_from_image(_processed_image)
	_update_processing_preview()
```

Note: `PixelArtProcessing` is a class_name defined in `scripts/tools/pixel_art_processing.gd` — it's globally available in Godot without `preload`.

### Step 3: Test the processing step

Load a weapon image, advance to Step 2. Verify:
- Processed preview updates in real-time as you adjust sliders
- Alpha threshold visibly affects transparency
- Outline toggle adds/removes a pixel border
- Target height slider changes the output resolution
- Source and processed shown side-by-side

### Step 4: Commit

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): add Step 2 — pixel art processing with live preview"
```

---

## Task 4: Weapon Pipeline — Step 3: Anchor Placement & Export

**Files:**
- Modify: `scripts/tools/weapon_pipeline.gd` (the `_build_step_2` and `_export_weapon` functions)

### Step 1: Build the anchor placement UI

Replace `_build_step_2` with:
- **Zoomed preview** of the processed weapon at `_anchor_zoom` (default 12x) — rendered via a `TextureRect` with `EXPAND_FIT_WIDTH` and `texture_filter = TEXTURE_FILTER_NEAREST` for crisp pixel display
- **Mode buttons**: "Place Grip" (magenta) and "Place Tip" (cyan) — clicking one activates placement mode
- **Coordinate labels** showing grip (x, y) and tip (x, y) positions
- **Visual markers** drawn over the zoomed preview using `_draw()` override on a custom Control
- **Vector line** from grip to tip showing the weapon's axis
- **Export button** at the bottom

The zoomed preview should be a custom `Control` subclass (inner class or just `_draw()` on a panel) that:
1. Draws the processed texture at zoom scale with nearest-neighbor filtering
2. Overlays colored crosshair markers at grip and tip positions
3. Draws a line from grip to tip
4. Handles click events to set grip/tip based on active placement mode

### Step 2: Implement click-to-place anchor logic

```gdscript
# In the zoomed preview's _gui_input or parent's handler:
func _on_anchor_preview_click(event: InputEventMouseButton, preview_rect: Rect2) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if _processed_image == null:
		return

	# Convert click position to pixel coordinates
	var local_pos: Vector2 = event.position - preview_rect.position
	var px: int = floori(local_pos.x / _anchor_zoom)
	var py: int = floori(local_pos.y / _anchor_zoom)

	# Clamp to image bounds
	px = clampi(px, 0, _processed_image.get_width() - 1)
	py = clampi(py, 0, _processed_image.get_height() - 1)

	if _placing_grip:
		_grip_point = Vector2i(px, py)
	elif _placing_tip:
		_tip_point = Vector2i(px, py)

	_update_anchor_display()
```

### Step 3: Implement `_export_weapon()`

```gdscript
func _export_weapon() -> void:
	if _processed_image == null:
		push_warning("WeaponPipeline: No processed image to export")
		return
	if _weapon_id.is_empty():
		push_warning("WeaponPipeline: Set a weapon ID first")
		return
	if _grip_point == Vector2i(-1, -1):
		push_warning("WeaponPipeline: Place the grip point first")
		return
	if _tip_point == Vector2i(-1, -1):
		push_warning("WeaponPipeline: Place the tip point first")
		return

	# Ensure output directory exists
	var dir_path: String = WEAPONS_DIR + "/" + _weapon_id
	DirAccess.make_dir_recursive_absolute(dir_path)

	# Save weapon PNG
	var png_path: String = dir_path + "/weapon.png"
	_processed_image.save_png(png_path)

	# Save metadata JSON
	var metadata := {
		"weapon_id": _weapon_id,
		"category": _weapon_category,
		"grip": [_grip_point.x, _grip_point.y],
		"tip": [_tip_point.x, _tip_point.y],
		"source_size": [_source_image.get_width(), _source_image.get_height()],
		"export_size": [_processed_image.get_width(), _processed_image.get_height()],
		"processing": {
			"target_height": _target_height,
			"alpha_threshold": _alpha_threshold,
			"dithering_enabled": _dithering_enabled,
			"outline_enabled": _outline_enabled,
			"denoising_enabled": _denoising_enabled,
		},
	}

	var json_path: String = dir_path + "/metadata.json"
	var json_str: String = JSON.stringify(metadata, "\t")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	file.store_string(json_str)
	file.close()

	print("WeaponPipeline: Exported to %s" % dir_path)
```

### Step 4: Test the full weapon pipeline

1. Load a weapon image
2. Process it (adjust settings)
3. Place grip and tip points
4. Click Export
5. Verify output exists at `assets/sprites/weapons/{weapon_id}/weapon.png` and `metadata.json`
6. Open `metadata.json` and verify grip/tip coordinates are correct

### Step 5: Commit

```bash
git add scripts/tools/weapon_pipeline.gd
git commit -m "feat(weapon-pipeline): add Step 3 — anchor placement and export"
```

---

## Task 5: Effect Pipeline — Scene Skeleton & Step Navigation

**Files:**
- Create: `scenes/tools/effect_pipeline.tscn`
- Create: `scripts/tools/effect_pipeline.gd`

### Step 1: Create the effect pipeline script with wizard skeleton

This follows the same wizard framework as the weapon pipeline but with 5 steps and a SubViewport for 3D capture. The 3D capture infrastructure is modeled after `sprite_pipeline.gd` lines 2120–2230.

```gdscript
extends Control

# ── Constants ────────────────────────────────────────────
const IMPORT_DIR := "res://assets/3d_imports"
const EFFECTS_DIR := "res://assets/sprites/effects"
const PRESETS_DIR := "res://assets/sprites/presets"
const CAPTURES_DIR := "res://assets/sprites/captures"
const CAPTURE_OVERSCAN := 1.5

# Theme (same as weapon_pipeline / attack_composer)
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#2A2A3E")
const C_SECTION := Color("#252538")
const C_SURFACE := Color("#363650")
const C_SURFACE_HOVER := Color("#454568")
const C_BORDER := Color("#4A4A6A")
const C_TEXT := Color("#E0E0F0")
const C_TEXT_DIM := Color("#8888AA")
const C_ACCENT := Color("#5B9CF5")
const C_SUCCESS := Color("#66BB6A")
const C_WARNING := Color("#FFA726")
const C_DANGER := Color("#EF5350")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_BODY := 13

const STEP_NAMES: Array[String] = [
	"Model & Animation",
	"Capture Preview",
	"Pixel Art Processing",
	"Frame Editor",
	"Export",
]

const DIRECTIONS: Array[Dictionary] = [
	{ "name": "down", "rotation_y": 0.0 },
	{ "name": "up", "rotation_y": PI },
	{ "name": "right", "rotation_y": -PI / 2.0 },
]

# ── State ────────────────────────────────────────────────
var _current_step: int = 0
var _step_containers: Array[VBoxContainer] = []

# Step 1 state — model & animation
var _current_model_path: String = ""
var _current_model: Node3D = null
var _current_anim_player: AnimationPlayer = null
var _available_anims: PackedStringArray = PackedStringArray()
var _selected_anim: String = ""
var _effect_id: String = ""
var _camera_elevation: float = 30.0
var _camera_zoom: float = 3.0
var _camera_target_y: float = 1.0

# Step 2 state — capture
var _capture_viewport: SubViewport = null
var _capture_camera: Camera3D = null
var _capture_scene_root: Node3D = null
var _captured_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
var _capture_frame_count: int = 0

# Step 3 state — pixel art processing
var _processed_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
var _target_height: int = 32
var _alpha_threshold: int = 64      # Softer default for effects
var _dithering_enabled: bool = false
var _dithering_strength: float = 0.5
var _dithering_pattern: int = 1
var _palette_enabled: bool = false
var _palette_colors: PackedColorArray = PackedColorArray()
var _outline_enabled: bool = false
var _outline_color: Color = Color.BLACK
var _denoising_enabled: bool = true
var _denoising_min_cluster: int = 2

# Step 4 state — frame editor
var _frame_images: Dictionary = {}  # { "down": Array[Image], "up": ..., "right": ... }
var _frame_textures: Dictionary = {}
var _deleted_frames: Array[int] = []
var _preview_direction: String = "down"
var _preview_frame_index: int = 0
var _effect_fps: float = 15.0

# ── 3D Capture infrastructure ────────────────────────────
var _capture_env: WorldEnvironment = null
var _capture_light: DirectionalLight3D = null
```

Build the same wizard navigation framework (title bar, nav bar, step containers) as the weapon pipeline. The `_ready()`, `_build_ui()`, `_build_title_bar()`, `_build_nav_bar()`, `_show_step()` functions are structurally identical — adapt from weapon_pipeline.gd with 5 steps instead of 3.

Add placeholder functions for all 5 step builders:
```gdscript
func _build_step_0(container: VBoxContainer) -> void: pass  # Task 6
func _build_step_1(container: VBoxContainer) -> void: pass  # Task 7
func _build_step_2(container: VBoxContainer) -> void: pass  # Task 8
func _build_step_3(container: VBoxContainer) -> void: pass  # Task 9
func _build_step_4(container: VBoxContainer) -> void: pass  # Task 10
```

### Step 2: Create the scene file

Create `scenes/tools/effect_pipeline.tscn`:
- Root node: `Control` named "EffectPipeline"
- Script: `res://scripts/tools/effect_pipeline.gd`
- Layout: Full rect anchor preset

### Step 3: Verify the skeleton runs

Run the scene. Verify 5-step navigation works, dark theme renders correctly.

### Step 4: Commit

```bash
git add scripts/tools/effect_pipeline.gd scenes/tools/effect_pipeline.tscn
git commit -m "feat(effect-pipeline): scaffold 5-step wizard with navigation"
```

---

## Task 6: Effect Pipeline — Step 1: Model & Animation Selection

**Files:**
- Modify: `scripts/tools/effect_pipeline.gd` (`_build_step_0`)

**Reference:** `scripts/tools/sprite_pipeline.gd` lines 1–100 for model scanning, and the model loading pattern.

### Step 1: Build the model selection UI

Replace `_build_step_0` with:
- **Model dropdown** (OptionButton) scanning `IMPORT_DIR` for `.glb`/`.gltf` files using `DirAccess`
- **Animation dropdown** (OptionButton) populated after model loads — lists animations from `AnimationPlayer`
- **Effect ID** text field (LineEdit) — auto-populated from model name + animation name
- **Camera controls**: elevation HSlider (0–90, default 30), zoom HSlider (1–10, default 3), target Y HSlider (0–3, default 1)
- **3D preview** — a SubViewport showing the loaded model with transparent background

Key implementation details:
- Scan `IMPORT_DIR` with `DirAccess.get_files_at()`, filter for `.glb` and `.gltf`
- Load model via `load(model_path).instantiate()` into the SubViewport's scene root
- Find `AnimationPlayer` recursively in the instantiated model (same approach as `sprite_pipeline.gd`)
- Set SubViewport to transparent: `transparent_bg = true`
- Camera: orthographic, positioned using elevation/zoom/target_y
- Set up environment with no ambient light (effects should show their own emissive/albedo colors)

### Step 2: Test the model selection

Run scene, select a .glb from the dropdown. Verify:
- Model loads and appears in the 3D preview
- Animations are listed in the animation dropdown
- Camera controls adjust the view
- Effect ID is auto-populated

### Step 3: Commit

```bash
git add scripts/tools/effect_pipeline.gd
git commit -m "feat(effect-pipeline): add Step 1 — model and animation selection"
```

---

## Task 7: Effect Pipeline — Step 2: Capture Preview

**Files:**
- Modify: `scripts/tools/effect_pipeline.gd` (`_build_step_1` and capture functions)

**Reference:** `scripts/tools/sprite_pipeline.gd` lines 2120–2230 for the capture algorithm.

### Step 1: Build the capture UI

Replace `_build_step_1` with:
- **Capture button** — triggers the full 3-direction capture
- **Direction preview panels** — three side-by-side panels showing thumbnail strips of captured frames for down/up/right
- **Frame count label** — shows detected frame count
- **Status label** — shows capture progress

### Step 2: Implement the capture function

This is the core of the effect pipeline. Model after the sprite pipeline's `_capture_animation()` but **without normal map or shadow passes** — only the color pass.

```gdscript
func _capture_effect() -> void:
	if _current_anim_player == null or _selected_anim.is_empty():
		push_warning("EffectPipeline: Select a model and animation first")
		return

	_captured_sheets.clear()
	var anim: Animation = _current_anim_player.get_animation(_selected_anim)
	var anim_length: float = anim.length
	_capture_frame_count = maxi(1, ceili(anim_length * _effect_fps))

	for dir_info in DIRECTIONS:
		var dir_name: String = dir_info["name"]
		var rotation_y: float = dir_info["rotation_y"]

		# Rotate model to face direction
		_capture_scene_root.rotation.y = rotation_y

		# Capture each frame
		var frame_size: int = _capture_viewport.size.y
		var sheet := Image.create(frame_size * _capture_frame_count, frame_size, false, Image.FORMAT_RGBA8)

		for f in _capture_frame_count:
			var seek_time: float = (float(f) / float(_capture_frame_count)) * anim_length
			_current_anim_player.seek(seek_time, true)

			# Wait for render
			await RenderingServer.frame_post_draw

			var frame_img: Image = _capture_viewport.get_texture().get_image()

			# Overscan: detect character extent, compute pan, re-render
			# (Same overscan algorithm as sprite_pipeline.gd lines 2176-2205)
			# For initial implementation, just use the direct capture

			sheet.blit_rect(frame_img, Rect2i(0, 0, frame_size, frame_size), Vector2i(f * frame_size, 0))

		_captured_sheets[dir_name] = sheet

	_update_capture_preview()
```

**Key difference from character capture:** No normal map pass, no shadow pass. Just the color capture. The overscan algorithm can be ported from sprite_pipeline.gd for better framing, but start with direct capture and add overscan as a refinement.

### Step 3: Test the capture

Load a 3D effect model, select animation, click Capture. Verify:
- All 3 direction strips appear in preview
- Frames show the effect animation from each angle
- Transparent background is preserved

### Step 4: Commit

```bash
git add scripts/tools/effect_pipeline.gd
git commit -m "feat(effect-pipeline): add Step 2 — 3-direction capture"
```

---

## Task 8: Effect Pipeline — Step 3: Pixel Art Processing

**Files:**
- Modify: `scripts/tools/effect_pipeline.gd` (`_build_step_2`)

**Reference:** Same approach as `weapon_pipeline.gd` Task 3, but applied to spritesheets per direction.

### Step 1: Build the processing UI

Same processing controls as the weapon pipeline Step 2, but with effect-tuned defaults:
- Alpha threshold: 64 (not 128)
- Dithering: Off
- Palette: Off
- Outline: Off
- Denoising: On

### Step 2: Implement sheet processing

Process each direction's captured sheet through the pixel art pipeline:

```gdscript
func _process_all_sheets() -> void:
	_processed_sheets.clear()

	for dir_name in ["down", "up", "right"]:
		if not _captured_sheets.has(dir_name):
			continue

		var src: Image = _captured_sheets[dir_name]
		var src_h: int = src.get_height()
		var scale_factor: float = float(_target_height) / float(src_h)
		var target_w: int = maxi(1, roundi(src.get_width() * scale_factor))

		var processed: Image = src.duplicate()
		processed.resize(target_w, _target_height, Image.INTERPOLATE_BILINEAR)

		PixelArtProcessing.apply_alpha_threshold(processed, _alpha_threshold)

		if _dithering_enabled:
			PixelArtProcessing.apply_ordered_dithering(processed, _dithering_strength, _dithering_pattern)

		if _palette_enabled and _palette_colors.size() > 0:
			PixelArtProcessing.apply_palette_mapping(processed, _palette_colors)

		if _outline_enabled:
			PixelArtProcessing.apply_outline(processed, _outline_color)

		if _denoising_enabled:
			PixelArtProcessing.apply_denoising(processed, _denoising_min_cluster)

		_processed_sheets[dir_name] = processed

	_update_processing_preview()
```

### Step 3: Test

Adjust processing controls, verify real-time preview updates for all 3 directions. Verify softer defaults produce visually distinct results from character pipeline defaults.

### Step 4: Commit

```bash
git add scripts/tools/effect_pipeline.gd
git commit -m "feat(effect-pipeline): add Step 3 — pixel art processing with soft defaults"
```

---

## Task 9: Effect Pipeline — Step 4: Frame Editor

**Files:**
- Modify: `scripts/tools/effect_pipeline.gd` (`_build_step_3`)

### Step 1: Build the frame editor UI

- **Animation preview** — AnimatedSprite2D or manual frame stepping in a preview panel
- **Frame strip** — horizontal row of frame thumbnails at pixel scale, scrollable
- **Delete frame button** — removes selected frame(s) from all 3 directions simultaneously
- **Direction toggle** — buttons to switch preview between down/up/right
- **Playback controls** — play/pause, step forward/back, FPS adjustment
- **Onion skin toggle** — overlay previous frame at reduced opacity

### Step 2: Implement frame extraction from sheets

Split processed spritesheets into individual frame images:

```gdscript
func _extract_frames() -> void:
	_frame_images.clear()
	_frame_textures.clear()
	_deleted_frames.clear()

	for dir_name in ["down", "up", "right"]:
		if not _processed_sheets.has(dir_name):
			continue

		var sheet: Image = _processed_sheets[dir_name]
		var frame_h: int = sheet.get_height()
		var frame_w: int = frame_h  # Square frames
		var count: int = sheet.get_width() / frame_w

		var images: Array[Image] = []
		var textures: Array[ImageTexture] = []

		for f in count:
			var frame_img: Image = Image.create(frame_w, frame_h, false, Image.FORMAT_RGBA8)
			frame_img.blit_rect(sheet, Rect2i(f * frame_w, 0, frame_w, frame_h), Vector2i.ZERO)
			images.append(frame_img)
			textures.append(ImageTexture.create_from_image(frame_img))

		_frame_images[dir_name] = images
		_frame_textures[dir_name] = textures
```

### Step 3: Implement frame deletion

When deleting frames, remove from all 3 directions at the same index to keep them synchronized:

```gdscript
func _delete_frame(index: int) -> void:
	for dir_name in ["down", "up", "right"]:
		if _frame_images.has(dir_name) and index < _frame_images[dir_name].size():
			_frame_images[dir_name].remove_at(index)
			_frame_textures[dir_name].remove_at(index)
	_capture_frame_count -= 1
	_preview_frame_index = clampi(_preview_frame_index, 0, maxi(0, _capture_frame_count - 1))
	_update_frame_editor_preview()
```

### Step 4: Test

Process an effect, advance to Frame Editor. Verify:
- Individual frames are visible in the strip
- Playback animates through frames
- Deleting a frame removes it from all directions
- Direction toggle switches the preview

### Step 5: Commit

```bash
git add scripts/tools/effect_pipeline.gd
git commit -m "feat(effect-pipeline): add Step 4 — frame editor with deletion and playback"
```

---

## Task 10: Effect Pipeline — Step 5: Export

**Files:**
- Modify: `scripts/tools/effect_pipeline.gd` (`_build_step_4`)

### Step 1: Build the export UI

- **Summary panel** — shows effect ID, frame count, frame size, estimated duration
- **Export button** — saves all 3 directional spritesheets + metadata.json

### Step 2: Implement export

```gdscript
func _export_effect() -> void:
	if _frame_images.is_empty():
		push_warning("EffectPipeline: No frames to export")
		return
	if _effect_id.is_empty():
		push_warning("EffectPipeline: Set an effect ID first")
		return

	var dir_path: String = EFFECTS_DIR + "/" + _effect_id
	DirAccess.make_dir_recursive_absolute(dir_path)

	var frame_count: int = 0
	var frame_size: int = _target_height

	# Re-assemble edited frames into spritesheets and save
	for dir_name in ["down", "up", "right"]:
		if not _frame_images.has(dir_name):
			continue

		var frames: Array = _frame_images[dir_name]
		frame_count = frames.size()
		if frame_count == 0:
			continue

		var sheet_w: int = frame_size * frame_count
		var sheet := Image.create(sheet_w, frame_size, false, Image.FORMAT_RGBA8)

		for f in frame_count:
			var frame_img: Image = frames[f]
			sheet.blit_rect(frame_img, Rect2i(0, 0, frame_size, frame_size), Vector2i(f * frame_size, 0))

		var png_path: String = dir_path + "/" + _effect_id + "_" + dir_name + ".png"
		sheet.save_png(png_path)

	# Calculate duration from frame count and FPS
	var duration_ms: int = roundi((float(frame_count) / _effect_fps) * 1000.0)

	# Save metadata
	var metadata := {
		"effect_id": _effect_id,
		"frame_count": frame_count,
		"frame_size": frame_size,
		"duration_ms": duration_ms,
		"fps": _effect_fps,
		"anchor_offset": [0, 0],
		"processing": {
			"target_height": _target_height,
			"alpha_threshold": _alpha_threshold,
			"dithering_enabled": _dithering_enabled,
			"outline_enabled": _outline_enabled,
			"denoising_enabled": _denoising_enabled,
		},
	}

	var json_path: String = dir_path + "/metadata.json"
	var json_str: String = JSON.stringify(metadata, "\t")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	file.store_string(json_str)
	file.close()

	print("EffectPipeline: Exported %d frames to %s" % [frame_count, dir_path])
```

### Step 3: Test the full effect pipeline end-to-end

1. Select a 3D model with an effect animation
2. Configure camera
3. Capture from 3 directions
4. Process to pixel art
5. Edit frames (trim if needed)
6. Export
7. Verify output: `assets/sprites/effects/{effect_id}/{effect_id}_down.png`, `_up.png`, `_right.png`, `metadata.json`

### Step 4: Commit

```bash
git add scripts/tools/effect_pipeline.gd
git commit -m "feat(effect-pipeline): add Step 5 — export directional spritesheets"
```

---

## Task 11: Attack Composer — Weapon Folder Scanning

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Key locations:**
- Line 480: `_weapon_set = PlaceholderWeaponSprites.create_sword_set()` — replace with folder scan
- Constants section (line 1–26): add `WEAPONS_DIR` constant

### Step 1: Add weapon folder scanning

Add a constant and scanning function:

```gdscript
const WEAPONS_DIR := "res://assets/sprites/weapons"

func _scan_weapon_folders() -> Array[String]:
	"""Scan WEAPONS_DIR for folders containing weapon.png + metadata.json"""
	var weapon_ids: Array[String] = []
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return weapon_ids
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var weapon_path: String = WEAPONS_DIR + "/" + folder + "/weapon.png"
			var meta_path: String = WEAPONS_DIR + "/" + folder + "/metadata.json"
			if FileAccess.file_exists(weapon_path) and FileAccess.file_exists(meta_path):
				weapon_ids.append(folder)
		folder = dir.get_next()
	return weapon_ids


func _load_weapon_from_folder(weapon_id: String) -> Dictionary:
	"""Load a real weapon asset from folder, returning the same dict format as PlaceholderWeaponSprites"""
	var dir_path: String = WEAPONS_DIR + "/" + weapon_id
	var img := Image.load_from_file(dir_path + "/weapon.png")
	if img == null:
		return {}

	var tex := ImageTexture.create_from_image(img)

	# Read metadata
	var meta_file := FileAccess.open(dir_path + "/metadata.json", FileAccess.READ)
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()

	var grip := Vector2(meta["grip"][0], meta["grip"][1])
	var tip := Vector2(meta["tip"][0], meta["tip"][1])

	# Return in the same format as PlaceholderWeaponSprites sets
	# Single texture for all directions (rotation handled by anchor system)
	return {
		"down": tex, "up": tex, "right": tex,
		"grip_down": grip, "grip_up": grip, "grip_right": grip,
		"tip_down": tip, "tip_up": tip, "tip_right": tip,
	}
```

### Step 2: Add weapon dropdown to the UI

In the left panel's Load/Save section, add an OptionButton for weapons populated by `_scan_weapon_folders()`. When changed, load the selected weapon and update `_weapon_set`. Keep a "Placeholder: Sword" entry as fallback.

Replace line 480's hardcoded `PlaceholderWeaponSprites.create_sword_set()` with:
```gdscript
var weapon_ids: Array[String] = _scan_weapon_folders()
if weapon_ids.size() > 0:
	_weapon_set = _load_weapon_from_folder(weapon_ids[0])
else:
	_weapon_set = PlaceholderWeaponSprites.create_sword_set()
```

### Step 3: Test

Export a weapon using the Weapon Pipeline, then open the Attack Composer. Verify:
- The weapon dropdown shows the exported weapon ID
- Selecting it loads the real weapon texture
- The weapon appears correctly in the preview viewport positioned at anchor points
- If no real weapons exist, placeholder still works

### Step 4: Commit

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add weapon folder scanning and dropdown"
```

---

## Task 12: Attack Composer — Effect Folder Scanning

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

### Step 1: Add effect folder scanning

```gdscript
const EFFECTS_DIR := "res://assets/sprites/effects"

func _scan_effect_folders() -> Array[String]:
	"""Scan EFFECTS_DIR for folders containing directional spritesheets + metadata.json"""
	var effect_ids: Array[String] = []
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		return effect_ids
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var meta_path: String = EFFECTS_DIR + "/" + folder + "/metadata.json"
			if FileAccess.file_exists(meta_path):
				effect_ids.append(folder)
		folder = dir.get_next()
	return effect_ids
```

### Step 2: Update the effect dropdown

The effect dropdown in the frame properties section currently has hardcoded entries. Replace with:
1. Scan real effect folders
2. Add those IDs to the dropdown first (with a visual indicator like "[Asset]" prefix)
3. Add placeholder effect IDs after (with "[Placeholder]" prefix)
4. When selecting a real effect, load the directional spritesheet matching `_preview_direction` for preview

### Step 3: Test

Export an effect using the Effect Pipeline, then open the Attack Composer. Verify:
- The effect dropdown shows the exported effect ID
- Selecting it shows the effect in the timeline's effect track
- Preview shows the effect spritesheet frames
- Placeholder effects still work

### Step 4: Commit

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add effect folder scanning and dropdown"
```

---

## Task 13: Runtime — WeaponTextureLoader Update

**Files:**
- Modify: `scripts/combat/weapon_texture_loader.gd`

**Reference:** Current code at `scripts/combat/weapon_texture_loader.gd` (97 lines). The `_load_from_disk` function (line 34) already checks `WEAPON_SPRITES_BASE` for direction-specific PNGs.

### Step 1: Update weapon loading to support new format

The new weapon format uses a single `weapon.png` + `metadata.json` instead of direction-specific PNGs. Update `_load_from_disk()` to check for the new format first, then fall back to the old format:

```gdscript
static func _load_from_disk(sprite_id: String) -> Dictionary:
	var base_path: String = WEAPON_SPRITES_BASE + sprite_id

	# New format: single weapon.png + metadata.json
	var new_weapon_path: String = base_path + "/weapon.png"
	var new_meta_path: String = base_path + "/metadata.json"

	if FileAccess.file_exists(new_weapon_path) and FileAccess.file_exists(new_meta_path):
		var img := Image.load_from_file(new_weapon_path)
		if img != null:
			var tex := ImageTexture.create_from_image(img)
			var meta_file := FileAccess.open(new_meta_path, FileAccess.READ)
			var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
			meta_file.close()

			var grip := Vector2(meta["grip"][0], meta["grip"][1])
			var tip := Vector2(meta["tip"][0], meta["tip"][1])

			return {
				"down": tex, "up": tex, "right": tex,
				"grip_down": grip, "grip_up": grip, "grip_right": grip,
				"tip_down": tip, "tip_up": tip, "tip_right": tip,
			}

	# Legacy format: per-direction PNGs (down.png, up.png, right.png)
	# ... (keep existing code)
```

### Step 2: Test

Verify that weapons exported by the Weapon Pipeline load correctly at runtime via `WeaponTextureLoader.load_weapon_textures()`.

### Step 3: Commit

```bash
git add scripts/combat/weapon_texture_loader.gd
git commit -m "feat(runtime): update WeaponTextureLoader to support new weapon.png + metadata.json format"
```

---

## Task 14: Runtime — CharacterVisuals Effect Loading

**Files:**
- Modify: `scripts/combat/character_visuals.gd` (around line 601, the `_on_effect_event` function)

### Step 1: Add real effect asset loading

Update `_on_effect_event()` (line 601) to check for real effect assets before falling back to placeholders:

```gdscript
const EFFECTS_DIR := "res://assets/sprites/effects"

func _load_real_effect(effect_id: String, direction: String) -> Node2D:
	"""Try to load a real effect spritesheet from assets/sprites/effects/{effect_id}/"""
	var meta_path: String = EFFECTS_DIR + "/" + effect_id + "/metadata.json"
	if not FileAccess.file_exists(meta_path):
		return null

	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()

	var sheet_path: String = EFFECTS_DIR + "/" + effect_id + "/" + effect_id + "_" + direction + ".png"
	var sheet_img := Image.load_from_file(sheet_path)
	if sheet_img == null:
		return null

	var frame_count: int = meta.get("frame_count", 1)
	var frame_size: int = meta.get("frame_size", 32)
	var duration_ms: int = meta.get("duration_ms", 200)
	var fps: float = float(frame_count) / (float(duration_ms) / 1000.0)

	# Build SpriteFrames resource
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("play")
	sprite_frames.set_animation_speed("play", fps)
	sprite_frames.set_animation_loop("play", false)

	for f in frame_count:
		var frame_img := Image.create(frame_size, frame_size, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(sheet_img, Rect2i(f * frame_size, 0, frame_size, frame_size), Vector2i.ZERO)
		var tex := ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame("play", tex)

	# Create AnimatedSprite2D
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sprite_frames
	sprite.animation = "play"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Auto-cleanup after animation finishes
	var duration_sec: float = float(duration_ms) / 1000.0
	sprite.ready.connect(func():
		sprite.play("play")
		var tw := sprite.create_tween()
		tw.tween_callback(sprite.queue_free).set_delay(duration_sec + 0.05)
	)

	var root := Node2D.new()
	root.add_child(sprite)
	return root
```

### Step 2: Update `_on_effect_event` to try real assets first

Modify the existing `_on_effect_event` (line 601):

```gdscript
func _on_effect_event(effect_id: String) -> void:
	# Try real effect asset first
	var effect_node: Node2D = _load_real_effect(effect_id, current_direction)

	# Fall back to placeholder
	if effect_node == null:
		effect_node = PlaceholderEffectSprites.create_effect(effect_id, current_direction)

	if effect_node == null:
		return

	spawn_effect(effect_node)
```

### Step 3: Test

Export an effect, set up a composition in the Attack Composer that references it, run the game. Verify:
- The real effect spritesheet plays at the correct speed
- Direction switching shows the correct directional variant
- Auto-cleanup works (no orphaned nodes)
- Placeholder effects still work for IDs without real assets

### Step 4: Commit

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(runtime): add real effect asset loading with placeholder fallback"
```

---

## Task 15: Final Integration Test & Polish

**Files:**
- All files from previous tasks (read-only verification)

### Step 1: End-to-end weapon test

1. Open `weapon_pipeline.tscn` (F6)
2. Load any high-res weapon image
3. Process to pixel art
4. Place grip and tip anchors
5. Export to `assets/sprites/weapons/test_sword/`
6. Open `attack_composer.tscn` (F6)
7. Verify `test_sword` appears in weapon dropdown
8. Load a composition, select `test_sword` — verify it renders at anchor positions

### Step 2: End-to-end effect test

1. Open `effect_pipeline.tscn` (F6)
2. Load a .glb with effect animation
3. Capture from 3 directions
4. Process to pixel art (soft defaults)
5. Edit frames (delete blank frames if any)
6. Export to `assets/sprites/effects/test_slash/`
7. Open `attack_composer.tscn`
8. Verify `test_slash` appears in effect dropdown
9. Assign to a frame, preview it

### Step 3: Verify placeholder fallbacks

1. Delete or rename the test weapon/effect folders temporarily
2. Open Attack Composer — verify placeholder weapon/effects still load
3. Run the game — verify combat still works with placeholders
4. Restore the folders

### Step 4: Commit any polish fixes

```bash
git add -A
git commit -m "fix: polish weapon/effect pipeline integration"
```

---

## Summary

| Task | Component | Estimated Scope |
|------|-----------|----------------|
| 1 | Weapon Pipeline skeleton | Scene + wizard navigation |
| 2 | Weapon Pipeline Step 1 | Image loading + preview |
| 3 | Weapon Pipeline Step 2 | Pixel art processing |
| 4 | Weapon Pipeline Step 3 | Anchor placement + export |
| 5 | Effect Pipeline skeleton | Scene + wizard navigation |
| 6 | Effect Pipeline Step 1 | Model & animation selection |
| 7 | Effect Pipeline Step 2 | 3-direction capture |
| 8 | Effect Pipeline Step 3 | Pixel art processing |
| 9 | Effect Pipeline Step 4 | Frame editor |
| 10 | Effect Pipeline Step 5 | Export |
| 11 | Attack Composer | Weapon folder scanning |
| 12 | Attack Composer | Effect folder scanning |
| 13 | Runtime | WeaponTextureLoader update |
| 14 | Runtime | CharacterVisuals effect loading |
| 15 | Integration | End-to-end testing |

**Dependency order:** Tasks 1–4 (Weapon Pipeline) and Tasks 5–10 (Effect Pipeline) are independent and can be built in parallel. Tasks 11–12 depend on the output format of Tasks 4 and 10. Tasks 13–14 depend on the output format too but can be built in parallel with 11–12. Task 15 requires all previous tasks.
