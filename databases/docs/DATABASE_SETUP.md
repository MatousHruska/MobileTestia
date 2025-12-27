# Database Setup Guide

This guide explains how to set up and use the Excel database system for MobileTestia.

## Quick Start

1. Create a new Excel workbook (`.xlsm` - macro-enabled)
2. Import all VBA modules from the `vba/` folder
3. Run `SetupWorkbook` macro to create all sheets
4. Add your data
5. Run `ExportAll` to generate JSON files
6. Copy JSON files to `databases/exports/` in your Godot project

---

## Importing VBA Modules

### In Excel:
1. Press `Alt + F11` to open VBA Editor
2. Right-click on your workbook in Project Explorer
3. Select **Import File...**
4. Import each `.bas` file from the `vba/` folder:
   - `SharedValidation.bas`
   - `ItemDatabase.bas`
   - `EnemyDatabase.bas`
   - `LootTableDatabase.bas`
   - `SkillDatabase.bas`
   - `QuestDatabase.bas`
   - `MasterExport.bas`
5. Save workbook as `.xlsm` (macro-enabled)

---

## Running Macros

### Via Developer Tab:
1. Enable Developer tab: File → Options → Customize Ribbon → Check "Developer"
2. Click **Macros** button
3. Select and run:
   - `SetupWorkbook` - Creates all sheets with headers
   - `ValidateAll` - Validates all data
   - `ExportAll` - Exports all to JSON
   - `AddDebugItems` - Adds test/debug items

### Via VBA Editor (Alt + F11):
1. Press `Ctrl + G` to open Immediate Window
2. Type command and press Enter:
   ```
   SetupWorkbook
   ValidateAll
   ExportAll
   ```

---

## Sheet Structures

### ItemBases
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `wep_sword_iron` |
| name | string | Yes | `Iron Sword` |
| slot | dropdown | Yes | `Weapon` |
| item_type | dropdown | Yes | `Sword` |
| base_damage | number | No | `15` |
| attack_speed | number | No | `1.2` |
| base_armor | number | No | `0` |
| req_str | number | No | `10` |
| req_dex | number | No | `0` |
| req_int | number | No | `0` |
| allowed_affix_tags | string | No | `physical,melee` |
| description | formula | No | Auto-generated |

**ID Prefixes:**
- `wep_` - Weapons
- `arm_` - Armor
- `acc_` - Accessories (rings, amulets)
- `con_` - Consumables (potions, scrolls)
- `debug_` - Debug/test items (reserved)

### Affixes
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `pre_fiery` or `suf_bear` |
| name | string | Yes | `Fiery` or `of the Bear` |
| type | dropdown | Yes | `prefix` or `suffix` |
| stat_modifier | dropdown | Yes | `fire_damage` |
| min_value | number | Yes | `5` |
| max_value | number | Yes | `15` |
| spawn_weight | number | No | `100` |
| item_level_min | number | No | `1` |
| item_level_max | number | No | `100` |
| allowed_tags | string | No | `weapon,melee` |

### UniqueItems
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `unq_sword_death` |
| name | string | Yes | `Sword of Death` |
| base_id | string | Yes | `wep_sword_iron` |
| fixed_stats | string | Yes | `melee_damage:50,critical_chance:25` |
| special_ability | string | No | `on_kill_heal_10` |
| lore_text | string | No | `Forged in darkness...` |
| drop_weight | number | No | `10` |
| min_level | number | No | `20` |

### Enemies
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `ene_zombie_basic` |
| name | string | Yes | `Zombie` |
| type | dropdown | Yes | `Normal`, `Miniboss`, `Boss` |
| base_health | number | Yes | `100` |
| base_damage | number | Yes | `10` |
| armor | number | No | `5` |
| move_speed | number | No | `80` |
| attack_speed | number | No | `1.0` |
| attack_range | number | No | `24` |
| detection_range | number | No | `150` |
| xp_reward | number | No | `25` |
| loot_table_id | string | No | `loot_zombie_basic` |
| ability_ids | string | No | `ability_bite,ability_grab` |
| description | string | No | `A shambling corpse...` |

### LootTables
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `loot_zombie_basic` |
| name | string | Yes | `Zombie Drops` |
| min_drops | number | No | `1` |
| max_drops | number | No | `3` |
| nothing_weight | number | No | `50` |
| common_weight | number | No | `100` |
| magic_weight | number | No | `30` |
| rare_weight | number | No | `10` |
| unique_weight | number | No | `1` |
| gold_min | number | No | `5` |
| gold_max | number | No | `20` |
| item_pool | string | No | `wep_,arm_` (prefixes or specific IDs) |
| guaranteed_drops | string | No | `con_pot_health_small` |

