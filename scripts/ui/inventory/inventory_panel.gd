extends Control
class_name InventoryPanel
## Mobile-optimized inventory panel with Equipment | Backpack layout + popup details
## Redesigned for small screens (424px+ height)
## Item management via drag & drop: move/swap items, equip, destroy via trash zone


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
const BACKPACK_MAX_COLUMNS: int = 7
const BACKPACK_H_SEPARATION: int = 4

## Margin percentages for equipment (relative to panel width/height)
const MARGIN_SIDE_PCT := 0.02      # 2% side margins
const MARGIN_TOP_PCT := 0.02      # 2% top margin
const MARGIN_BOTTOM_PCT := 0.03   # 3% bottom margin
const COLUMN_GAP_PCT := 0.04      # 4% gap between main columns (~32px)

## Slot sizing (responsive)
const SLOT_SIZE_SMALL := 44.0   # For screens < 500px height
const SLOT_SIZE_NORMAL := 48.0  # For screens 500-900px
const SLOT_SIZE_LARGE := 56.0   # For screens > 900px

## UI References (set up in _ready)
var equipment_container: VBoxContainer
var backpack_container: GridContainer
var item_popup: ItemPopup = null
var _popup_layer: CanvasLayer = null
var equip_margin: MarginContainer
var backpack_margin: MarginContainer
var gold_label: Label
var main_hbox: HBoxContainer
var trash_button: Button
var split_button: Button
var use_button: Button

## Drag & drop state
var pending_destroy_source: String = ""
var pending_destroy_index: int = -1

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
	main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	add_child(main_hbox)

	# Update column gap when panel resizes
	main_hbox.resized.connect(_on_main_hbox_resized)

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

	# VBox for header + equipment slots
	var equip_vbox := VBoxContainer.new()
	equip_vbox.name = "EquipmentVBox"
	equip_vbox.add_theme_constant_override("separation", 8)
	equip_margin.add_child(equip_vbox)

	# Header row: "Equipped Items:"
	var header_label := Label.new()
	header_label.text = "Equipped Items:"
	header_label.add_theme_font_size_override("font_size", 14)
	equip_vbox.add_child(header_label)

	# Center container for both horizontal and vertical centering
	var equip_center := CenterContainer.new()
	equip_center.name = "EquipmentCenter"
	equip_center.size_flags_horizontal = SIZE_EXPAND_FILL
	equip_center.size_flags_vertical = SIZE_EXPAND_FILL
	equip_vbox.add_child(equip_center)

	# Update margins when panel resizes
	equip_panel.resized.connect(_on_panel_resized.bind(equip_panel, equip_margin, equip_vbox, false))

	# Two-column layout: Armor | Combat
	var columns_hbox := HBoxContainer.new()
	columns_hbox.name = "EquipmentColumns"
	columns_hbox.add_theme_constant_override("separation", 20)
	equip_center.add_child(columns_hbox)

	# Column 1: Armor slots
	var armor_column := VBoxContainer.new()
	armor_column.name = "ArmorColumn"
	armor_column.add_theme_constant_override("separation", 8)
	columns_hbox.add_child(armor_column)

	for row_slots in ARMOR_LAYOUT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		armor_column.add_child(row)

		for slot in row_slots:
			var slot_btn := InventorySlot.new()
			slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
			slot_btn.equipment_slot = slot
			slot_btn.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
			slot_btn.slot_pressed.connect(_on_slot_pressed)
			slot_btn.item_dropped.connect(_on_item_dropped)
			row.add_child(slot_btn)
			equipment_slots[slot] = slot_btn

	# Column 2: Combat slots (Weapon + Quick Slot)
	var combat_column := VBoxContainer.new()
	combat_column.name = "CombatColumn"
	combat_column.add_theme_constant_override("separation", 8)
	combat_column.alignment = BoxContainer.ALIGNMENT_CENTER
	columns_hbox.add_child(combat_column)

	for slot in COMBAT_LAYOUT:
		var slot_btn := InventorySlot.new()
		slot_btn.slot_type = InventorySlot.SlotType.EQUIPMENT
		slot_btn.equipment_slot = slot
		slot_btn.custom_minimum_size = Vector2(current_slot_size, current_slot_size)
		slot_btn.slot_pressed.connect(_on_slot_pressed)
		slot_btn.item_dropped.connect(_on_item_dropped)
		combat_column.add_child(slot_btn)
		equipment_slots[slot] = slot_btn


