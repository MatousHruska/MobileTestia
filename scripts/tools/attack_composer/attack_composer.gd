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
const TOOLS_MENU_PATH := "res://scenes/tools/tools_menu.tscn"

# ── State ──────────────────────────────────────────────────────────────
var _current_composition: AttackCompositionData = null
var _frame_images: Dictionary = {}  # {direction_string: Array[Image]}
var _frame_textures: Dictionary = {}  # {direction_string: Array[ImageTexture]}
var _preview_direction := "down"
var _edit_all_directions: bool = false  # When true, edits apply to all directions
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

# ── Effect animation state ────────────────────────────────────────────
var _effect_anim_ms := 0.0    # Elapsed time within current effect animation
var _effect_anim_id := ""     # Effect ID that's currently animating (to detect changes)

# ── Anchor painting state ─────────────────────────────────────────────
var _anchor_draw_enabled: bool = false
var _anchor_onion_skin_enabled: bool = false
var _anchor_images_dirty: bool = false

# ── Preview zoom/pan state ────────────────────────────────────────────
var _preview_zoom: float = 1.0
var _preview_pan: Vector2 = Vector2.ZERO
var _pan_dragging: bool = false
var _pan_drag_start: Vector2 = Vector2.ZERO
var _zoom_label: Label = null

# ── Body clip mask painting state ────────────────────────────────────
var _body_clip_paint_enabled: bool = false
var _body_clip_brush_size: int = 1
var _body_clip_paint_erase: bool = false  # false=paint clip, true=erase clip
var _body_clip_draw_check: CheckButton = null
var _body_clip_generate_btn: Button = null
var _body_clip_buttons_container: VBoxContainer = null
var _body_clip_brush_buttons: Array[Button] = []

# ── Alpha painting state (effect) ────────────────────────────────────
var _effect_alpha_paint_enabled: bool = false
var _effect_alpha_paint_value: int = 128
var _effect_alpha_brush_size: int = 1
var _effect_alpha_draw_check: CheckButton = null
var _effect_alpha_buttons_container: VBoxContainer = null
var _effect_alpha_buttons: Array[Button] = []
var _effect_alpha_brush_buttons: Array[Button] = []

# ── Undo state ────────────────────────────────────────────────────────
var _undo_stack: Array = []  # Array of Dictionary {composition, images}
const MAX_UNDO := 50

# ── UI references ──────────────────────────────────────────────────────
var _status_label: Label
var _left_scroll_content: VBoxContainer
var _right_vbox: VBoxContainer
var _timeline_panel: TimelinePanel
var _timeline_scrollbar: HScrollBar
var _model_dropdown: OptionButton
var _anim_dropdown: OptionButton
var _load_info_label: Label
var _composition_dropdown: OptionButton
var _load_composition_btn: Button
var _frame_props_container: VBoxContainer
var _duration_spinbox: SpinBox
var _fps_label: Label
var _total_duration_label: Label
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
var _template_id_input: LineEdit
var _preview_viewport: SubViewport
var _preview_sprite: Sprite2D
var _preview_checker: ColorRect
var _weapon_sprite: Sprite2D
var _weapon_set: Dictionary = {}
var _echo_sprites: Array[Sprite2D] = []
var _direction_buttons: Array[Button] = []
var _all_directions_btn: Button
var _frame_section_wrapper: VBoxContainer  # Visibility wrapper for all frame sub-sections
var _undo_btn: Button
var _draw_anchors_check: CheckButton
var _onion_skin_check: CheckButton
var _onion_skin_container: VBoxContainer
var _save_spritesheets_btn: Button
var _crosshair_sprite: Sprite2D
var _effect_sprite: Sprite2D
var _effect_cache: Dictionary = {}  # { effect_id: { "texture": Texture2D, "frame_size": int, ... } }
var _effect_z_index_spin: SpinBox
var _effect_rotation_spin: SpinBox
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
			var seq := _active_sequence()
			if seq and not seq.frames.is_empty():
				_playing = false
				_play_btn.text = "\u25b6"
				_preview_frame_index = seq.frames.size() - 1
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
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	if seq.frames.size() <= 1:
		_set_status("Cannot delete the last frame.")
		return

	_push_undo()
	var deleted_idx := _selected_frame

	# Delete from all edit directions (All mode or single)
	for dir_name in _edit_directions():
		var s := _current_composition.get_sequence(dir_name)
		if s == null or deleted_idx >= s.frames.size() or s.frames.size() <= 1:
			continue
		s.frames.remove_at(deleted_idx)
		# Adjust sequence-level indices
		if s.damage_frame == deleted_idx:
			s.damage_frame = -1
		elif s.damage_frame > deleted_idx:
			s.damage_frame -= 1
		if s.movement_start_frame > deleted_idx:
			s.movement_start_frame -= 1
		elif s.movement_start_frame == deleted_idx:
			s.movement_start_frame = -1
		if s.movement_end_frame > deleted_idx:
			s.movement_end_frame -= 1
		elif s.movement_end_frame == deleted_idx:
			s.movement_end_frame = -1

	# Remove from frame images/textures for edited directions
	for dir_name in _edit_directions():
		if _frame_images.has(dir_name):
			var imgs: Array = _frame_images[dir_name]
			if deleted_idx < imgs.size():
				imgs.remove_at(deleted_idx)
		if _frame_textures.has(dir_name):
			var texs: Array = _frame_textures[dir_name]
			if deleted_idx < texs.size():
				texs.remove_at(deleted_idx)

	# Adjust selection
	seq = _active_sequence()
	if seq:
		_selected_frame = mini(_selected_frame, maxi(0, seq.frames.size() - 1))
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame
	_switch_to_direction(_preview_direction)
	_set_status("Deleted frame %d." % deleted_idx)


# ── Undo ──────────────────────────────────────────────────────────────

func _push_undo() -> void:
	if _current_composition == null:
		return
	var comp_snapshot := AttackCompositionData.new()
	comp_snapshot.composition_id = _current_composition.composition_id
	comp_snapshot.display_name = _current_composition.display_name
	comp_snapshot.runtime_template_id = _current_composition.runtime_template_id
	comp_snapshot.animation_name = _current_composition.animation_name
	comp_snapshot.locks_movement = _current_composition.locks_movement

	# Deep-copy all direction sequences
	for dir_name in AttackCompositionData.DIRECTIONS:
		var src_seq := _current_composition.get_sequence(dir_name)
		if src_seq == null:
			continue
		var seq_copy := DirectionSequence.new()
		seq_copy.movement_type = src_seq.movement_type
		seq_copy.movement_distance = src_seq.movement_distance
		seq_copy.movement_start_frame = src_seq.movement_start_frame
		seq_copy.movement_end_frame = src_seq.movement_end_frame
		seq_copy.damage_frame = src_seq.damage_frame
		for frame in src_seq.frames:
			var frame_copy := frame.duplicate()
			if frame.body_clip_mask != null:
				frame_copy.body_clip_mask = frame.body_clip_mask.duplicate()
			if frame.effect_alpha_mask != null:
				frame_copy.effect_alpha_mask = frame.effect_alpha_mask.duplicate()
			seq_copy.frames.append(frame_copy)
		comp_snapshot.direction_sequences[dir_name] = seq_copy

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
	_current_composition.runtime_template_id = snapshot.runtime_template_id
	_current_composition.animation_name = snapshot.animation_name
	_current_composition.locks_movement = snapshot.locks_movement

	# Restore all direction sequences
	_current_composition.direction_sequences.clear()
	for dir_name in snapshot.direction_sequences:
		_current_composition.direction_sequences[dir_name] = snapshot.direction_sequences[dir_name]

	# Restore frame images if snapshot includes them
	if entry.has("images"):
		var images_snapshot: Dictionary = entry["images"]
		for dir_name in images_snapshot:
			_frame_images[dir_name] = images_snapshot[dir_name]
			var new_textures: Array[ImageTexture] = []
			for img: Image in images_snapshot[dir_name]:
				new_textures.append(ImageTexture.create_from_image(img))
			_frame_textures[dir_name] = new_textures

	# Adjust selection to active direction
	var seq := _active_sequence()
	if seq:
		_selected_frame = clampi(_selected_frame, 0, maxi(0, seq.frames.size() - 1))
	else:
		_selected_frame = 0
	_selected_frames = [_selected_frame]
	_preview_frame_index = _selected_frame

	# Refresh timeline with active direction
	_switch_to_direction(_preview_direction)
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

	# Tools Menu button
	var tools_menu_margin := MarginContainer.new()
	tools_menu_margin.add_theme_constant_override("margin_left", 12)
	tools_menu_margin.add_theme_constant_override("margin_right", 12)
	tools_menu_margin.add_theme_constant_override("margin_top", 4)
	tools_menu_margin.add_theme_constant_override("margin_bottom", 0)
	left_vbox.add_child(tools_menu_margin)

	var tools_menu_btn := _make_button("\u2190 Tools Menu", func() -> void:
		get_tree().change_scene_to_file(TOOLS_MENU_PATH)
	)
	tools_menu_margin.add_child(tools_menu_btn)

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

	# Effect sprite — renders the first frame of the assigned effect
	_effect_sprite = Sprite2D.new()
	_effect_sprite.centered = true
	_effect_sprite.visible = false
	_effect_sprite.z_index = 2
	_preview_viewport.add_child(_effect_sprite)

	# Crosshair overlay — drawn on top of everything to show anchor positions
	_crosshair_sprite = Sprite2D.new()
	_crosshair_sprite.centered = true
	_crosshair_sprite.visible = false
	_crosshair_sprite.z_index = 3
	_preview_viewport.add_child(_crosshair_sprite)

	# Always use placeholder sword — compositions are weapon-agnostic
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

	# "All" direction button
	_all_directions_btn = _make_button("All", _on_all_directions_pressed)
	_all_directions_btn.custom_minimum_size.x = 40
	controls_inner.add_child(_all_directions_btn)

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

	# Zoom controls
	var spacer3 := Control.new()
	spacer3.custom_minimum_size.x = 8
	controls_inner.add_child(spacer3)

	_zoom_label = Label.new()
	_zoom_label.add_theme_font_size_override("font_size", FONT_HINT)
	_zoom_label.add_theme_color_override("font_color", C_ACCENT)
	_zoom_label.text = ""
	_zoom_label.custom_minimum_size.x = 36
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_inner.add_child(_zoom_label)

	var zoom_reset_btn := _make_button("1:1", _on_zoom_reset)
	zoom_reset_btn.custom_minimum_size.x = 32
	zoom_reset_btn.tooltip_text = "Reset zoom and pan"
	controls_inner.add_child(zoom_reset_btn)

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
	_timeline_panel.effect_toggled.connect(_on_timeline_effect_toggled)
	_timeline_panel.effect_moved.connect(_on_timeline_effect_moved)
	_timeline_panel.echo_toggled.connect(_on_timeline_echo_toggled)
	_timeline_panel.damage_moved.connect(_on_timeline_damage_moved)
	_timeline_panel.scroll_changed.connect(_on_timeline_scroll_changed)
	timeline_container.add_child(_timeline_panel)

	_timeline_scrollbar = HScrollBar.new()
	_timeline_scrollbar.custom_minimum_size.y = 16
	_timeline_scrollbar.min_value = 0
	_timeline_scrollbar.max_value = 1000
	_timeline_scrollbar.page = 500
	_timeline_scrollbar.value_changed.connect(_on_timeline_scrollbar_changed)
	_right_vbox.add_child(_timeline_scrollbar)


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
	var seq := _active_sequence()
	if seq == null:
		return
	_playback_ms += delta * 1000.0 * _playback_speed
	var total := seq.get_total_duration_sec() * 1000.0
	if total <= 0:
		return
	if _playback_ms >= total:
		_playback_ms = fmod(_playback_ms, total)  # Loop
	_update_playhead()
	_advance_effect_animation(delta)


