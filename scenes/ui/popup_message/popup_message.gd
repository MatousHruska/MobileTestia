extends Control
class_name PopupMessage
## PopupMessage - Screen announcement popup UI
## Displays at top-center of screen with title, subtitle, and optional icon

signal finished

## Components
@onready var background: Panel = $Background
@onready var title_label: Label = $Background/VBox/Title
@onready var subtitle_label: Label = $Background/VBox/Subtitle
@onready var icon_sprite: TextureRect = $Background/Icon

## State
var _duration: float = 3.0
var _elapsed: float = 0.0
var _is_active: bool = false
var _is_hiding: bool = false

## Icon textures (will be loaded on demand)
var _icon_textures: Dictionary = {}


func _ready() -> void:
	# Start hidden
	modulate.a = 0.0
	visible = false

	# Center the control
	pivot_offset = size / 2


func _process(delta: float) -> void:
	if not _is_active or _is_hiding:
		return

	# Update timer
	_elapsed += delta
	if _elapsed >= _duration:
		hide_popup()


## Show the popup with content
func show_popup(title: String, subtitle: String = "", icon: String = "none", duration: float = 3.0) -> void:
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

	# Set icon
	if icon_sprite:
		_set_icon(icon)

	# Resize background to fit content
	await get_tree().process_frame
	_update_layout()

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


func _set_icon(icon_type: String) -> void:
	if icon_sprite == null:
		return

	# Hide if no icon
	if icon_type == "none" or icon_type.is_empty():
		icon_sprite.visible = false
		return

	# TODO: Load actual icon textures when art is available
	# For now, just show/hide based on type
	icon_sprite.visible = true

	# Set placeholder color based on icon type
	match icon_type:
		"location":
			icon_sprite.modulate = Color(0.4, 0.8, 0.4)  # Green
		"quest":
			icon_sprite.modulate = Color(1.0, 0.8, 0.2)  # Gold
		"warning":
			icon_sprite.modulate = Color(1.0, 0.3, 0.3)  # Red
		"info":
			icon_sprite.modulate = Color(0.4, 0.6, 1.0)  # Blue
		"combat":
			icon_sprite.modulate = Color(0.8, 0.2, 0.2)  # Dark red
		"discovery":
			icon_sprite.modulate = Color(0.8, 0.6, 1.0)  # Purple
		_:
			icon_sprite.modulate = Color.WHITE


func _update_layout() -> void:
	# Resize to fit content
	if background:
		var min_width := 200.0
		var max_width := 500.0

		# Calculate width based on text
		var title_width := title_label.size.x if title_label else 0.0
		var subtitle_width := subtitle_label.size.x if subtitle_label else 0.0
		var content_width := maxf(title_width, subtitle_width) + 60  # padding + icon space

		background.custom_minimum_size.x = clampf(content_width, min_width, max_width)

	# Center the control horizontally
	position.x = -size.x / 2


func _animate_in() -> void:
	# Fade in and slide down
	var tween := create_tween()
	tween.set_parallel(true)

	# Start slightly above and fade in
	position.y = -20
	tween.tween_property(self, "position:y", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

	# Slight scale pop
	scale = Vector2(0.9, 0.9)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _animate_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade out and slide up
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "position:y", position.y - 30, 0.3).set_ease(Tween.EASE_IN)

	await tween.finished

	finished.emit()
	queue_free()


## Immediately cancel and clean up
func cancel() -> void:
	_is_active = false
	_is_hiding = true
	finished.emit()
	queue_free()
