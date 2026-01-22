# Collision Layer System

This document describes the collision layer architecture used in MobileTestia.

## Layer Assignments

| Layer | Binary | Decimal | Purpose | Used By |
|-------|--------|---------|---------|---------|
| 1 | `0b00000001` | 1 | **Walls/Obstacles** | StaticBody2D walls, TileMap collision |
| 2 | `0b00000010` | 2 | **Player Body** | Player CharacterBody2D |
| 3 | `0b00000100` | 4 | **Enemy Bodies** | Enemy CharacterBody2D (reserved) |
| 4 | `0b00001000` | 8 | **Player Attack Hitbox** | Player melee attack Area2D |
| 5 | `0b00010000` | 16 | **Enemy Hurtbox** | Enemy damage receiver Area2D |
| 6 | `0b00100000` | 32 | **Enemy Attack Hitbox** | Enemy ability hitboxes |
| 7 | `0b01000000` | 64 | **Triggers** | Zone transitions, interactables |
| 8 | `0b10000000` | 128 | *Reserved* | Future use |

---

## Component Configurations

### Player (`scenes/player/player.tscn`)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Player | CharacterBody2D | 2 | 1 | Detects walls for movement |
| AttackHitbox | Area2D | 4 | 8 | Detects enemy hurtboxes |

### Enemies (`scripts/npc/enemy_npc.gd`)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Body | CharacterBody2D | 1 (default) | 1 | Detects walls for movement |
| Hitbox | Area2D | 4 | 0 | Enemy attack (detected by player) |
| Hurtbox | Area2D | 8 | 2 | Receives player attacks |

### Walls (`scripts/world/wall.gd`)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Wall | StaticBody2D | 1 | 0 | Blocks CharacterBody2D, detected by projectile raycast |

**Important**: Walls must be added to the `"walls"` group for projectile raycast detection.

### Projectiles (`scripts/combat/projectile.gd`)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Projectile | Area2D | 0 | 3 (`0b00000011`) | Detects walls (1) + enemies (2) |
| WallRaycast | RayCast2D | - | 1 | Detects walls for collision |

### Magic Projectiles (`scripts/combat/magic_projectile.gd`)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| MagicProjectile | Area2D | 0 | 3 (`0b00000011`) | Detects walls (1) + enemies (2) |
| WallRaycast | RayCast2D | - | 1 | Detects walls for explosion trigger |

### Triggers (Zone Transitions)

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Zone Transition | Area2D | 0 | 2 | Detects player body (layer 2) |

### Interactables (InteractableBase subclasses)

All interactables extend `InteractableBase` which creates an internal `_interaction_area` Area2D for player detection.

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Chest | InteractableBase | 0 | 2 | Detects player for interact prompt |
| Lootable | InteractableBase | 0 | 2 | Quick-loot container |
| Sign | InteractableBase | 0 | 2 | Readable sign |
| Lore Echo | InteractableBase | 0 | 2 | Audio lore object |
| NPC | InteractableBase | 0 | 2 | Friendly NPC |

### Pressure Plates & Trigger Areas

These detect player entry without requiring interaction button press.

| Component | Type | Layer | Mask | Notes |
|-----------|------|-------|------|-------|
| Pressure Plate | Area2D | 0 | 2 | Detects player body (layer 2) |
| Trigger Area | Area2D | 0 | 2 | Invisible event trigger |

**Important**: Player is on `collision_layer = 2`, so all detection areas must have `collision_mask = 2`.

---

## Collision Interaction Matrix

```
                    DETECTED BY (Mask)
                    L1   L2   L3   L4   L5   L6
LAYER (Source)      Wall Play Enem PAtk EHrt EAtk
--------------------------------------------------
L1 Walls            -    -    -    -    -    -
L2 Player Body      X    -    -    -    -    -
L3 Enemy Bodies     X    -    -    -    -    -
L4 Player Attack    -    -    -    -    X    -
L5 Enemy Hurtbox    -    X    -    -    -    -
L6 Enemy Attack     -    X    -    -    -    -
```

Legend:
- `X` = Collision/Detection occurs
- `-` = No collision

---

## How Movement Works

### Player Movement
1. Player (Layer 2) has `collision_mask = 1` (walls)
2. `move_and_slide()` uses mask to detect walls
3. Player slides along walls, cannot pass through

### Enemy Movement
1. Enemies use CharacterBody2D with default Layer 1, Mask 1
2. Same `move_and_slide()` behavior as player
3. Navigation respects wall collisions

### Projectile Movement
1. Projectiles (Layer 0) have `collision_mask = 0b00000011`
2. Area2D detects enemies (Layer 2) for damage
3. RayCast2D detects walls (Layer 1) for stopping
4. Walls must be in `"walls"` group OR be TileMap

---

## Best Practices

### Creating New Walls
```gdscript
# Option 1: Use Wall script (recommended)
# Attach scripts/world/wall.gd to StaticBody2D

# Option 2: Manual setup
var wall = StaticBody2D.new()
wall.collision_layer = 1  # Layer 1
wall.collision_mask = 0   # Walls don't detect
wall.add_to_group("walls")
```

### Creating New Projectiles
```gdscript
# Inherit from Projectile or MagicProjectile
# Or set manually:
projectile.collision_layer = 0
projectile.collision_mask = 0b00000011  # Walls + Enemies
```

### Creating New Triggers
```gdscript
var trigger = Area2D.new()
trigger.collision_layer = 0
trigger.collision_mask = 2  # Player body is on layer 2
```

### Creating New Interactables
```gdscript
# Extend InteractableBase - collision is handled automatically
extends InteractableBase
class_name MyInteractable

# InteractableBase creates _interaction_area with:
#   collision_layer = 0
#   collision_mask = 2  # Detects player on layer 2
```

### Creating Enemy Hitboxes
```gdscript
var hitbox = Area2D.new()
hitbox.collision_layer = 4  # Or use dedicated layer
hitbox.collision_mask = 2   # Detect player
```

---

## Common Issues

### Player/Enemies pass through walls
- Check wall has `collision_layer = 1`
- Check CharacterBody2D has `collision_mask` including layer 1

### Projectiles don't hit walls
- Check wall is in `"walls"` group
- Check projectile raycast has `collision_mask = 1`
- Check wall has `collision_layer = 1`

### Projectiles don't hit enemies
- Check enemy has `collision_layer = 2` on body
- Check projectile has `collision_mask` including layer 2

### Attacks don't register
- Player attack: Check hitbox Layer 4, enemy hurtbox Layer 8
- Enemy attack: Check hitbox detects player Layer 2

### Interactables/Triggers not detecting player
- Check Area2D has `collision_mask = 2` (player is on layer 2, NOT layer 1)
- Check player scene has `collision_layer = 2` (see `scenes/player/player.tscn`)
- Common mistake: Using `collision_mask = 1` (that's walls, not player)

---

## Layer Bitmask Quick Reference

```
Layer 1:  0b00000001 = 1
Layer 2:  0b00000010 = 2
Layer 3:  0b00000100 = 4
Layer 4:  0b00001000 = 8
Layer 5:  0b00010000 = 16
Layer 6:  0b00100000 = 32
Layer 7:  0b01000000 = 64
Layer 8:  0b10000000 = 128

Combined examples:
Layers 1+2: 0b00000011 = 3
Layers 2+3: 0b00000110 = 6
Layers 1+2+3: 0b00000111 = 7
```
