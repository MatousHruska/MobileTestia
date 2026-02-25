class_name CompositionFrame
extends Resource
## A single frame in an attack composition timeline.
## Stores per-frame timing, weapon state, effect triggers, and echo settings.

## Frame duration in milliseconds (default 66ms ≈ 15fps)
@export var duration_ms: int = 66

## Whether the weapon sprite is visible during this frame
@export var weapon_visible: bool = true

## Whether the weapon renders in front of (true, z=1) or behind (false, z=-1) the body
@export var weapon_z_front: bool = true

## Effect asset ID to spawn when this frame plays (empty = no effect)
@export var effect_id: String = ""

## Where the effect spawns relative to the character
## "weapon_tip" = blade tip anchor, "center" = character center, "feet" = base
@export var effect_anchor: String = "weapon_tip"

## Pixel offset from the anchor point
@export var effect_offset: Vector2 = Vector2.ZERO

## Whether ghost afterimages are rendered during this frame
@export var echo_enabled: bool = false

## Number of ghost copies to show
@export var echo_count: int = 3

## Opacity range for ghost copies (first ghost → last ghost)
@export var echo_opacity_start: float = 0.5
@export var echo_opacity_end: float = 0.1

## Pixel spacing between ghost copies
@export var echo_spacing_px: float = 8.0
