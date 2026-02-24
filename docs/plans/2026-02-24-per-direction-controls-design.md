# Per-Direction Controls for Sprite Capture Wizard

## Problem

The sprite capture wizard currently forces all 3 directions (down, up, right) to be
captured and edited together. Users need per-direction control because:

- A sprite may need nudging in one direction but not others
- Re-capturing all 3 directions is wasteful when only one needs a redo

## Design

### Step 2 — Per-Direction Capture

**New UI:** A capture-scope toggle group (`All | Down | Up | Right`) above the
"Start Capturing" button.

**New state:** `_capture_scope: String = "all"` — one of `"all"`, `"down"`, `"up"`, `"right"`.

**Behavior:**
- `"all"`: Clears all sheets, captures all 3 directions (current behavior).
- Single direction: Clears only that direction's sheets from the dictionaries,
  captures only that direction. Other directions' data is preserved.
- Button label updates to reflect scope: "Capture All" / "Capture Down" / etc.
- Status message reflects what was captured.

### Step 4 — Per-Direction Editing

**New UI:** A `CheckButton` labeled "Apply to all directions" in the Frame Editor
section, below the onion skin toggle. Default: ON (preserves current behavior).

**New state:** `_frame_editor_all_directions_toggle: CheckButton`

**Nudge behavior (`_nudge_current_frame`):**
- Toggle ON: iterate over all `sheet_dict.keys()` (current behavior).
- Toggle OFF: iterate only over `[_frame_editor_direction]`.

**Delete behavior (`_delete_current_frame`):**
- Toggle ON: delete frame from all directions (current behavior).
- Toggle OFF: delete frame only from the currently selected direction.
  Directions may end up with different frame counts.

## Files Modified

- `scripts/tools/sprite_pipeline.gd` — all changes in this single file
