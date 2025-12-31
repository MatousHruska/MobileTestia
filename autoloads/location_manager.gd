extends Node
class_name LocationManagerClass
## LocationManager - Tracks player location within zones
## Handles location enter/exit, settings inheritance, and discovery

## Signals
signal location_entered(location_id: String)
signal location_exited(location_id: String)
signal settings_changed(setting_name: String, new_value: Variant)

## Current state
var current_location_id: String = ""
var current_zone_id: String = ""
var _location_stack: Array[String] = []  # For nested/overlapping locations

## Discovered locations (for future discovery popup system)
var discovered_locations: Array[String] = []


func _ready() -> void:
	# Connect to zone changes
	if Game:
		Game.zone_changed.connect(_on_zone_changed)

	Debug.info("Location", "LocationManager initialized")


#===============================================================================
# PUBLIC API
#===============================================================================

## Enter a location (called by Location nodes)
func enter_location(location_id: String) -> void:
	if location_id.is_empty():
		return

	# Add to stack (for overlapping locations)
	if location_id not in _location_stack:
		_location_stack.append(location_id)

	# Update current location to most recently entered
	var previous_location := current_location_id
	current_location_id = location_id

	# Track discovery
	if location_id not in discovered_locations:
		discovered_locations.append(location_id)
		_on_location_discovered(location_id)

	# Emit signal
	location_entered.emit(location_id)

	# Check for settings changes
	_check_settings_changes(previous_location, current_location_id)

	Debug.info("Location", "Entered location: %s" % location_id)


## Exit a location (called by Location nodes)
func exit_location(location_id: String) -> void:
	if location_id.is_empty():
		return

	# Remove from stack
	_location_stack.erase(location_id)

	var previous_location := current_location_id

	# Update current location to next in stack (or empty)
	if _location_stack.is_empty():
		current_location_id = ""
	else:
		current_location_id = _location_stack[-1]

	# Emit signal
	location_exited.emit(location_id)

	# Check for settings changes
	_check_settings_changes(previous_location, current_location_id)

	Debug.info("Location", "Exited location: %s (now: %s)" % [location_id, current_location_id])


## Get current location data
func get_current_location() -> Dictionary:
	if current_location_id.is_empty():
		return {}
	return DatabaseLoader.get_location(current_location_id)


## Get current zone data
func get_current_zone() -> Dictionary:
	if current_zone_id.is_empty():
		return {}
	return DatabaseLoader.get_zone(current_zone_id)


## Check if player is in any location (vs just zone)
func is_in_location() -> bool:
	return not current_location_id.is_empty()


## Check if player is in a specific location
func is_in_location_id(location_id: String) -> bool:
	return location_id in _location_stack


## Check if current area (location or zone) is safe
func is_current_area_safe() -> bool:
	if not current_location_id.is_empty():
		return DatabaseLoader.is_location_safe(current_location_id)

	# Fall back to zone
	if not current_zone_id.is_empty():
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get("is_safe_zone", false)

	return false


## Check if PvP is enabled in current area
func is_pvp_enabled() -> bool:
	if not current_location_id.is_empty():
		return DatabaseLoader.is_location_pvp_enabled(current_location_id)

	# Fall back to zone
	if not current_zone_id.is_empty():
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get("is_pvp_enabled", false)

	return false


## Get status effect for current area
func get_current_status_effect() -> String:
	if not current_location_id.is_empty():
		return DatabaseLoader.get_location_status_effect(current_location_id)

	# Fall back to zone
	if not current_zone_id.is_empty():
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get("status_effect_id", "")

	return ""


## Get music for current area
func get_current_music() -> String:
	if not current_location_id.is_empty():
		return DatabaseLoader.get_location_music(current_location_id)

	# Fall back to zone
	if not current_zone_id.is_empty():
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get("music_track", "")

	return ""


## Get ambient sound for current area
func get_current_ambient() -> String:
	if not current_location_id.is_empty():
		return DatabaseLoader.get_location_ambient(current_location_id)

	# Fall back to zone
	if not current_zone_id.is_empty():
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get("ambient_sound", "")

	return ""


## Check if a location has been discovered
func is_location_discovered(location_id: String) -> bool:
	return location_id in discovered_locations


#===============================================================================
# INTERNAL
#===============================================================================

func _on_zone_changed(zone_id: String) -> void:
	current_zone_id = zone_id

	# Clear location state on zone change
	current_location_id = ""
	_location_stack.clear()

	Debug.log("Location", "Zone changed to: %s" % zone_id)


func _on_location_discovered(location_id: String) -> void:
	var loc_data := DatabaseLoader.get_location(location_id)
	var discovery_popup: String = loc_data.get("discovery_popup", "")

	# Just log for now - popup system will be added later
	if not discovery_popup.is_empty():
		Debug.info("Location", "Discovery popup (future): %s - %s" % [
			loc_data.get("name", location_id),
			discovery_popup
		])
	else:
		Debug.log("Location", "Discovered location: %s" % loc_data.get("name", location_id))


func _check_settings_changes(old_location_id: String, new_location_id: String) -> void:
	# Compare settings between old and new location
	# Emit signals for any changes so other systems can react

	var settings := ["is_safe_zone", "is_pvp_enabled", "status_effect_id", "music_track", "ambient_sound"]

	for setting in settings:
		var old_value = _get_effective_setting(old_location_id, setting)
		var new_value = _get_effective_setting(new_location_id, setting)

		if old_value != new_value:
			settings_changed.emit(setting, new_value)

			# Handle specific settings
			match setting:
				"music_track":
					_on_music_changed(new_value)
				"ambient_sound":
					_on_ambient_changed(new_value)
				"status_effect_id":
					_on_status_effect_changed(old_value, new_value)


func _get_effective_setting(location_id: String, setting_name: String):
	if location_id.is_empty():
		# Just zone settings
		if current_zone_id.is_empty():
			return null
		var zone := DatabaseLoader.get_zone(current_zone_id)
		return zone.get(setting_name, null)

	return DatabaseLoader.get_effective_setting(location_id, setting_name, null)


func _on_music_changed(new_music: String) -> void:
	# TODO: Tell audio manager to change music
	if not new_music.is_empty():
		Debug.log("Location", "Music should change to: %s" % new_music)


func _on_ambient_changed(new_ambient: String) -> void:
	# TODO: Tell audio manager to change ambient
	if not new_ambient.is_empty():
		Debug.log("Location", "Ambient should change to: %s" % new_ambient)


func _on_status_effect_changed(old_effect: String, new_effect: String) -> void:
	# TODO: Apply/remove status effects
	if not old_effect.is_empty():
		Debug.log("Location", "Should remove status effect: %s" % old_effect)
	if not new_effect.is_empty():
		Debug.log("Location", "Should apply status effect: %s" % new_effect)


#===============================================================================
# PERSISTENCE
#===============================================================================

## Get save data for persistence
func get_save_data() -> Dictionary:
	return {
		"discovered_locations": discovered_locations.duplicate(),
	}


## Load save data from persistence
func load_save_data(data: Dictionary) -> void:
	discovered_locations = data.get("discovered_locations", [])
	Debug.log("Location", "Loaded %d discovered locations" % discovered_locations.size())


#===============================================================================
# DEBUG
#===============================================================================

func debug_print_state() -> void:
	Debug.snapshot("Location", "LocationManager State", {
		"current_zone": current_zone_id,
		"current_location": current_location_id,
		"location_stack": _location_stack,
		"discovered_count": discovered_locations.size(),
		"is_safe": is_current_area_safe(),
		"pvp_enabled": is_pvp_enabled(),
	})
