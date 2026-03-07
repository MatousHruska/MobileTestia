extends Node2D
## Shadow stacking investigation — FINAL TESTS
## All previous Sprite2D "invisible" results were caused by wrong texture path.
## Now testing the real game scenario with correct path.
## Run with F6 — SPACE to cycle.

enum Test {
	BASELINE,          # Step 0: No CG — shows stacking
	VP_CG_INSIDE,      # Step 1: VP + CG INSIDE y_sort + shader (known broken = stacks)
	VP_CG_SIBLING,     # Step 2: VP + CG SIBLING of y_sort + shader (THE FIX?)
	VP_CG_SIBLING_REAL,# Step 3: VP + CG sibling + real shadow shader + tree
}

const TEST_NAMES := {
	Test.BASELINE:          "Step 0: NO CG — baseline stacking",
	Test.VP_CG_INSIDE:      "Step 1: VP + CG INSIDE y_sort + shader (stacks?)",
	Test.VP_CG_SIBLING:     "Step 2: VP + CG SIBLING of y_sort + shader (fix?)",
	Test.VP_CG_SIBLING_REAL:"Step 3: VP + CG sibling + REAL shadow shader + tree",
}

const CHILD_SHADER_CODE := """
shader_type canvas_item;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

const SHADOW_SHADER_CODE := """
shader_type canvas_item;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D shadow_mask : hint_default_white;
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 mask_uv = (UV - frame_uv_rect.xy) / frame_uv_rect.zw;
	float m = texture(shadow_mask, mask_uv).r;
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a * m);
}
"""

var _child_shader: Shader
var _shadow_shader: Shader
var current_test: Test = Test.BASELINE
var _test_root: Node
var _label: Label


func _ready() -> void:
	_child_shader = Shader.new()
	_child_shader.code = CHILD_SHADER_CODE
	_shadow_shader = Shader.new()
	_shadow_shader.code = SHADOW_SHADER_CODE

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.55, 0.2, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	var instr := Label.new()
	instr.position = Vector2(10, 40)
	instr.add_theme_font_size_override("font_size", 14)
	instr.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	instr.text = "SPACE = next | Compare overlap (left) to reference (right)"
	add_child(instr)

	_build_test()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		current_test = wrapi(current_test + 1, 0, Test.size()) as Test
		_build_test()


func _build_test() -> void:
	if _test_root and is_instance_valid(_test_root):
		_test_root.queue_free()
	_label.text = TEST_NAMES[current_test]

	# All tests use SubViewport to match real game
	_test_root = SubViewportContainer.new()
	_test_root.size = Vector2(768, 432)
	_test_root.stretch = true
	add_child(_test_root)

	var vp := SubViewport.new()
	vp.size = Vector2i(768, 432)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_test_root.add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.55, 0.2, 1.0)
	bg.size = Vector2(768, 432)
	vp.add_child(bg)

	var tree_tex := load("res://assets/decorations/pinetreesnow1/sprite.png") as Texture2D

	match current_test:
		Test.BASELINE:
			_build_baseline(vp, tree_tex)
		Test.VP_CG_INSIDE:
			_build_cg_inside_ysort(vp, tree_tex)
		Test.VP_CG_SIBLING:
			_build_cg_sibling_ysort(vp, tree_tex, false)
		Test.VP_CG_SIBLING_REAL:
			_build_cg_sibling_ysort(vp, tree_tex, true)


func _build_baseline(vp: SubViewport, tex: Texture2D) -> void:
	## No CanvasGroup — shadows at 0.3 alpha, stacking visible.
	var ysort := Node2D.new()
	ysort.y_sort_enabled = true
	vp.add_child(ysort)
	_add_shadow_sprites(ysort, tex, false, true)  # use_real_shader=false, per_shadow_alpha=true


func _build_cg_inside_ysort(vp: SubViewport, tex: Texture2D) -> void:
	## CanvasGroup INSIDE y_sort — expected to stack (the bug).
	var ysort := Node2D.new()
	ysort.y_sort_enabled = true
	vp.add_child(ysort)

	var cg := CanvasGroup.new()
	cg.self_modulate = Color(1, 1, 1, 0.3)
	ysort.add_child(cg)
	_add_shadow_sprites(cg, tex, false, false)


func _build_cg_sibling_ysort(vp: SubViewport, tex: Texture2D, real_shader: bool) -> void:
	## CanvasGroup as SIBLING of y_sort — the proposed fix.
	## CG added after bg but before ysort (draws above bg, below zone content).
	var cg := CanvasGroup.new()
	cg.self_modulate = Color(1, 1, 1, 0.3)
	vp.add_child(cg)

	var ysort := Node2D.new()
	ysort.y_sort_enabled = true
	vp.add_child(ysort)

	_add_shadow_sprites(cg, tex, real_shader, false)


func _add_shadow_sprites(parent: Node, tex: Texture2D, real_shader: bool, per_shadow_alpha: bool) -> void:
	## Add 3 overlapping tree shadows + 1 reference.
	## per_shadow_alpha: true = each shadow at 0.3 (baseline stacking test)
	## per_shadow_alpha: false = full alpha shadows (CG controls opacity)
	var positions := [Vector2(280, 300), Vector2(340, 280), Vector2(310, 350)]
	var ref_pos := Vector2(580, 300)

	for pos in positions + [ref_pos]:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = pos
		s.scale = Vector2(1.0, -1.0)  # Flip vertically
		s.rotation = 0.5

		if real_shader:
			var mat := ShaderMaterial.new()
			mat.shader = _shadow_shader
			var alpha := 0.3 if per_shadow_alpha else 1.0
			mat.set_shader_parameter("shadow_color", Color(0, 0, 0, alpha))
			mat.set_shader_parameter("frame_uv_rect", Vector4(0, 0, 1, 1))
			s.material = mat
		else:
			var mat := ShaderMaterial.new()
			mat.shader = _child_shader
			s.material = mat
			if per_shadow_alpha:
				s.modulate.a = 0.3

		parent.add_child(s)

	# Reference label
	var lbl := Label.new()
	lbl.position = Vector2(545, 180)
	lbl.text = "Reference\n(single)"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(lbl)
