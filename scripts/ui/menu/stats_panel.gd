extends Control
class_name StatsPanel
## Stats Panel - Displays player attributes and derived stats
## Left side: Primary attributes + Resources (always visible)
## Right side: Subtabs for Offensive/Defensive/Utility stats + Description box

enum SubTab { OFFENSIVE, DEFENSIVE, UTILITY }

## Subtab state
var current_subtab: SubTab = SubTab.OFFENSIVE

## UI node caches
var _attribute_rows: Dictionary = {}
var _resource_labels: Dictionary = {}
var _subtab_buttons: Array[Button] = []
var _subtab_panels: Array[Control] = []

## Description box
var _description_title: Label = null
var _description_text: Label = null

## Effects section
var _effects_container: HBoxContainer = null
var _effect_icons: Dictionary = {}  # effect_type -> icon button
var _no_effects_label: Label = null


func _ready() -> void:
	_build_ui()
	_connect_signals()
	refresh_display()
	Debug.info("UI", "StatsPanel ready")


func _process(_delta: float) -> void:
	# Update effect timers in real-time while panel is visible
	_update_effect_timers()


func _build_ui() -> void:
	# Main vertical layout: Top (stats panels) | Bottom (effects section)
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# === TOP: Horizontal split for stats ===
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(main_hbox)

	# === LEFT SIDE: Primary Attributes + Resources ===
	var left_panel := _create_left_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.45
	main_hbox.add_child(left_panel)

	# === VERTICAL SEPARATOR ===
	var vsep := VSeparator.new()
	main_hbox.add_child(vsep)

	# === RIGHT SIDE: Secondary Stats with Subtabs ===
	var right_panel := _create_right_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.55
	main_hbox.add_child(right_panel)

	# === BOTTOM: Active Effects Section ===
	var effects_section := _create_effects_section()
	main_vbox.add_child(effects_section)


func _create_left_panel() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)

	# === HEADER: Level and XP ===
	var header := _create_header()
	container.add_child(header)

	# === PRIMARY ATTRIBUTES ===
	var attributes_section := _create_attributes_section()
	container.add_child(attributes_section)

	# === RESOURCES (simple text, no bars) ===
	var resources_section := _create_resources_section()
	container.add_child(resources_section)

	return container


func _create_right_panel() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)

	# === SUBTAB BAR ===
	var subtab_bar := _create_subtab_bar()
	container.add_child(subtab_bar)

	# === SUBTAB CONTENT ===
	var subtab_content := _create_subtab_content()
	container.add_child(subtab_content)

	# === DESCRIPTION BOX (aligned with Resources on left) ===
	var description_box := _create_description_box()
	container.add_child(description_box)

	return container


func _create_header() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	# Level row
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 12)

	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.text = "Level 1"
	level_row.add_child(level_label)

	var points_label := Label.new()
	points_label.name = "PointsLabel"
	points_label.add_theme_font_size_override("font_size", 14)
	points_label.text = "Attr: 0"
	points_label.modulate = Color(1.0, 0.9, 0.3)
	level_row.add_child(points_label)

	var skill_points_label := Label.new()
	skill_points_label.name = "SkillPointsLabel"
	skill_points_label.add_theme_font_size_override("font_size", 14)
	skill_points_label.text = "Skill: 0"
	skill_points_label.modulate = Color(0.3, 0.9, 1.0)
	level_row.add_child(skill_points_label)

	container.add_child(level_row)

	# XP row
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)

	var xp_bar := ProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.custom_minimum_size = Vector2(120, 14)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.show_percentage = false
	xp_row.add_child(xp_bar)

	var xp_label := Label.new()
	xp_label.name = "XPLabel"
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.text = "0 / 100"
	xp_row.add_child(xp_label)

	container.add_child(xp_row)

	return container


func _create_attributes_section() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "Primary Attributes"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.7, 0.7)
	container.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)

	var attributes := [
		["STR", "strength", "Physical Mastery"],
		["DEX", "dexterity", "Agility Mastery"],
		["INT", "intelligence", "Arcane Mastery"],
		["VIT", "vitality", "+2 HP per point"],
		["ENE", "energy", "+1.5 MP per point"],
		["LUK", "luck", "+1% Crit Dmg"],
	]

	for attr in attributes:
		var row := _create_attribute_row(attr[0], attr[1], attr[2])
		for child in row:
			grid.add_child(child)

	container.add_child(grid)
	return container


