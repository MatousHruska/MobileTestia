extends CharacterMenuPopup
class_name ItemPopup
## ItemPopup - Shows item details in a popup at tap position

#===============================================================================
# CONSTANTS
#===============================================================================

const POPUP_WIDTH := 280
const POPUP_MIN_HEIGHT := 100
const POPUP_MAX_HEIGHT := 320
const ICON_SIZE := 48

## Colors
const COLOR_DESCRIPTION := Color(0.8, 0.8, 0.8)
const COLOR_HINT := Color(0.5, 0.5, 0.5)
const COLOR_STAT := Color(0.7, 1.0, 0.7)

#===============================================================================
# STATE
#===============================================================================

var current_item: ItemData = null
var current_source: String = ""
var current_index: int = -1

#===============================================================================
# UI REFERENCES
#===============================================================================

var _icon: TextureRect
var _name_label: Label
var _type_label: Label
var _rarity_label: Label
var _stats_container: VBoxContainer
var _description_label: Label
var _hint_label: Label


#===============================================================================
# OVERRIDES
#===============================================================================

func _get_popup_width() -> int:
	return POPUP_WIDTH


func _get_popup_min_height() -> int:
	return POPUP_MIN_HEIGHT


func _get_popup_max_height() -> int:
	return POPUP_MAX_HEIGHT


func _create_icon_container() -> Control:
	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_bg.color = Color(0.2, 0.2, 0.25, 1)

	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 4
	_icon.offset_top = 4
	_icon.offset_right = -4
	_icon.offset_bottom = -4
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_bg.add_child(_icon)

	return icon_bg


func _build_header_content() -> VBoxContainer:
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	name_col.add_child(_name_label)

	_type_label = Label.new()
	_type_label.add_theme_font_size_override("font_size", 11)
	_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	name_col.add_child(_type_label)

	_rarity_label = Label.new()
	_rarity_label.add_theme_font_size_override("font_size", 11)
	name_col.add_child(_rarity_label)

	return name_col


func _build_content(content: VBoxContainer) -> void:
	# Stats container
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 2)
	content.add_child(_stats_container)

	# Description
	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.add_theme_font_size_override("font_size", 11)
	_description_label.add_theme_color_override("font_color", COLOR_DESCRIPTION)
	content.add_child(_description_label)

	# Hint text
	_hint_label = Label.new()
	_hint_label.text = "Drag items to move, equip, or destroy"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	content.add_child(_hint_label)


#===============================================================================
# PUBLIC API
#===============================================================================

## Show popup for an item at the given screen position
## If screen_pos is ZERO, keeps current position (for content updates)
func show_item(item: ItemData, source: String, index: int, screen_pos: Vector2 = Vector2.ZERO) -> void:
	if not item:
		return

	current_item = item
	current_source = source
	current_index = index

	_update_display()

	# Only reposition if a valid position was given
	if screen_pos != Vector2.ZERO:
		show_at(screen_pos)
	elif not visible:
		# If not visible and no position given, show at center
		var center := get_viewport().get_visible_rect().size / 2
		show_at(center)
	else:
		# Already visible, just update content (keep position)
		visible = true


## Override close to clear state and deselect inventory
func close() -> void:
	current_item = null
	current_source = ""
	current_index = -1
	Inventory.deselect()
	super.close()


#===============================================================================
# CONTENT UPDATE
#===============================================================================

func _update_display() -> void:
	if not current_item:
		return

	# Icon
	_icon.texture = current_item.icon

	# Name with rarity color
	_name_label.text = current_item.item_name
	_name_label.add_theme_color_override("font_color", ItemData.get_rarity_color(current_item.rarity))

	# Rarity
	_rarity_label.text = ItemData.get_rarity_name(current_item.rarity)
	_rarity_label.add_theme_color_override("font_color", ItemData.get_rarity_color(current_item.rarity))

	# Clear old stats
	for child in _stats_container.get_children():
		child.queue_free()

	# Type-specific display
	if current_item is EquipmentData:
		var equip: EquipmentData = current_item as EquipmentData
		_type_label.text = equip.get_type_name()
		_add_equipment_stats(equip)
	elif current_item is ConsumableData:
		var consumable: ConsumableData = current_item as ConsumableData
		_type_label.text = "Consumable"
		_add_consumable_stats(consumable)
	else:
		_type_label.text = "Item"

	# Description
	if current_item.description and current_item.description.length() > 0:
		_description_label.text = current_item.description
		_description_label.visible = true
	else:
		_description_label.visible = false


func _add_equipment_stats(equip: EquipmentData) -> void:
	var stat_text := equip.get_stat_text()
	if stat_text.is_empty():
		return

	# Parse stat text and add rows
	var lines := stat_text.split("\n")
	for line in lines:
		if line.is_empty():
			continue
		var stat_label := Label.new()
		stat_label.text = line
		stat_label.add_theme_font_size_override("font_size", 11)
		stat_label.add_theme_color_override("font_color", COLOR_STAT)
		_stats_container.add_child(stat_label)


func _add_consumable_stats(consumable: ConsumableData) -> void:
	var effect_text := consumable.get_effect_text()
	if effect_text.is_empty():
		return

	var effect_label := Label.new()
	effect_label.text = effect_text
	effect_label.add_theme_font_size_override("font_size", 11)
	effect_label.add_theme_color_override("font_color", COLOR_STAT)
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_container.add_child(effect_label)
