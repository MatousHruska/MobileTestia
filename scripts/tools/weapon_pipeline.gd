extends Control
## Weapon Pipeline Wizard
##
## 3-step tool for converting high-res weapon images to pixel art with anchor
## placement and standardized export.
##
## Steps:
##   1. Load & Preview — select source image, set weapon ID and category
##   2. Pixel Art Processing — configure downscale, dithering, palette, etc.
##   3. Anchor Placement & Export — place grip/tip anchors, export to folder
##
## Run: scenes/tools/weapon_pipeline.tscn (F6)

#===============================================================================
# CONSTANTS
#===============================================================================

const WEAPONS_DIR := "res://assets/sprites/weapons"

const CATEGORIES: PackedStringArray = [
	"melee_1h", "melee_2h", "dagger", "ranged", "magic",
]

#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")
const C_DANGER := Color("#EF5350")
const C_GRIP := Color("#FF00AA")
const C_TIP := Color("#00FFFF")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

const ANCHOR_ZOOM := 12

#===============================================================================
# WIZARD STATE
#===============================================================================

var _current_step := 0  # 0-2
var _step_containers: Array[VBoxContainer] = []

## Step 1 state
var _source_image: Image = null
var _source_texture: ImageTexture = null
var _weapon_id: String = ""
var _weapon_category: String = "melee_1h"

## Step 2 state
var _processed_image: Image = null
var _processed_texture: ImageTexture = null
var _target_height: int = 24
var _alpha_threshold: int = 128
var _dithering_enabled: bool = false
var _dithering_strength: float = 0.5
var _dithering_pattern: int = 0  # 0=2x2, 1=4x4, 2=8x8
var _palette_enabled: bool = false
var _palette_colors: PackedColorArray = PackedColorArray()
var _palette_path: String = ""
var _outline_enabled: bool = false
var _outline_color: Color = Color.BLACK
var _denoising_enabled: bool = false
var _denoising_min_cluster: int = 2

## Step 3 state
var _grip_point: Vector2i = Vector2i(-1, -1)
var _tip_point: Vector2i = Vector2i(-1, -1)
var _placement_mode: String = ""  # "", "grip", "tip"

## Alpha mask state
var _alpha_mask_image: Image = null
var _alpha_paint_mode: bool = false
var _alpha_paint_value: int = 128  # Current brush R8 value (0, 64, 128, 191, 255)
var _alpha_buttons: Array[Button] = []
var _alpha_paint_toggle_btn: Button = null

#===============================================================================
# NODE REFERENCES
#===============================================================================

# Step indicator
var _step_indicator: Control = null

# Navigation
var _back_button: Button = null
var _next_button: Button = null
var _status_label: Label = null

# Step 1 nodes
var _file_dialog: FileDialog = null
var _weapon_id_edit: LineEdit = null
var _category_dropdown: OptionButton = null
var _source_preview_rect: TextureRect = null
var _source_info_label: Label = null
var _load_button: Button = null

# Step 2 nodes
var _target_height_spin: SpinBox = null
var _alpha_threshold_spin: SpinBox = null
var _dithering_toggle: CheckButton = null
var _dithering_strength_slider: HSlider = null
var _dithering_pattern_dropdown: OptionButton = null
var _palette_toggle: CheckButton = null
var _palette_file_button: Button = null
var _palette_dialog: FileDialog = null
var _palette_status_label: Label = null
var _outline_toggle: CheckButton = null
var _outline_color_picker: ColorPickerButton = null
var _denoising_toggle: CheckButton = null
var _denoising_min_cluster_spin: SpinBox = null
var _source_side_rect: TextureRect = null
var _processed_side_rect: TextureRect = null

# Step 3 nodes
var _anchor_preview_rect: TextureRect = null
var _anchor_overlay: Control = null  # Custom draw overlay for crosshairs
var _grip_button: Button = null
var _tip_button: Button = null
var _grip_label: Label = null
var _tip_label: Label = null
var _export_button: Button = null
var _export_status_label: Label = null

# Right panel containers (for visibility toggling)
var _side_by_side_container: HBoxContainer = null
var _anchor_container: PanelContainer = null

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_go_to_step(0)


#===============================================================================
# UI CONSTRUCTION
#===============================================================================

