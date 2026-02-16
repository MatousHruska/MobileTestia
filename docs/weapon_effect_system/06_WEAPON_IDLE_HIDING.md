# Phase 6: Weapon Idle Hiding

## Context

The design principle is: **weapons are NOT visible outside of ability sequences**. During idle, walking, dashing (non-attack), or any non-combat state, the weapon is hidden. It only appears when an ability template explicitly shows it via `WEAPON_VISIBILITY(true)` phases.

The revised melee templates (Phase 4) no longer end with `WEAPON_VISIBILITY(true)` — they leave the weapon hidden after recovery. But we need to make sure the weapon is also hidden:
1. At game start / scene load.
2. After any ability sequence finishes (safety net).
3. When transitioning from combat to non-combat state.

This is a small but important phase — without it, the weapon might show unexpectedly.

## Prerequisites

- **Phase 2** (CharacterVisuals weapon set support) — weapon visibility API must exist.

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/combat/character_visuals.gd` | `set_weapon_visible()`, `weapon_visible` state |
| `scripts/player/player_controller.gd` | Where `CharacterVisuals` is created, signal connections |
| `scripts/combat/ability_visual_player.gd` | `sequence_finished` signal |
| `scripts/player/player_animator.gd` | Animation state machine, might need integration |

## Implementation Prompt

### Change 1: Default Weapon Visibility to False

In `CharacterVisuals`, the weapon should default to hidden:

**Current:**
```gdscript
var weapon_visible: bool = true
```

**Change to:**
```gdscript
var weapon_visible: bool = false
```

This ensures weapons start hidden. Only `WEAPON_VISIBILITY(true)` phases make them visible.

### Change 2: Hide Weapon on Sequence Finish

When an ability sequence finishes, ensure the weapon is hidden. This is a safety net — the templates should already leave the weapon hidden, but if a template is misconfigured (or a new template forgets to hide it), this catches it.

Find where `sequence_finished` is connected in `PlayerController` (or wherever the player handles sequencer signals). Add:

```gdscript
func _on_sequence_finished(_template_id: String) -> void:
    # ... existing code (unlock movement, etc.) ...

    # Safety: ensure weapon is hidden when not in a sequence
    if character_visuals:
        character_visuals.set_weapon_visible(false)
```

If the connection doesn't exist yet, add it where the `AbilityVisualPlayer` signals are connected.

### Change 3: Hide Weapon on Initialization

When `CharacterVisuals` is initialized, explicitly hide the weapon:

```gdscript
func initialize(body: AnimatedSprite2D) -> void:
    body_sprite = body
    _create_weapon_layer()
    _create_effect_anchor()
    _create_overlay_layer()
    # Ensure weapon starts hidden
    set_weapon_visible(false)
```

### Change 4: Verify Template End States

Double-check that the revised melee templates (Phase 4) do NOT end with `WEAPON_VISIBILITY(true)`. The last phases should be:

```
... → DAMAGE_EVENT → BODY_ANIM("idle", recovery) → [end]
```

No trailing weapon show. The weapon was already hidden before the strike, and stays hidden through recovery and idle.

Also verify that non-melee templates that DO end with `WEAPON_VISIBILITY(true)` (like `spell_cast`, `spell_instant`, `self_buff`) should be updated to end with `WEAPON_VISIBILITY(false)` instead, since we now want weapons hidden by default.

**Templates to check and update:**
- `spell_cast` — currently ends with `WEAPON_VISIBILITY(true)` → change to `WEAPON_VISIBILITY(false)` (or remove the final show)
- `spell_instant` — same
- `self_buff` — same
- `throw` — same

For now (melee focus), at minimum ensure the spell/buff templates don't re-show the weapon at the end. Since the weapon is hidden at sequence start for these templates, they should end with it still hidden. Remove the trailing `WEAPON_VISIBILITY(true)` from these templates:

```gdscript
# In _spell_cast():
# REMOVE this phase at the end:
# AbilityVisualPhase.create_weapon_visibility(true),
```

This ensures consistency — ALL templates end with weapon hidden. The next ability sequence's template is responsible for showing it if needed.

### What NOT to Change

- Don't hide the weapon during the middle of a sequence — that's the template's job.
- Don't change `AbilityVisualPlayer` — it just relays the `WEAPON_VISIBILITY` phases.
- Don't change `PlayerAnimator` — the weapon layer is managed by `CharacterVisuals`, not the animator.

## Acceptance Criteria

1. `CharacterVisuals.weapon_visible` defaults to `false`.
2. Weapon is hidden at game start / scene load.
3. Weapon is hidden after any `sequence_finished` signal fires.
4. All melee templates end without a trailing `WEAPON_VISIBILITY(true)`.
5. Non-melee templates (`spell_cast`, `spell_instant`, `self_buff`, `throw`) have their trailing `WEAPON_VISIBILITY(true)` removed.
6. Weapon only becomes visible when a template explicitly includes `WEAPON_VISIBILITY(true)`.
7. No visual regression — weapons still appear during ability windups as designed.

---

*Phase 6 of 7 — Depends on Phase 2*
