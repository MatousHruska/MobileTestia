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
   - `NPCDatabase.bas` (NEW)
   - `GameplayDatabase.bas` (NEW - for Consumables, StatusEffects, Zones)
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

## Complete Database List

### Item System
- **ItemBases** - Base items (weapons, armor, accessories)
- **Affixes** - Prefixes and suffixes for magic items
- **UniqueItems** - Legendary/unique items with fixed stats
- **Consumables** - Potions, scrolls, food items

### Enemy System
- **Enemies** - Enemy base definitions
- **EnemyAbilities** - Special abilities enemies can use
- **EnemyVariants** - Modifiers for enemies (Enraged, Elite, etc.)
- **LootTables** - What enemies/chests drop

### Quest System
- **Quests** - Quest definitions
- **QuestObjectives** - Individual quest tasks

### NPC & Trading System
- **NPCs** - Friendly NPCs, traders, quest givers
- **ShopInventory** - What NPCs sell

### Gameplay Systems
- **Skills** - Player skills and abilities
- **StatusEffects** - Buffs, debuffs, DoTs
- **Zones** - Game areas and their properties

---

# Sheet Structures

## Item System

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
- `mat_` - Crafting materials
- `debug_` - Debug/test items (reserved)

**Valid Slots:** `Weapon`, `Head`, `Chest`, `Hands`, `Legs`, `Feet`, `Ring`, `Amulet`, `Offhand`

**Valid Item Types:** `Sword`, `Axe`, `Mace`, `Dagger`, `Staff`, `Wand`, `Bow`, `Crossbow`, `Shield`, `Helmet`, `Chest`, `Gloves`, `Boots`, `Leggings`, `Ring`, `Amulet`

---

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

**ID Prefixes:**
- `pre_` - Prefix affixes (e.g., "Sharp Iron Sword")
- `suf_` - Suffix affixes (e.g., "Iron Sword of the Bear")

**Valid Stat Modifiers:**
- Damage: `melee_damage`, `ranged_damage`, `magic_damage`, `fire_damage`, `cold_damage`, `lightning_damage`, `poison_damage`
- Attributes: `strength`, `dexterity`, `intelligence`, `vitality`, `energy`, `luck`
- Defense: `armor`, `magic_resistance`, `dodge_chance`
- Combat: `attack_speed`, `critical_chance`, `critical_damage`
- Resources: `life`, `mana`, `life_regen`, `mana_regen`
- Mobility: `movement_speed`

---

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

**ID Prefix:** `unq_`

**Fixed Stats Format:** `stat_name:value,stat_name:value` (e.g., `melee_damage:25,strength:10,critical_chance:15`)

---

### Consumables (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `con_potion_health_small` |
| name | string | Yes | `Small Health Potion` |
| consumable_type | dropdown | Yes | `potion`, `scroll`, `food` |
| effect_type | dropdown | Yes | `heal_health`, `heal_mana`, `buff` |
| effect_value | number | Yes | `50` |
| duration | number | No | `0` (instant) or seconds |
| cooldown | number | No | `0` |
| stack_size | number | No | `20` |
| price_base | number | No | `25` |
| description | string | No | Auto-generated |

**ID Prefix:** `con_`

**Valid Consumable Types:** `potion`, `scroll`, `food`, `elixir`

**Valid Effect Types:**
- `heal_health` - Restore health
- `heal_mana` - Restore mana
- `buff_stat` - Temporary stat boost
- `cure_status` - Remove status effect
- `teleport_town` - Return to town
- `resurrect` - Revive at checkpoint

---

## Enemy System

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

**ID Prefix:** `ene_`

**Valid Types:** `Normal`, `Miniboss`, `Boss`

---

### EnemyAbilities (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `ability_slam` |
| name | string | Yes | `Ground Slam` |
| type | dropdown | Yes | `melee`, `ranged`, `aoe`, `buff` |
| damage | number | No | `25` |
| damage_type | dropdown | Yes | `physical`, `fire`, `cold` |
| cooldown | number | No | `5` |
| range | number | No | `50` |
| description | string | No | `Slams the ground...` |

**ID Prefix:** `ability_`

**Valid Ability Types:** `melee`, `ranged`, `aoe`, `buff`, `debuff`, `summon`, `dash`, `teleport`

**Valid Damage Types:** `physical`, `fire`, `cold`, `lightning`, `poison`, `chaos`, `pure`

---