func _update_playhead() -> void:
	var seq := _active_sequence()
	if seq == null:
		return
	# Determine which frame the playhead is in
	var cumulative := 0.0
	for i in seq.frames.size():
		cumulative += seq.frames[i].duration_ms
		if _playback_ms < cumulative:
			if _preview_frame_index != i:
				_preview_frame_index = i
				_update_preview_frame()
			break

	# Update timeline playhead
	_timeline_panel.playhead_ms = _playback_ms
	_timeline_panel.queue_redraw()

	# Update time label
	var total_ms := seq.get_total_duration_sec() * 1000.0
	_time_label.text = "%d:%03d / %d:%03d" % [
		int(_playback_ms / 1000.0), int(fmod(_playback_ms, 1000.0)),
		int(total_ms / 1000.0), int(fmod(total_ms, 1000.0))
	]


func _advance_effect_animation(delta: float) -> void:
	var seq := _active_sequence()
	if seq == null or _preview_frame_index < 0:
		return
	if _preview_frame_index >= seq.frames.size():
		return

	var frame := seq.frames[_preview_frame_index]
	var eid := frame.effect_id

	# Detect effect change — reset animation timer
	if eid != _effect_anim_id:
		_effect_anim_id = eid
		_effect_anim_ms = 0.0

	if eid.is_empty():
		return

	# Advance timer
	_effect_anim_ms += delta * 1000.0 * _playback_speed

	# Look up cached assets for frame count and FPS
	var assets := _load_effect_assets(eid)
	if assets.is_empty():
		return

	var frame_count: int = assets["frame_count"]
	var fps: float = assets["fps"]
	var frame_size: int = assets["frame_size"]
	if frame_count <= 1 or fps <= 0:
		return

	# Compute which effect frame to show
	var ms_per_frame := 1000.0 / fps
	var effect_frame := int(_effect_anim_ms / ms_per_frame)
	# Clamp to last frame (don't loop the effect — it plays once per trigger)
	effect_frame = mini(effect_frame, frame_count - 1)

	# Update the atlas region to show the correct frame
	var atlas: AtlasTexture = assets["texture"]
	atlas.region = Rect2(effect_frame * frame_size, 0, frame_size, frame_size)


func _on_play_toggle() -> void:
	_playing = not _playing
	_play_btn.text = "\u23f8" if _playing else "\u25b6"
	if _playing:
		_effect_anim_ms = 0.0
		_effect_anim_id = ""
	else:
		_update_effect_preview()  # Reset atlas to frame 0


func _on_stop() -> void:
	_playing = false
	_playback_ms = 0.0
	_effect_anim_ms = 0.0
	_effect_anim_id = ""
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
	# ── Frame sub-sections wrapper (hidden until data is loaded) ──
	_frame_section_wrapper = VBoxContainer.new()
	_frame_section_wrapper.add_theme_constant_override("separation", 0)
	_frame_section_wrapper.visible = false
	_left_scroll_content.add_child(_frame_section_wrapper)

	_build_frame_subsection()
	_build_weapon_subsection()
	_build_effect_subsection()
	_build_echo_subsection()

	# Total duration (always visible at the bottom of the frame sections)
	_total_duration_label = _make_label("Total: 0.000s", C_TEXT)
	_frame_section_wrapper.add_child(_total_duration_label)

	# ── Sequence Properties (collapsed by default) ──
	var seq_parts: Array = _make_collapsible_section("Sequence Properties", _left_scroll_content)
	var seq_wrapper: VBoxContainer = seq_parts[0]
	_seq_props_container = seq_parts[1]
	seq_wrapper.visible = false  # Hidden until data is loaded

	_build_seq_and_save_sections()


func _build_frame_subsection() -> void:
	var parts: Array = _make_collapsible_section("Frame", _frame_section_wrapper, false)
	_frame_props_container = parts[1]

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


func _build_weapon_subsection() -> void:
	var parts: Array = _make_collapsible_section("Weapon", _frame_section_wrapper, false)
	var section: VBoxContainer = parts[1]

	# Draw Anchors toggle
	_draw_anchors_check = CheckButton.new()
	_draw_anchors_check.text = "Draw Anchors"
	_draw_anchors_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_draw_anchors_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_draw_anchors_check.toggled.connect(_on_draw_anchors_toggled)
	section.add_child(_draw_anchors_check)

	# Onion skin container (shown when Draw Anchors is on)
	_onion_skin_container = VBoxContainer.new()
	_onion_skin_container.add_theme_constant_override("separation", 4)
	_onion_skin_container.visible = false
	section.add_child(_onion_skin_container)

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

	# ── Body Clip Mask toggle and controls ──
	_body_clip_draw_check = CheckButton.new()
	_body_clip_draw_check.text = "Body Clip Mask"
	_body_clip_draw_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_body_clip_draw_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_body_clip_draw_check.toggled.connect(_on_body_clip_draw_toggled)
	section.add_child(_body_clip_draw_check)

	_body_clip_buttons_container = VBoxContainer.new()
	_body_clip_buttons_container.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.visible = false
	section.add_child(_body_clip_buttons_container)

	# Generate mask from body alpha
	_body_clip_generate_btn = _make_button("Generate from Body", _on_generate_body_clip_from_body)
	_body_clip_buttons_container.add_child(_body_clip_generate_btn)

	# Paint/Erase toggle row
	var clip_mode_hbox := HBoxContainer.new()
	clip_mode_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_mode_hbox)
	var paint_btn := Button.new()
	paint_btn.text = "Paint Clip"
	paint_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	paint_btn.custom_minimum_size.y = 28
	paint_btn.add_theme_font_size_override("font_size", FONT_HINT)
	paint_btn.pressed.connect(func(): _body_clip_paint_erase = false)
	clip_mode_hbox.add_child(paint_btn)
	var erase_btn := Button.new()
	erase_btn.text = "Erase Clip"
	erase_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	erase_btn.custom_minimum_size.y = 28
	erase_btn.add_theme_font_size_override("font_size", FONT_HINT)
	erase_btn.pressed.connect(func(): _body_clip_paint_erase = true)
	clip_mode_hbox.add_child(erase_btn)

	# Brush size buttons row
	var clip_brush_label := Label.new()
	clip_brush_label.text = "Brush Size"
	clip_brush_label.add_theme_font_size_override("font_size", FONT_HINT)
	clip_brush_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_body_clip_buttons_container.add_child(clip_brush_label)

	var clip_brush_hbox := HBoxContainer.new()
	clip_brush_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_brush_hbox)

	_body_clip_brush_buttons.clear()
	for bsize in [1, 3, 5]:
		var brush_btn := Button.new()
		brush_btn.text = "%dpx" % bsize
		brush_btn.size_flags_horizontal = SIZE_EXPAND_FILL
		brush_btn.custom_minimum_size.y = 28
		brush_btn.add_theme_font_size_override("font_size", FONT_HINT)
		brush_btn.pressed.connect(_on_body_clip_brush_size.bind(bsize))
		clip_brush_hbox.add_child(brush_btn)
		_body_clip_brush_buttons.append(brush_btn)
	_update_body_clip_brush_highlight()

	# Hint label
	var clip_hint := Label.new()
	clip_hint.text = "L-click on body to paint/erase clip region"
	clip_hint.add_theme_font_size_override("font_size", FONT_HINT)
	clip_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_body_clip_buttons_container.add_child(clip_hint)

	# Action buttons row
	var clip_actions_hbox := HBoxContainer.new()
	clip_actions_hbox.add_theme_constant_override("separation", 4)
	_body_clip_buttons_container.add_child(clip_actions_hbox)

	var clear_clip_btn := _make_button("Clear Mask", _on_clear_body_clip)
	clear_clip_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	clip_actions_hbox.add_child(clear_clip_btn)

	var copy_clip_btn := _make_button("Copy \u2192 Next", _on_copy_body_clip_to_next)
	copy_clip_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	clip_actions_hbox.add_child(copy_clip_btn)


