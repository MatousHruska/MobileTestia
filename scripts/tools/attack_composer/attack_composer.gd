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

# ── State ──────────────────────────────────────────────────────────────
var _current_composition: AttackCompositionData = null
var _frame_images: Dictionary = {}  # {direction_string: Array[Image]}
var _frame_textures: Dictionary = {}  # {direction_string: Array[ImageTexture]}
var _preview_direction := "down"
var _preview_frame_index: int = 0
var _selected_frame: int = -1
var _available_models: Array[String] = []
var _available_anims: Array[String] = []
var _current_model: String = ""
var _current_anim: String = ""
var _frame_size: Vector2i = Vector2i.ZERO

# ── Playback state ─────────────────────────────────────────────────────
var _playing := false
var _playback_ms := 0.0
var _playback_speed := 1.0

# ── UI references ──────────────────────────────────────────────────────
var _status_label: Label
var _left_scroll_content: VBoxContainer
var _right_vbox: VBoxContainer
var _timeline_panel: TimelinePanel
var _model_dropdown: OptionButton
var _anim_dropdown: OptionButton
var _load_info_label: Label
var _frame_props_container: VBoxContainer
var _duration_spinbox: SpinBox
var _fps_label: Label
var _total_duration_label: Label
var _weapon_check: CheckButton
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
var _frame_label: Label
var _frame_nav_prev: Button
var _frame_nav_next: Button
var _play_btn: Button
var _stop_btn: Button
var _time_label: Label
var _speed_slider: HSlider

const DIRECTIONS := ["down", "up", "right"]


func _ready() -> void:
	_build_ui()
	_build_loading_section()
	_build_frame_props_section()
	_scan_animations()
	_set_status("Ready. Select a model and animation to begin.")


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
	preview_vbox.add_child(viewport_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.transparent_bg = false
	_preview_viewport.size = Vector2i(128, 128)
	_preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(_preview_viewport)

	# Checkerboard background
	_preview_checker = ColorRect.new()
	_preview_checker.color = C_SECTION
	_preview_checker.size = Vector2(128, 128)
	_preview_viewport.add_child(_preview_checker)

	# The sprite to display the current frame
	_preview_sprite = Sprite2D.new()
	_preview_sprite.centered = true
	_preview_sprite.position = Vector2(64, 64)
	_preview_viewport.add_child(_preview_sprite)

	# Weapon sprite (layered above body)
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.centered = true
	_weapon_sprite.visible = false
	_weapon_sprite.z_index = 1
	_preview_viewport.add_child(_weapon_sprite)

	# Load default weapon set
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
		var short := dir_name.substr(0, 1).to_upper()
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
	_timeline_panel.frame_duration_changed.connect(_on_timeline_duration_changed)
	_timeline_panel.playhead_moved.connect(_on_timeline_playhead_moved)
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
	_timeline_panel.playhead_ms = 0.0
	_timeline_panel.selected_frame = 0
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
	_left_scroll_content.add_child(_make_section_label("Spritesheet"))

	# Animation dropdown (folder names like Slash, Blocking, etc.)
	_left_scroll_content.add_child(_make_label("Animation"))
	_anim_dropdown = _make_option_button()
	_anim_dropdown.item_selected.connect(_on_anim_selected)
	_left_scroll_content.add_child(_anim_dropdown)

	# Model dropdown (model prefixes within animation folder)
	_left_scroll_content.add_child(_make_label("Model"))
	_model_dropdown = _make_option_button()
	_left_scroll_content.add_child(_model_dropdown)

	# Load button
	_left_scroll_content.add_child(_make_button("Load Spritesheet", _on_load_pressed, true))

	# Info label
	_load_info_label = _make_label("", C_TEXT_DIM)
	_load_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_scroll_content.add_child(_load_info_label)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	_left_scroll_content.add_child(sep)


func _build_frame_props_section() -> void:
	_frame_props_container = VBoxContainer.new()
	_frame_props_container.add_theme_constant_override("separation", 6)
	_frame_props_container.visible = false
	_left_scroll_content.add_child(_frame_props_container)

	_frame_props_container.add_child(_make_section_label("Frame Properties"))

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

	# Weapon visible
	_weapon_check = CheckButton.new()
	_weapon_check.text = "Weapon Visible"
	_weapon_check.add_theme_font_size_override("font_size", FONT_LABEL)
	_weapon_check.add_theme_color_override("font_color", C_TEXT_SEC)
	_weapon_check.toggled.connect(_on_weapon_toggled)
	_frame_props_container.add_child(_weapon_check)

	# Effect
	_frame_props_container.add_child(_make_label("Effect"))
	_effect_dropdown = _make_option_button()
	_effect_dropdown.add_item("(none)", 0)
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

	# Separator before sequence props
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _make_separator_style())
	_frame_props_container.add_child(sep)

	# Total duration
	_total_duration_label = _make_label("Total: 0.000s", C_TEXT)
	_frame_props_container.add_child(_total_duration_label)

	# Sequence-level properties
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _make_separator_style())
	_left_scroll_content.add_child(sep2)

	_seq_props_container = VBoxContainer.new()
	_seq_props_container.add_theme_constant_override("separation", 6)
	_seq_props_container.visible = false
	_left_scroll_content.add_child(_seq_props_container)

	_seq_props_container.add_child(_make_section_label("Sequence Properties"))

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

	# Generate & Save section
	var save_sep := HSeparator.new()
	save_sep.add_theme_stylebox_override("separator", _make_separator_style())
	_left_scroll_content.add_child(save_sep)

	var save_container := VBoxContainer.new()
	save_container.add_theme_constant_override("separation", 6)
	_left_scroll_content.add_child(save_container)

	save_container.add_child(_make_section_label("Save & Export"))
	save_container.add_child(_make_button("Generate Runtime Data", _on_generate_runtime))
	save_container.add_child(_make_button("Save Composition", _on_save_composition))
	save_container.add_child(_make_button("Save Runtime Data", _on_save_runtime))
	save_container.add_child(_make_button("Save Both", _on_save_both, true))

	# Load section
	var load_sep := HSeparator.new()
	load_sep.add_theme_stylebox_override("separator", _make_separator_style())
	_left_scroll_content.add_child(load_sep)

	var load_container := VBoxContainer.new()
	load_container.add_theme_constant_override("separation", 6)
	_left_scroll_content.add_child(load_container)

	load_container.add_child(_make_section_label("Load Composition"))
	load_container.add_child(_make_button("Refresh", _scan_saved_compositions))


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

	_load_info_label.text = "Loaded: %s (%d frames, %dx%d)" % [anim_folder, frame_count, _frame_size.x, _frame_size.y]
	_set_status("Spritesheet loaded. %d frames at %dx%d." % [frame_count, _frame_size.x, _frame_size.y])

	_on_spritesheet_loaded()