### EnemyVariants (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `var_enraged` |
| name | string | Yes | `Enraged` |
| health_multiplier | number | Yes | `1.5` |
| damage_multiplier | number | Yes | `1.3` |
| xp_multiplier | number | Yes | `1.4` |
| extra_abilities | string | No | `ability_rage,ability_slam` |
| visual_effect | string | No | `red_glow` |

**ID Prefix:** `var_`

**Multiplier Notes:**
- `1.0` = normal (100%)
- `1.5` = 150% (50% more)
- `0.8` = 80% (20% less)

---

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
| item_pool | string | No | `wep_,arm_` |
| guaranteed_drops | string | No | `con_potion_health_small` |

**ID Prefix:** `loot_`

**Item Pool Format:** Comma-separated item ID prefixes or full IDs (e.g., `wep_,arm_,acc_ring_copper`)

**Guaranteed Drops Format:** Comma-separated item IDs (e.g., `con_potion_health_small,mat_bone`)

---

## Quest System

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
| loot_table_reward | string | No | `loot_quest_tier1` |
| description | string | No | `Defeat the zombie threat` |
| completion_text | string | No | `Well done, hero!` |

**ID Prefix:** `qst_`

**Valid Types:** `main`, `side`, `daily`, `event`, `tutorial`

---

### QuestObjectives (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `obj_kill_zombies_5` |
| type | dropdown | Yes | `kill`, `collect`, `talk` |
| target_id | string | Yes | `ene_zombie_basic` |
| count | number | Yes | `5` |
| description | string | No | `Kill 5 zombies` |
| optional | boolean | No | `false` |

**ID Prefix:** `obj_`

**Valid Types:** `kill`, `collect`, `talk`, `explore`, `escort`, `defend`, `craft`, `use`

**Target ID Examples:**
- `kill` → enemy_id (e.g., `ene_zombie_basic`)
- `collect` → item_id (e.g., `mat_zombie_bone`)
- `talk` → npc_id (e.g., `npc_guard_captain`)
- `explore` → zone_id (e.g., `zone_dark_cave`)

---

## NPC & Trading System

### NPCs (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `npc_guard_captain` |
| name | string | Yes | `Captain Marcus` |
| type | dropdown | Yes | `quest_giver`, `trader` |
| location | string | No | `town_square` |
| shop_inventory_id | string | No | `shop_weapons_basic` |
| dialogue_greeting | string | No | `Welcome, traveler!` |
| faction | string | No | `town_guard` |
| sprite_id | string | No | `npc_guard_01` |
| min_level | number | No | `1` |

**ID Prefix:** `npc_`

**Valid Types:** `quest_giver`, `trader`, `trainer`, `innkeeper`, `blacksmith`, `generic`

**Type Descriptions:**
- `quest_giver` - Gives quests to player
- `trader` - Sells items (requires shop_inventory_id)
- `trainer` - Teaches skills
- `innkeeper` - Provides rest/save points
- `blacksmith` - Repairs/upgrades equipment
- `generic` - Ambient NPC with dialogue only

---

### ShopInventory (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `shop_weapons_basic` |
| name | string | Yes | `Basic Weapons` |
| item_id | string | Yes | `wep_sword_iron` |
| item_type | dropdown | Yes | `base`, `unique`, `consumable` |
| stock | number | No | `-1` (infinite) |
| restock_hours | number | No | `24` |
| price_multiplier | number | No | `1.5` |
| currency_type | dropdown | No | `gold`, `gems` |
| min_player_level | number | No | `1` |
| max_player_level | number | No | `100` |

**ID Prefix:** `shop_`

**Valid Item Types:** `base`, `unique`, `consumable`

**Stock Notes:**
- `-1` = Infinite stock (never runs out)
- `>0` = Limited quantity (restocks after restock_hours)
- `0` = Out of stock (one-time purchase)

**Restock Hours:**
- `0` = Never restocks
- `>0` = Hours until restock (e.g., `24` = daily restock)

---

## Gameplay Systems

