# PHASE 7: LIGHTING & ATMOSPHERE

> **Goal**: Dynamic lighting with normal maps, snow particles, atmospheric post-processing
> **Prerequisites**: Phase 6 complete (world objects and tileset working)
> **Estimated Scope**: Large - shaders + normal maps + particles + environment setup

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Lighting philosophy, snow/mountain atmosphere
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Lit shader code, light source colors
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Weather system requirements
- `docs/visual_phases/PHASE_6_WORLD_OBJECTS.md` - What was built in Phase 6

**Key decisions from Art Direction:**
- Dynamic lighting with normal maps
- Mountain peaks atmosphere with SNOW is key visual identity
- Light source colors: torch=warm orange, magic=cyan/varies, moon=blue-silver
- Post-processing: bloom on bright colors (cyans, magentas), subtle vignette
- Heavy particle use (snow, dust, embers)

---

## IMPLEMENTATION STEPS

### Step 7.1: Create Lit UV Shader

**File**: `shaders/uv_lookup_lit.gdshader`

Full version with normal map support:

```glsl
shader_type canvas_item;
render_mode light_only;

// Skin texture layers
uniform sampler2D skin_body : hint_default_white, filter_nearest;
uniform sampler2D skin_armor : hint_default_white, filter_nearest;
uniform sampler2D skin_helmet : hint_default_white, filter_nearest;
uniform sampler2D skin_boots : hint_default_white, filter_nearest;

// Normal map layers
uniform sampler2D normal_body : hint_normal, filter_nearest;
uniform sampler2D normal_armor : hint_normal, filter_nearest;
uniform sampler2D normal_helmet : hint_normal, filter_nearest;
uniform sampler2D normal_boots : hint_normal, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Ambient light (minimum illumination)
uniform vec4 ambient_color : source_color = vec4(0.15, 0.15, 0.2, 1.0);
uniform float ambient_strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    // Sample motion map
    vec4 motion_data = texture(TEXTURE, UV);

    if (motion_data.a < 0.01) {
        discard;
    }

    // UV lookup
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    // Sample all skin layers
    vec4 body_color = texture(skin_body, skin_uv);
    vec4 armor_color = texture(skin_armor, skin_uv);
    vec4 helmet_color = texture(skin_helmet, skin_uv);
    vec4 boots_color = texture(skin_boots, skin_uv);

    // Composite colors
    vec4 final_color = body_color;
    final_color = mix(final_color, boots_color, boots_color.a);
    final_color = mix(final_color, armor_color, armor_color.a);
    final_color = mix(final_color, helmet_color, helmet_color.a);

    // Sample and composite normal maps
    vec3 body_normal = texture(normal_body, skin_uv).rgb * 2.0 - 1.0;
    vec3 armor_normal = texture(normal_armor, skin_uv).rgb * 2.0 - 1.0;
    vec3 helmet_normal = texture(normal_helmet, skin_uv).rgb * 2.0 - 1.0;
    vec3 boots_normal = texture(normal_boots, skin_uv).rgb * 2.0 - 1.0;

    // Blend normals based on alpha
    vec3 final_normal = body_normal;
    final_normal = mix(final_normal, boots_normal, boots_color.a);
    final_normal = mix(final_normal, armor_normal, armor_color.a);
    final_normal = mix(final_normal, helmet_normal, helmet_color.a);
    final_normal = normalize(final_normal);

    // Apply tint and flash
    final_color.rgb *= tint.rgb;
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Add ambient light
    final_color.rgb += ambient_color.rgb * ambient_strength;

    // Output color and normal
    COLOR = vec4(final_color.rgb, motion_data.a * final_color.a);

    // Convert normal back to texture space for Godot lighting
    NORMAL_MAP = vec4(final_normal * 0.5 + 0.5, 1.0);
}

void light() {
    // Godot's 2D lighting uses NORMAL_MAP automatically
    float NdotL = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
    LIGHT = LIGHT_COLOR.rgb * LIGHT_ENERGY * NdotL * COLOR.rgb;
}
```

---

### Step 7.2: Create Enemy Lit Shader

**File**: `shaders/uv_lookup_enemy_lit.gdshader`

