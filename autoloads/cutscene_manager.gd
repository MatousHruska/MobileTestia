extends Node
class_name CutsceneManager
## CutsceneManager - Handles playing cutscene sequences
## Cutscenes are data-driven timelines of actions (dialogue, movement, camera, etc.)

## Signals
signal cutscene_started(cutscene_id: String)
signal cutscene_finished(cutscene_id: String)
signal cutscene_action_started(action_type: String)
signal dialogue_displayed(speaker: String, text: String)
signal dialogue_advance_requested

## State
var is_playing: bool = false
var current_cutscene_id: String = ""
var current_actions: Array = []
var current_action_index: int = 0
var is_waiting_for_input: bool = false

## UI Reference
var _dialogue_ui: CanvasLayer = null
const DIALOGUE_UI_SCENE := preload("res://scenes/ui/cutscene/cutscene_dialogue_ui.tscn")

## Action executors - map action type to handler function
var _action_handlers: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_action_handlers()

	# Connect to zone changes to trigger zone_enter cutscenes
	Game.zone_changed.connect(_on_zone_changed)

	Debug.info("Cutscene", "CutsceneManager initialized")


## Called when player enters a new zone
func _on_zone_changed(zone_name: String) -> void:
	# Check for zone_enter cutscene
	var cutscene := DatabaseLoader.get_zone_entry_cutscene(zone_name)
	if cutscene.is_empty():
		return

	var cutscene_id: String = cutscene.get("id", "")
	var once_only: bool = cutscene.get("once_only", false)

	# Check if already played (for once_only cutscenes)
	if once_only and _has_played_cutscene(cutscene_id):
		return

	# Delay slightly to let zone finish loading
	await get_tree().create_timer(0.1).timeout

	play(cutscene_id)

	if once_only:
		_mark_cutscene_played(cutscene_id)


## Track played cutscenes (for once_only)
var _played_cutscenes: Array[String] = []

func _has_played_cutscene(cutscene_id: String) -> bool:
	return cutscene_id in _played_cutscenes

func _mark_cutscene_played(cutscene_id: String) -> void:
	if cutscene_id not in _played_cutscenes:
		_played_cutscenes.append(cutscene_id)


func _register_action_handlers() -> void:
	_action_handlers = {
		"dialogue": _execute_dialogue,
		"wait": _execute_wait,
		"fade_in": _execute_fade_in,
		"fade_out": _execute_fade_out,
		"move": _execute_move,
		"spawn": _execute_spawn,
		"despawn": _execute_despawn,
		"camera_pan": _execute_camera_pan,
		"camera_shake": _execute_camera_shake,
		"camera_reset": _execute_camera_reset,
		"play_sound": _execute_play_sound,
		"set_facing": _execute_set_facing,
		"parallel": _execute_parallel,
	}


#===============================================================================
# PUBLIC API
#===============================================================================

## Play a cutscene by ID from database
func play(cutscene_id: String) -> void:
	if is_playing:
		Debug.warn("Cutscene", "Already playing a cutscene, ignoring request", cutscene_id)
		return

	var cutscene_data := _get_cutscene_data(cutscene_id)
	if cutscene_data.is_empty():
		Debug.err("Cutscene", "Cutscene not found", cutscene_id)
		return

	current_cutscene_id = cutscene_id
	current_actions = cutscene_data.get("actions", [])
	current_action_index = 0
	is_playing = true
	is_waiting_for_input = false

	# Enter cutscene state
	Game.start_cutscene()

	# Put camera in cutscene mode (stops following player)
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("enter_cutscene_mode"):
		camera.enter_cutscene_mode()

	# Show dialogue UI
	_show_dialogue_ui()

	cutscene_started.emit(cutscene_id)
	Debug.info("Cutscene", "Playing cutscene", cutscene_id)

	# Start executing actions
	_execute_next_action()


## Advance the cutscene (called when player taps)
func advance() -> void:
	Debug.info("Cutscene", "advance() called", {"is_playing": is_playing, "is_waiting_for_input": is_waiting_for_input, "action_index": current_action_index})
	if not is_playing:
		Debug.warn("Cutscene", "advance() ignored - not playing")
		return

	dialogue_advance_requested.emit()

	if is_waiting_for_input:
		Debug.info("Cutscene", "Advancing to next action")
		is_waiting_for_input = false
		current_action_index += 1  # Move to next action before executing
		_execute_next_action()
	else:
		Debug.info("Cutscene", "Not waiting for input, ignoring advance")


