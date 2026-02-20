extends CanvasLayer
class_name ChestMenu
## ChestMenu - UI for interacting with chest contents
## Two-column layout: Chest Contents | Backpack
## Uses ItemPopup for item details (no details column)
## Supports drag & drop for moving items between chest and inventory
## Gold appears as a regular slot item that converts to currency when looted

## Number of slots in a chest
const CHEST_SLOT_COUNT: int = 6
const CHEST_COLUMNS: int = 3
const BACKPACK_COLUMNS: int = 5

## Responsive sizing (percentages)
const MARGIN_PCT := 0.02          # 2% margins
const COLUMN_GAP_PCT := 0.03      # 3% gap between chest/backpack columns
const SLOT_SEPARATION_PCT := 0.01 # 1% slot separation
const BUTTON_HEIGHT_PCT := 0.08   # 8% button height

## Design size for responsive scaling
const DESIGN_WIDTH := 700.0
const DESIGN_HEIGHT := 480.0

## Minimum pixel values
const MIN_SEPARATION := 4
const MIN_BUTTON_HEIGHT := 36

## Signals
signal item_looted(item: ItemData)
signal gold_looted(amount: int)
signal chest_closed

## References to the chest being viewed
var current_chest: ChestBase = null
var chest_contents: Array[Dictionary] = []  # {item: ItemData, quantity: int} or {is_gold: true, amount: int}

## UI References
var menu_panel: Panel = null
var main_hbox: HBoxContainer
var chest_container: GridContainer
var backpack_container: GridContainer
var backpack_scroll: ScrollContainer
var player_gold_label: Label = null  # Player's current gold in backpack header
var loot_all_button: Button
var close_button: Button
var title_label: Label

## Chest grid slots
var chest_slots: Array[InventorySlot] = []
var backpack_slots: Array[InventorySlot] = []

## Item popup for details (shared across inventory)
var item_popup: ItemPopup = null
var _popup_layer: CanvasLayer = null

## Selection state
var selected_source: String = ""  # "chest" or "backpack"
var selected_index: int = -1

## Gold animation
var _gold_popup_label: Label = null


func _ready() -> void:
	layer = 25
	visible = false
	_build_ui()
	_build_item_popup()

	# Apply responsive sizing
	call_deferred("_apply_responsive_size")

	# Connect to viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)

	# Connect to inventory gold changes
	Inventory.gold_changed.connect(_on_player_gold_changed)

	Debug.info("UI", "ChestMenu initialized (popup-based)")


func _on_viewport_resized() -> void:
	_apply_responsive_size()


func _apply_responsive_size() -> void:
	## Constrain panel size to fit viewport on small screens
	if not menu_panel:
		return

	var responsive_ui := get_node_or_null("/root/ResponsiveUI")
	if responsive_ui:
		responsive_ui.constrain_centered_panel(menu_panel, DESIGN_WIDTH, DESIGN_HEIGHT, 0.02)
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


## Computed responsive sizes
func _get_slot_separation() -> int:
	return maxi(MIN_SEPARATION, int(DESIGN_WIDTH * SLOT_SEPARATION_PCT))

func _get_column_gap() -> int:
	return maxi(12, int(DESIGN_WIDTH * COLUMN_GAP_PCT))

