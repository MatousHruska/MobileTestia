extends VBoxContainer
class_name SkillsPanel
## SkillsPanel - Main UI for the talent tree and skill system
##
## Layout (based on SVG design):
## - Left side: Talent Tree with 3 tabs (Noble Legacy, Mountain Hunter, Spirit Whisperer)
## - Right top: Skillbook grid showing learned active abilities
## - Right middle: Skill/Talent description panel with icon
## - Right bottom: Skill Bind UI (1 main + 5 secondary slots)

#===============================================================================
# SIGNALS
#===============================================================================

signal talent_selected(talent_id: String)
signal skill_selected(talent_id: String)
signal binding_mode_entered
signal binding_mode_exited

#===============================================================================
# CONSTANTS - Responsive (percentages of panel dimensions)
#===============================================================================

## Sizing percentages (relative to panel width/height)
const TREE_WIDTH_PCT := 0.50           ## Tree panel takes ~50% of width
const TALENT_NODE_SIZE_PCT := 0.065    ## Node size ~6.5% of panel width
const TALENT_SPACING_X_PCT := 0.02     ## Horizontal spacing ~2%
const TALENT_SPACING_Y_PCT := 0.05     ## Vertical spacing ~5%
const ROW_HEIGHT_PCT := 0.12           ## Row height ~12% of panel height
const SKILLBOOK_CELL_PCT := 0.065      ## Skillbook cell ~6.5% of panel width

## Fixed values (counts, not sizes)
const SKILLBOOK_COLS := 6              ## Columns in skillbook grid
const SKILLBOOK_MIN_SLOTS := 30        ## Total slots (5 rows x 6 columns)

## Minimum pixel sizes (for accessibility)
const MIN_TALENT_SIZE := 40            ## Minimum touch target
const MIN_CELL_SIZE := 40              ## Minimum touch target

## Bind slot sizing
const BIND_MAIN_SLOT_PCT := 0.08       ## Main bind slot ~8% of panel width
const BIND_SLOT_PCT := 0.065           ## Secondary bind slot ~6.5% of panel width
const MIN_BIND_SIZE := 36              ## Minimum bind slot size
const BIND_PANEL_HEIGHT_PCT := 0.18    ## Active Skills panel ~18% of panel height
const MIN_BIND_PANEL_HEIGHT := 70      ## Minimum height for Active Skills panel

#===============================================================================
# COMPUTED SIZES (call these functions to get actual pixel values)
#===============================================================================

func _get_tree_width() -> float:
	return maxf(200, size.x * TREE_WIDTH_PCT)

func _get_talent_node_size() -> float:
	return maxf(MIN_TALENT_SIZE, size.x * TALENT_NODE_SIZE_PCT)

func _get_talent_spacing() -> Vector2:
	return Vector2(
		maxf(8, size.x * TALENT_SPACING_X_PCT),
		maxf(12, size.y * TALENT_SPACING_Y_PCT)
	)

func _get_row_height() -> float:
	return maxf(48, size.y * ROW_HEIGHT_PCT)

func _get_skillbook_cell_size() -> float:
	return maxf(MIN_CELL_SIZE, size.x * SKILLBOOK_CELL_PCT)

func _get_bind_main_slot_size() -> float:
	return maxf(MIN_BIND_SIZE + 8, size.x * BIND_MAIN_SLOT_PCT)

func _get_bind_slot_size() -> float:
	return maxf(MIN_BIND_SIZE, size.x * BIND_SLOT_PCT)

func _get_bind_panel_height() -> float:
	return maxf(MIN_BIND_PANEL_HEIGHT, size.y * BIND_PANEL_HEIGHT_PCT)


## Colors - use UITheme global singleton for shared colors

#===============================================================================
# STATE
#===============================================================================

var current_tree_id: String = ""
var selected_talent_id: String = ""
var selected_from_skillbook: bool = false
var binding_mode: bool = false

## Drag and drop state
var _is_dragging: bool = false
var _drag_talent_id: String = ""
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_preview: Control = null
var _drag_source_slot: int = -1  # -1 if from skillbook, 0-5 if from bind slot
const DRAG_THRESHOLD: float = 10.0  ## Pixels to move before drag starts

#===============================================================================
# UI REFERENCES
#===============================================================================

## Main containers
var _left_panel: PanelContainer
var _right_panel: VBoxContainer

## Talent tree
var _tree_tabs: HBoxContainer
var _tree_scroll: ScrollContainer
var _tree_content: Control  # Container for nodes and arrow layer
var _tree_rows: VBoxContainer  # Holds the talent row containers
var _arrow_layer: Control  # For drawing dependency arrows
var _points_label: Label
var _points_tree_label: Label

## Skillbook
var _skillbook_header: Label
var _skillbook_grid: GridContainer

## Action buttons
var _button1: Button
var _button2: Button

## Skill bind UI
var _bind_panel: PanelContainer
var _bind_main_slot: Button
var _bind_slots: Array[Button] = []

## Talent nodes (talent_id -> Button)
var _talent_nodes: Dictionary = {}

## Skillbook slots (index -> Button)
var _skillbook_slots: Array[Button] = []

