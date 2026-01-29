# scenes/test/test_custom_uv_shader.gd
extends Node2D

## Test scene for custom UV lookup shader validation
## Tests the player character textures: player_idle, player_uv, player_skin
##
## Controls:
##   Space - Test hit flash (white)
##   T - Toggle poison tint (green)
##   1-5 - Jump to specific animation frame
##   Left/Right arrows - Manual frame stepping
##   P - Toggle auto-play animation
##   S - Swap skin
##   R - Reload textures

const FRAME_WIDTH := 32
const FRAME_HEIGHT := 32
const FRAME_COUNT := 5
const ANIMATION_FPS := 6.0

# Base path for player assets
const BASE_PATH := "res://assets/sprites/characters/player/"

# Available skins to cycle through
const SKINS := [
	"player_skin.png",
	"player_skin_alt.png",
]

@onready var sprite: Sprite2D = $Sprite2D

var _current_frame: int = 0
var _animation_timer: float = 0.0
var _is_playing: bool = true
var _current_skin_index: int = 0


func _ready() -> void:
	_setup_textures()
	_update_frame_region()
	_print_instructions()


func _setup_textures() -> void:
	# Load player textures
	var idle_sheet = load(BASE_PATH + "player_idle.png")
	var uv_map = load(BASE_PATH + "player_uv.png")
	var skin = load(BASE_PATH + SKINS[_current_skin_index])

	if not idle_sheet or not uv_map or not skin:
		push_error("Failed to load player textures!")
		return

	# Set the animation sprite sheet as main texture
	sprite.texture = idle_sheet

	# Enable region for frame-by-frame animation
	sprite.region_enabled = true

	# Get the shader material and set parameters
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("uv_map", uv_map)
	material.set_shader_parameter("skin", skin)
	material.set_shader_parameter("uv_map_size", Vector2(32.0, 32.0))
	material.set_shader_parameter("color_tolerance", 0.02)

	print("=== Textures Loaded ===")
	print("Idle Sheet: ", idle_sheet.get_size())
	print("UV Map: ", uv_map.get_size())
	print("Skin: ", skin.get_size())


func _print_instructions() -> void:
	print("")
	print("=== Player UV Shader Test Scene ===")
	print("")
	print("Testing: player_idle + player_uv + player_skin")
	print("")
	print("Controls:")
	print("  R          - RELOAD textures from disk (hot-reload)")
	print("  S          - SWAP skin (cycle through skins)")
	print("  Space      - Test hit flash (white)")
	print("  T          - Toggle poison tint (green)")
	print("  1-5        - Jump to frame 1-5")
	print("  Left/Right - Step through frames")
	print("  P          - Toggle auto-play")
	print("")
	print("Expected: Character with skin colors from player_skin.png")
	print("Animation should show idle animation")
	print("")
	print("Current: Frame %d/%d, Playing: %s" % [_current_frame + 1, FRAME_COUNT, _is_playing])


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
	# Calculate region for current frame (horizontal strip)
	var x := _current_frame * FRAME_WIDTH
	sprite.region_rect = Rect2(x, 0, FRAME_WIDTH, FRAME_HEIGHT)


func _set_frame(frame: int) -> void:
	_current_frame = clampi(frame, 0, FRAME_COUNT - 1)
	_update_frame_region()
	print("Frame: %d/%d" % [_current_frame + 1, FRAME_COUNT])


func _input(event: InputEvent) -> void:
	# Flash on spacebar
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
		material.set_shader_parameter("tint", Color(0.5, 1.0, 0.5))  # Green poison
		print("Tint: Green (poisoned)")
	else:
		material.set_shader_parameter("tint", Color.WHITE)
		print("Tint: Normal")


func _toggle_play() -> void:
	_is_playing = not _is_playing
	print("Auto-play: %s" % ("ON" if _is_playing else "OFF"))


func _swap_skin() -> void:
	## Cycle through available skins
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
	## Hot-reload textures from disk without restarting
	print("")
	print("=== RELOADING TEXTURES ===")

	# Load fresh textures
	var idle_sheet = load(BASE_PATH + "player_idle.png")
	var uv_map = load(BASE_PATH + "player_uv.png")
	var skin = load(BASE_PATH + SKINS[_current_skin_index])

	if idle_sheet and uv_map and skin:
		sprite.texture = idle_sheet

		var material := sprite.material as ShaderMaterial
		material.set_shader_parameter("uv_map", uv_map)
		material.set_shader_parameter("skin", skin)
		material.set_shader_parameter("uv_map_size", Vector2(uv_map.get_width(), uv_map.get_height()))

		print("Reloaded: player_idle.png (%s)" % str(idle_sheet.get_size()))
		print("Reloaded: player_uv.png (%s)" % str(uv_map.get_size()))
		print("Reloaded: %s (%s)" % [SKINS[_current_skin_index], str(skin.get_size())])
		print("=== RELOAD COMPLETE ===")
	else:
		print("ERROR: Failed to reload textures!")

	_update_frame_region()
