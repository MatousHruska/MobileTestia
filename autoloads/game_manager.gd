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
		var old_player := player
		player = value
		print("[SAVELOAD] Game.player SETTER | Frame: %d" % Engine.get_process_frames())
		print("[SAVELOAD] GM player: old=%s, new=%s" % [old_player.name if old_player and is_instance_valid(old_player) else "null", value.name if value else "null"])
		print("[SAVELOAD] GM player: current_state=%s, tree_paused=%s" % [GameState.keys()[current_state], get_tree().paused])
		Debug.info("Player", "Player setter called", {
			"old": old_player.name if old_player and is_instance_valid(old_player) else "null",
			"new": value.name if value else "null",
			"current_state": GameState.keys()[current_state],
			"tree_paused": get_tree().paused
		})
		if player:
			print("[SAVELOAD] GM player: Emitting player_spawned signal")
			player_spawned.emit(player)
			# Auto-transition to PLAYING when player is ready
			if current_state == GameState.LOADING:
				print("[SAVELOAD] GM player: AUTO-TRANSITIONING to PLAYING from LOADING")
				Debug.info("Player", "Auto-transitioning to PLAYING from LOADING")
				set_playing()
				print("[SAVELOAD] GM player: State after set_playing(): %s" % GameState.keys()[current_state])
			else:
				print("[SAVELOAD] GM player: NOT auto-transitioning - state is not LOADING (is %s)" % GameState.keys()[current_state])
				Debug.warn("Player", "NOT auto-transitioning - state is not LOADING", GameState.keys()[current_state])

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


func _input(event: InputEvent) -> void:
	# Debug: Press F9 to dump game state
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		debug_full_state()

	# Debug: Press F10 to test ends_when buff system
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		debug_test_ends_when_buff()


## State management
func set_playing() -> void:
	Debug.info("System", "set_playing() called", {
		"from_state": GameState.keys()[current_state],
		"tree_paused_before": get_tree().paused
	})
	current_state = GameState.PLAYING
	get_tree().paused = false
	Debug.info("System", "set_playing() complete", {
		"tree_paused_after": get_tree().paused
	})

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
	Debug.info("UI", "close_character_menu() called", {
		"current_state": GameState.keys()[current_state],
		"tree_paused": get_tree().paused
	})
	if current_state != GameState.CHARACTER_MENU:
		Debug.warn("UI", "close_character_menu() - state is NOT CHARACTER_MENU, returning early")
		return
	current_state = GameState.PLAYING
	get_tree().paused = false
	Debug.info("UI", "Character menu closed (game resumed)", {
		"tree_paused_after": get_tree().paused
	})

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
	print("[SAVELOAD] Game.change_zone() called | Frame: %d" % Engine.get_process_frames())
	print("[SAVELOAD] GM: zone_path=%s, spawn_id=%s" % [zone_path, spawn_id])
	print("[SAVELOAD] GM: state BEFORE: %s, player_valid: %s" % [GameState.keys()[current_state], is_player_valid()])

	spawn_point_id = spawn_id
	current_state = GameState.LOADING
	print("[SAVELOAD] GM: Set state to LOADING, scheduling _load_zone via call_deferred")

	# Use call_deferred to allow current frame to finish
	call_deferred("_load_zone", zone_path)

## Pending zone load for retry when scene tree is busy
var _pending_zone_path: String = ""
var _zone_load_retry_count: int = 0
const MAX_ZONE_LOAD_RETRIES: int = 10

