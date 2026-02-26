extends Control
## Attack Composer — A timeline/track editor tool for visually authoring
## melee attack animations with per-frame timing, weapon visibility,
## effects, speed echoes, and movement.

# ── Theme constants (matches Sprite Pipeline) ──────────────────────────
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_ACCENT_HOVER := Color("#7BB0FF")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

const SPRITES_BASE := "res://assets/sprites/final"
const WEAPONS_DIR := "res://assets/sprites/weapons"
const EFFECTS_DIR := "res://assets/sprites/effects"

# ── State ──────────────────────────────────────────────────────────────
var _current_composition: AttackCompositionData = null
var _frame_images: Dictionary = {}  # {direction_string: Array[Image]}
var _frame_textures: Dictionary = {}  # {direction_string: Array[ImageTexture]}
var _preview_direction := "down"
var _preview_frame_index: int = 0
var _selected_frame: int = -1
var _selected_frames: Array[int] = []
var _available_models: Array[String] = []
var _available_anims: Array[String] = []
var _current_model: String = ""
var _current_anim: String = ""
var _frame_size: Vector2i = Vector2i.ZERO

# ── Playback state ─────────────────────────────────────────────────────
var _playing := false
var _playback_ms := 0.0
var _playback_speed := 1.0

# ── Anchor painting state ─────────────────────────────────────────────
var _anchor_draw_enabled: bool = false
var _anchor_onion_skin_enabled: bool = false
var _anchor_images_dirty: bool = false

# ── Undo state ────────────────────────────────────────────────────────
var _undo_stack: Array = []  # Array of Dictionary {composition, images}
const MAX_UNDO := 50

# ── UI references ──────────────────────────────────────────────────────
var _status_label: Label
var _left_scroll_content: VBoxContainer
var _right_vbox: VBoxContainer
var _timeline_panel: TimelinePanel
var _model_dropdown: OptionButton
var _anim_dropdown: OptionButton
var _load_info_label: Label
var _composition_dropdown: OptionButton
var _load_composition_btn: Button
var _frame_props_container: VBoxContainer
var _duration_spinbox: SpinBox
var _fps_label: Label
var _total_duration_label: Label
var _weapon_check: CheckButton
var _weapon_z_front_check: CheckButton
var _weapon_dropdown: OptionButton
var _effect_dropdown: OptionButton
var _effect_anchor_dropdown: OptionButton
var _effect_offset_x: SpinBox
var _effect_offset_y: SpinBox
var _echo_check: CheckButton
var _echo_settings_container: VBoxContainer
var _echo_count_spin: SpinBox
var _echo_opacity_start_slider: HSlider
var _echo_opacity_end_slider: HSlider
var _echo_spacing_spin: SpinBox
var _seq_props_container: VBoxContainer
var _movement_type_dropdown: OptionButton
var _movement_distance_spin: SpinBox
var _movement_start_spin: SpinBox
var _movement_end_spin: SpinBox
var _damage_frame_spin: SpinBox
var _preview_viewport: SubViewport
var _preview_sprite: Sprite2D
var _preview_checker: ColorRect
var _weapon_sprite: Sprite2D
var _weapon_set: Dictionary = {}
var _echo_sprites: Array[Sprite2D] = []
var _direction_buttons: Array[Button] = []
var _frame_props_header: Button
var _seq_props_header: Button
var _undo_btn: Button
var _draw_anchors_check: CheckButton
var _onion_skin_check: CheckButton
var _onion_skin_container: VBoxContainer
var _save_spritesheets_btn: Button
var _crosshair_sprite: Sprite2D
var _onion_weapon_sprite: Sprite2D
var _viewport_container_ref: SubViewportContainer
var _anchor_label: Label
var _weapon_debug: String = ""
var _frame_label: Label
var _frame_nav_prev: Button
var _frame_nav_next: Button
var _play_btn: Button
var _stop_btn: Button
var _time_label: Label
var _speed_slider: HSlider

const DIRECTIONS: Array[String] = ["down", "up", "right"]


func _ready() -> void:
	_build_ui()
	_build_loading_section()
	_build_frame_props_section()
	_scan_animations()
	_refresh_composition_dropdown()
	_set_status("Ready. Select a model and animation to begin.")


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var key := event as InputEventKey

	match key.keycode:
		KEY_SPACE:
			_on_play_toggle()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_on_step_back()
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_on_step_forward()
			get_viewport().set_input_as_handled()
		KEY_HOME:
			_on_stop()
			get_viewport().set_input_as_handled()
		KEY_END:
			if _current_composition and not _current_composition.frames.is_empty():
				_playing = false
				_play_btn.text = "\u25b6"
				_preview_frame_index = _current_composition.frames.size() - 1
				_selected_frame = _preview_frame_index
				_selected_frames = [_selected_frame]
				_timeline_panel.selected_frame = _selected_frame
				_timeline_panel.selected_frames = _selected_frames
				_timeline_panel.queue_redraw()
				_update_preview_frame()
				_update_frame_props_ui()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			_delete_selected_frame()
			get_viewport().set_input_as_handled()
		KEY_Z:
			if key.ctrl_pressed:
				_undo()
				get_viewport().set_input_as_handled()
		KEY_0:
			if key.ctrl_pressed:
				# Reset zoom
				_timeline_panel.pixels_per_ms = 2.0
				_timeline_panel.queue_redraw()
				get_viewport().set_input_as_handled()


func _delete_selected_frame() -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	if _current_composition.frames.size() <= 1:
		_set_status("Cannot delete the last frame.")
		return

	_push_undo()
	var deleted_idx := _selected_frame
	_current_composition.frames.remove_at(deleted_idx)

	# Update sequence-level indices
	if _current_composition.damage_frame == deleted_idx:
		_current_composition.damage_frame = -1
	elif _current_composition.damage_frame > deleted_idx:
		_current_composition.damage_frame -= 1

	if _current_composition.movement_start_frame > deleted_idx:
		_current_composition.movement_start_frame -= 1
	elif _current_composition.movement_start_frame == deleted_idx:
		_current_composition.movement_start_frame = -1

	if _current_composition.movement_end_frame > deleted_idx:
		_current_composition.movement_end_frame -= 1
	elif _current_composition.movement_end_frame == deleted_idx:
		_current_composition.movement_end_frame = -1

	# Rebuild thumbnails
	if _frame_textures.has("down"):
		var down_textures: Array = _frame_textures["down"]
		if deleted_idx < down_textures.size():
			down_textures.remove_at(deleted_idx)
		_timeline_panel.frame_thumbnails.clear()
		for tex in down_textures:
			_timeline_panel.frame_thumbnails.append(tex)

	# Also remove from all direction frame arrays
	for direction in DIRECTIONS:
		if _frame_images.has(direction):
			var imgs: Array = _frame_images[direction]
			if deleted_idx < imgs.size():
				imgs.remove_at(deleted_idx)
		if _frame_textures.has(direction):
			var texs: Array = _frame_textures[direction]
			if deleted_idx < texs.size():
				texs.remove_at(deleted_idx)

	# Adjust selection
	_selected_frame = mini(_selected_frame, _current_composition.frames.size() - 1)
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()
	_set_status("Deleted frame %d. %d frames remaining." % [deleted_idx, _current_composition.frames.size()])


# ── Undo ──────────────────────────────────────────────────────────────

func _push_undo() -> void:
	if _current_composition == null:
		return
	# Deep-copy each frame individually since Resource.duplicate doesn't deep-copy arrays of resources
	var comp_snapshot := AttackCompositionData.new()
	comp_snapshot.composition_id = _current_composition.composition_id
	comp_snapshot.display_name = _current_composition.display_name
	comp_snapshot.animation_name = _current_composition.animation_name
	comp_snapshot.movement_type = _current_composition.movement_type
	comp_snapshot.movement_distance = _current_composition.movement_distance
	comp_snapshot.movement_start_frame = _current_composition.movement_start_frame
	comp_snapshot.movement_end_frame = _current_composition.movement_end_frame
	comp_snapshot.damage_frame = _current_composition.damage_frame
	for frame in _current_composition.frames:
		comp_snapshot.frames.append(frame.duplicate())

	var entry: Dictionary = {"composition": comp_snapshot}

	# When anchor drawing is active, also snapshot all frame images
	if _anchor_draw_enabled and not _frame_images.is_empty():
		var images_snapshot: Dictionary = {}
		for dir_name in _frame_images:
			var originals: Array = _frame_images[dir_name]
			var copies: Array[Image] = []
			for img: Image in originals:
				copies.append(img.duplicate())
			images_snapshot[dir_name] = copies
		entry["images"] = images_snapshot

	_undo_stack.append(entry)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.remove_at(0)
	_update_undo_button()


func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	var entry: Dictionary = _undo_stack.pop_back()
	var snapshot: AttackCompositionData = entry["composition"]
	_current_composition.composition_id = snapshot.composition_id
	_current_composition.display_name = snapshot.display_name
	_current_composition.animation_name = snapshot.animation_name
	_current_composition.movement_type = snapshot.movement_type
	_current_composition.movement_distance = snapshot.movement_distance
	_current_composition.movement_start_frame = snapshot.movement_start_frame
	_current_composition.movement_end_frame = snapshot.movement_end_frame
	_current_composition.damage_frame = snapshot.damage_frame
	_current_composition.frames.clear()
	for frame in snapshot.frames:
		_current_composition.frames.append(frame)

	# Restore frame images if snapshot includes them
	if entry.has("images"):
		var images_snapshot: Dictionary = entry["images"]
		for dir_name in images_snapshot:
			_frame_images[dir_name] = images_snapshot[dir_name]
			# Recreate textures from restored images
			var new_textures: Array[ImageTexture] = []
			for img: Image in images_snapshot[dir_name]:
				new_textures.append(ImageTexture.create_from_image(img))
			_frame_textures[dir_name] = new_textures

	# Adjust selection
	_selected_frame = clampi(_selected_frame, 0, _current_composition.frames.size() - 1)
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame
	_timeline_panel.composition = _current_composition
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	# Rebuild thumbnails
	if _frame_textures.has("down"):
		_timeline_panel.frame_thumbnails.clear()
		var down_textures: Array = _frame_textures["down"]
		for i in _current_composition.frames.size():
			if i < down_textures.size():
				_timeline_panel.frame_thumbnails.append(down_textures[i])
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()
	_update_undo_button()
	_set_status("Undo. (%d remaining)" % _undo_stack.size())


