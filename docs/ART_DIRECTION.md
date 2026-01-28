# MOBILETESTIA ART DIRECTION DOCUMENT

> **Reference Style**: Hyper Light Drifter
> **Core Tech**: UV Lookup Animation System
> **Target**: Mobile (2022+ smartphones)

---

## TABLE OF CONTENTS

1. [Visual Identity](#visual-identity)
2. [Technical Specifications](#technical-specifications)
3. [Character Design](#character-design)
4. [Animation Philosophy](#animation-philosophy)
5. [World & Environment](#world--environment)
6. [Lighting System](#lighting-system)
7. [Effects & Feedback](#effects--feedback)
8. [UI Visual Language](#ui-visual-language)
9. [Items & Loot](#items--loot)
10. [Color Palette](#color-palette)
11. [Weather & Atmosphere](#weather--atmosphere)
12. [Implementation Priority](#implementation-priority)

---

## VISUAL IDENTITY

### Core Aesthetic
- **Style**: HLD-inspired pixel art with 3/4 oblique perspective
- **Mood**: Atmospheric, mysterious, vital
- **Differentiator**: Full dialogue/text systems (unlike HLD's wordless storytelling)

### Key Influences
| Element | Reference |
|---------|-----------|
| Character style | Hyper Light Drifter NPCs |
| Environment | HLD + mountain/snow atmosphere |
| Combat feel | HLD responsiveness + strong impacts |
| Lighting | Dynamic normal-mapped pixel art |
| Particles | Heavy, atmospheric |

### What We Are NOT
- Not chibi/cute (Enter the Gungeon)
- Not hyper-realistic
- Not anime-exaggerated
- Not wordless (we have full text/dialogue systems)

---

## TECHNICAL SPECIFICATIONS

### Display
| Spec | Value | Notes |
|------|-------|-------|
| Native Resolution | 480×270 | 16:9, scales to 1080p (4×) |
| Scaling | Integer nearest-neighbor | Crisp pixels |
| Target FPS | 60 | Mobile 2022+ |

### Sprite Sizes
| Entity | Size | Notes |
|--------|------|-------|
| Player | 32×32 | Female protagonist |
| Humanoid NPCs | 32×32 | Consistent with player |
| Standard Enemies | 24×24 to 32×32 | Based on type |
| Large Enemies | 48×48 | Mini-bosses, elites |
| Bosses | 64×64+ | Screen presence |
| Tiles | 16×16 | Standard grid |
| World Icons | 16×16 | Items on ground |
| UI Icons | 32×32 | Abilities, inventory |
| Portraits | 64×64 | NPC dialogue |

### UV Color-Lookup System
```
┌─────────────────────────────────────────────────────────────┐
│                    RENDERING ARCHITECTURE                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  COLOR-LOOKUP SHADER WORKFLOW:                               │
│                                                              │
│  1. Animation Sprite → Contains unique colors per pixel      │
│  2. UV Map → Same unique colors at same positions (32x32)    │
│  3. Shader searches UV map for matching color                │
│  4. Found position → samples Lookup/Skin texture at that UV  │
│                                                              │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐           │
│  │ Animation│ RGB  │  UV Map  │ pos  │  Lookup  │           │
│  │  Frame   │ ───► │ (search) │ ───► │ Texture  │ → Output  │
│  └──────────┘      └──────────┘      └──────────┘           │
│                                                              │
│  PLAYER CHARACTER (Equipment Shader)                         │
│  ├── Animation Sheet (colored silhouettes)                   │
│  ├── UV Map (unique color per pixel, 32x32)                  │
│  ├── Base Skin (fallback for all body parts)                 │
│  └── Equipment Slots (sector-based):                         │
│      ├── Head Skin (top sector: Y < 0.25)                    │
│      ├── Body Skin (middle-left: Y 0.25-0.75, X < 0.5)       │
│      ├── Hands Skin (middle-right: Y 0.25-0.75, X >= 0.5)    │
│      └── Feet Skin (bottom sector: Y >= 0.75)                │
│                                                              │
│  ENEMIES / NPCS (Single Skin Shader)                         │
│  ├── Animation Sheet (unique colors matching UV map)         │
│  ├── UV Map (shared with player or unique per type)          │
│  └── Single Lookup Texture (swappable for variants)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**How Color-Lookup Works:**
1. Each pixel in the animation sprite has a unique RGB color
2. The UV Map texture has the same colors at corresponding positions
3. The shader scans the UV map to find where the color appears
4. That found position becomes the UV coordinate to sample the skin

**Benefits:**
- Full RGB available for visual art workflow (no channel encoding)
- Pixel-perfect mapping between animation and skin textures
- Easy to create variants by swapping lookup textures
- Equipment slots determined by position, not color channels

### Weapon Categories
| Category | Examples | Animation Set |
|----------|----------|---------------|
| 1-Handed | Sword, axe, mace, dagger | attack_1h |
| 2-Handed | Greatsword, staff, polearm | attack_2h |
| Bow | All ranged bows | attack_bow |

---

## CHARACTER DESIGN

### Protagonist
- **Identity**: Young woman
- **Vibe**: Vital, capable, attractive (not sexualized)
- **Silhouette**: Distinct, readable at small sizes
- **Face**: HLD style - no detailed features (mysterious)

### Proportions
- **Style**: Balanced (HLD approach)
- **Not** chibi, not hyper-realistic
- Head-to-body ratio: ~1:3 to 1:4
- Clear silhouette even at 32×32

### Design Principles
```
DO:
├── Clear, readable shapes
├── Distinctive silhouettes per character type
├── Color as primary identifier for variants
├── Clothing/armor that reads at small scale
└── Sense of vitality and movement even in static poses

DON'T:
├── Overly busy details that become noise
├── Realistic facial features (too small to read)
├── Sexualized proportions or poses
├── Similar silhouettes for different enemy types
└── Details that disappear at native resolution
```

### Silhouette Strategy
| Level | Requirement |
|-------|-------------|
| Enemy Types | MUST be distinct (wolf ≠ skeleton ≠ slime) |
| Enemy Variants | CAN be similar (color differentiates) |
| Player vs NPCs | Player should stand out |
| Bosses | Significantly larger, imposing shapes |

---

## ANIMATION PHILOSOPHY

### Core Approach: "Pixel Impressionism"
- Keyframes at apex of action
- Let player's brain interpolate
- Fewer frames, more impact
- Quality over quantity

### Frame Counts
| Animation | Frames | FPS | Notes |
|-----------|--------|-----|-------|
| Idle | 4-6 | 6-8 | Subtle breathing, occasional fidget |
| Walk | 4-6 | 10-12 | Smooth cycle |
| Attack (player) | 3-4 | 12-15 | Quick, responsive |
| Attack (enemy) | 4-6 | 10-12 | More wind-up (telegraph for dodging) |
| Dodge/Dash | 2-3 | 15+ | Snappy |
| Hit React | 2-3 | 12 | Clear feedback |
| Death | 4-8 | 8-10 | Varies by enemy type |

### Directions
- 4-directional: Down, Up, Left, Right
- Left/Right can be mirrored where appropriate

### Movement Feel
| Entity | Feel | Reasoning |
|--------|------|-----------|
| Player | Snappy, responsive (HLD) | Player agency, feels good |
| Player attacks | Quick with strong impact | Satisfying combat |
| Enemy movement | Can vary by type | Personality |
| Enemy attacks | Noticeable wind-up | Dodge-focused combat, readability |

### Death Animations (Per Enemy Type)
| Enemy Type | Death Style |
|------------|-------------|
| Beasts (wolves) | Collapse, brief lay |
| Undead (skeletons) | Crumble apart |
| Slimes/Oozes | Splatter, dissolve |
| Humanoids | Dramatic fall |
| Bosses | Extended, cinematic |

### Idle Behavior
- **Primary**: Subtle breathing animation
- **Extended idle**: Occasional fidgets (shift weight, look around)
- **Future**: Environmental reactions (wind, etc.) - LOW PRIORITY

---

## WORLD & ENVIRONMENT

### Perspective
- **3/4 Oblique** (top-down with front faces visible)
- Ground seen from above
- Vertical surfaces show front face
- Y-sorting for depth

### Tile Density
- **Moderate** (HLD balance)
- Detailed but readable
- Negative space is intentional
- Key elements stand out

### Environmental Storytelling
- **Moderate to Heavy**
- Ruins tell history
- Corpses hint at dangers
- Visual narrative rewards exploration
- But NOT cluttered - curated details

### Interactivity
| Element | Behavior | Priority |
|---------|----------|----------|
| Grass | Sway when walked through | Medium |
| Crates/Barrels | Breakable | High |
| Torches | Flicker, cast light | High |
| Snow | Footprints, displacement | High (thematic) |
| Water | Minimal (not focus) | Low |

### Snow & Mountain Atmosphere
> **THIS IS A KEY VISUAL IDENTITY ELEMENT**

- Snow-covered peaks are primary environment
- Blowing snow particles
- Footprints in snow
- Frost effects on edges
- Cold color palette (blues, whites, cyans)
- Warm light contrast (torches, shelter)

---

## LIGHTING SYSTEM

### Approach: Dynamic with Normal Maps
```
┌─────────────────────────────────────────────────────────────┐
│                    LIGHTING ARCHITECTURE                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  BASE LAYER                                                  │
│  └── Sprites with normal maps for depth response            │
│                                                              │
│  LIGHT SOURCES                                               │
│  ├── Point Lights (torches, fires, magic)                   │
│  ├── Directional (sun/moon for outdoor zones)               │
│  └── Area Lights (glowing objects, portals)                 │
│                                                              │
│  POST-PROCESSING                                             │
│  ├── Bloom (on bright pixels, especially cyans/magentas)    │
│  ├── Vignette (subtle, focus attention)                     │
│  └── Zone color grading (optional per-area tint)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Light Source Colors
| Source | Color | Hex Reference |
|--------|-------|---------------|
| Torches/Fire | Warm orange | #FF9933, #FFCC66 |
| Magic (general) | Cyan | #00FFFF, #40E0D0 |
| Fire magic | Orange-red | #FF4400 |
| Ice magic | Light blue | #88DDFF |
| Lightning | Yellow-white | #FFFFAA |
| Poison | Sickly green | #88FF44 |
| Arcane | Purple | #AA44FF |
| Corruption | Magenta | #FF00AA |
| Moonlight | Blue-silver | #AABBDD |
| Shelter/Warmth | Golden | #FFDD88 |

### Day/Night
- **Not a cycle** - zones have fixed time
- Some zones default to night
- Lighting is per-zone atmospheric choice

---

## EFFECTS & FEEDBACK

### Hit Feedback: JUICY
| Element | Implementation |
|---------|----------------|
| Hit flash | White flash on damaged entity (1-2 frames) |
| Hitstop | Brief freeze (2-4 frames) on significant hits |
| Screen shake | On heavy hits, scales with damage |
| Particles | Blood/sparks on impact |
| Knockback | Visual and mechanical |
| Sound | Crunchy, satisfying (audio note) |

### Particle Philosophy: HEAVY
- Attacks have trails
- Magic has persistent particles
- Ambient particles everywhere (dust, snow, embers)
- Status effects are visually obvious
- Environment feels alive

### Screen Effects
| Effect | Usage |
|--------|-------|
| Screen shake | Heavy hits, explosions, boss attacks |
| Hitstop/Freeze | Significant damage moments |
| Chromatic aberration | Optional: low health, corruption zones |
| Flash | Critical hits |
| Vignette pulse | Damage taken |

### Blood & Gore: Minimal to Moderate
- Red particles on hit
- Brief blood spatters
- Fades relatively quickly
- Not persistent pools
- Not graphic dismemberment

---

## UI VISUAL LANGUAGE

### Health Bars
- **Style**: Floating above entities
- **Visibility**: Only when damaged (already implemented)
- **Design**: Clean, matches HLD aesthetic

### Damage Numbers
| Aspect | Style |
|--------|-------|
| Font | Stylized pixel font |
| Size | Varies with damage amount |
| Color | By damage type |
| Crits | Larger, possible bounce/shake effect |
| Animation | Float up, fade out |

### Ability Cooldowns
- **Primary**: Radial fill (pie chart depleting)
- **Out of mana**: Blue tint/desaturation
- **Ready**: Subtle pulse or glow

### General UI Principles
- Pixel art style matching game (not modern/flat)
- Corners of screen, center is gameplay
- Minimal but informative
- Full text support (unlike HLD)
- Frames/borders from UIThemeDatabase

---

## ITEMS & LOOT

### Loot Drop Visibility (Scales with Rarity)
| Rarity | Visual Treatment |
|--------|------------------|
| Common | Simple sprite on ground |
| Uncommon | Subtle glow |
| Rare | Brighter glow + gentle bob |
| Epic | Strong glow + particles |
| Legendary | Light beam + heavy particles + bob |

### Rarity Visual Language
- **Primary indicator**: Glow color/intensity
- Color coding (already in ui_theme.json):
  - Common: Gray/White
  - Uncommon: Green
  - Rare: Blue
  - Epic: Purple
  - Legendary: Orange/Gold

### Item Icons
- 16×16 for world drops
- 32×32 for inventory/UI
- Clear silhouette
- Rarity indicated by background/border glow

---

## COLOR PALETTE

### Philosophy
- **Guided, not strict** - 90% from palette, 10% exceptions allowed
- Zone-specific sub-palettes
- Signature accents consistent throughout (cyan, magenta)

### Master Palette (32 Colors Reference)
```
BLACKS & GRAYS (4)
├── Near Black:     #0A0A12
├── Dark Gray:      #2A2A3A
├── Mid Gray:       #5A5A6A
└── Light Gray:     #9A9AAA

BROWNS & SKIN (4)
├── Dark Brown:     #3A2211
├── Brown:          #6A4422
├── Tan:            #AA7744
└── Skin Light:     #DDAA88

REDS (4)
├── Dark Red:       #661122
├── Blood Red:      #AA2233
├── Red:            #DD4455
└── Light Red:      #FF8899

ORANGES (4)
├── Dark Orange:    #884411
├── Orange:         #DD7722
├── Light Orange:   #FFAA44
└── Gold:           #FFDD66

GREENS (4)
├── Dark Green:     #113322
├── Forest:         #227744
├── Green:          #44AA66
└── Light Green:    #88DD99

BLUES (4)
├── Deep Blue:      #111133
├── Dark Blue:      #223366
├── Blue:           #4477AA
└── Light Blue:     #88BBDD

CYANS (Signature) (4)
├── Dark Cyan:      #115555
├── Teal:           #228888
├── Cyan:           #44DDDD
└── Bright Cyan:    #88FFFF

MAGENTAS (Signature) (4)
├── Dark Magenta:   #551144
├── Magenta:        #AA2288
├── Pink:           #DD55AA
└── Light Pink:     #FF99CC
```

### Zone Sub-Palettes
| Zone | Primary Colors | Accent |
|------|----------------|--------|
| Mountain Peaks | Blues, whites, grays | Warm orange (shelter) |
| Corrupted Areas | Magentas, purples, blacks | Sickly green |
| Forest | Greens, browns | Golden light |
| Dungeon | Grays, dark blues | Torch orange |

---

## WEATHER & ATMOSPHERE

> **Mountain peaks atmosphere is KEY to visual identity**

### Snow System (HIGH PRIORITY)
| Element | Implementation |
|---------|----------------|
| Falling snow | Particle system, varies with intensity |
| Blowing snow | Directional particles (wind) |
| Footprints | Temporary marks in snow tiles |
| Accumulation | Snow on objects, edges |
| Snow drifts | Environmental tiles |

### Other Weather
| Weather | Priority | Notes |
|---------|----------|-------|
| Snowstorm/Blizzard | High | Reduced visibility, heavy particles |
| Wind | High | Affects particles, visual movement |
| Fog | Medium | Distance fade, mystery |
| Rain | Low | Not mountain-focused |
| Clear/Calm | High | Contrast to storms |

### Atmosphere Elements
- Breath visible in cold (character particles)
- Distant mountains in background (parallax)
- Aurora borealis in night zones (optional, beautiful)
- Warm interior contrast (shelter feels WARM)

---

## IMPLEMENTATION PRIORITY

### Phase 1: Core Foundation ✓
1. UV Color-Lookup shader (searches UV map for color match)
2. Test scene with hot-reload capability
3. Basic shader parameters (tint, flash)
4. Single lookup texture swapping

### Phase 2: Player Character
5. Player animation sheet (unique colors per pixel)
6. UV Map (32x32, pixel-perfect overlay with animation)
7. Multiple lookup textures (skin variants)
8. Integration with player controller

### Phase 3: Equipment System ✓
9. Sector-based equipment shader (position determines slot)
10. Head/Body/Hands/Feet lookup textures
11. Per-slot texture swapping
12. Equipment test scene with slot toggles

### Phase 3: Basic World
9. Terrain tileset (grass, stone, snow)
10. Basic interactables (chest, door)
11. Simple particle effects

### Phase 4: Enemies
12. One enemy motion map (wolf or skeleton)
13. Two enemy skin variants
14. Enemy death animations

### Phase 5: Polish & Effects
15. Full lighting system with normal maps
16. Weather system (snow)
17. Hit feedback (hitstop, shake)
18. Bloom and post-processing

### Phase 6: Content Expansion
19. Additional enemy types
20. Additional equipment skins
21. Additional weapon categories
22. Additional zones and tilesets

---

## REFERENCE IMAGES

*(To be populated with reference screenshots, concept art, and style guides)*

### Style References
- Hyper Light Drifter (overall aesthetic)
- Celeste (mountain atmosphere)
- Death's Door (character design balance)

### Technical References
- Aarthificial UV Lookup system (animation tech)
- Sprite Lamp / normal mapped 2D (lighting)

---

## APPENDIX: DIFFERENCES FROM HLD

| Aspect | HLD | MobileTestia |
|--------|-----|--------------|
| Storytelling | Wordless, visual only | Full dialogue & text |
| UI text | Symbols only | Full descriptions |
| Equipment | Fixed character | Visible equipment changes |
| Combat text | None | Floating damage numbers |
| Menus | Minimal | Deep progression systems |
| Character | The Drifter (mysterious) | Young woman (defined) |

---

*Document Version: 2.0*
*Last Updated: Session claude/phase-1-TestingShaders-spp2s*
*Major Update: Replaced R/G UV encoding with Color-Lookup shader system*
