# PHASE 3: EQUIPMENT VISUALS

> **Goal**: Changing armor/helmet/boots visually updates the character appearance
> **Prerequisites**: Phase 2 complete (player movement animation working)
> **Estimated Scope**: Medium - shader upgrade + skin layers + inventory integration

---

## CONTEXT FOR NEW SESSION

Before implementing, consult these documents:
- `docs/ART_DIRECTION.md` - Equipment slot definitions
- `docs/VISUAL_SYSTEM_TECHNICAL.md` - Multi-layer shader code
- `docs/VISUAL_IMPLEMENTATION_ROADMAP.md` - Asset specifications
- `docs/visual_phases/PHASE_2_PLAYER_MOVEMENT.md` - What was built in Phase 2

**Key decisions from Art Direction:**
- Equipment slots (visual): Body, Armor, Helmet, Boots
- Weapons are separate (handled in Phase 4)
- Skins are overlay textures - transparent where they don't cover
- "None" skins are fully transparent (unequipped state)

---

## IMPLEMENTATION STEPS

### Step 3.1: Upgrade Shader to Multi-Layer

**Modify**: `shaders/uv_lookup.gdshader`

Replace with the full multi-layer version:

```glsl
shader_type canvas_item;
render_mode blend_mix;

// Skin texture layers (sampled via UV lookup)
uniform sampler2D skin_body : hint_default_white, filter_nearest;
uniform sampler2D skin_armor : hint_default_white, filter_nearest;
uniform sampler2D skin_helmet : hint_default_white, filter_nearest;
uniform sampler2D skin_boots : hint_default_white, filter_nearest;

// Visual modifiers
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    // Sample the motion map (sprite's TEXTURE)
    vec4 motion_data = texture(TEXTURE, UV);

    // Discard fully transparent pixels
    if (motion_data.a < 0.01) {
        discard;
    }

    // R,G channels encode UV coordinates into skin textures
    vec2 skin_uv = vec2(motion_data.r, motion_data.g);

    // Sample all skin layers at the same UV coordinate
    vec4 body_color = texture(skin_body, skin_uv);
    vec4 armor_color = texture(skin_armor, skin_uv);
    vec4 helmet_color = texture(skin_helmet, skin_uv);
    vec4 boots_color = texture(skin_boots, skin_uv);

    // Composite layers: each layer's alpha controls visibility
    // Order: body (base) → boots → armor → helmet (top)
    vec4 final_color = body_color;
    final_color = mix(final_color, boots_color, boots_color.a);
    final_color = mix(final_color, armor_color, armor_color.a);
    final_color = mix(final_color, helmet_color, helmet_color.a);

    // Apply tint (for status effects)
    final_color.rgb *= tint.rgb;

    // Apply hit flash
    final_color.rgb = mix(final_color.rgb, flash_color.rgb, flash_amount);

    // Output with motion map's alpha controlling overall shape
    COLOR = vec4(final_color.rgb, motion_data.a * final_color.a);
}
```

---

### Step 3.2: Update VisualAssetManager

**Modify**: `autoloads/visual_asset_manager.gd`

Add equipment skin loading:

```gdscript
# Add these methods to visual_asset_manager.gd

## Get skin for a specific equipment slot
func get_equipment_skin(slot: String, item_id: String) -> Texture2D:
    if item_id.is_empty() or item_id == "none":
        # Return transparent "none" skin
        return get_texture("sprites/characters/player/skins/" + slot + "/" + slot + "_none.png")

    var path = "sprites/characters/player/skins/" + slot + "/" + slot + "_" + item_id + ".png"
    return get_texture(path)


## Get all equipment skins for current loadout
func get_equipment_skins(loadout: Dictionary) -> Dictionary:
    return {
        "body": get_skin(loadout.get("body", "body_default")),
        "armor": get_equipment_skin("armor", loadout.get("armor", "none")),
        "helmet": get_equipment_skin("helmet", loadout.get("helmet", "none")),
        "boots": get_equipment_skin("boots", loadout.get("boots", "none")),
    }
```

---

### Step 3.3: Update UV Character Animator

**Modify**: `scripts/rendering/uv_character_animator.gd`

Add equipment management:

```gdscript
# Add/modify these in uv_character_animator.gd

# Equipment skin IDs
var _equipment: Dictionary = {
    "body": "body_default",
    "armor": "none",
    "helmet": "none",
    "boots": "none",
}


func _setup_material() -> void:
    _material = ShaderMaterial.new()
    _material.shader = load("res://shaders/uv_lookup.gdshader")
    sprite.material = _material
    _update_all_skins()


func _update_all_skins() -> void:
    _material.set_shader_parameter("skin_body",
        VisualAssets.get_skin(_equipment.body))
    _material.set_shader_parameter("skin_armor",
        VisualAssets.get_equipment_skin("armor", _equipment.armor))
    _material.set_shader_parameter("skin_helmet",
        VisualAssets.get_equipment_skin("helmet", _equipment.helmet))
    _material.set_shader_parameter("skin_boots",
        VisualAssets.get_equipment_skin("boots", _equipment.boots))


# =============================================================================
# EQUIPMENT API
# =============================================================================

## Equip armor piece
func equip_armor(item_id: String) -> void:
    _equipment.armor = item_id if not item_id.is_empty() else "none"
    _material.set_shader_parameter("skin_armor",
        VisualAssets.get_equipment_skin("armor", _equipment.armor))


## Equip helmet
func equip_helmet(item_id: String) -> void:
    _equipment.helmet = item_id if not item_id.is_empty() else "none"
    _material.set_shader_parameter("skin_helmet",
        VisualAssets.get_equipment_skin("helmet", _equipment.helmet))


## Equip boots
func equip_boots(item_id: String) -> void:
    _equipment.boots = item_id if not item_id.is_empty() else "none"
    _material.set_shader_parameter("skin_boots",
        VisualAssets.get_equipment_skin("boots", _equipment.boots))


## Unequip a slot
func unequip(slot: String) -> void:
    match slot:
        "armor":
            equip_armor("")
        "helmet":
            equip_helmet("")
        "boots":
            equip_boots("")


## Set full equipment loadout
func set_equipment(loadout: Dictionary) -> void:
    _equipment.body = loadout.get("body", "body_default")
    _equipment.armor = loadout.get("armor", "none")
    _equipment.helmet = loadout.get("helmet", "none")
    _equipment.boots = loadout.get("boots", "none")
    _update_all_skins()


## Get current equipment
func get_equipment() -> Dictionary:
    return _equipment.duplicate()
```

---

### Step 3.4: Connect to Inventory System

**Modify**: `scripts/player/player_controller.gd` or create equipment bridge

```gdscript
# Add to player controller or create scripts/player/player_equipment_visual.gd

func _ready() -> void:
    # ... existing code ...

    # Connect to inventory equipment changes
    if Inventory:
        Inventory.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(slot: String, item: ItemData) -> void:
    if not _animator:
        return

    var item_id = item.id if item else ""

    match slot:
        "chest", "armor", "body_armor":
            _animator.equip_armor(item_id)
        "head", "helmet":
            _animator.equip_helmet(item_id)
        "feet", "boots":
            _animator.equip_boots(item_id)
```

**Note**: Adapt slot names to match your existing inventory system's naming convention.

---

### Step 3.5: Create Test Scene for Equipment

**File**: `scenes/test/test_equipment.tscn`

```gdscript
# scenes/test/test_equipment.gd
extends Node2D

@onready var animator: UVCharacterAnimator = $UVCharacterAnimator
@onready var label: Label = $UI/Label

var equipment_sets = [
    { "armor": "none", "helmet": "none", "boots": "none" },
    { "armor": "leather", "helmet": "none", "boots": "none" },
    { "armor": "leather", "helmet": "leather", "boots": "none" },
    { "armor": "leather", "helmet": "leather", "boots": "leather" },
    { "armor": "chainmail", "helmet": "iron", "boots": "iron" },
]
var current_set = 0


func _ready() -> void:
    _update_label()


func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_right"):
        current_set = (current_set + 1) % equipment_sets.size()
        _apply_equipment()

    if event.is_action_pressed("ui_left"):
        current_set = (current_set - 1 + equipment_sets.size()) % equipment_sets.size()
        _apply_equipment()


func _apply_equipment() -> void:
    var set = equipment_sets[current_set]
    animator.equip_armor(set.armor)
    animator.equip_helmet(set.helmet)
    animator.equip_boots(set.boots)
    _update_label()


func _update_label() -> void:
    var set = equipment_sets[current_set]
    label.text = "Set %d/%d\nArmor: %s\nHelmet: %s\nBoots: %s\n\n← → to change" % [
        current_set + 1,
        equipment_sets.size(),
        set.armor,
        set.helmet,
        set.boots
    ]
```

---

### Step 3.6: Create Equipment Skin Assets

**USER TASK: Create these equipment skin textures**

#### Required "None" Skins (Transparent)

These are fully transparent textures used when slot is empty.

**Files**:
- `assets/sprites/characters/player/skins/armor/armor_none.png`
- `assets/sprites/characters/player/skins/helmet/helmet_none.png`
- `assets/sprites/characters/player/skins/boots/boots_none.png`

**Size**: Same as body skin (32×32 or 64×64)
**Content**: Fully transparent (all pixels alpha = 0)

**Quick creation**: In any image editor, create new image, don't draw anything, save as PNG with transparency.

#### Leather Armor Skin

**File**: `assets/sprites/characters/player/skins/armor/armor_leather.png`
**Size**: Same as body skin (32×32 or 64×64)

**What to draw**: Only the armor parts, transparent everywhere else

```
┌────────────────────────────────┐
│        (transparent)           │
│                                │
│       ████████████             │  ← Shoulder straps
│      ██████████████            │  ← Chest piece (leather brown)
│      ██████████████            │
│       ████████████             │
│        ██████████              │  ← Belt/waist
│        (transparent)           │
│                                │
└────────────────────────────────┘
```