func _update_undo_button() -> void:
	if _undo_btn:
		_undo_btn.disabled = _undo_stack.is_empty()
		_undo_btn.tooltip_text = "Undo (Ctrl+Z) — %d steps" % _undo_stack.size()


# ── UI Construction ────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Root HBox
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# ── Left Panel ─────────────────────────────────────────────────────
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 300
	left_panel.size_flags_horizontal = SIZE_FILL
	var left_sb := StyleBoxFlat.new()
	left_sb.bg_color = C_PANEL
	left_sb.border_width_right = 1
	left_sb.border_color = C_BORDER
	left_panel.add_theme_stylebox_override("panel", left_sb)
	root_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 0)
	left_panel.add_child(left_vbox)

	# Title
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 16)
	title_margin.add_theme_constant_override("margin_right", 16)
	title_margin.add_theme_constant_override("margin_top", 12)
	title_margin.add_theme_constant_override("margin_bottom", 12)
	left_vbox.add_child(title_margin)

	var title := Label.new()
	title.text = "Attack Composer"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", C_TEXT)
	title_margin.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	left_vbox.add_child(sep)

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.add_theme_constant_override("margin_left", 12)
	scroll_margin.add_theme_constant_override("margin_right", 12)
	scroll_margin.add_theme_constant_override("margin_top", 8)
	scroll_margin.add_theme_constant_override("margin_bottom", 8)
	scroll_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(scroll_margin)

	_left_scroll_content = VBoxContainer.new()
	_left_scroll_content.add_theme_constant_override("separation", 8)
	_left_scroll_content.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll_margin.add_child(_left_scroll_content)

	# Bottom separator
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _make_separator_style())
	left_vbox.add_child(sep2)

	# Status bar
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 12)
	status_margin.add_theme_constant_override("margin_right", 12)
	status_margin.add_theme_constant_override("margin_top", 6)
	status_margin.add_theme_constant_override("margin_bottom", 6)
	left_vbox.add_child(status_margin)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", FONT_HINT)
	_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_margin.add_child(_status_label)

	# ── Right Panel ────────────────────────────────────────────────────
	_right_vbox = VBoxContainer.new()
	_right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_right_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	_right_vbox.add_theme_constant_override("separation", 0)
	root_hbox.add_child(_right_vbox)

	# Preview area (top ~60%)
	var preview_vbox := VBoxContainer.new()
	preview_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	preview_vbox.size_flags_stretch_ratio = 0.6
	preview_vbox.add_theme_constant_override("separation", 0)
	_right_vbox.add_child(preview_vbox)

	# SubViewport for frame preview
	var viewport_container := SubViewportContainer.new()
	viewport_container.size_flags_horizontal = SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.stretch_shrink = 1
	viewport_container.mouse_filter = MOUSE_FILTER_STOP
	viewport_container.gui_input.connect(_on_preview_viewport_input)
	preview_vbox.add_child(viewport_container)
	_viewport_container_ref = viewport_container

	_preview_viewport = SubViewport.new()
	_preview_viewport.transparent_bg = false
	_preview_viewport.size = Vector2i(128, 128)
	_preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.size_changed.connect(_on_preview_viewport_resized)
	viewport_container.add_child(_preview_viewport)

	# Checkerboard background — fills the entire viewport (resized manually)
	_preview_checker = ColorRect.new()
	_preview_checker.color = C_SECTION
	_preview_checker.size = Vector2(_preview_viewport.size)
	_preview_viewport.add_child(_preview_checker)

	# The sprite to display the current frame (centered and scaled dynamically)
	_preview_sprite = Sprite2D.new()
	_preview_sprite.centered = true
	_preview_viewport.add_child(_preview_sprite)

	# Weapon sprite (layered above body)
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.centered = true
	_weapon_sprite.visible = false
	_weapon_sprite.z_index = 1
	_preview_viewport.add_child(_weapon_sprite)

	# Onion weapon sprite — ghost of previous frame's weapon at 30% opacity
	_onion_weapon_sprite = Sprite2D.new()
	_onion_weapon_sprite.centered = true
	_onion_weapon_sprite.visible = false
	_onion_weapon_sprite.z_index = 1
	_onion_weapon_sprite.modulate = Color(1, 1, 1, 0.3)
	_preview_viewport.add_child(_onion_weapon_sprite)

	# Crosshair overlay — drawn on top of everything to show anchor positions
	_crosshair_sprite = Sprite2D.new()
	_crosshair_sprite.centered = true
	_crosshair_sprite.visible = false
	_crosshair_sprite.z_index = 3
	_preview_viewport.add_child(_crosshair_sprite)

	# Load default weapon set — prefer real weapon assets, fall back to placeholder
	var scanned_weapons := _scan_weapon_folders()
	if not scanned_weapons.is_empty():
		_weapon_set = _load_weapon_from_folder(scanned_weapons[0])
	if _weapon_set.is_empty():
		_weapon_set = PlaceholderWeaponSprites.create_sword_set()

	# Controls bar below preview
	var controls_bar := PanelContainer.new()
	var controls_sb := StyleBoxFlat.new()
	controls_sb.bg_color = C_PANEL
	controls_sb.border_width_bottom = 1
	controls_sb.border_color = C_BORDER
	controls_bar.add_theme_stylebox_override("panel", controls_sb)
	preview_vbox.add_child(controls_bar)

	var controls_hbox := HBoxContainer.new()
	controls_hbox.add_theme_constant_override("separation", 4)
	controls_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	controls_bar.add_child(controls_hbox)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 8)
	controls_margin.add_theme_constant_override("margin_right", 8)
	controls_margin.add_theme_constant_override("margin_top", 4)
	controls_margin.add_theme_constant_override("margin_bottom", 4)
	controls_bar.add_child(controls_margin)

	var controls_inner := HBoxContainer.new()
	controls_inner.add_theme_constant_override("separation", 6)
	controls_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	controls_margin.add_child(controls_inner)

	# Direction buttons
	for dir_name in DIRECTIONS:
		var short: String = dir_name.substr(0, 1).to_upper()
		var btn := _make_button(short, _on_direction_pressed.bind(dir_name))
		btn.custom_minimum_size.x = 32
		_direction_buttons.append(btn)
		controls_inner.add_child(btn)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 16
	controls_inner.add_child(spacer)

	# Frame navigation
	_frame_nav_prev = _make_button("\u25c0", _on_frame_prev)
	_frame_nav_prev.custom_minimum_size.x = 32
	controls_inner.add_child(_frame_nav_prev)

	_frame_label = Label.new()
	_frame_label.text = "Frame 0 / 0"
	_frame_label.add_theme_font_size_override("font_size", FONT_LABEL)
	_frame_label.add_theme_color_override("font_color", C_TEXT)
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_frame_label.custom_minimum_size.x = 80
	controls_inner.add_child(_frame_label)

	_frame_nav_next = _make_button("\u25b6", _on_frame_next)
	_frame_nav_next.custom_minimum_size.x = 32
	controls_inner.add_child(_frame_nav_next)

	# Spacer before undo
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 12
	controls_inner.add_child(spacer2)

	# Undo button
	_undo_btn = _make_button("\u21b6", _undo)
	_undo_btn.custom_minimum_size.x = 32
	_undo_btn.tooltip_text = "Undo (Ctrl+Z)"
	_undo_btn.disabled = true
	controls_inner.add_child(_undo_btn)

	# Anchor detection indicator
	_anchor_label = Label.new()
	_anchor_label.add_theme_font_size_override("font_size", FONT_HINT)
	_anchor_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_anchor_label.text = ""
	controls_inner.add_child(_anchor_label)

	# Transport bar
	_build_transport_bar(_right_vbox)

	# Timeline panel (bottom ~40%)
	var timeline_container := PanelContainer.new()
	timeline_container.size_flags_vertical = SIZE_EXPAND_FILL
	timeline_container.size_flags_stretch_ratio = 0.4
	var timeline_sb := StyleBoxFlat.new()
	timeline_sb.bg_color = C_BG
	timeline_container.add_theme_stylebox_override("panel", timeline_sb)
	_right_vbox.add_child(timeline_container)

	_timeline_panel = TimelinePanel.new()
	_timeline_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_timeline_panel.size_flags_vertical = SIZE_EXPAND_FILL
	_timeline_panel.frame_selected.connect(_on_timeline_frame_selected)
	_timeline_panel.frames_selected.connect(_on_timeline_frames_selected)
	_timeline_panel.frame_duration_changed.connect(_on_timeline_duration_changed)
	_timeline_panel.playhead_moved.connect(_on_timeline_playhead_moved)
	_timeline_panel.before_mutation.connect(_push_undo)
	timeline_container.add_child(_timeline_panel)


# ── Helpers ────────────────────────────────────────────────────────────

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _make_separator_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BORDER
	sb.content_margin_top = 0.5
	sb.content_margin_bottom = 0.5
	return sb


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SECTION)
	label.add_theme_color_override("font_color", C_ACCENT)
	return label


func _make_label(text: String, color: Color = C_TEXT_SEC) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, callable: Callable, accent: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_LABEL)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ACCENT if accent else C_SURFACE
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = C_ACCENT_HOVER if accent else C_SURFACE_HOVER
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.pressed.connect(callable)
	return btn


