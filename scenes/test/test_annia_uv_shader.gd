# scenes/test/test_annia_uv_shader.gd
extends Node2D

## Test scene for Annia UV lookup shader (basic, no body-part separation)
## Tests: Frame1 + AnniaUV + AnniaLookupEditedFinal / AnniaSecondaryLookup
##
## Controls:
##   Space - Test hit flash (white)
##   T - Toggle poison tint (green)
##   S - Swap skin (primary <-> secondary lookup)
##   R - Reload textures from disk

const FRAME_WIDTH := 64
const FRAME_HEIGHT := 64
const FRAME_COUNT := 1

const BASE_PATH := "res://assets/test/NewTest/"

const SKINS := [
	"AnniaLookupEditedFinal.png",
	"AnniaSecondaryLookup.png",
]

@onready var sprite: Sprite2D = $Sprite2D

var _current_skin_index: int = 0


func _ready() -> void:
	_setup_textures()
	_print_instructions()


func _setup_textures() -> void:
	var frame_sheet = load(BASE_PATH + "Frame1.png")
	var uv_map = load(BASE_PATH + "AnniaUV.png")
	var skin = load(BASE_PATH + SKINS[_current_skin_index])

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
	material.set_shader_parameter("color_tolerance", 0.02)

	print("=== Annia Textures Loaded ===")
	print("Frame: ", frame_sheet.get_size())
	print("UV Map: ", uv_map.get_size())
	print("Skin: ", skin.get_size(), " [", SKINS[_current_skin_index], "]")


func _print_instructions() -> void:
	print("")
	print("=== Annia UV Shader Test (Basic - No Body Parts) ===")
	print("")
	print("Testing: Frame1 + AnniaUV + Lookup textures")
	print("")
	print("Controls:")
	print("  S          - SWAP skin (primary <-> secondary)")
	print("  Space      - Test hit flash (white)")
	print("  T          - Toggle poison tint (green)")
	print("  R          - Reload textures from disk")
	print("")
	print("Expected: Character with skin colors from lookup texture")
	print("")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_test_flash()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_reload_textures()
			KEY_S:
				_swap_skin()
			KEY_T:
				_test_tint()


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


func _swap_skin() -> void:
	_current_skin_index = (_current_skin_index + 1) % SKINS.size()
	var skin_path = BASE_PATH + SKINS[_current_skin_index]

	if ResourceLoader.exists(skin_path):
		var skin = load(skin_path)
		if skin:
			var material := sprite.material as ShaderMaterial
			material.set_shader_parameter("skin", skin)
			print("Swapped to: %s" % SKINS[_current_skin_index])
		else:
			print("ERROR: Failed to load skin: %s" % skin_path)
	else:
		print("Skin not found: %s" % skin_path)


func _reload_textures() -> void:
	print("")
	print("=== RELOADING TEXTURES ===")

	var frame_sheet = load(BASE_PATH + "Frame1.png")
	var uv_map = load(BASE_PATH + "AnniaUV.png")
	var skin = load(BASE_PATH + SKINS[_current_skin_index])

	if frame_sheet and uv_map and skin:
		sprite.texture = frame_sheet

		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("uv_map", uv_map)
		material.set_shader_parameter("skin", skin)
		material.set_shader_parameter("uv_map_size", Vector2(64.0, 64.0))

		print("Reloaded: Frame1.png (%s)" % str(frame_sheet.get_size()))
		print("Reloaded: AnniaUV.png (%s)" % str(uv_map.get_size()))
		print("Reloaded: %s (%s)" % [SKINS[_current_skin_index], str(skin.get_size())])
		print("=== RELOAD COMPLETE ===")
	else:
		print("ERROR: Failed to reload textures!")

	sprite.region_rect = Rect2(0, 0, FRAME_WIDTH, FRAME_HEIGHT)
