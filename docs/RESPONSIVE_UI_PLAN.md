# Responsive UI Implementation Plan

This document outlines how screen responsiveness works in our project and what (minimal) changes are needed to support various mobile devices.

---

## Current Setup: How Godot Viewport Stretch Works

### Your project.godot settings:
```ini
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"
window/stretch/aspect="expand"
```

### What this means:

**Viewport Mode**: The game renders internally at 1280x720, then that image is scaled to fit the screen. ALL your pixel values (positions, sizes, fonts) are in this 1280x720 coordinate space.

**Expand Aspect**: When the screen aspect ratio differs from 16:9, extra viewport space is added (not cropped). This means:
- On a wider screen (21:9 phone): You see more horizontal area
- On a taller screen (4:3 tablet): You see more vertical area
- The original 1280x720 area is always visible and centered

### Your existing designs DO scale!

```
Design Target: 1280x720 (your testing window)

On 640x360 phone:    Everything scales to 50% size → Still looks the same proportionally
On 1920x1080 phone:  Everything scales to 150% size → Still looks the same proportionally
On 1920x1200 tablet: Scales + extra vertical space added at top/bottom
```

The character_menu.tscn panel (840x600) scales with the viewport. On a 640x360 screen, it becomes 420x300 pixels - same proportion, smaller physical size.

---

## What's Actually Flexible vs What Needs Work

### Already Flexible (No Changes Needed)

| Component | Why It Works |
|-----------|--------------|
| **Character Menu** | Centered anchors + viewport scaling = scales with screen |
| **Tab buttons** | `size_flags_horizontal = 3` (SIZE_EXPAND_FILL) = share available width |
| **Content panels** | `anchors_preset = 15` (FULL_RECT) = fill parent container |
| **Combat HUD buttons** | Percentage-based positioning in CombatHUDConfig |
| **Joystick** | Scales with its control area size |
| **VBox/HBox containers** | Auto-arrange children |
| **Stats Grid** | GridContainer handles child layout |

### The Real Edge Case Concerns