## Skill popup for showing talent/skill details
var _skill_popup: SkillPopup = null

## Canvas layer for popup (above CharacterMenu's layer 20)
var _popup_layer: CanvasLayer = null

## Store last tap position for popup positioning
var _last_tap_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_setup_popup()
	refresh()


func _setup_popup() -> void:
	# Create a CanvasLayer above CharacterMenu (layer 20) for the popup
	_popup_layer = CanvasLayer.new()
	_popup_layer.name = "SkillPopupLayer"
	_popup_layer.layer = 30  # Above CharacterMenu's layer 20

	# Create the skill popup
	_skill_popup = SkillPopup.new()
	_skill_popup.name = "SkillPopup"
	_popup_layer.add_child(_skill_popup)

	# Add layer to root
	call_deferred("_add_popup_to_root")


func _add_popup_to_root() -> void:
	if _popup_layer and is_inside_tree():
		get_tree().root.add_child(_popup_layer)


func _exit_tree() -> void:
	# Clean up popup layer when panel is removed
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null
		_skill_popup = null


#===============================================================================
# UI BUILDING
#===============================================================================

func _build_ui() -> void:
	# Main horizontal split
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 8)
	add_child(main_hbox)

	# Left margin wrapper for talent tree (50% width)
	var left_margin := _create_percentage_margin()
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_stretch_ratio = TREE_WIDTH_PCT
	main_hbox.add_child(left_margin)

	# Build left panel (Talent Tree)
	_build_talent_tree_panel(left_margin)

	# Right margin wrapper for skillbook/description (50% width)
	var right_margin := _create_percentage_margin()
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.size_flags_stretch_ratio = 1.0 - TREE_WIDTH_PCT
	main_hbox.add_child(right_margin)

	# Build right panel (Skillbook + Description + Bind UI)
	_build_right_panel(right_margin)


func _create_percentage_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	# Use ~2% of typical screen width (around 8-12 pixels)
	var side_margin := 10
	margin.add_theme_constant_override("margin_left", side_margin)
	margin.add_theme_constant_override("margin_right", side_margin)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	return margin


func _create_section_header(text: String) -> Label:
	return UITheme.create_section_header(text)


func _build_talent_tree_panel(parent: Control) -> void:
	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(outer_vbox, UITheme.SEPARATION_SMALL)
	parent.add_child(outer_vbox)

	# Talents header (outside the panel, like Skillbook)
	var header := UITheme.create_section_header("Talents")
	outer_vbox.add_child(header)

	# Main panel with border
	_left_panel = PanelContainer.new()
	_left_panel.custom_minimum_size.x = _get_tree_width()
	_left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_left_panel)

	# Style with border
	_left_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := UITheme.create_margin_container()
	_left_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	UITheme.setup_vbox(vbox, 10)
	margin.add_child(vbox)

	# Tree tabs container (horizontal row, names can wrap)
	_tree_tabs = HBoxContainer.new()
	UITheme.setup_hbox(_tree_tabs, UITheme.SEPARATION_SMALL)
	_tree_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tree_tabs)

	# Scrollable tree content with top padding
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_tree_scroll)

	# Container that holds both rows and arrow layer
	_tree_content = Control.new()
	_tree_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.add_child(_tree_content)

	# VBoxContainer for talent rows
	_tree_rows = VBoxContainer.new()
	_tree_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_rows.add_theme_constant_override("separation", 20)  # Prominent row padding
	_tree_rows.resized.connect(_on_tree_rows_resized)
	_tree_content.add_child(_tree_rows)

	# Arrow layer on top of rows (draws dependency lines)
	_arrow_layer = Control.new()
	_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_layer.draw.connect(_draw_dependency_arrows)
	_tree_content.add_child(_arrow_layer)

	# Static points section at bottom (outside scroll)
	_build_points_section(vbox)


func _build_points_section(parent: Control) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)

	# Style with border (darker variant)
	panel.add_theme_stylebox_override("panel", UITheme.create_panel_dark_style())

	var margin := UITheme.create_margin_container(
		UITheme.MARGIN_SMALL,
		UITheme.MARGIN_SMALL,
		UITheme.MARGIN_TINY,
		UITheme.MARGIN_TINY
	)
	panel.add_child(margin)

	# Horizontal layout: Available on left, Invested on right
	var hbox := HBoxContainer.new()
	margin.add_child(hbox)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 10)
	_points_label.add_theme_color_override("font_color", UITheme.COLOR_AVAILABLE)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_points_label)

	_points_tree_label = Label.new()
	_points_tree_label.add_theme_font_size_override("font_size", 10)
	_points_tree_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_points_tree_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_points_tree_label)