## Skip to end of cutscene
func skip() -> void:
	if not is_playing:
		return

	Debug.info("Cutscene", "Skipping cutscene", current_cutscene_id)
	_finish_cutscene()


#===============================================================================
# ACTION EXECUTION
#===============================================================================

func _execute_next_action() -> void:
	Debug.info("Cutscene", "Execute next action", {"index": current_action_index, "total": current_actions.size()})

	if current_action_index >= current_actions.size():
		_finish_cutscene()
		return

	var action: Dictionary = current_actions[current_action_index]
	var action_type: String = action.get("type", "")

	Debug.info("Cutscene", "Executing action", {"index": current_action_index, "type": action_type})

	if action_type.is_empty():
		Debug.warn("Cutscene", "Action missing type at index", current_action_index)
		current_action_index += 1
		_execute_next_action()
		return

	cutscene_action_started.emit(action_type)

	if _action_handlers.has(action_type):
		var handler: Callable = _action_handlers[action_type]
		handler.call(action)
	else:
		Debug.warn("Cutscene", "Unknown action type", action_type)
		current_action_index += 1
		_execute_next_action()


func _action_completed() -> void:
	current_action_index += 1
	_execute_next_action()


func _finish_cutscene() -> void:
	var finished_id := current_cutscene_id

	is_playing = false
	current_cutscene_id = ""
	current_actions = []
	current_action_index = 0
	is_waiting_for_input = false

	# Hide dialogue UI
	_hide_dialogue_ui()

	# Exit camera cutscene mode (resume following player)
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("exit_cutscene_mode"):
		camera.exit_cutscene_mode()

	# Exit cutscene state
	Game.end_cutscene()

	cutscene_finished.emit(finished_id)
	Debug.info("Cutscene", "Cutscene finished", finished_id)


#===============================================================================
# ACTION HANDLERS
#===============================================================================

func _execute_dialogue(action: Dictionary) -> void:
	var speaker: String = action.get("speaker", "")
	var text: String = action.get("text", "")
	var portrait: String = action.get("portrait", "")
	var auto_advance: bool = action.get("auto_advance", false)
	var auto_delay: float = action.get("auto_delay", 2.0)

	Debug.info("Cutscene", "Executing dialogue", {"speaker": speaker, "text": text, "auto_advance": auto_advance})

	if _dialogue_ui:
		_dialogue_ui.show_dialogue(speaker, text, portrait)
	else:
		Debug.err("Cutscene", "No dialogue UI available!")

	dialogue_displayed.emit(speaker, text)

	if auto_advance:
		# Auto-advance after delay
		await get_tree().create_timer(auto_delay).timeout
		_action_completed()
	else:
		# Wait for player input
		is_waiting_for_input = true
		Debug.info("Cutscene", "Waiting for player input to advance")


func _execute_wait(action: Dictionary) -> void:
	var duration: float = action.get("duration", 1.0)
	await get_tree().create_timer(duration).timeout
	_action_completed()


func _execute_fade_in(action: Dictionary) -> void:
	var duration: float = action.get("duration", 0.5)
	if _dialogue_ui:
		await _dialogue_ui.fade_in(duration)
	_action_completed()


func _execute_fade_out(action: Dictionary) -> void:
	var duration: float = action.get("duration", 0.5)
	if _dialogue_ui:
		await _dialogue_ui.fade_out(duration)
	_action_completed()


func _execute_move(action: Dictionary) -> void:
	var target_id: String = action.get("target", "")
	var position: Array = action.get("position", [0, 0])
	var speed: float = action.get("speed", 100.0)
	var wait_for_arrival: bool = action.get("wait", true)

	Debug.info("Cutscene", "Executing move", {"target": target_id, "position": position, "speed": speed})

	var target := _get_target_node(target_id)
	if not target:
		Debug.warn("Cutscene", "Move target not found", target_id)
		_action_completed()
		return

	Debug.info("Cutscene", "Move target found", target.name)

	var target_pos := Vector2(position[0], position[1])
	var distance := target.global_position.distance_to(target_pos)
	var duration := distance / speed

	var tween := create_tween()
	tween.tween_property(target, "global_position", target_pos, duration)

	if wait_for_arrival:
		await tween.finished
		_action_completed()
	else:
		_action_completed()


