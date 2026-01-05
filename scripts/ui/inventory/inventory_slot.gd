extends Button
class_name InventorySlot
## A single inventory slot - used for both equipment and backpack slots
## Supports drag & drop for moving/swapping items

signal slot_pressed(slot: InventorySlot)
signal item_dropped(from_slot: InventorySlot, to_slot: InventorySlot)
signal drag_started(slot: InventorySlot)
signal drag_ended(slot: InventorySlot)

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
var highlight_rect: ColorRect  # For drag & drop highlighting

## State
var current_item: ItemData = null
var current_quantity: int = 0
var current_charges: int = 0
var is_selected: bool = false
var is_blocked: bool = false
var is_drag_target: bool = false  # Currently hovered during drag

## Gold display mode (for chest gold)
var is_gold_display: bool = false
var gold_amount: int = 0

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
	rarity_border.color = UITheme.COLOR_EMPTY_SLOT_BORDER
	rarity_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rarity_border)

	# Background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.offset_left = 2
	bg.offset_top = 2
	bg.offset_right = -2
	bg.offset_bottom = -2
	bg.color = UITheme.COLOR_EMPTY_SLOT_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_rect)

	# Ghost label for empty equipment slots
	ghost_label = Label.new()
	ghost_label.name = "GhostLabel"
	ghost_label.set_anchors_preset(PRESET_CENTER)
	ghost_label.grow_horizontal = GROW_DIRECTION_BOTH
	ghost_label.grow_vertical = GROW_DIRECTION_BOTH
	ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ghost_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LARGE)
	ghost_label.modulate = UITheme.COLOR_LOCKED
	ghost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	quantity_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	quantity_label.visible = false
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quantity_label)

	# Highlight overlay for drag & drop (on top of everything)
	highlight_rect = ColorRect.new()
	highlight_rect.name = "HighlightRect"
	highlight_rect.set_anchors_preset(PRESET_FULL_RECT)
	highlight_rect.color = UITheme.COLOR_DRAG_HIGHLIGHT
	highlight_rect.visible = false
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(highlight_rect)

	# Initialize display
	_update_ghost_icon()
	refresh_display()


func _update_ghost_icon() -> void:
	if slot_type == SlotType.EQUIPMENT and GHOST_ICONS.has(equipment_slot):
		ghost_label.text = GHOST_ICONS[equipment_slot]
	else:
		ghost_label.text = ""


func set_item(item: ItemData, quantity: int = 1, charges: int = 0) -> void:
	current_item = item
	current_quantity = quantity
	current_charges = charges
	refresh_display()


func clear_item() -> void:
	current_item = null
	current_quantity = 0
	current_charges = 0
	is_gold_display = false
	gold_amount = 0
	refresh_display()


func set_gold(amount: int) -> void:
	## Display gold instead of an item (for chest gold slots)
	current_item = null
	current_quantity = 0
	current_charges = 0
	is_gold_display = true
	gold_amount = amount
	refresh_display()


func refresh_display() -> void:
	if is_gold_display and gold_amount > 0:
		# Show gold display
		icon_rect.texture = null
		icon_rect.visible = false
		ghost_label.text = "G"
		ghost_label.modulate = UITheme.COLOR_GOLD
		ghost_label.visible = true
		quantity_label.text = str(gold_amount)
		quantity_label.modulate = UITheme.COLOR_GOLD
		quantity_label.visible = true
		rarity_border.color = UITheme.COLOR_GOLD
	elif current_item:
		# Show item
		icon_rect.texture = current_item.icon
		icon_rect.visible = true
		ghost_label.visible = false

		# Show charges for consumables, quantity for stackables
		if current_item is ConsumableData:
			var consumable: ConsumableData = current_item as ConsumableData
			quantity_label.text = "%d/%d" % [current_charges, consumable.max_charges]
			quantity_label.visible = true
			# Dim if no charges
			if current_charges <= 0:
				quantity_label.modulate = UITheme.COLOR_DEBUFF
			else:
				quantity_label.modulate = UITheme.COLOR_SELECTED
		elif current_quantity > 1:
			quantity_label.text = str(current_quantity)
			quantity_label.modulate = UITheme.COLOR_SELECTED
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
		rarity_border.color = UITheme.COLOR_EMPTY_SLOT_BORDER

		# Show ghost icon for equipment slots
		if slot_type == SlotType.EQUIPMENT:
			ghost_label.modulate = UITheme.COLOR_LOCKED
			ghost_label.visible = true
			_update_ghost_icon()
		else:
			ghost_label.visible = false

	# Handle blocked state
	if is_blocked:
		modulate = UITheme.COLOR_LOCKED
		disabled = true
	else:
		modulate = UITheme.COLOR_SELECTED
		disabled = false

	# Selection visual
	if is_selected:
		rarity_border.color = UITheme.COLOR_SELECTED
		modulate = UITheme.COLOR_HIGHLIGHT


