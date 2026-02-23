# Sprite Wizard UI Redesign — Design Document

## Goal

Comprehensive visual overhaul of the sprite pipeline wizard (`scripts/tools/sprite_pipeline.gd`) from raw Godot defaults to a polished, clean minimal dark-theme tool aesthetic. Improve appearance, layout/readability, and navigation/flow.

## Approach

**Theme Resource + Programmatic (Approach A):** Create a `Theme` resource programmatically in the script that defines all visual styles. The existing programmatic UI-building code stays intact; we modify the `_build_*()` functions to use styled helper methods and apply the theme to the root node. A custom step indicator bar is drawn via `_draw()`.

## Color Palette

| Token           | Hex       | Usage                                      |
|-----------------|-----------|---------------------------------------------|
| Background      | `#1E1E2E` | Root/window fill                            |
| Panel BG        | `#252536` | Left panel background                       |
| Section BG      | `#2A2A3C` | Grouped section containers                  |
| Surface         | `#33334A` | Button/input backgrounds                    |
| Surface Hover   | `#3D3D55` | Hover state for buttons/inputs              |
| Border          | `#3A3A50` | Subtle borders around inputs/sections       |
| Text Primary    | `#E0E0EC` | Main labels, headings                       |
| Text Secondary  | `#8888A0` | Hints, descriptions, slider value readouts  |
| Text Dim        | `#555570` | Disabled text, future step indicators       |
| Accent          | `#5B9CF5` | Current step, active toggles, Next button   |
| Accent Hover    | `#7BB0FF` | Hover state for accent elements             |
| Success         | `#5BCC7F` | Completed steps, export success messages    |
| Warning         | `#F5A85B` | Attention-needed states, Export button       |

## Typography Hierarchy

| Role           | Size | Weight | Color          |
|----------------|------|--------|----------------|
| Title          | 18px | Bold   | Text Primary   |
| Section Header | 14px | Bold   | Accent         |
| Field Label    | 13px | Normal | Text Primary   |
| Hint Text      | 11px | Normal | Text Secondary |
| Value Readout  | 12px | Normal | Text Secondary |
| Status Text    | 11px | Normal | Text Secondary |

## Step Progress Indicator

Horizontal bar at top of left panel, below title (~50px tall):

```
 ●━━━━●━━━━◉━━━━○━━━━○━━━━○━━━━○
 1    2    3    4    5    6    7

      Pixel Art Settings
```

- Completed steps: Filled circle + line in Success green
- Current step: Larger/brighter circle in Accent blue
- Future steps: Hollow circle + dim line in Text Dim
- Step name label centered below
- Rendered via custom `Control._draw()` method

## Section Grouping & Layout

Each step's controls organized into styled sections:

- **Section containers**: `PanelContainer` with Section BG, 8px internal padding, 4px border radius
- **Section headers**: Bold 14px label in Accent color, optional expand/collapse arrow (for Camera Settings, Dithering, Outline, Denoising subsections)
- **Field layout**: Label above control with 4px gap (vertical stacking)
- **Toggle groups** (Color/Normal/Shadow, Down/Up/Right): Segmented control style — row of flat buttons, active one gets Accent background
- **HSeparators** replaced by section container gaps (8px between sections)

### Collapsible Subsections

These sections start collapsed by default:
- Camera Settings (Step 1)
- Dithering settings (Step 3)
- Outline settings (Step 3)
- Denoising settings (Step 3)

Toggle arrow: `▸` (collapsed) / `▾` (expanded), clickable header row.

## Navigation Bar

Fixed at bottom of left panel (outside scroll container):

- **Back button**: Subtle style — Surface BG, Border outline, Text Primary text
- **Next button**: Prominent — Accent BG, white text
- Both: 12px vertical padding, expand-fill horizontal
- Export step: Next button uses Warning color
- Disabled: 30% opacity

## Status Bar

Fixed below navigation (outside scroll container):

- 11px font, Text Secondary color
- Section BG background, 6px padding
- Auto-wrap, max 2 lines
- Success messages in Success green
- Error messages in Warning orange

## Button Styles

| Style    | Background    | Border | Text          | Use Case                        |
|----------|---------------|--------|---------------|---------------------------------|
| Default  | Surface       | Border | Text Primary  | Most buttons                    |
| Active   | Accent        | none   | White         | Selected tab/toggle             |
| Primary  | Accent        | none   | White         | Next button                     |
| Subtle   | Transparent   | Border | Text Primary  | Back button, secondary actions  |
| Warning  | Warning       | none   | White/Dark    | Export action button            |

## Slider Styling

- Track: Border color, 2px height
- Filled track: Accent color
- Grabber: Accent color, 12px circle
- Value readout: Inline label beside slider in Text Secondary, 12px font

## Panel Width

Left panel: 300px (unchanged). Content improvements happen within existing width.

## Implementation Scope

### What Changes

1. Add theme-building function that creates `Theme` resource with all StyleBox, Color, and Font overrides
2. Add `StepIndicator` custom Control with `_draw()` method
3. Refactor `_build_ui()` to:
   - Apply theme to root
   - Move nav bar + status bar outside ScrollContainer
   - Replace HSeparators with section containers
4. Refactor each `_build_step*()` to use styled helpers:
   - `_make_section(title)` — styled section container with header
   - `_make_field(label, control)` — label-above-control pair
   - `_make_toggle_group(options, callback)` — segmented control
   - `_make_collapsible(title, content)` — collapsible section
5. Style all buttons with appropriate StyleBox overrides

### What Does NOT Change

- Functional logic (capture, processing, export, anchors, apply)
- State management
- Signal connections and callbacks
- Right panel preview areas
- File paths, constants, data flow
