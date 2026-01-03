extends Button
## Drop zone for using consumable items - accepts drag & drop

var panel_ref: Control = null


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is InventorySlot:
		return false

	var slot: InventorySlot = data as InventorySlot
	if slot.current_item == null:
		return false

	# Only accept consumables
	if slot.current_item is ConsumableData:
		modulate = Color(0.5, 1.0, 0.5)  # Green tint
		return true

	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	modulate = Color.WHITE

	if not data is InventorySlot:
		return

	var slot: InventorySlot = data as InventorySlot
	if panel_ref and panel_ref.has_method("handle_use_drop"):
		panel_ref.handle_use_drop(slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