func _build_effect_subsection() -> void:
	var parts: Array = _make_collapsible_section("Effect", _frame_section_wrapper)
	var section: VBoxContainer = parts[1]

	section.add_child(_make_label("Effect"))
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
	section.add_child(_effect_dropdown)

	section.add_child(_make_label("Effect Anchor"))
	_effect_anchor_dropdown = _make_option_button()
	_effect_anchor_dropdown.add_item("weapon_tip")
	_effect_anchor_dropdown.add_item("center")
	_effect_anchor_dropdown.add_item("feet")
	_effect_anchor_dropdown.item_selected.connect(_on_effect_anchor_selected)
	section.add_child(_effect_anchor_dropdown)

	var offset_hbox := HBoxContainer.new()
	offset_hbox.add_theme_constant_override("separation", 4)
	section.add_child(offset_hbox)
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

	section.add_child(_make_label("Z Index"))
	_effect_z_index_spin = SpinBox.new()
	_effect_z_index_spin.min_value = -5
	_effect_z_index_spin.max_value = 10
	_effect_z_index_spin.step = 1
	_effect_z_index_spin.value = 2
	_effect_z_index_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_effect_z_index_spin.value_changed.connect(_on_effect_z_index_changed)
	section.add_child(_effect_z_index_spin)

	section.add_child(_make_label("Rotation (°)"))
	_effect_rotation_spin = SpinBox.new()
	_effect_rotation_spin.min_value = -180
	_effect_rotation_spin.max_value = 180
	_effect_rotation_spin.step = 5
	_effect_rotation_spin.value = 0
	_effect_rotation_spin.size_flags_horizontal = SIZE_EXPAND_FILL
	_effect_rotation_spin.value_changed.connect(_on_effect_rotation_changed)
	section.add_child(_effect_rotation_spin)

	# ── Draw Alpha toggle and controls (effect) ──
	_effect_alpha_draw_check = CheckButton.new()
	_effect_alpha_draw_check.text = "Draw Alpha"
	_effect_alpha_draw_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_effect_alpha_draw_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_effect_alpha_draw_check.toggled.connect(_on_effect_alpha_draw_toggled)
	section.add_child(_effect_alpha_draw_check)

	_effect_alpha_buttons_container = VBoxContainer.new()
	_effect_alpha_buttons_container.add_theme_constant_override("separation", 4)
	_effect_alpha_buttons_container.visible = false
	section.add_child(_effect_alpha_buttons_container)

	# Alpha level buttons row
	var eff_alpha_hbox := HBoxContainer.new()
	eff_alpha_hbox.add_theme_constant_override("separation", 4)
	_effect_alpha_buttons_container.add_child(eff_alpha_hbox)

	var eff_alpha_values: Array[Dictionary] = [
		{"label": "0%", "value": 0},
		{"label": "25%", "value": 64},
		{"label": "50%", "value": 128},
		{"label": "75%", "value": 191},
		{"label": "100%", "value": 255},
	]
	_effect_alpha_buttons.clear()
	for entry in eff_alpha_values:
		var alpha_btn := Button.new()
		alpha_btn.text = entry["label"]
		alpha_btn.size_flags_horizontal = SIZE_EXPAND_FILL
		alpha_btn.custom_minimum_size.y = 28
		alpha_btn.add_theme_font_size_override("font_size", FONT_HINT)
		var alpha_sb := StyleBoxFlat.new()
		alpha_sb.bg_color = Color(1, 1, 1, entry["value"] / 255.0)
		alpha_sb.border_width_left = 1
		alpha_sb.border_width_right = 1
		alpha_sb.border_width_top = 1
		alpha_sb.border_width_bottom = 1
		alpha_sb.border_color = C_BORDER
		alpha_sb.corner_radius_top_left = 3
		alpha_sb.corner_radius_top_right = 3
		alpha_sb.corner_radius_bottom_left = 3
		alpha_sb.corner_radius_bottom_right = 3
		alpha_btn.add_theme_stylebox_override("normal", alpha_sb)
		if entry["value"] > 128:
			alpha_btn.add_theme_color_override("font_color", Color.BLACK)
		else:
			alpha_btn.add_theme_color_override("font_color", Color.WHITE)
		alpha_btn.pressed.connect(_on_effect_alpha_level_btn.bind(entry["value"]))
		eff_alpha_hbox.add_child(alpha_btn)
		_effect_alpha_buttons.append(alpha_btn)

	# Brush size buttons row (effect)
	var eff_brush_label := Label.new()
	eff_brush_label.text = "Brush Size"
	eff_brush_label.add_theme_font_size_override("font_size", FONT_HINT)
	eff_brush_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_effect_alpha_buttons_container.add_child(eff_brush_label)

	var eff_brush_hbox := HBoxContainer.new()
	eff_brush_hbox.add_theme_constant_override("separation", 4)
	_effect_alpha_buttons_container.add_child(eff_brush_hbox)

	_effect_alpha_brush_buttons.clear()
	for bsize in [1, 3, 5]:
		var brush_btn := Button.new()
		brush_btn.text = "%dpx" % bsize
		brush_btn.size_flags_horizontal = SIZE_EXPAND_FILL
		brush_btn.custom_minimum_size.y = 28
		brush_btn.add_theme_font_size_override("font_size", FONT_HINT)
		brush_btn.pressed.connect(_on_effect_alpha_brush_size.bind(bsize))
		eff_brush_hbox.add_child(brush_btn)
		_effect_alpha_brush_buttons.append(brush_btn)
	_update_effect_alpha_brush_highlight()

	# Hint label
	var eff_alpha_hint := Label.new()
	eff_alpha_hint.text = "L-click on effect to paint alpha"
	eff_alpha_hint.add_theme_font_size_override("font_size", FONT_HINT)
	eff_alpha_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_effect_alpha_buttons_container.add_child(eff_alpha_hint)

	# Action buttons row
	var eff_alpha_actions := HBoxContainer.new()
	eff_alpha_actions.add_theme_constant_override("separation", 4)
	_effect_alpha_buttons_container.add_child(eff_alpha_actions)

	var eff_clear_btn := _make_button("Clear Mask", _on_clear_effect_alpha)
	eff_clear_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	eff_alpha_actions.add_child(eff_clear_btn)

	var eff_copy_btn := _make_button("Copy \u2192 Next", _on_copy_effect_alpha_to_next)
	eff_copy_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	eff_alpha_actions.add_child(eff_copy_btn)

	var eff_save_btn := _make_button("Save to Asset", _on_save_effect_alpha)
	eff_save_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	eff_alpha_actions.add_child(eff_save_btn)


func _build_echo_subsection() -> void:
	var parts: Array = _make_collapsible_section("Echo", _frame_section_wrapper)
	var section: VBoxContainer = parts[1]

	_echo_check = CheckButton.new()
	_echo_check.text = "Speed Echo"
	_echo_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_echo_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_echo_check.toggled.connect(_on_echo_toggled)
	section.add_child(_echo_check)

	_echo_settings_container = VBoxContainer.new()
	_echo_settings_container.add_theme_constant_override("separation", 4)
	_echo_settings_container.visible = false
	section.add_child(_echo_settings_container)

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


func _build_seq_and_save_sections() -> void:
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

	save_section.add_child(_make_label("Template ID (runtime)"))
	_template_id_input = LineEdit.new()
	_template_id_input.placeholder_text = "e.g. hilt_bash"
	_template_id_input.add_theme_font_size_override("font_size", FONT_LABEL)
	_template_id_input.add_theme_color_override("font_color", C_TEXT)
	_template_id_input.size_flags_horizontal = SIZE_EXPAND_FILL
	save_section.add_child(_template_id_input)

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
		var abs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			_set_status("Missing spritesheet: %s" % path)
			return

		var sheet_image := Image.new()
		var err := sheet_image.load(abs_path)
		if err != OK:
			_set_status("Failed to load: %s" % path)
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

	# Restore anchor pixels from SpriteFrames metadata (for stripped PNGs)
	_repaint_anchors_from_metadata()
	_on_spritesheet_loaded()


func _on_spritesheet_loaded() -> void:
	# Reset zoom/pan when loading new spritesheets
	_preview_zoom = 1.0
	_preview_pan = Vector2.ZERO
	_reposition_preview_sprite()

	# Enable spritesheet saving now that images are loaded
	if _save_spritesheets_btn:
		_save_spritesheets_btn.disabled = false

	# Initialize direction state and switch to "down"
	_preview_direction = "down"
	_edit_all_directions = false
	_switch_to_direction("down")
	_update_direction_highlight()


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

	# Update body clip mask tinted overlay (independent of weapon state)
	_update_body_clip_overlay()

	# Update anchor detection indicator
	_update_anchor_indicator()

	# Update echo ghosts
	_update_echo_preview()

	# Update crosshair overlay (anchor drawing mode)
	_update_crosshair_overlay()

	# Update onion weapon ghost (previous frame's weapon)
	_update_onion_weapon()

	# Update effect preview
	_update_effect_preview()