## Creates a collapsible section with a toggle header button and content VBox.
## Returns an Array: [wrapper: VBoxContainer, content: VBoxContainer]
## The wrapper can be shown/hidden to control the entire section's visibility.
func _make_collapsible_section(title: String, parent: Control, collapsed: bool = true) -> Array:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	parent.add_child(wrapper)

	var header := Button.new()
	header.text = ("%s  %s" % ["\u25b6" if collapsed else "\u25bc", title])
	header.add_theme_font_size_override("font_size", FONT_SECTION)
	header.add_theme_color_override("font_color", C_ACCENT)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = Color.TRANSPARENT
	header_sb.content_margin_left = 0
	header_sb.content_margin_right = 0
	header_sb.content_margin_top = 2
	header_sb.content_margin_bottom = 2
	header.add_theme_stylebox_override("normal", header_sb)
	var header_hover := header_sb.duplicate()
	header_hover.bg_color = C_SURFACE
	header.add_theme_stylebox_override("hover", header_hover)
	header.add_theme_stylebox_override("pressed", header_sb)
	wrapper.add_child(header)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.visible = not collapsed
	wrapper.add_child(content)

	header.pressed.connect(func():
		content.visible = not content.visible
		var arrow := "\u25bc" if content.visible else "\u25b6"
		header.text = "%s  %s" % [arrow, title]
	)
	return [wrapper, content]


func _make_option_button() -> OptionButton:
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", FONT_LABEL)
	opt.add_theme_color_override("font_color", C_TEXT)
	opt.size_flags_horizontal = SIZE_EXPAND_FILL
	return opt


# ── Transport ──────────────────────────────────────────────────────────

func _build_transport_bar(parent: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = C_PANEL
	bar_sb.border_width_top = 1
	bar_sb.border_width_bottom = 1
	bar_sb.border_color = C_BORDER
	bar.add_theme_stylebox_override("panel", bar_sb)
	parent.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	bar.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)

	# Play/Pause
	_play_btn = _make_button("\u25b6", _on_play_toggle)
	_play_btn.custom_minimum_size.x = 36
	hbox.add_child(_play_btn)

	# Stop
	_stop_btn = _make_button("\u25a0", _on_stop)
	_stop_btn.custom_minimum_size.x = 36
	hbox.add_child(_stop_btn)

	# Step back
	var step_back := _make_button("\u25c0\u25c0", _on_step_back)
	step_back.custom_minimum_size.x = 36
	hbox.add_child(step_back)

	# Step forward
	var step_fwd := _make_button("\u25b6\u25b6", _on_step_forward)
	step_fwd.custom_minimum_size.x = 36
	hbox.add_child(step_fwd)

	# Time label
	_time_label = Label.new()
	_time_label.text = "0:000 / 0:000"
	_time_label.add_theme_font_size_override("font_size", FONT_VALUE)
	_time_label.add_theme_color_override("font_color", C_TEXT)
	_time_label.custom_minimum_size.x = 100
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(_time_label)

	# Speed label
	var speed_label := _make_label("Speed:", C_TEXT_SEC)
	hbox.add_child(speed_label)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.25
	_speed_slider.max_value = 2.0
	_speed_slider.step = 0.25
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size.x = 80
	_speed_slider.value_changed.connect(func(v: float): _playback_speed = v)
	hbox.add_child(_speed_slider)

	var speed_val := _make_label("1.0x", C_TEXT_SEC)
	_speed_slider.value_changed.connect(func(v: float): speed_val.text = "%.1fx" % v)
	hbox.add_child(speed_val)


func _process(delta: float) -> void:
	if not _playing or _current_composition == null:
		return
	_playback_ms += delta * 1000.0 * _playback_speed
	var total := _current_composition.get_total_duration_sec() * 1000.0
	if total <= 0:
		return
	if _playback_ms >= total:
		_playback_ms = fmod(_playback_ms, total)  # Loop
	_update_playhead()


func _update_playhead() -> void:
	if _current_composition == null:
		return
	# Determine which frame the playhead is in
	var cumulative := 0.0
	for i in _current_composition.frames.size():
		cumulative += _current_composition.frames[i].duration_ms
		if _playback_ms < cumulative:
			if _preview_frame_index != i:
				_preview_frame_index = i
				_update_preview_frame()
			break

	# Update timeline playhead
	_timeline_panel.playhead_ms = _playback_ms
	_timeline_panel.queue_redraw()

	# Update time label
	var total_ms := _current_composition.get_total_duration_sec() * 1000.0
	_time_label.text = "%d:%03d / %d:%03d" % [
		int(_playback_ms / 1000.0), int(fmod(_playback_ms, 1000.0)),
		int(total_ms / 1000.0), int(fmod(total_ms, 1000.0))
	]


func _on_play_toggle() -> void:
	_playing = not _playing
	_play_btn.text = "\u23f8" if _playing else "\u25b6"


func _on_stop() -> void:
	_playing = false
	_playback_ms = 0.0
	_play_btn.text = "\u25b6"
	_preview_frame_index = 0
	_selected_frame = 0
	_selected_frames = [0]
	_timeline_panel.playhead_ms = 0.0
	_timeline_panel.selected_frame = 0
	_timeline_panel.selected_frames = [0]
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()
	_time_label.text = "0:000 / 0:000"


func _on_step_back() -> void:
	_playing = false
	_play_btn.text = "\u25b6"
	_on_frame_prev()


func _on_step_forward() -> void:
	_playing = false
	_play_btn.text = "\u25b6"
	_on_frame_next()


# ── Loading Section ────────────────────────────────────────────────────

func _build_loading_section() -> void:
	var parts: Array = _make_collapsible_section("Spritesheet", _left_scroll_content, false)
	var section: VBoxContainer = parts[1]

	# Animation dropdown (folder names like Slash, Blocking, etc.)
	section.add_child(_make_label("Animation"))
	_anim_dropdown = _make_option_button()
	_anim_dropdown.item_selected.connect(_on_anim_selected)
	section.add_child(_anim_dropdown)

	# Model dropdown (model prefixes within animation folder)
	section.add_child(_make_label("Model"))
	_model_dropdown = _make_option_button()
	section.add_child(_model_dropdown)

	# Load button
	section.add_child(_make_button("Load Spritesheet", _on_load_pressed, true))

	# Info label
	_load_info_label = _make_label("", C_TEXT_DIM)
	_load_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_load_info_label)

	# Load saved composition
	section.add_child(_make_label("Saved Compositions"))
	_composition_dropdown = _make_option_button()
	section.add_child(_composition_dropdown)
	_load_composition_btn = _make_button("Load Composition", _on_load_composition_pressed, false)
	section.add_child(_load_composition_btn)


