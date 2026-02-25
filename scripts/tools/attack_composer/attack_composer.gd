extends Control
## Attack Composer — A timeline/track editor tool for visually authoring
## melee attack animations with per-frame timing, weapon visibility,
## effects, speed echoes, and movement.

# ── Theme constants (matches Sprite Pipeline) ──────────────────────────
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

const SPRITES_BASE := "res://assets/sprites/final"

# ── State ──────────────────────────────────────────────────────────────
var _current_composition: AttackCompositionData = null
var _frame_images: Dictionary = {}  # {direction_string: Array[Image]}
var _frame_textures: Dictionary = {}  # {direction_string: Array[ImageTexture]}
var _preview_direction := "down"
var _preview_frame_index: int = 0
var _selected_frame: int = -1
var _available_models: Array[String] = []
var _available_anims: Array[String] = []
var _current_model: String = ""
var _current_anim: String = ""
var _frame_size: Vector2i = Vector2i.ZERO

# ── UI references ──────────────────────────────────────────────────────
var _status_label: Label
var _left_scroll_content: VBoxContainer
var _right_vbox: VBoxContainer
var _preview_placeholder: PanelContainer
var _timeline_placeholder: PanelContainer
var _model_dropdown: OptionButton
var _anim_dropdown: OptionButton
var _load_info_label: Label
var _frame_props_container: VBoxContainer

const DIRECTIONS := ["down", "up", "right"]


func _ready() -> void:
	_build_ui()
	_build_loading_section()
	_build_frame_props_section()
	_scan_animations()
	_set_status("Ready. Select a model and animation to begin.")


# ── UI Construction ────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Root HBox
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# ── Left Panel ─────────────────────────────────────────────────────
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 300
	left_panel.size_flags_horizontal = SIZE_FILL
	var left_sb := StyleBoxFlat.new()
	left_sb.bg_color = C_PANEL
	left_sb.border_width_right = 1
	left_sb.border_color = C_BORDER
	left_panel.add_theme_stylebox_override("panel", left_sb)
	root_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 0)
	left_panel.add_child(left_vbox)

	# Title
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 16)
	title_margin.add_theme_constant_override("margin_right", 16)
	title_margin.add_theme_constant_override("margin_top", 12)
	title_margin.add_theme_constant_override("margin_bottom", 12)
	left_vbox.add_child(title_margin)

	var title := Label.new()
	title.text = "Attack Composer"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	left_vbox.add_child(sep)

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.add_theme_constant_override("margin_left", 12)
	scroll_margin.add_theme_constant_override("margin_right", 12)
	scroll_margin.add_theme_constant_override("margin_top", 8)
	scroll_margin.add_theme_constant_override("margin_bottom", 8)
	scroll_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(scroll_margin)

	_left_scroll_content = VBoxContainer.new()
	_left_scroll_content.add_theme_constant_override("separation", 8)
	_left_scroll_content.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_margin.add_child(_left_scroll_content)

	# Bottom separator
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _make_separator_style())
	left_vbox.add_child(sep2)

	# Status bar
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 12)
	status_margin.add_theme_constant_override("margin_right", 12)
	status_margin.add_theme_constant_override("margin_top", 6)
	status_margin.add_theme_constant_override("margin_bottom", 6)
	left_vbox.add_child(status_margin)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_margin.add_child(_status_label)

	# ── Right Panel ────────────────────────────────────────────────────
	_right_vbox = VBoxContainer.new()
	_right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	_right_vbox.add_theme_constant_override("separation", 0)
	root_hbox.add_child(_right_vbox)

	# Preview placeholder (top ~60%)
	_preview_placeholder = PanelContainer.new()
	_preview_placeholder.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_placeholder.size_flags_stretch_ratio = 0.6
	var preview_sb := StyleBoxFlat.new()
	preview_sb.bg_color = C_SECTION
	preview_sb.border_width_bottom = 1
	preview_sb.border_color = C_BORDER
	_preview_placeholder.add_theme_stylebox_override("panel", preview_sb)
	_right_vbox.add_child(_preview_placeholder)

	var preview_label := Label.new()
	preview_label.text = "Preview"
	preview_label.add_theme_font_size_override("font_size", FONT_SECTION)
	preview_label.add_theme_color_override("font_color", C_TEXT_DIM)
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_label.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_placeholder.add_child(preview_label)

	# Timeline placeholder (bottom ~40%)
	_timeline_placeholder = PanelContainer.new()
	_timeline_placeholder.size_flags_vertical = SIZE_EXPAND_FILL
	_timeline_placeholder.size_flags_stretch_ratio = 0.4
	var timeline_sb := StyleBoxFlat.new()
	timeline_sb.bg_color = C_BG
	_timeline_placeholder.add_theme_stylebox_override("panel", timeline_sb)
	_right_vbox.add_child(_timeline_placeholder)

	var timeline_label := Label.new()
	timeline_label.text = "Timeline"
	timeline_label.add_theme_font_size_override("font_size", FONT_SECTION)
	timeline_label.add_theme_color_override("font_color", C_TEXT_DIM)
	timeline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timeline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timeline_label.size_flags_horizontal = SIZE_EXPAND_FILL
	timeline_label.size_flags_vertical = SIZE_EXPAND_FILL
	_timeline_placeholder.add_child(timeline_label)


