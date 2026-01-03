extends CanvasLayer
class_name ChestMenu
## ChestMenu - UI for interacting with chest contents
## Similar layout to inventory but with 3x2 chest grid and loot actions

## Number of slots in a chest
const CHEST_SLOT_COUNT: int = 6
const CHEST_COLUMNS: int = 3

## Signals
signal item_looted(item: ItemData)
signal chest_closed

## References to the chest being viewed
var current_chest: ChestBase = null
var chest_contents: Array[Dictionary] = []  # {item: ItemData, quantity: int}

## UI References
var chest_container: GridContainer
var details_container: VBoxContainer
var backpack_container: GridContainer
var backpack_scroll: ScrollContainer

## Chest grid slots
var chest_slots: Array[InventorySlot] = []
var backpack_slots: Array[InventorySlot] = []

## Details panel elements
var details_icon: TextureRect
var details_name: Label
var details_type: Label
var details_rarity: Label
var details_description: Label
var details_stats: Label
var details_placeholder: Label

## Action buttons
var loot_button: Button
var loot_all_button: Button
var swap_button: Button

## Feedback label
var feedback_label: Label
var feedback_timer: float = 0.0

## Selection state
var selected_chest_index: int = -1
var selected_backpack_index: int = -1
var selected_source: String = ""  # "chest" or "backpack"

## Swap mode
var swap_mode: bool = false

## Main panel reference for responsive sizing
var menu_panel: Panel = null

## Design size for responsive scaling (800x560 from _build_ui)
const DESIGN_WIDTH := 800.0
const DESIGN_HEIGHT := 560.0


func _ready() -> void:
	layer = 25
	visible = false
	_build_ui()

	# Apply responsive sizing
	call_deferred("_apply_responsive_size")

	# Connect to viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)

	Debug.info("UI", "ChestMenu initialized")


func _on_viewport_resized() -> void:
	_apply_responsive_size()


func _apply_responsive_size() -> void:
	## Constrain panel size to fit viewport on small screens
	if not menu_panel:
		return

	if ResponsiveUI:
		ResponsiveUI.constrain_centered_panel(menu_panel, DESIGN_WIDTH, DESIGN_HEIGHT, 0.02)
	else:
		# Fallback if ResponsiveUI not loaded yet
		var vp_size := get_viewport().get_visible_rect().size
		var max_width := vp_size.x * 0.96
		var max_height := vp_size.y * 0.96
		var width := minf(DESIGN_WIDTH, max_width)
		var height := minf(DESIGN_HEIGHT, max_height)
		menu_panel.offset_left = -width / 2.0
		menu_panel.offset_right = width / 2.0
		menu_panel.offset_top = -height / 2.0
		menu_panel.offset_bottom = height / 2.0


func _process(delta: float) -> void:
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_label.visible = false


func _build_ui() -> void:
	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.gui_input.connect(_on_dimmer_input)
	add_child(dimmer)

	# Main panel
	menu_panel = Panel.new()
	menu_panel.name = "MenuPanel"
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -400
	menu_panel.offset_top = -280
	menu_panel.offset_right = 400
	menu_panel.offset_bottom = 280
	add_child(menu_panel)

	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	menu_panel.add_child(vbox)

	# Header
	_build_header(vbox)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Content area (3 columns: Chest | Details | Backpack)
	var content := HBoxContainer.new()
	content.name = "ContentArea"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	vbox.add_child(content)

	# Build columns
	_build_chest_column(content)
	_build_details_column(content)
	_build_backpack_column(content)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	parent.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.text = "Chest"
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.text = "X"
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)


