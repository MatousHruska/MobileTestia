# Phase 3: Clean Modular Foundation - Session Prompt

## FIRST: Pull the Latest Branch

```
Please pull claude/[BRANCH_NAME]

This is the newest version of the codebase. Clone it and add Phase3-Foundation into its name. We will continue our work from here.
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

## Context: What We Did Before

### Phase 2 Completed (Legacy Cleanup):
- Removed EnemyBehavior class
- Removed EnemyAbilityController class
- Removed AbilityExecutor class
- Archived behavior_profiles.json
- Simplified enemies.json (removed ability_ids, behavior_profile)
- EnemyNPC is now a clean slate

### Current State:
- Enemies spawn but have NO AI (they just stand there)
- Module system infrastructure exists (EnemyContext, BaseModule, ModuleController)
- Phase 1 modules exist but may need revision (DetectionModule, ChaseModule, MeleeAttackModule)

Now we rebuild the AI system properly from scratch.

---

## Important Workflows

### VBA/Excel Database Workflow

**VBA Files Location:** `databases/vba/`

**Key VBA Commands** (press `Alt + F8` to run):
- `SetupWorkbook` - Creates all sheets with proper headers
- `ExportAll` - Exports all sheets to JSON files
- `ValidateAll` - Validates all data before export

### Testing in Godot

Test scenes: `tests/unit/`
- Press **F6** to run current scene only
- Check **Output** panel for test results

---

## Phase 3 Objectives

**Goal:** Build a clean, simple modular AI foundation.

### Design Principles:
1. **Simple over complex** - Start with minimal modules, add complexity later
2. **Single responsibility** - Each module does ONE thing
3. **Clear data flow** - Context is the ONLY way modules communicate
4. **No legacy assumptions** - Design fresh without old patterns

### Core Modules to Create:
1. **DetectionModule** - Find and track targets
2. **ChaseModule** - Move toward target
3. **BasicAttackModule** - Deal damage when in range
4. **IdleModule** - Stand/roam when no target
5. **LeashModule** - Return home if too far

### Module Communication:
```
EnemyNPC
    ↓ (creates)
ModuleController
    ↓ (manages)
[Modules] ←→ EnemyContext (shared state)
    ↓ (decisions)
EnemyNPC (applies movement, triggers attack animation)
```

---

## Step-by-Step Implementation

### Step 1: Review and Clean EnemyContext

The EnemyContext from Phase 1 might have legacy assumptions. Let's make it clean.

**File:** `scripts/npc/ai/enemy_context.gd`

```gdscript
extends RefCounted
class_name EnemyContext
## EnemyContext - Shared data structure for AI modules
## Modules READ state and WRITE decisions here

#===============================================================================
# OWNER REFERENCE
#===============================================================================

## Reference to the owning enemy
var owner: Node2D = null

#===============================================================================
# IDENTITY (Set once by owner)
#===============================================================================

var enemy_id: String = ""

#===============================================================================
# POSITION (Updated by owner each frame)
#===============================================================================

var global_position: Vector2 = Vector2.ZERO
var home_position: Vector2 = Vector2.ZERO

#===============================================================================
# STATS (Set from database, read-only for modules)
#===============================================================================

var max_health: float = 100.0
var current_health: float = 100.0
var base_damage: float = 10.0
var move_speed: float = 80.0
var attack_radius: float = 24.0
var detection_radius: float = 120.0
var leash_radius: float = 300.0

## Computed
var health_percent: float:
    get: return current_health / max_health if max_health > 0 else 0.0

#===============================================================================
# TARGET STATE (Written by DetectionModule)
#===============================================================================

var current_target: Node2D = null
var has_valid_target: bool = false
var target_distance: float = INF
var target_direction: Vector2 = Vector2.ZERO

## Frame flags (reset each frame)
var target_just_acquired: bool = false
var target_just_lost: bool = false

#===============================================================================
# SPATIAL STATE (Written by LeashModule)
#===============================================================================

var distance_from_home: float = 0.0
var is_beyond_leash: bool = false

#===============================================================================
# BEHAVIOR STATE
#===============================================================================

