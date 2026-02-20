extends BaseModule
class_name PackAlertModule
## PackAlertModule - Alert nearby allies when acquiring target
## Useful for pack behaviors where enemies coordinate aggro

## Track if we've already alerted for current target (prevent spam)
var _alerted_for_current_target: bool = false

## Last known target (to detect target changes)
var _last_target: Node2D = null

## Reference to owning enemy
var _owner_ref: Node2D = null


func _init() -> void:
	module_id = "mod_pack_alert"
	module_name = "Pack Alert"
	module_type = ModuleType.SOCIAL
	priority = 95  # Run early, after detection (100)


func _on_setup(owner: Node2D) -> void:
	_owner_ref = owner


func _process_module(context: EnemyContext, _delta: float) -> void:
	# Reset alert flag when target changes
	if context.current_target != _last_target:
		_last_target = context.current_target
		_alerted_for_current_target = false

	# Alert allies when we acquire a target
	if context.has_valid_target and not _alerted_for_current_target:
		_alert_nearby_allies(context)
		_alerted_for_current_target = true

	# Respond to alerts from allies (if we don't have a target)
	if context.pack_alert_received and not context.has_valid_target:
		if context.pack_target and is_instance_valid(context.pack_target):
			context.current_target = context.pack_target
			context.has_valid_target = true
			context.target_just_acquired = true
			context.behavior_state = EnemyContext.BehaviorState.COMBAT

			Debug.log("AI", "%s responding to pack alert, targeting %s" % [
				context.owner.name if context.owner else "Unknown",
				context.pack_target.name if context.pack_target else "Unknown"
			])

		# Clear the alert flag after processing (whether successful or not)
		context.pack_alert_received = false
		context.pack_target = null
		context.pack_alert_source = null


func _alert_nearby_allies(context: EnemyContext) -> void:
	"""Send alert to nearby allies about our target"""
	var alert_radius: float = get_config_float("alert_radius", 150.0)
	var pack_group: String = get_config_string("pack_group", "")
	var alert_require_los: bool = get_config_bool("alert_require_los", true)
	var alert_count: int = 0

	# Find nearby enemies
	var enemies: Array = _owner_ref.get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		# Skip self
		if enemy == _owner_ref:
			continue

		# Skip dead or invalid
		if not is_instance_valid(enemy):
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		# Check distance
		var dist: float = context.global_position.distance_to(enemy.global_position)
		if dist > alert_radius:
			continue

		# Check pack group match (if specified)
		if not pack_group.is_empty():
			if not _has_matching_pack_group(enemy, pack_group):
				continue

		# Check LOS if required - ally must see either us or the target
		if alert_require_los:
			var can_see_us: bool = PathfindingService.has_line_of_sight(
				enemy.global_position,
				context.global_position
			)
			var can_see_target: bool = PathfindingService.has_line_of_sight(
				enemy.global_position,
				context.current_target.global_position
			)
			if not can_see_us and not can_see_target:
				continue  # Ally can't see us or target - no alert

		# Alert this ally
		if _send_alert_to(enemy, context.current_target):
			alert_count += 1

	if alert_count > 0:
		Debug.log("AI", "%s alerted %d allies within %.0f radius" % [
			context.owner.name if context.owner else "Unknown",
			alert_count,
			alert_radius
		])


func _has_matching_pack_group(enemy: Node2D, pack_group: String) -> bool:
	"""Check if enemy has a matching pack group"""
	if not "module_controller" in enemy or not enemy.module_controller:
		return false

	var pack_module: BaseModule = enemy.module_controller.get_module("mod_pack_alert")
	if not pack_module:
		return false

	return pack_module.get_config_string("pack_group", "") == pack_group


func _send_alert_to(enemy: Node2D, target: Node2D) -> bool:
	"""Send alert to a specific enemy"""
	if not "module_controller" in enemy or not enemy.module_controller:
		return false

	var ctx: EnemyContext = enemy.module_controller.get_context()
	if not ctx:
		return false

	# Only alert if they don't have a target
	if ctx.has_valid_target:
		return false

	# Set alert flags for their PackAlertModule to pick up
	ctx.pack_alert_received = true
	ctx.pack_target = target
	ctx.pack_alert_source = _owner_ref
	return true


func get_debug_info() -> Dictionary:
	var info: Dictionary = super.get_debug_info()
	info["alert_radius"] = get_config_float("alert_radius", 150.0)
	info["pack_group"] = get_config_string("pack_group", "")
	info["alerted_for_target"] = _alerted_for_current_target
	return info
