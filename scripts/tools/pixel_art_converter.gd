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
var generate_palette_button: Button
var max_palette_colors_spin: SpinBox
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
	_scan_palettes()
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

	# Generate palette from folder
	vbox.add_child(_make_label("Max palette colors:"))
	max_palette_colors_spin = SpinBox.new()
	max_palette_colors_spin.min_value = 4
	max_palette_colors_spin.max_value = 128
	max_palette_colors_spin.value = 32
	max_palette_colors_spin.step = 4
	vbox.add_child(max_palette_colors_spin)

	generate_palette_button = Button.new()
	generate_palette_button.text = "Generate Palette from Folder"
	generate_palette_button.pressed.connect(_on_generate_palette_pressed)
	vbox.add_child(generate_palette_button)

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
	denoising_min_cluster_spin.value = 4
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

	var target_height := int(output_height_spin.value)
	var scale_factor := float(target_height) / float(result.get_height())
	var target_width := int(float(result.get_width()) * scale_factor)
	result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)

	PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

	if dithering_toggle.button_pressed:
		PixelArtProcessing.apply_ordered_dithering(result, dithering_strength_slider.value, dithering_pattern_dropdown.selected)

	if not _palette_colors.is_empty():
		PixelArtProcessing.apply_palette_mapping(result, _palette_colors)
	elif dithering_toggle.button_pressed:
		PixelArtProcessing.apply_auto_quantize(result)

	if outline_toggle.button_pressed:
		PixelArtProcessing.apply_outline(result, outline_color_picker.color)

	if denoising_toggle.button_pressed:
		PixelArtProcessing.apply_denoising(result, int(denoising_min_cluster_spin.value))

	return result


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


func _on_palette_dropdown_selected(index: int) -> void:
	if index == 0:
		# "(none)" selected — clear palette
		_palette_colors.clear()
		_update_palette_preview()
		_update_preview()
		return
	var palette_name: String = palette_dropdown.get_item_text(index)
	var palette_path := "%s/%s" % [PALETTE_DIR, palette_name]
	var global_path := ProjectSettings.globalize_path(palette_path)
	_load_palette_from_path(global_path)


func _on_generate_palette_pressed() -> void:
	if folder_dropdown.item_count == 0:
		_set_status("ERROR: No source folder selected.")
		return

	var folder_name: String = folder_dropdown.get_item_text(folder_dropdown.selected)
	var folder_path := "%s/%s" % [CAPTURES_DIR, folder_name]
	var global_folder := ProjectSettings.globalize_path(folder_path)
	var max_colors := int(max_palette_colors_spin.value)

	_set_status("Generating palette from %s..." % folder_name)

	# Collect colors from all PNGs in folder (downscaled + thresholded only)
	var color_counts := {}  # Dictionary<Color, int>
	var dir := DirAccess.open(global_folder)
	if dir == null:
		_set_status("ERROR: Could not open %s" % folder_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".png") and not file_name.ends_with(".import"):
			var file_path := "%s/%s" % [folder_path, file_name]
			var global_path := ProjectSettings.globalize_path(file_path)
			var img := Image.new()
			if img.load(global_path) == OK:
				# Downscale + threshold (no palette mapping)
				var target_height := int(output_height_spin.value)
				var scale_factor := float(target_height) / float(img.get_height())
				var target_width := int(float(img.get_width()) * scale_factor)
				img.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
				PixelArtProcessing.apply_alpha_threshold(img, int(alpha_threshold_slider.value))

				for y in range(img.get_height()):
					for x in range(img.get_width()):
						var color := img.get_pixel(x, y)
						if color.a < 0.5:
							continue
						# Snap to 5-bit per channel to merge near-identical colors
						var snapped := Color(
							snappedf(color.r, 1.0 / 31.0),
							snappedf(color.g, 1.0 / 31.0),
							snappedf(color.b, 1.0 / 31.0),
							1.0
						)
						if color_counts.has(snapped):
							color_counts[snapped] += 1
						else:
							color_counts[snapped] = 1
		file_name = dir.get_next()
	dir.list_dir_end()

	if color_counts.is_empty():
		_set_status("ERROR: No opaque pixels found in folder.")
		return

	# Sort by frequency (most common first) and take top N
	var sorted_colors: Array = color_counts.keys()
	sorted_colors.sort_custom(func(a: Color, b: Color) -> bool:
		return color_counts[a] > color_counts[b]
	)

	var final_colors: PackedColorArray = PackedColorArray()
	for i in range(mini(max_colors, sorted_colors.size())):
		final_colors.append(sorted_colors[i])

	# Save as 1-row PNG strip to assets/palettes/
	var palette_image := Image.create(final_colors.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(final_colors.size()):
		palette_image.set_pixel(i, 0, final_colors[i])

	var palette_name := "%s_palette.png" % folder_name
	var output_path := "%s/%s" % [PALETTE_DIR, palette_name]
	var global_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PALETTE_DIR))

	var err := palette_image.save_png(global_output)
	if err != OK:
		_set_status("ERROR: Failed to save palette (error %d)" % err)
		return

	_set_status("Generated palette: %d colors -> %s" % [final_colors.size(), output_path])
	print("[PixelArtConverter] Saved palette: %s" % output_path)

	# Load it immediately
	_palette_colors = final_colors
	_update_palette_preview()
	_update_preview()

	# Refresh dropdown so the new palette appears
	_scan_palettes()
	# Select the new palette in the dropdown
	for i in range(palette_dropdown.item_count):
		if palette_dropdown.get_item_text(i) == palette_name:
			palette_dropdown.selected = i
			break


