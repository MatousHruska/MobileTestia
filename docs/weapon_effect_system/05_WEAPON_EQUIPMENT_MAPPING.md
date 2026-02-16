# Phase 5: Weapon-Equipment Mapping

## Context

The player can equip weapons via the inventory system. Each weapon has a `weapon_category` field in `EquipmentData` (e.g., `"melee_1h"`, `"melee_2h"`, `"ranged"`, `"magic"`). After Phases 1-2, we have direction-aware weapon texture sets and a `CharacterVisuals` that can display them.

This phase connects the dots: when the player equips a weapon, the correct placeholder sprite set is loaded into `CharacterVisuals`. When the weapon changes, the sprite set updates.

**Scope**: Melee weapon categories only (`melee_1h`, `melee_2h`, `dagger`). Ranged/magic will be mapped in future phases.

## Prerequisites

- **Phase 2** (CharacterVisuals weapon set support) — `set_weapon_texture_set()` must exist.
- Phase 1 is implied via Phase 2.

## Files to Read Before Starting

| File | Why |
|------|-----|
| `scripts/data/equipment_data.gd` | EquipmentData structure — weapon_category field |
| `scripts/combat/character_visuals.gd` | The `set_weapon_texture_set()` API from Phase 2 |
| `scripts/combat/placeholder_weapon_sprites.gd` | The weapon set factory functions from Phase 1 |
| `scripts/player/player_controller.gd` | How CharacterVisuals is created, where equipment changes are handled |
| `scripts/ui/combat/combat_hud.gd` | May handle equipment changes, references to InventoryManager |
| `autoloads/inventory_manager.gd` | Equipment slots, signals for equipment changes (if exists) |
| `autoloads/player_stats.gd` | Equipment bonus calculation, may have equipped weapon reference |

## Implementation Prompt

### Step 1: Find the Equipment Change Hook

First, identify where in the codebase the player's equipped weapon changes. Look for:
- `InventoryManager` signals like `equipment_changed` or `weapon_equipped`
- Equipment slot UI that triggers weapon changes
- `PlayerStats` methods that recalculate on equipment change

The mapping code should run whenever the equipped weapon changes.

### Step 2: Create the Mapping Function

Add a static mapping function that converts `weapon_category` to a weapon texture set. This could live in `PlaceholderWeaponSprites` as a convenience method:

```gdscript
## In PlaceholderWeaponSprites:

## Returns the appropriate weapon texture set for a given weapon_category.
## Returns an empty dictionary if the category has no placeholder sprites.
static func create_set_for_category(weapon_category: String) -> Dictionary:
    match weapon_category:
        "melee_1h":
            return create_sword_set()
        "melee_2h":
            return create_greatsword_set()
        "dagger":
            return create_dagger_set()
        # Future:
        # "ranged": return create_bow_set()
        # "magic": return create_staff_set()
    return {}
```

### Step 3: Wire Up Equipment Changes

When the player equips a weapon, update `CharacterVisuals`:

```gdscript
## Called when equipped weapon changes
func _update_weapon_visual() -> void:
    if not character_visuals:
        return

    var weapon_data := _get_equipped_weapon_data()  # However the codebase gets this
    if weapon_data and weapon_data.weapon_category:
        var texture_set := PlaceholderWeaponSprites.create_set_for_category(weapon_data.weapon_category)
        character_visuals.set_weapon_texture_set(texture_set)
    else:
        # No weapon equipped — clear textures
        character_visuals.set_weapon_texture_set({})
```

**Where to put this:**
- If `PlayerController` manages `CharacterVisuals`, add it there.
- Connect to whatever signal fires on equipment change.
- Also call it during initialization (in case a weapon is already equipped on game load).

### Step 4: Handle No Weapon Equipped

When the player unequips a weapon or has no weapon, clear the texture set:

```gdscript
character_visuals.set_weapon_texture_set({})
```

This ensures no phantom weapon appears during abilities.

### Step 5: Handle weapon_category Field

Check how `weapon_category` is stored in `EquipmentData`. It might be:
- A string directly: `"melee_1h"`
- An enum value
- Derived from `equipment_type`

The mapping function should handle whatever format is used. Read `equipment_data.gd` carefully.

### Fallback for Unknown Categories

If a weapon has an unrecognized category (or one not yet implemented like `"ranged"`), fall back to a generic weapon:

```gdscript
static func create_set_for_category(weapon_category: String) -> Dictionary:
    match weapon_category:
        "melee_1h":
            return create_sword_set()
        "melee_2h":
            return create_greatsword_set()
        "dagger":
            return create_dagger_set()
    # Fallback: basic sword for any melee-ish weapon
    if weapon_category.begins_with("melee"):
        return create_sword_set()
    return {}
```

### Texture Caching (Optional Optimization)

Weapon textures are procedurally generated. If they're recreated every frame or every equipment change, that's wasteful. Consider caching:

```gdscript
## In PlaceholderWeaponSprites:
static var _cache: Dictionary = {}

static func create_set_for_category(weapon_category: String) -> Dictionary:
    if _cache.has(weapon_category):
        return _cache[weapon_category]

    var result: Dictionary = {}
    match weapon_category:
        "melee_1h": result = create_sword_set()
        # ...

    if not result.is_empty():
        _cache[weapon_category] = result
    return result
```

This is optional for placeholders but good practice.

## Acceptance Criteria

1. When the player equips a `melee_1h` weapon, `CharacterVisuals` receives the sword texture set.
2. When the player equips a `melee_2h` weapon, the greatsword texture set is used.
3. When the player equips a `dagger` weapon, the dagger texture set is used.
4. When the player unequips a weapon, the texture set is cleared (no weapon sprite shown).
5. The mapping updates when equipment changes (not just on game start).
6. The mapping runs during initialization (existing equipment is reflected on game load).
7. Unknown weapon categories fall back gracefully (no errors, empty dictionary or generic fallback).
8. `PlaceholderWeaponSprites.create_set_for_category()` convenience function exists.

---

*Phase 5 of 7 — Depends on Phase 2*
