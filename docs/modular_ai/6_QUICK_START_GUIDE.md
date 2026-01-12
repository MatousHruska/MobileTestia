# Quick Start Guide
## Step-by-Step Guide for Beginning Phase 0 Implementation

---

## Prerequisites

Before starting, ensure you have:
- [ ] Read CODEBASE_ANALYSIS.md
- [ ] Read COMPATIBILITY_REPORT.md
- [ ] Reviewed IMPLEMENTATION_FRAMEWORK.md
- [ ] Familiarity with existing EnemyBehavior and AbilityExecutor

---

## Phase 0: Foundation Setup

### Step 1: Create Directory Structure

Create the module system directory:

```bash
mkdir -p scripts/npc/ai/modules
```

Expected structure:
```
scripts/npc/ai/
├── enemy_context.gd       (Step 2)
├── base_module.gd         (Step 3)
└── module_controller.gd   (Step 4)
```

---

### Step 2: Create EnemyContext

Create `scripts/npc/ai/enemy_context.gd`:

```gdscript
extends RefCounted
class_name EnemyContext
## Shared data structure for module communication

#===============================================================================
# IDENTITY
#===============================================================================

var owner: Node2D = null
var enemy_id: String = ""

#===============================================================================
# PERCEPTION
#===============================================================================

var current_target: Node2D = null
var has_valid_target: bool = false
var target_distance: float = INF
var target_direction: Vector2 = Vector2.ZERO

#===============================================================================
# POSITION & MOVEMENT
#===============================================================================

var global_position: Vector2 = Vector2.ZERO
var home_position: Vector2 = Vector2.ZERO
var distance_from_home: float = 0.0
var is_beyond_leash: bool = false
var desired_direction: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
var should_stop: bool = false

#===============================================================================
# COMBAT
#===============================================================================

var is_in_attack_range: bool = false
var should_attack: bool = false
var attack_in_progress: bool = false
var attack_cooldown_remaining: float = 0.0

#===============================================================================
# HEALTH
#===============================================================================

var current_health: float = 100.0
var max_health: float = 100.0
var health_percent: float = 1.0
var is_dead: bool = false

#===============================================================================
# CONFIGURATION
#===============================================================================

var detection_radius: float = 120.0
var attack_radius: float = 24.0
var leash_radius: float = 300.0
var base_move_speed: float = 80.0

#===============================================================================
# TIMING
#===============================================================================

var delta: float = 0.0

#===============================================================================
# METHODS
#===============================================================================

func reset_frame_flags() -> void:
    should_attack = false
    should_stop = false
    desired_direction = Vector2.ZERO
    speed_multiplier = 1.0


func update_from_owner() -> void:
    if not owner:
        return

    global_position = owner.global_position

    # Update config from EnemyNPC
    if "detection_radius" in owner:
        detection_radius = owner.detection_radius
    if "attack_radius" in owner:
        attack_radius = owner.attack_radius
    if "leash_radius" in owner:
        leash_radius = owner.leash_radius
    if "move_speed" in owner:
        base_move_speed = owner.move_speed

    # Health
    if "current_health" in owner:
        current_health = owner.current_health
        max_health = owner.max_health
        health_percent = current_health / max_health if max_health > 0 else 0.0
    if "is_dead" in owner:
        is_dead = owner.is_dead

    # Home position
    if "home_position" in owner:
        home_position = owner.home_position
        distance_from_home = global_position.distance_to(home_position)
        is_beyond_leash = distance_from_home > leash_radius


func apply_to_owner() -> void:
    if not owner:
        return

    if should_stop:
        if owner.has_method("stop_movement"):
            owner.stop_movement()
    elif desired_direction != Vector2.ZERO:
        if owner.has_method("set_move_direction"):
            owner.set_move_direction(desired_direction)


func get_debug_dict() -> Dictionary:
    return {
        "target": current_target.name if current_target else "none",
        "target_distance": int(target_distance),
        "health": "%d/%d" % [int(current_health), int(max_health)],
        "in_attack_range": is_in_attack_range,
        "should_attack": should_attack,
    }
```

**Verify:** Run game, no errors on load.

---

### Step 3: Create BaseModule

Create `scripts/npc/ai/base_module.gd`:

```gdscript
extends RefCounted
class_name BaseModule
## Abstract base class for all AI modules

#===============================================================================
# METADATA
#===============================================================================

var module_id: String = ""
var module_name: String = "Base Module"

enum ModuleType { DETECTION, MOVEMENT, COMBAT, SOCIAL, SPECIAL, UTILITY }
var module_type: ModuleType = ModuleType.UTILITY

var priority: int = 0
var enabled: bool = true

#===============================================================================
# CONFIGURATION
#===============================================================================

var config: Dictionary = {}

#===============================================================================
# LIFECYCLE
#===============================================================================

func setup(owner: Node2D, module_config: Dictionary) -> void:
    config = module_config
    _on_setup(owner)


func _on_setup(_owner: Node2D) -> void:
    # Override in subclass
    pass


func cleanup() -> void:
    _on_cleanup()


func _on_cleanup() -> void:
    # Override in subclass
    pass

#===============================================================================
# PROCESSING
#===============================================================================

func process(context: EnemyContext, delta: float) -> void:
    if not enabled:
        return
    _process_module(context, delta)


func _process_module(_context: EnemyContext, _delta: float) -> void:
    # Override in subclass
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

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    return {
        "id": module_id,
        "name": module_name,
        "type": ModuleType.keys()[module_type],
        "priority": priority,
        "enabled": enabled
    }
```