func _build_backpack_column(parent: HBoxContainer) -> void:
	# Panel that expands to fill available space
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	backpack_panel.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(backpack_panel)

	# Margin container for 10% side margins
	backpack_margin = MarginContainer.new()
	backpack_margin.name = "BackpackMargin"
	backpack_panel.add_child(backpack_margin)

	# VBox for header + inventory
	var vbox := VBoxContainer.new()
	vbox.name = "BackpackVBox"
	vbox.add_theme_constant_override("separation", 8)
	backpack_margin.add_child(vbox)

	# Header row: "Backpack | Gold: XY" + trash/split icons
	var header_row := HBoxContainer.new()
	header_row.name = "HeaderRow"
	header_row.add_theme_constant_override("separation", 4)
	vbox.add_child(header_row)

	var backpack_label := Label.new()
	backpack_label.text = "Backpack"
	backpack_label.add_theme_font_size_override("font_size", 14)
	header_row.add_child(backpack_label)

	var separator := Label.new()
	separator.text = " | "
	separator.add_theme_font_size_override("font_size", 14)
	header_row.add_child(separator)

	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.modulate = Color(1.0, 0.85, 0.0)
	header_row.add_child(gold_label)

	# Spacer to push icons to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	# Split stack button
	split_button = Button.new()
	split_button.name = "SplitButton"
	split_button.text = "½"
	split_button.tooltip_text = "Split Stack (tap, then tap a stack)"
	split_button.custom_minimum_size = Vector2(28, 28)
	split_button.pressed.connect(_on_split_pressed)
	header_row.add_child(split_button)

	# Use item button (also accepts drops)
	use_button = Button.new()
	use_button.name = "UseButton"
	use_button.text = "Use"
	use_button.tooltip_text = "Use selected item (or drag potion here)"
	use_button.custom_minimum_size = Vector2(36, 28)
	use_button.set_script(preload("res://scripts/ui/inventory/use_drop_zone.gd"))
	use_button.panel_ref = self
	use_button.pressed.connect(_on_use_pressed)
	header_row.add_child(use_button)

	# Trash drop zone (accepts item drops to destroy)
	var trash_zone := _create_trash_drop_zone()
	header_row.add_child(trash_zone)

	# Scroll container for vertical scrolling
	var scroll_container := ScrollContainer.new()
	scroll_container.name = "BackpackScroll"
	scroll_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll_container)

	# Grid container - 7 columns
	backpack_container = GridContainer.new()
	backpack_container.name = "BackpackGrid"
	backpack_container.columns = 7
	backpack_container.add_theme_constant_override("h_separation", 4)
	backpack_container.add_theme_constant_override("v_separation", 4)
	scroll_container.add_child(backpack_container)

	# Create backpack slots (count from database)
	var slot_count := DatabaseLoader.get_setting_int("inventory_slots", 25)
	for i in slot_count:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.slot_pressed.connect(_on_slot_pressed)
		slot.item_dropped.connect(_on_item_dropped)
		slot.drag_started.connect(_on_drag_started)
		slot.drag_ended.connect(_on_drag_ended)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)

	# Apply margins and calculate slot sizes after layout is ready
	backpack_panel.ready.connect(_on_backpack_ready.bind(backpack_panel, backpack_margin, scroll_container))


func _on_backpack_ready(panel: PanelContainer, margin: MarginContainer, scroll: ScrollContainer) -> void:
	# Wait one frame for layout to settle
	await get_tree().process_frame

	# No side margins for now (can be adjusted in Godot Inspector on BackpackMargin node)

	# Calculate slot size to fill width with 7 columns
	var available_width := scroll.size.x
	var columns := 7
	var total_separation := (columns - 1) * 4  # 4px separation
	var slot_size := floori((available_width - total_separation) / columns)

	# Apply size to all slots
	for slot in backpack_slots:
		slot.custom_minimum_size = Vector2(slot_size, slot_size)


func _on_main_hbox_resized() -> void:
	var gap := maxi(16, int(main_hbox.size.x * COLUMN_GAP_PCT))
	main_hbox.add_theme_constant_override("separation", gap)


func _create_trash_drop_zone() -> Control:
	## Create a trash drop zone that accepts dragged items
	var zone := Panel.new()
	zone.name = "TrashZone"
	zone.custom_minimum_size = Vector2(32, 28)
	zone.tooltip_text = "Drag item here to destroy"

	# Add trash icon label
	var label := Label.new()
	label.text = "🗑"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zone.add_child(label)

	# Override drag methods using callables
	zone.set_script(preload("res://scripts/ui/inventory/trash_drop_zone.gd"))
	zone.set_meta("panel_ref", self)

	return zone


