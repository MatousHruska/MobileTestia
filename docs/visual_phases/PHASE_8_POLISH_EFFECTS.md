# PHASE 8: POLISH & EFFECTS

> **Goal**: Combat juice - hit feedback, screen shake, hitstop, particles, death effects
> **Prerequisites**: Phase 7 complete (lighting and atmosphere working)
> **Estimated Scope**: Medium - feedback systems + particles + tweening

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Hit feedback specs (JUICY with hitstops)
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Effect system overview
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Polish requirements
- `docs/visual_phases/PHASE_7_LIGHTING_ATMOSPHERE.md` - What was built in Phase 7

**Key decisions from Art Direction:**
- Hit feedback: JUICY with hitstops
- Screen shake on heavy hits
- Particles: HEAVY use
- Blood/gore: Minimal to moderate
- Magic style: Grounded (subtle, not anime-flashy)
- Damage numbers: Stylized, size varies with damage

---

## IMPLEMENTATION STEPS

### Step 8.1: Create Screen Shake System

**File**: `scripts/effects/screen_shake.gd`

Add to camera or as autoload:

```gdscript
class_name ScreenShake
extends Node

## Screen shake manager - attach to Camera2D or use as singleton

var _camera: Camera2D
var _trauma: float = 0.0  # Current shake intensity (0-1)
var _trauma_decay: float = 2.0  # How fast trauma decays
var _max_offset: Vector2 = Vector2(10, 8)  # Maximum shake offset
var _max_rotation: float = 0.02  # Maximum rotation (radians)
var _noise: FastNoiseLite

var _original_offset: Vector2
var _original_rotation: float


func _ready() -> void:
    # Find camera
    _camera = get_viewport().get_camera_2d()
    if _camera:
        _original_offset = _camera.offset
        _original_rotation = _camera.rotation

    # Set up noise for organic shake
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.frequency = 2.0


func _process(delta: float) -> void:
    if _trauma <= 0 or not _camera:
        return

    # Decay trauma over time
    _trauma = max(_trauma - _trauma_decay * delta, 0)

    # Calculate shake using noise for organic feel
    var shake_amount = _trauma * _trauma  # Square for exponential falloff

    var time = Time.get_ticks_msec() / 1000.0
    var offset_x = _noise.get_noise_2d(time * 100, 0) * _max_offset.x * shake_amount
    var offset_y = _noise.get_noise_2d(0, time * 100) * _max_offset.y * shake_amount
    var rotation = _noise.get_noise_2d(time * 100, time * 100) * _max_rotation * shake_amount

    _camera.offset = _original_offset + Vector2(offset_x, offset_y)
    _camera.rotation = _original_rotation + rotation

    # Reset when shake is done
    if _trauma <= 0:
        _camera.offset = _original_offset
        _camera.rotation = _original_rotation


## Add trauma (0-1 range, can exceed 1 and will be clamped)
func add_trauma(amount: float) -> void:
    _trauma = min(_trauma + amount, 1.0)


## Convenience presets
func shake_light() -> void:
    add_trauma(0.2)


func shake_medium() -> void:
    add_trauma(0.4)


func shake_heavy() -> void:
    add_trauma(0.7)


func shake_extreme() -> void:
    add_trauma(1.0)


## Direct shake with custom parameters
func shake(intensity: float, duration: float = 0.3) -> void:
    add_trauma(intensity)
    # Adjust decay to match duration
    _trauma_decay = 1.0 / duration
```

---

### Step 8.2: Create Hitstop System

**File**: `scripts/effects/hitstop.gd`

```gdscript
extends Node

## Hitstop/freeze frame manager - use as autoload

signal hitstop_started
signal hitstop_ended

var _is_frozen: bool = false
var _freeze_timer: float = 0.0
var _original_time_scale: float = 1.0


func _process(delta: float) -> void:
    if not _is_frozen:
        return

    _freeze_timer -= delta / _original_time_scale  # Use real delta

    if _freeze_timer <= 0:
        _end_hitstop()


## Freeze the game for a brief moment
func freeze(duration: float = 0.05) -> void:
    if _is_frozen:
        # Extend existing hitstop
        _freeze_timer = max(_freeze_timer, duration)
        return

    _is_frozen = true
    _freeze_timer = duration
    _original_time_scale = Engine.time_scale
    Engine.time_scale = 0.0

    hitstop_started.emit()


func _end_hitstop() -> void:
    _is_frozen = false
    Engine.time_scale = _original_time_scale

    hitstop_ended.emit()


## Convenience presets
func hitstop_light() -> void:
    freeze(0.03)


func hitstop_medium() -> void:
    freeze(0.05)


func hitstop_heavy() -> void:
    freeze(0.08)


func hitstop_kill() -> void:
    freeze(0.12)


## Check if currently frozen
func is_frozen() -> bool:
    return _is_frozen
```