func _build_frame_props_section() -> void:
	# ── Frame Properties (collapsed by default, shown when a frame is selected) ──
	var frame_parts: Array = _make_collapsible_section("Frame Properties", _left_scroll_content)
	var frame_wrapper: VBoxContainer = frame_parts[0]
	_frame_props_container = frame_parts[1]
	_frame_props_header = frame_wrapper.get_child(0)
	frame_wrapper.visible = false  # Hidden until data is loaded

	# Duration
	_frame_props_container.add_child(_make_label("Duration (ms)"))
	_duration_spinbox = SpinBox.new()
	_duration_spinbox.min_value = 8
	_duration_spinbox.max_value = 2000
	_duration_spinbox.step = 8
	_duration_spinbox.value = 66
	_duration_spinbox.size_flags_horizontal = SIZE_EXPAND_FILL
	_duration_spinbox.value_changed.connect(_on_duration_changed)
	_frame_props_container.add_child(_duration_spinbox)

	_fps_label = _make_label("~ 15.2 fps", C_TEXT_DIM)
	_frame_props_container.add_child(_fps_label)

	# Delete frame button
	_frame_props_container.add_child(_make_button("Delete Frame (Del)", _delete_selected_frame))

	# Weapon visible
	_weapon_check = CheckButton.new()
	_weapon_check.text = "Weapon Visible"
	_weapon_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_weapon_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_weapon_check.toggled.connect(_on_weapon_toggled)
	_frame_props_container.add_child(_weapon_check)

	# Weapon z-index (in front / behind body)
	_weapon_z_front_check = CheckButton.new()
	_weapon_z_front_check.text = "Weapon In Front"
	_weapon_z_front_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_weapon_z_front_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_weapon_z_front_check.toggled.connect(_on_weapon_z_front_toggled)
	_frame_props_container.add_child(_weapon_z_front_check)

	# Weapon selector dropdown
	_frame_props_container.add_child(_make_label("Weapon"))
	_weapon_dropdown = _make_option_button()
	var scanned_w := _scan_weapon_folders()
	for wid in scanned_w:
		_weapon_dropdown.add_item("[Asset] " + wid)
	_weapon_dropdown.add_item("[Placeholder] sword")
	# Select the entry matching the weapon we loaded at startup
	if not scanned_w.is_empty():
		_weapon_dropdown.select(0)
	else:
		_weapon_dropdown.select(_weapon_dropdown.item_count - 1)
	_weapon_dropdown.item_selected.connect(_on_weapon_dropdown_selected)
	_frame_props_container.add_child(_weapon_dropdown)

	# Draw Anchors toggle
	_draw_anchors_check = CheckButton.new()
	_draw_anchors_check.text = "Draw Anchors"
	_draw_anchors_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_draw_anchors_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_draw_anchors_check.toggled.connect(_on_draw_anchors_toggled)
	_frame_props_container.add_child(_draw_anchors_check)

	# Onion skin container (shown when Draw Anchors is on)
	_onion_skin_container = VBoxContainer.new()
	_onion_skin_container.add_theme_constant_override("separation", 4)
	_onion_skin_container.visible = false
	_frame_props_container.add_child(_onion_skin_container)

	_onion_skin_check = CheckButton.new()
	_onion_skin_check.text = "Weapon Onion Skin"
	_onion_skin_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_onion_skin_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_onion_skin_check.toggled.connect(_on_onion_skin_toggled)
	_onion_skin_container.add_child(_onion_skin_check)

	# Color legend
	var anchor_legend := HBoxContainer.new()
	anchor_legend.add_theme_constant_override("separation", 12)
	_onion_skin_container.add_child(anchor_legend)
	var grip_legend := Label.new()
	grip_legend.text = "\u25a0 Grip (L-click)"
	grip_legend.add_theme_color_override("font_color", Color("#FF00AA"))
	grip_legend.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_legend.add_child(grip_legend)
	var dir_legend := Label.new()
	dir_legend.text = "\u25a0 Dir (R-click)"
	dir_legend.add_theme_color_override("font_color", Color("#00FFFF"))
	dir_legend.add_theme_font_size_override("font_size", FONT_HINT)
	anchor_legend.add_child(dir_legend)

	# Effect
	_frame_props_container.add_child(_make_label("Effect"))
	_effect_dropdown = _make_option_button()
	_effect_dropdown.add_item("(none)", 0)
	# Real effect assets first
	var scanned_effects := _scan_effect_folders()
	for eid in scanned_effects:
		_effect_dropdown.add_item("[Asset] " + eid)
	# Placeholder effects as fallback
	for eid in ["slash_arc", "slash_arc_wide", "thrust_line", "impact_spark",
			"bowstring_snap", "cast_circle", "spell_burst", "buff_burst", "howl_aura"]:
		_effect_dropdown.add_item("[Placeholder] " + eid)
	_effect_dropdown.item_selected.connect(_on_effect_selected)
	_frame_props_container.add_child(_effect_dropdown)

	_frame_props_container.add_child(_make_label("Effect Anchor"))
	_effect_anchor_dropdown = _make_option_button()
	_effect_anchor_dropdown.add_item("weapon_tip")
	_effect_anchor_dropdown.add_item("center")
	_effect_anchor_dropdown.add_item("feet")
	_effect_anchor_dropdown.item_selected.connect(_on_effect_anchor_selected)
	_frame_props_container.add_child(_effect_anchor_dropdown)

	var offset_hbox := HBoxContainer.new()
	offset_hbox.add_theme_constant_override("separation", 4)
	_frame_props_container.add_child(offset_hbox)
	offset_hbox.add_child(_make_label("Offset X"))
	_effect_offset_x = SpinBox.new()
	_effect_offset_x.min_value = -64
	_effect_offset_x.max_value = 64
	_effect_offset_x.step = 1
	_effect_offset_x.size_flags_horizontal = SIZE_EXPAND_FILL
	_effect_offset_x.value_changed.connect(_on_effect_offset_changed)
	offset_hbox.add_child(_effect_offset_x)
	offset_hbox.add_child(_make_label("Y"))
	_effect_offset_y = SpinBox.new()
	_effect_offset_y.min_value = -64
	_effect_offset_y.max_value = 64
	_effect_offset_y.step = 1
	_effect_offset_y.size_flags_horizontal = SIZE_EXPAND_FILL
	_effect_offset_y.value_changed.connect(_on_effect_offset_changed)
	offset_hbox.add_child(_effect_offset_y)

	# Echo
	_echo_check = CheckButton.new()
	_echo_check.text = "Speed Echo"
	_echo_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_echo_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_echo_check.toggled.connect(_on_echo_toggled)
	_frame_props_container.add_child(_echo_check)

	_echo_settings_container = VBoxContainer.new()
	_echo_settings_container.add_theme_constant_override("separation", 4)
	_echo_settings_container.visible = false
	_frame_props_container.add_child(_echo_settings_container)

	_echo_settings_container.add_child(_make_label("Echo Count"))
	_echo_count_spin = SpinBox.new()
	_echo_count_spin.min_value = 1
	_echo_count_spin.max_value = 5
	_echo_count_spin.value = 3
	_echo_count_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_echo_count_spin.value_changed.connect(_on_echo_setting_changed)
	_echo_settings_container.add_child(_echo_count_spin)

	_echo_settings_container.add_child(_make_label("Opacity Start"))
	_echo_opacity_start_slider = HSlider.new()
	_echo_opacity_start_slider.min_value = 0.0
	_echo_opacity_start_slider.max_value = 1.0
	_echo_opacity_start_slider.step = 0.05
	_echo_opacity_start_slider.value = 0.5
	_echo_opacity_start_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_echo_opacity_start_slider.value_changed.connect(_on_echo_setting_changed)
	_echo_settings_container.add_child(_echo_opacity_start_slider)

	_echo_settings_container.add_child(_make_label("Opacity End"))
	_echo_opacity_end_slider = HSlider.new()
	_echo_opacity_end_slider.min_value = 0.0
	_echo_opacity_end_slider.max_value = 1.0
	_echo_opacity_end_slider.step = 0.05
	_echo_opacity_end_slider.value = 0.1
	_echo_opacity_end_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_echo_opacity_end_slider.value_changed.connect(_on_echo_setting_changed)
	_echo_settings_container.add_child(_echo_opacity_end_slider)

	_echo_settings_container.add_child(_make_label("Echo Spacing (px)"))
	_echo_spacing_spin = SpinBox.new()
	_echo_spacing_spin.min_value = 2
	_echo_spacing_spin.max_value = 24
	_echo_spacing_spin.value = 8
	_echo_spacing_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_echo_spacing_spin.value_changed.connect(_on_echo_setting_changed)
	_echo_settings_container.add_child(_echo_spacing_spin)

	# Total duration
	_total_duration_label = _make_label("Total: 0.000s", C_TEXT)
	_frame_props_container.add_child(_total_duration_label)

	# ── Sequence Properties (collapsed by default) ──
	var seq_parts: Array = _make_collapsible_section("Sequence Properties", _left_scroll_content)
	var seq_wrapper: VBoxContainer = seq_parts[0]
	_seq_props_container = seq_parts[1]
	_seq_props_header = seq_wrapper.get_child(0)
	seq_wrapper.visible = false  # Hidden until data is loaded

	_seq_props_container.add_child(_make_label("Movement Type"))
	_movement_type_dropdown = _make_option_button()
	_movement_type_dropdown.add_item("none")
	_movement_type_dropdown.add_item("lunge")
	_movement_type_dropdown.add_item("dash")
	_movement_type_dropdown.item_selected.connect(_on_movement_type_selected)
	_seq_props_container.add_child(_movement_type_dropdown)

	_seq_props_container.add_child(_make_label("Movement Distance (px)"))
	_movement_distance_spin = SpinBox.new()
	_movement_distance_spin.min_value = 0
	_movement_distance_spin.max_value = 100
	_movement_distance_spin.value = 20
	_movement_distance_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_movement_distance_spin.value_changed.connect(_on_seq_prop_changed)
	_seq_props_container.add_child(_movement_distance_spin)

	_seq_props_container.add_child(_make_label("Movement Start Frame"))
	_movement_start_spin = SpinBox.new()
	_movement_start_spin.min_value = -1
	_movement_start_spin.max_value = 99
	_movement_start_spin.value = -1
	_movement_start_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_movement_start_spin.value_changed.connect(_on_seq_prop_changed)
	_seq_props_container.add_child(_movement_start_spin)

	_seq_props_container.add_child(_make_label("Movement End Frame"))
	_movement_end_spin = SpinBox.new()
	_movement_end_spin.min_value = -1
	_movement_end_spin.max_value = 99
	_movement_end_spin.value = -1
	_movement_end_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_movement_end_spin.value_changed.connect(_on_seq_prop_changed)
	_seq_props_container.add_child(_movement_end_spin)

	_seq_props_container.add_child(_make_label("Damage Frame"))
	_damage_frame_spin = SpinBox.new()
	_damage_frame_spin.min_value = -1
	_damage_frame_spin.max_value = 99
	_damage_frame_spin.value = -1
	_damage_frame_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_damage_frame_spin.value_changed.connect(_on_damage_frame_changed)
	_seq_props_container.add_child(_damage_frame_spin)

	# ── Save & Export (collapsed by default) ──
	var save_parts: Array = _make_collapsible_section("Save & Export", _left_scroll_content)
	var save_section: VBoxContainer = save_parts[1]
	_save_spritesheets_btn = _make_button("Save Spritesheets", _on_save_spritesheets)
	_save_spritesheets_btn.disabled = true
	_save_spritesheets_btn.tooltip_text = "Save modified spritesheets (anchors baked into PNGs)"
	save_section.add_child(_save_spritesheets_btn)
	save_section.add_child(_make_button("Generate Runtime Data", _on_generate_runtime))
	save_section.add_child(_make_button("Save Composition", _on_save_composition))
	save_section.add_child(_make_button("Save Runtime Data", _on_save_runtime))
	save_section.add_child(_make_button("Save Both", _on_save_both, true))

	# ── Load Composition (collapsed by default) ──
	var load_parts: Array = _make_collapsible_section("Load Composition", _left_scroll_content)
	var load_section: VBoxContainer = load_parts[1]
	load_section.add_child(_make_button("Refresh", _refresh_composition_dropdown))


func _scan_animations() -> void:
	_anim_dropdown.clear()
	_available_anims.clear()

	var dir := DirAccess.open(SPRITES_BASE)
	if dir == null:
		_set_status("Sprites folder not found: %s" % SPRITES_BASE)
		return

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			_available_anims.append(folder_name)
		folder_name = dir.get_next()
	dir.list_dir_end()

	_available_anims.sort()
	for anim_name in _available_anims:
		_anim_dropdown.add_item(anim_name)

	if not _available_anims.is_empty():
		_on_anim_selected(0)
	else:
		_set_status("No animation folders found in %s" % SPRITES_BASE)


