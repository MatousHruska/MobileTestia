extends Control
class_name StatsPanel
## Stats Panel - Displays player attributes and derived stats
## Left side: Primary attributes + Resources (always visible)
## Right side: Subtabs for Offensive/Defensive/Utility stats + Description box

enum SubTab { OFFENSIVE, DEFENSIVE, UTILITY }

#===============================================================================
# RESPONSIVE CONSTANTS (percentages of panel dimensions)
#===============================================================================

const MAIN_GAP_PCT := 0.03          # 3% gap between left/right panels
const SECTION_PADDING_PCT := 0.015  # 1.5% vertical padding per section
const RIGHT_PANEL_GAP_PCT := 0.02   # 2% gap in right panel
const SUBTAB_BTN_WIDTH_PCT := 0.12  # 12% width for subtab buttons
const EFFECTS_MARGIN_PCT := 0.02    # 2% margin for effects container

## Subtab state
var current_subtab: SubTab = SubTab.OFFENSIVE

## UI node caches
var _attribute_rows: Dictionary = {}
var _resource_labels: Dictionary = {}
var _subtab_buttons: Array[Button] = []
var _subtab_panels: Array[Control] = []

## Stat detail popup
var _stat_popup: StatPopup = null
var _popup_layer: CanvasLayer = null

## Hold detection
const HOLD_THRESHOLD := 0.25  # seconds before hold is triggered
var _hold_timer: Timer = null
var _pending_stat: String = ""
var _pending_position: Vector2 = Vector2.ZERO
var _is_holding: bool = false

## Effects section
var _effects_container: HBoxContainer = null
var _effect_icons: Dictionary = {}  # effect_type -> icon button
var _no_effects_label: Label = null
var _effects_title_label: Label = null


func _ready() -> void:
	# Clip content to prevent overflow beyond panel bounds
	clip_contents = true
	_build_ui()
	_setup_popup()
	_setup_hold_timer()
	_connect_signals()
	refresh_display()
	Debug.info("UI", "StatsPanel ready")


func _setup_popup() -> void:
	# Create a CanvasLayer above CharacterMenu (layer 20) for the popup
	_popup_layer = CanvasLayer.new()
	_popup_layer.name = "StatPopupLayer"
	_popup_layer.layer = 30

	_stat_popup = StatPopup.new()
	_stat_popup.name = "StatPopup"
	_popup_layer.add_child(_stat_popup)

	call_deferred("_add_popup_to_root")


func _add_popup_to_root() -> void:
	if _popup_layer and is_inside_tree():
		get_tree().root.add_child(_popup_layer)


func _exit_tree() -> void:
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null
		_stat_popup = null


func _setup_hold_timer() -> void:
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.wait_time = HOLD_THRESHOLD
	_hold_timer.timeout.connect(_on_hold_timer_timeout)
	add_child(_hold_timer)


func _process(_delta: float) -> void:
	# Update effect timers in real-time while panel is visible
	_update_effect_timers()


## Reference to main hbox for responsive updates
var _main_hbox: HBoxContainer = null


func _build_ui() -> void:
	# Main horizontal layout: Left panel | Right panel
	_main_hbox = HBoxContainer.new()
	_main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_main_hbox)

	# Update spacing when panel resizes
	resized.connect(_update_responsive_spacing)
	call_deferred("_update_responsive_spacing")

	# === LEFT SIDE: Primary Attributes + Resources + Effects ===
	var left_panel := _create_left_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.45
	_main_hbox.add_child(left_panel)

	# === VERTICAL SEPARATOR ===
	var vsep := VSeparator.new()
	_main_hbox.add_child(vsep)

	# === RIGHT SIDE: Secondary Stats with Subtabs ===
	var right_panel := _create_right_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.55
	_main_hbox.add_child(right_panel)


func _update_responsive_spacing() -> void:
	if not _main_hbox:
		return
	var panel_width := size.x
	var panel_height := size.y

	# Update main gap between left/right panels
	var main_gap := maxi(8, int(panel_width * MAIN_GAP_PCT))
	_main_hbox.add_theme_constant_override("separation", main_gap)


func _create_left_panel() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 0)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# === HEADER: Level and XP ===
	var header := _create_section_with_padding(_create_header())
	container.add_child(header)

	container.add_child(HSeparator.new())

	# === PRIMARY ATTRIBUTES ===
	var attributes_section := _create_section_with_padding(_create_attributes_section())
	container.add_child(attributes_section)

	container.add_child(HSeparator.new())

	# === RESOURCES ===
	var resources_section := _create_section_with_padding(_create_resources_section())
	container.add_child(resources_section)

	container.add_child(HSeparator.new())

	# === ACTIVE EFFECTS (expands to fill remaining space) ===
	var effects_section := _create_section_with_padding(_create_effects_section())
	effects_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(effects_section)

	return container


