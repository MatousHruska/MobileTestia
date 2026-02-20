extends CanvasLayer
## DebugMenu - Tappable debug menu panel replacing numpad keybinds
## Opened via the eye icon button on the HUD
## All debug actions consolidated into categorized, scrollable sections

var is_open: bool = false

## UI references
var _dimmer: ColorRect
var _panel: Panel
var _scroll: ScrollContainer
var _vbox: VBoxContainer

## Toggle button references (to update on/off state)
var _toggle_buttons: Dictionary = {}  # key -> Button

## Panel sizing (percentage of viewport)
const PANEL_WIDTH_PCT := 0.42
const PANEL_HEIGHT_PCT := 0.90
const PANEL_MARGIN_PCT := 0.02


func _ready() -> void:
	layer = 202  # Above AI overlay (201) and quest overlay (200)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func toggle() -> void:
	is_open = not is_open
	visible = is_open
	if is_open:
		_refresh_toggle_states()


func open() -> void:
	is_open = true
	visible = true
	_refresh_toggle_states()


func close() -> void:
	is_open = false
	visible = false


## ─── UI CONSTRUCTION ─────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dimmer background (tap to close)
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0, 0, 0, 0.4)
	_dimmer.gui_input.connect(_on_dimmer_input)
	add_child(_dimmer)

	# Main panel (right side)
	_panel = Panel.new()
	_panel.name = "DebugPanel"
	add_child(_panel)

	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_BG
	style.border_color = UITheme.COLOR_PANEL_BORDER
	style.set_border_width_all(UITheme.BORDER_WIDTH_NORMAL)
	style.set_corner_radius_all(UITheme.CORNER_RADIUS_NORMAL)
	_panel.add_theme_stylebox_override("panel", style)

	# Scroll container inside panel
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := UITheme.MARGIN_SMALL
	_scroll.offset_left = pad
	_scroll.offset_right = -pad
	_scroll.offset_top = pad
	_scroll.offset_bottom = -pad
	_panel.add_child(_scroll)

	# Content VBox
	_vbox = VBoxContainer.new()
	_vbox.name = "Content"
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.setup_vbox(_vbox)
	_scroll.add_child(_vbox)

	# ── Header ──
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "DEBUG MENU"
	title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HEADER)
	title.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(UITheme.BUTTON_HEIGHT_NORMAL, UITheme.BUTTON_HEIGHT_NORMAL)
	close_btn.pressed.connect(close)
	_apply_button_style(close_btn)
	header_hbox.add_child(close_btn)

	_add_separator()

	# ── OVERLAYS section ──
	_add_section_header("OVERLAYS")
	_add_toggle_button("chunk_overlay", "Chunk Borders", _on_toggle_chunk_overlay)
	_add_toggle_button("ai_overlay", "AI Debug", _on_toggle_ai_overlay)
	_add_toggle_button("quest_overlay", "Quest Debug", _on_toggle_quest_overlay)
	_add_toggle_button("pathfinding_overlay", "Pathfinding", _on_toggle_pathfinding)
	_add_separator()

	# ── SNAPSHOTS section ──
	_add_section_header("SNAPSHOTS")
	_add_action_button("Chunk State", _on_chunk_state)
	_add_action_button("Loot State", _on_loot_state)
	_add_action_button("Enemy Summary", _on_enemy_summary)
	_add_action_button("Chunk Perf", _on_chunk_perf)
	_add_action_button("Game State", _on_game_state)
	_add_action_button("Chest Persistence", _on_chest_persistence)
	_add_action_button("Debug Settings", _on_debug_settings)
	_add_separator()

	# ── DIAGNOSTICS section ──
	_add_section_header("DIAGNOSTICS")
	_add_action_button("Zone Naming", _on_zone_naming)
	_add_action_button("Zone Resolution", _on_zone_resolution)
	_add_action_button("Test Pathfinding", _on_test_pathfinding)
	_add_action_button("Test ends_when Buff", _on_test_ends_when)
	_add_separator()

	# ── LOG SETTINGS section ──
	_add_section_header("LOG SETTINGS")
	_add_action_button("Cycle Log Level", _on_cycle_log_level)
	_add_toggle_button("verbose_all", "All Verbose", _on_toggle_all_verbose)
	_add_toggle_button("verbose_npc", "NPC Verbose", _on_toggle_npc_verbose)

	# Apply initial layout
	call_deferred("_apply_layout")
	get_viewport().size_changed.connect(_apply_layout)