```glsl
shader_type canvas_item;
render_mode light_only;

uniform sampler2D skin : hint_default_white, filter_nearest;
uniform sampler2D normal_map : hint_normal, filter_nearest;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec4 ambient_color : source_color = vec4(0.15, 0.15, 0.2, 1.0);
uniform float ambient_strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 motion_data = texture(TEXTURE, UV);

    if (motion_data.a < 0.01) {
        discard;
    }

    // Dissolve check
    if (dissolve_amount > 0.0 && motion_data.b < dissolve_amount) {
        discard;
    }

    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    vec4 skin_color = texture(skin, skin_uv);
    vec3 normal = texture(normal_map, skin_uv).rgb * 2.0 - 1.0;

    vec4 final_color = skin_color;
    final_color.rgb *= tint.rgb;
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);
    final_color.rgb += ambient_color.rgb * ambient_strength;

    // Dissolve edge glow
    if (dissolve_amount > 0.0 && motion_data.b < dissolve_amount + 0.1) {
        final_color.rgb += vec3(1.0, 0.5, 0.0) * 0.5;
    }

    COLOR = vec4(final_color.rgb, motion_data.a * skin_color.a);
    NORMAL_MAP = vec4(normal * 0.5 + 0.5, 1.0);
}

void light() {
    float NdotL = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
    LIGHT = LIGHT_COLOR.rgb * LIGHT_ENERGY * NdotL * COLOR.rgb;
}
```

---

### Step 7.3: Set Up WorldEnvironment

**Create scene/node**: Add to main game scene or zone scenes

```gdscript
# scripts/rendering/atmosphere_controller.gd
extends Node

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var canvas_modulate: CanvasModulate = $CanvasModulate


func _ready() -> void:
    _setup_environment()


func _setup_environment() -> void:
    var env = Environment.new()

    # Background
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.05, 0.05, 0.08)  # Dark blue-black

    # Ambient light (for areas without direct light)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.15, 0.15, 0.25)
    env.ambient_light_energy = 0.3

    # Glow/Bloom (essential for HLD look)
    env.glow_enabled = true
    env.glow_intensity = 0.8
    env.glow_strength = 1.0
    env.glow_bloom = 0.1
    env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
    env.glow_hdr_threshold = 0.8  # Only bright colors glow

    # Glow levels (which mip levels contribute)
    env.glow_levels = [true, true, true, false, false, false, false]

    # Adjustments (color grading)
    env.adjustment_enabled = true
    env.adjustment_brightness = 1.0
    env.adjustment_contrast = 1.1
    env.adjustment_saturation = 1.1

    world_env.environment = env


## Set zone-specific atmosphere
func set_zone_atmosphere(zone_type: String) -> void:
    var env = world_env.environment

    match zone_type:
        "snow_mountain":
            env.ambient_light_color = Color(0.2, 0.22, 0.3)
            env.glow_intensity = 0.6
            canvas_modulate.color = Color(0.9, 0.92, 1.0)

        "dark_dungeon":
            env.ambient_light_color = Color(0.1, 0.08, 0.12)
            env.glow_intensity = 1.0
            canvas_modulate.color = Color(0.7, 0.65, 0.8)

        "corrupted":
            env.ambient_light_color = Color(0.15, 0.08, 0.18)
            env.glow_intensity = 1.2
            canvas_modulate.color = Color(0.9, 0.7, 0.95)

        "forest":
            env.ambient_light_color = Color(0.12, 0.18, 0.1)
            env.glow_intensity = 0.5
            canvas_modulate.color = Color(0.85, 0.95, 0.8)

        _:  # Default
            env.ambient_light_color = Color(0.15, 0.15, 0.2)
            canvas_modulate.color = Color.WHITE
```

---

### Step 7.4: Create Light Sources

**File**: `scripts/rendering/game_light.gd`

Reusable light component:

```gdscript
class_name GameLight
extends PointLight2D

## Configurable game light with presets and animation

enum LightType { TORCH, MAGIC_FIRE, MAGIC_ICE, MAGIC_ARCANE, MAGIC_NATURE, MOONLIGHT, CAMPFIRE }

@export var light_type: LightType = LightType.TORCH
@export var flicker: bool = true
@export var flicker_intensity: float = 0.1
@export var flicker_speed: float = 10.0

var _base_energy: float
var _noise_offset: float


func _ready() -> void:
    _apply_preset()
    _base_energy = energy
    _noise_offset = randf() * 100.0

    # Load soft light texture
    texture = preload("res://assets/lights/soft_circle.png")


func _process(delta: float) -> void:
    if flicker:
        _update_flicker(delta)


func _apply_preset() -> void:
    match light_type:
        LightType.TORCH:
            color = Color(1.0, 0.7, 0.3)
            energy = 1.2
            texture_scale = 1.5
            shadow_enabled = true

        LightType.MAGIC_FIRE:
            color = Color(1.0, 0.4, 0.1)
            energy = 1.5
            texture_scale = 2.0
            shadow_enabled = false

        LightType.MAGIC_ICE:
            color = Color(0.5, 0.8, 1.0)
            energy = 1.0
            texture_scale = 1.8
            shadow_enabled = false

        LightType.MAGIC_ARCANE:
            color = Color(0.7, 0.3, 1.0)
            energy = 1.3
            texture_scale = 2.0
            shadow_enabled = false

        LightType.MAGIC_NATURE:
            color = Color(0.3, 1.0, 0.5)
            energy = 0.8
            texture_scale = 1.5
            shadow_enabled = false

        LightType.MOONLIGHT:
            color = Color(0.7, 0.75, 1.0)
            energy = 0.4
            texture_scale = 5.0
            shadow_enabled = true

        LightType.CAMPFIRE:
            color = Color(1.0, 0.6, 0.2)
            energy = 2.0
            texture_scale = 3.0
            shadow_enabled = true


func _update_flicker(delta: float) -> void:
    _noise_offset += delta * flicker_speed
    var noise_val = sin(_noise_offset) * sin(_noise_offset * 2.3) * sin(_noise_offset * 0.7)
    energy = _base_energy + (noise_val * flicker_intensity * _base_energy)
```

**Light texture needed**:
**File**: `assets/lights/soft_circle.png`
**Size**: 128×128 or 256×256
**What to create**: White circle with soft falloff (gradient from white center to transparent edge)

---

### Step 7.5: Create Snow Particle System

**File**: `scenes/effects/snow_particles.tscn`

```gdscript
# scripts/effects/snow_particles.gd
extends GPUParticles2D

## Configurable snow particle system

@export var intensity: float = 1.0:  # 0.0 = calm, 1.0 = normal, 2.0+ = blizzard
    set(value):
        intensity = value
        _update_intensity()

@export var wind_direction: Vector2 = Vector2(0.2, 0.0):
    set(value):
        wind_direction = value
        _update_wind()


func _ready() -> void:
    _setup_particles()


func _setup_particles() -> void:
    amount = 200
    lifetime = 8.0
    preprocess = 4.0
    explosiveness = 0.0
    randomness = 0.5

    var mat = ParticleProcessMaterial.new()

    # Emission (spawn at top of screen, wide area)
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    mat.emission_box_extents = Vector3(300, 10, 0)

    # Direction (falling with slight angle)
    mat.direction = Vector3(0.0, 1.0, 0.0)
    mat.spread = 15.0

    # Gravity
    mat.gravity = Vector3(0, 30, 0)

    # Initial velocity
    mat.initial_velocity_min = 20.0
    mat.initial_velocity_max = 40.0

    # Turbulence (wind effect)
    mat.turbulence_enabled = true
    mat.turbulence_noise_strength = 1.5
    mat.turbulence_noise_speed = 0.5
    mat.turbulence_noise_scale = 2.0

    # Scale variation
    mat.scale_min = 0.5
    mat.scale_max = 1.5

    # Fade in/out
    mat.color = Color(1, 1, 1, 0.8)

    process_material = mat

    # Snowflake texture
    texture = preload("res://assets/particles/snow_flake.png")

    _update_intensity()


func _update_intensity() -> void:
    if not process_material:
        return

    var mat = process_material as ParticleProcessMaterial

    amount = int(100 + 150 * intensity)
    mat.initial_velocity_min = 20.0 + 30.0 * intensity
    mat.initial_velocity_max = 40.0 + 60.0 * intensity
    mat.turbulence_noise_strength = 1.5 + 2.0 * intensity


func _update_wind() -> void:
    if not process_material:
        return

    var mat = process_material as ParticleProcessMaterial
    mat.direction = Vector3(wind_direction.x, 1.0, 0.0).normalized()


## Blizzard mode
func set_blizzard(enabled: bool) -> void:
    if enabled:
        intensity = 2.5
        wind_direction = Vector2(0.6, 0.0)
    else:
        intensity = 1.0
        wind_direction = Vector2(0.2, 0.0)
```

