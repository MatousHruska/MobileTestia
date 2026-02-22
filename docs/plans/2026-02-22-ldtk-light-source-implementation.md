# LDtk Light Source Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add LightSource entity support to the LDtk importer and chunk manager so PointLight2D nodes are spawned from map-placed entities.

**Architecture:** The LDtk importer extracts LightSource entities (with color, intensity, radius, height fields) into per-zone JSON. At runtime, chunk_manager reads these and spawns PointLight2D nodes using a shared GradientTexture2D.

**Tech Stack:** GDScript, Godot 4, LDtk, PointLight2D, GradientTexture2D

---

### Task 1: Add LightSource to LDtk Importer

**Files:**
- Modify: `ldtk_importer.gd`

**Context:** The importer processes LDtk entity types in `_extract_entities()` via a `match` on `entity_type`. Entities are collected into typed arrays, then grouped by zone and exported to JSON in `_export_entities_summary()`. Follow the exact pattern used by existing entities (e.g., `chestspawn`, `npcspawn`).

**Step 1: Add "lights" array to all entity collection points**

There are 3 places that initialize the entity dictionary structure. Add `"lights": []` to each:

In `_run()` (around line 80-97), add after `"patrol_waypoints": []`:
```gdscript
	# Lighting
	"lights": [],
```

In `_extract_entities()` (around line 582-600), add after `"patrol_waypoints": []`:
```gdscript
	# Lighting
	"lights": [],
```

In `_ensure_zone_data()` (around line 971-991), add after `"patrol_waypoints": []`:
```gdscript
	# Lighting
	"lights": [],
```

**Step 2: Add LightSource entity matching**

In `_extract_entities()`, inside the `match entity_type:` block (after the `"patrolwaypoint":` case around line 739-747), add:

```gdscript
			"lightsource":
				var color_val = fields.get("light_color", "#FFAA44")
				# LDtk color fields come as "#RRGGBB" strings
				result.lights.append({
					"zone_id": zone_id,
					"position_x": position.x,
					"position_y": position.y,
					"color": color_val if color_val != null else "#FFAA44",
					"intensity": float(fields.get("intensity", 1.5)),
					"radius": int(fields.get("radius", 128)),
					"height": float(fields.get("height", 50.0))
				})
```

**Step 3: Add light export in `_export_entities_summary()`**

After the patrol waypoints export block (around line 930-939), add:

```gdscript
	# Process lights
	for light in entities.lights:
		var zone_id: String = light.get("zone_id", "unknown")
		_ensure_zone_data(zones_data, zone_id)
		zones_data[zone_id].lights.append({
			"position": {"x": light.get("position_x", 0), "y": light.get("position_y", 0)},
			"color": light.get("color", "#FFAA44"),
			"intensity": light.get("intensity", 1.5),
			"radius": light.get("radius", 128),
			"height": light.get("height", 50.0)
		})
```

**Step 4: Update entity count in `_process_level()` print statement**

In `_process_level()` (around line 204-216), update the print to include lights. Add `, %d lights` to the format string and `entities.lights.size()` to the arguments.

**Step 5: Update entity summary print in `_export_entities_summary()`**

In the summary section (around line 946-968), add lights to the entity count (line ~949) and add a print line for lights similar to the existing conditional prints:

```gdscript
	entity_count += zd.lights.size()
```

And add after the patrol_waypoints print block:
```gdscript
		if zd.lights.size() > 0:
			print("    lights: %d" % [zd.lights.size()])
```

**Step 6: Verify the importer script loads without errors**

Open the Godot editor. The script should parse without errors. You cannot run the importer without actual LightSource entities in the LDtk file, but the code should be syntactically valid.

**Step 7: Commit**

```bash
git add ldtk_importer.gd
git commit -m "feat: add LightSource entity support to LDtk importer"
```

---

### Task 2: Add Light Spawning to ChunkManager

**Files:**
- Modify: `autoloads/chunk_manager.gd`

**Context:** `chunk_manager.gd` spawns entities in `_spawn_chunk_entities()` (line ~881). Each entity type has a spawning loop that checks if the entity's world position falls within the chunk bounds, then calls a type-specific `_spawn_*()` function. The spawned node is positioned relative to the chunk origin and tagged with metadata. Follow this exact pattern.

**Step 1: Add light spawning loop in `_spawn_chunk_entities()`**

After the trigger areas loop (around line 980-987), before the `_chunk_entities` tracking (line ~990), add:

