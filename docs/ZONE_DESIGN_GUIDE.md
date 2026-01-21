# Zone Design Guide

Creative guidelines for designing zones, locations, and world spaces in MobileTestia.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Zone Types](#zone-types)
3. [Difficulty Progression](#difficulty-progression)
4. [Location Design](#location-design)
5. [Points of Interest](#points-of-interest)
6. [Enemy Placement](#enemy-placement)
7. [Navigation Flow](#navigation-flow)
8. [Atmosphere and Mood](#atmosphere-and-mood)
9. [Placeholder Art Guide](#placeholder-art-guide)
10. [Design Checklist](#design-checklist)

---

## Design Philosophy

### Core Principles

1. **Exploration Rewarded**: Players should discover hidden areas, shortcuts, and secrets
2. **Clear Landmarks**: Easy to navigate without minimaps using visual landmarks
3. **Pacing Variety**: Mix combat areas with safe havens and exploration spaces
4. **Environmental Storytelling**: The world tells stories without words
5. **Mobile-Friendly**: Areas sized for short play sessions (5-15 min per location)

### The 30-Second Rule

Every 30 seconds of travel, the player should encounter:
- A decision point (path split)
- Something interesting (enemy, chest, NPC, landmark)
- A change in scenery

### Breathing Room

Not every space needs enemies. Include:
- Safe paths between dangerous areas
- Scenic overlooks
- Hidden rest spots
- NPC encounter areas

---

## Zone Types

### Outdoor Zones

Open areas with natural terrain, multiple paths, and wide visibility.

| Biome | Terrain | Enemies | Mood |
|-------|---------|---------|------|
| Meadow | Grass, flowers, streams | Wildlife, bandits | Peaceful, tutorial |
| Forest | Trees, undergrowth, clearings | Beasts, ghouls | Mysterious, dangerous |
| Mountain | Rocks, cliffs, narrow paths | Harpies, golems | Harsh, challenging |
| Swamp | Water, mud, dead trees | Undead, insects | Oppressive, toxic |
| Desert | Sand, ruins, oases | Scorpions, mummies | Hot, ancient |

**Outdoor Design Tips:**
- Multiple paths through the zone
- Natural chokepoints for encounters
- High ground for scouting
- Water as natural barriers

### Dungeon Zones

Enclosed spaces with limited paths, atmospheric lighting, and focused encounters.

| Type | Layout | Enemies | Mood |
|------|--------|---------|------|
| Crypt | Corridors, tombs, halls | Undead, spirits | Dark, reverent |
| Cave | Tunnels, caverns, drops | Bats, spiders, trolls | Claustrophobic |
| Ruins | Broken rooms, collapsed halls | Constructs, ghosts | Ancient, decayed |
| Fortress | Rooms, stairs, battlements | Soldiers, bosses | Orderly, hostile |

**Dungeon Design Tips:**
- Clear progression (entrance → depths → boss)
- Shortcuts that unlock after progress
- Resource management (limited healing spots)
- Environmental hazards (traps, collapses)

### Town/Safe Zones

Non-combat areas for services, quests, and story.

| Type | Features | NPCs | Purpose |
|------|----------|------|---------|
| Village | Homes, market, inn | Merchants, questgivers | Hub, services |
| Camp | Tents, campfire, supplies | Allies, refugees | Checkpoint, story |
| Outpost | Walls, guards, storage | Military, scouts | Quest hub, lore |

**Town Design Tips:**
- Central gathering point
- Clear NPC placement (visible from entrance)
- Multiple exits to different zones
- Visual hierarchy (important buildings stand out)

---

## Difficulty Progression

### Level Ranges

| Zone | Min Level | Max Level | Enemy Density |
|------|-----------|-----------|---------------|
| Tutorial | 1 | 3 | Low |
| Early | 3 | 7 | Medium |
| Mid | 7 | 12 | Medium-High |
| Late | 12 | 18 | High |
| Endgame | 18 | 25 | Very High |

### Difficulty Curve Within Zone

```
Zone Entrance
├── Light enemies, easy terrain
├── Teach zone mechanics
│
Middle Section
├── Normal enemy density
├── Optional challenging paths
│
Deep Section
├── Harder enemies, elites
├── Better loot
│
Boss Area
├── Pre-boss challenge
└── Boss encounter
```

### Enemy Density Guidelines

| Density | Enemies per Chunk | Spawn Groups |
|---------|-------------------|--------------|
| Low | 1-2 | Singles |
| Medium | 2-4 | Pairs, occasional group |
| High | 4-6 | Groups of 3-4 |
| Very High | 6-8 | Packs, elites |

---

## Location Design

Locations are named sub-areas within zones. They provide:
- Discovery moments ("Northern Forest discovered!")
- Music/atmosphere changes
- Quest objectives ("Go to the Northern Forest")
- Map markers (future feature)

### Location Sizing

| Size | Chunks | Purpose |
|------|--------|---------|
| Small | 1-2 | Specific POI (shrine, camp) |
| Medium | 3-6 | Named area (forest section) |
| Large | 7-12 | Major region (entire valley) |

### Location Naming

**Do:**
- Use descriptive names: "Whispering Hollow", "Broken Bridge"
- Reference landmarks: "Old Windmill Path"
- Hint at content: "Ghoul Warren", "Bandit Camp"

**Don't:**
- Use generic names: "Forest Area 1", "Cave Section"
- Spoil surprises: "Secret Treasure Room"
- Use confusing directions: "Northeast Southwest Corner"

### Location Boundaries

Locations should have natural boundaries:
- Rivers, cliffs, dense trees
- Changes in terrain type
- Architectural elements (walls, gates)
- Lighting transitions

---

## Points of Interest

### POI Types

| Type | Function | Frequency |
|------|----------|-----------|
| Landmark | Navigation aid | Every 2-3 chunks |
| Chest | Loot reward | 1-2 per location |
| NPC | Quest/dialogue | As needed |
| Secret | Hidden reward | 1 per zone |
| Transition | Zone connection | At zone edges |
| Shrine | Save/heal point | 1-2 per zone |

### Landmark Design

Landmarks should be:
- Visible from distance
- Unique within the zone
- Memorable (distinct silhouette)

**Examples:**
- Twisted ancient tree
- Ruined tower
- Giant skull
- Glowing crystal
- Waterfall
- Stone circle

### Chest Placement

| Visibility | Reward | Placement |
|------------|--------|-----------|
| Obvious | Common | Along main path |
| Semi-hidden | Uncommon | Requires exploration |
| Hidden | Rare | Behind puzzles/secrets |

**Chest Placement Rules:**
- Never behind enemies that respawn (frustrating)
- Clear path to retreat after opening
- Visual hint that something is there

### Secret Areas

Every zone should have 1-2 secrets:
- Hidden paths (behind destructible wall)
- Puzzle doors (levers, switches)
- Platforming challenges (jumping sequence)
- Environmental clues (discolored wall, draft)

---

## Enemy Placement

### Spawn Point Guidelines

**Do:**
- Place spawn points with line-of-sight consideration
- Group enemies of similar type
- Allow approach options (sneak, engage, bypass)
- Consider leash radius (300 default)

**Don't:**
- Spawn enemies directly on paths (feels unfair)
- Create unavoidable enemy gauntlets
- Place ranged enemies with no cover nearby
- Stack too many spawn points together

### Encounter Types

| Type | Description | Use For |
|------|-------------|---------|
| Patrol | Moving along path | Dynamic encounters |
| Guard | Stationary, high alert | Chokepoints |
| Ambush | Hidden until triggered | Surprises |
| Pack | Group that aggros together | Challenge |
| Boss | Unique, arena-based | Climax |

### Enemy Composition

Vary enemy groups for interesting combat:

```
Good: 2 melee + 1 ranged (tactical)
Good: 3 weak + 1 strong (priority targeting)
Good: 1 healer + 2 fighters (kill order puzzle)

Bad: 5 identical enemies (boring)
Bad: All ranged (frustrating)
Bad: Tank + healer + DPS (MMO cliche)
```

### Elite and Miniboss Placement

- Elites: Guard valuable areas or paths
- Minibosses: One per major location
- Bosses: End of dungeon/zone story

---

## Navigation Flow

### Path Hierarchy

```
Main Path (wide, obvious)
├── Side Path (narrower, exploration)
│   └── Hidden Path (secret, reward)
└── Shortcut (unlocks after progress)
```

### Wayfinding Elements

| Element | Purpose |
|---------|---------|
| Light sources | Draw attention, guide path |
| Ground texture | Show wear patterns, trails |
| Vegetation gaps | Indicate passable areas |
| Color variation | Highlight important spots |
| Enemy presence | Indicate challenge ahead |

### Dead Ends

Dead ends should ALWAYS have:
- A reward (chest, resource)
- OR lore/story element
- OR visual payoff (scenic view)

Never create empty dead ends.

### Loop Design

Good zones loop back on themselves:

```
Entrance
    ↓
Path Split ←───────┐
    ↓              │
Area A → Area B → Shortcut
    ↓
Boss Area
```

---

## Atmosphere and Mood

### Audio Zones

| Zone Feel | Music Style | Ambient |
|-----------|-------------|---------|
| Peaceful | Calm, melodic | Birds, wind |
| Tense | Minimal, drone | Silence, distant sounds |
| Dangerous | Rhythmic, urgent | Growls, creaking |
| Mysterious | Ethereal, sparse | Whispers, echoes |
| Epic | Orchestral, building | Rumbles, choir |

### Lighting Guidelines

| Time/Mood | Lighting | Shadows |
|-----------|----------|---------|
| Day/Safe | Bright, warm | Soft |
| Dusk/Tension | Orange, dim | Long |
| Night/Danger | Blue, dark | Sharp |
| Underground | Point lights only | Deep |
| Magical | Colored, glowing | Unusual |

### Environmental Storytelling

Tell stories through the environment:
- Abandoned campfire (travelers were here)
- Claw marks on trees (beast territory)
- Crumbling statue (ancient civilization)
- Fresh graves (recent tragedy)
- Scattered coins (robbery)

---

## Placeholder Art Guide

Until final art is created, use colored placeholders that communicate function.

### Terrain Colors

| Terrain | Hex Color | RGB |
|---------|-----------|-----|
| Grass | #3d6e3d | 61, 110, 61 |
| Dirt | #6b5344 | 107, 83, 68 |
| Stone | #666673 | 102, 102, 115 |
| Water | #334d99 | 51, 77, 153 |
| Wall | #4d4033 | 77, 64, 51 |
| Sand | #c4a35a | 196, 163, 90 |
| Snow | #e0e8f0 | 224, 232, 240 |
| Void | #1a1a1a | 26, 26, 26 |

### Entity Colors

| Entity | Hex Color | Shape |
|--------|-----------|-------|
| Player Spawn | #00ff00 | Circle |
| Enemy Spawn | #ff0000 | Circle |
| Chest | #ffcc00 | Square |
| NPC | #00ccff | Circle |
| Transition | #ff00ff | Rectangle |
| Location Area | #ffffff30 | Rectangle (transparent) |

### Collision Visualization

| Type | Color | Use |
|------|-------|-----|
| Solid | #ff0000 | Walls, obstacles |
| Water | #0000ff | Impassable water |
| Hazard | #ff6600 | Damage zones |
| Trigger | #00ff00 | Interaction areas |

---

## Design Checklist

### Before Building

- [ ] Define zone purpose (story, gameplay, hub)
- [ ] Set level range and difficulty
- [ ] List key locations within zone
- [ ] Identify boss/miniboss encounters
- [ ] Plan connections to other zones

### During Building

- [ ] Main path is clear and followable
- [ ] Side paths have rewards
- [ ] Enemy density matches difficulty
- [ ] Landmarks visible from main path
- [ ] Locations have natural boundaries
- [ ] Shortcuts loop back to earlier areas

### After Building

- [ ] Walk through as new player (is it confusing?)
- [ ] Check dead ends have purpose
- [ ] Verify spawn points have proper leash room
- [ ] Test chunk boundaries (no awkward loading)
- [ ] Confirm all POIs are reachable
- [ ] Validate zone transitions work

### Polish Pass

- [ ] Add environmental details
- [ ] Vary enemy compositions
- [ ] Hide 1-2 secrets
- [ ] Review pacing (combat → rest → combat)
- [ ] Test on target device (mobile)

---

## Quick Reference: Zone Planning Template

```
Zone: [Name]
ID: zone_[id]
Type: [outdoor/dungeon/town]
Level Range: [min] - [max]
Connected To: [zone_ids]

Locations:
1. [Location Name] - [purpose]
2. [Location Name] - [purpose]
3. ...

Key Encounters:
- [Miniboss/Boss name] at [location]
- [Special encounter] at [location]

Unique Features:
- [Environmental gimmick]
- [Special mechanic]
- [Secret area hint]

Music/Atmosphere:
- Main: [track_id]
- Location overrides: [location: track]

Story Beats:
- [What happens here narratively]
```

---

## Related Documentation

- **LDTK_MAP_REFERENCE.md** - Technical reference for implementing zones
- **ENEMY_REFERENCE.md** - Enemy behavior and AI
- **ABILITY_SYSTEM_REFERENCE.md** - Combat abilities