func _build_right_panel(parent: Control) -> void:
	_right_panel = VBoxContainer.new()
	_right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_panel.clip_contents = true  # Prevent content from stretching window
	parent.add_child(_right_panel)

	# Skillbook header (centered)
	_skillbook_header = _create_section_header("Skillbook")
	_right_panel.add_child(_skillbook_header)

	# Skillbook container with border
	var skillbook_panel := PanelContainer.new()
	# Height shows ~2.5 rows to imply scrolling
	var cell_size := _get_skillbook_cell_size()
	var visible_height := int(2.5 * (cell_size + 4)) + 16
	skillbook_panel.custom_minimum_size = Vector2(0, visible_height)
	_right_panel.add_child(skillbook_panel)

	# Style with border
	skillbook_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var skillbook_margin := UITheme.create_margin_container()
	skillbook_panel.add_child(skillbook_margin)

	var skillbook_scroll := ScrollContainer.new()
	skillbook_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skillbook_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skillbook_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skillbook_margin.add_child(skillbook_scroll)

	# Center container for the grid
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skillbook_scroll.add_child(center)

	_skillbook_grid = GridContainer.new()
	_skillbook_grid.columns = SKILLBOOK_COLS
	UITheme.setup_grid(_skillbook_grid)
	center.add_child(_skillbook_grid)

	# Build skill bind UI (below skillbook)
	_build_skill_bind_ui()

	# Build action buttons
	_build_action_buttons()


func _build_action_buttons() -> void:
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 8)
	_right_panel.add_child(btn_hbox)

	_button1 = Button.new()
	_button1.text = "Learn"
	_button1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button1.pressed.connect(_on_button1_pressed)
	btn_hbox.add_child(_button1)

	_button2 = Button.new()
	_button2.text = "Cancel"
	_button2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button2.pressed.connect(_on_button2_pressed)
	btn_hbox.add_child(_button2)

	# Initially hide buttons
	_button1.visible = false
	_button2.visible = false


func _build_skill_bind_ui() -> void:
	# Active Skills header
	var label := _create_section_header("Active Skills")
	_right_panel.add_child(label)

	_bind_panel = PanelContainer.new()
	_bind_panel.custom_minimum_size = Vector2(0, _get_bind_panel_height())
	_right_panel.add_child(_bind_panel)

	# Style with border
	_bind_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())

	var margin := UITheme.create_margin_container(
		UITheme.MARGIN_STANDARD,
		UITheme.MARGIN_STANDARD,
		UITheme.MARGIN_SMALL,
		UITheme.MARGIN_SMALL
	)
	_bind_panel.add_child(margin)

	# Simple horizontal row
	var row := HBoxContainer.new()
	UITheme.setup_hbox(row, UITheme.MARGIN_SMALL)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	# Main slot (attack button, first and bigger)
	_bind_main_slot = _create_bind_slot(0, true)
	row.add_child(_bind_main_slot)

	# Secondary slots in a row to the right
	for i in range(5):
		var slot := _create_bind_slot(i + 1, false)
		row.add_child(slot)
		_bind_slots.append(slot)


func _create_bind_slot(index: int, is_main: bool) -> Button:
	var slot_size := _get_bind_main_slot_size() if is_main else _get_bind_slot_size()
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(slot_size, slot_size)
	# Prevent HBoxContainer from stretching the button vertically
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_theme_font_size_override("font_size", 10)
	slot.set_meta("slot_index", index)
	slot.set_meta("is_main", is_main)

	# Use gui_input for drag detection
	slot.gui_input.connect(_on_bind_slot_input.bind(index, slot))

	# Style - square corners
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.2, 0.2, 0.25, 0.8)
	stylebox.border_color = UITheme.COLOR_HIGHLIGHT if is_main else Color(0.55, 1.0, 0.98, 0.7)
	stylebox.set_border_width_all(2 if is_main else 1)
	stylebox.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", stylebox)

	return slot


#===============================================================================
# SIGNAL CONNECTIONS
#===============================================================================

func _connect_signals() -> void:
	TalentManager.talent_learned.connect(_on_talent_learned)
	TalentManager.talent_points_changed.connect(_on_talent_points_changed)
	TalentManager.skillbook_updated.connect(_on_skillbook_updated)
	TalentManager.skill_bound.connect(_on_skill_bound)
	TalentManager.skill_unbound.connect(_on_skill_unbound)
	PlayerStats.skill_points_changed.connect(_on_skill_points_changed)
	Inventory.equipment_changed.connect(_on_equipment_changed)


#===============================================================================
# REFRESH / UPDATE
#===============================================================================

func refresh() -> void:
	_build_tree_tabs()
	_refresh_talent_tree()
	_refresh_skillbook()
	_refresh_bind_slots()
	_update_points_label()
	_update_buttons()


func _build_tree_tabs() -> void:
	# Clear existing tabs
	for child in _tree_tabs.get_children():
		child.queue_free()

	var trees := DatabaseLoader.get_all_talent_trees()
	if trees.is_empty():
		return

	# Set default tree if not set
	if current_tree_id.is_empty():
		current_tree_id = trees[0].get("id", "")

	for tree_data in trees:
		var tab := Button.new()
		tab.text = tree_data.get("name", "Unknown")
		tab.toggle_mode = true
		tab.button_pressed = (tree_data.get("id", "") == current_tree_id)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 36)  # Taller for two-line text
		tab.clip_text = false
		tab.add_theme_font_size_override("font_size", 10)
		tab.pressed.connect(_on_tree_tab_pressed.bind(tree_data.get("id", "")))

		# Style with outline
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18) if not tab.button_pressed else Color(0.25, 0.25, 0.3)
		style.border_color = Color(0.4, 0.4, 0.45) if not tab.button_pressed else UITheme.COLOR_AVAILABLE
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		tab.add_theme_stylebox_override("normal", style)

		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.25, 0.25, 0.3)
		pressed_style.border_color = UITheme.COLOR_AVAILABLE
		pressed_style.set_border_width_all(1)
		pressed_style.set_corner_radius_all(3)
		tab.add_theme_stylebox_override("pressed", pressed_style)

		_tree_tabs.add_child(tab)