## Wraps a section with percentage-based vertical padding
func _create_section_with_padding(content: Control) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)

	# Calculate padding based on expected panel height (~400-500px typical)
	var viewport_height := get_viewport().get_visible_rect().size.y
	var padding := maxi(4, int(viewport_height * SECTION_PADDING_PCT))

	# Top padding spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, padding)
	top_spacer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrapper.add_child(top_spacer)

	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrapper.add_child(content)

	# Bottom padding spacer
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, padding)
	bottom_spacer.size_flags_vertical = Control.SIZE_SHRINK_END
	wrapper.add_child(bottom_spacer)

	return wrapper


func _create_right_panel() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# === SUBTAB BAR ===
	var subtab_bar := _create_subtab_bar()
	container.add_child(subtab_bar)

	# === SUBTAB CONTENT (expands to fill remaining space) ===
	var subtab_content := _create_subtab_content()
	subtab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	points_label.text = "Attr: 0"
	points_label.modulate = UITheme.COLOR_AVAILABLE
	level_row.add_child(points_label)

	var skill_points_label := Label.new()
	skill_points_label.name = "SkillPointsLabel"
	skill_points_label.add_theme_font_size_override("font_size", 14)
	skill_points_label.text = "Skill: 0"
	skill_points_label.modulate = UITheme.COLOR_HIGHLIGHT
	level_row.add_child(skill_points_label)

	container.add_child(level_row)

	# XP bar
	var xp_bar := ProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.custom_minimum_size = Vector2(0, 14)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.show_percentage = false

	# Style the bar with outline
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UITheme.COLOR_PANEL_DARK_BG
	bg_style.set_border_width_all(UITheme.BORDER_WIDTH_NORMAL)
	bg_style.border_color = UITheme.COLOR_PANEL_BORDER
	xp_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.6, 0.9)
	xp_bar.add_theme_stylebox_override("fill", fill_style)

	container.add_child(xp_bar)

	return container


func _create_attributes_section() -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var grid := GridContainer.new()
	grid.columns = 9  # 3 attributes per row: (Label, Value, Plus) x 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)

	# Row 1: STR, DEX, INT
	# Row 2: VIT, ENE, LUK
	var rows := [
		[["STR", "strength"], ["DEX", "dexterity"], ["INT", "intelligence"]],
		[["VIT", "vitality"], ["ENE", "energy"], ["LUK", "luck"]],
	]

	for row in rows:
		for attr in row:
			var attr_row := _create_attribute_row(attr[0], attr[1])
			for child in attr_row:
				grid.add_child(child)

	container.add_child(grid)
	return container


func _create_attribute_row(abbrev: String, stat_name: String) -> Array:
	# Label (tap/hold for description popup)
	var label := Button.new()
	label.name = abbrev + "Label"
	label.flat = true
	label.text = abbrev + ":"
	label.custom_minimum_size = Vector2(40, 0)
	label.gui_input.connect(_on_stat_button_input.bind(stat_name, label))

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

	_attribute_rows[stat_name] = {
		"label": label,
		"value": value,
		"plus": plus_btn,
	}

	return [label, value, plus_btn]


func _create_resources_section() -> Control:
	# Horizontal layout: Life | Mana | Stamina
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var resources := [
		["life", "Life"],
		["mana", "Mana"],
		["stamina", "Stamina"],
	]

	for res in resources:
		var resource_col := _create_resource_column(res[0], res[1])
		hbox.add_child(resource_col)

	return hbox


func _create_resource_column(stat_name: String, display_name: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Label (tap/hold for description popup)
	var label := Button.new()
	label.flat = true
	label.text = display_name
	label.alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.gui_input.connect(_on_stat_button_input.bind(stat_name, label))
	col.add_child(label)

	# Value
	var value := Label.new()
	value.name = stat_name + "Value"
	value.text = "100 / 100"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(value)

	_resource_labels[stat_name] = value

	return col


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
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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


func _create_effects_section() -> Control:
	var container := PanelContainer.new()

	var margin := UITheme.create_margin_container(
		UITheme.MARGIN_STANDARD,
		UITheme.MARGIN_STANDARD,
		UITheme.MARGIN_TINY,
		UITheme.MARGIN_TINY
	)

	var vbox := VBoxContainer.new()
	UITheme.setup_vbox(vbox, UITheme.SEPARATION_SMALL)

	# Title row (hidden when effects are active)
	_effects_title_label = Label.new()
	_effects_title_label.text = "Active Effects"
	_effects_title_label.add_theme_font_size_override("font_size", 13)
	_effects_title_label.modulate = UITheme.COLOR_TEXT_DIM
	vbox.add_child(_effects_title_label)

	# Effects icons container (horizontal row)
	_effects_container = HBoxContainer.new()
	_effects_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_effects_container)

	# "No active effects" placeholder label
	_no_effects_label = Label.new()
	_no_effects_label.text = "No active effects"
	_no_effects_label.add_theme_font_size_override("font_size", 11)
	_no_effects_label.modulate = UITheme.COLOR_LOCKED
	_effects_container.add_child(_no_effects_label)

	margin.add_child(vbox)
	container.add_child(margin)
	return container