func _build_chest_column(parent: HBoxContainer) -> void:
	var chest_panel := PanelContainer.new()
	chest_panel.name = "ChestPanel"
	chest_panel.custom_minimum_size.x = 200
	parent.add_child(chest_panel)

	var chest_vbox := VBoxContainer.new()
	chest_vbox.add_theme_constant_override("separation", 8)
	chest_panel.add_child(chest_vbox)

	# Chest name header
	var chest_header := Label.new()
	chest_header.name = "ChestHeader"
	chest_header.text = "Chest Contents"
	chest_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_header.add_theme_font_size_override("font_size", 16)
	chest_vbox.add_child(chest_header)

	# 3x2 Grid for chest items
	chest_container = GridContainer.new()
	chest_container.name = "ChestGrid"
	chest_container.columns = CHEST_COLUMNS
	chest_container.add_theme_constant_override("h_separation", 4)
	chest_container.add_theme_constant_override("v_separation", 4)
	chest_vbox.add_child(chest_container)

	# Create chest slots
	for i in CHEST_SLOT_COUNT:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(56, 56)
		slot.slot_pressed.connect(_on_chest_slot_pressed)
		chest_container.add_child(slot)
		chest_slots.append(slot)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_vbox.add_child(spacer)

	# Gold display
	var gold_label := Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 0"
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.modulate = Color(1.0, 0.85, 0.0)
	chest_vbox.add_child(gold_label)

	# Loot All button
	loot_all_button = Button.new()
	loot_all_button.name = "LootAllButton"
	loot_all_button.text = "Loot All"
	loot_all_button.custom_minimum_size = Vector2(0, 40)
	loot_all_button.pressed.connect(_on_loot_all_pressed)
	chest_vbox.add_child(loot_all_button)


func _build_details_column(parent: HBoxContainer) -> void:
	var details_panel := PanelContainer.new()
	details_panel.name = "DetailsPanel"
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(details_panel)

	details_container = VBoxContainer.new()
	details_container.add_theme_constant_override("separation", 8)
	details_panel.add_child(details_container)

	# Header
	var header := Label.new()
	header.text = "Item Details"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	details_container.add_child(header)

	# Placeholder
	details_placeholder = Label.new()
	details_placeholder.name = "Placeholder"
	details_placeholder.text = "Select an item to view details"
	details_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_placeholder.modulate = Color(0.6, 0.6, 0.6)
	details_container.add_child(details_placeholder)

	# Info container (hidden until item selected)
	var info_container := VBoxContainer.new()
	info_container.name = "InfoContainer"
	info_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_container.add_theme_constant_override("separation", 4)
	info_container.visible = false
	details_container.add_child(info_container)

	# Icon and name row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	info_container.add_child(top_row)

	var icon_bg := ColorRect.new()
	icon_bg.custom_minimum_size = Vector2(80, 80)
	icon_bg.color = Color(0.2, 0.2, 0.25, 1)
	top_row.add_child(icon_bg)

	details_icon = TextureRect.new()
	details_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	details_icon.offset_left = 4
	details_icon.offset_top = 4
	details_icon.offset_right = -4
	details_icon.offset_bottom = -4
	details_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	details_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_bg.add_child(details_icon)

	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	details_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_container.add_child(details_stats)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_container.add_child(spacer)

	# Action buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_container.add_child(button_row)

	loot_button = Button.new()
	loot_button.name = "LootButton"
	loot_button.text = "Loot"
	loot_button.custom_minimum_size = Vector2(80, 40)
	loot_button.pressed.connect(_on_loot_pressed)
	button_row.add_child(loot_button)

	swap_button = Button.new()
	swap_button.name = "SwapButton"
	swap_button.text = "Swap"
	swap_button.custom_minimum_size = Vector2(80, 40)
	swap_button.pressed.connect(_on_swap_pressed)
	button_row.add_child(swap_button)

	# Feedback label
	feedback_label = Label.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.modulate = Color(1.0, 0.5, 0.3)
	feedback_label.visible = false
	info_container.add_child(feedback_label)


