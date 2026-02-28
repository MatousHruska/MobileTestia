class_name TimelinePanel
extends Control
## Custom-drawn timeline control with multiple tracks.
## Renders a time ruler, body track with frame thumbnails,
## and additional tracks for weapon/effect/echo/movement/damage.

signal frame_selected(index: int)
signal frames_selected(indices: Array[int])
signal frame_duration_changed(index: int, new_ms: int)
signal playhead_moved(ms: float)
signal before_mutation()  # Emitted before any data change, for undo snapshots
signal effect_toggled(index: int)  # Emitted when user clicks the effect track on a frame
signal effect_moved(from_index: int, to_index: int)  # Emitted when user drags an effect diamond to another frame
signal scroll_changed(offset_ms: float, total_ms: float, visible_ms: float)
signal weapon_toggled(index: int)  # Emitted when user clicks the weapon track on a frame
signal echo_toggled(index: int)    # Emitted when user clicks the echo track on a frame
signal damage_moved(index: int)    # Emitted when user clicks the damage track on a frame

# ── Theme (matches composer) ───────────────────────────────────────────
const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3C")
const C_SURFACE := Color("#33334A")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_SUCCESS := Color("#5BCC7F")
const C_WARNING := Color("#F5A85B")
const C_PLAYHEAD := Color("#FF4444")
const C_WEAPON_ON := Color("#5BCC7F", 0.6)
const C_WEAPON_OFF := Color("#555570", 0.3)
const C_ECHO_ON := Color("#5B9CF5", 0.4)
const C_EFFECT_MARKER := Color("#F5A85B")
const C_DAMAGE_MARKER := Color("#FF4444")
const C_MOVEMENT_BAR := Color("#A87CFF", 0.5)

const RULER_HEIGHT := 20.0
const BODY_TRACK_HEIGHT := 40.0
const SUB_TRACK_HEIGHT := 28.0
const LABEL_WIDTH := 60.0
const FONT_SIZE := 11

# ── State ──────────────────────────────────────────────────────────────
var sequence: DirectionSequence = null
var frame_thumbnails: Array[ImageTexture] = []
var selected_frame: int = -1
var selected_frames: Array[int] = []
var playhead_ms: float = 0.0
var pixels_per_ms: float = 2.0
var scroll_offset_ms: float = 0.0

# ── Drag state ─────────────────────────────────────────────────────────
var _dragging_edge: bool = false
var _drag_frame_index: int = -1
var _drag_start_x: float = 0.0
var _drag_start_ms: int = 0
var _scrubbing: bool = false
var _dragging_effect: bool = false
var _drag_effect_from: int = -1

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_default_cursor_shape = CURSOR_ARROW
	clip_contents = true


func _draw() -> void:
	if sequence == null or sequence.frames.is_empty():
		# Empty state
		var center := size / 2.0
		draw_string(_font, Vector2(center.x - 60, center.y), "Load a spritesheet",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_DIM)
		return

	_draw_ruler()
	_draw_body_track()
	_draw_weapon_track()
	_draw_effect_track()
	_draw_echo_track()
	_draw_movement_track()
	_draw_damage_track()
	_draw_playhead()


# ── Drawing helpers ────────────────────────────────────────────────────

func _get_frame_x(frame_index: int) -> float:
	var ms := 0
	for i in mini(frame_index, sequence.frames.size()):
		ms += sequence.frames[i].duration_ms
	return LABEL_WIDTH + (ms - scroll_offset_ms) * pixels_per_ms


func _get_frame_width(frame_index: int) -> float:
	if frame_index < 0 or frame_index >= sequence.frames.size():
		return 0.0
	return sequence.frames[frame_index].duration_ms * pixels_per_ms


func _get_total_ms() -> float:
	if sequence == null:
		return 0.0
	return float(sequence.get_total_duration_ms())


func get_visible_ms() -> float:
	return (size.x - LABEL_WIDTH) / pixels_per_ms


func set_scroll_from_scrollbar(value_ms: float) -> void:
	scroll_offset_ms = clampf(value_ms, 0.0, maxf(0.0, _get_total_ms() - get_visible_ms()))
	queue_redraw()