**Verify:** `var m = BaseModule.new()` works in debugger.

---

### Step 4: Create ModuleController

Create `scripts/npc/ai/module_controller.gd`:

```gdscript
extends Node
class_name ModuleController
## Manages and orchestrates AI modules for an enemy

#===============================================================================
# SIGNALS
#===============================================================================

signal modules_loaded()

#===============================================================================
# STATE
#===============================================================================

var _owner: Node2D = null
var _context: EnemyContext = null
var _modules: Array[BaseModule] = []

#===============================================================================
# LIFECYCLE
#===============================================================================

func _ready() -> void:
    _owner = get_parent()
    if not _owner:
        push_error("ModuleController must be child of a Node2D")
        return

    _context = EnemyContext.new()
    _context.owner = _owner


func setup_modules(module_list: Array[BaseModule]) -> void:
    _modules = module_list
    _sort_by_priority()
    modules_loaded.emit()


func add_module(module: BaseModule, module_config: Dictionary = {}) -> void:
    module.setup(_owner, module_config)
    _modules.append(module)
    _sort_by_priority()


func _sort_by_priority() -> void:
    _modules.sort_custom(func(a, b): return a.priority > b.priority)

#===============================================================================
# PROCESSING
#===============================================================================

func process_modules(delta: float) -> void:
    if not _owner:
        return

    # Update context from owner
    _context.delta = delta
    _context.reset_frame_flags()
    _context.update_from_owner()

    # Process each module
    for module in _modules:
        module.process(_context, delta)

    # Apply decisions to owner
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


func has_module(module_id: String) -> bool:
    return get_module(module_id) != null

#===============================================================================
# DEBUG
#===============================================================================

func get_debug_info() -> Dictionary:
    var infos = []
    for m in _modules:
        infos.append(m.get_debug_info())
    return {
        "module_count": _modules.size(),
        "modules": infos,
        "context": _context.get_debug_dict()
    }
```

**Verify:** Can instantiate and add dummy modules.

---

### Step 5: Create Test Module

Create `scripts/npc/ai/modules/test_module.gd`:

```gdscript
extends BaseModule
class_name TestModule
## Simple test module to verify system works

func _init() -> void:
    module_id = "mod_test"
    module_name = "Test Module"
    module_type = ModuleType.UTILITY
    priority = 50


func _process_module(context: EnemyContext, _delta: float) -> void:
    # Just log that we're running
    if Engine.get_process_frames() % 60 == 0:
        print("TestModule: owner at %s, target: %s" % [
            context.global_position,
            context.current_target
        ])
```

---

### Step 6: Integration Test Script

Create a test script to verify the system:

```gdscript
# test_module_system.gd - Run from debugger or test scene
extends Node

func _ready() -> void:
    print("=== Module System Test ===")

    # Test 1: Context creation
    var ctx = EnemyContext.new()
    ctx.current_health = 50.0
    ctx.max_health = 100.0
    ctx.health_percent = 0.5
    assert(ctx.health_percent == 0.5, "Context health failed")
    print("✓ Context creation works")

    # Test 2: Module creation
    var module = TestModule.new()
    assert(module.module_id == "mod_test", "Module ID failed")
    print("✓ Module creation works")

    # Test 3: Controller
    var controller = ModuleController.new()
    add_child(controller)
    controller.add_module(module)
    assert(controller.has_module("mod_test"), "Module not added")
    print("✓ Controller works")

    # Test 4: Processing
    controller.process_modules(0.016)
    print("✓ Processing works")

    print("=== All Tests Passed ===")
```

---

### Step 7: Database Schema (Prepare)

Create empty database file `databases/exports/enemy_modules.json`:

```json
{
  "enemy_modules": []
}
```

Add to `DatabaseLoader.gd` (in `load_all_databases()`):

```gdscript
var enemy_modules: Dictionary = {}
var enemy_modules_list: Array = []

# In load_all_databases():
success = _load_database("enemy_modules.json", "enemy_modules", enemy_modules, enemy_modules_list) and success
```

Add helper function:

```gdscript
func get_module(id: String) -> Dictionary:
    return enemy_modules.get(id, {})
```

---

### Step 8: VBA Setup

Create `databases/vba/EnemyModuleDatabase.bas`:

```vba
Attribute VB_Name = "EnemyModuleDatabase"
Option Explicit

' ============================================================================
' EnemyModuleDatabase - Validates and exports enemy module definitions
' ============================================================================

' Column definitions for EnemyModules sheet
Private Const COL_MOD_ID As Integer = 1
Private Const COL_MOD_NAME As Integer = 2
Private Const COL_MOD_TYPE As Integer = 3
Private Const COL_MOD_DESCRIPTION As Integer = 4
Private Const COL_MOD_SCRIPT_PATH As Integer = 5
Private Const COL_MOD_PRIORITY As Integer = 6
Private Const COL_MOD_DEFAULT_CONFIG As Integer = 7

' Valid module types
Private Const VALID_TYPES As String = "detection,movement,combat,social,special,utility"

' ----------------------------------------------------------------------------
' Setup - Configure sheet headers
' ----------------------------------------------------------------------------
Public Sub Setup()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("EnemyModules")

    ws.Cells(1, COL_MOD_ID).Value = "id"
    ws.Cells(1, COL_MOD_NAME).Value = "name"
    ws.Cells(1, COL_MOD_TYPE).Value = "module_type"
    ws.Cells(1, COL_MOD_DESCRIPTION).Value = "description"
    ws.Cells(1, COL_MOD_SCRIPT_PATH).Value = "script_path"
    ws.Cells(1, COL_MOD_PRIORITY).Value = "priority"
    ws.Cells(1, COL_MOD_DEFAULT_CONFIG).Value = "default_config"
End Sub

' ----------------------------------------------------------------------------
' Validate - Check data integrity
' ----------------------------------------------------------------------------
Public Function Validate() As Boolean
    Dim ws As Worksheet
    Dim lastRow As Long
    Dim i As Long
    Dim isValid As Boolean

    Set ws = ThisWorkbook.Sheets("EnemyModules")
    lastRow = ws.Cells(ws.Rows.Count, COL_MOD_ID).End(xlUp).Row
    isValid = True

    For i = 2 To lastRow
        Dim modId As String
        modId = ws.Cells(i, COL_MOD_ID).Value

        ' Check ID format
        If Not modId Like "mod_*" Then
            Debug.Print "WARNING: Module ID should start with 'mod_': " & modId
        End If

        ' Check type
        Dim modType As String
        modType = LCase(ws.Cells(i, COL_MOD_TYPE).Value)
        If InStr(VALID_TYPES, modType) = 0 Then
            Debug.Print "ERROR: Invalid module type '" & modType & "' for " & modId
            isValid = False
        End If

        ' Check priority is numeric
        If Not IsNumeric(ws.Cells(i, COL_MOD_PRIORITY).Value) Then
            Debug.Print "ERROR: Priority must be numeric for " & modId
            isValid = False
        End If
    Next i

    Validate = isValid
End Function
```

Update `MasterExport.bas` to include module export.
Update `SharedValidation.bas` if needed.

---

### Step 9: Verification Checklist

Run through this checklist to confirm Phase 0 is complete:

- [ ] `scripts/npc/ai/enemy_context.gd` exists and loads without errors
- [ ] `scripts/npc/ai/base_module.gd` exists and can be instantiated
- [ ] `scripts/npc/ai/module_controller.gd` exists and can process modules
- [ ] `scripts/npc/ai/modules/test_module.gd` works
- [ ] Test script passes all assertions
- [ ] `databases/exports/enemy_modules.json` exists (empty array)
- [ ] `DatabaseLoader.gd` can load enemy_modules
- [ ] `EnemyModuleDatabase.bas` created
- [ ] No errors in Godot console

---

## Next Steps

After Phase 0 completion:

1. **Phase 1 Preview:**
   - Create DetectionModule from EnemyBehavior._try_acquire_target()
   - Create ChaseModule from EnemyBehavior._do_chase()
   - Create BasicAttackModule for simple melee attack

2. **Testing:**
   - Create modular zombie variant
   - Run side-by-side comparison
   - Profile performance

3. **Documentation:**
   - Document any changes to this guide
   - Note any issues encountered
   - Update risk assessment if needed

---

## Troubleshooting

### "Class not found: EnemyContext"
- Ensure file is saved as `enemy_context.gd`
- Verify `class_name EnemyContext` is present
- Restart Godot to reload classes

### "Module not processing"
- Check `module.enabled = true`
- Verify `_process_module` is overridden
- Add print statement to confirm execution

### "Context not updating"
- Check `_owner` is set correctly
- Verify `update_from_owner()` is called
- Confirm owner has expected properties

### "Performance concerns"
- Add timing around `process_modules()`
- Profile with Godot profiler
- Consider skipping frames for low-priority modules

---

## Support

If you encounter issues:
1. Check existing documentation
2. Review related code in EnemyBehavior for patterns
3. Add debug logging to isolate problem
4. Document issue for team discussion

---

**Phase 0 Goal:** New system exists alongside old system with no breaking changes.

Good luck! 🎮