enum BehaviorState { IDLE, CHASING, ATTACKING, RETURNING, DEAD }
var behavior_state: BehaviorState = BehaviorState.IDLE

#===============================================================================
# MODULE DECISIONS (Written by modules, read by owner)
#===============================================================================

## Movement
var desired_direction: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
var should_stop: bool = false

## Combat
var should_attack: bool = false
var attack_cooldown_remaining: float = 0.0

## Facing
var facing_direction: Vector2 = Vector2.DOWN

#===============================================================================
# FRAME TIMING
#===============================================================================

var delta: float = 0.0

#===============================================================================
# METHODS
#===============================================================================

func reset_frame_flags() -> void:
    """Called at start of each frame before modules process"""
    target_just_acquired = false
    target_just_lost = false
    should_attack = false
    should_stop = false
    desired_direction = Vector2.ZERO
    speed_multiplier = 1.0


func sync_from_owner() -> void:
    """Update context from owner's current state"""
    if not owner:
        return

    global_position = owner.global_position

    if owner.has_method("get_current_health"):
        current_health = owner.get_current_health()
    elif "current_health" in owner:
        current_health = owner.current_health


func apply_to_owner() -> void:
    """Apply module decisions to owner"""
    if not owner:
        return

    # Apply movement
    if should_stop:
        if "move_direction" in owner:
            owner.move_direction = Vector2.ZERO
    elif desired_direction != Vector2.ZERO:
        if "move_direction" in owner:
            owner.move_direction = desired_direction
        # Speed is applied via move_speed * speed_multiplier

    # Facing
    if "facing_direction" in owner:
        owner.facing_direction = facing_direction


func get_debug_dict() -> Dictionary:
    return {
        "state": BehaviorState.keys()[behavior_state],
        "target": current_target.name if current_target else "none",
        "target_dist": "%.0f" % target_distance,
        "health": "%.0f/%.0f" % [current_health, max_health],
        "direction": desired_direction,
        "should_attack": should_attack,
    }
```

### Step 2: Review and Clean BaseModule

**File:** `scripts/npc/ai/base_module.gd`

```gdscript
extends RefCounted
class_name BaseModule
## BaseModule - Abstract base class for AI modules
## Each module processes the shared EnemyContext

#===============================================================================
# MODULE IDENTITY
#===============================================================================

var module_id: String = ""
var module_name: String = ""
var priority: int = 0  # Higher = runs first
var enabled: bool = true

enum ModuleType { DETECTION, MOVEMENT, COMBAT, UTILITY }
var module_type: ModuleType = ModuleType.UTILITY

#===============================================================================
# CONFIGURATION
#===============================================================================

var config: Dictionary = {}
var _owner: Node2D = null

#===============================================================================
# LIFECYCLE
#===============================================================================

func setup(owner: Node2D, module_config: Dictionary = {}) -> void:
    """Called once when module is added to controller"""
    _owner = owner
    config = module_config
    _on_setup()


func _on_setup() -> void:
    """Override for custom setup logic"""
    pass


func process(context: EnemyContext, delta: float) -> void:
    """Called each frame by ModuleController"""
    if not enabled:
        return
    _process_module(context, delta)


func _process_module(_context: EnemyContext, _delta: float) -> void:
    """Override this - main module logic"""
    pass

#===============================================================================
# CONFIG HELPERS
#===============================================================================

func get_config_float(key: String, default: float = 0.0) -> float:
    return float(config.get(key, default))


func get_config_int(key: String, default: int = 0) -> int:
    return int(config.get(key, default))


func get_config_bool(key: String, default: bool = false) -> bool:
    return bool(config.get(key, default))


func get_config_string(key: String, default: String = "") -> String:
    return str(config.get(key, default))

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    return {
        "id": module_id,
        "name": module_name,
        "type": ModuleType.keys()[module_type],
        "priority": priority,
        "enabled": enabled,
    }
```

### Step 3: Review and Clean ModuleController

**File:** `scripts/npc/ai/module_controller.gd`

```gdscript
extends Node
class_name ModuleController
## ModuleController - Orchestrates AI modules for an enemy

#===============================================================================
# STATE
#===============================================================================

