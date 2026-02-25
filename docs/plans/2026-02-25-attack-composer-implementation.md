# Attack Composer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone timeline/track editor tool for visually authoring melee attack animations with per-frame timing, weapon visibility, effects, speed echoes, and movement.

**Architecture:** New `AttackCompositionData` resource stores the frame-level timeline (editor source). A converter generates `AbilityVisualData` resources (runtime phases) consumed by the existing `AbilityVisualPlayer`. The tool runs as its own scene (`scenes/tools/attack_composer.tscn`) with the same dark UI theme as the Sprite Pipeline wizard.

**Tech Stack:** Godot 4 / GDScript, custom `_draw()` for timeline rendering, SubViewport for live preview, Resource-based save/load.

**Design doc:** `docs/plans/2026-02-25-attack-composer-design.md`

---

## Task 1: Data Model Resources

Create the two resource classes that form the editor's data model.

**Files:**
- Create: `scripts/tools/attack_composer/composition_frame.gd`
- Create: `scripts/tools/attack_composer/attack_composition_data.gd`

**Step 1: Create CompositionFrame resource**

```gdscript
# scripts/tools/attack_composer/composition_frame.gd
class_name CompositionFrame
extends Resource
## A single frame in an attack composition timeline.
## Stores per-frame timing, weapon state, effect triggers, and echo settings.

## Frame duration in milliseconds (default 66ms ≈ 15fps)
@export var duration_ms: int = 66

## Whether the weapon sprite is visible during this frame
@export var weapon_visible: bool = true

## Effect asset ID to spawn when this frame plays (empty = no effect)
@export var effect_id: String = ""

## Where the effect spawns relative to the character
## "weapon_tip" = blade tip anchor, "center" = character center, "feet" = base
@export var effect_anchor: String = "weapon_tip"

## Pixel offset from the anchor point
@export var effect_offset: Vector2 = Vector2.ZERO

## Whether ghost afterimages are rendered during this frame
@export var echo_enabled: bool = false

## Number of ghost copies to show
@export var echo_count: int = 3

## Opacity range for ghost copies (first ghost → last ghost)
@export var echo_opacity_start: float = 0.5
@export var echo_opacity_end: float = 0.1

## Pixel spacing between ghost copies
@export var echo_spacing_px: float = 8.0
```

**Step 2: Create AttackCompositionData resource**

```gdscript
# scripts/tools/attack_composer/attack_composition_data.gd
class_name AttackCompositionData
extends Resource
## The editor's native format for attack animation compositions.
## Stores a per-frame timeline with timing, weapon, effects, echoes, and movement.
## A converter generates AbilityVisualData from this for runtime playback.

## Unique composition ID (matches the template ID, e.g., "melee_single")
@export var composition_id: String = ""

## Human-readable name for display in the editor
@export var display_name: String = ""

## Base animation name in SpriteFrames (e.g., "attack")
## Direction suffix (_down, _up, _right) added at runtime.
@export var animation_name: String = "attack"

## Whether the character is movement-locked during the entire sequence
@export var locks_movement: bool = true

## Per-frame timeline data — the core of the composition
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


## Helper: total duration of all frames in seconds
func get_total_duration_sec() -> float:
	var total_ms := 0
	for frame in frames:
		total_ms += frame.duration_ms
	return total_ms / 1000.0


## Helper: create a default composition with N frames at the given FPS
static func create_default(frame_count: int, fps: float = 15.0) -> AttackCompositionData:
	var data := AttackCompositionData.new()
	var ms_per_frame := int(1000.0 / fps)
	for i in frame_count:
		var frame := CompositionFrame.new()
		frame.duration_ms = ms_per_frame
		data.frames.append(frame)
	return data
```

**Step 3: Verify resources load in Godot**

Run the project (F5 or F6). Open the Godot script editor and confirm both classes appear in autocompletion with `CompositionFrame.new()` and `AttackCompositionData.new()`. No errors in the output panel.

**Step 4: Commit**

```bash
git add scripts/tools/attack_composer/
git commit -m "feat(attack-composer): add CompositionFrame and AttackCompositionData resources"
```

---

## Task 2: Scene Skeleton & Panel Layout

Create the tool scene with left/right panel structure matching the Sprite Pipeline style.