func _on_anim_selected(index: int) -> void:
	if index < 0 or index >= _available_anims.size():
		return

	_model_dropdown.clear()
	_available_models.clear()

	var anim_folder: String = _available_anims[index]
	var folder_path := "%s/%s" % [SPRITES_BASE, anim_folder]
	var dir := DirAccess.open(folder_path)
	if dir == null:
		return

	# Parse filenames to find model prefixes: {model}_{direction}.png
	var model_set := {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png") and not file_name.ends_with("_normal.png") and not file_name.ends_with("_shadow.png"):
			# Strip .png and try to extract model prefix
			var base := file_name.get_basename()
			for direction in DIRECTIONS:
				var suffix := "_%s" % direction
				if base.ends_with(suffix):
					var model := base.substr(0, base.length() - suffix.length())
					model_set[model] = true
					break
		file_name = dir.get_next()
	dir.list_dir_end()

	for model in model_set.keys():
		_available_models.append(model)
	_available_models.sort()

	for model in _available_models:
		_model_dropdown.add_item(model)


func _on_load_pressed() -> void:
	var anim_idx := _anim_dropdown.selected
	var model_idx := _model_dropdown.selected
	if anim_idx < 0 or model_idx < 0:
		_set_status("Select an animation and model first.")
		return

	var anim_folder: String = _available_anims[anim_idx]
	var model_name: String = _available_models[model_idx]
	_current_anim = anim_folder
	_current_model = model_name

	_frame_images.clear()
	_frame_textures.clear()
	var frame_count := -1

	for direction in DIRECTIONS:
		var path := "%s/%s/%s_%s.png" % [SPRITES_BASE, anim_folder, model_name, direction]
		if not ResourceLoader.exists(path):
			_set_status("Missing spritesheet: %s" % path)
			return

		var tex := load(path) as Texture2D
		if tex == null:
			_set_status("Failed to load: %s" % path)
			return

		var sheet_image := tex.get_image()
		if sheet_image == null:
			_set_status("Failed to get image data from: %s" % path)
			return

		# Square frames: frame_width = sheet_height
		var sheet_w := sheet_image.get_width()
		var sheet_h := sheet_image.get_height()
		var fw := sheet_h  # Square frames
		var count := sheet_w / fw

		if frame_count < 0:
			frame_count = count
			_frame_size = Vector2i(fw, sheet_h)
		elif count != frame_count:
			_set_status("Frame count mismatch: %s has %d frames (expected %d)" % [direction, count, frame_count])
			return

		# Extract individual frames
		var images: Array[Image] = []
		var textures: Array[ImageTexture] = []
		for i in count:
			var frame_img := Image.create(fw, sheet_h, false, sheet_image.get_format())
			frame_img.blit_rect(sheet_image, Rect2i(i * fw, 0, fw, sheet_h), Vector2i.ZERO)
			images.append(frame_img)
			textures.append(ImageTexture.create_from_image(frame_img))

		_frame_images[direction] = images
		_frame_textures[direction] = textures

	# Create default composition
	_current_composition = AttackCompositionData.create_default(frame_count)
	_current_composition.animation_name = anim_folder.to_lower()
	_current_composition.composition_id = "%s_%s" % [model_name, anim_folder.to_lower()]
	_current_composition.display_name = "%s %s" % [model_name, anim_folder]

	_preview_frame_index = 0
	_selected_frame = 0
	_selected_frames = [0]
	_undo_stack.clear()
	_update_undo_button()

	_load_info_label.text = "Loaded: %s (%d frames, %dx%d)" % [anim_folder, frame_count, _frame_size.x, _frame_size.y]
	_set_status("Spritesheet loaded. %d frames at %dx%d." % [frame_count, _frame_size.x, _frame_size.y])

	_on_spritesheet_loaded()


func _on_spritesheet_loaded() -> void:
	# Reposition sprite to center of viewport (viewport size is managed by stretch)
	_reposition_preview_sprite()

	# Feed data to timeline
	_timeline_panel.composition = _current_composition
	_timeline_panel.selected_frame = 0
	_selected_frames = [0]
	_timeline_panel.selected_frames = [0]
	# Create thumbnails from the "down" direction frames
	_timeline_panel.frame_thumbnails.clear()
	if _frame_textures.has("down"):
		for tex in _frame_textures["down"]:
			_timeline_panel.frame_thumbnails.append(tex)
	_timeline_panel.queue_redraw()

	_update_preview_frame()
	_update_direction_highlight()
	_update_frame_props_ui()


# ── Preview ────────────────────────────────────────────────────────────

func _update_preview_frame() -> void:
	if _frame_textures.is_empty() or not _frame_textures.has(_preview_direction):
		return
	var textures: Array = _frame_textures[_preview_direction]
	if _preview_frame_index >= 0 and _preview_frame_index < textures.size():
		_preview_sprite.texture = textures[_preview_frame_index]
	_frame_label.text = "Frame %d / %d" % [_preview_frame_index + 1, textures.size()]

	# Update weapon
	_update_weapon_preview()

	# Update anchor detection indicator
	_update_anchor_indicator()

	# Update echo ghosts
	_update_echo_preview()

	# Update crosshair overlay (anchor drawing mode)
	_update_crosshair_overlay()

	# Update onion weapon ghost (previous frame's weapon)
	_update_onion_weapon()


func _update_direction_highlight() -> void:
	for i in DIRECTIONS.size():
		var btn: Button = _direction_buttons[i]
		var is_active: bool = DIRECTIONS[i] == _preview_direction
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_ACCENT if is_active else C_SURFACE
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", sb)


func _on_direction_pressed(dir: String) -> void:
	_preview_direction = dir
	_update_preview_frame()
	_update_direction_highlight()


const WEAPON_ANCHOR_COLOR := Color("#FF00AA")
const WEAPON_DIRECTION_COLOR := Color("#00FFFF")


func _update_weapon_preview() -> void:
	if _current_composition == null or _preview_frame_index < 0:
		_weapon_sprite.visible = false
		_weapon_debug = "no composition"
		return

	if _preview_frame_index >= _current_composition.frames.size():
		_weapon_sprite.visible = false
		_weapon_debug = "frame out of range"
		return

	var frame := _current_composition.frames[_preview_frame_index]
	if not frame.weapon_visible:
		_weapon_sprite.visible = false
		_weapon_debug = "weapon_visible=false"
		return

	# Find anchor pixels in the current body frame
	if not _frame_images.has(_preview_direction):
		_weapon_sprite.visible = false
		_weapon_debug = "no images for dir=%s" % _preview_direction
		return
	var images: Array = _frame_images[_preview_direction]
	if _preview_frame_index >= images.size():
		_weapon_sprite.visible = false
		_weapon_debug = "frame idx >= images"
		return

	var img: Image = images[_preview_frame_index]
	var anchors := _find_anchors_in_image(img)
	var grip_px: Vector2 = anchors.get("grip", Vector2.INF)

	if grip_px == Vector2.INF:
		_weapon_sprite.visible = false
		_weapon_debug = "no grip pixel found"
		return

	# Always use the "right" texture as base and rotate to exact angle
	var weapon_tex: Texture2D = _weapon_set.get("right")
	if weapon_tex == null:
		_weapon_sprite.visible = false
		_weapon_debug = "no 'right' tex in weapon_set"
		return

	_weapon_sprite.texture = weapon_tex
	_weapon_sprite.visible = true
	_weapon_sprite.scale = _preview_sprite.scale

	# Compute rotation from grip → direction pixel
	var direction_px: Vector2 = anchors.get("direction", Vector2.INF)
	if direction_px != Vector2.INF:
		_weapon_sprite.rotation = atan2(direction_px.y - grip_px.y, direction_px.x - grip_px.x)
	else:
		_weapon_sprite.rotation = 0.0

	# Position: grip pixel in image coords → viewport coords
	var anchor_offset := (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
	_weapon_sprite.position = _preview_sprite.position + anchor_offset

	# Offset: shift texture so the "right" grip point sits at the position
	var weapon_grip: Vector2 = _weapon_set.get("grip_right", Vector2.ZERO)
	if weapon_grip != Vector2.ZERO:
		var tex_size := weapon_tex.get_size()
		_weapon_sprite.offset = Vector2(tex_size.x / 2.0 - weapon_grip.x, tex_size.y / 2.0 - weapon_grip.y)
	else:
		_weapon_sprite.offset = Vector2.ZERO

	# Z-index preview: "behind" shown as semi-transparent instead of z=-1,
	# because the preview body is a single sprite so z=-1 hides the weapon entirely.
	# In-game, layered body parts allow true partial occlusion.
	if frame.weapon_z_front:
		_weapon_sprite.z_index = 1
		_weapon_sprite.modulate = Color(1.0, 1.0, 1.0, 0.9)
	else:
		_weapon_sprite.z_index = 1
		_weapon_sprite.modulate = Color(0.6, 0.6, 1.0, 0.4)
	var angle_deg := rad_to_deg(_weapon_sprite.rotation)
	_weapon_debug = "OK %.0fdeg pos=%s" % [angle_deg, str(_weapon_sprite.position)]



func _find_anchors_in_image(img: Image) -> Dictionary:
	var result := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel := img.get_pixel(x, y)
			# Compare RGB only — alpha can vary depending on image format
			if _rgb_approx(pixel, WEAPON_ANCHOR_COLOR) and not result.has("grip"):
				result["grip"] = Vector2(x, y)
			elif _rgb_approx(pixel, WEAPON_DIRECTION_COLOR) and not result.has("direction"):
				result["direction"] = Vector2(x, y)
			if result.size() == 2:
				return result
	return result


## Compare two colors by RGB channels only, ignoring alpha.
func _rgb_approx(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _update_echo_preview() -> void:
	# Clear old echoes
	for ghost in _echo_sprites:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_echo_sprites.clear()

	if _current_composition == null or _preview_frame_index < 0:
		return
	if _preview_frame_index >= _current_composition.frames.size():
		return

	var frame := _current_composition.frames[_preview_frame_index]
	if not frame.echo_enabled:
		return

	if not _frame_textures.has(_preview_direction):
		return
	var textures: Array = _frame_textures[_preview_direction]

	var count := frame.echo_count
	var spacing := frame.echo_spacing_px

	for i in count:
		var echo_frame_idx := _preview_frame_index - (i + 1)
		if echo_frame_idx < 0:
			continue

		var ghost := Sprite2D.new()
		ghost.centered = true
		ghost.texture = textures[echo_frame_idx]
		ghost.scale = _preview_sprite.scale
		ghost.position = _preview_sprite.position - Vector2(0, spacing * _preview_sprite.scale.y * (i + 1))
		var t := float(i) / float(count - 1) if count > 1 else 0.0
		ghost.modulate.a = lerpf(frame.echo_opacity_start, frame.echo_opacity_end, t)
		ghost.z_index = -1
		_preview_viewport.add_child(ghost)
		_echo_sprites.append(ghost)


func _update_anchor_indicator() -> void:
	if _anchor_label == null:
		return
	if _frame_images.is_empty() or not _frame_images.has(_preview_direction):
		_anchor_label.text = ""
		return
	var images: Array = _frame_images[_preview_direction]
	if _preview_frame_index < 0 or _preview_frame_index >= images.size():
		_anchor_label.text = ""
		return

	var img: Image = images[_preview_frame_index]
	var anchors := _find_anchors_in_image(img)
	var has_grip := anchors.has("grip")
	var has_dir := anchors.has("direction")

	var parts: Array[String] = []
	if has_grip:
		var g: Vector2 = anchors["grip"]
		parts.append("Grip(%d,%d)" % [int(g.x), int(g.y)])
	if has_dir:
		var d: Vector2 = anchors["direction"]
		parts.append("Dir(%d,%d)" % [int(d.x), int(d.y)])

	var anchor_text := " | ".join(parts) if not parts.is_empty() else "No anchors"
	# Append weapon status directly in the label
	var weapon_short := _weapon_debug.substr(0, mini(30, _weapon_debug.length()))
	_anchor_label.text = "%s [W:%s]" % [anchor_text, weapon_short]
	if parts.is_empty():
		_anchor_label.add_theme_color_override("font_color", C_WARNING)
	elif parts.size() == 1:
		_anchor_label.add_theme_color_override("font_color", C_WARNING)
	else:
		_anchor_label.add_theme_color_override("font_color", C_SUCCESS)


func _on_preview_viewport_resized() -> void:
	if _preview_checker == null:
		return
	_preview_checker.size = Vector2(_preview_viewport.size)
	_reposition_preview_sprite()


func _reposition_preview_sprite() -> void:
	var vp_size := Vector2(_preview_viewport.size)
	# Center the sprite in the viewport
	var center := vp_size / 2.0
	_preview_sprite.position = center

	# Scale to fit within the viewport with some padding (80%)
	if _frame_size != Vector2i.ZERO:
		var scale_x := (vp_size.x * 0.8) / float(_frame_size.x)
		var scale_y := (vp_size.y * 0.8) / float(_frame_size.y)
		var uniform_scale := minf(scale_x, scale_y)
		# Snap to integer scale if possible for crisp pixel art
		if uniform_scale >= 2.0:
			uniform_scale = floorf(uniform_scale)
		_preview_sprite.scale = Vector2(uniform_scale, uniform_scale)
	else:
		_preview_sprite.scale = Vector2.ONE

	# Reposition weapon, echo ghosts, crosshair, and onion skin too
	_update_weapon_preview()
	_update_echo_preview()
	_update_crosshair_overlay()
	_update_onion_weapon()


func _on_frame_prev() -> void:
	if _current_composition == null:
		return
	_preview_frame_index = max(0, _preview_frame_index - 1)
	_selected_frame = _preview_frame_index
	_selected_frames = [_selected_frame]
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


func _on_frame_next() -> void:
	if _current_composition == null:
		return
	var max_frame := _current_composition.frames.size() - 1
	_preview_frame_index = min(max_frame, _preview_frame_index + 1)
	_selected_frame = _preview_frame_index
	_selected_frames = [_selected_frame]
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


func show_frame(index: int) -> void:
	if _current_composition == null:
		return
	_preview_frame_index = clampi(index, 0, _current_composition.frames.size() - 1)
	_selected_frame = _preview_frame_index
	_selected_frames = [_selected_frame]
	_timeline_panel.selected_frames = _selected_frames
	_update_preview_frame()


# ── Timeline signal handlers ──────────────────────────────────────────

func _on_timeline_frame_selected(index: int) -> void:
	_selected_frame = index
	_selected_frames = [index]
	_preview_frame_index = index
	_update_preview_frame()
	_update_frame_props_ui()


func _on_timeline_frames_selected(indices: Array[int]) -> void:
	_selected_frames = indices
	if not indices.is_empty():
		_selected_frame = indices[-1]
		_preview_frame_index = _selected_frame
		_update_preview_frame()
		_update_frame_props_ui()
	_set_status("%d frames selected." % indices.size())


func _on_timeline_duration_changed(_index: int, _new_ms: int) -> void:
	# Timeline handles redraw internally; just update status
	if _current_composition:
		var total := _current_composition.get_total_duration_sec()
		_set_status("Total: %.3fs" % total)


func _on_timeline_playhead_moved(ms: float) -> void:
	# Determine which frame the playhead is in
	if _current_composition == null:
		return
	var cumulative := 0.0
	for i in _current_composition.frames.size():
		cumulative += _current_composition.frames[i].duration_ms
		if ms < cumulative:
			_preview_frame_index = i
			_selected_frame = i
			_selected_frames = [i]
			_update_preview_frame()
			return


# ── Frame property handlers ────────────────────────────────────────────

func _update_frame_props_ui() -> void:
	var has_data := _current_composition != null and _selected_frame >= 0 and _selected_frame < _current_composition.frames.size()
	# Show/hide the wrapper containers (header + content)
	var frame_wrapper := _frame_props_container.get_parent()
	var seq_wrapper := _seq_props_container.get_parent()
	frame_wrapper.visible = has_data
	seq_wrapper.visible = has_data
	if not has_data:
		return

	var frame := _current_composition.frames[_selected_frame]

	# Block signals during UI update to avoid feedback loops
	_duration_spinbox.set_value_no_signal(frame.duration_ms)
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(frame.duration_ms, 1))
	_weapon_check.set_pressed_no_signal(frame.weapon_visible)
	_weapon_z_front_check.set_pressed_no_signal(frame.weapon_z_front)
	_echo_check.set_pressed_no_signal(frame.echo_enabled)
	_echo_settings_container.visible = frame.echo_enabled
	_echo_count_spin.set_value_no_signal(frame.echo_count)
	_echo_opacity_start_slider.set_value_no_signal(frame.echo_opacity_start)
	_echo_opacity_end_slider.set_value_no_signal(frame.echo_opacity_end)
	_echo_spacing_spin.set_value_no_signal(frame.echo_spacing_px)

	# Effect
	_effect_offset_x.set_value_no_signal(frame.effect_offset.x)
	_effect_offset_y.set_value_no_signal(frame.effect_offset.y)
	# Select effect anchor
	for i in _effect_anchor_dropdown.item_count:
		if _effect_anchor_dropdown.get_item_text(i) == frame.effect_anchor:
			_effect_anchor_dropdown.select(i)
			break

	# Sequence props
	var max_idx := _current_composition.frames.size() - 1
	_movement_start_spin.max_value = max_idx
	_movement_end_spin.max_value = max_idx
	_damage_frame_spin.max_value = max_idx
	_movement_distance_spin.set_value_no_signal(_current_composition.movement_distance)
	_movement_start_spin.set_value_no_signal(_current_composition.movement_start_frame)
	_movement_end_spin.set_value_no_signal(_current_composition.movement_end_frame)
	_damage_frame_spin.set_value_no_signal(_current_composition.damage_frame)

	# Movement type
	var mt := _current_composition.movement_type
	for i in _movement_type_dropdown.item_count:
		if _movement_type_dropdown.get_item_text(i) == (mt if mt != "" else "none"):
			_movement_type_dropdown.select(i)
			break

	_total_duration_label.text = "Total: %.3fs" % _current_composition.get_total_duration_sec()


func _get_target_frames() -> Array[int]:
	if _selected_frames.size() > 1:
		return _selected_frames
	if _selected_frame >= 0:
		return [_selected_frame]
	return []


func _on_duration_changed(value: float) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	for idx in targets:
		_current_composition.frames[idx].duration_ms = int(value)
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(value, 1))
	_total_duration_label.text = "Total: %.3fs" % _current_composition.get_total_duration_sec()
	_timeline_panel.queue_redraw()


func _on_weapon_toggled(pressed: bool) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	for idx in targets:
		_current_composition.frames[idx].weapon_visible = pressed
	_update_preview_frame()
	_timeline_panel.queue_redraw()


func _on_weapon_z_front_toggled(pressed: bool) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	for idx in targets:
		_current_composition.frames[idx].weapon_z_front = pressed
	_update_preview_frame()
	_timeline_panel.queue_redraw()


func _on_effect_selected(index: int) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	var text := _effect_dropdown.get_item_text(index)
	var effect_id := ""
	if text != "(none)":
		# Strip "[Asset] " or "[Placeholder] " prefix to get clean effect ID
		if text.begins_with("[Asset] "):
			effect_id = text.substr(8)
		elif text.begins_with("[Placeholder] "):
			effect_id = text.substr(14)
		else:
			effect_id = text
	for idx in targets:
		_current_composition.frames[idx].effect_id = effect_id
	_timeline_panel.queue_redraw()


func _on_effect_anchor_selected(index: int) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	var anchor_text := _effect_anchor_dropdown.get_item_text(index)
	for idx in targets:
		_current_composition.frames[idx].effect_anchor = anchor_text


func _on_effect_offset_changed(_value: float) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	var offset := Vector2(_effect_offset_x.value, _effect_offset_y.value)
	for idx in targets:
		_current_composition.frames[idx].effect_offset = offset


func _on_echo_toggled(pressed: bool) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	for idx in targets:
		_current_composition.frames[idx].echo_enabled = pressed
	_echo_settings_container.visible = pressed
	_timeline_panel.queue_redraw()


func _on_echo_setting_changed(_value: float) -> void:
	var targets := _get_target_frames()
	if _current_composition == null or targets.is_empty():
		return
	_push_undo()
	for idx in targets:
		var frame := _current_composition.frames[idx]
		frame.echo_count = int(_echo_count_spin.value)
		frame.echo_opacity_start = _echo_opacity_start_slider.value
		frame.echo_opacity_end = _echo_opacity_end_slider.value
		frame.echo_spacing_px = _echo_spacing_spin.value


func _on_movement_type_selected(index: int) -> void:
	if _current_composition == null:
		return
	_push_undo()
	var text := _movement_type_dropdown.get_item_text(index)
	_current_composition.movement_type = "" if text == "none" else text
	_timeline_panel.queue_redraw()


func _on_seq_prop_changed(_value: float) -> void:
	if _current_composition == null:
		return
	_push_undo()
	_current_composition.movement_distance = _movement_distance_spin.value
	_current_composition.movement_start_frame = int(_movement_start_spin.value)
	_current_composition.movement_end_frame = int(_movement_end_spin.value)
	_timeline_panel.queue_redraw()


func _on_damage_frame_changed(value: float) -> void:
	if _current_composition == null:
		return
	_push_undo()
	_current_composition.damage_frame = int(value)
	_timeline_panel.queue_redraw()


# ── Save & Load ────────────────────────────────────────────────────────

const COMPOSITIONS_DIR := "res://resources/compositions"
const SEQUENCES_DIR := "res://resources/sequences"


func _ensure_dirs() -> void:
	for dir_path in [COMPOSITIONS_DIR, SEQUENCES_DIR]:
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)


