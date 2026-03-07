class_name EnvironmentManagerClass
extends Node
## Manages zone atmosphere — applies ZoneMood settings to CanvasModulate and WorldEnvironment.
##
## IMPORTANT: CanvasModulate and WorldEnvironment are viewport-scoped. They must
## live inside the game SubViewport to affect game rendering. This autoload defers
## node creation until DualViewport registers the game viewport.

var _canvas_modulate: CanvasModulate
var _world_env: WorldEnvironment
var _environment: Environment
var _particle_manager: ZoneParticleManager
var _shadow_group: CanvasGroup  ## Shared CanvasGroup for anti-stacking shadows
var current_mood: ZoneMood

## Pending mood to apply once nodes are ready (if apply_mood called before viewport)
var _pending_mood: ZoneMood = null


func _ready() -> void:
	# Create the nodes but don't add them yet — wait for the game viewport
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "ZoneAmbient"
	_canvas_modulate.color = Color.WHITE  # neutral until mood is set

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CANVAS
	_environment.glow_enabled = false
	_world_env = WorldEnvironment.new()
	_world_env.name = "ZoneBloom"
	_world_env.environment = _environment

	_shadow_group = CanvasGroup.new()
	_shadow_group.name = "ShadowGroup"
	_shadow_group.self_modulate = Color(1, 1, 1, 0.0)  # Invisible until mood sets opacity

	# Wait for the game viewport to be registered, then attach nodes there
	var dual_viewport = get_node_or_null("/root/DualViewport")
	if dual_viewport:
		if dual_viewport.game_viewport:
			_attach_to_viewport(dual_viewport.game_viewport)
		else:
			dual_viewport.game_viewport_ready.connect(_on_game_viewport_ready, CONNECT_ONE_SHOT)
	else:
		# Fallback: attach to self (e.g., running a tool scene directly via F6)
		add_child(_canvas_modulate)
		add_child(_world_env)
		add_child(_shadow_group)


func _on_game_viewport_ready() -> void:
	var dual_viewport = get_node_or_null("/root/DualViewport")
	if dual_viewport and dual_viewport.game_viewport:
		_attach_to_viewport(dual_viewport.game_viewport)


func _attach_to_viewport(viewport: SubViewport) -> void:
	## Reparent CanvasModulate, WorldEnvironment, and ShadowGroup into the game viewport.
	for node in [_canvas_modulate, _world_env, _shadow_group]:
		if node.get_parent():
			node.get_parent().remove_child(node)

	viewport.add_child(_canvas_modulate)
	viewport.add_child(_world_env)
	# ShadowGroup must be a sibling of world_root (not inside it) to avoid
	# y_sort + shader interaction that breaks CanvasGroup merging.
	viewport.add_child(_shadow_group)
	Debug.log("Environment", "Attached to game viewport: %s" % viewport.name)

	# Apply any mood that was requested before the viewport was ready
	if _pending_mood:
		apply_mood(_pending_mood)
		_pending_mood = null


func apply_mood(mood: ZoneMood) -> void:
	## Apply a ZoneMood to the scene. Call from zone_base._ready().
	current_mood = mood

	# If nodes aren't in the tree yet, defer until they are
	if not _canvas_modulate.is_inside_tree():
		_pending_mood = mood
		return

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

	# Shadows
	_apply_shadow_params(mood.shadow_angle, mood.shadow_opacity)

	Debug.log("Environment", "Applied mood: ambient=%s, bloom=%s, particles=%s, shadow_angle=%s" % [
		mood.ambient_color, mood.bloom_enabled, mood.particle_type, mood.shadow_angle
	])


func clear_mood() -> void:
	## Reset to neutral — called when leaving a zone.
	current_mood = null
	_pending_mood = null
	if _canvas_modulate.is_inside_tree():
		_canvas_modulate.color = Color.WHITE
	_environment.glow_enabled = false
	if _particle_manager:
		_particle_manager.deactivate()
	_apply_shadow_params(0.0, 0.0)


func _apply_shadow_params(angle: float, opacity: float) -> void:
	## Update shadow group opacity and per-shadow angle.
	_shadow_group.self_modulate = Color(1, 1, 1, opacity)
	for shadow in get_tree().get_nodes_in_group("shadows"):
		if shadow is SilhouetteShadow:
			shadow.apply_params({"angle": angle})


func get_shadow_group() -> CanvasGroup:
	## Returns the shared CanvasGroup that shadows should reparent into.
	return _shadow_group


func _ensure_particle_manager() -> void:
	if _particle_manager and is_instance_valid(_particle_manager):
		return
	_particle_manager = ZoneParticleManager.new()
	_particle_manager.name = "ZoneParticles"
	# Particles should also live in the game viewport
	var target: Node = _canvas_modulate.get_parent() if _canvas_modulate.is_inside_tree() else self
	target.add_child(_particle_manager)
	# Find the game camera in the correct viewport
	var viewport := _particle_manager.get_viewport()
	if viewport:
		var camera := viewport.get_camera_2d()
		if camera:
			_particle_manager.setup(camera)
