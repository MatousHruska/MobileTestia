extends Node2D
class_name EnemyHealthBar
## EnemyHealthBar - Floating health bar for enemies
##
## Features:
## - Smooth health bar animation with damage trailing effect
## - DoT (Damage over Time) preview showing predicted damage
## - Shield overlay (stub for future implementation)
## - Optional name label for bosses
## - Auto-hide at full health (configurable)

#===============================================================================
# SIGNALS
#===============================================================================

signal visibility_changed(is_visible: bool)

#===============================================================================
# CONSTANTS
#===============================================================================

const DOT_SEGMENT_MIN_WIDTH := 2.0  # Minimum pixel width for DoT segment to be visible

#===============================================================================
# INTERNAL NODES
#===============================================================================

var _bar_container: Control
var _background: ColorRect
var _health_fill: ColorRect
var _damage_fill: ColorRect  # Trailing damage indicator
var _dot_container: Control  # Container for DoT preview segments
var _shield_fill: ColorRect
var _border: ReferenceRect
var _name_label: Label

#===============================================================================
# STATE
#===============================================================================

var _owner_enemy: Node2D = null
var _status_effects: Node = null  # Reference to StatusEffectComponent

var _current_health_percent: float = 1.0
var _displayed_health_percent: float = 1.0
var _damage_trail_percent: float = 1.0
var _shield_percent: float = 0.0  # Stub: shield system not yet implemented

var _is_boss: bool = false
var _enemy_size: float = 24.0  # Detected enemy size for percentage calculations
var _bar_width: float = 32.0
var _bar_height: float = 6.0

var _dot_segments: Dictionary = {}  # effect_type -> ColorRect
var _dot_data: Dictionary = {}  # effect_type -> {damage_per_tick, tick_interval, remaining_duration}

var _hide_timer: float = 0.0
var _is_visible: bool = false
var _flash_timer: float = 0.0

#===============================================================================
# INITIALIZATION
#===============================================================================

func setup(enemy: Node2D, is_boss: bool = false) -> void:
	_owner_enemy = enemy
	_is_boss = is_boss

	# Detect enemy size from hurtbox for percentage-based scaling
	_detect_enemy_size()

	# Calculate bar dimensions based on enemy
	_calculate_bar_dimensions()

	# Build the UI structure
	_build_ui()

	# Connect to enemy signals
	if enemy.has_signal("health_changed"):
		enemy.health_changed.connect(_on_health_changed)
	if enemy.has_signal("damaged"):
		enemy.damaged.connect(_on_damaged)

	# Connect to status effects if available
	if "status_effects" in enemy and enemy.status_effects:
		_status_effects = enemy.status_effects
		_status_effects.effect_applied.connect(_on_effect_applied)
		_status_effects.effect_removed.connect(_on_effect_removed)
		_status_effects.effect_tick.connect(_on_effect_tick)

	# Initial visibility
	_update_visibility()

	Debug.log("UI", "Health bar setup for %s" % enemy.name, {"is_boss": is_boss, "width": _bar_width})


func _detect_enemy_size() -> void:
	## Detect enemy size from hurtbox for percentage-based calculations
	_enemy_size = 24.0  # Default fallback
	if _owner_enemy and "hurtbox" in _owner_enemy and _owner_enemy.hurtbox:
		for child in _owner_enemy.hurtbox.get_children():
			if child is CollisionShape2D and child.shape:
				if child.shape is CircleShape2D:
					_enemy_size = child.shape.radius * 2.0
				elif child.shape is RectangleShape2D:
					_enemy_size = maxf(child.shape.size.x, child.shape.size.y)
				break


func _calculate_bar_dimensions() -> void:
	# Get percentage-based dimensions from theme
	var height_percent := UITheme.ENEMY_HEALTH_BAR_HEIGHT_PERCENT if not _is_boss else UITheme.ENEMY_HEALTH_BAR_BOSS_HEIGHT_PERCENT
	var width_percent := UITheme.ENEMY_HEALTH_BAR_WIDTH_PERCENT

	# Calculate actual dimensions from percentages (relative to enemy size)
	_bar_height = maxf(_enemy_size * height_percent, float(UITheme.ENEMY_HEALTH_BAR_MIN_HEIGHT))
	_bar_width = maxf(_enemy_size * width_percent, float(UITheme.ENEMY_HEALTH_BAR_MIN_WIDTH))