func _refresh_talent_tree() -> void:
	# Clear existing rows
	for child in _tree_rows.get_children():
		child.queue_free()
	_talent_nodes.clear()

	if current_tree_id.is_empty():
		return

	# Build rows
	var max_row := TalentManager.get_max_row(current_tree_id)
	for row in range(1, max_row + 1):
		_build_talent_row(row)


## Called when tree rows container resizes - sync arrow layer
func _on_tree_rows_resized() -> void:
	if not _arrow_layer or not _tree_rows:
		return
	# Match arrow layer size to rows container
	_tree_content.custom_minimum_size = _tree_rows.size
	_arrow_layer.size = _tree_rows.size
	_arrow_layer.queue_redraw()


func _build_talent_row(row: int) -> void:
	var row_container := HBoxContainer.new()
	row_container.custom_minimum_size.y = _get_row_height()
	row_container.add_theme_constant_override("separation", 8)
	row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_tree_rows.add_child(row_container)

	# Get talents for this row
	var talents := TalentManager.get_talents_at_row(current_tree_id, row)

	# Create 3 columns (some may be empty)
	for col in range(1, 4):
		var found := false
		for talent in talents:
			if talent.column == col:
				var node := _create_talent_node(talent)
				row_container.add_child(node)
				_talent_nodes[talent.id] = node
				found = true
				break

		if not found:
			# Empty spacer
			var spacer := Control.new()
			var node_size := _get_talent_node_size()
			spacer.custom_minimum_size = Vector2(node_size, node_size)
			row_container.add_child(spacer)


func _create_talent_node(talent: TalentData) -> Control:
	# Container for square node
	var container := Control.new()
	var node_size := _get_talent_node_size()
	container.custom_minimum_size = Vector2(node_size, node_size)

	# Main button (square)
	var node := Button.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.toggle_mode = true
	# Use gui_input instead of pressed to capture tap position
	node.gui_input.connect(_on_talent_node_input.bind(talent.id, node))
	node.set_meta("talent_id", talent.id)
	node.set_meta("is_pressed", false)
	container.add_child(node)

	# Points label in bottom right corner
	var points_label := Label.new()
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	points_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	points_label.add_theme_font_size_override("font_size", 9)
	points_label.set_meta("points_label", true)
	container.add_child(points_label)

	# Name label (abbreviated)
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.set_meta("name_label", true)
	container.add_child(name_label)

	# Update visual state
	_update_talent_node_visual(container, talent)

	return container


func _update_talent_node_visual(container: Control, talent: TalentData) -> void:
	var invested := TalentManager.get_invested_points(talent.id)
	var can_learn := TalentManager.can_learn_talent(talent.id)
	var is_selected := (talent.id == selected_talent_id)

	# Determine color
	var color: Color
	if is_selected:
		color = UITheme.COLOR_SELECTED
	elif invested >= talent.max_points:
		color = UITheme.COLOR_MAXED
	elif invested > 0:
		color = UITheme.COLOR_LEARNED
	elif can_learn:
		color = UITheme.COLOR_AVAILABLE
	else:
		color = UITheme.COLOR_LOCKED

	# Find the button child
	var node: Button = null
	var points_label: Label = null
	var name_label: Label = null
	for child in container.get_children():
		if child is Button:
			node = child
		elif child is Label and child.has_meta("points_label"):
			points_label = child
		elif child is Label and child.has_meta("name_label"):
			name_label = child

	if not node:
		return

	# Create stylebox (square corners)
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.15, 0.15, 0.2) if invested == 0 else Color(0.2, 0.25, 0.3)
	stylebox.border_color = color
	stylebox.set_border_width_all(2 if not is_selected else 3)
	stylebox.set_corner_radius_all(4)
	node.add_theme_stylebox_override("normal", stylebox)
	node.add_theme_stylebox_override("pressed", stylebox)

	# Update points label
	if points_label:
		points_label.text = "%d/%d" % [invested, talent.max_points]
		points_label.add_theme_color_override("font_color", color)

	# Update name label (abbreviated to 2-3 chars)
	if name_label:
		name_label.text = talent.talent_name.substr(0, 3).to_upper()
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	# Tooltip
	node.tooltip_text = "%s\n%s" % [talent.talent_name, talent.description]


