extends CharacterMenuPopup
class_name SkillPopup
## SkillPopup - Shows talent/skill details in a popup at tap position

#===============================================================================
# CONSTANTS
#===============================================================================

const POPUP_MIN_HEIGHT_PCT := 0.55  # 55% of viewport (increased from 45%)
const POPUP_MAX_HEIGHT_PCT := 0.90  # 90% of viewport (increased from 75%)

#===============================================================================
# STATE
#===============================================================================

var current_talent_id: String = ""
var _from_talent_tree: bool = false  # Whether showing from talent tree (vs skillbook/active skills)

#===============================================================================
# UI REFERENCES
#===============================================================================

var _icon: TextureRect
var _name_label: Label
var _rank_label: Label
var _stats_container: VBoxContainer
var _description_label: RichTextLabel
var _learn_button: Button


#===============================================================================
# OVERRIDES
#===============================================================================

func _get_popup_width() -> int:
	return UITheme.POPUP_SKILL_BASE_WIDTH


func _get_popup_min_height_pct() -> float:
	return POPUP_MIN_HEIGHT_PCT


func _get_popup_max_height_pct() -> float:
	return POPUP_MAX_HEIGHT_PCT


func _build_header_content() -> VBoxContainer:
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	_name_label.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_col.add_child(_name_label)

	_rank_label = Label.new()
	_rank_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_rank_label.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
	name_col.add_child(_rank_label)

	return name_col


func _create_icon_container() -> Control:
	var icon_size := UITheme.scale_size(Vector2(15, 15))  # Base 15px scaled
	_icon = TextureRect.new()
	_icon.custom_minimum_size = icon_size
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = icon_size
	icon_bg.color = UITheme.COLOR_BUTTON_BG
	_icon.add_child(icon_bg)
	icon_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_bg.z_index = -1

	return _icon


func _build_content(content: VBoxContainer) -> void:
	# Stats container (for Type, Costs, etc.)
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 2)
	content.add_child(_stats_container)

	# Description
	_description_label = RichTextLabel.new()
	_description_label.bbcode_enabled = true
	_description_label.fit_content = true
	_description_label.scroll_active = false
	_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_label.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE_SMALL)
	_description_label.add_theme_color_override("default_color", UITheme.COLOR_TEXT_DIM)
	content.add_child(_description_label)

	# Learn button (only visible for talent tree selections that aren't maxed)
	_learn_button = Button.new()
	_learn_button.text = "Learn"
	_learn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learn_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	_learn_button.pressed.connect(_on_learn_pressed)
	_learn_button.visible = false
	content.add_child(_learn_button)

	# Connect to talent manager to update button when talent is learned
	TalentManager.talent_learned.connect(_on_talent_learned)


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup for a talent at the given screen position
## from_talent_tree: if true, shows Learn button for talents that can be learned
func show_talent(talent_id: String, screen_pos: Vector2, from_talent_tree: bool = false) -> void:
	var talent := TalentManager.get_talent(talent_id)
	if not talent:
		return

	current_talent_id = talent_id
	_from_talent_tree = from_talent_tree
	_update_content(talent)
	_update_learn_button(talent)
	show_at(screen_pos)


## Override close to clear talent id
func close() -> void:
	current_talent_id = ""
	super.close()


#===============================================================================
# CONTENT UPDATE
#===============================================================================

