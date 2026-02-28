# Attack Composer: Horizontal Scrollbar & Per-Direction Sequences

**Date:** 2026-02-28
**Status:** Approved

## Overview

Two changes to the attack composer tool:
1. Add a horizontal scrollbar under the timeline for panning
2. Convert directions from viewpoints (shared timeline) to independent sequences

## Requirements (from user answers)

- Each direction has fully independent frame counts
- All per-frame and sequence-level properties are independent per direction
- "All" button broadcasts edits to all directions; skips missing frames silently
- Standard Godot HScrollBar for the timeline scrollbar

## Data Model

### New class: `DirectionSequence` (Resource)

```gdscript
class_name DirectionSequence
extends Resource

@export var frames: Array[CompositionFrame] = []
@export var movement_type: String = ""
@export var movement_distance: float = 0.0
@export var movement_start_frame: int = -1
@export var movement_end_frame: int = -1
@export var damage_frame: int = -1

func get_total_duration_ms() -> int:
    var total := 0
    for f in frames:
        total += f.duration_ms
    return total
```

### Modified: `AttackCompositionData`

- **Remove:** `frames`, `movement_type`, `movement_distance`, `movement_start_frame`, `movement_end_frame`, `damage_frame`
- **Add:** `direction_sequences: Dictionary` mapping `"down"`, `"up"`, `"right"` → `DirectionSequence`
- **Keep shared:** `composition_id`, `display_name`, `animation_name`, `runtime_template_id`, `locks_movement`
- **Migration:** Old `.tres` with flat `frames` → copy into all 3 directions on load

### `CompositionFrame` — unchanged

## UI Changes

### Timeline Scrollbar

- Standard `HScrollBar` placed directly below the `TimelinePanel`
- `min_value = 0`, `max_value = total_duration_ms`
- `page = visible_width_px / pixels_per_ms` (size of thumb)
- Bidirectional sync:
  - Scrollbar value_changed → `scroll_offset_ms = value`
  - Mouse wheel scroll in timeline → update scrollbar value
  - Zoom change → recalculate `page` and clamp value

### Direction Buttons

**New layout:** `All | D | U | R`

- `All` — edits propagate to all directions. Timeline shows "down" as visual reference.
- `D/U/R` — single direction mode. Timeline shows that direction's frames.
- "All" button uses distinct color (gold/yellow).
- Frame index clamps on direction switch if new direction has fewer frames.

### Frame/Sequence Properties

- Frame properties: in "All" mode, iterate all directions, apply to frame at current index (skip if index out of bounds).
- Sequence properties (movement, damage_frame): in "All" mode, apply to all `DirectionSequence` objects. In single mode, only active direction.

### Timeline Panel

- Always shows the active direction's data
- In "All" mode, shows "down" direction as reference
- Frame thumbnails sourced from active direction

## Systems

### Undo

- Snapshots capture all `direction_sequences` (deep copy of all 3)
- Frame images already stored per-direction — no change
- Alpha masks deep-copied as before

### Save/Load

- Single `.tres` per composition (contains all 3 direction sequences)
- Migration: detect old format (has `frames` but no `direction_sequences`), auto-migrate
- On load, initialize frame textures for all 3 directions

### Composition Converter

- Takes direction parameter or processes all 3
- Generates `AbilityVisualData` per direction
- Runtime already handles direction-specific assets

### "All" Mode Edit Flow

1. `_push_undo()` captures full state
2. For each direction in `["down", "up", "right"]`:
   - Get `DirectionSequence`
   - If frame index < sequence.frames.size(): apply edit
   - Else: skip
3. Refresh timeline with "down" as reference visual
