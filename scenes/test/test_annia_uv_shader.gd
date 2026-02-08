# scenes/test/test_annia_uv_shader.gd
extends Node2D

## Test scene for Annia UV lookup shader
## Tests: Frame1 / Idle animation + FinalsUV + FinalsLookup
##
## Controls:
##   Space - Test hit flash (white)
##   T - Toggle poison tint (green)
##   R - Reload textures from disk
##   Buttons - Debug mode switching, animation switching (Basic/Idle)

const FRAME_WIDTH := 64
const FRAME_HEIGHT := 64

const BASE_PATH := "res://assets/test/NewTest/"

const UV_MAP_FILE := "FinalsUV.png"
const SKIN_FILE := "FinalsLookup.png"

const ANIMATIONS := {
	"Basic": ["Frame1.png"],
	"Idle": ["Idle01.png", "Idle02.png"],
}

const ANIM_FRAME_TIME := 0.2  # 200ms between frames

var current_anim: String = "Basic"
var current_anim_index: int = 0
var anim_timer: float = 0.0

const DEBUG_NAMES := {
	0: "Normal",
	1: "Frame Colors (raw TEXTURE)",
	2: "UV Positions (R=x, G=y)",
	3: "Match Status (green=ok, red=fallback)",
	4: "Raw Skin Lookup (no tint/flash)",
}

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label


func _ready() -> void:
	_setup_textures()
	_print_instructions()


func _setup_textures() -> void:
	var frame_file: String = ANIMATIONS[current_anim][0]
	var frame_sheet = load(BASE_PATH + frame_file)
	var uv_map = load(BASE_PATH + UV_MAP_FILE)
	var skin = load(BASE_PATH + SKIN_FILE)

	if not frame_sheet or not uv_map or not skin:
		push_error("Failed to load Annia textures!")
		return

	sprite.texture = frame_sheet
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)

	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("uv_map", uv_map)
	material.set_shader_parameter("skin", skin)
	material.set_shader_parameter("uv_map_size", Vector2(64.0, 64.0))
	material.set_shader_parameter("color_tolerance", 0.002)
	material.set_shader_parameter("debug_mode", 0.0)

	print("=== Annia Textures Loaded ===")
	print("Frame: %s (%s)" % [frame_file, str(frame_sheet.get_size())])
	print("UV Map: ", uv_map.get_size())
	print("Skin: ", skin.get_size(), " [", SKIN_FILE, "]")
	print("Tolerance: 0.002 (~0.5 in 0-255)")


func _print_instructions() -> void:
	print("")
	print("=== Annia UV Shader Test ===")
	print("")
	print("Controls:")
	print("  Space      - Test hit flash (white)")
	print("  T          - Toggle poison tint (green)")
	print("  R          - Reload textures from disk")
	print("  Buttons    - Switch debug modes")
	print("")


func _process(delta: float) -> void:
	var frames: Array = ANIMATIONS[current_anim]
	if frames.size() <= 1:
		return
	anim_timer += delta
	if anim_timer >= ANIM_FRAME_TIME:
		anim_timer -= ANIM_FRAME_TIME
		current_anim_index = (current_anim_index + 1) % frames.size()
		var frame_file: String = frames[current_anim_index]
		var tex = load(BASE_PATH + frame_file)
		if tex:
			sprite.texture = tex


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_test_flash()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_reload_textures()
			KEY_T:
				_test_tint()


func _set_debug_mode(mode: int) -> void:
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("debug_mode", float(mode))
	var mode_name: String = DEBUG_NAMES.get(mode, "Unknown")
	label.text = "Debug Mode %d: %s" % [mode, mode_name]
	print("Debug mode: %d - %s" % [mode, mode_name])


# Button callbacks
func _on_debug_normal() -> void:
	_set_debug_mode(0)

func _on_debug_frame() -> void:
	_set_debug_mode(1)

func _on_debug_uv_pos() -> void:
	_set_debug_mode(2)

func _on_debug_match() -> void:
	_set_debug_mode(3)

func _on_debug_skin() -> void:
	_set_debug_mode(4)


# Animation switching callbacks
func _switch_anim(anim_name: String) -> void:
	current_anim = anim_name
	current_anim_index = 0
	anim_timer = 0.0
	var frames: Array = ANIMATIONS[current_anim]
	var frame_file: String = frames[0]
	var frame_sheet = load(BASE_PATH + frame_file)
	if not frame_sheet:
		push_error("Failed to load frame: " + frame_file)
		return
	sprite.texture = frame_sheet
	sprite.region_rect = Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
	var frame_count: int = frames.size()
	label.text = "Anim: %s (%d frames, %dms)" % [current_anim, frame_count, int(ANIM_FRAME_TIME * 1000)]
	print("Switched to anim: %s (%d frames)" % [current_anim, frame_count])


func _on_frame_basic() -> void:
	_switch_anim("Basic")


func _on_frame_idle() -> void:
	_switch_anim("Idle")


func _test_flash() -> void:
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("flash_amount", 1.0)

	var tween := create_tween()
	tween.tween_property(material, "shader_parameter/flash_amount", 0.0, 0.15)
	print("Flash triggered!")


func _test_tint() -> void:
	var material := sprite.material as ShaderMaterial
	var current_tint: Color = material.get_shader_parameter("tint")

	if current_tint == Color.WHITE:
		material.set_shader_parameter("tint", Color(0.5, 1.0, 0.5))
		print("Tint: Green (poisoned)")
	else:
		material.set_shader_parameter("tint", Color.WHITE)
		print("Tint: Normal")


func _reload_textures() -> void:
	print("")
	print("=== RELOADING TEXTURES ===")

	var frame_file: String = ANIMATIONS[current_anim][current_anim_index]
	var frame_sheet = load(BASE_PATH + frame_file)
	var uv_map = load(BASE_PATH + UV_MAP_FILE)
	var skin = load(BASE_PATH + SKIN_FILE)

	if frame_sheet and uv_map and skin:
		sprite.texture = frame_sheet

		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("uv_map", uv_map)
		material.set_shader_parameter("skin", skin)
		material.set_shader_parameter("uv_map_size", Vector2(64.0, 64.0))

		print("Reloaded: %s (%s)" % [frame_file, str(frame_sheet.get_size())])
		print("Reloaded: %s (%s)" % [UV_MAP_FILE, str(uv_map.get_size())])
		print("Reloaded: %s (%s)" % [SKIN_FILE, str(skin.get_size())])
		print("=== RELOAD COMPLETE ===")
	else:
		print("ERROR: Failed to reload textures!")

	sprite.region_rect = Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
