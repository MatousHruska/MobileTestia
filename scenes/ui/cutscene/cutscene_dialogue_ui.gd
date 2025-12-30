extends CanvasLayer
class_name CutsceneDialogueUI
## CutsceneDialogueUI - Simplified dialogue box for cutscenes
## Portrait (left) + Speaker Name + Dialogue Text
## Tap anywhere to advance/skip typewriter

## Signals
signal advance_requested

## UI References
var _panel: PanelContainer
var _portrait_placeholder: ColorRect
var _portrait_rect: TextureRect
var _speaker_label: Label
var _dialogue_label: RichTextLabel
var _background_dimmer: ColorRect
var _fade_rect: ColorRect
var _advance_hint: Label

## Typewriter effect
var _typewriter_text: String = ""
var _typewriter_index: int = 0
var _typewriter_timer: float = 0.0
@export var typewriter_speed: float = 0.025  ## Seconds per character

## State
var _is_typing: bool = false


func _ready() -> void:
	_build_ui()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	hide()


func _process(delta: float) -> void:
	if _is_typing:
		_typewriter_timer += delta
		while _typewriter_timer >= typewriter_speed and _typewriter_index < _typewriter_text.length():
			_typewriter_timer -= typewriter_speed
			_typewriter_index += 1
			_dialogue_label.text = _typewriter_text.substr(0, _typewriter_index)

		if _typewriter_index >= _typewriter_text.length():
			_is_typing = false
			set_process(false)
			_advance_hint.show()


## Handle clicks/taps on the background dimmer
func _on_background_input(event: InputEvent) -> void:
	# Handle tap/click to advance
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_advance_tap()

	# Handle touch
	if event is InputEventScreenTouch and event.pressed:
		_handle_advance_tap()


func _handle_advance_tap() -> void:
	if _is_typing:
		_complete_typewriter()
	else:
		advance_requested.emit()


#===============================================================================
# PUBLIC API
#===============================================================================

## Show dialogue with speaker and text
func show_dialogue(speaker: String, text: String, portrait_id: String = "") -> void:
	_speaker_label.text = speaker
	_advance_hint.hide()

	# Set portrait
	if portrait_id.is_empty():
		_portrait_placeholder.show()
		_portrait_rect.hide()
	else:
		# TODO: Load actual portrait texture
		_portrait_placeholder.show()
		_portrait_rect.hide()

	# Start typewriter
	_typewriter_text = text
	_typewriter_index = 0
	_typewriter_timer = 0.0
	_dialogue_label.text = ""
	_is_typing = true
	set_process(true)

	# Show the panel
	_panel.show()


## Reset to initial state
func reset() -> void:
	_speaker_label.text = ""
	_dialogue_label.text = ""
	_is_typing = false
	set_process(false)
	_advance_hint.hide()
	_fade_rect.color.a = 0.0


## Fade screen in (from black)
func fade_in(duration: float) -> void:
	_fade_rect.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, duration)
	await tween.finished


## Fade screen out (to black)
func fade_out(duration: float) -> void:
	_fade_rect.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, duration)
	await tween.finished


## Hide the dialogue panel (but keep layer visible for fades)
func hide_dialogue() -> void:
	_panel.hide()


#===============================================================================
# UI BUILDING
#===============================================================================

func _build_ui() -> void:
	layer = 100

	# Screen fade rect (for fade in/out effects)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_rect)

	# Semi-transparent background (but not as dark as HubUI)
	_background_dimmer = ColorRect.new()
	_background_dimmer.name = "BackgroundDimmer"
	_background_dimmer.color = Color(0, 0, 0, 0.3)
	_background_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_background_dimmer.gui_input.connect(_on_background_input)
	add_child(_background_dimmer)

	# Main panel at bottom
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.set_anchor_and_offset(SIDE_LEFT, 0.05, 0)
	_panel.set_anchor_and_offset(SIDE_RIGHT, 0.95, 0)
	_panel.set_anchor_and_offset(SIDE_TOP, 0.7, 0)
	_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.95, 0)
	add_child(_panel)

	# Main HBox: Portrait | Dialogue
	var hbox := HBoxContainer.new()
	hbox.name = "MainLayout"
	hbox.add_theme_constant_override("separation", 16)
	_panel.add_child(hbox)

	# LEFT: Portrait section
	var portrait_container := _build_portrait_section()
	hbox.add_child(portrait_container)

	# RIGHT: Speaker + Dialogue section
	var dialogue_container := _build_dialogue_section()
	dialogue_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(dialogue_container)


func _build_portrait_section() -> Control:
	var container := PanelContainer.new()
	container.name = "PortraitSection"
	container.custom_minimum_size = Vector2(100, 100)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	container.add_child(margin)

	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(stack)

	# Placeholder
	_portrait_placeholder = ColorRect.new()
	_portrait_placeholder.name = "PortraitPlaceholder"
	_portrait_placeholder.color = Color(0.3, 0.3, 0.5)
	_portrait_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_portrait_placeholder)

	# Portrait texture
	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "PortraitTexture"
	_portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_rect.hide()
	stack.add_child(_portrait_rect)

	return container


func _build_dialogue_section() -> Control:
	var container := VBoxContainer.new()
	container.name = "DialogueSection"
	container.add_theme_constant_override("separation", 8)

	# Speaker name
	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerName"
	_speaker_label.add_theme_font_size_override("font_size", 20)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	container.add_child(_speaker_label)

	# Dialogue text panel
	var text_panel := PanelContainer.new()
	text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var text_margin := MarginContainer.new()
	text_margin.add_theme_constant_override("margin_left", 12)
	text_margin.add_theme_constant_override("margin_right", 12)
	text_margin.add_theme_constant_override("margin_top", 8)
	text_margin.add_theme_constant_override("margin_bottom", 8)
	text_panel.add_child(text_margin)

	_dialogue_label = RichTextLabel.new()
	_dialogue_label.name = "DialogueText"
	_dialogue_label.bbcode_enabled = true
	_dialogue_label.fit_content = false
	_dialogue_label.scroll_active = false
	_dialogue_label.add_theme_font_size_override("normal_font_size", 18)
	text_margin.add_child(_dialogue_label)

	container.add_child(text_panel)

	# Advance hint (tap to continue)
	_advance_hint = Label.new()
	_advance_hint.name = "AdvanceHint"
	_advance_hint.text = "Tap to continue..."
	_advance_hint.add_theme_font_size_override("font_size", 12)
	_advance_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_advance_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advance_hint.hide()
	container.add_child(_advance_hint)

	return container


#===============================================================================
# HELPERS
#===============================================================================

func _complete_typewriter() -> void:
	if _is_typing:
		_dialogue_label.text = _typewriter_text
		_typewriter_index = _typewriter_text.length()
		_is_typing = false
		set_process(false)
		_advance_hint.show()
