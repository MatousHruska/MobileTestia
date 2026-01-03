extends Control
class_name InventoryPanel
## Mobile-optimized inventory panel with Equipment | Backpack layout + popup details
## Redesigned for small screens (424px+ height)

signal destroy_requested  # Emitted when destroy button pressed, parent shows confirmation

## Preload ItemDetailPopup to avoid class_name load order issues
const ItemDetailPopupScript = preload("res://scripts/ui/inventory/item_detail_popup.gd")

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

## Slot sizing (responsive)
const SLOT_SIZE_SMALL := 44.0   # For screens < 500px height
const SLOT_SIZE_NORMAL := 48.0  # For screens 500-900px
const SLOT_SIZE_LARGE := 56.0   # For screens > 900px

## UI References (set up in _ready)
var equipment_container: VBoxContainer
var backpack_container: GridContainer
var backpack_scroll: ScrollContainer
var gold_label: Label
var item_popup: Control  # ItemDetailPopup instance

## Slot tracking
var equipment_slots: Dictionary = {}  # EquipSlot -> InventorySlot
var backpack_slots: Array[InventorySlot] = []

## Current slot size (set based on screen)
var current_slot_size: float = SLOT_SIZE_NORMAL


func _ready() -> void:
	_calculate_slot_size()
	_build_ui()
	_connect_signals()
	_refresh_all()
	Debug.info("UI", "InventoryPanel initialized (2-column mobile layout)")


func _calculate_slot_size() -> void:
	if ResponsiveUI and ResponsiveUI.is_small_screen():
		current_slot_size = SLOT_SIZE_SMALL
	elif ResponsiveUI and ResponsiveUI.is_large_screen():
		current_slot_size = SLOT_SIZE_LARGE
	else:
		current_slot_size = SLOT_SIZE_NORMAL


func _build_ui() -> void:
	# Main horizontal container (2 columns: Equipment | Backpack)
	var main_hbox := HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 8)
	add_child(main_hbox)

	# Left column - Equipment
	_build_equipment_column(main_hbox)

	# Right column - Backpack (fills remaining space)
	_build_backpack_column(main_hbox)

	# Item detail popup (overlays everything)
	_build_item_popup()


func _build_equipment_column(parent: HBoxContainer) -> void:
	var equip_panel := PanelContainer.new()
	equip_panel.name = "EquipmentPanel"
	# Width based on 2 slots + spacing
	var panel_width := current_slot_size * 2 + 24  # 2 slots + padding
	equip_panel.custom_minimum_size.x = panel_width
	parent.add_child(equip_panel)

	var equip_vbox := VBoxContainer.new()
	equip_vbox.name = "EquipmentVBox"
	equip_vbox.add_theme_constant_override("separation", 4)
	equip_panel.add_child(equip_vbox)

	# Header
	var header := Label.new()
	header.text = "Equipment"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	equip_vbox.add_child(header)

	# Equipment slots container
	equipment_container = VBoxContainer.new()
	equipment_container.name = "EquipmentSlots"
	equipment_container.add_theme_constant_override("separation", 2)
	equip_vbox.add_child(equipment_container)

	# Create equipment slots using the 2-column layout (no labels - ghost icons are enough)
	for row_slots in EQUIPMENT_LAYOUT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		equipment_container.add_child(row)

		for slot in row_slots:
			var slot_btn := InventorySlot.new()
			slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
			slot_btn.equipment_slot = slot
			slot_btn.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
			slot_btn.slot_pressed.connect(_on_slot_pressed)
			row.add_child(slot_btn)
			equipment_slots[slot] = slot_btn


func _build_backpack_column(parent: HBoxContainer) -> void:
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(backpack_panel)

	var backpack_vbox := VBoxContainer.new()
	backpack_vbox.name = "BackpackVBox"
	backpack_vbox.add_theme_constant_override("separation", 4)
	backpack_panel.add_child(backpack_vbox)

	# Header with gold
	var header_row := HBoxContainer.new()
	header_row.name = "HeaderRow"
	backpack_vbox.add_child(header_row)

	var header := Label.new()
	header.text = "Backpack"
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 14)
	header_row.add_child(header)

	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.modulate = Color(1.0, 0.85, 0.0)
	header_row.add_child(gold_label)

	# Scrollable backpack grid
	backpack_scroll = ScrollContainer.new()
	backpack_scroll.name = "BackpackScroll"
	backpack_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	backpack_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
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
		slot.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
		slot.slot_pressed.connect(_on_slot_pressed)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)


