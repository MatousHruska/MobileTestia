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
@export var show_module_info: bool = true

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
var color_module := Color(0.9, 0.6, 1.0, 0.8)

## State colors for AI
var ai_state_colors := {
	"idle": Color(0.5, 0.5, 0.5),
	"combat": Color(1.0, 0.3, 0.0),
	"dead": Color(0.3, 0.3, 0.3),
	"chase": Color(1.0, 0.6, 0.0),
	"attack": Color(1.0, 0.2, 0.2),
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


func _draw_enemy(enemy: Node2D, camera: Camera2D) -> void:
	var screen_pos: Vector2 = _world_to_screen(enemy.global_position, camera)

	# Detection radius
	if show_detection_radii:
		var radius: float = enemy.detection_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 32, color_detection, 2.0)

	# Attack radius
	if show_attack_radii:
		var radius: float = enemy.attack_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, color_attack, 2.0)

	# Health bar
	if show_health_bars and not enemy.is_dead:
		_draw_health_bar(screen_pos + Vector2(-20, -30), 40, 6, enemy.get_health_percent())

	# AI State label - check for ModularEnemyNPC module system
	if show_ai_states:
		var state_name := "STATIC"
		var state_color := ai_state_colors.get("idle", Color.WHITE)

		# Check if using module system (ModularEnemyNPC)
		if enemy is ModularEnemyNPC and enemy.module_controller:
			var ctx = enemy.module_controller.get_context()
			state_name = EnemyContext.BehaviorState.keys()[ctx.behavior_state]
			match ctx.behavior_state:
				EnemyContext.BehaviorState.IDLE:
					state_color = ai_state_colors.get("idle", Color.WHITE)
				EnemyContext.BehaviorState.COMBAT:
					state_color = ai_state_colors.get("combat", Color.WHITE)
				EnemyContext.BehaviorState.DEAD:
					state_color = ai_state_colors.get("dead", Color.WHITE)

		_draw_label(screen_pos + Vector2(0, -40), state_name, state_color)

	# Target line - check for ModularEnemyNPC
	if show_target_lines and enemy is ModularEnemyNPC and enemy.module_controller:
		var ctx = enemy.module_controller.get_context()
		if ctx.current_target and is_instance_valid(ctx.current_target):
			var target_pos: Vector2 = _world_to_screen(ctx.current_target.global_position, camera)
			draw_node.draw_line(screen_pos, target_pos, color_target_line, 2.0)

	# Facing arrow
	if show_facing_arrows:
		var facing_vec: Vector2 = enemy.get_facing_vector() * 20 * camera.zoom.x
		var arrow_end: Vector2 = screen_pos + facing_vec
		draw_node.draw_line(screen_pos, arrow_end, color_facing, 2.0)
		_draw_arrow_head(arrow_end, facing_vec.normalized(), color_facing)

	# Velocity vector
	if show_velocity_vectors and enemy.velocity.length() > 1:
		var vel_vec: Vector2 = enemy.velocity.normalized() * 30 * camera.zoom.x
		draw_node.draw_line(screen_pos, screen_pos + vel_vec, color_velocity, 1.5)

	# Leash radius (area enemy will chase within)
	if show_patrol_paths:
		var leash_screen: Vector2 = _world_to_screen(enemy.home_position, camera)
		var leash_radius: float = enemy.leash_radius * camera.zoom.x
		draw_node.draw_arc(leash_screen, leash_radius, 0, TAU, 32, Color(0.5, 0.3, 0.3, 0.2), 1.5)

	# Module info for ModularEnemyNPC
	if show_module_info and enemy is ModularEnemyNPC and enemy.module_controller:
		_draw_module_info(enemy, screen_pos)


