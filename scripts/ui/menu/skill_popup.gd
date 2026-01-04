extends CharacterMenuPopup
class_name SkillPopup
## SkillPopup - Shows talent/skill details in a popup at tap position

#===============================================================================
# CONSTANTS
#===============================================================================

const POPUP_WIDTH := 280
const POPUP_MIN_HEIGHT_PCT := 0.45  # 45% of viewport - ensures decent size
const POPUP_MAX_HEIGHT_PCT := 0.75  # 75% of viewport

## Colors - use UITheme for consistency + additional skill-specific colors
const COLOR_MANA := Color(0.4, 0.6, 1.0)
const COLOR_STAMINA := Color(0.4, 1.0, 0.6)
const COLOR_REQUIREMENT_UNMET := Color(1.0, 0.4, 0.4)

#===============================================================================
# STATE
#===============================================================================

var current_talent_id: String = ""

#===============================================================================
# UI REFERENCES
#===============================================================================

var _icon: TextureRect
var _name_label: Label
var _rank_label: Label
var _stats_container: VBoxContainer
var _description_label: RichTextLabel


#===============================================================================
# OVERRIDES
#===============================================================================

func _get_popup_width() -> int:
	return POPUP_WIDTH


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
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(40, 40)
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


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup for a talent at the given screen position
func show_talent(talent_id: String, screen_pos: Vector2) -> void:
	var talent := TalentManager.get_talent(talent_id)
	if not talent:
		return

	current_talent_id = talent_id
	_update_content(talent)
	show_at(screen_pos)


## Override close to clear talent id
func close() -> void:
	current_talent_id = ""
	super.close()


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
			add_stat_row(_stats_container, "Mana Cost", str(int(talent.mana_cost)), COLOR_MANA)
		if talent.stamina_cost > 0:
			add_stat_row(_stats_container, "Stamina Cost", str(int(talent.stamina_cost)), COLOR_STAMINA)
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
			var req_color := UITheme.COLOR_LEARNED if is_met else COLOR_REQUIREMENT_UNMET
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