func _build_ui() -> void:
	theme = _build_theme()

	# Background fill
	var bg_rect := ColorRect.new()
	bg_rect.color = C_BG
	bg_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_rect.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg_rect)

	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# -- Left panel --
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	root_hbox.add_child(panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(left_vbox)

	# Title
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_top", 12)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(title_margin)
	var title := Label.new()
	title.text = "Weapon Pipeline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Step indicator
	var StepIndicatorScript: GDScript = load("res://scripts/tools/step_indicator.gd") as GDScript
	_step_indicator = StepIndicatorScript.new() as Control
	_step_indicator.total_steps = 3
	_step_indicator.step_names = PackedStringArray([
		"Load & Preview", "Pixel Art Processing", "Anchor & Export",
	])
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 8)
	indicator_margin.add_theme_constant_override("margin_right", 8)
	indicator_margin.add_theme_constant_override("margin_bottom", 8)
	left_vbox.add_child(indicator_margin)
	indicator_margin.add_child(_step_indicator)

	# Separator
	var top_sep := HSeparator.new()
	left_vbox.add_child(top_sep)

	# Scrollable step content
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	scroll_vbox.add_child(content_margin)

	var steps_vbox := VBoxContainer.new()
	steps_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	steps_vbox.add_theme_constant_override("separation", 8)
	content_margin.add_child(steps_vbox)

	# Build 3 step containers
	for i in range(3):
		var step_cont := VBoxContainer.new()
		step_cont.add_theme_constant_override("separation", 10)
		step_cont.visible = (i == 0)
		steps_vbox.add_child(step_cont)
		_step_containers.append(step_cont)

	_build_step_load(_step_containers[0])
	_build_step_processing(_step_containers[1])
	_build_step_anchor(_step_containers[2])

	# -- Bottom bar --
	var bottom_sep := HSeparator.new()
	left_vbox.add_child(bottom_sep)

	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_top", 8)
	nav_margin.add_theme_constant_override("margin_bottom", 4)
	nav_margin.add_theme_constant_override("margin_left", 12)
	nav_margin.add_theme_constant_override("margin_right", 12)
	left_vbox.add_child(nav_margin)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 8)
	nav_margin.add_child(nav_hbox)

	_back_button = _make_subtle_button("\u25c0  Back")
	_back_button.visible = false
	_back_button.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(_back_button)

	_next_button = _make_primary_button("Next  \u25b6")
	_next_button.disabled = true
	_next_button.pressed.connect(_on_next_pressed)
	nav_hbox.add_child(_next_button)

	# Status bar
	var status_panel := PanelContainer.new()
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = C_SECTION
	status_sb.set_content_margin_all(6)
	status_sb.content_margin_left = 12
	status_sb.content_margin_right = 12
	status_panel.add_theme_stylebox_override("panel", status_sb)
	left_vbox.add_child(status_panel)

	_status_label = Label.new()
	_status_label.text = "Load a weapon image to begin."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_status_label.max_lines_visible = 2
	status_panel.add_child(_status_label)

	# -- Right side: preview areas --
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 0)
	root_hbox.add_child(right_vbox)

	_build_right_panel(right_vbox)

	# FileDialogs (added as children so they work with the tree)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png;*.jpg;*.jpeg ; Image files"])
	_file_dialog.title = "Select Weapon Image"
	_file_dialog.size = Vector2i(800, 500)
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_palette_dialog = FileDialog.new()
	_palette_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_palette_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_palette_dialog.filters = PackedStringArray(["*.png ; Palette PNG"])
	_palette_dialog.title = "Select Palette Image"
	_palette_dialog.size = Vector2i(800, 500)
	_palette_dialog.file_selected.connect(_on_palette_file_selected)
	add_child(_palette_dialog)


func _build_right_panel(parent: VBoxContainer) -> void:
	# Step 1: source preview
	_source_preview_rect = TextureRect.new()
	_source_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_source_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_source_preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_source_preview_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	_source_preview_rect.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(_source_preview_rect)

	# Step 2: side-by-side preview (source left, processed right)
	_side_by_side_container = HBoxContainer.new()
	_side_by_side_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_side_by_side_container.size_flags_vertical = SIZE_EXPAND_FILL
	_side_by_side_container.add_theme_constant_override("separation", 4)
	_side_by_side_container.visible = false
	parent.add_child(_side_by_side_container)

	# Source side (left)
	var source_panel := _make_preview_panel("Source")
	_side_by_side_container.add_child(source_panel[0])
	_source_side_rect = source_panel[1]

	# Processed side (right)
	var processed_panel := _make_preview_panel("Processed")
	_side_by_side_container.add_child(processed_panel[0])
	_processed_side_rect = processed_panel[1]

	# Step 3: anchor placement preview (zoomed)
	_anchor_container = PanelContainer.new()
	_anchor_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_anchor_container.size_flags_vertical = SIZE_EXPAND_FILL
	_anchor_container.visible = false
	var anchor_sb := StyleBoxFlat.new()
	anchor_sb.bg_color = C_BG
	_anchor_container.add_theme_stylebox_override("panel", anchor_sb)
	parent.add_child(_anchor_container)

	# Use a ScrollContainer inside anchor panel so large zoomed images can scroll
	var anchor_scroll := ScrollContainer.new()
	anchor_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_anchor_container.add_child(anchor_scroll)

	# Container for the texture + overlay to stack them
	var anchor_stack := Control.new()
	anchor_stack.size_flags_horizontal = SIZE_EXPAND_FILL
	anchor_stack.size_flags_vertical = SIZE_EXPAND_FILL
	anchor_scroll.add_child(anchor_stack)

	_anchor_preview_rect = TextureRect.new()
	_anchor_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anchor_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_anchor_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anchor_stack.add_child(_anchor_preview_rect)

	# Overlay for drawing crosshairs and line
	_anchor_overlay = Control.new()
	_anchor_overlay.mouse_filter = MOUSE_FILTER_STOP
	anchor_stack.add_child(_anchor_overlay)
	_anchor_overlay.draw.connect(_on_anchor_overlay_draw)
	_anchor_overlay.gui_input.connect(_on_anchor_overlay_input)


func _make_preview_panel(label_text: String) -> Array:
	## Returns [VBoxContainer, TextureRect] for a labeled preview panel.
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", FONT_HINT)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(lbl)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#181828")
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	vbox.add_child(panel)

	var tex_rect := TextureRect.new()
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	tex_rect.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(tex_rect)

	return [vbox, tex_rect]


#===============================================================================
# STEP 1 — LOAD & PREVIEW
#===============================================================================

func _build_step_load(parent: VBoxContainer) -> void:
	var sec := _make_section("Load Weapon Image")
	parent.add_child(sec[0])
	var content: VBoxContainer = sec[1]

	# Load button
	_load_button = Button.new()
	_load_button.text = "Browse Image..."
	_load_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_load_button.pressed.connect(func() -> void:
		_file_dialog.popup_centered()
	)
	content.add_child(_load_button)

	_source_info_label = Label.new()
	_source_info_label.text = "No image loaded"
	_source_info_label.add_theme_font_size_override("font_size", FONT_HINT)
	_source_info_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_source_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_source_info_label)

	# Weapon ID
	var id_sec := _make_section("Weapon Identity")
	parent.add_child(id_sec[0])
	var id_content: VBoxContainer = id_sec[1]

	_weapon_id_edit = LineEdit.new()
	_weapon_id_edit.placeholder_text = "e.g. iron_sword"
	_weapon_id_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_weapon_id_edit.text_changed.connect(func(new_text: String) -> void:
		_weapon_id = new_text.strip_edges()
		_update_nav_state()
	)
	id_content.add_child(_make_field("Weapon ID", _weapon_id_edit))

	# Category dropdown
	_category_dropdown = OptionButton.new()
	_category_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	for cat in CATEGORIES:
		_category_dropdown.add_item(cat)
	_category_dropdown.item_selected.connect(func(idx: int) -> void:
		_weapon_category = CATEGORIES[idx]
	)
	id_content.add_child(_make_field("Category", _category_dropdown))


