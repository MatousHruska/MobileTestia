# Plan: Remove UV Shader Equipment System — Clean Slate

## Context

The UV color-lookup shader system allowed dynamic equipment changes on the player character via UV maps, lookup textures, and skin swapping. This is being replaced with a much simpler system: static sprite animations where only the weapon is visible during attack animations. This plan removes **everything** related to the old system.

---

## Phase 1: Delete Shader Files (2 files)

| # | File | Action |
|---|------|--------|
| 1 | `shaders/uv_color_lookup.gdshader` | DELETE |
| 2 | `shaders/uv_equipment_lookup.gdshader` | DELETE |

---

## Phase 2: Delete Scripts (4 files)

| # | File | Action |
|---|------|--------|
| 3 | `autoloads/visual_asset_manager.gd` | DELETE — central UV asset manager |
| 4 | `scripts/rendering/uv_character_animator.gd` | DELETE — UV animator class |
| 5 | `scripts/tools/motion_map_generator.gd` | DELETE — tool for generating UV motion maps |
| 6 | `scripts/tools/uv_texture_generator.gd` | DELETE — tool for generating UV test textures |

---

## Phase 3: Delete Test Scenes + Scripts (7 files)

| # | File | Action |
|---|------|--------|
| 7 | `scenes/test/test_annia_uv_shader.tscn` | DELETE |
| 8 | `scenes/test/test_annia_uv_shader.gd` | DELETE |
| 9 | `scenes/test/test_custom_uv_shader.tscn` | DELETE |
| 10 | `scenes/test/test_custom_uv_shader.gd` | DELETE |
| 11 | `scenes/test/test_equipment_shader.tscn` | DELETE |
| 12 | `scenes/test/test_equipment_shader.gd` | DELETE |
| 13 | `scenes/rendering/uv_character_animator.tscn` | DELETE — reusable scene for the UV animator |

---

## Phase 4: Delete UV Asset Files (17 files)

All UV-specific textures and their `.import` files. Also the empty placeholder directories.

| # | File | Action |
|---|------|--------|
| 14 | `assets/sprites/characters/player/player_idle.png` + `.import` | DELETE — UV motion map |
| 15 | `assets/sprites/characters/player/player_skin.png` + `.import` | DELETE — lookup texture |
| 16 | `assets/sprites/characters/player/player_skin_alt.png` + `.import` | DELETE — alt skin |
| 17 | `assets/sprites/characters/player/player_equip_head.png` + `.import` | DELETE — equipment slot |
| 18 | `assets/sprites/characters/player/player_equip_body.png` + `.import` | DELETE — equipment slot |
| 19 | `assets/sprites/characters/player/player_equip_hands.png` + `.import` | DELETE — equipment slot |
| 20 | `assets/sprites/characters/player/player_equip_legs.png` + `.import` | DELETE — equipment slot |
| 21 | `assets/sprites/characters/player/player_uv.png` + `.import` | DELETE — UV map |
| 22 | `assets/sprites/characters/player/motion/.gitkeep` | DELETE — empty placeholder dir |
| 23 | `assets/sprites/characters/player/skins/.gitkeep` | DELETE — empty placeholder dir |
| 24 | `assets/test/NewTest/` (entire directory) | DELETE — UV test assets (FinalsLookup.png, FinalsUV.png, Frame1.png, Idle01.png, Idle02.png + their .import files) |
| 25 | `assets/test/.gitkeep` | DELETE if directory becomes empty |

---

## Phase 5: Delete Documentation (10 files)

