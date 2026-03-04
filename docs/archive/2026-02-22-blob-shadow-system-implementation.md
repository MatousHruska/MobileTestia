# Blob Shadow System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add pre-baked top-down silhouette shadows to all characters, captured during the sprite pipeline wizard and displayed via CharacterVisuals with light-responsive opacity and scale.

**Architecture:** Three components: (1) shadow capture pass in the sprite pipeline wizard using a top-down orthographic camera, (2) ShadowSprite layer in CharacterVisuals that syncs with body animation, with ellipse fallback for characters without shadow animations, (3) lightweight runtime light detection that adjusts shadow opacity and scale.

**Tech Stack:** GDScript, Godot 4 AnimatedSprite2D, CanvasItem modulate, SpriteFrames

---

### Task 1: Add Shadow Capture State to Sprite Pipeline

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:73-74` (wizard state section)
- Modify: `scripts/tools/sprite_pipeline.gd:1987-1998` (`_start_capture`)

**Step 1: Add shadow sheet state variable**

At line 74, after `_captured_normal_sheets`, add:

```gdscript
var _captured_shadow_sheets: Dictionary = {}  # { "down": Image, "up": Image, "right": Image }
```

**Step 2: Clear shadow sheets in `_start_capture`**

At line 1993, after `_captured_normal_sheets.clear()`, add:

```gdscript
	_captured_shadow_sheets.clear()
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): add shadow capture state to sprite pipeline"
```

---

### Task 2: Add Shadow Capture Material (Flat Black)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:119-122` (state variables)
- Modify: `scripts/tools/sprite_pipeline.gd:199-206` (`_ready`)
- Modify: `scripts/tools/sprite_pipeline.gd:1819-1828` (near material functions)

**Step 1: Add shadow material variable**

At line 122, after `_normal_capture_material`, add:

```gdscript
var _shadow_capture_material: StandardMaterial3D = null
```

**Step 2: Create the shadow material in `_ready`**

After line 206 (after normal shader setup), add:

```gdscript
	# Create shadow capture material — flat black, unshaded
	_shadow_capture_material = StandardMaterial3D.new()
	_shadow_capture_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_capture_material.albedo_color = Color.BLACK
```

**Step 3: Add `_apply_shadow_capture_materials` function**

After `_apply_normal_capture_materials` (around line 1828), add:

```gdscript
func _apply_shadow_capture_materials(node: Node) -> void:
	## Override all mesh materials with flat black for shadow silhouette capture.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_idx in range(mesh.get_surface_count()):
				mesh_instance.set_surface_override_material(surface_idx, _shadow_capture_material)
	for child in node.get_children():
		_apply_shadow_capture_materials(child)
```

**Step 4: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): add flat-black shadow capture material"
```

---

### Task 3: Add Top-Down Camera and Shadow Capture Pass

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:2001-2120` (`_capture_animation`)

This is the core capture logic. After the normal map pass (line 2091), add a shadow capture pass using a temporary top-down camera.

**Step 1: Add top-down camera helper function**

Add after `_position_camera` (around line 1841):

```gdscript
func _create_shadow_camera() -> Camera3D:
	## Create a temporary top-down orthographic camera for shadow capture.
	var shadow_cam := Camera3D.new()
	shadow_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	shadow_cam.size = camera.size  # Match main camera's view width
	shadow_cam.position = camera_target + Vector3(0.0, 10.0, 0.0)  # High above
	shadow_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # Look straight down
	return shadow_cam
```

**Step 2: Add shadow capture pass inside `_capture_animation`**

Inside the `for frame_idx in range(frame_count):` loop, after the normal map restoration (line 2091 `_restore_saved_materials()`), add the shadow pass:

```gdscript
			# --- Shadow capture pass: top-down silhouette ---
			if _shadow_capture_material:
				# Swap main camera for top-down shadow camera
				var shadow_cam := _create_shadow_camera()
				sub_viewport.add_child(shadow_cam)
				shadow_cam.current = true

				_save_current_materials(current_model_instance)
				_apply_shadow_capture_materials(current_model_instance)
				# Re-seek animation
				current_anim_player.play(anim_name)
				current_anim_player.seek(seek_time, true)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw

				var shadow_frame := sub_viewport.get_texture().get_image()
				shadow_frame.convert(Image.FORMAT_RGBA8)
				shadow_sheet.blit_rect(shadow_frame, Rect2i(0, 0, output_size, output_size), Vector2i(frame_idx * output_size, 0))

				_restore_saved_materials()
				# Restore main camera
				shadow_cam.queue_free()
				camera.current = true
```

**Step 3: Add shadow sheet initialization before the frame loop**

Inside the `for dir_idx` loop (after `normal_sheet` creation at line 2034), add:

```gdscript
		var shadow_sheet := Image.create(sheet_width, output_size, false, Image.FORMAT_RGBA8)
		shadow_sheet.fill(Color.TRANSPARENT)
```

**Step 4: Store the shadow sheet after the frame loop**

After `_captured_normal_sheets[dir_name] = normal_sheet` (line 2094), add:

```gdscript
		_captured_shadow_sheets[dir_name] = shadow_sheet
```

**Step 5: Save shadow captures to disk**

After the normal map save loop (lines 2110-2113), add:

```gdscript
	for dir_name in _captured_shadow_sheets:
		var file_path := "%s/%s_%s_shadow.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(file_path)
		_captured_shadow_sheets[dir_name].save_png(global_path)
```

**Step 6: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): add top-down shadow capture pass to wizard"
```

---

### Task 4: Add Shadow Preview to Step 2

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:536-579` (`_build_step2`)
- Modify: `scripts/tools/sprite_pipeline.gd:2176-2183` (`_update_capture_preview`)

**Step 1: Add "Shadow" button to Step 2 preview mode toggle**

In `_build_step2`, after the "Normal" button (around line 557), add:

```gdscript
	var shadow_btn := Button.new()
	shadow_btn.text = "Shadow"
	shadow_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	shadow_btn.pressed.connect(func() -> void:
		_capture_preview_mode = "shadow"
		_update_capture_preview()
	)
	mode_hbox.add_child(shadow_btn)
```

**Step 2: Update `_update_capture_preview` to handle shadow mode**

Modify the function at line 2176:

```gdscript
func _update_capture_preview() -> void:
	var sheets: Dictionary
	match _capture_preview_mode:
		"color":
			sheets = _captured_sheets
		"normal":
			sheets = _captured_normal_sheets
		"shadow":
			sheets = _captured_shadow_sheets
		_:
			sheets = _captured_sheets
	var rects := [capture_down_rect, capture_up_rect, capture_right_rect]
	var dir_names := ["down", "up", "right"]
	for i in range(3):
		if sheets.has(dir_names[i]):
			rects[i].texture = ImageTexture.create_from_image(sheets[dir_names[i]])
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): add shadow preview mode in capture step"
```

---

### Task 5: Export Shadow Sheets in Step 5

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:2407-2457` (`_start_export`)

**Step 1: Add shadow export after normal map export**

After the normal map export loop (around line 2451), add:

```gdscript
	# Export shadow maps
	var shadow_count := 0
	for dir_name in _captured_shadow_sheets:
		_set_status("Processing shadow %s..." % dir_name)
		# Shadow processing: just downscale + alpha threshold (no dithering/palette/outline)
		var shadow_source := _captured_shadow_sheets[dir_name]
		var result := shadow_source.duplicate() as Image
		var target_height := int(output_height_spin.value)
		var scale_factor := float(target_height) / float(result.get_height())
		var target_width := int(float(result.get_width()) * scale_factor)
		result.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
		PixelArtProcessing.apply_alpha_threshold(result, int(alpha_threshold_slider.value))

		var output_path := "%s/%s_%s_shadow.png" % [output_dir, safe_anim_name, dir_name]
		var global_path := ProjectSettings.globalize_path(output_path)
		var err := result.save_png(global_path)
		if err != OK:
			_append_log("ERROR: Failed to save shadow %s" % output_path)
			continue
		_append_log("Saved shadow: %s" % output_path)
		shadow_count += 1
