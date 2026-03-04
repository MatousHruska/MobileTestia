# Project Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up the project folder so only runtime assets end up in Android/iOS exports, and dev-only files are properly excluded.

**Architecture:** Three-pronged approach — (1) move reference-only assets outside the Godot project, (2) add `.gdignore` files to dev-only directories that stay in-project, (3) fix export presets to use exclude filters. Pipeline source assets (3D imports, captures) stay in-project because Godot's `load()` requires them to be importable — they're already gitignored so they don't bloat the repo.

**Tech Stack:** Godot 4 export presets, `.gdignore` files, file system operations

---

## Important Context

### Why 3D Imports Stay In-Project

The pipeline tools (`sprite_pipeline.gd`, `decoration_pipeline.gd`, etc.) use `load("res://assets/3d_imports/model.fbx")` to load 3D models. Godot's `load()` function only works with imported resources inside the project tree. Moving them outside would break all pipeline tools. Since these files are already in `.gitignore`, they don't bloat the git repo — we just need the export filter to keep them out of APK builds.

### Current `.gitignore` Coverage

Already excluded from git: `assets/3d_imports/`, `assets/sprites/captures/`, `assets/sprites/final/`, `assets/sprites/presets/`, `exports/`, `debug/`, `*.bak`, temp files. The problem is only the **export preset** bundling everything into the APK.

---

### Task 1: Delete Temp and Backup Files

**Files:**
- Delete: `fix1.txt`
- Delete: `fix_script.py`
- Delete: `run_fix.py`
- Delete: `temp_rest.txt`
- Delete: `scripts/data/legacy_behavior_profile_data.gd.bak`
- Delete: `scripts/data/legacy_behavior_profile_data.gd.uid.bak`
- Delete: `scripts/npc/legacy/ability_executor.gd.bak`
- Delete: `scripts/npc/legacy/ai_state_machine.gd.bak`
- Delete: `scripts/npc/legacy/enemy_ability_controller.gd.bak`
- Delete: `scripts/npc/legacy/enemy_behavior.gd.bak`
- Delete: `scripts/tools/pixel_art_processing.gd.bak`
- Delete: `scripts/tools/sprite_pipeline.gd.bak`
- Delete: `scripts/tools/pixel_art_converter.gd.bak`
- Delete: `scripts/tools/pixel_art_processing.gd.new`

**Step 1: Delete all temp/backup files**

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia/MobileTestia
rm -f fix1.txt fix_script.py run_fix.py temp_rest.txt
rm -f scripts/data/legacy_behavior_profile_data.gd.bak
rm -f scripts/data/legacy_behavior_profile_data.gd.uid.bak
rm -f scripts/npc/legacy/ability_executor.gd.bak
rm -f scripts/npc/legacy/ai_state_machine.gd.bak
rm -f scripts/npc/legacy/enemy_ability_controller.gd.bak
rm -f scripts/npc/legacy/enemy_behavior.gd.bak
rm -f scripts/tools/pixel_art_processing.gd.bak
rm -f scripts/tools/sprite_pipeline.gd.bak
rm -f scripts/tools/pixel_art_converter.gd.bak
rm -f scripts/tools/pixel_art_processing.gd.new
```

**Step 2: Verify deletion**

```bash
find . -name "*.bak" -o -name "*.new" -o -name "fix*.txt" -o -name "temp_*.txt" -o -name "fix_script.py" -o -name "run_fix.py" | head -20
```

Expected: no output (all deleted)

**Step 3: Commit**

```bash
git add -u
git commit -m "chore: remove temp files and legacy .bak backups"
```

---

### Task 2: Move Reference Assets Outside Project

**Files:**
- Move: `tests/2Deffects/` → `../source_assets/reference/2Deffects/`
- Move: `tests/Epic RPG World - Highlands V1.4.1/` → `../source_assets/reference/Epic RPG World - Highlands V1.4.1/`

**Step 1: Create the source_assets directory structure**

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia
mkdir -p source_assets/reference
```

**Step 2: Move test reference assets**

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia
mv "MobileTestia/tests/2Deffects" "source_assets/reference/2Deffects"
mv "MobileTestia/tests/Epic RPG World - Highlands V1.4.1" "source_assets/reference/Epic RPG World - Highlands V1.4.1"
```

**Step 3: Verify the tests/ folder is now empty (or nearly empty)**

```bash
ls -la MobileTestia/tests/
```

Expected: empty or only `.gitkeep`

**Step 4: Clean up empty tests directory and any leftover .import files**

```bash
cd MobileTestia
find tests/ -name "*.import" -delete 2>/dev/null
# Leave the tests/ folder — it may be used for actual test scripts later
```

**Step 5: Commit**

```bash
git add -A tests/
git commit -m "chore: move reference asset packs to source_assets/ (outside project)"
```

Note: The moved files were untracked in git, so this commit only records the deletion of any tracked files in tests/. No git history is lost.

---

### Task 3: Add `.gdignore` Files

These tell Godot to completely skip importing the contents of these directories.

**Files:**
- Create: `databases/vba/.gdignore`
- Create: `databases/docs/.gdignore`
- Create: `docs/.gdignore`
- Create: `debug/.gdignore`

**Step 1: Create `.gdignore` files**

`.gdignore` is an empty file — its mere presence tells Godot to skip the directory.

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia/MobileTestia
touch databases/vba/.gdignore
touch databases/docs/.gdignore
touch docs/.gdignore
touch debug/.gdignore
```

