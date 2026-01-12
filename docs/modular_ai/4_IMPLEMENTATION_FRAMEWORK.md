# Implementation Framework
## Detailed Specifications for Modular AI System

---

## I. EnemyContext Schema

### Purpose
EnemyContext is the **shared data structure** through which modules communicate. Modules read context to understand world state and write context to influence behavior.

### Design Principles
1. **No direct module communication** - all data flows through context
2. **Clear ownership** - each field has one writer, many readers
3. **Frame-scoped** - context represents current frame state
4. **Serializable** - for debugging and save/load

### Context Structure

```gdscript
extends RefCounted
class_name EnemyContext

#===============================================================================
# IDENTITY
#===============================================================================

## Reference to owning enemy
var owner: EnemyNPC = null

## Enemy's database ID
var enemy_id: String = ""

## Current level
var level: int = 1

#===============================================================================
# PERCEPTION (Written by: DetectionModule)
#===============================================================================

## Current combat target (player or other hostile)
var current_target: Node2D = null

## Is target valid and alive
var has_valid_target: bool = false

## Distance to current target (pixels)
var target_distance: float = INF

## Direction to target (normalized)
var target_direction: Vector2 = Vector2.ZERO

## Nearby enemies (for pack behavior)
var nearby_allies: Array[EnemyNPC] = []

## Nearby threats (for flee behavior)
var nearby_threats: Array[Node2D] = []

## Target was lost this frame
var target_just_lost: bool = false

## Target was acquired this frame
var target_just_acquired: bool = false

#===============================================================================
# POSITION & MOVEMENT (Written by: MovementModule)
#===============================================================================

## Current global position
var global_position: Vector2 = Vector2.ZERO

## Home/spawn position
var home_position: Vector2 = Vector2.ZERO

## Distance from home position
var distance_from_home: float = 0.0

## Is beyond leash radius
var is_beyond_leash: bool = false

## Current velocity
var current_velocity: Vector2 = Vector2.ZERO

## Desired movement direction (output)
var desired_direction: Vector2 = Vector2.ZERO

## Desired movement speed multiplier (1.0 = normal)
var speed_multiplier: float = 1.0

## Should stop moving this frame
var should_stop: bool = false

#===============================================================================
# COMBAT STATE (Written by: CombatModule)
#===============================================================================

## Is within attack range
var is_in_attack_range: bool = false

## Is aligned for attack (cardinal alignment)
var is_attack_aligned: bool = false

## Should attempt attack this frame
var should_attack: bool = false

## Attack is currently in progress
var attack_in_progress: bool = false

## Attack completed this frame
var attack_completed: bool = false

## Last used ability
var last_ability_id: String = ""

## Attack cooldown remaining (seconds)
var attack_cooldown_remaining: float = 0.0

#===============================================================================
# HEALTH STATE (Read from: EnemyNPC)
#===============================================================================

## Current health
var current_health: float = 100.0

## Maximum health
var max_health: float = 100.0

## Health percentage (0.0 to 1.0)
var health_percent: float = 1.0

## Was damaged this frame
var was_damaged_this_frame: bool = false

## Damage amount this frame
var damage_this_frame: float = 0.0

## Attacker that dealt damage
var last_attacker: Node2D = null

## Is dead
var is_dead: bool = false

#===============================================================================
# SHIELD STATE (Read from: ShieldComponent)
#===============================================================================

## Current shield amount
var current_shield: float = 0.0

## Has active shield
var has_shield: bool = false

## Shield percentage (0.0 to 1.0)
var shield_percent: float = 0.0

#===============================================================================
# STATUS EFFECTS (Read from: StatusEffectComponent)
#===============================================================================

## Active buff types
var active_buffs: Array[String] = []

## Active debuff types
var active_debuffs: Array[String] = []

## Is stunned (can't act)
var is_stunned: bool = false

## Is slowed
var is_slowed: bool = false

## Slow amount (0.0 to 1.0)
var slow_amount: float = 0.0

#===============================================================================
# BEHAVIOR STATE (Written by: Various Modules)
#===============================================================================

## Current high-level state
enum BehaviorState { IDLE, ROAMING, COMBAT, RETURNING, FLEEING, DEAD }
var behavior_state: BehaviorState = BehaviorState.IDLE

## Idle sub-state
enum IdleState { STANDING, ROAMING, PATROLLING }
var idle_state: IdleState = IdleState.STANDING

## Is currently performing an action that locks movement
var is_locked: bool = false

## Current facing direction
var facing_direction: Vector2 = Vector2.DOWN

#===============================================================================
# PACK/SOCIAL (Written by: PackModule)
#===============================================================================

## Received alert from ally
var pack_alert_received: bool = false

## Source of pack alert
var pack_alert_source: EnemyNPC = null

## Pack target (shared target from pack)
var pack_target: Node2D = null

## Formation position relative to pack leader
var formation_offset: Vector2 = Vector2.ZERO

## Is pack leader
var is_pack_leader: bool = false

#===============================================================================
# CONFIGURATION (Read from: Database)
#===============================================================================

## Detection radius
var detection_radius: float = 120.0

## Attack radius
var attack_radius: float = 24.0

## Leash radius
var leash_radius: float = 300.0

## Base move speed
var base_move_speed: float = 80.0

## Base damage
var base_damage: float = 10.0

#===============================================================================
# FRAME TIMING
#===============================================================================

## Delta time this frame
var delta: float = 0.0

## Total elapsed time
var elapsed_time: float = 0.0

#===============================================================================
# METHODS
#===============================================================================

func reset_frame_flags() -> void:
    """Reset per-frame flags at start of each frame"""
    target_just_lost = false
    target_just_acquired = false
    was_damaged_this_frame = false
    damage_this_frame = 0.0
    attack_completed = false
    should_attack = false
    should_stop = false
    desired_direction = Vector2.ZERO
    speed_multiplier = 1.0

func update_from_owner() -> void:
    """Sync context from owner EnemyNPC"""
    if not owner:
        return

    global_position = owner.global_position
    current_velocity = owner.velocity
    is_locked = owner.is_locked

    # Health
    current_health = owner.current_health
    max_health = owner.max_health
    health_percent = owner.get_health_percent()
    is_dead = owner.is_dead

    # Shield
    if owner.shield:
        current_shield = owner.shield.current_shield
        has_shield = owner.has_shield()
        shield_percent = owner.get_shield_percent()

    # Config
    detection_radius = owner.detection_radius
    attack_radius = owner.attack_radius
    leash_radius = owner.leash_radius
    base_move_speed = owner.move_speed
    base_damage = owner.base_damage

func apply_to_owner() -> void:
    """Apply context decisions to owner EnemyNPC"""
    if not owner:
        return

    if should_stop:
        owner.stop_movement()
    elif desired_direction != Vector2.ZERO:
        owner.set_move_direction(desired_direction)
        if speed_multiplier != 1.0:
            owner.move_speed = base_move_speed * speed_multiplier

func get_debug_dict() -> Dictionary:
    """Return context as dictionary for debugging"""
    return {
        "target": current_target.name if current_target else "none",
        "target_distance": target_distance,
        "health": "%d/%d" % [current_health, max_health],
        "state": BehaviorState.keys()[behavior_state],
        "in_attack_range": is_in_attack_range,
        "should_attack": should_attack,
        "desired_direction": desired_direction
    }
```

