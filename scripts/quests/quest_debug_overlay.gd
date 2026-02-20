extends CanvasLayer
## QuestDebugOverlay - Visual debugging overlay for the quest system
## Toggle with QuestManager.debug_toggle_overlay() or F9 key
##
## Shows:
## - Active quests and their objectives
## - Quest state changes in real-time
## - Debug controls for testing

var enabled: bool = false

var _panel: Panel
var _vbox: VBoxContainer
var _quest_labels: Dictionary = {}  # quest_id -> Label
var _log_label: RichTextLabel
var _log_entries: Array[String] = []
const MAX_LOG_ENTRIES := 20


func _ready() -> void:
	layer = 200  # Above everything
	_create_ui()
	_connect_signals()
	visible = false
	Debug.info("Quest", "Debug overlay initialized (press F9 to toggle)")


func _create_ui() -> void:
	# Main panel
	_panel = Panel.new()
	_panel.name = "QuestDebugPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -400
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = 500
	_panel.size = Vector2(390, 490)
	add_child(_panel)

	# Scroll container
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 5
	scroll.offset_right = -5
	scroll.offset_top = 5
	scroll.offset_bottom = -5
	_panel.add_child(scroll)

	# Content
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	# Header
	var header := Label.new()
	header.text = "=== QUEST DEBUG ==="
	header.add_theme_color_override("font_color", Color.GOLD)
	_vbox.add_child(header)

	# Stats section
	var stats_header := Label.new()
	stats_header.text = "--- Statistics ---"
	stats_header.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	_vbox.add_child(stats_header)

	var stats_label := Label.new()
	stats_label.name = "StatsLabel"
	_vbox.add_child(stats_label)

	# Active quests section
	var quests_header := Label.new()
	quests_header.text = "--- Active Quests ---"
	quests_header.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	_vbox.add_child(quests_header)

	var quests_container := VBoxContainer.new()
	quests_container.name = "QuestsContainer"
	_vbox.add_child(quests_container)

	# Log section
	var log_header := Label.new()
	log_header.text = "--- Event Log ---"
	log_header.add_theme_color_override("font_color", Color.ORANGE)
	_vbox.add_child(log_header)

	_log_label = RichTextLabel.new()
	_log_label.name = "LogLabel"
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.custom_minimum_size = Vector2(0, 150)
	_vbox.add_child(_log_label)


func _connect_signals() -> void:
	# Wait for QuestManager to be ready
	if not has_node("/root/QuestManager"):
		call_deferred("_connect_signals")
		return

	var qm = get_node("/root/QuestManager")
	qm.quest_started.connect(_on_quest_started)
	qm.quest_completed.connect(_on_quest_completed)
	qm.quest_failed.connect(_on_quest_failed)
	qm.quest_abandoned.connect(_on_quest_abandoned)
	qm.objective_updated.connect(_on_objective_updated)
	qm.objective_completed.connect(_on_objective_completed)
	qm.rewards_granted.connect(_on_rewards_granted)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			toggle()


func _process(_delta: float) -> void:
	if not enabled:
		return

	_update_display()


func toggle() -> void:
	enabled = not enabled
	visible = enabled
	Debug.info("Quest", "Debug overlay %s" % ("enabled" if enabled else "disabled"))


func _update_display() -> void:
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")

	# Update stats
	var stats_label := _vbox.get_node_or_null("StatsLabel") as Label
	if stats_label and qm._debug_stats:
		stats_label.text = "Started: %d | Completed: %d | Failed: %d\nObjectives: %d | XP: %d | Gold: %d" % [
			qm._debug_stats.quests_started,
			qm._debug_stats.quests_completed,
			qm._debug_stats.quests_failed,
			qm._debug_stats.objectives_completed,
			qm._debug_stats.total_xp_rewarded,
			qm._debug_stats.total_gold_rewarded
		]

	# Update quest list
	var quests_container := _vbox.get_node_or_null("QuestsContainer") as VBoxContainer
	if quests_container:
		_update_quest_list(qm, quests_container)


func _update_quest_list(qm, container: VBoxContainer) -> void:
	var active_quests: Array = qm.get_active_quests()

	# Remove stale quest labels
	for quest_id in _quest_labels.keys():
		if quest_id not in active_quests:
			var label: Label = _quest_labels[quest_id]
			if is_instance_valid(label):
				label.queue_free()
			_quest_labels.erase(quest_id)

	# Update/create quest labels
	for quest_id in active_quests:
		var state = qm.get_quest_state(quest_id)
		if not state:
			continue

		var quest_data := DatabaseLoader.get_quest(quest_id)
		var label: Label

		if _quest_labels.has(quest_id):
			label = _quest_labels[quest_id]
		else:
			label = Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			container.add_child(label)
			_quest_labels[quest_id] = label

		# Build quest text
		var text := "[%s] %s" % [
			"TRACKED" if quest_id == qm.tracked_quest_id else quest_data.get("type", "side").to_upper(),
			quest_data.get("name", quest_id)
		]

		for obj_id in state.objectives:
			var obj: Dictionary = state.objectives[obj_id]
			var status_icon := "[X]" if obj.complete else "[ ]"
			var progress := "%d/%d" % [obj.current, obj.target] if obj.target > 1 else ""
			var optional := " (opt)" if obj.get("optional", false) else ""
			text += "\n  %s %s %s%s" % [status_icon, obj_id, progress, optional]

		label.text = text

		# Color based on tracking
		if quest_id == qm.tracked_quest_id:
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			label.remove_theme_color_override("font_color")


func _log(message: String, color: Color = Color.WHITE) -> void:
	var time := Time.get_time_dict_from_system()
	var timestamp := "%02d:%02d:%02d" % [time.hour, time.minute, time.second]
	var entry := "[color=#%s][%s] %s[/color]" % [color.to_html(false), timestamp, message]

	_log_entries.append(entry)
	if _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()

	if _log_label:
		_log_label.text = "\n".join(_log_entries)


func _on_quest_started(quest_id: String) -> void:
	var quest_data := DatabaseLoader.get_quest(quest_id)
	_log("STARTED: %s" % quest_data.get("name", quest_id), Color.GREEN)


func _on_quest_completed(quest_id: String) -> void:
	var quest_data := DatabaseLoader.get_quest(quest_id)
	_log("COMPLETED: %s" % quest_data.get("name", quest_id), Color.GOLD)


func _on_quest_failed(quest_id: String) -> void:
	var quest_data := DatabaseLoader.get_quest(quest_id)
	_log("FAILED: %s" % quest_data.get("name", quest_id), Color.RED)


func _on_quest_abandoned(quest_id: String) -> void:
	var quest_data := DatabaseLoader.get_quest(quest_id)
	_log("ABANDONED: %s" % quest_data.get("name", quest_id), Color.GRAY)


func _on_objective_updated(quest_id: String, objective_id: String, current: int, target: int) -> void:
	_log("%s: %s (%d/%d)" % [quest_id, objective_id, current, target], Color.LIGHT_BLUE)


func _on_objective_completed(quest_id: String, objective_id: String) -> void:
	_log("OBJ DONE: %s/%s" % [quest_id, objective_id], Color.LIGHT_GREEN)


func _on_rewards_granted(quest_id: String, rewards: Dictionary) -> void:
	var reward_str := ""
	if rewards.get("experience", 0) > 0:
		reward_str += "+%dXP " % rewards.experience
	if rewards.get("gold", 0) > 0:
		reward_str += "+%dG " % rewards.gold
	if rewards.get("items", []).size() > 0:
		reward_str += "+%d items" % rewards.items.size()

	_log("REWARDS: %s" % reward_str, Color.YELLOW)
