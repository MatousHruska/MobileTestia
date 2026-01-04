extends Control
class_name SkillPopup
## SkillPopup - Shows talent/skill details in a popup at tap position
##
## Features:
## - Appears at tap position (clamped to screen bounds)
## - Shows skill icon, name, rank, stats, and description
## - X button to close
## - Tap outside to close

#===============================================================================
# SIGNALS
#===============================================================================

signal closed

#===============================================================================
# CONSTANTS
#===============================================================================

const POPUP_WIDTH := 280
const POPUP_MIN_HEIGHT := 120
const POPUP_MAX_HEIGHT := 300
const MARGIN := 8
const SCREEN_PADDING := 10

## Colors
const COLOR_ACTIVE := Color(0.4, 0.9, 1.0)
const COLOR_PASSIVE := Color(1.0, 0.9, 0.3)
const COLOR_LEARNED := Color(0.5, 1.0, 0.5)
const COLOR_LOCKED := Color(0.6, 0.6, 0.6)
const COLOR_MANA := Color(0.4, 0.6, 1.0)
const COLOR_STAMINA := Color(0.4, 1.0, 0.6)
const COLOR_REQUIREMENT_MET := Color(0.5, 1.0, 0.5)
const COLOR_REQUIREMENT_UNMET := Color(1.0, 0.4, 0.4)

#===============================================================================
# STATE
#===============================================================================

var current_talent_id: String = ""
var _is_closing: bool = false

#===============================================================================
# UI REFERENCES
#===============================================================================

var _background: ColorRect
var _panel: PanelContainer
var _close_button: Button
var _icon: TextureRect
var _name_label: Label
var _rank_label: Label
var _stats_container: VBoxContainer
var _description_label: RichTextLabel
var _scroll: ScrollContainer


func _ready() -> void:
	_build_ui()
	visible = false
	# Process input even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS


#===============================================================================
# UI BUILDING
#===============================================================================

func _build_ui() -> void:
	# Full screen background for detecting outside clicks
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0, 0, 0, 0.3)
	_background.gui_input.connect(_on_background_input)
	add_child(_background)

	# Main popup panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(POPUP_WIDTH, POPUP_MIN_HEIGHT)
	add_child(_panel)

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	margin.add_theme_constant_override("margin_top", MARGIN)
	margin.add_theme_constant_override("margin_bottom", MARGIN)
	_panel.add_child(margin)

	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header row: Icon + Name/Rank + Close button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	# Icon
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header.add_child(_icon)

	# Icon placeholder background
	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(40, 40)
	icon_bg.color = Color(0.2, 0.2, 0.25, 0.8)
	_icon.add_child(icon_bg)
	icon_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_bg.z_index = -1

	# Name and rank column
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_col)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_col.add_child(_name_label)

	_rank_label = Label.new()
	_rank_label.add_theme_font_size_override("font_size", 11)
	_rank_label.add_theme_color_override("font_color", COLOR_LEARNED)
	name_col.add_child(_rank_label)

	# Close button
	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.pressed.connect(_on_close_pressed)
	header.add_child(_close_button)

	# Style close button
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.4, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(4)
	_close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.6, 0.2, 0.2, 0.9)
	close_hover.set_corner_radius_all(4)
	_close_button.add_theme_stylebox_override("hover", close_hover)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable content area
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 60)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	var scroll_content := VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("separation", 4)
	_scroll.add_child(scroll_content)

	# Stats container (for Type, Costs, etc.)
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 2)
	scroll_content.add_child(_stats_container)

	# Description
	_description_label = RichTextLabel.new()
	_description_label.bbcode_enabled = true
	_description_label.fit_content = true
	_description_label.scroll_active = false
	_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_label.add_theme_font_size_override("normal_font_size", 11)
	_description_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8))
	scroll_content.add_child(_description_label)


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup for a talent at the given screen position
func show_talent(talent_id: String, screen_pos: Vector2) -> void:
	var talent := TalentManager.get_talent(talent_id)
	if not talent:
		return

	current_talent_id = talent_id
	_is_closing = false

	# Update content
	_update_content(talent)

	# Position popup
	_position_popup(screen_pos)

	visible = true


## Close the popup
func close() -> void:
	if _is_closing:
		return
	_is_closing = true
	visible = false
	current_talent_id = ""
	closed.emit()


#===============================================================================
# CONTENT UPDATE
#===============================================================================

