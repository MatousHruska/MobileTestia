# Phase 2: Legacy AI Cleanup - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase2-Cleanup into its name. We will continue our work from here.
```

**IMPORTANT:** Replace `[BRANCH_NAME]` with the actual branch name from your last session before pasting this prompt.

---

## CRITICAL: Database Workflow

> **NEVER EDIT `.json` FILES DIRECTLY!**
>
> The database is managed through Excel with VBA macros. Direct JSON edits will be overwritten.
>
> **Correct workflow:**
> 1. **First:** Provide updated `.bas` VBA files for any schema changes
> 2. **Second:** Provide Excel-ready data to paste into sheets
> 3. **Third:** User imports VBA, pastes data, runs `ExportAll`
>
> When you need to change database structure or data:
> - Give me the `.bas` file updates (if schema changes)
> - Give me tab-separated or table data ready to paste into Excel
> - I will import/paste and export the JSON myself

---

## Context: Why Clean Slate?

### Problem with Hybrid Approach
Phase 1 tried to build the modular system alongside the legacy EnemyBehavior system. This created:
- **Two AI systems fighting** - EnemyBehavior and ModuleController both trying to control the enemy
- **Ability system coupling** - The `ability_ids` / `behavior_profile` approach was tightly integrated with legacy
- **Mixed responsibilities** - Unclear what controls attack timing, movement, target detection
- **Debugging nightmare** - Hard to know which system is causing issues

### New Approach: Clean Slate
1. **Phase 2 (THIS)**: Remove legacy AI code
2. **Phase 3**: Rebuild modular system from scratch
3. **Phase 4**: Create enemies with new system
4. **Phase 5**: Testing and polish

This gives us a clean foundation without legacy conflicts.

---

## Important Workflows

### VBA/Excel Database Workflow

The game uses Excel with VBA macros for database management.

**VBA Files Location:** `databases/vba/`

**To Import/Update VBA Modules:**
1. Open `TesiaDatabase.xlsm` in Excel
2. Press `Alt + F11` to open VBA Editor
3. For new modules: File → Import File → Select `.bas` file
4. For updated modules: Right-click existing module → Remove → No (don't export) → then Import the new `.bas` file
5. Close VBA Editor and save the workbook

**Key VBA Commands** (press `Alt + F8` to run):
- `SetupWorkbook` - Creates all sheets with proper headers
- `ExportAll` - Exports all sheets to JSON files
- `ValidateAll` - Validates all data before export

---

## Phase 2 Objectives

**Goal:** Remove legacy AI systems to create a clean slate for modular AI.

### What to REMOVE:

1. **EnemyBehavior class** (`scripts/npc/enemy_behavior.gd`)
   - State machine logic
   - Target acquisition
   - Chase/attack decisions

2. **EnemyAbilityController class** (`scripts/npc/enemy_ability_controller.gd`)
   - Ability selection logic
   - Condition parsing

3. **AbilityExecutor class** (`scripts/npc/ability_executor.gd`)
   - Complex ability execution
   - Hitbox spawning (keep HitboxSpawner itself)

4. **Behavior Profile system**
   - `behavior_profiles.json` data (archive, don't delete file)
   - `BehaviorProfileData` class
   - References in EnemyNPC

5. **Legacy references in EnemyNPC**
   - `behavior` variable and setup
   - `ability_controller` variable and setup
   - `_use_ability_system` flag

### What to KEEP:

1. **EnemyNPC base** - Health, damage, death, loot, signals
2. **BaseCharacter** - Movement physics, animation
3. **StatusEffectComponent** - DoT/buffs still useful
4. **ShieldComponent** - Damage absorption
5. **Spawn system** - SpawnPoint works fine
6. **DatabaseLoader** - Core infrastructure
7. **HitboxSpawner** - Will reuse for module attacks
8. **Module system (Phase 1)** - EnemyContext, BaseModule, ModuleController

### What to SIMPLIFY:

1. **Enemies database** - Remove `behavior_profile`, keep `module_ids`
2. **Enemy Abilities database** - Simplify or archive (modules will handle attacks)

---

## Step-by-Step Implementation

### Step 1: Analyze Legacy Dependencies

Before removing anything, understand what depends on what.

Run this analysis:
```gdscript
# Check what uses EnemyBehavior
# Search for: "behavior.", "EnemyBehavior", "behavior:"

