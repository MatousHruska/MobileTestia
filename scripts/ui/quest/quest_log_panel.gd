extends Control
class_name QuestLogPanel
## QuestLogPanel - Quest log UI for the character menu
## Shows active/completed quests with objectives and rewards

## Signals
signal quest_selected(quest_id: String)
signal quest_tracked(quest_id: String)
signal quest_abandoned(quest_id: String)

## UI References
var _quest_list: VBoxContainer
var _quest_scroll: ScrollContainer
var _details_panel: VBoxContainer
var _details_scroll: ScrollContainer

## Currently selected quest
var _selected_quest_id: String = ""

## Tracking buttons
var _track_button: Button
var _abandon_button: Button

## Filter state
enum Filter { ACTIVE, COMPLETED }
var _current_filter: Filter = Filter.ACTIVE

## Filter buttons
var _active_filter: Button
var _completed_filter: Button


func _ready() -> void:
	Debug.info("Quest", "QuestLogPanel _ready() called")

	# Set anchors to fill parent (since we're a Control in a VBoxContainer)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_ui()
	Debug.info("Quest", "QuestLogPanel _build_ui() completed, _quest_list valid: %s" % is_instance_valid(_quest_list))
	_connect_signals()
	refresh()
	Debug.info("Quest", "QuestLogPanel _ready() completed, _quest_list children: %d" % _quest_list.get_child_count())

	# Debug sizes after a frame
	call_deferred("_debug_sizes")


func _debug_sizes() -> void:
	Debug.info("Quest", "=== SIZE DEBUG ===")
	Debug.info("Quest", "QuestLogPanel size: %s, position: %s" % [size, position])
	if get_child_count() > 0:
		var hbox = get_child(0)
		Debug.info("Quest", "HBox size: %s, child_count: %d" % [hbox.size, hbox.get_child_count()])
		if hbox.get_child_count() > 0:
			var left = hbox.get_child(0)
			Debug.info("Quest", "Left panel size: %s" % left.size)
	Debug.info("Quest", "_quest_scroll size: %s" % _quest_scroll.size)
	Debug.info("Quest", "_quest_list size: %s, children: %d" % [_quest_list.size, _quest_list.get_child_count()])
	Debug.info("Quest", "=== END SIZE DEBUG ===")


func _build_ui() -> void:
	# Main horizontal split - use anchors to fill parent Control
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL)
	add_child(hbox)

	# LEFT: Quest list (25% width)
	var left_panel := _build_quest_list_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.25
	hbox.add_child(left_panel)

	# RIGHT: Quest details (75% width)
	var right_panel := _build_details_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.75
	hbox.add_child(right_panel)


func _build_quest_list_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION_SMALL)
	panel.add_child(vbox)

	# Filter tabs
	var filter_hbox := HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", UITheme.SEPARATION_SMALL)
	vbox.add_child(filter_hbox)

	# Filter tabs are Level 2 - Header
	_active_filter = Button.new()
	_active_filter.text = "Active"
	_active_filter.toggle_mode = true
	_active_filter.button_pressed = true
	_active_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_filter.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	_active_filter.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	_active_filter.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	_active_filter.add_theme_color_override("font_pressed_color", UITheme.COLOR_TEXT_NAV)
	_active_filter.add_theme_stylebox_override("normal", UITheme.create_tab_style(false))
	_active_filter.add_theme_stylebox_override("pressed", UITheme.create_tab_style(true))
	_active_filter.pressed.connect(_on_active_filter_pressed)
	filter_hbox.add_child(_active_filter)

	_completed_filter = Button.new()
	_completed_filter.text = "Completed"
	_completed_filter.toggle_mode = true
	_completed_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_completed_filter.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	_completed_filter.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	_completed_filter.add_theme_color_override("font_hover_color", UITheme.COLOR_TEXT_NAV)
	_completed_filter.add_theme_color_override("font_pressed_color", UITheme.COLOR_TEXT_NAV)
	_completed_filter.add_theme_stylebox_override("normal", UITheme.create_tab_style(false))
	_completed_filter.add_theme_stylebox_override("pressed", UITheme.create_tab_style(true))
	_completed_filter.pressed.connect(_on_completed_filter_pressed)
	filter_hbox.add_child(_completed_filter)

	# Scroll container for quest list
	_quest_scroll = ScrollContainer.new()
	_quest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_quest_scroll)

	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.add_theme_constant_override("separation", UITheme.SEPARATION_SMALL)
	_quest_scroll.add_child(_quest_list)

	# DEBUG: Add visible test label
	var debug_label := Label.new()
	debug_label.text = "DEBUG: Quest list container"
	debug_label.add_theme_color_override("font_color", Color.RED)
	_quest_list.add_child(debug_label)

	return panel