func _apply_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := viewport_size.x * PANEL_MARGIN_PCT
	var panel_w := viewport_size.x * PANEL_WIDTH_PCT
	var panel_h := viewport_size.y * PANEL_HEIGHT_PCT
	var panel_y := (viewport_size.y - panel_h) / 2.0

	_panel.position = Vector2(viewport_size.x - panel_w - margin, panel_y)
	_panel.size = Vector2(panel_w, panel_h)


## ─── UI HELPERS ──────────────────────────────────────────────────────────────

func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)
	label.add_theme_color_override("font_color", UITheme.COLOR_SECTION_HEADER)
	_vbox.add_child(label)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", UITheme.MARGIN_SMALL)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = UITheme.COLOR_PANEL_BORDER
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	_vbox.add_child(sep)


func _add_action_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, UITheme.BUTTON_HEIGHT_NORMAL)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_apply_button_style(btn)
	_vbox.add_child(btn)


func _add_toggle_button(key: String, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = "[ ] " + text
	btn.custom_minimum_size = Vector2(0, UITheme.BUTTON_HEIGHT_NORMAL)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_apply_button_style(btn)
	_toggle_buttons[key] = btn
	_vbox.add_child(btn)


func _set_toggle_state(key: String, active: bool) -> void:
	if not _toggle_buttons.has(key):
		return
	var btn: Button = _toggle_buttons[key]
	var label_text: String = btn.text.substr(4)  # Strip "[ ] " or "[X] " prefix
	btn.text = ("[X] " if active else "[ ] ") + label_text
	if active:
		btn.add_theme_color_override("font_color", UITheme.COLOR_LEARNED)
	else:
		btn.remove_theme_color_override("font_color")


func _apply_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.COLOR_BUTTON_BG
	normal.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	normal.content_margin_left = UITheme.MARGIN_SMALL
	normal.content_margin_right = UITheme.MARGIN_SMALL
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = UITheme.COLOR_BUTTON_BG_ACTIVE
	hover.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	hover.content_margin_left = UITheme.MARGIN_SMALL
	hover.content_margin_right = UITheme.MARGIN_SMALL
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = UITheme.COLOR_HIGHLIGHT
	pressed.set_corner_radius_all(UITheme.CORNER_RADIUS_SMALL)
	pressed.content_margin_left = UITheme.MARGIN_SMALL
	pressed.content_margin_right = UITheme.MARGIN_SMALL
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_LABEL)


func _on_dimmer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


## ─── REFRESH TOGGLE STATES ───────────────────────────────────────────────────

func _refresh_toggle_states() -> void:
	# Chunk overlay
	if ChunkManager and ChunkManager.has_method("is_overlay_enabled"):
		_set_toggle_state("chunk_overlay", ChunkManager.is_overlay_enabled())
	else:
		_set_toggle_state("chunk_overlay", false)

	# AI overlay
	var ai_overlay = _get_ai_overlay()
	_set_toggle_state("ai_overlay", ai_overlay != null and ai_overlay.enabled)

	# Quest overlay
	if UIManager and UIManager.quest_debug_overlay:
		_set_toggle_state("quest_overlay", UIManager.quest_debug_overlay.enabled)
	else:
		_set_toggle_state("quest_overlay", false)

	# Pathfinding
	var pathfinding_service = _get_pathfinding_service()
	if pathfinding_service:
		_set_toggle_state("pathfinding_overlay", pathfinding_service.is_debug_enabled())
	else:
		_set_toggle_state("pathfinding_overlay", false)

	# Verbose modes
	_set_toggle_state("verbose_all", Debug.verbose_npc or Debug.verbose_chunks or Debug.verbose_spawn)
	_set_toggle_state("verbose_npc", Debug.verbose_npc)