func _load_zone(zone_path: String) -> void:
	print("[SAVELOAD] Game._load_zone() EXECUTING | Frame: %d" % Engine.get_process_frames())
	print("[SAVELOAD] GM load: zone_path=%s" % zone_path)
	print("[SAVELOAD] GM load: state=%s, tree_paused=%s, player_valid=%s" % [GameState.keys()[current_state], get_tree().paused, is_player_valid()])
	print("[SAVELOAD] GM load: ChunkManager state: initialized=%s, zone=%s" % [ChunkManager._initialized if ChunkManager else "null", ChunkManager.current_zone_id if ChunkManager else "null"])

	# Clear player reference since it will be invalid after scene change
	# The new scene's player will set this in its _ready()
	print("[SAVELOAD] GM load: Clearing player reference")
	player = null

	print("[SAVELOAD] GM load: Calling change_scene_to_file()...")
	var error := get_tree().change_scene_to_file(zone_path)
	if error != OK:
		print("[SAVELOAD] GM load: change_scene_to_file returned error: %d" % error)
		# ERR_BUSY (19) means scene tree is busy - retry after a short delay
		if error == ERR_BUSY:
			_zone_load_retry_count += 1
			if _zone_load_retry_count <= MAX_ZONE_LOAD_RETRIES:
				print("[SAVELOAD] GM load: ERR_BUSY - scheduling retry %d/%d" % [_zone_load_retry_count, MAX_ZONE_LOAD_RETRIES])
				_pending_zone_path = zone_path
				# Use a timer to retry after a short delay
				get_tree().create_timer(0.05).timeout.connect(_retry_load_zone)
				return
			else:
				print("[SAVELOAD] GM load: ERROR! Max retries exceeded for zone load")
				Debug.err("System", "Failed to load zone after %d retries" % MAX_ZONE_LOAD_RETRIES, zone_path)
		else:
			Debug.err("System", "Failed to load zone", [zone_path, "error:", error])
		return

	# Success - reset retry counter
	_zone_load_retry_count = 0
	_pending_zone_path = ""

	print("[SAVELOAD] GM load: change_scene_to_file() returned OK")
	# Note: change_scene_to_file() queues the scene change for end of frame
	# The actual scene loads asynchronously, but the function returns OK immediately
	current_zone = zone_path.get_file().get_basename()
	zone_changed.emit(current_zone)
	print("[SAVELOAD] GM load: Emitted zone_changed signal for: %s" % current_zone)
	print("[SAVELOAD] GM load: DONE (scene change queued for end of frame) | Frame: %d" % Engine.get_process_frames())


func _retry_load_zone() -> void:
	print("[SAVELOAD] Game._retry_load_zone() | Frame: %d | Retry: %d" % [Engine.get_process_frames(), _zone_load_retry_count])
	if _pending_zone_path.is_empty():
		print("[SAVELOAD] GM retry: No pending zone path!")
		return
	_load_zone(_pending_zone_path)


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


func debug_full_state() -> void:
	## Print comprehensive debug state - call this to diagnose issues
	print("============================================================")
	print("=== GAME STATE DEBUG ===")
	print("============================================================")
	print("GameManager.current_state: ", GameState.keys()[current_state])
	print("get_tree().paused: ", get_tree().paused)
	print("can_player_move: ", can_player_move)
	print("can_player_attack: ", can_player_attack)
	print("player valid: ", is_player_valid())
	print("player ref: ", player)
	print("current_zone: ", current_zone)
	print("spawn_point_id: ", spawn_point_id)

	# Check UIManager state
	if UIManager:
		print("UIManager.is_character_menu_open(): ", UIManager.is_character_menu_open())
		print("UIManager.is_any_menu_open(): ", UIManager.is_any_menu_open())

	print("============================================================")

	Debug.info("System", "DEBUG STATE DUMP", {
		"state": GameState.keys()[current_state],
		"tree_paused": get_tree().paused,
		"can_move": can_player_move,
		"player_valid": is_player_valid()
	})


func debug_test_ends_when_buff() -> void:
	## Test the ends_when buff system - applies a buff that ends when player heals to full
	## Press F10 to activate
	print("============================================================")
	print("=== TESTING ENDS_WHEN BUFF SYSTEM ===")
	print("============================================================")

	if not is_player_valid():
		print("ERROR: No valid player found!")
		return

	if player.has_method("debug_test_ends_when_buff"):
		player.debug_test_ends_when_buff()
		print("")
		print("Test buff 'test_frenzy' applied!")
		print("- This buff will automatically END when you heal to full health")
		print("- Current health: %.0f / %.0f" % [PlayerStats.current_life, PlayerStats.max_life])
		print("- Wait for natural regen or use a heal to see the buff disappear")
		print("============================================================")
	else:
		print("ERROR: Player doesn't have debug_test_ends_when_buff method!")
