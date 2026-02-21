extends Control
## Pixel Art Converter Tool
##
## Converts high-res captured spritesheets into pixel art using downscaling,
## alpha thresholding, palette mapping, dithering, outlines, and denoising.
##
## Workflow:
##   1. Run scenes/tools/sprite_capture.tscn to produce high-res spritesheets
##   2. Run scenes/tools/pixel_art_converter.tscn (this tool)
##   3. Select source folder and spritesheet, configure settings
##   4. Export — get pixel-art-ready PNGs in assets/sprites/final/
##
## Input:  Horizontal spritesheets in assets/sprites/captures/{folder}/
## Output: Processed PNGs in assets/sprites/final/{folder}/

#===============================================================================
# CONSTANTS
#===============================================================================

const CAPTURES_DIR := "res://assets/sprites/captures"
const OUTPUT_BASE := "res://assets/sprites/final"
const PALETTE_DIR := "res://assets/palettes"

#===============================================================================
# NODE REFERENCES
#===============================================================================

var folder_dropdown: OptionButton
var file_dropdown: OptionButton
var palette_dropdown: OptionButton
var palette_preview_container: HFlowContainer
var output_height_spin: SpinBox
var alpha_threshold_slider: HSlider
var alpha_threshold_label: Label
var dithering_toggle: CheckButton
var dithering_strength_slider: HSlider
var dithering_pattern_dropdown: OptionButton
var outline_toggle: CheckButton
var outline_color_picker: ColorPickerButton
var denoising_toggle: CheckButton
var denoising_min_cluster_spin: SpinBox
var show_original_toggle: CheckButton
var export_button: Button
var export_all_button: Button
var status_label: Label
var preview_texture_rect: TextureRect

## State
var _source_image: Image = null
var _palette_colors: PackedColorArray = PackedColorArray()

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_scan_source_folders()


