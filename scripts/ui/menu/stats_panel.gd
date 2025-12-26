extends Control
class_name StatsPanel
## Stats Panel - Displays player attributes and derived stats
## Shows primary attributes (always visible), resources, and subtabs for derived stats

signal stat_tapped(stat_name: String)

enum SubTab { OFFENSIVE, DEFENSIVE, UTILITY }

## Subtab state
var current_subtab: SubTab = SubTab.OFFENSIVE

## UI node caches (set in _ready)
var _attribute_rows: Dictionary = {}
var _resource_bars: Dictionary = {}
var _subtab_buttons: Array[Button] = []
var _subtab_panels: Array[Control] = []


func _ready() -> void:
	_build_ui()
	_connect_signals()
	refresh_display()
	Debug.info("UI", "StatsPanel ready")


func _build_ui() -> void:
	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# === HEADER: Level and XP ===
	var header := _create_header()
	main_vbox.add_child(header)

	# === PRIMARY ATTRIBUTES (Always Visible) ===
	var attributes_section := _create_attributes_section()
	main_vbox.add_child(attributes_section)

	# === RESOURCES (Always Visible) ===
	var resources_section := _create_resources_section()
	main_vbox.add_child(resources_section)

	# === SEPARATOR ===
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# === SUBTABS ===
	var subtab_bar := _create_subtab_bar()
	main_vbox.add_child(subtab_bar)

	# === SUBTAB CONTENT ===
	var subtab_content := _create_subtab_content()
	main_vbox.add_child(subtab_content)


func _create_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)

	# Level
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.add_theme_font_size_override("font_size", 20)
	level_label.text = "Level 1"
	header.add_child(level_label)

	# XP Bar container
	var xp_container := VBoxContainer.new()
	xp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var xp_bar := ProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.custom_minimum_size = Vector2(0, 16)
	xp_bar.show_percentage = false
	xp_container.add_child(xp_bar)

	var xp_label := Label.new()
	xp_label.name = "XPLabel"
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.text = "XP: 0 / 100"
	xp_container.add_child(xp_label)

	header.add_child(xp_container)

	# Points available
	var points_label := Label.new()
	points_label.name = "PointsLabel"
	points_label.add_theme_font_size_override("font_size", 14)
	points_label.text = "Points: 0"
	points_label.modulate = Color(1.0, 0.9, 0.3)
	header.add_child(points_label)

	return header


func _create_attributes_section() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "Primary Attributes"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.8, 0.8, 0.8)
	container.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)

	# Create attribute rows
	var attributes := [
		["STR", "strength", "Physical Mastery"],
		["DEX", "dexterity", "Agility Mastery"],
		["INT", "intelligence", "Arcane Mastery"],
		["VIT", "vitality", "Life Force (+2 HP)"],
		["ENE", "energy", "Magical Capacity (+1.5 MP)"],
		["LUK", "luck", "Fortune (+1% Crit Dmg)"],
	]

	for attr in attributes:
		var row := _create_attribute_row(attr[0], attr[1], attr[2])
		for child in row:
			grid.add_child(child)

	container.add_child(grid)
	return container


func _create_attribute_row(abbrev: String, stat_name: String, hint: String) -> Array:
	# Label (tappable)
	var label := Button.new()
	label.name = abbrev + "Label"
	label.flat = true
	label.text = abbrev + ":"
	label.tooltip_text = hint
	label.custom_minimum_size = Vector2(50, 0)
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	# Value
	var value := Label.new()
	value.name = abbrev + "Value"
	value.text = "10"
	value.custom_minimum_size = Vector2(40, 0)

	# Plus button
	var plus_btn := Button.new()
	plus_btn.name = abbrev + "Plus"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(30, 30)
	plus_btn.pressed.connect(_on_allocate_pressed.bind(stat_name))

	# Info text
	var info := Label.new()
	info.name = abbrev + "Info"
	info.text = hint
	info.add_theme_font_size_override("font_size", 11)
	info.modulate = Color(0.6, 0.6, 0.6)
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
	container.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Resources"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.8, 0.8, 0.8)
	container.add_child(title)

	# Life bar
	var life_row := _create_resource_bar("life", "Life", Color(0.8, 0.2, 0.2))
	container.add_child(life_row)

	# Mana bar
	var mana_row := _create_resource_bar("mana", "Mana", Color(0.2, 0.4, 0.9))
	container.add_child(mana_row)

	# Stamina bar
	var stamina_row := _create_resource_bar("stamina", "Stamina", Color(0.2, 0.7, 0.3))
	container.add_child(stamina_row)

	return container


