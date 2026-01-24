extends Node2D
class_name LOSDebugDrawer
## LOSDebugDrawer - Visual debugging for Line of Sight in enemy AI
## Draws lines showing LOS status and last known positions

## Update interval for redrawing
const REDRAW_INTERVAL := 0.1
var _redraw_timer: float = 0.0


func _ready() -> void:
	# Draw on top of everything
	z_index = 1000


func _process(delta: float) -> void:
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Get all enemies
	var enemies := tree.get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		# Check for modular AI with context
		if not "module_controller" in enemy or not enemy.module_controller:
			continue

		var ctx: EnemyContext = enemy.module_controller.get_context()
		if not ctx:
			continue

		_draw_enemy_los(enemy, ctx)


func _draw_enemy_los(enemy: Node2D, ctx: EnemyContext) -> void:
	"""Draw LOS visualization for a single enemy"""
	var enemy_pos: Vector2 = enemy.global_position

	if ctx.has_valid_target and ctx.current_target:
		var target_pos: Vector2 = ctx.current_target.global_position

		if ctx.has_line_of_sight:
			# Green line - clear LOS
			draw_line(enemy_pos, target_pos, Color.GREEN, 1.0)
			# Draw small circle at target
			draw_circle(target_pos, 4.0, Color(0, 1, 0, 0.5))
		else:
			# Red line - blocked LOS
			draw_line(enemy_pos, target_pos, Color(1, 0, 0, 0.5), 1.0)

			# Draw X at collision point if we can determine it
			var los_result := PathfindingService.get_los_collision_point(enemy_pos, target_pos)
			if los_result.has_collision:
				var collision_pos: Vector2 = los_result.collision_point
				# Draw X marker at collision
				var x_size := 4.0
				draw_line(
					collision_pos + Vector2(-x_size, -x_size),
					collision_pos + Vector2(x_size, x_size),
					Color.RED, 2.0
				)
				draw_line(
					collision_pos + Vector2(-x_size, x_size),
					collision_pos + Vector2(x_size, -x_size),
					Color.RED, 2.0
				)

			# Draw yellow line to last known position
			if ctx.last_known_target_position != Vector2.ZERO:
				draw_line(
					enemy_pos,
					ctx.last_known_target_position,
					Color.YELLOW, 1.0
				)
				# Draw circle at last known position
				draw_circle(ctx.last_known_target_position, 6.0, Color(1, 1, 0, 0.3))

				# Draw timer text near enemy
				var timer_text := "%.1fs" % ctx.los_timer
				_draw_text_at(enemy_pos + Vector2(10, -20), timer_text, Color.YELLOW)


func _draw_text_at(pos: Vector2, text: String, color: Color) -> void:
	"""Draw text at a position (using a simple approach)"""
	# Note: In Godot 4, drawing text in _draw requires a font
	# We'll skip this for now - the text is shown in the overlay panel instead
	pass