```

**Step 2: Update the summary log line**

Change the final log line from:
```gdscript
	_append_log("\nExported %d color + %d normal files to %s/" % [count, normal_count, output_dir])
	_set_status("Export complete! %d files saved." % (count + normal_count))
```
to:
```gdscript
	_append_log("\nExported %d color + %d normal + %d shadow files to %s/" % [count, normal_count, shadow_count, output_dir])
	_set_status("Export complete! %d files saved." % (count + normal_count + shadow_count))
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): export shadow sheets in wizard Step 5"
```

---

### Task 6: Load Shadow Animations in Step 7 (Apply to SpriteFrames)

**Files:**
- Modify: `scripts/tools/sprite_pipeline.gd:2541-2582` (`_try_add_export_folder`)
- Modify: `scripts/tools/sprite_pipeline.gd:2584-2678` (`_apply_to_spriteframes`)

**Step 1: Detect shadow files in `_try_add_export_folder`**

The current scan at line 2553 explicitly skips `_normal.png` files. We need to also skip `_shadow.png` files from the main sheets, and collect them separately.

Modify the file scan (line 2553) from:
```gdscript
		if file_name.ends_with(".png") and not file_name.ends_with(".png.import") and not file_name.ends_with("_normal.png"):
```
to:
```gdscript
		if file_name.ends_with(".png") and not file_name.ends_with(".png.import") and not file_name.ends_with("_normal.png") and not file_name.ends_with("_shadow.png"):
```

This ensures shadow PNGs don't get picked up as regular animations. The shadow files will be found automatically by `_apply_to_spriteframes` using the naming convention (same pattern as normal maps).

**Step 2: Add shadow animation loading in `_apply_to_spriteframes`**

After the normal map handling block (around line 2656), before the frame-building loop, add shadow detection:

```gdscript
			# Check for corresponding shadow map
			var shadow_filename := sheet_filename.get_basename() + "_shadow.png"
			var shadow_path := "%s/%s/%s" % [OUTPUT_BASE, folder, shadow_filename]
			var shadow_abs_path := ProjectSettings.globalize_path(shadow_path)
			var shadow_image: Image = null
			if FileAccess.file_exists(shadow_abs_path):
				shadow_image = Image.load_from_file(shadow_abs_path)
```

Then after the main animation frame loop (where AtlasTexture frames are added), add shadow animation creation:

```gdscript
			# Create shadow animation if shadow map exists
			if shadow_image:
				var shadow_anim_name := anim_name + "_shadow"
				if frames.has_animation(shadow_anim_name):
					frames.remove_animation(shadow_anim_name)
				frames.add_animation(shadow_anim_name)
				frames.set_animation_speed(shadow_anim_name, fps)
				frames.set_animation_loop(shadow_anim_name, loop)

				var shadow_texture := ImageTexture.create_from_image(shadow_image)
				for i in range(frame_count):
					var atlas_tex := AtlasTexture.new()
					atlas_tex.atlas = shadow_texture
					atlas_tex.region = Rect2(i * _export_frame_size, 0, _export_frame_size, _export_frame_size)
					frames.add_frame(shadow_anim_name, atlas_tex)

				_append_apply_log("    + shadow: %s (%s)" % [shadow_filename, shadow_anim_name])
				total_anims += 1
