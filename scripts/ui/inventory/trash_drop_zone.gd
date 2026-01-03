extends Panel
## Drop zone for destroying inventory items via drag & drop

var highlight_color := Color(0.8, 0.2, 0.2, 0.3)  # Red tint when hovering
var normal_color := Color(1, 1, 1, 1)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	## Accept any InventorySlot with an item
	if not data is InventorySlot:
		return false

	var slot: InventorySlot = data as InventorySlot
	if slot.current_item == null:
		return false

	# Show highlight
	modulate = highlight_color
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	## Handle item drop - destroy the item
	modulate = normal_color

	if not data is InventorySlot:
		return

	var slot: InventorySlot = data as InventorySlot

	# Get reference to the inventory panel and call its handler
	var panel_ref = get_meta("panel_ref")
	if panel_ref and panel_ref.has_method("handle_trash_drop"):
		panel_ref.handle_trash_drop(slot)


func _notification(what: int) -> void:
	## Reset highlight when drag ends
	if what == NOTIFICATION_DRAG_END:
		modulate = normal_color