func set_selected(selected: bool) -> void:
	is_selected = selected
	button_pressed = selected
	refresh_display()


func set_blocked(blocked: bool) -> void:
	is_blocked = blocked
	refresh_display()


func _on_pressed() -> void:
	slot_pressed.emit(self)


## DRAG & DROP SUPPORT

func _get_drag_data(_at_position: Vector2) -> Variant:
	## Called when drag starts - return data if this slot has an item or gold

	# Handle gold display mode
	if is_gold_display and gold_amount > 0:
		var label := Label.new()
		label.text = "%d Gold" % gold_amount
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
		label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		set_drag_preview(label)
		modulate = UITheme.COLOR_LOCKED
		drag_started.emit(self)
		return self

	if current_item == null:
		return null

	# Create drag preview (a copy of the item icon)
	var preview := TextureRect.new()
	preview.texture = current_item.icon
	preview.custom_minimum_size = Vector2(48, 48)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.8)

	# If no icon, show text preview
	if not current_item.icon:
		var label := Label.new()
		label.text = current_item.item_name.left(6)
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
		set_drag_preview(label)
	else:
		set_drag_preview(preview)

	# Dim this slot while dragging
	modulate = UITheme.COLOR_LOCKED

	# Notify panel that drag started (for highlighting target slots)
	drag_started.emit(self)

	# Return drag data - the slot itself
	return self


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	## Called to check if we can accept a drop
	if not data is InventorySlot:
		return false

	var source_slot: InventorySlot = data as InventorySlot

	# Can't drop on self
	if source_slot == self:
		return false

	# Equipment slots have restrictions
	if slot_type == SlotType.EQUIPMENT:
		# Check if the dragged item can go in this equipment slot
		if source_slot.current_item == null:
			return false
		return _can_equip_item(source_slot.current_item)

	# Backpack slots accept any item
	return true


func _can_equip_item(item: ItemData) -> bool:
	## Check if an item can be equipped in this slot
	if item == null:
		return false

	# Consumables can only go to quick slot
	if item.item_type == ItemData.ItemType.CONSUMABLE:
		return equipment_slot == ItemData.EquipSlot.QUICK_SLOT

	# Equipment items
	if item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData

		# Check stat requirements
		if not equip.can_equip():
			return false

		var target := equip.get_target_slot()

		# Rings can go to either accessory slot
		if equip.equipment_type == ItemData.EquipmentType.RING:
			return equipment_slot == ItemData.EquipSlot.ACCESSORY_1 or equipment_slot == ItemData.EquipSlot.ACCESSORY_2

		return target == equipment_slot

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	## Called when item is dropped on this slot
	if not data is InventorySlot:
		return

	var source_slot: InventorySlot = data as InventorySlot

	# Emit signal for the inventory panel to handle the actual swap
	item_dropped.emit(source_slot, self)


func _notification(what: int) -> void:
	## Handle drag end to restore visuals
	if what == NOTIFICATION_DRAG_END:
		modulate = UITheme.COLOR_SELECTED if not is_blocked else UITheme.COLOR_LOCKED
		set_drag_highlight(false)
		drag_ended.emit(self)


func set_drag_highlight(enabled: bool) -> void:
	## Show/hide the drag target highlight
	is_drag_target = enabled
	highlight_rect.visible = enabled
