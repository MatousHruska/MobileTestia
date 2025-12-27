extends CanvasLayer
class_name NPCDebugOverlay
## NPCDebugOverlay - Visual debugging overlay for NPC systems
## Shows AI states, detection radii, patrol paths, health bars, etc.

## Configuration
@export var enabled: bool = true
@export var show_health_bars: bool = true
@export var show_ai_states: bool = true
@export var show_detection_radii: bool = true
@export var show_attack_radii: bool = true
@export var show_patrol_paths: bool = true
@export var show_facing_arrows: bool = true
@export var show_target_lines: bool = true
@export var show_velocity_vectors: bool = false

## Colors
var color_health_bar_bg := Color(0.2, 0.2, 0.2, 0.8)
var color_health_bar_fill := Color(0.2, 0.8, 0.2, 0.9)
var color_health_bar_low := Color(0.9, 0.2, 0.2, 0.9)
var color_detection := Color(0.3, 0.6, 1.0, 0.2)
var color_attack := Color(1.0, 0.3, 0.3, 0.3)
var color_patrol := Color(0.4, 0.8, 0.4, 0.6)
var color_facing := Color(1.0, 1.0, 0.3, 0.8)
var color_target_line := Color(1.0, 0.5, 0.0, 0.6)
var color_velocity := Color(0.0, 1.0, 1.0, 0.7)
var color_friendly := Color(0.3, 0.8, 1.0, 0.8)
var color_enemy := Color(1.0, 0.4, 0.4, 0.8)

## State colors for AI
var ai_state_colors := {
	AIStateMachine.AIState.IDLE: Color(0.5, 0.5, 0.5),
	AIStateMachine.AIState.PATROL: Color(0.3, 0.6, 1.0),
	AIStateMachine.AIState.AGGRO: Color(1.0, 0.6, 0.0),
	AIStateMachine.AIState.CHASE: Color(1.0, 0.4, 0.0),
	AIStateMachine.AIState.ATTACK: Color(1.0, 0.0, 0.0),
	AIStateMachine.AIState.FLEE: Color(0.8, 0.8, 0.0),
	AIStateMachine.AIState.KITE: Color(0.6, 0.0, 0.8),
	AIStateMachine.AIState.BLOCK: Color(0.0, 0.5, 1.0),
	AIStateMachine.AIState.STUNNED: Color(0.6, 0.6, 0.6),
	AIStateMachine.AIState.DEAD: Color(0.3, 0.3, 0.3),
}

## Drawing node
var draw_node: Control


func _ready() -> void:
	layer = 100  ## Above everything
	_setup_draw_node()
	Debug.info("Debug", "NPC Debug Overlay ready")


func _setup_draw_node() -> void:
	draw_node = Control.new()
	draw_node.name = "DrawNode"
	draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(draw_node)

	draw_node.draw.connect(_on_draw)


func _process(_delta: float) -> void:
	if enabled:
		draw_node.queue_redraw()


func _on_draw() -> void:
	if not enabled:
		return

	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	# Get all NPCs in scene
	var enemies := get_tree().get_nodes_in_group("enemies")
	var friendlies := get_tree().get_nodes_in_group("friendlies")
	var spawners := get_tree().get_nodes_in_group("spawners")

	# Draw spawner info
	for spawner in spawners:
		if spawner is EnemySpawner:
			_draw_spawner(spawner, camera)

	# Draw friendly NPCs
	for npc in friendlies:
		if npc is FriendlyNPC:
			_draw_friendly(npc, camera)

	# Draw enemies
	for enemy in enemies:
		if enemy is EnemyNPC:
			_draw_enemy(enemy, camera)


func _world_to_screen(world_pos: Vector2, camera: Camera2D) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera_pos := camera.global_position
	var zoom := camera.zoom
	var offset := (world_pos - camera_pos) * zoom
	return viewport_size / 2.0 + offset


