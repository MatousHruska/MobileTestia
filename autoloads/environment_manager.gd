extends Node
class_name EnvironmentManagerClass
## Manages zone atmosphere — applies ZoneMood settings to CanvasModulate and WorldEnvironment.

var _canvas_modulate: CanvasModulate
var _world_env: WorldEnvironment
var _environment: Environment
var current_mood: ZoneMood


func _ready() -> void:
	# Create CanvasModulate for ambient color
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "ZoneAmbient"
	_canvas_modulate.color = Color.WHITE  # neutral until mood is set
	add_child(_canvas_modulate)

	# Create WorldEnvironment for bloom
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CANVAS
	_environment.glow_enabled = false
	_world_env = WorldEnvironment.new()
	_world_env.name = "ZoneBloom"
	_world_env.environment = _environment
	add_child(_world_env)


func apply_mood(mood: ZoneMood) -> void:
	## Apply a ZoneMood to the scene. Call from zone_base._ready().
	current_mood = mood

	# Ambient
	_canvas_modulate.color = mood.ambient_color

	# Bloom
	_environment.glow_enabled = mood.bloom_enabled
	if mood.bloom_enabled:
		_environment.glow_intensity = mood.bloom_intensity
		_environment.glow_bloom = 0.3
		_environment.glow_hdr_threshold = mood.bloom_threshold
		_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	Debug.log("Environment", "Applied mood: ambient=%s, bloom=%s (intensity=%.1f)" % [
		mood.ambient_color, mood.bloom_enabled, mood.bloom_intensity if mood.bloom_enabled else 0.0
	])


func clear_mood() -> void:
	## Reset to neutral — called when leaving a zone.
	current_mood = null
	_canvas_modulate.color = Color.WHITE
	_environment.glow_enabled = false
