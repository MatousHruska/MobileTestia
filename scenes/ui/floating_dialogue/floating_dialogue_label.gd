extends Node2D
class_name FloatingDialogueLabel
## FloatingDialogueLabel - A floating text bubble that appears above characters
## Used for character barks/quips/contextual dialogue

signal finished

## Components
@onready var label: Label = $Label
@onready var background: Panel = $Background
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## State
var _target: Node2D = null
var _offset := Vector2(0, -50)
var _duration: float = 3.0
var _elapsed: float = 0.0
var _is_active: bool = false


func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	visible = false

	# Apply UITheme styling - dialogue text is Level 4 value
	if label:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_VALUE)


func _process(delta: float) -> void:
	if not _is_active:
		return

	# Follow target
	if _target and is_instance_valid(_target):
		global_position = _target.global_position + _offset

	# Update timer
	_elapsed += delta
	if _elapsed >= _duration:
		_hide_and_finish()


## Show text above target for duration
func show_text(text: String, duration: float = 3.0, target: Node2D = null) -> void:
	_target = target
	_duration = duration
	_elapsed = 0.0
	_is_active = true

	# Set text
	label.text = text

	# Size background to fit text
	await get_tree().process_frame
	_update_background_size()

	# Position if target provided
	if _target and is_instance_valid(_target):
		global_position = _target.global_position + _offset

	# Show with animation
	visible = true
	_animate_in()


func _update_background_size() -> void:
	# Add padding around text
	var text_size := label.size
	var padding := Vector2(16, 8)
	background.size = text_size + padding * 2
	background.position = -background.size / 2

	# Center label in background
	label.position = -text_size / 2


func _animate_in() -> void:
	# Fade in and float up slightly
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade in
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

	# Float up slightly
	var start_offset := _offset + Vector2(0, 10)
	_offset = Vector2(0, -50)
	tween.tween_property(self, "_offset", Vector2(0, -60), 0.3).set_ease(Tween.EASE_OUT)


func _hide_and_finish() -> void:
	_is_active = false

	# Fade out and float up
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.3)

	# Float up
	tween.tween_property(self, "_offset", _offset + Vector2(0, -20), 0.3)

	await tween.finished

	finished.emit()
	queue_free()


## Immediately hide and clean up
func cancel() -> void:
	_is_active = false
	finished.emit()
	queue_free()