func _draw_enemy(enemy: EnemyNPC, camera: Camera2D) -> void:
	var screen_pos := _world_to_screen(enemy.global_position, camera)

	# Detection radius
	if show_detection_radii and enemy.ai_state_machine:
		var radius := enemy.detection_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 32, color_detection, 2.0)

	# Attack radius
	if show_attack_radii and enemy.ai_state_machine:
		var radius := enemy.attack_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, color_attack, 2.0)

	# Health bar
	if show_health_bars and not enemy.is_dead:
		_draw_health_bar(screen_pos + Vector2(-20, -30), 40, 6, enemy.get_health_percent())

	# AI State label
	if show_ai_states and enemy.ai_state_machine:
		var state_name := enemy.ai_state_machine.get_state_name()
		var state_color := ai_state_colors.get(enemy.ai_state_machine.current_state, Color.WHITE)
		_draw_label(screen_pos + Vector2(0, -40), state_name, state_color)

		# Archetype in smaller text
		var archetype := enemy.ai_state_machine.get_archetype_name()
		_draw_label(screen_pos + Vector2(0, -52), "[%s]" % archetype, Color(0.7, 0.7, 0.7), 10)

	# Target line
	if show_target_lines and enemy.ai_state_machine and enemy.ai_state_machine.target:
		var target_pos := _world_to_screen(enemy.ai_state_machine.target.global_position, camera)
		draw_node.draw_line(screen_pos, target_pos, color_target_line, 2.0)

	# Facing arrow
	if show_facing_arrows:
		var facing_vec := enemy.get_facing_vector() * 20 * camera.zoom.x
		var arrow_end := screen_pos + facing_vec
		draw_node.draw_line(screen_pos, arrow_end, color_facing, 2.0)
		_draw_arrow_head(arrow_end, facing_vec.normalized(), color_facing)

	# Velocity vector
	if show_velocity_vectors and enemy.velocity.length() > 1:
		var vel_vec := enemy.velocity.normalized() * 30 * camera.zoom.x
		draw_node.draw_line(screen_pos, screen_pos + vel_vec, color_velocity, 1.5)

	# Patrol path
	if show_patrol_paths and not enemy.patrol_points.is_empty():
		_draw_patrol_path(enemy.home_position, enemy.patrol_points, camera)


func _draw_friendly(npc: FriendlyNPC, camera: Camera2D) -> void:
	var screen_pos := _world_to_screen(npc.global_position, camera)

	# Interaction radius
	if npc.is_interactable:
		var radius := npc.interaction_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, color_friendly, 1.5)

	# Name label
	_draw_label(screen_pos + Vector2(0, -30), npc.npc_name, color_friendly)

	# Movement pattern indicator
	var pattern_name := FriendlyNPC.MovementPattern.keys()[npc.movement_pattern]
	_draw_label(screen_pos + Vector2(0, -42), "[%s]" % pattern_name, Color(0.6, 0.8, 0.6), 10)

	# Wander radius
	if npc.movement_pattern == FriendlyNPC.MovementPattern.WANDER:
		var home_screen := _world_to_screen(npc.home_position, camera)
		var radius := npc.wander_radius * camera.zoom.x
		draw_node.draw_arc(home_screen, radius, 0, TAU, 32, Color(0.4, 0.7, 0.4, 0.3), 1.5)

	# Patrol path
	if npc.movement_pattern == FriendlyNPC.MovementPattern.PATROL and not npc.patrol_points.is_empty():
		_draw_patrol_path(npc.home_position, npc.patrol_points, camera)

	# Facing arrow
	if show_facing_arrows:
		var facing_vec := npc.get_facing_vector() * 15 * camera.zoom.x
		draw_node.draw_line(screen_pos, screen_pos + facing_vec, color_friendly, 1.5)