func _build_ui() -> void:
	# Calculate Y offset from percentage (relative to enemy size)
	var y_offset := _enemy_size * UITheme.ENEMY_HEALTH_BAR_Y_OFFSET_PERCENT
	position = Vector2(-_bar_width / 2.0, y_offset - _bar_height)

	# Main container
	_bar_container = Control.new()
	_bar_container.name = "BarContainer"
	_bar_container.custom_minimum_size = Vector2(_bar_width, _bar_height)
	_bar_container.size = Vector2(_bar_width, _bar_height)
	add_child(_bar_container)

	# Corner radius as percentage of bar height
	var corner_radius := int(_bar_height * UITheme.ENEMY_HEALTH_BAR_CORNER_RADIUS_PERCENT)

	# Background
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = UITheme.COLOR_ENEMY_HEALTH_BG
	_background.size = Vector2(_bar_width, _bar_height)
	_bar_container.add_child(_background)

	# Damage trail (behind health fill)
	_damage_fill = ColorRect.new()
	_damage_fill.name = "DamageFill"
	_damage_fill.color = UITheme.COLOR_ENEMY_HEALTH_DAMAGE
	_damage_fill.size = Vector2(_bar_width, _bar_height)
	_bar_container.add_child(_damage_fill)

	# Health fill
	_health_fill = ColorRect.new()
	_health_fill.name = "HealthFill"
	_health_fill.color = UITheme.COLOR_ENEMY_HEALTH_FILL
	_health_fill.size = Vector2(_bar_width, _bar_height)
	_bar_container.add_child(_health_fill)

	# DoT preview container (on top of health fill)
	_dot_container = Control.new()
	_dot_container.name = "DoTContainer"
	_dot_container.size = Vector2(_bar_width, _bar_height)
	_bar_container.add_child(_dot_container)

	# Shield fill (on top of everything, semi-transparent)
	_shield_fill = ColorRect.new()
	_shield_fill.name = "ShieldFill"
	_shield_fill.color = UITheme.COLOR_ENEMY_SHIELD_FILL
	_shield_fill.size = Vector2(0, _bar_height)  # Hidden by default (no shield)
	_shield_fill.visible = false
	_bar_container.add_child(_shield_fill)

	# Border (visual only, using ReferenceRect for outline effect)
	# We'll draw the border manually in _draw or use a Panel with stylebox

	# Boss name label
	if _is_boss and UITheme.ENEMY_HEALTH_BAR_BOSS_SHOW_NAME:
		_name_label = Label.new()
		_name_label.name = "NameLabel"
		_name_label.text = _owner_enemy.enemy_name if "enemy_name" in _owner_enemy else "Boss"
		_name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		_name_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_VALUE)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.size.x = _bar_width
		_name_label.position.y = -UITheme.FONT_SIZE_SMALL - 2
		add_child(_name_label)

	# Start hidden
	visible = false


#===============================================================================
# PROCESS
#===============================================================================

