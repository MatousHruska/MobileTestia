# scenes/test/test_annia_uv_shader.gd
extends Node2D

## Test scene for Annia UV lookup shader
## Tests: Frame1 + AnniaUVsimplified + AnniaLookup
##
## Controls:
##   Space - Test hit flash (white)
##   T - Toggle poison tint (green)
##   R - Reload textures from disk
##   1-4 - Debug modes (1=frame colors, 2=UV positions, 3=match status, 4=raw skin)
##   0 - Normal rendering

const FRAME_WIDTH := 64
const FRAME_HEIGHT := 64

const BASE_PATH := "res://assets/test/NewTest/"

const UV_MAP_FILE := "AnniaUVsimplified.png"
const SKIN_FILE := "AnniaLookup.png"

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
	var frame_sheet = load(BASE_PATH + "Frame1.png")
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
	material.set_shader_parameter("debug_mode", 0)

	print("=== Annia Textures Loaded ===")
	print("Frame: ", frame_sheet.get_size())
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
	print("  0          - Normal rendering")
	print("  1          - Debug: show raw frame colors")
	print("  2          - Debug: show UV match positions")
	print("  3          - Debug: match success (green/red)")
	print("  4          - Debug: raw skin lookup")
	print("")


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
			KEY_0:
				_set_debug_mode(0)
			KEY_1:
				_set_debug_mode(1)
			KEY_2:
				_set_debug_mode(2)
			KEY_3:
				_set_debug_mode(3)
			KEY_4:
				_set_debug_mode(4)


func _set_debug_mode(mode: int) -> void:
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("debug_mode", mode)
	var mode_name: String = DEBUG_NAMES.get(mode, "Unknown")
	label.text = "Debug Mode %d: %s" % [mode, mode_name]
	print("Debug mode: %d - %s" % [mode, mode_name])


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

	var frame_sheet = load(BASE_PATH + "Frame1.png")
	var uv_map = load(BASE_PATH + UV_MAP_FILE)
	var skin = load(BASE_PATH + SKIN_FILE)

	if frame_sheet and uv_map and skin:
		sprite.texture = frame_sheet

		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("uv_map", uv_map)
		material.set_shader_parameter("skin", skin)
		material.set_shader_parameter("uv_map_size", Vector2(64.0, 64.0))

		print("Reloaded: Frame1.png (%s)" % str(frame_sheet.get_size()))
		print("Reloaded: %s (%s)" % [UV_MAP_FILE, str(uv_map.get_size())])
		print("Reloaded: %s (%s)" % [SKIN_FILE, str(skin.get_size())])
		print("=== RELOAD COMPLETE ===")
	else:
		print("ERROR: Failed to reload textures!")

	sprite.region_rect = Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
