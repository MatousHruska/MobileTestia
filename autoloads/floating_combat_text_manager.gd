extends Node
## FloatingCombatTextManager - Central manager for all floating combat text
##
## Manages object pooling, signal connections, tick batching, and text display.
## Automatically connects to combat signals when enemies/player are available.

## Scene reference
const COMBAT_TEXT_SCENE := preload("res://scenes/ui/combat_text/floating_combat_text.tscn")

## Signals for debug/external monitoring
signal text_displayed(target: Node2D, category: String, value: float)
signal text_pooled(active_count: int, pool_size: int)

## Settings (loaded from database)
var _enabled: bool = true
var _pool_size: int = 30
var _max_visible_per_target: int = 8
var _default_lifetime: float = 1.0
var _rise_speed: float = 45.0
var _spread_x: float = 20.0
var _spread_y: float = 8.0
var _fade_start: float = 0.65
var _stack_offset_y: float = 14.0
var _batch_window: float = 0.15
var _min_batch_count: int = 2

## Category data (loaded from database)
var _categories: Dictionary = {}  ## category_id -> category_data

## Object pool
var _pool: Array[FloatingCombatText] = []
var _active_texts: Array[FloatingCombatText] = []

## Active texts per target for stacking
var _target_texts: Dictionary = {}  ## target_instance_id -> Array[FloatingCombatText]

## Tick batching
var _pending_ticks: Dictionary = {}  ## target_instance_id -> {type: String, total: float, count: int, timer: float, color: Color}

## Connected enemies for cleanup
var _connected_enemies: Array[int] = []  ## instance IDs


#===============================================================================
# INITIALIZATION
#===============================================================================

func _ready() -> void:
	# Wait for databases to load
	if DatabaseLoader.combat_text_settings.is_empty():
		DatabaseLoader.databases_loaded.connect(_on_databases_loaded, CONNECT_ONE_SHOT)
	else:
		_load_settings()
		_initialize_pool()

	# Connect to Game signals for enemy tracking
	if Game:
		Game.zone_changed.connect(_on_zone_changed)

	# Connect to NPCManager for enemy registration
	if NPCManager:
		NPCManager.enemy_registered.connect(_on_enemy_spawned)

	# Connect to player stats
	_connect_player_signals()


func _on_databases_loaded() -> void:
	_load_settings()
	_initialize_pool()


func _load_settings() -> void:
	var settings: Dictionary = DatabaseLoader.combat_text_settings
	if settings.is_empty():
		Debug.warn("CombatTextManager", "No combat text settings found, using defaults")
		return

	_enabled = settings.get("enabled", true)
	_pool_size = int(settings.get("pool_size", 30))
	_max_visible_per_target = int(settings.get("max_visible_per_target", 8))
	_default_lifetime = float(settings.get("default_lifetime", 1.0))
	_rise_speed = float(settings.get("rise_speed", 45.0))
	_spread_x = float(settings.get("spread_range_x", 20.0))
	_spread_y = float(settings.get("spread_range_y", 8.0))
	_fade_start = float(settings.get("fade_start_percent", 0.65))
	_stack_offset_y = float(settings.get("stack_offset_y", 14.0))
	_batch_window = float(settings.get("batch_window", 0.15))
	_min_batch_count = int(settings.get("min_batch_count", 2))

	# Load categories
	_categories = DatabaseLoader.combat_text_categories.duplicate()

	Debug.info("CombatTextManager", "Settings loaded", {
		"enabled": _enabled,
		"pool_size": _pool_size,
		"categories": _categories.size()
	})


func _initialize_pool() -> void:
	# Clear existing pool
	for text in _pool:
		text.queue_free()
	_pool.clear()
	_active_texts.clear()

	# Create pool
	for i in _pool_size:
		var text_instance: FloatingCombatText = COMBAT_TEXT_SCENE.instantiate()
		text_instance.animation_finished.connect(_on_text_finished)
		add_child(text_instance)
		_pool.append(text_instance)

	Debug.log("CombatTextManager", "Pool initialized with %d instances" % _pool_size)


