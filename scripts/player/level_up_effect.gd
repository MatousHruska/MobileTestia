extends Node2D
class_name LevelUpEffect
## LevelUpEffect - Visual feedback when player levels up
## Shows a colored glow and text animation over the character

## Effect settings
@export var effect_duration: float = 1.5
@export var glow_color: Color = Color(1.0, 0.85, 0.2, 0.8)  ## Golden yellow
@export var text_color: Color = Color(1.0, 1.0, 1.0)

## Internal nodes
var _glow_rect: ColorRect
var _level_label: Label
var _tween: Tween


func _ready() -> void:
	_setup_effect_nodes()
	visible = false


func _setup_effect_nodes() -> void:
	## Create glow rectangle (placeholder for particle effect)
	_glow_rect = ColorRect.new()
	_glow_rect.size = Vector2(64, 64)
	_glow_rect.position = Vector2(-32, -48)
	_glow_rect.color = glow_color
	_glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow_rect)

	## Create level up text
	_level_label = Label.new()
	_level_label.text = "LEVEL UP!"
	_level_label.add_theme_font_size_override("font_size", 16)
	_level_label.add_theme_color_override("font_color", text_color)
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 2)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.position = Vector2(-40, -70)
	_level_label.custom_minimum_size = Vector2(80, 20)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_label)


func play(new_level: int) -> void:
	## Play the level up effect animation
	if _tween and _tween.is_running():
		_tween.kill()

	## Update text
	_level_label.text = "LEVEL %d!" % new_level

	## Reset state
	visible = true
	modulate.a = 1.0
	_glow_rect.scale = Vector2.ONE
	_level_label.position.y = -70

	## Create animation tween
	_tween = create_tween()
	_tween.set_parallel(true)

	## Glow pulse animation
	_tween.tween_property(_glow_rect, "scale", Vector2(1.5, 1.5), effect_duration * 0.3)
	_tween.chain().tween_property(_glow_rect, "scale", Vector2(0.8, 0.8), effect_duration * 0.7)

	## Text float up animation
	_tween.tween_property(_level_label, "position:y", -100.0, effect_duration)

	## Fade out
	_tween.tween_property(self, "modulate:a", 0.0, effect_duration).set_delay(effect_duration * 0.5)

	## Hide when done
	_tween.chain().tween_callback(func(): visible = false)

	Debug.log("Effects", "Level up effect played for level %d" % new_level)
