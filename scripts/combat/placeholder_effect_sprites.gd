class_name PlaceholderEffectSprites
## PlaceholderEffectSprites - Generates placeholder VFX nodes for combat.
##
## Each effect is a self-contained Node2D with a procedural texture and
## tween-based animation. Effects auto-remove after their lifetime.
## Replace with real particle effects or AnimatedSprite2D when art is ready.
##
## Usage:
##   var fx := PlaceholderEffectSprites.create_effect("slash_arc", "down")
##   effect_anchor.add_child(fx)  # fx animates and self-destructs

#===============================================================================
# COLOR CONSTANTS
#===============================================================================

const COL_SLASH := Color("#DDDDEE")        # Slash arc body
const COL_SLASH_EDGE := Color("#FFFFFF")    # Slash leading edge
const COL_SLASH_WARM := Color("#EEDDCC")    # Wide slash tint
const COL_THRUST := Color("#EEEEFF")        # Thrust core
const COL_THRUST_GLOW := Color("#AABBDD")   # Thrust edge glow
const COL_SPARK_CORE := Color("#FFFFFF")     # Impact center
const COL_SPARK_BODY := Color("#FFFFDD")     # Impact cross
const COL_SPARK_WARM := Color("#FFDDAA")     # Impact corners


#===============================================================================
# PUBLIC API
#===============================================================================

## Create a placeholder effect by ID.
## direction: "down", "up", "right" — affects orientation of directional effects.
## Returns a Node2D ready to be added as a child. Returns null if effect_id unknown.
static func create_effect(effect_id: String, direction: String = "down") -> Node2D:
	match effect_id:
		"slash_arc":
			return _create_slash_arc(direction)
		"slash_arc_wide":
			return _create_slash_arc_wide(direction)
		"thrust_line":
			return _create_thrust_line(direction)
		"impact_spark":
			return _create_impact_spark()
	return null


#===============================================================================
# SLASH ARC — Melee swing VFX (24×24, 0.15s lifetime)
#===============================================================================

static func _create_slash_arc(direction: String) -> Node2D:
	var root := Node2D.new()
	root.name = "SlashArc"

	# Position offset toward attack direction
	match direction:
		"down": root.position = Vector2(0, 8)
		"up": root.position = Vector2(0, -12)
		"right": root.position = Vector2(10, 0)

	# Draw arc texture
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	_draw_arc(img, direction, COL_SLASH, COL_SLASH_EDGE, 3)

	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	root.add_child(sprite)

	# Initial state + tween on ready
	root.scale = Vector2(0.6, 0.6)
	root.ready.connect(func():
		var tween := root.create_tween()
		tween.set_parallel(true)
		tween.tween_property(root, "scale", Vector2(1.2, 1.2), 0.15)
		tween.tween_property(root, "modulate:a", 0.0, 0.15)
		tween.chain().tween_callback(root.queue_free)
	)

	return root


#===============================================================================
# SLASH ARC WIDE — Combo hit VFX (28×28, 0.18s lifetime)
#===============================================================================

static func _create_slash_arc_wide(direction: String) -> Node2D:
	var root := Node2D.new()
	root.name = "SlashArcWide"

	match direction:
		"down": root.position = Vector2(0, 8)
		"up": root.position = Vector2(0, -12)
		"right": root.position = Vector2(10, 0)

	# Wider arc on larger canvas with warm tint
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	_draw_arc(img, direction, COL_SLASH_WARM, COL_SLASH_EDGE, 4)

	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	root.add_child(sprite)

	root.scale = Vector2(0.7, 0.7)
	root.ready.connect(func():
		var tween := root.create_tween()
		tween.set_parallel(true)
		tween.tween_property(root, "scale", Vector2(1.3, 1.3), 0.18)
		tween.tween_property(root, "modulate:a", 0.0, 0.18)
		tween.chain().tween_callback(root.queue_free)
	)

	return root


#===============================================================================
# THRUST LINE — Stab VFX (4×16 or 16×4, 0.12s lifetime)
#===============================================================================

