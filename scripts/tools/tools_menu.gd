extends Control
## Tools Menu — Unified launcher for all MobileTestia tool scenes.
##
## Provides a centered menu with buttons to navigate to each tool pipeline.
## Run: scenes/tools/tools_menu.tscn (F6)

#===============================================================================
# UI THEME CONSTANTS
#===============================================================================

const C_BG := Color("#1E1E2E")
const C_PANEL := Color("#252536")
const C_SURFACE := Color("#33334A")
const C_SURFACE_HOVER := Color("#3D3D55")
const C_BORDER := Color("#3A3A50")
const C_TEXT := Color("#E0E0EC")
const C_TEXT_SEC := Color("#8888A0")
const C_TEXT_DIM := Color("#555570")
const C_ACCENT := Color("#5B9CF5")

const FONT_TITLE := 18
const FONT_SECTION := 14
const FONT_LABEL := 13
const FONT_HINT := 11

#===============================================================================
# TOOL ENTRIES
#===============================================================================

const TOOLS := [
	{
		"label": "Sprite Pipeline",
		"description": "Capture & process 3D model into pixel art spritesheets",
		"scene": "res://scenes/tools/sprite_pipeline.tscn",
	},
	{
		"label": "Weapon Pipeline",
		"description": "Convert weapon images to pixel art with anchor points",
		"scene": "res://scenes/tools/weapon_pipeline.tscn",
	},
	{
		"label": "Effect Pipeline",
		"description": "Capture & process effects into directional spritesheets",
		"scene": "res://scenes/tools/effect_pipeline.tscn",
	},
	{
		"label": "Attack Composer",
		"description": "Compose attack animations with weapon, effects & timing",
		"scene": "res://scenes/tools/attack_composer.tscn",
	},
]

#===============================================================================
# SETUP
#===============================================================================

func _ready() -> void:
	# Full-screen dark background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Centering container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	# Main content column
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 500
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MobileTestia Tools"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Select a tool to launch"
	subtitle.add_theme_font_size_override("font_size", FONT_HINT)
	subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	vbox.add_child(spacer)

	# Tool buttons
	for entry in TOOLS:
		var btn := _make_tool_button(entry["label"], entry["description"], entry["scene"])
		vbox.add_child(btn)


func _make_tool_button(label_text: String, description: String, scene_path: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = C_SURFACE
	bg_style.set_corner_radius_all(6)
	bg_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", bg_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", FONT_SECTION)
	name_label.add_theme_color_override("font_color", C_TEXT)
	content.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", FONT_HINT)
	desc_label.add_theme_color_override("font_color", C_TEXT_SEC)
	content.add_child(desc_label)

	# Make the entire panel clickable via a transparent Button overlay
	var click_btn := Button.new()
	click_btn.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	click_btn.flat = true
	click_btn.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	click_btn.pressed.connect(_navigate_to.bind(scene_path))
	panel.add_child(click_btn)

	# Hover effect
	click_btn.mouse_entered.connect(func() -> void:
		bg_style.bg_color = C_SURFACE_HOVER
	)
	click_btn.mouse_exited.connect(func() -> void:
		bg_style.bg_color = C_SURFACE
	)

	return panel


func _navigate_to(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