#===============================================================================
# STEP 2 — PIXEL ART PROCESSING
#===============================================================================

func _build_step_processing(parent: VBoxContainer) -> void:
	# Size section
	var size_sec := _make_section("Downscale")
	parent.add_child(size_sec[0])
	var size_content: VBoxContainer = size_sec[1]

	_target_height_spin = SpinBox.new()
	_target_height_spin.min_value = 8
	_target_height_spin.max_value = 128
	_target_height_spin.value = 24
	_target_height_spin.step = 1
	_target_height_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_target_height_spin.value_changed.connect(func(v: float) -> void:
		_target_height = int(v)
		_process_pixel_art()
	)
	size_content.add_child(_make_field("Target Height (px)", _target_height_spin))

	# Alpha threshold
	var alpha_sec := _make_section("Alpha Threshold")
	parent.add_child(alpha_sec[0])
	var alpha_content: VBoxContainer = alpha_sec[1]

	_alpha_threshold_spin = SpinBox.new()
	_alpha_threshold_spin.min_value = 0
	_alpha_threshold_spin.max_value = 255
	_alpha_threshold_spin.value = 128
	_alpha_threshold_spin.step = 1
	_alpha_threshold_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_alpha_threshold_spin.value_changed.connect(func(v: float) -> void:
		_alpha_threshold = int(v)
		_process_pixel_art()
	)
	alpha_content.add_child(_make_field("Threshold (0-255)", _alpha_threshold_spin))

	# Dithering section
	var dither_sec := _make_section("Dithering")
	parent.add_child(dither_sec[0])
	var dither_content: VBoxContainer = dither_sec[1]

	_dithering_toggle = CheckButton.new()
	_dithering_toggle.text = "Enable Dithering"
	_dithering_toggle.toggled.connect(func(on: bool) -> void:
		_dithering_enabled = on
		_process_pixel_art()
	)
	dither_content.add_child(_dithering_toggle)

	var strength_data := _make_slider_row(0.0, 1.0, 0.5, 0.05)
	_dithering_strength_slider = strength_data[1]
	_dithering_strength_slider.value_changed.connect(func(v: float) -> void:
		_dithering_strength = v
		_process_pixel_art()
	)
	dither_content.add_child(_make_field("Strength", strength_data[0]))

	_dithering_pattern_dropdown = OptionButton.new()
	_dithering_pattern_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	_dithering_pattern_dropdown.add_item("2x2")
	_dithering_pattern_dropdown.add_item("4x4")
	_dithering_pattern_dropdown.add_item("8x8")
	_dithering_pattern_dropdown.item_selected.connect(func(idx: int) -> void:
		_dithering_pattern = idx
		_process_pixel_art()
	)
	dither_content.add_child(_make_field("Pattern", _dithering_pattern_dropdown))

	# Palette section
	var palette_sec := _make_section("Palette Mapping")
	parent.add_child(palette_sec[0])
	var palette_content: VBoxContainer = palette_sec[1]

	_palette_toggle = CheckButton.new()
	_palette_toggle.text = "Enable Palette"
	_palette_toggle.toggled.connect(func(on: bool) -> void:
		_palette_enabled = on
		_process_pixel_art()
	)
	palette_content.add_child(_palette_toggle)

	_palette_file_button = Button.new()
	_palette_file_button.text = "Load Palette PNG..."
	_palette_file_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_palette_file_button.pressed.connect(func() -> void:
		_palette_dialog.popup_centered()
	)
	palette_content.add_child(_palette_file_button)

	_palette_status_label = Label.new()
	_palette_status_label.text = "No palette loaded"
	_palette_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_palette_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	palette_content.add_child(_palette_status_label)

	# Outline section
	var outline_sec := _make_section("Outline")
	parent.add_child(outline_sec[0])
	var outline_content: VBoxContainer = outline_sec[1]

	var outline_row := HBoxContainer.new()
	outline_row.add_theme_constant_override("separation", 8)
	outline_content.add_child(outline_row)

	_outline_toggle = CheckButton.new()
	_outline_toggle.text = "Enable Outline"
	_outline_toggle.toggled.connect(func(on: bool) -> void:
		_outline_enabled = on
		_process_pixel_art()
	)
	outline_row.add_child(_outline_toggle)

	_outline_color_picker = ColorPickerButton.new()
	_outline_color_picker.color = Color.BLACK
	_outline_color_picker.custom_minimum_size = Vector2(40, 30)
	_outline_color_picker.color_changed.connect(func(c: Color) -> void:
		_outline_color = c
		_process_pixel_art()
	)
	outline_row.add_child(_outline_color_picker)

	# Denoising section
	var denoise_sec := _make_section("Denoising")
	parent.add_child(denoise_sec[0])
	var denoise_content: VBoxContainer = denoise_sec[1]

	_denoising_toggle = CheckButton.new()
	_denoising_toggle.text = "Enable Denoising"
	_denoising_toggle.toggled.connect(func(on: bool) -> void:
		_denoising_enabled = on
		_process_pixel_art()
	)
	denoise_content.add_child(_denoising_toggle)

	_denoising_min_cluster_spin = SpinBox.new()
	_denoising_min_cluster_spin.min_value = 1
	_denoising_min_cluster_spin.max_value = 20
	_denoising_min_cluster_spin.value = 2
	_denoising_min_cluster_spin.step = 1
	_denoising_min_cluster_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_denoising_min_cluster_spin.value_changed.connect(func(v: float) -> void:
		_denoising_min_cluster = int(v)
		_process_pixel_art()
	)
	denoise_content.add_child(_make_field("Min Cluster Size", _denoising_min_cluster_spin))