---

## II. BaseModule Specification

### Class Definition

```gdscript
extends RefCounted
class_name BaseModule

#===============================================================================
# METADATA
#===============================================================================

## Unique module ID (from database)
var module_id: String = ""

## Human-readable name
var module_name: String = "Base Module"

## Module type for categorization
enum ModuleType { DETECTION, MOVEMENT, COMBAT, SOCIAL, SPECIAL, UTILITY }
var module_type: ModuleType = ModuleType.UTILITY

## Execution priority (higher = runs first)
var priority: int = 0

## Is module currently enabled
var enabled: bool = true

#===============================================================================
# CONFIGURATION
#===============================================================================

## Configuration dictionary loaded from database
var config: Dictionary = {}

#===============================================================================
# LIFECYCLE
#===============================================================================

func _init() -> void:
    """Constructor - override for setup"""
    pass

func setup(owner: EnemyNPC, module_config: Dictionary) -> void:
    """Called when module is attached to enemy"""
    config = module_config
    _on_setup(owner)

func _on_setup(_owner: EnemyNPC) -> void:
    """Override for custom setup logic"""
    pass

func cleanup() -> void:
    """Called when module is removed"""
    _on_cleanup()

func _on_cleanup() -> void:
    """Override for custom cleanup logic"""
    pass

#===============================================================================
# PROCESSING
#===============================================================================

func process(context: EnemyContext, delta: float) -> void:
    """Main processing entry point - called every frame"""
    if not enabled:
        return

    _process_module(context, delta)

func _process_module(_context: EnemyContext, _delta: float) -> void:
    """Override to implement module logic"""
    pass

#===============================================================================
# UTILITY
#===============================================================================

func get_config_float(key: String, default: float = 0.0) -> float:
    """Get float value from config with default"""
    return float(config.get(key, default))

func get_config_int(key: String, default: int = 0) -> int:
    """Get int value from config with default"""
    return int(config.get(key, default))

func get_config_bool(key: String, default: bool = false) -> bool:
    """Get bool value from config with default"""
    return bool(config.get(key, default))

func get_config_string(key: String, default: String = "") -> String:
    """Get string value from config with default"""
    return str(config.get(key, default))

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    """Return module state for debugging"""
    return {
        "id": module_id,
        "name": module_name,
        "type": ModuleType.keys()[module_type],
        "priority": priority,
        "enabled": enabled
    }
```