func _build_ui() -> void:
	## Build the configuration UI on the left side, preview on the right
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 12)
	add_child(root_hbox)

	# Left panel — controls
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280
	root_hbox.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Pixel Art Converter"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Source folder selector
	vbox.add_child(_make_label("Source folder:"))
	folder_dropdown = OptionButton.new()
	folder_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	folder_dropdown.item_selected.connect(_on_folder_selected)
	vbox.add_child(folder_dropdown)

	# Spritesheet file selector
	vbox.add_child(_make_label("Spritesheet file:"))
	file_dropdown = OptionButton.new()
	file_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	file_dropdown.item_selected.connect(_on_file_selected)
	vbox.add_child(file_dropdown)

	vbox.add_child(HSeparator.new())

	# Palette dropdown (scanned from assets/palettes/)
	vbox.add_child(_make_label("Palette:"))
	palette_dropdown = OptionButton.new()
	palette_dropdown.size_flags_horizontal = SIZE_EXPAND_FILL
	palette_dropdown.item_selected.connect(_on_palette_dropdown_selected)
	vbox.add_child(palette_dropdown)

	# Load palette button
	var load_palette_btn := Button.new()
	load_palette_btn.text = "Load Palette (.png)..."
	load_palette_btn.pressed.connect(_on_load_palette_pressed)
	vbox.add_child(load_palette_btn)

	# Palette preview swatches
	palette_preview_container = HFlowContainer.new()
	palette_preview_container.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(palette_preview_container)

	# Output height
	vbox.add_child(_make_label("Output height (px):"))
	output_height_spin = SpinBox.new()
	output_height_spin.min_value = 16
	output_height_spin.max_value = 256
	output_height_spin.value = 64
	output_height_spin.step = 8
	output_height_spin.value_changed.connect(_on_setting_changed)
	vbox.add_child(output_height_spin)

	# Alpha threshold
	vbox.add_child(_make_label("Alpha threshold:"))
	var alpha_hbox := HBoxContainer.new()
	vbox.add_child(alpha_hbox)
	alpha_threshold_slider = HSlider.new()
	alpha_threshold_slider.min_value = 0
	alpha_threshold_slider.max_value = 255
	alpha_threshold_slider.value = 128
	alpha_threshold_slider.step = 1
	alpha_threshold_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	alpha_threshold_slider.value_changed.connect(_on_alpha_threshold_changed)
	alpha_hbox.add_child(alpha_threshold_slider)
	alpha_threshold_label = Label.new()
	alpha_threshold_label.text = "128"
	alpha_threshold_label.custom_minimum_size.x = 30
	alpha_hbox.add_child(alpha_threshold_label)

	vbox.add_child(HSeparator.new())

	# Dithering
	dithering_toggle = CheckButton.new()
	dithering_toggle.text = "Dithering"
	dithering_toggle.toggled.connect(_on_toggle_changed)
	vbox.add_child(dithering_toggle)

	vbox.add_child(_make_label("  Strength:"))
	dithering_strength_slider = HSlider.new()
	dithering_strength_slider.min_value = 0.0
	dithering_strength_slider.max_value = 1.0
	dithering_strength_slider.value = 0.5
	dithering_strength_slider.step = 0.05
	dithering_strength_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	dithering_strength_slider.value_changed.connect(_on_setting_changed)
	vbox.add_child(dithering_strength_slider)

	vbox.add_child(_make_label("  Pattern:"))
	dithering_pattern_dropdown = OptionButton.new()
	dithering_pattern_dropdown.add_item("2x2")
	dithering_pattern_dropdown.add_item("4x4")
	dithering_pattern_dropdown.add_item("8x8")
	dithering_pattern_dropdown.selected = 1  # Default to 4x4
	dithering_pattern_dropdown.item_selected.connect(_on_setting_changed)
	vbox.add_child(dithering_pattern_dropdown)

	# Outline
	outline_toggle = CheckButton.new()
	outline_toggle.text = "Outline"
	outline_toggle.toggled.connect(_on_toggle_changed)
	vbox.add_child(outline_toggle)

	var outline_hbox := HBoxContainer.new()
	vbox.add_child(outline_hbox)
	outline_hbox.add_child(_make_label("  Color: "))
	outline_color_picker = ColorPickerButton.new()
	outline_color_picker.color = Color.BLACK
	outline_color_picker.custom_minimum_size = Vector2(40, 30)
	outline_color_picker.color_changed.connect(_on_color_changed)
	outline_hbox.add_child(outline_color_picker)

	# Denoising
	denoising_toggle = CheckButton.new()
	denoising_toggle.text = "Denoising"
	denoising_toggle.toggled.connect(_on_toggle_changed)
	vbox.add_child(denoising_toggle)

	var denoise_hbox := HBoxContainer.new()
	vbox.add_child(denoise_hbox)
	denoise_hbox.add_child(_make_label("  Min cluster: "))
	denoising_min_cluster_spin = SpinBox.new()
	denoising_min_cluster_spin.min_value = 1
	denoising_min_cluster_spin.max_value = 50
	denoising_min_cluster_spin.value = 2
	denoising_min_cluster_spin.step = 1
	denoising_min_cluster_spin.value_changed.connect(_on_setting_changed)
	denoise_hbox.add_child(denoising_min_cluster_spin)

	vbox.add_child(HSeparator.new())

	# Export buttons
	export_button = Button.new()
	export_button.text = "Export Selected"
	export_button.pressed.connect(_on_export_pressed)
	vbox.add_child(export_button)

	export_all_button = Button.new()
	export_all_button.text = "Export All in Folder"
	export_all_button.pressed.connect(_on_export_all_pressed)
	vbox.add_child(export_all_button)

	vbox.add_child(HSeparator.new())

	# Status
	status_label = Label.new()
	status_label.text = "Select a source folder to begin."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(status_label)

	# Right side — preview with show-original toggle
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_hbox.add_child(right_vbox)

	show_original_toggle = CheckButton.new()
	show_original_toggle.text = "Show Original"
	show_original_toggle.toggled.connect(_on_show_original_toggled)
	right_vbox.add_child(show_original_toggle)

	var preview_scroll := ScrollContainer.new()
	preview_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	right_vbox.add_child(preview_scroll)

	preview_texture_rect = TextureRect.new()
	preview_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_texture_rect.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_texture_rect.size_flags_vertical = SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_texture_rect)


#===============================================================================
# FILE SCANNING
#===============================================================================

