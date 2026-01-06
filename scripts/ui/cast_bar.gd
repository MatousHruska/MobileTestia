extends Control
class_name CastBar
## CastBar - Visual indicator for skill casting progress
##
## Displays a horizontal progress bar when the player is casting a skill.
## Connects to PlayerController's cast signals and uses UITheme for styling.

## Components
var _background: ColorRect
var _fill: ColorRect
var _border: ReferenceRect
var _label: Label

## State
var _is_visible: bool = false
var _current_skill: String = ""
var _target_progress: float = 0.0
var _current_progress: float = 0.0

## Animation
const LERP_SPEED := 15.0  ## How fast the bar fills
const FADE_DURATION := 0.3  ## How long to fade out when interrupted


func _ready() -> void:
	_create_components()
	_apply_theme()
	_connect_to_player()
	visible = false


func _create_components() -> void:
	## Build the cast bar UI structure

	# Main container - centers the bar horizontally at top of screen
	custom_minimum_size = Vector2(UITheme.CAST_BAR_WIDTH, UITheme.CAST_BAR_HEIGHT)

	# Background
	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	# Fill bar (progress)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.anchor_left = 0.0
	_fill.anchor_top = 0.0
	_fill.anchor_right = 0.0  # We'll control width manually
	_fill.anchor_bottom = 1.0
	_fill.offset_left = 2  # Padding inside border
	_fill.offset_top = 2
	_fill.offset_right = 0
	_fill.offset_bottom = -2
	add_child(_fill)

	# Border
	_border = ReferenceRect.new()
	_border.name = "Border"
	_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border.border_width = 2.0
	_border.editor_only = false  # Make visible at runtime
	add_child(_border)

	# Skill name label
	_label = Label.new()
	_label.name = "SkillLabel"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _apply_theme() -> void:
	## Apply UITheme colors to components
	_background.color = UITheme.COLOR_CAST_BAR_BG
	_fill.color = UITheme.COLOR_CAST_BAR_FILL
	_border.border_color = UITheme.COLOR_CAST_BAR_BORDER
	_label.add_theme_color_override("font_color", UITheme.COLOR_CAST_BAR_TEXT)
	_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)


func _connect_to_player() -> void:
	## Connect to player cast signals
	if Game and Game.is_player_valid():
		_on_player_ready()
	elif Game:
		Game.player_spawned.connect(_on_player_spawned)


func _on_player_spawned(_player: Node2D) -> void:
	await get_tree().process_frame
	_on_player_ready()


func _on_player_ready() -> void:
	var player := Game.player as PlayerController
	if not player:
		return

	# Connect to cast signals
	if not player.cast_started.is_connected(_on_cast_started):
		player.cast_started.connect(_on_cast_started)
		player.cast_progress.connect(_on_cast_progress)
		player.cast_completed.connect(_on_cast_completed)
		player.cast_interrupted.connect(_on_cast_interrupted)
		Debug.log("UI", "CastBar connected to PlayerController")


func _on_cast_started(skill_id: String, _duration: float) -> void:
	## Show the cast bar when casting begins
	_current_skill = skill_id
	_current_progress = 0.0
	_target_progress = 0.0

	# Get skill name from TalentManager
	var talent := TalentManager.get_talent(skill_id)
	var skill_name := talent.talent_name if talent else skill_id
	_label.text = skill_name

	# Reset fill bar
	_update_fill_visual(0.0)
	_fill.color = UITheme.COLOR_CAST_BAR_FILL

	# Show cast bar
	visible = true
	_is_visible = true
	modulate.a = 1.0


func _on_cast_progress(progress: float) -> void:
	## Update the target progress (smoothed in _process)
	_target_progress = progress


func _on_cast_completed(_skill_id: String) -> void:
	## Hide the cast bar on successful completion
	_target_progress = 1.0
	_current_progress = 1.0
	_update_fill_visual(1.0)

	# Quick fade out
	_fade_out()


func _on_cast_interrupted(_skill_id: String, reason: String) -> void:
	## Show interrupted state then fade out
	_fill.color = UITheme.COLOR_CAST_BAR_INTERRUPTED
	_label.text = reason.capitalize() if reason else "Interrupted"

	# Fade out
	_fade_out()


func _fade_out() -> void:
	## Animate fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(_hide_complete)


func _hide_complete() -> void:
	## Called when fade out completes
	visible = false
	_is_visible = false
	_current_skill = ""


func _process(delta: float) -> void:
	## Smooth the progress bar fill
	if not _is_visible:
		return

	if _current_progress < _target_progress:
		_current_progress = lerpf(_current_progress, _target_progress, delta * LERP_SPEED)
		_current_progress = minf(_current_progress, _target_progress)  # Don't overshoot
		_update_fill_visual(_current_progress)


func _update_fill_visual(progress: float) -> void:
	## Update the fill bar width based on progress
	var bar_width := size.x - 4  # Account for padding
	_fill.offset_right = 2 + (bar_width * progress)
