# Terrain System + Snow Footprints — Design

## Goal

Wire up terrain types from LDtk through the chunk system so any game system can query "what terrain is the player standing on?", then use that to spawn fading footprint decals and snow puff particles when walking on snow (extensible to sand/dirt).

## Architecture

### Part 1: Terrain Layer Infrastructure

**LDtk:** Add a `ground` IntGrid layer to `MobileTestia.ldtk`. Values map to the existing `terrain_types.json` database:

| Value | Terrain ID |
|-------|-----------|
| 1 | terrain_grass |
| 2 | terrain_dirt |
| 3 | terrain_stone |
| 4 | terrain_water |
| 5 | terrain_wall |
| 6 | terrain_sand |
| 7 | terrain_snow |
| 8 | terrain_pit |
| 9 | terrain_lava |

**Importer:** New `_extract_ground_tiles()` function in `ldtk_importer.gd`. Reads the IntGrid, maps int values to terrain IDs, exports per-chunk as:

```json
{
  "ground": [
    {"x": 0, "y": 0, "terrain_id": "terrain_snow"},
    {"x": 1, "y": 0, "terrain_id": "terrain_grass"}
  ]
}
```

Only non-empty tiles are stored (sparse format, same as collision).

**Runtime query:** `get_terrain_at(world_pos: Vector2) -> String` on ChunkManager. Converts world position to chunk coords + local tile coords, looks up the terrain ID. Returns `""` if no terrain data at that position.

Chunk tile data is already loaded into `ChunkData.tile_data` — the ground array gets parsed into a Dictionary keyed by `Vector2i(x, y)` for O(1) lookup.

### Part 2: Footprint Decals

**FootprintManager** — new autoload singleton.

**Step detection:** Tracks cumulative player movement distance. Every ~16px (one tile width), checks terrain at player's feet via `ChunkManager.get_terrain_at()`. If terrain has footprints enabled, spawns a decal.

**Decal properties:**
- Small `Sprite2D` with a pre-made placeholder footprint texture
- Positioned at player's foot (node origin, since sprite is offset to y=-20)
- Rotated to match last movement direction
- Alternates left/right foot offset (slight x offset from center)
- Fades out over ~8 seconds via tween on `modulate.a`, then `queue_free()`
- Tinted per terrain (`footprint_tint` from database)
- Added to the world node (not the player), so they stay in place

**Snow puff particles:**
- Small `GPUParticles2D` burst at each step on snow
- 3-5 white particles, ~0.5s lifetime, slight upward drift and spread
- One-shot, auto-frees after emission completes
- Follows existing particle patterns from `ZoneParticleManager`

### Part 3: Database Changes

Add two fields to `terrain_types.json` (via `TerrainDatabase.bas`):
- `has_footprints: bool` — whether this terrain leaves footprint marks
- `footprint_tint: String` — hex color for the footprint decal (e.g., `"#FFFFFF"` for snow, `"#C8B496"` for sand)

Terrains with footprints: snow, sand, dirt. Others: no footprints.

### Part 4: Not Building Now

- Footstep sounds (no audio assets)
- Movement speed modifiers (no slow-walk animations)
- Navigation restrictions per terrain (wire up later via `NavigationGrid`)
- Spawn restrictions (already has `can_spawn_on`, wire up later)

All become trivial once `get_terrain_at()` exists.

## Key Files

| File | Change |
|------|--------|
| `maps/MobileTestia.ldtk` | Add `ground` IntGrid layer (manual in LDtk editor) |
| `ldtk_importer.gd` | Add `_extract_ground_tiles()`, include in chunk export |
| `autoloads/chunk_manager.gd` | Parse ground data, add `get_terrain_at()` |
| `databases/vba/TerrainDatabase.bas` | Add `has_footprints`, `footprint_tint` columns |
| `autoloads/footprint_manager.gd` | New autoload — step detection, decal spawning, particles |
| `assets/particles/` or inline | Snow puff particle config |
| `assets/effects/footprint.png` | Placeholder footprint texture |
