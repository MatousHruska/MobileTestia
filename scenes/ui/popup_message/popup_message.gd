extends Control
## PopupMessageUI - Screen announcement popup UI
## Displays at top-center of screen with title, subtitle, and optional icon

signal finished

## Components
@onready var background: Panel = $Background
@onready var title_label: Label = $Background/MarginContainer/VBox/Title
@onready var subtitle_label: Label = $Background/MarginContainer/VBox/Subtitle

## State
var _duration: float = 3.0
var _elapsed: float = 0.0
var _is_active: bool = false
var _is_hiding: bool = false
var _start_offset_top: float = 0.0


func _ready() -> void:
	# Store initial offset for animations
	_start_offset_top = offset_top

	# Start hidden
	modulate.a = 0.0
	visible = false

	# Set pivot for scale animation
	pivot_offset = size / 2

	# Apply UITheme styling
	if title_label:
		title_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LARGE)
		title_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	if subtitle_label:
		subtitle_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
		subtitle_label.add_theme_color_override("font_color", UITheme.COLOR_SECTION_HEADER)


func _process(delta: float) -> void:
	if not _is_active or _is_hiding:
		return

	# Update timer
	_elapsed += delta
	if _elapsed >= _duration:
		hide_popup()


## Show the popup with content
func show_popup(title: String, subtitle: String = "", _icon: String = "none", duration: float = 3.0) -> void:
	_duration = duration
	_elapsed = 0.0
	_is_active = true
	_is_hiding = false

	# Set title
	if title_label:
		title_label.text = title
		title_label.visible = not title.is_empty()

	# Set subtitle
	if subtitle_label:
		subtitle_label.text = subtitle
		subtitle_label.visible = not subtitle.is_empty()

	# Show with animation
	visible = true
	_animate_in()


## Hide the popup with animation
func hide_popup() -> void:
	if _is_hiding:
		return

	_is_hiding = true
	_is_active = false
	_animate_out()


func _animate_in() -> void:
	# Fade in and slide down
	var tween := create_tween()
	tween.set_parallel(true)

	# Start slightly above and fade in
	offset_top = _start_offset_top - 30
	tween.tween_property(self, "offset_top", _start_offset_top, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)

	# Slight scale pop
	scale = Vector2(0.85, 0.85)
	tween.tween_property(self, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _animate_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade out and slide up
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "offset_top", offset_top - 40, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.3)

	await tween.finished

	finished.emit()
	queue_free()


## Immediately cancel and clean up
func cancel() -> void:
	_is_active = false
	_is_hiding = true
	finished.emit()
	queue_free()
