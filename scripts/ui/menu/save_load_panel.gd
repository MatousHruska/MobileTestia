extends PanelContainer
class_name SaveLoadPanel
## SaveLoadPanel - UI for save/load slot selection
## Shows 3 manual slots + 1 auto-save slot with metadata

signal slot_selected(slot: int)
signal cancelled

enum Mode { SAVE, LOAD }

## Current mode
var mode: Mode = Mode.SAVE

## References
var _title_label: Label
var _scroll: ScrollContainer
var _slots_container: VBoxContainer
var _cancel_button: Button
var _slot_buttons: Array[Control] = []

## Design constants
const MAX_HEIGHT_PCT := 0.85  # 85% of viewport height

## Get slot height from UITheme
func _get_slot_height() -> int:
	return UITheme.SLOT_SIZE_LARGE + UITheme.MARGIN_SMALL

## Get panel width from UITheme
func _get_panel_width() -> int:
	return UITheme.POPUP_WIDTH_LARGE


func _init() -> void:
	_setup_ui()


func _ready() -> void:
	_refresh_slots()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_size()


func _on_viewport_size_changed() -> void:
	_update_size()


func _update_size() -> void:
	## Constrain panel height to viewport
	var viewport_size := get_viewport().get_visible_rect().size
	var max_height := int(viewport_size.y * MAX_HEIGHT_PCT)

	var slot_h := _get_slot_height()
	var header_footer := UITheme.BUTTON_HEIGHT_LARGE * 2 + UITheme.MARGIN_STANDARD

	# Calculate content height needed
	var content_height := slot_h * 4 + header_footer  # 4 slots + header/footer
	var target_height := mini(content_height, max_height)

	# Update scroll container size
	if _scroll:
		var scroll_height := target_height - (UITheme.BUTTON_HEIGHT_LARGE * 2)
		_scroll.custom_minimum_size.y = scroll_height

	custom_minimum_size = Vector2(_get_panel_width(), 0)


func _setup_ui() -> void:
	## Build the save/load panel UI

	# Main panel style
	add_theme_stylebox_override("panel", UITheme.create_popup_style())

	# Main layout
	var margin := UITheme.create_margin_container()
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	UITheme.setup_vbox(main_vbox, UITheme.SEPARATION_NORMAL)
	margin.add_child(main_vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "Save Game"
	_title_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title_label.add_theme_color_override("font_color", UITheme.COLOR_SECTION_HEADER)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(_title_label)

	# Separator
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Scroll container for slots
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, _get_slot_height() * 4)
	main_vbox.add_child(_scroll)

	# Slots container
	_slots_container = VBoxContainer.new()
	_slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(_slots_container, UITheme.SEPARATION_SMALL)
	_scroll.add_child(_slots_container)

	# Bottom buttons
	var button_hbox := HBoxContainer.new()
	UITheme.setup_hbox(button_hbox)
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(button_hbox)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(UITheme.BUTTON_WIDTH_NORMAL, UITheme.BUTTON_HEIGHT_NORMAL)
	_cancel_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	_cancel_button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	button_hbox.add_child(_cancel_button)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	if _title_label:
		_title_label.text = "Save Game" if mode == Mode.SAVE else "Load Game"
	_refresh_slots()


func _refresh_slots() -> void:
	## Refresh all slot displays
	if not _slots_container:
		return

	# Clear existing slots
	for child in _slots_container.get_children():
		child.queue_free()
	_slot_buttons.clear()

	# Get all slot metadata
	var slots_data := SaveManager.get_all_slots_metadata()

	# Create slot buttons
	for slot_data in slots_data:
		var slot_button := _create_slot_button(slot_data)
		_slots_container.add_child(slot_button)
		_slot_buttons.append(slot_button)


