# Responsive UI Implementation Plan

This document outlines the mobile-first UI redesign for character menu and related panels.

---

## Combat HUD Terminology

The right-side combat controls use the following structure:

```
Combat HUD
├── Primary Controls (Attack button + Ability Wheel)
│   ├── Attack Button - Main attack, can have skill bound
│   └── Ability Wheel - Skills bound in arc around attack [1-5 slots]
├── Secondary Controls
│   ├── Dodge Button - Evasion/roll
│   └── Quick Slot Button - Consumable items
└── Interact Button - Context-sensitive (Talk, Loot, Open)
```

---

## Mobile-First Character Menu Redesign

### Target Specifications

| Screen Category | Resolution Example | Min Height | Status |
|-----------------|-------------------|------------|--------|
| **Small Mobile** | 918x424, 854x480 | 424px | Primary Target |
| **Standard Mobile** | 1280x720 | 720px | Must look good |
| **Tablet** | 1920x1080+ | 1080px+ | Scale up nicely |

### Current Problem

The current 3-column Inventory layout (Equipment | Item Details | Backpack) requires ~550px height minimum:
- Tab bar: 40px
- Margins: 16px
- Equipment column needs: ~300px (4 slot rows + labels)
- **Total minimum: ~360px content + 56px chrome = 416px**

On 424px screens, content gets cut off at the bottom.

---

## Phase 1: Inventory Tab Redesign

### New Layout: Two-Panel with Popup Details

```
┌─────────────────────────────────────────────────────────┐
│ [Inventory] [Stats(+10)] [Skills] [Quests] [Menu] [X]   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────┐    ┌────────────────────────────────┐  │
│  │  EQUIPMENT  │    │          BACKPACK              │  │
│  │             │    │  ┌───┬───┬───┬───┬───┐        │  │
│  │   [H] [A]   │    │  │   │   │   │   │   │ Gold:  │  │
│  │             │    │  ├───┼───┼───┼───┼───┤  100   │  │
│  │     [B]     │    │  │   │   │   │   │   │        │  │
│  │             │    │  ├───┼───┼───┼───┼───┤        │  │
│  │   [G] [R]   │    │  │   │   │   │   │   │        │  │
│  │             │    │  ├───┼───┼───┼───┼───┤        │  │
│  │     [F]     │    │  │   │   │   │   │   │        │  │
│  │             │    │  └───┴───┴───┴───┴───┘        │  │
│  └─────────────┘    └────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘

[Item Details appear as popup/overlay when item selected]
```

### Key Changes

1. **Remove Item Details column** - Replace with popup overlay
2. **Two columns only**: Equipment (left) + Backpack (right)
3. **Smaller slot sizes**: 48px instead of 56px for mobile
4. **Scrollable backpack**: If needed, backpack scrolls vertically

### Item Details Popup

When an item is selected (tap), show a popup overlay:

```
┌───────────────────────────────────┐
│  [Icon]  Iron Sword           [X] │
│          One-Handed Weapon        │
│          Common                   │
├───────────────────────────────────┤
│  8 Damage (1 Physical, 5 Cold)    │
│  1.0 Attacks/sec                  │
├───────────────────────────────────┤
│  "Drag items to move, equip,      │
│   or destroy"                     │
└───────────────────────────────────┘
```

- **Positioned near tapped item** (not centered) - popup appears over the slot
- Clamped to screen bounds with 8px margin
- Tap outside or [X] to dismiss
- **Info only** - no action buttons, all actions via drag & drop

### Drag & Drop System ✅ COMPLETE

Replaces the old button-based system (Equip, Destroy, Swap, Quick Slot):

```
┌────────────────────────────┬─────────────────────────────────────┐
│  Equipped Items:           │  Backpack | Gold: 100  [½][Use][🗑] │
├────────────────────────────┼─────────────────────────────────────┤
│                            │                                     │
│    [H] [Amulet]            │   [■][■][■][■][■][■][■]            │
│  [Gloves][Body][Ring]      │   [■][■][■][■][■][■][■]            │
│    [Boots]                 │   [■][■][■][■][■][■][■]            │
│                            │   ... (scrollable)                  │
│  [Weapon]   [QuickSlot]    │                                     │
│                            │                                     │
└────────────────────────────┴─────────────────────────────────────┘
```

**Header icons:**
- `[½]` - Split stack (always splits in half)
- `[Use]` - Use selected consumable (or drag consumable onto it)
- `[🗑]` - Trash zone (drag items here to destroy)

**Drag behaviors:**
| Action | How to perform |
|--------|----------------|
| Move/Swap items | Drag between backpack slots |
| Equip item | Drag to equipment slot (or drop anywhere on equipment panel) |
| Use consumable | Drag to Use button (or click Use with item selected) |
| Destroy item | Drag to trash icon (confirms for Rare+ items) |
| Split stack | Click ½ button, then click a stack |