---

## III. Module Controller Specification

```gdscript
extends Node
class_name ModuleController

#===============================================================================
# SIGNALS
#===============================================================================

signal modules_loaded()
signal module_error(module_id: String, error: String)

#===============================================================================
# STATE
#===============================================================================

var _owner: EnemyNPC = null
var _context: EnemyContext = null
var _modules: Array[BaseModule] = []
var _modules_by_type: Dictionary = {}  # ModuleType -> Array[BaseModule]

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    _owner = get_parent() as EnemyNPC
    if not _owner:
        push_error("ModuleController must be child of EnemyNPC")
        return

    _context = EnemyContext.new()
    _context.owner = _owner

func setup_from_database(enemy_id: String) -> void:
    """Load and initialize modules from database config"""
    var enemy_data = DatabaseLoader.get_enemy(enemy_id)
    if enemy_data.is_empty():
        push_error("Enemy not found: %s" % enemy_id)
        return

    var module_ids_str: String = enemy_data.get("module_ids", "")
    if module_ids_str.is_empty():
        return

    var module_ids = module_ids_str.split(",")
    for module_id in module_ids:
        module_id = module_id.strip_edges()
        _load_module(module_id)

    _sort_modules_by_priority()
    _categorize_modules()
    modules_loaded.emit()

func _load_module(module_id: String) -> void:
    """Load single module from database"""
    var module_data = DatabaseLoader.get_module(module_id)
    if module_data.is_empty():
        module_error.emit(module_id, "Module not found in database")
        return

    var script_path: String = module_data.get("script_path", "")
    if script_path.is_empty():
        script_path = _get_default_script_path(module_id)

    if not ResourceLoader.exists(script_path):
        module_error.emit(module_id, "Script not found: %s" % script_path)
        return

    var ModuleScript = load(script_path)
    var module: BaseModule = ModuleScript.new()
    module.module_id = module_id
    module.module_name = module_data.get("name", module_id)
    module.priority = int(module_data.get("priority", 0))

    # Merge default config with enemy-specific overrides
    var default_config: Dictionary = module_data.get("default_config", {})
    var enemy_overrides = _get_enemy_config_overrides(module_id)
    var final_config = default_config.duplicate()
    final_config.merge(enemy_overrides, true)

    module.setup(_owner, final_config)
    _modules.append(module)

func _get_default_script_path(module_id: String) -> String:
    """Convert module ID to script path"""
    # mod_target_detection -> res://scripts/npc/ai/modules/target_detection_module.gd
    var name = module_id.replace("mod_", "")
    return "res://scripts/npc/ai/modules/%s_module.gd" % name

func _get_enemy_config_overrides(module_id: String) -> Dictionary:
    """Get enemy-specific config overrides for module"""
    var overrides_str: String = _owner.get_meta("module_config_overrides", "")
    if overrides_str.is_empty():
        return {}

    # Parse format: "module_id.key:value;module_id.key2:value2"
    var result: Dictionary = {}
    var pairs = overrides_str.split(";")
    for pair in pairs:
        var kv = pair.split(":")
        if kv.size() != 2:
            continue
        var full_key = kv[0].strip_edges()
        if not full_key.begins_with(module_id + "."):
            continue
        var key = full_key.substr(module_id.length() + 1)
        var value = kv[1].strip_edges()
        result[key] = _parse_value(value)

    return result

func _parse_value(value: String):
    """Parse string value to appropriate type"""
    if value.is_valid_float():
        return float(value)
    if value.is_valid_int():
        return int(value)
    if value.to_lower() in ["true", "false"]:
        return value.to_lower() == "true"
    return value

func _sort_modules_by_priority() -> void:
    """Sort modules by priority (highest first)"""
    _modules.sort_custom(func(a, b): return a.priority > b.priority)

func _categorize_modules() -> void:
    """Group modules by type for quick access"""
    _modules_by_type.clear()
    for module in _modules:
        var type_key = module.module_type
        if not _modules_by_type.has(type_key):
            _modules_by_type[type_key] = []
        _modules_by_type[type_key].append(module)

#===============================================================================
# PROCESSING
#===============================================================================

func process_modules(delta: float) -> void:
    """Process all modules for this frame"""
    if _owner.is_dead:
        return

    # Update context from owner
    _context.delta = delta
    _context.elapsed_time += delta
    _context.reset_frame_flags()
    _context.update_from_owner()

    # Process each module in priority order
    for module in _modules:
        module.process(_context, delta)

    # Apply context decisions to owner
    _context.apply_to_owner()

#===============================================================================
# QUERY
#===============================================================================

func get_context() -> EnemyContext:
    return _context

func get_module(module_id: String) -> BaseModule:
    for module in _modules:
        if module.module_id == module_id:
            return module
    return null

func get_modules_by_type(type: BaseModule.ModuleType) -> Array[BaseModule]:
    return _modules_by_type.get(type, [])

func has_module(module_id: String) -> bool:
    return get_module(module_id) != null

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    var module_info = []
    for module in _modules:
        module_info.append(module.get_debug_info())

    return {
        "module_count": _modules.size(),
        "modules": module_info,
        "context": _context.get_debug_dict()
    }
```