func _build_item_popup() -> void:
	item_popup = ItemDetailPopupScript.new()
	item_popup.name = "ItemDetailPopup"
	item_popup.set_anchors_preset(PRESET_FULL_RECT)
	add_child(item_popup)

	# Connect popup signals
	item_popup.equip_pressed.connect(_on_equip_pressed)
	item_popup.use_pressed.connect(_on_use_pressed)
	item_popup.swap_pressed.connect(_on_swap_pressed)
	item_popup.destroy_pressed.connect(_on_destroy_pressed)
	item_popup.closed.connect(_on_popup_closed)


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
	_refresh_gold()


func _refresh_equipment() -> void:
	for slot in EQUIPMENT_SLOTS:
		var slot_ui: InventorySlot = equipment_slots[slot]
		var item_data: Dictionary = Inventory.get_equipped_item(slot)

		if item_data.is_empty():
			slot_ui.clear_item()
		else:
			var charges: int = item_data.get("charges", 0)
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
			var charges: int = item_data.get("charges", 0)
			slot_ui.set_item(item_data.item, item_data.quantity, charges)

		# Update selection state
		slot_ui.set_selected(
			Inventory.selected_source == "backpack" and
			Inventory.selected_index == i
		)


func _refresh_gold() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % Inventory.gold


## Public method to force refresh all UI (called when panel becomes visible)
func refresh() -> void:
	_refresh_all()


## Signal handlers

func _on_slot_pressed(slot: InventorySlot) -> void:
	var slot_idx = slot.backpack_index if slot.slot_type == InventorySlot.SlotType.BACKPACK else slot.equipment_slot
	Debug.info("UI", "Slot pressed", "type=%s index=%d swap_mode=%s" % [slot.slot_type, slot_idx, Inventory.swap_mode])

	# Handle swap mode
	if Inventory.swap_mode:
		if slot.slot_type == InventorySlot.SlotType.BACKPACK:
			Inventory.swap_with_backpack_slot(slot.backpack_index)
		else:
			# Can't swap with equipment slots, exit swap mode
			Inventory.exit_swap_mode()
		return

	# Normal selection
	if slot.slot_type == InventorySlot.SlotType.BACKPACK:
		Inventory.select_backpack_item(slot.backpack_index)
	else:
		Inventory.select_equipment_item(slot.equipment_slot)


func _on_inventory_changed() -> void:
	_refresh_backpack()
	# Update popup if visible
	if item_popup.visible and Inventory.has_selection():
		item_popup.show_item(Inventory.selected_item, Inventory.selected_source, Inventory.selected_index)


func _on_equipment_changed(_slot: ItemData.EquipSlot) -> void:
	_refresh_equipment()
	# Update popup if visible
	if item_popup.visible and Inventory.has_selection():
		item_popup.show_item(Inventory.selected_item, Inventory.selected_source, Inventory.selected_index)


func _on_item_selected(item: ItemData, source: String, index: int) -> void:
	_refresh_equipment()
	_refresh_backpack()
	# Show popup with item details
	item_popup.show_item(item, source, index)


func _on_item_deselected() -> void:
	_refresh_equipment()
	_refresh_backpack()
	# Hide popup
	item_popup.hide_popup()


func _on_gold_changed(_new_amount: int) -> void:
	_refresh_gold()


func _on_swap_mode_changed(active: bool) -> void:
	# Popup handles its own swap mode display
	if not active:
		# Swap completed or cancelled - refresh display
		_refresh_backpack()


## Action button handlers (from popup)

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
	# Emit signal for parent (character_menu) to show confirmation
	destroy_requested.emit()


func _on_popup_closed() -> void:
	# Popup was closed - deselection already handled by popup
	pass
