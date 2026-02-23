# Sprite Pipeline Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 7 code quality and correctness issues in the pixel sprite pipeline.

**Architecture:** Extract duplicated image processing into a shared static utility (`pixel_art_processing.gd`), fix a hardcoded frame size bug, add single-level undo to the anchor editor, and update docs.

**Tech Stack:** GDScript (Godot 4), no external dependencies.

---

## Task 1: Create `pixel_art_processing.gd` — Shared Image Processing Utility

**Files:**
- Create: `scripts/tools/pixel_art_processing.gd`

**Step 1: Create the utility script with all shared functions**

Create `scripts/tools/pixel_art_processing.gd` as a `class_name PixelArtProcessing` static utility. Extract these from `sprite_pipeline.gd:1721-1922` (identical code also in `pixel_art_converter.gd:402-549, 754-794`):

```gdscript
class_name PixelArtProcessing
## Static utility class for pixel art image processing.
## Shared by sprite_pipeline.gd and pixel_art_converter.gd.

#===============================================================================
# BAYER MATRICES
#===============================================================================

const BAYER_2X2 := [
	[0.0, 2.0],
	[3.0, 1.0],
]

const BAYER_4X4 := [
	[ 0.0,  8.0,  2.0, 10.0],
	[12.0,  4.0, 14.0,  6.0],
	[ 3.0, 11.0,  1.0,  9.0],
	[15.0,  7.0, 13.0,  5.0],
]

const BAYER_8X8 := [
	[ 0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0],
	[48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0],
	[12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0],
	[60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0],
	[ 3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0],
	[51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0],
	[15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0],
	[63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0],
]

#===============================================================================
# IMAGE PROCESSING
#===============================================================================

static func apply_alpha_threshold(image: Image, threshold: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if int(color.a * 255.0) >= threshold:
				color.a = 1.0
			else:
				color.a = 0.0
			image.set_pixel(x, y, color)


static func apply_ordered_dithering(image: Image, strength: float, pattern_index: int) -> void:
	var matrix: Array
	var matrix_size: int
	var matrix_max: float
	match pattern_index:
		0:
			matrix = BAYER_2X2
			matrix_size = 2
			matrix_max = 4.0
		1:
			matrix = BAYER_4X4
			matrix_size = 4
			matrix_max = 16.0
		2:
			matrix = BAYER_8X8
			matrix_size = 8
			matrix_max = 64.0
		_:
			return

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var threshold: float = (matrix[y % matrix_size][x % matrix_size] / matrix_max - 0.5) * strength
			color.r = clampf(color.r + threshold, 0.0, 1.0)
			color.g = clampf(color.g + threshold, 0.0, 1.0)
			color.b = clampf(color.b + threshold, 0.0, 1.0)
			image.set_pixel(x, y, color)


static func apply_palette_mapping(image: Image, palette_colors: PackedColorArray) -> void:
	if palette_colors.is_empty():
		return
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var nearest := find_nearest_palette_color(color, palette_colors)
			nearest.a = 1.0
			image.set_pixel(x, y, nearest)


static func apply_auto_quantize(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			color.r = snappedf(color.r, 1.0 / 31.0)
			color.g = snappedf(color.g, 1.0 / 31.0)
			color.b = snappedf(color.b, 1.0 / 31.0)
			image.set_pixel(x, y, color)


static func apply_outline(image: Image, outline_color: Color) -> void:
	## Fix #4: uses `or` instead of `elif` for clarity.
	var width := image.get_width()
	var height := image.get_height()
	var outline_pixels: Array[Vector2i] = []

	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if color.a >= 0.5:
				continue
			var has_opaque_neighbor := (
				(x > 0 and image.get_pixel(x - 1, y).a >= 0.5)
				or (x < width - 1 and image.get_pixel(x + 1, y).a >= 0.5)
				or (y > 0 and image.get_pixel(x, y - 1).a >= 0.5)
				or (y < height - 1 and image.get_pixel(x, y + 1).a >= 0.5)
			)
			if has_opaque_neighbor:
				outline_pixels.append(Vector2i(x, y))

	for pos in outline_pixels:
		image.set_pixel(pos.x, pos.y, outline_color)


static func apply_denoising(image: Image, min_cluster_size: int) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}

	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if visited.has(pos):
				continue
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				visited[pos] = true
				continue

			var cluster: Array[Vector2i] = []
			var queue: Array[Vector2i] = [pos]
			while not queue.is_empty():
				var current: Vector2i = queue.pop_back()
				if visited.has(current):
					continue
				if current.x < 0 or current.x >= width or current.y < 0 or current.y >= height:
					continue
				if image.get_pixel(current.x, current.y).a < 0.5:
					visited[current] = true
					continue
				visited[current] = true
				cluster.append(current)
				queue.append(Vector2i(current.x + 1, current.y))
				queue.append(Vector2i(current.x - 1, current.y))
				queue.append(Vector2i(current.x, current.y + 1))
				queue.append(Vector2i(current.x, current.y - 1))

			if cluster.size() < min_cluster_size:
				for pixel_pos in cluster:
					image.set_pixel(pixel_pos.x, pixel_pos.y, Color.TRANSPARENT)


static func find_nearest_palette_color(target: Color, palette_colors: PackedColorArray) -> Color:
	var best_color := palette_colors[0]
	var best_dist := color_distance_sq(target, best_color)
	for i in range(1, palette_colors.size()):
		var dist := color_distance_sq(target, palette_colors[i])
		if dist < best_dist:
			best_dist = dist
			best_color = palette_colors[i]
	return best_color


static func color_distance_sq(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db
```