func _draw_spawner(spawner: EnemySpawner, camera: Camera2D) -> void:
	var screen_pos := _world_to_screen(spawner.global_position, camera)

	# Spawn radius
	var radius := spawner.spawn_radius * camera.zoom.x
	draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, Color(0.8, 0.4, 0.8, 0.4), 2.0)

	# Spawner icon (simple X)
	var size := 8.0
	draw_node.draw_line(screen_pos + Vector2(-size, -size), screen_pos + Vector2(size, size), Color(0.8, 0.4, 0.8), 2.0)
	draw_node.draw_line(screen_pos + Vector2(size, -size), screen_pos + Vector2(-size, size), Color(0.8, 0.4, 0.8), 2.0)

	# Status label
	var status := "Active" if spawner.is_active else "Inactive"
	var alive_count := spawner.alive_enemies.size()
	var remaining := spawner.spawns_remaining if spawner.spawns_remaining >= 0 else "INF"
	var label := "%s (%d/%d) [%s]" % [status, alive_count, spawner.max_alive, remaining]
	_draw_label(screen_pos + Vector2(0, -20), label, Color(0.8, 0.4, 0.8))

	# Wave info if applicable
	if spawner.wave_mode:
		var wave_label := "Wave %d" % spawner.current_wave
		_draw_label(screen_pos + Vector2(0, -32), wave_label, Color(0.9, 0.6, 0.9), 10)


func _draw_health_bar(pos: Vector2, width: float, height: float, percent: float) -> void:
	# Background
	draw_node.draw_rect(Rect2(pos, Vector2(width, height)), color_health_bar_bg)

	# Fill
	var fill_color := color_health_bar_fill if percent > 0.3 else color_health_bar_low
	var fill_width := width * percent
	draw_node.draw_rect(Rect2(pos, Vector2(fill_width, height)), fill_color)

	# Border
	draw_node.draw_rect(Rect2(pos, Vector2(width, height)), Color.WHITE, false, 1.0)


func _draw_label(pos: Vector2, text: String, color: Color, font_size: int = 12) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := pos - Vector2(text_size.x / 2, 0)

	# Background
	var bg_rect := Rect2(text_pos - Vector2(2, font_size), text_size + Vector2(4, 4))
	draw_node.draw_rect(bg_rect, Color(0, 0, 0, 0.6))

	# Text
	draw_node.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_arrow_head(tip: Vector2, direction: Vector2, color: Color) -> void:
	var size := 6.0
	var left := tip - direction * size + direction.rotated(PI / 2) * size * 0.5
	var right := tip - direction * size - direction.rotated(PI / 2) * size * 0.5
	draw_node.draw_polygon([tip, left, right], [color, color, color])


func _draw_patrol_path(home: Vector2, points: Array, camera: Camera2D) -> void:
	if points.is_empty():
		return

	var prev_screen := _world_to_screen(home + points[0], camera)

	for i in range(1, points.size()):
		var next_screen := _world_to_screen(home + points[i], camera)
		draw_node.draw_line(prev_screen, next_screen, color_patrol, 2.0)

		# Draw point marker
		draw_node.draw_circle(prev_screen, 4, color_patrol)
		prev_screen = next_screen

	# Connect last to first for loop
	var first_screen := _world_to_screen(home + points[0], camera)
	draw_node.draw_line(prev_screen, first_screen, color_patrol * 0.5, 1.5)
	draw_node.draw_circle(prev_screen, 4, color_patrol)


## Toggle functions
func toggle() -> void:
	enabled = not enabled
	Debug.log("Debug", "NPC overlay %s" % ("enabled" if enabled else "disabled"))


func toggle_health_bars() -> void:
	show_health_bars = not show_health_bars


func toggle_ai_states() -> void:
	show_ai_states = not show_ai_states


func toggle_detection_radii() -> void:
	show_detection_radii = not show_detection_radii


func toggle_attack_radii() -> void:
	show_attack_radii = not show_attack_radii


func toggle_patrol_paths() -> void:
	show_patrol_paths = not show_patrol_paths


func toggle_facing_arrows() -> void:
	show_facing_arrows = not show_facing_arrows


func toggle_target_lines() -> void:
	show_target_lines = not show_target_lines


func toggle_velocity_vectors() -> void:
	show_velocity_vectors = not show_velocity_vectors