#===============================================================================
# STEP 3 — ANCHOR PLACEMENT & EXPORT
#===============================================================================

func _build_step_anchor(parent: VBoxContainer) -> void:
	# Anchor placement section
	var anchor_sec := _make_section("Anchor Points")
	parent.add_child(anchor_sec[0])
	var anchor_content: VBoxContainer = anchor_sec[1]

	anchor_content.add_child(_make_small_label(
		"Click on the zoomed preview to place anchors. Grip = where the hand holds. Tip = furthest point."
	))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	anchor_content.add_child(btn_row)

	_grip_button = Button.new()
	_grip_button.text = "Place Grip"
	_grip_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_grip_button.toggle_mode = true
	_grip_button.pressed.connect(_on_grip_button_pressed)
	_style_anchor_button(_grip_button, C_GRIP)
	btn_row.add_child(_grip_button)

	_tip_button = Button.new()
	_tip_button.text = "Place Tip"
	_tip_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_tip_button.toggle_mode = true
	_tip_button.pressed.connect(_on_tip_button_pressed)
	_style_anchor_button(_tip_button, C_TIP)
	btn_row.add_child(_tip_button)

	_grip_label = Label.new()
	_grip_label.text = "Grip: --"
	_grip_label.add_theme_font_size_override("font_size", FONT_VALUE)
	_grip_label.add_theme_color_override("font_color", C_GRIP)
	anchor_content.add_child(_grip_label)

	_tip_label = Label.new()
	_tip_label.text = "Tip: --"
	_tip_label.add_theme_font_size_override("font_size", FONT_VALUE)
	_tip_label.add_theme_color_override("font_color", C_TIP)
	anchor_content.add_child(_tip_label)

	# Draw Alpha Mask section
	var alpha_sec := _make_section("Draw Alpha Mask")
	parent.add_child(alpha_sec[0])
	var alpha_content: VBoxContainer = alpha_sec[1]

	alpha_content.add_child(_make_small_label(
		"Paint transparency on weapon pixels. L-click to paint."
	))

	var alpha_row := HBoxContainer.new()
	alpha_row.add_theme_constant_override("separation", 4)
	alpha_content.add_child(alpha_row)

	_alpha_buttons.clear()
	var alpha_levels: Array[Array] = [
		[0, "0%"], [64, "25%"], [128, "50%"], [191, "75%"], [255, "100%"],
	]
	for entry in alpha_levels:
		var value: int = entry[0]
		var label_text: String = entry[1]
		var btn := Button.new()
		btn.text = label_text
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		var btn_sb := StyleBoxFlat.new()
		btn_sb.bg_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, value / 255.0)
		btn_sb.set_corner_radius_all(4)
		btn_sb.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", btn_sb)
		var btn_hover_sb := StyleBoxFlat.new()
		btn_hover_sb.bg_color = Color(C_ACCENT_HOVER.r, C_ACCENT_HOVER.g, C_ACCENT_HOVER.b, clampf(value / 255.0 + 0.15, 0.0, 1.0))
		btn_hover_sb.set_corner_radius_all(4)
		btn_hover_sb.set_content_margin_all(6)
		btn.add_theme_stylebox_override("hover", btn_hover_sb)
		btn.add_theme_font_size_override("font_size", FONT_HINT)
		btn.pressed.connect(_on_alpha_level_selected.bind(value))
		alpha_row.add_child(btn)
		_alpha_buttons.append(btn)

	_alpha_paint_toggle_btn = _make_primary_button("Enable Alpha Painting")
	_alpha_paint_toggle_btn.pressed.connect(_on_alpha_paint_toggled)
	alpha_content.add_child(_alpha_paint_toggle_btn)

	var clear_alpha_btn := _make_subtle_button("Clear Mask")
	clear_alpha_btn.pressed.connect(_on_clear_alpha_mask)
	alpha_content.add_child(clear_alpha_btn)

	# Export section
	var export_sec := _make_section("Export")
	parent.add_child(export_sec[0])
	var export_content: VBoxContainer = export_sec[1]

	_export_button = _make_primary_button("Export Weapon")
	_export_button.pressed.connect(_export_weapon)
	export_content.add_child(_export_button)

	_export_status_label = Label.new()
	_export_status_label.text = ""
	_export_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_export_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	export_content.add_child(_export_status_label)


#===============================================================================
# NAVIGATION
#===============================================================================

func _go_to_step(step: int) -> void:
	_current_step = clampi(step, 0, 2)
	for i in range(_step_containers.size()):
		_step_containers[i].visible = (i == _current_step)

	_step_indicator.set_step(_current_step)
	_back_button.visible = (_current_step > 0)

	# Show/hide right panel sections
	_source_preview_rect.visible = (_current_step == 0)
	_side_by_side_container.visible = (_current_step == 1)
	_anchor_container.visible = (_current_step == 2)

	# Update next button text
	if _current_step < 2:
		_next_button.text = "Next  \u25b6"
	else:
		_next_button.visible = false

	_update_nav_state()

	# When entering step 2, process the pixel art
	if _current_step == 1:
		_process_pixel_art()
	# When entering step 3, update anchor preview
	elif _current_step == 2:
		_update_anchor_preview()


func _update_nav_state() -> void:
	match _current_step:
		0:
			# Can proceed when we have a source image and weapon ID
			_next_button.visible = true
			_next_button.disabled = (_source_image == null or _weapon_id.is_empty())
		1:
			# Can always proceed from processing step
			_next_button.visible = true
			_next_button.disabled = (_processed_image == null)
		2:
			_next_button.visible = false