**Files:**
- Create: `scripts/tools/attack_composer/attack_composer.gd`
- Create: `scenes/tools/attack_composer.tscn`

**Reference:** Read `scripts/tools/sprite_pipeline.gd` lines 60-80 (theme constants) and lines 256-400 (`_build_ui` method) for the panel layout pattern.

**Step 1: Create the main script with UI skeleton**

Build the script with `_build_ui()` that creates:
- Dark background (`C_BG = Color("#1E1E2E")`)
- Root HBoxContainer spanning full rect
- **Left panel** (PanelContainer, 300px min width) with:
  - Title label "Attack Composer"
  - Scrollable VBoxContainer for controls
  - Status bar at the bottom
- **Right panel** (VBoxContainer, fills remaining) with:
  - Top: placeholder for preview viewport (empty PanelContainer with "Preview" label)
  - Bottom: placeholder for timeline (empty PanelContainer with "Timeline" label)

Use the same theme constants as sprite_pipeline.gd:
```gdscript
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")
```

**Step 2: Create the .tscn scene**

Minimal scene: root Control node with the script attached, full-rect anchors.

**Step 3: Verify**

Run `scenes/tools/attack_composer.tscn` with F6. Confirm:
- Dark background fills the window
- Left panel (300px) with "Attack Composer" title visible
- Right panel with placeholder areas for preview and timeline
- Status bar at the bottom shows a default message

**Step 4: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd scenes/tools/attack_composer.tscn
git commit -m "feat(attack-composer): create scene skeleton with left/right panel layout"
```

---

## Task 3: Spritesheet Loading & Frame Extraction

Add controls to load spritesheets from `assets/sprites/final/` and extract individual frames.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Reference:** Read `scripts/tools/sprite_pipeline.gd` — search for `OUTPUT_BASE` and `_scan_models` to see how spritesheets are organized in the output folder. The folder structure is `assets/sprites/final/{model_name}/{anim}_{direction}.png`. Each PNG is a horizontal spritesheet where frame_width = frame_height (square frames).

**Step 1: Add spritesheet scanning**

In the left panel, add:
- **Model dropdown** (OptionButton): Scans `assets/sprites/final/` subfolders
- **Animation dropdown** (OptionButton): Lists animation names found in the selected model folder (by parsing `{anim}_{dir}.png` filenames, extracting unique `{anim}` prefixes)
- **Load button**: Loads the spritesheet for all 3 directions

On load:
1. For each direction (down, up, right), load `{anim}_{dir}.png` as an Image
2. Compute frame count: `sheet_width / sheet_height` (square frames)
3. Extract individual frame images into an array
4. Create a default `AttackCompositionData` with that many frames at 15fps
5. Store in `_current_composition`, `_frame_images` dict (`{dir: Array[Image]}`)

**Step 2: Add frame count display**

Show a label: "Loaded: attack (6 frames, 32x32)" after loading.

**Step 3: Verify**

Run the scene. Select a model and animation. Click Load. Confirm frame count label updates correctly. Check output panel for any errors.

**Step 4: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add spritesheet loading and frame extraction"
```

---

## Task 4: Live Preview Viewport

Add a SubViewport that shows the current frame with body sprite.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Reference:** Read `scripts/tools/sprite_pipeline.gd` — search for `_light_preview_viewport` and `SubViewportContainer` to see the pattern for embedding a 2D viewport preview.

**Step 1: Create the SubViewport preview**

Replace the "Preview" placeholder with:
- SubViewportContainer (fills top portion of right panel, ~60% height)
- SubViewport inside (size matches the frame, e.g., 64x64, scaled up with stretch)
- Sprite2D using AtlasTexture to show individual frames from the loaded sheet
- Direction toggle buttons (Down / Up / Right) below the viewport
- The viewport background should be a checkerboard pattern (transparency indicator)

**Step 2: Wire up direction toggle**

Clicking D/U/R switches which direction's spritesheet is displayed. Store `_preview_direction := "down"`.

**Step 3: Add frame navigation**

Below the direction buttons, add a frame indicator label ("Frame 3 / 6") and two arrow buttons (Prev / Next) so you can manually step through frames to verify the loaded spritesheet.