**Colors**: Browns, tans (leather look)
- Main leather: #8B4513 or #A0522D
- Darker accents: #5D3A1A
- Highlights: #C4A484

#### Leather Helmet Skin

**File**: `assets/sprites/characters/player/skins/helmet/helmet_leather.png`
**Size**: Same as body skin

**What to draw**: Only the head covering area

```
┌────────────────────────────────┐
│         ████████               │  ← Leather cap top
│        ██████████              │  ← Cap sides
│       ████████████             │  ← Covers forehead
│        (transparent)           │  ← Face visible
│                                │
│        (transparent)           │
└────────────────────────────────┘
```

#### Leather Boots Skin

**File**: `assets/sprites/characters/player/skins/boots/boots_leather.png`
**Size**: Same as body skin

**What to draw**: Only the feet/lower leg area

```
┌────────────────────────────────┐
│        (transparent)           │
│                                │
│                                │
│                                │
│        ██      ██              │  ← Boot tops
│        ████████████            │  ← Boot feet (leather brown)
│        ████████████            │
└────────────────────────────────┘
```

#### Optional: Chainmail/Iron Set (More Advanced)

For testing variety, create a second equipment tier:

- `armor/armor_chainmail.png` - Gray metallic chest piece
- `helmet/helmet_iron.png` - Metal helmet
- `boots/boots_iron.png` - Metal boots

**Colors**: Grays, silvers
- Base metal: #808080
- Dark accents: #505050
- Highlights: #C0C0C0

---

## ASSET ALIGNMENT CRITICAL

**All skin textures must align with the body skin!**

The motion map's UV coordinates point to the same locations on ALL skin textures. If armor skin is shifted by even 1 pixel, it won't align with the body.

**Workflow**:
1. Open body_default.png
2. Create new layer
3. Draw armor ON TOP of the body (using body as reference)
4. Hide body layer
5. Export just the armor layer as armor_leather.png

**Or use a template**:
```
┌────────────────────────────────┐
│  Create a template PSD/XCF:    │
│  - Layer 1: Body (reference)   │
│  - Layer 2: Armor (export)     │
│  - Layer 3: Helmet (export)    │
│  - Layer 4: Boots (export)     │
│                                │
│  Each layer exports separately │
│  but all aligned to same grid  │
└────────────────────────────────┘
```

---

## VALIDATION CHECKLIST

After implementation, verify:

- [ ] Shader compiles without errors
- [ ] Character renders with body only (no equipment)
- [ ] Equipping leather armor shows armor overlay
- [ ] Equipping leather helmet shows helmet overlay
- [ ] Equipping leather boots shows boots overlay
- [ ] All three equipped together look correct
- [ ] Unequipping removes the overlay
- [ ] Equipment persists through animation (walk, idle)
- [ ] Test scene cycles through equipment sets
- [ ] No visual artifacts at equipment edges

**Visual alignment test**:
```
1. Equip armor
2. Walk around
3. Equipment should stay perfectly aligned with body
4. No "sliding" or "floating" armor pieces
```

**If something is wrong**:
| Problem | Likely Cause |
|---------|--------------|
| Armor invisible | Skin texture not loading, or all alpha=0 |
| Armor misaligned | Skin texture not same size/alignment as body |
| Armor flickers | Z-fighting (shouldn't happen with 2D) |
| Armor doesn't change | Shader parameter not being set |
| Armor on wrong layer | mix() order in shader is wrong |

---

## FILES CREATED THIS PHASE

```
shaders/
└── uv_lookup.gdshader            ← MODIFIED (multi-layer)

autoloads/
└── visual_asset_manager.gd       ← MODIFIED (equipment methods)

scripts/
└── rendering/
    └── uv_character_animator.gd  ← MODIFIED (equipment API)

scenes/
└── test/
    ├── test_equipment.tscn
    └── test_equipment.gd

assets/
└── sprites/
    └── characters/
        └── player/
            └── skins/
                ├── armor/
                │   ├── armor_none.png       ← USER CREATES
                │   ├── armor_leather.png    ← USER CREATES
                │   └── armor_chainmail.png  ← USER CREATES (optional)
                ├── helmet/
                │   ├── helmet_none.png      ← USER CREATES
                │   ├── helmet_leather.png   ← USER CREATES
                │   └── helmet_iron.png      ← USER CREATES (optional)
                └── boots/
                    ├── boots_none.png       ← USER CREATES
                    ├── boots_leather.png    ← USER CREATES
                    └── boots_iron.png       ← USER CREATES (optional)
```

---

## NEXT PHASE

Once validated, proceed to `PHASE_4_PLAYER_COMBAT.md` which adds:
- Attack animations
- Weapon sprite rendering
- Anchor system for weapon positioning
- Combat integration

---

## NOTES FOR IMPLEMENTER

- Keep Phase 1 and 2 test scenes for debugging
- The "none" skins are critical - without them, unequipped slots may show garbage
- Equipment skin alignment is the #1 source of visual bugs
- Consider creating a debug mode that draws UV coordinates for alignment checking
- The inventory connection code depends on your existing inventory system's signals - adapt as needed
