extends Node
class_name PopupMessageManagerClass
## PopupMessageManager - Handles screen popup announcements
## Displays messages at top-center of screen for zone/location entry, quest updates, etc.

## Signals
signal popup_shown(popup_id: String, title: String, subtitle: String)
signal popup_hidden(popup_id: String)

## Configuration
const DEFAULT_DURATION := 3.0
const FADE_IN_DURATION := 0.3
const FADE_OUT_DURATION := 0.5
const POPUP_OFFSET_Y := 80  # Pixels from top of screen

## State
var _current_container: Control = null
var _current_popup: Control = null
var _current_popup_id: String = ""
var _current_priority: int = 0
var _popup_queue: Array[Dictionary] = []

## UI
var _popup_scene: PackedScene = null
var _canvas_layer: CanvasLayer = null

## Settings
var enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Create canvas layer for popups (high layer to be on top)
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 90  # Below UI layer 100, but above game
	add_child(_canvas_layer)

	# Preload UI scene
	_popup_scene = preload("res://scenes/ui/popup_message/popup_message.tscn")

	# Connect to game events
	_connect_game_signals()

	Debug.info("PopupMessage", "PopupMessageManager initialized")


#===============================================================================
# PUBLIC API
#===============================================================================

## Trigger a popup message event
## trigger_event: The event type (zone_enter, quest_start, etc.)
## context: Dictionary with filter values and auto-fill data
func trigger_event(trigger_event: String, context: Dictionary = {}) -> void:
	if not enabled:
		return

	# During cutscenes, queue the popup for after
	if Cutscene and Cutscene.is_playing:
		# For cutscene_end events, still process them
		if trigger_event != "cutscene_end":
			Debug.log("PopupMessage", "Cutscene playing, queuing popup")
			_popup_queue.append({"event": trigger_event, "context": context})
			return

	# Check for custom popup message in database
	var custom_popup := _get_matching_popup(trigger_event, context)

	if not custom_popup.is_empty():
		# Use custom popup from database
		_show_popup_from_data(custom_popup)
	else:
		# Auto-generate popup based on event type
		_auto_generate_popup(trigger_event, context)


## Show a popup directly with custom content
func show_popup(title: String, subtitle: String = "", icon: String = "none", duration: float = DEFAULT_DURATION, priority: int = 5) -> void:
	if not enabled:
		return

	var popup_data := {
		"id": "manual_%d" % Time.get_ticks_msec(),
		"title": title,
		"subtitle": subtitle,
		"icon": icon,
		"duration": duration,
		"priority": priority,
	}

	_display_popup(popup_data)


## Show popup by database ID
func show_popup_by_id(popup_id: String) -> void:
	var popup_data := DatabaseLoader.get_popup_message(popup_id)
	if popup_data.is_empty():
		Debug.warn("PopupMessage", "Popup not found: %s" % popup_id)
		return

	_show_popup_from_data(popup_data)


## Hide current popup immediately
func hide_current_popup() -> void:
	if _current_popup and is_instance_valid(_current_popup):
		_current_popup.hide_popup()


#===============================================================================
# POPUP GENERATION
#===============================================================================

func _get_matching_popup(trigger_event: String, context: Dictionary) -> Dictionary:
	var matches := DatabaseLoader.get_matching_popup_messages(trigger_event, context)
	if matches.is_empty():
		return {}

	# Sort by priority (highest first) and return first match
	matches.sort_custom(func(a, b): return int(a.get("priority", 5)) > int(b.get("priority", 5)))
	return matches[0]