func _process(delta: float) -> void:
	if not _owner_enemy or not is_instance_valid(_owner_enemy):
		queue_free()
		return

	# Update displayed health with lerp for smooth animation
	var lerp_speed := UITheme.ENEMY_HEALTH_BAR_LERP_SPEED
	_displayed_health_percent = lerpf(_displayed_health_percent, _current_health_percent, delta * lerp_speed)

	# Update damage trail (slower lerp for trailing effect)
	_damage_trail_percent = lerpf(_damage_trail_percent, _current_health_percent, delta * lerp_speed * 0.3)

	# Clamp to prevent overshooting
	if absf(_displayed_health_percent - _current_health_percent) < 0.001:
		_displayed_health_percent = _current_health_percent
	if absf(_damage_trail_percent - _current_health_percent) < 0.001:
		_damage_trail_percent = _current_health_percent

	# Update visual widths
	_health_fill.size.x = _bar_width * _displayed_health_percent
	_damage_fill.size.x = _bar_width * _damage_trail_percent

	# Update DoT preview segments
	_update_dot_preview()

	# Update flash effect
	if _flash_timer > 0:
		_flash_timer -= delta
		var flash_alpha := _flash_timer / 0.1
		_health_fill.modulate = Color(1.0 + flash_alpha * 0.5, 1.0 + flash_alpha * 0.5, 1.0 + flash_alpha * 0.5, 1.0)
		if _flash_timer <= 0:
			_health_fill.modulate = Color.WHITE

	# Handle auto-hide timer
	if _hide_timer > 0:
		_hide_timer -= delta
		if _hide_timer <= 0 and _should_hide():
			_set_visible(false)


#===============================================================================
# HEALTH UPDATE
#===============================================================================

func _on_health_changed(current: float, maximum: float) -> void:
	_current_health_percent = clampf(current / maximum, 0.0, 1.0) if maximum > 0 else 0.0
	_update_visibility()


func _on_damaged(_amount: float, _attacker: Node2D) -> void:
	# Flash effect on damage
	_flash_timer = 0.1

	# Reset hide timer
	_hide_timer = UITheme.ENEMY_HEALTH_BAR_FADE_DELAY

	# Show bar if hidden
	if not _is_visible:
		_set_visible(true)


#===============================================================================
# DOT PREVIEW
#===============================================================================

func _on_effect_applied(effect_type: String, duration: float, _show_in_hud: bool, is_debuff: bool) -> void:
	if not is_debuff:
		return  # Only track debuffs (DoT effects)

	# Get effect data from status effects component
	if _status_effects and _status_effects.has_effect(effect_type):
		var effect_data: Dictionary = _status_effects.get_all_effect_data().get(effect_type, {})
		var damage_per_tick: float = effect_data.get("damage_per_tick", 0.0)
		var tick_interval: float = effect_data.get("tick_interval", 1.0)

		if damage_per_tick > 0:
			_dot_data[effect_type] = {
				"damage_per_tick": damage_per_tick,
				"tick_interval": tick_interval,
				"remaining_duration": duration
			}
			_create_dot_segment(effect_type)

	_update_visibility()


func _on_effect_removed(effect_type: String) -> void:
	if effect_type in _dot_data:
		_dot_data.erase(effect_type)

	if effect_type in _dot_segments:
		_dot_segments[effect_type].queue_free()
		_dot_segments.erase(effect_type)

	_update_visibility()


func _on_effect_tick(effect_type: String, _damage: float) -> void:
	# Update remaining duration from status effects
	if _status_effects and _status_effects.has_effect(effect_type):
		var remaining := _status_effects.get_remaining_duration(effect_type)
		if effect_type in _dot_data:
			_dot_data[effect_type].remaining_duration = remaining


func _create_dot_segment(effect_type: String) -> void:
	if effect_type in _dot_segments:
		return  # Already exists

	var segment := ColorRect.new()
	segment.name = "DoT_" + effect_type
	segment.color = _get_dot_color(effect_type)
	segment.size = Vector2(0, _bar_height)
	_dot_container.add_child(segment)
	_dot_segments[effect_type] = segment


func _get_dot_color(effect_type: String) -> Color:
	var type_lower := effect_type.to_lower().replace("status_", "")

	match type_lower:
		"burning", "burn", "fire":
			return UITheme.COLOR_ENEMY_DOT_FIRE
		"poison", "poisoned", "rot":
			return UITheme.COLOR_ENEMY_DOT_POISON
		"bleed", "bleeding":
			return UITheme.COLOR_ENEMY_DOT_BLEED
		"freeze", "frozen", "cold", "chill":
			return UITheme.COLOR_ENEMY_DOT_COLD
		_:
			return UITheme.COLOR_ENEMY_DOT_GENERIC