---

### Step 8.3: Create Hit Particle System

**File**: `scripts/effects/hit_particles.gd`

```gdscript
class_name HitParticles
extends GPUParticles2D

## One-shot hit effect particles

enum HitType { PHYSICAL, FIRE, ICE, LIGHTNING, POISON, ARCANE, BLEED }

@export var hit_type: HitType = HitType.PHYSICAL
@export var auto_free: bool = true


func _ready() -> void:
    one_shot = true
    emitting = false

    # Auto-free after particles finish
    if auto_free:
        finished.connect(_on_finished)


func emit_at(pos: Vector2, direction: Vector2 = Vector2.ZERO, type: HitType = HitType.PHYSICAL) -> void:
    global_position = pos
    hit_type = type
    _configure_for_type()

    # Set direction if provided
    if direction != Vector2.ZERO and process_material:
        var mat = process_material as ParticleProcessMaterial
        mat.direction = Vector3(direction.x, direction.y, 0).normalized()

    emitting = true


func _configure_for_type() -> void:
    var mat = ParticleProcessMaterial.new()

    # Common settings
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 4.0
    mat.spread = 60.0
    mat.initial_velocity_min = 50.0
    mat.initial_velocity_max = 100.0
    mat.gravity = Vector3(0, 50, 0)
    mat.scale_min = 0.5
    mat.scale_max = 1.5

    amount = 12
    lifetime = 0.4

    match hit_type:
        HitType.PHYSICAL:
            mat.color = Color(1.0, 0.2, 0.2)  # Red (blood)
            texture = preload("res://assets/particles/blood_drop.png")

        HitType.FIRE:
            mat.color = Color(1.0, 0.5, 0.1)
            mat.gravity = Vector3(0, -30, 0)  # Float up
            texture = preload("res://assets/particles/ember.png")
            amount = 15

        HitType.ICE:
            mat.color = Color(0.5, 0.8, 1.0)
            mat.initial_velocity_min = 30.0
            mat.initial_velocity_max = 60.0
            texture = preload("res://assets/particles/ice_shard.png")

        HitType.LIGHTNING:
            mat.color = Color(1.0, 1.0, 0.5)
            mat.initial_velocity_min = 80.0
            mat.initial_velocity_max = 150.0
            texture = preload("res://assets/particles/spark.png")
            amount = 20
            lifetime = 0.2

        HitType.POISON:
            mat.color = Color(0.3, 0.8, 0.2)
            mat.gravity = Vector3(0, -10, 0)
            texture = preload("res://assets/particles/poison_drop.png")

        HitType.ARCANE:
            mat.color = Color(0.7, 0.3, 1.0)
            mat.gravity = Vector3(0, -20, 0)
            texture = preload("res://assets/particles/sparkle.png")

        HitType.BLEED:
            mat.color = Color(0.8, 0.0, 0.0)
            mat.gravity = Vector3(0, 80, 0)  # Drip down
            texture = preload("res://assets/particles/blood_drop.png")
            amount = 8
            lifetime = 0.5

    process_material = mat


func _on_finished() -> void:
    queue_free()
```

---

### Step 8.4: Create Combat Effects Manager

**File**: `autoloads/combat_effects.gd`

Centralized manager for all combat feedback:

```gdscript
extends Node

## Combat effects manager - handles all hit feedback
## Use as autoload: CombatEffects

# References (set in _ready or injected)
var _screen_shake: ScreenShake
var _hitstop: Node  # Hitstop autoload

# Particle pools
var _hit_particle_scene = preload("res://scenes/effects/hit_particles.tscn")


func _ready() -> void:
    # Get shake system (attached to camera or as child)
    _screen_shake = ScreenShake.new()
    add_child(_screen_shake)

    # Hitstop is assumed to be an autoload named "Hitstop"
    _hitstop = get_node_or_null("/root/Hitstop")


## Full hit feedback package
func do_hit_feedback(
    position: Vector2,
    damage: float,
    damage_type: String = "physical",
    is_critical: bool = false,
    is_kill: bool = false
) -> void:
    # Determine intensity based on damage and flags
    var intensity = _calculate_intensity(damage, is_critical, is_kill)

    # Screen shake
    if _screen_shake:
        _screen_shake.add_trauma(intensity * 0.3)

    # Hitstop
    if _hitstop:
        if is_kill:
            _hitstop.hitstop_kill()
        elif is_critical:
            _hitstop.hitstop_heavy()
        elif intensity > 0.5:
            _hitstop.hitstop_medium()
        else:
            _hitstop.hitstop_light()

    # Particles
    _spawn_hit_particles(position, damage_type, intensity)


func _calculate_intensity(damage: float, is_critical: bool, is_kill: bool) -> float:
    var base = clamp(damage / 50.0, 0.1, 1.0)  # Normalize by expected damage range

    if is_kill:
        return 1.0
    if is_critical:
        return min(base * 1.5, 1.0)

    return base


func _spawn_hit_particles(position: Vector2, damage_type: String, intensity: float) -> void:
    var particles = _hit_particle_scene.instantiate() as HitParticles

    var hit_type = HitParticles.HitType.PHYSICAL
    match damage_type.to_lower():
        "fire":
            hit_type = HitParticles.HitType.FIRE
        "cold", "ice":
            hit_type = HitParticles.HitType.ICE
        "lightning":
            hit_type = HitParticles.HitType.LIGHTNING
        "poison":
            hit_type = HitParticles.HitType.POISON
        "arcane":
            hit_type = HitParticles.HitType.ARCANE
        "bleed":
            hit_type = HitParticles.HitType.BLEED

    get_tree().current_scene.add_child(particles)
    particles.emit_at(position, Vector2.UP, hit_type)


## Shake only (for environmental effects)
func shake(intensity: float = 0.3) -> void:
    if _screen_shake:
        _screen_shake.add_trauma(intensity)


## Death effect (more dramatic)
func do_death_effect(position: Vector2, enemy_type: String = "") -> void:
    # Screen shake
    if _screen_shake:
        _screen_shake.shake_heavy()

    # Hitstop
    if _hitstop:
        _hitstop.hitstop_kill()

    # Death particles (more than hit particles)
    var particles = _hit_particle_scene.instantiate() as HitParticles
    particles.amount = 25
    particles.lifetime = 0.6
    get_tree().current_scene.add_child(particles)
    particles.emit_at(position, Vector2.ZERO, HitParticles.HitType.PHYSICAL)

    # Could add additional effects based on enemy_type
    # e.g., slimes splatter, skeletons scatter bones
```

---

### Step 8.5: Integrate with Combat System

**Modify**: Damage dealing code (wherever damage is applied)

```gdscript
# Example integration in your damage system

func apply_damage(target: Node, damage: float, damage_type: String, source: Node) -> void:
    # ... existing damage calculation ...

    var is_critical = _roll_critical()
    var final_damage = damage * (2.0 if is_critical else 1.0)

    # Apply damage to target
    target.take_damage(final_damage)

    # Check if this is a kill
    var is_kill = target.health <= 0

    # Trigger visual feedback
    CombatEffects.do_hit_feedback(
        target.global_position,
        final_damage,
        damage_type,
        is_critical,
        is_kill
    )

    # Flash the target
    if target.has_method("flash"):
        target.flash()

    # Spawn damage number
    CombatText.spawn_damage_number(
        target.global_position + Vector2(0, -20),
        int(final_damage),
        damage_type,
        is_critical
    )
```

---

### Step 8.6: Enhance Floating Combat Text

**Modify**: `autoloads/floating_combat_text_manager.gd` or equivalent

Add more visual polish to damage numbers:

```gdscript
# Add to your existing combat text system

func spawn_damage_number(
    position: Vector2,
    amount: int,
    damage_type: String = "physical",
    is_critical: bool = false
) -> void:
    var text = _create_combat_text()
    text.position = position

    # Set text
    text.text = str(amount)

    # Size based on damage (and critical)
    var base_size = 12
    var size_bonus = clamp(amount / 20.0, 0, 8)
    if is_critical:
        size_bonus += 4
        text.text = str(amount) + "!"

    text.add_theme_font_size_override("font_size", int(base_size + size_bonus))

    # Color based on damage type
    var color = _get_damage_color(damage_type)
    if is_critical:
        color = color.lightened(0.3)
    text.modulate = color

    # Animation
    var anim_type = "bounce" if is_critical else "float_up"
    _animate_text(text, anim_type)

    get_tree().current_scene.add_child(text)


func _get_damage_color(damage_type: String) -> Color:
    match damage_type.to_lower():
        "physical":
            return Color(1.0, 0.9, 0.8)  # White/cream
        "fire":
            return Color(1.0, 0.5, 0.1)  # Orange
        "cold", "ice":
            return Color(0.5, 0.8, 1.0)  # Light blue
        "lightning":
            return Color(1.0, 1.0, 0.3)  # Yellow
        "poison":
            return Color(0.3, 0.9, 0.2)  # Green
        "arcane":
            return Color(0.8, 0.4, 1.0)  # Purple
        "bleed":
            return Color(0.9, 0.1, 0.1)  # Red
        "heal":
            return Color(0.2, 1.0, 0.4)  # Bright green
        _:
            return Color.WHITE


func _animate_text(text: Label, anim_type: String) -> void:
    match anim_type:
        "float_up":
            var tween = create_tween()
            tween.set_parallel(true)
            tween.tween_property(text, "position:y", text.position.y - 30, 0.8)
            tween.tween_property(text, "modulate:a", 0.0, 0.8).set_delay(0.3)
            tween.chain().tween_callback(text.queue_free)

        "bounce":
            # Initial pop
            text.scale = Vector2(0.5, 0.5)
            var tween = create_tween()
            tween.tween_property(text, "scale", Vector2(1.3, 1.3), 0.1)
            tween.tween_property(text, "scale", Vector2(1.0, 1.0), 0.1)

            # Then float
            tween.set_parallel(true)
            tween.tween_property(text, "position:y", text.position.y - 40, 1.0)
            tween.tween_property(text, "modulate:a", 0.0, 1.0).set_delay(0.4)
            tween.chain().tween_callback(text.queue_free)

        "slide_right":
            var tween = create_tween()
            tween.set_parallel(true)
            tween.tween_property(text, "position:x", text.position.x + 50, 0.6)
            tween.tween_property(text, "position:y", text.position.y - 10, 0.6)
            tween.tween_property(text, "modulate:a", 0.0, 0.6).set_delay(0.2)
            tween.chain().tween_callback(text.queue_free)
```

---

### Step 8.7: Create Additional Particle Textures

**USER TASK: Create remaining particle assets**

#### Blood Drop
**File**: `assets/particles/blood_drop.png`
**Size**: 4×4 pixels
**What to draw**: Red droplet
```
┌────┐
│░██░│
│████│
│████│
│░██░│
└────┘
Color: #CC2222
```

#### Ice Shard
**File**: `assets/particles/ice_shard.png`
**Size**: 8×8 pixels
**What to draw**: Angular ice fragment
```
┌────────┐
│░░██░░░░│
│░████░░░│
│░░████░░│
│░░░███░░│
│░░░░██░░│
└────────┘
Colors: #88CCFF (main), #FFFFFF (highlight)
```

#### Spark
**File**: `assets/particles/spark.png`
**Size**: 4×4 pixels
**What to draw**: Bright yellow/white dot
```
┌────┐
│░██░│
│████│
│░██░│
└────┘
Color: #FFFFAA with #FFFFFF center
```

#### Poison Drop
**File**: `assets/particles/poison_drop.png`
**Size**: 4×4 pixels
**What to draw**: Green droplet (similar to blood)
```
Color: #44AA22
```

---

### Step 8.8: Create Test Scene

**File**: `scenes/test/test_combat_effects.tscn`

```gdscript
# scenes/test/test_combat_effects.gd
extends Node2D

@onready var dummy: Node2D = $Dummy  # A stationary target for testing
@onready var label: Label = $UI/Label

var damage_types = ["physical", "fire", "ice", "lightning", "poison", "arcane", "bleed"]
var current_type = 0
var test_damage = 25


func _ready() -> void:
    _update_label()


func _input(event: InputEvent) -> void:
    # Light hit
    if event.is_action_pressed("ui_accept"):
        _do_hit(false, false)

    # Critical hit
    if event is InputEventKey and event.pressed and event.keycode == KEY_C:
        _do_hit(true, false)

    # Kill hit
    if event is InputEventKey and event.pressed and event.keycode == KEY_K:
        _do_hit(false, true)

    # Cycle damage type
    if event.is_action_pressed("ui_right"):
        current_type = (current_type + 1) % damage_types.size()
        _update_label()

    if event.is_action_pressed("ui_left"):
        current_type = (current_type - 1 + damage_types.size()) % damage_types.size()
        _update_label()

    # Adjust damage
    if event.is_action_pressed("ui_up"):
        test_damage = min(test_damage + 10, 200)
        _update_label()

    if event.is_action_pressed("ui_down"):
        test_damage = max(test_damage - 10, 5)
        _update_label()

    # Screen shake only
    if event is InputEventKey and event.pressed and event.keycode == KEY_S:
        CombatEffects.shake(0.5)


func _do_hit(is_critical: bool, is_kill: bool) -> void:
    var pos = dummy.global_position

    # Flash dummy
    if dummy.has_method("flash"):
        dummy.flash()

    # Do feedback
    CombatEffects.do_hit_feedback(
        pos,
        test_damage,
        damage_types[current_type],
        is_critical,
        is_kill
    )

    # If kill, play death
    if is_kill and dummy.has_method("play_death"):
        dummy.play_death()


func _update_label() -> void:
    label.text = "Damage: %d\nType: %s\n\nSPACE = Hit\nC = Critical\nK = Kill\n← → = Type\n↑ ↓ = Damage\nS = Shake" % [
        test_damage,
        damage_types[current_type]
    ]
```