# Check what uses EnemyAbilityController
# Search for: "ability_controller.", "EnemyAbilityController"

# Check what uses behavior_profile
# Search for: "behavior_profile", "BehaviorProfileData"
```

**Create a dependency map showing what calls what.**

### Step 2: Create Backup Branch

Before making changes, ensure you have a backup:
```bash
git checkout -b backup/pre-cleanup-[DATE]
git push origin backup/pre-cleanup-[DATE]
git checkout claude/[WORKING_BRANCH]
```

### Step 3: Remove EnemyBehavior

**File:** `scripts/npc/enemy_behavior.gd`

1. First, disconnect all signals in EnemyNPC that reference behavior:
```gdscript
# Find and remove:
# behavior.target_acquired.connect(...)
# behavior.target_lost.connect(...)
# behavior.attack_performed.connect(...)
```

2. Remove behavior creation in EnemyNPC._ready():
```gdscript
# Find and remove:
# behavior = EnemyBehavior.new()
# behavior.setup(self, profile_data)
# add_child(behavior)
```

3. Remove behavior variable declaration:
```gdscript
# Find and remove:
# var behavior: EnemyBehavior = null
```

4. Delete or archive the file:
```bash
# Option A: Delete
rm scripts/npc/enemy_behavior.gd

# Option B: Archive (safer)
mkdir -p scripts/npc/legacy/
mv scripts/npc/enemy_behavior.gd scripts/npc/legacy/enemy_behavior.gd.bak
```

### Step 4: Remove EnemyAbilityController

**File:** `scripts/npc/enemy_ability_controller.gd`

1. Remove from EnemyNPC._ready():
```gdscript
# Find and remove:
# ability_controller = EnemyAbilityController.new()
# ability_controller.setup(self, abilities)
# add_child(ability_controller)
```

2. Remove variable and related code:
```gdscript
# Find and remove:
# var ability_controller: EnemyAbilityController = null
# var _use_ability_system: bool = true
```

3. Remove attack delegation:
```gdscript
# Find and remove:
# if _use_ability_system and ability_controller:
#     ability_controller.try_attack(target)
```

4. Archive the file:
```bash
mv scripts/npc/enemy_ability_controller.gd scripts/npc/legacy/
```

### Step 5: Remove AbilityExecutor

**File:** `scripts/npc/ability_executor.gd`

This is referenced by EnemyAbilityController, so removing that should make this unused.

```bash
mv scripts/npc/ability_executor.gd scripts/npc/legacy/
```

### Step 6: Clean Up EnemyNPC

After removing the above, EnemyNPC should be simplified.

**Keep these core responsibilities:**
```gdscript
extends BaseCharacter
class_name EnemyNPC

# Identity
var enemy_id: String = ""
var enemy_name: String = ""
var enemy_level: int = 1

# Stats
var max_health: float = 100.0
var current_health: float = 100.0
var base_damage: float = 10.0
var armor: float = 0.0
var move_speed: float = 80.0
var attack_radius: float = 24.0
var detection_radius: float = 120.0

# State
var is_dead: bool = false
var home_position: Vector2 = Vector2.ZERO

# Components (keep these)
var shield_component: ShieldComponent = null
var status_effect_component: StatusEffectComponent = null

# Modular AI (from Phase 1)
var module_controller: ModuleController = null

