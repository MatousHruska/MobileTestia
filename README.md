# MobileTestia

A mobile game testing project built with Godot 4.

## Project Structure

```
MobileTestia/
├── project.godot          # Main Godot project configuration
├── export_presets.cfg     # Mobile export configurations (Android/iOS)
├── icon.svg               # Application icon
├── scenes/                # Scene files (.tscn)
│   └── main.tscn          # Main entry scene
├── scripts/               # GDScript files (.gd)
│   └── main.gd            # Main scene logic
└── assets/                # Game assets
    ├── images/            # Sprites, textures, UI elements
    ├── sounds/            # Audio files
    └── fonts/             # Custom fonts
```

## Requirements

- Godot 4.2 or later
- For Android export: Android SDK, JDK 17+
- For iOS export: Xcode, Apple Developer account

## Getting Started

1. Open the project in Godot 4
2. The main scene will load automatically (`scenes/main.tscn`)
3. Press F5 or click "Run Project" to test

## Mobile Configuration

The project is pre-configured for mobile:
- Portrait orientation (720x1280 viewport)
- Touch input emulation from mouse
- Mobile rendering pipeline
- ETC2/ASTC texture compression

## Export

### Android
1. Set up Android SDK in Editor Settings
2. Configure keystores for signing
3. Export via Project > Export > Android

### iOS
1. Set up Xcode export templates
2. Configure provisioning profile
3. Export via Project > Export > iOS

## Version

Current version: 0.1.0
