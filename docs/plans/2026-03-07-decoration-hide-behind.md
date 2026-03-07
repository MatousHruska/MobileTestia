# Decoration Hide-Behind-Character Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make decorations fade to semi-transparent when the player walks behind them, using an Area2D overlap zone derived from the existing occluder polygon.

**Architecture:** A boolean `hide_behind` flag is configured per decoration in the pipeline wizard (Step 5, alongside shadow config) and exported in `shadow.json`. At runtime, `DecorationSpawner` reads this flag and attaches an `Area2D` + `CollisionPolygon2D` (from the occluder) that tweens the sprite's `self_modulate.a` when the player overlaps.

**Tech Stack:** GDScript, Godot 4 Area2D/CollisionPolygon2D, Tween

---

### Task 1: Add hide_behind checkbox to pipeline wizard (Step 5)

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Add state variable for the checkbox**

At line ~173 (after the shadow alpha mask state variables), add:

```gdscript
# Hide-behind-character state
var _hide_behind_check: CheckButton = null
```

**Step 2: Add the checkbox UI in `_build_step5()`**

At the end of `_build_step5()` (after the Shadow Alpha Mask collapsible section), add a new section:

```gdscript
# ── Hide Behind Character ────────────────────────────────────────
var hide_sec := _make_section("Hide Behind Character")
parent.add_child(hide_sec[0])
var hide_content: VBoxContainer = hide_sec[1]

hide_content.add_child(_make_small_label(
    "When enabled, the decoration fades when the player walks behind it. Requires an occluder polygon (Step 4)."))

_hide_behind_check = CheckButton.new()
_hide_behind_check.text = "Hide in front of character"
_hide_behind_check.button_pressed = false
_style_checkbutton_transparent(_hide_behind_check)
hide_content.add_child(_hide_behind_check)
```

**Step 3: Reset the checkbox on new decoration**

Find the 3 places where `_shadow_alpha_mask = null` is set during resets (lines ~651, ~691, ~993). After each one, add:

```gdscript
if _hide_behind_check:
    _hide_behind_check.button_pressed = false
```

**Step 4: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(pipeline): add hide-behind-character checkbox to Step 5"
```

---

### Task 2: Export hide_behind flag in shadow.json

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Add hide_behind to shadow.json export**

In `_start_export()` at line ~1876, the `shadow_params` dictionary is built. Add the `hide_behind` key:

Change:
```gdscript
var shadow_params := {
    "length": _shadow_length_slider.value,
    "offset_x": _shadow_offset_x_slider.value,
    "offset_y": _shadow_offset_y_slider.value,
    "overlap": _shadow_overlap_slider.value,
}
```

To:
```gdscript
var shadow_params := {
    "length": _shadow_length_slider.value,
    "offset_x": _shadow_offset_x_slider.value,
    "offset_y": _shadow_offset_y_slider.value,
    "overlap": _shadow_overlap_slider.value,
    "hide_behind": _hide_behind_check.button_pressed if _hide_behind_check else false,
}
```

**Step 2: Also export hide_behind even when shadow is disabled**

Currently `shadow.json` is only saved when the shadow checkbox is enabled (line ~1875: `if _shadow_enabled_check and _shadow_enabled_check.button_pressed`). A decoration might want hide-behind but no shadow. After the shadow export block (after line ~1897), add:

```gdscript
# Save hide_behind flag even without shadow enabled
if not (_shadow_enabled_check and _shadow_enabled_check.button_pressed):
    if _hide_behind_check and _hide_behind_check.button_pressed:
        var hide_params := {"hide_behind": true}
        var hide_json := JSON.stringify(hide_params, "  ")
        var hide_path := ProjectSettings.globalize_path(output_dir + "/shadow.json")
        var hide_file := FileAccess.open(hide_path, FileAccess.WRITE)
        if hide_file:
            hide_file.store_string(hide_json)
            hide_file.close()
            _append_log("Saved: %s/shadow.json (hide_behind only)" % deco_id)