func _on_generate_runtime() -> void:
	if _current_composition == null:
		_set_status("No composition loaded.")
		return
	var data := CompositionConverter.convert(_current_composition)
	var output := CompositionConverter.phases_to_string(data)
	print("=== Generated Runtime Data for '%s' ===" % _current_composition.composition_id)
	print(output)
	_set_status("Generated %d phases. Check output panel." % data.phases.size())


func _on_save_composition() -> void:
	if _current_composition == null:
		_set_status("No composition loaded.")
		return
	_ensure_dirs()
	var path := "%s/%s.tres" % [COMPOSITIONS_DIR, _current_composition.composition_id]
	var err := ResourceSaver.save(_current_composition, path)
	if err == OK:
		_refresh_composition_dropdown()
		_set_status("Saved composition to %s" % path)
	else:
		_set_status("Error saving composition: %s" % error_string(err))


func _on_save_runtime() -> void:
	if _current_composition == null:
		_set_status("No composition loaded.")
		return
	_ensure_dirs()
	var data := CompositionConverter.convert(_current_composition)
	var path := "%s/%s.tres" % [SEQUENCES_DIR, _current_composition.composition_id]
	var err := ResourceSaver.save(data, path)
	if err == OK:
		_set_status("Saved runtime data to %s" % path)
	else:
		_set_status("Error saving runtime data: %s" % error_string(err))