func _emit_scroll_changed() -> void:
	scroll_changed.emit(scroll_offset_ms, _get_total_ms(), get_visible_ms())


func _ms_to_x(ms: float) -> float:
	return LABEL_WIDTH + (ms - scroll_offset_ms) * pixels_per_ms


func _x_to_ms(x: float) -> float:
	return (x - LABEL_WIDTH) / pixels_per_ms + scroll_offset_ms


func _frame_at_x(x: float, track_y_start: float, track_height: float, mouse_y: float) -> int:
	if mouse_y < track_y_start or mouse_y > track_y_start + track_height:
		return -1
	var ms := _x_to_ms(x)
	if ms < 0:
		return -1
	var cumulative := 0.0
	for i in sequence.frames.size():
		cumulative += sequence.frames[i].duration_ms
		if ms < cumulative:
			return i
	return -1


# ── Ruler ──────────────────────────────────────────────────────────────

func _draw_ruler() -> void:
	# Background
	draw_rect(Rect2(LABEL_WIDTH, 0, size.x - LABEL_WIDTH, RULER_HEIGHT), C_PANEL)

	# Tick marks
	var total_ms := _get_total_ms()
	var start_ms := int(scroll_offset_ms / 50.0) * 50
	var ms := start_ms
	while ms <= total_ms + 50:
		var x := _ms_to_x(ms)
		if x < LABEL_WIDTH:
			ms += 50
			continue
		if x > size.x:
			break

		if int(ms) % 100 == 0:
			# Major tick with label
			draw_line(Vector2(x, 0), Vector2(x, RULER_HEIGHT), C_TEXT_DIM, 1.0)
			var label_text := "%dms" % ms
			draw_string(_font, Vector2(x + 2, RULER_HEIGHT - 4), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_DIM)
		else:
			# Minor tick
			draw_line(Vector2(x, RULER_HEIGHT * 0.5), Vector2(x, RULER_HEIGHT), C_BORDER, 1.0)

		ms += 50

	# Bottom border
	draw_line(Vector2(LABEL_WIDTH, RULER_HEIGHT), Vector2(size.x, RULER_HEIGHT), C_BORDER, 1.0)


# ── Body Track ─────────────────────────────────────────────────────────

func _draw_body_track() -> void:
	var y := RULER_HEIGHT

	# Track label
	draw_rect(Rect2(0, y, LABEL_WIDTH, BODY_TRACK_HEIGHT), C_PANEL)
	draw_string(_font, Vector2(4, y + BODY_TRACK_HEIGHT / 2.0 + 4), "Body",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_SEC)

	# Frame blocks
	for i in sequence.frames.size():
		var x := _get_frame_x(i)
		var w := _get_frame_width(i)

		if x + w < LABEL_WIDTH or x > size.x:
			continue

		# Block background (primary = bright, multi-selected = dim blue, normal = surface)
		var is_primary := (i == selected_frame)
		var is_selected := (i in selected_frames)
		var block_color := C_ACCENT.darkened(0.3) if is_primary else (C_ACCENT.darkened(0.5) if is_selected else C_SURFACE)
		draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), block_color)

		# Thumbnail
		if i < frame_thumbnails.size() and frame_thumbnails[i] != null:
			var thumb_size := minf(w - 4, BODY_TRACK_HEIGHT - 6)
			if thumb_size > 4:
				var thumb_rect := Rect2(x + 2, y + 3, thumb_size, thumb_size)
				draw_texture_rect(frame_thumbnails[i], thumb_rect, false)

		# Frame index label
		if w > 16:
			var idx_text := str(i)
			draw_string(_font, Vector2(x + w - 14, y + BODY_TRACK_HEIGHT - 4), idx_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_DIM)

		# Selection border (thicker for primary, thinner for multi-selected)
		if is_primary:
			draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), C_ACCENT, false, 2.0)
		elif is_selected:
			draw_rect(Rect2(x, y + 1, w - 1, BODY_TRACK_HEIGHT - 2), C_ACCENT.darkened(0.2), false, 1.0)

	# Track border
	draw_line(Vector2(LABEL_WIDTH, y + BODY_TRACK_HEIGHT),
		Vector2(size.x, y + BODY_TRACK_HEIGHT), C_BORDER, 1.0)