---

## IV. Core Module Specifications

### Detection Module

```gdscript
extends BaseModule
class_name DetectionModule

func _init() -> void:
    module_type = ModuleType.DETECTION
    module_name = "Target Detection"

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Check for existing target validity
    if context.current_target:
        if not is_instance_valid(context.current_target):
            _lose_target(context)
        else:
            _update_target_info(context)

    # Try to acquire new target if none
    if not context.has_valid_target:
        _try_acquire_target(context)

func _try_acquire_target(context: EnemyContext) -> void:
    var player = Game.player if Game else null
    if not player or not is_instance_valid(player):
        return

    var distance = context.global_position.distance_to(player.global_position)
    var detection_range = get_config_float("detection_radius", context.detection_radius)

    if distance <= detection_range:
        context.current_target = player
        context.has_valid_target = true
        context.target_just_acquired = true
        context.behavior_state = EnemyContext.BehaviorState.COMBAT

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
    context.behavior_state = EnemyContext.BehaviorState.IDLE
```

### Chase Module

```gdscript
extends BaseModule
class_name ChaseModule

func _init() -> void:
    module_type = ModuleType.MOVEMENT
    module_name = "Chase"

func _process_module(context: EnemyContext, _delta: float) -> void:
    # Only chase if we have a target and not in attack range
    if not context.has_valid_target:
        return

    if context.is_in_attack_range:
        return

    if context.is_beyond_leash:
        return

    # Chase target
    context.desired_direction = context.target_direction
    context.speed_multiplier = get_config_float("chase_speed_mult", 1.0)
```

