# Pixel Art Converter Tool — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Godot tool scene that converts high-res captured spritesheets into pixel art using downscaling, alpha thresholding, palette mapping, dithering, outlines, and denoising.

**Architecture:** A single GDScript tool (`pixel_art_converter.gd`) attached to a minimal scene. The UI follows the same left-panel/right-preview pattern as `sprite_capture.tscn`. All image processing is CPU-based using Godot's `Image` class — the output sizes (64px) are small enough for real-time preview.

**Tech Stack:** GDScript, Godot 4 Image API, SubViewportContainer for preview

---

## Reference Files

Before starting any task, read these for context:

- `scripts/tools/sprite_capture.gd` — Reference for UI pattern, file scanning, export flow
- `scenes/tools/sprite_capture.tscn` — Reference for scene structure (minimal: root Control + script)
- `assets/sprites/captures/Walking/` — Example input spritesheets to test with
- `docs/plans/2026-02-21-pixel-art-converter-design.md` — Full design doc

## Important Conventions

- The project uses GDScript (not C#)
- Tool scenes are run directly in the editor (Run Current Scene / F6)
- UI is built entirely in code (`_build_ui()`) — no editor-created nodes
- File paths use `res://` Godot resource paths; use `ProjectSettings.globalize_path()` for disk I/O
- Spritesheets are horizontal strips: width = frame_size * frame_count, height = frame_size

---

### Task 1: Scaffold — Scene file + empty script with UI skeleton

**Files:**
- Create: `scenes/tools/pixel_art_converter.tscn`
- Create: `scripts/tools/pixel_art_converter.gd`

**Step 1: Create the scene file**

Create `scenes/tools/pixel_art_converter.tscn` as a minimal scene (identical structure to `sprite_capture.tscn`):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/tools/pixel_art_converter.gd" id="1"]

[node name="PixelArtConverterRoot" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

**Step 2: Create the script with UI skeleton**

Create `scripts/tools/pixel_art_converter.gd` with:
- `extends Control`
- Constants: `CAPTURES_DIR = "res://assets/sprites/captures"`, `OUTPUT_BASE = "res://assets/sprites/final"`, `PALETTE_DIR = "res://assets/palettes"`
- Node reference vars for all UI elements (dropdowns, sliders, toggles, buttons, labels, preview TextureRect)
- `_ready()` → calls `_build_ui()` then `_scan_source_folders()`
- `_build_ui()` → builds the full left-panel/right-preview layout:
  - Left panel (PanelContainer > ScrollContainer > VBoxContainer) with:
    - Title label "Pixel Art Converter"
    - Source folder dropdown (OptionButton)
    - Spritesheet file dropdown (OptionButton)
    - Separator
    - "Load Palette (.png)" button + palette preview (HBoxContainer of ColorRects)
    - Output height spinner (SpinBox, min 16, max 256, default 64, step 8)
    - Alpha threshold slider (HSlider, 0-255, default 128) + value label
    - Separator
    - "Dithering" CheckButton + strength slider (0.0-1.0, default 0.5) + pattern OptionButton (2x2, 4x4, 8x8)
    - "Outline" CheckButton + color picker (ColorPickerButton, default black)
    - "Denoising" CheckButton + min cluster size SpinBox (default 2)
    - Separator
    - "Export Selected" button
    - "Export All in Folder" button
    - Separator
    - Status label (autowrap)
  - Right side: ScrollContainer > TextureRect for preview (with `texture_filter = NEAREST` for crisp pixel zoom)
- `_scan_source_folders()` → lists subdirectories in `CAPTURES_DIR`, populates folder dropdown
- `_on_folder_selected(index)` → lists `.png` files in selected folder, populates file dropdown
- `_on_file_selected(index)` → loads the PNG into `_source_image` (Image), calls `_update_preview()`
- `_update_preview()` → stub that just shows the source image for now
- `_set_status(text)` → updates status label + prints

**Step 3: Verify the scaffold runs**

Open the scene in the Godot editor and run with F6. Verify:
- UI renders with all controls visible
- Folder dropdown populates with "Walking" (the existing capture folder)
- Selecting Walking populates file dropdown with the 3 PNG files
- Selecting a PNG shows the raw spritesheet in the preview area
- All sliders/toggles are interactive (no processing yet)

**Step 4: Commit**

```bash
git add scenes/tools/pixel_art_converter.tscn scripts/tools/pixel_art_converter.gd
git commit -m "feat: scaffold pixel art converter tool with UI"
```

---

### Task 2: Core processing — Downscale + Alpha threshold

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Implement `_process_image()` pipeline**

Add the main processing function that will be called by `_update_preview()`:

```gdscript
func _process_image(source: Image) -> Image:
    var result := source.duplicate() as Image

    # Step 1: Downscale
    var target_height := int(output_height_spin.value)
    var scale_factor := float(target_height) / float(result.get_height())
    var target_width := int(float(result.get_width()) * scale_factor)
    result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

    # Step 2: Alpha threshold
    var threshold := int(alpha_threshold_slider.value)
    _apply_alpha_threshold(result, threshold)

    return result
```

**Step 2: Implement `_apply_alpha_threshold()`**

```gdscript
func _apply_alpha_threshold(image: Image, threshold: int) -> void:
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var color := image.get_pixel(x, y)
            if int(color.a * 255.0) >= threshold:
                color.a = 1.0
            else:
                color.a = 0.0
            image.set_pixel(x, y, color)
```

**Step 3: Wire `_update_preview()` to use the pipeline**

```gdscript
func _update_preview() -> void:
    if _source_image == null:
        return
    var processed := _process_image(_source_image)
    var tex := ImageTexture.create_from_image(processed)
    preview_texture_rect.texture = tex
```

Connect all relevant slider/toggle `value_changed` signals to `_update_preview()` so the preview updates live.

**Step 4: Verify**

Run the scene (F6):
- Load a capture spritesheet
- Verify it downscales to 64px height in the preview
- Drag the alpha threshold slider — see edges get sharper/softer
- At threshold ~128, the silhouette should have clean hard edges with no semi-transparent fringe

**Step 5: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add downscale and alpha threshold processing"
```

---

### Task 3: Palette loading + color mapping

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`
- Create: `assets/palettes/` directory (empty, for user to drop palette PNGs)

**Step 1: Implement palette loading**

```gdscript
var _palette_colors: PackedColorArray = PackedColorArray()

func _on_load_palette_pressed() -> void:
    # Open a FileDialog to pick a .png palette strip
    var dialog := FileDialog.new()
    dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.filters = PackedStringArray(["*.png ; PNG Palette"])
    dialog.file_selected.connect(_on_palette_file_selected)
    add_child(dialog)
    dialog.popup_centered(Vector2i(600, 400))

func _on_palette_file_selected(path: String) -> void:
    var image := Image.new()
    var err := image.load(path)
    if err != OK:
        _set_status("ERROR: Could not load palette from %s" % path)
        return

    _palette_colors.clear()
    # Read every unique pixel from the image as a palette color
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var color := image.get_pixel(x, y)
            if color.a > 0.5 and not _palette_colors.has(color):
                _palette_colors.append(color)

    _set_status("Loaded palette: %d colors" % _palette_colors.size())
    _update_palette_preview()
    _update_preview()
```

**Step 2: Implement palette preview**

Show loaded palette colors as a row of small ColorRects in the UI:

```gdscript
func _update_palette_preview() -> void:
    # Clear existing swatches
    for child in palette_preview_container.get_children():
        child.queue_free()
    # Add new swatches
    for color in _palette_colors:
        var swatch := ColorRect.new()
        swatch.custom_minimum_size = Vector2(12, 12)
        swatch.color = color
        palette_preview_container.add_child(swatch)
```

`palette_preview_container` is an HFlowContainer added in the UI build (below the palette button).

**Step 3: Implement `_apply_palette_mapping()`**

Add to the `_process_image()` pipeline after alpha threshold:

```gdscript
func _apply_palette_mapping(image: Image) -> void:
    if _palette_colors.is_empty():
        return
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var color := image.get_pixel(x, y)
            if color.a < 0.5:
                continue  # Skip transparent pixels
            var nearest := _find_nearest_palette_color(color)
            nearest.a = 1.0
            image.set_pixel(x, y, nearest)

func _find_nearest_palette_color(target: Color) -> Color:
    var best_color := _palette_colors[0]
    var best_dist := _color_distance_sq(target, best_color)
    for i in range(1, _palette_colors.size()):
        var dist := _color_distance_sq(target, _palette_colors[i])
        if dist < best_dist:
            best_dist = dist
            best_color = _palette_colors[i]
    return best_color

func _color_distance_sq(a: Color, b: Color) -> float:
    var dr := a.r - b.r
    var dg := a.g - b.g
    var db := a.b - b.b
    return dr * dr + dg * dg + db * db
```

**Step 4: Verify**

- Download a palette PNG from Lospec (e.g., https://lospec.com/palette-list — pick any, export as 1x PNG)
- Place it anywhere accessible
- Run the scene, load a capture spritesheet, click "Load Palette", pick the palette PNG
- Preview should show the spritesheet mapped to the palette colors
- Palette swatches should appear in the UI

**Step 5: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add palette loading and color mapping"
```

---

### Task 4: Ordered dithering

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Implement Bayer matrix dithering**

Add dithering to the `_process_image()` pipeline. Dithering runs **before** palette mapping — it shifts pixel color values using a threshold matrix so that when they snap to the nearest palette color, the result creates a pattern that simulates in-between colors.

```gdscript
# Bayer matrices for ordered dithering
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

func _apply_ordered_dithering(image: Image, strength: float, pattern_index: int) -> void:
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
            var threshold := (matrix[y % matrix_size][x % matrix_size] / matrix_max - 0.5) * strength
            color.r = clampf(color.r + threshold, 0.0, 1.0)
            color.g = clampf(color.g + threshold, 0.0, 1.0)
            color.b = clampf(color.b + threshold, 0.0, 1.0)
            image.set_pixel(x, y, color)
```

Wire it into `_process_image()` after alpha threshold, before palette mapping:

```gdscript
# Step 3: Dithering (before palette mapping)
if dithering_toggle.button_pressed and not _palette_colors.is_empty():
    _apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

# Step 4: Palette mapping
_apply_palette_mapping(result)
```

**Step 2: Verify**

- Run the scene, load a spritesheet, load a palette
- Toggle dithering on — preview should show dithering pattern
- Adjust strength slider — dithering intensity should change
- Switch between 2x2/4x4/8x8 patterns — pattern granularity should change
- With dithering off, palette mapping should still look clean

**Step 3: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add ordered dithering with Bayer matrices"
```

---

### Task 5: Outline effect

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Implement outline detection**

Outline runs **after** palette mapping. It scans for pixels where a transparent pixel has an opaque 4-connected neighbor, and colors those transparent pixels with the outline color.

```gdscript
func _apply_outline(image: Image, outline_color: Color) -> void:
    var width := image.get_width()
    var height := image.get_height()

    # Build a map of which pixels need outlines
    # (we can't modify the image while scanning it)
    var outline_pixels: Array[Vector2i] = []

    for y in range(height):
        for x in range(width):
            var color := image.get_pixel(x, y)
            if color.a >= 0.5:
                continue  # Already opaque, skip
            # Check 4-connected neighbors for opaque pixels
            var has_opaque_neighbor := false
            if x > 0 and image.get_pixel(x - 1, y).a >= 0.5:
                has_opaque_neighbor = true
            elif x < width - 1 and image.get_pixel(x + 1, y).a >= 0.5:
                has_opaque_neighbor = true
            elif y > 0 and image.get_pixel(x, y - 1).a >= 0.5:
                has_opaque_neighbor = true
            elif y < height - 1 and image.get_pixel(x, y + 1).a >= 0.5:
                has_opaque_neighbor = true
            if has_opaque_neighbor:
                outline_pixels.append(Vector2i(x, y))

    # Apply outlines
    for pos in outline_pixels:
        image.set_pixel(pos.x, pos.y, outline_color)
```

Wire into `_process_image()` after palette mapping:

```gdscript
# Step 5: Outline
if outline_toggle.button_pressed:
    _apply_outline(result, outline_color_picker.color)
```

**Step 2: Verify**

- Run scene, load spritesheet, load palette
- Toggle outline on — character silhouette gets a dark border
- Change outline color with the color picker — outline changes
- Toggle outline off — outlines disappear cleanly

**Step 3: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add outline detection at silhouette edges"
```

---

### Task 6: Denoising

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Implement connected component denoising**

After all other effects, scan for isolated pixel clusters (flood fill) and remove clusters smaller than the threshold.

```gdscript
func _apply_denoising(image: Image, min_cluster_size: int) -> void:
    var width := image.get_width()
    var height := image.get_height()
    var visited := {}  # Dictionary<Vector2i, bool> for fast lookup

    for y in range(height):
        for x in range(width):
            var pos := Vector2i(x, y)
            if visited.has(pos):
                continue
            var color := image.get_pixel(x, y)
            if color.a < 0.5:
                visited[pos] = true
                continue

            # Flood fill to find cluster
            var cluster: Array[Vector2i] = []
            var queue: Array[Vector2i] = [pos]
            while not queue.is_empty():
                var current := queue.pop_back()
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

            # Remove small clusters
            if cluster.size() < min_cluster_size:
                for pixel_pos in cluster:
                    image.set_pixel(pixel_pos.x, pixel_pos.y, Color.TRANSPARENT)
```

Wire into `_process_image()` as the last step:

```gdscript
# Step 6: Denoising
if denoising_toggle.button_pressed:
    _apply_denoising(result, int(denoising_min_cluster_spin.value))
```

**Step 2: Verify**

- Run scene, load spritesheet at low alpha threshold (to create stray pixels)
- Toggle denoising on — stray isolated pixels should disappear
- Increase min cluster size — larger groups get removed
- Main character body should remain intact

**Step 3: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add connected component denoising"
```

---

### Task 7: Export functionality

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Implement single file export**

```gdscript
func _on_export_pressed() -> void:
    if _source_image == null:
        _set_status("ERROR: No spritesheet loaded.")
        return

    export_button.disabled = true
    export_all_button.disabled = true

    var file_name: String = file_dropdown.get_item_text(file_dropdown.selected)
    _export_file(file_name)

    export_button.disabled = false
    export_all_button.disabled = false

func _export_file(file_name: String) -> void:
    var folder_name: String = folder_dropdown.get_item_text(folder_dropdown.selected)
    var source_path := "%s/%s/%s" % [CAPTURES_DIR, folder_name, file_name]

    var source := Image.new()
    source.load(ProjectSettings.globalize_path(source_path))

    var processed := _process_image(source)

    var output_dir := "%s/%s" % [OUTPUT_BASE, folder_name]
    var global_output_dir := ProjectSettings.globalize_path(output_dir)
    DirAccess.make_dir_recursive_absolute(global_output_dir)

    var output_path := "%s/%s" % [output_dir, file_name]
    var global_path := ProjectSettings.globalize_path(output_path)
    var err := processed.save_png(global_path)
    if err != OK:
        _set_status("ERROR: Failed to save %s (error %d)" % [output_path, err])
        return

    _set_status("Exported: %s -> %s" % [file_name, output_path])
    print("[PixelArtConverter] Saved: %s" % output_path)
```

**Step 2: Implement batch export**

```gdscript
func _on_export_all_pressed() -> void:
    if folder_dropdown.item_count == 0:
        _set_status("ERROR: No source folder selected.")
        return

    export_button.disabled = true
    export_all_button.disabled = true

    var count := 0
    for i in range(file_dropdown.item_count):
        var file_name: String = file_dropdown.get_item_text(i)
        _export_file(file_name)
        count += 1

    _set_status("Exported %d files!" % count)
    export_button.disabled = false
    export_all_button.disabled = false
```

**Step 3: Verify**

- Run scene, load a spritesheet, configure all settings
- Click "Export Selected" — check `assets/sprites/final/Walking/` for the exported PNG
- Open the exported PNG — verify it's 64px tall with clean pixel art
- Click "Export All in Folder" — all 3 direction PNGs should export
- Verify file names match the originals

**Step 4: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add export for single and batch spritesheet processing"
```

---

### Task 8: Polish — Before/after toggle + palette directory scanning

**Files:**
- Modify: `scripts/tools/pixel_art_converter.gd`

**Step 1: Add before/after toggle**

Add a CheckButton "Show Original" at the top of the preview area. When toggled on, shows the raw source image (scaled to fit). When off, shows the processed result.

```gdscript
func _on_show_original_toggled(enabled: bool) -> void:
    if _source_image == null:
        return
    if enabled:
        var tex := ImageTexture.create_from_image(_source_image)
        preview_texture_rect.texture = tex
    else:
        _update_preview()
```

**Step 2: Add palette folder scanning**

Instead of only the FileDialog, also scan `assets/palettes/` for .png files and show them in a dropdown for quick selection:

```gdscript
func _scan_palettes() -> void:
    palette_dropdown.clear()
    palette_dropdown.add_item("(none)")

    var global_dir := ProjectSettings.globalize_path(PALETTE_DIR)
    var dir := DirAccess.open(global_dir)
    if dir == null:
        DirAccess.make_dir_recursive_absolute(global_dir)
        return

    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        if file_name.to_lower().ends_with(".png"):
            palette_dropdown.add_item(file_name)
        file_name = dir.get_next()
    dir.list_dir_end()
```

Add a dropdown above the "Load Palette" button. Selecting from the dropdown auto-loads that palette. The button remains for loading palettes from elsewhere on disk.

**Step 3: Verify**

- Drop a palette PNG into `assets/palettes/`
- Run the scene — palette dropdown should list it
- Select it — palette loads and preview updates
- Toggle "Show Original" — switches between processed and raw
- "Load Palette" button still works for files outside the palettes folder

**Step 4: Commit**

```bash
git add scripts/tools/pixel_art_converter.gd
git commit -m "feat: add before/after toggle and palette folder scanning"
```

---

## Summary

| Task | What it adds | Key test |
|------|-------------|----------|
| 1 | Scene + UI skeleton + file browsing | UI renders, folder/file selection works |
| 2 | Downscale + alpha threshold | 64px output with clean hard edges |
| 3 | Palette loading + color mapping | Colors snap to loaded palette |
| 4 | Ordered dithering | Dithering pattern visible, configurable |
| 5 | Outline effect | Dark border around silhouette |
| 6 | Denoising | Stray pixels removed |
| 7 | Export | PNGs saved to final/ directory |
| 8 | Polish (before/after, palette scanning) | Quick palette swap, visual comparison |

After all 8 tasks, the full pipeline is: `sprite_capture.tscn` (3D → 512px PNG) → `pixel_art_converter.tscn` (512px → 64px pixel art PNG) → game-ready assets.