```

**Step 3: Commit**

```bash
git add scripts/tools/sprite_pipeline.gd
git commit -m "feat(shadow): load shadow animations in wizard Step 7"
```

---

### Task 7: Add ShadowSprite Layer to CharacterVisuals

**Files:**
- Modify: `scripts/combat/character_visuals.gd:20-22` (references section)
- Modify: `scripts/combat/character_visuals.gd:65-71` (`initialize`)
- Modify: `scripts/combat/character_visuals.gd:92-97` (after `_create_overlay_layer`)

**Step 1: Add shadow state variables**

After `overlay_sprite` declaration (line 37), add:

```gdscript
## Shadow layer
var shadow_sprite: AnimatedSprite2D = null
var _shadow_has_animations: bool = false  # True if SpriteFrames has _shadow anims
```

**Step 2: Add shadow constants**

After the `WEAPON_DIRECTION_COLOR` constant (line 53), add:

```gdscript
#===============================================================================
# SHADOW CONSTANTS
#===============================================================================

## Fallback ellipse shadow dimensions (fraction of frame size)
const SHADOW_ELLIPSE_WIDTH_RATIO := 0.8
const SHADOW_ELLIPSE_HEIGHT_RATIO := 0.3

## Shadow Y offset — positions shadow at character's feet
const SHADOW_Y_OFFSET := 14.0

## Light detection
const SHADOW_LIGHT_SEARCH_RADIUS := 512.0
const SHADOW_TRANSITION_SPEED := 3.3

## Shadow appearance ranges (based on light distance)
const SHADOW_CLOSE_DISTANCE := 64.0
const SHADOW_FAR_DISTANCE := 512.0
const SHADOW_CLOSE_OPACITY := 0.5
const SHADOW_FAR_OPACITY := 0.15
const SHADOW_NO_LIGHT_OPACITY := 0.15
const SHADOW_CLOSE_SCALE := 0.8
const SHADOW_FAR_SCALE := 1.3
const SHADOW_NO_LIGHT_SCALE := 1.3

## Current shadow targets (for lerping)
var _shadow_target_opacity := SHADOW_NO_LIGHT_OPACITY
var _shadow_target_scale := SHADOW_NO_LIGHT_SCALE
```

**Step 3: Add `_create_shadow_layer` function**

After `_create_overlay_layer` (line 97), add:

```gdscript
func _create_shadow_layer() -> void:
	shadow_sprite = AnimatedSprite2D.new()
	shadow_sprite.name = "ShadowSprite"
	shadow_sprite.z_index = -2
	shadow_sprite.position.y = SHADOW_Y_OFFSET
	shadow_sprite.modulate = Color(1, 1, 1, SHADOW_NO_LIGHT_OPACITY)
	add_child(shadow_sprite)
	# Move shadow to be the first child (renders behind everything)
	move_child(shadow_sprite, 0)
```

**Step 4: Add `_setup_shadow` function to detect and configure shadow mode**

```gdscript
func _setup_shadow() -> void:
	if not body_sprite or not body_sprite.sprite_frames:
		return

	# Check if SpriteFrames has any _shadow animations
	var anims := body_sprite.sprite_frames.get_animation_names()
	for anim_name in anims:
		if anim_name.ends_with("_shadow"):
			_shadow_has_animations = true
			break

	if _shadow_has_animations:
		# Use the same SpriteFrames — shadow plays _shadow variant animations
		shadow_sprite.sprite_frames = body_sprite.sprite_frames
	else:
		# Generate a simple ellipse fallback
		_generate_ellipse_shadow()