**Step 2: Commit**

```
git add scripts/tools/pixel_art_processing.gd
git commit -m "refactor: extract shared pixel art processing into utility class"
```

---

## Task 2: Rewire `sprite_pipeline.gd` to Use Shared Utility

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Delete Bayer matrices and all duplicated functions**

Delete these line ranges from `sprite_pipeline.gd`:
- Lines 1717-1922: The entire `# IMAGE PROCESSING (Step 3)` section containing `BAYER_2X2`, `BAYER_4X4`, `BAYER_8X8`, `_process_image`, `_apply_alpha_threshold`, `_apply_ordered_dithering`, `_apply_palette_mapping`, `_apply_auto_quantize`, `_find_nearest_palette_color`, `_color_distance_sq`, `_apply_outline`, `_apply_denoising`.

**Step 2: Rewrite `_process_image` to delegate to `PixelArtProcessing`**

Replace the deleted section with a slim `_process_image` that reads UI state and delegates:

```gdscript
#===============================================================================
# IMAGE PROCESSING (Step 3)
#===============================================================================

func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	if not _palette_colors.is_empty():
		PixelArtProcessing.apply_palette_mapping(result, _palette_colors)
	elif dithering_toggle.button_pressed:
		PixelArtProcessing.apply_auto_quantize(result)

	if outline_toggle.button_pressed:
		PixelArtProcessing.apply_outline(result, outline_color_picker.color)

	if denoising_toggle.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result
```

**Step 3: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "refactor: sprite_pipeline delegates to PixelArtProcessing utility"
```

---

## Task 3: Rewire `pixel_art_converter.gd` to Use Shared Utility

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Delete Bayer matrices and all duplicated functions**

Delete these line ranges from `pixel_art_converter.gd`:
- Lines 402-411: `_apply_alpha_threshold`
- Lines 413-470: Bayer matrix constants + `_apply_ordered_dithering`
- Lines 473-504: `_apply_outline`
- Lines 507-548: `_apply_denoising`
- Lines 754-794: `_apply_palette_mapping`, `_apply_auto_quantize`, `_find_nearest_palette_color`, `_color_distance_sq`

**Step 2: Rewrite `_process_image` to delegate to `PixelArtProcessing`**

Replace the body of `_process_image` (lines 368-399) with:

```gdscript
func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	if not _palette_colors.is_empty():
		PixelArtProcessing.apply_palette_mapping(result, _palette_colors)
	elif dithering_toggle.button_pressed:
		PixelArtProcessing.apply_auto_quantize(result)

	if outline_toggle.button_pressed:
		PixelArtProcessing.apply_outline(result, outline_color_picker.color)

	if denoising_toggle.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result