func _build_details_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_right", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_top", UITheme.MARGIN_STANDARD)
	margin.add_theme_constant_override("margin_bottom", UITheme.MARGIN_STANDARD)
	panel.add_child(margin)

	_details_scroll = ScrollContainer.new()
	_details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_details_scroll)

	_details_panel = VBoxContainer.new()
	_details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_panel.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL)
	_details_scroll.add_child(_details_panel)

	# Placeholder text
	var placeholder := Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = "Select a quest to view details"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	placeholder.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_details_panel.add_child(placeholder)

	return panel


func _connect_signals() -> void:
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		qm.quest_started.connect(_on_quest_changed)
		qm.quest_completed.connect(_on_quest_changed)
		qm.quest_failed.connect(_on_quest_changed)
		qm.quest_abandoned.connect(_on_quest_changed)
		qm.objective_updated.connect(_on_objective_updated)
		Debug.info("Quest", "QuestLogPanel connected to QuestManager signals")
	else:
		Debug.warn("Quest", "QuestLogPanel: QuestManager not found for signal connection")

	# Connect to theme reload for live editing
	UITheme.theme_reloaded.connect(_on_theme_reloaded)


func _on_theme_reloaded() -> void:
	## Rebuild UI when theme is reloaded (R hotkey)
	Debug.info("Quest", "QuestLogPanel: Rebuilding from reloaded theme")
	# Clear and rebuild UI
	for child in get_children():
		child.queue_free()
	# Wait a frame for cleanup then rebuild
	await get_tree().process_frame
	_build_ui()
	refresh()


func _on_quest_changed(_quest_id: String) -> void:
	refresh()


func _on_objective_updated(_quest_id: String, _obj_id: String, _current: int, _target: int) -> void:
	if _quest_id == _selected_quest_id:
		_show_quest_details(_selected_quest_id)


func _on_active_filter_pressed() -> void:
	_current_filter = Filter.ACTIVE
	_active_filter.button_pressed = true
	_completed_filter.button_pressed = false
	refresh()


func _on_completed_filter_pressed() -> void:
	_current_filter = Filter.COMPLETED
	_active_filter.button_pressed = false
	_completed_filter.button_pressed = true
	refresh()


func refresh() -> void:
	_populate_quest_list()
	if _selected_quest_id.is_empty():
		_clear_details()
	else:
		_show_quest_details(_selected_quest_id)


func _populate_quest_list() -> void:
	Debug.info("Quest", ">>> _populate_quest_list called, _quest_list valid: %s" % is_instance_valid(_quest_list))

	# Clear existing items
	for child in _quest_list.get_children():
		child.queue_free()

	Debug.log("Quest", "Populating quest list, filter: %s" % ("ACTIVE" if _current_filter == Filter.ACTIVE else "COMPLETED"))

	if not has_node("/root/QuestManager"):
		Debug.warn("Quest", "QuestManager not found in quest log panel")
		return

	var qm = get_node("/root/QuestManager")

	if _current_filter == Filter.ACTIVE:
		_populate_active_quests(qm)
	else:
		_populate_completed_quests(qm)

	# Debug: Log final state
	Debug.info("Quest", ">>> After populate: _quest_list children = %d, size = %s" % [_quest_list.get_child_count(), _quest_list.size])


