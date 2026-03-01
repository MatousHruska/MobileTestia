class_name EnvironmentManagerClass
extends Node
## Manages zone atmosphere — applies ZoneMood settings to CanvasModulate and WorldEnvironment.

var _canvas_modulate: CanvasModulate
var _world_env: WorldEnvironment
var _environment: Environment
var _particle_manager: ZoneParticleManager
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

	# Particles
	if not mood.particle_type.is_empty():
		_ensure_particle_manager()
		_particle_manager.activate(mood.particle_type, mood.particle_tint)
	elif _particle_manager:
		_particle_manager.deactivate()

	Debug.log("Environment", "Applied mood: ambient=%s, bloom=%s, particles=%s" % [
		mood.ambient_color, mood.bloom_enabled, mood.particle_type
	])


func clear_mood() -> void:
	## Reset to neutral — called when leaving a zone.
	current_mood = null
	_canvas_modulate.color = Color.WHITE
	_environment.glow_enabled = false
	if _particle_manager:
		_particle_manager.deactivate()


func _ensure_particle_manager() -> void:
	if _particle_manager and is_instance_valid(_particle_manager):
		return
	_particle_manager = ZoneParticleManager.new()
	_particle_manager.name = "ZoneParticles"
	add_child(_particle_manager)
	# Find the game camera
	var camera := get_viewport().get_camera_2d()
	if camera:
		_particle_manager.setup(camera)