```

**Step 3: Update `_on_generate_palette_pressed` to use shared functions**

In `_on_generate_palette_pressed` (around line 668), replace the direct call:
- `_apply_alpha_threshold(img, ...)` → `PixelArtProcessing.apply_alpha_threshold(img, ...)`

**Step 4: Commit**

```
git add scripts/tools/pixel_art_converter.gd
git commit -m "refactor: pixel_art_converter delegates to PixelArtProcessing utility"
```

---

## Task 4: Fix Hardcoded FRAME_SIZE (Dynamic Frame Size in Steps 5/6)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add `_export_frame_size` state variable**

In the wizard state section (around line 61), add:

```gdscript
## Actual frame size from the most recent export (set in Step 4)
var _export_frame_size := 64
```

**Step 2: Set `_export_frame_size` during export**

In `_start_export()` (line 2094), after `export_log_label.text = ""` (line 2097), add:

```gdscript
	_export_frame_size = int(output_height_spin.value)
```

**Step 3: Replace all `FRAME_SIZE` references in Steps 5/6 with `_export_frame_size`**

Replace every occurrence of `FRAME_SIZE` in these functions with `_export_frame_size`:
- `_on_anchor_dir_selected` (line 828)
- `_enter_anchor_editor` (lines 871, 875)
- `_update_anchor_display` (lines 894, 932, 933, 935, 936)
- `_on_anchor_frame_input` (lines 1005, 1006, 1007, 1008)
- `_place_anchor_pixel` (lines 1023, 1026, 1028, 1030)
- `_clear_color_from_frame` (lines 1036, 1037, 1038)
- `_on_anchor_copy_to_all` (lines 1053, 1054, 1055, 1069, 1071)
- `_apply_to_spriteframes` (lines 2294, 2309)

Keep the `const FRAME_SIZE := 64` declaration — it is still used as the default value for `_export_frame_size`.

**Step 4: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "fix: use dynamic frame size in anchor editor and apply step"
```

---

## Task 5: Add Single-Level Undo to Anchor Editor

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add undo state variable**

In the Step 5 (Anchor Editor) state section (around line 79), add:

```gdscript
var _anchor_undo_state: Dictionary = {}  # {dir_name: Image} — single-level undo snapshot
```

**Step 2: Add undo button in `_build_step_anchors`**

In `_build_step_anchors` (line 714), after the "Copy to All Frames" button block (after line 806), add:

```gdscript
	# Undo
	var undo_btn := Button.new()
	undo_btn.text = "Undo Last Placement"
	undo_btn.pressed.connect(_on_anchor_undo)
	parent.add_child(undo_btn)
```

**Step 3: Save snapshot before each anchor modification**

In `_place_anchor_pixel` (line 1013), at the very start of the function body (before the `if not _anchor_images.has(...)` guard), add:

```gdscript
	# Save undo snapshot before modifying
	if _anchor_images.has(_anchor_current_dir):
		_anchor_undo_state[_anchor_current_dir] = (_anchor_images[_anchor_current_dir] as Image).duplicate()
```

Also in `_on_anchor_copy_to_all` (line 1043), at the start of the function body (after the guard), add the same pattern but for the current direction:

```gdscript
	# Save undo snapshot before copy-to-all
	_anchor_undo_state[_anchor_current_dir] = (sheet as Image).duplicate()
```

**Step 4: Implement `_on_anchor_undo`**

Add after `_on_anchor_save`:

```gdscript
func _on_anchor_undo() -> void:
	if not _anchor_undo_state.has(_anchor_current_dir):
		_append_anchor_log("Nothing to undo for %s." % _anchor_current_dir)
		return
	_anchor_images[_anchor_current_dir] = _anchor_undo_state[_anchor_current_dir]
	_anchor_undo_state.erase(_anchor_current_dir)
	_anchor_frame_count = _anchor_images[_anchor_current_dir].get_width() / _export_frame_size
	_append_anchor_log("Undid last change to %s." % _anchor_current_dir)
	_update_anchor_display()
```

**Step 5: Clear undo state when entering editor**

In `_enter_anchor_editor` (line 848), after `anchor_log_label.text = ""` (line 853), add:

```gdscript
	_anchor_undo_state.clear()
```

