extends CanvasLayer
## TalentDebugOverlay - Real-time debug overlay for talent procs and damage
## Toggle with F10 key or via Debug Menu
##
## Shows:
## - Proc event log (timestamped, with trigger/condition/effect details)
## - Current stat bonuses from passive talents
## - Next-attack damage bonus and timer
## - Per-hit damage breakdown (auto-clears after 5s)

var enabled: bool = false

## UI references
var _panel: Panel
var _vbox: VBoxContainer
var _proc_log: RichTextLabel
var _stat_label: Label
var _next_attack_label: Label
var _breakdown_label: RichTextLabel

## State
var _log_entries: Array[String] = []
const MAX_LOG_ENTRIES := 15
var _poll_timer: float = 0.0
const POLL_INTERVAL := 0.1
var _breakdown_clear_timer: float = 0.0
const BREAKDOWN_DISPLAY_TIME := 5.0

## Pending procs collected between hits (populated by proc_triggered, flushed by damage_breakdown)
var _pending_procs: Array[String] = []


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	_connect_signals()
	visible = false
	Debug.info("Debug", "TalentDebugOverlay initialized (press F10 to toggle)")


func _create_ui() -> void:
	# Main panel - bottom-left, ~35% x 55% viewport
	_panel = Panel.new()
	_panel.name = "TalentDebugPanel"
	add_child(_panel)

	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.COLOR_PANEL_BG, 0.85)
	style.border_color = UITheme.COLOR_PANEL_BORDER
	style.set_border_width_all(UITheme.BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	_panel.add_theme_stylebox_override("panel", style)

	# Scroll container
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := UITheme.MARGIN_SMALL
	scroll.offset_left = pad
	scroll.offset_right = -pad
	scroll.offset_top = pad
	scroll.offset_bottom = -pad
	_panel.add_child(scroll)

	# Content VBox
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(_vbox)
	scroll.add_child(_vbox)

	# Header
	var header := Label.new()
	header.text = "=== TALENT DEBUG (F10) ==="
	header.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	_vbox.add_child(header)

	# --- Proc Log Section ---
	var proc_header := Label.new()
	proc_header.text = "--- Proc Log ---"
	proc_header.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	proc_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(proc_header)

	_proc_log = RichTextLabel.new()
	_proc_log.name = "ProcLog"
	_proc_log.bbcode_enabled = true
	_proc_log.scroll_following = true
	_proc_log.custom_minimum_size = Vector2(0, 120)
	_proc_log.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(_proc_log)

	# --- Stat Bonuses Section ---
	var stat_header := Label.new()
	stat_header.text = "--- Stat Bonuses ---"
	stat_header.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	stat_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(stat_header)

	_stat_label = Label.new()
	_stat_label.name = "StatBonuses"
	_stat_label.text = "(none)"
	_stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stat_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(_stat_label)

	# --- Next Attack Bonus Section ---
	var next_header := Label.new()
	next_header.text = "--- Next Attack Bonus ---"
	next_header.add_theme_color_override("font_color", Color.ORANGE)
	next_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(next_header)

	_next_attack_label = Label.new()
	_next_attack_label.name = "NextAttackBonus"
	_next_attack_label.text = "Bonus: 0%"
	_next_attack_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(_next_attack_label)

	# --- Last Hit Breakdown Section ---
	var breakdown_header := Label.new()
	breakdown_header.text = "--- Last Hit Breakdown ---"
	breakdown_header.add_theme_color_override("font_color", Color.YELLOW)
	breakdown_header.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(breakdown_header)

	_breakdown_label = RichTextLabel.new()
	_breakdown_label.name = "Breakdown"
	_breakdown_label.bbcode_enabled = true
	_breakdown_label.custom_minimum_size = Vector2(0, 60)
	_breakdown_label.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE_SMALL)
	_vbox.add_child(_breakdown_label)

	# Apply layout
	call_deferred("_apply_layout")
	get_viewport().size_changed.connect(_apply_layout)


func _apply_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var panel_w := vp_size.x * 0.35
	var panel_h := vp_size.y * 0.55
	var margin := vp_size.x * 0.02
	_panel.position = Vector2(margin, vp_size.y - panel_h - margin)
	_panel.size = Vector2(panel_w, panel_h)


