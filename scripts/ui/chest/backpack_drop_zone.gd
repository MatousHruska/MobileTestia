extends PanelContainer
## Drop zone for backpack panel - accepts gold drops from chest

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Accept gold drops
	if data is Dictionary and data.get("is_gold", false):
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	# Handle gold drop
	if data is Dictionary and data.get("is_gold", false):
		var chest_menu: ChestMenu = get_meta("chest_menu")
		if chest_menu:
			chest_menu.collect_gold()
