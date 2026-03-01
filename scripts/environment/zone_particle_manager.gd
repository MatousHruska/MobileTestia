extends Node2D
class_name ZoneParticleManager
## Manages zone-wide particle effects (snow, dust motes, embers).
## Attaches to the camera to follow the player.

var _active_particles: GPUParticles2D
var _camera: Camera2D


func setup(camera: Camera2D) -> void:
	_camera = camera


func _process(_delta: float) -> void:
	# Follow camera position so particles cover the viewport
	if _camera and is_instance_valid(_camera):
		global_position = _camera.global_position


func activate(particle_type: String, tint: Color) -> void:
	## Start the specified particle system.
	deactivate()

	match particle_type:
		"snow":
			_active_particles = _create_snow(tint)
		"dust_motes":
			_active_particles = _create_dust_motes(tint)
		"embers":
			_active_particles = _create_embers(tint)
		_:
			return

	add_child(_active_particles)


func deactivate() -> void:
	## Stop and remove current particle system.
	if _active_particles and is_instance_valid(_active_particles):
		_active_particles.queue_free()
		_active_particles = null


func _create_snow(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "SnowParticles"
	particles.amount = 60
	particles.lifetime = 5.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.2, 1.0, 0)
	mat.spread = 15.0
	mat.gravity = Vector3(10, 30, 0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 10, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.6)
	particles.process_material = mat

	particles.texture = _create_dot_texture(Color.WHITE, 4)
	return particles


func _create_dust_motes(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "DustParticles"
	particles.amount = 20
	particles.lifetime = 8.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -0.3, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, -2, 0)
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.scale_min = 0.3
	mat.scale_max = 1.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 250, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.3)
	particles.process_material = mat

	particles.texture = _create_dot_texture(Color.WHITE, 3)
	return particles


func _create_embers(tint: Color) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.name = "EmberParticles"
	particles.amount = 15
	particles.lifetime = 3.0
	particles.visibility_rect = Rect2(-500, -300, 1000, 600)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(5, -15, 0)
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(500, 250, 0)
	mat.color = Color(tint.r, tint.g, tint.b, 0.7)
	particles.process_material = mat

	particles.texture = _create_dot_texture(Color.WHITE, 3)
	return particles


func _create_dot_texture(color: Color, size: int) -> ImageTexture:
	## Create a small dot texture for particles.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