func _auto_generate_popup(trigger_event: String, context: Dictionary) -> void:
	var title := ""
	var subtitle := ""
	var icon := "none"
	var duration := DEFAULT_DURATION
	var priority := 5

	match trigger_event:
		"zone_enter":
			var zone_id: String = context.get("zone_id", "")
			var zone_data := DatabaseLoader.get_zone(zone_id)
			if zone_data.is_empty():
				return

			# Only show popup if discovery_popup is true
			var show_popup: bool = zone_data.get("discovery_popup", false)
			if not show_popup:
				return

			# Skip zone popup if player is in a location (location popup takes priority)
			if LocationManager and LocationManager.is_in_location():
				var loc_data := LocationManager.get_current_location()
				if loc_data.get("discovery_popup", false):
					Debug.log("PopupMessage", "Skipping zone popup - location popup takes priority")
					return

			title = "Entering"
			subtitle = zone_data.get("name", zone_id)
			icon = "location"
			priority = 6

		"location_enter":
			var location_id: String = context.get("location_id", "")
			var loc_data := DatabaseLoader.get_location(location_id)
			if loc_data.is_empty():
				return

			# Only show popup if discovery_popup is true
			var show_popup: bool = loc_data.get("discovery_popup", false)
			if not show_popup:
				return

			title = "Entering"
			subtitle = loc_data.get("name", location_id)
			icon = "location"
			priority = 5

		"quest_start":
			var quest_id: String = context.get("quest_id", "")
			var quest_data := DatabaseLoader.get_quest(quest_id)
			if quest_data.is_empty():
				return

			title = "New Quest"
			subtitle = quest_data.get("name", quest_id)
			icon = "quest"
			priority = 7

		"quest_complete":
			var quest_id: String = context.get("quest_id", "")
			var quest_data := DatabaseLoader.get_quest(quest_id)
			if quest_data.is_empty():
				return

			title = "Quest Complete"
			subtitle = quest_data.get("name", quest_id)
			icon = "quest"
			priority = 7

		"quest_objective":
			title = context.get("title", "New Objective")
			subtitle = context.get("subtitle", "")
			icon = "quest"
			priority = 8

		_:
			# Unknown event type, don't auto-generate
			return

	if title.is_empty() and subtitle.is_empty():
		return

	var popup_data := {
		"id": "auto_%s_%d" % [trigger_event, Time.get_ticks_msec()],
		"title": title,
		"subtitle": subtitle,
		"icon": icon,
		"duration": duration,
		"priority": priority,
	}

	_display_popup(popup_data)


func _show_popup_from_data(popup_data: Dictionary) -> void:
	_display_popup(popup_data)


#===============================================================================
# DISPLAY
#===============================================================================

func _display_popup(popup_data: Dictionary) -> void:
	var popup_id: String = popup_data.get("id", "")
	var priority: int = int(popup_data.get("priority", 5))

	# Check if we should replace current popup
	if _current_popup and is_instance_valid(_current_popup):
		if priority <= _current_priority:
			# Lower/equal priority, queue it
			Debug.log("PopupMessage", "Queuing lower priority popup", popup_id)
			_popup_queue.append({"data": popup_data})
			return
		else:
			# Higher priority, replace current
			if _current_popup.has_method("hide_popup"):
				_current_popup.hide_popup()

	# Create and show popup
	_create_popup(popup_data)


func _create_popup(popup_data: Dictionary) -> void:
	if _popup_scene == null:
		Debug.warn("PopupMessage", "Popup scene not loaded")
		return

	# Create a full-rect container for proper anchor calculations
	var container := Control.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(container)

	var popup = _popup_scene.instantiate()
	container.add_child(popup)

	# Store references
	_current_container = container
	_current_popup = popup
	_current_popup_id = popup_data.get("id", "")
	_current_priority = int(popup_data.get("priority", 5))

	# Initialize popup
	var title: String = popup_data.get("title", "")
	var subtitle: String = popup_data.get("subtitle", "")
	var icon: String = popup_data.get("icon", "none")
	var duration: float = float(popup_data.get("duration", DEFAULT_DURATION))
	var sound: String = popup_data.get("sound", "")

	if popup.has_method("show_popup"):
		popup.show_popup(title, subtitle, icon, duration)

	# Connect to finished signal - also free the container
	if popup.has_signal("finished"):
		popup.finished.connect(_on_popup_finished.bind(_current_popup_id, container))

	# Play sound if specified
	if not sound.is_empty():
		_play_sound(sound)

	# Emit signal
	popup_shown.emit(_current_popup_id, title, subtitle)

	Debug.info("PopupMessage", "Showing popup", {"id": _current_popup_id, "title": title, "subtitle": subtitle})