func _create_attribute_row(abbrev: String, stat_name: String, hint: String) -> Array:
	# Label (tap for description)
	var label := Button.new()
	label.name = abbrev + "Label"
	label.flat = true
	label.text = abbrev + ":"
	label.custom_minimum_size = Vector2(45, 0)
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	# Value
	var value := Label.new()
	value.name = abbrev + "Value"
	value.text = "10"
	value.custom_minimum_size = Vector2(30, 0)

	# Plus button
	var plus_btn := Button.new()
	plus_btn.name = abbrev + "Plus"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 28)
	plus_btn.pressed.connect(_on_allocate_pressed.bind(stat_name))

	# Info text
	var info := Label.new()
	info.name = abbrev + "Info"
	info.text = hint
	info.add_theme_font_size_override("font_size", 10)
	info.modulate = Color(0.5, 0.5, 0.5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_attribute_rows[stat_name] = {
		"label": label,
		"value": value,
		"plus": plus_btn,
		"info": info
	}

	return [label, value, plus_btn, info]


func _create_resources_section() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "Resources"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.7, 0.7)
	container.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)

	# Life
	var life_row := _create_resource_row("life", "Life")
	for child in life_row:
		grid.add_child(child)

	# Mana
	var mana_row := _create_resource_row("mana", "Mana")
	for child in mana_row:
		grid.add_child(child)

	# Stamina
	var stamina_row := _create_resource_row("stamina", "Stamina")
	for child in stamina_row:
		grid.add_child(child)

	container.add_child(grid)
	return container


func _create_resource_row(stat_name: String, display_name: String) -> Array:
	# Label (tap for description)
	var label := Button.new()
	label.flat = true
	label.text = display_name + ":"
	label.custom_minimum_size = Vector2(70, 0)
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	# Value
	var value := Label.new()
	value.name = stat_name + "Value"
	value.text = "100 / 100"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_resource_labels[stat_name] = value

	return [label, value]


func _create_subtab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	var tabs := ["Offensive", "Defensive", "Utility"]
	for i in range(tabs.size()):
		var btn := Button.new()
		btn.text = tabs[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(80, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_subtab_pressed.bind(i))
		bar.add_child(btn)
		_subtab_buttons.append(btn)

	return bar


func _create_subtab_content() -> Control:
	var container := Control.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(0, 140)

	# Offensive panel
	var offensive := _create_offensive_panel()
	offensive.name = "OffensivePanel"
	container.add_child(offensive)
	_subtab_panels.append(offensive)

	# Defensive panel
	var defensive := _create_defensive_panel()
	defensive.name = "DefensivePanel"
	defensive.visible = false
	container.add_child(defensive)
	_subtab_panels.append(defensive)

	# Utility panel
	var utility := _create_utility_panel()
	utility.name = "UtilityPanel"
	utility.visible = false
	container.add_child(utility)
	_subtab_panels.append(utility)

	return container


func _create_description_box() -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 90)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	_description_title = Label.new()
	_description_title.name = "DescTitle"
	_description_title.add_theme_font_size_override("font_size", 14)
	_description_title.text = "Tap a stat for details"
	_description_title.modulate = Color(1.0, 0.9, 0.6)
	vbox.add_child(_description_title)

	_description_text = Label.new()
	_description_text.name = "DescText"
	_description_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_text.add_theme_font_size_override("font_size", 12)
	_description_text.text = ""
	_description_text.modulate = Color(0.8, 0.8, 0.8)
	_description_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_description_text)

	margin.add_child(vbox)
	container.add_child(margin)
	return container


func _create_effects_section() -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(0, 50)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Title row
	var title := Label.new()
	title.text = "Active Effects"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(title)

	# Effects icons container (horizontal row)
	_effects_container = HBoxContainer.new()
	_effects_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_effects_container)

	# "No active effects" placeholder label
	_no_effects_label = Label.new()
	_no_effects_label.text = "No active effects"
	_no_effects_label.add_theme_font_size_override("font_size", 11)
	_no_effects_label.modulate = Color(0.5, 0.5, 0.5)
	_effects_container.add_child(_no_effects_label)

	margin.add_child(vbox)
	container.add_child(margin)
	return container