**Visual feedback during drag:**
- Source slot dims (50% opacity)
- Valid target equipment slot highlights green
- Use button highlights green for consumables
- Trash zone highlights when valid item hovers

**Auto-equip:** Dropping an item anywhere on the equipment panel (not on a specific slot) automatically equips it to the correct slot.

---

## Phase 2: Stats Tab Optimization

### Current Issues
- Player info section takes vertical space
- Stats grid may overflow on small screens

### Mobile Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Inventory] [Stats(+10)] [Skills] [Quests] [Menu] [X]   │
├─────────────────────────────────────────────────────────┤
│  Hero Name              Lv. 5    Points: 10             │
│  ████████████░░░░  350/1000 XP                          │
├─────────────────────────────────────────────────────────┤
│  STR: 12 [+]  Phys Dmg +6                               │
│  DEX: 10 [+]  Atk Spd +2%, Crit +1%                     │
│  INT: 10 [+]  Magic Dmg +5, Mana +10                    │
│  END: 14 [+]  Health +28, Regen +1.4                    │
│  LUK:  8 [+]  Drop +1.6%, Crit Dmg +2.4%                │
├─────────────────────────────────────────────────────────┤
│  [Derived Stats ▼]  (collapsible section)               │
│  Health: 280/280  |  Mana: 100/100  |  Stamina: 50/50   │
└─────────────────────────────────────────────────────────┘
```

### Changes
- Compact single-line player info
- Inline stat layout (name + value + button + effect on same row)
- Collapsible derived stats section

---

## Phase 3: Skills Tab Optimization

### Mobile Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Inventory] [Stats(+10)] [Skills] [Quests] [Menu] [X]   │
├─────────────────────────────────────────────────────────┤
│  Talent Points: 3                                       │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐    │
│  │  [Skill1]  [Skill2]  [Skill3]    <- Tier 1      │    │
│  │      ↓         ↓         ↓                      │    │
│  │  [Skill4]  [Skill5]  [Skill6]    <- Tier 2      │    │
│  │      ↓         ↓         ↓                      │    │
│  │  [Skill7]  [Skill8]  [Skill9]    <- Tier 3      │    │
│  └─────────────────────────────────────────────────┘    │
│  (scrollable if more tiers)                             │
├─────────────────────────────────────────────────────────┤
│  Power Strike (1/5)                                     │
│  Deal 150% weapon damage.  [Learn] [Bind]               │
└─────────────────────────────────────────────────────────┘
```

### Changes
- Skill tree takes most of vertical space (scrollable)
- Selected skill info at bottom (fixed height)
- Smaller skill buttons (64x64 instead of 80x80)

---

## Phase 4: Quests Tab Optimization

### Mobile Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Inventory] [Stats(+10)] [Skills] [Quests] [Menu] [X]   │
├─────────────────────────────────────────────────────────┤
│  Active Quests (3)                                      │
├─────────────────────────────────────────────────────────┤
│  ▶ Kill 10 Goblins          [████████░░] 8/10          │
│  ▶ Find the Lost Sword      [░░░░░░░░░░] 0/1           │
│  ▶ Talk to the Blacksmith   [██████████] Complete!     │
├─────────────────────────────────────────────────────────┤
│  (tap quest to expand details)                          │
│                                                         │
│  ┌─ Find the Lost Sword ─────────────────────────────┐  │
│  │  The blacksmith has lost his prized sword...      │  │
│  │  Objectives:                                      │  │
│  │  • Search the goblin cave                         │  │
│  │  Rewards: 500 XP, 100 Gold                        │  │
│  │                               [Track] [Abandon]   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Changes
- Compact quest list with progress bars
- Expandable quest details (accordion style)
- No separate details panel

---

## Implementation Order

### Session 1: Inventory Tab Redesign ✅ COMPLETE
1. [x] Create ItemDetailPopup component (`scripts/ui/inventory/item_detail_popup.gd`)
2. [x] Redesign InventoryPanel to 2-column layout
3. [x] Reduce slot sizes for mobile (44/48/56px responsive)
4. [x] Connect item selection to popup
5. [x] Remove slot labels (ghost icons sufficient)
6. [x] Implement drag & drop system (replaces button actions)
7. [x] Add trash zone for item destruction
8. [x] Add split stack button
9. [x] Add Use button (click or drag consumables)
10. [x] Equipment slot highlighting during drag
11. [x] Auto-equip when dropping on equipment panel
12. [x] Popup positions near tapped item (not centered)
13. [x] Move inventory_slots to database (gameplay_settings.json)
14. [ ] Test on 424px and 720px heights