func _update_direction_highlight() -> void:
	# "All" button highlight
	var all_sb := StyleBoxFlat.new()
	all_sb.bg_color = Color("#B8860B") if _edit_all_directions else C_SURFACE
	all_sb.corner_radius_top_left = 4
	all_sb.corner_radius_top_right = 4
	all_sb.corner_radius_bottom_left = 4
	all_sb.corner_radius_bottom_right = 4
	all_sb.content_margin_left = 8
	all_sb.content_margin_right = 8
	all_sb.content_margin_top = 4
	all_sb.content_margin_bottom = 4
	_all_directions_btn.add_theme_stylebox_override("normal", all_sb)

	# Direction buttons
	for i in DIRECTIONS.size():
		var btn: Button = _direction_buttons[i]
		var is_active: bool = not _edit_all_directions and DIRECTIONS[i] == _preview_direction
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


func _on_all_directions_pressed() -> void:
	_edit_all_directions = true
	_preview_direction = "down"
	_switch_to_direction("down")
	_update_direction_highlight()


func _on_direction_pressed(dir: String) -> void:
	_edit_all_directions = false
	_preview_direction = dir
	_switch_to_direction(dir)
	_update_direction_highlight()


func _switch_to_direction(dir: String) -> void:
	if _current_composition == null:
		return
	var seq := _current_composition.get_sequence(dir)
	if seq == null:
		return
	_timeline_panel.sequence = seq
	# Update timeline thumbnails for this direction
	if _frame_textures.has(dir):
		var thumbs: Array[ImageTexture] = []
		for tex in _frame_textures[dir]:
			thumbs.append(tex)
		_timeline_panel.frame_thumbnails = thumbs
	else:
		_timeline_panel.frame_thumbnails = []
	# Clamp selection to new direction's frame count
	var max_idx := maxi(0, seq.frames.size() - 1)
	if _selected_frame > max_idx:
		_selected_frame = max_idx
		_selected_frames = [_selected_frame]
		_preview_frame_index = _selected_frame
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


const WEAPON_ANCHOR_COLOR := Color("#FF00AA")
const WEAPON_DIRECTION_COLOR := Color("#00FFFF")


