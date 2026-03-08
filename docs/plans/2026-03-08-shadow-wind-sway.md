# Shadow Wind Sway Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a subtle wind sway animation to decoration shadows — a slow sine-wave horizontal oscillation (1-2px) with per-instance random phase, toggled per-decoration in the pipeline.

**Architecture:** A `wind_sway` boolean is stored in `shadow.json`, read at spawn time, and drives a sine-based horizontal offset in `SilhouetteShadow._process()`. Each instance picks a random phase so decorations sway independently. The pipeline shadow step (Step 5) gets a new checkbox to toggle it.

**Tech Stack:** GDScript, decoration pipeline UI, shadow.json schema

---

### Task 1: Add wind sway logic to SilhouetteShadow

**Files:**
- Modify: `scripts/environment/silhouette_shadow.gd`

**Step 1: Add wind sway properties (after line 28)**

Add these member variables after the existing `_inherited_scale` line:

```gdscript
var _wind_sway_enabled := false  ## Whether this shadow oscillates horizontally
var _wind_sway_phase := 0.0  ## Random phase offset (radians) for desynchronized sway
```

**Step 2: Add wind sway to `apply_params()`**

In `apply_params()` (around line 95), add handling for the `wind_sway` key after the existing param checks:

```gdscript
if params.has("wind_sway"):
    _wind_sway_enabled = params["wind_sway"]
    if _wind_sway_enabled and _wind_sway_phase == 0.0:
        _wind_sway_phase = randf() * TAU
```

**Step 3: Apply sway offset in `_process()`**

In `_process()`, after the existing position tracking block (after the line that sets `global_position = _original_parent.global_position + _local_offset * _inherited_scale`), add the sway offset. Also add it to the non-reparented path. The sway applies to the shadow's `global_position.x` after all other position calculations:

```gdscript
# Wind sway — subtle horizontal oscillation for decoration shadows
if _wind_sway_enabled:
    var sway_offset := sin(Time.get_ticks_msec() * 0.001 * 0.8 + _wind_sway_phase) * 1.5
    global_position.x += sway_offset
```

This goes at the end of `_process()`, after both the `_in_shadow_group` position tracking and the animated frame sync blocks, so it applies regardless of whether the shadow was reparented.

**Step 4: Commit**

```
feat: add wind sway animation to decoration shadows
```

---

### Task 2: Add Wind Sway checkbox to pipeline Step 5

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd`

**Step 1: Add member variable for the checkbox**

Near the existing `_hide_behind_check` declaration (line 176), add:

```gdscript
var _wind_sway_check: CheckButton = null
```

**Step 2: Add checkbox UI in `_build_step5()` — inside the shadow section**

Add the wind sway checkbox right after the `_shadow_overlap_slider` section (after line 1303), before the sun sweep / preview-only controls. Place it inside the shadow-enabled content area so it hides/shows with the shadow toggle:

```gdscript
_wind_sway_check = CheckButton.new()
_wind_sway_check.text = "Wind Sway"
_wind_sway_check.tooltip_text = "Subtle horizontal oscillation simulating wind"
_wind_sway_check.button_pressed = false
_style_checkbutton_transparent(_wind_sway_check)
shadow_controls.add_child(_wind_sway_check)
```

Note: `shadow_controls` is the container that holds the shadow parameter sliders. Check the exact variable name used in `_build_step5` — it's the VBoxContainer that the sliders are added to, which is toggled visible/hidden by `_shadow_enabled_check`. Find where `_shadow_length_slider` is added to identify the correct parent container.

**Step 3: Reset checkbox on decoration ID change**

In the three places where `_hide_behind_check.button_pressed = false` is set on decoration change (lines 655-656, 697-698, 1001-1002), add the same for `_wind_sway_check`:

```gdscript
if _wind_sway_check:
    _wind_sway_check.button_pressed = false
```

**Step 4: Commit**

```
feat: add wind sway checkbox to decoration pipeline shadow step
```

---

### Task 3: Export and load `wind_sway` flag

**Files:**
- Modify: `scripts/tools/decoration_pipeline.gd` (export)
- Modify: `scripts/environment/decoration_spawner.gd` (no changes needed — it passes the whole dict)

**Step 1: Include `wind_sway` in shadow.json export**

In `_start_export()` (around line 1899), add `wind_sway` to the `shadow_params` dict:

```gdscript
var shadow_params := {
    "length": _shadow_length_slider.value,
    "offset_x": _shadow_offset_x_slider.value,
    "offset_y": _shadow_offset_y_slider.value,
    "overlap": _shadow_overlap_slider.value,
    "hide_behind": _hide_behind_check.button_pressed if _hide_behind_check else false,
    "wind_sway": _wind_sway_check.button_pressed if _wind_sway_check else false,
}
```

**Step 2: Add `has_wind_sway` to atlas metadata**

In `_regenerate_atlas()`, add `has_wind_sway` to the deco_entries scan (around line 2002):

```gdscript
"has_wind_sway": _read_shadow_flag(folder_name, "wind_sway"),
```

And to the metadata output (around line 2060):

```gdscript
"has_wind_sway": entry.get("has_wind_sway", false),
```

**Step 3: No spawner changes needed**

`decoration_spawner.gd` already passes the entire `shadow_params` dict to `shadow.apply_params()`, so `wind_sway` will flow through automatically. `SilhouetteShadow.apply_params()` (modified in Task 1) handles the key.

**Step 4: Commit**

```
feat: export wind_sway flag in shadow.json and atlas metadata
```

---

### Task 4: Verify end-to-end

**Step 1: Manual test**

1. Open the decoration pipeline, select a decoration with shadow enabled
2. Toggle "Wind Sway" on, export
3. Verify `shadow.json` contains `"wind_sway": true`
4. Run the game, observe the decoration shadow sways slowly left/right (~1-2px)
5. Place multiple decorations — verify each sways at its own phase
6. Verify player/NPC shadows do NOT sway (they don't have `wind_sway` in their params)

**Step 2: Commit final state**

```
feat: shadow wind sway — slow horizontal oscillation for decoration shadows
```
