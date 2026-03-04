# Shadow System Removal — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the entire shadow system (character blob shadows, decoration shadows, zone mood realtime shadows, PointLight2D shadow casting) to create a clean slate for a new shadow implementation.

**Architecture:** Surgical removal across 8 GDScript files, 4 zone mood resources, 1 SpriteFrames resource, 3 VBA files, LDtk map data, ~94 asset files, and documentation. Leave TODO stub comments at key integration points.

**Tech Stack:** GDScript, VBA, LDtk JSON, Godot resources (.tres)

---

### Task 1: Remove shadow code from character_visuals.gd

**Files:**
- Modify: `scripts/combat/character_visuals.gd`

**Step 1: Remove shadow variable declarations (lines 40-43)**

Remove these 4 lines:
```gdscript
var shadow_sprite: AnimatedSprite2D = null
var _shadow_has_animations: bool = false
var _shadow_animation_valid: bool = true
var _shadow_last_body_anim: StringName = &""
```

**Step 2: Remove shadow constants block (lines ~105-127)**

Remove the entire shadow constants block:
```gdscript
## Fallback ellipse shadow dimensions (fraction of frame size)
const SHADOW_ELLIPSE_WIDTH_RATIO := 0.8
const SHADOW_ELLIPSE_HEIGHT_RATIO := 0.3

## Shadow Y offset — positions shadow at character's feet
const SHADOW_Y_OFFSET := 14.0

## Light detection
const SHADOW_LIGHT_SEARCH_RADIUS := 512.0
const SHADOW_TRANSITION_SPEED := 3.3

const SHADOW_CLOSE_DISTANCE := 64.0
const SHADOW_FAR_DISTANCE := 512.0
const SHADOW_CLOSE_OPACITY := 0.1
const SHADOW_FAR_OPACITY := 0.6
const SHADOW_NO_LIGHT_OPACITY := 0.5
const SHADOW_CLOSE_SCALE := 0.7
const SHADOW_FAR_SCALE := 1.0
const SHADOW_NO_LIGHT_SCALE := 1.0
```

**Step 3: Remove shadow target variables (lines ~130-131)**

Remove:
```gdscript
## Current shadow targets (for lerping)
var _shadow_target_opacity := SHADOW_NO_LIGHT_OPACITY
var _shadow_target_scale := SHADOW_NO_LIGHT_SCALE
```

**Step 4: Remove shadow function calls from initialize() (lines ~144, ~151)**

Remove the `_create_shadow_layer()` call and the `_setup_shadow()` call from initialize(). Add a stub comment:
```gdscript
# TODO: Shadow system — hook new shadow implementation here
```

**Step 5: Remove shadow sync/update code from _process() (lines ~332-361)**

Remove:
- Auto-sync shadow animation block (lines ~332-342)
- Shadow frame sync (lines ~344-346)
- Shadow flip sync (lines ~348-349)
- `_update_shadow_light_response(delta)` call (line ~361)

**Step 6: Remove shadow sync from set_direction() (lines ~1108-1116)**

Remove the shadow animation re-sync block at the end of `set_direction()`.

**Step 7: Remove shadow sync call from _on_play_body_animation() (line ~883)**

Remove the `_sync_shadow_animation(anim_name)` call.

**Step 8: Remove all 6 shadow functions (lines ~182-321)**

Remove these entire functions:
- `_create_shadow_layer()` (lines ~182-191)
- `_setup_shadow()` (lines ~193-210)
- `_generate_ellipse_shadow()` (lines ~212-250)
- `_sync_shadow_animation()` (lines ~252-279)
- `_update_shadow_light_response()` (lines ~281-312)
- `_apply_shadow_lerp()` (lines ~314-321)

**Step 9: Commit**

```
git add scripts/combat/character_visuals.gd
git commit -m "refactor: remove shadow system from CharacterVisuals"
```

---