### Skills
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `skl_combat_powerattack` |
| name | string | Yes | `Power Attack` |
| type | dropdown | Yes | `active`, `passive`, `buff` |
| tree | dropdown | Yes | `combat`, `magic`, `utility` |
| tier | number | Yes | `1` (1-5) |
| max_level | number | No | `5` |
| mana_cost | number | No | `0` |
| stamina_cost | number | No | `20` |
| cooldown | number | No | `3` |
| base_damage | number | No | `25` |
| damage_per_level | number | No | `5` |
| effect_type | dropdown | No | `damage`, `buff` |
| effect_value | number | No | `0` |
| effect_per_level | number | No | `0` |
| duration | number | No | `0` |
| prerequisite_ids | string | No | `skl_combat_slash` |
| description | string | No | `A powerful strike` |
| icon_name | string | No | `skl_combat_powerattack` |

**ID Prefix:** `skl_`

**Valid Types:** `active`, `passive`, `buff`, `toggle`

**Valid Trees:** `combat`, `magic`, `utility`, `class`

**Valid Effect Types:** `damage`, `buff`, `debuff`, `heal`, `teleport`, `summon`

---

### StatusEffects (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `status_poison` |
| name | string | Yes | `Poisoned` |
| type | dropdown | Yes | `debuff_dot`, `buff` |
| stat_affected | string | Yes | `health`, `strength` |
| value | number | Yes | `-5` |
| duration | number | Yes | `10` |
| tick_interval | number | No | `1` |
| visual_effect | string | No | `poison_cloud` |
| stackable | boolean | No | `true` |
| max_stacks | number | No | `5` |
| description | string | No | Auto-generated |

**ID Prefix:** `status_`

**Valid Types:**
- `buff` - Positive effect (increases stats)
- `debuff` - Negative effect (decreases stats)
- `debuff_dot` - Damage over time
- `buff_hot` - Heal over time
- `control` - Stun, freeze, slow, etc.

**Value Notes:**
- Positive values = beneficial
- Negative values = harmful
- For DoTs/HoTs, this is damage/heal per tick

**Tick Interval:** Seconds between damage/heal ticks (0 = one-time effect)

---

### Zones (NEW)
| Column | Type | Required | Example |
|--------|------|----------|---------|
| id | string | Yes | `zone_dark_forest` |
| name | string | Yes | `Dark Forest` |
| zone_type | dropdown | Yes | `outdoor`, `dungeon`, `town` |
| min_level | number | Yes | `3` |
| max_level | number | Yes | `8` |
| enemy_spawn_list | string | Yes | `ene_zombie_basic,ene_skeleton` |
| loot_table_id | string | No | `loot_forest_common` |
| respawn_time | number | No | `60` |
| music_track | string | No | `music_forest_ambient` |
| description | string | No | `A dangerous forest...` |

**ID Prefix:** `zone_`

**Valid Zone Types:** `outdoor`, `dungeon`, `cave`, `town`, `boss_room`, `camp`

**Enemy Spawn List Format:** Comma-separated enemy IDs (e.g., `ene_zombie_basic,ene_skeleton_warrior,ene_goblin`)

**Respawn Time:** Seconds until enemies respawn in this zone

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
| ItemBases | item_type | `Sword,Axe,Mace,Dagger,Staff,Wand,Bow,Shield,Helmet,Chest,Gloves,Boots,Ring,Amulet` |
| Affixes | type | `prefix,suffix` |
| Affixes | stat_modifier | (see StatModifiers reference list below) |
| Consumables | consumable_type | `potion,scroll,food,elixir` |
| Consumables | effect_type | `heal_health,heal_mana,buff_stat,cure_status,teleport_town,resurrect` |
| Enemies | type | `Normal,Miniboss,Boss` |
| EnemyAbilities | type | `melee,ranged,aoe,buff,debuff,summon,dash,teleport` |
| EnemyAbilities | damage_type | `physical,fire,cold,lightning,poison,chaos,pure` |
| NPCs | type | `quest_giver,trader,trainer,innkeeper,blacksmith,generic` |
| ShopInventory | item_type | `base,unique,consumable` |
| ShopInventory | currency_type | `gold,gems` |
| Skills | type | `active,passive,buff,toggle` |
| Skills | tree | `combat,magic,utility,class` |
| StatusEffects | type | `buff,debuff,debuff_dot,buff_hot,control` |
| Zones | zone_type | `outdoor,dungeon,cave,town,boss_room,camp` |
| Quests | type | `main,side,daily,event,tutorial` |
| QuestObjectives | type | `kill,collect,talk,explore,escort,defend,craft,use` |