func _create_effect_icon(effect_type: String, effect_data: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(40, 40)
	btn.flat = true
	btn.gui_input.connect(_on_effect_button_input.bind(effect_type, btn))

	# Container for icon visuals
	var icon_container := Control.new()
	icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon_container)

	# Background (border color indicates buff/debuff)
	var is_debuff: bool = effect_data.get("is_debuff", true)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.6, 0.1, 0.1, 0.9) if is_debuff else UITheme.COLOR_LEARNED
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
	bar_bg.bg_color = UITheme.COLOR_BUTTON_BG
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
		["attack_speed", "Attack Speed"],
		["weapon_dps", "Weapon DPS"],
		["attack_power", "Attack Power"],
		["critical_chance", "Crit Chance"],
		["critical_damage", "Crit Damage"],
		["spell_power", "Spell Power"],
		["fire_spell_damage", "Fire Spell Dmg"],
		["cold_spell_damage", "Cold Spell Dmg"],
		["lightning_spell_damage", "Lightning Spell Dmg"],
		["poison_spell_damage", "Poison Spell Dmg"],
		["arcane_spell_damage", "Arcane Spell Dmg"],
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
	label.gui_input.connect(_on_stat_button_input.bind(stat_name, label))

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
	_set_stat_value("attack_speed", "%.2f/s" % final_attack_speed)
	_set_stat_value("weapon_dps", "%.1f" % weapon_dps)

	# Offensive - Physical stats
	_set_stat_value("attack_power", "%.0f" % PlayerStats.attack_power)
	_set_stat_value("critical_chance", "%.1f%%" % PlayerStats.critical_chance)
	_set_stat_value("critical_damage", "%.0f%%" % PlayerStats.critical_damage)

	# Offensive - Spell stats
	_set_stat_value("spell_power", "%.0f" % PlayerStats.spell_power)
	_set_stat_value("fire_spell_damage", "%.0f" % PlayerStats.get_equipment_bonus("fire_spell_damage"))
	_set_stat_value("cold_spell_damage", "%.0f" % PlayerStats.get_equipment_bonus("cold_spell_damage"))
	_set_stat_value("lightning_spell_damage", "%.0f" % PlayerStats.get_equipment_bonus("lightning_spell_damage"))
	_set_stat_value("poison_spell_damage", "%.0f" % PlayerStats.get_equipment_bonus("poison_spell_damage"))
	_set_stat_value("arcane_spell_damage", "%.0f" % PlayerStats.get_equipment_bonus("arcane_spell_damage"))

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


## Stat button input handling (tap vs hold)
func _on_stat_button_input(event: InputEvent, stat_name: String, _button: Button) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start hold detection
				_pending_stat = stat_name
				_pending_position = mb.global_position
				_is_holding = false
				_hold_timer.start()
			else:
				# Button released
				_hold_timer.stop()
				if _is_holding:
					# Was holding - release the popup
					if _stat_popup:
						_stat_popup.release_hold()
					_is_holding = false
				elif not _pending_stat.is_empty():
					# Quick tap - show popup (tap mode)
					_show_stat_popup(stat_name, _pending_position, false)
				_pending_stat = ""


func _on_hold_timer_timeout() -> void:
	if not _pending_stat.is_empty():
		_is_holding = true
		# Check if this is an effect or a stat
		if _pending_stat.begins_with("effect:"):
			var effect_type := _pending_stat.substr(7)  # Remove "effect:" prefix
			_show_effect_popup(effect_type, _pending_position, true)
		else:
			_show_stat_popup(_pending_stat, _pending_position, true)


func _show_stat_popup(stat_name: String, position: Vector2, hold_mode: bool) -> void:
	if not _stat_popup:
		return

	# Get stat value
	var stat_value := _get_stat_value_text(stat_name)

	# Get description from PlayerStats
	var description := PlayerStats.get_stat_description(stat_name)

	if hold_mode:
		_stat_popup.show_stat_hold(stat_name, stat_value, description, position)
	else:
		_stat_popup.show_stat(stat_name, stat_value, description, position)