```

**Step 5: Add `_generate_ellipse_shadow` function**

```gdscript
func _generate_ellipse_shadow() -> void:
	## Generate a simple oval shadow texture for characters without shadow animations.
	if not body_sprite or not body_sprite.sprite_frames:
		return

	# Get frame size from the first available animation
	var anims := body_sprite.sprite_frames.get_animation_names()
	if anims.is_empty():
		return
	var first_tex := body_sprite.sprite_frames.get_frame_texture(anims[0], 0)
	if not first_tex:
		return

	var frame_w := first_tex.get_width()
	var frame_h := first_tex.get_height()
	var shadow_w := int(frame_w * SHADOW_ELLIPSE_WIDTH_RATIO)
	var shadow_h := int(frame_h * SHADOW_ELLIPSE_HEIGHT_RATIO)

	# Draw ellipse
	var img := Image.create(shadow_w, shadow_h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(shadow_w / 2.0, shadow_h / 2.0)
	var radius := Vector2(shadow_w / 2.0, shadow_h / 2.0)
	for y in range(shadow_h):
		for x in range(shadow_w):
			var dx := (x - center.x) / radius.x
			var dy := (y - center.y) / radius.y
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color.BLACK)

	var tex := ImageTexture.create_from_image(img)
	# Create a single-frame SpriteFrames for the ellipse
	var frames := SpriteFrames.new()
	frames.add_animation("ellipse")
	frames.add_frame("ellipse", tex)
	frames.set_animation_loop("ellipse", true)
	shadow_sprite.sprite_frames = frames
	shadow_sprite.play("ellipse")
```

**Step 6: Wire shadow creation into `initialize`**

Modify `initialize` (line 65) to add shadow setup:

```gdscript
func initialize(body: AnimatedSprite2D) -> void:
	body_sprite = body
	_create_shadow_layer()
	_create_weapon_layer()
	_create_effect_anchor()
	_create_overlay_layer()
	# Ensure weapon starts hidden
	set_weapon_visible(false)
	# Setup shadow after layers are created
	_setup_shadow()
```

**Step 7: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(shadow): add ShadowSprite layer with ellipse fallback"
```

---

### Task 8: Shadow Animation Sync

**Files:**
- Modify: `scripts/combat/character_visuals.gd` (`_process`, `_on_play_body_animation`)

**Step 1: Add shadow sync to `_on_play_body_animation`**

After the body sprite play call (line 395), add shadow sync:

```gdscript
	# Sync shadow animation
	_sync_shadow_animation(anim_name)
```

**Step 2: Add `_sync_shadow_animation` function**

```gdscript
func _sync_shadow_animation(base_anim_name: String) -> void:
	if not shadow_sprite or not shadow_sprite.sprite_frames:
		return

	if not _shadow_has_animations:
		# Ellipse mode — shadow is always the same, nothing to sync
		return

	# Resolve the shadow animation name
	var dir := current_direction
	if is_flipped:
		dir = "right"

	# Try: {base}_{dir}_shadow, then idle_{dir}_shadow
	var candidates: Array[String] = [
		"%s_%s_shadow" % [base_anim_name, dir],
		"idle_%s_shadow" % dir,
	]

	for candidate in candidates:
		if shadow_sprite.sprite_frames.has_animation(candidate):
			shadow_sprite.play(candidate)
			return

	# If no shadow animation at all, hide shadow
	shadow_sprite.visible = false
```

**Step 3: Add frame sync in `_process`**

At the top of `_process` (after the null check at line 106), add:

```gdscript
	# Keep shadow frame in sync with body
	if shadow_sprite and shadow_sprite.visible and _shadow_has_animations:
		if body_sprite.sprite_frames and shadow_sprite.sprite_frames:
			shadow_sprite.frame = body_sprite.frame
	# Flip shadow to match body
	if shadow_sprite:
		shadow_sprite.flip_h = is_flipped
```

