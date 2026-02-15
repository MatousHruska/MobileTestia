# Phase 6: Database Schema Update — visual_type Field

> **Goal**: Add a `visual_type` field to both the player talent and enemy ability databases, allowing each ability to explicitly specify which visual template it uses. This replaces the automatic effect_type-to-template mapping with explicit control.

> **Depends on**: All previous phases (the system is fully wired and working with auto-mapped templates)

---

## Context

In Phases 4 and 5, we mapped ability types to visual templates automatically:
- Player: `TalentData.effect_type` -> template (DAMAGE -> melee_single, PROJECTILE -> ranged_aim, etc.)
- Enemy: `AbilityData.type` -> template (MELEE -> melee_single, DASH_ATTACK -> dash_attack, etc.)

This works for basic cases, but we need explicit control. For example:
- Two different melee skills might want different visuals (one uses `melee_single`, another uses `melee_combo_2`)
- A skill might be a "DAMAGE" type but visually look like a `thrust` instead of a `melee_single`
- Future abilities can reference custom templates without changing code

The `visual_type` field gives designers (via the Excel database) direct control over which visual template each ability uses.

---

## Database Workflow Reminder

**CRITICAL: NEVER edit JSON files in `databases/exports/` directly!**

This phase provides:
1. Updated VBA `.bas` files
2. Data to paste into Excel sheets
3. The user runs `ExportAll` to regenerate JSON

---

## What To Modify

### VBA File 1: `databases/vba/SkillDatabase.bas`

The existing skill export handles player talents. Add a `visual_type` column to the export.

#### In the `ExportSkillsData` function:

After the existing field exports, add:

```vba
' Visual type (which animation template to use)
If Not IsEmpty(ws.Cells(r, colVisualType)) Then
    jsonStr = jsonStr & """visual_type"": """ & CStr(ws.Cells(r, colVisualType).Value) & ""","
Else
    jsonStr = jsonStr & """visual_type"": """","
End If
```

#### Column mapping:

Add `colVisualType` to the column detection logic. The new column should be placed after the existing combat-related columns (after `explosion_falloff` or similar). Suggested column header name: `visual_type`.

#### Valid values for player talents:

```
melee_single       — Standard single melee strike
melee_combo_2      — Two-hit melee combo
melee_combo_3      — Three-hit melee combo
dash_attack        — Rush forward then strike
ranged_aim         — Hold-to-charge ranged shot
spell_cast         — Cast-time spell
spell_instant      — Instant-cast spell
throw              — Throw an object
self_buff          — Cast a buff on self
```

If the field is empty, the automatic mapping from Phase 4 (`_get_visual_template_for_talent()`) is used as fallback. This means existing data works without changes — the field is optional.

---

### VBA File 2: `databases/vba/AbilityDatabase.bas`

The enemy ability export. Add `visual_type` column.

#### In the `ExportAbilitiesData` function:

```vba
' Visual type (animation template override)
If Not IsEmpty(ws.Cells(r, colVisualType)) Then
    jsonStr = jsonStr & """visual_type"": """ & CStr(ws.Cells(r, colVisualType).Value) & ""","
Else
    jsonStr = jsonStr & """visual_type"": """","
End If
```

#### Valid values for enemy abilities:

```
melee_single       — Standard melee strike
melee_combo_2      — Two-hit melee combo
dash_attack        — Rush forward then strike
ranged_attack      — Enemy ranged (no aiming)
spell_cast         — Cast-time spell
howl               — Wolf howl (custom)
```

Same fallback rule: empty means use the automatic mapping from Phase 5.

---

### VBA File 3: `databases/vba/MasterExport.bas`

#### In `ValidateAll`:

Add validation for the `visual_type` field — it should be either empty or one of the known template IDs:

```vba
' Validate visual_type (if present)
Dim validVisualTypes As String
validVisualTypes = ",melee_single,melee_combo_2,melee_combo_3,dash_attack,ranged_aim,ranged_attack,spell_cast,spell_instant,throw,self_buff,howl,"

If Not IsEmpty(ws.Cells(r, colVisualType)) Then
    Dim vt As String
    vt = CStr(ws.Cells(r, colVisualType).Value)
    If InStr(1, validVisualTypes, "," & vt & ",") = 0 Then
        errorCount = errorCount + 1
        Debug.Print "  ERROR: Row " & r & " - Invalid visual_type: " & vt
    End If
End If
```

#### In `SetupWorkbook`:

Add `visual_type` to the column headers for both the Skills and Abilities sheets.

---

### VBA File 4: `databases/vba/SharedValidation.bas`

Add `visual_type` to the named ranges if applicable (for dropdown validation in Excel).

---

## What To Modify in GDScript

### File 1: `scripts/data/talent_data.gd`

Add the field and parse it:

```gdscript
## Visual template override (empty = auto-detect from effect_type)
@export var visual_type: String = ""

## In from_dict():
talent.visual_type = data.get("visual_type", "")
```

