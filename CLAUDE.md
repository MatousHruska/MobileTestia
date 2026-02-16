# MobileTestia - Claude Code Instructions

## Project Overview

MobileTestia is a Godot 4 mobile game project. The codebase uses GDScript, LDtk for map editing, and an Excel/VBA-driven database pipeline for all game data.

## Database Workflow

**CRITICAL: NEVER edit `.json` files in `databases/exports/` directly!**

The database is managed through Excel with VBA macros. Direct JSON edits will be overwritten on the next export.

### Correct workflow for database changes:

1. Provide updated `.bas` VBA files for any schema changes (located in `databases/vba/`)
2. Provide Excel-ready data to paste into sheets (tab-separated or table format)
3. The user imports VBA, pastes data, and runs `ExportAll` to generate JSON

### When changing database schema, always update all three:

- The specific database `.bas` file (e.g., `databases/vba/EnemyDatabase.bas`)
- `databases/vba/MasterExport.bas` (`ExportAll`, `ValidateAll`, `SetupWorkbook` functions)
- `databases/vba/SharedValidation.bas` (named ranges, foreign key validations, enum validations)

### VBA naming convention:

Export functions must be named `ExportXxxData` where `Xxx` matches the sheet name (e.g., `ExportAbilitiesData`, `ExportEnemyAbilitiesData`).

### Data formatting:

When writing data for a database, be careful about `,` and `.` characters. JSON requires `.` for decimal separators — always use `.` for numbers, never `,`.

## Stats and Descriptions

Whenever you make an update to stats, add a new stat, or create a new way of implementing one, check `databases/vba/StatDescriptionDatabase.bas` and the exported `databases/exports/stat_descriptions.json`, and update the appropriate stat description.

## UI and Layout

- Always prefer dynamic percentage-based sizing over fixed pixels for scaling across different devices.
- When designing any UI element (texts, containers, wireframes), read `databases/exports/ui_theme.json` (sourced from `databases/vba/UIThemeDatabase.bas`) where style classes are defined.
- No text in the game should be classless. No UI wireframe should be classless.

## Save/Load System

The project has an existing save/load system (`autoloads/save_manager.gd`, `autoloads/persistence_manager.gd`). When planning new features and systems, always integrate with this existing framework rather than creating separate persistence logic.

## Reference Documentation

Consult these docs when working on the corresponding systems:

| Topic | Reference Files |
|-------|----------------|
| Enemies, behavior, AI | `docs/ENEMY_REFERENCE.md`, `docs/ABILITY_SYSTEM_REFERENCE.md`, `docs/QUICK_REFERENCE.md` |
| Maps and LDtk | `docs/LDTK_MAP_REFERENCE.md`, `docs/ZONE_DESIGN_GUIDE.md` |
| Debugging tools | `docs/DEBUG_QUICK_REFERENCE.md` |
| Combat system | `docs/COMBAT_SYSTEM.md` |
| Ability visual sequencer, templates, CharacterVisuals | `docs/COMBAT_SYSTEM.md` (Ability Visual Sequencer section) |
| Animations, sprite generation, pose types | `docs/PLACEHOLDER_SPRITES.md` |
| Collision layers | `docs/COLLISION_LAYERS.md` |
| UI system | `docs/UI_DOCUMENTATION.md` |
| Art direction | `docs/ART_DIRECTION.md` |

## Project Structure

```
autoloads/       # Singleton managers (game_manager, save_manager, database_loader, etc.)
databases/
  vba/           # VBA macro source files (.bas) — the source of truth for schema
  exports/       # Generated JSON files — DO NOT EDIT DIRECTLY
  docs/          # Database setup documentation
docs/            # Game design and system reference documentation
maps/            # LDtk map files
scenes/          # Godot scene files (.tscn)
scripts/         # GDScript files (.gd)
shaders/         # Shader files
assets/          # Sprites, textures, and other assets
resources/       # Godot resource files
tests/           # Test files
```
