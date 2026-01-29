# Responsive UI System Documentation

This document provides comprehensive documentation for the game's responsive UI system, including the dual viewport architecture, scaling system, and UITheme database.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Dual Viewport System](#dual-viewport-system)
3. [Responsive Scaling](#responsive-scaling)
4. [UITheme Database](#uitheme-database)
5. [Using UITheme in Code](#using-uitheme-in-code)
6. [Character Menu System](#character-menu-system)
7. [Database Values Reference](#database-values-reference)

---

## Architecture Overview

The UI system is built on three core principles:

1. **Dual Viewport**: Pixel art renders at 480x270, UI renders at native resolution
2. **Percentage-Based Layout**: Panels/menus sized as percentage of viewport
3. **Scaled Elements**: Buttons, fonts, icons scale with `ui_scale` factor

### Key Files

| File | Purpose |
|------|---------|
| `autoloads/ui_theme.gd` | Central theme singleton with colors, sizes, and scaling |
| `autoloads/responsive_ui.gd` | Screen detection and panel constraint utilities |
| `databases/exports/ui_theme.json` | Database-driven theme values |

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
│  │  • Character Menu                                  │ │
│  │  • HUD elements                                    │ │
│  │  • Popups/Dialogs                                  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Implementation

1. **Game World**: Rendered in SubViewport at 480x270
   - Uses `canvas_item_default_texture_filter = TEXTURE_FILTER_NEAREST`
   - Scaled up to fill screen with crisp pixels

2. **UI Layer**: CanvasLayer at native resolution
   - `layer = 10+` to render above game
   - Text, buttons, icons all crisp at any resolution

---

## Responsive Scaling

### Base Design Resolution

All element sizes are defined for **720p (1280x720)** base resolution.

```gdscript
# UITheme constants
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

### Screen Categories (ResponsiveUI)

```gdscript
enum ScreenCategory { SMALL, NORMAL, LARGE }

# Thresholds (based on 720p base)
if viewport_height < 540:
    screen_category = SMALL      # Phones, small windows
elif viewport_height > 1080:
    screen_category = LARGE      # Tablets, desktops, TVs
else:
    screen_category = NORMAL     # Standard displays
```

---

## UITheme Database

### Value Types

| Type | Description | Scaling |
|------|-------------|---------|
| **Colors** | RGBA as comma-separated string | None |
| **Font sizes** | Base pixel size for 720p | × ui_scale |
| **Element sizes** | Base pixel size for 720p | × ui_scale |
| **Percentages** | 0.0-1.0 of viewport dimension | Applied to viewport |
| **Margins/Spacing** | Base pixel size for 720p | × ui_scale |

### Percentage-Based Layout

Menu and panel sizes use percentage of viewport:

```gdscript
# Database values
"menu_width_pct": 0.65      # 65% of viewport width
"menu_height_pct": 0.90     # 90% of viewport height
"save_panel_width_pct": 0.30
"save_panel_height_pct": 0.58
```

### Scaled Element Sizes

Element sizes are base 720p values that get multiplied by ui_scale:

```gdscript
# Database values (base 720p pixels)
"button_height_normal": 29
"slot_size_normal": 56
"icon_size_normal": 31

# At runtime
actual_size = base_size × ui_scale
```

---

## Using UITheme in Code

### Getting Scaled Values

```gdscript
# Element sizes (automatically scaled)
var btn_height := UITheme.BUTTON_HEIGHT_NORMAL  # Returns scaled int
var slot_size := UITheme.SLOT_SIZE_NORMAL       # Returns scaled int
var icon_size := UITheme.ICON_SIZE_NORMAL       # Returns scaled int

# Percentage-based sizes (returns actual pixels)
var menu_width := UITheme.MENU_WIDTH   # viewport.x × menu_width_pct
var menu_height := UITheme.MENU_HEIGHT # viewport.y × menu_height_pct

# Colors (no scaling)
var bg_color := UITheme.COLOR_PANEL_BG
var gold_color := UITheme.COLOR_GOLD

# Font sizes (automatically scaled)
var header_size := UITheme.FONT_SIZE_HEADER
```

### Manual Scaling

```gdscript
# Scale a custom pixel value
var custom_size := UITheme.scale_px(100.0)    # Returns float
var custom_int := UITheme.scale_px_i(100)     # Returns int

# Scale a Vector2
var scaled_vec := UITheme.scale_size(Vector2(100, 50))
```

### Creating UI Elements

```gdscript
# Button with proper sizing
var button := Button.new()
button.custom_minimum_size = Vector2(
    UITheme.BUTTON_WIDTH_NORMAL,
    UITheme.BUTTON_HEIGHT_NORMAL
)

# Label with scaled font
var label := UITheme.create_label("Hello", UITheme.FONT_SIZE_HEADER)

# Slot with proper sizing
slot.custom_minimum_size = Vector2(
    UITheme.SLOT_SIZE_NORMAL,
    UITheme.SLOT_SIZE_NORMAL
)
```

### Responsive Panels

```gdscript
# In your panel script
func _get_panel_width() -> float:
    return float(UITheme.MENU_WIDTH)

func _get_panel_height() -> float:
    return float(UITheme.MENU_HEIGHT)

# Apply to centered panel
func _apply_size() -> void:
    var width := _get_panel_width()
    var height := _get_panel_height()
    panel.offset_left = -width / 2.0
    panel.offset_right = width / 2.0
    panel.offset_top = -height / 2.0
    panel.offset_bottom = height / 2.0
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

### Inventory Tab (2-Column Layout)

```
┌────────────────────────┬─────────────────────────────────┐
│  Equipped Items:       │  Backpack | Gold: 100 [½][Use][🗑]│
├────────────────────────┼─────────────────────────────────┤
│                        │                                 │
│    [H] [Amulet]        │   [■][■][■][■][■][■][■]        │
│  [Gloves][Body][Ring]  │   [■][■][■][■][■][■][■]        │
│    [Boots]             │   [■][■][■][■][■][■][■]        │
│                        │   ... (scrollable)              │
│  [Weapon] [QuickSlot]  │                                 │
│                        │                                 │
└────────────────────────┴─────────────────────────────────┘
```

**Drag & Drop Actions:**
- Drag between slots to move/swap
- Drag to equipment slot to equip
- Drag to [🗑] to destroy
- Drag consumable to [Use] to use

### Stats Tab (2-Panel Layout)

```
┌─────────────────────┬──────────────────────────┐
│ Hero Name    Lv. 5  │  Attack Power: 50        │
│ Points: 10          │  Defense: 25             │
│ ███████░░░ XP       │  Critical: 5%            │
├─────────────────────┤  ... (scrollable)        │
│ STR:10+ DEX:10+ INT │                          │
│ VIT:10+ ENE:10+ LUK │                          │
├─────────────────────┤                          │
│ Life | Mana | Stam  │                          │
│  100    50     25   │                          │
├─────────────────────┤                          │
│ [buff] [debuff]     │                          │
└─────────────────────┴──────────────────────────┘
```

---

## Database Values Reference

### Menu/Panel Sizes (Percentages)

| Key | Value | Description |
|-----|-------|-------------|
| `menu_width_pct` | 0.65 | Character menu width |
| `menu_height_pct` | 0.90 | Character menu height |
| `save_panel_width_pct` | 0.30 | Save/Load panel width |
| `save_panel_height_pct` | 0.58 | Save/Load panel height |

### Element Sizes (Base 720p, auto-scaled)

| Key | Value | Description |
|-----|-------|-------------|
| `button_height_small` | 21 | Small button height |
| `button_height_normal` | 29 | Normal button height |
| `button_height_large` | 36 | Large button height |
| `button_width_small` | 62 | Small button width |
| `button_width_normal` | 94 | Normal button width |
| `button_width_large` | 130 | Large button width |
| `icon_size_small` | 20 | Small icon size |
| `icon_size_normal` | 31 | Normal icon size |
| `icon_size_large` | 47 | Large icon size |
| `slot_size_small` | 52 | Small inventory slot |
| `slot_size_normal` | 56 | Normal inventory slot |
| `slot_size_large` | 64 | Large inventory slot |
| `bar_height_thin` | 5 | Thin progress bar |
| `bar_height_normal` | 10 | Normal progress bar |
| `bar_height_thick` | 16 | Thick progress bar |
| `min_touch_target` | 36 | Minimum touch target size |
| `popup_width_small` | 200 | Small popup width |
| `popup_width_normal` | 280 | Normal popup width |
| `popup_width_large` | 390 | Large popup width |
| `label_width_small` | 24 | Small label width |
| `label_width_normal` | 31 | Normal label width |
| `label_width_large` | 47 | Large label width |
| `row_height_normal` | 26 | Normal row height |
| `row_height_large` | 36 | Large row height |

### Font Sizes (Base 720p, auto-scaled)

| Key | Value | Description |
|-----|-------|-------------|
| `font_size_title` | 22 | Title text |
| `font_size_large` | 20 | Large text |
| `font_size_header` | 18 | Section headers |
| `font_size_label` | 16 | Normal labels |
| `font_size_small` | 14 | Small text |
| `font_size_tiny` | 12 | Tiny text |

### Margins & Spacing (Base 720p, auto-scaled)

| Key | Value | Description |
|-----|-------|-------------|
| `margin_standard` | 10 | Standard margin |
| `margin_small` | 8 | Small margin |
| `margin_tiny` | 6 | Tiny margin |
| `separation_normal` | 10 | Normal separation |
| `separation_small` | 6 | Small separation |
| `separation_tiny` | 4 | Tiny separation |
| `separation_grid` | 6 | Grid separation |

### Colors

| Key | Value | Description |
|-----|-------|-------------|
| `color_panel_bg` | 0.12,0.12,0.14,0.9 | Panel background |
| `color_popup_bg` | 0.1,0.1,0.12,0.95 | Popup background |
| `color_button_bg` | 0.2,0.2,0.25,0.8 | Button background |
| `color_gold` | 1.0,0.85,0.0,1.0 | Gold text color |
| `color_available` | 1.0,0.85,0.3,1.0 | Available/notification |
| `color_learned` | 0.5,1.0,0.5,1.0 | Learned/success |
| `color_life` | 0.9,0.3,0.3,1.0 | Health resource |
| `color_mana` | 0.4,0.6,1.0,1.0 | Mana resource |
| `color_stamina` | 0.4,1.0,0.6,1.0 | Stamina resource |

---

## Example: Adding a New Scaled Element

1. **Add to database** (`ui_theme.json`):
```json
{
    "my_element_size": 40
}
```

2. **Add default** (`ui_theme.gd` DEFAULTS):
```gdscript
"my_element_size": 40,
```

3. **Add property getter** (`ui_theme.gd`):
```gdscript
var MY_ELEMENT_SIZE: int:
    get: return _scaled_int("my_element_size")
```

4. **Use in code**:
```gdscript
my_element.custom_minimum_size = Vector2(
    UITheme.MY_ELEMENT_SIZE,
    UITheme.MY_ELEMENT_SIZE
)
```

---

## Testing Checklist

### Resolution Tests

| Resolution | Height | ui_scale | Expected Menu Size |
|------------|--------|----------|-------------------|
| 854x480 | 480 | 0.67 | 555x432 |
| 1280x720 | 720 | 1.0 | 832x648 |
| 1920x1080 | 1080 | 1.5 | 1248x972 |
| 2560x1440 | 1440 | 2.0 | 1664x1296 |
| 3840x2160 | 2160 | 3.0 | 2496x1944 |

### Visual Tests

- [ ] UI text is crisp at all resolutions
- [ ] Pixel art remains pixelated (no blur)
- [ ] Touch targets are large enough on mobile
- [ ] Menu fits on screen with margins
- [ ] Fonts scale proportionally
- [ ] Icons/buttons scale proportionally

---

## Summary

The responsive UI system ensures the game looks good across all screen sizes:

1. **Pixel art** stays crisp via SubViewport at 480x270
2. **UI elements** render at native resolution for crisp text
3. **Layout** uses percentage-based sizing for menus/panels
4. **Elements** use base 720p sizes × ui_scale factor
5. **Database-driven** values allow easy tuning without code changes

All UI code should use `UITheme` constants instead of hardcoded pixel values.
