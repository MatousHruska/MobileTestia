extends Control
class_name StatusEffectIcon
## StatusEffectIcon - Individual status effect icon with timer display
##
## Shows an icon with remaining duration, used for both DoTs and buffs

## Effect data
var effect_type: String = ""
var is_debuff: bool = true
var duration: float = 0.0
var max_duration: float = 0.0
var is_permanent: bool = false

## Visual components
var _background: ColorRect
var _icon: ColorRect
var _timer_label: Label
var _duration_bar: ProgressBar

## Icon size
const ICON_SIZE := Vector2(32, 32)


func _ready() -> void:
	custom_minimum_size = ICON_SIZE
	_setup_visuals()


func _process(delta: float) -> void:
	# Permanent effects don't count down
	if is_permanent:
		return

	if duration > 0:
		duration -= delta
		_update_timer_display()

		if duration <= 0:
			queue_free()


func _setup_visuals() -> void:
	# Background (border color indicates buff/debuff)
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.6, 0.1, 0.1, 0.9) if is_debuff else Color(0.2, 0.7, 0.2, 0.9)
	add_child(_background)

	# Icon placeholder (inner colored square)
	_icon = ColorRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 2
	_icon.offset_top = 2
	_icon.offset_right = -2
	_icon.offset_bottom = -8  # Leave room for timer
	_icon.color = _get_effect_color()
	add_child(_icon)

	# Duration bar at bottom
	_duration_bar = ProgressBar.new()
	_duration_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_duration_bar.offset_top = -6
	_duration_bar.offset_left = 2
	_duration_bar.offset_right = -2
	_duration_bar.custom_minimum_size.y = 4
	_duration_bar.show_percentage = false

	if is_permanent:
		# Permanent effects show full bar
		_duration_bar.max_value = 1.0
		_duration_bar.value = 1.0
	else:
		_duration_bar.max_value = max_duration
		_duration_bar.value = duration

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(1.0, 1.0, 1.0, 0.8)
	bar_style.corner_radius_bottom_left = 1
	bar_style.corner_radius_bottom_right = 1
	_duration_bar.add_theme_stylebox_override("fill", bar_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar_bg.corner_radius_bottom_left = 1
	bar_bg.corner_radius_bottom_right = 1
	_duration_bar.add_theme_stylebox_override("background", bar_bg)

	add_child(_duration_bar)

	# Timer label (centered on icon)
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_timer_label.add_theme_color_override("font_color", UITheme.COLOR_SELECTED)
	_timer_label.add_theme_color_override("font_shadow_color", UITheme.COLOR_PANEL_DARK_BG)
	_timer_label.add_theme_constant_override("shadow_offset_x", 1)
	_timer_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_timer_label)

	_update_timer_display()


func _update_timer_display() -> void:
	if _timer_label:
		if is_permanent:
			_timer_label.text = "∞"
		elif duration >= 10:
			_timer_label.text = "%d" % int(duration)
		else:
			_timer_label.text = "%.1f" % duration

	if _duration_bar and not is_permanent:
		_duration_bar.value = duration


func _get_effect_color() -> Color:
	# First check database for icon_color
	var status_id := "status_" + effect_type
	var status_data: Dictionary = DatabaseLoader.status_effects.get(status_id, {})
	var icon_color_str: String = status_data.get("icon_color", "")

	# If database has a color defined, use it (supports hex like #FF5500)
	if not icon_color_str.is_empty():
		if icon_color_str.begins_with("#"):
			return Color.html(icon_color_str)
		else:
			# Try parsing as Color name or direct value
			return Color(icon_color_str)

	# Fallback to hardcoded defaults if not in database
	match effect_type:
		# Debuffs
		"rot":
			return Color(0.4, 0.25, 0.1)  # Brown/rot color
		"poison":
			return Color(0.2, 0.5, 0.1)  # Green
		"burn", "burning":
			return Color(0.9, 0.4, 0.1)  # Orange
		"bleed":
			return Color(0.7, 0.1, 0.1)  # Dark red
		"slow":
			return Color(0.3, 0.3, 0.7)  # Blue-ish
		"stun":
			return Color(0.8, 0.8, 0.2)  # Yellow
		# Buffs
		"bandage":
			return Color(0.9, 0.9, 0.8)  # Cream/white bandage
		"regen", "heal":
			return Color(0.3, 0.8, 0.3)  # Bright green
		_:
			# Default: greenish for buffs, gray for debuffs
			return Color(0.4, 0.7, 0.4) if not is_debuff else Color(0.5, 0.5, 0.5)


func setup(p_effect_type: String, p_duration: float, p_is_debuff: bool = true) -> void:
	effect_type = p_effect_type
	is_debuff = p_is_debuff

	# Negative duration or zero means permanent effect
	if p_duration < 0:
		is_permanent = true
		duration = 0.0
		max_duration = 0.0
	else:
		is_permanent = false
		duration = p_duration
		max_duration = p_duration

	if is_inside_tree():
		_setup_visuals()


func refresh_duration(new_duration: float) -> void:
	# Handle permanent effect refresh
	if new_duration < 0:
		is_permanent = true
		return

	duration = new_duration
	if new_duration > max_duration:
		max_duration = new_duration
		if _duration_bar:
			_duration_bar.max_value = max_duration