### Valid Stat Modifiers (for Affixes):
`melee_damage,ranged_damage,magic_damage,fire_damage,cold_damage,lightning_damage,poison_damage,strength,dexterity,intelligence,vitality,energy,luck,armor,magic_resistance,dodge_chance,attack_speed,critical_chance,critical_damage,life,mana,life_regen,mana_regen,movement_speed`

---

## ID Naming Convention

**Format:** `category_type_name`

### Category Prefixes:
| Prefix | Category | Examples |
|--------|----------|----------|
| `wep_` | Weapons | `wep_sword_iron`, `wep_bow_short` |
| `arm_` | Armor | `arm_helmet_iron`, `arm_chest_leather` |
| `acc_` | Accessories | `acc_ring_copper`, `acc_amulet_jade` |
| `con_` | Consumables | `con_potion_health_small`, `con_scroll_teleport` |
| `mat_` | Materials | `mat_iron_ore`, `mat_leather` |
| `pre_` | Prefix Affixes | `pre_sharp`, `pre_flaming` |
| `suf_` | Suffix Affixes | `suf_bear`, `suf_agility` |
| `unq_` | Unique Items | `unq_sword_flamebrand`, `unq_ring_lifesteal` |
| `ene_` | Enemies | `ene_zombie_basic`, `ene_dragon_ancient` |
| `ability_` | Enemy Abilities | `ability_slam`, `ability_fireball` |
| `var_` | Enemy Variants | `var_enraged`, `var_frozen` |
| `loot_` | Loot Tables | `loot_zombie_basic`, `loot_tier1_boss` |
| `npc_` | NPCs | `npc_guard_captain`, `npc_trader_weapons` |
| `shop_` | Shop Inventories | `shop_weapons_basic`, `shop_consumables` |
| `skl_` | Skills | `skl_combat_powerattack`, `skl_magic_fireball` |
| `status_` | Status Effects | `status_poison`, `status_haste` |
| `zone_` | Zones | `zone_dark_forest`, `zone_goblin_camp` |
| `qst_` | Quests | `qst_main_intro`, `qst_side_bones` |
| `obj_` | Quest Objectives | `obj_kill_zombies_5`, `obj_collect_bones` |
| `debug_` | Debug Items | `debug_god_sword`, `debug_all_stats` |

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
- Code can filter by prefix: `item_bases.keys().filter(func(k): return k.begins_with("wep_"))`

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

### Example for Consumables:
```excel
="Restores "&E2&" "&SUBSTITUTE(D2,"heal_","")
```

This auto-generates: `Restores 50 health`

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

## Exported JSON Files

After running `ExportAll`, you should have these files:

### Item System
- `item_bases.json`
- `affixes.json`
- `unique_items.json`
- `consumables.json`

### Enemy System
- `enemies.json`
- `enemy_abilities.json`
- `enemy_variants.json`
- `loot_tables.json`

### Quest System
- `quests.json`
- `quest_objectives.json`

### NPC & Trading
- `npcs.json`
- `shop_inventory.json`

### Gameplay Systems
- `skills.json`
- `status_effects.json`
- `zones.json`

---

## Placeholder Data

Use these placeholder entries to test your setup:

### Copy-Paste Format (Tab-Separated)

**Consumables:**
```
id	name	consumable_type	effect_type	effect_value	duration	cooldown	stack_size	price_base	description
con_potion_health_small	Small Health Potion	potion	heal_health	50	0	0	20	25	Restores 50 health instantly
con_potion_mana_small	Small Mana Potion	potion	heal_mana	30	0	0	20	20	Restores 30 mana instantly
con_scroll_teleport_town	Town Portal Scroll	scroll	teleport_town	0	0	5	5	100	Teleports you back to town
con_food_bread	Bread	food	heal_health	20	0	0	50	5	Slowly restores 20 health
```

**StatusEffects:**
```
id	name	type	stat_affected	value	duration	tick_interval	visual_effect	stackable	max_stacks	description
status_poison	Poisoned	debuff_dot	health	-5	10	1	poison_cloud	true	3	Takes 5 damage per second
status_burn	Burning	debuff_dot	health	-8	6	1	fire_particles	false	1	Takes 8 damage per second
status_strength	Strength Buff	buff	strength	10	30	0	red_aura	false	1	Increases strength by 10
status_haste	Haste	buff	attack_speed	25	15	0	speed_lines	false	1	Increases attack speed by 25%
```