**Step 4: Verify**

Run the scene. Load a spritesheet. Confirm:
- The preview shows the first frame of the spritesheet
- Switching direction changes the displayed sprite
- Prev/Next buttons cycle through frames
- Frame label updates correctly

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add live preview viewport with frame navigation"
```

---

## Task 5: Timeline — Body Track Rendering

Implement the core timeline with the Body track using custom `_draw()`.

**Files:**
- Create: `scripts/tools/attack_composer/timeline_panel.gd`
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Create the TimelinePanel control**

A custom Control with `_draw()` that renders:
- **Time ruler** at the top (tick marks at 50ms intervals, labels at 100ms intervals)
- **Body track**: horizontal row of frame blocks where each block's width is proportional to `duration_ms`. Each block shows a small thumbnail of the frame sprite and the frame index number.
- **Playhead**: vertical red line at the current playback position
- **Selection highlight**: selected frame has an accent border

Key state:
```gdscript
var composition: AttackCompositionData = null
var frame_thumbnails: Array[ImageTexture] = []  # Tiny previews per frame
var selected_frame: int = -1
var playhead_ms: float = 0.0
var pixels_per_ms: float = 2.0  # Zoom level
var scroll_offset_ms: float = 0.0  # Horizontal scroll
```

Drawing math:
- Each frame block starts at `x = sum(frames[0..i-1].duration_ms) * pixels_per_ms - scroll_offset`
- Each frame block width = `frame.duration_ms * pixels_per_ms`
- Track height = 40px
- Frame thumbnail scaled to fit inside the block

**Step 2: Add click-to-select**

Override `_gui_input()`:
- On click, determine which frame was clicked based on x position
- Set `selected_frame`, emit `signal frame_selected(index: int)`
- `queue_redraw()`

**Step 3: Wire timeline to composer**

In `attack_composer.gd`:
- Replace the "Timeline" placeholder with TimelinePanel instance
- Connect `frame_selected` signal to update the preview viewport to show the selected frame
- Pass composition data and thumbnails after loading a spritesheet

**Step 4: Verify**

Run the scene. Load a spritesheet. Confirm:
- Body track shows frame blocks with correct proportional widths (all equal initially at 66ms)
- Clicking a frame selects it (accent border) and updates the preview
- Time ruler shows tick marks

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/timeline_panel.gd scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add timeline body track with frame selection"
```

---

## Task 6: Frame Duration Editing

Add the ability to edit frame durations via the left panel and timeline drag.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

**Step 1: Add frame properties panel (left side)**

When a frame is selected, show in the left panel:
- **Duration spinbox** (SpinBox, range 8-2000ms, step 8ms) — 8ms = ~120fps minimum
- **Duration label** showing the equivalent FPS for that frame
- Total composition duration label at the bottom

**Step 2: Wire duration changes**

When the spinbox value changes:
1. Update `composition.frames[selected_frame].duration_ms`
2. Emit `composition_changed` signal
3. Timeline panel redraws with new proportional widths
4. Total duration label updates

**Step 3: Add edge-drag resizing on timeline**

In `timeline_panel.gd`:
- When mouse is within 4px of a frame edge, change cursor to `CURSOR_HSIZE`
- On drag, adjust the frame's `duration_ms` (minimum 8ms)
- Snap to 8ms increments while dragging
- Emit `frame_duration_changed(index, new_ms)`

**Step 4: Verify**

Run the scene. Load a spritesheet. Confirm:
- Select a frame → duration spinbox shows 66ms
- Change to 200ms → the frame block in the timeline grows wider
- Drag a frame edge → duration updates in both spinbox and timeline
- Total duration label updates correctly
- This is the core use case: "frame 2 holds for 200ms, frame 3 plays for 16ms"

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd scripts/tools/attack_composer/timeline_panel.gd
git commit -m "feat(attack-composer): add frame duration editing via spinbox and timeline drag"
```

---

## Task 7: Timeline Transport Controls & Playback

Add play/pause/step controls and animated playhead.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

**Step 1: Add transport bar**

Above the timeline tracks, add an HBoxContainer with:
- **Play/Pause** toggle button (triangle / double-bar icons via Unicode: `\u25b6` / `\u23f8`)
- **Stop** button (`\u25a0`) — resets to frame 0
- **Step Back** (`\u25c0\u25c0`) and **Step Forward** (`\u25b6\u25b6`) — single frame steps
- **Time label**: "0:234 / 0:466" (current ms / total ms)
- **Speed slider**: 0.25x to 2.0x playback speed (HSlider, default 1.0)

**Step 2: Implement playback in `_process()`**

```gdscript
var _playing := false
var _playback_ms := 0.0
var _playback_speed := 1.0

