# Weapon & Effect Placeholder System — Implementation Plan

> **Scope**: Melee weapons and melee attack effects first. Ranged/magic/throw follow in later phases.

---

## Goal

Add procedurally drawn placeholder weapons and combat effects to the game, using the same Image-based draw system as the player/enemy sprite generators. Weapons appear only during ability sequences, are direction-aware, and integrate with the existing AbilityVisualPlayer phase/template system.

---

## Design Principles

1. **Weapons are props, not permanent fixtures** — hidden during idle/walk, shown only during ability sequences via WEAPON_VISIBILITY phases.
2. **Effects replace weapons during fast motion** — a slash arc VFX instead of a visible sword during the strike frame.
3. **Direction-aware rendering** — weapons have separate textures for down/up/right (left = right flipped).
4. **Procedural placeholder art** — everything drawn in code with `Image.create()` + `_fill_rect()`, replaceable with real art later.
5. **Data-driven** — weapon visibility and effects controlled entirely by template phases, not hardcoded per-ability.

---

## Melee Weapon Visibility Model

```
[IDLE] weapon hidden
  |
  v
[ABILITY STARTS]
  |
  v
SHOW weapon ──> Windup animation (sword raised/pulled back)
  |
  v
HIDE weapon ──> Slash EFFECT plays ──> Strike animation (arms swing, no sword visible)
  |
  v
DAMAGE EVENT
  |
  v
Recovery animation ──> weapon stays hidden
  |
  v
[IDLE] weapon hidden
```

The weapon appears as a physical object during preparation (windup), then "becomes" the slash effect during the strike. This is the cinematic pattern used by games like Hyper Light Drifter and Dead Cells.

---

## Implementation Phases

| Phase | File | Summary | Depends On |
|-------|------|---------|------------|
| 1 | `01_DIRECTION_AWARE_WEAPON_SPRITES.md` | Expand PlaceholderWeaponSprites with direction-aware texture sets for melee weapons | — |
| 2 | `02_CHARACTER_VISUALS_WEAPON_SETS.md` | Update CharacterVisuals to store/select textures by direction | Phase 1 |
| 3 | `03_PLACEHOLDER_EFFECT_SPRITES.md` | New PlaceholderEffectSprites class for melee VFX (slash_arc, thrust_line, impact_spark) | — |
| 4 | `04_MELEE_TEMPLATES_REVISION.md` | Revise melee templates to use new weapon show/hide + effect pattern | Phase 2, 3 |
| 5 | `05_WEAPON_EQUIPMENT_MAPPING.md` | Connect EquipmentData.weapon_category to weapon sprite sets | Phase 2 |
| 6 | `06_WEAPON_IDLE_HIDING.md` | Ensure weapons are hidden outside of ability sequences | Phase 2 |
| 7 | `07_DOCUMENTATION_UPDATES.md` | Update PLACEHOLDER_SPRITES.md and COMBAT_SYSTEM.md | Phase 1-6 |

### Dependency Graph

```
Phase 1 (weapon sprites) ──> Phase 2 (CharacterVisuals) ──> Phase 4 (templates)
                                                        ──> Phase 5 (equipment mapping)
                                                        ──> Phase 6 (idle hiding)
Phase 3 (effect sprites)  ──────────────────────────────> Phase 4 (templates)

Phase 1-6 ──> Phase 7 (docs)
```

Phases 1 and 3 are independent and can be done in parallel. Phase 4 requires both 2 and 3. Phases 5 and 6 can be done in parallel after Phase 2.

---

## Files Modified/Created

| File | Action | Phase |
|------|--------|-------|
| `scripts/combat/placeholder_weapon_sprites.gd` | Expand | 1 |
| `scripts/combat/character_visuals.gd` | Modify | 2, 6 |
| `scripts/combat/placeholder_effect_sprites.gd` | **CREATE** | 3 |
| `scripts/combat/ability_visual_templates.gd` | Modify | 4 |
| `scripts/combat/ability_visual_phase.gd` | Minor modify (if needed) | 4 |
| `scripts/ui/combat/combat_hud.gd` | Modify (equipment mapping) | 5 |
| `scripts/player/player_controller.gd` | Modify (weapon hiding) | 6 |
| `docs/PLACEHOLDER_SPRITES.md` | Update | 7 |
| `docs/COMBAT_SYSTEM.md` | Update | 7 |

---

## Melee Weapon Types (Phase 1 Scope)

| weapon_category | Sprite Set | Dimensions | Description |
|----------------|-----------|------------|-------------|
| `melee_1h` | Sword | ~8x20 per direction | Short blade + crossguard + handle |
| `melee_2h` | Greatsword | ~10x26 per direction | Longer blade, larger guard |
| `dagger` | Dagger | ~6x14 per direction | Short narrow blade |

Future (not in scope): `ranged` (bow), `magic` (staff).

---

## Melee Effect Types (Phase 3 Scope)

| Effect ID | Used By | Size | Lifetime | Description |
|-----------|---------|------|----------|-------------|
| `slash_arc` | melee_single, melee_combo | 24x24 | 0.15s | White/gray arc sweep |
| `slash_arc_wide` | melee_combo hit 2/3 | 28x28 | 0.15s | Wider arc for combo hits |
| `thrust_line` | thrust attacks | 20x8 | 0.12s | Narrow forward stab line |
| `impact_spark` | on damage event | 12x12 | 0.10s | Small star/cross flash |

Future (not in scope): cast_circle, spell_burst, buff_burst, howl_aura, bow_string_snap.

---

## How to Use These Phase Documents

Each phase document (`01_` through `07_`) contains:

1. **Context** — what this phase does and why
2. **Prerequisites** — which phases must be complete first
3. **Files to read** — existing files you need to understand before coding
4. **Implementation prompt** — the detailed instructions for what to build
5. **Acceptance criteria** — how to verify the phase is complete

Execute phases in dependency order. Phases 1+3 can run in parallel. Phase 4 is the integration point where everything comes together.

---

*Created: 2026-02-16*
