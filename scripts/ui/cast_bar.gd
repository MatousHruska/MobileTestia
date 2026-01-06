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

## Dimensions (cached from UITheme)
var _bar_width: float = 200.0
var _bar_height: float = 16.0

## Animation
const LERP_SPEED := 15.0  ## How fast the bar fills
const FADE_DURATION := 0.3  ## How long to fade out when interrupted


func _ready() -> void:
	# Cache dimensions
	_bar_width = UITheme.CAST_BAR_WIDTH
	_bar_height = UITheme.CAST_BAR_HEIGHT

	# Set explicit size (don't rely on anchors for this)
	size = Vector2(_bar_width, _bar_height)
	custom_minimum_size = size

	_create_components()
	_apply_theme()
	_connect_to_player()
	visible = false


func _create_components() -> void:
	## Build the cast bar UI structure

	# Background - explicit size, not anchor-based
	_background = ColorRect.new()
	_background.name = "Background"
	_background.size = Vector2(_bar_width, _bar_height)
	_background.position = Vector2.ZERO
	add_child(_background)

	# Fill bar (progress) - explicit positioning
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.position = Vector2(2, 2)  # Padding inside border
	_fill.size = Vector2(0, _bar_height - 4)  # Start with 0 width
	add_child(_fill)

	# Border
	_border = ReferenceRect.new()
	_border.name = "Border"
	_border.size = Vector2(_bar_width, _bar_height)
	_border.position = Vector2.ZERO
	_border.border_width = 2.0
	_border.editor_only = false  # Make visible at runtime
	add_child(_border)

	# Skill name label
	_label = Label.new()
	_label.name = "SkillLabel"
	_label.size = Vector2(_bar_width, _bar_height)
	_label.position = Vector2.ZERO
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
	Debug.log("UI", "CastBar: cast_started received", {"skill": skill_id})

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
	var fill_width := (_bar_width - 4) * progress  # Account for 2px padding on each side
	_fill.size.x = fill_width