func _get_button_height() -> int:
	return maxi(MIN_BUTTON_HEIGHT, int(DESIGN_HEIGHT * BUTTON_HEIGHT_PCT))


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
	menu_panel.offset_left = -DESIGN_WIDTH / 2.0
	menu_panel.offset_top = -DESIGN_HEIGHT / 2.0
	menu_panel.offset_right = DESIGN_WIDTH / 2.0
	menu_panel.offset_bottom = DESIGN_HEIGHT / 2.0
	add_child(menu_panel)

	# Main margin container
	var margin := UITheme.create_margin_container()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(margin)

	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	UITheme.setup_vbox(vbox, UITheme.SEPARATION_NORMAL)
	margin.add_child(vbox)

	# Header
	_build_header(vbox)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Content area (2 columns: Chest | Backpack)
	main_hbox = HBoxContainer.new()
	main_hbox.name = "ContentArea"
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", _get_column_gap())
	vbox.add_child(main_hbox)

	# Build columns
	_build_chest_column(main_hbox)
	_build_backpack_column(main_hbox)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.name = "Header"
	UITheme.setup_hbox(header, UITheme.SEPARATION_NORMAL)
	parent.add_child(header)

	title_label = Label.new()
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	title_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_NAV)
	title_label.text = "Chest"
	header.add_child(title_label)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.custom_minimum_size = Vector2(UITheme.CLOSE_BUTTON_SIZE, UITheme.CLOSE_BUTTON_SIZE)
	close_button.text = "X"
	close_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Style close button
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = UITheme.COLOR_DEBUFF
	close_style.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = UITheme.COLOR_DEBUFF.lightened(0.2)
	close_hover.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	close_button.add_theme_stylebox_override("hover", close_hover)


func _build_chest_column(parent: HBoxContainer) -> void:
	var chest_panel := PanelContainer.new()
	chest_panel.name = "ChestPanel"
	chest_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())
	parent.add_child(chest_panel)

	var chest_margin := UITheme.create_margin_container()
	chest_panel.add_child(chest_margin)

	var chest_vbox := VBoxContainer.new()
	chest_vbox.name = "ChestVBox"
	UITheme.setup_vbox(chest_vbox, UITheme.SEPARATION_NORMAL)
	chest_margin.add_child(chest_vbox)

	# Chest header
	var chest_header := UITheme.create_label("Contents", UITheme.FONT_SIZE_HEADER)
	chest_header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	chest_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_vbox.add_child(chest_header)

	# Center container for chest grid
	var center := CenterContainer.new()
	center.name = "ChestCenter"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_vbox.add_child(center)

	# 3x2 Grid for chest items (including gold as a slot)
	chest_container = GridContainer.new()
	chest_container.name = "ChestGrid"
	chest_container.columns = CHEST_COLUMNS
	UITheme.setup_grid(chest_container, _get_slot_separation(), _get_slot_separation())
	center.add_child(chest_container)

	# Create chest slots
	for i in CHEST_SLOT_COUNT:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(UITheme.SLOT_SIZE_NORMAL, UITheme.SLOT_SIZE_NORMAL)
		slot.slot_pressed.connect(_on_chest_slot_pressed)
		slot.item_dropped.connect(_on_item_dropped_to_chest)
		slot.drag_started.connect(_on_drag_started)
		slot.drag_ended.connect(_on_drag_ended)
		chest_container.add_child(slot)
		chest_slots.append(slot)

	# Loot All button
	loot_all_button = Button.new()
	loot_all_button.name = "LootAllButton"
	loot_all_button.text = "Loot All"
	loot_all_button.custom_minimum_size = Vector2(0, _get_button_height())
	loot_all_button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	loot_all_button.pressed.connect(_on_loot_all_pressed)
	chest_vbox.add_child(loot_all_button)


