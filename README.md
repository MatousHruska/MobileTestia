# Heroes of Tesia

Mobile Action RPG built with Godot 4. Pixel art, top-down 3/4 perspective.

## Project Structure

```
HeroesOfTesia/
├── project.godot              # Godot project config + autoloads
├── GAME_DESIGN.md             # Complete design document
├── export_presets.cfg         # Android/iOS export configs
│
├── autoloads/                 # Global singletons
│   ├── debug_manager.gd       # Debug logging system
│   └── game_manager.gd        # Game state management
│
├── scenes/
│   ├── player/
│   │   └── player.tscn        # Player character (paper doll)
│   ├── camera/                # Camera scenes
│   ├── ui/
│   │   ├── hud/
│   │   │   └── game_hud.tscn  # In-game HUD
│   │   └── controls/          # Mobile input UI
│   └── world/
│       └── test_zone.tscn     # Test scene
│
├── scripts/
│   ├── player/
│   │   ├── player_controller.gd    # Movement, combat, input
│   │   └── character_animator.gd   # Paper doll animation system
│   ├── camera/
│   │   └── game_camera.gd     # Look-ahead camera
│   ├── ui/
│   │   ├── hud.gd             # HUD controller
│   │   ├── virtual_joystick.gd # Mobile joystick
│   │   └── action_button.gd   # Touch action buttons
│   ├── systems/               # Core game systems
│   ├── data/                  # Data structures
│   └── debug/                 # Debug utilities
│
└── resources/
    ├── sprites/               # Spritesheets
    ├── animations/            # Animation resources
    └── data/                  # JSON data files
```

## Debug System

Extensive logging for development. Use `Debug.print_export()` to copy console output for AI analysis.

```gdscript
# Logging
Debug.log("Player", "Spawned", position)
Debug.warn("Combat", "Damage overflow", value)
Debug.err("Save", "Failed to write", error)

# Performance timing
Debug.perf_start("loading")
# ... do work ...
Debug.perf_end("loading")

# State snapshots
Debug.snapshot("Player", "State", { "hp": hp, "pos": pos })

# Export for AI analysis
Debug.print_export(50)  # Last 50 log entries
```

## Controls (Mobile)

- **Left side**: Virtual joystick (floating)
- **Right side**: Attack button (large), Dodge button (small)

## Key Systems

| System | Description |
|--------|-------------|
| Paper Doll | Body + Head + Weapon layers with sync |
| 8→4 Animation | 8-way input maps to 4 cardinal animations |
| Look-ahead Camera | Camera leads player movement |
| Y-Sort | Lower objects render in front |

## Running

1. Open in Godot 4.2+
2. Press F5 to run test_zone.tscn
3. Touch/click left to move, right buttons to attack/dodge

## Version

0.1.0 - Foundation
