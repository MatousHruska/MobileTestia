extends Control
## Decoration Pipeline — 6-step wizard for creating pixel art decorations.
##
## Converts 3D models or 2D source images into pixel art sprites with normal maps,
## baked shadows, and auto-traced occluder polygons. Generates an LDtk tileset atlas.

#===============================================================================
# CONSTANTS
#===============================================================================

const IMPORT_DIR := "res://assets/3d_imports"
const DECORATIONS_DIR := "res://assets/decorations"
const ATLAS_DIR := "res://assets/decorations/_atlas"
const TOOLS_MENU_PATH := "res://scenes/tools/tools_menu.tscn"
const CAPTURE_OVERSCAN := 1.5

const STEP_NAMES := [
	"Source Selection",
	"Capture / Import",
	"Pixel Art Processing",
	"Normal & Shadow",
	"Preview & Adjust",
	"Export & Atlas",
]

# 3D capture directions — orbit around Y axis
const ANGLE_CONFIGS := {
	"single": [{ "name": "front", "suffix": "", "rotation_y": 0.0 }],
	"two": [
		{ "name": "front", "suffix": "_front", "rotation_y": 0.0 },
		{ "name": "back", "suffix": "_back", "rotation_y": 180.0 },
	],
	"four": [
		{ "name": "front", "suffix": "_front", "rotation_y": 0.0 },
		{ "name": "back", "suffix": "_back", "rotation_y": 180.0 },
		{ "name": "left", "suffix": "_left", "rotation_y": 270.0 },
		{ "name": "right", "suffix": "_right", "rotation_y": 90.0 },
	],
}

#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SECTION := Color("#2A2A3D")
const C_SECTION_BORDER := Color("#33334A")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")
const C_SUCCESS := Color("#66BB6A")
const C_WARN := Color("#FFA726")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11
const FONT_VALUE := 12

#===============================================================================
# WIZARD STATE
#===============================================================================

var _current_step := 0
var _source_mode := "3d"  # "3d" or "2d"
var _decoration_id := ""
var _angle_mode := "single"  # "single", "two", "four"

# 3D state
var available_models: Array[String] = []
var current_model_path := ""
var current_model_instance: Node = null

# Capture results: angle_name -> Image
var _captured_color: Dictionary = {}
var _captured_normal: Dictionary = {}
var _captured_shadow: Dictionary = {}

# 2D import state
var _imported_image: Image = null

# Processing results: angle_name -> Image
var _processed_color: Dictionary = {}
var _processed_normal: Dictionary = {}
var _processed_shadow: Dictionary = {}
var _processed_occluder_points: Dictionary = {}  # angle_name -> PackedVector2Array

#===============================================================================
# NODE REFERENCES
#===============================================================================

var step_indicator: Control
var step_containers: Array[Control] = []
var preview_container: SubViewportContainer
var sub_viewport: SubViewport
var camera: Camera3D
var model_slot: Node3D
var status_label: Label
var back_button: Button
var next_button: Button

# Step 1 refs
var model_dropdown: OptionButton
var deco_id_input: LineEdit
var angle_mode_group: HBoxContainer
var _3d_container: VBoxContainer
var _2d_container: VBoxContainer

# Capture materials
var _normal_capture_shader: Shader
var _normal_capture_material: ShaderMaterial = null
var _shadow_capture_material: StandardMaterial3D = null
var _saved_unlit_materials: Array[Dictionary] = []

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	_build_ui()
	_build_viewport()
	# Load normal capture shader
	_normal_capture_shader = load("res://shaders/normal_capture.gdshader") as Shader
	if _normal_capture_shader:
		_normal_capture_material = ShaderMaterial.new()
		_normal_capture_material.shader = _normal_capture_shader
	# Create shadow capture material
	_shadow_capture_material = StandardMaterial3D.new()
	_shadow_capture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_capture_material.albedo_color = Color.BLACK
	await get_tree().process_frame
	_scan_models()


func _build_ui() -> void:
	# Placeholder — will be built in subsequent tasks
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	status_label = Label.new()
	status_label.text = "Decoration Pipeline — skeleton loaded"
	status_label.add_theme_color_override("font_color", C_TEXT)
	status_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	add_child(status_label)


func _build_viewport() -> void:
	pass  # Will be built in Task 3


func _scan_models() -> void:
	pass  # Will be built in Task 3


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