| # | File | Action |
|---|------|--------|
| 26 | `docs/VISUAL_SYSTEM_TECHNICAL.md` | DELETE — entire doc describes UV system |
| 27 | `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` | DELETE — UV implementation roadmap |
| 28 | `docs/visual_phases/PHASE_1_BASIC_SHADER.md` | DELETE |
| 29 | `docs/visual_phases/PHASE_2_PLAYER_MOVEMENT.md` | DELETE |
| 30 | `docs/visual_phases/PHASE_3_EQUIPMENT_VISUALS.md` | DELETE |
| 31 | `docs/visual_phases/PHASE_4_PLAYER_COMBAT.md` | DELETE |
| 32 | `docs/visual_phases/PHASE_5_ENEMIES.md` | DELETE |
| 33 | `docs/visual_phases/PHASE_6_WORLD_OBJECTS.md` | DELETE |
| 34 | `docs/visual_phases/PHASE_7_LIGHTING_ATMOSPHERE.md` | DELETE |
| 35 | `docs/visual_phases/PHASE_8_POLISH_EFFECTS.md` | DELETE |
| 36 | `docs/visual_phases/` directory itself | DELETE |

---

## Phase 6: Edit `project.godot` — Remove Autoload

Remove the VisualAssets autoload entry:
```
VisualAssets="*res://autoloads/visual_asset_manager.gd"
```

---

## Phase 7: Edit `scenes/player/player.tscn` — Remove UV Animator Node

Remove:
- The `[ext_resource]` line referencing `scripts/rendering/uv_character_animator.gd`
- The `[node name="UVCharacterAnimator"]` node and its child `Sprite2D`

The player scene will need a new simple sprite setup later (out of scope for this cleanup).

---

## Phase 8: Edit `scripts/player/player_controller.gd` — Strip All UV References

Changes needed:
1. **Remove** `@onready var animator: UVCharacterAnimator = $UVCharacterAnimator` (line 43)
2. **Remove** entire `_setup_animator()` function (lines 109-119) — connects UV animator signals
3. **Remove** `_setup_animator()` call from `_ready()` (if present)
4. **Remove** all `animator.` calls throughout the file:
   - `animator.attack_hit_frame.is_connected(...)` / `.connect(...)`
   - `animator.play_attack()`
   - `animator.play_dodge()`
   - `animator.update_movement(velocity)`
   - `animator.set_facing(current_facing)`
   - `animator.set_skin(...)`
   - `animator.print_state()`
5. **Remove** entire `debug_cycle_skin()` function (lines 550-565)
6. **Remove** any `debug_toggle_test_shader()` function if present

**Important**: The `_on_attack_hit_frame()` function (line 122+) should be KEPT — it handles hitbox timing which is gameplay logic, not visual. It just needs to be disconnected from the UV animator signal for now (it will be reconnected to whatever new animation system is used later).

---

## Phase 9: Edit `autoloads/debug_manager.gd` — Remove UV Debug Commands

Changes needed:
1. **Remove** the `KEY_KP_9` case (lines 144-146) that calls `_toggle_test_motion()`
2. **Remove** entire `_toggle_test_motion()` function (lines 209-222) — calls `debug_toggle_test_shader`

---

## Phase 10: Edit `docs/ART_DIRECTION.md` — Remove UV System Sections

Remove all sections describing:
- UV Color-Lookup System architecture
- Motion maps, lookup textures, UV maps
- Sector-based equipment system
- UV shader parameters and code examples

Keep: Color palette, visual identity, general art direction guidance.

---

## Phase 11: Edit `CLAUDE.md` — Update References

Remove from the reference documentation table:
- `Visual system` row (points to deleted docs)
- `Visual phases` row (points to deleted docs)

---

## Summary

| Action | Count |
|--------|-------|
| Files to DELETE | ~40 (including .import files) |
| Files to EDIT | 5 (`project.godot`, `player.tscn`, `player_controller.gd`, `debug_manager.gd`, `CLAUDE.md`) |
| Docs to EDIT | 1 (`ART_DIRECTION.md`) |
| Docs to DELETE | 10 |

### What is NOT touched (correctly preserved):
- **Item/equipment database** (stats, items, loot) — unrelated to visuals
- **Combat system** — damage, abilities, hitboxes stay
- **Enemy visual_effect fields** — these are combat feedback effects, not UV rendering
- **General game systems** — save/load, quests, NPCs, etc.