func _build_backpack_column(parent: HBoxContainer) -> void:
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.custom_minimum_size.x = 280
	parent.add_child(backpack_panel)

	var backpack_vbox := VBoxContainer.new()
	backpack_vbox.add_theme_constant_override("separation", 4)
	backpack_panel.add_child(backpack_vbox)

	# Header with inventory space
	var header_row := HBoxContainer.new()
	backpack_vbox.add_child(header_row)

	var header := Label.new()
	header.text = "Inventory"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 16)
	header_row.add_child(header)

	var space_label := Label.new()
	space_label.name = "SpaceLabel"
	space_label.add_theme_font_size_override("font_size", 12)
	space_label.modulate = Color(0.7, 0.7, 0.7)
	header_row.add_child(space_label)

	# Scrollable backpack grid
	backpack_scroll = ScrollContainer.new()
	backpack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backpack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backpack_vbox.add_child(backpack_scroll)

	backpack_container = GridContainer.new()
	backpack_container.columns = 5
	backpack_container.add_theme_constant_override("h_separation", 4)
	backpack_container.add_theme_constant_override("v_separation", 4)
	backpack_scroll.add_child(backpack_container)

	# Create backpack slots
	for i in Inventory.BACKPACK_SIZE:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(48, 48)
		slot.slot_pressed.connect(_on_backpack_slot_pressed)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)


## Open the chest menu with specified chest and contents
func open_chest(chest: ChestBase, contents: Dictionary) -> void:
	current_chest = chest
	chest_contents.clear()

	# Initialize chest contents array
	for i in CHEST_SLOT_COUNT:
		chest_contents.append({})

	# Populate with generated items
	var items: Array = contents.get("items", [])
	for i in mini(items.size(), CHEST_SLOT_COUNT):
		if items[i] is ItemData:
			chest_contents[i] = {item = items[i], quantity = 1}

	# Set chest title
	var title: Label = get_node_or_null("MenuPanel/VBox/HBoxContainer/Title")
	if not title:
		title = get_node_or_null("MenuPanel/VBox/Header/Title")
	if title:
		title.text = "%s Chest" % ChestBase.TIER_NAMES[chest.chest_tier]

	# Update chest header in chest panel
	var chest_header: Label = get_node_or_null("MenuPanel/VBox/ContentArea/ChestPanel/VBoxContainer/ChestHeader")
	if chest_header:
		chest_header.text = "%s Chest" % ChestBase.TIER_NAMES[chest.chest_tier]

	# Update gold display
	var gold_amount: int = contents.get("gold", 0)
	var gold_label: Label = get_node_or_null("MenuPanel/VBox/ContentArea/ChestPanel/VBoxContainer/GoldLabel")
	if gold_label:
		gold_label.text = "Gold: %d" % gold_amount
		gold_label.visible = gold_amount > 0

	# Reset selection
	_deselect_all()

	# Refresh displays
	_refresh_chest_slots()
	_refresh_backpack()
	_refresh_details()
	_update_space_label()

	visible = true
	Debug.info("UI", "Chest menu opened: %s" % chest.display_name)


func close_menu() -> void:
	# Store remaining items back in chest for respawn
	if current_chest:
		var remaining_items: Array[ItemData] = []
		for slot in chest_contents:
			if not slot.is_empty():
				remaining_items.append(slot.item)
		# Store for persistence if needed
		current_chest.set_meta("remaining_items", remaining_items)

	visible = false
	current_chest = null
	chest_contents.clear()
	_deselect_all()
	chest_closed.emit()
	Debug.info("UI", "Chest menu closed")


func _refresh_chest_slots() -> void:
	for i in chest_slots.size():
		var slot_ui: InventorySlot = chest_slots[i]
		if i < chest_contents.size():
			var item_data: Dictionary = chest_contents[i]
			if item_data.is_empty():
				slot_ui.clear_item()
			else:
				slot_ui.set_item(item_data.item, item_data.quantity)
		else:
			slot_ui.clear_item()

		# Update selection state
		slot_ui.set_selected(selected_source == "chest" and selected_chest_index == i)


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
		slot_ui.set_selected(selected_source == "backpack" and selected_backpack_index == i)