func _get_stat_value_text(stat_name: String) -> String:
	match stat_name:
		# Primary attributes
		"strength":
			return str(PlayerStats.strength + int(PlayerStats.get_equipment_bonus("strength")))
		"dexterity":
			return str(PlayerStats.dexterity + int(PlayerStats.get_equipment_bonus("dexterity")))
		"intelligence":
			return str(PlayerStats.intelligence + int(PlayerStats.get_equipment_bonus("intelligence")))
		"vitality":
			return str(PlayerStats.vitality + int(PlayerStats.get_equipment_bonus("vitality")))
		"energy":
			return str(PlayerStats.energy + int(PlayerStats.get_equipment_bonus("energy")))
		"luck":
			return str(PlayerStats.luck + int(PlayerStats.get_equipment_bonus("luck")))
		# Resources
		"life":
			return "%d / %d" % [int(PlayerStats.current_life), int(PlayerStats.max_life)]
		"mana":
			return "%d / %d" % [int(PlayerStats.current_mana), int(PlayerStats.max_mana)]
		"stamina":
			return "%d / %d" % [int(PlayerStats.current_stamina), int(PlayerStats.max_stamina)]
		# Offensive
		"weapon_damage":
			return "%.0f" % Inventory.get_equipped_weapon_damage()
		"attack_speed":
			var weapon_speed := Inventory.get_equipped_weapon_attack_speed()
			var bonus := PlayerStats.attack_speed
			return "%.2f/s" % (weapon_speed * (1.0 + bonus / 100.0))
		"weapon_dps":
			var weapon_damage := Inventory.get_equipped_weapon_damage()
			var weapon_speed := Inventory.get_equipped_weapon_attack_speed()
			var bonus := PlayerStats.attack_speed
			return "%.1f" % (weapon_damage * weapon_speed * (1.0 + bonus / 100.0))
		"attack_power":
			return "%.0f" % PlayerStats.attack_power
		"critical_chance":
			return "%.1f%%" % PlayerStats.critical_chance
		"critical_damage":
			return "%.0f%%" % PlayerStats.critical_damage
		"spell_power":
			return "%.0f" % PlayerStats.spell_power
		"fire_spell_damage", "cold_spell_damage", "lightning_spell_damage", "poison_spell_damage", "arcane_spell_damage":
			return "%.0f" % PlayerStats.get_equipment_bonus(stat_name)
		# Defensive
		"armor":
			return "%.0f" % PlayerStats.armor
		"magic_resistance":
			return "%.0f" % PlayerStats.magic_resistance
		"dodge_chance":
			return "%.1f%%" % PlayerStats.dodge_chance
		# Utility
		"movement_speed":
			return "+%.0f%%" % PlayerStats.movement_speed
		"life_regen":
			return "%.1f/s" % PlayerStats.life_regen
		"mana_regen":
			return "%.1f/s" % PlayerStats.mana_regen
		"stamina_regen":
			return "%.1f/s" % PlayerStats.stamina_regen
		_:
			return ""


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

	# Show/hide title and "No active effects" label based on whether effects exist
	var has_effects := not effects.is_empty()
	if _effects_title_label:
		_effects_title_label.visible = not has_effects
	if _no_effects_label:
		_no_effects_label.visible = not has_effects

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


## Effect button input handling (tap vs hold)
func _on_effect_button_input(event: InputEvent, effect_type: String, _button: Button) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start hold detection (reusing the same timer)
				_pending_stat = "effect:" + effect_type
				_pending_position = mb.global_position
				_is_holding = false
				_hold_timer.start()
			else:
				# Button released
				_hold_timer.stop()
				if _is_holding:
					# Was holding - release the popup
					if _stat_popup:
						_stat_popup.release_hold()
					_is_holding = false
				elif _pending_stat == "effect:" + effect_type:
					# Quick tap - show popup (tap mode)
					_show_effect_popup(effect_type, _pending_position, false)
				_pending_stat = ""


func _show_effect_popup(effect_type: String, position: Vector2, hold_mode: bool) -> void:
	if not _stat_popup:
		return

	# Get effect data for details
	var effects := _get_all_effects()
	var effect_data: Dictionary = effects.get(effect_type, {})

	# Build description
	var description := _get_effect_description(effect_type, effect_data)

	# Get remaining duration as value text
	var remaining: float = effect_data.get("remaining_duration", 0.0)
	var max_dur: float = effect_data.get("max_duration", 0.0)
	var value_text := ""
	if max_dur > 0:
		value_text = "%.1fs remaining" % remaining
	elif max_dur == 0 and remaining > 0:
		value_text = "Permanent"

	if hold_mode:
		_stat_popup.show_stat_hold(effect_type, value_text, description, position)
	else:
		_stat_popup.show_stat(effect_type, value_text, description, position)


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
