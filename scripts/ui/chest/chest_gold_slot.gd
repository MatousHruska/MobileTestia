extends Button
class_name ChestGoldSlot
## Special slot for displaying and dragging gold from chests

signal gold_collected(amount: int)
signal slot_pressed(slot: ChestGoldSlot)

## Gold amount in this slot
var gold_amount: int = 0

## Visual elements
var icon_rect: TextureRect
var amount_label: Label
var border_rect: ColorRect


func _ready() -> void:
	_setup_visuals()
	pressed.connect(_on_pressed)


func _setup_visuals() -> void:
	custom_minimum_size = Vector2(56, 56)

	# Border (gold colored)
	border_rect = ColorRect.new()
	border_rect.name = "Border"
	border_rect.set_anchors_preset(PRESET_FULL_RECT)
	border_rect.color = UITheme.COLOR_GOLD
	border_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border_rect)

	# Background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.offset_left = 2
	bg.offset_top = 2
	bg.offset_right = -2
	bg.offset_bottom = -2
	bg.color = UITheme.COLOR_BUTTON_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Gold icon/text
	var gold_text := Label.new()
	gold_text.name = "GoldIcon"
	gold_text.text = "G"
	gold_text.set_anchors_preset(PRESET_CENTER)
	gold_text.grow_horizontal = GROW_DIRECTION_BOTH
	gold_text.grow_vertical = GROW_DIRECTION_BOTH
	gold_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_text.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	gold_text.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	gold_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gold_text)

	# Amount label (bottom right)
	amount_label = Label.new()
	amount_label.name = "AmountLabel"
	amount_label.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	amount_label.offset_left = -40
	amount_label.offset_top = -18
	amount_label.offset_right = -2
	amount_label.offset_bottom = -2
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	amount_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(amount_label)


func set_gold(amount: int) -> void:
	gold_amount = amount
	if amount > 0:
		amount_label.text = str(amount)
		amount_label.visible = true
		visible = true
	else:
		visible = false


func clear_gold() -> void:
	gold_amount = 0
	visible = false


func _on_pressed() -> void:
	slot_pressed.emit(self)


## DRAG & DROP SUPPORT

func _get_drag_data(_at_position: Vector2) -> Variant:
	if gold_amount <= 0:
		return null

	# Create drag preview
	var preview := Label.new()
	preview.text = "%d Gold" % gold_amount
	preview.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	preview.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	set_drag_preview(preview)

	# Dim while dragging
	modulate = UITheme.COLOR_LOCKED

	# Return special gold drag data
	return {"is_gold": true, "amount": gold_amount, "source_slot": self}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