static func _create_thrust_line(direction: String) -> Node2D:
	var root := Node2D.new()
	root.name = "ThrustLine"

	var img: Image
	var start_scale: Vector2

	match direction:
		"down":
			root.position = Vector2(0, 10)
			img = Image.create(4, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color.TRANSPARENT)
			# Edge glow on sides
			_fill_rect(img, 0, 0, 1, 16, COL_THRUST_GLOW)
			_fill_rect(img, 3, 0, 1, 16, COL_THRUST_GLOW)
			# Core line
			_fill_rect(img, 1, 0, 2, 16, COL_THRUST)
			start_scale = Vector2(0.8, 0.3)
		"up":
			root.position = Vector2(0, -14)
			img = Image.create(4, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color.TRANSPARENT)
			_fill_rect(img, 0, 0, 1, 16, COL_THRUST_GLOW)
			_fill_rect(img, 3, 0, 1, 16, COL_THRUST_GLOW)
			_fill_rect(img, 1, 0, 2, 16, COL_THRUST)
			start_scale = Vector2(0.8, 0.3)
		_:  # "right" and default
			root.position = Vector2(12, 0)
			img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color.TRANSPARENT)
			# Edge glow on top/bottom
			_fill_rect(img, 0, 0, 16, 1, COL_THRUST_GLOW)
			_fill_rect(img, 0, 3, 16, 1, COL_THRUST_GLOW)
			# Core line
			_fill_rect(img, 0, 1, 16, 2, COL_THRUST)
			start_scale = Vector2(0.3, 0.8)

	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	root.add_child(sprite)

	root.scale = start_scale
	root.ready.connect(func():
		var end_scale: Vector2
		if direction == "right":
			end_scale = Vector2(1.2, 1.0)
		else:
			end_scale = Vector2(1.0, 1.2)
		var tween := root.create_tween()
		tween.set_parallel(true)
		tween.tween_property(root, "scale", end_scale, 0.12)
		tween.tween_property(root, "modulate:a", 0.0, 0.12)
		tween.chain().tween_callback(root.queue_free)
	)

	return root


#===============================================================================
# IMPACT SPARK — Hit confirmation VFX (12×12, 0.10s lifetime)
#===============================================================================

static func _create_impact_spark() -> Node2D:
	var root := Node2D.new()
	root.name = "ImpactSpark"
	# No position offset — spawns at effect anchor center

	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Horizontal bar (8×2, centered)
	_fill_rect(img, 2, 5, 8, 2, COL_SPARK_BODY)
	# Vertical bar (2×8, centered)
	_fill_rect(img, 5, 2, 2, 8, COL_SPARK_BODY)
	# Bright center (2×2)
	_fill_rect(img, 5, 5, 2, 2, COL_SPARK_CORE)
	# Diagonal corner accents
	_set_pixel_safe(img, 3, 3, COL_SPARK_WARM)
	_set_pixel_safe(img, 8, 3, COL_SPARK_WARM)
	_set_pixel_safe(img, 3, 8, COL_SPARK_WARM)
	_set_pixel_safe(img, 8, 8, COL_SPARK_WARM)

	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	root.add_child(sprite)

	root.scale = Vector2(0.5, 0.5)
	root.ready.connect(func():
		var tween := root.create_tween()
		tween.set_parallel(true)
		tween.tween_property(root, "scale", Vector2(1.5, 1.5), 0.10)
		tween.tween_property(root, "modulate:a", 0.0, 0.10)
		tween.chain().tween_callback(root.queue_free)
	)

	return root


#===============================================================================
# ARC DRAWING HELPER
#===============================================================================

## Draw an approximate arc shape on an image for the given direction.
## Approximated with small pixel blocks positioned along a curve.
## thickness: pixel thickness of the arc stroke.
static func _draw_arc(img: Image, direction: String, body_color: Color, edge_color: Color, thickness: int) -> void:
	var w := img.get_width()
	var h := img.get_height()

	# Arc is approximated by 5 segments positioned along a curve.
	# Each segment is a small rectangle at a calculated position.
	match direction:
		"down":
			# Arc sweeps left-to-right across the top half, curving downward.
			# Attack goes down, so the arc is above/in-front.
			var seg_w := maxi(w / 5, 2)
			# 5 segments across, with vertical positions forming a shallow curve
			var y_positions := [4, 2, 1, 2, 4]
			for i in range(5):
				var sx := int(i * (w - seg_w) / 4.0)
				var sy: int = y_positions[i]
				# Leading edge highlight (top row)
				_fill_rect(img, sx, sy, seg_w, 1, edge_color)
				# Body
				_fill_rect(img, sx, sy + 1, seg_w, thickness, body_color)
		"up":
			# Arc sweeps left-to-right across the bottom half, curving upward.
			var seg_w := maxi(w / 5, 2)
			var base_y := h - thickness - 5
			var y_offsets := [4, 2, 1, 2, 4]
			for i in range(5):
				var sx := int(i * (w - seg_w) / 4.0)
				var sy: int = base_y + y_offsets[i]
				_fill_rect(img, sx, sy, seg_w, thickness, body_color)
				# Leading edge highlight (bottom row)
				_fill_rect(img, sx, sy + thickness, seg_w, 1, edge_color)
		_:  # "right"
			# Arc sweeps top-to-bottom along the left half, curving rightward.
			var seg_h := maxi(h / 5, 2)
			var x_positions := [4, 2, 1, 2, 4]
			for i in range(5):
				var sy := int(i * (h - seg_h) / 4.0)
				var sx: int = x_positions[i]
				# Leading edge highlight (left column)
				_fill_rect(img, sx, sy, 1, seg_h, edge_color)
				# Body
				_fill_rect(img, sx + 1, sy, thickness, seg_h, body_color)


#===============================================================================
# DRAWING UTILITIES
#===============================================================================

static func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)


static func _set_pixel_safe(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)
