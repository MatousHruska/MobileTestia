extends Control
class_name InventoryPanel
## Unified inventory panel with Equipment | Details | Backpack layout

signal destroy_requested  # Emitted when destroy button pressed, parent shows confirmation

## Equipment slot layout (2-column grid)
## Format: Array of rows, each row is an array of slots
const EQUIPMENT_LAYOUT: Array = [
	[ItemData.EquipSlot.HEAD, ItemData.EquipSlot.ACCESSORY_2],      # H  A (Amulet)
	[ItemData.EquipSlot.BODY],                                       # B
	[ItemData.EquipSlot.HANDS, ItemData.EquipSlot.ACCESSORY_1],     # G  R (Ring)
	[ItemData.EquipSlot.BOOTS],                                      # F
	[ItemData.EquipSlot.MAIN_HAND, ItemData.EquipSlot.QUICK_SLOT]   # W  Q
]

## All equipment slots for iteration
const EQUIPMENT_SLOTS: Array[ItemData.EquipSlot] = [
	ItemData.EquipSlot.HEAD,
	ItemData.EquipSlot.BODY,
	ItemData.EquipSlot.HANDS,
	ItemData.EquipSlot.BOOTS,
	ItemData.EquipSlot.MAIN_HAND,
	ItemData.EquipSlot.ACCESSORY_1,
	ItemData.EquipSlot.ACCESSORY_2,
	ItemData.EquipSlot.QUICK_SLOT
]

## Backpack settings
const BACKPACK_COLUMNS: int = 5

## UI References (set up in _ready)
var equipment_container: VBoxContainer
var details_container: VBoxContainer
var backpack_container: GridContainer
var backpack_scroll: ScrollContainer

## Details panel elements
var details_icon: TextureRect
var details_name: Label
var details_type: Label
var details_rarity: Label
var details_description: Label
var details_stats: Label
var action_equip_button: Button
var action_use_button: Button
var action_swap_button: Button
var action_destroy_button: Button
var details_placeholder: Label
var swap_mode_label: Label

## Slot tracking
var equipment_slots: Dictionary = {}  # EquipSlot -> InventorySlot
var backpack_slots: Array[InventorySlot] = []


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_refresh_all()
	Debug.info("UI", "InventoryPanel initialized")


func _build_ui() -> void:
	# Main horizontal container
	var main_hbox := HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 8)
	add_child(main_hbox)

	# Left column - Equipment
	_build_equipment_column(main_hbox)

	# Center column - Details
	_build_details_column(main_hbox)

	# Right column - Backpack
	_build_backpack_column(main_hbox)


func _build_equipment_column(parent: HBoxContainer) -> void:
	var equip_panel := PanelContainer.new()
	equip_panel.name = "EquipmentPanel"
	equip_panel.custom_minimum_size.x = 160
	parent.add_child(equip_panel)

	var equip_vbox := VBoxContainer.new()
	equip_vbox.name = "EquipmentVBox"
	equip_vbox.add_theme_constant_override("separation", 4)
	equip_panel.add_child(equip_vbox)

	# Header
	var header := Label.new()
	header.text = "Equipment"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	equip_vbox.add_child(header)

	# Equipment slots container
	equipment_container = VBoxContainer.new()
	equipment_container.name = "EquipmentSlots"
	equipment_container.add_theme_constant_override("separation", 4)
	equip_vbox.add_child(equipment_container)

	# Create equipment slots using the 2-column layout
	for row_slots in EQUIPMENT_LAYOUT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		equipment_container.add_child(row)

		for slot in row_slots:
			var slot_container := VBoxContainer.new()
			slot_container.add_theme_constant_override("separation", 2)
			row.add_child(slot_container)

			# Slot button
			var slot_btn := InventorySlot.new()
			slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
			slot_btn.equipment_slot = slot
			slot_btn.custom_minimum_size = Vector2(56, 56)
			slot_btn.slot_pressed.connect(_on_slot_pressed)
			slot_container.add_child(slot_btn)

			# Slot label below
			var label := Label.new()
			label.text = ItemData.get_slot_name(slot)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 10)
			label.modulate = Color(0.7, 0.7, 0.7)
			slot_container.add_child(label)

			equipment_slots[slot] = slot_btn