## Draw dependency arrows between talents with prerequisites
func _draw_dependency_arrows() -> void:
	if current_tree_id.is_empty():
		return

	var arrow_color := Color(0.6, 0.6, 0.65, 0.8)
	var arrow_color_met := Color(0.5, 1.0, 0.5, 0.9)  # Green when prereq is maxed
	var line_width := 2.0
	var arrow_size := 8.0

	# Iterate through all talents in current tree
	var talents := TalentManager.get_talents_for_tree(current_tree_id)
	for talent in talents:
		if not talent.has_prerequisites():
			continue

		# Get the node for this talent
		var target_node := _talent_nodes.get(talent.id) as Control
		if not target_node:
			continue

		# Draw arrow from each prerequisite to this talent
		for prereq_id in talent.prerequisite_ids:
			var prereq_node := _talent_nodes.get(prereq_id) as Control
			if not prereq_node:
				continue

			# Calculate positions relative to arrow layer
			var start_pos := prereq_node.get_global_position() - _arrow_layer.get_global_position()
			var end_pos := target_node.get_global_position() - _arrow_layer.get_global_position()

			# Center horizontally, connect bottom of prereq to top of target
			start_pos += Vector2(prereq_node.size.x / 2, prereq_node.size.y)
			end_pos += Vector2(target_node.size.x / 2, 0)

			# Determine if prerequisite is met (maxed)
			var prereq_talent := TalentManager.get_talent(prereq_id)
			var invested := TalentManager.get_invested_points(prereq_id)
			var is_met := prereq_talent and invested >= prereq_talent.max_points

			var color := arrow_color_met if is_met else arrow_color

			# Draw line
			_arrow_layer.draw_line(start_pos, end_pos, color, line_width, true)

			# Draw arrow head at the end
			_draw_arrow_head(end_pos, start_pos, color, arrow_size)


## Draw arrow head pointing from start towards end
func _draw_arrow_head(tip: Vector2, from: Vector2, color: Color, size: float) -> void:
	var direction := (tip - from).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)

	var base := tip - direction * size
	var left := base + perpendicular * (size * 0.5)
	var right := base - perpendicular * (size * 0.5)

	var points := PackedVector2Array([tip, left, right])
	_arrow_layer.draw_polygon(points, PackedColorArray([color, color, color]))


func _refresh_skillbook() -> void:
	# Clear existing slots
	for child in _skillbook_grid.get_children():
		child.queue_free()
	_skillbook_slots.clear()

	# Get learned active talents
	var active_talents := TalentManager.get_skillbook_talents()

	# Create slots for learned talents
	for i in range(active_talents.size()):
		var talent := active_talents[i]
		var slot := _create_skillbook_slot(talent)
		_skillbook_grid.add_child(slot)
		_skillbook_slots.append(slot)

	# Add empty slots to fill minimum grid
	var empty_count := maxi(0, SKILLBOOK_MIN_SLOTS - active_talents.size())
	for i in range(empty_count):
		var empty_slot := _create_empty_skillbook_slot()
		_skillbook_grid.add_child(empty_slot)


func _create_skillbook_slot(talent: TalentData) -> Button:
	var slot := Button.new()
	var cell_size := _get_skillbook_cell_size()
	slot.custom_minimum_size = Vector2(cell_size, cell_size)
	slot.toggle_mode = true
	slot.text = talent.talent_name.substr(0, 2).to_upper()
	slot.add_theme_font_size_override("font_size", 12)

	# Check weapon requirement
	var weapon_met := _is_weapon_requirement_met(talent)
	if not weapon_met:
		var req_name := _get_weapon_category_display_name(talent.required_weapon_category)
		slot.tooltip_text = talent.talent_name + "\n[Requires: " + req_name + "]"
	else:
		slot.tooltip_text = talent.talent_name + "\n[Hold and drag to bind]"

	# Use gui_input for drag detection instead of pressed signal
	slot.gui_input.connect(_on_skillbook_slot_input.bind(talent.id, slot))

	# Visual state
	var is_bound := TalentManager.is_talent_bound(talent.id)
	var is_selected := (talent.id == selected_talent_id and selected_from_skillbook)

	var stylebox := StyleBoxFlat.new()

	# Gray out if weapon requirement not met
	if not weapon_met:
		stylebox.bg_color = Color(0.15, 0.15, 0.15, 0.6)
		stylebox.border_color = UITheme.COLOR_LOCKED
		slot.modulate = Color(0.6, 0.6, 0.6, 0.8)
	else:
		stylebox.bg_color = Color(0.2, 0.25, 0.35) if is_bound else Color(0.15, 0.15, 0.2)
		stylebox.border_color = UITheme.COLOR_SELECTED if is_selected else (UITheme.COLOR_HIGHLIGHT if is_bound else UITheme.COLOR_LEARNED)

	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", stylebox)

	# Store metadata for drag detection
	slot.set_meta("talent_id", talent.id)
	slot.set_meta("press_pos", Vector2.ZERO)
	slot.set_meta("is_pressed", false)

	return slot


func _create_empty_skillbook_slot() -> Control:
	var slot := Control.new()
	var cell_size := _get_skillbook_cell_size()
	slot.custom_minimum_size = Vector2(cell_size, cell_size)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UITheme.create_empty_slot_style())
	slot.add_child(panel)

	return slot


