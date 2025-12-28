extends CanvasLayer
class_name QuestRewardPopup
## QuestRewardPopup - Displays quest completion rewards
## Shows XP, gold, and items granted when a quest is completed

signal popup_closed

var _panel: PanelContainer
var _dimmer: ColorRect
var _content: VBoxContainer
var _continue_button: Button

var _is_open: bool = false


func _ready() -> void:
	layer = 150  # Above most UI but below top dialogs
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()

	# Connect to QuestManager rewards signal
	call_deferred("_connect_quest_manager")


func _connect_quest_manager() -> void:
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		qm.rewards_granted.connect(_on_rewards_granted)
		Debug.log("Quest", "RewardPopup connected to QuestManager")


func _build_ui() -> void:
	# Background dimmer
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = Color(0, 0, 0, 0.6)
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.gui_input.connect(_on_dimmer_input)
	add_child(_dimmer)

	# Main panel
	_panel = PanelContainer.new()
	_panel.name = "RewardPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(300, 200)
	add_child(_panel)

	# Content margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	margin.add_child(_content)


func _on_rewards_granted(quest_id: String, rewards: Dictionary) -> void:
	show_rewards(quest_id, rewards)


func show_rewards(quest_id: String, rewards: Dictionary) -> void:
	# Clear previous content
	for child in _content.get_children():
		child.queue_free()

	var quest_data := DatabaseLoader.get_quest(quest_id)

	# Header
	var header := Label.new()
	header.text = "Quest Complete!"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color.GOLD)
	_content.add_child(header)

	# Quest name
	var name_label := Label.new()
	name_label.text = quest_data.get("name", quest_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	_content.add_child(name_label)

	# Separator
	var sep := HSeparator.new()
	_content.add_child(sep)

	# Rewards header
	var rewards_header := Label.new()
	rewards_header.text = "Rewards:"
	rewards_header.add_theme_font_size_override("font_size", 14)
	rewards_header.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	_content.add_child(rewards_header)

	# Rewards list
	var rewards_vbox := VBoxContainer.new()
	rewards_vbox.add_theme_constant_override("separation", 4)
	_content.add_child(rewards_vbox)

	# XP
	var xp: int = rewards.get("experience", 0)
	if xp > 0:
		var xp_hbox := _create_reward_row("Experience", "+%d XP" % xp, Color(0.6, 0.8, 1.0))
		rewards_vbox.add_child(xp_hbox)

	# Gold
	var gold: int = rewards.get("gold", 0)
	if gold > 0:
		var gold_hbox := _create_reward_row("Gold", "+%d" % gold, Color.GOLD)
		rewards_vbox.add_child(gold_hbox)

	# Items
	var items: Array = rewards.get("items", [])
	for item_id in items:
		var item_data := DatabaseLoader.get_item_base(item_id)
		var item_name: String = item_data.get("name", item_id) if not item_data.is_empty() else item_id
		var item_hbox := _create_reward_row("Item", item_name, Color.LIGHT_CORAL)
		rewards_vbox.add_child(item_hbox)

	# No rewards case
	if xp == 0 and gold == 0 and items.is_empty():
		var no_rewards := Label.new()
		no_rewards.text = "(No additional rewards)"
		no_rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_rewards.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		rewards_vbox.add_child(no_rewards)

	# Continue button
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.custom_minimum_size.y = 40
	_continue_button.pressed.connect(_on_continue_pressed)
	_content.add_child(_continue_button)

	# Show popup with animation
	show()
	_is_open = true

	# Simple scale animation
	_panel.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.tween_property(_panel, "scale", Vector2(1, 1), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	Debug.info("Quest", "Showing reward popup", quest_id)


func _create_reward_row(label_text: String, value_text: String, color: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text + ":"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", color)
	hbox.add_child(value)

	return hbox


func _on_continue_pressed() -> void:
	close_popup()


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_popup()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		close_popup()
		get_viewport().set_input_as_handled()


func close_popup() -> void:
	if not _is_open:
		return

	_is_open = false

	# Fade out animation on child controls (CanvasLayer doesn't have modulate)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dimmer, "modulate:a", 0.0, 0.15)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.15)
	tween.set_parallel(false)
	tween.tween_callback(func():
		hide()
		_dimmer.modulate.a = 1.0
		_panel.modulate.a = 1.0
		popup_closed.emit()
	)

	Debug.log("Quest", "Reward popup closed")