func _build_details_column(parent: HBoxContainer) -> void:
	var details_panel := PanelContainer.new()
	details_panel.name = "DetailsPanel"
	details_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(details_panel)

	details_container = VBoxContainer.new()
	details_container.name = "DetailsVBox"
	details_container.add_theme_constant_override("separation", 8)
	details_panel.add_child(details_container)

	# Header
	var header := Label.new()
	header.text = "Item Details"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	details_container.add_child(header)

	# Placeholder text (shown when nothing selected)
	details_placeholder = Label.new()
	details_placeholder.name = "Placeholder"
	details_placeholder.text = "Select an item to view details"
	details_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_placeholder.size_flags_vertical = SIZE_EXPAND_FILL
	details_placeholder.modulate = Color(0.6, 0.6, 0.6)
	details_container.add_child(details_placeholder)

	# Item info container (hidden until item selected)
	var info_container := VBoxContainer.new()
	info_container.name = "InfoContainer"
	info_container.size_flags_vertical = SIZE_EXPAND_FILL
	info_container.add_theme_constant_override("separation", 4)
	info_container.visible = false
	details_container.add_child(info_container)

	# Icon and name row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	info_container.add_child(top_row)

	# Large icon
	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(80, 80)
	icon_bg.color = Color(0.2, 0.2, 0.25, 1)
	top_row.add_child(icon_bg)

	details_icon = TextureRect.new()
	details_icon.set_anchors_preset(PRESET_FULL_RECT)
	details_icon.offset_left = 4
	details_icon.offset_top = 4
	details_icon.offset_right = -4
	details_icon.offset_bottom = -4
	details_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	details_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_bg.add_child(details_icon)

	# Name and type
	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	top_row.add_child(name_vbox)

	details_name = Label.new()
	details_name.add_theme_font_size_override("font_size", 18)
	name_vbox.add_child(details_name)

	details_type = Label.new()
	details_type.add_theme_font_size_override("font_size", 12)
	details_type.modulate = Color(0.7, 0.7, 0.7)
	name_vbox.add_child(details_type)

	details_rarity = Label.new()
	details_rarity.add_theme_font_size_override("font_size", 12)
	name_vbox.add_child(details_rarity)

	# Description
	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	info_container.add_child(desc_label)

	details_description = Label.new()
	details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_container.add_child(details_description)

	# Stats
	var stats_label := Label.new()
	stats_label.text = "Stats:"
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.modulate = Color(0.7, 0.7, 0.7)
	info_container.add_child(stats_label)

	details_stats = Label.new()
	details_stats.size_flags_vertical = SIZE_EXPAND_FILL
	info_container.add_child(details_stats)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	info_container.add_child(spacer)

	# Action buttons
	var button_row := HBoxContainer.new()
	button_row.name = "ActionButtons"
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_container.add_child(button_row)

	action_equip_button = Button.new()
	action_equip_button.name = "EquipButton"
	action_equip_button.text = "Equip"
	action_equip_button.custom_minimum_size = Vector2(80, 40)
	action_equip_button.pressed.connect(_on_equip_pressed)
	button_row.add_child(action_equip_button)

	action_use_button = Button.new()
	action_use_button.name = "UseButton"
	action_use_button.text = "Use"
	action_use_button.custom_minimum_size = Vector2(70, 40)
	action_use_button.pressed.connect(_on_use_pressed)
	action_use_button.visible = false
	button_row.add_child(action_use_button)

	action_swap_button = Button.new()
	action_swap_button.name = "SwapButton"
	action_swap_button.text = "Swap"
	action_swap_button.custom_minimum_size = Vector2(70, 40)
	action_swap_button.pressed.connect(_on_swap_pressed)
	button_row.add_child(action_swap_button)

	action_destroy_button = Button.new()
	action_destroy_button.name = "DestroyButton"
	action_destroy_button.text = "Destroy"
	action_destroy_button.custom_minimum_size = Vector2(70, 40)
	action_destroy_button.pressed.connect(_on_destroy_pressed)
	button_row.add_child(action_destroy_button)

	# Swap mode indicator label
	swap_mode_label = Label.new()
	swap_mode_label.name = "SwapModeLabel"
	swap_mode_label.text = "Select target slot to swap..."
	swap_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	swap_mode_label.modulate = Color(1.0, 0.8, 0.2)
	swap_mode_label.visible = false
	info_container.add_child(swap_mode_label)


