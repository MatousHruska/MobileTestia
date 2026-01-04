extends CanvasLayer
class_name HubUI
## HubUI - NPC Interaction Menu (Hub Style)
## Three-panel layout: Portrait (left), Dialogue (center), Buttons (right)

## Signals
signal closed
signal talk_pressed
signal quest_pressed
signal trade_pressed

## References to UI elements (set in _ready)
var panel: PanelContainer
var portrait_rect: TextureRect
var portrait_placeholder: ColorRect
var dialogue_label: RichTextLabel
var buttons_container: VBoxContainer
var talk_button: Button
var quest_button: Button
var trade_button: Button
var exit_button: Button
var background_dimmer: ColorRect

## Current NPC data
var current_npc_id: String = ""
var current_npc_data: Dictionary = {}

## Typewriter effect
var _typewriter_text: String = ""
var _typewriter_index: int = 0
var _typewriter_timer: float = 0.0
@export var typewriter_speed: float = 0.03  ## Seconds per character

## State
var is_open: bool = false
var _is_typing: bool = false

## Quest offer state
var _pending_quest_id: String = ""
var _quest_accept_button: Button
var _quest_decline_button: Button


func _ready() -> void:
	_build_ui()
	_connect_signals()
	hide()

	# Process for typewriter effect
	set_process(false)


func _process(delta: float) -> void:
	if _is_typing:
		_typewriter_timer += delta
		while _typewriter_timer >= typewriter_speed and _typewriter_index < _typewriter_text.length():
			_typewriter_timer -= typewriter_speed
			_typewriter_index += 1
			dialogue_label.text = _typewriter_text.substr(0, _typewriter_index)

		if _typewriter_index >= _typewriter_text.length():
			_is_typing = false
			set_process(false)


func _input(event: InputEvent) -> void:
	if not is_open:
		return

	# Skip typewriter on any input
	if _is_typing and event is InputEventMouseButton and event.pressed:
		_complete_typewriter()
		get_viewport().set_input_as_handled()
		return

	# Close on Escape
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


#===============================================================================
# PUBLIC API
#===============================================================================

## Open the Hub UI for an NPC
func open(npc_id: String) -> void:
	current_npc_id = npc_id
	current_npc_data = DatabaseLoader.get_npc(npc_id)

	if current_npc_data.is_empty():
		Debug.warn("HubUI", "NPC not found in database: %s" % npc_id)
		return

	_setup_for_npc()

	show()
	is_open = true

	# Pause game
	get_tree().paused = true

	Debug.info("HubUI", "Opened for NPC: %s" % current_npc_data.get("name", npc_id))


## Close the Hub UI
func close() -> void:
	hide()
	is_open = false
	_is_typing = false
	set_process(false)

	# Unpause game
	get_tree().paused = false

	# Notify the NPC that interaction has ended
	if not current_npc_id.is_empty():
		var npc := NPCManager.get_friendly_by_id(current_npc_id)
		if npc and npc.has_method("end_interaction"):
			npc.end_interaction()

	closed.emit()
	Debug.info("HubUI", "Closed")


## Display text with typewriter effect
func show_dialogue(text: String) -> void:
	_typewriter_text = text
	_typewriter_index = 0
	_typewriter_timer = 0.0
	dialogue_label.text = ""
	_is_typing = true
	set_process(true)


## Display text immediately (no typewriter)
func show_dialogue_instant(text: String) -> void:
	dialogue_label.text = text
	_is_typing = false
	set_process(false)


#===============================================================================
# SETUP
#===============================================================================

func _setup_for_npc() -> void:
	# Set portrait (placeholder for now)
	var portrait_id: String = current_npc_data.get("portrait_id", "")
	if portrait_id.is_empty():
		# Show green placeholder
		portrait_placeholder.show()
		portrait_rect.hide()
	else:
		# TODO: Load portrait texture
		portrait_placeholder.show()
		portrait_rect.hide()

	# Show greeting dialogue
	var greeting: String = current_npc_data.get("dialogue_greeting", "...")
	show_dialogue(greeting)

	# Configure buttons based on NPC data
	_setup_buttons()