| Concern | When It Happens | Impact |
|---------|-----------------|--------|
| **Physical readability** | Very small phones (5" at 720p) | 14px font might be physically tiny |
| **Touch targets** | Small high-DPI screens | 40px button might be physically 4mm |
| **Aspect ratio gaps** | Ultra-wide (21:9) or tablet (4:3) | UI clumps in center, edges empty |
| **Expand overflow** | Very wide screens | Corner-anchored UI far from center UI |

---

## The Minimal-Impact Solution

Instead of rebuilding your UI, we add a **thin scaling layer** that only activates on extreme screen sizes.

### Phase 1: Create ResponsiveUI Autoload

A lightweight singleton that provides:
1. Screen size category detection (small/normal/large)
2. Optional font size adjustment for readability
3. Safe area detection (notches, status bars)

```
This does NOT change your existing designs.
It provides utilities for edge cases only.
```

### Phase 2: Add Optional Size Constraints to Modal Dialogs

For character_menu and chest_menu, add constraints that only kick in on unusual screens:

```gdscript
# Only affects very small or very large screens
func _ready():
    var vp_size = get_viewport_rect().size

    # On normal screens (around 1280x720), do nothing different
    # On very small screens, ensure minimum readable size
    # On very large screens, cap maximum size

    var panel_width = 840  # Your current design
    var panel_height = 600

    # Constrain to 95% of viewport if panel would be too big
    panel_width = min(panel_width, vp_size.x * 0.95)
    panel_height = min(panel_height, vp_size.y * 0.9)

    # Apply only if different from design
    if panel_width < 840 or panel_height < 600:
        # Adjust panel size
```

**This preserves your 840x600 design on normal screens** - constraints only activate when the viewport is unusually small.

### Phase 3: Font Scaling for Extreme Screens (Optional)

If physical readability is an issue on real devices, add per-device font scaling:

```gdscript
# Only if testing reveals readability issues
func get_font_scale() -> float:
    var physical_height = DisplayServer.screen_get_size().y
    var dpi = DisplayServer.screen_get_dpi()

    # Calculate approximate physical size
    var physical_inches = physical_height / dpi

    # Scale fonts up on very small physical screens
    if physical_inches < 3.5:  # Very small phone
        return 1.3
    elif physical_inches > 8.0:  # Large tablet
        return 0.9
    return 1.0  # Normal devices - no change
```

---

## What Stays The Same

| Element | Current Value | After Implementation |
|---------|--------------|----------------------|
| Character menu panel | 840x600 centered | 840x600 centered (unchanged) |
| Tab buttons | 80-100px minimum, expand fill | Same (unchanged) |
| Font sizes | 12px, 14px, 16px, 20px, 24px | Same (scaled only on extreme devices) |
| Inventory slots | 56x56 | Same (unchanged) |
| Combat HUD | % positioning | Same (unchanged) |
| Joystick area | Bottom-left anchored | Same (unchanged) |

---

## Testing Strategy

### Method 1: Project Settings Override (Recommended for Quick Tests)

In `Project → Project Settings → Display → Window`:

| Test Case | Override Settings |
|-----------|-------------------|
| Small phone | 640x360 |
| Normal phone | 1280x720 (your default) |
| Large phone | 1920x1080 |
| Tall phone (19.5:9) | 720x1560 |
| Tablet landscape | 1920x1200 |
| Tablet portrait | 1200x1920 |
| Ultra-wide | 2560x720 |

### Method 2: Command Line Testing

```bash
# Test different resolutions
godot --resolution 640x360
godot --resolution 1920x1080
godot --resolution 1920x1200
```

### Method 3: In-Game Debug Panel

Add a simple debug tool to cycle through test resolutions while playing:

```
[Debug Menu]
Screen Size: 1280x720 ▼
├── 640x360 (Small Phone)
├── 1280x720 (Normal Phone) ✓
├── 1920x1080 (Large Phone)
├── 1920x1200 (Tablet Landscape)
└── 1200x1920 (Tablet Portrait)
```

---

## Implementation Priority

### Must Have (Before Testing on Devices)

1. **Create ResponsiveUI autoload** with screen size detection
2. **Add safe area margins** for notched phones
3. **Test at common resolutions** to verify viewport scaling works

### Nice to Have (If Testing Reveals Issues)

4. **Font scaling** for physical readability on extremes
5. **Panel size constraints** for unusually small viewports
6. **Dynamic grid columns** for tablets with lots of space

### Future Considerations

7. **Left-handed mode** (already stubbed in CombatHUDConfig)
8. **User-adjustable UI scale** (already stubbed)
9. **Layout presets** for different playstyles

---

## Files To Be Created/Modified

### New Files

| File | Purpose |
|------|---------|
| `autoloads/responsive_ui.gd` | Screen detection, scaling utilities, safe areas |

### Modified Files (Minimal Changes)

| File | Change |
|------|--------|
| `project.godot` | Add ResponsiveUI to autoloads |
| `scripts/ui/menu/character_menu.gd` | Optional: Add panel size constraints for small screens |
| `scripts/ui/chest/chest_menu.gd` | Optional: Add panel size constraints for small screens |

### Files That Stay Unchanged

| File | Reason |
|------|--------|
| `character_menu.tscn` | Design preserved - viewport scaling handles it |
| `game_hud.tscn` | Anchor-based positioning works with expand aspect |
| `combat_hud_config.gd` | Already uses percentages |
| All container-based layouts | Containers adapt automatically |

---

## Summary

**The good news**: Your viewport stretch mode (`mode=viewport`, `aspect=expand`) already handles most scaling. The 840x600 character menu stays 840x600 in viewport coordinates and scales proportionally to different screens.

**What we're adding**: A thin utility layer for edge cases (very small/large screens, safe areas) that doesn't touch your existing designs.

**What we're NOT doing**: Rebuilding UI layouts, changing container structures, or converting fixed sizes to percentages throughout the codebase.

---

## Next Steps

1. Review this plan - any concerns or questions?
2. Create ResponsiveUI autoload
3. Test on multiple resolutions to verify current behavior
4. Add constraints/adjustments only where testing shows problems

The goal is to **validate that viewport scaling works** before adding complexity. Your designs may already work on most devices!