# Signals
signal died()
signal health_changed(current: float, max_hp: float)
signal damaged(amount: float, source: Node2D)
```

**Remove these:**
```gdscript
# DELETE THESE:
var behavior: EnemyBehavior = null
var ability_controller: EnemyAbilityController = null
var _use_ability_system: bool = true
```

### Step 7: Simplify Database Schema

**Update enemies.json structure:**

BEFORE (complex):
```json
{
  "id": "ene_zombie_basic",
  "name": "Zombie",
  "base_health": 30,
  "ability_ids": "abl_zombie_bite,abl_zombie_slam",
  "behavior_profile": "bhv_zombie_shamble",
  "module_ids": "mod_target_detection,mod_chase,mod_melee_attack"
}
```

AFTER (simplified):
```json
{
  "id": "ene_zombie_basic",
  "name": "Zombie",
  "base_health": 30,
  "base_damage": 5,
  "armor": 0,
  "move_speed": 80,
  "attack_range": 25,
  "detection_range": 120,
  "xp_reward": 15,
  "loot_table_id": "loot_zombie",
  "module_ids": "mod_target_detection,mod_chase,mod_melee_attack"
}
```

**Fields to REMOVE from Enemies sheet:**
- `ability_ids` (modules handle attacks now)
- `behavior_profile` (deprecated)
- `attack_speed` (modules control timing)

**Fields to KEEP:**
- All stat fields (health, damage, armor, speed, ranges)
- `module_ids` (this is the new AI system)
- `loot_table_id` (still need loot)
- `xp_reward` (still need rewards)

### Step 8: Archive Behavior Profiles

Don't delete `behavior_profiles.json` - just clear it or mark as deprecated:

```json
{
  "behavior_profiles": [],
  "_note": "DEPRECATED - Enemy AI now uses module_ids system. See enemy_modules.json"
}
```

### Step 9: Archive Enemy Abilities (Optional)

The `enemy_abilities.json` had complex ability definitions. For now, archive it:

```json
{
  "enemy_abilities": [],
  "_note": "DEPRECATED - Attacks now handled by combat modules with simpler configs"
}
```

Or keep specific abilities that might be useful as reference for module configs.

### Step 10: Update VBA Files

Update the VBA export to remove deprecated columns.

**EnemyDatabase.bas changes:**
- Remove `COL_EN_ABILITY_IDS`
- Remove `COL_EN_BEHAVIOR_PROFILE`
- Remove `COL_EN_ATTACK_SPEED`
- Keep `COL_EN_MODULE_IDS`

**SetupEnemiesSheet changes:**
```vba
headers = Array("id", "name", "type", "base_health", "base_damage", "armor", "base_shield", _
                "move_speed", "attack_range", "detection_range", _
                "xp_reward", "loot_table_id", "module_ids", "description")
```

---

## Testing After Cleanup

### Test 1: Game Starts Without Errors

Run the game. There should be NO errors about missing:
- EnemyBehavior
- EnemyAbilityController
- AbilityExecutor
- behavior_profile

### Test 2: Enemies Still Spawn

Go to meadow zone. Enemies should:
- Spawn from spawn points
- Have health bars
- Be targetable
- Take damage and die

They will NOT:
- Chase the player (no AI yet)
- Attack (no combat modules active yet)

This is expected! We're just cleaning up, not rebuilding yet.

### Test 3: No Orphaned References

Search codebase for any remaining references:
```bash
grep -r "EnemyBehavior" scripts/
grep -r "ability_controller" scripts/
grep -r "behavior_profile" scripts/
```

All should return empty or only find archived/legacy files.

### Test 4: Database Loads

Check DatabaseLoader still works:
```gdscript
var enemy = DatabaseLoader.get_enemy("ene_zombie_basic")
print(enemy)  # Should print enemy data without errors
```

---

## Deliverables Checklist

Before ending this session, verify:

### Code Removal
- [ ] `enemy_behavior.gd` removed or archived
- [ ] `enemy_ability_controller.gd` removed or archived
- [ ] `ability_executor.gd` removed or archived
- [ ] `behavior_profile_data.gd` removed or archived
- [ ] EnemyNPC cleaned of legacy references
- [ ] No errors on game start

### Database Cleanup
- [ ] `enemies.json` simplified (no ability_ids, behavior_profile)
- [ ] `behavior_profiles.json` archived/emptied
- [ ] `enemy_abilities.json` archived (optional)
- [ ] VBA files updated

### Documentation
- [ ] List of what was removed
- [ ] Any issues encountered
- [ ] Ready for Phase 3

---

## What to Report Back

After cleanup, tell me:

1. **What was removed?** List all files/code deleted
2. **Any issues?** Anything that couldn't be removed cleanly
3. **Remaining references?** Any code still referencing legacy systems
4. **Database state?** Is the simplified schema working?
5. **Game state?** Does it start without errors?

---

## What's Next (Phase 3 Preview)

With legacy code removed, Phase 3 will:
1. Redesign EnemyContext for clean module communication
2. Create simple, focused modules:
   - DetectionModule (find targets)
   - ChaseModule (move toward target)
   - BasicAttackModule (simple melee damage)
   - RoamModule (idle wandering)
3. Make EnemyNPC purely module-driven
4. No backwards compatibility concerns!

The clean slate lets us design properly without legacy constraints.
