extends Control
## Horizontal step progress indicator drawn with _draw().
## Shows numbered circles connected by lines. Completed = green,
## current = accent blue, future = dim.

const C_SUCCESS := Color("#5BCC7F")
const C_ACCENT := Color("#5B9CF5")
const C_TEXT_DIM := Color("#555570")
const C_TEXT := Color("#E0E0EC")
const C_BG := Color("#252536")

var total_steps := 8
var current_step := 0  # 0-indexed
var step_names: PackedStringArray = [
	"Model & Animation", "Capture Preview", "Pixel Art Settings",
	"Frame Editor", "Light Preview", "Shadow", "Export", "Apply to SpriteFrames"
]

func _ready() -> void:
	custom_minimum_size.y = 56


func set_step(step: int) -> void:
	current_step = clampi(step, 0, total_steps - 1)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var padding := 20.0
	var usable := w - padding * 2
	var spacing := usable / float(total_steps - 1) if total_steps > 1 else 0.0
	var y_center := 16.0
	var radius := 6.0
	var line_y := y_center

	# Draw connecting lines first (behind circles)
	for i in range(total_steps - 1):
		var x1 := padding + i * spacing + radius
		var x2 := padding + (i + 1) * spacing - radius
		var color: Color
		if i < current_step:
			color = C_SUCCESS
		else:
			color = Color(C_TEXT_DIM, 0.4)
		draw_line(Vector2(x1, line_y), Vector2(x2, line_y), color, 2.0, true)

	# Draw circles
	for i in range(total_steps):
		var cx := padding + i * spacing
		var cy := y_center
		var pos := Vector2(cx, cy)

		if i < current_step:
			# Completed — filled green
			draw_circle(pos, radius, C_SUCCESS)
			# Checkmark (small V shape)
			var check_size := 3.0
			draw_line(pos + Vector2(-check_size, 0), pos + Vector2(-1, check_size), Color.WHITE, 1.5, true)
			draw_line(pos + Vector2(-1, check_size), pos + Vector2(check_size, -check_size + 1), Color.WHITE, 1.5, true)
		elif i == current_step:
			# Current — accent blue, slightly larger
			draw_circle(pos, radius + 2, Color(C_ACCENT, 0.25))
			draw_circle(pos, radius, C_ACCENT)
			_draw_number(pos, i + 1, Color.WHITE)
		else:
			# Future — hollow dim
			draw_arc(pos, radius, 0, TAU, 32, C_TEXT_DIM, 1.5, true)
			_draw_number(pos, i + 1, C_TEXT_DIM)

	# Step name label
	var name_y := y_center + radius + 14.0
	var font := ThemeDB.fallback_font
	var font_size := 12
	var step_name: String = step_names[current_step] if current_step < step_names.size() else ""
	var text_size := font.get_string_size(step_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_x := (w - text_size.x) / 2.0
	draw_string(font, Vector2(text_x, name_y), step_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, C_TEXT)


func _draw_number(pos: Vector2, number: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 9
	var text := str(number)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