func _scan_source_folders() -> void:
	folder_dropdown.clear()

	var global_dir := ProjectSettings.globalize_path(CAPTURES_DIR)
	var dir := DirAccess.open(global_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(global_dir)
		_set_status("Created %s — run sprite_capture.tscn first to generate spritesheets." % CAPTURES_DIR)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			folder_dropdown.add_item(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	if folder_dropdown.item_count > 0:
		_on_folder_selected(0)
	else:
		_set_status("No capture folders found in %s" % CAPTURES_DIR)


func _on_folder_selected(index: int) -> void:
	file_dropdown.clear()
	_source_image = null

	var folder_name: String = folder_dropdown.get_item_text(index)
	var folder_path := "%s/%s" % [CAPTURES_DIR, folder_name]
	var global_dir := ProjectSettings.globalize_path(folder_path)

	var dir := DirAccess.open(global_dir)
	if dir == null:
		_set_status("ERROR: Could not open %s" % folder_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".png") and not file_name.ends_with(".import"):
			file_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if file_dropdown.item_count > 0:
		_set_status("Found %d file(s) in %s" % [file_dropdown.item_count, folder_name])
		_on_file_selected(0)
	else:
		_set_status("No PNG files found in %s" % folder_name)


func _on_file_selected(index: int) -> void:
	if index < 0 or index >= file_dropdown.item_count:
		return

	var folder_name: String = folder_dropdown.get_item_text(folder_dropdown.selected)
	var file_name: String = file_dropdown.get_item_text(index)
	var file_path := "%s/%s/%s" % [CAPTURES_DIR, folder_name, file_name]
	var global_path := ProjectSettings.globalize_path(file_path)

	_source_image = Image.new()
	var err := _source_image.load(global_path)
	if err != OK:
		_set_status("ERROR: Could not load %s (error %d)" % [file_path, err])
		_source_image = null
		return

	_set_status("Loaded: %s (%dx%d)" % [file_name, _source_image.get_width(), _source_image.get_height()])
	_update_preview()


#===============================================================================
# PREVIEW
#===============================================================================

func _update_preview() -> void:
	if _source_image == null:
		return
	if show_original_toggle.button_pressed:
		var tex := ImageTexture.create_from_image(_source_image)
		preview_texture_rect.texture = tex
		return
	var processed := _process_image(_source_image)
	var tex := ImageTexture.create_from_image(processed)
	preview_texture_rect.texture = tex


func _process_image(source: Image) -> Image:
	var result := source.duplicate() as Image

	# Step 1: Downscale
	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	# Step 2: Alpha threshold
	var threshold := int(alpha_threshold_slider.value)
	_apply_alpha_threshold(result, threshold)

	# Step 3: Palette mapping
	_apply_palette_mapping(result)

	return result


func _apply_alpha_threshold(image: Image, threshold: int) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if int(color.a * 255.0) >= threshold:
				color.a = 1.0
			else:
				color.a = 0.0
			image.set_pixel(x, y, color)


#===============================================================================
# SIGNAL CALLBACKS
#===============================================================================

func _on_alpha_threshold_changed(value: float) -> void:
	alpha_threshold_label.text = str(int(value))
	_update_preview()


func _on_setting_changed(_value) -> void:
	_update_preview()


func _on_toggle_changed(_enabled: bool) -> void:
	_update_preview()


func _on_color_changed(_color: Color) -> void:
	_update_preview()


func _on_show_original_toggled(enabled: bool) -> void:
	_update_preview()


#===============================================================================
# PALETTE
#===============================================================================

func _on_load_palette_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png ; PNG Palette"])
	dialog.file_selected.connect(_on_palette_file_selected)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_palette_file_selected(path: String) -> void:
	_load_palette_from_path(path)


func _load_palette_from_path(path: String) -> void:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		_set_status("ERROR: Could not load palette from %s" % path)
		return

	_palette_colors.clear()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a > 0.5 and not _palette_colors.has(color):
				_palette_colors.append(color)

	_set_status("Loaded palette: %d colors" % _palette_colors.size())
	_update_palette_preview()
	_update_preview()


func _update_palette_preview() -> void:
	for child in palette_preview_container.get_children():
		child.queue_free()
	for color in _palette_colors:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = color
		palette_preview_container.add_child(swatch)


func _on_palette_dropdown_selected(_index: int) -> void:
	pass  # Implemented in Task 8


func _apply_palette_mapping(image: Image) -> void:
	if _palette_colors.is_empty():
		return
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			var nearest := _find_nearest_palette_color(color)
			nearest.a = 1.0
			image.set_pixel(x, y, nearest)


func _find_nearest_palette_color(target: Color) -> Color:
	var best_color := _palette_colors[0]
	var best_dist := _color_distance_sq(target, best_color)
	for i in range(1, _palette_colors.size()):
		var dist := _color_distance_sq(target, _palette_colors[i])
		if dist < best_dist:
			best_dist = dist
			best_color = _palette_colors[i]
	return best_color


func _color_distance_sq(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db


#===============================================================================
# EXPORT
#===============================================================================

func _on_export_pressed() -> void:
	pass  # Implemented in Task 7


func _on_export_all_pressed() -> void:
	pass  # Implemented in Task 7


#===============================================================================
# UTILS
#===============================================================================

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _set_status(text: String) -> void:
	status_label.text = text
	print("[PixelArtConverter] %s" % text)