---

### Step 7.6: Create Ambient Particles

**File**: `scripts/effects/ambient_particles.gd`

For dust motes, floating debris, etc:

```gdscript
class_name AmbientParticles
extends GPUParticles2D

enum ParticleType { DUST, EMBERS, MAGIC_SPARKLES, POLLEN, ASH }

@export var particle_type: ParticleType = ParticleType.DUST


func _ready() -> void:
    _setup_by_type()


func _setup_by_type() -> void:
    var mat = ParticleProcessMaterial.new()

    match particle_type:
        ParticleType.DUST:
            _setup_dust(mat)
        ParticleType.EMBERS:
            _setup_embers(mat)
        ParticleType.MAGIC_SPARKLES:
            _setup_sparkles(mat)
        ParticleType.POLLEN:
            _setup_pollen(mat)
        ParticleType.ASH:
            _setup_ash(mat)

    process_material = mat


func _setup_dust(mat: ParticleProcessMaterial) -> void:
    amount = 30
    lifetime = 5.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    mat.emission_box_extents = Vector3(200, 150, 0)

    mat.direction = Vector3(0.3, -0.1, 0)
    mat.spread = 180.0
    mat.gravity = Vector3(0, 2, 0)
    mat.initial_velocity_min = 2.0
    mat.initial_velocity_max = 8.0

    mat.scale_min = 0.3
    mat.scale_max = 0.8
    mat.color = Color(1, 1, 1, 0.3)

    texture = preload("res://assets/particles/dust.png")


func _setup_embers(mat: ParticleProcessMaterial) -> void:
    amount = 20
    lifetime = 3.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
    mat.direction = Vector3(0, -1, 0)
    mat.spread = 30.0
    mat.gravity = Vector3(0, -20, 0)  # Float upward
    mat.initial_velocity_min = 10.0
    mat.initial_velocity_max = 30.0

    mat.scale_min = 0.5
    mat.scale_max = 1.0
    mat.color = Color(1, 0.6, 0.2, 0.8)

    # Fade out
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(1, 0.8, 0.3, 1))
    gradient.add_point(0.5, Color(1, 0.5, 0.2, 0.8))
    gradient.add_point(1.0, Color(0.5, 0.2, 0.1, 0))
    mat.color_ramp = GradientTexture1D.new()
    mat.color_ramp.gradient = gradient

    texture = preload("res://assets/particles/ember.png")


func _setup_sparkles(mat: ParticleProcessMaterial) -> void:
    amount = 15
    lifetime = 2.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 30.0
    mat.direction = Vector3(0, -1, 0)
    mat.spread = 180.0
    mat.gravity = Vector3(0, -5, 0)
    mat.initial_velocity_min = 5.0
    mat.initial_velocity_max = 15.0

    mat.scale_min = 0.3
    mat.scale_max = 0.7
    mat.color = Color(0.5, 1, 1, 0.9)

    texture = preload("res://assets/particles/sparkle.png")


func _setup_pollen(mat: ParticleProcessMaterial) -> void:
    amount = 40
    lifetime = 8.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    mat.emission_box_extents = Vector3(200, 150, 0)
    mat.direction = Vector3(0.5, 0.2, 0)
    mat.spread = 45.0
    mat.gravity = Vector3(0, 5, 0)
    mat.initial_velocity_min = 5.0
    mat.initial_velocity_max = 15.0
    mat.turbulence_enabled = true
    mat.turbulence_noise_strength = 3.0

    mat.scale_min = 0.2
    mat.scale_max = 0.5
    mat.color = Color(1, 1, 0.8, 0.5)

    texture = preload("res://assets/particles/dust.png")


func _setup_ash(mat: ParticleProcessMaterial) -> void:
    amount = 50
    lifetime = 6.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    mat.emission_box_extents = Vector3(250, 10, 0)
    mat.direction = Vector3(0.1, 1, 0)
    mat.spread = 20.0
    mat.gravity = Vector3(0, 15, 0)
    mat.initial_velocity_min = 10.0
    mat.initial_velocity_max = 25.0
    mat.turbulence_enabled = true
    mat.turbulence_noise_strength = 1.0

    mat.scale_min = 0.4
    mat.scale_max = 1.0
    mat.color = Color(0.4, 0.4, 0.4, 0.6)

    texture = preload("res://assets/particles/ash.png")
```