func _on_popup_finished(popup_id: String, container: Control = null) -> void:
	if popup_id == _current_popup_id:
		_current_container = null
		_current_popup = null
		_current_popup_id = ""
		_current_priority = 0

		# Free the container if provided
		if container and is_instance_valid(container):
			container.queue_free()

		popup_hidden.emit(popup_id)

		# Process queue
		_process_queue()


func _process_queue() -> void:
	if _popup_queue.is_empty():
		return

	if _current_popup and is_instance_valid(_current_popup):
		return  # Still showing a popup

	var next_item: Dictionary = _popup_queue.pop_front()

	if next_item.has("data"):
		# Direct popup data
		_display_popup(next_item["data"])
	elif next_item.has("event"):
		# Event to process
		trigger_event(next_item["event"], next_item.get("context", {}))


func _play_sound(sound_id: String) -> void:
	# TODO: Implement sound playback when audio system is ready
	Debug.log("PopupMessage", "Sound playback not implemented", sound_id)


#===============================================================================
# GAME EVENT CONNECTIONS
#===============================================================================

func _connect_game_signals() -> void:
	# Zone changes
	if Game:
		Game.zone_changed.connect(_on_zone_changed)

	# Quest events
	if QuestManager:
		if QuestManager.has_signal("quest_started"):
			QuestManager.quest_started.connect(_on_quest_started)
		if QuestManager.has_signal("quest_completed"):
			QuestManager.quest_completed.connect(_on_quest_completed)

	# Location events
	if LocationManager:
		LocationManager.location_entered.connect(_on_location_entered)

	# Cutscene events
	if Cutscene:
		if Cutscene.has_signal("cutscene_finished"):
			Cutscene.cutscene_finished.connect(_on_cutscene_finished)

	Debug.log("PopupMessage", "Connected to game signals")


#===============================================================================
# EVENT HANDLERS
#===============================================================================

func _on_zone_changed(zone_id: String) -> void:
	# Small delay to let zone load
	await get_tree().create_timer(0.3).timeout

	# Look up database zone ID
	var db_zone_id := ""
	for zone in DatabaseLoader.zones_list:
		var id: String = zone.get("id", "")
		if id == zone_id or id == "zone_" + zone_id or id.ends_with("_" + zone_id):
			db_zone_id = id
			break

	trigger_event("zone_enter", {"zone_id": db_zone_id if db_zone_id else zone_id})


func _on_location_entered(location_id: String) -> void:
	trigger_event("location_enter", {"location_id": location_id})


func _on_quest_started(quest_id: String) -> void:
	trigger_event("quest_start", {"quest_id": quest_id})


func _on_quest_completed(quest_id: String) -> void:
	trigger_event("quest_complete", {"quest_id": quest_id})


func _on_cutscene_finished(cutscene_id: String) -> void:
	# Check for cutscene_end popups
	trigger_event("cutscene_end", {"cutscene_id": cutscene_id})

	# Process any queued popups
	await get_tree().create_timer(0.5).timeout
	_process_queue()


#===============================================================================
# DEBUG
#===============================================================================

## Debug: Force show a popup
func debug_show(title: String, subtitle: String = "") -> void:
	show_popup(title, subtitle, "info", 5.0, 10)


## Debug: Print current state
func debug_print_state() -> void:
	Debug.snapshot("PopupMessage", "State", {
		"enabled": enabled,
		"has_current_popup": _current_popup != null,
		"current_popup_id": _current_popup_id,
		"current_priority": _current_priority,
		"queue_size": _popup_queue.size(),
	})