func _on_back_pressed() -> void:
	_go_to_step(_current_step - 1)


func _on_next_pressed() -> void:
	_go_to_step(_current_step + 1)


#===============================================================================
# STEP 1 — FILE LOADING
#===============================================================================

func _on_file_selected(path: String) -> void:
	_source_image = Image.load_from_file(path)
	if _source_image == null:
		_source_texture = null
		_source_preview_rect.texture = null
		_source_info_label.text = "Failed to load: %s" % path
		_source_info_label.add_theme_color_override("font_color", C_WARNING)
		_set_status("Error loading image file.")
		_update_nav_state()
		return

	_source_texture = ImageTexture.create_from_image(_source_image)
	_source_preview_rect.texture = _source_texture
	_source_info_label.text = "%s\n%d x %d px" % [
		path.get_file(),
		_source_image.get_width(),
		_source_image.get_height(),
	]
	_source_info_label.add_theme_color_override("font_color", C_TEXT_DIM)

	# Auto-populate weapon ID from filename (sans extension) if empty
	if _weapon_id_edit.text.is_empty():
		var auto_id: String = path.get_file().get_basename().to_lower().replace(" ", "_").replace("-", "_")
		_weapon_id_edit.text = auto_id
		_weapon_id = auto_id

	_set_status("Image loaded: %s (%dx%d)" % [
		path.get_file(),
		_source_image.get_width(),
		_source_image.get_height(),
	])

	# Reset processed state and anchors for new image
	_processed_image = null
	_processed_texture = null
	_grip_point = Vector2i(-1, -1)
	_tip_point = Vector2i(-1, -1)

	_update_nav_state()


#===============================================================================
# STEP 2 — PIXEL ART PROCESSING
#===============================================================================

func _process_pixel_art() -> void:
	if _source_image == null:
		return

	var src_w: int = _source_image.get_width()
	var src_h: int = _source_image.get_height()
	var scale_factor: float = float(_target_height) / float(src_h)
	var target_w: int = maxi(1, roundi(src_w * scale_factor))

	_processed_image = _source_image.duplicate()
	_processed_image.resize(target_w, _target_height, Image.INTERPOLATE_BILINEAR)

	PixelArtProcessing.apply_alpha_threshold(_processed_image, _alpha_threshold)

	if _dithering_enabled:
		PixelArtProcessing.apply_ordered_dithering(
			_processed_image, _dithering_strength, _dithering_pattern
		)

	if _palette_enabled and _palette_colors.size() > 0:
		PixelArtProcessing.apply_palette_mapping(_processed_image, _palette_colors)

	if _outline_enabled:
		PixelArtProcessing.apply_outline(_processed_image, _outline_color)

	if _denoising_enabled:
		PixelArtProcessing.apply_denoising(_processed_image, _denoising_min_cluster)

	_processed_texture = ImageTexture.create_from_image(_processed_image)
	_update_processing_preview()


func _update_processing_preview() -> void:
	if _source_texture != null:
		_source_side_rect.texture = _source_texture
	if _processed_texture != null:
		_processed_side_rect.texture = _processed_texture

	# Reset anchors when processing changes (image dimensions may differ)
	_grip_point = Vector2i(-1, -1)
	_tip_point = Vector2i(-1, -1)

	_update_nav_state()


func _on_palette_file_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		_palette_status_label.text = "Failed to load palette"
		_palette_status_label.add_theme_color_override("font_color", C_WARNING)
		return

	_palette_path = path
	_palette_colors = PackedColorArray()

	# Extract unique colors from palette image
	var seen := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := "%d,%d,%d" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
			if not seen.has(key):
				seen[key] = true
				_palette_colors.append(c)

	_palette_status_label.text = "%s (%d colors)" % [path.get_file(), _palette_colors.size()]
	_palette_status_label.add_theme_color_override("font_color", C_SUCCESS)

	if _palette_enabled:
		_process_pixel_art()


#===============================================================================
# STEP 3 — ANCHOR PLACEMENT
#===============================================================================

func _update_anchor_preview() -> void:
	if _processed_image == null:
		return

	# Set zoomed texture
	_anchor_preview_rect.texture = _processed_texture

	# Size the preview at ANCHOR_ZOOM scale
	var zoomed_w: int = _processed_image.get_width() * ANCHOR_ZOOM
	var zoomed_h: int = _processed_image.get_height() * ANCHOR_ZOOM
	_anchor_preview_rect.custom_minimum_size = Vector2(zoomed_w, zoomed_h)
	_anchor_preview_rect.size = Vector2(zoomed_w, zoomed_h)

	# Match overlay size to preview size
	_anchor_overlay.custom_minimum_size = Vector2(zoomed_w, zoomed_h)
	_anchor_overlay.size = Vector2(zoomed_w, zoomed_h)

	# Also size parent stack control
	var stack: Control = _anchor_preview_rect.get_parent()
	stack.custom_minimum_size = Vector2(zoomed_w, zoomed_h)
	stack.size = Vector2(zoomed_w, zoomed_h)

	# Try to load existing alpha mask for this weapon
	if _alpha_mask_image == null and not _weapon_id.is_empty():
		var alpha_res_path: String = WEAPONS_DIR + "/" + _weapon_id + "/alpha_mask.png"
		if ResourceLoader.exists(alpha_res_path):
			var alpha_global_path: String = ProjectSettings.globalize_path(alpha_res_path)
			var loaded_mask := Image.load_from_file(alpha_global_path)
			if loaded_mask != null and loaded_mask.get_width() == _processed_image.get_width() and loaded_mask.get_height() == _processed_image.get_height():
				_alpha_mask_image = loaded_mask
				# Ensure R8 format
				if _alpha_mask_image.get_format() != Image.FORMAT_R8:
					_alpha_mask_image.convert(Image.FORMAT_R8)

	# Update labels
	_update_anchor_labels()
	_anchor_overlay.queue_redraw()


