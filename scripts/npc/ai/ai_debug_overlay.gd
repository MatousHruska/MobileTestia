extends CanvasLayer
## AIDebugOverlay - Visual debugging overlay for the enemy AI system
## Toggle with F11 key
##
## Shows:
## - Nearby enemies and their AI state
## - Module info, abilities loaded, cooldowns
## - Context flags (should_attack, attack_in_progress, etc.)
## - Real-time updates every frame

var enabled: bool = false

var _panel: Panel
var _vbox: VBoxContainer
var _enemy_labels: Dictionary = {}  # enemy node -> Label
var _summary_label: Label
var _last_update_time: float = 0.0
const UPDATE_INTERVAL := 0.1  # Update every 100ms

## LOS debug drawer instance
var _los_drawer: LOSDebugDrawer = null

## Singleton reference
static var instance: Node = null


func _ready() -> void:
	instance = self
	layer = 201  # Above quest overlay
	_create_ui()
	visible = false
	Debug.info("AI", "Debug overlay initialized (toggle via debug menu)")


func _process(delta: float) -> void:
	if not enabled:
		return

	_last_update_time += delta
	if _last_update_time >= UPDATE_INTERVAL:
		_last_update_time = 0.0
		_update_display()


func toggle() -> void:
	enabled = not enabled
	visible = enabled
	if enabled:
		Debug.info("AI", "Debug overlay enabled")
		_update_display()
		_create_los_drawer()
	else:
		Debug.info("AI", "Debug overlay disabled")
		_remove_los_drawer()


func _create_los_drawer() -> void:
	"""Create LOS debug drawer in the current scene"""
	if _los_drawer != null:
		return

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	_los_drawer = LOSDebugDrawer.new()
	_los_drawer.name = "LOSDebugDrawer"
	tree.current_scene.add_child(_los_drawer)


func _remove_los_drawer() -> void:
	"""Remove LOS debug drawer"""
	if _los_drawer != null:
		_los_drawer.queue_free()
		_los_drawer = null


func _create_ui() -> void:
	# Main panel
	_panel = Panel.new()
	_panel.name = "AIDebugPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 10
	_panel.offset_right = 500
	_panel.offset_top = 10
	_panel.offset_bottom = 600
	_panel.size = Vector2(490, 590)

	# Semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.set_corner_radius_all(5)
	_panel.add_theme_stylebox_override("panel", style)

	add_child(_panel)

	# Scroll container
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 5
	scroll.offset_right = -5
	scroll.offset_top = 5
	scroll.offset_bottom = -5
	_panel.add_child(scroll)

	# Content
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	# Header
	var header := Label.new()
	header.text = "=== AI DEBUG ==="
	header.add_theme_color_override("font_color", Color.GOLD)
	_vbox.add_child(header)

	# Summary section
	_summary_label = Label.new()
	_summary_label.name = "SummaryLabel"
	_summary_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	_vbox.add_child(_summary_label)

	# Separator
	var sep := Label.new()
	sep.text = "─".repeat(50)
	sep.add_theme_color_override("font_color", Color.DIM_GRAY)
	_vbox.add_child(sep)


func _update_display() -> void:
	if not is_inside_tree():
		return

	var tree = get_tree()
	if not tree:
		return

	# Get all enemies
	var enemies = tree.get_nodes_in_group("enemies")

	# Update summary
	var alive_count := 0
	var modular_count := 0
	for enemy in enemies:
		if "is_dead" in enemy and not enemy.is_dead:
			alive_count += 1
			if "module_controller" in enemy and enemy.module_controller:
				modular_count += 1

	_summary_label.text = "Enemies: %d alive (%d modular)" % [alive_count, modular_count]

	# Get player position for distance calculation
	var player_pos := Vector2.ZERO
	var player = tree.get_first_node_in_group("player")
	if player:
		player_pos = player.global_position

	# Clear old labels
	for label in _enemy_labels.values():
		if is_instance_valid(label):
			label.queue_free()
	_enemy_labels.clear()

	# Sort enemies by distance
	var enemy_data: Array = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue
		var dist := 0.0
		if player:
			dist = player_pos.distance_to(enemy.global_position)
		enemy_data.append({"enemy": enemy, "distance": dist})

	enemy_data.sort_custom(func(a, b): return a.distance < b.distance)

	# Show nearest 5 enemies
	var shown := 0
	for data in enemy_data:
		if shown >= 5:
			break
		_add_enemy_debug(data.enemy, data.distance)
		shown += 1