**Zones:**
```
id	name	zone_type	min_level	max_level	enemy_spawn_list	loot_table_id	respawn_time	music_track	description
zone_dark_forest	Dark Forest	outdoor	3	8	ene_zombie_basic,ene_skeleton_warrior	loot_forest_common	60	music_forest	A dangerous forest filled with undead
zone_goblin_camp	Goblin Camp	camp	5	10	ene_goblin_basic,ene_goblin_shaman	loot_goblin_camp	120	music_goblin	Goblin encampment in the hills
zone_training_grounds	Training Grounds	outdoor	1	3	ene_training_dummy	loot_training	30	music_town	Safe area for new adventurers
```

**NPCs:**
```
id	name	type	location	shop_inventory_id	dialogue_greeting	faction	sprite_id	min_level
npc_guard_captain	Captain Marcus	quest_giver	town_square		Greetings, citizen. The town needs your help!	town_guard	npc_guard_01	1
npc_trader_weapons	Weapon Merchant	trader	marketplace	shop_weapons_basic	Looking for quality weapons?	merchant_guild	npc_merchant_01	1
npc_trader_armor	Armor Dealer	trader	marketplace	shop_armor_basic	The finest armor in the land!	merchant_guild	npc_merchant_02	1
npc_trainer_combat	Combat Trainer	trainer	training_grounds		Want to improve your combat skills?	town_guard	npc_trainer_01	3
npc_blacksmith	Forge Master Durin	blacksmith	smithy	shop_smithing	Need repairs or upgrades?	craftsmen_guild	npc_blacksmith_01	1
npc_innkeeper	Innkeeper Sarah	innkeeper	inn		Rest and recover, weary traveler.	neutral	npc_innkeeper_01	1
```

**ShopInventory:**
```
id	name	item_id	item_type	stock	restock_hours	price_multiplier	currency_type	min_player_level	max_player_level
shop_weapons_basic	Basic Weapons	wep_sword_iron	base	-1	0	1.5	gold	1	10
shop_weapons_basic	Basic Weapons	wep_dagger_iron	base	-1	0	1.5	gold	1	10
shop_weapons_basic	Basic Weapons	wep_staff_oak	base	-1	0	1.5	gold	1	10
shop_armor_basic	Basic Armor	arm_helmet_leather	base	-1	0	1.5	gold	1	10
shop_armor_basic	Basic Armor	arm_chest_leather	base	-1	0	1.5	gold	1	10
shop_consumables	Potions & Scrolls	con_potion_health_small	consumable	50	24	2.0	gold	1	100
shop_consumables	Potions & Scrolls	con_potion_mana_small	consumable	50	24	2.0	gold	1	100
shop_smithing	Smithing Materials	mat_iron_ore	base	20	48	1.8	gold	5	100
```

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
- Check ID format matches convention (lowercase, underscores, correct prefix)
- Ensure dropdown values match exactly (case-sensitive)
- Verify numeric fields contain numbers, not text
- For affixes: stat_modifier must match valid list exactly
- For loot tables: ID must follow `loot_type_name` format

### Common ID Format Mistakes
- ❌ `loot_boss_tier1` → ✅ `loot_tier1_boss` (type comes before descriptor)
- ❌ `pre_Sharp` → ✅ `pre_sharp` (all lowercase)
- ❌ `npc-trader` → ✅ `npc_trader` (underscores, not hyphens)
- ❌ `FireDamage` → ✅ `fire_damage` (stat modifiers are lowercase with underscores)

---

## Best Practices

1. **Always validate before exporting** - Catch errors early
2. **Use consistent naming** - Follow ID conventions strictly
3. **Test with placeholder data first** - Ensure systems work before adding real data
4. **Back up your Excel file regularly** - Keep version history
5. **Document custom formulas** - Add comments for complex calculations
6. **Use dropdowns extensively** - Prevent typos in critical fields
7. **Start small, expand gradually** - Add a few items per sheet first, then expand
8. **Keep debug items** - Useful for testing throughout development

---

## Next Steps

1. ✅ Set up your Excel workbook with all sheets
2. ✅ Import VBA modules
3. ✅ Run `SetupWorkbook` to create sheet headers
4. ✅ Add placeholder data from this guide
5. ✅ Run `ValidateAll` and fix any errors
6. ✅ Run `ExportAll` to generate JSON files
7. ✅ Copy JSON files to Godot project
8. ✅ Test in-game to verify databases load correctly
9. 🔄 Expand with your actual game content
10. 🔄 Iterate and refine as needed

Happy database building! 🎮