func _update_weapon_preview() -> void:
	var seq := _active_sequence()
	if seq == null or _preview_frame_index < 0:
		_weapon_sprite.visible = false
		_weapon_debug = "no composition"
		return

	if _preview_frame_index >= seq.frames.size():
		_weapon_sprite.visible = false
		_weapon_debug = "frame out of range"
		return

	var frame := seq.frames[_preview_frame_index]

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

	# Compute rotation from grip → direction pixel, accounting for the weapon
	# texture's inherent orientation (grip→tip angle in the source image).
	var weapon_grip: Vector2 = _weapon_set.get("grip_right", Vector2.ZERO)
	var weapon_tip: Vector2 = _weapon_set.get("tip_right", Vector2.ZERO)
	var inherent_angle := atan2(weapon_tip.y - weapon_grip.y, weapon_tip.x - weapon_grip.x)

	var direction_px: Vector2 = anchors.get("direction", Vector2.INF)
	if direction_px != Vector2.INF:
		var desired_angle := atan2(direction_px.y - grip_px.y, direction_px.x - grip_px.x)
		_weapon_sprite.rotation = desired_angle - inherent_angle
	else:
		_weapon_sprite.rotation = 0.0

	# Position: grip pixel in image coords → viewport coords
	var anchor_offset := (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
	_weapon_sprite.position = _preview_sprite.position + anchor_offset

	# Offset: shift texture so the weapon grip point sits at the position
	if weapon_grip != Vector2.ZERO:
		var tex_size := weapon_tex.get_size()
		_weapon_sprite.offset = Vector2(tex_size.x / 2.0 - weapon_grip.x, tex_size.y / 2.0 - weapon_grip.y)
	else:
		_weapon_sprite.offset = Vector2.ZERO

	# Apply body clip mask visualization
	var clip_mask: Image = frame.body_clip_mask

	if clip_mask != null:
		# Clip weapon preview: hide weapon pixels that overlap body clip region
		var base_img := weapon_tex.get_image()
		if base_img != null:
			var composited := base_img.duplicate()
			var body_size := Vector2(_frame_size)
			var wp_rot := _weapon_sprite.rotation
			var wp_ofs := _weapon_sprite.offset
			# Weapon position relative to body center (in pixel space)
			var wp_pos := grip_px - body_size / 2.0
			for wy in range(composited.get_height()):
				for wx in range(composited.get_width()):
					var wpx: Color = composited.get_pixel(wx, wy)
					if wpx.a < 0.01:
						continue
					var weapon_local := Vector2(wx, wy) - Vector2(composited.get_width(), composited.get_height()) / 2.0 + wp_ofs
					var body_local: Vector2 = weapon_local.rotated(wp_rot) + wp_pos
					var body_px := Vector2i(
						int(body_local.x + body_size.x / 2.0),
						int(body_local.y + body_size.y / 2.0)
					)
					if body_px.x < 0 or body_px.x >= int(body_size.x):
						continue
					if body_px.y < 0 or body_px.y >= int(body_size.y):
						continue
					if body_px.x >= clip_mask.get_width() or body_px.y >= clip_mask.get_height():
						continue
					if clip_mask.get_pixel(body_px.x, body_px.y).r > 0.5:
						wpx.a = 0.0
						composited.set_pixel(wx, wy, wpx)
			_weapon_sprite.texture = ImageTexture.create_from_image(composited)

	# Weapon always in front — no z-ordering toggle
	_weapon_sprite.z_index = 1
	_weapon_sprite.modulate = Color(1.0, 1.0, 1.0, 0.9)
	var angle_deg := rad_to_deg(_weapon_sprite.rotation)
	_weapon_debug = "OK %.0fdeg pos=%s" % [angle_deg, str(_weapon_sprite.position)]


func _update_body_clip_overlay() -> void:
	if not _body_clip_paint_enabled:
		return
	var seq := _active_sequence()
	if seq == null or _preview_frame_index < 0 or _preview_frame_index >= seq.frames.size():
		return
	var clip_mask: Image = seq.frames[_preview_frame_index].body_clip_mask
	if clip_mask == null:
		return
	var body_images: Array = _frame_images.get(_preview_direction, [])
	if _preview_frame_index >= body_images.size():
		return
	var body_img: Image = body_images[_preview_frame_index].duplicate()
	for y in range(mini(body_img.get_height(), clip_mask.get_height())):
		for x in range(mini(body_img.get_width(), clip_mask.get_width())):
			if clip_mask.get_pixel(x, y).r > 0.5:
				var px: Color = body_img.get_pixel(x, y)
				px = px.lerp(Color(1.0, 0.2, 0.2, px.a), 0.4)
				body_img.set_pixel(x, y, px)
	_preview_sprite.texture = ImageTexture.create_from_image(body_img)


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


## Re-paint anchor pixels from SpriteFrames metadata onto loaded body images.
## After PNGs are stripped of colored pixels, this restores them for editing.
func _repaint_anchors_from_metadata() -> void:
	if _frame_images.is_empty() or _current_anim.is_empty():
		return
	# Try to load the SpriteFrames resource that may contain anchor metadata
	var sf_path := "res://resources/player_sprites.tres"
	if not ResourceLoader.exists(sf_path):
		return
	var sf: SpriteFrames = load(sf_path)
	if sf == null:
		return
	var anchor_data: Dictionary = sf.get_meta("anchor_data", {})
	if anchor_data.is_empty():
		return

	var total_repainted := 0
	for direction in DIRECTIONS:
		if not _frame_images.has(direction):
			continue
		# Build the animation name: {anim_folder_lowercase}_{direction}
		var anim_name := _current_anim.to_lower() + "_" + direction
		var anim_anchors: Dictionary = anchor_data.get(anim_name, {})
		if anim_anchors.is_empty():
			continue
		var dir_repainted := 0
		var images: Array = _frame_images[direction]
		for fi in range(images.size()):
			var frame_data: Dictionary = anim_anchors.get(str(fi), {})
			if frame_data.has("grip"):
				var gp: Array = frame_data["grip"]
				if gp[0] >= 0 and gp[0] < images[fi].get_width() and gp[1] >= 0 and gp[1] < images[fi].get_height():
					images[fi].set_pixel(gp[0], gp[1], WEAPON_ANCHOR_COLOR)
					dir_repainted += 1
			if frame_data.has("direction"):
				var dp: Array = frame_data["direction"]
				if dp[0] >= 0 and dp[0] < images[fi].get_width() and dp[1] >= 0 and dp[1] < images[fi].get_height():
					images[fi].set_pixel(dp[0], dp[1], WEAPON_DIRECTION_COLOR)
					dir_repainted += 1
		# Refresh textures only for directions that had pixels repainted
		if dir_repainted > 0 and _frame_textures.has(direction):
			var new_textures: Array[ImageTexture] = []
			for img: Image in images:
				new_textures.append(ImageTexture.create_from_image(img))
			_frame_textures[direction] = new_textures
		total_repainted += dir_repainted
	if total_repainted > 0:
		_set_status("Restored %d anchor pixels from SpriteFrames metadata." % total_repainted)


func _update_echo_preview() -> void:
	# Clear old echoes
	for ghost in _echo_sprites:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_echo_sprites.clear()

	var seq := _active_sequence()
	if seq == null or _preview_frame_index < 0:
		return
	if _preview_frame_index >= seq.frames.size():
		return

	var frame := seq.frames[_preview_frame_index]
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
	# Center the sprite in the viewport, offset by pan
	var center := vp_size / 2.0 + _preview_pan
	_preview_sprite.position = center

	# Scale to fit within the viewport with some padding (80%), then apply zoom
	if _frame_size != Vector2i.ZERO:
		var scale_x := (vp_size.x * 0.8) / float(_frame_size.x)
		var scale_y := (vp_size.y * 0.8) / float(_frame_size.y)
		var uniform_scale := minf(scale_x, scale_y)
		# Snap to integer scale if possible for crisp pixel art
		if uniform_scale >= 2.0:
			uniform_scale = floorf(uniform_scale)
		_preview_sprite.scale = Vector2(uniform_scale, uniform_scale) * _preview_zoom
	else:
		_preview_sprite.scale = Vector2.ONE * _preview_zoom

	# Update zoom label
	if _zoom_label:
		if absf(_preview_zoom - 1.0) < 0.01:
			_zoom_label.text = ""
		else:
			_zoom_label.text = "%.0f%%" % (_preview_zoom * 100.0)

	# Reposition weapon, echo ghosts, crosshair, onion skin, and effect too
	_update_weapon_preview()
	_update_echo_preview()
	_update_crosshair_overlay()
	_update_onion_weapon()
	_update_effect_preview()


func _on_zoom_reset() -> void:
	_preview_zoom = 1.0
	_preview_pan = Vector2.ZERO
	_reposition_preview_sprite()


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
	var seq := _active_sequence()
	if seq == null:
		return
	var max_frame := seq.frames.size() - 1
	_preview_frame_index = min(max_frame, _preview_frame_index + 1)
	_selected_frame = _preview_frame_index
	_selected_frames = [_selected_frame]
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.selected_frames = _selected_frames
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


func show_frame(index: int) -> void:
	var seq := _active_sequence()
	if seq == null:
		return
	_preview_frame_index = clampi(index, 0, seq.frames.size() - 1)
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


func _on_timeline_effect_toggled(index: int) -> void:
	var active_seq := _active_sequence()
	if active_seq == null or index < 0 or index >= active_seq.frames.size():
		return
	_push_undo()
	# Determine the new effect_id from the active direction's current state
	var active_frame := active_seq.frames[index]
	var new_effect_id := ""
	if not active_frame.effect_id.is_empty():
		new_effect_id = ""  # Toggle off
	else:
		# Apply the currently selected effect from the dropdown
		var sel := _effect_dropdown.selected
		if sel > 0:
			var text := _effect_dropdown.get_item_text(sel)
			if text.begins_with("[Asset] "):
				new_effect_id = text.substr(8)
			elif text.begins_with("[Placeholder] "):
				new_effect_id = text.substr(14)
			else:
				new_effect_id = text
	# Apply to all edit directions
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq and index < seq.frames.size():
			seq.frames[index].effect_id = new_effect_id
	_timeline_panel.queue_redraw()
	if index == _preview_frame_index:
		_update_effect_preview()
		_update_frame_props_ui()


func _on_timeline_effect_moved(from_index: int, to_index: int) -> void:
	var active_seq := _active_sequence()
	if active_seq == null:
		return
	if from_index < 0 or from_index >= active_seq.frames.size():
		return
	if to_index < 0 or to_index >= active_seq.frames.size():
		return
	_push_undo()
	# Move effect data in all edit directions
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null or from_index >= seq.frames.size() or to_index >= seq.frames.size():
			continue
		var src := seq.frames[from_index]
		var dst := seq.frames[to_index]
		dst.effect_id = src.effect_id
		dst.effect_anchor = src.effect_anchor
		dst.effect_offset = src.effect_offset
		dst.effect_z_index = src.effect_z_index
		dst.effect_rotation_deg = src.effect_rotation_deg
		src.effect_id = ""
		src.effect_anchor = "weapon_tip"
		src.effect_offset = Vector2.ZERO
		src.effect_z_index = 2
		src.effect_rotation_deg = 0.0
	_timeline_panel.queue_redraw()
	if _preview_frame_index == from_index or _preview_frame_index == to_index:
		_update_effect_preview()
		_update_frame_props_ui()



func _on_timeline_echo_toggled(index: int) -> void:
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq and index < seq.frames.size():
			seq.frames[index].echo_enabled = not seq.frames[index].echo_enabled
	_timeline_panel.queue_redraw()
	if index == _preview_frame_index:
		_update_frame_props_ui()


func _on_timeline_damage_moved(index: int) -> void:
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq:
			seq.damage_frame = index
	_timeline_panel.queue_redraw()
	_update_frame_props_ui()


func _on_timeline_scrollbar_changed(value: float) -> void:
	_timeline_panel.set_scroll_from_scrollbar(value)


func _on_timeline_scroll_changed(offset_ms: float, total_ms: float, visible_ms: float) -> void:
	_timeline_scrollbar.max_value = maxf(total_ms, visible_ms)
	_timeline_scrollbar.page = visible_ms
	_timeline_scrollbar.set_value_no_signal(offset_ms)


func _on_timeline_duration_changed(_index: int, _new_ms: int) -> void:
	# Timeline handles redraw internally; just update status
	var seq := _active_sequence()
	if seq:
		var total := seq.get_total_duration_sec()
		_set_status("Total: %.3fs" % total)


func _on_timeline_playhead_moved(ms: float) -> void:
	# Determine which frame the playhead is in
	var seq := _active_sequence()
	if seq == null:
		return
	var cumulative := 0.0
	for i in seq.frames.size():
		cumulative += seq.frames[i].duration_ms
		if ms < cumulative:
			_preview_frame_index = i
			_selected_frame = i
			_selected_frames = [i]
			_update_preview_frame()
			return


# ── Frame property handlers ────────────────────────────────────────────

func _update_frame_props_ui() -> void:
	var seq := _active_sequence()
	var has_data := seq != null and _selected_frame >= 0 and _selected_frame < seq.frames.size()
	# Show/hide the wrapper containers
	_frame_section_wrapper.visible = has_data
	var seq_wrapper := _seq_props_container.get_parent()
	seq_wrapper.visible = has_data
	if not has_data:
		return

	var frame := seq.frames[_selected_frame]

	# Block signals during UI update to avoid feedback loops
	_duration_spinbox.set_value_no_signal(frame.duration_ms)
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(frame.duration_ms, 1))
	_echo_check.set_pressed_no_signal(frame.echo_enabled)
	_echo_settings_container.visible = frame.echo_enabled
	_echo_count_spin.set_value_no_signal(frame.echo_count)
	_echo_opacity_start_slider.set_value_no_signal(frame.echo_opacity_start)
	_echo_opacity_end_slider.set_value_no_signal(frame.echo_opacity_end)
	_echo_spacing_spin.set_value_no_signal(frame.echo_spacing_px)

	# Effect
	_effect_offset_x.set_value_no_signal(frame.effect_offset.x)
	_effect_offset_y.set_value_no_signal(frame.effect_offset.y)
	_effect_z_index_spin.set_value_no_signal(frame.effect_z_index)
	_effect_rotation_spin.set_value_no_signal(frame.effect_rotation_deg)
	# Select effect anchor
	for i in _effect_anchor_dropdown.item_count:
		if _effect_anchor_dropdown.get_item_text(i) == frame.effect_anchor:
			_effect_anchor_dropdown.select(i)
			break
	# Sync effect dropdown to current frame's effect_id
	if frame.effect_id.is_empty():
		_effect_dropdown.select(0)  # "(none)"
	else:
		var found := false
		for i in _effect_dropdown.item_count:
			var text := _effect_dropdown.get_item_text(i)
			if text == "[Asset] " + frame.effect_id or text == "[Placeholder] " + frame.effect_id:
				_effect_dropdown.select(i)
				found = true
				break
		if not found:
			_effect_dropdown.select(0)

	# Sequence props — read from active direction's sequence
	var max_idx := seq.frames.size() - 1
	_movement_start_spin.max_value = max_idx
	_movement_end_spin.max_value = max_idx
	_damage_frame_spin.max_value = max_idx
	_movement_distance_spin.set_value_no_signal(seq.movement_distance)
	_movement_start_spin.set_value_no_signal(seq.movement_start_frame)
	_movement_end_spin.set_value_no_signal(seq.movement_end_frame)
	_damage_frame_spin.set_value_no_signal(seq.damage_frame)

	# Movement type
	var mt := seq.movement_type
	for i in _movement_type_dropdown.item_count:
		if _movement_type_dropdown.get_item_text(i) == (mt if mt != "" else "none"):
			_movement_type_dropdown.select(i)
			break

	_total_duration_label.text = "Total: %.3fs" % seq.get_total_duration_sec()


func _get_target_frames() -> Array[int]:
	if _selected_frames.size() > 1:
		return _selected_frames
	if _selected_frame >= 0:
		return [_selected_frame]
	return []


## Returns the active DirectionSequence for the current preview direction.
func _active_sequence() -> DirectionSequence:
	if _current_composition == null:
		return null
	return _current_composition.get_sequence(_preview_direction)


## Returns direction keys to edit: all 3 if "All" mode, else just the active one.
func _edit_directions() -> Array[String]:
	if _edit_all_directions:
		return AttackCompositionData.DIRECTIONS.duplicate()
	return [_preview_direction]


## Apply a callable to target frames across all edit directions.
## The callable receives a CompositionFrame as its argument.
func _apply_to_target_frames(callable: Callable) -> void:
	var indices := _get_target_frames()
	if indices.is_empty() or _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		for idx in indices:
			if idx < seq.frames.size():
				callable.call(seq.frames[idx])