### Skills
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `skl_combat_powerattack` |
| name | string | Yes | `Power Attack` |
| type | dropdown | Yes | `active`, `passive`, `buff`, `toggle` |
| tree | dropdown | Yes | `combat`, `magic`, `utility` |
| tier | number | Yes | `1` (1-5) |
| max_level | number | No | `5` |
| mana_cost | number | No | `0` |
| stamina_cost | number | No | `20` |
| cooldown | number | No | `3` |
| base_damage | number | No | `25` |
| damage_per_level | number | No | `5` |
| effect_type | dropdown | No | `damage`, `buff`, etc. |
| effect_value | number | No | `0` |
| effect_per_level | number | No | `0` |
| duration | number | No | `0` |
| prerequisite_ids | string | No | `skl_combat_slash` |
| description | string | No | `A powerful overhead strike` |
| icon_name | string | No | `skl_combat_powerattack` (defaults to id) |

### Quests
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `qst_main_firstbattle` |
| name | string | Yes | `First Battle` |
| type | dropdown | Yes | `main`, `side`, `daily`, `event` |
| giver_npc | string | No | `npc_guard_captain` |
| min_level | number | No | `1` |
| prerequisite_quests | string | No | `qst_main_intro` |
| objective_ids | string | Yes | `obj_kill_zombies_5` |
| xp_reward | number | No | `100` |
| gold_reward | number | No | `50` |
| item_rewards | string | No | `wep_sword_iron` |
| loot_table_reward | string | No | `loot_quest_reward_tier1` |
| description | string | No | `Defeat the zombie threat` |
| completion_text | string | No | `Well done, hero!` |

---

## Data Validation (Dropdowns)

To prevent typos, add Data Validation to these columns:

### How to Add:
1. Select the column (click column letter)
2. Data → Data Validation
3. Allow: **List**
4. Source: Type values comma-separated

### Recommended Validations:

| Sheet | Column | Values |
|-------|--------|--------|
| ItemBases | slot | `Weapon,Head,Chest,Hands,Legs,Feet,Ring,Amulet,Offhand` |
| ItemBases | item_type | `Sword,Axe,Mace,Dagger,Staff,Wand,Bow,Shield,...` |
| Affixes | type | `prefix,suffix` |
| Affixes | stat_modifier | (see StatModifiers sheet) |
| Enemies | type | `Normal,Miniboss,Boss` |
| Skills | type | `active,passive,buff,toggle` |
| Skills | tree | `combat,magic,utility,class` |
| Quests | type | `main,side,daily,event,tutorial` |

---

## ID Naming Convention

**Format:** `category_type_name`

### Examples:
```
wep_sword_iron        ✓ Good
wep_axe_battle_heavy  ✓ Good (4 parts ok)
Sword                 ✗ Bad (no prefix)
wep_Sword_Iron        ✗ Bad (uppercase)
wep-sword-iron        ✗ Bad (hyphens)
```

### Why This Matters:
- Sorting by ID groups related items
- Easy to spot missing items
- No collisions between categories
- Sprite files match: `wep_sword_iron.png`

---

## Description Builder (Formulas)

Instead of manually typing descriptions, use formulas:

### Example for ItemBases:
In the `description` column, enter:
```excel
=IF(E2>0,"Damage: "&E2&" | ","")&IF(G2>0,"Armor: "&G2&" | ","")&IF(H2>0,"Req STR: "&H2,"")
```

This auto-generates: `Damage: 15 | Req STR: 10`

### Example for Affixes:
```excel
="Adds "&E2&"-"&F2&" "&PROPER(SUBSTITUTE(D2,"_"," "))
```

This auto-generates: `Adds 5-15 Fire Damage`

---

## Debug Items (Reserved Rows)

Keep the first 5 rows of ItemBases for debug/test items:

| ID | Purpose |
|----|---------|
| `debug_god_sword` | 99999 damage - test boss patterns |
| `debug_god_armor` | 99999 armor - test without dying |
| `debug_weak_sword` | 1 damage - test death animations |
| `debug_all_stats` | +100 all stats - test requirements |
| `debug_xp_boost` | +10000% XP - test leveling |

Run `AddDebugItems` macro to auto-populate these.

---

## Export Workflow

1. **Validate First:**
   ```
   ValidateAll
   ```
   Fix any errors reported.

2. **Export:**
   ```
   ExportAll
   ```
   Creates JSON files in `exports/` folder next to workbook.

3. **Copy to Godot:**
   Copy all `.json` files to your Godot project's `databases/exports/` folder.

4. **Test in Game:**
   The Godot `DatabaseLoader` autoload will read these files.

---

## Troubleshooting

### "Macro not found"
- Ensure workbook is `.xlsm` (macro-enabled)
- Check that modules were imported correctly

### "Sheet not found"
- Run `SetupWorkbook` to create all sheets

### Export fails silently
- Check that `exports/` folder exists
- Ensure no JSON file is open in another program

### Validation errors
- Check ID format matches convention
- Ensure dropdown values match exactly (case-sensitive)
- Verify numeric fields contain numbers, not text