# ── Helpers ────────────────────────────────────────────────────────────

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _make_separator_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BORDER
	sb.content_margin_top = 0.5
	sb.content_margin_bottom = 0.5
	return sb


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SECTION)
	label.add_theme_color_override("font_color", C_ACCENT)
	return label


func _make_label(text: String, color: Color = C_TEXT_SEC) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, callable: Callable, accent: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_LABEL)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT if accent else C_SURFACE
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = C_ACCENT_HOVER if accent else C_SURFACE_HOVER
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.pressed.connect(callable)
	return btn


func _make_option_button() -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FONT_LABEL)
	opt.add_theme_color_override("font_color", C_TEXT)
	opt.size_flags_horizontal = SIZE_EXPAND_FILL
	return opt


# ── Loading Section ────────────────────────────────────────────────────

func _build_loading_section() -> void:
	_left_scroll_content.add_child(_make_section_label("Spritesheet"))

	# Animation dropdown (folder names like Slash, Blocking, etc.)
	_left_scroll_content.add_child(_make_label("Animation"))
	_anim_dropdown = _make_option_button()
	_anim_dropdown.item_selected.connect(_on_anim_selected)
	_left_scroll_content.add_child(_anim_dropdown)

	# Model dropdown (model prefixes within animation folder)
	_left_scroll_content.add_child(_make_label("Model"))
	_model_dropdown = _make_option_button()
	_left_scroll_content.add_child(_model_dropdown)

	# Load button
	_left_scroll_content.add_child(_make_button("Load Spritesheet", _on_load_pressed, true))

	# Info label
	_load_info_label = _make_label("", C_TEXT_DIM)
	_load_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_scroll_content.add_child(_load_info_label)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	_left_scroll_content.add_child(sep)


func _build_frame_props_section() -> void:
	_frame_props_container = VBoxContainer.new()
	_frame_props_container.add_theme_constant_override("separation", 6)
	_frame_props_container.visible = false
	_left_scroll_content.add_child(_frame_props_container)