func handle_trash_drop(slot: InventorySlot) -> void:
	## Called when an item is dropped on the trash zone
	var source: String
	var index: int

	if slot.slot_type == InventorySlot.SlotType.BACKPACK:
		source = "backpack"
		index = slot.backpack_index
	else:
		source = "equipment"
		index = slot.equipment_slot

	var result := Inventory.destroy_item(source, index)

	if result.get("needs_confirm", false):
		# Show confirmation dialog for rare+ items
		pending_destroy_source = source
		pending_destroy_index = index
		_show_destroy_confirmation(result.item)
	elif result.get("success", false):
		Debug.info("UI", "Item destroyed")


func handle_use_drop(slot: InventorySlot) -> void:
	## Called when a consumable is dropped on the Use button
	var source: String
	var index: int

	if slot.slot_type == InventorySlot.SlotType.BACKPACK:
		source = "backpack"
		index = slot.backpack_index
	else:
		source = "equipment"
		index = slot.equipment_slot

	var result := Inventory.use_item(source, index)

	if result.get("success", false):
		Debug.info("UI", "Used item via drag", result.get("message", ""))
	else:
		Debug.info("UI", "Use failed", result.get("message", ""))


func _show_destroy_confirmation(item: ItemData) -> void:
	## Show confirmation dialog for destroying rare+ items
	# Create simple confirmation popup
	var dialog := AcceptDialog.new()
	dialog.title = "Destroy Item?"
	dialog.dialog_text = "Are you sure you want to destroy %s?\nThis item is %s quality!" % [item.item_name, ItemData.get_rarity_name(item.rarity)]
	dialog.ok_button_text = "Destroy"
	dialog.add_cancel_button("Cancel")
	dialog.confirmed.connect(_on_destroy_confirmed)
	dialog.canceled.connect(_on_destroy_cancelled)
	add_child(dialog)
	dialog.popup_centered()


func _on_destroy_confirmed() -> void:
	## Confirmed destruction of rare+ item
	if pending_destroy_source != "":
		Inventory.destroy_item(pending_destroy_source, pending_destroy_index, true)
	pending_destroy_source = ""
	pending_destroy_index = -1


func _on_destroy_cancelled() -> void:
	## Cancelled destruction
	pending_destroy_source = ""
	pending_destroy_index = -1


func _on_panel_resized(panel: PanelContainer, margin_container: MarginContainer, content: Control, is_backpack: bool) -> void:
	var panel_width := panel.size.x
	var panel_height := panel.size.y

	if is_backpack:
		# No margins/padding on backpack for now
		margin_container.add_theme_constant_override("margin_left", 0)
		margin_container.add_theme_constant_override("margin_right", 0)
		margin_container.add_theme_constant_override("margin_top", 0)
		margin_container.add_theme_constant_override("margin_bottom", 0)
		content.add_theme_constant_override("separation", 0)
	else:
		# Calculate proportional margins for equipment (minimum 8px for readability)
		var side_margin := maxi(8, int(panel_width * MARGIN_SIDE_PCT))
		var top_margin := maxi(6, int(panel_height * MARGIN_TOP_PCT))
		var bottom_margin := maxi(8, int(panel_height * MARGIN_BOTTOM_PCT))

		# Apply margins
		margin_container.add_theme_constant_override("margin_left", side_margin)
		margin_container.add_theme_constant_override("margin_right", side_margin)
		margin_container.add_theme_constant_override("margin_top", top_margin)
		margin_container.add_theme_constant_override("margin_bottom", bottom_margin)


func _build_item_popup() -> void:
	# Create a CanvasLayer above CharacterMenu (layer 20) for the popup
	_popup_layer = CanvasLayer.new()
	_popup_layer.name = "ItemPopupLayer"
	_popup_layer.layer = 30

	item_popup = ItemPopup.new()
	item_popup.name = "ItemPopup"
	_popup_layer.add_child(item_popup)

	# Connect popup closed signal
	item_popup.closed.connect(_on_popup_closed)

	call_deferred("_add_popup_to_root")


func _add_popup_to_root() -> void:
	if _popup_layer and is_inside_tree():
		get_tree().root.add_child(_popup_layer)


func _exit_tree() -> void:
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null
		item_popup = null


func _connect_signals() -> void:
	Inventory.inventory_changed.connect(_on_inventory_changed)
	Inventory.equipment_changed.connect(_on_equipment_changed)
	Inventory.item_selected.connect(_on_item_selected)
	Inventory.item_deselected.connect(_on_item_deselected)
	Inventory.gold_changed.connect(_on_gold_changed)


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
	Debug.info("UI", "Slot pressed", "type=%s index=%d" % [slot.slot_type, slot_idx])

	# Select item to show details popup
	if slot.slot_type == InventorySlot.SlotType.BACKPACK:
		Inventory.select_backpack_item(slot.backpack_index)
	else:
		Inventory.select_equipment_item(slot.equipment_slot)