func _build_backpack_column(parent: HBoxContainer) -> void:
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.custom_minimum_size.x = 340
	parent.add_child(backpack_panel)

	var backpack_vbox := VBoxContainer.new()
	backpack_vbox.name = "BackpackVBox"
	backpack_vbox.add_theme_constant_override("separation", 4)
	backpack_panel.add_child(backpack_vbox)

	# Header with gold
	var header_row := HBoxContainer.new()
	backpack_vbox.add_child(header_row)

	var header := Label.new()
	header.text = "Backpack"
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 16)
	header_row.add_child(header)

	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.modulate = Color(1.0, 0.85, 0.0)
	header_row.add_child(gold_label)

	# Scrollable backpack grid
	backpack_scroll = ScrollContainer.new()
	backpack_scroll.name = "BackpackScroll"
	backpack_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	backpack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backpack_vbox.add_child(backpack_scroll)

	backpack_container = GridContainer.new()
	backpack_container.name = "BackpackGrid"
	backpack_container.columns = BACKPACK_COLUMNS
	backpack_container.add_theme_constant_override("h_separation", 4)
	backpack_container.add_theme_constant_override("v_separation", 4)
	backpack_scroll.add_child(backpack_container)

	# Create backpack slots
	for i in Inventory.BACKPACK_SIZE:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(56, 56)
		slot.slot_pressed.connect(_on_slot_pressed)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)


func _connect_signals() -> void:
	Inventory.inventory_changed.connect(_on_inventory_changed)
	Inventory.equipment_changed.connect(_on_equipment_changed)
	Inventory.item_selected.connect(_on_item_selected)
	Inventory.item_deselected.connect(_on_item_deselected)
	Inventory.gold_changed.connect(_on_gold_changed)
	Inventory.swap_mode_changed.connect(_on_swap_mode_changed)


func _refresh_all() -> void:
	_refresh_equipment()
	_refresh_backpack()
	_refresh_details()
	_refresh_gold()


func _refresh_equipment() -> void:
	for slot in EQUIPMENT_SLOTS:
		var slot_ui: InventorySlot = equipment_slots[slot]
		var item_data: Dictionary = Inventory.get_equipped_item(slot)

		if item_data.is_empty():
			slot_ui.clear_item()
		else:
			var charges := item_data.get("charges", 0)
			slot_ui.set_item(item_data.item, item_data.quantity, charges)

		# Check if slot is blocked
		slot_ui.set_blocked(Inventory.is_slot_blocked(slot))

		# Update selection state
		slot_ui.set_selected(
			Inventory.selected_source == "equipment" and
			Inventory.selected_index == slot
		)


func _refresh_backpack() -> void:
	for i in backpack_slots.size():
		var slot_ui: InventorySlot = backpack_slots[i]
		var item_data: Dictionary = Inventory.get_backpack_item(i)

		if item_data.is_empty():
			slot_ui.clear_item()
		else:
			var charges := item_data.get("charges", 0)
			slot_ui.set_item(item_data.item, item_data.quantity, charges)

		# Update selection state
		slot_ui.set_selected(
			Inventory.selected_source == "backpack" and
			Inventory.selected_index == i
		)