func _connect_signals() -> void:
	# Proc triggered
	if TalentProcSystem:
		TalentProcSystem.proc_triggered.connect(_on_proc_triggered)
		TalentProcSystem.damage_breakdown_available.connect(_on_damage_breakdown)

	# Talent changes
	if TalentManager:
		TalentManager.talent_learned.connect(_on_talent_changed)
		TalentManager.talent_points_changed.connect(_on_points_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			toggle()


func _process(delta: float) -> void:
	if not enabled:
		return

	# Poll stat bonuses and next-attack bonus at interval
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_update_stat_bonuses()
		_update_next_attack_bonus()

	# Auto-clear breakdown after timeout
	if _breakdown_clear_timer > 0:
		_breakdown_clear_timer -= delta
		if _breakdown_clear_timer <= 0:
			_breakdown_label.text = ""


func toggle() -> void:
	enabled = not enabled
	visible = enabled
	if enabled:
		_update_stat_bonuses()
		_update_next_attack_bonus()
	Debug.info("Debug", "Talent debug overlay %s" % ("enabled" if enabled else "disabled"))


#===============================================================================
# SIGNAL HANDLERS
#===============================================================================

func _on_proc_triggered(talent_id: String, effect: String) -> void:
	# Get talent details for richer logging
	var talent := TalentManager.get_talent(talent_id)
	var talent_name := talent.talent_name if talent else talent_id
	var trigger := talent.proc_trigger if talent else "?"
	var condition := talent.proc_condition if talent else ""

	# Timestamp
	var time := Time.get_time_dict_from_system()
	var ts := "%02d:%02d:%02d" % [time.hour, time.minute, time.second]

	# Build log entry
	var entry := "[color=#66ccff][%s][/color] [color=#ffdd44]%s[/color] PROC\n" % [ts, talent_name]
	entry += "  trigger: %s" % trigger
	if not condition.is_empty():
		entry += "  |  condition: %s" % condition
	entry += "\n  effect: %s" % effect

	_log_entries.append(entry)
	if _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()

	if _proc_log:
		_proc_log.text = "\n".join(_log_entries)

	# Track for damage breakdown association
	_pending_procs.append(talent_name)


func _on_damage_breakdown(info: Dictionary) -> void:
	var skill_name: String = info.get("skill_name", "?")
	var target_name: String = info.get("target_name", "?")
	var base_damage: float = info.get("base_damage", 0.0)
	var proc_bonus_pct: float = info.get("proc_bonus_pct", 0.0)
	var final_damage: float = info.get("final_damage", 0.0)
	var is_critical: bool = info.get("is_critical", false)

	var text := "[color=#ffdd44]%s[/color] -> [color=#ff8866]%s[/color]" % [skill_name, target_name]
	text += "\n  Base: %.0f" % base_damage
	if proc_bonus_pct > 0:
		text += "  |  Proc: [color=#44ff44]+%.0f%%[/color]" % proc_bonus_pct
	text += "  |  Final: [color=#ffffff]%.0f[/color]" % final_damage
	if is_critical:
		text += "  [color=#ff4444]CRIT![/color]"

	if not _pending_procs.is_empty():
		text += "\n  Procs: [color=#bb88ff]%s[/color]" % ", ".join(_pending_procs)

	_pending_procs.clear()

	if _breakdown_label:
		_breakdown_label.text = text
	_breakdown_clear_timer = BREAKDOWN_DISPLAY_TIME


func _on_talent_changed(_talent_id: String, _new_points: int) -> void:
	if enabled:
		_update_stat_bonuses()


func _on_points_changed(_total: int, _available: int) -> void:
	if enabled:
		_update_stat_bonuses()


#===============================================================================
# POLLING UPDATES
#===============================================================================

func _update_stat_bonuses() -> void:
	## Aggregate stat bonuses from all invested passive talents
	var bonuses: Dictionary = {}

	for talent_id in TalentManager.invested_talents:
		var points: int = TalentManager.invested_talents[talent_id]
		if points <= 0:
			continue
		var talent := TalentManager.get_talent(talent_id)
		if not talent or not talent.is_passive():
			continue
		var talent_bonuses := talent.get_stat_bonuses_at_points(points)
		for stat in talent_bonuses:
			bonuses[stat] = bonuses.get(stat, 0.0) + talent_bonuses[stat]

	if bonuses.is_empty():
		_stat_label.text = "(none)"
	else:
		var lines: Array[String] = []
		for stat in bonuses:
			lines.append("%s: +%s" % [stat, int(bonuses[stat]) if bonuses[stat] == int(bonuses[stat]) else "%.1f" % bonuses[stat]])
		_stat_label.text = "\n".join(lines)


func _update_next_attack_bonus() -> void:
	if not TalentProcSystem:
		_next_attack_label.text = "Bonus: 0%"
		return

	var bonus: float = TalentProcSystem._next_attack_bonus_percent
	var timer: float = TalentProcSystem._next_attack_bonus_timer

	if bonus > 0 and timer > 0:
		_next_attack_label.text = "Bonus: +%.0f%% (timer: %.1fs)" % [bonus, timer]
		_next_attack_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_next_attack_label.text = "Bonus: 0%"
		_next_attack_label.remove_theme_color_override("font_color")