---

## VALIDATION CHECKLIST

After implementation, verify:

**Screen Shake:**
- [ ] Light shake is subtle
- [ ] Heavy shake is noticeable but not nauseating
- [ ] Shake decays smoothly
- [ ] Shake uses noise (not random jitter)

**Hitstop:**
- [ ] Brief freeze on hit
- [ ] Longer freeze on critical
- [ ] Even longer on kill
- [ ] Game resumes smoothly after hitstop

**Particles:**
- [ ] Physical hits spawn red particles
- [ ] Fire hits spawn orange/ember particles
- [ ] Ice hits spawn blue shards
- [ ] Lightning spawns yellow sparks
- [ ] Particles emit from hit position
- [ ] Particles auto-cleanup after emission

**Damage Numbers:**
- [ ] Numbers appear at hit position
- [ ] Size scales with damage
- [ ] Critical hits are larger with "!"
- [ ] Colors match damage type
- [ ] Numbers animate up and fade

**Integration:**
- [ ] Hitting enemy triggers all feedback
- [ ] Killing enemy triggers enhanced feedback
- [ ] Player getting hit triggers feedback
- [ ] Combat feels JUICY

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| No shake | ScreenShake not finding camera |
| Hitstop freezes forever | Engine.time_scale not resetting |
| Particles not visible | Texture missing or amount=0 |
| Numbers wrong color | damage_type string not matching |
| Effects feel weak | Intensity values too low |

---

## FILES CREATED THIS PHASE

```
scripts/
└── effects/
    ├── screen_shake.gd
    ├── hitstop.gd
    └── hit_particles.gd

autoloads/
└── combat_effects.gd

scenes/
└── effects/
    └── hit_particles.tscn

scenes/
└── test/
    ├── test_combat_effects.tscn
    └── test_combat_effects.gd

assets/
└── particles/
    ├── blood_drop.png    ← USER CREATES
    ├── ice_shard.png     ← USER CREATES
    ├── spark.png         ← USER CREATES
    └── poison_drop.png   ← USER CREATES
```

---

## AUTOLOAD REGISTRATION

Add to `project.godot`:
```
Hitstop="*res://scripts/effects/hitstop.gd"
CombatEffects="*res://autoloads/combat_effects.gd"
```

---

## PHASE COMPLETE - VISUAL SYSTEM DONE!

After Phase 8, the visual system is complete with:

✅ UV Lookup rendering for player and enemies
✅ Equipment visualization (armor, helmet, boots)
✅ Weapon sprites with anchor system
✅ Enemy variants using skin swapping
✅ World objects (chests, loot, tileset)
✅ Dynamic lighting with normal maps
✅ Snow/weather particle systems
✅ Hit feedback (shake, hitstop, particles)
✅ Polished damage numbers

---

## FUTURE ENHANCEMENTS

Not part of the core system, but could be added later:

- **Weapon trails/swooshes** during attacks
- **Footstep particles** (dust, snow)
- **Breath particles** in cold zones
- **Status effect visuals** (poison bubbles, burn embers on character)
- **More enemy types** (wolf, skeleton motion maps)
- **Additional weapon categories** (2-handed, bow)
- **Boss-specific effects**
- **Environmental interactions** (grass sway, water ripples)

---

## NOTES FOR IMPLEMENTER

- Hitstop can feel bad if overdone - keep it brief (< 0.1s for normal hits)
- Screen shake intensity should be tuned for mobile - too much is disorienting
- Particle counts affect mobile performance - test on device
- The combat feedback is modular - can be called from anywhere damage happens
- Consider adding haptic feedback on mobile (device vibration on hits)
- All timing values are starting points - tune based on feel