#===============================================================================
# SIGNAL CONNECTIONS
#===============================================================================

func _connect_player_signals() -> void:
	# Connect to PlayerStats for damage/healing on player
	if PlayerStats:
		if not PlayerStats.is_connected("damaged", _on_player_damaged):
			PlayerStats.damaged.connect(_on_player_damaged)
		if not PlayerStats.is_connected("healed", _on_player_healed):
			PlayerStats.healed.connect(_on_player_healed)

	# Connect to player's status effect manager for DoT/HoT ticks
	await get_tree().process_frame
	if Game and Game.player:
		var status_manager = Game.player.get_node_or_null("StatusEffectManager")
		if status_manager:
			if not status_manager.is_connected("effect_tick", _on_player_dot_tick):
				status_manager.effect_tick.connect(_on_player_dot_tick)
			if not status_manager.is_connected("heal_tick", _on_player_hot_tick):
				status_manager.heal_tick.connect(_on_player_hot_tick)


func _on_enemy_spawned(enemy: Node2D) -> void:
	if not enemy or not is_instance_valid(enemy):
		return

	var enemy_id := enemy.get_instance_id()
	if enemy_id in _connected_enemies:
		return

	# Connect to enemy damage signal with CONNECT_REFERENCE_COUNTED to auto-disconnect on free
	if enemy.has_signal("damaged"):
		enemy.damaged.connect(_on_enemy_damaged.bind(enemy), CONNECT_REFERENCE_COUNTED)
		_connected_enemies.append(enemy_id)

		# Clean up tracking when enemy dies
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died.bind(enemy_id), CONNECT_ONE_SHOT)

		# Connect to enemy status effects for DoT batching
		var status_component = enemy.get_node_or_null("StatusEffects")
		if status_component and status_component.has_signal("effect_tick"):
			status_component.effect_tick.connect(_on_enemy_dot_tick.bind(enemy), CONNECT_REFERENCE_COUNTED)
			Debug.log("CombatTextManager", "Connected to enemy DoT: %s" % enemy.name)

		Debug.log("CombatTextManager", "Connected to enemy: %s" % enemy.name)


func _on_enemy_died(enemy_id: int) -> void:
	## Clean up tracking when enemy dies to prevent stale references
	if enemy_id in _connected_enemies:
		_connected_enemies.erase(enemy_id)
	if enemy_id in _target_texts:
		_target_texts.erase(enemy_id)
	# Clean up any pending tick batches for this enemy
	var keys_to_remove: Array[String] = []
	for key in _pending_ticks:
		if key.begins_with(str(enemy_id) + "_"):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_pending_ticks.erase(key)


func _on_zone_changed(_zone_id: String) -> void:
	# Clear all active texts and pending batches when changing zones
	_clear_all_texts()
	_connected_enemies.clear()
	_pending_ticks.clear()

	# Reconnect to player in new zone
	call_deferred("_connect_player_signals")


func _clear_all_texts() -> void:
	for text in _active_texts:
		text.reset()
		if text not in _pool:
			_pool.append(text)
	_active_texts.clear()
	_target_texts.clear()


#===============================================================================
# DAMAGE/HEAL HANDLERS
#===============================================================================

func _on_player_damaged(amount: float, damage_type: String = "physical", is_crit: bool = false) -> void:
	if not _enabled or not Game.player:
		return

	var category_id := "ct_damage_" + damage_type.to_lower()
	if is_crit:
		category_id = "ct_damage_critical"

	_show_damage(Game.player, amount, category_id, is_crit)


func _on_player_healed(amount: float) -> void:
	if not _enabled or not Game.player:
		return

	_show_heal(Game.player, amount, "ct_heal_direct")