func _process(delta: float) -> void:
    if not _playing or _current_composition == null:
        return
    _playback_ms += delta * 1000.0 * _playback_speed
    var total := _current_composition.get_total_duration_sec() * 1000.0
    if _playback_ms >= total:
        _playback_ms = 0.0  # Loop
    _update_playhead()
```

`_update_playhead()`:
1. Determine which frame the playhead is in (sum durations until exceeding `_playback_ms`)
2. Update the preview viewport to show that frame
3. Update the timeline's playhead position
4. Update the time label

**Step 3: Add playhead scrubbing on timeline**

In `timeline_panel.gd`:
- Clicking on the time ruler area (top 20px) sets the playhead position
- Dragging on the ruler scrubs the playhead
- Emits `playhead_moved(ms: float)`

**Step 4: Verify**

Run the scene. Load a spritesheet. Confirm:
- Press Play → animation loops, preview shows each frame for its duration
- Frames with longer durations hold longer in the preview
- Step forward/back moves one frame at a time
- Stop resets to frame 0
- Speed slider changes playback rate
- Clicking the ruler scrubs the playhead

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd scripts/tools/attack_composer/timeline_panel.gd
git commit -m "feat(attack-composer): add transport controls with play/pause/step and playhead scrubbing"
```

---

## Task 8: Weapon, Effect, Movement & Damage Tracks

Add the remaining timeline tracks and their left-panel controls.

**Files:**
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Render additional tracks in TimelinePanel**

Below the Body track, add these tracks (each ~28px tall):
- **Weapon track**: colored regions — green for `weapon_visible=true`, dim for `false`. Click a frame region to toggle.
- **Effect track**: diamond markers on frames that have an `effect_id`. Color-coded by effect type.
- **Echo track**: blue-tinted regions for frames with `echo_enabled=true`. Click to toggle.
- **Movement track**: A single colored bar spanning `movement_start_frame` to `movement_end_frame`. Drag edges to resize.
- **Damage track**: A single red diamond marker on `damage_frame`. Click to move.

Track labels drawn on the left side of the timeline (60px wide label column).

**Step 2: Add effect selection in left panel**

When a frame is selected, add below the duration spinbox:
- **Weapon visible** CheckButton
- **Effect ID** dropdown (OptionButton) — scans `assets/effects/` folder for `.png` files, lists them. Include an empty option for "no effect".
- **Effect anchor** dropdown: "weapon_tip", "center", "feet"
- **Effect offset** (two SpinBoxes for x, y)

**Step 3: Add echo settings in left panel**

Below effect settings (only visible when echo_enabled):
- **Echo enabled** CheckButton
- **Echo count** SpinBox (1-5)
- **Echo opacity start** HSlider (0.0-1.0)
- **Echo opacity end** HSlider (0.0-1.0)
- **Echo spacing** SpinBox (2-24px)

**Step 4: Add sequence-level settings in left panel**

In the "Sequence Properties" section:
- **Movement type** dropdown: "none", "lunge", "dash"
- **Movement distance** SpinBox (0-100px)
- **Movement start/end frame** SpinBoxes (clamped to 0..frame_count-1, or -1 for none)
- **Damage frame** SpinBox (clamped to 0..frame_count-1, or -1 for none)

All changes update the composition data and trigger timeline redraw.

**Step 5: Wire track interactions**

- Clicking weapon track toggles `weapon_visible` on that frame
- Clicking echo track toggles `echo_enabled`
- Clicking effect track with no effect opens the effect dropdown in the left panel
- Clicking damage track moves the damage marker to that frame
- Dragging movement track edges updates `movement_start_frame` / `movement_end_frame`

**Step 6: Verify**