func _on_save_both() -> void:
	_on_save_composition()
	_on_save_runtime()


func _refresh_composition_dropdown() -> void:
	_ensure_dirs()
	_composition_dropdown.clear()
	var dir := DirAccess.open(COMPOSITIONS_DIR)
	if dir == null:
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			files.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for f in files:
		_composition_dropdown.add_item(f)
	_load_composition_btn.disabled = files.is_empty()


func _on_load_composition_pressed() -> void:
	var idx := _composition_dropdown.selected
	if idx < 0:
		_set_status("No composition selected.")
		return
	var composition_id: String = _composition_dropdown.get_item_text(idx)

	# Load the composition resource
	var path := "%s/%s.tres" % [COMPOSITIONS_DIR, composition_id]
	if not ResourceLoader.exists(path):
		_set_status("Composition not found: %s" % path)
		return
	var loaded := load(path)
	if not loaded is AttackCompositionData:
		_set_status("Invalid composition resource: %s" % path)
		return
	var comp: AttackCompositionData = loaded

	# Derive model name from composition_id by stripping the animation suffix
	# composition_id = "{model}_{animation_name}" (e.g., "mixamo_com_hiltbash")
	var anim_lower: String = comp.animation_name
	var model_name := ""
	if composition_id.ends_with("_" + anim_lower):
		model_name = composition_id.substr(0, composition_id.length() - anim_lower.length() - 1)

	# Find the actual animation folder (case-insensitive match against available anims)
	var anim_folder := ""
	for folder in _available_anims:
		if folder.to_lower() == anim_lower:
			anim_folder = folder
			break

	if anim_folder.is_empty() or model_name.is_empty():
		_set_status("Cannot determine spritesheet for composition '%s'. Load spritesheet manually." % composition_id)
		# Still apply the composition data without spritesheet
		_current_composition = comp
		_selected_frame = 0
		_selected_frames = [0]
		_preview_frame_index = 0
		_undo_stack.clear()
		_update_undo_button()
		_timeline_panel.composition = _current_composition
		_timeline_panel.selected_frame = 0
		_timeline_panel.selected_frames = [0]
		_timeline_panel.queue_redraw()
		_update_frame_props_ui()
		return

	# Load spritesheets for all directions
	_frame_images.clear()
	_frame_textures.clear()
	var frame_count := -1

	for direction in DIRECTIONS:
		var sheet_path := "%s/%s/%s_%s.png" % [SPRITES_BASE, anim_folder, model_name, direction]
		if not ResourceLoader.exists(sheet_path):
			_set_status("Missing spritesheet: %s" % sheet_path)
			return

		var tex := load(sheet_path) as Texture2D
		if tex == null:
			_set_status("Failed to load: %s" % sheet_path)
			return

		var sheet_image := tex.get_image()
		if sheet_image == null:
			_set_status("Failed to get image data from: %s" % sheet_path)
			return

		var sheet_w := sheet_image.get_width()
		var sheet_h := sheet_image.get_height()
		var fw := sheet_h
		var count := sheet_w / fw

		if frame_count < 0:
			frame_count = count
			_frame_size = Vector2i(fw, sheet_h)
		elif count != frame_count:
			_set_status("Frame count mismatch: %s has %d frames (expected %d)" % [direction, count, frame_count])
			return

		var images: Array[Image] = []
		var textures: Array[ImageTexture] = []
		for i in count:
			var frame_img := Image.create(fw, sheet_h, false, sheet_image.get_format())
			frame_img.blit_rect(sheet_image, Rect2i(i * fw, 0, fw, sheet_h), Vector2i.ZERO)
			images.append(frame_img)
			textures.append(ImageTexture.create_from_image(frame_img))

		_frame_images[direction] = images
		_frame_textures[direction] = textures

	# Apply composition and set up state
	_current_anim = anim_folder
	_current_model = model_name
	_current_composition = comp
	_preview_frame_index = 0
	_selected_frame = 0
	_selected_frames = [0]
	_undo_stack.clear()
	_update_undo_button()

	# Sync dropdowns to match
	for i in _available_anims.size():
		if _available_anims[i] == anim_folder:
			_anim_dropdown.select(i)
			_on_anim_selected(i)
			break
	for i in _available_models.size():
		if _available_models[i] == model_name:
			_model_dropdown.select(i)
			break

	_load_info_label.text = "Loaded: %s (%d frames, %dx%d)" % [anim_folder, frame_count, _frame_size.x, _frame_size.y]
	_on_spritesheet_loaded()
	_set_status("Loaded composition '%s' with spritesheets." % composition_id)


# ── Anchor Painting ───────────────────────────────────────────────────