func _on_enemy_damaged(amount: float, _attacker: Node2D, enemy: Node2D) -> void:
	if not _enabled or not is_instance_valid(enemy):
		return

	# Check if this was DoT damage - if so, let the batching handler deal with it
	var was_dot := false
	if enemy.has_meta("last_damage_was_dot"):
		was_dot = enemy.get_meta("last_damage_was_dot")
		enemy.set_meta("last_damage_was_dot", false)  # Clear the flag

	if was_dot:
		# DoT damage is handled by _on_enemy_dot_tick batching, skip here
		return

	# Get damage type from last hit context if available
	var damage_type := "physical"
	var is_crit := false

	if enemy.has_meta("last_damage_type"):
		damage_type = enemy.get_meta("last_damage_type")
	if enemy.has_meta("last_hit_was_crit"):
		is_crit = enemy.get_meta("last_hit_was_crit")

	var category_id := "ct_damage_" + damage_type.to_lower()
	if is_crit:
		category_id = "ct_damage_critical"

	_show_damage(enemy, amount, category_id, is_crit)


#===============================================================================
# DOT/HOT TICK HANDLERS (with batching)
#===============================================================================

func _on_player_dot_tick(effect_type: String, damage: float) -> void:
	if not _enabled or not Game.player:
		return

	_batch_tick(Game.player, "dot", damage, effect_type)


func _on_player_hot_tick(effect_type: String, heal_amount: float) -> void:
	if not _enabled or not Game.player:
		return

	_batch_tick(Game.player, "hot", heal_amount, effect_type)


func _on_enemy_dot_tick(effect_type: String, damage: float, enemy: Node2D) -> void:
	if not _enabled or not is_instance_valid(enemy):
		return

	_batch_tick(enemy, "dot", damage, effect_type)


func _batch_tick(target: Node2D, tick_type: String, value: float, effect_type: String) -> void:
	var target_id := target.get_instance_id()
	var batch_key := "%d_%s" % [target_id, tick_type]

	if batch_key in _pending_ticks:
		# Add to existing batch
		_pending_ticks[batch_key].total += value
		_pending_ticks[batch_key].count += 1
	else:
		# Start new batch
		var color := _get_tick_color(tick_type, effect_type)
		_pending_ticks[batch_key] = {
			"target": target,
			"type": tick_type,
			"total": value,
			"count": 1,
			"timer": _batch_window,
			"color": color,
			"effect": effect_type
		}


func _process(delta: float) -> void:
	# Process tick batches
	var batches_to_remove: Array[String] = []

	for batch_key in _pending_ticks:
		var batch: Dictionary = _pending_ticks[batch_key]
		batch.timer -= delta

		if batch.timer <= 0:
			_flush_batch(batch_key, batch)
			batches_to_remove.append(batch_key)

	for key in batches_to_remove:
		_pending_ticks.erase(key)


func _flush_batch(_batch_key: String, batch: Dictionary) -> void:
	var target: Node2D = batch.target
	if not is_instance_valid(target):
		return

	var total: float = batch.total
	var count: int = batch.count
	var tick_type: String = batch.type
	var color: Color = batch.color

	# Determine category
	var category_id: String
	if tick_type == "dot":
		category_id = "ct_dot_tick"
	else:
		category_id = "ct_heal_tick"

	# Show batched text
	_show_tick(target, total, category_id, color, count)

	Debug.log("CombatTextManager", "Flushed batch", {
		"target": target.name,
		"type": tick_type,
		"total": total,
		"count": count
	})


func _get_tick_color(tick_type: String, effect_type: String) -> Color:
	if tick_type == "hot":
		return Color(0.3, 0.85, 0.4, 1.0)

	# Match DoT color to effect type
	match effect_type.to_lower():
		"burning", "burn", "fire":
			return Color(1.0, 0.4, 0.1, 1.0)
		"poison", "poisoned":
			return Color(0.3, 0.8, 0.2, 1.0)
		"rot", "decay":
			return Color(0.4, 0.25, 0.1, 1.0)
		"bleed", "bleeding":
			return Color(0.8, 0.1, 0.1, 1.0)
		_:
			return Color(0.85, 0.5, 0.3, 1.0)


#===============================================================================
# DISPLAY FUNCTIONS
#===============================================================================

func _show_damage(target: Node2D, amount: float, category_id: String, is_crit: bool = false) -> void:
	var category: Dictionary = _categories.get(category_id, {})
	if category.is_empty():
		category = _categories.get("ct_damage_physical", {})

	var config := _build_config(target, amount, category, is_crit)
	config.text = "-%d" % int(amount)

	_display_text(target, config)
	text_displayed.emit(target, category_id, amount)