```gdscript
	# Spawn lights
	for light_data in _zone_entities.get("lights", []):
		var pos: Dictionary = light_data.get("position", {})
		var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))
		if chunk_bounds.has_point(world_pos):
			var entity := _spawn_light(light_data, chunk_node, chunk_origin, chunk_id)
			if entity:
				spawned_entities.append(entity)
```

**Step 2: Create the shared light gradient texture**

Add a class-level variable near the other state variables at the top of the file (look for variable declarations, likely near line ~160-180):

```gdscript
var _light_gradient_texture: GradientTexture2D = null
```

Add a function to create/return the shared texture:

```gdscript
func _get_light_texture() -> GradientTexture2D:
	if _light_gradient_texture != null:
		return _light_gradient_texture
	_light_gradient_texture = GradientTexture2D.new()
	_light_gradient_texture.width = 256
	_light_gradient_texture.height = 256
	_light_gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_gradient_texture.fill_from = Vector2(0.5, 0.5)
	_light_gradient_texture.fill_to = Vector2(0.5, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	_light_gradient_texture.gradient = gradient
	return _light_gradient_texture
```

**Step 3: Create the `_spawn_light()` function**

Add this function near the other `_spawn_*()` functions (after `_spawn_trigger_area()` or similar):

```gdscript
func _spawn_light(data: Dictionary, parent: Node2D, chunk_origin: Vector2, chunk_id: String) -> Node2D:
	var pos: Dictionary = data.get("position", {})
	var world_pos := Vector2(pos.get("x", 0), pos.get("y", 0))

	var light := PointLight2D.new()
	light.name = "Light_%d_%d" % [int(world_pos.x), int(world_pos.y)]
	light.position = world_pos - chunk_origin

	# Color (hex string from LDtk)
	var color_str: String = data.get("color", "#FFAA44")
	light.color = Color.html(color_str)

	# Intensity
	light.energy = float(data.get("intensity", 1.5))

	# Height (for normal map interaction)
	light.height = float(data.get("height", 50.0))

	# Texture and scale
	var texture := _get_light_texture()
	light.texture = texture
	var radius: float = float(data.get("radius", 128))
	light.texture_scale = radius / (texture.width * 0.5)

	# Metadata for chunk cleanup
	light.set_meta("chunk_spawned", true)
	light.set_meta("chunk_id", chunk_id)
	light.set_meta("world_position", world_pos)

	parent.add_child(light)
	return light
```

**Step 4: Update debug entity summary if one exists**

Search for the debug summary function that prints entity counts (look for `debug_print_state` or similar). If it lists entity types, add lights. For example, in the diagnostics print (around line ~2452):

```gdscript
Debug.info("ChunkManager", "  Lights: %d" % _zone_entities.get("lights", []).size())
```

**Step 5: Verify the script loads without errors**

Open Godot editor. The chunk_manager.gd should parse without errors.

**Step 6: Commit**

```bash
git add autoloads/chunk_manager.gd
git commit -m "feat: add PointLight2D spawning from LDtk LightSource entities"
```

---

### Task 3: Manual Integration Test

**No code changes — this is a verification task.**

**Step 1: Create LightSource entity in LDtk**

Open `maps/MobileTestia.ldtk` in LDtk editor. In the entity definitions:
1. Create new entity `LightSource`
2. Set color to `#FFDD00`, size 16x16
3. Add fields:
   - `light_color`: Color, default `#FFAA44`
   - `intensity`: Float, default `1.5`
   - `radius`: Int, default `128`
   - `height`: Float, default `50.0`

**Step 2: Place test lights**

Place 2-3 LightSource entities on the test zone map near where the player spawns. Try different colors/intensities.

**Step 3: Run the importer**

In Godot editor: Script > Run (`ldtk_importer.gd`). Check the output — should show light count in the entity summary.

**Step 4: Verify zone entity JSON**

Open the zone entity JSON file (e.g., `maps/entities/zone_ldtk_test.json`). Confirm the `"lights"` array contains your placed lights with correct position/color/intensity/radius/height values.

**Step 5: Play the scene**

Run the game. Walk near the placed lights. Verify:
- PointLight2D nodes appear at the correct positions
- Light color and intensity match what was set in LDtk
- Normal-mapped sprites react to the light (color shifts based on light direction)

**Step 6: Commit LDtk changes if test passes**

```bash
git add maps/
git commit -m "test: add LightSource entities to test zone for normal map verification"
```