func _update_content(talent: TalentData) -> void:
	# Icon
	if _icon:
		var tex := TalentIconLoader.load_icon(talent.icon_name)
		if tex:
			_icon.texture = tex
		else:
			_icon.texture = null

	# Name
	_name_label.text = talent.talent_name

	# Rank/Points
	var invested := TalentManager.get_invested_points(talent.id)
	if talent.is_active():
		var skill_rank := TalentManager.get_skill_rank(talent.id)
		if invested > 0:
			_rank_label.text = "Skill Rank: %d / %d" % [skill_rank, TalentManager.MAX_SKILL_RANK]
			_rank_label.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
		else:
			_rank_label.text = "Not Learned"
			_rank_label.add_theme_color_override("font_color", UITheme.COLOR_LOCKED)
	else:
		_rank_label.text = "Points: %d / %d" % [invested, talent.max_points]
		if invested >= talent.max_points:
			_rank_label.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
		elif invested > 0:
			_rank_label.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
		else:
			_rank_label.add_theme_color_override("font_color", UITheme.COLOR_LOCKED)

	# Clear old stats
	for child in _stats_container.get_children():
		child.queue_free()

	# Build stats based on talent type
	if talent.is_active():
		add_stat_row(_stats_container, "Type", "Active", UITheme.COLOR_HIGHLIGHT)

		# Costs
		if talent.mana_cost > 0:
			add_stat_row(_stats_container, "Mana Cost", str(int(talent.mana_cost)), UITheme.COLOR_MANA)
		if talent.stamina_cost > 0:
			add_stat_row(_stats_container, "Stamina Cost", str(int(talent.stamina_cost)), UITheme.COLOR_STAMINA)
		if talent.cooldown > 0:
			add_stat_row(_stats_container, "Cooldown", "%.1fs" % talent.cooldown, UITheme.COLOR_SELECTED)

		# Combat stats
		if talent.hit_range > 0:
			add_stat_row(_stats_container, "Range", "%d px" % int(talent.hit_range), UITheme.COLOR_TEXT_DIM)
		if talent.weapon_damage_percent > 0:
			add_stat_row(_stats_container, "Weapon Damage", "%d%%" % int(talent.weapon_damage_percent), UITheme.COLOR_GOLD)
		if talent.base_damage > 0:
			add_stat_row(_stats_container, "Base Damage", str(int(talent.base_damage)), UITheme.COLOR_GOLD)

		# Weapon requirement
		if talent.has_weapon_requirement():
			var weapon_cat := Inventory.get_equipped_weapon_category()
			var is_met := talent.matches_weapon_category(weapon_cat)
			var req_text := _get_weapon_category_display_name(talent.required_weapon_category)
			var req_color := UITheme.COLOR_LEARNED if is_met else UITheme.COLOR_REQUIREMENT_UNMET
			add_stat_row(_stats_container, "Requires", req_text, req_color)

		# Rank effect
		var skill_rank := TalentManager.get_skill_rank(talent.id)
		if invested > 0 and skill_rank > 0 and skill_rank <= talent.rank_descriptions.size():
			add_stat_row(_stats_container, "Effect", talent.rank_descriptions[skill_rank - 1], UITheme.COLOR_LEARNED)
	else:
		# Passive talent
		add_stat_row(_stats_container, "Type", "Passive", UITheme.COLOR_AVAILABLE)

		# Stat bonuses
		if not talent.stat_bonuses.is_empty():
			var bonus_text := ""
			for stat in talent.stat_bonuses:
				if not bonus_text.is_empty():
					bonus_text += ", "
				bonus_text += "+%d %s" % [int(talent.stat_bonuses[stat]), stat.capitalize()]
			add_stat_row(_stats_container, "Per Point", bonus_text, UITheme.COLOR_LEARNED)

		# Current/Next rank effects
		if invested > 0 and invested <= talent.rank_descriptions.size():
			add_stat_row(_stats_container, "Current", talent.rank_descriptions[invested - 1], UITheme.COLOR_LEARNED)
		if invested < talent.max_points and invested < talent.rank_descriptions.size():
			add_stat_row(_stats_container, "Next", talent.rank_descriptions[invested], UITheme.COLOR_LOCKED)

	# Description
	_description_label.text = talent.description


func _get_weapon_category_display_name(category: String) -> String:
	match category:
		"melee": return "Melee Weapon"
		"melee_1h": return "One-Handed Melee"
		"melee_2h": return "Two-Handed Melee"
		"ranged": return "Ranged Weapon"
		"magic": return "Magic Weapon"
		_: return category.capitalize()


#===============================================================================
# LEARN BUTTON
#===============================================================================

## Update learn button visibility and text
func _update_learn_button(talent: TalentData) -> void:
	if not _learn_button:
		return

	var invested := TalentManager.get_invested_points(talent.id)
	var is_maxed := invested >= talent.max_points

	# Only show Learn button if:
	# - From talent tree (not skillbook or active skills)
	# - Talent is not fully learned/maxed
	if not _from_talent_tree or is_maxed:
		_learn_button.visible = false
		return

	_learn_button.visible = true

	# Update button text: "Learn" when 0/X, "Learn 1/X" when 1+/X
	if invested == 0:
		_learn_button.text = "Learn"
	else:
		_learn_button.text = "Learn %d/%d" % [invested, talent.max_points]

	# Enable/disable based on whether we can learn
	var can_learn := TalentManager.can_learn_talent(talent.id)
	_learn_button.disabled = not can_learn

	if not can_learn:
		var reason := TalentManager.get_learn_block_reason(talent.id)
		_learn_button.tooltip_text = reason
	else:
		_learn_button.tooltip_text = ""


## Handle Learn button press
func _on_learn_pressed() -> void:
	if current_talent_id.is_empty():
		return

	if TalentManager.can_learn_talent(current_talent_id):
		TalentManager.learn_talent(current_talent_id)


## Handle talent learned event - refresh the popup content
func _on_talent_learned(talent_id: String, _new_points: int) -> void:
	if talent_id == current_talent_id and visible:
		var talent := TalentManager.get_talent(talent_id)
		if talent:
			_update_content(talent)
			_update_learn_button(talent)