func _on_preview_viewport_input(event: InputEvent) -> void:
	if not _anchor_draw_enabled:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	# Left-click = grip, Right-click = direction
	var tool_name: String
	if mb.button_index == MOUSE_BUTTON_LEFT:
		tool_name = "grip"
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		tool_name = "direction"
	else:
		return

	# Convert container click coords → viewport pixel coords → frame pixel coords
	var container_size := _viewport_container_ref.size
	var vp_size := Vector2(_preview_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return

	var vp_click := mb.position * (vp_size / container_size)

	# Viewport coords → frame pixel coords
	# The sprite is centered at _preview_sprite.position, scaled by _preview_sprite.scale
	var sprite_pos := _preview_sprite.position
	var sprite_scale := _preview_sprite.scale
	if sprite_scale.x <= 0 or sprite_scale.y <= 0:
		return

	var pixel := (vp_click - sprite_pos) / sprite_scale + Vector2(_frame_size) / 2.0
	var px := int(pixel.x)
	var py := int(pixel.y)

	# Bounds check
	if px < 0 or px >= _frame_size.x or py < 0 or py >= _frame_size.y:
		return

	_push_undo()
	_place_anchor_on_frame(px, py, tool_name)
	_viewport_container_ref.accept_event()


func _place_anchor_on_frame(x: int, y: int, tool_name: String) -> void:
	if not _frame_images.has(_preview_direction):
		return
	var images: Array = _frame_images[_preview_direction]
	if _preview_frame_index < 0 or _preview_frame_index >= images.size():
		return

	var img: Image = images[_preview_frame_index]
	var color: Color
	if tool_name == "grip":
		color = WEAPON_ANCHOR_COLOR
	else:
		color = WEAPON_DIRECTION_COLOR

	# Clear existing pixels of that color from this frame
	_clear_anchor_color(img, color)
	# Place the new anchor pixel
	img.set_pixel(x, y, color)

	# Recreate texture for this frame
	var textures: Array = _frame_textures[_preview_direction]
	textures[_preview_frame_index] = ImageTexture.create_from_image(img)

	# Update timeline thumbnails if this is the "down" direction
	if _preview_direction == "down":
		_timeline_panel.frame_thumbnails.clear()
		var down_textures: Array = _frame_textures["down"]
		for tex in down_textures:
			_timeline_panel.frame_thumbnails.append(tex)
		_timeline_panel.queue_redraw()

	_anchor_images_dirty = true
	if _save_spritesheets_btn:
		_save_spritesheets_btn.disabled = false

	_update_preview_frame()


func _clear_anchor_color(img: Image, color: Color) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel := img.get_pixel(x, y)
			if _rgb_approx(pixel, color):
				img.set_pixel(x, y, Color.TRANSPARENT)


func _on_draw_anchors_toggled(pressed: bool) -> void:
	_anchor_draw_enabled = pressed
	_onion_skin_container.visible = pressed
	if not pressed:
		_anchor_onion_skin_enabled = false
		if _onion_skin_check:
			_onion_skin_check.set_pressed_no_signal(false)
		_onion_weapon_sprite.visible = false
		_crosshair_sprite.visible = false
	_update_crosshair_overlay()
	if pressed:
		_set_status("Anchor drawing ON. L-click = grip, R-click = direction.")
	else:
		_set_status("Anchor drawing OFF.")


func _on_onion_skin_toggled(pressed: bool) -> void:
	_anchor_onion_skin_enabled = pressed
	_update_onion_weapon()


func _update_crosshair_overlay() -> void:
	if not _anchor_draw_enabled:
		if _crosshair_sprite:
			_crosshair_sprite.visible = false
		return
	if _frame_images.is_empty() or not _frame_images.has(_preview_direction):
		_crosshair_sprite.visible = false
		return
	var images: Array = _frame_images[_preview_direction]
	if _preview_frame_index < 0 or _preview_frame_index >= images.size():
		_crosshair_sprite.visible = false
		return

	var img: Image = images[_preview_frame_index]
	var anchors := _find_anchors_in_image(img)

	if anchors.is_empty():
		_crosshair_sprite.visible = false
		return

	# Create transparent overlay at frame size
	var overlay := Image.create(_frame_size.x, _frame_size.y, true, Image.FORMAT_RGBA8)
	# Draw crosshairs at anchor positions
	if anchors.has("grip"):
		var g: Vector2 = anchors["grip"]
		_draw_crosshair_on_image(overlay, int(g.x), int(g.y), WEAPON_ANCHOR_COLOR)
	if anchors.has("direction"):
		var d: Vector2 = anchors["direction"]
		_draw_crosshair_on_image(overlay, int(d.x), int(d.y), WEAPON_DIRECTION_COLOR)

	_crosshair_sprite.texture = ImageTexture.create_from_image(overlay)
	_crosshair_sprite.position = _preview_sprite.position
	_crosshair_sprite.scale = _preview_sprite.scale
	_crosshair_sprite.visible = true


func _draw_crosshair_on_image(img: Image, cx: int, cy: int, color: Color) -> void:
	## Draw a small crosshair (4-pixel arms) around the given pixel.
	var offsets: Array[Vector2i] = [
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, -2), Vector2i(0, -1), Vector2i(0, 1), Vector2i(0, 2)]
	for ofs in offsets:
		var px: int = cx + ofs.x
		var py: int = cy + ofs.y
		if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
			img.set_pixel(px, py, color)
	# Also draw the center pixel
	if cx >= 0 and cx < img.get_width() and cy >= 0 and cy < img.get_height():
		img.set_pixel(cx, cy, color)


func _update_onion_weapon() -> void:
	if not _anchor_onion_skin_enabled or _preview_frame_index <= 0:
		if _onion_weapon_sprite:
			_onion_weapon_sprite.visible = false
		return
	if _current_composition == null or _preview_frame_index >= _current_composition.frames.size():
		_onion_weapon_sprite.visible = false
		return
	if not _frame_images.has(_preview_direction):
		_onion_weapon_sprite.visible = false
		return

	var prev_idx := _preview_frame_index - 1
	var images: Array = _frame_images[_preview_direction]
	if prev_idx < 0 or prev_idx >= images.size():
		_onion_weapon_sprite.visible = false
		return

	var prev_img: Image = images[prev_idx]
	var anchors := _find_anchors_in_image(prev_img)
	var grip_px: Vector2 = anchors.get("grip", Vector2.INF)
	if grip_px == Vector2.INF:
		_onion_weapon_sprite.visible = false
		return

	# Use same weapon texture as main weapon sprite
	var weapon_tex: Texture2D = _weapon_set.get("right")
	if weapon_tex == null:
		_onion_weapon_sprite.visible = false
		return

	_onion_weapon_sprite.texture = weapon_tex
	_onion_weapon_sprite.visible = true
	_onion_weapon_sprite.scale = _preview_sprite.scale
	_onion_weapon_sprite.modulate = Color(1, 1, 1, 0.3)

	# Compute rotation from grip → direction pixel (same as _update_weapon_preview)
	var direction_px: Vector2 = anchors.get("direction", Vector2.INF)
	if direction_px != Vector2.INF:
		_onion_weapon_sprite.rotation = atan2(direction_px.y - grip_px.y, direction_px.x - grip_px.x)
	else:
		_onion_weapon_sprite.rotation = 0.0

	# Position: grip pixel → viewport coords
	var anchor_offset := (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
	_onion_weapon_sprite.position = _preview_sprite.position + anchor_offset

	# Offset weapon grip point
	var weapon_grip: Vector2 = _weapon_set.get("grip_right", Vector2.ZERO)
	if weapon_grip != Vector2.ZERO:
		var tex_size := weapon_tex.get_size()
		_onion_weapon_sprite.offset = Vector2(tex_size.x / 2.0 - weapon_grip.x, tex_size.y / 2.0 - weapon_grip.y)
	else:
		_onion_weapon_sprite.offset = Vector2.ZERO


func _on_save_spritesheets() -> void:
	if _frame_images.is_empty() or _current_anim == "" or _current_model == "":
		_set_status("No spritesheet loaded to save.")
		return

	var saved := 0
	for direction in DIRECTIONS:
		if not _frame_images.has(direction):
			continue
		var images: Array = _frame_images[direction]
		if images.is_empty():
			continue

		# Reassemble horizontal spritesheet from individual frame images
		var fw := _frame_size.x
		var fh := _frame_size.y
		var sheet := Image.create(fw * images.size(), fh, false, (images[0] as Image).get_format())
		for i in images.size():
			sheet.blit_rect(images[i], Rect2i(0, 0, fw, fh), Vector2i(i * fw, 0))

		var file_path := "%s/%s/%s_%s.png" % [SPRITES_BASE, _current_anim, _current_model, direction]
		var global_path := ProjectSettings.globalize_path(file_path)
		var err := sheet.save_png(global_path)
		if err == OK:
			saved += 1
		else:
			_set_status("Error saving %s: %s" % [file_path, error_string(err)])
			return

	_anchor_images_dirty = false
	if _save_spritesheets_btn:
		_save_spritesheets_btn.disabled = true

	_set_status("Saved %d spritesheet(s) to %s/%s/." % [saved, SPRITES_BASE, _current_anim])


# ── Asset scanning ────────────────────────────────────────────────────

func _scan_weapon_folders() -> Array[String]:
	var weapon_ids: Array[String] = []
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return weapon_ids
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var weapon_path: String = WEAPONS_DIR + "/" + folder + "/weapon.png"
			var meta_path: String = WEAPONS_DIR + "/" + folder + "/metadata.json"
			if FileAccess.file_exists(weapon_path) and FileAccess.file_exists(meta_path):
				weapon_ids.append(folder)
		folder = dir.get_next()
	return weapon_ids


func _load_weapon_from_folder(weapon_id: String) -> Dictionary:
	var dir_path: String = WEAPONS_DIR + "/" + weapon_id
	var img := Image.load_from_file(ProjectSettings.globalize_path(dir_path + "/weapon.png"))
	if img == null:
		return {}
	var tex := ImageTexture.create_from_image(img)

	var meta_file := FileAccess.open(dir_path + "/metadata.json", FileAccess.READ)
	if meta_file == null:
		return {}
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if meta == null:
		return {}

	var grip := Vector2(meta["grip"][0], meta["grip"][1])
	var tip := Vector2(meta["tip"][0], meta["tip"][1])

	# Return same format as PlaceholderWeaponSprites sets.
	# Single texture for all directions (rotation handled by anchor system).
	return {
		"down": tex, "up": tex, "right": tex,
		"grip_down": grip, "grip_up": grip, "grip_right": grip,
		"tip_down": tip, "tip_up": tip, "tip_right": tip,
	}


func _scan_effect_folders() -> Array[String]:
	var effect_ids: Array[String] = []
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		return effect_ids
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var meta_path: String = EFFECTS_DIR + "/" + folder + "/metadata.json"
			if FileAccess.file_exists(meta_path):
				effect_ids.append(folder)
		folder = dir.get_next()
	return effect_ids


func _on_weapon_dropdown_selected(index: int) -> void:
	var text := _weapon_dropdown.get_item_text(index)
	if text.begins_with("[Asset] "):
		var weapon_id := text.substr(8)
		var loaded := _load_weapon_from_folder(weapon_id)
		if not loaded.is_empty():
			_weapon_set = loaded
			_update_preview_frame()
			return
	# Fallback to placeholder sword
	_weapon_set = PlaceholderWeaponSprites.create_sword_set()
	_update_preview_frame()