func _on_grip_button_pressed() -> void:
	if _grip_button.button_pressed:
		_placement_mode = "grip"
		_tip_button.button_pressed = false
		_set_status("Click on the preview to place the grip point.")
	else:
		_placement_mode = ""


func _on_tip_button_pressed() -> void:
	if _tip_button.button_pressed:
		_placement_mode = "tip"
		_grip_button.button_pressed = false
		_set_status("Click on the preview to place the tip point.")
	else:
		_placement_mode = ""


func _on_anchor_overlay_input(event: InputEvent) -> void:
	if _processed_image == null:
		return

	# Alpha painting: handle click and drag
	if _alpha_paint_mode:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var local_pos: Vector2 = mb.position
				var px: int = clampi(int(local_pos.x) / ANCHOR_ZOOM, 0, _processed_image.get_width() - 1)
				var py: int = clampi(int(local_pos.y) / ANCHOR_ZOOM, 0, _processed_image.get_height() - 1)
				_paint_alpha_pixel(px, py)
		elif event is InputEventMouseMotion:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				var mm: InputEventMouseMotion = event as InputEventMouseMotion
				var local_pos: Vector2 = mm.position
				var px: int = clampi(int(local_pos.x) / ANCHOR_ZOOM, 0, _processed_image.get_width() - 1)
				var py: int = clampi(int(local_pos.y) / ANCHOR_ZOOM, 0, _processed_image.get_height() - 1)
				_paint_alpha_pixel(px, py)
		return

	# Anchor placement mode
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _placement_mode.is_empty():
		return

	# Convert click position to pixel coordinates
	var local_pos: Vector2 = mb.position
	var px: int = clampi(int(local_pos.x) / ANCHOR_ZOOM, 0, _processed_image.get_width() - 1)
	var py: int = clampi(int(local_pos.y) / ANCHOR_ZOOM, 0, _processed_image.get_height() - 1)

	if _placement_mode == "grip":
		_grip_point = Vector2i(px, py)
		_grip_button.button_pressed = false
		_placement_mode = ""
		_set_status("Grip point placed at (%d, %d)." % [px, py])
	elif _placement_mode == "tip":
		_tip_point = Vector2i(px, py)
		_tip_button.button_pressed = false
		_placement_mode = ""
		_set_status("Tip point placed at (%d, %d)." % [px, py])

	_update_anchor_labels()
	_anchor_overlay.queue_redraw()


func _paint_alpha_pixel(px: int, py: int) -> void:
	if _alpha_mask_image == null or _processed_image == null:
		return
	var weapon_pixel := _processed_image.get_pixel(px, py)
	if weapon_pixel.a < 0.01:
		return  # Only paint on non-transparent weapon pixels
	_alpha_mask_image.set_pixel(px, py, Color(_alpha_paint_value / 255.0, 0, 0))
	_anchor_overlay.queue_redraw()


func _on_anchor_overlay_draw() -> void:
	if _processed_image == null:
		return

	var img_w: int = _processed_image.get_width()
	var img_h: int = _processed_image.get_height()
	var zoom: float = float(ANCHOR_ZOOM)

	# Draw grid lines (subtle)
	var grid_color := Color(C_BORDER, 0.3)
	for x in range(img_w + 1):
		_anchor_overlay.draw_line(
			Vector2(x * zoom, 0),
			Vector2(x * zoom, img_h * zoom),
			grid_color, 1.0
		)
	for y in range(img_h + 1):
		_anchor_overlay.draw_line(
			Vector2(0, y * zoom),
			Vector2(img_w * zoom, y * zoom),
			grid_color, 1.0
		)

	# Draw line from grip to tip
	if _grip_point != Vector2i(-1, -1) and _tip_point != Vector2i(-1, -1):
		var grip_center := Vector2(_grip_point.x * zoom + zoom * 0.5, _grip_point.y * zoom + zoom * 0.5)
		var tip_center := Vector2(_tip_point.x * zoom + zoom * 0.5, _tip_point.y * zoom + zoom * 0.5)
		_anchor_overlay.draw_line(grip_center, tip_center, Color(1, 1, 1, 0.5), 2.0)

	# Draw grip crosshair
	if _grip_point != Vector2i(-1, -1):
		_draw_crosshair(_grip_point, C_GRIP, zoom)

	# Draw tip crosshair
	if _tip_point != Vector2i(-1, -1):
		_draw_crosshair(_tip_point, C_TIP, zoom)

	# Draw alpha mask overlay
	if _alpha_paint_mode and _alpha_mask_image != null:
		for y in range(img_h):
			for x in range(img_w):
				var weapon_pixel := _processed_image.get_pixel(x, y)
				if weapon_pixel.a < 0.01:
					continue
				var mask_val: float = _alpha_mask_image.get_pixel(x, y).r
				if mask_val > 0.99:
					continue  # Fully opaque, no overlay needed
				var rect := Rect2(x * zoom, y * zoom, zoom, zoom)
				# Red-tinted overlay proportional to transparency
				_anchor_overlay.draw_rect(rect, Color(1.0, 0.2, 0.2, (1.0 - mask_val) * 0.6))
				# Checkerboard pattern for strongly transparent pixels
				if mask_val < 0.5:
					var half := zoom * 0.5
					_anchor_overlay.draw_rect(
						Rect2(x * zoom, y * zoom, half, half),
						Color(0, 0, 0, 0.3))
					_anchor_overlay.draw_rect(
						Rect2(x * zoom + half, y * zoom + half, half, half),
						Color(0, 0, 0, 0.3))