---

### Step 7.7: Create Particle Textures

**USER TASK: Create particle texture assets**

#### Snowflake
**File**: `assets/particles/snow_flake.png`
**Size**: 8×8 pixels
**What to draw**: Simple white dot or tiny snowflake
```
┌────────┐
│░░██░░░░│
│░████░░░│
│██████░░│
│░████░░░│
│░░██░░░░│
└────────┘
White (#FFFFFF) with soft edges
```

#### Dust
**File**: `assets/particles/dust.png`
**Size**: 4×4 pixels
**What to draw**: Tiny soft white dot
```
┌────┐
│░██░│
│████│
│░██░│
└────┘
```

#### Ember
**File**: `assets/particles/ember.png`
**Size**: 4×4 pixels
**What to draw**: Orange-yellow dot
```
Same shape as dust but:
- Center: #FFAA44
- Edge: #FF6622
```

#### Sparkle
**File**: `assets/particles/sparkle.png`
**Size**: 8×8 pixels
**What to draw**: Star/cross shape
```
┌────────┐
│░░░█░░░░│
│░░░█░░░░│
│░█████░░│
│░░░█░░░░│
│░░░█░░░░│
└────────┘
Cyan/white (#88FFFF)
```

#### Soft Light Circle (for lights)
**File**: `assets/lights/soft_circle.png`
**Size**: 128×128 pixels
**What to draw**: Radial gradient from white center to transparent edge
- Center: #FFFFFF, alpha 255
- Edge: #FFFFFF, alpha 0
- Smooth gradient between

---

### Step 7.8: Create Normal Maps

**USER TASK: Create normal maps for skins**

#### Body Normal Map
**File**: `assets/sprites/characters/player/skins/body_default_n.png`
**Size**: Same as body_default.png

**How to create normal maps:**

**Option A: Manual (basic)**
- Neutral flat: RGB(128, 128, 255) - the default blue
- Left-facing surface: decrease R (e.g., 100, 128, 255)
- Right-facing surface: increase R (e.g., 156, 128, 255)
- Up-facing surface: increase G (e.g., 128, 156, 255)
- Down-facing surface: decrease G (e.g., 128, 100, 255)

**Option B: Use a tool**
- Sprite Lamp
- Laigter (free)
- Normalizer (Photoshop plugin)
- GIMP normal map plugin

**Simple normal map for character:**
```
┌────────────────────────────────────┐
│  Areas curving LEFT: more red      │
│  Areas curving RIGHT: less red     │
│  Areas curving UP: more green      │
│  Areas curving DOWN: less green    │
│  Flat areas: (128, 128, 255)       │
└────────────────────────────────────┘
```

For a basic test, you can use a flat neutral normal map (all pixels = 128, 128, 255).

---

### Step 7.9: Create Test Scene

**File**: `scenes/test/test_lighting.tscn`