Run the scene. Load a spritesheet. Confirm:
- All 6 tracks render (Body, Weapon, Effect, Echo, Movement, Damage)
- Click weapon track → frame toggles green/dim, left panel checkbox updates
- Set effect on frame 3 → diamond marker appears
- Toggle echo on frames 2-3 → blue region appears
- Set damage frame → red marker appears
- Set movement start=2, end=4 → colored bar spans those frames
- Editing left panel controls updates timeline tracks in real-time

**Step 7: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd scripts/tools/attack_composer/timeline_panel.gd
git commit -m "feat(attack-composer): add weapon/effect/echo/movement/damage tracks with editing"
```

---

## Task 9: Enhanced Preview with Weapon & Effects

Add weapon and effect rendering to the live preview viewport.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Reference:** Read `scripts/combat/character_visuals.gd` — search for `_weapon_sprite` and `_update_weapon_anchor` to understand how weapon anchors work (magenta/cyan pixel scanning).

**Step 1: Add weapon sprite to preview**

In the SubViewport:
- Add a second Sprite2D for the weapon, layered above the body
- When previewing a frame with `weapon_visible=true`:
  - Load the weapon texture from `PlaceholderWeaponSprites.create_sword_set()` (default weapon)
  - Scan the body frame image for magenta (#FF00AA) grip pixel and cyan (#00FFFF) direction pixel (same logic as CharacterVisuals)
  - Position the weapon sprite at the grip anchor, rotated toward the direction anchor
- When `weapon_visible=false`, hide the weapon sprite

**Step 2: Add effect sprite to preview**

- When the playhead is on a frame with an `effect_id`:
  - Load the effect image from `assets/effects/{effect_id}_{direction}.png` (with fallback to `assets/effects/{effect_id}.png` if direction-specific doesn't exist)
  - Display it as a third Sprite2D at the specified anchor + offset
  - Auto-hide after the frame advances

**Step 3: Add echo ghost rendering to preview**

- When the playhead is on a frame with `echo_enabled`:
  - Create N additional Sprite2D nodes showing previous frames
  - Position each at `echo_spacing_px` intervals behind the character
  - Set opacity from `echo_opacity_start` to `echo_opacity_end`
  - Clean up ghost sprites when advancing past echo frames

**Step 4: Verify**

Run the scene. Load a spritesheet with weapon anchors (e.g., an attack animation). Confirm:
- Weapon appears on frames marked `weapon_visible=true`, positioned at the grip anchor
- Setting an effect on a frame shows the effect image during playback
- Toggling echo shows ghost copies of previous frames
- All layers composite correctly in the preview

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add weapon, effect, and echo rendering to preview"
```

---

## Task 10: Converter — Composition to AbilityVisualData

Implement the converter that generates runtime-ready AbilityVisualData from AttackCompositionData.

**Files:**
- Create: `scripts/tools/attack_composer/composition_converter.gd`

**Reference:** Read `scripts/combat/ability_visual_phase.gd` for the factory helpers, and `scripts/combat/ability_visual_templates.gd` lines 130-200 for how melee templates are structured.

**Step 1: Create the converter class**

```gdscript
# scripts/tools/attack_composer/composition_converter.gd
class_name CompositionConverter
## Converts AttackCompositionData (editor format) to AbilityVisualData (runtime format).
## Groups consecutive frames with the same weapon state into BODY_ANIM phases,
## inserts WEAPON_VISIBILITY transitions, EFFECT phases, MOVEMENT phases, and
## DAMAGE_EVENT at the appropriate points.
```

**Step 2: Implement `convert()` static method**

Core algorithm:
1. Iterate through frames, grouping consecutive frames with the same `weapon_visible` state
2. For each group, create a BODY_ANIM phase with:
   - `anim_name` = composition's `animation_name`
   - `duration` = sum of group's frame durations (in seconds)
   - `context_data.frame_timings` = array of individual frame durations in ms
   - `context_data.frame_start_index` = index of first frame in the group
   - `context_data.echo_data` = array of echo configs for frames that have `echo_enabled`
3. Before each group, if weapon state differs from previous, insert WEAPON_VISIBILITY phase
4. For frames with `effect_id`, insert EFFECT phase (concurrent with the BODY_ANIM)
5. If `movement_start_frame` is within a group, insert MOVEMENT phase (concurrent)
6. If `damage_frame` is within a group, insert DAMAGE_EVENT after the BODY_ANIM
7. Append a final recovery BODY_ANIM("idle", 0.0, "recovery") phase