var context: EnemyContext = null
var modules: Array[BaseModule] = []
var _owner: Node2D = null

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    context = EnemyContext.new()


func setup(owner: Node2D) -> void:
    """Initialize controller with owner reference"""
    _owner = owner
    context.owner = owner

    # Copy relevant data from owner to context
    if "enemy_id" in owner:
        context.enemy_id = owner.enemy_id
    if "home_position" in owner:
        context.home_position = owner.home_position
    if "max_health" in owner:
        context.max_health = owner.max_health
        context.current_health = owner.max_health
    if "base_damage" in owner:
        context.base_damage = owner.base_damage
    if "move_speed" in owner:
        context.move_speed = owner.move_speed
    if "attack_radius" in owner:
        context.attack_radius = owner.attack_radius
    if "detection_radius" in owner:
        context.detection_radius = owner.detection_radius


func add_module(module: BaseModule, config: Dictionary = {}) -> void:
    """Add a module and sort by priority"""
    module.setup(_owner, config)
    modules.append(module)
    # Sort by priority (highest first)
    modules.sort_custom(func(a, b): return a.priority > b.priority)


func process_modules(delta: float) -> void:
    """Process all modules in priority order"""
    # Update context from owner
    context.sync_from_owner()
    context.delta = delta
    context.reset_frame_flags()

    # Process each module
    for module in modules:
        module.process(context, delta)

    # Apply decisions to owner
    context.apply_to_owner()

#===============================================================================
# QUERY
#===============================================================================

func get_context() -> EnemyContext:
    return context


func get_module(module_id: String) -> BaseModule:
    for module in modules:
        if module.module_id == module_id:
            return module
    return null


func has_module(module_id: String) -> bool:
    return get_module(module_id) != null


func get_all_modules() -> Array[BaseModule]:
    return modules

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    var module_info: Array = []
    for module in modules:
        module_info.append(module.get_debug_info())

    return {
        "module_count": modules.size(),
        "modules": module_info,
        "context": context.get_debug_dict() if context else {},
    }
```

### Step 4: Create Clean DetectionModule

**File:** `scripts/npc/ai/modules/target_detection_module.gd`

```gdscript
extends BaseModule
class_name DetectionModule
## DetectionModule - Finds and tracks combat targets

func _init() -> void:
    module_id = "mod_target_detection"
    module_name = "Target Detection"
    module_type = ModuleType.DETECTION
    priority = 100  # Runs first


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Validate existing target
    if context.current_target:
        if _is_target_valid(context.current_target):
            _update_target_info(context)
        else:
            _lose_target(context)

    # Try to acquire new target if none
    if not context.has_valid_target:
        _try_acquire_target(context)


func _is_target_valid(target: Node2D) -> bool:
    if not is_instance_valid(target):
        return false
    if "is_dead" in target and target.is_dead:
        return false
    return true


func _update_target_info(context: EnemyContext) -> void:
    context.has_valid_target = true
    context.target_distance = context.global_position.distance_to(
        context.current_target.global_position
    )
    context.target_direction = context.global_position.direction_to(
        context.current_target.global_position
    )


func _lose_target(context: EnemyContext) -> void:
    context.current_target = null
    context.has_valid_target = false
    context.target_just_lost = true
    context.target_distance = INF
    context.target_direction = Vector2.ZERO
    context.behavior_state = EnemyContext.BehaviorState.IDLE


func _try_acquire_target(context: EnemyContext) -> void:
    # Get player from Game singleton
    var player = _get_player()
    if not player:
        return

    if not _is_target_valid(player):
        return

    var distance = context.global_position.distance_to(player.global_position)
    var detection_range = get_config_float("detection_radius", context.detection_radius)

    if distance <= detection_range:
        context.current_target = player
        context.has_valid_target = true
        context.target_just_acquired = true
        context.behavior_state = EnemyContext.BehaviorState.CHASING
        _update_target_info(context)