func _execute_spawn(action: Dictionary) -> void:
	var npc_id: String = action.get("npc_id", "")
	var position: Array = action.get("position", [0, 0])
	# TODO: Implement NPC spawning when spawn system is ready
	Debug.info("Cutscene", "Spawn action (not implemented)", [npc_id, position])
	_action_completed()


func _execute_despawn(action: Dictionary) -> void:
	var target_id: String = action.get("target", "")
	var target := _get_target_node(target_id)
	if target and target_id != "player":
		target.queue_free()
	_action_completed()


func _execute_camera_pan(action: Dictionary) -> void:
	var position: Array = action.get("position", [0, 0])
	var duration: float = action.get("duration", 1.0)
	var target_pos := Vector2(position[0], position[1])

	var camera := get_viewport().get_camera_2d()
	if camera:
		# Detach from player temporarily
		if camera.has_method("set_target"):
			camera.set_target(null)

		var tween := create_tween()
		tween.tween_property(camera, "global_position", target_pos, duration)
		await tween.finished

	_action_completed()


func _execute_camera_shake(action: Dictionary) -> void:
	var intensity: float = action.get("intensity", 0.5)
	var duration: float = action.get("duration", 0.3)

	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(intensity)

	await get_tree().create_timer(duration).timeout
	_action_completed()


func _execute_camera_reset(action: Dictionary) -> void:
	var duration: float = action.get("duration", 0.5)

	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("set_target") and Game.player:
		camera.set_target(Game.player)
		if duration > 0:
			await get_tree().create_timer(duration).timeout

	_action_completed()


func _execute_play_sound(action: Dictionary) -> void:
	var sound_id: String = action.get("sound", "")
	# TODO: Integrate with audio system
	Debug.info("Cutscene", "Play sound (not implemented)", sound_id)
	_action_completed()


func _execute_set_facing(action: Dictionary) -> void:
	var target_id: String = action.get("target", "")
	var direction: String = action.get("direction", "right")

	var target := _get_target_node(target_id)
	if target and target.has_method("set_facing_direction"):
		target.set_facing_direction(direction)
	elif target and "sprite" in target:
		target.sprite.flip_h = (direction == "left")

	_action_completed()


func _execute_parallel(action: Dictionary) -> void:
	var sub_actions: Array = action.get("actions", [])
	if sub_actions.is_empty():
		_action_completed()
		return

	var pending_count := sub_actions.size()
	var completed_count := 0

	for sub_action in sub_actions:
		var action_type: String = sub_action.get("type", "")
		if action_type.is_empty() or not _action_handlers.has(action_type):
			completed_count += 1
			continue

		# Execute in parallel - each one will call back when done
		# For simplicity, we'll wait for longest one
		var handler: Callable = _action_handlers[action_type]
		handler.call(sub_action)

	# Wait a frame then complete (parallel actions are fire-and-forget for now)
	await get_tree().process_frame
	_action_completed()


#===============================================================================
# HELPERS
#===============================================================================

func _get_cutscene_data(cutscene_id: String) -> Dictionary:
	if DatabaseLoader.cutscenes.has(cutscene_id):
		return DatabaseLoader.cutscenes[cutscene_id]
	return {}


func _get_target_node(target_id: String) -> Node2D:
	Debug.info("Cutscene", "Looking up target", target_id)

	if target_id == "player":
		return Game.player

	# Try NPCManager
	if NPCManager:
		var npc := NPCManager.get_friendly_by_id(target_id)
		if npc:
			Debug.info("Cutscene", "Found friendly NPC", npc.name)
			return npc
		var enemy := NPCManager.get_enemy_by_id(target_id)
		if enemy:
			Debug.info("Cutscene", "Found enemy", enemy.name)
			return enemy

		# Also try by display name for convenience
		for e in NPCManager.all_enemies:
			if is_instance_valid(e) and e.npc_name == target_id:
				Debug.info("Cutscene", "Found enemy by name", e.name)
				return e

	Debug.warn("Cutscene", "Target not found in any lookup", target_id)
	return null


func _show_dialogue_ui() -> void:
	if _dialogue_ui == null:
		_dialogue_ui = DIALOGUE_UI_SCENE.instantiate()
		_dialogue_ui.advance_requested.connect(advance)
		get_tree().root.add_child(_dialogue_ui)

	_dialogue_ui.show()
	_dialogue_ui.reset()


func _hide_dialogue_ui() -> void:
	if _dialogue_ui:
		_dialogue_ui.hide()
