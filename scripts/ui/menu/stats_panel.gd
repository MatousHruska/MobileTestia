extends Control
class_name StatsPanel
## Stats Panel - Displays player attributes and derived stats
## Left side: Primary attributes + Resources (always visible)
## Right side: Subtabs for Offensive/Defensive/Utility stats

signal stat_tooltip_requested(stat_name: String, global_pos: Vector2)
signal stat_tooltip_dismissed

enum SubTab { OFFENSIVE, DEFENSIVE, UTILITY }

## Subtab state
var current_subtab: SubTab = SubTab.OFFENSIVE

## UI node caches
var _attribute_rows: Dictionary = {}
var _resource_labels: Dictionary = {}
var _subtab_buttons: Array[Button] = []
var _subtab_panels: Array[Control] = []

## Tooltip state
var _tooltip_button: Button = null


func _ready() -> void:
	_build_ui()
	_connect_signals()
	refresh_display()
	Debug.info("UI", "StatsPanel ready")


func _build_ui() -> void:
	# Main horizontal split: Left (primary) | Right (secondary)
	var main_hbox := HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 16)
	add_child(main_hbox)

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
	points_label.text = "Points: 0"
	points_label.modulate = Color(1.0, 0.9, 0.3)
	level_row.add_child(points_label)

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
	# Label (hold for tooltip)
	var label := Button.new()
	label.name = abbrev + "Label"
	label.flat = true
	label.text = abbrev + ":"
	label.custom_minimum_size = Vector2(45, 0)
	label.button_down.connect(_on_stat_pressed.bind(stat_name, label))
	label.button_up.connect(_on_stat_released)

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
	# Label (hold for tooltip)
	var label := Button.new()
	label.flat = true
	label.text = display_name + ":"
	label.custom_minimum_size = Vector2(70, 0)
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.button_down.connect(_on_stat_pressed.bind(stat_name, label))
	label.button_up.connect(_on_stat_released)

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


func _create_offensive_panel() -> Control:
	var grid := GridContainer.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["melee_damage", "Melee Damage"],
		["ranged_damage", "Ranged Damage"],
		["magic_damage", "Magic Damage"],
		["attack_speed", "Attack Speed"],
		["critical_chance", "Crit Chance"],
		["critical_damage", "Crit Damage"],
	]

	for stat in stats:
		var row := _create_derived_stat_row(stat[0], stat[1])
		for child in row:
			grid.add_child(child)

	return grid


func _create_defensive_panel() -> Control:
	var grid := GridContainer.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.columns = 2
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

	return grid


func _create_utility_panel() -> Control:
	var grid := GridContainer.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.columns = 2
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

	return grid


func _create_derived_stat_row(stat_name: String, display_name: String) -> Array:
	var label := Button.new()
	label.name = stat_name + "_label"
	label.flat = true
	label.text = display_name + ":"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.button_down.connect(_on_stat_pressed.bind(stat_name, label))
	label.button_up.connect(_on_stat_released)

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
	PlayerStats.resource_changed.connect(_on_resource_changed)


func refresh_display() -> void:
	_update_level_display()
	_update_attributes()
	_update_resources()
	_update_derived_stats()
	_update_plus_buttons()


func _update_level_display() -> void:
	# Find nodes by traversing (since they're dynamically created)
	_find_and_update_node("LevelLabel", func(n: Label): n.text = "Level %d" % PlayerStats.level)
	_find_and_update_node("PointsLabel", func(n: Label):
		n.text = "Points: %d" % PlayerStats.attribute_points
		n.visible = PlayerStats.attribute_points > 0
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
	if _attribute_rows.has("strength"):
		_attribute_rows["strength"]["value"].text = str(PlayerStats.strength)
	if _attribute_rows.has("dexterity"):
		_attribute_rows["dexterity"]["value"].text = str(PlayerStats.dexterity)
	if _attribute_rows.has("intelligence"):
		_attribute_rows["intelligence"]["value"].text = str(PlayerStats.intelligence)
	if _attribute_rows.has("vitality"):
		_attribute_rows["vitality"]["value"].text = str(PlayerStats.vitality)
	if _attribute_rows.has("energy"):
		_attribute_rows["energy"]["value"].text = str(PlayerStats.energy)
	if _attribute_rows.has("luck"):
		_attribute_rows["luck"]["value"].text = str(PlayerStats.luck)


func _update_resources() -> void:
	if _resource_labels.has("life"):
		_resource_labels["life"].text = "%d / %d" % [int(PlayerStats.current_life), int(PlayerStats.max_life)]
	if _resource_labels.has("mana"):
		_resource_labels["mana"].text = "%d / %d" % [int(PlayerStats.current_mana), int(PlayerStats.max_mana)]
	if _resource_labels.has("stamina"):
		_resource_labels["stamina"].text = "%d / %d" % [int(PlayerStats.current_stamina), int(PlayerStats.max_stamina)]


func _update_derived_stats() -> void:
	# Offensive
	_set_stat_value("melee_damage", "%.0f" % PlayerStats.melee_damage)
	_set_stat_value("ranged_damage", "%.0f" % PlayerStats.ranged_damage)
	_set_stat_value("magic_damage", "%.0f" % PlayerStats.magic_damage)
	_set_stat_value("attack_speed", "+%.1f%%" % PlayerStats.attack_speed)
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


func _on_stat_pressed(stat_name: String, button: Button) -> void:
	_tooltip_button = button
	var global_pos := button.global_position + Vector2(button.size.x + 8, 0)
	stat_tooltip_requested.emit(stat_name, global_pos)


func _on_stat_released() -> void:
	_tooltip_button = null
	stat_tooltip_dismissed.emit()