Return the AbilityVisualData with all phases assembled.

**Step 3: Add "Generate" button to the left panel**

In the Save section, add a button "Generate Runtime Data". On click:
1. Run `CompositionConverter.convert(_current_composition)`
2. Print the resulting phase list to the output panel (for verification)
3. Store the result for later saving

**Step 4: Verify**

Run the scene. Set up a test composition:
- 6 frames: first 3 weapon=ON, last 3 weapon=OFF
- Effect "slash_arc" on frame 3
- Movement lunge frames 3-4
- Damage on frame 4

Click "Generate Runtime Data". Check output panel for correct phase sequence:
```
1. WEAPON_VISIBILITY(true)
2. BODY_ANIM("attack", ~0.2s, frame_timings=[66,66,66])
3. WEAPON_VISIBILITY(false)
4. EFFECT("slash_arc") [concurrent]
5. BODY_ANIM("attack", ~0.2s, frame_timings=[66,66,66])
   + MOVEMENT("toward_target", 20px, ...) [concurrent]
6. DAMAGE_EVENT
7. BODY_ANIM("idle", recovery)
```

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/composition_converter.gd scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): implement composition-to-AbilityVisualData converter"
```

---

## Task 11: Save & Load Compositions

Add save/load functionality for compositions and generated runtime data.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Add Save controls**

In the left panel Save section:
- **Composition ID** text field (LineEdit) — defaults to `{model}_{anim}`
- **Save Composition** button → saves to `res://resources/compositions/{id}.tres`
- **Save Runtime Data** button → runs converter, saves to `res://resources/sequences/{id}.tres`
- **Save Both** primary button → saves both files

Create `resources/compositions/` and `resources/sequences/` directories if they don't exist (using DirAccess).

**Step 2: Implement saving**

```gdscript
func _save_composition(path: String) -> void:
    var err := ResourceSaver.save(_current_composition, path)
    if err == OK:
        _set_status("Saved composition to %s" % path)
    else:
        _set_status("Error saving: %s" % error_string(err))

func _save_runtime_data(path: String) -> void:
    var data := CompositionConverter.convert(_current_composition)
    var err := ResourceSaver.save(data, path)
    if err == OK:
        _set_status("Saved runtime data to %s" % path)
    else:
        _set_status("Error saving: %s" % error_string(err))
```

**Step 3: Add Load controls**

- **Composition dropdown** (OptionButton): Scans `res://resources/compositions/` for `.tres` files
- On selection: load the resource, populate the editor (composition data, spritesheet from `animation_name` + model folder)
- **Refresh** button to re-scan

**Step 4: Verify**

Run the scene. Create a composition:
1. Load a spritesheet, adjust some frame durations, set weapon/effect/echo
2. Click "Save Both"
3. Confirm files appear in `resources/compositions/` and `resources/sequences/`
4. Close and reopen the scene
5. Select the saved composition from the dropdown
6. Confirm all settings restored correctly

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/attack_composer.gd
git commit -m "feat(attack-composer): add save/load for compositions and runtime data"
```

---

## Task 12: Runtime Integration — Template Load Override

Modify `AbilityVisualTemplates.get_template()` to check for saved resources first.

**Files:**
- Modify: `scripts/combat/ability_visual_templates.gd` (lines 48-51)

**Step 1: Update get_template() to check for data-driven resource**

```gdscript
## Retrieve a single template by ID.
## Checks for a data-driven resource first (from Attack Composer),
## then falls back to hardcoded template. Returns null if not found.
static func get_template(template_id: String) -> AbilityVisualData:
    # Check for data-driven resource (generated by Attack Composer)
    var resource_path := "res://resources/sequences/%s.tres" % template_id
    if ResourceLoader.exists(resource_path):
        var loaded := load(resource_path)
        if loaded is AbilityVisualData:
            return loaded
    # Fall back to hardcoded template
    var all_templates := get_all()
    return all_templates.get(template_id) as AbilityVisualData
