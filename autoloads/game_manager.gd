extends Node
## GameManager - Central game state and coordination singleton
## Manages game flow, player reference, and global state

## Signals
signal game_paused
signal game_resumed
signal player_spawned(player: Node2D)
signal zone_changed(zone_name: String)
signal game_state_changed(old_state: GameState, new_state: GameState)

## Game states
enum GameState { LOADING, MENU, PLAYING, PAUSED, DIALOGUE, CHARACTER_MENU, CUTSCENE, GAME_OVER }

## Current state
var current_state: GameState = GameState.LOADING:
	set(value):
		var old := current_state
		current_state = value
		game_state_changed.emit(old, value)
		Debug.info("System", "Game state changed", [GameState.keys()[old], "→", GameState.keys()[value]])

## Player reference
var player: Node2D = null:
	set(value):
		player = value
		if player:
			player_spawned.emit(player)
			Debug.info("Player", "Player reference set", player.name)
			# Auto-transition to PLAYING when player is ready
			if current_state == GameState.LOADING:
				set_playing()

## Game flags
var is_paused: bool:
	get: return current_state == GameState.PAUSED

var is_playing: bool:
	get: return current_state == GameState.PLAYING

var can_player_move: bool:
	get: return current_state in [GameState.PLAYING]

var can_player_attack: bool:
	get: return current_state in [GameState.PLAYING]

## Zone tracking
var current_zone: String = ""
var spawn_point_id: String = ""

## Game time (for day/night, timers, etc.)
var game_time: float = 0.0
var game_time_scale: float = 1.0

## UI References
var hub_ui: Node = null
const HUB_UI_SCENE := preload("res://scenes/ui/hub/hub_ui.tscn")


func _ready() -> void:
	Debug.info("System", "GameManager initialized")
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running when paused


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta * game_time_scale


## State management
func set_playing() -> void:
	current_state = GameState.PLAYING
	get_tree().paused = false

func pause_game() -> void:
	if current_state != GameState.PLAYING:
		return
	current_state = GameState.PAUSED
	get_tree().paused = true
	game_paused.emit()
	Debug.info("System", "Game paused")

func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	current_state = GameState.PLAYING
	get_tree().paused = false
	game_resumed.emit()
	Debug.info("System", "Game resumed")

func toggle_pause() -> void:
	if is_paused:
		resume_game()
	elif is_playing:
		pause_game()

func open_character_menu() -> void:
	if current_state != GameState.PLAYING:
		return
	current_state = GameState.CHARACTER_MENU
	get_tree().paused = true
	Debug.info("UI", "Character menu opened (game paused)")

func close_character_menu() -> void:
	if current_state != GameState.CHARACTER_MENU:
		return
	current_state = GameState.PLAYING
	get_tree().paused = false
	Debug.info("UI", "Character menu closed (game resumed)")

func start_dialogue() -> void:
	if current_state != GameState.PLAYING:
		return
	current_state = GameState.DIALOGUE
	Debug.info("UI", "Dialogue started")

func end_dialogue() -> void:
	if current_state != GameState.DIALOGUE:
		return
	current_state = GameState.PLAYING
	Debug.info("UI", "Dialogue ended")


## Cutscene state management
func start_cutscene() -> void:
	if current_state not in [GameState.PLAYING, GameState.DIALOGUE]:
		return
	current_state = GameState.CUTSCENE
	Debug.info("Cutscene", "Cutscene started")


func end_cutscene() -> void:
	if current_state != GameState.CUTSCENE:
		return
	current_state = GameState.PLAYING
	Debug.info("Cutscene", "Cutscene ended")


var is_in_cutscene: bool:
	get: return current_state == GameState.CUTSCENE


## Hub UI (NPC Interaction Menu)
func open_hub_ui(npc_id: String) -> void:
	if current_state != GameState.PLAYING:
		return

	# Create Hub UI if not exists
	if hub_ui == null:
		hub_ui = HUB_UI_SCENE.instantiate()
		hub_ui.closed.connect(_on_hub_ui_closed)
		get_tree().root.add_child(hub_ui)

	current_state = GameState.DIALOGUE
	hub_ui.open(npc_id)
	Debug.info("UI", "Hub UI opened for NPC: %s" % npc_id)


func close_hub_ui() -> void:
	if hub_ui and hub_ui.is_open:
		hub_ui.close()


func _on_hub_ui_closed() -> void:
	if current_state == GameState.DIALOGUE:
		current_state = GameState.PLAYING
	Debug.info("UI", "Hub UI closed")


func game_over() -> void:
	current_state = GameState.GAME_OVER
	Debug.warn("System", "Game over triggered")


## Zone management
func change_zone(zone_path: String, spawn_id: String = "default") -> void:
	Debug.info("System", "Zone change requested", [zone_path, "spawn:", spawn_id])
	spawn_point_id = spawn_id
	current_state = GameState.LOADING

	# Use call_deferred to allow current frame to finish
	call_deferred("_load_zone", zone_path)

func _load_zone(zone_path: String) -> void:
	Debug.perf_start("zone_load")
	var error := get_tree().change_scene_to_file(zone_path)
	if error != OK:
		Debug.err("System", "Failed to load zone", [zone_path, "error:", error])
		return
	current_zone = zone_path.get_file().get_basename()
	zone_changed.emit(current_zone)
	Debug.perf_end("zone_load")


## Utility
func get_player_position() -> Vector2:
	if player and is_instance_valid(player):
		return player.global_position
	return Vector2.ZERO

func is_player_valid() -> bool:
	return player != null and is_instance_valid(player)


## Debug helpers
func print_state() -> void:
	Debug.snapshot("System", "GameManager State", {
		"current_state": GameState.keys()[current_state],
		"is_paused": is_paused,
		"current_zone": current_zone,
		"player_valid": is_player_valid(),
		"game_time": game_time,
	})