**Step 2: Verify they exist**

```bash
find . -name ".gdignore" -not -path "./.godot/*"
```

Expected:
```
./databases/vba/.gdignore
./databases/docs/.gdignore
./docs/.gdignore
./debug/.gdignore
```

**Step 3: Commit**

```bash
git add databases/vba/.gdignore databases/docs/.gdignore docs/.gdignore debug/.gdignore
git commit -m "chore: add .gdignore to dev-only directories

Prevents Godot from importing VBA sources, documentation,
and debug files. Reduces import cache and editor startup time."
```

---

### Task 4: Fix Export Presets

**Files:**
- Modify: `export_presets.cfg` (3 presets: lines 9-11, 230-232, 495-497)

**Step 1: Update all three export presets**

For each of the 3 presets (`[preset.0]`, `[preset.1]`, `[preset.2]`), change:

```
export_filter="all_resources"
include_filter=""
exclude_filter=""
```

To:

```
export_filter="exclude"
include_filter=""
exclude_filter="assets/3d_imports/*, assets/sprites/captures/*, assets/sprites/final/*, assets/sprites/presets/*, assets/palettes/*, databases/vba/*, databases/docs/*, databases/*.xlsm, docs/*, tests/*, debug/*, scripts/tools/*, scenes/tools/*, *.md, *.bas"
```

This uses `"exclude"` mode which exports everything EXCEPT matched patterns. The patterns exclude:
- Pipeline source assets (3D models, intermediate captures, final sheets, presets, palettes)
- Database source files (VBA macros, Excel workbook, docs)
- Documentation
- Test/debug files
- Pipeline tool scripts and scenes
- Markdown files and VBA source files

**Step 2: Verify the file is valid**

Open `export_presets.cfg` and confirm the 3 preset sections each have the updated filter lines.

**Step 3: Commit**

```bash
git add export_presets.cfg
git commit -m "fix(export): exclude dev-only files from Android/iOS builds

Switch from 'all_resources' to 'exclude' mode with filters for
pipeline assets, VBA sources, docs, tools, and test data.
Drastically reduces APK size."
```

---

### Task 5: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

**Step 1: Add source_assets to gitignore and clean up**

The `.gitignore` already excludes most of the right things. Add the new `source_assets/` directory and the `tests/` reference content patterns:

Add after the existing `debug/` line:

```gitignore
# Reference assets (moved outside project to source_assets/)
# Kept in .gitignore in case someone puts them back
tests/2Deffects/
tests/Epic RPG World*/
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for project reorganization"
```

---

### Task 6: Delete Stale `.import` Files

After adding `.gdignore` files, Godot will no longer import files in those directories. But existing `.import` metadata files will be stale. Clean them up.

**Step 1: Find and delete .import files in gdignored directories**

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia/MobileTestia
find databases/vba/ -name "*.import" -delete 2>/dev/null
find databases/docs/ -name "*.import" -delete 2>/dev/null
find docs/ -name "*.import" -delete 2>/dev/null
find debug/ -name "*.import" -delete 2>/dev/null
```

**Step 2: Verify**

```bash
find databases/vba/ databases/docs/ docs/ debug/ -name "*.import" 2>/dev/null | wc -l
```

Expected: 0

**Step 3: Delete the debug image if still present**

```bash
rm -f debug/1.jpg debug/1.jpg.import
```

**Step 4: Commit if any tracked files were removed**

```bash
git add -u
git status
# Only commit if there are staged changes
git diff --cached --quiet || git commit -m "chore: remove stale .import files from gdignored directories"
```

---

### Task 7: Verify and Document

**Step 1: Count remaining .import files**

```bash
cd C:/Users/mathr/Documents/MobileTesia/mobile-tesia/MobileTestia
find . -name "*.import" -not -path "./.godot/*" | wc -l
```

This should be significantly lower than the original 1,056.

**Step 2: Verify no runtime files were accidentally excluded**

Spot-check that key runtime assets still exist and are not in excluded/ignored directories:

```bash
ls assets/sprites/characters/
ls assets/sprites/weapons/
ls assets/sprites/effects/
ls assets/decorations/
ls assets/icons/
ls databases/exports/
ls resources/tilesets/
ls maps/chunk_tiles/
```

All should list files normally.

**Step 3: Final commit with all cleanup**

```bash
git status
# Commit any remaining tracked changes
git add -A
git diff --cached --quiet || git commit -m "chore: project cleanup complete — dev files excluded from builds"
```