## Handle input on skillbook slots for drag detection
func _on_skillbook_slot_input(event: InputEvent, talent_id: String, slot: Button) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			# Start potential drag
			slot.set_meta("press_pos", event.position)
			slot.set_meta("is_pressed", true)
			# Store global tap position for popup
			_last_tap_pos = slot.get_global_position() + event.position
		else:
			# Release - if we didn't drag, treat as click
			if slot.get_meta("is_pressed", false) and not _is_dragging:
				_on_skillbook_slot_pressed(talent_id)
			slot.set_meta("is_pressed", false)

	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and slot.get_meta("is_pressed", false):
		# Check if we should start dragging
		var press_pos: Vector2 = slot.get_meta("press_pos", Vector2.ZERO)
		var event_pos: Vector2 = event.position
		var delta: Vector2 = event_pos - press_pos

		if delta.length() > DRAG_THRESHOLD and not _is_dragging:
			slot.set_meta("is_pressed", false)
			_start_drag(talent_id, slot.get_global_position() + event_pos)


func _refresh_bind_slots() -> void:
	# Update main slot
	_update_bind_slot_visual(_bind_main_slot, 0)

	# Update secondary slots
	for i in range(_bind_slots.size()):
		_update_bind_slot_visual(_bind_slots[i], i + 1)


func _update_bind_slot_visual(slot: Button, index: int) -> void:
	var talent := TalentManager.get_bound_talent(index)
	var is_main := (index == 0)

	# Check weapon requirement
	var weapon_met := true
	if talent:
		weapon_met = _is_weapon_requirement_met(talent)
		slot.text = talent.talent_name.substr(0, 2).to_upper()
		if not weapon_met:
			var req_name := _get_weapon_category_display_name(talent.required_weapon_category)
			slot.tooltip_text = talent.talent_name + "\n[Requires: " + req_name + "]"
		else:
			slot.tooltip_text = talent.talent_name
	else:
		slot.text = "+" if is_main else ""
		slot.tooltip_text = "Main Slot" if is_main else "Slot %d" % index

	# Highlight in binding mode
	var stylebox := StyleBoxFlat.new()

	# Gray out if weapon requirement not met
	if talent and not weapon_met:
		stylebox.bg_color = Color(0.15, 0.15, 0.15, 0.6)
		stylebox.border_color = UITheme.COLOR_LOCKED
		stylebox.set_border_width_all(2)
		slot.modulate = Color(0.6, 0.6, 0.6, 0.8)
	else:
		stylebox.bg_color = Color(0.2, 0.2, 0.25, 0.8) if not talent else Color(0.25, 0.3, 0.4, 0.9)
		slot.modulate = Color(1.0, 1.0, 1.0, 1.0)

		if binding_mode:
			stylebox.border_color = UITheme.COLOR_HIGHLIGHT
			stylebox.set_border_width_all(3)
		else:
			stylebox.border_color = UITheme.COLOR_HIGHLIGHT if is_main else Color(0.55, 1.0, 0.98, 0.5)
			stylebox.set_border_width_all(2)

	stylebox.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", stylebox)


func _update_points_label() -> void:
	var available := TalentManager.get_available_points()
	var tree_invested := TalentManager.get_tree_invested_points(current_tree_id)
	_points_label.text = "Available: %d" % available
	_points_tree_label.text = "Invested in tree: %d" % tree_invested


func _update_buttons() -> void:
	# Hide buttons if nothing selected or selected from skillbook
	# (skillbook uses drag-and-drop for binding)
	if selected_talent_id.is_empty() or selected_from_skillbook:
		_button1.visible = false
		_button2.visible = false
		return

	# Selected from talent tree - show Learn button
	var can_learn := TalentManager.can_learn_talent(selected_talent_id)
	_button1.visible = true
	_button1.text = "Learn"
	_button1.disabled = not can_learn
	_button2.visible = false

	if not can_learn:
		var reason := TalentManager.get_learn_block_reason(selected_talent_id)
		_button1.tooltip_text = reason


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_tree_tab_pressed(tree_id: String) -> void:
	current_tree_id = tree_id
	selected_talent_id = ""
	selected_from_skillbook = false

	# Update tab visuals
	for child in _tree_tabs.get_children():
		if child is Button:
			child.button_pressed = false

	_refresh_talent_tree()
	_update_points_label()
	_update_buttons()


## Handle input on talent nodes for tap position tracking
func _on_talent_node_input(event: InputEvent, talent_id: String, node: Button) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			node.set_meta("is_pressed", true)
			# Store global tap position for popup
			_last_tap_pos = node.get_global_position() + event.position
		else:
			# Release - treat as click
			if node.get_meta("is_pressed", false):
				_on_talent_node_pressed(talent_id)
			node.set_meta("is_pressed", false)


func _on_talent_node_pressed(talent_id: String) -> void:
	selected_talent_id = talent_id
	selected_from_skillbook = false
	binding_mode = false

	# Update all node visuals
	for id in _talent_nodes:
		var talent := TalentManager.get_talent(id)
		if talent:
			_update_talent_node_visual(_talent_nodes[id], talent)

	_update_buttons()
	talent_selected.emit(talent_id)

	# Show the popup at tap position
	if _skill_popup:
		_skill_popup.show_talent(talent_id, _last_tap_pos)