func _build_backpack_column(parent: HBoxContainer) -> void:
	var backpack_panel := PanelContainer.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backpack_panel.add_theme_stylebox_override("panel", UITheme.create_panel_style())
	parent.add_child(backpack_panel)

	var backpack_margin := UITheme.create_margin_container()
	backpack_panel.add_child(backpack_margin)

	var backpack_vbox := VBoxContainer.new()
	backpack_vbox.name = "BackpackVBox"
	UITheme.setup_vbox(backpack_vbox, UITheme.SEPARATION_SMALL)
	backpack_margin.add_child(backpack_vbox)

	# Header row: Backpack | Gold: X | Slots: X/Y
	var header_row := HBoxContainer.new()
	header_row.name = "HeaderRow"
	UITheme.setup_hbox(header_row, UITheme.SEPARATION_SMALL)
	backpack_vbox.add_child(header_row)

	var header := UITheme.create_label("Backpack", UITheme.FONT_SIZE_HEADER)
	header.add_theme_color_override("font_color", UITheme.COLOR_TEXT_HEADER)
	header_row.add_child(header)

	# Separator
	var sep := UITheme.create_label(" | ", UITheme.FONT_SIZE_HEADER)
	sep.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	header_row.add_child(sep)

	# Player's gold display
	player_gold_label = Label.new()
	player_gold_label.name = "PlayerGoldLabel"
	player_gold_label.text = "Gold: %d" % Inventory.gold
	player_gold_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	player_gold_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	header_row.add_child(player_gold_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	var space_label := Label.new()
	space_label.name = "SpaceLabel"
	space_label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	space_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	header_row.add_child(space_label)

	# Scrollable backpack grid
	backpack_scroll = ScrollContainer.new()
	backpack_scroll.name = "BackpackScroll"
	backpack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	backpack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backpack_vbox.add_child(backpack_scroll)

	backpack_container = GridContainer.new()
	backpack_container.name = "BackpackGrid"
	backpack_container.columns = BACKPACK_COLUMNS
	UITheme.setup_grid(backpack_container, _get_slot_separation(), _get_slot_separation())
	backpack_scroll.add_child(backpack_container)

	# Create backpack slots
	for i in Inventory.backpack_size:
		var slot := InventorySlot.new()
		slot.slot_type = InventorySlot.SlotType.BACKPACK
		slot.backpack_index = i
		slot.custom_minimum_size = Vector2(UITheme.SLOT_SIZE_SMALL, UITheme.SLOT_SIZE_SMALL)
		slot.slot_pressed.connect(_on_backpack_slot_pressed)
		slot.item_dropped.connect(_on_item_dropped_to_backpack)
		slot.drag_started.connect(_on_drag_started)
		slot.drag_ended.connect(_on_drag_ended)
		backpack_container.add_child(slot)
		backpack_slots.append(slot)


func _build_item_popup() -> void:
	# Create a CanvasLayer above ChestMenu for the popup
	_popup_layer = CanvasLayer.new()
	_popup_layer.name = "ChestItemPopupLayer"
	_popup_layer.layer = 30

	item_popup = ItemPopup.new()
	item_popup.name = "ChestItemPopup"
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


## Open the chest menu with specified chest and contents
func open_chest(chest: ChestBase, contents: Dictionary) -> void:
	current_chest = chest
	chest_contents.clear()

	# Initialize chest contents array
	for i in CHEST_SLOT_COUNT:
		chest_contents.append({})

	# Populate with generated items
	var items: Array = contents.get("items", [])
	var slot_index := 0
	for i in mini(items.size(), CHEST_SLOT_COUNT):
		if items[i] is ItemData:
			chest_contents[slot_index] = {item = items[i], quantity = 1}
			slot_index += 1

	# Add gold as a slot item (if any) in the next available slot
	var gold_amount: int = contents.get("gold", 0)
	if gold_amount > 0 and slot_index < CHEST_SLOT_COUNT:
		chest_contents[slot_index] = {is_gold = true, amount = gold_amount}

	# Set chest title
	if title_label:
		title_label.text = "%s Chest" % ChestBase.TIER_NAMES[chest.chest_tier]

	# Reset selection
	_deselect_all()

	# Refresh displays
	_refresh_chest_slots()
	_refresh_backpack()
	_update_labels()

	visible = true
	Debug.info("UI", "Chest menu opened: %s" % chest.display_name)


func close_menu() -> void:
	# Close popup if open
	if item_popup and item_popup.is_open():
		item_popup.close()

	# Store remaining items back in chest for respawn
	if current_chest:
		var remaining_items: Array[ItemData] = []
		var remaining_gold: int = 0
		for slot in chest_contents:
			if slot.get("is_gold", false):
				remaining_gold = slot.get("amount", 0)
			elif not slot.is_empty() and slot.has("item"):
				remaining_items.append(slot.item)
		current_chest.set_meta("remaining_items", remaining_items)
		current_chest.set_meta("remaining_gold", remaining_gold)

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
			var slot_data: Dictionary = chest_contents[i]
			if slot_data.is_empty():
				slot_ui.clear_item()
			elif slot_data.get("is_gold", false):
				# Gold slot
				slot_ui.set_gold(slot_data.get("amount", 0))
			else:
				# Regular item
				slot_ui.set_item(slot_data.item, slot_data.quantity)
		else:
			slot_ui.clear_item()

		# Update selection state
		slot_ui.set_selected(selected_source == "chest" and selected_index == i)


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
		slot_ui.set_selected(selected_source == "backpack" and selected_index == i)


func _update_labels() -> void:
	# Update space label
	var space_label: Label = backpack_container.get_parent().get_parent().get_node_or_null("HeaderRow/SpaceLabel")
	if space_label:
		var used := 0
		for slot in Inventory.backpack:
			if not slot.is_empty():
				used += 1
		space_label.text = "%d/%d" % [used, Inventory.backpack_size]

	# Update player gold label
	if player_gold_label:
		player_gold_label.text = "Gold: %d" % Inventory.gold


func _on_player_gold_changed(_amount: int) -> void:
	if player_gold_label:
		player_gold_label.text = "Gold: %d" % Inventory.gold


func _deselect_all() -> void:
	selected_source = ""
	selected_index = -1
	if item_popup and item_popup.is_open():
		item_popup.close()


func _has_inventory_space() -> bool:
	for slot in Inventory.backpack:
		if slot.is_empty():
			return true
	return false


#===============================================================================
# GOLD ANIMATION
#===============================================================================

func _show_gold_collected_animation(amount: int, from_pos: Vector2) -> void:
	## Show floating "+X Gold" text that rises and fades
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	label.position = from_pos - Vector2(20, 10)
	label.z_index = 100
	add_child(label)

	# Animate: rise up and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _collect_gold_from_slot(chest_index: int, trigger_pos: Vector2 = Vector2.ZERO) -> void:
	## Collect gold from a chest slot and add to player inventory
	if chest_index < 0 or chest_index >= chest_contents.size():
		return

	var slot_data: Dictionary = chest_contents[chest_index]
	if not slot_data.get("is_gold", false):
		return

	var amount: int = slot_data.get("amount", 0)
	if amount <= 0:
		return

	# Add gold to player
	Inventory.add_gold(amount)
	gold_looted.emit(amount)

	# Clear the chest slot
	chest_contents[chest_index] = {}

	# Show animation
	var anim_pos := trigger_pos
	if anim_pos == Vector2.ZERO and player_gold_label:
		anim_pos = player_gold_label.global_position
	_show_gold_collected_animation(amount, anim_pos)

	Debug.info("Chest", "Collected %d gold" % amount)


#===============================================================================
# SLOT PRESS HANDLERS (for showing popup)
#===============================================================================

func _on_chest_slot_pressed(slot: InventorySlot) -> void:
	var index := slot.backpack_index

	if index < chest_contents.size():
		var slot_data: Dictionary = chest_contents[index]

		# If it's gold, collect it on tap
		if slot_data.get("is_gold", false):
			var slot_center := slot.global_position + slot.size / 2
			_collect_gold_from_slot(index, slot_center)
			_refresh_chest_slots()
			_update_labels()
			return

		# Otherwise select item and show popup
		if not slot_data.is_empty() and slot_data.has("item"):
			selected_source = "chest"
			selected_index = index
			_show_item_popup(slot)
		else:
			_deselect_all()
	else:
		_deselect_all()

	_refresh_chest_slots()
	_refresh_backpack()


func _on_backpack_slot_pressed(slot: InventorySlot) -> void:
	var index := slot.backpack_index

	# Select backpack item and show popup
	var item_data: Dictionary = Inventory.get_backpack_item(index)
	if not item_data.is_empty():
		selected_source = "backpack"
		selected_index = index
		_show_item_popup(slot)
	else:
		_deselect_all()

	_refresh_chest_slots()
	_refresh_backpack()


func _show_item_popup(slot: InventorySlot) -> void:
	var item: ItemData = null
	if selected_source == "chest" and selected_index >= 0:
		var chest_slot: Dictionary = chest_contents[selected_index]
		if not chest_slot.is_empty() and chest_slot.has("item"):
			item = chest_slot.item
	elif selected_source == "backpack" and selected_index >= 0:
		var bp_slot: Dictionary = Inventory.get_backpack_item(selected_index)
		if not bp_slot.is_empty():
			item = bp_slot.item

	if item and item_popup:
		var slot_center := slot.global_position + slot.size / 2
		item_popup.show_item(item, selected_source, selected_index, slot_center)


func _on_popup_closed() -> void:
	# Popup was closed via X button or tap outside - deselect
	_deselect_all()
	_refresh_chest_slots()
	_refresh_backpack()


#===============================================================================
# DRAG & DROP HANDLERS
#===============================================================================

func _on_item_dropped_to_chest(from_slot: InventorySlot, to_slot: InventorySlot) -> void:
	## Handle drop onto a chest slot
	var to_index := to_slot.backpack_index

	# Don't allow dropping onto gold slot
	if to_index < chest_contents.size() and chest_contents[to_index].get("is_gold", false):
		return

	# Determine source
	if from_slot in chest_slots:
		var from_index := from_slot.backpack_index

		# If dragging gold within chest, just swap positions
		if from_index < chest_contents.size() and chest_contents[from_index].get("is_gold", false):
			_swap_chest_slots(from_index, to_index)
		else:
			# Chest to Chest swap
			_swap_chest_slots(from_index, to_index)
	else:
		# Backpack to Chest
		var from_index := from_slot.backpack_index
		_move_backpack_to_chest(from_index, to_index)

	_refresh_chest_slots()
	_refresh_backpack()
	_update_labels()


func _on_item_dropped_to_backpack(from_slot: InventorySlot, to_slot: InventorySlot) -> void:
	## Handle drop onto a backpack slot
	var to_index := to_slot.backpack_index

	# Determine source
	if from_slot in chest_slots:
		var from_index := from_slot.backpack_index

		# Check if this is gold being dropped
		if from_index < chest_contents.size() and chest_contents[from_index].get("is_gold", false):
			# Collect gold instead of moving to inventory
			var slot_center := to_slot.global_position + to_slot.size / 2
			_collect_gold_from_slot(from_index, slot_center)
		else:
			# Chest to Backpack (loot item)
			_move_chest_to_backpack(from_index, to_index)
	else:
		# Backpack to Backpack swap
		var from_index := from_slot.backpack_index
		Inventory.drag_drop_swap("backpack", from_index, "backpack", to_index)

	_refresh_chest_slots()
	_refresh_backpack()
	_update_labels()


func _swap_chest_slots(from_index: int, to_index: int) -> void:
	## Swap two chest slots
	if from_index < 0 or from_index >= chest_contents.size():
		return
	if to_index < 0 or to_index >= chest_contents.size():
		return

	var temp: Dictionary = chest_contents[from_index]
	chest_contents[from_index] = chest_contents[to_index]
	chest_contents[to_index] = temp


func _move_chest_to_backpack(chest_index: int, backpack_index: int) -> void:
	## Move item from chest to backpack (swap if backpack has item)
	if chest_index < 0 or chest_index >= chest_contents.size():
		return
	if backpack_index < 0 or backpack_index >= Inventory.backpack_size:
		return

	var chest_slot: Dictionary = chest_contents[chest_index]

	# Don't move gold as an item - it should be collected
	if chest_slot.get("is_gold", false):
		return

	var backpack_slot: Dictionary = Inventory.get_backpack_item(backpack_index)

	if backpack_slot.is_empty():
		# Just move chest item to backpack
		if not chest_slot.is_empty() and chest_slot.has("item"):
			Inventory.backpack[backpack_index] = {item = chest_slot.item, quantity = chest_slot.quantity, charges = 0}
			chest_contents[chest_index] = {}
			Inventory.inventory_changed.emit()
			item_looted.emit(chest_slot.item)
	else:
		# Swap: backpack item goes to chest, chest item goes to backpack
		chest_contents[chest_index] = {item = backpack_slot.item, quantity = backpack_slot.quantity}
		if chest_slot.is_empty() or not chest_slot.has("item"):
			Inventory.backpack[backpack_index] = {}
		else:
			Inventory.backpack[backpack_index] = {item = chest_slot.item, quantity = chest_slot.quantity, charges = 0}
			item_looted.emit(chest_slot.item)
		Inventory.inventory_changed.emit()


func _move_backpack_to_chest(backpack_index: int, chest_index: int) -> void:
	## Move item from backpack to chest (swap if chest has item)
	if chest_index < 0 or chest_index >= chest_contents.size():
		return
	if backpack_index < 0 or backpack_index >= Inventory.backpack_size:
		return

	var backpack_slot: Dictionary = Inventory.get_backpack_item(backpack_index)
	var chest_slot: Dictionary = chest_contents[chest_index]

	# Don't allow swapping with gold
	if chest_slot.get("is_gold", false):
		return

	if chest_slot.is_empty():
		# Just move backpack item to chest
		if not backpack_slot.is_empty():
			chest_contents[chest_index] = {item = backpack_slot.item, quantity = backpack_slot.quantity}
			Inventory.backpack[backpack_index] = {}
			Inventory.inventory_changed.emit()
	else:
		# Swap: chest item goes to backpack, backpack item goes to chest
		if backpack_slot.is_empty():
			Inventory.backpack[backpack_index] = {item = chest_slot.item, quantity = chest_slot.quantity, charges = 0}
			chest_contents[chest_index] = {}
			item_looted.emit(chest_slot.item)
		else:
			Inventory.backpack[backpack_index] = {item = chest_slot.item, quantity = chest_slot.quantity, charges = 0}
			chest_contents[chest_index] = {item = backpack_slot.item, quantity = backpack_slot.quantity}
			item_looted.emit(chest_slot.item)
		Inventory.inventory_changed.emit()


func _on_drag_started(_slot: InventorySlot) -> void:
	## Close popup during drag
	if item_popup and item_popup.is_open():
		item_popup.close()


func _on_drag_ended(_slot: InventorySlot) -> void:
	## Drag ended - refresh displays
	pass


#===============================================================================
# ACTION HANDLERS
#===============================================================================

func _on_loot_all_pressed() -> void:
	# Loot all items and gold
	var looted_count := 0
	var failed_count := 0

	for i in chest_contents.size():
		var slot: Dictionary = chest_contents[i]
		if slot.is_empty():
			continue

		# Handle gold
		if slot.get("is_gold", false):
			var amount: int = slot.get("amount", 0)
			if amount > 0:
				Inventory.add_gold(amount)
				gold_looted.emit(amount)
				if player_gold_label:
					_show_gold_collected_animation(amount, player_gold_label.global_position)
				chest_contents[i] = {}
				looted_count += 1
			continue

		# Handle items
		if not slot.has("item"):
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
		Debug.warn("Chest", "Inventory full! %d items left" % failed_count)
	elif looted_count > 0:
		Debug.info("Chest", "Looted all %d items" % looted_count)

	_deselect_all()
	_refresh_chest_slots()
	_refresh_backpack()
	_update_labels()

	# Mark chest as looted if completely empty (but don't close menu)
	var has_items := false
	for slot in chest_contents:
		if not slot.is_empty():
			has_items = true
			break

	if not has_items:
		if current_chest:
			current_chest.current_state = ChestBase.ChestState.LOOTED
			current_chest._on_chest_looted()


func _on_close_pressed() -> void:
	close_menu()


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_menu()