## ─── OVERLAY TOGGLES ─────────────────────────────────────────────────────────

func _on_toggle_chunk_overlay() -> void:
	if ChunkManager:
		ChunkManager.debug_toggle_overlay()
	_refresh_toggle_states()


func _on_toggle_ai_overlay() -> void:
	var ai_overlay = _get_ai_overlay()
	if ai_overlay and ai_overlay.has_method("toggle"):
		ai_overlay.toggle()
	_refresh_toggle_states()


func _on_toggle_quest_overlay() -> void:
	if UIManager:
		UIManager.toggle_quest_debug()
	_refresh_toggle_states()


func _on_toggle_pathfinding() -> void:
	var pathfinding_service = _get_pathfinding_service()
	if pathfinding_service:
		var new_state: bool = not pathfinding_service.is_debug_enabled()
		pathfinding_service.set_debug_enabled(new_state)
		Debug.info("Debug", "Pathfinding debug: %s" % ("ON" if new_state else "OFF"))
	_refresh_toggle_states()


## ─── SNAPSHOT ACTIONS ────────────────────────────────────────────────────────

func _on_chunk_state() -> void:
	if ChunkManager:
		ChunkManager.debug_print_state()


func _on_loot_state() -> void:
	var loot_mgr = get_node_or_null("/root/LootManager")
	if loot_mgr and loot_mgr.has_method("debug_print_state"):
		loot_mgr.debug_print_state()
	else:
		Debug.info("Debug", "LootManager not available")


func _on_enemy_summary() -> void:
	if NPCManager and NPCManager.has_method("print_state"):
		NPCManager.print_state()
	elif Game and Game.has_method("_debug_print_enemy_summary"):
		Game._debug_print_enemy_summary()
	else:
		Debug.info("Debug", "NPCManager not available")


func _on_chunk_perf() -> void:
	if ChunkManager:
		ChunkManager.debug_print_perf()


func _on_game_state() -> void:
	if Game and Game.has_method("debug_full_state"):
		Game.debug_full_state()


func _on_chest_persistence() -> void:
	if Persistence:
		Persistence.debug_print_chests()
	else:
		Debug.info("Debug", "Persistence not available")


func _on_debug_settings() -> void:
	Debug._print_debug_settings()


## ─── DIAGNOSTIC ACTIONS ──────────────────────────────────────────────────────

func _on_zone_naming() -> void:
	if ChunkManager:
		ChunkManager.debug_zone_naming_diagnostic()


func _on_zone_resolution() -> void:
	if ChunkManager:
		ChunkManager.debug_trace_zone_resolution()


func _on_test_pathfinding() -> void:
	var pathfinding_service = _get_pathfinding_service()
	if pathfinding_service:
		pathfinding_service.debug_test_path()
	else:
		Debug.info("Debug", "PathfindingService not available")


func _on_test_ends_when() -> void:
	if Game and Game.has_method("debug_test_ends_when_buff"):
		Game.debug_test_ends_when_buff()


## ─── LOG SETTINGS ────────────────────────────────────────────────────────────

func _on_cycle_log_level() -> void:
	Debug._cycle_log_level()


func _on_toggle_all_verbose() -> void:
	Debug._toggle_all_verbose()
	_refresh_toggle_states()


func _on_toggle_npc_verbose() -> void:
	Debug._toggle_npc_verbose()
	_refresh_toggle_states()


## ─── HELPERS ─────────────────────────────────────────────────────────────────

func _get_ai_overlay():
	if NPCManager and "ai_debug_overlay" in NPCManager:
		return NPCManager.ai_debug_overlay
	return null


func _get_pathfinding_service():
	return get_node_or_null("/root/PathfindingService")