func _refresh_details() -> void:
	var info_container := details_container.get_node_or_null("InfoContainer")
	if not info_container:
		return

	if not Inventory.has_selection():
		details_placeholder.visible = true
		info_container.visible = false
		return

	details_placeholder.visible = false
	info_container.visible = true

	var item: ItemData = Inventory.selected_item

	# Update details
	details_name.text = item.item_name
	details_name.modulate = ItemData.get_rarity_color(item.rarity)

	details_rarity.text = ItemData.get_rarity_name(item.rarity)
	details_rarity.modulate = ItemData.get_rarity_color(item.rarity)

	details_description.text = item.description if item.description else "No description"

	# Icon (or placeholder)
	details_icon.texture = item.icon

	# Type and stats based on item type
	if item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData
		details_type.text = equip.get_type_name()
		details_stats.text = equip.get_stat_text()
	elif item is ConsumableData:
		var consumable: ConsumableData = item as ConsumableData
		details_type.text = "Consumable"
		details_stats.text = consumable.get_effect_text()
	else:
		details_type.text = "Item"
		details_stats.text = "No stats"

	# Update action buttons
	_update_action_buttons()


func _update_action_buttons() -> void:
	if not Inventory.has_selection():
		action_equip_button.visible = false
		action_use_button.visible = false
		action_destroy_button.visible = false
		return

	var item: ItemData = Inventory.selected_item
	var is_in_backpack := Inventory.selected_source == "backpack"
	var is_equipped := Inventory.selected_source == "equipment"

	# Equip/Unequip button
	if item.item_type == ItemData.ItemType.EQUIPMENT:
		action_equip_button.visible = true
		action_use_button.visible = false
		if is_in_backpack:
			action_equip_button.text = "Equip"
		else:
			action_equip_button.text = "Unequip"
	else:
		# Consumable
		action_equip_button.visible = is_in_backpack
		action_use_button.visible = true
		if is_in_backpack:
			action_equip_button.text = "Quick Slot"

	# Swap is only available for backpack items
	action_swap_button.visible = is_in_backpack

	# Destroy is always available
	action_destroy_button.visible = true


func _refresh_gold() -> void:
	var gold_label := get_node_or_null("MainHBox/BackpackPanel/BackpackVBox/HBoxContainer/GoldLabel")
	if gold_label:
		gold_label.text = "Gold: %d" % Inventory.gold


## Signal handlers

func _on_slot_pressed(slot: InventorySlot) -> void:
	Debug.log("UI", "Slot pressed", "%s index %d" % [slot.slot_type, slot.backpack_index if slot.slot_type == InventorySlot.SlotType.BACKPACK else slot.equipment_slot])

	# Handle swap mode
	if Inventory.swap_mode:
		if slot.slot_type == InventorySlot.SlotType.BACKPACK:
			Inventory.swap_with_backpack_slot(slot.backpack_index)
		else:
			# Can't swap with equipment slots, exit swap mode
			Inventory.exit_swap_mode()
		return

	if slot.slot_type == InventorySlot.SlotType.BACKPACK:
		Inventory.select_backpack_item(slot.backpack_index)
	else:
		Inventory.select_equipment_item(slot.equipment_slot)


func _on_inventory_changed() -> void:
	_refresh_backpack()
	_refresh_details()


func _on_equipment_changed(_slot: ItemData.EquipSlot) -> void:
	_refresh_equipment()
	_refresh_details()


func _on_item_selected(_item: ItemData, _source: String, _index: int) -> void:
	_refresh_equipment()
	_refresh_backpack()
	_refresh_details()


func _on_item_deselected() -> void:
	_refresh_equipment()
	_refresh_backpack()
	_refresh_details()


func _on_gold_changed(new_amount: int) -> void:
	_refresh_gold()


## Action button handlers

func _on_equip_pressed() -> void:
	if Inventory.selected_source == "backpack":
		Inventory.equip_selected()
	else:
		Inventory.unequip_selected()


func _on_use_pressed() -> void:
	Inventory.use_selected()


func _on_swap_pressed() -> void:
	Inventory.enter_swap_mode()


func _on_destroy_pressed() -> void:
	# Emit signal for parent to show confirmation
	destroy_requested.emit()


func _on_swap_mode_changed(active: bool) -> void:
	swap_mode_label.visible = active
	# Hide action buttons when in swap mode
	if active:
		action_equip_button.visible = false
		action_use_button.visible = false
		action_swap_button.visible = false
		action_destroy_button.visible = false
	else:
		_update_action_buttons()