func _on_item_dropped(from_slot: InventorySlot, to_slot: InventorySlot) -> void:
	## Handle drag & drop between slots
	var from_source: String
	var from_index: int
	var to_source: String
	var to_index: int

	# Determine source info
	if from_slot.slot_type == InventorySlot.SlotType.BACKPACK:
		from_source = "backpack"
		from_index = from_slot.backpack_index
	else:
		from_source = "equipment"
		from_index = from_slot.equipment_slot

	# Determine target info
	if to_slot.slot_type == InventorySlot.SlotType.BACKPACK:
		to_source = "backpack"
		to_index = to_slot.backpack_index
	else:
		to_source = "equipment"
		to_index = to_slot.equipment_slot

	# Perform the swap via inventory manager
	Inventory.drag_drop_swap(from_source, from_index, to_source, to_index)


func _on_split_pressed() -> void:
	## Handle split button - if item selected, split it
	if Inventory.has_selection() and Inventory.selected_source == "backpack":
		Inventory.split_stack("backpack", Inventory.selected_index)
	else:
		Debug.info("UI", "Split: Select a backpack item first")


func _on_use_pressed() -> void:
	## Handle use button - use the selected item (consume charge for potions)
	if not Inventory.has_selection():
		Debug.info("UI", "Use: Select an item first")
		return

	var result := Inventory.use_item(Inventory.selected_source, Inventory.selected_index)

	if result.get("success", false):
		Debug.info("UI", "Used item", result.get("message", ""))
		# Update popup if open
		if item_popup.is_open() and Inventory.has_selection():
			item_popup.show_item(Inventory.selected_item, Inventory.selected_source, Inventory.selected_index)
	else:
		Debug.info("UI", "Use failed", result.get("message", "Cannot use this item"))


func _on_drag_started(slot: InventorySlot) -> void:
	## Highlight the target equipment slot when dragging an equippable item
	if slot.current_item == null:
		return

	var item: ItemData = slot.current_item
	var target_slot: ItemData.EquipSlot = ItemData.EquipSlot.NONE

	# Find target equipment slot for this item
	if item.item_type == ItemData.ItemType.CONSUMABLE:
		target_slot = ItemData.EquipSlot.QUICK_SLOT
		# Also highlight Use button for consumables
		use_button.modulate = Color(0.5, 1.0, 0.5)
	elif item is EquipmentData:
		var equip: EquipmentData = item as EquipmentData
		# Ring -> ACCESSORY_1 (finger), Amulet -> ACCESSORY_2 (neck)
		target_slot = equip.get_target_slot()

	# Highlight the target slot
	if target_slot != ItemData.EquipSlot.NONE and equipment_slots.has(target_slot):
		equipment_slots[target_slot].set_drag_highlight(true)


func _on_drag_ended(_slot: InventorySlot) -> void:
	## Clear all equipment slot highlights when drag ends
	for equip_slot in equipment_slots.values():
		equip_slot.set_drag_highlight(false)
	# Reset Use button highlight
	use_button.modulate = Color.WHITE


func _on_inventory_changed() -> void:
	_refresh_backpack()
	# Update popup if open
	if item_popup.is_open() and Inventory.has_selection():
		item_popup.show_item(Inventory.selected_item, Inventory.selected_source, Inventory.selected_index)


func _on_equipment_changed(_slot: ItemData.EquipSlot) -> void:
	_refresh_equipment()
	# Update popup if open
	if item_popup.is_open() and Inventory.has_selection():
		item_popup.show_item(Inventory.selected_item, Inventory.selected_source, Inventory.selected_index)


func _on_item_selected(item: ItemData, source: String, index: int) -> void:
	_refresh_equipment()
	_refresh_backpack()

	# Find the slot's position for popup placement
	var slot_center := Vector2.ZERO
	if source == "backpack" and index >= 0 and index < backpack_slots.size():
		var slot: InventorySlot = backpack_slots[index]
		slot_center = slot.global_position + slot.size / 2
	elif source == "equipment":
		var equip_slot := index as ItemData.EquipSlot
		if equipment_slots.has(equip_slot):
			var slot: InventorySlot = equipment_slots[equip_slot]
			slot_center = slot.global_position + slot.size / 2

	# Show popup with item details at slot position
	item_popup.show_item(item, source, index, slot_center)


func _on_item_deselected() -> void:
	_refresh_equipment()
	_refresh_backpack()
	# Close popup
	item_popup.close()


func _on_gold_changed(_new_amount: int) -> void:
	_refresh_gold()


func _on_popup_closed() -> void:
	# Popup was closed via X button or tap outside - deselect inventory
	Inventory.deselect()
