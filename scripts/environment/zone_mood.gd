@tool
class_name ZoneMood
extends Resource
## Defines the atmospheric mood for a zone — ambient lighting, bloom, particles.

@export_group("Ambient")
@export var ambient_color: Color = Color(0.8, 0.75, 0.7, 1.0)  ## CanvasModulate color

@export_group("Bloom")
@export var bloom_enabled: bool = true
@export var bloom_intensity: float = 0.8
@export var bloom_threshold: float = 0.7  ## Only bright things glow

@export_group("Particles")
@export var particle_type: String = ""  ## "snow", "dust_motes", "embers", or "" for none
@export var particle_tint: Color = Color.WHITE