### Melee Attack Module

```gdscript
extends BaseModule
class_name MeleeAttackModule

var _attack_cooldown: float = 0.0

func _init() -> void:
    module_type = ModuleType.COMBAT
    module_name = "Melee Attack"

func _process_module(context: EnemyContext, delta: float) -> void:
    # Update cooldown
    _attack_cooldown = maxf(0.0, _attack_cooldown - delta)
    context.attack_cooldown_remaining = _attack_cooldown

    # Check if we can attack
    if not context.has_valid_target:
        return

    # Calculate attack range
    var attack_range = get_config_float("attack_radius", context.attack_radius)
    context.is_in_attack_range = context.target_distance <= attack_range

    if not context.is_in_attack_range:
        return

    if _attack_cooldown > 0:
        return

    if context.attack_in_progress:
        return

    # Signal attack
    context.should_attack = true
    context.should_stop = true
    _attack_cooldown = get_config_float("attack_cooldown", 1.0)
```

---

## V. Database Schema Extensions

### enemy_modules.json

```json
{
  "enemy_modules": [
    {
      "id": "mod_target_detection",
      "name": "Target Detection",
      "module_type": "detection",
      "description": "Detects and tracks combat targets",
      "script_path": "res://scripts/npc/ai/modules/detection_module.gd",
      "priority": 100,
      "default_config": {
        "detection_radius": 120,
        "detection_type": "sight",
        "aggro_on_damage": true
      }
    },
    {
      "id": "mod_chase",
      "name": "Chase",
      "module_type": "movement",
      "description": "Pursues combat target",
      "script_path": "res://scripts/npc/ai/modules/chase_module.gd",
      "priority": 80,
      "default_config": {
        "chase_speed_mult": 1.0
      }
    },
    {
      "id": "mod_melee_attack",
      "name": "Melee Attack",
      "module_type": "combat",
      "description": "Triggers attack when in range",
      "script_path": "res://scripts/npc/ai/modules/melee_attack_module.gd",
      "priority": 60,
      "default_config": {
        "attack_radius": 24,
        "attack_cooldown": 1.0
      }
    },
    {
      "id": "mod_roam",
      "name": "Roam",
      "module_type": "movement",
      "description": "Wanders when idle",
      "script_path": "res://scripts/npc/ai/modules/roam_module.gd",
      "priority": 20,
      "default_config": {
        "roam_radius": 60,
        "roam_speed_mult": 0.5,
        "pause_min": 2.0,
        "pause_max": 5.0
      }
    },
    {
      "id": "mod_leash",
      "name": "Leash Check",
      "module_type": "utility",
      "description": "Returns home if too far",
      "script_path": "res://scripts/npc/ai/modules/leash_module.gd",
      "priority": 90,
      "default_config": {
        "leash_radius": 300
      }
    }
  ]
}
```

### VBA Module Headers (EnemyModuleDatabase.bas)

