# MobileTestia Performance Audit — 2026-02-28

## Summary

Full codebase audit focused on load time, runtime performance, and memory usage for mobile (Android/iOS). The game currently takes too long to load despite minimal content, primarily due to embedded pixel data in resource files and per-frame CPU work that should be pre-computed.

---

## Critical Findings

### P0 — SpriteFrames embed raw pixel data (153 MB player_sprites.tres)

**Files:** `resources/player_sprites.tres`, `resources/enemies/starved_wolf_sprites.tres`

**Problem:** SpriteFrames `.tres` files contain full spritesheet pixel data as text-encoded `PackedByteArray` entries instead of referencing external PNG files. The player resource alone is 153 MB (33 embedded images, each 3-9 million characters of comma-separated decimal byte values). Enemy sprites follow the same pattern (1.4 MB per enemy type, will compound).

**Root cause — two generation pipelines:**
1. `scripts/tools/generate_player_sprites.gd:1340` — Always uses `ImageTexture.create_from_image(sheet_image)` which embeds pixel data when saved via `ResourceSaver.save()`.
2. `scripts/tools/sprite_pipeline.gd:2907-2910` — Tries `load(sheet_path)` first (creates ext_resource reference), but falls back to `ImageTexture.create_from_image()` when Godot hasn't imported the PNG yet. Normal maps are the biggest offenders (~9M chars each).

**Impact:** Player scene (`player.tscn:5`) directly references this resource. At startup, Godot parses 153 MB of text, reconstructs 33 images from decimal bytes, and uploads to VRAM — all synchronously before the first frame renders. On mobile devices, this causes multi-second load times and excessive memory pressure.

**Fix:** See `P0_SPRITEFRAMES_FIX.md`

---

### P1 — Per-frame GPU→CPU pixel scanning for weapon anchors

**File:** `scripts/combat/character_visuals.gd:308,514-554`

**Problem:** `_find_weapon_anchors()` runs every frame in `_process()`. It calls `tex.get_image()` (GPU→CPU readback) then iterates every pixel of the current body sprite frame to find magenta/cyan anchor markers. This is O(width × height) per frame per visible character.

**Impact:** On a 64×64 sprite, that's 4,096 `get_pixel()` calls per frame per character. With player + 5 enemies visible = 24,576 pixel reads per frame at 60 FPS = ~1.47 million pixel reads per second. The GPU→CPU readback alone is a pipeline stall on mobile GPUs.

**The data is deterministic:** Anchor positions for a given (animation, frame_index) pair never change — they're painted into the sprites at build time.

**Fix:** See `P1_ANCHOR_CACHE_FIX.md`

---

### P2 — Synchronous database loading blocks startup

**File:** `autoloads/database_loader.gd:91-149`

**Problem:** All 37 JSON databases are loaded and parsed synchronously in `_ready()`. Total data is ~250 KB but the sequential FileAccess.open + JSON.parse × 37 adds measurable startup time.

**Fix (future):** Split into essential (items, abilities, enemies) loaded at startup vs deferred (quests, dialogues, lore) loaded on first zone entry. Or use `ResourceLoader.load_threaded()`.

---

### P3 — Weapon textures generated at runtime via per-pixel rotation

**File:** `scripts/combat/weapon_texture_loader.gd:89-147`

**Problem:** Every weapon equip triggers: alpha mask per-pixel loop + two `Image.duplicate()` + `rotate_90()` + `rotate_180()` + three `ImageTexture.create_from_image()` calls. No global cache — equipping the same weapon twice repeats all work.

**Fix (future):** Pre-bake direction variants as separate PNGs in the weapon pipeline tool. Cache by weapon sprite_id at runtime.

---

### P4 — Effect spritesheet splitting uncached

**File:** `scripts/combat/character_visuals.gd:815-883`

**Problem:** Every effect spawn splits a spritesheet into individual frame Images via `blit_rect` + optional per-pixel alpha mask loop + creates N `ImageTexture` objects. No caching across spawns of the same effect.

**Fix (future):** Cache built `SpriteFrames` by (effect_id, direction) key. Reuse across spawns.

---

### P5 — Synchronous chunk entity spawning

**File:** `autoloads/chunk_manager.gd:389-450`

**Problem:** `load_chunk()` spawns all entities in a chunk synchronously. Combined with `_process()` calling `update_chunks()` every frame, chunk boundary crossings cause frame stutter.

**Fix (future):** Spread entity spawning across multiple frames. Use `ResourceLoader.load_threaded()` for scene loading.

---

### P6 — Weapon alpha masks composited at runtime

**File:** `scripts/combat/character_visuals.gd:641-684`

**Problem:** During ability animations with alpha masks: image duplicate + per-pixel alpha multiply + `rotate_90()` + GPU texture upload per unique frame. Cached per frame_index but first-time cost is high mid-combat.

**Fix (future):** Pre-composite masked weapon variants at export time in the Attack Composer. Store as pre-baked textures.

---

## Other Observations

- **No async loading:** Zero uses of `ResourceLoader.load_threaded()` in the entire codebase.
- **No loading screen:** Game transitions directly from init to gameplay.
- **25 autoloads:** All initialize simultaneously at engine startup.
- **Import cache:** 1.1 GB in `.godot/imported/` (1,517 files).
- **Texture compression:** Project enables ETC2/ASTC (`import_etc2_astc=true`) which is correct for mobile, but the embedded ImageTextures bypass this pipeline entirely.
- **Enemy sprites:** `starved_wolf_sprites.tres` uses the same embedded-pixel-data pattern. Every new enemy type will add 1-2+ MB of embedded data.

---

## Architecture Principle

> **Never cross the CPU/GPU boundary at runtime for deterministic data.**

Anchor positions, alpha-masked weapon variants, direction rotations — all are deterministic functions of the source art. They should be pre-computed once in the pipeline tools and stored as metadata or pre-baked PNGs, not recomputed every frame or every equip event.
