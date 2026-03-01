@tool
extends Resource
class_name ZoneMood
## Defines the atmospheric mood for a zone — ambient lighting, bloom, particles, shadow mode.

@export_group("Ambient")
@export var ambient_color: Color = Color(0.8, 0.75, 0.7, 1.0)  ## CanvasModulate color

@export_group("Bloom")
@export var bloom_enabled: bool = true
@export var bloom_intensity: float = 0.8
@export var bloom_threshold: float = 0.7  ## Only bright things glow

@export_group("Particles")
@export var particle_type: String = ""  ## "snow", "dust_motes", "embers", or "" for none
@export var particle_tint: Color = Color.WHITE

@export_group("Shadows")
@export var realtime_shadows: bool = false  ## true for caves/interiors, false for outdoor