```vba
' Column definitions for EnemyModules sheet
Private Const COL_MOD_ID As Integer = 1
Private Const COL_MOD_NAME As Integer = 2
Private Const COL_MOD_TYPE As Integer = 3
Private Const COL_MOD_DESCRIPTION As Integer = 4
Private Const COL_MOD_SCRIPT_PATH As Integer = 5
Private Const COL_MOD_PRIORITY As Integer = 6
Private Const COL_MOD_DEFAULT_CONFIG As Integer = 7
```

---

## VI. Testing Strategy

### Unit Tests

```gdscript
# test_enemy_context.gd
extends GutTest

func test_context_reset_flags():
    var ctx = EnemyContext.new()
    ctx.target_just_acquired = true
    ctx.was_damaged_this_frame = true

    ctx.reset_frame_flags()

    assert_false(ctx.target_just_acquired)
    assert_false(ctx.was_damaged_this_frame)

func test_context_health_percent():
    var ctx = EnemyContext.new()
    ctx.current_health = 50.0
    ctx.max_health = 100.0
    ctx.health_percent = ctx.current_health / ctx.max_health

    assert_almost_eq(ctx.health_percent, 0.5, 0.001)
```

### Integration Tests

```gdscript
# test_modular_enemy.gd
extends GutTest

var _enemy: ModularEnemyNPC

func before_each():
    _enemy = preload("res://scenes/npc/modular_enemy.tscn").instantiate()
    add_child(_enemy)

func after_each():
    _enemy.queue_free()

func test_modules_load():
    _enemy.enemy_id = "ene_zombie_basic_modular"
    await get_tree().process_frame

    assert_true(_enemy.module_controller.has_module("mod_target_detection"))
    assert_true(_enemy.module_controller.has_module("mod_chase"))

func test_detection_acquires_target():
    var player = _create_mock_player()
    player.global_position = _enemy.global_position + Vector2(50, 0)

    await get_tree().process_frame

    var ctx = _enemy.module_controller.get_context()
    assert_true(ctx.has_valid_target)
```

### Behavior Validation Tests

```gdscript
# test_behavior_parity.gd
extends GutTest

func test_zombie_chase_distance():
    var legacy = _spawn_legacy_zombie()
    var modular = _spawn_modular_zombie()
    var player = _create_mock_player()

    # Position player at detection range
    player.global_position = Vector2(100, 0)
    legacy.global_position = Vector2.ZERO
    modular.global_position = Vector2.ZERO

    # Run 60 frames
    for i in 60:
        await get_tree().process_frame

    # Both should be at similar positions
    var distance = legacy.global_position.distance_to(modular.global_position)
    assert_lt(distance, 5.0, "Enemies should be within 5 pixels")
```

---

## VII. Directory Structure

```
scripts/npc/ai/
├── enemy_context.gd           # Shared context class
├── base_module.gd             # Abstract module base
├── module_controller.gd       # Module orchestrator
├── modular_enemy_npc.gd       # Modular enemy class
└── modules/
    ├── detection/
    │   ├── detection_module.gd
    │   └── damage_aggro_module.gd
    ├── movement/
    │   ├── chase_module.gd
    │   ├── roam_module.gd
    │   ├── return_home_module.gd
    │   └── leash_module.gd
    ├── combat/
    │   ├── melee_attack_module.gd
    │   ├── ability_combat_module.gd
    │   └── ranged_attack_module.gd
    ├── social/
    │   ├── pack_alert_module.gd
    │   └── pack_formation_module.gd
    └── special/
        ├── flee_module.gd
        └── kite_module.gd

databases/
├── exports/
│   ├── enemy_modules.json
│   └── (existing files)
└── vba/
    ├── EnemyModuleDatabase.bas
    └── (existing files)

tests/
└── unit/
    ├── test_enemy_context.gd
    ├── test_base_module.gd
    └── test_module_controller.gd
```

This implementation framework provides all the specifications needed to begin Phase 0 development.