```

**Step 2: Verify**

1. In the Attack Composer, create and save a `melee_single` composition with obviously different timing (e.g., very slow windup)
2. Enter the game, trigger a melee attack
3. Confirm the attack uses the data-driven timing (slow windup) instead of the hardcoded template
4. Delete the saved resource file
5. Trigger melee attack again — should fall back to the hardcoded fast timing

**Step 3: Commit**

```bash
git add scripts/combat/ability_visual_templates.gd
git commit -m "feat(attack-composer): add data-driven template override in get_template()"
```

---

## Task 13: Runtime Integration — Per-Frame Timing Support

Add `frame_timings` support to AbilityVisualPlayer so BODY_ANIM phases can advance frames at custom rates.

**Files:**
- Modify: `scripts/combat/ability_visual_player.gd`

**Reference:** The converter stores `frame_timings` (array of ms ints) and `frame_start_index` in the BODY_ANIM phase's `context_data`. The player needs to read these and manually advance frames.

**Step 1: Add frame timing state**

```gdscript
## Per-frame timing state (for data-driven compositions)
var _frame_timing_active: bool = false
var _frame_timing_array: Array = []  # Array of duration_ms ints
var _frame_timing_index: int = 0
var _frame_timing_timer: float = 0.0
var _frame_timing_start_index: int = 0
```

**Step 2: Modify BODY_ANIM execution to check for frame_timings**

In `_execute_phase_single()` and `_execute_phase_in_slot()`, when handling `PhaseType.BODY_ANIM`:

After emitting `play_body_animation`, check:
```gdscript
if phase.context_data.has("frame_timings"):
    _frame_timing_active = true
    _frame_timing_array = phase.context_data["frame_timings"]
    _frame_timing_index = 0
    _frame_timing_start_index = phase.context_data.get("frame_start_index", 0)
    _frame_timing_timer = _frame_timing_array[0] / 1000.0
    # Pause the sprite's auto-playback
    if _sprite:
        _sprite.speed_scale = 0.0
        _sprite.frame = _frame_timing_start_index
```

**Step 3: Add frame timing tick in `_process()`**

```gdscript
if _frame_timing_active:
    _frame_timing_timer -= delta
    if _frame_timing_timer <= 0.0:
        _frame_timing_index += 1
        if _frame_timing_index >= _frame_timing_array.size():
            # All frames played — stop frame timing, let phase timer resolve
            _frame_timing_active = false
            if _sprite:
                _sprite.speed_scale = 1.0
        else:
            _frame_timing_timer += _frame_timing_array[_frame_timing_index] / 1000.0
            if _sprite:
                _sprite.frame = _frame_timing_start_index + _frame_timing_index
```

**Step 4: Add echo signal emission**

New signal:
```gdscript
signal echo_requested(frame_index: int, echo_config: Dictionary)
```

When advancing to a frame with echo data in `context_data.echo_data`:
```gdscript
var echo_data: Array = phase.context_data.get("echo_data", [])
for echo_config in echo_data:
    if echo_config.get("frame_index", -1) == _frame_timing_start_index + _frame_timing_index:
        echo_requested.emit(_frame_timing_start_index + _frame_timing_index, echo_config)
```

**Step 5: Reset frame timing on cancel/finish**

In `cancel()` and `_finish_sequence()`:
```gdscript
_frame_timing_active = false
if _sprite:
    _sprite.speed_scale = 1.0
```

**Step 6: Verify**

1. Create a composition with varied frame timings (100ms, 100ms, 200ms hold, 16ms fast, 50ms, 100ms)
2. Save as runtime data
3. Trigger the attack in game
4. Confirm the hold frame pauses visibly and the fast frame is barely visible
5. Confirm existing hardcoded templates still work correctly (no regression)

**Step 7: Commit**

```bash
git add scripts/combat/ability_visual_player.gd
git commit -m "feat(attack-composer): add per-frame timing support to AbilityVisualPlayer"
```

---

## Task 14: Runtime Integration — Echo Support in CharacterVisuals

Add speed echo rendering to CharacterVisuals.

**Files:**
- Modify: `scripts/combat/character_visuals.gd`

**Reference:** Read `scripts/combat/character_visuals.gd` — search for `_effect_anchor` and `_body_sprite` to understand the layer structure.

**Step 1: Connect to echo_requested signal**

In the CharacterVisuals initialization (where AbilityVisualPlayer signals are connected):
```gdscript
visual_player.echo_requested.connect(_on_echo_requested)
```

**Step 2: Implement echo rendering**

```gdscript
var _echo_sprites: Array[Sprite2D] = []