```

**Step 3: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(pipeline): export hide_behind flag in shadow.json"
```

---

### Task 3: Read hide_behind flag in DecorationSpawner and create Area2D

**Files:**
- Modify: `scripts/environment/decoration_spawner.gd`

**Step 1: Add global constants**

After the existing constants at the top of the file (line ~6):

```gdscript
const HIDE_BEHIND_OPACITY := 0.3
const HIDE_BEHIND_FADE_DURATION := 0.2
```

**Step 2: Add hide-behind Area2D creation in `spawn()`**

After the shadow block (line ~69) and before the z-sorting block (line ~72), add:

```gdscript
# Hide-behind: fade decoration when player walks behind it
var hide_behind: bool = assets.shadow_params.get("hide_behind", false) if assets.shadow_params else false
if hide_behind and assets.occluder:
    var area := Area2D.new()
    area.name = "HideBehindArea"
    area.collision_layer = 0
    area.collision_mask = 2  # Detect player body (layer 2)
    var col_poly := CollisionPolygon2D.new()
    col_poly.polygon = assets.occluder.polygon
    area.add_child(col_poly)
    # Occluder polygon is in image-space; offset to match bottom-center anchor
    area.position = anchor_offset
    node.add_child(area)

    area.body_entered.connect(func(_body: Node2D) -> void:
        var tw := sprite.create_tween()
        tw.tween_property(sprite, "self_modulate:a", HIDE_BEHIND_OPACITY, HIDE_BEHIND_FADE_DURATION)
    )
    area.body_exited.connect(func(_body: Node2D) -> void:
        var tw := sprite.create_tween()
        tw.tween_property(sprite, "self_modulate:a", 1.0, HIDE_BEHIND_FADE_DURATION)
    )
```

**Step 3: Commit**

```bash
git add scripts/environment/decoration_spawner.gd
git commit -m "feat: decoration fades when player walks behind it"
```

---

### Task 4: Add hide_behind to atlas metadata

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Read hide_behind from shadow.json during atlas build**

In the atlas metadata collection (line ~1944 area where `deco_entries.append` happens), add a `has_hide_behind` field. Before the append, read the shadow.json to check:

After the existing `has_shadow_mask` line (line ~1952), add:

```gdscript
"has_hide_behind": _read_shadow_flag(folder_name, "hide_behind"),
```

Add a helper function near `_start_export`:

```gdscript
func _read_shadow_flag(deco_id: String, key: String) -> bool:
    var path := ProjectSettings.globalize_path("%s/%s/shadow.json" % [DECORATIONS_DIR, deco_id])
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    var json := JSON.new()
    if json.parse(file.get_as_text()) != OK:
        return false
    return json.data.get(key, false)
```

**Step 2: Include in atlas JSON output**

In the metadata append block (line ~2000 area), add after `has_shadow_mask`:

```gdscript
"has_hide_behind": entry.get("has_hide_behind", false),
```

**Step 3: Commit**

```bash
git add scripts/tools/decoration_pipeline.gd
git commit -m "feat(pipeline): include has_hide_behind in atlas metadata"
```

---

### Task 5: Manual test in-game

**Step 1: Test with existing decoration**

Edit an existing decoration's `shadow.json` (e.g., `assets/decorations/pinetree2/shadow.json`) and add `"hide_behind": true` to test runtime behavior. Walk the player behind the tree and verify:

- Decoration fades to ~30% opacity over 0.2s
- Shadow stays at full opacity
- Walking away restores full opacity smoothly

**Step 2: Test in pipeline**

Open the decoration pipeline, process any decoration, verify:

- Step 5 shows "Hide Behind Character" section with checkbox
- Checkbox state is exported to shadow.json
- Checkbox resets when starting a new decoration

**Step 3: Clean up test edit and commit**

Remove the manual `hide_behind` addition from pinetree2 if it was just for testing (or keep it if desired).