func _get_player() -> Node2D:
    # Try Game singleton
    if Engine.has_singleton("Game"):
        var game = Engine.get_singleton("Game")
        if "player" in game:
            return game.player

    # Try global Game autoload
    var game_node = Engine.get_main_loop().root.get_node_or_null("Game")
    if game_node and "player" in game_node:
        return game_node.player

    # Try finding player in tree
    var players = Engine.get_main_loop().root.get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        return players[0]

    return null
```

### Step 5: Create Clean ChaseModule

**File:** `scripts/npc/ai/modules/chase_module.gd`

```gdscript
extends BaseModule
class_name ChaseModule
## ChaseModule - Moves toward the current target

func _init() -> void:
    module_id = "mod_chase"
    module_name = "Chase"
    module_type = ModuleType.MOVEMENT
    priority = 50


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only chase if we have a valid target
    if not context.has_valid_target:
        return

    # Don't chase if we're returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    # Don't chase if in attack range (let attack module handle)
    var attack_range = get_config_float("stop_distance", context.attack_radius)
    if context.target_distance <= attack_range:
        context.behavior_state = EnemyContext.BehaviorState.ATTACKING
        return

    # Chase!
    context.behavior_state = EnemyContext.BehaviorState.CHASING
    context.desired_direction = context.target_direction
    context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)
    context.facing_direction = _snap_to_cardinal(context.target_direction)


func _snap_to_cardinal(direction: Vector2) -> Vector2:
    if abs(direction.x) > abs(direction.y):
        return Vector2.RIGHT if direction.x > 0 else Vector2.LEFT
    else:
        return Vector2.DOWN if direction.y > 0 else Vector2.UP
```

### Step 6: Create Clean BasicAttackModule

**File:** `scripts/npc/ai/modules/basic_attack_module.gd`

```gdscript
extends BaseModule
class_name BasicAttackModule
## BasicAttackModule - Simple melee attack when in range

var _cooldown: float = 0.0

func _init() -> void:
    module_id = "mod_basic_attack"
    module_name = "Basic Attack"
    module_type = ModuleType.COMBAT
    priority = 40


func _process_module(context: EnemyContext, delta: float) -> void:
    # Update cooldown
    _cooldown = maxf(0.0, _cooldown - delta)
    context.attack_cooldown_remaining = _cooldown

    # Need a valid target
    if not context.has_valid_target:
        return

    # Check if in attack range
    var attack_range = get_config_float("attack_range", context.attack_radius)
    var in_range = context.target_distance <= attack_range

    if not in_range:
        return

    # Stop moving to attack
    context.should_stop = true
    context.behavior_state = EnemyContext.BehaviorState.ATTACKING

    # On cooldown?
    if _cooldown > 0:
        return

    # Attack!
    context.should_attack = true
    _cooldown = get_config_float("attack_cooldown", 1.0)
```

### Step 7: Create IdleModule

**File:** `scripts/npc/ai/modules/idle_module.gd`

```gdscript
extends BaseModule
class_name IdleModule
## IdleModule - Handles behavior when no target (stand or roam)

var _roam_target: Vector2 = Vector2.ZERO
var _pause_timer: float = 0.0
var _is_paused: bool = true

func _init() -> void:
    module_id = "mod_idle"
    module_name = "Idle"
    module_type = ModuleType.MOVEMENT
    priority = 10  # Low priority - other movement takes precedence


func _on_setup() -> void:
    _start_pause()


func _process_module(context: EnemyContext, delta: float) -> void:
    # Only run when idle (no target)
    if context.has_valid_target:
        return

    # Don't idle if returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        return

    var can_roam = get_config_bool("can_roam", true)
    if not can_roam:
        # Just stand
        context.behavior_state = EnemyContext.BehaviorState.IDLE
        context.should_stop = true
        return

    # Roaming behavior
    context.behavior_state = EnemyContext.BehaviorState.IDLE

    # Handle pause between roams
    if _is_paused:
        _pause_timer -= delta
        if _pause_timer <= 0:
            _is_paused = false
            _pick_roam_target(context)
        context.should_stop = true
        return

    # Check if reached roam target
    var dist = context.global_position.distance_to(_roam_target)
    if dist < 8.0:
        _start_pause()
        context.should_stop = true
        return

    # Move toward roam target
    context.desired_direction = context.global_position.direction_to(_roam_target)
    context.speed_multiplier = get_config_float("roam_speed_mult", 0.5)


