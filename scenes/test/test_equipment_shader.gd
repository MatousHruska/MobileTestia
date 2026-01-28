# scenes/test/test_equipment_shader.gd
extends Node2D

## Test scene for equipment UV shader with multiple slots
## Tests swapping individual equipment pieces (head, body, hands, legs)
##
## Controls:
##   H - Toggle HEAD slot (on/off)
##   B - Toggle BODY slot (on/off)
##   A - Toggle HANDS/ARMS slot (on/off)
##   L - Toggle LEGS slot (on/off)
##   R - Reload all textures from disk
##   S - Cycle base skin
##   Space - Test hit flash
##   T - Toggle poison tint
##   1-5 - Jump to animation frame
##   P - Toggle auto-play

const FRAME_WIDTH := 32
const FRAME_HEIGHT := 32
const FRAME_COUNT := 5
const ANIMATION_FPS := 6.0

const BASE_PATH := "res://assets/sprites/characters/player/Tests/"

@onready var sprite: Sprite2D = $Sprite2D

var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = true

# Equipment slot states (true = equipped, false = empty/base skin)
var _head_equipped: bool = true
var _body_equipped: bool = true
var _hands_equipped: bool = true
var _legs_equipped: bool = true

# Loaded textures
var _tex_uv_map: Texture2D
var _tex_base: Texture2D
var _tex_head: Texture2D
var _tex_body: Texture2D
var _tex_hands: Texture2D
var _tex_legs: Texture2D
var _tex_idle_sheet: Texture2D


func _ready() -> void:
	_load_all_textures()
	_setup_shader()
	_update_frame_region()
	_print_instructions()


func _load_all_textures() -> void:
	_tex_idle_sheet = load(BASE_PATH + "TestIdle-Sheet.png")
	_tex_uv_map = load(BASE_PATH + "TestUVMap.png")
	_tex_base = load(BASE_PATH + "TestLookupTexture2.png")  # Base skin
	_tex_head = load(BASE_PATH + "LookupTextureHead.png")
	_tex_body = load(BASE_PATH + "LookupTextureBody.png")
	_tex_hands = load(BASE_PATH + "LookupTextureHands.png")
	_tex_legs = load(BASE_PATH + "LookupTextureLegs.png")

	print("=== Textures Loaded ===")
	print("Idle Sheet: ", _tex_idle_sheet.get_size() if _tex_idle_sheet else "MISSING")
	print("UV Map: ", _tex_uv_map.get_size() if _tex_uv_map else "MISSING")
	print("Base Skin: ", _tex_base.get_size() if _tex_base else "MISSING")
	print("Head: ", _tex_head.get_size() if _tex_head else "MISSING")
	print("Body: ", _tex_body.get_size() if _tex_body else "MISSING")
	print("Hands: ", _tex_hands.get_size() if _tex_hands else "MISSING")
	print("Legs: ", _tex_legs.get_size() if _tex_legs else "MISSING")


func _setup_shader() -> void:
	sprite.texture = _tex_idle_sheet
	sprite.region_enabled = true

	var material := sprite.material as ShaderMaterial

	# Set UV map
	material.set_shader_parameter("uv_map", _tex_uv_map)
	material.set_shader_parameter("uv_map_size", Vector2(32.0, 32.0))
	material.set_shader_parameter("color_tolerance", 0.02)

	# Set base skin (fallback for all slots)
	material.set_shader_parameter("skin_base", _tex_base)

	# Set equipment slot textures
	_update_all_slots()


func _update_all_slots() -> void:
	var material := sprite.material as ShaderMaterial

	# Head slot
	if _head_equipped and _tex_head:
		material.set_shader_parameter("skin_head", _tex_head)
	else:
		material.set_shader_parameter("skin_head", _tex_base)

	# Body slot
	if _body_equipped and _tex_body:
		material.set_shader_parameter("skin_body", _tex_body)
	else:
		material.set_shader_parameter("skin_body", _tex_base)

	# Hands slot
	if _hands_equipped and _tex_hands:
		material.set_shader_parameter("skin_hands", _tex_hands)
	else:
		material.set_shader_parameter("skin_hands", _tex_base)

	# Legs/Feet slot
	if _legs_equipped and _tex_legs:
		material.set_shader_parameter("skin_feet", _tex_legs)
	else:
		material.set_shader_parameter("skin_feet", _tex_base)

	_print_slot_status()


func _print_slot_status() -> void:
	print("Slots: HEAD=%s  BODY=%s  HANDS=%s  LEGS=%s" % [
		"ON" if _head_equipped else "off",
		"ON" if _body_equipped else "off",
		"ON" if _hands_equipped else "off",
		"ON" if _legs_equipped else "off",
	])


func _print_instructions() -> void:
	print("")
	print("=== Equipment UV Shader Test Scene ===")
	print("")
	print("Controls:")
	print("  H          - Toggle HEAD slot")
	print("  B          - Toggle BODY slot")
	print("  A          - Toggle HANDS/ARMS slot")
	print("  L          - Toggle LEGS slot")
	print("  R          - Reload all textures")
	print("  Space      - Test hit flash")
	print("  T          - Toggle poison tint")
	print("  1-5        - Jump to frame")
	print("  P          - Toggle auto-play")
	print("")


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_animation_timer += delta
	var frame_duration := 1.0 / ANIMATION_FPS

	if _animation_timer >= frame_duration:
		_animation_timer -= frame_duration
		_advance_frame()


func _advance_frame() -> void:
	_current_frame = (_current_frame + 1) % FRAME_COUNT
	_update_frame_region()


func _update_frame_region() -> void:
	var x := _current_frame * FRAME_WIDTH
	sprite.region_rect = Rect2(x, 0, FRAME_WIDTH, FRAME_HEIGHT)


func _set_frame(frame: int) -> void:
	_current_frame = clampi(frame, 0, FRAME_COUNT - 1)
	_update_frame_region()
	print("Frame: %d/%d" % [_current_frame + 1, FRAME_COUNT])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_test_flash()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_H:
				_head_equipped = not _head_equipped
				_update_all_slots()
			KEY_B:
				_body_equipped = not _body_equipped
				_update_all_slots()
			KEY_A:
				_hands_equipped = not _hands_equipped
				_update_all_slots()
			KEY_L:
				_legs_equipped = not _legs_equipped
				_update_all_slots()
			KEY_R:
				_reload_textures()
			KEY_T:
				_test_tint()
			KEY_P:
				_toggle_play()
			KEY_1:
				_set_frame(0)
			KEY_2:
				_set_frame(1)
			KEY_3:
				_set_frame(2)
			KEY_4:
				_set_frame(3)
			KEY_5:
				_set_frame(4)
			KEY_LEFT:
				_is_playing = false
				_set_frame(_current_frame - 1 if _current_frame > 0 else FRAME_COUNT - 1)
			KEY_RIGHT:
				_is_playing = false
				_set_frame((_current_frame + 1) % FRAME_COUNT)


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


func _toggle_play() -> void:
	_is_playing = not _is_playing
	print("Auto-play: %s" % ("ON" if _is_playing else "OFF"))


func _reload_textures() -> void:
	print("")
	print("=== RELOADING TEXTURES ===")
	_load_all_textures()
	_setup_shader()
	print("=== RELOAD COMPLETE ===")
	_update_frame_region()