```gdscript
# scenes/test/test_lighting.gd
extends Node2D

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var player: Node2D = $Player
@onready var snow: GPUParticles2D = $SnowParticles
@onready var label: Label = $UI/Label

var torch_light: GameLight
var zone_types = ["snow_mountain", "dark_dungeon", "corrupted", "forest"]
var current_zone = 0


func _ready() -> void:
    _setup_test_light()
    _update_label()


func _setup_test_light() -> void:
    torch_light = preload("res://scenes/rendering/game_light.tscn").instantiate()
    torch_light.light_type = GameLight.LightType.TORCH
    torch_light.position = Vector2(100, 100)
    add_child(torch_light)


func _input(event: InputEvent) -> void:
    # Cycle zone atmosphere
    if event.is_action_pressed("ui_right"):
        current_zone = (current_zone + 1) % zone_types.size()
        $AtmosphereController.set_zone_atmosphere(zone_types[current_zone])
        _update_label()

    # Toggle snow
    if event is InputEventKey and event.pressed and event.keycode == KEY_S:
        snow.emitting = not snow.emitting
        _update_label()

    # Toggle blizzard
    if event is InputEventKey and event.pressed and event.keycode == KEY_B:
        snow.set_blizzard(not snow.intensity > 2.0)
        _update_label()

    # Move torch with mouse
    if event is InputEventMouseMotion:
        torch_light.position = event.position

    # Cycle light types
    if event is InputEventKey and event.pressed and event.keycode == KEY_L:
        var new_type = (torch_light.light_type + 1) % GameLight.LightType.size()
        torch_light.light_type = new_type
        torch_light._apply_preset()
        _update_label()


func _update_label() -> void:
    label.text = "Zone: %s\nSnow: %s\nLight: %s\n\n→ = Change zone\nS = Toggle snow\nB = Blizzard\nL = Light type\nMouse = Move light" % [
        zone_types[current_zone],
        "Blizzard" if snow.intensity > 2.0 else ("On" if snow.emitting else "Off"),
        GameLight.LightType.keys()[torch_light.light_type]
    ]
```

---

## VALIDATION CHECKLIST

After implementation, verify:

**Lighting:**
- [ ] Lit shader compiles without errors
- [ ] Characters respond to nearby PointLight2D
- [ ] Normal maps create depth illusion under light
- [ ] Light colors affect character appearance
- [ ] Torch light flickers
- [ ] Different light types have correct colors

**Atmosphere:**
- [ ] WorldEnvironment applies glow/bloom
- [ ] Bright colors (cyan, magenta) glow
- [ ] Zone atmosphere changes work
- [ ] Ambient light prevents pure black

**Particles:**
- [ ] Snow particles fall correctly
- [ ] Snow responds to wind
- [ ] Blizzard mode increases intensity
- [ ] Particle textures render correctly
- [ ] Dust/embers/sparkles work

**Integration:**
- [ ] Player character uses lit shader
- [ ] Enemies use lit shader
- [ ] Torches in test zone cast light
- [ ] Overall atmosphere feels "HLD-like"

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| No lighting effect | Sprite not using lit shader, or no PointLight2D |
| Lighting looks flat | Normal map missing or all neutral |
| No glow/bloom | WorldEnvironment not in scene or glow disabled |
| Particles invisible | Texture not loading or amount=0 |
| Snow too fast/slow | velocity or gravity values need tuning |

---

## FILES CREATED THIS PHASE

```
shaders/
├── uv_lookup_lit.gdshader
└── uv_lookup_enemy_lit.gdshader

scripts/
└── rendering/
    ├── atmosphere_controller.gd
    └── game_light.gd

scripts/
└── effects/
    ├── snow_particles.gd
    └── ambient_particles.gd

scenes/
└── rendering/
    └── game_light.tscn

scenes/
└── effects/
    ├── snow_particles.tscn
    └── ambient_particles.tscn

scenes/
└── test/
    ├── test_lighting.tscn
    └── test_lighting.gd

assets/
├── particles/
│   ├── snow_flake.png    ← USER CREATES
│   ├── dust.png          ← USER CREATES
│   ├── ember.png         ← USER CREATES
│   └── sparkle.png       ← USER CREATES
├── lights/
│   └── soft_circle.png   ← USER CREATES
└── sprites/
    └── characters/
        └── player/
            └── skins/
                └── body_default_n.png  ← USER CREATES (normal map)
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_8_POLISH_EFFECTS.md` which adds:
- Hit flash refinement
- Screen shake system
- Hitstop/freeze frame
- Hit particles
- Death effects
- Combat "juice"

---

## NOTES FOR IMPLEMENTER

- Normal maps are optional for first pass - can use flat neutral maps
- Glow/bloom is essential for HLD look - don't skip it
- Snow is KEY to mountain atmosphere - this is the visual identity
- Light texture (soft_circle) is crucial - without it lights look wrong
- Zone atmosphere presets can be expanded as new zones are created
- Consider adding breath particles for characters in snow zones (future polish)
- Performance note: too many particles or lights can impact mobile - test on device
