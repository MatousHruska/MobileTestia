extends Button
class_name InventorySlot
## A single inventory slot - used for both equipment and backpack slots

signal slot_pressed(slot: InventorySlot)

## Slot type
enum SlotType { BACKPACK, EQUIPMENT }

## Slot configuration
@export var slot_type: SlotType = SlotType.BACKPACK
@export var equipment_slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE
@export var backpack_index: int = -1

## Visual elements
var icon_rect: TextureRect
var quantity_label: Label
var rarity_border: ColorRect
var ghost_label: Label

## State
var current_item: ItemData = null
var current_quantity: int = 0
var is_selected: bool = false
var is_blocked: bool = false

## Ghost icon labels for empty equipment slots
const GHOST_ICONS: Dictionary = {
	ItemData.EquipSlot.HEAD: "H",
	ItemData.EquipSlot.BODY: "B",
	ItemData.EquipSlot.HANDS: "G",
	ItemData.EquipSlot.BOOTS: "F",
	ItemData.EquipSlot.MAIN_HAND: "W",
	ItemData.EquipSlot.ACCESSORY_1: "R",
	ItemData.EquipSlot.ACCESSORY_2: "A",
	ItemData.EquipSlot.QUICK_SLOT: "Q"
}


func _ready() -> void:
	_setup_visuals()
	pressed.connect(_on_pressed)
	toggle_mode = true


func _setup_visuals() -> void:
	# Main button styling
	custom_minimum_size = Vector2(60, 60)

	# Rarity border (behind everything)
	rarity_border = ColorRect.new()
	rarity_border.name = "RarityBorder"
	rarity_border.set_anchors_preset(PRESET_FULL_RECT)
	rarity_border.color = Color(0.3, 0.3, 0.3, 0.5)
	add_child(rarity_border)

	# Background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.offset_left = 2
	bg.offset_top = 2
	bg.offset_right = -2
	bg.offset_bottom = -2
	bg.color = Color(0.15, 0.15, 0.2, 1.0)
	add_child(bg)

	# Item icon
	icon_rect = TextureRect.new()
	icon_rect.name = "ItemIcon"
	icon_rect.set_anchors_preset(PRESET_FULL_RECT)
	icon_rect.offset_left = 4
	icon_rect.offset_top = 4
	icon_rect.offset_right = -4
	icon_rect.offset_bottom = -4
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(icon_rect)

	# Ghost label for empty equipment slots
	ghost_label = Label.new()
	ghost_label.name = "GhostLabel"
	ghost_label.set_anchors_preset(PRESET_CENTER)
	ghost_label.grow_horizontal = GROW_DIRECTION_BOTH
	ghost_label.grow_vertical = GROW_DIRECTION_BOTH
	ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ghost_label.add_theme_font_size_override("font_size", 16)
	ghost_label.modulate = Color(0.4, 0.4, 0.4, 0.6)
	add_child(ghost_label)

	# Quantity label (bottom right)
	quantity_label = Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	quantity_label.offset_left = -24
	quantity_label.offset_top = -18
	quantity_label.offset_right = -2
	quantity_label.offset_bottom = -2
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.add_theme_font_size_override("font_size", 12)
	quantity_label.visible = false
	add_child(quantity_label)

	# Initialize display
	_update_ghost_icon()
	refresh_display()


func _update_ghost_icon() -> void:
	if slot_type == SlotType.EQUIPMENT and GHOST_ICONS.has(equipment_slot):
		ghost_label.text = GHOST_ICONS[equipment_slot]
	else:
		ghost_label.text = ""


func set_item(item: ItemData, quantity: int = 1) -> void:
	current_item = item
	current_quantity = quantity
	refresh_display()


func clear_item() -> void:
	current_item = null
	current_quantity = 0
	refresh_display()


func refresh_display() -> void:
	if current_item:
		# Show item
		icon_rect.texture = current_item.icon
		icon_rect.visible = true
		ghost_label.visible = false

		# Show quantity if stackable
		if current_quantity > 1:
			quantity_label.text = str(current_quantity)
			quantity_label.visible = true
		else:
			quantity_label.visible = false

		# Rarity border color
		rarity_border.color = ItemData.get_rarity_color(current_item.rarity)

		# If no icon, show placeholder text
		if not current_item.icon:
			ghost_label.text = current_item.item_name.left(3).to_upper()
			ghost_label.modulate = ItemData.get_rarity_color(current_item.rarity)
			ghost_label.visible = true
	else:
		# Empty slot
		icon_rect.texture = null
		icon_rect.visible = false
		quantity_label.visible = false
		rarity_border.color = Color(0.3, 0.3, 0.3, 0.5)

		# Show ghost icon for equipment slots
		if slot_type == SlotType.EQUIPMENT:
			ghost_label.modulate = Color(0.4, 0.4, 0.4, 0.6)
			ghost_label.visible = true
			_update_ghost_icon()
		else:
			ghost_label.visible = false

	# Handle blocked state (e.g., off-hand with two-handed weapon)
	if is_blocked:
		modulate = Color(0.5, 0.5, 0.5, 0.5)
		disabled = true
	else:
		modulate = Color.WHITE
		disabled = false

	# Selection visual
	if is_selected:
		rarity_border.color = Color.WHITE
		modulate = Color(1.2, 1.2, 1.2, 1.0)


func set_selected(selected: bool) -> void:
	is_selected = selected
	button_pressed = selected
	refresh_display()


func set_blocked(blocked: bool) -> void:
	is_blocked = blocked
	refresh_display()


func _on_pressed() -> void:
	slot_pressed.emit(self)