func _pick_roam_target(context: EnemyContext) -> void:
    var roam_radius = get_config_float("roam_radius", 50.0)
    var angle = randf() * TAU
    var distance = randf_range(roam_radius * 0.3, roam_radius)
    _roam_target = context.home_position + Vector2(cos(angle), sin(angle)) * distance


func _start_pause() -> void:
    _is_paused = true
    var pause_min = get_config_float("pause_min", 2.0)
    var pause_max = get_config_float("pause_max", 5.0)
    _pause_timer = randf_range(pause_min, pause_max)
```

### Step 8: Create LeashModule

**File:** `scripts/npc/ai/modules/leash_module.gd`

```gdscript
extends BaseModule
class_name LeashModule
## LeashModule - Returns enemy home if too far from spawn

func _init() -> void:
    module_id = "mod_leash"
    module_name = "Leash"
    module_type = ModuleType.UTILITY
    priority = 90  # High priority - can override chase


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Calculate distance from home
    context.distance_from_home = context.global_position.distance_to(context.home_position)

    var leash_radius = get_config_float("leash_radius", context.leash_radius)
    context.is_beyond_leash = context.distance_from_home > leash_radius

    # If beyond leash, lose target and return home
    if context.is_beyond_leash and context.has_valid_target:
        context.current_target = null
        context.has_valid_target = false
        context.target_just_lost = true
        context.behavior_state = EnemyContext.BehaviorState.RETURNING

    # Handle returning home
    if context.behavior_state == EnemyContext.BehaviorState.RETURNING:
        var home_threshold = get_config_float("home_threshold", 16.0)

        if context.distance_from_home <= home_threshold:
            # Arrived home
            context.behavior_state = EnemyContext.BehaviorState.IDLE
            context.should_stop = true
        else:
            # Move toward home
            context.desired_direction = context.global_position.direction_to(context.home_position)
            context.speed_multiplier = get_config_float("return_speed_mult", 1.0)
```

### Step 9: Update EnemyNPC for Modular AI

**File:** `scripts/npc/enemy_npc.gd`

Add module support to EnemyNPC (this integrates with existing health/damage code):

```gdscript
#===============================================================================
# MODULAR AI
#===============================================================================

var module_controller: ModuleController = null

func _setup_modules() -> void:
    """Initialize modular AI from database"""
    var enemy_data = DatabaseLoader.get_enemy(enemy_id)
    var module_ids_str: String = enemy_data.get("module_ids", "")

    if module_ids_str.is_empty():
        push_warning("Enemy %s has no modules configured!" % enemy_id)
        return

    # Create controller
    module_controller = ModuleController.new()
    module_controller.name = "ModuleController"
    add_child(module_controller)
    module_controller.setup(self)

    # Load modules
    var module_ids = module_ids_str.split(",")
    for module_id in module_ids:
        module_id = module_id.strip_edges()
        if not module_id.is_empty():
            _load_module(module_id)


func _load_module(module_id: String) -> void:
    var module_data = DatabaseLoader.get_module(module_id)
    if module_data.is_empty():
        push_warning("Module not found: %s" % module_id)
        return

    var module = _create_module(module_id)
    if not module:
        push_warning("Could not create module: %s" % module_id)
        return

    # Get config
    var config: Dictionary = {}
    var config_raw = module_data.get("default_config", {})
    if config_raw is Dictionary:
        config = config_raw

    module_controller.add_module(module, config)


func _create_module(module_id: String) -> BaseModule:
    match module_id:
        "mod_target_detection":
            return DetectionModule.new()
        "mod_chase":
            return ChaseModule.new()
        "mod_basic_attack":
            return BasicAttackModule.new()
        "mod_idle":
            return IdleModule.new()
        "mod_leash":
            return LeashModule.new()
        _:
            push_warning("Unknown module: %s" % module_id)
            return null


func _physics_process(delta: float) -> void:
    if is_dead:
        return

    # Process modules
    if module_controller:
        module_controller.process_modules(delta)
        _handle_module_output()

    # Continue with normal physics
    # ... (existing movement code)


