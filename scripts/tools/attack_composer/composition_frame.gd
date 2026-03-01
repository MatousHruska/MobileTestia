class_name CompositionFrame
extends Resource
## A single frame in an attack composition timeline.
## Stores per-frame timing, weapon state, effect triggers, and echo settings.

## Frame duration in milliseconds (default 66ms ≈ 15fps)
@export var duration_ms: int = 66

## Whether the weapon sprite is visible during this frame
@export var weapon_visible: bool = true

## Effect asset ID to spawn when this frame plays (empty = no effect)
@export var effect_id: String = ""

## Where the effect spawns relative to the character
## "weapon_tip" = blade tip anchor, "center" = character center, "feet" = base
@export var effect_anchor: String = "weapon_tip"

## Pixel offset from the anchor point
@export var effect_offset: Vector2 = Vector2.ZERO

## Z-index for the effect sprite in the preview viewport
## Default 2 = above weapon (z=1), below crosshair overlay (z=3)
@export var effect_z_index: int = 2

## Rotation of the effect sprite in degrees (0 = no rotation)
@export var effect_rotation_deg: float = 0.0

## Whether ghost afterimages are rendered during this frame
@export var echo_enabled: bool = false

## Number of ghost copies to show
@export var echo_count: int = 3

## Opacity range for ghost copies (first ghost → last ghost)
@export var echo_opacity_start: float = 0.5
@export var echo_opacity_end: float = 0.1

## Pixel spacing between ghost copies
@export var echo_spacing_px: float = 8.0

## Per-frame body clip mask for weapon occlusion.
## Same dimensions as body sprite frame. null = no clipping.
## FORMAT_R8: 255 = body pixel (clips weapon), 0 = no clip.
@export var body_clip_mask: Image = null

## When true, auto-generate body_clip_mask from body sprite alpha on export/preview.
## When false, use hand-painted body_clip_mask (or null = no clipping).
@export var body_clip_auto: bool = false

## Per-frame alpha mask for effect transparency painting.
## Same dimensions as effect frame (frame_size × frame_size). null = fully opaque.
## FORMAT_R8: 255 = opaque, 0 = fully transparent.
@export var effect_alpha_mask: Image = null