func _show_heal(target: Node2D, amount: float, category_id: String) -> void:
	var category: Dictionary = _categories.get(category_id, {})
	if category.is_empty():
		category = _categories.get("ct_heal_direct", {})

	var config := _build_config(target, amount, category)
	var prefix: String = category.get("prefix", "+")
	config.text = "%s%d" % [prefix, int(amount)]

	_display_text(target, config)
	text_displayed.emit(target, category_id, amount)


func _show_tick(target: Node2D, amount: float, category_id: String, color: Color, count: int) -> void:
	var category: Dictionary = _categories.get(category_id, {})
	if category.is_empty():
		return

	var config := _build_config(target, amount, category)
	config.color = color

	var prefix: String = category.get("prefix", "")
	var sign_str := "-" if category_id == "ct_dot_tick" else "+"
	if count > 1:
		config.text = "%s%d (x%d)" % [sign_str, int(amount), count]
	else:
		config.text = "%s%d" % [sign_str, int(amount)]

	_display_text(target, config)
	text_displayed.emit(target, category_id, amount)


func _build_config(_target: Node2D, amount: float, category: Dictionary, _is_crit: bool = false) -> Dictionary:
	var lifetime_mult: float = category.get("lifetime_mult", 1.0)
	var font_size: int = int(category.get("font_size", 12))
	var anim_str: String = category.get("animation", "float_up")
	var color := _parse_color(category.get("color", "1.0,1.0,1.0,1.0"))
	var show_sign: bool = category.get("show_sign", true)

	# Calculate scale based on damage
	var scale_factor := 1.0
	if category.get("scale_with_damage", false):
		var min_scale: float = category.get("min_scale", 0.8)
		var max_scale: float = category.get("max_scale", 1.4)
		var threshold: float = category.get("scale_threshold", 50)
		if threshold > 0:
			var scale_progress := clampf(amount / threshold, 0.0, 1.0)
			scale_factor = lerpf(min_scale, max_scale, scale_progress)

	return {
		"category_id": category.get("id", ""),
		"text": "",
		"color": color,
		"font_size": font_size,
		"animation": FloatingCombatText.animation_from_string(anim_str),
		"lifetime": _default_lifetime * lifetime_mult,
		"show_sign": show_sign,
		"scale": scale_factor,
		"fade_start": _fade_start,
		"rise_speed": _rise_speed,
		"spread_x": _spread_x,
		"spread_y": _spread_y
	}


func _display_text(target: Node2D, config: Dictionary) -> void:
	if _pool.is_empty():
		Debug.warn("CombatTextManager", "Pool exhausted, recycling oldest text")
		_recycle_oldest()

	if _pool.is_empty():
		return

	var text_instance: FloatingCombatText = _pool.pop_back()
	_active_texts.append(text_instance)

	# Calculate position with stacking offset
	var base_position := _get_target_head_position(target)
	var stack_offset := _calculate_stack_offset(target)
	text_instance.position = base_position + stack_offset

	# Track per-target texts
	var target_id := target.get_instance_id()
	if target_id not in _target_texts:
		_target_texts[target_id] = []
	_target_texts[target_id].append(text_instance)

	# Show the text
	text_instance.show_text(config)

	text_pooled.emit(_active_texts.size(), _pool.size())


func _get_target_head_position(target: Node2D) -> Vector2:
	# Try to get head position from target
	if target.has_method("get_head_position"):
		return target.get_head_position()

	# Default: above center
	var offset_y := -30.0
	if target.has_node("CollisionShape2D"):
		var collision: CollisionShape2D = target.get_node("CollisionShape2D")
		if collision.shape is CapsuleShape2D:
			offset_y = -collision.shape.height / 2 - 10
	elif target.has_node("Sprite2D"):
		var sprite: Sprite2D = target.get_node("Sprite2D")
		offset_y = -sprite.texture.get_height() / 2 - 5 if sprite.texture else -30.0

	return target.global_position + Vector2(0, offset_y)