func _on_skillbook_slot_pressed(talent_id: String) -> void:
	selected_talent_id = talent_id
	selected_from_skillbook = true

	if binding_mode:
		# Cancel binding mode
		binding_mode = false
		binding_mode_exited.emit()

	_refresh_skillbook()
	_refresh_bind_slots()
	_update_buttons()
	skill_selected.emit(talent_id)

	# Show the popup at tap position
	if _skill_popup:
		_skill_popup.show_talent(talent_id, _last_tap_pos)


func _on_bind_slot_input(event: InputEvent, slot_index: int, slot: Button) -> void:
	var talent := TalentManager.get_bound_talent(slot_index)

	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.pressed:
			# Start potential drag
			slot.set_meta("press_pos", event.position)
			slot.set_meta("is_pressed", true)
			# Store global tap position for popup
			_last_tap_pos = slot.get_global_position() + event.position
		else:
			# Release - if we didn't drag, treat as click
			if slot.get_meta("is_pressed", false) and not _is_dragging:
				_on_bind_slot_pressed(slot_index)
			slot.set_meta("is_pressed", false)

	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and slot.get_meta("is_pressed", false):
		# Check if we should start dragging (only if slot has a talent)
		if talent:
			var press_pos: Vector2 = slot.get_meta("press_pos", Vector2.ZERO)
			var event_pos: Vector2 = event.position
			var delta: Vector2 = event_pos - press_pos

			if delta.length() > DRAG_THRESHOLD and not _is_dragging:
				slot.set_meta("is_pressed", false)
				# Unbind from current slot and start drag (pass source slot for swapping)
				TalentManager.unbind_skill(slot_index)
				_start_drag(talent.id, slot.get_global_position() + event_pos, slot_index)


func _on_bind_slot_pressed(slot_index: int) -> void:
	if binding_mode and not selected_talent_id.is_empty():
		# Bind the selected skill to this slot
		TalentManager.bind_skill(slot_index, selected_talent_id)
		binding_mode = false
		binding_mode_exited.emit()
		_refresh_skillbook()
		_refresh_bind_slots()
		_update_buttons()
	else:
		# Select the bound skill and show popup
		var talent := TalentManager.get_bound_talent(slot_index)
		if talent:
			selected_talent_id = talent.id
			selected_from_skillbook = true
			_refresh_skillbook()
			_update_buttons()
			# Show the popup
			if _skill_popup:
				_skill_popup.show_talent(talent.id, _last_tap_pos)


func _on_button1_pressed() -> void:
	# Only handles "Learn" from talent tree (skillbook uses drag-and-drop)
	if selected_talent_id.is_empty() or selected_from_skillbook:
		return

	if TalentManager.can_learn_talent(selected_talent_id):
		TalentManager.learn_talent(selected_talent_id)


func _on_button2_pressed() -> void:
	# No longer used - kept for signal connection
	pass


func _on_talent_learned(talent_id: String, _new_points: int) -> void:
	# Update the node visual
	if _talent_nodes.has(talent_id):
		var talent := TalentManager.get_talent(talent_id)
		if talent:
			_update_talent_node_visual(_talent_nodes[talent_id], talent)

	# Update all nodes (some may become available)
	for id in _talent_nodes:
		var talent := TalentManager.get_talent(id)
		if talent:
			_update_talent_node_visual(_talent_nodes[id], talent)

	# Redraw arrows (color changes when prereqs are met)
	if _arrow_layer:
		_arrow_layer.queue_redraw()

	_update_buttons()


func _on_talent_points_changed(_total: int, _available: int) -> void:
	_update_points_label()


func _on_skillbook_updated(_talents: Array) -> void:
	_refresh_skillbook()


func _on_skill_bound(_slot: int, _talent_id: String) -> void:
	_refresh_skillbook()
	_refresh_bind_slots()


func _on_skill_unbound(_slot: int) -> void:
	_refresh_skillbook()
	_refresh_bind_slots()


func _on_skill_points_changed(_points: int) -> void:
	_update_points_label()
	# Update all talent nodes since availability may have changed
	for id in _talent_nodes:
		var talent := TalentManager.get_talent(id)
		if talent:
			_update_talent_node_visual(_talent_nodes[id], talent)


func _on_equipment_changed(slot: ItemData.EquipSlot) -> void:
	## Handle equipment change - refresh skillbook and bind slots for weapon validity
	if slot == ItemData.EquipSlot.MAIN_HAND:
		_refresh_skillbook()
		_refresh_bind_slots()


## Convert weapon category ID to display name
func _get_weapon_category_display_name(category: String) -> String:
	match category:
		"melee": return "Melee Weapon"
		"melee_1h": return "One-Handed Melee"
		"melee_2h": return "Two-Handed Melee"
		"ranged": return "Ranged Weapon"
		"magic": return "Magic Weapon"
		_: return category.capitalize()


