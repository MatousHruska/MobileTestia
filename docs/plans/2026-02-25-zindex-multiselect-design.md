# Per-Frame Weapon Z-Index & Multi-Select Frames

## Date: 2026-02-25

## Context

The Attack Composer currently hardcodes weapon z_index=2 in the preview and the runtime uses a direction-based heuristic (z=-1 for up, z=1 otherwise). Users need per-frame control over whether the weapon renders in front of or behind the character body. Additionally, editing frame properties one-at-a-time is tedious — shift-click multi-select with batch editing is needed.

## Feature 1: Per-Frame Weapon Z-Index

**Data**: Add `weapon_z_front: bool = true` to `CompositionFrame`. When true, z=1 (in front); when false, z=-1 (behind).

**UI**: CheckButton "Weapon In Front" below "Weapon Visible" in Frame Properties. Batch-editable when multi-selecting.

**Preview**: `_weapon_sprite.z_index` set from `frame.weapon_z_front` per frame.

**Timeline**: Weapon track shows "B" marker on frames where weapon is behind body.

**Runtime**: Composition converter outputs per-frame z_index. `character_visuals.gd` uses it instead of direction heuristic.

## Feature 2: Multi-Select Frames

**Selection model**: `selected_frames: Array[int]` (sorted). Primary frame = last clicked. Single click = clear + select one. Shift+click = range select from last clicked to shift-clicked (inclusive).

**Visual**: All selected frames get blue selection border. Primary frame gets thicker/brighter border.

**Batch editing**: Duration, weapon visible, weapon z-front, echo, effect — all apply to all selected frames as "set to same value". Single undo step for batch changes.

**Status**: Shows "N frames selected" when multi-selecting.

## Files Modified

| File | Change |
|------|--------|
| `composition_frame.gd` | Add `weapon_z_front: bool` |
| `attack_composer.gd` | Multi-select state, batch property editing, z-index preview |
| `timeline_panel.gd` | Multi-select rendering, shift-click handling, "B" marker on weapon track |
