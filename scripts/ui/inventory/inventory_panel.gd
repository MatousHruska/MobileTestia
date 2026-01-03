extends Control
class_name InventoryPanel
## Mobile-optimized inventory panel with Equipment | Backpack layout + popup details
## Redesigned for small screens (424px+ height)

signal destroy_requested  # Emitted when destroy button pressed, parent shows confirmation

## Preload ItemDetailPopup to avoid class_name load order issues
const ItemDetailPopupScript = preload("res://scripts/ui/inventory/item_detail_popup.gd")

## Equipment slot layout - Two columns:
## Column 1 (Armor): HEAD+AMULET, HAND+BODY+RING, LEGS
## Column 2 (Combat): WEAPON, QUICK_SLOT
const ARMOR_LAYOUT: Array = [
	[ItemData.EquipSlot.HEAD, ItemData.EquipSlot.ACCESSORY_2],           # Head, Amulet
	[ItemData.EquipSlot.HANDS, ItemData.EquipSlot.BODY, ItemData.EquipSlot.ACCESSORY_1],  # Hand, Body, Ring
	[ItemData.EquipSlot.BOOTS]                                           # Legs/Feet
]

const COMBAT_LAYOUT: Array = [
	ItemData.EquipSlot.MAIN_HAND,   # Weapon
	ItemData.EquipSlot.QUICK_SLOT   # Quick Slot
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

## Backpack settings (columns calculated dynamically based on width)
const BACKPACK_MIN_COLUMNS: int = 5
const BACKPACK_H_SEPARATION: int = 4

## Margin percentages (relative to panel width/height)
const MARGIN_SIDE_PCT := 0.02      # 2% side margins
const MARGIN_RIGHT_PCT := 0.03    # 3% right margin for backpack
const MARGIN_TOP_PCT := 0.02      # 2% top margin
const MARGIN_BOTTOM_PCT := 0.03   # 3% bottom margin
const HEADER_GAP_PCT := 0.04      # 4% gap after header

## Slot sizing (responsive)
const SLOT_SIZE_SMALL := 44.0   # For screens < 500px height
const SLOT_SIZE_NORMAL := 48.0  # For screens 500-900px
const SLOT_SIZE_LARGE := 56.0   # For screens > 900px

## UI References (set up in _ready)
var equipment_container: VBoxContainer
var backpack_container: GridContainer
var gold_label: Label
var item_popup: Control  # ItemDetailPopup instance
var equip_margin: MarginContainer
var equip_vbox: VBoxContainer
var backpack_margin: MarginContainer
var backpack_vbox: VBoxContainer

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
	# Outer container with outline (PanelContainer provides the outline)
	var equip_panel := PanelContainer.new()
	equip_panel.name = "EquipmentPanel"
	parent.add_child(equip_panel)

	# Inner margin for padding (will be updated dynamically)
	equip_margin = MarginContainer.new()
	equip_margin.name = "EquipmentMargin"
	equip_panel.add_child(equip_margin)

	equip_vbox = VBoxContainer.new()
	equip_vbox.name = "EquipmentVBox"
	equip_margin.add_child(equip_vbox)

	# Update margins when panel resizes
	equip_panel.resized.connect(_on_panel_resized.bind(equip_panel, equip_margin, equip_vbox, false))

	# Header
	var header := Label.new()
	header.text = "Equipment"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	equip_vbox.add_child(header)

	# Two-column layout: Armor | Combat
	var columns_hbox := HBoxContainer.new()
	columns_hbox.name = "EquipmentColumns"
	columns_hbox.add_theme_constant_override("separation", 12)
	equip_vbox.add_child(columns_hbox)

	# Column 1: Armor slots
	var armor_column := VBoxContainer.new()
	armor_column.name = "ArmorColumn"
	armor_column.add_theme_constant_override("separation", 4)
	columns_hbox.add_child(armor_column)

	for row_slots in ARMOR_LAYOUT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		armor_column.add_child(row)

		for slot in row_slots:
			var slot_btn := InventorySlot.new()
			slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
			slot_btn.equipment_slot = slot
			slot_btn.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
			slot_btn.slot_pressed.connect(_on_slot_pressed)
			row.add_child(slot_btn)
			equipment_slots[slot] = slot_btn

	# Column 2: Combat slots (Weapon + Quick Slot)
	var combat_column := VBoxContainer.new()
	combat_column.name = "CombatColumn"
	combat_column.add_theme_constant_override("separation", 4)
	combat_column.alignment = BoxContainer.ALIGNMENT_CENTER
	columns_hbox.add_child(combat_column)

	for slot in COMBAT_LAYOUT:
		var slot_btn := InventorySlot.new()
		slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
		slot_btn.equipment_slot = slot
		slot_btn.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
		slot_btn.slot_pressed.connect(_on_slot_pressed)
		combat_column.add_child(slot_btn)
		equipment_slots[slot] = slot_btn


func _build_backpack_column(parent: HBoxContainer) -> void:
	# Outer container with outline (PanelContainer provides the outline)
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	backpack_panel.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(backpack_panel)

	# Inner margin for padding (will be updated dynamically)
	backpack_margin = MarginContainer.new()
	backpack_margin.name = "BackpackMargin"
	backpack_panel.add_child(backpack_margin)

	backpack_vbox = VBoxContainer.new()
	backpack_vbox.name = "BackpackVBox"
	backpack_margin.add_child(backpack_vbox)

	# Update margins when panel resizes
	backpack_panel.resized.connect(_on_panel_resized.bind(backpack_panel, backpack_margin, backpack_vbox, true))

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

	# Grid container - right-aligned using HBoxContainer with spacer
	var grid_row := HBoxContainer.new()
	grid_row.name = "GridRow"
	grid_row.size_flags_vertical = SIZE_EXPAND_FILL
	backpack_vbox.add_child(grid_row)

	# Spacer to push grid to right
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	grid_row.add_child(spacer)

	backpack_container = GridContainer.new()
	backpack_container.name = "BackpackGrid"
	backpack_container.columns = BACKPACK_MIN_COLUMNS  # Will be recalculated
	backpack_container.add_theme_constant_override("h_separation", BACKPACK_H_SEPARATION)
	backpack_container.add_theme_constant_override("v_separation", 4)
	grid_row.add_child(backpack_container)

	# Create backpack slots
	for i in Inventory.BACKPACK_SIZE:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
		slot.slot_pressed.connect(_on_slot_pressed)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)

	# Adjust columns to fill width after layout
	backpack_vbox.resized.connect(_on_backpack_resized.bind(backpack_vbox))