## Check if a talent's weapon requirement is met
func _is_weapon_requirement_met(talent: TalentData) -> bool:
	if not talent.has_weapon_requirement():
		return true
	var weapon_cat := Inventory.get_equipped_weapon_category()
	return talent.matches_weapon_category(weapon_cat)


#===============================================================================
# DRAG AND DROP
#===============================================================================

## Handle input for drag and drop
func _input(event: InputEvent) -> void:
	if _is_dragging:
		if event is InputEventMouseMotion or event is InputEventScreenDrag:
			_update_drag_position(event.position)
		elif event is InputEventMouseButton or event is InputEventScreenTouch:
			if not event.pressed:
				_end_drag(event.position)


## Start dragging a skill from skillbook or bind slot
## source_slot: -1 if from skillbook, 0-5 if from bind slot
func _start_drag(talent_id: String, start_pos: Vector2, source_slot: int = -1) -> void:
	var talent := TalentManager.get_talent(talent_id)
	if not talent or not TalentManager.is_in_skillbook(talent_id):
		return

	_is_dragging = true
	_drag_talent_id = talent_id
	_drag_start_pos = start_pos
	_drag_source_slot = source_slot

	# Create drag preview
	_create_drag_preview(talent)

	# Enter visual binding mode
	binding_mode = true
	_refresh_bind_slots()
	binding_mode_entered.emit()

	Debug.log("UI", "Started dragging skill: %s from slot %d" % [talent_id, source_slot])


## Create the visual drag preview
func _create_drag_preview(talent: TalentData) -> void:
	if _drag_preview:
		_drag_preview.queue_free()

	_drag_preview = PanelContainer.new()
	_drag_preview.z_index = 100
	_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.3, 0.4, 0.5, 0.9)
	stylebox.border_color = UITheme.COLOR_HIGHLIGHT
	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(6)
	_drag_preview.add_theme_stylebox_override("panel", stylebox)

	var label := Label.new()
	label.text = talent.talent_name.substr(0, 3).to_upper()
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(48, 48)
	_drag_preview.add_child(label)

	# Add to root so it's not clipped
	get_tree().root.add_child(_drag_preview)
	_drag_preview.global_position = _drag_start_pos - Vector2(24, 24)


## Update drag preview position
func _update_drag_position(pos: Vector2) -> void:
	if _drag_preview:
		_drag_preview.global_position = pos - Vector2(24, 24)


## End drag and check for drop target
func _end_drag(end_pos: Vector2) -> void:
	if not _is_dragging:
		return

	_is_dragging = false

	# Check if dropped on a bind slot
	var dropped_on_slot := _get_slot_at_position(end_pos)
	if dropped_on_slot >= 0:
		# Check if target slot already has a skill (for swapping)
		var existing_talent := TalentManager.get_bound_talent(dropped_on_slot)
		var existing_talent_id := existing_talent.id if existing_talent else ""

		# Bind the dragged skill to target slot
		TalentManager.bind_skill(dropped_on_slot, _drag_talent_id)

		# If there was an existing skill and we dragged from another slot, swap
		if not existing_talent_id.is_empty() and _drag_source_slot >= 0 and _drag_source_slot != dropped_on_slot:
			TalentManager.bind_skill(_drag_source_slot, existing_talent_id)
			Debug.log("UI", "Swapped skills: %s to slot %d, %s to slot %d" % [_drag_talent_id, dropped_on_slot, existing_talent_id, _drag_source_slot])
		else:
			Debug.log("UI", "Dropped skill %s on slot %d" % [_drag_talent_id, dropped_on_slot])

	# Clean up
	if _drag_preview:
		_drag_preview.queue_free()
		_drag_preview = null

	_drag_talent_id = ""
	_drag_source_slot = -1
	binding_mode = false
	binding_mode_exited.emit()

	_refresh_skillbook()
	_refresh_bind_slots()
	_update_buttons()


## Get which bind slot is at the given position (-1 if none)
func _get_slot_at_position(pos: Vector2) -> int:
	# Check main slot
	if _bind_main_slot and _is_point_in_control(_bind_main_slot, pos):
		return 0

	# Check secondary slots
	for i in range(_bind_slots.size()):
		if _is_point_in_control(_bind_slots[i], pos):
			return i + 1

	return -1


## Check if a point is inside a control's global rect
func _is_point_in_control(control: Control, point: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.has_point(point)


## Cancel any ongoing drag operation
func _cancel_drag() -> void:
	if _is_dragging:
		_is_dragging = false
		_drag_talent_id = ""
		_drag_source_slot = -1

		if _drag_preview:
			_drag_preview.queue_free()
			_drag_preview = null

		binding_mode = false
		binding_mode_exited.emit()
		_refresh_bind_slots()


#===============================================================================
# FLASH ANIMATION FOR NEW SKILLS
#===============================================================================

## Play flash animation when a new skill is added to the skillbook
func _play_skillbook_flash(slot: Button) -> void:
	if not slot:
		return

	# Store original modulate
	var original_color := slot.modulate

	# Create flash tween
	var tween := create_tween()
	tween.tween_property(slot, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.1)
	tween.tween_property(slot, "modulate", original_color, 0.3)

	# Also scale pulse
	tween.parallel().tween_property(slot, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
