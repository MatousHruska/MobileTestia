# UI System Documentation

This document provides comprehensive documentation for the game's UI system, including the in-game HUD, character menu, responsive scaling, and configuration resources.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [In-Game HUD](#in-game-hud)
3. [Combat HUD](#combat-hud)
4. [Configuration Resources](#configuration-resources)
5. [Dual Viewport System](#dual-viewport-system)
6. [Responsive Scaling](#responsive-scaling)
7. [UITheme Database](#uitheme-database)
8. [Character Menu System](#character-menu-system)
9. [Database Values Reference](#database-values-reference)

---

## Architecture Overview

The UI system is built on these core principles:

1. **Dual Viewport**: Pixel art renders at 480x270, UI renders at native resolution
2. **Percentage-Based Layout**: Elements sized/positioned as percentage of viewport
3. **Configuration Resources**: Dedicated `.tres` files for HUD/Combat settings
4. **Scaled Elements**: Buttons, fonts, icons scale with `ui_scale` factor

### Key Files

| File | Purpose |
|------|---------|
| `scripts/ui/hud.gd` | Main HUD controller (PlayerFrame, Joystick, Status Effects) |
| `scripts/ui/combat/combat_hud.gd` | Combat buttons (Attack, Abilities, Dodge, Interact) |
| `resources/player_frame_config.tres` | PlayerFrame layout configuration |
| `resources/combat_hud_config.tres` | Combat button layout configuration |
| `autoloads/ui_theme.gd` | Central theme singleton with colors, sizes, scaling |
| `scenes/ui/hud/game_hud.tscn` | Main HUD scene file |

---

## In-Game HUD

The in-game HUD is managed by `hud.gd` and consists of several components positioned using **percentage-based values** for multi-resolution support.

### HUD Structure

```
HUD (CanvasLayer, layer 10)
├── PlayerFrame (Control)
│   ├── Background (ColorRect)
│   └── BarsContainer (VBoxContainer)
│       ├── HealthBar (ProgressBar + Label)
│       ├── ManaBar (ProgressBar + Label)
│       └── StaminaBar (ProgressBar + Label)
├── StatusEffectDisplay (HBoxContainer) - Below PlayerFrame
│   └── StatusEffectIcon(s) - Dynamic buff/debuff icons
├── MenuButton (Control) - Top-right hamburger menu
│   └── Button ("☰")
├── Controls (Control)
│   ├── JoystickArea (Control)
│   │   └── VirtualJoystick (Control)
│   └── CombatHUD (Control) - Combat buttons
└── CastBar (Control) - Spell casting progress
```

### PlayerFrame Configuration

The PlayerFrame uses `PlayerFrameConfig` resource (`resources/player_frame_config.tres`) for all sizing and positioning. **All values are percentages**, making it resolution-independent.

```gdscript
# Key properties in PlayerFrameConfig
@export var anchor_pct: Vector2 = Vector2(0.01, 0.01)  # Position from top-left
@export var size_pct: Vector2 = Vector2(0.20, 0.20)    # 20% of screen width/height
@export var padding_pct: float = 0.08                   # 8% internal padding
@export var bar_height_pct: float = 0.22               # Bar height as % of frame
@export var bar_gap_pct: float = 0.06                  # Gap between bars
@export var status_icon_size_pct: float = 0.35         # Icon size as % of frame height
```

### Status Effect Display

Status effect icons (buffs/debuffs) appear below the PlayerFrame, left-aligned with the health bars.

- **Icon size**: Controlled by `status_icon_size_pct` in PlayerFrameConfig
- **Position**: Aligned with bars inside frame (includes padding offset)
- **Spacing**: 15% of icon size between icons

```gdscript
# In hud.gd - Status effect positioning
var gap_below: float = padding * 0.5  # Small gap below frame
var status_x: float = frame_pos.x + (padding * 1.5)  # Align with bars
status_effect_display.position = Vector2(status_x, frame_pos.y + frame_size.y + gap_below)
```

### Virtual Joystick

The joystick uses percentage-based sizing defined as constants in `hud.gd`:

```gdscript
# Joystick sizing (percentage of screen)
const JOYSTICK_AREA_WIDTH_PCT := 0.40    # Touch area width
const JOYSTICK_AREA_HEIGHT_PCT := 0.67   # Touch area height
const JOYSTICK_MARGIN_PCT := 0.01        # Margin from screen edge
const JOYSTICK_RADIUS_PCT := 0.108       # Visual radius (% of screen height)
const KNOB_RADIUS_PCT := 0.054           # Knob radius (% of screen height)
```

The visual joystick position is offset from the bottom-left corner:

```gdscript
# Position visual with 10% offset from edges
var offset_x := joystick.size.x * 0.10
var offset_y := joystick.size.y * 0.10
joystick.joystick_center = Vector2(radius + offset_x, joystick.size.y - radius - offset_y)
```

### Menu Button

The hamburger menu button (top-right) is defined in `game_hud.tscn`:
- Container: 90×90 pixels
- Button: 66×66 pixels (with 12px padding)
- Anchored to top-right corner

---

## Combat HUD

The Combat HUD is managed by `combat_hud.gd` and handles all combat-related buttons.

### Combat HUD Structure

```
CombatHUD (Control)
├── AbilityWheel (Control) - Group container
│   ├── AttackButton (CombatButton)
│   └── AbilitySlots[0-3] (CombatButton)
├── UtilityBar (Control) - Group container
│   ├── DodgeButton (CombatButton)
│   └── QuickSlotButton (CombatButton)
└── InteractButton (Button) - Context-sensitive action
```

### Button Layout System

Combat buttons use a **hierarchical positioning system**:

1. **Groups** (AbilityWheel, UtilityBar) positioned relative to screen via anchor percentages
2. **Buttons** within groups positioned relative to each other

```gdscript
# CombatHUDConfig properties
@export var ability_wheel_anchor_pct: Vector2 = Vector2(0.08, 0.18)
@export var utility_bar_anchor_pct: Vector2 = Vector2(0.28, 0.12)
@export var utility_bar_gap_pct: float = 0.01
```

### Interact Button

The interact button appears when near NPCs, chests, or other interactables.

```gdscript
# In CombatHUDConfig
@export var interact_offset_pct: Vector2 = Vector2(0.15, 0.42)
@export var interact_size: Vector2 = Vector2(45, 18)  # Base size, gets scaled
```

The button size is calculated using the config:

```gdscript
var scaled_interact_size := config.interact_size * scale_factor
interact_button.offset_left = -scaled_interact_size.x
interact_button.offset_top = -scaled_interact_size.y / 2.0
interact_button.offset_right = 0.0
interact_button.offset_bottom = scaled_interact_size.y / 2.0
```

---

## Configuration Resources

### PlayerFrameConfig (`resources/player_frame_config.tres`)

Controls the PlayerFrame (health/mana/stamina bars) layout:

| Property | Default | Description |
|----------|---------|-------------|
| `anchor_pct` | (0.01, 0.01) | Position from top-left as % of screen |
| `size_pct` | (0.20, 0.20) | Size as % of screen |
| `padding_pct` | 0.08 | Internal padding as % of size |
| `bar_height_pct` | 0.22 | Bar height as % of frame height |
| `bar_gap_pct` | 0.06 | Gap between bars as % of frame height |
| `status_icon_size_pct` | 0.35 | Status icon size as % of frame height |

### CombatHUDConfig (`resources/combat_hud_config.tres`)

Controls combat button layout:

| Property | Default | Description |
|----------|---------|-------------|
| `attack_offset_pct` | (0.1, 0.15) | Attack button position |
| `dodge_offset_pct` | (0.26, 0.09) | Dodge button position |
| `quick_slot_offset_pct` | (0.34, 0.09) | Quick slot position |
| `interact_offset_pct` | (0.15, 0.42) | Interact button position |
| `interact_size` | (45, 18) | Interact button base size |
| `base_screen_height` | 270.0 | Reference height for scaling |

---

## Dual Viewport System

### Why Dual Viewport?

The game uses pixel art at 480x270 resolution. Without dual viewport:
- Scaling pixel art to native resolution causes blur
- UI text/elements become pixelated or blurry
- Touch targets are too small on mobile

### How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    Native Resolution                     │
│                    (e.g., 1920x1080)                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │                                                   │  │
│  │              SubViewport (480x270)                │  │
│  │              Pixel Art Game World                 │  │
│  │              Scaled with nearest-neighbor         │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ CanvasLayer (UI) ─────────────────────────────────┐ │
│  │  Rendered at native resolution (crisp text/icons)  │ │
│  │  • HUD (PlayerFrame, Joystick, Combat buttons)    │ │
│  │  • Character Menu                                  │ │
│  │  • Popups/Dialogs                                  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## Responsive Scaling

### Base Design Resolution

All element sizes are defined for **720p (1280x720)** base resolution.

```gdscript
const BASE_DESIGN_WIDTH: float = 1280.0
const BASE_DESIGN_HEIGHT: float = 720.0
```

### Scale Factor Calculation

```gdscript
ui_scale = viewport_height / 720.0
```

| Resolution | Viewport Height | ui_scale | Example Button (29px base) |
|------------|-----------------|----------|----------------------------|
| 480p | 480 | 0.67 | 19px |
| 720p | 720 | 1.0 | 29px |
| 1080p | 1080 | 1.5 | 44px |
| 1440p | 1440 | 2.0 | 58px |
| 4K | 2160 | 3.0 | 87px |

---

## UITheme Database

### Using UITheme in Code

```gdscript
# Element sizes (automatically scaled)
var btn_height := UITheme.BUTTON_HEIGHT_NORMAL
var slot_size := UITheme.SLOT_SIZE_NORMAL
var icon_size := UITheme.ICON_SIZE_NORMAL

# Colors (no scaling)
var bg_color := UITheme.COLOR_PANEL_BG
var gold_color := UITheme.COLOR_GOLD

# Font sizes (automatically scaled)
var header_size := UITheme.FONT_SIZE_HEADER
```

### Manual Scaling

```gdscript
# Scale a custom pixel value
var custom_size := UITheme.scale_px(100.0)
var custom_int := UITheme.scale_px_i(100)

# Scale a Vector2
var scaled_vec := UITheme.scale_size(Vector2(100, 50))
```

---

## Character Menu System

### Layout Structure

```
┌─────────────────────────────────────────────────────────┐
│ [Inventory] [Stats] [Skills] [Quests] [Menu] [X]        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Content Area (tab-specific panels)                     │
│                                                         │
│  • InventoryPanel - Equipment + Backpack grid           │
│  • StatsPanel - Attributes + derived stats              │
│  • SkillsPanel - Talent tree + skill binding            │
│  • QuestLogPanel - Active/completed quests              │
│  • MenuPanel - Save/Load/Exit buttons                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Sizing

Menu size is percentage-based:
- **Width**: 65% of viewport (832px at 1280px width)
- **Height**: 90% of viewport (648px at 720px height)

---

## Database Values Reference

### Element Sizes (Base 720p, auto-scaled)

| Key | Value | Description |
|-----|-------|-------------|
| `button_height_normal` | 29 | Normal button height |
| `icon_size_normal` | 31 | Normal icon size |
| `slot_size_normal` | 56 | Normal inventory slot |
| `min_touch_target` | 36 | Minimum touch target size |

### Font Sizes (Base 720p, auto-scaled)

| Key | Value | Description |
|-----|-------|-------------|
| `font_size_title` | 22 | Title text |
| `font_size_header` | 18 | Section headers |
| `font_size_label` | 16 | Normal labels |
| `font_size_small` | 14 | Small text |

### Key Colors

| Key | Description |
|-----|-------------|
| `color_panel_bg` | Panel background |
| `color_gold` | Gold text color |
| `color_life` | Health resource |
| `color_mana` | Mana resource |
| `color_stamina` | Stamina resource |

---

## Modifying UI Elements

### To Change PlayerFrame Size/Position

Edit `resources/player_frame_config.tres`:
```
size_pct = Vector2(0.20, 0.20)  # Change percentages
anchor_pct = Vector2(0.01, 0.01)
```

### To Change Status Effect Icon Size

Edit `resources/player_frame_config.tres`:
```
status_icon_size_pct = 0.35  # 35% of frame height
```

### To Change Joystick Size

Edit constants in `scripts/ui/hud.gd`:
```gdscript
const JOYSTICK_RADIUS_PCT := 0.108  # Adjust percentage
const KNOB_RADIUS_PCT := 0.054
```

### To Change Combat Button Positions

Edit `resources/combat_hud_config.tres`:
```
attack_offset_pct = Vector2(0.1, 0.15)
interact_size = Vector2(45, 18)
```

### To Change Menu Button Size

Edit `scenes/ui/hud/game_hud.tscn` MenuButton node offsets.

---

## Summary

The UI system ensures the game looks good across all screen sizes:

1. **In-Game HUD** uses `PlayerFrameConfig` for percentage-based layout
2. **Combat HUD** uses `CombatHUDConfig` for button positioning
3. **Joystick** uses percentage constants in `hud.gd`
4. **Character Menu** uses UITheme database values
5. **All sizing** is relative (percentages or scaled pixels), not hardcoded

**Key Principle**: Never use hardcoded pixel values. Always use:
- Percentage of screen/container for positioning
- Config resources for adjustable values
- UITheme for scaled standard sizes