func _create_effect_icon(effect_type: String, effect_data: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(40, 40)
	btn.flat = true
	btn.pressed.connect(_on_effect_tapped.bind(effect_type))

	# Container for icon visuals
	var icon_container := Control.new()
	icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon_container)

	# Background (border color indicates buff/debuff)
	var is_debuff: bool = effect_data.get("is_debuff", true)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.6, 0.1, 0.1, 0.9) if is_debuff else Color(0.1, 0.5, 0.1, 0.9)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(background)

	# Icon inner (colored based on effect type)
	var icon_inner := ColorRect.new()
	icon_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_inner.offset_left = 2
	icon_inner.offset_top = 2
	icon_inner.offset_right = -2
	icon_inner.offset_bottom = -10  # Leave room for timer bar
	icon_inner.color = _get_effect_color(effect_type)
	icon_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_inner)

	# Duration bar at bottom
	var duration: float = effect_data.get("remaining_duration", 0.0)
	var max_duration: float = effect_data.get("max_duration", duration)

	var duration_bar := ProgressBar.new()
	duration_bar.name = "DurationBar"
	duration_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	duration_bar.offset_top = -8
	duration_bar.offset_left = 2
	duration_bar.offset_right = -2
	duration_bar.custom_minimum_size.y = 6
	duration_bar.max_value = max_duration if max_duration > 0 else 1.0
	duration_bar.value = duration
	duration_bar.show_percentage = false
	duration_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(1.0, 1.0, 1.0, 0.8)
	bar_style.corner_radius_bottom_left = 1
	bar_style.corner_radius_bottom_right = 1
	duration_bar.add_theme_stylebox_override("fill", bar_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar_bg.corner_radius_bottom_left = 1
	bar_bg.corner_radius_bottom_right = 1
	duration_bar.add_theme_stylebox_override("background", bar_bg)

	icon_container.add_child(duration_bar)

	# Timer label (centered on icon)
	var timer_label := Label.new()
	timer_label.name = "TimerLabel"
	timer_label.set_anchors_preset(Control.PRESET_CENTER)
	timer_label.offset_top = -4  # Adjust for duration bar
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 11)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	timer_label.add_theme_constant_override("shadow_offset_x", 1)
	timer_label.add_theme_constant_override("shadow_offset_y", 1)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if max_duration > 0:
		timer_label.text = "%d" % int(duration) if duration >= 10 else "%.1f" % duration
	else:
		timer_label.text = "∞"  # Permanent effect

	icon_container.add_child(timer_label)

	return btn


func _get_effect_color(effect_type: String) -> Color:
	match effect_type:
		"rot":
			return Color(0.4, 0.25, 0.1)  # Brown/rot color
		"poison":
			return Color(0.2, 0.5, 0.1)  # Green
		"burn":
			return Color(0.9, 0.4, 0.1)  # Orange
		"bleed":
			return Color(0.7, 0.1, 0.1)  # Dark red
		"slow":
			return Color(0.3, 0.3, 0.7)  # Blue-ish
		"stun":
			return Color(0.8, 0.8, 0.2)  # Yellow
		"haste":
			return Color(0.2, 0.7, 0.9)  # Cyan
		"regen":
			return Color(0.2, 0.8, 0.3)  # Bright green
		"shield":
			return Color(0.6, 0.6, 0.9)  # Light blue
		_:
			return Color(0.5, 0.5, 0.5)  # Gray default


func _create_offensive_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["weapon_damage", "Weapon Damage"],
		["weapon_dps", "Weapon DPS"],
		["attack_power", "Attack Power"],
		["spell_power", "Spell Power"],
		["attack_speed", "Attack Speed"],
		["critical_chance", "Crit Chance"],
		["critical_damage", "Crit Damage"],
	]

	for stat in stats:
		var row := _create_derived_stat_row(stat[0], stat[1])
		for child in row:
			grid.add_child(child)

	scroll.add_child(grid)
	return scroll


func _create_defensive_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["armor", "Armor"],
		["magic_resistance", "Magic Resist"],
		["dodge_chance", "Dodge Chance"],
	]

	for stat in stats:
		var row := _create_derived_stat_row(stat[0], stat[1])
		for child in row:
			grid.add_child(child)

	scroll.add_child(grid)
	return scroll