func _refresh_details() -> void:
	var info_container := details_container.get_node_or_null("InfoContainer")
	if not info_container:
		return

	var item: ItemData = null
	if selected_source == "chest" and selected_chest_index >= 0:
		var slot: Dictionary = chest_contents[selected_chest_index]
		if not slot.is_empty():
			item = slot.item
	elif selected_source == "backpack" and selected_backpack_index >= 0:
		var slot: Dictionary = Inventory.get_backpack_item(selected_backpack_index)
		if not slot.is_empty():
			item = slot.item

	if item == null:
		details_placeholder.visible = true
		info_container.visible = false
		return

	details_placeholder.visible = false
	info_container.visible = true

	# Update details
	details_name.text = item.item_name
	details_name.modulate = ItemData.get_rarity_color(item.rarity)

	details_rarity.text = ItemData.get_rarity_name(item.rarity)
	details_rarity.modulate = ItemData.get_rarity_color(item.rarity)

	details_description.text = item.description if item.description else "No description"
	details_icon.texture = item.icon

	# Type and stats
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
	if selected_source == "chest" and selected_chest_index >= 0:
		loot_button.visible = true
		loot_button.text = "Loot"
		swap_button.visible = true
		swap_button.text = "Swap" if not swap_mode else "Cancel"
	elif selected_source == "backpack" and selected_backpack_index >= 0:
		loot_button.visible = false
		swap_button.visible = swap_mode
		swap_button.text = "Cancel" if swap_mode else "Swap"
	else:
		loot_button.visible = false
		swap_button.visible = false


func _update_space_label() -> void:
	var space_label: Label = get_node_or_null("MenuPanel/VBox/ContentArea/BackpackPanel/VBoxContainer/HBoxContainer/SpaceLabel")
	if space_label:
		var used := 0
		for slot in Inventory.backpack:
			if not slot.is_empty():
				used += 1
		space_label.text = "%d/%d" % [used, Inventory.BACKPACK_SIZE]


func _deselect_all() -> void:
	selected_source = ""
	selected_chest_index = -1
	selected_backpack_index = -1
	swap_mode = false
	feedback_label.visible = false


func _show_feedback(text: String, duration: float = 2.0) -> void:
	feedback_label.text = text
	feedback_label.visible = true
	feedback_timer = duration


func _has_inventory_space() -> bool:
	for slot in Inventory.backpack:
		if slot.is_empty():
			return true
	return false


## Slot press handlers

func _on_chest_slot_pressed(slot: InventorySlot) -> void:
	var index := slot.backpack_index

	if swap_mode:
		# In swap mode - swap with backpack selection
		if selected_source == "backpack" and selected_backpack_index >= 0:
			_swap_items(index, selected_backpack_index)
		swap_mode = false
		_deselect_all()
		_refresh_chest_slots()
		_refresh_backpack()
		_refresh_details()
		return

	# Select chest item
	if index < chest_contents.size() and not chest_contents[index].is_empty():
		selected_source = "chest"
		selected_chest_index = index
		selected_backpack_index = -1
	else:
		_deselect_all()

	_refresh_chest_slots()
	_refresh_backpack()
	_refresh_details()


func _on_backpack_slot_pressed(slot: InventorySlot) -> void:
	var index := slot.backpack_index

	if swap_mode:
		# In swap mode - swap with chest selection
		if selected_source == "chest" and selected_chest_index >= 0:
			_swap_items(selected_chest_index, index)
		swap_mode = false
		_deselect_all()
		_refresh_chest_slots()
		_refresh_backpack()
		_refresh_details()
		return

	# Select backpack item (for potential swap)
	var item_data: Dictionary = Inventory.get_backpack_item(index)
	if not item_data.is_empty():
		selected_source = "backpack"
		selected_backpack_index = index
		selected_chest_index = -1
	else:
		_deselect_all()

	_refresh_chest_slots()
	_refresh_backpack()
	_refresh_details()