func _on_backpack_resized(container: VBoxContainer) -> void:
	if backpack_slots.is_empty():
		return

	# Get actual available width (container width minus margins already applied)
	var available_width := container.size.x

	# Calculate how many columns fit
	var slot_with_sep := current_slot_size + BACKPACK_H_SEPARATION
	var max_columns := floori((available_width + BACKPACK_H_SEPARATION) / slot_with_sep)

	# Clamp to reasonable bounds (min 5, max based on backpack size)
	var columns := clampi(max_columns, BACKPACK_MIN_COLUMNS, Inventory.BACKPACK_SIZE)

	if backpack_container.columns != columns:
		backpack_container.columns = columns


func _on_panel_resized(panel: PanelContainer, margin_container: MarginContainer, vbox: VBoxContainer, is_backpack: bool) -> void:
	var panel_width := panel.size.x
	var panel_height := panel.size.y

	# Calculate proportional margins (minimum 8px for readability)
	var side_margin := maxi(8, int(panel_width * MARGIN_SIDE_PCT))
	var right_margin := maxi(12, int(panel_width * (MARGIN_RIGHT_PCT if is_backpack else MARGIN_SIDE_PCT)))
	var top_margin := maxi(6, int(panel_height * MARGIN_TOP_PCT))
	var bottom_margin := maxi(8, int(panel_height * MARGIN_BOTTOM_PCT))
	var header_gap := maxi(12, int(panel_height * HEADER_GAP_PCT))

	# Apply margins
	margin_container.add_theme_constant_override("margin_left", side_margin)
	margin_container.add_theme_constant_override("margin_right", right_margin)
	margin_container.add_theme_constant_override("margin_top", top_margin)
	margin_container.add_theme_constant_override("margin_bottom", bottom_margin)

	# Apply header gap
	vbox.add_theme_constant_override("separation", header_gap)


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