func _update_dot_preview() -> void:
	if _dot_data.is_empty():
		return

	# Get current and max health from owner
	var current_health := 0.0
	var max_health := 1.0
	if _owner_enemy:
		current_health = _owner_enemy.current_health if "current_health" in _owner_enemy else 0.0
		max_health = _owner_enemy.max_health if "max_health" in _owner_enemy else 1.0

	if max_health <= 0:
		return

	# Calculate total DoT damage and position segments
	var cumulative_damage := 0.0
	var health_bar_start := _bar_width * _displayed_health_percent

	for effect_type in _dot_data:
		var data: Dictionary = _dot_data[effect_type]
		var damage_per_tick: float = data.damage_per_tick
		var tick_interval: float = data.tick_interval
		var remaining_duration: float = data.remaining_duration

		# Calculate remaining ticks and total damage
		var remaining_ticks := floorf(remaining_duration / tick_interval) if tick_interval > 0 else 0.0
		var total_damage := damage_per_tick * remaining_ticks

		# Convert to health percentage
		var damage_percent := total_damage / max_health

		# Position segment
		if effect_type in _dot_segments:
			var segment: ColorRect = _dot_segments[effect_type]
			var segment_width := _bar_width * damage_percent

			# Only show if meaningful width
			if segment_width >= DOT_SEGMENT_MIN_WIDTH:
				var segment_start := health_bar_start - cumulative_damage * _bar_width / max_health - segment_width
				segment_start = maxf(segment_start, 0.0)
				segment.position.x = segment_start
				segment.size.x = minf(segment_width, health_bar_start - segment_start)
				segment.visible = true
			else:
				segment.visible = false

			cumulative_damage += total_damage


#===============================================================================
# SHIELD (STUB)
#===============================================================================

## Update shield display (for future shield system implementation)
func set_shield_percent(percent: float) -> void:
	_shield_percent = clampf(percent, 0.0, 1.0)
	_shield_fill.visible = _shield_percent > 0.0
	_shield_fill.size.x = _bar_width * _shield_percent
	_update_visibility()


#===============================================================================
# VISIBILITY
#===============================================================================

func _update_visibility() -> void:
	var should_show := not _should_hide()

	if should_show and not _is_visible:
		_set_visible(true)
	elif not should_show and _is_visible:
		# Start hide timer instead of immediately hiding
		if _hide_timer <= 0:
			_hide_timer = UITheme.ENEMY_HEALTH_BAR_FADE_DELAY


func _should_hide() -> bool:
	# Never hide boss health bars
	if _is_boss:
		return false

	# Don't hide if has DoTs active
	if not _dot_data.is_empty():
		return false

	# Don't hide if has shield
	if _shield_percent > 0:
		return false

	# Check full health setting
	if not UITheme.ENEMY_HEALTH_BAR_SHOW_ON_FULL and _current_health_percent >= 1.0:
		return true

	# Check if dead
	if _current_health_percent <= 0:
		return true

	return false


func _set_visible(is_visible: bool) -> void:
	if _is_visible == is_visible:
		return

	_is_visible = is_visible
	visible = is_visible
	visibility_changed.emit(is_visible)


#===============================================================================
# CLEANUP
#===============================================================================

func _exit_tree() -> void:
	# Disconnect signals
	if _owner_enemy and is_instance_valid(_owner_enemy):
		if _owner_enemy.has_signal("health_changed") and _owner_enemy.health_changed.is_connected(_on_health_changed):
			_owner_enemy.health_changed.disconnect(_on_health_changed)
		if _owner_enemy.has_signal("damaged") and _owner_enemy.damaged.is_connected(_on_damaged):
			_owner_enemy.damaged.disconnect(_on_damaged)

	if _status_effects and is_instance_valid(_status_effects):
		if _status_effects.effect_applied.is_connected(_on_effect_applied):
			_status_effects.effect_applied.disconnect(_on_effect_applied)
		if _status_effects.effect_removed.is_connected(_on_effect_removed):
			_status_effects.effect_removed.disconnect(_on_effect_removed)
		if _status_effects.effect_tick.is_connected(_on_effect_tick):
			_status_effects.effect_tick.disconnect(_on_effect_tick)