func _on_duration_changed(value: float) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.duration_ms = int(value))
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(value, 1))
	var seq := _active_sequence()
	if seq:
		_total_duration_label.text = "Total: %.3fs" % seq.get_total_duration_sec()
	_timeline_panel.queue_redraw()
	_timeline_panel._emit_scroll_changed()




func _on_effect_selected(index: int) -> void:
	var text := _effect_dropdown.get_item_text(index)
	var effect_id := ""
	if text != "(none)":
		if text.begins_with("[Asset] "):
			effect_id = text.substr(8)
		elif text.begins_with("[Placeholder] "):
			effect_id = text.substr(14)
		else:
			effect_id = text
	_apply_to_target_frames(func(frame: CompositionFrame): frame.effect_id = effect_id)
	_timeline_panel.queue_redraw()
	_update_effect_preview()


func _on_effect_anchor_selected(index: int) -> void:
	var anchor_text := _effect_anchor_dropdown.get_item_text(index)
	_apply_to_target_frames(func(frame: CompositionFrame): frame.effect_anchor = anchor_text)
	_update_effect_preview()


func _on_effect_offset_changed(_value: float) -> void:
	var offset := Vector2(_effect_offset_x.value, _effect_offset_y.value)
	_apply_to_target_frames(func(frame: CompositionFrame): frame.effect_offset = offset)
	_update_effect_preview()


func _on_effect_z_index_changed(value: float) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.effect_z_index = int(value))
	_update_effect_preview()


func _on_effect_rotation_changed(value: float) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.effect_rotation_deg = value)
	_update_effect_preview()


func _on_echo_toggled(pressed: bool) -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.echo_enabled = pressed)
	_echo_settings_container.visible = pressed
	_timeline_panel.queue_redraw()


func _on_echo_setting_changed(_value: float) -> void:
	var count := int(_echo_count_spin.value)
	var op_start := _echo_opacity_start_slider.value
	var op_end := _echo_opacity_end_slider.value
	var spacing := _echo_spacing_spin.value
	_apply_to_target_frames(func(frame: CompositionFrame):
		frame.echo_count = count
		frame.echo_opacity_start = op_start
		frame.echo_opacity_end = op_end
		frame.echo_spacing_px = spacing
	)


func _on_movement_type_selected(index: int) -> void:
	if _current_composition == null:
		return
	_push_undo()
	var text := _movement_type_dropdown.get_item_text(index)
	var mt: String = "" if text == "none" else text
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq:
			seq.movement_type = mt
	_timeline_panel.queue_redraw()


func _on_seq_prop_changed(_value: float) -> void:
	if _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq:
			seq.movement_distance = _movement_distance_spin.value
			seq.movement_start_frame = int(_movement_start_spin.value)
			seq.movement_end_frame = int(_movement_end_spin.value)
	_timeline_panel.queue_redraw()


func _on_damage_frame_changed(value: float) -> void:
	if _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq:
			seq.damage_frame = int(value)
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
	var template_id := _get_runtime_template_id()
	var images: Array = _frame_images.get(_preview_direction, [])
	var data := CompositionConverter.convert(_current_composition, _preview_direction, images)
	data.template_id = template_id
	var output := CompositionConverter.phases_to_string(data)
	print("=== Generated Runtime Data for '%s' dir=%s (template: %s) ===" % [_current_composition.composition_id, _preview_direction, template_id])
	print(output)
	_set_status("Generated %d phases for template '%s' (%s). Check output panel." % [data.phases.size(), template_id, _preview_direction])


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


func _get_runtime_template_id() -> String:
	## Returns the template ID for runtime export.
	## Uses the Template ID field if set, otherwise falls back to composition_id.
	var custom_id := _template_id_input.text.strip_edges()
	if not custom_id.is_empty():
		# Also persist to composition so it's saved
		_current_composition.runtime_template_id = custom_id
		return custom_id
	if not _current_composition.runtime_template_id.is_empty():
		return _current_composition.runtime_template_id
	return _current_composition.composition_id


func _on_save_runtime() -> void:
	if _current_composition == null:
		_set_status("No composition loaded.")
		return
	_ensure_dirs()
	var template_id := _get_runtime_template_id()
	var saved_count := 0
	for dir_name in AttackCompositionData.DIRECTIONS:
		var images: Array = _frame_images.get(dir_name, [])
		var data := CompositionConverter.convert(_current_composition, dir_name, images)
		data.template_id = template_id
		var path := "%s/%s_%s.tres" % [SEQUENCES_DIR, template_id, dir_name]
		var err := ResourceSaver.save(data, path)
		if err == OK:
			saved_count += 1
		else:
			_set_status("Error saving runtime data for %s: %s" % [dir_name, error_string(err)])
			return
	_set_status("Saved runtime data for %d directions to %s/" % [saved_count, SEQUENCES_DIR])


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

	# Migrate from legacy flat format if needed
	comp.migrate_from_legacy()
	comp.ensure_all_directions()

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
		_current_composition = comp
		_selected_frame = 0
		_selected_frames = [0]
		_preview_frame_index = 0
		_undo_stack.clear()
		_update_undo_button()
		_preview_direction = "down"
		_edit_all_directions = false
		_switch_to_direction("down")
		_update_direction_highlight()
		return

	# Load spritesheets for all directions
	_frame_images.clear()
	_frame_textures.clear()
	var frame_count := -1

	for direction in DIRECTIONS:
		var sheet_path := "%s/%s/%s_%s.png" % [SPRITES_BASE, anim_folder, model_name, direction]
		var abs_sheet_path := ProjectSettings.globalize_path(sheet_path)
		if not FileAccess.file_exists(abs_sheet_path):
			_set_status("Missing spritesheet: %s" % sheet_path)
			return

		var sheet_image := Image.new()
		var err := sheet_image.load(abs_sheet_path)
		if err != OK:
			_set_status("Failed to load: %s" % sheet_path)
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

	# Sync template ID field from saved composition
	_template_id_input.text = comp.runtime_template_id

	_load_info_label.text = "Loaded: %s (%d frames, %dx%d)" % [anim_folder, frame_count, _frame_size.x, _frame_size.y]
	# Restore anchor pixels from SpriteFrames metadata (for stripped PNGs)
	_repaint_anchors_from_metadata()
	_on_spritesheet_loaded()
	_set_status("Loaded composition '%s' with spritesheets." % composition_id)


# ── Anchor Painting ───────────────────────────────────────────────────