func _draw_crosshair(pixel_pos: Vector2i, color: Color, zoom: float) -> void:
	var cx: float = pixel_pos.x * zoom + zoom * 0.5
	var cy: float = pixel_pos.y * zoom + zoom * 0.5
	var arm: float = zoom * 1.5  # Crosshair arm length

	# Highlight the pixel cell
	_anchor_overlay.draw_rect(
		Rect2(pixel_pos.x * zoom, pixel_pos.y * zoom, zoom, zoom),
		Color(color, 0.3)
	)

	# Crosshair lines
	_anchor_overlay.draw_line(Vector2(cx - arm, cy), Vector2(cx + arm, cy), color, 2.0)
	_anchor_overlay.draw_line(Vector2(cx, cy - arm), Vector2(cx, cy + arm), color, 2.0)

	# Small center dot
	_anchor_overlay.draw_circle(Vector2(cx, cy), 3.0, color)


func _update_anchor_labels() -> void:
	if _grip_point != Vector2i(-1, -1):
		_grip_label.text = "Grip: (%d, %d)" % [_grip_point.x, _grip_point.y]
	else:
		_grip_label.text = "Grip: --"

	if _tip_point != Vector2i(-1, -1):
		_tip_label.text = "Tip: (%d, %d)" % [_tip_point.x, _tip_point.y]
	else:
		_tip_label.text = "Tip: --"


func _on_alpha_level_selected(value: int) -> void:
	_alpha_paint_value = value
	_anchor_overlay.queue_redraw()


func _on_alpha_paint_toggled() -> void:
	_alpha_paint_mode = not _alpha_paint_mode
	_alpha_paint_toggle_btn.text = "Disable Alpha Painting" if _alpha_paint_mode else "Enable Alpha Painting"
	if _alpha_paint_mode and _alpha_mask_image == null and _processed_image != null:
		_alpha_mask_image = Image.create(
			_processed_image.get_width(), _processed_image.get_height(),
			false, Image.FORMAT_R8)
		_alpha_mask_image.fill(Color(1, 1, 1))  # 255 = opaque
	_anchor_overlay.queue_redraw()


func _on_clear_alpha_mask() -> void:
	if _alpha_mask_image != null:
		_alpha_mask_image.fill(Color(1, 1, 1))
		_anchor_overlay.queue_redraw()


func _style_anchor_button(btn: Button, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.2)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", sb)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(color, 0.35)
	hover_sb.set_border_width_all(2)
	hover_sb.border_color = color
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb := StyleBoxFlat.new()
	pressed_sb.bg_color = Color(color, 0.5)
	pressed_sb.set_border_width_all(2)
	pressed_sb.border_color = Color.WHITE
	pressed_sb.set_corner_radius_all(4)
	pressed_sb.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


#===============================================================================
# EXPORT
#===============================================================================

func _export_weapon() -> void:
	if _processed_image == null:
		_set_status("Error: No processed image to export.")
		return
	if _weapon_id.is_empty():
		_set_status("Error: Set a weapon ID first.")
		return
	if _grip_point == Vector2i(-1, -1):
		_set_status("Error: Place the grip point first.")
		return
	if _tip_point == Vector2i(-1, -1):
		_set_status("Error: Place the tip point first.")
		return

	var res_dir: String = WEAPONS_DIR + "/" + _weapon_id
	var global_dir: String = ProjectSettings.globalize_path(res_dir)
	DirAccess.make_dir_recursive_absolute(global_dir)

	# Save processed pixel art
	var png_res_path: String = res_dir + "/weapon.png"
	var png_global_path: String = ProjectSettings.globalize_path(png_res_path)
	var save_err := _processed_image.save_png(png_global_path)
	if save_err != OK:
		_set_status("Error: Failed to save weapon.png (err %d)" % save_err)
		return

	# Save alpha mask if custom values exist
	var has_alpha := _has_custom_alpha()
	if _alpha_mask_image != null and has_alpha:
		var alpha_res_path: String = res_dir + "/alpha_mask.png"
		var alpha_global_path: String = ProjectSettings.globalize_path(alpha_res_path)
		var alpha_err := _alpha_mask_image.save_png(alpha_global_path)
		if alpha_err != OK:
			_set_status("Error: Failed to save alpha_mask.png (err %d)" % alpha_err)
			return

	# Build and save metadata
	var metadata := {
		"weapon_id": _weapon_id,
		"category": _weapon_category,
		"grip": [_grip_point.x, _grip_point.y],
		"tip": [_tip_point.x, _tip_point.y],
		"source_size": [_source_image.get_width(), _source_image.get_height()],
		"export_size": [_processed_image.get_width(), _processed_image.get_height()],
		"has_alpha_mask": has_alpha,
		"processing": {
			"target_height": _target_height,
			"alpha_threshold": _alpha_threshold,
			"dithering_enabled": _dithering_enabled,
			"dithering_strength": _dithering_strength,
			"dithering_pattern": _dithering_pattern,
			"palette_enabled": _palette_enabled,
			"palette_path": _palette_path,
			"outline_enabled": _outline_enabled,
			"outline_color": "#%s" % _outline_color.to_html(false),
			"denoising_enabled": _denoising_enabled,
			"denoising_min_cluster": _denoising_min_cluster,
		},
	}

	var json_res_path: String = res_dir + "/metadata.json"
	var json_global_path: String = ProjectSettings.globalize_path(json_res_path)
	var json_str: String = JSON.stringify(metadata, "\t")
	var file := FileAccess.open(json_global_path, FileAccess.WRITE)
	if file == null:
		_set_status("Error: Could not write metadata.json")
		return
	file.store_string(json_str)
	file.close()

	var export_files := "  weapon.png (%dx%d)\n  metadata.json" % [
		_processed_image.get_width(), _processed_image.get_height(),
	]
	if has_alpha:
		export_files += "\n  alpha_mask.png"
	_export_status_label.text = "Exported to:\n%s/\n%s" % [res_dir, export_files]
	_export_status_label.add_theme_color_override("font_color", C_SUCCESS)
	_set_status("Done! Exported to %s" % res_dir)
	print("WeaponPipeline: Exported to %s" % res_dir)


