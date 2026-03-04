# Project Cleanup & Organization Design

## Problem

The Godot project folder contains ~520 MB of files, but only ~10-15 MB is needed at runtime. Large source assets (3D models, intermediate sprite captures, reference art packs) are physically present in the project tree, causing:

- Godot imports all of them (~1,056 .import files, ~1.3 GB cache)
- `export_filter="all_resources"` with empty `exclude_filter` bundles everything into the APK (~88 MB)
- Slow editor startup and large Android builds
- Dev-only files (VBA sources, docs, debug images) included in exports

## Solution

### Revised Approach: Keep Pipeline Assets In-Project

The pipeline tools (`sprite_pipeline.gd`, `decoration_pipeline.gd`, `effect_pipeline.gd`) use `load("res://assets/3d_imports/model.fbx")` which requires Godot to have imported the FBX files. Moving them outside the project would break all pipeline tools. Since these files are **already gitignored**, they don't bloat the repository — the fix is the **export exclude filter**.

### 1. Move Reference Assets Outside Project

Only non-pipeline reference materials move to a sibling folder:

```
mobile-tesia/
  MobileTestia/          # Godot project
  source_assets/         # Outside Godot's view
    reference/           # From tests/ (Epic RPG World, 2Deffects)
```

### 2. Add `.gdignore` Files

Directories that should not be imported by Godot:

| Directory | Reason |
|---|---|
| `databases/vba/` | VBA macro source files |
| `databases/docs/` | Database documentation |
| `docs/` | Reference documentation |
| `debug/` | Debug screenshots |

### 3. Fix Export Presets

For all 3 export presets in `export_presets.cfg`:

- Change `export_filter` from `"all_resources"` to `"exclude"`
- Set `exclude_filter` to exclude: pipeline assets, VBA sources, docs, tools, tests, debug, markdown, `.bas` files

### 4. Delete Temp/Leftover Files

- Root temp files: `fix1.txt`, `fix_script.py`, `run_fix.py`, `temp_rest.txt`
- All `.bak` backup files in `scripts/`
- `.new` files in `scripts/tools/`
- Debug image: `debug/1.jpg`

### 5. Clean Up Stale `.import` Files

Remove `.import` metadata from newly-gdignored directories.

## What Stays In-Project (and why)

| Directory | Reason to Keep |
|---|---|
| `assets/3d_imports/` | Pipeline tools require `load()` via `res://` (already gitignored) |
| `assets/sprites/captures/` | Pipeline intermediate (already gitignored) |
| `assets/sprites/final/` | Pipeline output (already gitignored) |
| `assets/sprites/presets/` | Pipeline config (already gitignored) |
| `scripts/tools/` | Editor tools, useful during development (small ~300 KB) |
| `databases/vba/` | Version-controlled source of truth for data schema |

## Expected Impact

| Metric | Before | After |
|---|---|---|
| APK size | ~88 MB | ~10-15 MB |
| Files Godot imports | 1,056 | reduced (gdignored dirs excluded) |
| Export includes dev files | yes | no |
| Editor startup | slow (imports FBX etc.) | faster |