func _create_slot_button(slot_data: Dictionary) -> Control:
	## Create a single save slot button

	var slot: int = slot_data.get("slot", 0)
	var is_auto_save: bool = slot_data.get("is_auto_save", false)
	var has_save: bool = slot_data.get("has_save", false) or is_auto_save and SaveManager.has_save(slot)

	# Button container
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, _get_slot_height())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Style
	var style := UITheme.create_button_style(false)
	style.set_content_margin_all(UITheme.MARGIN_SMALL)
	button.add_theme_stylebox_override("normal", style)

	var hover_style := UITheme.create_button_style(true)
	hover_style.set_content_margin_all(UITheme.MARGIN_SMALL)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)

	# Content layout
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.setup_hbox(hbox, UITheme.SEPARATION_NORMAL)
	button.add_child(hbox)

	# Slot icon/number
	var slot_icon := Label.new()
	slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_auto_save:
		slot_icon.text = "AUTO"
		slot_icon.add_theme_color_override("font_color", UITheme.COLOR_MANA)
	else:
		slot_icon.text = "Slot %d" % (slot + 1)
		slot_icon.add_theme_color_override("font_color", UITheme.COLOR_TEXT_VALUE)
	slot_icon.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	slot_icon.custom_minimum_size = Vector2(UITheme.LABEL_WIDTH_LARGE, 0)
	hbox.add_child(slot_icon)

	# Vertical separator
	var vsep := VSeparator.new()
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vsep)

	# Info section
	var info_vbox := VBoxContainer.new()
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(info_vbox, UITheme.SEPARATION_TINY)
	hbox.add_child(info_vbox)

	if has_save:
		# Has save data
		var player_level: int = slot_data.get("player_level", 1)
		var player_gold: int = slot_data.get("player_gold", 0)
		var zone: String = slot_data.get("zone", "Unknown")
		var playtime: float = slot_data.get("total_playtime", 0.0)
		var timestamp_str: String = slot_data.get("timestamp_str", "")
		var ng_plus: int = slot_data.get("ng_plus_count", 0)

		# Level and location line
		var line1 := Label.new()
		line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ng_text := " (NG+%d)" % ng_plus if ng_plus > 0 else ""
		line1.text = "Level %d%s - %s" % [player_level, ng_text, _format_zone_name(zone)]
		line1.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		line1.add_theme_color_override("font_color", UITheme.COLOR_TEXT_VALUE)
		info_vbox.add_child(line1)

		# Gold and playtime line
		var line2 := HBoxContainer.new()
		line2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.setup_hbox(line2, UITheme.SEPARATION_NORMAL)
		info_vbox.add_child(line2)

		var gold_label := Label.new()
		gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gold_label.text = "%d Gold" % player_gold
		gold_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		gold_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		line2.add_child(gold_label)

		var time_label := Label.new()
		time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		time_label.text = "Playtime: %s" % _format_playtime(playtime)
		time_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		time_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_LABEL)
		line2.add_child(time_label)

		# Timestamp line
		var line3 := Label.new()
		line3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line3.text = "Saved: %s" % _format_timestamp(timestamp_str)
		line3.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TINY)
		line3.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		info_vbox.add_child(line3)

	else:
		# Empty slot
		var empty_label := Label.new()
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_label.text = "- Empty Slot -"
		empty_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		empty_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info_vbox.add_child(empty_label)

	# Disable button for load mode on empty slots
	if mode == Mode.LOAD and not has_save:
		button.disabled = true
		button.modulate.a = 0.5

	# Connect signal
	button.pressed.connect(_on_slot_pressed.bind(slot))

	return button


func _format_zone_name(zone: String) -> String:
	## Format zone ID to readable name
	if zone.is_empty():
		return "Unknown"
	return zone.replace("_", " ").capitalize()


func _format_playtime(seconds: float) -> String:
	## Format playtime in hours:minutes:seconds
	var hours := int(seconds / 3600)
	var minutes := int(fmod(seconds, 3600) / 60)
	var secs := int(fmod(seconds, 60))

	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	else:
		return "%d:%02d" % [minutes, secs]


func _format_timestamp(timestamp_str: String) -> String:
	## Format timestamp for display
	if timestamp_str.is_empty():
		return "Unknown"
	# Shorten the timestamp (remove seconds if present)
	var parts := timestamp_str.split("T")
	if parts.size() >= 2:
		var date := parts[0]
		var time := parts[1].split(":").slice(0, 2)
		return "%s %s" % [date, ":".join(time)]
	return timestamp_str


func _on_slot_pressed(slot: int) -> void:
	## Handle slot button press
	Debug.info("UI", "Save slot pressed", { "slot": slot, "mode": Mode.keys()[mode] })

	if mode == Mode.SAVE:
		# Check if overwriting existing save
		if SaveManager.has_save(slot):
			_show_overwrite_confirm(slot)
		else:
			_perform_save(slot)
	else:
		# Load mode
		if SaveManager.has_save(slot):
			_perform_load(slot)


func _show_overwrite_confirm(slot: int) -> void:
	## Show confirmation dialog for overwriting save
	var dialog := ConfirmationDialog.new()
	dialog.title = "Overwrite Save?"
	dialog.dialog_text = "This will overwrite the existing save in Slot %d.\nAre you sure?" % (slot + 1)
	dialog.ok_button_text = "Overwrite"
	dialog.cancel_button_text = "Cancel"
	dialog.confirmed.connect(func(): _perform_save(slot); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _perform_save(slot: int) -> void:
	## Execute the save operation
	Debug.info("UI", "Performing save to slot", slot)

	var success := SaveManager.save_game(slot)
	if success:
		_show_message("Game Saved!", UITheme.COLOR_LEARNED)
		_refresh_slots()
	else:
		_show_message("Save Failed!", UITheme.COLOR_LIFE)


func _perform_load(slot: int) -> void:
	## Execute the load operation
	Debug.info("UI", "Performing load from slot", slot)

	var success := SaveManager.load_game(slot)
	if success:
		slot_selected.emit(slot)
	else:
		_show_message("Load Failed!", UITheme.COLOR_LIFE)


func _show_message(text: String, color: Color) -> void:
	## Show a temporary message
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LARGE)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-100, -20)
	label.z_index = 100
	add_child(label)

	# Fade out
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(0.5)
	tween.tween_callback(label.queue_free)


func _on_cancel_pressed() -> void:
	cancelled.emit()