### Task 2: Remove shadow code from sprite_pipeline.gd

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd`

**Step 1: Remove shadow state variables (lines ~103, ~165)**

Remove:
```gdscript
var _captured_shadow_sheets: Dictionary = {}
```
```gdscript
var _shadow_capture_material: StandardMaterial3D = null
```

**Step 2: Remove shadow material creation (lines ~247-249)**

Remove the shadow capture material setup code (StandardMaterial3D creation with flat black, unshaded).

**Step 3: Remove shadow preview mode button (line ~596)**

Remove the shadow radio button from the capture preview mode group.

**Step 4: Remove shadow nudge label reference (line ~883)**

Update the nudge label text to remove mention of "shadow" (change "color, normal & shadow" to "color & normal").

**Step 5: Remove shadow sheet initialization in capture loop (lines ~2171-2172)**

Remove the lines that create the transparent shadow sheet for the current direction.

**Step 6: Remove shadow capture pass (lines ~2231-2253)**

Remove the entire shadow capture block:
- Check for `_shadow_capture_material`
- Create shadow camera
- Apply shadow materials
- Capture shadow frame
- Restore materials
- Free shadow camera

Add stub comment:
```gdscript
# TODO: Shadow pipeline — hook new shadow capture here
```

**Step 7: Remove shadow sheet storage (line ~2257)**

Remove the line that stores the captured shadow sheet in the dictionary.

**Step 8: Remove shadow sheet save during capture (lines ~2278-2281)**

Remove shadow sheet PNG save code.

**Step 9: Remove shadow map export (lines ~2640-2664)**

Remove the entire shadow map export loop (downscale, alpha threshold, save PNG). Remove shadow count from export summary log (lines ~2666-2667).

Add stub comment:
```gdscript
# TODO: Shadow pipeline — hook new shadow export here
```

**Step 10: Remove shadow map loading in Step 7 (lines ~1832-1837, ~2898-2904)**

Remove shadow PNG detection/loading code.

**Step 11: Remove shadow animation creation (lines ~2939-2959)**

Remove the code that creates `*_shadow` animation variants in SpriteFrames.

**Step 12: Remove shadow state clearing (lines ~2115, ~2119, ~1797, ~2683, ~2691)**

Remove all `_captured_shadow_sheets.clear()` and related clearing lines.

**Step 13: Remove shadow functions (lines ~1929-1938, ~1954-1961)**

Remove:
- `_apply_shadow_capture_materials()` function
- `_create_shadow_camera()` function

**Step 14: Remove shadow file filter in auto-scan (line ~2778)**

Remove the `_shadow.png` filter from model detection (no longer needed since shadow files won't exist).

**Step 15: Commit**

```
git add scripts/tools/sprite_pipeline.gd
git commit -m "refactor: remove shadow capture/export from sprite pipeline"
```

---

### Task 3: Remove shadow code from decoration system

**Files:**
- Modify: `scripts/environment/decoration_spawner.gd`
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Update decoration_spawner.gd**

Remove from class docstring: mention of "baked shadows"

Remove from asset cache comment (line ~8): the "shadow" key

Remove shadow mode handling (lines ~54-73): the entire `shadow_mode` match block (both "realtime" LightOccluder2D and "baked" Sprite2D branches)

Remove `"shadow": null` from assets dict init (line ~105)

Remove shadow loading code (lines ~124-126): `shadow.png` load path

Remove shadow debug logging (lines ~129-135)

Add stub:
```gdscript
# TODO: Shadow system — hook new decoration shadow here
```

**Step 2: Update decoration_pipeline.gd**

Remove shadow state dictionaries: `_captured_shadow` (line ~85), `_processed_shadow` (line ~93)

Remove shadow material variable and creation (lines ~170, ~185-188)

Remove shadow UI variables (lines ~148-152): offset slider, opacity slider, preview rect, show shadow check

Remove shadow UI section creation (lines ~1231-1256): header, offset slider, opacity slider, preview rect

Remove "Shadow" from generate button text (line ~1282)

Remove shadow visibility checkbox (lines ~1338-1343)

Remove shadow from export description (line ~1376)

Remove shadow capture pass (lines ~802-820): top-down camera, shadow material application, render, capture

Remove shadow processing (lines ~1821-1827): both 3D and 2D shadow branches

Remove shadow export (lines ~1470-1473): save shadow.png

Remove `has_shadow` from atlas metadata (lines ~1535, ~1591)

Remove shadow clearing/updating (lines ~1773, ~1838)

Remove shadow status message (line ~1849)

Remove `_generate_shadow_from_alpha()` function (lines ~1918-1940)

Remove `_apply_shadow_styling()` function (lines ~1943-1972)

Remove shadow layer from composite preview (lines ~2185-2209)

**Step 3: Commit**

```
git add scripts/environment/decoration_spawner.gd scripts/tools/decoration_pipeline.gd
git commit -m "refactor: remove shadow system from decoration spawner and pipeline"
```

---

### Task 4: Remove shadow from zone mood and chunk manager

**Files:**
- Modify: `scripts/environment/zone_mood.gd`
- Modify: `autoloads/chunk_manager.gd`
- Modify: `resources/zone_moods/town_safe.tres`
- Modify: `resources/zone_moods/lava_cave.tres`
- Modify: `resources/zone_moods/deep_cave.tres`
- Modify: `resources/zone_moods/snowy_mountain.tres`

**Step 1: Remove from zone_mood.gd (line 19)**

Remove:
```gdscript
@export_group("Shadows")
@export var realtime_shadows: bool = false
```

**Step 2: Remove from chunk_manager.gd (lines ~1769-1776)**

Remove the entire block:
```gdscript
# Shadow — enabled based on zone mood setting
var env_mgr = get_node_or_null("/root/EnvironmentManager")
if env_mgr and env_mgr.current_mood:
    light.shadow_enabled = env_mgr.current_mood.realtime_shadows