func _calculate_stack_offset(target: Node2D) -> Vector2:
	var target_id := target.get_instance_id()
	if target_id not in _target_texts:
		return Vector2.ZERO

	var active_count := 0
	for text in _target_texts[target_id]:
		if text._is_active:
			active_count += 1

	# Limit stacking
	active_count = mini(active_count, _max_visible_per_target)

	return Vector2(0, -_stack_offset_y * active_count)


func _recycle_oldest() -> void:
	if _active_texts.is_empty():
		return

	var oldest: FloatingCombatText = _active_texts.pop_front()
	oldest.reset()
	_pool.append(oldest)


func _on_text_finished(text: FloatingCombatText) -> void:
	text.reset()

	if text in _active_texts:
		_active_texts.erase(text)

	if text not in _pool:
		_pool.append(text)

	# Remove from target tracking
	for target_id in _target_texts:
		if text in _target_texts[target_id]:
			_target_texts[target_id].erase(text)
			if _target_texts[target_id].is_empty():
				_target_texts.erase(target_id)
			break

	text_pooled.emit(_active_texts.size(), _pool.size())


#===============================================================================
# PUBLIC API - Label Display
#===============================================================================

## Show a status label (DODGE, MISS, IMMUNE, ABSORB)
func show_label(target: Node2D, label_type: String) -> void:
	if not _enabled or not is_instance_valid(target):
		return

	var category_id := "ct_label_" + label_type.to_lower()
	var category: Dictionary = _categories.get(category_id, {})
	if category.is_empty():
		Debug.warn("CombatTextManager", "Unknown label category: %s" % category_id)
		return

	var config := _build_config(target, 0, category)
	config.text = label_type.to_upper()

	_display_text(target, config)
	text_displayed.emit(target, category_id, 0)


## Show custom text (for extensibility)
func show_custom(target: Node2D, text: String, color: Color = Color.WHITE, font_size: int = 12) -> void:
	if not _enabled or not is_instance_valid(target):
		return

	var config := {
		"category_id": "custom",
		"text": text,
		"color": color,
		"font_size": font_size,
		"animation": FloatingCombatText.AnimationType.FLOAT_UP,
		"lifetime": _default_lifetime,
		"show_sign": false,
		"scale": 1.0,
		"fade_start": _fade_start,
		"rise_speed": _rise_speed,
		"spread_x": _spread_x,
		"spread_y": _spread_y
	}

	_display_text(target, config)


#===============================================================================
# UTILITY
#===============================================================================

func _parse_color(color_str: String) -> Color:
	var parts := color_str.split(",")
	if parts.size() >= 3:
		var r := float(parts[0].strip_edges())
		var g := float(parts[1].strip_edges())
		var b := float(parts[2].strip_edges())
		var a := float(parts[3].strip_edges()) if parts.size() >= 4 else 1.0
		return Color(r, g, b, a)
	return Color.WHITE


## Toggle combat text on/off
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	Debug.log("CombatTextManager", "Combat text %s" % ("enabled" if enabled else "disabled"))


## Check if combat text is enabled
func is_enabled() -> bool:
	return _enabled


#===============================================================================
# DEBUG
#===============================================================================

## Debug: Show test damage on player
func debug_test_player_damage(amount: float = 25.0, damage_type: String = "physical", is_crit: bool = false) -> void:
	if Game.player:
		_on_player_damaged(amount, damage_type, is_crit)


## Debug: Show test heal on player
func debug_test_player_heal(amount: float = 15.0) -> void:
	if Game.player:
		_on_player_healed(amount)


## Debug: Show test label on player
func debug_test_label(label_type: String = "DODGE") -> void:
	if Game.player:
		show_label(Game.player, label_type)


## Debug: Print pool stats
func debug_print_stats() -> void:
	Debug.snapshot("CombatTextManager", "Pool Stats", {
		"pool_available": _pool.size(),
		"active_texts": _active_texts.size(),
		"pending_batches": _pending_ticks.size(),
		"connected_enemies": _connected_enemies.size(),
		"targets_tracked": _target_texts.size()
	})
