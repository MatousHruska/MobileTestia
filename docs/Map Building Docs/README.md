# Map Building Implementation Phases

This folder contains implementation prompts for building the chunk-based map system in MobileTestia. Each phase is designed to be completed in a single Claude session.

---

## Overview

The map building system uses a chunk-based loading approach for large explorable zones. Key features:
- **16x16 pixel tiles** for detailed terrain
- **64x64 tile chunks** (1024x1024 px) for performance
- **5x5 loading radius** (25 chunks loaded around player)
- **LDtk** as external map editor
- **Combat/leash locks** prevent chunk unload during active gameplay
- **LootManager** preserves dropped items across chunk loads

---

## Phase Summary

| Phase | Focus | Key Deliverables |
|-------|-------|------------------|
| **Phase 1** | Foundation | Database schema, autoload stubs |
| **Phase 2** | Chunk Core | Loading/unloading, combat/leash locks |
| **Phase 3** | Loot System | LootManager, drop persistence |
| **Phase 4** | LDtk Integration | Importer, tileset, tile rendering |
| **Phase 5** | Entities | Spawn points, transitions, chests |
| **Phase 6** | Testing & Polish | Test zone, debug tools, documentation |

---

## Phase Details

### [Phase 1: Foundation & Database](MapBuildingPhase1.md)
- VBA files for chunks and terrain types
- ChunkManager and LootManager stubs
- DatabaseLoader extensions
- Placeholder database entries

### [Phase 2: Chunk System Core](MapBuildingPhase2.md)
- Chunk coordinate calculations
- 5x5 loading radius management
- Combat lock (enemies targeting player)
- Leash lock (enemies returning home)
- Enemy temp state storage

### [Phase 3: Loot Manager System](MapBuildingPhase3.md)
- Drop registration and tracking
- Chunk load/unload handling
- Visual node recreation
- Timeout system
- Saveable interface (clears on save)

### [Phase 4: LDtk Integration](MapBuildingPhase4.md)
- LDtk project setup
- Import script for JSON conversion
- Placeholder tileset generation
- TileMap creation from chunk data

### [Phase 5: Entity Integration](MapBuildingPhase5.md)
- Spawn point creation from LDtk data
- Enemy state save/restore
- Chest and transition spawning
- Location area handling

### [Phase 6: Testing & Polish](MapBuildingPhase6.md)
- Complete test zone (4x4 chunks)
- Debug overlay and commands
- Performance testing
- Edge case handling
- Final documentation

---

## Recommended Order

Complete phases in order (1 → 6). Each phase builds on the previous:

```
Phase 1 ──→ Phase 2 ──→ Phase 3
   │           │           │
   │           │           ↓
   │           │     Loot works with chunks
   │           ↓
   │     Chunks load/unload safely
   ↓
Database & stubs ready

Phase 4 ──→ Phase 5 ──→ Phase 6
   │           │           │
   │           │           ↓
   │           │     Production ready
   │           ↓
   │     Enemies & entities work
   ↓
Maps import from LDtk
```

---

## Quick Start for Each Session

When starting a new session, provide:

1. **System prompt** with database workflow rules (from main session notes)
2. **The phase prompt** (contents of that phase's .md file)
3. **Context**: "Previous phases completed, now working on Phase X"

Example:
```
I want to continue implementing the map building system.
We've completed Phases 1-3.
Please read MapBuildingPhase4.md and implement LDtk integration.
```

---

## Reference Documentation

- `docs/MAP_BUILDING_REFERENCE.md` - Full technical specification
- `docs/ZONE_DESIGN_GUIDE.md` - Design guidelines
- `docs/QUICK_REFERENCE.md` - Quick lookup (Map Building section)

---

## Dependencies

### Required Before Phase 1
- Excel database system working
- Existing zone/location system
- Spawn point system
- Persistence system

### External Tools
- **LDtk** (https://ldtk.io/) - Free level editor, install before Phase 4

---

## Notes

- Each phase can be done in 1-2 sessions
- Test after each phase before proceeding
- Phase 6 is optional if you want to build your own test zone differently
- Debug tools from Phase 6 are highly recommended for development

---

## Estimated Effort

| Phase | Complexity | Estimated Time |
|-------|------------|----------------|
| Phase 1 | Low | 1 session |
| Phase 2 | High | 1-2 sessions |
| Phase 3 | Medium | 1 session |
| Phase 4 | High | 1-2 sessions |
| Phase 5 | Medium | 1 session |
| Phase 6 | Medium | 1-2 sessions |

**Total: 6-10 sessions** for complete implementation