func _create_resource_bar(stat_name: String, display_name: String, bar_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Label (tappable)
	var label := Button.new()
	label.flat = true
	label.text = display_name
	label.custom_minimum_size = Vector2(70, 0)
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	# Progress bar
	var bar := ProgressBar.new()
	bar.name = stat_name + "Bar"
	bar.custom_minimum_size = Vector2(150, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false

	# Style the bar
	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	bar.add_theme_stylebox_override("fill", style)

	# Value label
	var value := Label.new()
	value.name = stat_name + "Value"
	value.text = "100 / 100"
	value.custom_minimum_size = Vector2(80, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	row.add_child(label)
	row.add_child(bar)
	row.add_child(value)

	_resource_bars[stat_name] = {
		"bar": bar,
		"value": value
	}

	return row


func _create_subtab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

	var tabs := ["Offensive", "Defensive", "Utility"]
	for i in range(tabs.size()):
		var btn := Button.new()
		btn.text = tabs[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(100, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_subtab_pressed.bind(i))
		bar.add_child(btn)
		_subtab_buttons.append(btn)

	return bar


func _create_subtab_content() -> Control:
	var container := Control.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(0, 120)

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
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["melee_damage", "Melee Damage"],
		["ranged_damage", "Ranged Damage"],
		["magic_damage", "Magic Damage"],
		["attack_speed", "Attack Speed"],
		["critical_chance", "Critical Chance"],
		["critical_damage", "Critical Damage"],
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
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["armor", "Armor"],
		["magic_resistance", "Magic Resistance"],
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
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)

	var stats := [
		["movement_speed", "Movement Speed"],
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
	label.pressed.connect(_on_stat_tapped.bind(stat_name))

	var value := Label.new()
	value.name = stat_name + "_value"
	value.text = "0"
	value.custom_minimum_size = Vector2(60, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_attribute_rows[stat_name] = {"value": value}

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
	var level_label := get_node_or_null("VBoxContainer/HBoxContainer/LevelLabel")
	if not level_label:
		# Find by traversing
		for child in get_children():
			if child is VBoxContainer:
				for sub in child.get_children():
					if sub is HBoxContainer:
						for node in sub.get_children():
							if node is Label and node.name == "LevelLabel":
								node.text = "Level %d" % PlayerStats.level
							elif node.name == "PointsLabel":
								node.text = "Points: %d" % PlayerStats.attribute_points
								node.visible = PlayerStats.attribute_points > 0
							elif node is VBoxContainer:
								for vnode in node.get_children():
									if vnode is ProgressBar and vnode.name == "XPBar":
										vnode.max_value = PlayerStats.experience_for_next_level
										vnode.value = PlayerStats.experience
									elif vnode is Label and vnode.name == "XPLabel":
										vnode.text = "XP: %d / %d" % [PlayerStats.experience, PlayerStats.experience_for_next_level]


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
	if _resource_bars.has("life"):
		var bar: ProgressBar = _resource_bars["life"]["bar"]
		bar.max_value = PlayerStats.max_life
		bar.value = PlayerStats.current_life
		_resource_bars["life"]["value"].text = "%d / %d" % [int(PlayerStats.current_life), int(PlayerStats.max_life)]

	if _resource_bars.has("mana"):
		var bar: ProgressBar = _resource_bars["mana"]["bar"]
		bar.max_value = PlayerStats.max_mana
		bar.value = PlayerStats.current_mana
		_resource_bars["mana"]["value"].text = "%d / %d" % [int(PlayerStats.current_mana), int(PlayerStats.max_mana)]

	if _resource_bars.has("stamina"):
		var bar: ProgressBar = _resource_bars["stamina"]["bar"]
		bar.max_value = PlayerStats.max_stamina
		bar.value = PlayerStats.current_stamina
		_resource_bars["stamina"]["value"].text = "%d / %d" % [int(PlayerStats.current_stamina), int(PlayerStats.max_stamina)]


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


func _on_resource_changed(resource: String, current: float, maximum: float) -> void:
	if _resource_bars.has(resource):
		var bar: ProgressBar = _resource_bars[resource]["bar"]
		bar.max_value = maximum
		bar.value = current
		_resource_bars[resource]["value"].text = "%d / %d" % [int(current), int(maximum)]


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
	stat_tapped.emit(stat_name)