func _draw_module_info(enemy: ModularEnemyNPC, screen_pos: Vector2) -> void:
	## Draw module system debug info
	var y_offset := 15.0
	var x_offset := 50.0

	var ctx = enemy.module_controller.get_context()

	# Show target info
	if ctx.has_valid_target and ctx.current_target:
		var target_label := "Target: %s (%.0f)" % [ctx.current_target.name, ctx.target_distance]
		_draw_label(screen_pos + Vector2(x_offset, y_offset), target_label, color_target_line, 9)
		y_offset += 10.0

	# Show attack state
	if ctx.is_in_attack_range:
		_draw_label(screen_pos + Vector2(x_offset, y_offset), "[IN RANGE]", color_attack, 9)
		y_offset += 10.0

	if ctx.attack_in_progress:
		_draw_label(screen_pos + Vector2(x_offset, y_offset), "[ATTACKING]", Color(1.0, 0.3, 0.3), 9)
		y_offset += 10.0

	# Show active modules
	var modules = enemy.module_controller.get_all_modules()
	for module in modules:
		var minfo = module.get_debug_info()
		var module_label := "%s (p=%d)" % [minfo.name, minfo.priority]
		_draw_label(screen_pos + Vector2(x_offset, y_offset), module_label, color_module, 8)
		y_offset += 9.0


func _draw_friendly(npc: Node2D, camera: Camera2D) -> void:
	var screen_pos: Vector2 = _world_to_screen(npc.global_position, camera)

	# Interaction radius
	if npc.is_interactable:
		var radius: float = npc.interaction_radius * camera.zoom.x
		draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, color_friendly, 1.5)

	# Name label
	_draw_label(screen_pos + Vector2(0, -30), npc.npc_name, color_friendly)

	# Movement pattern indicator
	var pattern_names: Array = ["STATIC", "WANDER", "PATROL"]
	var pattern_name: String = pattern_names[npc.movement_pattern] if npc.movement_pattern < pattern_names.size() else "UNKNOWN"
	_draw_label(screen_pos + Vector2(0, -42), "[%s]" % pattern_name, Color(0.6, 0.8, 0.6), 10)

	# Wander radius (movement_pattern 1 = WANDER)
	if npc.movement_pattern == 1:
		var home_screen: Vector2 = _world_to_screen(npc.home_position, camera)
		var radius: float = npc.wander_radius * camera.zoom.x
		draw_node.draw_arc(home_screen, radius, 0, TAU, 32, Color(0.4, 0.7, 0.4, 0.3), 1.5)

	# Patrol path (movement_pattern 2 = PATROL)
	if npc.movement_pattern == 2 and not npc.patrol_points.is_empty():
		_draw_patrol_path(npc.home_position, npc.patrol_points, camera)

	# Facing arrow
	if show_facing_arrows:
		var facing_vec: Vector2 = npc.get_facing_vector() * 15 * camera.zoom.x
		draw_node.draw_line(screen_pos, screen_pos + facing_vec, color_friendly, 1.5)


func _draw_spawner(spawner: Node2D, camera: Camera2D) -> void:
	var screen_pos: Vector2 = _world_to_screen(spawner.global_position, camera)

	# Spawn radius
	var radius: float = spawner.spawn_radius * camera.zoom.x
	draw_node.draw_arc(screen_pos, radius, 0, TAU, 24, Color(0.8, 0.4, 0.8, 0.4), 2.0)

	# Spawner icon (simple X)
	var size: float = 8.0
	draw_node.draw_line(screen_pos + Vector2(-size, -size), screen_pos + Vector2(size, size), Color(0.8, 0.4, 0.8), 2.0)
	draw_node.draw_line(screen_pos + Vector2(size, -size), screen_pos + Vector2(-size, size), Color(0.8, 0.4, 0.8), 2.0)

	# Status label
	var status: String = "Active" if spawner.is_active else "Inactive"
	var alive_count: int = spawner.alive_enemies.size()
	var remaining_str: String = str(spawner.spawns_remaining) if spawner.spawns_remaining >= 0 else "INF"
	var label: String = "%s (%d/%d) [%s]" % [status, alive_count, spawner.max_alive, remaining_str]
	_draw_label(screen_pos + Vector2(0, -20), label, Color(0.8, 0.4, 0.8))

	# Wave info if applicable
	if spawner.wave_mode:
		var wave_label: String = "Wave %d" % spawner.current_wave
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


func toggle_module_info() -> void:
	show_module_info = not show_module_info