func _populate_active_quests(qm) -> void:
	# Story quests first
	var story_quests: Array = qm.get_active_story_quests()
	var side_quests_preview: Array = qm.get_active_side_quests()
	Debug.info("Quest", "Active quests - Story: %d, Side: %d" % [story_quests.size(), side_quests_preview.size()])
	if not story_quests.is_empty():
		var header := _create_section_header("Story Quests")
		_quest_list.add_child(header)

		for quest_id in story_quests:
			var item := _create_quest_item(quest_id, qm.tracked_quest_id == quest_id)
			_quest_list.add_child(item)

	# Side quests
	var side_quests: Array = qm.get_active_side_quests()
	if not side_quests.is_empty():
		var header := _create_section_header("Side Quests")
		_quest_list.add_child(header)

		for quest_id in side_quests:
			var item := _create_quest_item(quest_id, qm.tracked_quest_id == quest_id)
			_quest_list.add_child(item)

	# No quests message
	if story_quests.is_empty() and side_quests.is_empty():
		var label := Label.new()
		label.text = "No active quests"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		_quest_list.add_child(label)


func _populate_completed_quests(qm) -> void:
	var completed: Array = qm.get_completed_quests()

	if completed.is_empty():
		var label := Label.new()
		label.text = "No completed quests"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		_quest_list.add_child(label)
		return

	for quest_id in completed:
		var item := _create_quest_item(quest_id, false, true)
		_quest_list.add_child(item)


func _create_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	label.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	return label


func _create_quest_item(quest_id: String, is_tracked: bool, is_completed: bool = false) -> Button:
	var quest_data := DatabaseLoader.get_quest(quest_id)
	var quest_name: String = quest_data.get("name", quest_id)

	Debug.info("Quest", "Creating quest item: %s (tracked: %s)" % [quest_name, is_tracked])

	var button := Button.new()
	button.text = quest_name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = UITheme.scale_px(12)  # Base 12px scaled
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)

	# Styling
	if is_tracked:
		button.text = "> " + quest_name
		button.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	elif is_completed:
		button.modulate.a = 0.6

	if _selected_quest_id == quest_id:
		button.button_pressed = true

	button.pressed.connect(_on_quest_item_pressed.bind(quest_id))

	return button


func _on_quest_item_pressed(quest_id: String) -> void:
	_selected_quest_id = quest_id
	_show_quest_details(quest_id)
	quest_selected.emit(quest_id)
	refresh()  # Update selection state in list


func _clear_details() -> void:
	for child in _details_panel.get_children():
		child.queue_free()

	var placeholder := Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = "Select a quest to view details"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	placeholder.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_details_panel.add_child(placeholder)