**Step 6: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat: add single-level undo to anchor editor"
```

---

## Task 6: Mark `sprite_capture.gd` as Superseded

**Files:**
- Modify: `scripts/tools/sprite_capture.gd`

**Step 1: Add deprecation notice**

Replace the docstring at lines 1-13 with:

```gdscript
extends Control
## [SUPERSEDED] 3D-to-Spritesheet Capture Tool
##
## NOTE: This standalone tool has been superseded by the unified Sprite Pipeline
## Wizard at scenes/tools/sprite_pipeline.tscn, which adds overscan-based camera
## panning, pixel art conversion, weapon anchor editing, and SpriteFrames export.
## Use the wizard instead for new work.
##
## This tool is kept for reference and simple one-off captures.
##
## Workflow:
##   1. Drop .glb/.glb files into assets/3d_imports/
##   2. Run scenes/tools/sprite_capture.tscn
##   3. Select model, animation, configure settings
##   4. Press Export — get {action}_down.png, {action}_up.png, {action}_right.png
##
## Output: Horizontal spritesheets in assets/sprites/captures/{model_name}/
```

**Step 2: Commit**

```
git add scripts/tools/sprite_capture.gd
git commit -m "docs: mark sprite_capture.gd as superseded by pipeline wizard"
```

---

## Task 7: Add Palette `(none)` Entry to Wizard Palette File Dropdown

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Add `(none)` entry in `_scan_palettes`**

In `_scan_palettes` (line 1981), after `palette_file_dropdown.clear()` (line 1982), add:

```gdscript
	palette_file_dropdown.add_item("(none)")
```

**Step 2: Handle the `(none)` selection in `_on_palette_file_selected`**

In `_on_palette_file_selected` (line 1972), add a guard for index 0:

```gdscript
func _on_palette_file_selected(index: int) -> void:
	if index <= 0:
		# "(none)" or invalid — clear palette
		_palette_colors.clear()
		_update_palette_preview()
		_update_pixel_preview()
		return
	var palette_name: String = palette_file_dropdown.get_item_text(index)
	var palette_path := "%s/%s" % [PALETTE_DIR, palette_name]
	var global_path := ProjectSettings.globalize_path(palette_path)
	_load_palette_from_path(global_path)
```

**Step 3: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "fix: add (none) entry to wizard palette file dropdown for UX consistency"
```

---

## Task 8: Update `PLACEHOLDER_SPRITES.md` Documentation

**Files:**
- Modify: `docs/PLACEHOLDER_SPRITES.md`

**Step 1: Add Sprite Pipeline Wizard section**

After the `## Generators` section (after line 33), add a new section:

```markdown
## Sprite Pipeline Wizard

> **Primary tool** — use this for all new sprite work.

The Sprite Pipeline Wizard (`scenes/tools/sprite_pipeline.tscn`) is a 6-step tool that chains 3D capture, pixel art conversion, weapon anchor editing, and SpriteFrames export into a single workflow.

### How to run

1. Run `scenes/tools/sprite_pipeline.tscn` (F6 in Godot)
2. Follow the 6-step wizard

### Steps

| Step | Name | Description |
|------|------|-------------|
| 1 | Model & Animation | Select 3D model from `assets/3d_imports/`, pick animation, configure camera (elevation, zoom, target height). Presets auto-load per model. |
| 2 | Capture Preview | Auto-captures 3 directions (down, up, right) at 512×512 with overscan-based camera panning to prevent limb clipping. |
| 3 | Pixel Art Settings | Configure output height, alpha threshold, dithering, palette, outline, denoising. Real-time preview. |
| 4 | Export | Processes all 3 directions with configured settings. Saves to `assets/sprites/final/{model_name}/`. |
| 5 | Weapon Anchors | (Optional) Place grip pixel (magenta #FF00AA) and direction pixel (cyan #00FFFF) on exported frames. |
| 6 | Apply to SpriteFrames | Load exported sheets into `resources/player_sprites.tres` as AtlasTexture regions with configurable FPS and loop. |

### Presets

Camera and pixel art settings are saved per model to `assets/sprites/presets/{model_name}.json`. They auto-load when selecting a model.

### Standalone Tools

Two standalone tools exist for specialized use:

| Tool | Scene | Use Case |
|------|-------|----------|
| Sprite Capture | `sprite_capture.tscn` | Simple one-off 3D captures (superseded by wizard) |
| Pixel Art Converter | `pixel_art_converter.tscn` | Process pre-captured spritesheets without re-capturing |
```

**Step 2: Update the "Last Updated" date**

Change `*Last Updated: 2026-02-16*` to `*Last Updated: 2026-02-22*`.

**Step 3: Commit**

```
git add docs/PLACEHOLDER_SPRITES.md
git commit -m "docs: add Sprite Pipeline Wizard section to PLACEHOLDER_SPRITES.md"
```