func _scan_animations() -> void:
	_anim_dropdown.clear()
	_available_anims.clear()

	var dir := DirAccess.open(SPRITES_BASE)
	if dir == null:
		_set_status("Sprites folder not found: %s" % SPRITES_BASE)
		return

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			_available_anims.append(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	_available_anims.sort()
	for anim_name in _available_anims:
		_anim_dropdown.add_item(anim_name)

	if not _available_anims.is_empty():
		_on_anim_selected(0)
	else:
		_set_status("No animation folders found in %s" % SPRITES_BASE)


func _on_anim_selected(index: int) -> void:
	if index < 0 or index >= _available_anims.size():
		return

	_model_dropdown.clear()
	_available_models.clear()

	var anim_folder: String = _available_anims[index]
	var folder_path := "%s/%s" % [SPRITES_BASE, anim_folder]
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return

	# Parse filenames to find model prefixes: {model}_{direction}.png
	var model_set := {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png") and not file_name.ends_with("_normal.png") and not file_name.ends_with("_shadow.png"):
			# Strip .png and try to extract model prefix
			var base := file_name.get_basename()
			for direction in DIRECTIONS:
				var suffix := "_%s" % direction
				if base.ends_with(suffix):
					var model := base.substr(0, base.length() - suffix.length())
					model_set[model] = true
					break
		file_name = dir.get_next()
	dir.list_dir_end()

	for model in model_set.keys():
		_available_models.append(model)
	_available_models.sort()

	for model in _available_models:
		_model_dropdown.add_item(model)


func _on_load_pressed() -> void:
	var anim_idx := _anim_dropdown.selected
	var model_idx := _model_dropdown.selected
	if anim_idx < 0 or model_idx < 0:
		_set_status("Select an animation and model first.")
		return

	var anim_folder: String = _available_anims[anim_idx]
	var model_name: String = _available_models[model_idx]
	_current_anim = anim_folder
	_current_model = model_name

	_frame_images.clear()
	_frame_textures.clear()
	var frame_count := -1

	for direction in DIRECTIONS:
		var path := "%s/%s/%s_%s.png" % [SPRITES_BASE, anim_folder, model_name, direction]
		if not ResourceLoader.exists(path):
			_set_status("Missing spritesheet: %s" % path)
			return

		var tex := load(path) as Texture2D
		if tex == null:
			_set_status("Failed to load: %s" % path)
			return

		var sheet_image := tex.get_image()
		if sheet_image == null:
			_set_status("Failed to get image data from: %s" % path)
			return

		# Square frames: frame_width = sheet_height
		var sheet_w := sheet_image.get_width()
		var sheet_h := sheet_image.get_height()
		var fw := sheet_h  # Square frames
		var count := sheet_w / fw

		if frame_count < 0:
			frame_count = count
			_frame_size = Vector2i(fw, sheet_h)
		elif count != frame_count:
			_set_status("Frame count mismatch: %s has %d frames (expected %d)" % [direction, count, frame_count])
			return

		# Extract individual frames
		var images: Array[Image] = []
		var textures: Array[ImageTexture] = []
		for i in count:
			var frame_img := Image.create(fw, sheet_h, false, sheet_image.get_format())
			frame_img.blit_rect(sheet_image, Rect2i(i * fw, 0, fw, sheet_h), Vector2i.ZERO)
			images.append(frame_img)
			textures.append(ImageTexture.create_from_image(frame_img))

		_frame_images[direction] = images
		_frame_textures[direction] = textures

	# Create default composition
	_current_composition = AttackCompositionData.create_default(frame_count)
	_current_composition.animation_name = anim_folder.to_lower()
	_current_composition.composition_id = "%s_%s" % [model_name, anim_folder.to_lower()]
	_current_composition.display_name = "%s %s" % [model_name, anim_folder]

	_preview_frame_index = 0
	_selected_frame = 0

	_load_info_label.text = "Loaded: %s (%d frames, %dx%d)" % [anim_folder, frame_count, _frame_size.x, _frame_size.y]
	_set_status("Spritesheet loaded. %d frames at %dx%d." % [frame_count, _frame_size.x, _frame_size.y])

	_on_spritesheet_loaded()


func _on_spritesheet_loaded() -> void:
	# Will be expanded by later tasks (preview, timeline, etc.)
	pass