func _on_spritesheet_loaded() -> void:
	# Resize viewport to match frame size
	_preview_viewport.size = Vector2i(_frame_size.x, _frame_size.y)
	_preview_checker.size = Vector2(_frame_size.x, _frame_size.y)
	_preview_sprite.position = Vector2(_frame_size.x / 2.0, _frame_size.y / 2.0)

	# Feed data to timeline
	_timeline_panel.composition = _current_composition
	_timeline_panel.selected_frame = 0
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

	# Update echo ghosts
	_update_echo_preview()


func _update_direction_highlight() -> void:
	for i in DIRECTIONS.size():
		var btn: Button = _direction_buttons[i]
		var is_active := DIRECTIONS[i] == _preview_direction
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
		return

	if _preview_frame_index >= _current_composition.frames.size():
		_weapon_sprite.visible = false
		return

	var frame := _current_composition.frames[_preview_frame_index]
	if not frame.weapon_visible:
		_weapon_sprite.visible = false
		return

	# Get weapon texture for current direction
	var weapon_tex: Texture2D = _weapon_set.get(_preview_direction)
	if weapon_tex == null:
		_weapon_sprite.visible = false
		return

	_weapon_sprite.texture = weapon_tex
	_weapon_sprite.visible = true

	# Find anchor pixels in the current body frame
	if not _frame_images.has(_preview_direction):
		return
	var images: Array = _frame_images[_preview_direction]
	if _preview_frame_index >= images.size():
		return

	var img: Image = images[_preview_frame_index]
	var anchors := _find_anchors_in_image(img)
	var grip: Vector2 = anchors.get("grip", Vector2.INF)

	if grip == Vector2.INF:
		# No anchor found — center weapon
		_weapon_sprite.position = _preview_sprite.position
		return

	# Position weapon at grip anchor
	var grip_key := "grip_%s" % _preview_direction
	var weapon_grip: Vector2 = _weapon_set.get(grip_key, Vector2.ZERO)
	_weapon_sprite.position = _preview_sprite.position + grip - Vector2(_frame_size.x / 2.0, _frame_size.y / 2.0)
	_weapon_sprite.offset = -weapon_grip


func _find_anchors_in_image(img: Image) -> Dictionary:
	var result := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var pixel := img.get_pixel(x, y)
			if pixel.is_equal_approx(WEAPON_ANCHOR_COLOR) and not result.has("grip"):
				result["grip"] = Vector2(x, y)
			elif pixel.is_equal_approx(WEAPON_DIRECTION_COLOR) and not result.has("direction"):
				result["direction"] = Vector2(x, y)
			if result.size() == 2:
				return result
	return result


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
		ghost.position = _preview_sprite.position - Vector2(0, spacing * (i + 1))
		var t := float(i) / float(count - 1) if count > 1 else 0.0
		ghost.modulate.a = lerpf(frame.echo_opacity_start, frame.echo_opacity_end, t)
		ghost.z_index = -1
		_preview_viewport.add_child(ghost)
		_echo_sprites.append(ghost)


func _on_frame_prev() -> void:
	if _current_composition == null:
		return
	_preview_frame_index = max(0, _preview_frame_index - 1)
	_selected_frame = _preview_frame_index
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