func _setup_buttons() -> void:
	# Talk button - always visible
	talk_button.show()

	# Quest button - show if NPC has quests
	var has_quest := _npc_has_quest()
	quest_button.visible = has_quest

	# Update quest button text based on state
	if has_quest and has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		if qm.has_quest_to_turn_in(current_npc_id):
			quest_button.text = "Complete Quest"
			quest_button.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		else:
			quest_button.text = "Quest"
			quest_button.remove_theme_color_override("font_color")

	# Trade button - show if NPC has shop
	var shop_id: String = current_npc_data.get("shop_inventory_id", "")
	trade_button.visible = not shop_id.is_empty()

	# Exit button - always visible
	exit_button.show()


func _npc_has_quest() -> bool:
	## Check if NPC has available quests or quests to turn in
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		# Check for new quests
		var available: Array = qm.get_quests_for_npc(current_npc_id)
		if not available.is_empty():
			return true
		# Check for turn-in quests
		if qm.has_quest_to_turn_in(current_npc_id):
			return true
	return false


#===============================================================================
# UI BUILDING
#===============================================================================

func _build_ui() -> void:
	# This layer should process while paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	# Background dimmer (click to close)
	background_dimmer = ColorRect.new()
	background_dimmer.name = "BackgroundDimmer"
	background_dimmer.color = Color(0, 0, 0, 0.5)
	background_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dimmer.gui_input.connect(_on_background_input)
	add_child(background_dimmer)

	# Main panel container
	panel = PanelContainer.new()
	panel.name = "HubPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.set_anchor_and_offset(SIDE_LEFT, 0.1, 0)
	panel.set_anchor_and_offset(SIDE_RIGHT, 0.9, 0)
	panel.set_anchor_and_offset(SIDE_TOP, 0.6, 0)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 0.95, 0)
	panel.add_theme_stylebox_override("panel", UITheme.create_popup_style())
	add_child(panel)

	# Main HBox for three sections
	var hbox := HBoxContainer.new()
	hbox.name = "MainLayout"
	hbox.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL * 2)
	panel.add_child(hbox)

	# LEFT: Portrait section
	var portrait_container := _build_portrait_section()
	hbox.add_child(portrait_container)

	# CENTER: Dialogue section
	var dialogue_container := _build_dialogue_section()
	dialogue_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(dialogue_container)

	# RIGHT: Buttons section
	var buttons_section := _build_buttons_section()
	hbox.add_child(buttons_section)


func _build_portrait_section() -> Control:
	var container := PanelContainer.new()
	container.name = "PortraitSection"
	container.custom_minimum_size = Vector2(120, 120)
	container.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_right", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_top", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_bottom", UITheme.MARGIN_STANDARD)
	container.add_child(margin)

	# Stack portrait texture and placeholder
	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(stack)

	# Green placeholder
	portrait_placeholder = ColorRect.new()
	portrait_placeholder.name = "PortraitPlaceholder"
	portrait_placeholder.color = Color(0.2, 0.6, 0.3)
	portrait_placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(portrait_placeholder)

	# Portrait texture (hidden by default)
	portrait_rect = TextureRect.new()
	portrait_rect.name = "PortraitTexture"
	portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_rect.hide()
	stack.add_child(portrait_rect)

	return container


func _build_dialogue_section() -> Control:
	var container := PanelContainer.new()
	container.name = "DialogueSection"
	container.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITheme.MARGIN_STANDARD * 2)
	margin.add_theme_constant_override("margin_right", UITheme.MARGIN_STANDARD * 2)
	margin.add_theme_constant_override("margin_top", UITheme.MARGIN_STANDARD + 4)
	margin.add_theme_constant_override("margin_bottom", UITheme.MARGIN_STANDARD + 4)
	container.add_child(margin)

	dialogue_label = RichTextLabel.new()
	dialogue_label.name = "DialogueText"
	dialogue_label.bbcode_enabled = true
	dialogue_label.fit_content = false
	dialogue_label.scroll_active = true
	dialogue_label.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE_TITLE)
	margin.add_child(dialogue_label)

	return container