func _on_preview_viewport_input(event: InputEvent) -> void:
	# ── Zoom (mouse wheel) ────────────────────────────────────────────
	if event is InputEventMouseButton:
		var mb_zoom := event as InputEventMouseButton
		if mb_zoom.pressed and (mb_zoom.button_index == MOUSE_BUTTON_WHEEL_UP or mb_zoom.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var zoom_dir := 1.0 if mb_zoom.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			var old_zoom := _preview_zoom
			_preview_zoom = clampf(_preview_zoom + zoom_dir * 0.25 * _preview_zoom, 0.5, 20.0)
			# Zoom toward cursor position for natural feel
			var container_size := _viewport_container_ref.size
			var vp_size := Vector2(_preview_viewport.size)
			if container_size.x > 0 and container_size.y > 0:
				var vp_cursor := mb_zoom.position * (vp_size / container_size)
				var vp_center := vp_size / 2.0
				# Adjust pan so the point under the cursor stays fixed
				var zoom_ratio := _preview_zoom / old_zoom
				_preview_pan = vp_cursor - (vp_cursor - vp_center - _preview_pan) * zoom_ratio - vp_center
			_reposition_preview_sprite()
			_viewport_container_ref.accept_event()
			return

	# ── Pan (middle-click drag) ───────────────────────────────────────
	if event is InputEventMouseButton:
		var mb_pan := event as InputEventMouseButton
		if mb_pan.button_index == MOUSE_BUTTON_MIDDLE:
			if mb_pan.pressed:
				_pan_dragging = true
				_pan_drag_start = mb_pan.position
			else:
				_pan_dragging = false
			_viewport_container_ref.accept_event()
			return
	if event is InputEventMouseMotion and _pan_dragging:
		var motion := event as InputEventMouseMotion
		var container_size := _viewport_container_ref.size
		var vp_size := Vector2(_preview_viewport.size)
		if container_size.x > 0 and container_size.y > 0:
			_preview_pan += motion.relative * (vp_size / container_size)
		_reposition_preview_sprite()
		_viewport_container_ref.accept_event()
		return

	# Body clip mask painting mode (handles click + drag)
	if _body_clip_paint_enabled:
		var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var is_drag: bool = event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if is_click or is_drag:
			var pos: Vector2 = event.position
			var body_px := _viewport_to_body_pixel(pos)
			if body_px != Vector2i(-1, -1):
				if is_click:
					_push_undo()
				_paint_body_clip(body_px.x, body_px.y)
				_viewport_container_ref.accept_event()
			return

	# Alpha painting mode — effect (handles click + drag)
	if _effect_alpha_paint_enabled:
		var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var is_drag: bool = event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if is_click or is_drag:
			var pos: Vector2 = event.position
			var effect_px := _viewport_to_effect_pixel(pos)
			if effect_px != Vector2i(-1, -1):
				if is_click:
					_push_undo()
				_paint_effect_alpha(effect_px.x, effect_px.y)
				_viewport_container_ref.accept_event()
			return

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


func _on_body_clip_draw_toggled(enabled: bool) -> void:
	_body_clip_paint_enabled = enabled
	_body_clip_buttons_container.visible = enabled
	_update_preview_frame()


func _on_generate_body_clip_from_body() -> void:
	var indices := _get_target_frames()
	if indices.is_empty() or _current_composition == null:
		return
	_push_undo()
	for dir_name in _edit_directions():
		var seq := _current_composition.get_sequence(dir_name)
		if seq == null:
			continue
		var images: Array = _frame_images.get(dir_name, [])
		for idx in indices:
			if idx < seq.frames.size() and idx < images.size():
				seq.frames[idx].body_clip_mask = CompositionConverter._generate_body_clip_mask(images[idx])
	_update_preview_frame()
	_set_status("Body clip mask generated from body alpha for %d frame(s)." % indices.size())


func _on_body_clip_brush_size(bsize: int) -> void:
	_body_clip_brush_size = bsize
	_update_body_clip_brush_highlight()


func _update_body_clip_brush_highlight() -> void:
	for i in _body_clip_brush_buttons.size():
		var btn := _body_clip_brush_buttons[i]
		var sizes := [1, 3, 5]
		if i < sizes.size() and sizes[i] == _body_clip_brush_size:
			btn.add_theme_color_override("font_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")


func _on_clear_body_clip() -> void:
	_apply_to_target_frames(func(frame: CompositionFrame): frame.body_clip_mask = null)
	_update_preview_frame()


func _on_copy_body_clip_to_next() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	if frame.body_clip_mask == null:
		_set_status("No body clip mask on current frame to copy.")
		return
	var next_idx := _selected_frame + 1
	if next_idx >= seq.frames.size():
		_set_status("No next frame to copy to.")
		return
	_push_undo()
	seq.frames[next_idx].body_clip_mask = frame.body_clip_mask.duplicate()
	_set_status("Body clip mask copied to frame %d." % next_idx)


func _viewport_to_weapon_pixel(container_pos: Vector2) -> Vector2i:
	if _weapon_sprite == null or not _weapon_sprite.visible or _weapon_sprite.texture == null:
		return Vector2i(-1, -1)
	var container_size := _viewport_container_ref.size
	var vp_size := Vector2(_preview_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return Vector2i(-1, -1)
	# Container -> viewport coords
	var vp_click := container_pos * (vp_size / container_size)
	# Viewport -> weapon local space (undo position, rotation, scale)
	var local := (vp_click - _weapon_sprite.position).rotated(-_weapon_sprite.rotation) / _weapon_sprite.scale
	# Local space -> texture pixel (undo offset and centering)
	var tex_size := Vector2(_weapon_sprite.texture.get_size())
	var tex_px := local - _weapon_sprite.offset + tex_size / 2.0
	var px := int(tex_px.x)
	var py := int(tex_px.y)
	if px < 0 or px >= int(tex_size.x) or py < 0 or py >= int(tex_size.y):
		return Vector2i(-1, -1)
	return Vector2i(px, py)


func _viewport_to_body_pixel(container_pos: Vector2) -> Vector2i:
	if _preview_sprite == null or _preview_sprite.texture == null:
		return Vector2i(-1, -1)
	var container_size := _viewport_container_ref.size
	var vp_size := Vector2(_preview_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return Vector2i(-1, -1)
	# Container -> viewport coords
	var vp_click := container_pos * (vp_size / container_size)
	# Viewport -> body local space (undo position and scale; body has no rotation)
	var local := (vp_click - _preview_sprite.position) / _preview_sprite.scale
	# Local space -> body frame pixel (undo centering)
	var frame_px := local + Vector2(_frame_size) / 2.0
	var px := int(frame_px.x)
	var py := int(frame_px.y)
	if px < 0 or px >= _frame_size.x or py < 0 or py >= _frame_size.y:
		return Vector2i(-1, -1)
	return Vector2i(px, py)


func _paint_body_clip(px: int, py: int) -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	# Get body frame to check if pixel has content
	var images: Array = _frame_images.get(_preview_direction, [])
	if _preview_frame_index < 0 or _preview_frame_index >= images.size():
		return
	var body_img: Image = images[_preview_frame_index]
	var w := body_img.get_width()
	var h := body_img.get_height()
	# Only paint on non-transparent body pixels
	if body_img.get_pixel(px, py).a < 0.01:
		return
	# Initialize mask if needed
	if frame.body_clip_mask == null:
		frame.body_clip_mask = Image.create(w, h, false, Image.FORMAT_R8)
		frame.body_clip_mask.fill(Color(0, 0, 0))  # Default: no clip
	var radius := (_body_clip_brush_size - 1) / 2
	var paint_color: Color
	if _body_clip_paint_erase:
		paint_color = Color(0, 0, 0)  # Erase: no clip
	else:
		paint_color = Color(1, 0, 0)  # Paint: clip (R=255)
	for bx in range(px - radius, px + radius + 1):
		for by in range(py - radius, py + radius + 1):
			if bx < 0 or bx >= w or by < 0 or by >= h:
				continue
			if body_img.get_pixel(bx, by).a < 0.01:
				continue  # Only paint on visible body pixels
			frame.body_clip_mask.set_pixel(bx, by, paint_color)
	_update_preview_frame()


# ── Effect alpha painting ────────────────────────────────────────────

func _on_effect_alpha_draw_toggled(enabled: bool) -> void:
	_effect_alpha_paint_enabled = enabled
	_effect_alpha_buttons_container.visible = enabled
	_update_effect_preview()


func _on_effect_alpha_level_btn(value: int) -> void:
	_effect_alpha_paint_value = value


func _on_effect_alpha_brush_size(bsize: int) -> void:
	_effect_alpha_brush_size = bsize
	_update_effect_alpha_brush_highlight()


func _update_effect_alpha_brush_highlight() -> void:
	for i in _effect_alpha_brush_buttons.size():
		var btn := _effect_alpha_brush_buttons[i]
		var sizes := [1, 3, 5]
		if i < sizes.size() and sizes[i] == _effect_alpha_brush_size:
			btn.add_theme_color_override("font_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")


func _on_clear_effect_alpha() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	_push_undo()
	var frame := seq.frames[_selected_frame]
	frame.effect_alpha_mask = null
	_update_effect_preview()


func _on_copy_effect_alpha_to_next() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	if frame.effect_alpha_mask == null:
		_set_status("No effect alpha mask on current frame to copy.")
		return
	var next_idx := _selected_frame + 1
	if next_idx >= seq.frames.size():
		_set_status("No next frame to copy to.")
		return
	_push_undo()
	seq.frames[next_idx].effect_alpha_mask = frame.effect_alpha_mask.duplicate()
	_set_status("Effect alpha mask copied to frame %d." % next_idx)


func _on_save_effect_alpha() -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	if frame.effect_alpha_mask == null:
		_set_status("No effect alpha mask to save.")
		return
	if frame.effect_id.is_empty():
		_set_status("No effect assigned to save mask for.")
		return
	var dir_path: String = EFFECTS_DIR + "/" + frame.effect_id
	var save_path: String = dir_path + "/alpha_mask.png"
	var global_path := ProjectSettings.globalize_path(save_path)
	var err := frame.effect_alpha_mask.save_png(global_path)
	if err == OK:
		# Invalidate cache so it reloads with the new mask
		_effect_cache.erase(frame.effect_id)
		_set_status("Effect alpha mask saved to %s" % save_path)
	else:
		_set_status("Failed to save effect alpha mask (error %d)" % err)


func _viewport_to_effect_pixel(container_pos: Vector2) -> Vector2i:
	if _effect_sprite == null or not _effect_sprite.visible or _effect_sprite.texture == null:
		return Vector2i(-1, -1)
	var container_size := _viewport_container_ref.size
	var vp_size := Vector2(_preview_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return Vector2i(-1, -1)
	# Container -> viewport coords
	var vp_click := container_pos * (vp_size / container_size)
	# Viewport -> effect local space (undo position, rotation, scale)
	var local := (vp_click - _effect_sprite.position).rotated(-_effect_sprite.rotation) / _effect_sprite.scale
	# Local space -> texture pixel (effect sprite is centered)
	var tex_size := Vector2(_effect_sprite.texture.get_size())
	var tex_px := local + tex_size / 2.0
	var px := int(tex_px.x)
	var py := int(tex_px.y)
	if px < 0 or px >= int(tex_size.x) or py < 0 or py >= int(tex_size.y):
		return Vector2i(-1, -1)
	return Vector2i(px, py)


func _paint_effect_alpha(px: int, py: int) -> void:
	var seq := _active_sequence()
	if seq == null or _selected_frame < 0 or _selected_frame >= seq.frames.size():
		return
	var frame := seq.frames[_selected_frame]
	if frame.effect_id.is_empty():
		return
	var assets := _load_effect_assets(frame.effect_id)
	if assets.is_empty():
		return
	var frame_size: int = assets["frame_size"]
	# Get source image for transparency check
	var sheet_img: Image = null
	var sheet_tex: Texture2D = assets.get("sheet_texture")
	if sheet_tex != null:
		sheet_img = sheet_tex.get_image()
	# Initialize mask if needed
	if frame.effect_alpha_mask == null:
		frame.effect_alpha_mask = Image.create(frame_size, frame_size, false, Image.FORMAT_R8)
		frame.effect_alpha_mask.fill(Color(1, 1, 1))
	var radius := (_effect_alpha_brush_size - 1) / 2
	var paint_color := Color(_effect_alpha_paint_value / 255.0, 0, 0)
	for bx in range(px - radius, px + radius + 1):
		for by in range(py - radius, py + radius + 1):
			if bx < 0 or bx >= frame_size or by < 0 or by >= frame_size:
				continue
			if sheet_img != null and bx < sheet_img.get_width() and by < sheet_img.get_height():
				if sheet_img.get_pixel(bx, by).a < 0.01:
					continue  # Only paint on non-transparent effect pixels
			frame.effect_alpha_mask.set_pixel(bx, by, paint_color)
	_update_effect_preview()


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
	var seq := _active_sequence()
	if seq == null or _preview_frame_index >= seq.frames.size():
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

	# Compute rotation from grip → direction pixel, subtracting the weapon's
	# inherent grip→tip angle (same formula as _update_weapon_preview)
	var weapon_grip: Vector2 = _weapon_set.get("grip_right", Vector2.ZERO)
	var weapon_tip: Vector2 = _weapon_set.get("tip_right", Vector2.ZERO)
	var inherent_angle := atan2(weapon_tip.y - weapon_grip.y, weapon_tip.x - weapon_grip.x)

	var direction_px: Vector2 = anchors.get("direction", Vector2.INF)
	if direction_px != Vector2.INF:
		var desired_angle := atan2(direction_px.y - grip_px.y, direction_px.x - grip_px.x)
		_onion_weapon_sprite.rotation = desired_angle - inherent_angle
	else:
		_onion_weapon_sprite.rotation = 0.0

	# Position: grip pixel → viewport coords
	var anchor_offset := (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
	_onion_weapon_sprite.position = _preview_sprite.position + anchor_offset

	# Offset weapon so grip point sits at the anchor position
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
	var meta: Variant = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if not meta is Dictionary or not meta.has("grip") or not meta.has("tip"):
		return {}

	var grip := Vector2(float(meta["grip"][0]), float(meta["grip"][1]))
	var tip := Vector2(float(meta["tip"][0]), float(meta["tip"][1]))

	# Load optional global alpha mask
	var alpha_mask: Image = null
	var alpha_path: String = dir_path + "/alpha_mask.png"
	if FileAccess.file_exists(alpha_path):
		alpha_mask = Image.load_from_file(ProjectSettings.globalize_path(alpha_path))

	# Return same format as PlaceholderWeaponSprites sets.
	# Single texture for all directions (rotation handled by anchor system).
	return {
		"down": tex, "up": tex, "right": tex,
		"grip_down": grip, "grip_up": grip, "grip_right": grip,
		"tip_down": tip, "tip_up": tip, "tip_right": tip,
		"alpha_mask": alpha_mask,
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


func _load_effect_assets(effect_id: String) -> Dictionary:
	if _effect_cache.has(effect_id):
		return _effect_cache[effect_id]

	var dir_path: String = EFFECTS_DIR + "/" + effect_id
	var meta_path: String = dir_path + "/metadata.json"
	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	if meta_file == null:
		return {}
	var meta: Variant = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if not meta is Dictionary:
		return {}

	var frame_count: int = int(meta.get("frame_count", 1))
	var frame_size: int = int(meta.get("frame_size", 32))
	var fps: float = float(meta.get("fps", 12.0))

	# Load the directional spritesheet — prefer current preview direction, fall back to "down"
	var sheet_name: String = "%s_%s.png" % [effect_id, _preview_direction]
	var sheet_path: String = dir_path + "/" + sheet_name
	if not FileAccess.file_exists(sheet_path):
		sheet_name = "%s_down.png" % effect_id
		sheet_path = dir_path + "/" + sheet_name
	if not FileAccess.file_exists(sheet_path):
		return {}

	# Load through Godot's import pipeline (same as runtime) so the composer
	# preview matches in-game rendering (import settings like fix_alpha_border apply).
	var raw_tex: Texture2D = load(sheet_path)
	if raw_tex == null:
		return {}
	var sheet_img: Image = raw_tex.get_image()
	if sheet_img == null:
		return {}
	var sheet_tex := ImageTexture.create_from_image(sheet_img)

	# Build an AtlasTexture for the first frame
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet_tex
	atlas.region = Rect2(0, 0, frame_size, frame_size)

	# Load optional global alpha mask
	var alpha_mask: Image = null
	var alpha_path: String = dir_path + "/alpha_mask.png"
	if FileAccess.file_exists(alpha_path):
		alpha_mask = Image.load_from_file(ProjectSettings.globalize_path(alpha_path))

	var result := {
		"texture": atlas,
		"sheet_texture": sheet_tex,
		"frame_count": frame_count,
		"frame_size": frame_size,
		"fps": fps,
		"direction": _preview_direction,
		"alpha_mask": alpha_mask,
	}
	_effect_cache[effect_id] = result
	return result


func _update_effect_preview() -> void:
	var seq := _active_sequence()
	if seq == null or _preview_frame_index < 0:
		_effect_sprite.visible = false
		return
	if _preview_frame_index >= seq.frames.size():
		_effect_sprite.visible = false
		return

	var frame := seq.frames[_preview_frame_index]
	if frame.effect_id.is_empty():
		_effect_sprite.visible = false
		return

	# Check if cached entry is for a different direction — invalidate if so
	if _effect_cache.has(frame.effect_id):
		var cached: Dictionary = _effect_cache[frame.effect_id]
		if cached.get("direction", "") != _preview_direction:
			_effect_cache.erase(frame.effect_id)

	var assets := _load_effect_assets(frame.effect_id)
	if assets.is_empty():
		_effect_sprite.visible = false
		return

	_effect_sprite.visible = true
	_effect_sprite.scale = _preview_sprite.scale
	_effect_sprite.z_index = frame.effect_z_index
	_effect_sprite.rotation = deg_to_rad(frame.effect_rotation_deg)

	var eff_fs: int = assets["frame_size"]

	# When not playing, reset atlas to first frame
	if not _playing:
		var atlas: AtlasTexture = assets["texture"]
		atlas.region = Rect2(0, 0, eff_fs, eff_fs)

	# Apply alpha mask compositing (global + per-frame)
	var global_mask: Image = assets.get("alpha_mask")
	var frame_mask: Image = frame.effect_alpha_mask

	if global_mask != null or frame_mask != null:
		# Extract current frame from spritesheet
		var sheet_tex: Texture2D = assets["sheet_texture"]
		var sheet_img := sheet_tex.get_image()
		if sheet_img != null:
			var atlas_tex: AtlasTexture = assets["texture"]
			var region := atlas_tex.region
			var frame_img := Image.create(eff_fs, eff_fs, false, Image.FORMAT_RGBA8)
			frame_img.blit_rect(sheet_img, Rect2i(int(region.position.x), 0, eff_fs, eff_fs), Vector2i.ZERO)
			for y in range(eff_fs):
				for x in range(eff_fs):
					var alpha_mult := 1.0
					if global_mask != null and x < global_mask.get_width() and y < global_mask.get_height():
						alpha_mult *= global_mask.get_pixel(x, y).r
					if frame_mask != null and x < frame_mask.get_width() and y < frame_mask.get_height():
						alpha_mult *= frame_mask.get_pixel(x, y).r
					if alpha_mult < 0.99:
						var px: Color = frame_img.get_pixel(x, y)
						px.a *= alpha_mult
						frame_img.set_pixel(x, y, px)
			_effect_sprite.texture = ImageTexture.create_from_image(frame_img)
	else:
		_effect_sprite.texture = assets["texture"]

	# Resolve anchor position
	var anchor_pos: Vector2 = _preview_sprite.position  # default: center

	match frame.effect_anchor:
		"weapon_tip":
			# Use grip + direction anchors to compute the weapon tip in viewport coords
			if _frame_images.has(_preview_direction):
				var images: Array = _frame_images[_preview_direction]
				if _preview_frame_index < images.size():
					var img: Image = images[_preview_frame_index]
					var anchors := _find_anchors_in_image(img)
					var grip_px: Vector2 = anchors.get("grip", Vector2.INF)
					var dir_px: Vector2 = anchors.get("direction", Vector2.INF)
					if grip_px != Vector2.INF:
						# Get the weapon tip in viewport space
						var weapon_tex: Texture2D = _weapon_set.get("right")
						var weapon_grip: Vector2 = _weapon_set.get("grip_right", Vector2.ZERO)
						var weapon_tip: Vector2 = _weapon_set.get("tip_right", Vector2.ZERO)
						if weapon_tex != null and weapon_tip != Vector2.ZERO:
							# Grip position in viewport coords
							var grip_vp := _preview_sprite.position + (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
							# Compute rotation (same as weapon preview)
							var inherent_angle := atan2(weapon_tip.y - weapon_grip.y, weapon_tip.x - weapon_grip.x)
							var desired_angle := 0.0
							if dir_px != Vector2.INF:
								desired_angle = atan2(dir_px.y - grip_px.y, dir_px.x - grip_px.x)
							var rot := desired_angle - inherent_angle
							# Tip offset from grip in weapon-local space, rotated
							var tip_local := (weapon_tip - weapon_grip) * _preview_sprite.scale
							var tip_rotated := tip_local.rotated(rot)
							anchor_pos = grip_vp + tip_rotated
						else:
							# No weapon data — fall back to grip pixel
							anchor_pos = _preview_sprite.position + (grip_px - Vector2(_frame_size) / 2.0) * _preview_sprite.scale
		"center":
			anchor_pos = _preview_sprite.position
		"feet":
			# Bottom center of the character sprite
			if _frame_size != Vector2i.ZERO:
				anchor_pos = _preview_sprite.position + Vector2(0, float(_frame_size.y) / 2.0) * _preview_sprite.scale

	# Apply user offset (in pixels, scaled to viewport)
	anchor_pos += frame.effect_offset * _preview_sprite.scale
	_effect_sprite.position = anchor_pos
