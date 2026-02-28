# P0: Fix SpriteFrames to Reference External PNGs

## Problem

All SpriteFrames generation code uses `ImageTexture.create_from_image()` which causes `ResourceSaver.save()` to embed raw pixel data as text-encoded PackedByteArray entries. Result: 153 MB player_sprites.tres, 1.4 MB per enemy.

## Affected Scripts (4 total)

1. **`scripts/tools/sprite_pipeline.gd:2906-2944`** — Main pipeline. Has `load()` with fallback to `ImageTexture.create_from_image()`. The fallback triggers when PNGs haven't been imported yet.

2. **`scripts/tools/generate_player_sprites.gd:1340`** — Placeholder generator. Always uses `ImageTexture.create_from_image()`.

3. **`scripts/tools/generate_wolf_sprites.gd:675-683`** — Wolf generator. Extracts individual frame images via `blit_rect` then creates separate ImageTextures per frame (N embedded images instead of 1 atlas reference).

4. **`scripts/tools/apply_final_walk_sprites.gd:139,143,169`** — Walk sprite applier. Always uses `ImageTexture.create_from_image()` for diffuse, normal, and shadow textures.

## Fix

### Core principle

Replace all `ImageTexture.create_from_image(img)` with `load(png_path)` when building SpriteFrames that will be saved to disk. The `load()` function creates an `ext_resource` reference that serializes as a path string (~50 bytes) instead of embedded pixel data (~5 MB).

### Prerequisite: filesystem scan

`load()` returns null if Godot hasn't imported the PNG yet. Before building SpriteFrames, trigger a filesystem scan:

```gdscript
# Force Godot to detect and import new/changed PNGs
if Engine.is_editor_hint():
    EditorInterface.get_resource_filesystem().scan()
    # Wait for scan to complete
    await EditorInterface.get_resource_filesystem().filesystem_changed
```

### Per-script changes

**sprite_pipeline.gd** — Remove fallback, make `load()` failure an error:
```gdscript
var sheet_texture: Texture2D = load(sheet_path)
if sheet_texture == null:
    _append_apply_log("  ERROR: PNG not imported: %s (run filesystem scan)" % sheet_path)
    continue
```

**generate_player_sprites.gd** — Switch from `ImageTexture.create_from_image()` to `load()`:
```gdscript
var sheet_texture: Texture2D = load(sheet_path)
# ... use AtlasTexture referencing sheet_texture
```

**generate_wolf_sprites.gd** — Switch from per-frame ImageTexture to AtlasTexture:
```gdscript
var sheet_texture: Texture2D = load(sheet_path)
for i in range(frame_count):
    var atlas_tex := AtlasTexture.new()
    atlas_tex.atlas = sheet_texture
    atlas_tex.region = Rect2(i * SPRITE_SIZE, 0, SPRITE_SIZE, SPRITE_SIZE)
    frames.add_frame(anim_name, atlas_tex)
```

**apply_final_walk_sprites.gd** — Same pattern as sprite_pipeline fix.

### Expected result

- `player_sprites.tres`: 153 MB → ~50 KB (only ext_resource paths + AtlasTexture regions)
- `starved_wolf_sprites.tres`: 1.4 MB → ~15 KB
- Startup load time: seconds faster (no text parsing of millions of decimal bytes)
- GPU memory: unchanged (same textures loaded, just referenced externally)
- Mobile import pipeline: ETC2/ASTC compression now applies correctly (embedded ImageTextures bypass it)