func _show_quest_details(quest_id: String) -> void:
	for child in _details_panel.get_children():
		child.queue_free()

	var quest_data := DatabaseLoader.get_quest(quest_id)
	if quest_data.is_empty():
		_clear_details()
		return

	var qm = get_node("/root/QuestManager") if has_node("/root/QuestManager") else null

	# Quest name
	var name_label := Label.new()
	name_label.text = quest_data.get("name", quest_id)
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_details_panel.add_child(name_label)

	# Quest type badge
	var type_label := Label.new()
	var quest_type: String = quest_data.get("type", "side")
	type_label.text = "[%s]" % quest_type.to_upper()
	type_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	type_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD if quest_type == "story" else UITheme.COLOR_HIGHLIGHT)
	_details_panel.add_child(type_label)

	# Separator
	var sep1 := HSeparator.new()
	_details_panel.add_child(sep1)

	# Description
	var desc_label := RichTextLabel.new()
	desc_label.bbcode_enabled = true
	desc_label.fit_content = true
	desc_label.text = quest_data.get("description", "No description available.")
	desc_label.custom_minimum_size.y = UITheme.scale_px(22)  # Base 22px scaled
	_details_panel.add_child(desc_label)

	# Separator
	var sep2 := HSeparator.new()
	_details_panel.add_child(sep2)

	# Objectives header
	var obj_header := Label.new()
	obj_header.text = "Objectives:"
	obj_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	obj_header.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
	_details_panel.add_child(obj_header)

	# Objectives list
	var state = qm.get_quest_state(quest_id) if qm else null
	var objectives: Array = quest_data.get("objectives", [])

	for obj in objectives:
		var obj_id: String = obj.get("id", "")
		var obj_desc: String = obj.get("description", obj_id)
		var obj_optional: bool = obj.get("optional", false)
		var obj_target: int = obj.get("count", 1)

		var obj_current := 0
		var obj_complete := false

		if state and state.objectives.has(obj_id):
			var obj_state: Dictionary = state.objectives[obj_id]
			obj_current = obj_state.get("current", 0)
			obj_complete = obj_state.get("complete", false)

		# Build objective text
		var obj_text := ""
		if obj_complete:
			obj_text = "[X] %s" % obj_desc
		else:
			obj_text = "[ ] %s" % obj_desc
			if obj_target > 1:
				obj_text += " (%d/%d)" % [obj_current, obj_target]

		if obj_optional:
			obj_text += " (optional)"

		var obj_label := Label.new()
		obj_label.text = obj_text
		obj_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)

		if obj_complete:
			obj_label.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
		elif obj_optional:
			obj_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

		_details_panel.add_child(obj_label)

	# Separator
	var sep3 := HSeparator.new()
	_details_panel.add_child(sep3)

	# Rewards header
	var rewards: Dictionary = quest_data.get("rewards", {})
	if not rewards.is_empty():
		var reward_header := Label.new()
		reward_header.text = "Rewards:"
		reward_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		reward_header.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		_details_panel.add_child(reward_header)

		if rewards.get("experience", 0) > 0:
			var xp_label := Label.new()
			xp_label.text = "  + %d Experience" % rewards.experience
			xp_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
			_details_panel.add_child(xp_label)

		if rewards.get("gold", 0) > 0:
			var gold_label := Label.new()
			gold_label.text = "  + %d Gold" % rewards.gold
			gold_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
			_details_panel.add_child(gold_label)

		var items: Array = rewards.get("items", [])
		for item_id in items:
			var item_label := Label.new()
			item_label.text = "  + %s" % item_id
			item_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
			_details_panel.add_child(item_label)

	# Action buttons (only for active quests)
	if _current_filter == Filter.ACTIVE and qm:
		var button_hbox := HBoxContainer.new()
		button_hbox.add_theme_constant_override("separation", UITheme.SEPARATION_NORMAL)
		_details_panel.add_child(button_hbox)

		_track_button = Button.new()
		_track_button.text = "Untrack" if qm.tracked_quest_id == quest_id else "Track"
		_track_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		_track_button.pressed.connect(_on_track_pressed.bind(quest_id))
		button_hbox.add_child(_track_button)

		if quest_data.get("can_abandon", true):
			_abandon_button = Button.new()
			_abandon_button.text = "Abandon"
			_abandon_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
			_abandon_button.add_theme_color_override("font_color", UITheme.COLOR_DEBUFF)
			_abandon_button.pressed.connect(_on_abandon_pressed.bind(quest_id))
			button_hbox.add_child(_abandon_button)


func _on_track_pressed(quest_id: String) -> void:
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	if qm.tracked_quest_id == quest_id:
		qm.untrack_quest()
	else:
		qm.track_quest(quest_id)

	quest_tracked.emit(quest_id)
	refresh()


func _on_abandon_pressed(quest_id: String) -> void:
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	qm.abandon_quest(quest_id)
	_selected_quest_id = ""
	quest_abandoned.emit(quest_id)
	refresh()