func _handle_module_output() -> void:
    """Apply module decisions"""
    var ctx = module_controller.get_context()

    # Handle attack
    if ctx.should_attack:
        _perform_attack(ctx)


func _perform_attack(ctx: EnemyContext) -> void:
    """Execute an attack"""
    if not ctx.current_target:
        return

    # Play animation
    play_attack()

    # Deal damage
    if ctx.current_target.has_method("take_damage"):
        ctx.current_target.take_damage(base_damage, self)
```

### Step 10: Update Database

**Add modules to enemy_modules.json:**

```json
{
  "enemy_modules": [
    {
      "id": "mod_target_detection",
      "name": "Target Detection",
      "module_type": "detection",
      "description": "Finds and tracks targets in detection range",
      "priority": 100,
      "default_config": {"detection_radius": 120}
    },
    {
      "id": "mod_chase",
      "name": "Chase",
      "module_type": "movement",
      "description": "Moves toward current target",
      "priority": 50,
      "default_config": {"chase_speed_mult": 1.0, "stop_distance": 24}
    },
    {
      "id": "mod_basic_attack",
      "name": "Basic Attack",
      "module_type": "combat",
      "description": "Simple melee attack when in range",
      "priority": 40,
      "default_config": {"attack_range": 24, "attack_cooldown": 1.0}
    },
    {
      "id": "mod_idle",
      "name": "Idle",
      "module_type": "movement",
      "description": "Stand or roam when no target",
      "priority": 10,
      "default_config": {"can_roam": true, "roam_radius": 50, "roam_speed_mult": 0.5, "pause_min": 2.0, "pause_max": 5.0}
    },
    {
      "id": "mod_leash",
      "name": "Leash",
      "module_type": "utility",
      "description": "Returns home if too far from spawn",
      "priority": 90,
      "default_config": {"leash_radius": 300, "home_threshold": 16, "return_speed_mult": 1.0}
    }
  ]
}
```

**Update a test enemy in enemies.json:**

```json
{
  "id": "ene_zombie_basic",
  "name": "Zombie",
  "type": "Normal",
  "base_health": 30,
  "base_damage": 5,
  "armor": 0,
  "move_speed": 80,
  "attack_range": 25,
  "detection_range": 120,
  "xp_reward": 15,
  "loot_table_id": "loot_zombie",
  "module_ids": "mod_target_detection,mod_leash,mod_chase,mod_basic_attack,mod_idle"
}
```

---

## Testing

### Test 1: Enemy Loads Modules

```gdscript
var enemy = DatabaseLoader.create_enemy("ene_zombie_basic")
add_child(enemy)
await get_tree().process_frame

print(enemy.module_controller.get_debug_info())
# Should show 5 modules loaded
```

### Test 2: Detection Works

1. Spawn enemy far from player
2. Walk into detection range
3. Enemy should start chasing

### Test 3: Chase Works

1. Enemy is chasing
2. Run away
3. Enemy should follow

### Test 4: Attack Works

1. Get in attack range
2. Enemy should stop and attack
3. Player should take damage

### Test 5: Leash Works

1. Aggro enemy
2. Lead far from spawn (>300px)
3. Enemy should give up and return home

### Test 6: Idle/Roam Works

1. Spawn enemy with no player nearby
2. Enemy should wander around spawn point
3. Should pause between movements

---

## Deliverables Checklist

- [ ] EnemyContext cleaned and documented
- [ ] BaseModule cleaned and documented
- [ ] ModuleController cleaned and documented
- [ ] DetectionModule working
- [ ] ChaseModule working
- [ ] BasicAttackModule working
- [ ] IdleModule working
- [ ] LeashModule working
- [ ] EnemyNPC integrates with modules
- [ ] Database has all 5 modules
- [ ] Test enemy (zombie) works correctly
- [ ] All 6 tests pass

---

## What's Next (Phase 4 Preview)

With the foundation working, Phase 4 will:
1. Create all enemies with appropriate modules
2. Add more modules as needed (ranged attack, flee, pack behavior)
3. Create module presets for common patterns
4. Balance and polish