func _scan_palettes() -> void:
	palette_dropdown.clear()
	palette_dropdown.add_item("(none)")

	var global_dir := ProjectSettings.globalize_path(PALETTE_DIR)
	var dir := DirAccess.open(global_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(global_dir)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".png"):
			palette_dropdown.add_item(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


#===============================================================================
# EXPORT
#===============================================================================

func _on_export_pressed() -> void:
	if _source_image == null:
		_set_status("ERROR: No spritesheet loaded.")
		return

	export_button.disabled = true
	export_all_button.disabled = true

	var file_name: String = file_dropdown.get_item_text(file_dropdown.selected)
	_export_file(file_name)

	export_button.disabled = false
	export_all_button.disabled = false


func _on_export_all_pressed() -> void:
	if folder_dropdown.item_count == 0:
		_set_status("ERROR: No source folder selected.")
		return

	export_button.disabled = true
	export_all_button.disabled = true

	var count := 0
	for i in range(file_dropdown.item_count):
		var file_name: String = file_dropdown.get_item_text(i)
		_export_file(file_name)
		count += 1

	_set_status("Exported %d files!" % count)
	export_button.disabled = false
	export_all_button.disabled = false


func _export_file(file_name: String) -> void:
	var folder_name: String = folder_dropdown.get_item_text(folder_dropdown.selected)
	var source_path := "%s/%s/%s" % [CAPTURES_DIR, folder_name, file_name]

	var source := Image.new()
	var global_source := ProjectSettings.globalize_path(source_path)
	var err := source.load(global_source)
	if err != OK:
		_set_status("ERROR: Could not load %s (error %d)" % [source_path, err])
		return

	var processed := _process_image(source)

	var output_dir := "%s/%s" % [OUTPUT_BASE, folder_name]
	var global_output_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(global_output_dir)

	var output_path := "%s/%s" % [output_dir, file_name]
	var global_path := ProjectSettings.globalize_path(output_path)
	err = processed.save_png(global_path)
	if err != OK:
		_set_status("ERROR: Failed to save %s (error %d)" % [output_path, err])
		return

	_set_status("Exported: %s -> %s" % [file_name, output_path])
	print("[PixelArtConverter] Saved: %s" % output_path)


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