# ── Sub-tracks ─────────────────────────────────────────────────────────

func _get_track_y(track_index: int) -> float:
	return RULER_HEIGHT + BODY_TRACK_HEIGHT + track_index * SUB_TRACK_HEIGHT


func _draw_sub_track_bg(track_index: int, label: String) -> void:
	var y := _get_track_y(track_index)
	draw_rect(Rect2(0, y, LABEL_WIDTH, SUB_TRACK_HEIGHT), C_PANEL)
	draw_string(_font, Vector2(4, y + SUB_TRACK_HEIGHT / 2.0 + 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, C_TEXT_DIM)
	draw_line(Vector2(LABEL_WIDTH, y + SUB_TRACK_HEIGHT),
		Vector2(size.x, y + SUB_TRACK_HEIGHT), C_BORDER, 0.5)


func _draw_weapon_track() -> void:
	_draw_sub_track_bg(0, "Weapon")
	if sequence == null:
		return
	var y := _get_track_y(0)
	for i in sequence.frames.size():
		var x := _get_frame_x(i)
		var w := _get_frame_width(i)
		if x + w < LABEL_WIDTH or x > size.x:
			continue
		var color := C_WEAPON_ON if sequence.frames[i].weapon_visible else C_WEAPON_OFF
		draw_rect(Rect2(x, y + 2, w - 1, SUB_TRACK_HEIGHT - 4), color)
		# Show "B" marker on frames where weapon renders behind body
		if not sequence.frames[i].weapon_z_front and sequence.frames[i].weapon_visible:
			draw_string(_font, Vector2(x + 2, y + SUB_TRACK_HEIGHT - 4), "B",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT)


func _draw_effect_track() -> void:
	_draw_sub_track_bg(1, "Effect")
	if sequence == null:
		return
	var y := _get_track_y(1)
	for i in sequence.frames.size():
		if sequence.frames[i].effect_id.is_empty():
			continue
		var x := _get_frame_x(i)
		var w := _get_frame_width(i)
		if x + w < LABEL_WIDTH or x > size.x:
			continue
		var cx := x + w / 2.0
		var cy := y + SUB_TRACK_HEIGHT / 2.0
		var diamond_size := 6.0
		var points := PackedVector2Array([
			Vector2(cx, cy - diamond_size),
			Vector2(cx + diamond_size, cy),
			Vector2(cx, cy + diamond_size),
			Vector2(cx - diamond_size, cy),
		])
		draw_colored_polygon(points, C_EFFECT_MARKER)


func _draw_echo_track() -> void:
	_draw_sub_track_bg(2, "Echo")
	if sequence == null:
		return
	var y := _get_track_y(2)
	for i in sequence.frames.size():
		if not sequence.frames[i].echo_enabled:
			continue
		var x := _get_frame_x(i)
		var w := _get_frame_width(i)
		if x + w < LABEL_WIDTH or x > size.x:
			continue
		draw_rect(Rect2(x, y + 2, w - 1, SUB_TRACK_HEIGHT - 4), C_ECHO_ON)


func _draw_movement_track() -> void:
	_draw_sub_track_bg(3, "Move")
	if sequence == null:
		return
	var start := sequence.movement_start_frame
	var end := sequence.movement_end_frame
	if start < 0 or end < 0 or start >= sequence.frames.size() or end >= sequence.frames.size():
		return
	var y := _get_track_y(3)
	var x1 := _get_frame_x(start)
	var x2 := _get_frame_x(end) + _get_frame_width(end)
	if x2 < LABEL_WIDTH or x1 > size.x:
		return
	draw_rect(Rect2(x1, y + 4, x2 - x1, SUB_TRACK_HEIGHT - 8), C_MOVEMENT_BAR)
	# Label
	if sequence.movement_type != "":
		draw_string(_font, Vector2(x1 + 4, y + SUB_TRACK_HEIGHT / 2.0 + 3),
			sequence.movement_type, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT)


func _draw_damage_track() -> void:
	_draw_sub_track_bg(4, "Damage")
	if sequence == null:
		return
	var dmg := sequence.damage_frame
	if dmg < 0 or dmg >= sequence.frames.size():
		return
	var y := _get_track_y(4)
	var x := _get_frame_x(dmg)
	var w := _get_frame_width(dmg)
	var cx := x + w / 2.0
	var cy := y + SUB_TRACK_HEIGHT / 2.0
	var diamond_size := 7.0
	var points := PackedVector2Array([
		Vector2(cx, cy - diamond_size),
		Vector2(cx + diamond_size, cy),
		Vector2(cx, cy + diamond_size),
		Vector2(cx - diamond_size, cy),
	])
	draw_colored_polygon(points, C_DAMAGE_MARKER)


# ── Playhead ───────────────────────────────────────────────────────────

func _draw_playhead() -> void:
	var x := _ms_to_x(playhead_ms)
	if x < LABEL_WIDTH or x > size.x:
		return
	var total_height := RULER_HEIGHT + BODY_TRACK_HEIGHT + 5 * SUB_TRACK_HEIGHT
	draw_line(Vector2(x, 0), Vector2(x, total_height), C_PLAYHEAD, 1.5)
	# Playhead triangle at top
	var tri := PackedVector2Array([
		Vector2(x - 5, 0),
		Vector2(x + 5, 0),
		Vector2(x, 6),
	])
	draw_colored_polygon(tri, C_PLAYHEAD)


# ── Input ──────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if sequence == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_click(mb.position, mb.shift_pressed)
			else:
				if _dragging_effect:
					# Resolve effect drag — find destination frame
					var effect_y := _get_track_y(1)
					var dest := _frame_at_x(mb.position.x, effect_y, SUB_TRACK_HEIGHT, effect_y + SUB_TRACK_HEIGHT / 2.0)
					if dest >= 0 and dest != _drag_effect_from:
						effect_moved.emit(_drag_effect_from, dest)
					elif dest == _drag_effect_from:
						# Click-release on same diamond = toggle off
						effect_toggled.emit(_drag_effect_from)
					_dragging_effect = false
					_drag_effect_from = -1
					queue_redraw()
				_dragging_edge = false
				_scrubbing = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.shift_pressed:
				# Shift+wheel = horizontal scroll
				scroll_offset_ms = maxf(0, scroll_offset_ms - 50)
			else:
				pixels_per_ms = minf(pixels_per_ms * 1.15, 10.0)
			_emit_scroll_changed()
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.shift_pressed:
				scroll_offset_ms = minf(_get_total_ms(), scroll_offset_ms + 50)
			else:
				pixels_per_ms = maxf(pixels_per_ms / 1.15, 0.3)
			_emit_scroll_changed()
			queue_redraw()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_edge:
			_handle_edge_drag(mm.position)
		elif _scrubbing:
			_handle_scrub(mm.position)
		else:
			_update_cursor(mm.position)


func _handle_click(pos: Vector2, shift: bool = false) -> void:
	# Ruler click → scrub
	if pos.y < RULER_HEIGHT:
		_scrubbing = true
		_handle_scrub(pos)
		return

	# Check for edge drag on body track
	var body_y := RULER_HEIGHT
	if pos.y >= body_y and pos.y <= body_y + BODY_TRACK_HEIGHT:
		# Check edge proximity
		for i in sequence.frames.size():
			var right_edge := _get_frame_x(i) + _get_frame_width(i)
			if absf(pos.x - right_edge) < 5.0:
				before_mutation.emit()
				_dragging_edge = true
				_drag_frame_index = i
				_drag_start_x = pos.x
				_drag_start_ms = sequence.frames[i].duration_ms
				return

		# Click → select frame (shift = range select)
		var idx := _frame_at_x(pos.x, body_y, BODY_TRACK_HEIGHT, pos.y)
		if idx >= 0:
			if shift and selected_frame >= 0:
				# Range select from last selected to clicked
				var from_idx := mini(selected_frame, idx)
				var to_idx := maxi(selected_frame, idx)
				selected_frames.clear()
				for i in range(from_idx, to_idx + 1):
					selected_frames.append(i)
				selected_frame = idx
				frames_selected.emit(selected_frames.duplicate())
			else:
				# Normal click — single select
				selected_frame = idx
				selected_frames = [idx]
				frame_selected.emit(idx)
			queue_redraw()
		return

	# Sub-track clicks
	_handle_sub_track_click(pos)


func _handle_sub_track_click(pos: Vector2) -> void:
	# Weapon track (index 0) — toggle weapon_visible (routed via signal for All-mode support)
	var weapon_y := _get_track_y(0)
	if pos.y >= weapon_y and pos.y <= weapon_y + SUB_TRACK_HEIGHT:
		var idx := _frame_at_x(pos.x, weapon_y, SUB_TRACK_HEIGHT, pos.y)
		if idx >= 0:
			weapon_toggled.emit(idx)
		return

	# Effect track (index 1) — click to toggle, drag to move
	var effect_y := _get_track_y(1)
	if pos.y >= effect_y and pos.y <= effect_y + SUB_TRACK_HEIGHT:
		var idx := _frame_at_x(pos.x, effect_y, SUB_TRACK_HEIGHT, pos.y)
		if idx >= 0:
			if not sequence.frames[idx].effect_id.is_empty():
				# Start dragging existing effect diamond
				_dragging_effect = true
				_drag_effect_from = idx
			else:
				# Empty frame — toggle effect on
				effect_toggled.emit(idx)
		return

	# Echo track (index 2) — toggle echo_enabled (routed via signal for All-mode support)
	var echo_y := _get_track_y(2)
	if pos.y >= echo_y and pos.y <= echo_y + SUB_TRACK_HEIGHT:
		var idx := _frame_at_x(pos.x, echo_y, SUB_TRACK_HEIGHT, pos.y)
		if idx >= 0:
			echo_toggled.emit(idx)
		return

	# Damage track (index 4) — move damage marker (routed via signal for All-mode support)
	var damage_y := _get_track_y(4)
	if pos.y >= damage_y and pos.y <= damage_y + SUB_TRACK_HEIGHT:
		var idx := _frame_at_x(pos.x, damage_y, SUB_TRACK_HEIGHT, pos.y)
		if idx >= 0:
			damage_moved.emit(idx)
		return


func _handle_edge_drag(pos: Vector2) -> void:
	if _drag_frame_index < 0 or _drag_frame_index >= sequence.frames.size():
		return
	var delta_px := pos.x - _drag_start_x
	var delta_ms := int(delta_px / pixels_per_ms)
	# Snap to 8ms
	var new_ms := maxi(8, _drag_start_ms + delta_ms)
	new_ms = int(round(new_ms / 8.0)) * 8
	sequence.frames[_drag_frame_index].duration_ms = new_ms
	frame_duration_changed.emit(_drag_frame_index, new_ms)
	queue_redraw()


func _handle_scrub(pos: Vector2) -> void:
	var ms := _x_to_ms(pos.x)
	ms = clampf(ms, 0.0, _get_total_ms())
	playhead_ms = ms
	playhead_moved.emit(ms)
	queue_redraw()


func _update_cursor(pos: Vector2) -> void:
	var body_y := RULER_HEIGHT
	if pos.y >= body_y and pos.y <= body_y + BODY_TRACK_HEIGHT:
		for i in sequence.frames.size():
			var right_edge := _get_frame_x(i) + _get_frame_width(i)
			if absf(pos.x - right_edge) < 5.0:
				mouse_default_cursor_shape = CURSOR_HSIZE
				return
	mouse_default_cursor_shape = CURSOR_ARROW


func get_total_height() -> float:
	return RULER_HEIGHT + BODY_TRACK_HEIGHT + 5 * SUB_TRACK_HEIGHT
