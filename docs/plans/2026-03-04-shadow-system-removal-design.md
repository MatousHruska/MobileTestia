# Shadow System Removal — Design Document

**Date:** 2026-03-04
**Status:** Approved
**Goal:** Remove the entire shadow system (character blob shadows, decoration shadows, zone mood realtime shadows, PointLight2D shadow casting) to create a clean slate for a new shadow implementation.

## Context

The current shadow system has three components:
1. **Character blob shadows** — top-down silhouette capture in sprite pipeline, AnimatedSprite2D at z=-2 with light-responsive opacity/scale
2. **Decoration shadows** — baked shadow.png sprites (z=-1) + realtime LightOccluder2D mode
3. **Zone mood realtime shadows** — PointLight2D.shadow_enabled toggled per zone

All three are being removed. Light sources (torches, magic), normal maps, and UI text shadows are **kept**.

## What Stays Untouched

- UI text/panel shadows (font_shadow_color, shadow_offset — cosmetic text styling)
- "shadow" damage type in combat system (element type, not visual)
- color_damage_shadow in ui_theme.json (UI color for shadow damage element)
- COL_SKIN_SHADOW in generate_player_sprites.gd (skin palette color)
- Normal map capture pipeline
- Light source behavior (torches, magic lights, PointLight2D — minus shadow casting)

## Removal Scope

### 1. Character Visuals (character_visuals.gd)

**Remove:**
- Variables: `shadow_sprite`, `_shadow_has_animations`, `_shadow_animation_valid`, `_shadow_last_body_anim`, `_shadow_target_opacity`, `_shadow_target_scale`
- 13 shadow constants (SHADOW_ELLIPSE_*, SHADOW_Y_OFFSET, SHADOW_LIGHT_SEARCH_RADIUS, SHADOW_TRANSITION_SPEED, SHADOW_CLOSE/FAR_*, SHADOW_NO_LIGHT_*)
- Functions: `_create_shadow_layer()`, `_setup_shadow()`, `_generate_ellipse_shadow()`, `_sync_shadow_animation()`, `_update_shadow_light_response()`, `_apply_shadow_lerp()`
- Shadow sync calls in `_process()` and direction change handlers

**Stub:** `# TODO: Shadow system — hook new shadow implementation here`

### 2. Sprite Pipeline (sprite_pipeline.gd)

**Remove:**
- `_captured_shadow_sheets` dictionary
- `_shadow_capture_material` (StandardMaterial3D)
- Shadow camera creation, material application/restore functions
- Shadow capture pass in wizard
- Shadow preview mode button
- Shadow export in Step 5
- Shadow animation loading in Step 7

**Stub:** `# TODO: Shadow pipeline — hook new shadow capture/export here`

### 3. Decoration System

**decoration_spawner.gd:**
- Remove `shadow` from asset cache, shadow mode handling block, shadow texture loading

**decoration_pipeline.gd:**
- Remove shadow capture pass, `_generate_shadow_from_alpha()`, `_apply_shadow_styling()`, shadow UI controls, shadow export, shadow dictionaries

**decoration_atlas.json:**
- Remove `has_shadow` field from all entries

**Stub:** `# TODO: Shadow system — hook new decoration shadow here`

### 4. Zone Mood & Chunk Manager

**zone_mood.gd:**
- Remove `@export_group("Shadows")` and `realtime_shadows` property

**chunk_manager.gd:**
- Remove `light.shadow_enabled`, `light.shadow_filter`, `light.shadow_filter_smooth` lines

**4 zone mood .tres files:**
- Remove `realtime_shadows` property

**Stub:** `# TODO: Shadow system — hook new light shadow config here`

### 5. LDtk & Importer

- Remove `shadow_mode` field parsing from `ldtk_importer.gd`
- Remove `shadow_mode` from LDtk decoration entity definitions
- Remove `shadow_mode` values from exported entity data

### 6. Database (VBA + JSON)

**ZoneMoodDatabase.bas:**
- Remove `COL_ZM_REALTIME_SHADOWS`, export logic, column header, help text

**SharedValidation.bas:**
- Remove realtime_shadows validation line

**zone_moods.json:**
- Will be regenerated after VBA changes (not edited directly)

### 7. Asset Cleanup

- Delete ~48 character shadow PNGs (captures/ and final/ directories) + .import files
- Delete 3 decoration shadow PNGs + .import files
- Remove 24 `*_shadow` animation entries from `player_sprites.tres`

### 8. Other Scripts

- `apply_final_walk_sprites.gd`: Remove shadow animation integration
- `attack_composer.gd`: Remove shadow file filter
- `effect_pipeline.gd`: Keep `shadow_enabled = false` (harmless)

### 9. Documentation

- Archive blob shadow design/implementation docs (move to docs/archive/)
- Update LDTK_MAP_REFERENCE.md (remove shadow_mode from decoration fields)
- Update ZONE_DESIGN_GUIDE.md (remove shadow references from lighting guidelines)