### File 2: `scripts/data/ability_data.gd`

Add the field:

```gdscript
## Visual template override (empty = auto-detect from ability type)
@export var visual_type: String = ""
```

Also update `from_dict()` if AbilityData has one, or the database loading logic in `DatabaseLoader`.

### File 3: `scripts/ui/combat/combat_hud.gd`

Update `_get_visual_template_for_talent()` to check the explicit field first:

```gdscript
static func _get_visual_template_for_talent(talent: TalentData) -> String:
    # Explicit override takes priority
    if not talent.visual_type.is_empty():
        return talent.visual_type

    # Auto-detect fallback (existing code from Phase 4)
    match talent.effect_type:
        TalentData.EffectType.DAMAGE:
            return "melee_single"
        # ... etc
```

### File 4: `scripts/npc/enemy_npc.gd`

Update `_get_visual_template_for_ability()` to check the explicit field first:

```gdscript
static func _get_visual_template_for_ability(ability: AbilityData) -> String:
    # Explicit override takes priority
    if not ability.visual_type.is_empty():
        return ability.visual_type

    # Check custom animation field (for things like "howl")
    if ability.animation != "attack" and ability.animation != "":
        if AbilityVisualTemplates.get_all().has(ability.animation):
            return ability.animation

    # Auto-detect fallback (existing code from Phase 5)
    match ability.type:
        AbilityData.AbilityType.MELEE:
            return "melee_single"
        # ... etc
```

---

## Excel Data Updates

### Skills Sheet — Add visual_type Values

For existing player talents, populate the `visual_type` column. Here are the recommended values based on the current talent data:

| Talent ID | Current effect_type | Recommended visual_type |
|-----------|-------------------|----------------------|
| (melee skills with DAMAGE) | DAMAGE | `melee_single` (or leave empty for auto) |
| (ranged skills with PROJECTILE) | PROJECTILE | `ranged_aim` (or leave empty) |
| (magic with MAGIC_PROJECTILE) | MAGIC_PROJECTILE | `spell_cast` (or leave empty) |
| (magic with MAGIC_PROJECTILE_AOE) | MAGIC_PROJECTILE_AOE | `spell_cast` (or leave empty) |
| (buffs with SELF_BUFF) | SELF_BUFF | `self_buff` (or leave empty) |

Since the auto-detection already works correctly for all current abilities, leaving the column **empty for all existing rows** is perfectly fine. The field becomes useful when:
- A new melee skill should use `melee_combo_2` instead of `melee_single`
- A throw ability is added (effect_type PROJECTILE but visual_type `throw`)
- Any ability needs a non-default visual

### Abilities Sheet — Add visual_type Values

Same approach for enemy abilities. Recommended explicit values only where auto-detection wouldn't give the right result:

| Ability ID | Current type | Recommended visual_type |
|-----------|-------------|----------------------|
| Blood Howl | AOE | `howl` (explicit — auto would give `spell_cast`) |
| (everything else) | varies | (leave empty for auto) |

---

## Stat Descriptions

### `databases/vba/StatDescriptionDatabase.bas`

Add a description entry for `visual_type`:

```
visual_type — Determines the animation template used when this ability is activated. Controls the sequence of body animations, weapon visibility, movement, and VFX timing. Leave empty to auto-detect from ability type.
```

---

## What NOT To Do In This Phase

- Do NOT add new visual templates (that can be done incrementally after the system is live)
- Do NOT change the sequencer or CharacterVisuals code
- Do NOT edit JSON files directly — only provide VBA changes and data

---

## Testing / Validation

1. Export the database with the new `visual_type` column — JSON should include the field.
2. A talent with `visual_type: "melee_combo_2"` should use the two-hit combo template.
3. A talent with empty `visual_type` should fall back to automatic detection (no change in behavior).
4. The wolf's Blood Howl with `visual_type: "howl"` should play the howl animation.
5. An invalid `visual_type` value should be caught by `ValidateAll` in the VBA.
6. All existing abilities should work identically to before (empty visual_type = auto-detect).

---

## Existing Code Reference

| File | Why |
|------|-----|
| `databases/vba/SkillDatabase.bas` | Player talent export — add visual_type column |
| `databases/vba/AbilityDatabase.bas` | Enemy ability export — add visual_type column |
| `databases/vba/MasterExport.bas` | Validation and setup — add visual_type validation |
| `databases/vba/SharedValidation.bas` | Named ranges and enums |
| `databases/vba/StatDescriptionDatabase.bas` | Stat descriptions |
| `scripts/data/talent_data.gd` | Add visual_type property + parsing |
| `scripts/data/ability_data.gd` | Add visual_type property |
| `scripts/ui/combat/combat_hud.gd` | Use visual_type in template selection |
| `scripts/npc/enemy_npc.gd` | Use visual_type in template selection |
| `scripts/combat/ability_visual_templates.gd` | Template IDs referenced by visual_type values |

---

*This prompt is Phase 6 of 6 in the Ability Visual System implementation.*