### Session 2: Stats Tab Optimization
1. [ ] Compact player info header
2. [ ] Inline stat rows
3. [ ] Collapsible derived stats
4. [ ] Test on small screens

### Session 3: Skills Tab Optimization
1. [ ] Smaller skill buttons
2. [ ] Scrollable skill tree
3. [ ] Fixed skill info footer
4. [ ] Test on small screens

### Session 4: Quests Tab Optimization
1. [ ] Accordion-style quest list
2. [ ] Inline progress bars
3. [ ] Expandable details
4. [ ] Test on small screens

### Session 5: Final Polish
1. [ ] Test all tabs at 424px, 720px, 1080px
2. [ ] Adjust spacing/fonts as needed
3. [ ] Update chest_menu with same principles
4. [ ] Document final responsive behavior

---

## Design Constants (Mobile-First)

```gdscript
# Target minimum viewport height
const MIN_VIEWPORT_HEIGHT := 424.0

# Panel sizing
const MENU_PANEL_WIDTH := 840.0
const MENU_PANEL_HEIGHT := 400.0  # Reduced from 550

# Slot sizes
const SLOT_SIZE_MOBILE := 48.0    # For phones
const SLOT_SIZE_TABLET := 56.0    # For tablets (scale up)

# Font sizes (base, scaled on tablets)
const FONT_SMALL := 12
const FONT_NORMAL := 14
const FONT_LARGE := 16
const FONT_HEADER := 18

# Touch targets (minimum)
const MIN_TOUCH_TARGET := 40.0
```

---

## Scaling Strategy

### On Load
```gdscript
func _ready():
    var viewport_height = get_viewport().get_visible_rect().size.y

    if viewport_height <= 480:
        # Small mobile - use compact layout
        _apply_compact_mode()
    elif viewport_height <= 800:
        # Standard mobile - normal layout
        _apply_normal_mode()
    else:
        # Tablet - scale up with extra polish
        _apply_tablet_mode()
```

### Scaling Factors
| Viewport Height | Scale | Slot Size | Font Scale |
|-----------------|-------|-----------|------------|
| ≤480px | 0.85 | 44px | 0.9 |
| 481-800px | 1.0 | 48px | 1.0 |
| 801-1080px | 1.15 | 56px | 1.1 |
| >1080px | 1.3 | 64px | 1.2 |

---

## Files to Modify

### Core Changes
| File | Status | Changes |
|------|--------|---------|
| `scripts/ui/inventory/inventory_panel.gd` | ✅ Done | 2-column layout, drag & drop, header icons |
| `scripts/ui/inventory/inventory_slot.gd` | ✅ Done | Drag & drop support, highlight signals |
| `scripts/inventory/inventory_manager.gd` | ✅ Done | drag_drop_swap, split_stack, destroy_item, use_item, auto_equip |
| `scripts/ui/menu/character_menu.gd` | ✅ Done | Removed old destroy confirmation flow |
| `databases/exports/gameplay_settings.json` | ✅ Done | Added inventory_slots setting |
| `scripts/ui/menu/stats_panel.gd` | Pending | Compact layout |
| `scripts/ui/menu/skills_panel.gd` | Pending | Smaller buttons, scrollable |
| `scripts/ui/quest/quest_log_panel.gd` | Pending | Accordion layout |

### New Files
| File | Status | Purpose |
|------|--------|---------|
| `scripts/ui/inventory/item_detail_popup.gd` | ✅ Done | Modal popup for item details (info only) |
| `scripts/ui/inventory/trash_drop_zone.gd` | ✅ Done | Drop zone for destroying items |
| `scripts/ui/inventory/use_drop_zone.gd` | ✅ Done | Drop zone for using consumables |
| `scripts/ui/inventory/equipment_drop_zone.gd` | ✅ Done | Auto-equip drop zone overlay |

### Scene Changes
| File | Status | Changes |
|------|--------|---------|
| `scenes/ui/menu/character_menu.tscn` | Pending | May need reduced panel height |

---

## Testing Checklist

### Resolution Tests
- [ ] 918x424 (user's small test window)
- [ ] 854x480 (small phone landscape)
- [ ] 1280x720 (standard mobile)
- [ ] 1920x1080 (large phone/tablet)
- [ ] 2560x1440 (tablet)

### Functional Tests
- [ ] All tabs accessible and readable
- [ ] Item selection shows popup
- [ ] Equipment drag/drop works
- [ ] Stats can be increased
- [ ] Skills can be learned/bound
- [ ] Quests expand/collapse
- [ ] Close button works
- [ ] ESC/back closes menu

---

## Summary

**Approach**: Design for 424px height first, scale UP for larger screens.

**Key insight**: The 3-column inventory layout doesn't fit on small screens. Replace with 2-column + popup overlay.

**Goal**: Full functionality on 424px screens, enhanced experience on tablets.