**Step 4: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(shadow): sync shadow animation and frame with body"
```

---

### Task 9: Runtime Light Response

**Files:**
- Modify: `scripts/combat/character_visuals.gd` (`_process`)

**Step 1: Add `_update_shadow_light_response` function**

```gdscript
func _update_shadow_light_response(delta: float) -> void:
	if not shadow_sprite:
		return

	# Find nearest PointLight2D in "lights" group
	var nearest_dist := SHADOW_LIGHT_SEARCH_RADIUS + 1.0
	var lights := get_tree().get_nodes_in_group("lights")
	for light_node in lights:
		if light_node is PointLight2D and light_node.visible:
			var dist := global_position.distance_to(light_node.global_position)
			if dist < nearest_dist:
				nearest_dist = dist

	# Determine target opacity and scale based on distance
	if nearest_dist > SHADOW_LIGHT_SEARCH_RADIUS:
		# No light nearby — ambient fallback
		_shadow_target_opacity = SHADOW_NO_LIGHT_OPACITY
		_shadow_target_scale = SHADOW_NO_LIGHT_SCALE
	else:
		# Interpolate between close and far values
		var t := clampf((nearest_dist - SHADOW_CLOSE_DISTANCE) / (SHADOW_FAR_DISTANCE - SHADOW_CLOSE_DISTANCE), 0.0, 1.0)
		_shadow_target_opacity = lerpf(SHADOW_CLOSE_OPACITY, SHADOW_FAR_OPACITY, t)
		_shadow_target_scale = lerpf(SHADOW_CLOSE_SCALE, SHADOW_FAR_SCALE, t)

	# Smooth lerp toward targets
	var lerp_speed := SHADOW_TRANSITION_SPEED * delta
	shadow_sprite.modulate.a = lerpf(shadow_sprite.modulate.a, _shadow_target_opacity, lerp_speed)
	var current_scale := shadow_sprite.scale.x
	var new_scale := lerpf(current_scale, _shadow_target_scale, lerp_speed)
	shadow_sprite.scale = Vector2(new_scale, new_scale)

	shadow_sprite.visible = true
```

**Step 2: Call from `_process`**

At the end of `_process` (after the weapon update), add:

```gdscript
	_update_shadow_light_response(_delta)
```

Note: the `_delta` parameter is already available (line 104) — just need to rename it from `_delta` to `delta` since it's now used, or pass `_delta` directly.

**Step 3: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(shadow): add light-responsive shadow opacity and scale"
```

---

### Task 10: Shadow Direction Update on Facing Change

**Files:**
- Modify: `scripts/combat/character_visuals.gd` (`set_direction`)

**Step 1: Update shadow when direction changes**

At the end of `set_direction` (line 439), add:

```gdscript
	# Update shadow animation for new direction
	if shadow_sprite and _shadow_has_animations and body_sprite:
		var current_body_anim := body_sprite.animation as String
		# Strip direction suffix to get base name
		var base_name := current_body_anim
		for dir_suffix in ["_down", "_up", "_right"]:
			if base_name.ends_with(dir_suffix):
				base_name = base_name.substr(0, base_name.length() - dir_suffix.length())
				break
		_sync_shadow_animation(base_name)
```

**Step 2: Commit**

```bash
git add scripts/combat/character_visuals.gd
git commit -m "feat(shadow): update shadow on direction change"
```

---

### Task 11: Manual Testing

**No code changes.** Verify the system works end-to-end.

**Step 1: Test ellipse fallback**

Run the game. All characters (player and enemies) should now show a faint oval shadow beneath them, since no shadow animations exist in SpriteFrames yet. Verify:
- Shadow is positioned at feet
- Shadow opacity changes near light sources
- Shadow scales slightly near/far from lights
- Shadow doesn't break any existing animations

**Step 2: Test wizard shadow capture**

Open the sprite pipeline wizard (`scenes/tools/sprite_pipeline.tscn`, F6). Run through the 7 steps with any model:
1. Step 2: After capture, click "Shadow" button — should show top-down black silhouettes
2. Step 5: Export should report shadow files saved
3. Step 7: Apply should report `_shadow` animations created

**Step 3: Test full pipeline result**

After applying in Step 7, run the game. The player character should now show the captured silhouette shadow instead of the ellipse fallback.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix(shadow): address issues found during manual testing"
```