func _create_utility_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["movement_speed", "Move Speed"],
		["life_regen", "Life Regen"],
		["mana_regen", "Mana Regen"],
		["stamina_regen", "Stamina Regen"],
	]

	for stat in stats:
		var row := _create_derived_stat_row(stat[0], stat[1])
		for child in row:
			grid.add_child(child)

	scroll.add_child(grid)
	return scroll


func _create_derived_stat_row(stat_name: String, display_name: String) -> Array:
	var label := Button.new()
	label.name = stat_name + "_label"
	label.flat = true
	label.text = display_name + ":"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	var value := Label.new()
	value.name = stat_name + "_value"
	value.text = "0"
	value.custom_minimum_size = Vector2(60, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_attribute_rows[stat_name] = {"value": value, "label": label}

	return [label, value]


func _connect_signals() -> void:
	PlayerStats.stats_changed.connect(refresh_display)
	PlayerStats.level_changed.connect(_on_level_changed)
	PlayerStats.experience_changed.connect(_on_experience_changed)
	PlayerStats.attribute_points_changed.connect(_on_points_changed)
	PlayerStats.skill_points_changed.connect(_on_skill_points_changed)
	PlayerStats.resource_changed.connect(_on_resource_changed)

	# Connect to TalentManager for when skill points are spent
	TalentManager.talent_points_changed.connect(_on_talent_points_changed)

	# Connect to Inventory for equipment changes (updates weapon stats)
	Inventory.equipment_changed.connect(_on_equipment_changed)

	# Connect to StatusEffectManager if player exists
	_connect_to_status_effect_manager()


func _on_equipment_changed(_slot: ItemData.EquipSlot) -> void:
	_update_derived_stats()


func _connect_to_status_effect_manager() -> void:
	if not Game or not Game.is_player_valid():
		# Try again later when player is ready
		if Game:
			Game.player_spawned.connect(_on_player_spawned_for_effects)
		return

	var player := Game.player as PlayerController
	if not player:
		return

	var manager := player.get_node_or_null("StatusEffectManager") as StatusEffectManager
	if manager:
		manager.effect_applied.connect(_on_effect_applied)
		manager.effect_removed.connect(_on_effect_removed)


func _on_player_spawned_for_effects(_player: Node2D) -> void:
	# Small delay to ensure StatusEffectManager is ready
	await get_tree().process_frame
	_connect_to_status_effect_manager()
	_update_effects()


func refresh_display() -> void:
	_update_level_display()
	_update_attributes()
	_update_resources()
	_update_derived_stats()
	_update_plus_buttons()
	_update_effects()


func _update_level_display() -> void:
	# Find nodes by traversing (since they're dynamically created)
	_find_and_update_node("LevelLabel", func(n: Label): n.text = "Level %d" % PlayerStats.level)
	_find_and_update_node("PointsLabel", func(n: Label):
		n.text = "Attr: %d" % PlayerStats.attribute_points
		n.visible = PlayerStats.attribute_points > 0
	)
	_find_and_update_node("SkillPointsLabel", func(n: Label):
		# Show available (unspent) skill points, not total
		var available := TalentManager.get_available_points()
		n.text = "Skill: %d" % available
		n.visible = available > 0
	)
	_find_and_update_node("XPBar", func(n: ProgressBar):
		n.max_value = PlayerStats.experience_for_next_level
		n.value = PlayerStats.experience
	)
	_find_and_update_node("XPLabel", func(n: Label):
		n.text = "%d / %d" % [PlayerStats.experience, PlayerStats.experience_for_next_level]
	)


func _find_and_update_node(node_name: String, update_func: Callable) -> void:
	var node := _find_node_recursive(self, node_name)
	if node:
		update_func.call(node)


func _find_node_recursive(parent: Node, node_name: String) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found := _find_node_recursive(child, node_name)
		if found:
			return found
	return null


func _update_attributes() -> void:
	_update_primary_stat("strength", PlayerStats.strength)
	_update_primary_stat("dexterity", PlayerStats.dexterity)
	_update_primary_stat("intelligence", PlayerStats.intelligence)
	_update_primary_stat("vitality", PlayerStats.vitality)
	_update_primary_stat("energy", PlayerStats.energy)
	_update_primary_stat("luck", PlayerStats.luck)


func _update_primary_stat(stat_name: String, base_value: int) -> void:
	if not _attribute_rows.has(stat_name):
		return
	var bonus := int(PlayerStats.get_equipment_bonus(stat_name))
	var total := base_value + bonus
	if bonus > 0:
		_attribute_rows[stat_name]["value"].text = "%d (+%d)" % [total, bonus]
	else:
		_attribute_rows[stat_name]["value"].text = str(total)


func _update_resources() -> void:
	if _resource_labels.has("life"):
		_resource_labels["life"].text = "%d / %d" % [int(PlayerStats.current_life), int(PlayerStats.max_life)]
	if _resource_labels.has("mana"):
		_resource_labels["mana"].text = "%d / %d" % [int(PlayerStats.current_mana), int(PlayerStats.max_mana)]
	if _resource_labels.has("stamina"):
		_resource_labels["stamina"].text = "%d / %d" % [int(PlayerStats.current_stamina), int(PlayerStats.max_stamina)]


func _update_derived_stats() -> void:
	# Offensive - Weapon stats
	var weapon_damage := Inventory.get_equipped_weapon_damage()
	var weapon_speed := Inventory.get_equipped_weapon_attack_speed()
	var attack_speed_bonus := PlayerStats.attack_speed  # Percentage bonus
	var final_attack_speed := weapon_speed * (1.0 + attack_speed_bonus / 100.0)
	var weapon_dps := weapon_damage * final_attack_speed
	_set_stat_value("weapon_damage", "%.0f" % weapon_damage)
	_set_stat_value("weapon_dps", "%.1f" % weapon_dps)

	# Offensive - Player stats
	_set_stat_value("attack_power", "%.0f" % PlayerStats.attack_power)
	_set_stat_value("spell_power", "%.0f" % PlayerStats.spell_power)
	_set_stat_value("attack_speed", "%.2f/s" % final_attack_speed)
	_set_stat_value("critical_chance", "%.1f%%" % PlayerStats.critical_chance)
	_set_stat_value("critical_damage", "%.0f%%" % PlayerStats.critical_damage)

	# Defensive
	_set_stat_value("armor", "%.0f" % PlayerStats.armor)
	_set_stat_value("magic_resistance", "%.0f" % PlayerStats.magic_resistance)
	_set_stat_value("dodge_chance", "%.1f%%" % PlayerStats.dodge_chance)

	# Utility
	_set_stat_value("movement_speed", "+%.0f%%" % PlayerStats.movement_speed)
	_set_stat_value("life_regen", "%.1f/s" % PlayerStats.life_regen)
	_set_stat_value("mana_regen", "%.1f/s" % PlayerStats.mana_regen)
	_set_stat_value("stamina_regen", "%.1f/s" % PlayerStats.stamina_regen)


func _set_stat_value(stat_name: String, text: String) -> void:
	if _attribute_rows.has(stat_name) and _attribute_rows[stat_name].has("value"):
		_attribute_rows[stat_name]["value"].text = text


func _update_plus_buttons() -> void:
	var can_allocate := PlayerStats.can_allocate_point()
	for stat_name in ["strength", "dexterity", "intelligence", "vitality", "energy", "luck"]:
		if _attribute_rows.has(stat_name) and _attribute_rows[stat_name].has("plus"):
			_attribute_rows[stat_name]["plus"].disabled = not can_allocate
			_attribute_rows[stat_name]["plus"].visible = true


## Signal handlers
func _on_level_changed(_old: int, _new: int) -> void:
	refresh_display()


func _on_experience_changed(_current: int, _required: int) -> void:
	_update_level_display()


func _on_points_changed(_points: int) -> void:
	_update_level_display()
	_update_plus_buttons()


func _on_skill_points_changed(_points: int) -> void:
	_update_level_display()


func _on_talent_points_changed(_total: int, _available: int) -> void:
	_update_level_display()


func _on_resource_changed(resource: String, _current: float, _maximum: float) -> void:
	_update_resources()


func _on_subtab_pressed(index: int) -> void:
	current_subtab = index as SubTab

	# Update button states
	for i in range(_subtab_buttons.size()):
		_subtab_buttons[i].button_pressed = (i == index)

	# Show/hide panels
	for i in range(_subtab_panels.size()):
		_subtab_panels[i].visible = (i == index)


func _on_allocate_pressed(stat_name: String) -> void:
	match stat_name:
		"strength":
			PlayerStats.allocate_strength()
		"dexterity":
			PlayerStats.allocate_dexterity()
		"intelligence":
			PlayerStats.allocate_intelligence()
		"vitality":
			PlayerStats.allocate_vitality()
		"energy":
			PlayerStats.allocate_energy()
		"luck":
			PlayerStats.allocate_luck()


func _on_stat_tapped(stat_name: String) -> void:
	if _description_title and _description_text:
		_description_title.text = stat_name.capitalize().replace("_", " ")
		_description_text.text = PlayerStats.get_stat_description(stat_name)


#===============================================================================
# EFFECTS SECTION
#===============================================================================

func _update_effects() -> void:
	if not _effects_container:
		return

	# Get current effects from StatusEffectManager
	var effects := _get_all_effects()

	# Clear existing icons
	for effect_type in _effect_icons.keys():
		if is_instance_valid(_effect_icons[effect_type]):
			_effect_icons[effect_type].queue_free()
	_effect_icons.clear()

	# Show/hide "No active effects" label
	if _no_effects_label:
		_no_effects_label.visible = effects.is_empty()

	# Create icons for each active effect
	for effect_type in effects:
		var effect_data: Dictionary = effects[effect_type]
		var icon := _create_effect_icon(effect_type, effect_data)
		_effects_container.add_child(icon)
		_effect_icons[effect_type] = icon


func _get_all_effects() -> Dictionary:
	if not Game or not Game.is_player_valid():
		return {}

	var player := Game.player as PlayerController
	if not player:
		return {}

	var manager := player.get_node_or_null("StatusEffectManager") as StatusEffectManager
	if manager:
		return manager.get_all_effect_data()

	return {}


func _update_effect_timers() -> void:
	if _effect_icons.is_empty():
		return

	var effects := _get_all_effects()

	for effect_type in _effect_icons:
		var icon: Button = _effect_icons[effect_type]
		if not is_instance_valid(icon):
			continue

		var effect_data: Dictionary = effects.get(effect_type, {})
		if effect_data.is_empty():
			continue

		var remaining: float = effect_data.get("remaining_duration", 0.0)
		var max_duration: float = effect_data.get("max_duration", 0.0)

		# Update timer label
		var timer_label := icon.find_child("TimerLabel", true, false) as Label
		if timer_label:
			if max_duration > 0:
				timer_label.text = "%d" % int(remaining) if remaining >= 10 else "%.1f" % remaining
			else:
				timer_label.text = "∞"

		# Update duration bar
		var duration_bar := icon.find_child("DurationBar", true, false) as ProgressBar
		if duration_bar:
			duration_bar.value = remaining


func _on_effect_applied(_effect_type: String, _duration: float, _show_in_hud: bool) -> void:
	_update_effects()


func _on_effect_removed(_effect_type: String) -> void:
	_update_effects()


func _on_effect_tapped(effect_type: String) -> void:
	if not _description_title or not _description_text:
		return

	# Get effect data for details
	var effects := _get_all_effects()
	var effect_data: Dictionary = effects.get(effect_type, {})

	# Build description
	var title := effect_type.capitalize()
	var description := _get_effect_description(effect_type, effect_data)

	_description_title.text = title
	_description_text.text = description


func _get_effect_description(effect_type: String, effect_data: Dictionary) -> String:
	var lines: Array[String] = []

	# Effect type (buff/debuff)
	var is_debuff: bool = effect_data.get("is_debuff", true)
	lines.append("Type: %s" % ("Debuff" if is_debuff else "Buff"))

	# Duration info
	var remaining: float = effect_data.get("remaining_duration", 0.0)
	var max_dur: float = effect_data.get("max_duration", 0.0)
	if max_dur > 0:
		lines.append("Duration: %.1fs remaining" % remaining)
	else:
		lines.append("Duration: Permanent")

	# Damage info (for DoTs)
	var damage: float = effect_data.get("damage_per_tick", 0.0)
	if damage > 0:
		var interval: float = effect_data.get("tick_interval", 1.0)
		lines.append("Damage: %.1f per %.1fs" % [damage, interval])

	# Try to get description from database
	var db_desc := _get_effect_db_description(effect_type)
	if not db_desc.is_empty():
		lines.append("")
		lines.append(db_desc)

	return "\n".join(lines)


func _get_effect_db_description(effect_type: String) -> String:
	var status_id := "status_" + effect_type
	if DatabaseLoader.status_effects.has(status_id):
		var data: Dictionary = DatabaseLoader.status_effects[status_id]
		return data.get("description", "")
	return ""