else:
    light.shadow_enabled = false
light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
light.shadow_filter_smooth = 1.5
```

Add stub:
```gdscript
# TODO: Shadow system — hook new light shadow config here
```

**Step 3: Remove `realtime_shadows` line from all 4 .tres files**

Each file has `realtime_shadows = true` or `realtime_shadows = false` on line 13. Remove this line.

**Step 4: Commit**

```
git add scripts/environment/zone_mood.gd autoloads/chunk_manager.gd resources/zone_moods/
git commit -m "refactor: remove realtime shadow configuration from zone moods"
```

---

### Task 5: Remove shadow from LDtk importer and map data

**Files:**
- Modify: `ldtk_importer.gd`
- Modify: `maps/entities/zone_ldtk_test.json`

Note: `MobileTestia.ldtk` field definition removal should be done in LDtk editor by the user. We remove it from the importer so it's ignored even if present.

**Step 1: Remove shadow_mode parsing from ldtk_importer.gd (lines ~674, ~892)**

Remove the `"shadow_mode"` key from both decoration data dictionaries.

**Step 2: Remove shadow_mode from zone_ldtk_test.json**

Remove all `"shadow_mode": "baked"` lines (6 occurrences on lines 12, 23, 34, 45, 56, 67).

**Step 3: Commit**

```
git add ldtk_importer.gd maps/entities/zone_ldtk_test.json
git commit -m "refactor: remove shadow_mode from LDtk importer and entity data"
```

---

### Task 6: Remove shadow from other scripts

**Files:**
- Modify: `scripts/tools/apply_final_walk_sprites.gd`
- Modify: `scripts/tools/attack_composer/attack_composer.gd`

**Step 1: Remove shadow animation code from apply_final_walk_sprites.gd**

Remove shadow comments (lines ~14, ~24)

Remove shadow map detection and loading (lines ~130-136): shadow filename generation, path construction, image loading

Remove shadow animation creation (lines ~167-187): shadow animation name, add animation, create frames, print info

Remove shadow mention from final output comment (line ~195)

**Step 2: Remove shadow file filter from attack_composer.gd (line ~1509)**

Remove `and not file_name.ends_with("_shadow.png")` from the file filter condition.

**Step 3: Commit**

```
git add scripts/tools/apply_final_walk_sprites.gd scripts/tools/attack_composer/attack_composer.gd
git commit -m "refactor: remove shadow handling from walk sprite and attack composer tools"
```

---

### Task 7: Remove shadow animations from player_sprites.tres

**Files:**
- Modify: `resources/player_sprites.tres`

**Step 1: Remove all *_shadow animation entries**

Remove all animation entries ending in `_shadow` from the SpriteFrames resource. There are ~24 shadow animations:
- `attack_down_shadow`, `attack_right_shadow`, `attack_up_shadow`
- `hiltbash_down_shadow`, `hiltbash_right_shadow`, `hiltbash_up_shadow`
- `idle_down_shadow`, `idle_right_shadow`, `idle_up_shadow`
- `kicking_down_shadow`, `kicking_right_shadow`, `kicking_up_shadow`
- `run_down_shadow`, `run_right_shadow`, `run_up_shadow`
- `walk_down_shadow`, `walk_right_shadow`, `walk_up_shadow`
- `blocking_down_shadow`, `blocking_right_shadow`, `blocking_up_shadow`
- Plus any additional shadow animation variants

**Step 2: Commit**

```
git add resources/player_sprites.tres
git commit -m "refactor: remove shadow animations from player SpriteFrames"
```

---

### Task 8: Delete shadow asset files

**Files:**
- Delete: 45 character shadow PNGs + 45 .import files
- Delete: 3 decoration shadow PNGs + 3 .import files
- Modify: `assets/decorations/_atlas/decoration_atlas.json`

**Step 1: Delete character shadow PNGs and imports**

Delete all `*_shadow.png` and `*_shadow.png.import` files from:
- `assets/sprites/captures/Blocking/`
- `assets/sprites/captures/HiltBash/`
- `assets/sprites/captures/Idle/`
- `assets/sprites/captures/Kicking/`
- `assets/sprites/captures/Running/`
- `assets/sprites/captures/Slash/`
- `assets/sprites/captures/Walking/`
- `assets/sprites/captures/Standing Block Idle/`
- `assets/sprites/final/Blocking/`
- `assets/sprites/final/HiltBash/`
- `assets/sprites/final/Idle/`
- `assets/sprites/final/Kicking/`
- `assets/sprites/final/Running/`
- `assets/sprites/final/Slash/`
- `assets/sprites/final/Walking/`

Command:
```bash
find assets/sprites -name "*_shadow.png" -delete
find assets/sprites -name "*_shadow.png.import" -delete
```

**Step 2: Delete decoration shadow PNGs and imports**

```bash
rm assets/decorations/pinetree/shadow.png assets/decorations/pinetree/shadow.png.import
rm assets/decorations/pinetree2/shadow.png assets/decorations/pinetree2/shadow.png.import
rm assets/decorations/blocking/shadow.png assets/decorations/blocking/shadow.png.import
```

**Step 3: Remove has_shadow from decoration_atlas.json**

Change all `"has_shadow": true` to `"has_shadow": false` in `assets/decorations/_atlas/decoration_atlas.json`. (Or remove the field entirely.)

**Step 4: Commit**

```
git add -A assets/sprites/ assets/decorations/
git commit -m "refactor: delete all shadow sprite assets and update decoration atlas"
```

---

### Task 9: Update VBA database files

**Files:**
- Modify: `databases/vba/ZoneMoodDatabase.bas`
- Modify: `databases/vba/SharedValidation.bas`

Note: User must re-run ExportAll in Excel after these changes to regenerate zone_moods.json.

**Step 1: Remove from ZoneMoodDatabase.bas**

Remove `COL_ZM_REALTIME_SHADOWS` constant (line 22)

Remove realtime shadows processing block (lines ~173-179): variable declaration and true/false conversion

Remove `realtime_shadows` export line (line ~190): the JSON output line

Remove `"realtime_shadows"` from headers array (line ~216)

Remove help comment for column 9 (line ~229)

**Step 2: Remove from SharedValidation.bas (line ~768)**

Remove:
```vba
ApplyListValidation "ZoneMoods", 9, "TRUE,FALSE"           ' realtime_shadows
```

**Step 3: Update docstring in ZoneMoodDatabase.bas (line ~5)**

Change "shadow settings" to remove shadow reference from module description.

**Step 4: Commit**

```
git add databases/vba/ZoneMoodDatabase.bas databases/vba/SharedValidation.bas
git commit -m "refactor: remove realtime_shadows from ZoneMood VBA database"
```

---

### Task 10: Update documentation

**Files:**
- Modify: `docs/LDTK_MAP_REFERENCE.md`
- Modify: `docs/ZONE_DESIGN_GUIDE.md`
- Move: `docs/plans/2026-02-22-blob-shadow-system-design.md` → `docs/archive/`
- Move: `docs/plans/2026-02-22-blob-shadow-system-implementation.md` → `docs/archive/`

**Step 1: Update LDTK_MAP_REFERENCE.md**

Remove `shadow_mode` from decoration entity field list (line ~459)

Remove shadow asset entries from the directory structure (lines ~469-470)

Remove "Shadow Mode Options" section (lines ~478-480)

**Step 2: Update ZONE_DESIGN_GUIDE.md**

Remove "Shadows" column from lighting guidelines table (line ~452 area). Change the table to only have "Time/Mood" and "Lighting" columns.

**Step 3: Archive old shadow design docs**

```bash
mkdir -p docs/archive
mv docs/plans/2026-02-22-blob-shadow-system-design.md docs/archive/
mv docs/plans/2026-02-22-blob-shadow-system-implementation.md docs/archive/
```

**Step 4: Commit**

```
git add docs/
git commit -m "docs: update references and archive old shadow system design docs"
```

---

### Task 11: Verify clean build

**Step 1: Search for remaining shadow references**

Run a comprehensive grep to ensure no shadow system references remain:
```bash
grep -rn "shadow" scripts/ autoloads/ --include="*.gd" | grep -v "font_shadow" | grep -v "COL_SKIN_SHADOW" | grep -v "color_damage_shadow" | grep -v "# TODO: Shadow"
```

Expected: No results (only UI text shadows, skin palette color, damage type color, and TODO stubs should remain).

**Step 2: Verify no broken references**

Check that `player_sprites.tres` doesn't reference any deleted shadow PNG files:
```bash
grep -n "shadow" resources/player_sprites.tres
```

Expected: No results.

**Step 3: Final commit if any fixes needed**

```
git commit -m "fix: clean up any remaining shadow references"
```