func _build_buttons_section() -> Control:
	var container := PanelContainer.new()
	container.name = "ButtonsSection"
	container.custom_minimum_size = Vector2(140, 0)
	container.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_right", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_top", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_bottom", UITheme.MARGIN_STANDARD)
	container.add_child(margin)

	buttons_container = VBoxContainer.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL)
	margin.add_child(buttons_container)

	# Talk button
	talk_button = Button.new()
	talk_button.name = "TalkButton"
	talk_button.text = "Talk"
	talk_button.custom_minimum_size.y = 36
	talk_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	buttons_container.add_child(talk_button)

	# Quest button
	quest_button = Button.new()
	quest_button.name = "QuestButton"
	quest_button.text = "Quest"
	quest_button.custom_minimum_size.y = 36
	quest_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	buttons_container.add_child(quest_button)

	# Trade button
	trade_button = Button.new()
	trade_button.name = "TradeButton"
	trade_button.text = "Trade"
	trade_button.custom_minimum_size.y = 36
	trade_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	buttons_container.add_child(trade_button)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	buttons_container.add_child(spacer)

	# Exit button
	exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "Exit"
	exit_button.custom_minimum_size.y = 36
	exit_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	buttons_container.add_child(exit_button)

	# Quest Accept/Decline buttons (hidden by default)
	_quest_accept_button = Button.new()
	_quest_accept_button.name = "AcceptQuestButton"
	_quest_accept_button.text = "Accept"
	_quest_accept_button.custom_minimum_size.y = 36
	_quest_accept_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	_quest_accept_button.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
	_quest_accept_button.hide()
	buttons_container.add_child(_quest_accept_button)

	_quest_decline_button = Button.new()
	_quest_decline_button.name = "DeclineQuestButton"
	_quest_decline_button.text = "Decline"
	_quest_decline_button.custom_minimum_size.y = 36
	_quest_decline_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	_quest_decline_button.add_theme_color_override("font_color", UITheme.COLOR_DEBUFF)
	_quest_decline_button.hide()
	buttons_container.add_child(_quest_decline_button)

	return container


#===============================================================================
# SIGNAL CONNECTIONS
#===============================================================================