func _on_frame_next() -> void:
	if _current_composition == null:
		return
	var max_frame := _current_composition.frames.size() - 1
	_preview_frame_index = min(max_frame, _preview_frame_index + 1)
	_selected_frame = _preview_frame_index
	_timeline_panel.selected_frame = _selected_frame
	_timeline_panel.queue_redraw()
	_update_preview_frame()
	_update_frame_props_ui()


func show_frame(index: int) -> void:
	if _current_composition == null:
		return
	_preview_frame_index = clampi(index, 0, _current_composition.frames.size() - 1)
	_selected_frame = _preview_frame_index
	_update_preview_frame()


# ── Timeline signal handlers ──────────────────────────────────────────

func _on_timeline_frame_selected(index: int) -> void:
	_selected_frame = index
	_preview_frame_index = index
	_update_preview_frame()
	_update_frame_props_ui()


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
			_update_preview_frame()
			return


# ── Frame property handlers ────────────────────────────────────────────

func _update_frame_props_ui() -> void:
	if _current_composition == null or _selected_frame < 0 or _selected_frame >= _current_composition.frames.size():
		_frame_props_container.visible = false
		_seq_props_container.visible = false
		return

	_frame_props_container.visible = true
	_seq_props_container.visible = true

	var frame := _current_composition.frames[_selected_frame]

	# Block signals during UI update to avoid feedback loops
	_duration_spinbox.set_value_no_signal(frame.duration_ms)
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(frame.duration_ms, 1))
	_weapon_check.set_pressed_no_signal(frame.weapon_visible)
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


func _on_duration_changed(value: float) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	_current_composition.frames[_selected_frame].duration_ms = int(value)
	_fps_label.text = "~ %.1f fps" % (1000.0 / maxf(value, 1))
	_total_duration_label.text = "Total: %.3fs" % _current_composition.get_total_duration_sec()
	_timeline_panel.queue_redraw()


func _on_weapon_toggled(pressed: bool) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	_current_composition.frames[_selected_frame].weapon_visible = pressed
	_timeline_panel.queue_redraw()


func _on_effect_selected(index: int) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	var text := _effect_dropdown.get_item_text(index)
	_current_composition.frames[_selected_frame].effect_id = "" if text == "(none)" else text
	_timeline_panel.queue_redraw()


func _on_effect_anchor_selected(index: int) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	_current_composition.frames[_selected_frame].effect_anchor = _effect_anchor_dropdown.get_item_text(index)


func _on_effect_offset_changed(_value: float) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	_current_composition.frames[_selected_frame].effect_offset = Vector2(_effect_offset_x.value, _effect_offset_y.value)


func _on_echo_toggled(pressed: bool) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	_current_composition.frames[_selected_frame].echo_enabled = pressed
	_echo_settings_container.visible = pressed
	_timeline_panel.queue_redraw()


func _on_echo_setting_changed(_value: float) -> void:
	if _current_composition == null or _selected_frame < 0:
		return
	var frame := _current_composition.frames[_selected_frame]
	frame.echo_count = int(_echo_count_spin.value)
	frame.echo_opacity_start = _echo_opacity_start_slider.value
	frame.echo_opacity_end = _echo_opacity_end_slider.value
	frame.echo_spacing_px = _echo_spacing_spin.value


func _on_movement_type_selected(index: int) -> void:
	if _current_composition == null:
		return
	var text := _movement_type_dropdown.get_item_text(index)
	_current_composition.movement_type = "" if text == "none" else text
	_timeline_panel.queue_redraw()


func _on_seq_prop_changed(_value: float) -> void:
	if _current_composition == null:
		return
	_current_composition.movement_distance = _movement_distance_spin.value
	_current_composition.movement_start_frame = int(_movement_start_spin.value)
	_current_composition.movement_end_frame = int(_movement_end_spin.value)
	_timeline_panel.queue_redraw()


func _on_damage_frame_changed(value: float) -> void:
	if _current_composition == null:
		return
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


func _scan_saved_compositions() -> void:
	_ensure_dirs()
	var dir := DirAccess.open(COMPOSITIONS_DIR)
	if dir == null:
		_set_status("Cannot open compositions directory")
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			files.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()

	if files.is_empty():
		_set_status("No saved compositions found.")
	else:
		_set_status("Found %d saved composition(s)." % files.size())
		for f in files:
			print("  - %s" % f)


func _load_composition(composition_id: String) -> void:
	var path := "%s/%s.tres" % [COMPOSITIONS_DIR, composition_id]
	if not ResourceLoader.exists(path):
		_set_status("Composition not found: %s" % path)
		return
	var loaded := load(path)
	if loaded is AttackCompositionData:
		_current_composition = loaded
		_selected_frame = 0
		_preview_frame_index = 0
		_timeline_panel.composition = _current_composition
		_timeline_panel.selected_frame = 0
		_timeline_panel.queue_redraw()
		_update_frame_props_ui()
		_set_status("Loaded composition: %s" % composition_id)
	else:
		_set_status("Invalid composition resource: %s" % path)