func _has_custom_alpha() -> bool:
	if _alpha_mask_image == null:
		return false
	for y in range(_alpha_mask_image.get_height()):
		for x in range(_alpha_mask_image.get_width()):
			if _alpha_mask_image.get_pixel(x, y).r < 0.99:
				return true
	return false


#===============================================================================
# STATUS
#===============================================================================

func _set_status(text: String) -> void:
	_status_label.text = text
	if text.begins_with("Error") or text.begins_with("Failed"):
		_status_label.add_theme_color_override("font_color", C_WARNING)
	elif text.begins_with("Done") or text.begins_with("Saved") or text.begins_with("Export"):
		_status_label.add_theme_color_override("font_color", C_SUCCESS)
	else:
		_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	print("[WeaponPipeline] %s" % text)


#===============================================================================
# THEME BUILDER
#===============================================================================

func _build_theme() -> Theme:
	var t := Theme.new()

	# PanelContainer
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_PANEL
	panel_sb.set_corner_radius_all(0)
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	# Button: normal
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = C_SURFACE
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = C_BORDER
	btn_normal.set_corner_radius_all(4)
	btn_normal.set_content_margin_all(8)
	t.set_stylebox("normal", "Button", btn_normal)

	# Button: hover
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = C_SURFACE_HOVER
	btn_hover.set_border_width_all(1)
	btn_hover.border_color = C_BORDER
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(8)
	t.set_stylebox("hover", "Button", btn_hover)

	# Button: pressed
	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = C_ACCENT
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.set_content_margin_all(8)
	t.set_stylebox("pressed", "Button", btn_pressed)

	# Button: disabled
	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(C_SURFACE, 0.3)
	btn_disabled.set_corner_radius_all(4)
	btn_disabled.set_content_margin_all(8)
	t.set_stylebox("disabled", "Button", btn_disabled)

	# Button: focus
	var btn_focus := StyleBoxEmpty.new()
	t.set_stylebox("focus", "Button", btn_focus)

	# Button colors
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", C_TEXT_DIM)

	# OptionButton
	t.set_stylebox("normal", "OptionButton", btn_normal)
	t.set_stylebox("hover", "OptionButton", btn_hover)
	t.set_stylebox("pressed", "OptionButton", btn_pressed)
	t.set_stylebox("focus", "OptionButton", btn_focus)
	t.set_color("font_color", "OptionButton", C_TEXT)
	t.set_color("font_hover_color", "OptionButton", C_TEXT)

	# CheckButton
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_color("font_hover_color", "CheckButton", C_TEXT)
	t.set_color("font_pressed_color", "CheckButton", C_ACCENT)

	# Label
	t.set_color("font_color", "Label", C_TEXT)
	t.set_font_size("font_size", "Label", FONT_LABEL)

	# HSlider
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = C_BORDER
	slider_bg.set_content_margin_all(0)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider_bg)

	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = C_ACCENT
	slider_fill.set_content_margin_all(0)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", slider_fill)

	# LineEdit / SpinBox
	var line_edit_sb := StyleBoxFlat.new()
	line_edit_sb.bg_color = C_SURFACE
	line_edit_sb.set_border_width_all(1)
	line_edit_sb.border_color = C_BORDER
	line_edit_sb.set_corner_radius_all(4)
	line_edit_sb.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", line_edit_sb)
	t.set_stylebox("focus", "LineEdit", line_edit_sb)
	t.set_color("font_color", "LineEdit", C_TEXT)

	# ScrollContainer
	var scroll_sb := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", scroll_sb)

	# HSeparator
	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_BORDER
	sep_sb.set_content_margin_all(0)
	sep_sb.content_margin_top = 4
	sep_sb.content_margin_bottom = 4
	t.set_stylebox("separator", "HSeparator", sep_sb)
	t.set_constant("separation", "HSeparator", 1)

	return t


#===============================================================================
# STYLED HELPERS
#===============================================================================

func _make_section(title_text: String) -> Array:
	## Returns [section_container, content_vbox].
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = title_text
	header.add_theme_font_size_override("font_size", FONT_SECTION)
	header.add_theme_color_override("font_color", C_ACCENT)
	outer.add_child(header)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SECTION
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	outer.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_child(content)

	return [outer, content]


func _make_field(label_text: String, control: Control) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var lbl := _make_label(label_text)
	vbox.add_child(lbl)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(control)
	return vbox


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", FONT_LABEL)
	return l


func _make_small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FONT_HINT)
	l.add_theme_color_override("font_color", C_TEXT_DIM)
	return l


func _make_slider_row(min_val: float, max_val: float, default_val: float, step_val: float) -> Array:
	## Returns [HBoxContainer, HSlider, Label].
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step_val
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var val_label := Label.new()
	val_label.custom_minimum_size.x = 40
	val_label.add_theme_font_size_override("font_size", FONT_VALUE)
	val_label.add_theme_color_override("font_color", C_TEXT_DIM)
	hbox.add_child(val_label)

	if step_val >= 1.0:
		val_label.text = str(int(default_val))
	else:
		val_label.text = "%.2f" % default_val

	slider.value_changed.connect(func(v: float) -> void:
		if step_val >= 1.0:
			val_label.text = str(int(v))
		else:
			val_label.text = "%.2f" % v
	)

	return [hbox, slider, val_label]


func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = C_ACCENT_HOVER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	hover_sb.content_margin_top = 12
	hover_sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn


func _make_subtle_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_border_width_all(1)
	sb.border_color = C_BORDER
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(C_SURFACE, 0.5)
	hover_sb.set_border_width_all(1)
	hover_sb.border_color = C_BORDER
	hover_sb.set_corner_radius_all(4)
	hover_sb.set_content_margin_all(10)
	hover_sb.content_margin_top = 12
	hover_sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("hover", hover_sb)
	return btn