func _connect_signals() -> void:
	talk_button.pressed.connect(_on_talk_pressed)
	quest_button.pressed.connect(_on_quest_pressed)
	trade_button.pressed.connect(_on_trade_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	_quest_accept_button.pressed.connect(_on_quest_accept_pressed)
	_quest_decline_button.pressed.connect(_on_quest_decline_pressed)


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if click is outside the panel
		var panel_rect := panel.get_global_rect()
		if not panel_rect.has_point(event.global_position):
			close()


func _on_talk_pressed() -> void:
	Debug.log("HubUI", "Talk pressed")

	# Notify quest system that player talked to this NPC
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		qm.on_npc_talked(current_npc_id)

	# Get dialogue_talk_id and play it
	var dialogue_id: String = current_npc_data.get("dialogue_talk_id", "")
	if dialogue_id.is_empty():
		show_dialogue("...")
		return

	var frames: Array = DatabaseLoader.get_dialogue_frames(dialogue_id)
	if frames.is_empty():
		show_dialogue("...")
		return

	# For now, just show first frame (TODO: implement frame sequencing)
	var first_frame: Dictionary = frames[0]
	var text: String = first_frame.get("text", "...")
	show_dialogue(text)

	talk_pressed.emit()


func _on_quest_pressed() -> void:
	Debug.log("HubUI", "Quest pressed")

	if not has_node("/root/QuestManager"):
		show_dialogue("Quest system not available.")
		return

	var qm = get_node("/root/QuestManager")

	# Check for quests to turn in first
	var turn_in_quests: Array = qm.get_turn_in_quests_for_npc(current_npc_id)
	if not turn_in_quests.is_empty():
		var quest_id: String = turn_in_quests[0]
		var quest_data := DatabaseLoader.get_quest(quest_id)

		# Show completion dialogue
		var complete_dialogue: String = quest_data.get("complete_dialogue", "")
		if not complete_dialogue.is_empty():
			var frames := DatabaseLoader.get_dialogue_frames(complete_dialogue)
			if not frames.is_empty():
				show_dialogue(frames[0].get("text", "Thank you for completing the quest!"))
			else:
				show_dialogue("Thank you for completing the quest!")
		else:
			show_dialogue("Thank you for completing the quest!")

		# Complete the quest
		qm.complete_quest(quest_id)

		# Notify NPC talked (for any talk objectives)
		qm.on_npc_talked(current_npc_id)

		# Update button visibility
		_setup_buttons()
		quest_pressed.emit()
		return

	# Check for available quests
	var available: Array = qm.get_quests_for_npc(current_npc_id)
	if not available.is_empty():
		var quest_data: Dictionary = available[0]
		var quest_id: String = quest_data.get("id", "")

		# Store pending quest for accept/decline
		_pending_quest_id = quest_id

		# Show quest description
		var start_dialogue: String = quest_data.get("start_dialogue", "")
		if not start_dialogue.is_empty():
			var frames := DatabaseLoader.get_dialogue_frames(start_dialogue)
			if not frames.is_empty():
				show_dialogue(frames[0].get("text", quest_data.get("description", "I have a task for you.")))
			else:
				show_dialogue(quest_data.get("description", "I have a task for you."))
		else:
			show_dialogue(quest_data.get("description", "I have a task for you."))

		# Show Accept/Decline buttons, hide other buttons
		_show_quest_offer_buttons()
		quest_pressed.emit()
		return

	# No quests available
	show_dialogue("I don't have any quests for you right now.")
	quest_pressed.emit()


func _show_quest_offer_buttons() -> void:
	## Show Accept/Decline buttons, hide normal buttons
	talk_button.hide()
	quest_button.hide()
	trade_button.hide()
	exit_button.hide()
	_quest_accept_button.show()
	_quest_decline_button.show()


func _hide_quest_offer_buttons() -> void:
	## Hide Accept/Decline buttons, restore normal buttons
	_quest_accept_button.hide()
	_quest_decline_button.hide()
	_pending_quest_id = ""
	_setup_buttons()


func _on_quest_accept_pressed() -> void:
	Debug.log("HubUI", "Quest accepted: %s" % _pending_quest_id)

	if _pending_quest_id.is_empty():
		_hide_quest_offer_buttons()
		return

	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		var success: bool = qm.start_quest(_pending_quest_id)
		Debug.info("HubUI", "Quest start result: %s for %s" % [success, _pending_quest_id])
		qm.on_npc_talked(current_npc_id)

	show_dialogue("Good luck, adventurer!")
	_hide_quest_offer_buttons()


func _on_quest_decline_pressed() -> void:
	Debug.log("HubUI", "Quest declined: %s" % _pending_quest_id)

	show_dialogue("Come back if you change your mind.")
	_hide_quest_offer_buttons()


func _on_trade_pressed() -> void:
	Debug.log("HubUI", "Trade pressed")
	# TODO: Open shop UI
	show_dialogue("Trade functionality coming soon...")
	trade_pressed.emit()


func _on_exit_pressed() -> void:
	close()


#===============================================================================
# HELPERS
#===============================================================================

func _complete_typewriter() -> void:
	if _is_typing:
		dialogue_label.text = _typewriter_text
		_typewriter_index = _typewriter_text.length()
		_is_typing = false
		set_process(false)