func _on_echo_requested(frame_index: int, config: Dictionary) -> void:
    _clear_echoes()
    var count: int = config.get("count", 3)
    var opacity_start: float = config.get("opacity_start", 0.5)
    var opacity_end: float = config.get("opacity_end", 0.1)
    var spacing: float = config.get("spacing_px", 8.0)

    var current_texture = _body_sprite.texture
    if not current_texture:
        return

    for i in count:
        var ghost := Sprite2D.new()
        ghost.texture = current_texture
        # Use same region if AtlasTexture
        if current_texture is AtlasTexture:
            var atlas := AtlasTexture.new()
            atlas.atlas = current_texture.atlas
            atlas.region = current_texture.region
            ghost.texture = atlas
        var t := float(i) / float(count - 1) if count > 1 else 0.0
        ghost.modulate.a = lerp(opacity_start, opacity_end, t)
        ghost.position = _body_sprite.position - Vector2(0, spacing * (i + 1))  # Trail behind
        ghost.z_index = _body_sprite.z_index - 1
        add_child(ghost)
        _echo_sprites.append(ghost)

    # Auto-cleanup after a short delay
    var tween := create_tween()
    tween.tween_interval(0.15)
    tween.tween_callback(_clear_echoes)

func _clear_echoes() -> void:
    for ghost in _echo_sprites:
        if is_instance_valid(ghost):
            ghost.queue_free()
    _echo_sprites.clear()
```

**Step 3: Verify**

1. Create a composition with echo enabled on the fast-swing frames
2. Save and trigger in game
3. Confirm ghost afterimages appear during the echo frames
4. Confirm ghosts fade out and clean up correctly
5. Confirm no memory leaks (ghosts are freed)

**Step 4: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(attack-composer): add speed echo rendering to CharacterVisuals"
```

---

## Task 15: Polish & Integration Testing

Final polish pass and end-to-end verification.

**Files:**
- Modify: `scripts/tools/attack_composer/attack_composer.gd`
- Modify: `scripts/tools/attack_composer/timeline_panel.gd`

**Step 1: Add timeline zoom**

- Mouse wheel on timeline: adjust `pixels_per_ms` (zoom in/out)
- Ctrl+0: reset to default zoom
- Horizontal scrollbar or Shift+mouse wheel for panning

**Step 2: Add keyboard shortcuts**

In `_input()`:
- Space: play/pause toggle
- Left/Right arrow: step frame
- Home: go to frame 0
- End: go to last frame
- Delete: remove selected frame from composition (shift remaining frames)

**Step 3: Add "Delete Frame" functionality**

- Button in left panel + Delete key
- Removes the selected CompositionFrame from the array
- Updates all sequence-level indices (damage_frame, movement_start/end) if they're >= deleted index
- Rebuilds thumbnails and timeline

**Step 4: End-to-end test**

Complete workflow:
1. Open Attack Composer (F6 on `scenes/tools/attack_composer.tscn`)
2. Load a melee attack spritesheet
3. Set frame 0-1 to 100ms (windup start)
4. Set frame 2 to 200ms (windup hold — tension)
5. Set frame 3 to 16ms (fast swing — barely visible)
6. Set frame 4 to 50ms (impact)
7. Set frame 5 to 100ms (recovery)
8. Mark weapon visible on frames 0-2, hidden on 3-5
9. Add "slash_arc" effect on frame 3
10. Enable echo on frames 2-3 (speed trail during swing)
11. Set movement lunge on frames 3-4
12. Set damage on frame 4
13. Preview playback — should look like: slow windup → hold → BAM fast swing with echo+slash → impact → recover
14. Save Both
15. Open game, trigger melee attack, confirm it uses the composed sequence

**Step 5: Commit**

```bash
git add scripts/tools/attack_composer/ scripts/combat/
git commit -m "feat(attack-composer): add polish, keyboard shortcuts, and frame deletion"
```