func _update_content(talent: TalentData) -> void:
	# Name
	_name_label.text = talent.talent_name

	# Rank/Points
	var invested := TalentManager.get_invested_points(talent.id)
	if talent.is_active():
		var skill_rank := TalentManager.get_skill_rank(talent.id)
		if invested > 0:
			_rank_label.text = "Skill Rank: %d / %d" % [skill_rank, TalentManager.MAX_SKILL_RANK]
			_rank_label.add_theme_color_override("font_color", COLOR_LEARNED)
		else:
			_rank_label.text = "Not Learned"
			_rank_label.add_theme_color_override("font_color", COLOR_LOCKED)
	else:
		_rank_label.text = "Points: %d / %d" % [invested, talent.max_points]
		if invested >= talent.max_points:
			_rank_label.add_theme_color_override("font_color", COLOR_LEARNED)
		elif invested > 0:
			_rank_label.add_theme_color_override("font_color", COLOR_PASSIVE)
		else:
			_rank_label.add_theme_color_override("font_color", COLOR_LOCKED)

	# Clear old stats
	for child in _stats_container.get_children():
		child.queue_free()

	# Build stats based on talent type
	if talent.is_active():
		_add_stat_row("Type", "Active", COLOR_ACTIVE)

		# Costs
		if talent.mana_cost > 0:
			_add_stat_row("Mana Cost", str(int(talent.mana_cost)), COLOR_MANA)
		if talent.stamina_cost > 0:
			_add_stat_row("Stamina Cost", str(int(talent.stamina_cost)), COLOR_STAMINA)
		if talent.cooldown > 0:
			_add_stat_row("Cooldown", "%.1fs" % talent.cooldown, Color(0.9, 0.9, 0.9))

		# Combat stats
		if talent.hit_range > 0:
			_add_stat_row("Range", "%d px" % int(talent.hit_range), Color(0.8, 0.8, 0.8))
		if talent.weapon_damage_percent > 0:
			_add_stat_row("Weapon Damage", "%d%%" % int(talent.weapon_damage_percent), Color(0.9, 0.7, 0.5))
		if talent.base_damage > 0:
			_add_stat_row("Base Damage", str(int(talent.base_damage)), Color(0.9, 0.7, 0.5))

		# Weapon requirement
		if talent.has_weapon_requirement():
			var weapon_cat := Inventory.get_equipped_weapon_category()
			var is_met := talent.matches_weapon_category(weapon_cat)
			var req_text := _get_weapon_category_display_name(talent.required_weapon_category)
			var req_color := COLOR_REQUIREMENT_MET if is_met else COLOR_REQUIREMENT_UNMET
			_add_stat_row("Requires", req_text, req_color)

		# Rank effect
		var skill_rank := TalentManager.get_skill_rank(talent.id)
		if invested > 0 and skill_rank > 0 and skill_rank <= talent.rank_descriptions.size():
			_add_stat_row("Effect", talent.rank_descriptions[skill_rank - 1], Color(0.7, 1.0, 0.7))
	else:
		# Passive talent
		_add_stat_row("Type", "Passive", COLOR_PASSIVE)

		# Stat bonuses
		if not talent.stat_bonuses.is_empty():
			var bonus_text := ""
			for stat in talent.stat_bonuses:
				if not bonus_text.is_empty():
					bonus_text += ", "
				bonus_text += "+%d %s" % [int(talent.stat_bonuses[stat]), stat.capitalize()]
			_add_stat_row("Per Point", bonus_text, Color(0.7, 1.0, 0.7))

		# Current/Next rank effects
		if invested > 0 and invested <= talent.rank_descriptions.size():
			_add_stat_row("Current", talent.rank_descriptions[invested - 1], Color(0.7, 1.0, 0.7))
		if invested < talent.max_points and invested < talent.rank_descriptions.size():
			_add_stat_row("Next", talent.rank_descriptions[invested], Color(0.6, 0.6, 0.6))

	# Description
	_description_label.text = talent.description


func _add_stat_row(label_text: String, value_text: String, value_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_stats_container.add_child(row)

	var label := Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", value_color)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value)


func _get_weapon_category_display_name(category: String) -> String:
	match category:
		"melee": return "Melee Weapon"
		"melee_1h": return "One-Handed Melee"
		"melee_2h": return "Two-Handed Melee"
		"ranged": return "Ranged Weapon"
		"magic": return "Magic Weapon"
		_: return category.capitalize()


#===============================================================================
# POSITIONING
#===============================================================================

func _position_popup(tap_pos: Vector2) -> void:
	# Wait for layout to calculate sizes
	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _panel.size

	# Limit panel height
	if panel_size.y > POPUP_MAX_HEIGHT:
		_panel.custom_minimum_size.y = POPUP_MAX_HEIGHT
		_scroll.custom_minimum_size.y = POPUP_MAX_HEIGHT - 100
		panel_size.y = POPUP_MAX_HEIGHT

	# Start position: slightly above and to the right of tap
	var pos := tap_pos + Vector2(10, -panel_size.y / 2)

	# Clamp to screen bounds
	pos.x = clampf(pos.x, SCREEN_PADDING, viewport_size.x - panel_size.x - SCREEN_PADDING)
	pos.y = clampf(pos.y, SCREEN_PADDING, viewport_size.y - panel_size.y - SCREEN_PADDING)

	_panel.position = pos


#===============================================================================
# INPUT HANDLING
#===============================================================================

func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			# Check if tap is outside the panel
			var panel_rect := _panel.get_global_rect()
			var tap_pos: Vector2 = event.position
			if not panel_rect.has_point(tap_pos):
				close()


func _on_close_pressed() -> void:
	close()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on escape
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