## Action handlers

func _on_loot_pressed() -> void:
	if selected_source != "chest" or selected_chest_index < 0:
		return

	var slot: Dictionary = chest_contents[selected_chest_index]
	if slot.is_empty():
		return

	if not _has_inventory_space():
		_show_feedback("Inventory full!")
		return

	# Add item to inventory
	var item: ItemData = slot.item
	if Inventory.add_item(item, slot.quantity):
		chest_contents[selected_chest_index] = {}
		item_looted.emit(item)
		Debug.info("Chest", "Looted item: %s" % item.item_name)
		_deselect_all()
	else:
		_show_feedback("Inventory full!")

	_refresh_chest_slots()
	_refresh_backpack()
	_refresh_details()
	_update_space_label()


func _on_loot_all_pressed() -> void:
	# Loot gold first
	var gold_label: Label = get_node_or_null("MenuPanel/VBox/ContentArea/ChestPanel/VBoxContainer/GoldLabel")
	if gold_label and gold_label.visible:
		var gold_text: String = gold_label.text
		var gold_match := gold_text.get_slice(":", 1).strip_edges()
		var gold_amount := gold_match.to_int()
		if gold_amount > 0:
			Inventory.add_gold(gold_amount)
			gold_label.text = "Gold: 0"
			gold_label.visible = false

	# Loot all items
	var looted_count := 0
	var failed_count := 0

	for i in chest_contents.size():
		var slot: Dictionary = chest_contents[i]
		if slot.is_empty():
			continue

		if not _has_inventory_space():
			failed_count += 1
			continue

		if Inventory.add_item(slot.item, slot.quantity):
			item_looted.emit(slot.item)
			chest_contents[i] = {}
			looted_count += 1
		else:
			failed_count += 1

	if failed_count > 0:
		_show_feedback("Inventory full! %d items left" % failed_count)
	elif looted_count > 0:
		Debug.info("Chest", "Looted all %d items" % looted_count)

	_deselect_all()
	_refresh_chest_slots()
	_refresh_backpack()
	_refresh_details()
	_update_space_label()

	# Close menu if chest is empty
	var has_items := false
	for slot in chest_contents:
		if not slot.is_empty():
			has_items = true
			break

	if not has_items:
		# Mark chest as looted
		if current_chest:
			current_chest.current_state = ChestBase.ChestState.LOOTED
			current_chest._on_chest_looted()
		close_menu()


func _on_swap_pressed() -> void:
	if swap_mode:
		swap_mode = false
		_update_action_buttons()
		return

	if selected_source == "chest" and selected_chest_index >= 0:
		swap_mode = true
		_show_feedback("Select inventory slot to swap")
		_update_action_buttons()


func _swap_items(chest_index: int, backpack_index: int) -> void:
	var chest_slot: Dictionary = chest_contents[chest_index]
	var backpack_slot: Dictionary = Inventory.get_backpack_item(backpack_index)

	# Swap items
	if backpack_slot.is_empty():
		# Just move chest item to backpack
		if not chest_slot.is_empty():
			Inventory.add_item(chest_slot.item, chest_slot.quantity)
			chest_contents[chest_index] = {}
	else:
		# Actual swap
		chest_contents[chest_index] = {
			item = backpack_slot.item,
			quantity = backpack_slot.quantity
		}

		if chest_slot.is_empty():
			Inventory.remove_item_at(backpack_index, backpack_slot.quantity)
		else:
			# Remove old backpack item and add chest item
			Inventory.remove_item_at(backpack_index, backpack_slot.quantity)
			Inventory.add_item(chest_slot.item, chest_slot.quantity)

	Debug.info("Chest", "Swapped items between chest and inventory")
	_update_space_label()


func _on_close_pressed() -> void:
	close_menu()


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_menu()