func _add_enemy_debug(enemy: Node2D, distance: float) -> void:
	var container := VBoxContainer.new()
	_vbox.add_child(container)
	_enemy_labels[enemy] = container

	# Enemy header
	var name_text := ""
	if "enemy_name" in enemy:
		name_text = enemy.enemy_name
	else:
		name_text = enemy.name

	var header := Label.new()
	header.text = "\n[%s] (dist: %.0f)" % [name_text, distance]
	header.add_theme_color_override("font_color", Color.ORANGE)
	container.add_child(header)

	# Check if using modular AI
	if not "module_controller" in enemy or not enemy.module_controller:
		var no_mod := Label.new()
		no_mod.text = "  (Not using modular AI)"
		no_mod.add_theme_color_override("font_color", Color.GRAY)
		container.add_child(no_mod)
		return

	var ctx: EnemyContext = enemy.module_controller.get_context()
	if not ctx:
		var no_ctx := Label.new()
		no_ctx.text = "  (No context)"
		no_ctx.add_theme_color_override("font_color", Color.RED)
		container.add_child(no_ctx)
		return

	# Context state
	var state_label := Label.new()
	var state_name = EnemyContext.BehaviorState.keys()[ctx.behavior_state]
	state_label.text = "  State: %s" % state_name
	state_label.add_theme_color_override("font_color", Color.CYAN)
	container.add_child(state_label)

	# Target info
	var target_label := Label.new()
	var target_text := "None"
	if ctx.has_valid_target and ctx.current_target:
		target_text = "%s (%.0f px)" % [ctx.current_target.name, ctx.target_distance]
	target_label.text = "  Target: %s" % target_text
	target_label.add_theme_color_override("font_color", Color.YELLOW if ctx.has_valid_target else Color.GRAY)
	container.add_child(target_label)

	# Flags
	var flags_label := Label.new()
	var flags: Array = []
	if ctx.should_attack:
		flags.append("ATTACK")
	if ctx.attack_in_progress:
		flags.append("ATTACKING")
	if ctx.is_in_attack_range:
		flags.append("IN_RANGE")
	if ctx.is_locked:
		flags.append("LOCKED")
	if ctx.should_stop:
		flags.append("STOP")
	if ctx.is_beyond_leash:
		flags.append("LEASHED")

	var flags_text := ", ".join(flags) if flags.size() > 0 else "(none)"
	flags_label.text = "  Flags: %s" % flags_text
	flags_label.add_theme_color_override("font_color", Color.LIME_GREEN if flags.size() > 0 else Color.GRAY)
	container.add_child(flags_label)

	# LOS status
	var los_label := Label.new()
	var los_text := ""
	if ctx.has_valid_target:
		if ctx.has_line_of_sight:
			los_text = "LOS: CLEAR"
			los_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			los_text = "LOS: BLOCKED (memory: %.1fs)" % ctx.los_timer
			los_label.add_theme_color_override("font_color", Color.ORANGE)
	else:
		los_text = "LOS: N/A"
		los_label.add_theme_color_override("font_color", Color.GRAY)
	los_label.text = "  %s" % los_text
	container.add_child(los_label)

	# Cooldown
	var cooldown_label := Label.new()
	cooldown_label.text = "  Cooldown: %.1fs" % ctx.attack_cooldown_remaining
	cooldown_label.add_theme_color_override("font_color", Color.CORAL if ctx.attack_cooldown_remaining > 0 else Color.GRAY)
	container.add_child(cooldown_label)

	# Movement
	var move_label := Label.new()
	move_label.text = "  Move: dir=%s spd=%.1f" % [
		_vec_str(ctx.desired_direction),
		ctx.speed_multiplier
	]
	move_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	container.add_child(move_label)

	# Modules
	var modules = enemy.module_controller.get_all_modules()
	var mod_names: Array = []
	for m in modules:
		mod_names.append(m.module_id.replace("mod_", ""))
	var modules_label := Label.new()
	modules_label.text = "  Modules (%d): %s" % [modules.size(), ", ".join(mod_names)]
	modules_label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
	container.add_child(modules_label)

	# Combat module details
	var combat_mod = enemy.module_controller.get_module("mod_combat")
	if combat_mod:
		var abilities_info := _get_combat_module_info(combat_mod)
		var combat_label := Label.new()
		combat_label.text = "  Combat: %s" % abilities_info
		combat_label.add_theme_color_override("font_color", Color.SALMON)
		container.add_child(combat_label)


func _get_combat_module_info(combat_mod: BaseModule) -> String:
	# Access private _abilities array
	if "_abilities" in combat_mod:
		var abilities: Array = combat_mod._abilities
		if abilities.is_empty():
			return "NO ABILITIES LOADED!"

		var info: Array = []
		for ability in abilities:
			var id: String = ability.get("id", "?")
			var short_id := id.replace("abi_", "")
			var cooldown_remaining := 0.0
			if "_cooldowns" in combat_mod:
				cooldown_remaining = combat_mod._cooldowns.get(id, 0.0)
			if cooldown_remaining > 0:
				info.append("%s (%.1fs)" % [short_id, cooldown_remaining])
			else:
				info.append(short_id)

		return "%d abilities: %s" % [abilities.size(), ", ".join(info)]

	return "(unable to read abilities)"


func _vec_str(v: Vector2) -> String:
	if v == Vector2.ZERO:
		return "ZERO"
	return "(%.1f, %.1f)" % [v.x, v.y]
